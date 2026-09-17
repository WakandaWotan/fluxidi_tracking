import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_addresses.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_vehicles.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';

void main() {
  test('only offered company categories are bookable', () {
    final categories = customerBookingBookableCategories(
      const <Map<String, dynamic>>[
        <String, dynamic>{
          'vehicle_id': 'vh_1',
          'vehicle_type': 'sedan',
          'tier': 'premium',
          'seats': 3,
        },
      ],
      passengers: 1,
    );
    expect(categories, <CompanyPlanVehicleCategory>[
      CompanyPlanVehicleCategory.premium,
    ]);
    expect(categories, isNot(contains(CompanyPlanVehicleCategory.minivan)));
  });

  test('profile default address uses street, postcode and city', () {
    const profile = CustomerProfile(
      customerId: 'cus_1',
      name: 'Christophe',
      phone: '+32',
      email: 'c@example.com',
      preferredPostcode: '9688',
      companyName: '',
      vatNumber: '',
      billingStreet: 'Koekamerstraat 488A',
      billingPostalCode: '9688',
      billingCity: 'Maarkedal',
      createdAt: '',
      updatedAt: '',
    );
    expect(
      customerProfileDefaultAddressLine(profile),
      'Koekamerstraat 488A, 9688 Maarkedal',
    );
  });

  test('registered capacity is shown instead of a default sedan guess', () {
    expect(
      customerBookingVehicleCapacityLabel(
        vehicle: const <String, dynamic>{
          'seats': 3,
          'bags': 2,
        },
        category: CompanyPlanVehicleCategory.premium,
        language: AppLanguage.nl,
      ),
      '3 pax · 2 bagage',
    );
  });
}
