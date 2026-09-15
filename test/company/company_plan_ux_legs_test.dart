import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_address_field.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_booking_route_coords.dart';
import 'package:fluxidi_tracking/company/company_crew_combo.dart';
import 'package:fluxidi_tracking/company/company_plan_presence.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_plan_ride_form.dart';
import 'package:fluxidi_tracking/company/company_plan_route_map.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/company/company_plan_waypoints.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/company/company_roundtrip.dart';
import 'package:fluxidi_tracking/company/company_roundtrip_fields.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

LimousineAddressValue _selected(
  String text, {
  double lat = 51.05,
  double lon = 3.72,
}) {
  return LimousineAddressValue(
    displayText: text,
    canonicalLabel: text,
    lat: lat,
    lon: lon,
    acceptance: LimousineAddressAcceptance.selected,
  );
}

void main() {
  test('1 single A to B quote request stays one-way', () {
    final request = companyPlanQuoteRequestFromAddresses(
      from: _selected('A', lat: 50.8, lon: 3.2),
      to: _selected('B', lat: 50.9, lon: 4.4),
      pickupLocal: DateTime(2026, 9, 20, 11),
      options: const CompanyRideOptions(),
      passengers: 2,
    );
    expect(request, isNotNull);
    expect(request!.body['return_enabled'], isFalse);
    expect(request.body['from'], 'A');
    expect(request.body['to'], 'B');
  });

  test('2 later single ride keeps pickup_iso and no now stamp', () {
    final request = companyPlanQuoteRequestFromAddresses(
      from: _selected('A'),
      to: _selected('B', lat: 50.74, lon: 3.60),
      pickupLocal: DateTime(2026, 9, 20, 14, 30),
      whenNow: false,
      options: const CompanyRideOptions(),
      passengers: 1,
    );
    expect(request!.body['pickup_iso'], isNotNull);
    expect(request.body['when_now'], isNot(true));
  });

  test('3 waiting return quotes reverse route without a typed duration', () {
    final request = companyPlanQuoteRequestFromAddresses(
      from: _selected('A'),
      to: _selected('B', lat: 50.74, lon: 3.60),
      pickupLocal: DateTime(2026, 9, 20, 11),
      whenNow: true,
      options: const CompanyRideOptions(waitMin: 45),
      passengers: 2,
      returnEnabled: true,
      returnFrom: _selected('B', lat: 50.74, lon: 3.60),
      returnTo: _selected('A'),
      returnPickupLocal: DateTime(2026, 9, 20, 12, 30),
    );
    expect(request, isNotNull);
    expect(request!.body['return_enabled'], isTrue);
    expect(request.body['return_from'], 'B');
    expect(request.body['return_to'], 'A');
    expect(request.body.containsKey('return_duration_min'), isFalse);
    expect(
      companyPlanReturnDurationMin(
        choice: CompanyRoundtripChoice.continuousWait,
        outboundDurationMin: 40,
        quotedReturnDurationMin: 38,
      ),
      38,
    );
  });

  test('4 split A-B-A builds two legs and sums valid prices', () {
    const outbound = CompanyPlanQuoteResult(
      fingerprint: 'out',
      distanceKm: 40.6,
      durationMin: 41,
      priceInclVat: 81.7,
      currency: 'EUR',
      priceAvailable: true,
    );
    const inbound = CompanyPlanQuoteResult(
      fingerprint: 'in',
      distanceKm: 40.6,
      durationMin: 43,
      priceInclVat: 79.2,
      currency: 'EUR',
      priceAvailable: true,
    );
    final merged = companyPlanMergeLegQuotes(
      outbound: outbound,
      inbound: inbound,
    );
    expect(merged.hasRoute, isTrue);
    expect(merged.hasReturnRoute, isTrue);
    expect(merged.returnDurationMin, 43);
    expect(merged.displayTotalPrice, 160.9);
    expect(
      formatCompanyPlanQuoteLegLine(
        label: 'Heenrit',
        result: merged,
        inbound: false,
        language: AppLanguage.nl,
      ),
      contains('Heenrit'),
    );
    expect(
      formatCompanyPlanQuoteLegLine(
        label: 'Terugrit',
        result: merged,
        inbound: true,
        language: AppLanguage.nl,
      ),
      contains('Terugrit'),
    );
  });

  test('5 split return to C uses the changed return address', () {
    final request = companyPlanQuoteRequestFromAddresses(
      from: _selected('A'),
      to: _selected('B', lat: 50.74, lon: 3.60),
      pickupLocal: DateTime(2026, 9, 20, 11),
      options: const CompanyRideOptions(),
      passengers: 1,
      returnEnabled: true,
      returnFrom: _selected('B', lat: 50.74, lon: 3.60),
      returnTo: _selected('C', lat: 51.2, lon: 4.4),
      returnPickupLocal: DateTime(2026, 9, 20, 16),
    );
    expect(request!.body['return_from'], 'B');
    expect(request.body['return_to'], 'C');
  });

  test('6 waypoints stay numbered up to ten and enter the quote body', () {
    final stops = List<LimousineAddressValue>.generate(
      10,
      (index) => _selected('Stop ${index + 1}', lat: 51 + index / 100, lon: 3.7),
    );
    expect(stops.length, kCompanyPlanMaxStops);
    final request = companyPlanQuoteRequestFromAddresses(
      from: _selected('A'),
      to: _selected('B', lat: 50.74, lon: 3.60),
      pickupLocal: DateTime(2026, 9, 20, 11),
      options: const CompanyRideOptions(),
      passengers: 1,
      stops: stops,
    );
    expect((request!.body['stops'] as List).length, 10);
  });

  test('7 and 8 both return legs keep their own duration and summed price', () {
    const merged = CompanyPlanQuoteResult(
      fingerprint: 'both',
      distanceKm: 20,
      durationMin: 25,
      priceInclVat: 90,
      priceAvailable: true,
      returnDistanceKm: 22,
      returnDurationMin: 28,
      returnPriceInclVat: 40,
      outboundPriceInclVat: 50,
      totalPriceInclVat: 90,
    );
    expect(merged.hasReturnRoute, isTrue);
    expect(merged.displayTotalPrice, 90);
    expect(merged.returnDurationMin, 28);
  });

  test('9 chosen vehicle type applies to both crew combos', () {
    final combos = companyPlanCrewCombos(
      drivers: const [
        {
          'driver_id': 'drv_karel',
          'display_name': 'Karel Peeters',
          'is_active': true,
          'linked_vehicle_ids': ['vh_s', 'vh_van'],
        },
      ],
      vehicles: const [
        {
          'vehicle_id': 'vh_s',
          'vehicle_name': 'S-Klasse',
          'vehicle_type': 'sedan',
          'passenger_capacity': 3,
          'is_active': true,
        },
        {
          'vehicle_id': 'vh_van',
          'vehicle_name': 'V-Klasse',
          'vehicle_type': 'minivan',
          'passenger_capacity': 7,
          'is_active': true,
        },
      ],
      type: CompanyPlanVehicleType.sedan,
      passengers: 2,
    );
    expect(combos, hasLength(1));
    expect(combos.single.vehicleId, 'vh_s');
  });

  test('10 proposed driver is paired with a linked matching vehicle', () {
    final combos = companyPlanCrewCombos(
      drivers: const [
        {
          'driver_id': 'drv_karel',
          'display_name': 'Karel Peeters',
          'is_active': true,
          'linked_vehicle_ids': ['vh_s'],
        },
      ],
      vehicles: const [
        {
          'vehicle_id': 'vh_s',
          'vehicle_name': 'S-Klasse',
          'vehicle_type': 'sedan',
          'passenger_capacity': 3,
          'is_active': true,
        },
      ],
      type: CompanyPlanVehicleType.sedan,
      passengers: 1,
    );
    final proposed = proposeCompanyPlanCrewAssignment(
      combos: combos,
      userPicked: false,
      currentDriverId: '',
      currentVehicleId: '',
    );
    expect(proposed.driverId, 'drv_karel');
    expect(proposed.vehicleId, 'vh_s');
  });

  test('11 same combo is reused for return when available', () {
    final combos = companyPlanCrewCombos(
      drivers: const [
        {
          'driver_id': 'drv_karel',
          'display_name': 'Karel Peeters',
          'is_active': true,
          'linked_vehicle_ids': ['vh_s'],
        },
        {
          'driver_id': 'drv_amira',
          'display_name': 'Amira Benali',
          'is_active': true,
          'linked_vehicle_ids': ['vh_s2'],
        },
      ],
      vehicles: const [
        {
          'vehicle_id': 'vh_s',
          'vehicle_name': 'S-Klasse',
          'vehicle_type': 'sedan',
          'passenger_capacity': 3,
          'is_active': true,
        },
        {
          'vehicle_id': 'vh_s2',
          'vehicle_name': 'E-Klasse',
          'vehicle_type': 'sedan',
          'passenger_capacity': 3,
          'is_active': true,
        },
      ],
      type: CompanyPlanVehicleType.sedan,
      passengers: 1,
    );
    final same = proposeCompanyPlanReturnCrew(
      combos: combos,
      outboundDriverId: 'drv_karel',
      outboundVehicleId: 'vh_s',
      preferSame: true,
    );
    expect(same.driverId, 'drv_karel');
    expect(same.vehicleId, 'vh_s');
  });

  test('12 a different combo is proposed when the same one is unavailable', () {
    final combos = companyPlanCrewCombos(
      drivers: const [
        {
          'driver_id': 'drv_karel',
          'display_name': 'Karel Peeters',
          'is_active': true,
          'linked_vehicle_ids': ['vh_s'],
        },
        {
          'driver_id': 'drv_amira',
          'display_name': 'Amira Benali',
          'is_active': true,
          'linked_vehicle_ids': ['vh_s2'],
        },
      ],
      vehicles: const [
        {
          'vehicle_id': 'vh_s',
          'vehicle_name': 'S-Klasse',
          'vehicle_type': 'sedan',
          'passenger_capacity': 3,
          'is_active': true,
        },
        {
          'vehicle_id': 'vh_s2',
          'vehicle_name': 'E-Klasse',
          'vehicle_type': 'sedan',
          'passenger_capacity': 3,
          'is_active': true,
        },
      ],
      type: CompanyPlanVehicleType.sedan,
      passengers: 1,
    );
    final other = proposeCompanyPlanReturnCrew(
      combos: combos,
      outboundDriverId: 'drv_karel',
      outboundVehicleId: 'vh_s',
      preferSame: true,
      outboundAvailableForReturn: false,
    );
    expect(other.driverId, 'drv_amira');
    expect(other.vehicleId, 'vh_s2');
  });

  test('15 booking detail resolver prefers quote coords over empty booking', () {
    final resolved = resolveCompanyBookingRouteEndpoints(
      row: <String, dynamic>{
        'from': 'Koekamerstraat 48A, 9688 Schorisse',
        'to': 'Gent',
        'booking': <String, dynamic>{
          'from': 'Koekamerstraat 48A, 9688 Schorisse',
          'to': 'Gent',
        },
      },
      quote: const CompanyPlanQuoteResult(
        fingerprint: 'q',
        distanceKm: 40.6,
        durationMin: 41,
        pickupLat: 50.77,
        pickupLon: 3.62,
        dropoffLat: 51.05,
        dropoffLon: 3.72,
      ),
    );
    expect(resolved.hasCoordinates, isTrue);
    expect(resolved.pickup.acceptance, LimousineAddressAcceptance.selected);
    expect(resolved.canDrawRoute, isTrue);
    expect(resolved.missingReason, isEmpty);
  });

  test('15b text without coords becomes a compact restore, not incomplete', () {
    final resolved = resolveCompanyBookingRouteEndpoints(
      row: <String, dynamic>{
        'from': 'Koekamerstraat 48A',
        'to': 'Gent',
      },
    );
    expect(resolved.hasCoordinates, isFalse);
    expect(resolved.hasAddressText, isTrue);
    expect(resolved.pickup.acceptance, LimousineAddressAcceptance.manualFallback);
    expect(resolved.canDrawRoute, isFalse);
    expect(
      companyPlanRouteStatus(
        from: resolved.pickup,
        to: resolved.dropoff,
        loading: false,
        quote: const CompanyPlanQuoteResult(
          fingerprint: 'stale',
          distanceKm: 40,
          durationMin: 41,
        ),
      ),
      CompanyPlanRouteStatus.needsRestore,
    );
  });

  testWidgets('13 14 16 17 18 19 planner hides chips, duration field and vehicle dropdown', (
    tester,
  ) async {
    final lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async {
        return const LimousinePlaceLookupResult();
      },
    );
    addTearDown(lookup.dispose);
    final pickup = LimousineAddressFieldController(
      lookup: lookup,
      fieldId: 'from',
    );
    final dropoff = LimousineAddressFieldController(
      lookup: lookup,
      fieldId: 'to',
    );
    final returnTo = LimousineAddressFieldController(
      lookup: lookup,
      fieldId: 'return_to',
    );
    addTearDown(pickup.dispose);
    addTearDown(dropoff.dispose);
    addTearDown(returnTo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
              CompanyAddressField(
                controller: pickup,
                label: 'Vertrek',
                language: AppLanguage.nl,
                savedAddresses: const [
                  CompanyCustomerAddress(
                    label: 'Thuis',
                    line1: 'Koekamerstraat 48A',
                    city: 'Schorisse',
                    postalCode: '9688',
                    countryCode: 'BE',
                  ),
                ],
              ),
              CompanyRoundtripFields(
                language: AppLanguage.nl,
                choice: CompanyRoundtripChoice.splitNoWait,
                onChoiceChanged: (_) {},
                returnPickup: DateTime(2026, 9, 20, 16),
                onReturnPickupChanged: (_) {},
                returnTo: returnTo,
              ),
            ],
            ),
          ),
        ),
      ),
    );
    expect(find.text(kCompanySavedAddresses.of(AppLanguage.nl)), findsNothing);
    expect(find.text('Duur terugrit (minuten)'), findsNothing);
    expect(find.text('Vertrek terugrit'), findsNothing);
    expect(find.text(kCompanyRoundtripReturnToPlace.of(AppLanguage.nl)), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Scaffold(
            body: SizedBox(
              width: 390,
              height: 844,
              child: CompanyPlanRideForm(
                language: AppLanguage.nl,
                title: 'Rit plannen',
                audience: CompanyPlanAudience.customer,
                whenNow: true,
                onWhenNowChanged: (_) {},
                customer: null,
                customers: const [],
                onCustomerSelected: (_) {},
                onAddCustomer: () {},
                vehicleType: CompanyPlanVehicleType.sedan,
                airportMode: false,
                onVehicleTypeChanged: (_) {},
                onAirportModeChanged: (_) {},
                routeFields: const Text('route-slot'),
                whenLaterFields: const SizedBox.shrink(),
                passengers: 1,
                onPassengersChanged: (_) {},
                bags: 0,
                onBagsChanged: (_) {},
                quote: const Text('quote-slot'),
                proposedAssignment: const Text('driver-slot'),
                moreOptions: const [],
                primary: const Text('primary-slot'),
                secondary: const Text('secondary-slot'),
                map: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(kCompanyAgendaPlanCustomerFieldKey), findsNothing);
    expect(find.text('driver-slot'), findsNothing);
    expect(find.byKey(const Key('company_agenda_plan_vehicle')), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyPlanRideForm(
            language: AppLanguage.nl,
            title: 'Rit plannen',
            whenNow: false,
            onWhenNowChanged: (_) {},
            customer: null,
            customers: const [],
            onCustomerSelected: (_) {},
            onAddCustomer: () {},
            vehicleType: CompanyPlanVehicleType.sedan,
            airportMode: false,
            onVehicleTypeChanged: (_) {},
            onAirportModeChanged: (_) {},
            routeFields: const Text('route-slot'),
            whenLaterFields: const Text('heenrit-when'),
            returnWhenFields: const Text('retour-when'),
            waitFields: const Text('wait-slot'),
            roundtripChoiceFields: const Text('ritvorm-slot'),
            passengers: 1,
            onPassengersChanged: (_) {},
            bags: 0,
            onBagsChanged: (_) {},
            quote: const Text('quote-slot'),
            proposedAssignment: const Text('driver-slot'),
            moreOptions: const [],
            primary: const Text('primary-slot'),
            secondary: const Text('secondary-slot'),
            map: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    final later = tester.getTopLeft(find.text('heenrit-when')).dy;
    final retour = tester.getTopLeft(find.text('retour-when')).dy;
    final wait = tester.getTopLeft(find.text('wait-slot')).dy;
    final ritvorm = tester.getTopLeft(find.text('ritvorm-slot')).dy;
    final route = tester.getTopLeft(find.text('route-slot')).dy;
    expect(later < retour, isTrue);
    expect(retour < wait, isTrue);
    expect(wait < ritvorm, isTrue);
    expect(ritvorm < route, isTrue);
    expect(find.text('Gewoon vervoer'), findsOneWidget);
  });

  testWidgets('15 map with addresses and no coords stays compact', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompanyPlanRouteMap(
            language: AppLanguage.nl,
            pickup: LimousineAddressValue(
              displayText: 'Koekamerstraat 48A',
              canonicalLabel: 'Koekamerstraat 48A',
              acceptance: LimousineAddressAcceptance.manualFallback,
            ),
            dropoff: LimousineAddressValue(
              displayText: 'Gent',
              canonicalLabel: 'Gent',
              acceptance: LimousineAddressAcceptance.manualFallback,
            ),
            compactPlaceholder: true,
          ),
        ),
      ),
    );
    expect(find.text(kCompanyAgendaRouteRequired.of(AppLanguage.nl)), findsNothing);
    expect(find.text(kCompanyAgendaRestoreRoute.of(AppLanguage.nl)), findsOneWidget);
    expect(find.textContaining('Koekamerstraat'), findsWidgets);
  });

  test('20 later time sits under Nu/Later and wait is not a second Date/Time', () {
    expect(
      companyPlanQuoteSanityCheck(
        const CompanyPlanQuoteResult(
          fingerprint: 'gap',
          distanceKm: 36.5,
          durationMin: 36,
          priceInclVat: 252.3,
          priceAvailable: true,
          returnDistanceKm: 37.4,
          returnDurationMin: 37,
          outboundPriceInclVat: 181.8,
          returnPriceInclVat: 70.5,
          totalPriceInclVat: 252.3,
          breakdown: CompanyPlanQuoteBreakdown(waitingEx: 90),
        ),
      ).ok,
      isTrue,
    );
    expect(
      companyPlanQuoteSanityCheck(
        const CompanyPlanQuoteResult(
          fingerprint: 'bad',
          distanceKm: 36.5,
          durationMin: 36,
          priceInclVat: -4,
          priceAvailable: true,
        ),
      ).ok,
      isFalse,
    );
    expect(
      companyPlanQuoteDisplayedLegPrice(
        const CompanyPlanQuoteResult(
          fingerprint: 'wait',
          priceInclVat: 181.8,
          outboundPriceInclVat: 181.8,
          breakdown: CompanyPlanQuoteBreakdown(
            waitingEx: 90,
            vatRate: 0,
            vatMode: 'excl',
          ),
        ),
        inbound: false,
      ),
      closeTo(91.8, 0.01),
    );
    expect(
      companyPlanQuoteLineIncl(
        const CompanyPlanQuoteBreakdown(vatRate: 0.06, vatMode: 'excl'),
        40,
      ),
      closeTo(42.4, 0.01),
    );
  });

  test('overlap status is never Beschikbaar', () {
    const presence = CompanyPlanPresence(
      tone: CompanyPlanPresenceTone.blocked,
      code: 'assignment_overlap',
      icon: Icons.event_busy_outlined,
    );
    expect(
      companyPlanPresenceLabel(presence, AppLanguage.nl),
      kCompanyAgendaOverlapBlocked.of(AppLanguage.nl),
    );
    expect(
      companyPlanPresenceLabel(presence, AppLanguage.nl).contains('Beschikbaar'),
      isFalse,
    );
  });

  test('21 assignment race warning keeps the booking text exact', () {
    expect(
      companyPlanAssignmentRaceWarning(
        driverName: 'Karel Peeters',
        vehicleName: 'S-Klasse',
        reason: 'overlappende rit',
      ),
      'Rit bewaard, maar Karel Peeters · S-Klasse kon niet worden toegewezen wegens overlappende rit.',
    );
    expect(
      companyPlanAssignmentWarningReason('assignment_overlap'),
      'overlappende rit',
    );
  });
}
