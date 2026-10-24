import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ordinary receipt PDF uses 4× logo box; invoice CSS height stays 48', () {
    final receiptRunner = File(
      'lib/main_parts/receipt_pdf_action_runner.dart',
    ).readAsStringSync();
    final rideReceipt = File(
      'lib/main_parts/ride_receipt_body_state.dart',
    ).readAsStringSync();
    final invoiceCss = File(
      'workers/booking/modules/invoice_print_layout.js',
    ).readAsStringSync();

    expect(receiptRunner.contains('kReceiptPdfLogoBoxWidth'), isTrue);
    expect(rideReceipt.contains('kReceiptPdfLogoBoxWidth'), isTrue);
    expect(receiptRunner.contains('width: 82'), isFalse);
    expect(rideReceipt.contains('width: 82'), isFalse);

    expect(invoiceCss.contains('INVOICE_LOGO_CSS_HEIGHT_PX = 48'), isTrue);
    expect(invoiceCss.contains('Math.min(72,'), isTrue);
  });
}
