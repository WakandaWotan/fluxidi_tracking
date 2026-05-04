import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:http/http.dart' as http;

const String kFluxidiPaymentReturnScheme = 'fluxidi';
const String kFluxidiPaymentReturnHost = 'pay';
const String kFluxidiPaymentReturnUrl = 'fluxidi://pay/return';

enum FluxidiPaymentStatus { pending, paid, confirmed, failed }

class FluxidiPendingPayment {
  const FluxidiPendingPayment({
    required this.paymentBookingId,
    this.publicBookingId,
    this.status = FluxidiPaymentStatus.pending,
    this.lastCheckedAt,
  });

  final String paymentBookingId;
  final String? publicBookingId;
  final FluxidiPaymentStatus status;
  final DateTime? lastCheckedAt;

  FluxidiPendingPayment copyWith({
    FluxidiPaymentStatus? status,
    DateTime? lastCheckedAt,
    String? publicBookingId,
  }) {
    return FluxidiPendingPayment(
      paymentBookingId: paymentBookingId,
      publicBookingId: publicBookingId ?? this.publicBookingId,
      status: status ?? this.status,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    );
  }
}

final ValueNotifier<FluxidiPendingPayment?> fluxidiPendingPaymentNotifier =
    ValueNotifier<FluxidiPendingPayment?>(null);

Map<String, String> _activePaymentScopeQuery() {
  final resolvedId = resolvedCompanyId.trim();
  final tenantId = resolvedId.isNotEmpty ? resolvedId : kTenantId.trim();
  final companyId = resolvedId.isNotEmpty ? resolvedId : tenantId;
  return <String, String>{
    'tenant_id': tenantId,
    'company_id': companyId,
    'tenantId': tenantId,
    'companyId': companyId,
  };
}

void setFluxidiPendingPayment({
  required String paymentBookingId,
  String? publicBookingId,
}) {
  if (paymentBookingId.trim().isEmpty) return;
  fluxidiPendingPaymentNotifier.value = FluxidiPendingPayment(
    paymentBookingId: paymentBookingId.trim(),
    publicBookingId: (publicBookingId ?? '').trim().isEmpty
        ? null
        : publicBookingId!.trim(),
  );
}

void clearFluxidiPendingPayment() {
  fluxidiPendingPaymentNotifier.value = null;
}

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

  /// Starts (idempotently) the deep-link listener and lifecycle observer.
  /// [bookingBaseUrl] is the same value the rest of the app uses for the
  /// booking Worker; we keep it as a parameter so we don't pull main.dart's
  /// configuration into this lightweight module.
  void start({required String bookingBaseUrl}) {
    _bookingBaseUrl = bookingBaseUrl;
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
    if (scheme != kFluxidiPaymentReturnScheme ||
        host != kFluxidiPaymentReturnHost) {
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
    if (paymentBookingId.isEmpty) return;

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

    try {
      // Up to 6 attempts, 2s apart (~12s) — enough for /pay/status to finalize.
      for (int attempt = 1; attempt <= 6; attempt++) {
        final ok = await _pollPaymentStatusOnce(
          pending.paymentBookingId,
          attempt: attempt,
          source: source,
        );
        if (ok) break;
        if (attempt < 6) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    } catch (e) {
      debugPrint('[PAY_RETURN][RECONCILE][ERROR] source=$source error=$e');
    } finally {
      _reconcileInFlight = false;
    }
  }

  Future<bool> _pollPaymentStatusOnce(
    String paymentBookingId, {
    required int attempt,
    required String source,
  }) async {
    try {
      final uri = Uri.parse('$_bookingBaseUrl/pay/status').replace(
        queryParameters: <String, String>{
          'id': paymentBookingId,
          ..._activePaymentScopeQuery(),
        },
      );
      final res = await http
          .get(uri, headers: const {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) {
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
    unawaited(_reconcilePendingPayment(source: 'LIFECYCLE_RESUME'));
  }
}

final PaymentReturnCoordinator paymentReturnCoordinator =
    PaymentReturnCoordinator.instance;
