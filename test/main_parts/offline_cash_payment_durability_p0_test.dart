import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/offline_cash_payment_durability.dart';

void main() {
  setUp(OfflineCashSyncGuard.resetForTest);

  OfflineCashPaymentIntent intent({
    String bookingId = 'street_1',
    String tripId = 'trip_1',
    OfflineCashIntentStatus status = OfflineCashIntentStatus.pending,
  }) {
    final now = '2026-08-15T18:00:00.000Z';
    return OfflineCashPaymentIntent(
      idempotencyKey: offlineCashIdempotencyKey(
        tenantId: 'T1',
        companyId: 'C1',
        bookingId: bookingId,
        tripId: tripId,
      ),
      tenantId: 'T1',
      companyId: 'C1',
      driverId: 'D1',
      bookingId: bookingId,
      tripId: tripId,
      payload: <String, dynamic>{
        'booking_id': bookingId,
        'payment_status': 'paid',
        'payment_method': 'cash',
      },
      createdAtIso: now,
      updatedAtIso: now,
      status: status,
    );
  }

  test('offline cash is locally durable pending and survives restart JSON', () {
    final stored = intent();
    expect(stored.isPending, isTrue);
    final recovered = OfflineCashPaymentIntent.fromJson(stored.toJson())!;
    expect(recovered.idempotencyKey, stored.idempotencyKey);
    expect(recovered.status, OfflineCashIntentStatus.pending);
    expect(recovered.bookingId, 'street_1');
    expect(recovered.payload['payment_method'], 'cash');
    expect(recovered.idempotencyKey, 'cash_v1:T1:C1:street_1:trip_1:cash');
  });

  test('pending copy is the required Dutch status line', () {
    expect(
      kOfflineCashPendingStatusText,
      'Contant ontvangen · wacht op synchronisatie',
    );
    expect(
      offlineCashStatusCopyKey(OfflineCashUiPhase.pendingSync),
      kOfflineCashPendingCopyKey,
    );
    expect(
      offlineCashUiPhase(
        serverPaid: false,
        localStatus: OfflineCashIntentStatus.pending,
      ),
      OfflineCashUiPhase.pendingSync,
    );
  });

  test('pending cash blocks conflicting payment methods', () {
    expect(
      shouldBlockConflictingPaymentMethods(
        status: OfflineCashIntentStatus.pending,
      ),
      isTrue,
    );
    expect(
      shouldBlockConflictingPaymentMethods(
        status: OfflineCashIntentStatus.synced,
      ),
      isFalse,
    );
    expect(shouldBlockConflictingPaymentMethods(status: null), isFalse);
  });

  test('upsert keeps one intent per ride across widget/service restart', () {
    final first = intent();
    final again = intent().copyWith(updatedAtIso: '2026-08-15T18:05:00.000Z');
    final kept = upsertOfflineCashIntent(
      upsertOfflineCashIntent(const [], first),
      again,
    );
    expect(kept, hasLength(1));
    expect(kept.single.updatedAtIso, '2026-08-15T18:05:00.000Z');
    expect(
      offlineCashIntentForRide(
        kept,
        tenantId: 'T1',
        companyId: 'C1',
        bookingId: 'street_1',
        tripId: 'trip_1',
      )?.isPending,
      isTrue,
    );
  });

  test('reconnect posts at most once via the in-flight guard', () {
    final key = offlineCashIdempotencyKey(
      tenantId: 'T1',
      companyId: 'C1',
      bookingId: 'street_1',
      tripId: 'trip_1',
    );
    expect(OfflineCashSyncGuard.tryAcquire(key), isTrue);
    expect(OfflineCashSyncGuard.tryAcquire(key), isFalse);
    OfflineCashSyncGuard.release(key);
    expect(OfflineCashSyncGuard.tryAcquire(key), isTrue);
  });

  test('duplicate reconnect/resume does not create a second identity', () {
    final a = intent();
    final b = intent();
    expect(a.idempotencyKey, b.idempotencyKey);
    final pending = pendingOfflineCashIntents(
      upsertOfflineCashIntent([a], b),
      tenantId: 'T1',
      companyId: 'C1',
      driverId: 'D1',
    );
    expect(pending, hasLength(1));
  });

  test('idempotent already-applied cash converges to paid', () {
    expect(
      classifyExistingPaymentForOfflineCash(
        paymentStatus: 'paid',
        paymentMethod: 'cash',
      ),
      OfflineCashServerOutcome.alreadyAppliedCash,
    );
    expect(
      classifyOfflineCashHttpResponse(
        statusCode: 200,
        body: <String, dynamic>{
          'payment_status': 'paid',
          'payment_method': 'cash',
        },
      ),
      OfflineCashServerOutcome.alreadyAppliedCash,
    );
    expect(
      offlineCashUiPhase(
        serverPaid: true,
        localStatus: OfflineCashIntentStatus.pending,
      ),
      OfflineCashUiPhase.paid,
    );
  });

  test('a different confirmed method is a conflict and is not overwritten', () {
    expect(
      classifyExistingPaymentForOfflineCash(
        paymentStatus: 'paid',
        paymentMethod: 'mollie',
      ),
      OfflineCashServerOutcome.methodConflict,
    );
    expect(
      classifyOfflineCashHttpResponse(
        statusCode: 409,
        body: <String, dynamic>{
          'error': 'payment_already_paid_mollie',
          'payment_status': 'paid',
          'payment_method': 'mollie',
        },
      ),
      OfflineCashServerOutcome.methodConflict,
    );
    expect(
      offlineCashUiPhase(
        serverPaid: false,
        localStatus: OfflineCashIntentStatus.conflict,
      ),
      OfflineCashUiPhase.conflict,
    );
  });

  test('online cash success still classifies as applied', () {
    expect(
      classifyOfflineCashHttpResponse(
        statusCode: 200,
        body: <String, dynamic>{
          'ok': true,
          'payment_status': 'paid',
          'payment_method': 'cash',
        },
      ),
      OfflineCashServerOutcome.alreadyAppliedCash,
    );
    expect(isTransientPaymentNetworkError(Exception('HTTP 200')), isFalse);
  });

  test('network errors stay pending and are retryable', () {
    expect(
      isTransientPaymentNetworkError(Exception('SocketException: failed')),
      isTrue,
    );
    expect(
      isTransientPaymentNetworkError(
        Exception('TimeoutException after 0:00:12.000000'),
      ),
      isTrue,
    );
    expect(
      classifyOfflineCashHttpResponse(statusCode: 503, body: const {}),
      OfflineCashServerOutcome.retryableNetwork,
    );
  });

  test('Chiron STOP retry is independent of cash payment sync', () {
    final cash = intent();
    expect(cash.endpoint, isNot('chiron'));
    expect(cash.payload.containsKey('event_id'), isFalse);
    expect(isOfflineCashMethod('cash'), isTrue);
    expect(shouldBlockConflictingPaymentMethods(status: cash.status), isTrue);
  });

  test('document/Billit trigger stays a single cash identity', () {
    final first = intent();
    final replay = intent().copyWith(updatedAtIso: '2026-08-15T18:10:00.000Z');
    final rows = upsertOfflineCashIntent([first], replay);
    expect(rows, hasLength(1));
    expect(rows.single.payload['payment_method'], 'cash');
    expect(
      classifyExistingPaymentForOfflineCash(
        paymentStatus: 'paid',
        paymentMethod: 'contant',
      ),
      OfflineCashServerOutcome.alreadyAppliedCash,
    );
  });
}
