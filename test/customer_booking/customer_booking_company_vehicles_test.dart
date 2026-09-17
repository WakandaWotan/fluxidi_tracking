import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_addresses.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_vehicles.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

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

  test('missing passenger seats stay unknown instead of a sedan default', () {
    expect(
      customerBookingVehicleCapacityLabel(
        vehicle: const <String, dynamic>{
          'vehicle_id': 'vh_unknown',
        },
        category: CompanyPlanVehicleCategory.sedan,
        language: AppLanguage.nl,
      ),
      'Capaciteit onbekend',
    );
  });

  test('owned 9688 address keeps its text and refuses Ronse coordinates', () {
    const query = 'Koekamerstraat 48A, 9688 Schorisse, BE';
    final resolved = limousineResolveOwnedAddress(
      query: query,
      result: LimousinePlaceLookupResult(
        suggestions: const <LimousinePlaceSuggestion>[
          LimousinePlaceSuggestion(
            label: 'Koekamerstraat - Rue Cocambre 48a, 9600 Ronse, België',
            lat: 50.770403,
            lon: 3.672568,
            placeType: 'address',
            postcode: '9600',
            locality: 'Ronse',
          ),
          LimousinePlaceSuggestion(
            label: 'Koekamerstraat 48, 9688 Maarkedal, België',
            lat: 50.77205,
            lon: 3.66942,
            placeType: 'address',
            postcode: '9688',
            locality: 'Maarkedal',
          ),
        ],
      ),
    );
    expect(resolved.value.displayText, query);
    expect(resolved.value.hasCoordinates, isFalse);
    expect(resolved.needsConfirm, isTrue);
    expect(resolved.candidate?.lat, 50.77205);
    expect(resolved.candidate?.lon, 3.66942);
    expect(resolved.value.displayText.contains('Ronse'), isFalse);
  });

  test('a proven 48A match at 9688 may attach coordinates', () {
    const query = 'Koekamerstraat 48A, 9688 Schorisse, BE';
    final resolved = limousineResolveOwnedAddress(
      query: query,
      result: const LimousinePlaceLookupResult(
        suggestions: <LimousinePlaceSuggestion>[
          LimousinePlaceSuggestion(
            label: 'Koekamerstraat - Rue Cocambre 48a, 9600 Ronse, België',
            lat: 50.770403,
            lon: 3.672568,
            placeType: 'address',
            postcode: '9600',
            locality: 'Ronse',
          ),
          LimousinePlaceSuggestion(
            label: 'Koekamerstraat 48A, 9688 Maarkedal, België',
            lat: 50.77205,
            lon: 3.66942,
            placeType: 'address',
            postcode: '9688',
            locality: 'Maarkedal',
          ),
        ],
      ),
    );
    expect(resolved.value.displayText, query);
    expect(resolved.value.lat, 50.77205);
    expect(resolved.value.lon, 3.66942);
    expect(resolved.needsConfirm, isFalse);
  });

  test('street-level Koekamerstraat without a house number is not proven', () {
    const query = 'Koekamerstraat 48A, 9688 Schorisse, BE';
    final resolved = limousineResolveOwnedAddress(
      query: query,
      result: const LimousinePlaceLookupResult(
        suggestions: <LimousinePlaceSuggestion>[
          LimousinePlaceSuggestion(
            label: 'Koekamerstraat, 9688 Maarkedal, België',
            lat: 50.771,
            lon: 3.67,
            placeType: 'address',
            postcode: '9688',
            locality: 'Maarkedal',
          ),
        ],
      ),
    );
    expect(resolved.value.displayText, query);
    expect(resolved.value.hasCoordinates, isFalse);
    expect(resolved.needsConfirm, isTrue);
    expect(resolved.candidate, isNull);
  });

  test('geocode failure keeps the typed address and asks for confirmation', () {
    const query = 'Koekamerstraat 48A, 9688 Schorisse, BE';
    final resolved = limousineResolveOwnedAddress(
      query: query,
      result: const LimousinePlaceLookupResult(hadError: true),
    );
    expect(resolved.value.displayText, query);
    expect(resolved.value.hasCoordinates, isFalse);
    expect(resolved.needsConfirm, isTrue);
  });

  test('public-media photo refs become booking HTTPS and missing photos stay', () {
    expect(
      customerBookingVehiclePhotoUrl(<String, dynamic>{
        'vehicle_id': 'vh_tesla',
        'photo_url': 'public-media/t1/c1/vehicles/vh_tesla/gallery/a.jpg',
      }),
      contains('/public/media/t1/c1/vehicles/vh_tesla/gallery/a.jpg'),
    );
    expect(
      customerBookingVehiclePhotoUrl(<String, dynamic>{
        'vehicle_id': 'vh_bare',
        'name': 'Cadillac',
      }),
      isEmpty,
    );
  });

  test('Fluxidi taxi catalog keeps Hoofdwagen and Cadillac, not limousines', () {
    final snapshot = customerBookingCompanySnapshotFromProfile(
      <String, dynamic>{
        'company_name': 'Fluxidi',
        'vehicles': <Map<String, dynamic>>[
          <String, dynamic>{
            'vehicle_id': 'vh_1',
            'name': 'Hoofdwagen',
            'passenger_capacity': 3,
          },
          <String, dynamic>{
            'vehicle_id': 'vh_1786881139131',
            'name': 'Cadillac',
            'passenger_capacity': 4,
          },
          <String, dynamic>{
            'vehicle_id': 'vh_1787058237109',
            'name': 'Party Limo',
            'service_category': 'limousine',
            'passenger_capacity': 16,
          },
          <String, dynamic>{
            'vehicle_id': 'vh_1787076028764',
            'name': 'Hummer white',
            'service_category': 'limousine',
            'passenger_capacity': 8,
          },
        ],
      },
    );
    expect(
      snapshot.vehicles
          .map((vehicle) => vehicle['vehicle_id']?.toString())
          .toList(),
      <String>['vh_1', 'vh_1786881139131'],
    );
    expect(
      snapshot.vehicles
          .map(
            (vehicle) =>
                vehicle['passenger_capacity'] ?? vehicle['pax'] ?? vehicle['seats'],
          )
          .toList(),
      <int>[3, 4],
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
