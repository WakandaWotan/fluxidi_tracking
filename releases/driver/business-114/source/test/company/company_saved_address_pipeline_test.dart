import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_address_field.dart';
import 'package:fluxidi_tracking/company/company_customer_ground.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

/// The saved address exactly as the dossier shows it.
const _saved = CompanyCustomerAddress(
  type: 'home',
  label: 'Thuis',
  line1: 'Koekamerstraat 48A',
  postalCode: '9688',
  city: 'Maarkedal',
  countryCode: 'BE',
);

CompanyCustomer _customerWith(List<CompanyCustomerAddress> addresses) {
  return CompanyCustomer(
    customerId: 'cus_anon',
    tenantId: 'tenant_anon',
    companyId: 'company_anon',
    displayName: 'Anon Customer',
    firstName: 'Anon',
    lastName: 'Customer',
    phone: '',
    phoneNormalized: '',
    countryCallingCode: '32',
    email: '',
    locale: 'nl',
    companyName: 'Anon BV',
    vatNumber: '',
    addresses: addresses,
    internalNotes: '',
    preferences: const CompanyCustomerPreferences(),
    source: 'manual',
    status: 'active',
    createdAt: '',
    updatedAt: '',
    archivedAt: null,
    revision: 1,
  );
}

LimousineAddressFieldController _field(String id) {
  return LimousineAddressFieldController(
    lookup: LimousinePlaceLookup(
      searchOverride: (query, language) async =>
          const LimousinePlaceLookupResult(suggestions: []),
    ),
    fieldId: id,
  );
}

void main() {
  group('saved customer address reaches the planner intact', () {
    test('the formatted line keeps street and house number', () {
      expect(
        companyCustomerAddressLine(_saved),
        'Koekamerstraat 48A, 9688 Maarkedal, BE',
      );
    });

    test('applying it to the pickup field keeps the street', () {
      final pickup = _field('pickup');
      final dropoff = _field('dropoff');
      addTearDown(pickup.dispose);
      addTearDown(dropoff.dispose);

      companyApplyCustomerGroundAddress(
        customer: _customerWith(const <CompanyCustomerAddress>[_saved]),
        options: const CompanyRideOptions(),
        pickup: pickup,
        dropoff: dropoff,
      );

      expect(pickup.textController.text, contains('Koekamerstraat 48A'));
      expect(pickup.value.displayText, contains('Koekamerstraat 48A'));
      expect(pickup.value.routeText, contains('Koekamerstraat 48A'));
    });

    test('a stored address without a street degrades to the locality', () {
      // This is what the planner actually showed, so it pins the shape that
      // produces it: the street simply was not in the record.
      const withoutStreet = CompanyCustomerAddress(
        type: 'home',
        label: 'Thuis',
        postalCode: '9688',
        city: 'Maarkedal',
        countryCode: 'BE',
      );
      expect(companyCustomerAddressLine(withoutStreet), '9688 Maarkedal, BE');
    });

    test('a separate house number stays on the street line', () {
      final parsed = parseCompanyCustomerAddress(<String, dynamic>{
        'type': 'home',
        'street': 'Koekamerstraat',
        'house_number': '48A',
        'postal_code': '9688',
        'city': 'Maarkedal',
        'country_code': 'BE',
      });
      expect(parsed.line1, 'Koekamerstraat 48A');
      expect(
        companyCustomerAddressLine(parsed),
        'Koekamerstraat 48A, 9688 Maarkedal, BE',
      );

      final pickup = _field('pickup_house');
      final dropoff = _field('dropoff_house');
      addTearDown(pickup.dispose);
      addTearDown(dropoff.dispose);
      companyApplyCustomerGroundAddress(
        customer: _customerWith(<CompanyCustomerAddress>[parsed]),
        options: const CompanyRideOptions(),
        pickup: pickup,
        dropoff: dropoff,
      );
      expect(pickup.textController.text, contains('Koekamerstraat 48A'));
      expect(pickup.value.displayText, contains('9688'));
      expect(pickup.value.displayText, contains('Maarkedal'));
    });

    test('the stored record is parsed with its street', () {
      final parsed = parseCompanyCustomerAddress(<String, dynamic>{
        'type': 'home',
        'label': 'Thuis',
        'line1': 'Koekamerstraat 48A',
        'postal_code': '9688',
        'city': 'Maarkedal',
        'country_code': 'BE',
      });
      expect(parsed.line1, 'Koekamerstraat 48A');
      expect(
        companyCustomerAddressLine(parsed),
        'Koekamerstraat 48A, 9688 Maarkedal, BE',
      );
    });

    test('alternative street keys are read instead of being dropped', () {
      for (final key in const <String>[
        'street',
        'address_line1',
        'addressLine1',
        'line_1',
        'streetAddress',
        'street_address',
      ]) {
        final parsed = parseCompanyCustomerAddress(<String, dynamic>{
          'type': 'home',
          key: 'Koekamerstraat 48A',
          'postal_code': '9688',
          'city': 'Maarkedal',
          'country_code': 'BE',
        });
        expect(
          parsed.line1,
          'Koekamerstraat 48A',
          reason: 'street key "$key" was dropped',
        );
      }
      // `line1` still wins when several are present.
      expect(
        parseCompanyCustomerAddress(<String, dynamic>{
          'type': 'home',
          'line1': 'Koekamerstraat 48A',
          'street': 'Andere straat 1',
        }).line1,
        'Koekamerstraat 48A',
      );
    });

    test('an address with a street beats a bare locality of the same type', () {
      const bareLocality = CompanyCustomerAddress(
        type: 'home',
        label: 'Thuis',
        postalCode: '9688',
        city: 'Maarkedal',
        countryCode: 'BE',
      );
      // Bare one first: the full address must still win.
      final chosen = companyCustomerPreferredAddress(
        _customerWith(const <CompanyCustomerAddress>[bareLocality, _saved]),
      );
      expect(chosen?.line1, 'Koekamerstraat 48A');

      final pickup = _field('pickup');
      final dropoff = _field('dropoff');
      addTearDown(pickup.dispose);
      addTearDown(dropoff.dispose);
      companyApplyCustomerGroundAddress(
        customer: _customerWith(
          const <CompanyCustomerAddress>[bareLocality, _saved],
        ),
        options: const CompanyRideOptions(),
        pickup: pickup,
        dropoff: dropoff,
      );
      expect(pickup.textController.text, contains('Koekamerstraat 48A'));
    });

    test('label and coordinates stay together when applied', () {
      const withCoords = CompanyCustomerAddress(
        type: 'home',
        line1: 'Koekamerstraat 48A',
        postalCode: '9688',
        city: 'Maarkedal',
        countryCode: 'BE',
        lat: 50.7964,
        lon: 3.6572,
      );
      final value = companyAddressValueFromSaved(withCoords);
      expect(value.displayText, contains('Koekamerstraat 48A'));
      expect(value.lat, 50.7964);
      expect(value.lon, 3.6572);
      expect(value.acceptance, LimousineAddressAcceptance.selected);

      const moved = CompanyCustomerAddress(
        type: 'home',
        line1: 'Korenmarkt 1',
        postalCode: '9000',
        city: 'Gent',
        countryCode: 'BE',
        lat: 51.0543,
        lon: 3.7174,
      );
      final next = companyAddressValueFromSaved(moved);
      expect(next.displayText, contains('Korenmarkt 1'));
      expect(next.lat, 51.0543);
      expect(next.lon, 3.7174);
      expect(next.lat, isNot(value.lat));
    });

    test('a billing-only address is still used when nothing better exists', () {
      const billing = CompanyCustomerAddress(
        type: 'billing',
        line1: 'Factuurstraat 2',
        postalCode: '9000',
        city: 'Gent',
        countryCode: 'BE',
      );
      expect(
        companyCustomerPreferredAddress(
          _customerWith(const <CompanyCustomerAddress>[billing]),
        )?.line1,
        'Factuurstraat 2',
      );
    });
  });
}
