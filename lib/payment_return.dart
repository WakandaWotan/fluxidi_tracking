import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';
import 'package:fluxidi_tracking/payment/mollie_street_status_auth.dart';
import 'package:fluxidi_tracking/payment/pending_payment.dart';
import 'package:http/http.dart' as http;

export 'package:fluxidi_tracking/payment/pending_payment.dart';

const String kFluxidiPaymentReturnScheme = 'fluxidi';
const String kFluxidiPaymentReturnHost = 'pay';
const String kFluxidiPaymentReturnUrl = 'fluxidi://pay/return';

/// Return link the booking payload advertises and the coordinator answers to.
///
/// The combined Fluxidi app owns `fluxidi://pay/return` and never changes it.
/// A second host app installed alongside it — the standalone customer app —
/// owns its own scheme, so it declares that identity once at boot through
/// [PaymentReturnCoordinator.start]. Until something declares otherwise this
/// resolves to exactly the constants above.
String get fluxidiPaymentReturnUrl =>
    PaymentReturnCoordinator.instance.returnUrl;

Map<String, String>? _activePaymentScopeQuery() =>
    resolveMollieStreetStatusScopeQuery();

/// App-level coordinator that owns the Mollie return-to-app flow.
///
/// It MUST be started exactly once at app boot (before [runApp]) so the
/// `app_links` listener and the [WidgetsBindingObserver] are alive for the
/// whole app lifetime. Tying these to a screen-level [State] is unsafe because
/// the customer flow may not have the driver dashboard mounted when the
/// browser hands the deep link back.
class PaymentReturnCoordinator with WidgetsBindingObserver {
  PaymentReturnCoordinator._();

  static final PaymentReturnCoordinator instance = PaymentReturnCoordinator._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  bool _started = false;
  bool _initialChecked = false;
  bool _reconcileInFlight = false;
  String _bookingBaseUrl = '';
  String _returnScheme = kFluxidiPaymentReturnScheme;
  String _returnHost = kFluxidiPaymentReturnHost;
  String _returnUrl = kFluxidiPaymentReturnUrl;

  /// Return link this app hands to the payment provider and accepts back.
  String get returnUrl => _returnUrl;

  /// Starts (idempotently) the deep-link listener and lifecycle observer.
  /// [bookingBaseUrl] is the same value the rest of the app uses for the
  /// booking Worker; we keep it as a parameter so we don't pull main.dart's
  /// configuration into this lightweight module.
  ///
  /// [scheme], [host] and [returnUrl] default to the combined app's own
  /// `fluxidi://pay/return` identity. A host app that owns a different scheme
  /// passes its own, so two Fluxidi apps can be installed side by side without
  /// intercepting each other's return links.
  void start({
    required String bookingBaseUrl,
    String scheme = kFluxidiPaymentReturnScheme,
    String host = kFluxidiPaymentReturnHost,
    String returnUrl = kFluxidiPaymentReturnUrl,
  }) {
    _bookingBaseUrl = bookingBaseUrl;
    _returnScheme = scheme.trim().toLowerCase();
    _returnHost = host.trim().toLowerCase();
    _returnUrl = returnUrl.trim();
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _linkSub?.cancel();
    _linkSub = _appLinks.uriLinkStream.listen(
      (uri) => _handleIncomingDeepLink(uri, source: 'STREAM'),
      onError: (Object e) =>
          debugPrint('[PAY_RETURN][DEEP_LINK][STREAM_ERROR] $e'),
    );
    unawaited(_checkInitialDeepLink());
  }

  Future<void> _checkInitialDeepLink() async {
    if (_initialChecked) return;
    _initialChecked = true;
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _handleIncomingDeepLink(initial, source: 'COLD_START');
      }
    } catch (e) {
      debugPrint('[PAY_RETURN][DEEP_LINK][INITIAL_ERROR] $e');
    }
  }

  void _handleIncomingDeepLink(Uri uri, {required String source}) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    if (scheme != _returnScheme || host != _returnHost) {
      return;
    }
    final params = uri.queryParameters;
    final paymentBookingId =
        (params['payment_booking_id'] ??
                params['paymentBookingId'] ??
                params['payment_id'] ??
                params['id'] ??
                '')
            .trim();
    final publicBookingId =
        (params['booking_id'] ?? params['public_booking_id'] ?? '').trim();
    final statusRaw =
        (params['status'] ??
                params['payment_status'] ??
                params['paymentStatus'] ??
                '')
            .trim()
            .toLowerCase();
    if (paymentBookingId.isEmpty) return;

    // Deep-link query status is advisory only. Return URL / custom-scheme
    // handoff must NEVER mark the ride paid or confirmed by itself — only
    // authenticated `/pay/status` (or the Mollie webhook finalizer) may.
    final existing = fluxidiPendingPaymentNotifier.value;
    if (existing == null || existing.paymentBookingId != paymentBookingId) {
      setFluxidiPendingPayment(
        paymentBookingId: paymentBookingId,
        publicBookingId: publicBookingId.isNotEmpty ? publicBookingId : null,
      );
    } else if (publicBookingId.isNotEmpty &&
        (existing.publicBookingId == null ||
            existing.publicBookingId!.isEmpty)) {
      fluxidiPendingPaymentNotifier.value = existing.copyWith(
        publicBookingId: publicBookingId,
      );
    }
    final afterLink = fluxidiPendingPaymentNotifier.value;
    if (afterLink != null && afterLink.paymentBookingId == paymentBookingId) {
      fluxidiPendingPaymentNotifier.value = afterLink.copyWith(
        isChecking: true,
        lastCheckedAt: DateTime.now(),
      );
    }
    debugPrint(
      '[PAY_RETURN][DEEP_LINK] source=$source '
      'pay=${mollieStreetIdHash(paymentBookingId)} '
      'booking=${mollieStreetIdHash(publicBookingId)} '
      'hint_status=$statusRaw (hint ignored until /pay/status)',
    );
    unawaited(_reconcilePendingPayment(source: 'DEEP_LINK'));
  }

  Future<void> _reconcilePendingPayment({required String source}) async {
    if (_reconcileInFlight) return;
    final pending = fluxidiPendingPaymentNotifier.value;
    if (pending == null) return;
    if (pending.paymentBookingId.isEmpty) return;
    if (pending.status == FluxidiPaymentStatus.confirmed) return;
    if (_bookingBaseUrl.isEmpty) {
      debugPrint(
        '[PAY_RETURN][RECONCILE][SKIP] reason=no_base_url source=$source',
      );
      return;
    }

    _reconcileInFlight = true;
    fluxidiPendingPaymentNotifier.value = pending.copyWith(
      isChecking: true,
      lastCheckedAt: DateTime.now(),
    );

    try {
      final strictScope = _activePaymentScopeQuery();
      if (strictScope == null) {
        debugPrint(
          '[PAYMENT_SCOPE][BLOCK] reason=missing_street_status_scope action=pay_status',
        );
        return;
      }
      // Up to 6 attempts, 2s apart (~12s) — enough for /pay/status to finalize.
      for (int attempt = 1; attempt <= 6; attempt++) {
        final ok = await _pollPaymentStatusOnce(
          pending.paymentBookingId,
          attempt: attempt,
          source: source,
          strictScope: strictScope,
          publicBookingId: pending.publicBookingId,
        );
        if (ok) break;
        if (attempt < 6) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    } catch (e) {
      debugPrint('[PAY_RETURN][RECONCILE][ERROR] source=$source error=$e');
    } finally {
      final current = fluxidiPendingPaymentNotifier.value;
      if (current != null &&
          current.paymentBookingId == pending.paymentBookingId) {
        fluxidiPendingPaymentNotifier.value = current.copyWith(
          isChecking: false,
          lastCheckedAt: DateTime.now(),
        );
      }
      _reconcileInFlight = false;
    }
  }

  Future<bool> _pollPaymentStatusOnce(
    String paymentBookingId, {
    required int attempt,
    required String source,
    required Map<String, String> strictScope,
    String? publicBookingId,
  }) async {
    try {
      final uri = Uri.parse('$_bookingBaseUrl/pay/status').replace(
        queryParameters: <String, String>{
          'id': paymentBookingId,
          ...strictScope,
        },
      );
      // Same company-first auth helper as the street Mollie dialog.
      final auth = await resolveMollieStreetStatusAuthHeaders(json: false);
      if (auth.mode == MollieStreetStatusAuthMode.none) {
        logMollieStreetStatusDiag(
          authMode: auth.mode,
          httpStatus: 0,
          errorCode: 'missing_auth',
          paymentBookingId: paymentBookingId,
          canonicalBookingId: publicBookingId,
        );
        return false;
      }
      final res = await http
          .get(uri, headers: auth.headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        logMollieStreetStatusDiag(
          authMode: auth.mode,
          httpStatus: res.statusCode,
          errorCode: 'http_error',
          paymentBookingId: paymentBookingId,
          canonicalBookingId: publicBookingId,
        );
        return false;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return false;
      if (decoded['ok'] != true) return false;
      final dataRaw = decoded['data'];
      if (dataRaw is! Map) return false;
      final data = Map<String, dynamic>.from(dataRaw);

      final mollieMap = data['mollie'];
      final mollieStatus =
          (mollieMap is Map ? (mollieMap['status'] ?? '').toString() : '')
              .toLowerCase();
      final paymentStatus =
          (data['payment_status'] ?? data['paymentStatus'] ?? '')
              .toString()
              .toLowerCase();
      final paid = mollieStatus == 'paid' || paymentStatus == 'paid';
      final confirmedAt = (data['confirmed_at'] ?? data['confirmedAt'] ?? '')
          .toString()
          .trim();
      final confirmed = confirmedAt.isNotEmpty;

      logMollieStreetStatusDiag(
        authMode: auth.mode,
        httpStatus: res.statusCode,
        errorCode: confirmed
            ? 'confirmed'
            : (paid ? 'paid' : 'pending'),
        paymentBookingId: paymentBookingId,
        canonicalBookingId: publicBookingId,
      );

      final pending = fluxidiPendingPaymentNotifier.value;
      if (pending != null) {
        FluxidiPaymentStatus next = pending.status;
        if (confirmed) {
          next = FluxidiPaymentStatus.confirmed;
        } else if (paid) {
          next = FluxidiPaymentStatus.paid;
        }
        if (next != pending.status) {
          fluxidiPendingPaymentNotifier.value = pending.copyWith(
            status: next,
            lastCheckedAt: DateTime.now(),
            isChecking: !confirmed,
          );
        } else if (pending.isChecking) {
          fluxidiPendingPaymentNotifier.value = pending.copyWith(
            lastCheckedAt: DateTime.now(),
          );
        }
      }
      return confirmed;
    } catch (e) {
      debugPrint(
        '[PAY_RETURN][POLL][ERROR] source=$source attempt=$attempt error=$e',
      );
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final pending = fluxidiPendingPaymentNotifier.value;
    if (pending == null ||
        pending.paymentBookingId.isEmpty ||
        pending.status == FluxidiPaymentStatus.confirmed) {
      return;
    }
    fluxidiPendingPaymentNotifier.value = pending.copyWith(
      isChecking: true,
      lastCheckedAt: DateTime.now(),
    );
    unawaited(_reconcilePendingPayment(source: 'LIFECYCLE_RESUME'));
  }
}

final PaymentReturnCoordinator paymentReturnCoordinator =
    PaymentReturnCoordinator.instance;
