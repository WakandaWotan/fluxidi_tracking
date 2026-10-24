import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_showroom_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_unified_intent.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_detail_page.dart';

Map<String, dynamic> _offerJson({
  required String presentation,
  Map<String, dynamic>? hourly,
  String id = 'off_1',
}) {
  return <String, dynamic>{
    'offer_id': id,
    'target_type': 'vehicle',
    'vehicle_id': 'veh_1',
    'price_presentation': presentation,
    'display_amount_cents': 25000,
    'currency': 'EUR',
    'title': <String, String>{'nl': 'Hummer Party', 'en': 'Hummer Party'},
    'journey_types': <String>['point_to_point', 'hourly_package'],
    if (hourly != null) 'hourly': hourly,
  };
}

LimousinePublishedOffer _offer({
  required String presentation,
  Map<String, dynamic>? hourly,
}) {
  return LimousinePublishedOffer.fromJson(
    _offerJson(presentation: presentation, hourly: hourly),
  );
}

LimousineShowroomVehicle _vehicle(LimousinePublishedOffer offer) {
  return LimousineShowroomVehicle(
    key: 'veh_1',
    vehicleId: 'veh_1',
    name: 'Party Limo',
    serviceClassId: 'party',
    passengerCapacity: 16,
    luggageCapacity: 4,
    photoUrls: const <String>[],
    offers: <LimousinePublishedOffer>[offer],
  );
}

Widget _app(Widget child) {
  return MaterialApp(home: child);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    appLanguageNotifier.value = AppLanguage.nl;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  test('CTA mapping stays Offerte/Boeking aanvragen for the five modes', () {
    expect(
      limousineShowroomCtaFor(_offer(presentation: 'quote_required')),
      LimousineShowroomCta.requestQuote,
    );
    expect(
      limousineShowroomCtaFor(_offer(presentation: 'from_price')),
      LimousineShowroomCta.requestQuote,
    );
    expect(
      limousineShowroomCtaFor(_offer(presentation: 'exact_fixed')),
      LimousineShowroomCta.book,
    );
    expect(
      limousineShowroomCtaFor(
        _offer(
          presentation: 'exact_fixed',
          hourly: <String, dynamic>{
            'enabled': true,
            'first_hour_cents': 12000,
            'additional_hour_cents': 9000,
            'minimum_duration_minutes': 120,
          },
        ),
      ),
      LimousineShowroomCta.book,
    );
    expect(
      limousineShowroomCtaFor(
        _offer(
          presentation: 'quote_required',
          hourly: <String, dynamic>{
            'enabled': true,
            'package_amount_cents': 45000,
            'package_duration_minutes': 180,
          },
        ),
      ),
      LimousineShowroomCta.book,
    );
    expect(kLimousineShowroomRequestQuote.nl, 'Offerte aanvragen');
    expect(kLimousineShowroomBook.nl, 'Boeking aanvragen');
    expect(kLimousineDetailQuoteCta.nl, 'Offerte aanvragen');
    expect(kLimousineDetailBookCta.nl, 'Boeking aanvragen');
    expect(kLimousineCustomerQuoteGateEnabled, isFalse);
    expect(kLimousineCustomerBookGateEnabled, isFalse);
  });

  testWidgets('quote CTA opens the limousine wizard immediately when gated on', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LimousineVehicleDetailPage(
          vehicle: _vehicle(_offer(presentation: 'quote_required')),
          companyName: 'FLX-00001',
          partnerId: 'company:fluxidi_fluxidi_ddmh9g:fluxidi_fluxidi_ddmh9g',
          quoteEnabled: true,
          manualQuoteEnabled: true,
          bookEnabled: true,
        ),
      ),
    );
    await tester.pump();
    expect(find.text(kLimousineDetailQuoteComingSoon.nl), findsNothing);
    expect(find.text(kLimousineDetailQuoteCta.nl), findsWidgets);
    tester
        .widget<ButtonStyleButton>(find.byKey(kLimousineDetailQuoteCtaKey))
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(kLimousineCustomerQuotePageKey), findsOneWidget);
    expect(find.byType(LimousineCustomerQuotePage), findsOneWidget);
    expect(find.text('Taxi'), findsNothing);
    expect(find.text('Straatrit'), findsNothing);
  });

  testWidgets('fixed-price CTA opens the same wizard as a booking request', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LimousineVehicleDetailPage(
          vehicle: _vehicle(_offer(presentation: 'exact_fixed')),
          companyName: 'FLX-00001',
          partnerId: 'company:fluxidi_fluxidi_ddmh9g:fluxidi_fluxidi_ddmh9g',
          quoteEnabled: true,
          manualQuoteEnabled: true,
          bookEnabled: true,
        ),
      ),
    );
    await tester.pump();
    expect(find.text(kLimousineDetailBookComingSoon.nl), findsNothing);
    expect(find.text(kLimousineDetailBookCta.nl), findsWidgets);
    tester
        .widget<ButtonStyleButton>(find.byKey(kLimousineDetailBookCtaKey))
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(kLimousineCustomerQuotePageKey), findsOneWidget);
    expect(find.byType(LimousineCustomerQuotePage), findsOneWidget);
  });

  test('client book/quote bodies never send tenant, company or totals', () {
    final quoteBody = limousineCustomerCreateBody(
      const LimousineQuoteCreateDraft(
        publicPartnerId: 'prt_1',
        offerId: 'off_1',
        from: 'Gent',
        to: 'Brussel',
        scheduledPickupIso: '2026-09-01T10:00:00Z',
        occasion: 'wedding',
      ),
    );
    final bookBody = limousineCustomerBookBody(
      const LimousineQuoteCreateDraft(
        publicPartnerId: 'prt_1',
        offerId: 'off_1',
        journeyType: 'hourly_package',
        from: 'Gent',
        to: 'Brussel',
        scheduledPickupIso: '2026-09-01T10:00:00Z',
        requestedDurationMinutes: 180,
      ),
    );
    for (final body in <Map<String, dynamic>>[quoteBody, bookBody]) {
      expect(body.containsKey('tenant_id'), isFalse);
      expect(body.containsKey('company_id'), isFalse);
      expect(body.containsKey('total_incl_vat_cents'), isFalse);
    }
    expect(quoteBody['offer_id'], 'off_1');
    expect(bookBody['offer_id'], 'off_1');
    expect(bookBody['service_category'], 'limousine');
  });

  test('review keeps partner, offer, route, duration, occasion and price mode', () {
    final rows = buildLimousineRequestReviewRows(
      draft: const LimousineQuoteCreateDraft(
        publicPartnerId: 'prt_1',
        offerId: 'off_1',
        from: 'Gent',
        to: 'Brussel',
        scheduledPickupIso: '2026-09-01T10:00:00Z',
        requestedDurationMinutes: 180,
        occasion: 'gala',
      ),
      language: AppLanguage.nl,
      offer: _offer(presentation: 'exact_fixed'),
      providerName: 'FLX-00001',
    );
    final ids = rows.map((row) => row.id).toSet();
    expect(ids.contains('provider'), isTrue);
    expect(ids.contains('offer'), isTrue);
    expect(ids.contains('route'), isTrue);
    expect(ids.contains('duration'), isTrue);
    expect(ids.contains('occasion'), isTrue);
    expect(ids.contains('price_status'), isTrue);
    expect(
      rows.singleWhere((row) => row.id == 'price_status').value,
      kLimousineReviewPriceStatusBook.nl,
    );
  });
}
