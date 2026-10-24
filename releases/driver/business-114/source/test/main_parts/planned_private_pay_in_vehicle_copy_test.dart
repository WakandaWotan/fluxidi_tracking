// Source-contract: private pay-in-vehicle success copy promises a ritbon,
// never an invoice. Business-invoice copy stays on the checked path.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) fail('Source file not found: $relativePath');
  return file.readAsStringSync();
}

void main() {
  group('private pay-in-vehicle ritbon copy', () {
    late String calculator;
    late String airport;

    setUpAll(() {
      calculator = _read('lib/calculator_page.dart');
      airport = _read('lib/airport/airport_booking_review_page.dart');
    });

    test('private calculator success uses ritbon copy, not invoice copy', () {
      const privateNl =
          'Boeking aangemaakt. Betaling in de wagen. De ritbon wordt aangemaakt na betaling.';
      expect(calculator, contains(privateNl));
      expect(
        calculator,
        contains('The ride receipt will be created after payment.'),
      );
      expect(
        calculator,
        contains('Le recu de course sera cree apres le paiement.'),
      );
      expect(
        calculator,
        contains('El recibo de viaje se creara despues del pago.'),
      );
      expect(calculator, isNot(contains('De factuur volgt na betaling')));
      final privateMsgIdx = calculator.indexOf(privateNl);
      final nearby = calculator.substring(
        privateMsgIdx,
        privateMsgIdx + privateNl.length + 80,
      );
      expect(nearby, isNot(contains('Factuur volgt na betaling')));
    });

    test('private airport success uses the same ritbon copy', () {
      const privateNl =
          'Boeking aangemaakt. Betaling in de wagen. De ritbon wordt aangemaakt na betaling.';
      expect(airport, contains(privateNl));
      expect(airport, isNot(contains('De factuur volgt na betaling')));
      final privateMsgIdx = airport.indexOf(privateNl);
      final nearby = airport.substring(
        privateMsgIdx,
        privateMsgIdx + privateNl.length + 80,
      );
      expect(nearby, isNot(contains('Factuur volgt na betaling')));
    });

    test('checked business invoice still promises the invoice after payment', () {
      expect(
        calculator,
        contains('Factuur volgt na betaling.'),
      );
      expect(
        airport,
        contains('Factuur volgt na betaling.'),
      );
    });

    test('invoice snackbar is gated on the user invoice toggle, not inferred VAT', () {
      expect(calculator, contains('userRequestedBusinessInvoice = _billingDetailsEnabled'));
      expect(calculator, contains('!explicitPrivateIntent'));
      final companyIdx = calculator.indexOf('final companyName = _billingDetailsEnabled');
      expect(companyIdx, greaterThan(-1));
      final vatIdx = calculator.indexOf('final vatNumber = _billingDetailsEnabled');
      expect(vatIdx, greaterThan(-1));
      expect(airport, contains('_billingDetailsEnabled'));
      final airportBusinessIdx = airport.indexOf('final manualBusinessFlow =');
      expect(airportBusinessIdx, greaterThan(-1));
      final airportBusiness = airport.substring(
        airportBusinessIdx,
        airportBusinessIdx + 280,
      );
      expect(airportBusiness, contains('_billingDetailsEnabled'));
      expect(airportBusiness, isNot(contains('businessInvoiceIntent')));
    });
  });
}
