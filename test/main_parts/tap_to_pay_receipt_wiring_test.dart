// TAP-TO-PAY-DRIVER-UI-1 — source-contract wiring for receipt Tap to Pay.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) =>
    File(relativePath).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  late String receiptSource;
  late String helpersSource;
  late String appConfigSource;

  setUpAll(() {
    receiptSource = _read('lib/main_parts/ride_receipt_body_state.dart');
    helpersSource = _read('lib/main_parts/receipt_text_helpers.dart');
    appConfigSource = _read('lib/app_config.dart');
  });

  test('Tap to Pay and manual Bancontact are distinct actions', () {
    expect(helpersSource, contains("case 'tapToPay':"));
    expect(helpersSource, contains("case 'paidByCardTerminal':"));
    expect(helpersSource, contains('Bancontact handmatig registreren'));
    expect(helpersSource, contains('Tap to Pay'));
    expect(helpersSource, isNot(contains('Betaald via Bancontact')));

    expect(receiptSource, contains('_startTapToPay'));
    expect(receiptSource, contains("method: 'bancontact'"));
    expect(receiptSource, contains('_persistInCarPayment'));
    expect(receiptSource, contains("'tapToPay'"));
    expect(receiptSource, contains("'paidByCardTerminal'"));
  });

  test('Tap to Pay is capability-gated and double-tap guarded', () {
    expect(receiptSource, contains('_tapToPayAvailable'));
    expect(receiptSource, contains('shouldShowTapToPayAction'));
    expect(receiptSource, contains('_tapToPayStartGuard'));
    expect(receiptSource, contains('if (_tapToPayAvailable)'));
    expect(receiptSource, contains('!_tapToPayInFlight'));
  });

  test('client start path never sends amount authority', () {
    expect(appConfigSource, contains('startDriverMollieTerminalPayment'));
    expect(appConfigSource, contains('pollDriverMollieTerminalPaymentStatus'));
    expect(appConfigSource, contains('fetchDriverMollieTerminalCapability'));
    final startFn = RegExp(
      r'Future<Map<String, dynamic>> startDriverMollieTerminalPayment\([\s\S]*?\n\}',
    ).firstMatch(appConfigSource)?.group(0);
    expect(startFn, isNotNull);
    expect(startFn!, isNot(contains("'amount'")));
    expect(startFn, isNot(contains('terminal_id')));
    expect(receiptSource, contains('Never send amount'));
  });

  test('paid only via server poll / paid mapping; not on cancel', () {
    expect(receiptSource, contains('cardTerminalShouldWritePaid'));
    expect(receiptSource, contains('pollDriverMollieTerminalPaymentStatus'));
    expect(receiptSource, contains('never invent paid'));
  });

  test('phone and tablet share the same logical path helper', () {
    expect(receiptSource, contains('tapToPayLogicalPathId'));
  });
}
