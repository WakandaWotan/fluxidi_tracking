import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1c_journey.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_showroom_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_unified_intent.dart';

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

void main() {
  test('quote and from-price stay on the existing quote CTA', () {
    expect(
      limousineShowroomCtaFor(_offer(presentation: 'quote_required')),
      LimousineShowroomCta.requestQuote,
    );
    expect(
      limousineShowroomCtaFor(_offer(presentation: 'from_price')),
      LimousineShowroomCta.requestQuote,
    );
    expect(
      limousineCustomerIntentKindOf(_offer(presentation: 'quote_required')),
      LimousineCustomerIntentKind.quoteRequest,
    );
  });

  test('fixed, hourly and package use booking-request CTA', () {
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
            'first_hour_cents': 12000,
            'additional_hour_cents': 9000,
            'minimum_duration_minutes': 120,
            'package_amount_cents': 45000,
            'package_duration_minutes': 180,
          },
        ),
      ),
      LimousineShowroomCta.book,
    );
  });

  test('book payload reuses public partner + offer and never sends totals', () {
    final body = limousineCustomerBookBody(
      const LimousineQuoteCreateDraft(
        publicPartnerId: 'prt_1',
        offerId: 'off_1',
        journeyType: 'hourly_package',
        from: 'Gent',
        to: 'Brussel',
        scheduledPickupIso: '2026-09-01T10:00:00Z',
        requestedDurationMinutes: 180,
        occasion: 'wedding',
      ),
    );
    expect(body['service_category'], 'limousine');
    expect(body['public_partner_id'], 'prt_1');
    expect(body['offer_id'], 'off_1');
    expect(body['occasion'], 'wedding');
    expect(body.containsKey('total_incl_vat_cents'), isFalse);
    expect(body.containsKey('tenant_id'), isFalse);
    expect(body.containsKey('company_id'), isFalse);
    expect(limousineCustomerBookBodyIsBounded(body), isTrue);
  });

  testWidgets('disabled book/quote gates never push a flash route', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                opened = true;
                openLimousineCustomerQuoteFlow(
                  context,
                  publicPartnerId: 'prt_1',
                  offer: _offer(presentation: 'exact_fixed'),
                  bookEnabled: false,
                  quoteEnabled: false,
                  manualQuoteEnabled: false,
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(opened, isTrue);
    expect(find.byKey(kLimousineCustomerQuotePageKey), findsNothing);
    expect(find.byType(LimousineCustomerQuotePage), findsNothing);
  });

  test('production CTA gates stay fail-closed', () {
    expect(kLimousineCustomerQuoteGateEnabled, isFalse);
    expect(kLimousineCustomerManualQuoteGateEnabled, isFalse);
    expect(kLimousineCustomerBookGateEnabled, isFalse);
    expect(kLimousineCustomerQuoteGateDefineKey, 'LIMOUSINE_QUOTE_ENABLED');
    expect(
      kLimousineCustomerManualQuoteGateDefineKey,
      'LIMOUSINE_MANUAL_QUOTE_ENABLED',
    );
    expect(kLimousineCustomerBookGateDefineKey, 'LIMOUSINE_BOOK_ENABLED');
  });

  test('published CTAs use localized Offerte/Boeking aanvragen copy', () {
    expect(kLimousineShowroomRequestQuote.nl, 'Offerte aanvragen');
    expect(kLimousineShowroomBook.nl, 'Boeking aanvragen');
    expect(kLimousineReviewSubmit.nl, 'Offerte aanvragen');
    expect(kLimousineReviewSubmitBooking.nl, 'Boeking aanvragen');
    for (final language in AppLanguage.values) {
      expect(kLimousineShowroomRequestQuote.of(language).trim(), isNotEmpty);
      expect(kLimousineShowroomBook.of(language).trim(), isNotEmpty);
      expect(kLimousineReviewSubmitBooking.of(language).trim(), isNotEmpty);
    }
  });

  test('from-price and quote bodies never send a booking total', () {
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
    expect(quoteBody['occasion'], 'wedding');
    expect(quoteBody.containsKey('service_category'), isFalse);
    expect(quoteBody.containsKey('total_incl_vat_cents'), isFalse);
    expect(limousineCustomerCreateBodyIsBounded(quoteBody), isTrue);
    expect(
      limousineCustomerIntentKindOf(_offer(presentation: 'from_price')),
      LimousineCustomerIntentKind.quoteRequest,
    );
  });

  test('review price status distinguishes the five published modes', () {
    final quoteRows = buildLimousineRequestReviewRows(
      draft: const LimousineQuoteCreateDraft(occasion: 'gala'),
      language: AppLanguage.nl,
      offer: _offer(presentation: 'quote_required'),
    );
    expect(
      quoteRows.singleWhere((row) => row.id == 'price_status').value,
      kLimousineReviewPriceStatusQuote.nl,
    );
    final fromRows = buildLimousineRequestReviewRows(
      draft: const LimousineQuoteCreateDraft(),
      language: AppLanguage.nl,
      offer: _offer(presentation: 'from_price'),
    );
    expect(
      fromRows.singleWhere((row) => row.id == 'price_status').value,
      kLimousineReviewPriceStatusFrom.nl,
    );
    final bookRows = buildLimousineRequestReviewRows(
      draft: const LimousineQuoteCreateDraft(requestedDurationMinutes: 180),
      language: AppLanguage.nl,
      offer: _offer(presentation: 'exact_fixed'),
    );
    expect(
      bookRows.singleWhere((row) => row.id == 'price_status').value,
      kLimousineReviewPriceStatusBook.nl,
    );
    expect(
      bookRows.singleWhere((row) => row.id == 'duration').value,
      '180 min',
    );
  });
}
