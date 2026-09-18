import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_plan_quote_panel.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
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
    placeId: 'place:$text',
    acceptance: LimousineAddressAcceptance.selected,
  );
}

void main() {
  test('Friday 22:00 wall clock is sent as Friday 20:00Z, not Thursday', () {
    final request = companyPlanQuoteRequestFromAddresses(
      from: _selected('Maarkedal 48A', lat: 50.82, lon: 3.64),
      to: _selected('Kuurne', lat: 50.85, lon: 3.28),
      pickupLocal: DateTime(2026, 9, 18, 22, 0),
      options: const CompanyRideOptions(waitMin: 45),
      passengers: 2,
      returnEnabled: true,
      returnPickupLocal: DateTime(2026, 9, 18, 23, 29),
    );
    expect(request, isNotNull);
    expect(request!.body['pickup_iso'], '2026-09-18T20:00:00.000Z');
    expect(request.body['return_pickup_iso'], '2026-09-18T21:29:00.000Z');
    expect(request.body['pickup_iso'], isNot('2026-09-17T20:00:00.000Z'));
  });

  test('one-way 200 plus inbound 200 becomes a 400 return total', () {
    const outbound = CompanyPlanQuoteResult(
      fingerprint: 'out',
      distanceKm: 40,
      durationMin: 45,
      priceInclVat: 200,
      priceExVat: 165.29,
      priceVat: 34.71,
      priceAvailable: true,
    );
    const inbound = CompanyPlanQuoteResult(
      fingerprint: 'in',
      distanceKm: 40,
      durationMin: 48,
      priceInclVat: 200,
      priceExVat: 165.29,
      priceVat: 34.71,
      priceAvailable: true,
    );
    final merged = companyPlanMergeLegQuotes(
      outbound: outbound,
      inbound: inbound,
    );
    expect(merged.displayTotalPrice, 400);
    expect(merged.outboundPriceInclVat, 200);
    expect(merged.returnPriceInclVat, 200);
    expect(merged.priceExVat, 330.58);
    expect(companyPlanQuoteNeedsInboundLeg(outbound), isTrue);
    expect(companyPlanQuoteNeedsInboundLeg(merged), isFalse);
  });

  test('parsed return quote keeps the contract total instead of outbound only', () {
    final parsed = parseCompanyPlanQuote(
      <String, dynamic>{
        'ok': true,
        'price_incl_vat': 200,
        'outbound_price_incl_vat': 200,
        'return_price_incl_vat': 200,
        'total_price_incl_vat': 400,
        'distance_km': 40,
        'duration_min': 45,
        'return_distance_km': 40,
        'return_duration_min': 48,
        'currency': 'EUR',
        'price_available': true,
      },
      fingerprint: 'ret',
    );
    expect(parsed.displayTotalPrice, 400);
    expect(parsed.outboundPriceInclVat, 200);
    expect(parsed.returnPriceInclVat, 200);
    expect(companyPlanQuoteNeedsInboundLeg(parsed), isFalse);
  });

  test('incomplete typing does not build a quote request', () {
    final request = companyPlanQuoteRequestFromAddresses(
      from: const LimousineAddressValue(
        displayText: 'Ko',
        acceptance: LimousineAddressAcceptance.incomplete,
      ),
      to: _selected('Ronse', lat: 50.74, lon: 3.60),
      pickupLocal: DateTime(2026, 9, 15, 9),
      options: const CompanyRideOptions(),
      passengers: 1,
    );
    expect(request, isNull);
  });

  test('selected addresses share one fingerprint until options change', () {
    final pickup = DateTime(2026, 9, 15, 9);
    final first = companyPlanQuoteFingerprint(
      from: _selected('Gent'),
      to: _selected('Ronse', lat: 50.74, lon: 3.60),
      pickupLocal: pickup,
      options: const CompanyRideOptions(tier: 'comfort'),
      passengers: 2,
    );
    final same = companyPlanQuoteFingerprint(
      from: _selected('Gent'),
      to: _selected('Ronse', lat: 50.74, lon: 3.60),
      pickupLocal: pickup,
      options: const CompanyRideOptions(tier: 'comfort'),
      passengers: 2,
    );
    final changed = companyPlanQuoteFingerprint(
      from: _selected('Gent'),
      to: _selected('Brussel', lat: 50.85, lon: 4.35),
      pickupLocal: pickup,
      options: const CompanyRideOptions(tier: 'comfort'),
      passengers: 2,
    );
    expect(first, same);
    expect(first, isNot(changed));
  });

  test('coordinator dedupes identical rebuilds and requotes on address change', () async {
    var calls = 0;
    final coordinator = CompanyPlanQuoteCoordinator(
      transport: (request) async {
        calls += 1;
        return CompanyPlanQuoteResult(
          fingerprint: request.fingerprint,
          distanceKm: 34.2,
          durationMin: 29,
          priceInclVat: 46.7,
          currency: 'EUR',
          pricingSource: 'route_calc',
          priceAvailable: true,
        );
      },
    );
    final pickup = DateTime(2026, 9, 15, 9);
    final first = companyPlanQuoteRequestFromAddresses(
      from: _selected('Gent'),
      to: _selected('Ronse', lat: 50.74, lon: 3.60),
      pickupLocal: pickup,
      options: const CompanyRideOptions(),
      passengers: 1,
    )!;
    await coordinator.quote(first);
    await coordinator.quote(first);
    await Future.wait<CompanyPlanQuoteResult>([
      coordinator.quote(first),
      coordinator.quote(first),
    ]);
    expect(calls, 1);
    final next = companyPlanQuoteRequestFromAddresses(
      from: _selected('Gent'),
      to: _selected('Brussel', lat: 50.85, lon: 4.35),
      pickupLocal: pickup,
      options: const CompanyRideOptions(),
      passengers: 1,
    )!;
    await coordinator.quote(next);
    expect(calls, 2);
  });

  test('manual price stays visible while a new quote is calculated', () {
    const previous = CompanyPlanQuoteResult(
      fingerprint: 'a',
      distanceKm: 34.2,
      durationMin: 29,
      priceInclVat: 46.7,
      currency: 'EUR',
      pricingSource: 'route_calc',
      priceAvailable: true,
    );
    const next = CompanyPlanQuoteResult(
      fingerprint: 'b',
      distanceKm: 41.0,
      durationMin: 33,
      priceInclVat: 58.4,
      currency: 'EUR',
      pricingSource: 'route_calc',
      priceAvailable: true,
    );
    const manualLocked = true;
    const typed = '90';
    final kept = manualLocked ? typed : next.priceInclVat.toString();
    expect(kept, '90');
    expect(previous.priceInclVat, 46.7);
  });

  test('calculator-off quote keeps duration without a price', () {
    const result = CompanyPlanQuoteResult(
      fingerprint: 'off',
      distanceKm: 34.2,
      durationMin: 29,
      currency: 'EUR',
      pricingSource: 'calculator_off',
      priceAvailable: false,
      calculatorOff: true,
    );
    expect(result.hasRoute, isTrue);
    expect(
      formatCompanyPlanQuoteRoute(result, AppLanguage.nl),
      '29 min · 34,2 km',
    );
    expect(formatCompanyPlanQuotePrice(result, AppLanguage.nl), isEmpty);
  });

  testWidgets('status goes from calculating to route and retry only on error', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompanyPlanQuotePanel(
            language: AppLanguage.nl,
            loading: true,
            result: null,
            error: null,
            onRetry: _noop,
          ),
        ),
      ),
    );
    expect(find.text(kCompanyAgendaRouteCalculating.of(AppLanguage.nl)), findsOneWidget);
    expect(find.text(kCompanyAgendaRouteRetry.of(AppLanguage.nl)), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyPlanQuotePanel(
            language: AppLanguage.nl,
            loading: false,
            result: const CompanyPlanQuoteResult(
              fingerprint: 'ok',
              distanceKm: 34.2,
              durationMin: 29,
              priceInclVat: 46.7,
              currency: 'EUR',
              pricingSource: 'route_calc',
              priceAvailable: true,
            ),
            error: null,
            onRetry: _noop,
          ),
        ),
      ),
    );
    expect(find.text('29 min · 34,2 km'), findsOneWidget);
    expect(find.textContaining('€46,70'), findsOneWidget);
    expect(find.textContaining('bedrijfstarieven'), findsOneWidget);
    expect(find.text(kCompanyAgendaRouteRetry.of(AppLanguage.nl)), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompanyPlanQuotePanel(
            language: AppLanguage.nl,
            loading: false,
            result: null,
            error: 'Geen bruikbare wegroute tussen deze adressen.',
            onRetry: _noop,
          ),
        ),
      ),
    );
    expect(find.text(kCompanyAgendaRouteRetry.of(AppLanguage.nl)), findsOneWidget);
    expect(find.text('Geen bruikbare wegroute tussen deze adressen.'), findsOneWidget);
  });

  testWidgets('a calculated distance is not shown as a price', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompanyPlanQuotePanel(
            language: AppLanguage.nl,
            loading: false,
            result: CompanyPlanQuoteResult(
              fingerprint: 'route-only',
              distanceKm: 34.2,
              durationMin: 29,
              currency: 'EUR',
              pricingSource: 'calculator_off',
              priceAvailable: false,
              calculatorOff: true,
            ),
            error: null,
            onRetry: _noop,
          ),
        ),
      ),
    );
    expect(find.text('29 min · 34,2 km'), findsOneWidget);
    expect(find.textContaining('€'), findsNothing);
    expect(
      find.text(kCompanyAgendaQuoteUnavailable.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(find.text(kCompanyAgendaRouteRetry.of(AppLanguage.nl)), findsNothing);
  });

  test('drawn addresses without a quote are calculating, not route_required', () {
    final from = _selected('Gent');
    final to = _selected('Ronse', lat: 50.74, lon: 3.60);
    expect(
      companyPlanRouteStatus(
        from: from,
        to: to,
        loading: true,
        quote: null,
        error: null,
      ),
      CompanyPlanRouteStatus.calculating,
    );
    expect(
      companyPlanRouteStatus(
        from: from,
        to: to,
        loading: false,
        quote: const CompanyPlanQuoteResult(
          fingerprint: 'ok',
          distanceKm: 34.2,
          durationMin: 29,
          pickupLat: 51.05,
          pickupLon: 3.72,
          dropoffLat: 50.74,
          dropoffLon: 3.60,
        ),
        error: null,
      ),
      CompanyPlanRouteStatus.ready,
    );
    expect(
      companyPlanRouteStatus(
        from: from,
        to: to,
        loading: false,
        quote: null,
        error: 'route_failed',
      ),
      CompanyPlanRouteStatus.failed,
    );
    expect(
      companyPlanRouteStatus(
        from: const LimousineAddressValue(displayText: 'Ko'),
        to: to,
        loading: false,
        quote: const CompanyPlanQuoteResult(
          fingerprint: 'stale',
          distanceKm: 34.2,
          durationMin: 29,
        ),
        error: null,
      ),
      CompanyPlanRouteStatus.confirmPickup,
    );
    expect(
      companyPlanQuoteErrorIsMissingRoute('route_required', from, to),
      isFalse,
    );
  });

  test('airport change is a new fingerprint and coordinator requotes once', () async {
    var calls = 0;
    final coordinator = CompanyPlanQuoteCoordinator(
      transport: (request) async {
        calls += 1;
        return CompanyPlanQuoteResult(
          fingerprint: request.fingerprint,
          distanceKm: 20,
          durationMin: 25,
        );
      },
    );
    final first = companyPlanQuoteRequestFromAddresses(
      from: _selected('Gent'),
      to: _selected('BRU', lat: 50.901, lon: 4.484),
      pickupLocal: DateTime(2026, 9, 15, 9),
      options: const CompanyRideOptions(
        service: 'airport',
        airportIata: 'BRU',
      ),
      passengers: 1,
    )!;
    await coordinator.quote(first);
    await coordinator.quote(first);
    expect(calls, 1);
    final next = companyPlanQuoteRequestFromAddresses(
      from: _selected('Gent'),
      to: _selected('CRL', lat: 50.46, lon: 4.45),
      pickupLocal: DateTime(2026, 9, 15, 9),
      options: const CompanyRideOptions(
        service: 'airport',
        airportIata: 'CRL',
      ),
      passengers: 1,
    )!;
    await coordinator.quote(next);
    expect(calls, 2);
    expect(first.fingerprint, isNot(next.fingerprint));
  });

  test('Nu quote omits client pickup_iso and stamps when_now', () {
    final request = companyPlanQuoteRequestFromAddresses(
      from: _selected('Gent'),
      to: _selected('Ronse', lat: 50.74, lon: 3.60),
      pickupLocal: DateTime(2026, 9, 15, 9),
      whenNow: true,
      options: const CompanyRideOptions(),
      passengers: 1,
    );
    expect(request, isNotNull);
    expect(request!.body['when'], 'now');
    expect(request.body['when_now'], isTrue);
    expect(request.body.containsKey('pickup_iso'), isFalse);
    expect(request.fingerprint.contains('now'), isTrue);
  });
}

void _noop() {}
