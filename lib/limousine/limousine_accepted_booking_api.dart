// LIMOUSINE-MARKETPLACE-P2D3 — one authenticated POST /book for an accepted
// quote. Reuses the existing booking engine. Never logs limacc1.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../customer_bookings_store.dart';
import '../customer_profile_store.dart';
import '../customer_session_store.dart';
import '../payment/booking_billing_identity.dart';
import '../payment/booking_checkout_response.dart';
import '../payment/booking_payment_options.dart';
import '../payment/payment_booking_selection.dart';
import '../payment/payment_method_catalog.dart';
import '../payment_return.dart';
import 'limousine_accepted_booking.dart';
import 'limousine_accepted_booking_vault.dart';
import 'limousine_customer_quote.dart';
import 'limousine_customer_quote_api.dart';
import 'limousine_quote_inbox.dart';

typedef LimousineAcceptedBookingCustomerLoader =
    Future<LimousineAcceptedBookingCustomer?> Function();

typedef LimousineAcceptedBookingPersister =
    Future<void> Function({
      required Map<String, dynamic> response,
      required Map<String, dynamic> requestPayload,
      required LimousineAcceptedBookingCustomer customer,
    });

/// Reads the payment capability of the partner performing the accepted ride.
///
/// Returns null when no authoritative answer could be obtained, which keeps the
/// picker closed instead of guessing what the partner accepts.
typedef LimousineAcceptedPaymentCapabilityLoader =
    Future<BookingPaymentCapability?> Function();

/// Hands a hosted checkout link to the platform. Returns false if it could not
/// be opened.
typedef LimousineAcceptedCheckoutOpener = Future<bool> Function(String url);

abstract class LimousineAcceptedBookingGateway {
  Future<LimousineAcceptedBookResult> book(Map<String, dynamic> payload);
}

class HttpLimousineAcceptedBookingGateway
    implements LimousineAcceptedBookingGateway {
  HttpLimousineAcceptedBookingGateway({
    http.Client? client,
    LimousineCustomerAuthHeaders? authHeaders,
    String? bookingBaseUrl,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client,
       _authHeaders = authHeaders ?? defaultLimousineCustomerAuthHeaders,
       _bookingBaseUrl = bookingBaseUrl ?? kBookingBaseUrl;

  final http.Client? _client;
  final LimousineCustomerAuthHeaders _authHeaders;
  final String _bookingBaseUrl;
  final Duration timeout;

  @override
  Future<LimousineAcceptedBookResult> book(Map<String, dynamic> payload) async {
    if (!limousineAcceptedBookPayloadIsSafe(payload)) {
      throw const LimousineAcceptedBookException(code: 'unknown_response');
    }
    final uri = Uri.parse('$_bookingBaseUrl/book');
    try {
      final headers = await _authHeaders();
      if ((headers['Authorization'] ?? '').trim().isEmpty) {
        throw const LimousineAcceptedBookException(
          code: 'missing_customer_scope',
        );
      }
      final client = _client ?? http.Client();
      final ownsClient = _client == null;
      try {
        final res = await client
            .post(uri, headers: headers, body: jsonEncode(payload))
            .timeout(timeout);
        return _decodeBookResponse(res);
      } finally {
        if (ownsClient) client.close();
      }
    } on TimeoutException {
      throw const LimousineAcceptedBookException(
        code: 'ambiguous_timeout',
        ambiguous: true,
      );
    } on LimousineAcceptedBookException {
      rethrow;
    } catch (_) {
      throw const LimousineAcceptedBookException(code: 'network');
    }
  }
}

LimousineAcceptedBookResult _decodeBookResponse(http.Response res) {
  Map<String, dynamic> body = <String, dynamic>{};
  if (res.body.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        body = decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      throw const LimousineAcceptedBookException(code: 'unknown_response');
    }
  }
  if (res.statusCode < 200 || res.statusCode >= 300 || body['ok'] == false) {
    final code = (body['error'] ?? body['message'] ?? 'network').toString();
    throw LimousineAcceptedBookException(
      code: code,
      statusCode: res.statusCode,
    );
  }
  if (body['ok'] != true) {
    throw const LimousineAcceptedBookException(code: 'unknown_response');
  }
  final bookingId = firstLimousineBookingReference(body);
  if (bookingId.isEmpty) {
    throw const LimousineAcceptedBookException(code: 'unknown_response');
  }
  return LimousineAcceptedBookResult(
    bookingId: bookingId,
    publicReference: firstLimousinePublicBookingReference(body),
    raw: body,
  );
}

/// Reads the partner's sanitized payment capability from the authoritative
/// accepted-quote status read.
///
/// This is the same server read the quote flow already polls, so a customer
/// whose app was killed mid-flow can be offered the partner's real methods
/// again instead of a locally remembered guess.
Future<BookingPaymentCapability?> readLimousinePartnerPaymentCapability({
  required String statusRef,
  http.Client? client,
  LimousineCustomerAuthHeaders? authHeaders,
  String? bookingBaseUrl,
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (!looksLikeLimousineStatusRef(statusRef)) return null;
  final base = bookingBaseUrl ?? kBookingBaseUrl;
  final uri = Uri.parse('$base/limousine/quote-requests/status');
  final headers = await (authHeaders ?? defaultLimousineCustomerAuthHeaders)();
  final ownsClient = client == null;
  final httpClient = client ?? http.Client();
  try {
    final res = await httpClient
        .post(
          uri,
          headers: headers,
          body: jsonEncode(<String, dynamic>{'status_ref': statusRef}),
        )
        .timeout(timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final decoded = jsonDecode(res.body);
    if (decoded is! Map || decoded['ok'] != true) return null;
    final capability = decoded['payment_capability'];
    if (capability is! Map) return null;
    return BookingPaymentCapability.fromPublicJson(capability);
  } catch (_) {
    return null;
  } finally {
    if (ownsClient) httpClient.close();
  }
}

/// Opens a hosted checkout the same way the other booking surfaces do.
Future<bool> defaultLimousineAcceptedCheckoutOpener(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

Future<LimousineAcceptedBookingCustomer?>
defaultLimousineAcceptedBookingCustomer() async {
  try {
    final session = await CustomerSessionStore.instance.loadValidSession();
    final token = (session?.customerSessionToken ?? '').trim();
    if (token.isEmpty) return null;
    var name = '';
    var email = '';
    var phone = (session?.phoneE164 ?? '').trim();
    try {
      final profile = await CustomerProfileStore.instance.load();
      name = (profile?.name ?? '').trim();
      email = (profile?.email ?? '').trim();
      if (phone.isEmpty) phone = (profile?.phone ?? '').trim();
    } catch (_) {}
    return LimousineAcceptedBookingCustomer(
      sessionToken: token,
      customerId: (session?.customerId ?? '').trim(),
      name: name,
      phone: phone,
      email: email,
    );
  } catch (_) {
    return null;
  }
}

Future<void> defaultLimousineAcceptedBookingPersister({
  required Map<String, dynamic> response,
  required Map<String, dynamic> requestPayload,
  required LimousineAcceptedBookingCustomer customer,
}) async {
  try {
    final stored = StoredCustomerBooking.fromBookSuccess(
      response: response,
      requestPayload: requestPayload,
      customerName: customer.name,
      customerPhone: customer.phone,
      customerEmail: customer.email,
    );
    await CustomerBookingsStore.instance.upsert(stored);
  } catch (_) {
    // History persist must not roll back a server-confirmed booking.
  }
}

class LimousineAcceptedBookingController extends ChangeNotifier {
  LimousineAcceptedBookingController({
    required this.handoff,
    required this.draft,
    required LimousineAcceptedBookingGateway gateway,
    this.request,
    this.offer,
    this.providerName = '',
    this.entryEnabled = false,
    this.quoteController,
    this.resumeRepository,
    this.reviewSnapshot,
    LimousineAcceptedBookingCustomerLoader? customerLoader,
    LimousineAcceptedBookingPersister? persister,
    LimousineAcceptedBookingCustomer? customerOverride,
    LimousineAcceptedPaymentCapabilityLoader? paymentCapabilityLoader,
    LimousineAcceptedCheckoutOpener? checkoutOpener,
    BookingPaymentCapability? initialPaymentCapability,
    bool? isApplePaymentPlatform,
  }) : _gateway = gateway,
       _customerLoader =
           customerLoader ?? defaultLimousineAcceptedBookingCustomer,
       _persister = persister ?? defaultLimousineAcceptedBookingPersister,
       _paymentCapabilityLoader = paymentCapabilityLoader,
       _checkoutOpener =
           checkoutOpener ?? defaultLimousineAcceptedCheckoutOpener,
       _isApplePaymentPlatform =
           isApplePaymentPlatform ?? (!kIsWeb && Platform.isIOS),
       paymentCapability = initialPaymentCapability,
       customer = customerOverride {
    CustomerSessionStore.instance.addClearedListener(_onSessionCleared);
    if (paymentCapability != null) _applyDefaultPaymentSelection();
  }

  final LimousineAcceptedQuoteHandoff handoff;
  final LimousineQuoteCreateDraft draft;
  final LimousineQuoteRequest? request;
  final LimousinePublishedOffer? offer;
  final String providerName;
  final bool entryEnabled;
  final LimousineCustomerQuoteController? quoteController;
  final LimousineAcceptedBookingResumeRepository? resumeRepository;
  final LimousineAcceptedBookingReview? reviewSnapshot;
  final LimousineAcceptedBookingGateway _gateway;
  final LimousineAcceptedBookingCustomerLoader _customerLoader;
  final LimousineAcceptedBookingPersister _persister;
  final LimousineAcceptedPaymentCapabilityLoader? _paymentCapabilityLoader;
  final LimousineAcceptedCheckoutOpener _checkoutOpener;
  final bool _isApplePaymentPlatform;

  LimousineAcceptedBookingPhase phase = LimousineAcceptedBookingPhase.review;
  bool confirmationAcknowledged = false;
  LimousineAcceptedBookingError? error;
  LimousineAcceptedBookResult? result;
  LimousineAcceptedBookingCustomer? customer;
  bool handoffCleared = false;
  int bookCalls = 0;

  /// What the partner performing this ride accepts. Null until read.
  BookingPaymentCapability? paymentCapability;

  bool loadingPaymentCapability = false;

  /// The method the customer picked. Never set on their behalf beyond the same
  /// visible default the other booking surfaces preselect.
  String? selectedPaymentMethodId;

  /// Checkout could not be opened after a booking the server already created.
  /// The customer finishes payment from their bookings list.
  bool checkoutStartFailed = false;

  /// Whether the customer asked for a company invoice. Private is the default,
  /// as it is on the taxi and airport surfaces.
  bool billingEnabled = false;

  /// What the customer typed into the billing form. Held in memory only: an
  /// accepted quote is resumable but billing identity is not persisted on any
  /// booking surface today, so a resumed session asks again rather than
  /// reusing anyone's stored details.
  BookingBillingIdentity billingIdentity = BookingBillingIdentity.empty;

  int capabilityLoads = 0;
  final List<String> _logSink = <String>[];
  int _bookGeneration = 0;
  int _capabilityGeneration = 0;
  bool _sessionCleared = false;

  List<String> get logSinkForTests => List<String>.unmodifiable(_logSink);
  bool get submitting => phase == LimousineAcceptedBookingPhase.submitting;
  bool get succeeded => phase == LimousineAcceptedBookingPhase.success;

  /// Resolved picker state, or null while no capability is known.
  ///
  /// [languageCode] only affects wording, never which methods are offered.
  BookingPaymentOptions? paymentOptionsFor(String languageCode) {
    final capability = paymentCapability;
    if (capability == null) return null;
    return BookingPaymentOptions(
      capability: capability,
      countryCode: paymentMarketCountryCode(capability.countryCode),
      languageCode: languageCode,
      isApplePlatform: _isApplePaymentPlatform,
    );
  }

  BookingPaymentOptions? get _paymentOptions => paymentOptionsFor('nl');

  /// Methods to show, in the order the resolver produced them.
  List<String> get visiblePaymentMethodIds =>
      _paymentOptions?.visibleMethodIds ?? const <String>[];

  /// Methods the customer can actually confirm a booking with.
  List<String> get selectablePaymentMethodIds {
    final options = _paymentOptions;
    if (options == null) return const <String>[];
    return options.visibleMethodIds
        .where((id) => !options.isDisplayOnly(id))
        .toList(growable: false);
  }

  /// The picked method as canonical booking fields, or null when the customer
  /// has not made a usable choice.
  BookingPaymentSelection? get paymentSelection {
    final methodId = selectedPaymentMethodId;
    if (methodId == null) return null;
    if (!selectablePaymentMethodIds.contains(methodId)) return null;
    return BookingPaymentSelection.fromMethodId(methodId);
  }

  bool get hasPaymentSelection => paymentSelection != null;

  /// True when a requested company invoice still lacks a field the existing
  /// canonical rule requires.
  bool get billingIdentityIncomplete =>
      billingEnabled && !billingIdentity.isCompleteForBusinessInvoice;

  /// The first required billing field still missing, or null when nothing is.
  BookingBillingIdentityField? get missingBillingIdentityField => billingEnabled
      ? firstMissingBookingBillingIdentityField(billingIdentity)
      : null;

  /// True once the customer may submit: a real capability, a usable choice, a
  /// complete billing identity if they asked for an invoice, and the
  /// acknowledgement the accepted quote requires.
  bool get canConfirmBooking =>
      !submitting &&
      !succeeded &&
      confirmationAcknowledged &&
      !loadingPaymentCapability &&
      hasPaymentSelection &&
      !billingIdentityIncomplete;

  /// Turns the company-invoice choice on or off. Never flips on the customer's
  /// behalf in either direction.
  void setBillingEnabled(bool enabled) {
    if (billingEnabled == enabled) return;
    billingEnabled = enabled;
    notifyListeners();
  }

  void updateBillingIdentity(BookingBillingIdentity identity) {
    billingIdentity = identity;
    notifyListeners();
  }

  /// Reads the partner capability and preselects the same default the taxi and
  /// airport pickers use, but only when the partner actually offers it.
  Future<void> loadPaymentCapability() async {
    final loader = _paymentCapabilityLoader;
    if (loader == null) {
      if (paymentCapability == null) {
        error = LimousineAcceptedBookingError.paymentCapabilityUnavailable;
        notifyListeners();
      }
      return;
    }
    if (loadingPaymentCapability) return;
    loadingPaymentCapability = true;
    capabilityLoads += 1;
    if (error == LimousineAcceptedBookingError.paymentCapabilityUnavailable ||
        error == LimousineAcceptedBookingError.paymentMethodUnavailable) {
      error = null;
    }
    notifyListeners();
    final generation = ++_capabilityGeneration;
    BookingPaymentCapability? loaded;
    try {
      loaded = await loader();
    } catch (_) {
      loaded = null;
    }
    if (generation != _capabilityGeneration) return;
    loadingPaymentCapability = false;
    if (loaded == null) {
      // Fail closed: no capability means no methods, not every method.
      paymentCapability = null;
      selectedPaymentMethodId = null;
      error = LimousineAcceptedBookingError.paymentCapabilityUnavailable;
      _safeLog('payment_capability_unavailable');
      notifyListeners();
      return;
    }
    paymentCapability = loaded;
    _applyDefaultPaymentSelection();
    if (selectablePaymentMethodIds.isEmpty) {
      error = LimousineAcceptedBookingError.paymentMethodUnavailable;
    }
    notifyListeners();
  }

  void _applyDefaultPaymentSelection() {
    final selectable = selectablePaymentMethodIds;
    final current = selectedPaymentMethodId;
    if (current != null && selectable.contains(current)) return;
    if (selectable.contains(PaymentMethodIds.inVehicleCard)) {
      selectedPaymentMethodId = PaymentMethodIds.inVehicleCard;
      return;
    }
    selectedPaymentMethodId = selectable.length == 1 ? selectable.single : null;
  }

  /// Records an explicit choice. Ignores methods the partner does not accept.
  void selectPaymentMethod(String methodId) {
    if (submitting || succeeded) return;
    final id = normalizePaymentMethodId(methodId);
    if (!selectablePaymentMethodIds.contains(id)) return;
    selectedPaymentMethodId = id;
    if (error == LimousineAcceptedBookingError.paymentMethodRequired ||
        error == LimousineAcceptedBookingError.paymentMethodUnavailable) {
      error = null;
    }
    notifyListeners();
  }

  void _safeLog(String message) {
    if (limousineAcceptedBookingTextLeaksToken(message)) return;
    _logSink.add(message);
  }

  @visibleForTesting
  void handleSessionClearedForTests() => _onSessionCleared();

  void _onSessionCleared() {
    _sessionCleared = true;
    quoteController?.clearAcceptedHandoff();
    if (quoteController == null) {
      unawaited(resumeRepository?.discard());
    }
    handoffCleared = quoteController?.handoff == null;
    if (phase != LimousineAcceptedBookingPhase.success) {
      error = LimousineAcceptedBookingError.missingCustomerScope;
      phase = LimousineAcceptedBookingPhase.failed;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    CustomerSessionStore.instance.removeClearedListener(_onSessionCleared);
    super.dispose();
  }

  void setConfirmationAcknowledged(bool value) {
    confirmationAcknowledged = value;
    notifyListeners();
  }

  LimousineAcceptedBookingReview reviewFor(AppLanguage language) {
    return reviewSnapshot ??
        buildLimousineAcceptedBookingReview(
          handoff: handoff,
          draft: draft,
          request: request,
          offer: offer,
          providerName: providerName,
          language: language,
        );
  }

  Future<bool> confirmBooking() async {
    if (submitting || succeeded) return false;
    if (!confirmationAcknowledged) return false;
    if (_sessionCleared) {
      error = LimousineAcceptedBookingError.missingCustomerScope;
      phase = LimousineAcceptedBookingPhase.failed;
      notifyListeners();
      return false;
    }
    final loaded = customer ?? await _customerLoader() ?? customer;
    customer = loaded;
    final preflight = limousineAcceptedBookPreflightError(
      entryEnabled: entryEnabled,
      handoff: quoteController?.handoff ?? handoff,
      customer: loaded,
      draft: draft,
      request: request,
    );
    if (preflight != null) {
      error = preflight;
      phase = LimousineAcceptedBookingPhase.failed;
      _safeLog('book_blocked');
      notifyListeners();
      return false;
    }
    // The partner's capability and the customer's choice: no capability means
    // no method, and no method means nothing to send. Never a cash default.
    if (paymentCapability == null) {
      error = LimousineAcceptedBookingError.paymentCapabilityUnavailable;
      phase = LimousineAcceptedBookingPhase.failed;
      _safeLog('book_blocked');
      notifyListeners();
      return false;
    }
    final payment = paymentSelection;
    if (payment == null) {
      error = LimousineAcceptedBookingError.paymentMethodRequired;
      phase = LimousineAcceptedBookingPhase.failed;
      _safeLog('book_blocked');
      notifyListeners();
      return false;
    }
    // A requested company invoice needs a complete buyer identity. Never
    // submit partial billing data and never quietly fall back to private.
    if (billingIdentityIncomplete) {
      error = LimousineAcceptedBookingError.billingIdentityIncomplete;
      phase = LimousineAcceptedBookingPhase.failed;
      _safeLog('book_blocked');
      notifyListeners();
      return false;
    }
    final payload = limousineAcceptedBookPayload(
      handoff: quoteController?.handoff ?? handoff,
      draft: draft,
      customer: loaded!,
      payment: payment,
      request: request,
      billingEnabled: billingEnabled,
      billing: billingIdentity,
    );
    if (!limousineAcceptedBookPayloadIsSafe(payload)) {
      error = LimousineAcceptedBookingError.unknownResponse;
      phase = LimousineAcceptedBookingPhase.failed;
      notifyListeners();
      return false;
    }
    phase = LimousineAcceptedBookingPhase.submitting;
    error = null;
    notifyListeners();
    final generation = ++_bookGeneration;
    bookCalls += 1;
    try {
      final booked = await _gateway.book(payload);
      if (generation != _bookGeneration) return false;
      result = booked;
      phase = LimousineAcceptedBookingPhase.success;
      quoteController?.clearAcceptedHandoff();
      if (quoteController == null) {
        await resumeRepository?.discard();
      }
      handoffCleared =
          quoteController == null || quoteController?.handoff == null;
      _safeLog('booking_created');
      await _persister(
        response: booked.raw,
        requestPayload: payload,
        customer: loaded,
      );
      await _startOnlineCheckoutIfNeeded(payment, booked);
      notifyListeners();
      return true;
    } on LimousineAcceptedBookException catch (caught) {
      if (generation != _bookGeneration) return false;
      error = limousineAcceptedBookErrorFromCode(caught.code);
      phase = caught.ambiguous
          ? LimousineAcceptedBookingPhase.ambiguous
          : LimousineAcceptedBookingPhase.failed;
      _safeLog(caught.ambiguous ? 'book_ambiguous' : 'book_failed');
      if (error == LimousineAcceptedBookingError.paymentMethodUnavailable) {
        // The partner's configuration moved under us. Read it again and make
        // the customer confirm a method that is still accepted; the accepted
        // quote is untouched, so no second booking can come out of this.
        selectedPaymentMethodId = null;
        notifyListeners();
        await loadPaymentCapability();
        return false;
      }
      notifyListeners();
      return false;
    }
  }

  /// Hands an online booking to the app-wide payment return flow, exactly as
  /// the taxi and airport surfaces do: the worker created the payment, the
  /// coordinator owns `/pay/status`, and the bookings list owns resuming it.
  Future<void> _startOnlineCheckoutIfNeeded(
    BookingPaymentSelection payment,
    LimousineAcceptedBookResult booked,
  ) async {
    checkoutStartFailed = false;
    if (!payment.isMollieCheckout) return;
    final paymentBookingId = bookingPaymentBookingId(booked.raw);
    final checkoutUrl = bookingCheckoutUrl(booked.raw);
    if (paymentBookingId.isNotEmpty) {
      setFluxidiPendingPayment(
        paymentBookingId: paymentBookingId,
        publicBookingId: booked.publicReference.isEmpty
            ? null
            : booked.publicReference,
      );
    }
    if (checkoutUrl.isEmpty) {
      checkoutStartFailed = true;
      _safeLog('checkout_url_missing');
      return;
    }
    if (paymentBookingId.isNotEmpty) {
      markFluxidiPendingPaymentChecking(paymentBookingId: paymentBookingId);
    }
    final opened = await _checkoutOpener(checkoutUrl);
    checkoutStartFailed = !opened;
    _safeLog(opened ? 'checkout_opened' : 'checkout_open_failed');
  }
}
