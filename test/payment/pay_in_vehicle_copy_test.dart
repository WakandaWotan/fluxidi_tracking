import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/payment/booking_payment_method_tile.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';

String t({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) {
  expect(nl, isNotEmpty);
  expect(en, isNotEmpty);
  expect(fr, isNotEmpty);
  expect(es, isNotEmpty);
  return nl;
}

void main() {
  test('pay in vehicle copy is informational and localized', () {
    final label = paymentMethodDisplayLabel(PaymentMethodIds.inVehicleCard, t);
    expect(label, contains('voertuig'));
    final description = paymentMethodShortDescription(
      PaymentMethodIds.inVehicleCard,
      t,
      qrPaymentConfigured: true,
    );
    expect(description, contains('contant'));
    expect(description, contains('QR'));
    expect(description, contains('kaart'));
    expect(description, contains('ingeschakeld'));
  });

  test('customer and tile surfaces keep NL/FR/EN/ES pay-in-vehicle wording', () {
    final tile = File(
      'lib/payment/booking_payment_method_tile.dart',
    ).readAsStringSync();
    final detail = File(
      'lib/main_parts/customer_booking_detail_page.dart',
    ).readAsStringSync();
    expect(tile, contains('Betalen in het voertuig'));
    expect(tile, contains('Pay in the vehicle'));
    expect(tile, contains('Payer dans le véhicule'));
    expect(tile, contains('Pagar en el vehículo'));
    expect(detail, contains('Te betalen in het voertuig'));
    expect(detail, contains('To pay in the vehicle'));
    expect(detail, contains('À payer dans le véhicule'));
    expect(detail, contains('A pagar en el vehículo'));
    expect(detail, contains('contant'));
    expect(detail, contains('QR'));
  });
}
