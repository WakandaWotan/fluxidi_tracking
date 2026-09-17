import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_billing.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_vehicles.dart';
import 'package:fluxidi_tracking/payment/booking_billing_identity.dart';

void main() {
  const leftover = BookingBillingIdentity(
    legalName: 'Flex Demo BV',
    vatNumber: 'BE0123456789',
    street: 'Koekamerstraat 48A',
    postalCode: '9688',
    city: 'Maarkedal',
    country: 'BE',
  );

  test('private ride sends no leftover billing_customer', () {
    final fields = customerBookingBillingPayloadFields(
      businessRide: false,
      identity: leftover,
      defaultEmail: 'c@example.com',
      defaultPhone: '+32469788891',
    );
    expect(fields, isEmpty);
  });

  test('business ride reuses the shared billing_customer fragment', () {
    final fields = customerBookingBillingPayloadFields(
      businessRide: true,
      identity: leftover,
      defaultEmail: 'c@example.com',
      defaultPhone: '+32469788891',
    );
    expect(fields['billing_customer'], isA<Map<String, dynamic>>());
    final customer = fields['billing_customer'] as Map<String, dynamic>;
    expect(customer['customer_type'], 'business');
    expect(customer['legal_name'], 'Flex Demo BV');
    expect(customer['vat_number'], 'BE0123456789');
  });

  test('profile name is read without inventing a company', () {
    expect(
      customerBookingCompanyNameFromProfile(const <String, dynamic>{
        'display_name': 'All-in Taxi Christophe Vanroeghem',
      }),
      'All-in Taxi Christophe Vanroeghem',
    );
    expect(
      customerBookingCompanyNameFromProfile(const <String, dynamic>{}),
      isEmpty,
    );
  });
}
