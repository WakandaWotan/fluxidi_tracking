import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_supplement.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_form_date_time.dart';
import 'package:fluxidi_tracking/company/company_plan_airport_cards.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_plan_ride_form.dart';
import 'package:fluxidi_tracking/company/company_plan_ride_mode.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/company/company_trip_route.dart';
import 'package:fluxidi_tracking/company/company_trip_route_fields.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

void main() {
  test('each featured IATA maps to its own webp and the catalog record', () {
    const expected = <String, String>{
      'BRU': kCompanyPlanAirportCardBru,
      'CRL': kCompanyPlanAirportCardCrl,
      'ANR': kCompanyPlanAirportCardAnr,
      'OST': kCompanyPlanAirportCardOst,
      'LGG': kCompanyPlanAirportCardLgg,
      'KJK': kCompanyPlanAirportCardKjk,
    };
    for (final entry in expected.entries) {
      expect(companyPlanAirportCardAssetForIata(entry.key), entry.value);
      expect(companyPlanAirportCardAsset(entry.key), entry.value);
      expect(
        companyPlanAirportCatalogRecord(entry.key)?.iata,
        airportByIata(entry.key)?.iata,
      );
    }
    expect(kCompanyPlanFeaturedAirportIata, <String>[
      'BRU',
      'CRL',
      'ANR',
      'OST',
      'LGG',
      'KJK',
    ]);
  });

  test('missing IATA uses the generic airport-mode fallback', () {
    expect(companyPlanAirportCardAssetForIata('AMS'), isNull);
    expect(companyPlanAirportCardAsset('AMS'), kCompanyPlanAirportModeAsset);
    expect(companyPlanAirportCardAsset(''), kCompanyPlanAirportModeAsset);
    expect(companyPlanAirportCardAsset(null), kCompanyPlanAirportModeAsset);
  });

  test('canonical catalog remains the only coordinate source', () {
    final bru = airportByIata('BRU');
    expect(bru, isNotNull);
    expect(bru!.latitude, isNotNull);
    expect(companyPlanAirportCatalogRecord('BRU')?.iata, 'BRU');
    expect(
      companyPlanAirportCatalogRecord('BRU')?.latitude,
      airportByIata('BRU')?.latitude,
    );
    expect(airportByIata('KJK'), isNotNull);
    expect(companyPlanAirportCatalogRecord('KJK')?.iata, 'KJK');
    expect(
      companyPlanAirportCatalogRecord('KJK')?.latitude,
      kAirportCatalogKortrijkWevelgem.latitude,
    );
    expect(
      companyPlanAirportCatalogRecord('KJK')?.longitude,
      kAirportCatalogKortrijkWevelgem.longitude,
    );
    expect(
      companyPlanAirportCatalogRecord('KJK')?.preciseAddress,
      'Luchthavenstraat 1, 8560 Wevelgem, Belgium',
    );
    expect(
      publishedAirportCatalog().any(
        (airport) => airport.iata.trim().toUpperCase() == 'KJK',
      ),
      isTrue,
    );
    final cardsSource =
        File('lib/company/company_plan_airport_cards.dart').readAsStringSync();
    expect(cardsSource, isNot(contains('latitude')));
    expect(cardsSource, isNot(contains('4.484')));
    expect(cardsSource, isNot(contains('asset_manifest.json')));
  });

  test('to/from airport fills the matching route endpoint from the catalog', () {
    final airport = airportByIata('CRL')!;
    LimousineAddressValue? pickup;
    LimousineAddressValue? dropoff;
    companyTripApplyAirportEndpoint(
      kind: CompanyTripRouteKind.toAirport,
      airport: airport,
      applyPickup: (value) => pickup = value,
      applyDropoff: (value) => dropoff = value,
    );
    expect(pickup, isNull);
    expect(dropoff?.placeId, 'airport:CRL');
    expect(dropoff?.lat, airport.latitude);

    pickup = null;
    dropoff = null;
    companyTripApplyAirportEndpoint(
      kind: CompanyTripRouteKind.fromAirport,
      airport: airport,
      applyPickup: (value) => pickup = value,
      applyDropoff: (value) => dropoff = value,
    );
    expect(dropoff, isNull);
    expect(pickup?.placeId, 'airport:CRL');
  });

  test('airport ride stays a service mode and still needs a vehicle type', () {
    expect(parseCompanyPlanVehicleType('airport'), isNull);
    expect(parseCompanyPlanVehicleType('airport_ride'), isNull);
    expect(companyPlanRideModeIsAirport('airport_ride'), isTrue);
    final options = const CompanyRideOptions(
      service: 'airport',
      vehicleType: 'sedan',
    );
    expect(options.isAirport, isTrue);
    expect(options.vehicleType, 'sedan');
    expect(options.toJson()['vehicle_type'], 'sedan');
    expect(options.toJson()['service'], 'airport');
  });

  test('quotes stay on the existing fingerprint/calculator path', () {
    final first = companyPlanQuoteRequestFromAddresses(
      from: const LimousineAddressValue(
        displayText: 'Gent',
        canonicalLabel: 'Gent',
        lat: 51.05,
        lon: 3.72,
        placeId: 'place:gent',
        acceptance: LimousineAddressAcceptance.selected,
      ),
      to: const LimousineAddressValue(
        displayText: 'BRU',
        canonicalLabel: 'Brussels Airport (BRU)',
        lat: 50.90,
        lon: 4.48,
        placeId: 'airport:BRU',
        acceptance: LimousineAddressAcceptance.selected,
      ),
      pickupLocal: DateTime(2026, 9, 16, 9),
      options: const CompanyRideOptions(
        service: 'airport',
        vehicleType: 'sedan',
      ),
      passengers: 1,
    )!;
    final same = companyPlanQuoteRequestFromAddresses(
      from: const LimousineAddressValue(
        displayText: 'Gent',
        canonicalLabel: 'Gent',
        lat: 51.05,
        lon: 3.72,
        placeId: 'place:gent',
        acceptance: LimousineAddressAcceptance.selected,
      ),
      to: const LimousineAddressValue(
        displayText: 'BRU',
        canonicalLabel: 'Brussels Airport (BRU)',
        lat: 50.90,
        lon: 4.48,
        placeId: 'airport:BRU',
        acceptance: LimousineAddressAcceptance.selected,
      ),
      pickupLocal: DateTime(2026, 9, 16, 9),
      options: const CompanyRideOptions(
        service: 'airport',
        vehicleType: 'sedan',
      ),
      passengers: 1,
    )!;
    expect(first.fingerprint, same.fingerprint);
    expect(first.body.containsKey('price'), isFalse);
    expect(first.body.containsKey('duration_min'), isFalse);
    expect(first.body['distance_km'], isNull);
    final nowRequest = companyPlanQuoteRequestFromAddresses(
      from: const LimousineAddressValue(
        displayText: 'Gent',
        canonicalLabel: 'Gent',
        lat: 51.05,
        lon: 3.72,
        placeId: 'place:gent',
        acceptance: LimousineAddressAcceptance.selected,
      ),
      to: const LimousineAddressValue(
        displayText: 'BRU',
        canonicalLabel: 'Brussels Airport (BRU)',
        lat: 50.90,
        lon: 4.48,
        placeId: 'airport:BRU',
        acceptance: LimousineAddressAcceptance.selected,
      ),
      pickupLocal: DateTime(2026, 9, 16, 9),
      options: const CompanyRideOptions(
        service: 'airport',
        vehicleType: 'sedan',
      ),
      passengers: 1,
      whenNow: true,
    )!;
    expect(nowRequest.body['when'], 'now');
    expect(nowRequest.body.containsKey('pickup_iso'), isFalse);
  });

  test('pubspec bundles only the six app_webp airport cards', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/booking/airports/v1/'));
    expect(pubspec, isNot(contains('source_images')));
    expect(pubspec, isNot(contains('GENERATION_PROMPTS')));
    expect(pubspec, isNot(contains('preview/fluxidi_belgian')));
    expect(Directory('assets/booking/airports/source_images').existsSync(), isFalse);
    expect(Directory('assets/booking/airports/preview').existsSync(), isFalse);
    final files = Directory('assets/booking/airports/v1')
        .listSync()
        .whereType<File>()
        .toList();
    expect(files, hasLength(6));
    expect(files.every((file) => file.path.endsWith('.webp')), isTrue);
    final bytes = files.fold<int>(0, (sum, file) => sum + file.lengthSync());
    expect(bytes, 91780);
  });

  testWidgets('arrows and search selection reach every featured airport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var selected = 'BRU';
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return CompanyPlanAirportDestinationCards(
                  language: AppLanguage.nl,
                  selectedIata: selected,
                  onSelectedIata: (next) => setState(() => selected = next),
                  onSelectedOther: () => setState(() => selected = ''),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(kCompanyPlanAirportPrevKey), findsOneWidget);
    expect(find.byKey(kCompanyPlanAirportNextKey), findsOneWidget);
    Future<void> reveal(Key key) async {
      for (var i = 0; i < 8; i++) {
        final hit = find.byKey(key).hitTestable();
        if (tester.any(hit)) return;
        final next = find.byKey(kCompanyPlanAirportNextKey).hitTestable();
        if (tester.any(next)) {
          await tester.tap(next);
          await tester.pumpAndSettle();
        }
      }
    }

    for (final iata in kCompanyPlanFeaturedAirportIata) {
      final key = companyPlanAirportCardKey(iata);
      await reveal(key);
      await tester.tap(find.byKey(key).hitTestable());
      await tester.pumpAndSettle();
      expect(selected, iata);
    }
    await reveal(companyPlanAirportCardKey('other'));
    await tester.tap(find.byKey(companyPlanAirportCardKey('other')).hitTestable());
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
  });

  testWidgets('airport cards use cover inside a 16:9 clip', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyPlanAirportDestinationCards(
            language: AppLanguage.nl,
            selectedIata: 'BRU',
            onSelectedIata: (_) {},
            onSelectedOther: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(companyPlanAirportCardKey('BRU')), findsOneWidget);
    expect(find.byKey(companyPlanAirportCardKey('other')), findsOneWidget);
    expect(find.text('Andere luchthaven'), findsOneWidget);
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, isNotEmpty);
    for (final image in images) {
      expect(image.fit, BoxFit.cover);
      expect(image.fit, isNot(BoxFit.fill));
    }
    expect(find.byType(AspectRatio), findsWidgets);
  });

  testWidgets('cards stay inside phone, tablet and Windows sizes', (
    tester,
  ) async {
    for (final size in const <Size>[
      Size(390, 844),
      Size(800, 1280),
      Size(1100, 720),
      Size(1180, 820),
      Size(1524, 900),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: Scaffold(
              body: SizedBox(
                width: size.width,
                height: size.height,
                child: CompanyPlanAirportDestinationCards(
                  language: AppLanguage.nl,
                  selectedIata: '',
                  onSelectedIata: (_) {},
                  onSelectedOther: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Nu hides pickup date/time and Later shows them', (tester) async {
    var whenNow = true;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: CompanyPlanRideForm(
                language: AppLanguage.nl,
                title: 'Rit plannen',
                whenNow: whenNow,
                onWhenNowChanged: (next) => setState(() => whenNow = next),
                customer: null,
                customers: const <CompanyCustomerListItem>[],
                onCustomerSelected: (_) {},
                onAddCustomer: () {},
                vehicleType: CompanyPlanVehicleType.sedan,
                airportMode: true,
                onVehicleTypeChanged: (_) {},
                onAirportModeChanged: (_) {},
                routeFields: const SizedBox.shrink(),
                whenLaterFields: CompanyDateTimeFields(
                  fieldId: 'agenda_pickup',
                  language: AppLanguage.nl,
                  value: DateTime(2026, 9, 16, 9),
                  onChanged: (_) {},
                ),
                passengers: 1,
                onPassengersChanged: (_) {},
                bags: 0,
                onBagsChanged: (_) {},
                quote: const SizedBox.shrink(),
                proposedAssignment: const SizedBox.shrink(),
                moreOptions: const <Widget>[],
                primary: const SizedBox.shrink(),
                secondary: const SizedBox.shrink(),
                map: const SizedBox.shrink(),
              ),
            );
          },
        ),
      ),
    );
    expect(find.byKey(companyFormDateFieldKey('agenda_pickup')), findsNothing);
    expect(find.byKey(companyFormTimeFieldKey('agenda_pickup')), findsNothing);
    await tester.tap(find.byKey(kCompanyAgendaPlanWhenLaterKey));
    await tester.pumpAndSettle();
    expect(find.byKey(companyFormDateFieldKey('agenda_pickup')), findsOneWidget);
    expect(find.byKey(companyFormTimeFieldKey('agenda_pickup')), findsOneWidget);
  });

  testWidgets('featured and other airport cards fill or clear the catalog endpoint', (
    tester,
  ) async {
    final lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async {
        return const LimousinePlaceLookupResult(
          suggestions: <LimousinePlaceSuggestion>[],
        );
      },
    );
    final pickup = LimousineAddressFieldController(
      lookup: lookup,
      fieldId: 'from',
    );
    final dropoff = LimousineAddressFieldController(
      lookup: lookup,
      fieldId: 'to',
    );
    addTearDown(pickup.dispose);
    addTearDown(dropoff.dispose);
    var options = const CompanyRideOptions(
      service: 'airport',
      airportDirection: 'to_airport',
      vehicleType: 'sedan',
    );
    await tester.binding.setSurfaceSize(const Size(1100, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SingleChildScrollView(
                child: CompanyTripRouteFields(
                  language: AppLanguage.nl,
                  pickup: pickup,
                  dropoff: dropoff,
                  rideOptions: options,
                  onRideOptionsChanged: (next) => setState(() => options = next),
                  showAirportDestinationCards: true,
                  hideAddressKindChip: true,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Naar de luchthaven'), findsOneWidget);
    expect(find.text('Van de luchthaven'), findsOneWidget);
    await tester.tap(find.byKey(companyPlanAirportCardKey('BRU')));
    await tester.pumpAndSettle();
    expect(options.airportIata, 'BRU');
    expect(dropoff.value.placeId, 'airport:BRU');
    expect(find.byKey(kCompanyPlanAirportSummaryKey), findsOneWidget);
    expect(find.byKey(kCompanyAirportSearchFieldKey), findsNothing);
    expect(dropoff.value.lat, airportByIata('BRU')?.latitude);
    expect(pickup.value.placeId, isNot('airport:BRU'));

    await tester.tap(find.byKey(kCompanyTripRouteFromAirportKey));
    await tester.pumpAndSettle();
    expect(options.airportDirection, 'from_airport');
    expect(pickup.value.placeId, 'airport:BRU');
    expect(dropoff.value.placeId, isNot('airport:BRU'));

    await tester.ensureVisible(find.byKey(companyPlanAirportCardKey('KJK')));
    await tester.tap(find.byKey(companyPlanAirportCardKey('KJK')));
    await tester.pumpAndSettle();
    expect(options.airportIata, 'KJK');
    expect(pickup.value.placeId, 'airport:KJK');
    expect(pickup.value.lat, airportByIata('KJK')?.latitude);
    expect(pickup.value.lon, airportByIata('KJK')?.longitude);
    expect(find.byKey(kCompanyPlanAirportSummaryKey), findsOneWidget);
    expect(find.byKey(kCompanyAirportSearchFieldKey), findsNothing);

    await tester.ensureVisible(find.byKey(companyPlanAirportCardKey('other')));
    await tester.tap(find.byKey(companyPlanAirportCardKey('other')));
    await tester.pumpAndSettle();
    expect(options.airportIata, isEmpty);
    expect(find.text('Andere luchthaven'), findsOneWidget);
    expect(find.byKey(kCompanyAirportSearchFieldKey), findsOneWidget);
    expect(find.text('Zoek andere luchthaven'), findsOneWidget);
  });

  test('every featured airport card uses the same catalog record as search', () {
    for (final iata in kCompanyPlanFeaturedAirportIata) {
      final card = companyPlanAirportCatalogRecord(iata);
      final search = airportByIata(iata);
      expect(card, isNotNull, reason: iata);
      expect(search, isNotNull, reason: iata);
      expect(card!.iata, search!.iata);
      expect(card.latitude, search.latitude);
      expect(card.longitude, search.longitude);
      expect(card.preciseAddress, search.preciseAddress);
      expect(card.latitude, isNotNull, reason: iata);
      expect(card.longitude, isNotNull, reason: iata);
      final value = companyAirportAddressValue(card);
      expect(value.placeId, 'airport:$iata');
      expect(value.lat, card.latitude);
      expect(value.lon, card.longitude);
    }
  });
}
