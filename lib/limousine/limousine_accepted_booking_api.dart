// LIMOUSINE-MARKETPLACE-P2D3 — one authenticated POST /book for an accepted
// quote. Reuses the existing booking engine. Never logs limacc1.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../app_strings.dart';
import '../customer_bookings_store.dart';
import '../customer_profile_store.dart';
import '../customer_session_store.dart';
import 'limousine_accepted_booking.dart';
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
    LimousineAcceptedBookingCustomerLoader? customerLoader,
    LimousineAcceptedBookingPersister? persister,
    LimousineAcceptedBookingCustomer? customerOverride,
  }) : _gateway = gateway,
       _customerLoader =
           customerLoader ?? defaultLimousineAcceptedBookingCustomer,
       _persister = persister ?? defaultLimousineAcceptedBookingPersister,
       customer = customerOverride {
    CustomerSessionStore.instance.addClearedListener(_onSessionCleared);
  }

  final LimousineAcceptedQuoteHandoff handoff;
  final LimousineQuoteCreateDraft draft;
  final LimousineQuoteRequest? request;
  final LimousinePublishedOffer? offer;
  final String providerName;
  final bool entryEnabled;
  final LimousineCustomerQuoteController? quoteController;
  final LimousineAcceptedBookingGateway _gateway;
  final LimousineAcceptedBookingCustomerLoader _customerLoader;
  final LimousineAcceptedBookingPersister _persister;

  LimousineAcceptedBookingPhase phase = LimousineAcceptedBookingPhase.review;
  bool confirmationAcknowledged = false;
  LimousineAcceptedBookingError? error;
  LimousineAcceptedBookResult? result;
  LimousineAcceptedBookingCustomer? customer;
  bool handoffCleared = false;
  int bookCalls = 0;
  final List<String> _logSink = <String>[];
  int _bookGeneration = 0;
  bool _sessionCleared = false;

  List<String> get logSinkForTests => List<String>.unmodifiable(_logSink);
  bool get submitting => phase == LimousineAcceptedBookingPhase.submitting;
  bool get succeeded => phase == LimousineAcceptedBookingPhase.success;

  void _safeLog(String message) {
    if (limousineAcceptedBookingTextLeaksToken(message)) return;
    _logSink.add(message);
  }

  @visibleForTesting
  void handleSessionClearedForTests() => _onSessionCleared();

  void _onSessionCleared() {
    _sessionCleared = true;
    quoteController?.clearAcceptedHandoff();
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
    return buildLimousineAcceptedBookingReview(
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
    );
    if (preflight != null) {
      error = preflight;
      phase = LimousineAcceptedBookingPhase.failed;
      _safeLog('book_blocked');
      notifyListeners();
      return false;
    }
    final payload = limousineAcceptedBookPayload(
      handoff: quoteController?.handoff ?? handoff,
      draft: draft,
      customer: loaded!,
      request: request,
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
      handoffCleared =
          quoteController == null || quoteController?.handoff == null;
      _safeLog('booking_created');
      await _persister(
        response: booked.raw,
        requestPayload: payload,
        customer: loaded,
      );
      notifyListeners();
      return true;
    } on LimousineAcceptedBookException catch (caught) {
      if (generation != _bookGeneration) return false;
      error = limousineAcceptedBookErrorFromCode(caught.code);
      phase = caught.ambiguous
          ? LimousineAcceptedBookingPhase.ambiguous
          : LimousineAcceptedBookingPhase.failed;
      _safeLog(caught.ambiguous ? 'book_ambiguous' : 'book_failed');
      notifyListeners();
      return false;
    }
  }
}
