import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/planned_ride_price_presentation.dart';

/// PLANNED-RIDE-FIXED-PRICE-PRESENTATION-AND-DURABILITY-1
void main() {
  group('resolveDriverCockpitFarePresentation', () {
    test('1. active planned ride shows fixed booking price', () {
      final fare = resolveDriverCockpitFarePresentation(
        hasActiveBooking: true,
        isStreetOrDirectBooking: false,
        fixedBookingPriceEur: 42.5,
        liveMeterPreviewEur: 3.2,
      );
      expect(fare.amountText, '€ 42.50');
      expect(fare.usesFixedPrice, isTrue);
      expect(fare.cockpitLabel, 'Vaste prijs');
      expect(fare.tellersLabel, 'Vaste prijs');
    });

    test('2. planned ride does not show live meter total', () {
      final fare = resolveDriverCockpitFarePresentation(
        hasActiveBooking: true,
        isStreetOrDirectBooking: false,
        fixedBookingPriceEur: 42.5,
        liveMeterPreviewEur: 99.9,
      );
      expect(fare.amountText, isNot(contains('99.90')));
      expect(fare.amountText, '€ 42.50');
      expect(fare.usesFixedPrice, isTrue);
    });

    test('4. street/direct ride still shows live meter', () {
      final fare = resolveDriverCockpitFarePresentation(
        hasActiveBooking: true,
        isStreetOrDirectBooking: true,
        fixedBookingPriceEur: 42.5,
        liveMeterPreviewEur: 7.8,
      );
      expect(fare.amountText, '€ 7.80');
      expect(fare.usesFixedPrice, isFalse);
      expect(fare.cockpitLabel, '€');
      expect(fare.tellersLabel, 'Tarief');
    });

    test('5. missing planned price shows € — without meter fallback', () {
      final fare = resolveDriverCockpitFarePresentation(
        hasActiveBooking: true,
        isStreetOrDirectBooking: false,
        fixedBookingPriceEur: null,
        liveMeterPreviewEur: 12.34,
      );
      expect(fare.amountText, '€ —');
      expect(fare.amountText, isNot(contains('12.34')));
      expect(fare.usesFixedPrice, isTrue);
    });

    test('active planned ride ignores zero fixed and still never uses meter', () {
      final fare = resolveDriverCockpitFarePresentation(
        hasActiveBooking: true,
        isStreetOrDirectBooking: false,
        fixedBookingPriceEur: 0,
        liveMeterPreviewEur: 5.0,
      );
      expect(fare.amountText, '€ —');
    });

    test('no booking keeps live meter presentation', () {
      final fare = resolveDriverCockpitFarePresentation(
        hasActiveBooking: false,
        isStreetOrDirectBooking: false,
        fixedBookingPriceEur: null,
        liveMeterPreviewEur: 2.5,
      );
      expect(fare.amountText, '€ 2.50');
      expect(fare.usesFixedPrice, isFalse);
    });
  });

  group('resolvePlannedDisplayPriceFromBookingMap', () {
    test('3. return operational leg uses return-leg price not package total', () {
      final price = resolvePlannedDisplayPriceFromBookingMap(<String, dynamic>{
        'booking_id': 'bk_roundtrip',
        'leg_id': 'leg_return_1',
        'leg_type': 'return',
        'is_operational_leg': true,
        'price_incl_vat_return': 40.0,
        'price_incl_vat_main': 60.0,
        'parent_price_incl_vat': 100.0,
        'price': 100.0,
      });
      expect(price, 40.0);
      expect(price, isNot(100.0));
    });

    test('outbound operational leg uses main-leg price', () {
      final price = resolvePlannedDisplayPriceFromBookingMap(<String, dynamic>{
        'booking_id': 'bk_roundtrip',
        'leg_id': 'leg_out_1',
        'leg_type': 'outbound',
        'is_operational_leg': true,
        'price_incl_vat_main': 60.0,
        'price_incl_vat_return': 40.0,
        'parent_price_incl_vat': 100.0,
      });
      expect(price, 60.0);
    });

    test('leg_price_incl_vat wins for planned display', () {
      final price = resolvePlannedDisplayPriceFromBookingMap(<String, dynamic>{
        'booking_id': 'bk_one',
        'leg_id': 'leg_1',
        'leg_type': 'outbound',
        'is_operational_leg': true,
        'leg_price_incl_vat': 22.5,
        'price_incl_vat_main': 60.0,
        'parent_price_incl_vat': 100.0,
      });
      expect(price, 22.5);
    });
  });

  group('street booking classifier for presentation', () {
    test('street_ride source is treated as live-meter ride', () {
      expect(
        bookingRecordIsStreetDirect(<String, dynamic>{
          'booking_id': 'street_123_abc',
          'source': 'street_ride',
          'ride_type': 'direct',
        }),
        isTrue,
      );
    });

    test('planned booking is not street/direct', () {
      expect(
        bookingRecordIsStreetDirect(<String, dynamic>{
          'booking_id': 'bk_planned_1',
          'source': 'customer_app',
          'ride_type': 'planned',
        }),
        isFalse,
      );
    });
  });
}
