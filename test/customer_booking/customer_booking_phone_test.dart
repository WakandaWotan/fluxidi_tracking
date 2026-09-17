import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_billing.dart';

void main() {
  group('booking contact phone', () {
    test('plus and 00 follow the international contract on their own', () {
      for (final raw in <String>['+32470123456', '0032470123456']) {
        final resolved = resolveCustomerBookingPhone(phone: raw);
        expect(resolved.state, CustomerBookingPhoneState.international);
        expect(resolved.e164, '+32470123456');
      }
      // Spacing and punctuation do not change the contract.
      expect(
        resolveCustomerBookingPhone(phone: '+32 470 12 34 56').e164,
        '+32470123456',
      );
    });

    test('an ambiguous national number asks instead of guessing', () {
      final resolved = resolveCustomerBookingPhone(phone: '0470123456');
      expect(resolved.state, CustomerBookingPhoneState.needsCountry);
      expect(resolved.e164, isEmpty);
      // The raw input is preserved, never rewritten to a guessed country.
      expect(
        customerBookingInternationalPhone(phone: '0470123456'),
        '0470123456',
      );
    });

    test('an explicit phone country completes a national number', () {
      expect(
        resolveCustomerBookingPhone(
          phone: '0470123456',
          phoneCountry: 'BE',
        ).e164,
        '+32470123456',
      );
      expect(
        resolveCustomerBookingPhone(
          phone: '0470123456',
          phoneCountryCallingCode: '32',
        ).e164,
        '+32470123456',
      );
    });

    test('the billing address is never used as the phone country', () {
      // A Dutch number stored with a Dutch phone country stays Dutch even
      // though the customer is invoiced in Belgium.
      final dutchNumber = resolveCustomerBookingPhone(
        phone: '+31612345678',
        phoneCountry: 'BE',
      );
      expect(dutchNumber.e164, '+31612345678');

      // A foreign number typed nationally is not silently made Belgian: the
      // helper has no billing-country input at all.
      final ambiguous = resolveCustomerBookingPhone(phone: '0612345678');
      expect(ambiguous.state, CustomerBookingPhoneState.needsCountry);
    });

    test('a foreign number with a Belgian billing address stays foreign', () {
      // French mobile, customer invoiced in Belgium.
      expect(
        customerBookingInternationalPhone(
          phone: '+33612345678',
          phoneCountry: 'BE',
        ),
        '+33612345678',
      );
      // Same number typed with 00.
      expect(
        customerBookingInternationalPhone(
          phone: '0033612345678',
          phoneCountry: 'BE',
        ),
        '+33612345678',
      );
      // And when the stored phone country is the real one.
      expect(
        customerBookingInternationalPhone(
          phone: '0612345678',
          phoneCountry: 'FR',
        ),
        '+33612345678',
      );
    });

    test('an incomplete international number is reported, not accepted', () {
      final resolved = resolveCustomerBookingPhone(phone: '+32');
      expect(resolved.state, CustomerBookingPhoneState.invalid);
      expect(resolved.isUsable, isFalse);
    });

    test('an empty field is empty, not an error', () {
      expect(
        resolveCustomerBookingPhone(phone: '   ').state,
        CustomerBookingPhoneState.empty,
      );
      expect(customerBookingInternationalPhone(phone: ''), isEmpty);
    });

    test('unknown countries yield no calling code', () {
      expect(customerBookingCountryCallingCode('BE'), '32');
      expect(customerBookingCountryCallingCode('fr'), '33');
      expect(customerBookingCountryCallingCode('ZZ'), isEmpty);
      expect(
        resolveCustomerBookingPhone(
          phone: '0470123456',
          phoneCountry: 'ZZ',
        ).state,
        CustomerBookingPhoneState.needsCountry,
      );
    });
  });
}
