import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_addresses.dart';
import 'package:fluxidi_tracking/customer_profile/customer_profile_address_editor.dart';
import 'package:fluxidi_tracking/customer_profile/customer_stored_address.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

CustomerProfile _profile({
  CustomerStoredAddress homeAddress = CustomerStoredAddress.empty,
  String billingStreet = 'Factuurstraat 1',
  String billingPostalCode = '1000',
  String billingCity = 'Brussel',
  String billingCountry = 'BE',
}) {
  return CustomerProfile(
    customerId: 'cus_1',
    name: 'Christophe',
    phone: '+32470000001',
    email: 'c@example.com',
    preferredPostcode: '9688',
    companyName: '',
    vatNumber: '',
    billingStreet: billingStreet,
    billingPostalCode: billingPostalCode,
    billingCity: billingCity,
    billingCountry: billingCountry,
    homeAddress: homeAddress,
    createdAt: '2026-01-01',
    updatedAt: '2026-01-01',
  );
}

const _koekamer48a = CustomerStoredAddress(
  street: 'Koekamerstraat',
  houseNumber: '48',
  houseAddition: 'A',
  bus: '2',
  postalCode: '9688',
  locality: 'Schorisse',
  country: 'BE',
  lat: 50.77205,
  lon: 3.66942,
  placeId: 'address.koekamer-48a',
  placeType: 'address',
);

void main() {
  test('parses house addition and bus from a full label', () {
    final parsed = customerStoredAddressFromLabel(
      'Koekamerstraat 48A bus 2, 9688 Schorisse, België',
    );
    expect(parsed.street, 'Koekamerstraat');
    expect(parsed.houseNumber, '48');
    expect(parsed.houseAddition, 'A');
    expect(parsed.bus, '2');
    expect(parsed.postalCode, '9688');
    expect(parsed.locality, 'Schorisse');
    expect(parsed.displayLabel, contains('48A'));
    expect(parsed.displayLabel, contains('bus 2'));
  });

  test('json roundtrip keeps house addition, bus and coordinates', () {
    final restored = CustomerStoredAddress.fromJson(_koekamer48a.toJson());
    expect(restored.houseNumber, '48');
    expect(restored.houseAddition, 'A');
    expect(restored.bus, '2');
    expect(restored.postalCode, '9688');
    expect(restored.locality, 'Schorisse');
    expect(restored.lat, 50.77205);
    expect(restored.lon, 3.66942);
    expect(restored.displayLabel, contains('48A'));
    expect(restored.displayLabel, isNot(contains('50')));
  });

  test('bus-only change keeps the building coordinates', () {
    final next = customerStoredAddressApplyManualParts(
      current: _koekamer48a,
      bus: '4',
    );
    expect(next.bus, '4');
    expect(next.houseNumber, '48');
    expect(next.houseAddition, 'A');
    expect(next.hasValidCoordinates, isTrue);
    expect(next.positionNeedsConfirm, isFalse);
    expect(next.lat, 50.77205);
  });

  test('house or postcode change clears stale coordinates', () {
    final next = customerStoredAddressApplyManualParts(
      current: _koekamer48a,
      houseNumber: '50',
    );
    expect(next.houseNumber, '50');
    expect(next.hasValidCoordinates, isFalse);
    expect(next.positionNeedsConfirm, isTrue);
  });

  test('keeps deelgemeente when provider returns the parent city', () {
    final next = customerStoredAddressFromSuggestion(
      const LimousinePlaceSuggestion(
        label: 'Koekamerstraat 48, 9688 Maarkedal, België',
        lat: 50.77205,
        lon: 3.66942,
        placeId: 'address.koekamer-48',
        placeType: 'address',
        postcode: '9688',
        locality: 'Maarkedal',
        country: 'BE',
      ),
      keepManual: const CustomerStoredAddress(
        houseNumber: '48',
        houseAddition: 'A',
        bus: '2',
        locality: 'Schorisse',
      ),
    );
    expect(next.houseNumber, '48');
    expect(next.houseAddition, 'A');
    expect(next.bus, '2');
    expect(next.locality, 'Schorisse');
    expect(next.postalCode, '9688');
    expect(next.displayLabel, isNot(contains('Ronse')));
  });

  test('keeps typed 48A when the provider only knows house 48', () {
    final next = customerStoredAddressFromSuggestion(
      const LimousinePlaceSuggestion(
        label: 'Koekamerstraat 48, 9688 Maarkedal, België',
        lat: 50.77205,
        lon: 3.66942,
        placeId: 'address.koekamer-48',
        placeType: 'address',
        postcode: '9688',
        locality: 'Maarkedal',
        country: 'BE',
      ),
      keepManual: customerStoredAddressFromLabel(
        'Koekamerstraat 48A, 9688 Schorisse, België',
      ),
    );
    expect(next.houseNumber, '48');
    expect(next.houseAddition, 'A');
    expect(next.locality, 'Schorisse');
    expect(next.displayLabel, contains('48A'));
    expect(next.displayLabel, isNot(contains('Ronse')));
  });

  test('street-level result without a house number needs confirmation', () {
    final next = customerStoredAddressFromSuggestion(
      const LimousinePlaceSuggestion(
        label: 'Koekamerstraat, 9688 Maarkedal, België',
        lat: 50.7721,
        lon: 3.6695,
        placeId: 'street.koekamer',
        placeType: 'street',
        postcode: '9688',
        locality: 'Maarkedal',
        country: 'BE',
      ),
    );
    expect(next.houseNumber, isEmpty);
    expect(next.positionNeedsConfirm, isTrue);
  });

  test('Mijn adres uses home, not the billing address', () {
    final billingOnly = _profile();
    expect(customerProfileDefaultAddressLine(billingOnly), isEmpty);
    expect(customerBookingAddressFromProfile(billingOnly), isNull);

    final withHome = _profile(homeAddress: _koekamer48a);
    expect(
      composeCustomerStoredAddressLabel(_koekamer48a, language: 'nl'),
      'Koekamerstraat 48A bus 2, 9688 Schorisse, België',
    );
    expect(
      customerProfileDefaultAddressLine(withHome),
      composeCustomerStoredAddressLabel(_koekamer48a),
    );
    expect(customerProfileBillingAddressLine(withHome), contains('Factuurstraat'));
    final pickup = customerBookingAddressFromProfile(withHome)!;
    expect(pickup.displayText, contains('Koekamerstraat 48A'));
    expect(pickup.lat, 50.77205);
    expect(pickup.lon, 3.66942);
    expect(customerProfileAddressNeedsMapConfirm(withHome), isFalse);
  });

  test('text-only home keeps the label and asks for a map check', () {
    final profile = _profile(
      homeAddress: customerStoredAddressFromLabel(
        'Koekamerstraat 48A, 9688 Schorisse, België',
      ),
    );
    expect(profile.homeAddress.hasValidCoordinates, isFalse);
    expect(customerProfileAddressNeedsMapConfirm(profile), isTrue);
    final pickup = customerBookingAddressFromProfile(profile)!;
    expect(pickup.displayText, contains('48A'));
    expect(pickup.hasCoordinates, isFalse);
  });

  test('profile json keeps home address and billing separately', () {
    final profile = _profile(homeAddress: _koekamer48a);
    final restored = CustomerProfile.fromJson(profile.toJson());
    expect(restored.homeAddress.houseAddition, 'A');
    expect(restored.homeAddress.bus, '2');
    expect(restored.homeAddress.lat, 50.77205);
    expect(restored.billingStreet, 'Factuurstraat 1');
    expect(restored.homeAddress.street, 'Koekamerstraat');
  });

  test('server payload does not claim a home address the worker cannot store', () {
    final payload = buildPublicCustomerProfilePayload(
      profile: _profile(homeAddress: _koekamer48a),
      intent: CustomerProfileSyncIntent.explicitProfileSave,
    );
    expect(payload.containsKey('home_address'), isFalse);
    expect(payload.containsKey('homeAddress'), isFalse);
    expect(payload['billing_street'], 'Factuurstraat 1');
  });

  test('backend profile without home_address does not wipe a local home', () {
    final local = _profile(homeAddress: _koekamer48a);
    final backend = CustomerProfile.fromJson(<String, dynamic>{
      'customerId': 'cus_1',
      'name': 'Christophe',
      'phone': '+32470000001',
      'email': 'c@example.com',
      'preferredPostcode': '9688',
      'companyName': '',
      'vatNumber': '',
      'billingStreet': 'Factuurstraat 1',
      'createdAt': '2026-01-01',
      'updatedAt': '2026-01-02',
    });
    expect(backend.homeAddress.isEmpty, isTrue);
    final kept = backend.homeAddress.isEmpty
        ? local.homeAddress
        : backend.homeAddress;
    expect(kept.houseNumber, '48');
    expect(kept.houseAddition, 'A');
    expect(kept.bus, '2');
    expect(kept.lat, 50.77205);
  });

  test('stale lookup responses do not replace newer typed input', () async {
    final later = Completer<LimousinePlaceLookupResult>();
    var searches = 0;
    final controller = LimousineAddressFieldController(
      lookup: LimousinePlaceLookup(
        searchOverride: (query, language) async {
          searches += 1;
          final q = query.toLowerCase();
          if (q.contains('48a')) {
            return const LimousinePlaceLookupResult(
              suggestions: <LimousinePlaceSuggestion>[
                LimousinePlaceSuggestion(
                  label: 'Koekamerstraat 48A, 9688 Schorisse, België',
                  lat: 50.77205,
                  lon: 3.66942,
                  placeType: 'address',
                  postcode: '9688',
                  locality: 'Schorisse',
                ),
              ],
            );
          }
          if (q.contains('koekamerstraat 48')) {
            return later.future;
          }
          return const LimousinePlaceLookupResult(
            suggestions: <LimousinePlaceSuggestion>[
              LimousinePlaceSuggestion(
                label: 'Koekamerstraat 50, 9600 Ronse, België',
                lat: 50.74,
                lon: 3.60,
                placeType: 'address',
                postcode: '9600',
                locality: 'Ronse',
              ),
            ],
          );
        },
      ),
      fieldId: 'stale',
      debounce: Duration.zero,
    );
    controller.searchContextCountry = () => 'be';
    controller.textController.text = 'koekamerstraat 48';
    controller.onTextChanged('koekamerstraat 48');
    await Future<void>.delayed(Duration.zero);
    controller.textController.text = 'koekamerstraat 48A, 9688 Schorisse';
    controller.onTextChanged('koekamerstraat 48A, 9688 Schorisse');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    later.complete(
      const LimousinePlaceLookupResult(
        suggestions: <LimousinePlaceSuggestion>[
          LimousinePlaceSuggestion(
            label: 'Koekamerstraat 48, 9688 Maarkedal, België',
            lat: 50.77,
            lon: 3.66,
            placeType: 'address',
            postcode: '9688',
            locality: 'Maarkedal',
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.textController.text, contains('48A'));
    expect(
      controller.suggestions.map((item) => item.label).join(),
      isNot(contains('Ronse')),
    );
    expect(searches, greaterThanOrEqualTo(1));
    controller.dispose();
  });

  testWidgets('address editor fills parts from a mocked suggestion', (
    tester,
  ) async {
    CustomerStoredAddress? captured;
    final lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async {
        return const LimousinePlaceLookupResult(
          suggestions: <LimousinePlaceSuggestion>[
            LimousinePlaceSuggestion(
              label: 'Koekamerstraat 48A, 9688 Schorisse, België',
              lat: 50.77205,
              lon: 3.66942,
              placeId: 'address.koekamer-48a',
              placeType: 'address',
              postcode: '9688',
              locality: 'Schorisse',
              country: 'BE',
            ),
          ],
        );
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerProfileAddressEditor(
            fieldId: 'home',
            palette: paletteForCustomerTheme(CustomerThemeVariant.premiumLight),
            language: AppLanguage.nl,
            value: CustomerStoredAddress.empty,
            lookup: lookup,
            requireExactHouse: true,
            contextCountry: 'BE',
            contextPostalCode: '9688',
            onChanged: (next) => captured = next,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('customer_profile_home_input')),
      'koek',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Koekamerstraat 48A'), findsWidgets);
    await tester.tap(
      find.byKey(limousineAddressSuggestionKey('home', 0)),
    );
    await tester.pump();
    expect(captured, isNotNull);
    expect(captured!.houseNumber, '48');
    expect(captured!.houseAddition, 'A');
    expect(captured!.postalCode, '9688');
    expect(captured!.locality, 'Schorisse');
    expect(captured!.lat, 50.77205);
  });
}
