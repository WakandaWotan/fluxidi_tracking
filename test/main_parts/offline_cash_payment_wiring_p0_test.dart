import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-wiring guard for OFFLINE-CASH-COLLECTION-P0.
void main() {
  late String receipt;
  late String driverHome;
  late String stores;
  late String texts;

  setUpAll(() {
    receipt = File(
      'lib/main_parts/ride_receipt_body_state.dart',
    ).readAsStringSync();
    driverHome = File(
      'lib/main_parts/driver_home_page_state.dart',
    ).readAsStringSync();
    stores = File(
      'lib/main_parts/compliance_local_stores.dart',
    ).readAsStringSync();
    texts = File('lib/main_parts/receipt_text_helpers.dart').readAsStringSync();
  });

  test('cash persist writes the local outbox before the network POST', () {
    expect(receipt.contains('_tryPersistOfflineCashBeforePost('), isTrue);
    expect(receipt.contains("endpoint: 'booking'"), isTrue);
    expect(
      texts.contains('Contant ontvangen · wacht op synchronisatie'),
      isTrue,
    );
    expect(receipt.contains("method: 'cash'"), isTrue);
  });

  test('conflicting methods are blocked while cash is pending', () {
    expect(receipt.contains('!_offlineCashAwaitingSync'), isTrue);
    expect(receipt.contains('!_offlineCashConflict'), isTrue);
    expect(
      receipt.contains('_shouldShowStreetInvoicePaymentSlot() &&'),
      isTrue,
    );
  });

  test('reconnect and resume drain the same cash outbox once', () {
    expect(driverHome.contains('_drainOfflineCashPayments()'), isTrue);
    expect(receipt.contains('_drainOfflineCashPayments()'), isTrue);
    expect(stores.contains('OfflineCashSyncGuard.tryAcquire'), isTrue);
    expect(stores.contains('_replayOfflineCashPaymentIntent'), isTrue);
  });

  test('online cash still uses the existing mark-paid POST', () {
    expect(
      receipt.contains('/bookings/\${Uri.encodeComponent(bookingId)}/payment'),
      isTrue,
    );
    expect(receipt.contains('_receiptText(\'paymentMarkedPaid\')'), isTrue);
    expect(receipt.contains('isTransientPaymentNetworkError(err)'), isTrue);
  });

  test('Chiron STOP drain stays separate from cash sync', () {
    expect(driverHome.contains('_recoverPendingDirectTripSession()'), isTrue);
    expect(stores.contains('Chiron STOP remains a separate outbox'), isTrue);
    expect(stores.contains('_drainOfflineCashPayments'), isTrue);
    final cashDrain = driverHome.indexOf(
      'unawaited(_drainOfflineCashPayments());',
    );
    final stopRecover = driverHome.indexOf(
      'unawaited(_recoverPendingDirectTripSession());',
    );
    expect(cashDrain, greaterThan(0));
    expect(stopRecover, greaterThan(0));
  });
}
