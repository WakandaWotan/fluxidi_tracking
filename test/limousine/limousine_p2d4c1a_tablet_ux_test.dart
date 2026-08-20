import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/limousine/limousine_dimensions.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_offer_editor.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_pricing_separation.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';

LimousinePublishedOffer _offer() {
  return LimousinePublishedOffer.fromJson(<String, dynamic>{
    'offer_id': 'off_1',
    'target_type': 'vehicle',
    'vehicle_id': 'veh_1',
    'service_class_id': 'executive_sedan',
    'title': {'nl': 'Executive', 'en': 'Executive'},
    'description': {'nl': 'Incl. btw', 'en': 'Incl. VAT'},
    'journey_types': ['point_to_point'],
    'price_presentation': 'quote_required',
    'display_amount_cents': 45000,
    'currency': 'EUR',
    'vehicle': {'passenger_capacity': 3, 'luggage_capacity': 2},
  });
}

LimousineQuoteCreateDraft _validDraft() {
  return const LimousineQuoteCreateDraft(
    publicPartnerId: 'p1',
    offerId: 'off_1',
    journeyType: 'point_to_point',
    from: 'Gent',
    to: 'Brussel',
    stops: ['Antwerpen'],
    scheduledPickupIso: '2026-09-01T10:00:00Z',
    pax: 2,
    bags: 1,
  );
}

class _FakeGateway implements LimousineCustomerQuoteGateway {
  int discoverCalls = 0;
  int createCalls = 0;

  @override
  Future<List<LimousineDiscoveredProvider>> discoverNearby({
    String? postcode,
    double? lat,
    double? lng,
    int radiusKm = 20,
  }) async {
    discoverCalls += 1;
    return const [
      LimousineDiscoveredProvider(
        partnerId: 'p1',
        companyName: 'Coachline',
        limousineAvailable: true,
      ),
    ];
  }

  @override
  Future<LimousineProviderDetail> loadProvider(String publicPartnerId) async {
    return LimousineProviderDetail(
      provider: const LimousineDiscoveredProvider(
        partnerId: 'p1',
        companyName: 'Coachline',
        limousineAvailable: true,
      ),
      offers: [_offer()],
    );
  }

  @override
  Future<LimousineQuoteCreateResult> createRequest(
    LimousineQuoteCreateDraft draft,
  ) async {
    createCalls += 1;
    throw const LimousineCustomerQuoteException(
      code: 'not_found',
      unavailable: true,
    );
  }

  @override
  Future<LimousineQuoteRequest> pollStatus(String statusRef) async {
    throw const LimousineCustomerQuoteException(code: 'not_found');
  }

  @override
  Future<LimousineQuoteAcceptResult> accept({
    required String quoteRequestId,
    required int expectedRevision,
    required int termsRevision,
  }) async {
    throw const LimousineCustomerQuoteException(code: 'not_found');
  }
}

Widget _app(Widget child, {Size size = kLimousinePhonePortrait}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SM-X400, landscape and phone widths stay distinct', () {
    expect(kLimousineSmX400Portrait.width, 1320);
    expect(kLimousineSmX400Portrait.height, 2112);
    expect(kLimousineTabletLandscape.width, 2112);
    expect(
      limousineRequestWizardContentWidth(kLimousineSmX400Portrait.width),
      kLimousineRequestWizardTabletMaxWidth,
    );
    expect(
      limousineRequestWizardContentWidth(kLimousinePhonePortrait.width),
      kLimousinePhonePortrait.width,
    );
  });

  test('every wizard step has a progress label and validation', () {
    expect(kLimousineRequestWizardSteps, hasLength(4));
    expect(kLimousineCustomerStepJourney.nl, 'Traject');
    expect(kLimousineCustomerStepProvider.nl, 'Aanbieder');
    expect(kLimousineCustomerStepDetails.nl.toLowerCase(), contains('extra'));
    expect(kLimousineCustomerStepReview.nl, 'Controleren');
    final empty = const LimousineQuoteCreateDraft();
    expect(
      limousineRequestWizardCanAdvance(
        step: LimousineRequestWizardStep.journey,
        draft: empty,
      ),
      isFalse,
    );
    expect(
      limousineRequestWizardGaps(
        step: LimousineRequestWizardStep.journey,
        draft: empty,
      ).map((gap) => gap.code),
      containsAll(<String>[
        'pickup_required',
        'destination_required',
        'pickup_time_required',
      ]),
    );
    expect(
      limousineRequestWizardCanAdvance(
        step: LimousineRequestWizardStep.provider,
        draft: _validDraft(),
        offer: _offer(),
        hasProvider: true,
      ),
      isTrue,
    );
    expect(
      limousineRequestWizardCanAdvance(
        step: LimousineRequestWizardStep.provider,
        draft: const LimousineQuoteCreateDraft(from: 'Gent', to: 'Brussel'),
      ),
      isFalse,
    );
    final overCapacity = _validDraft().copyWith(pax: 9);
    expect(
      limousineRequestWizardGaps(
        step: LimousineRequestWizardStep.details,
        draft: overCapacity,
        offer: _offer(),
        hasProvider: true,
      ).map((gap) => gap.code),
      contains('capacity_exceeded'),
    );
  });

  test('roundtrip return is required only when enabled', () {
    final oneWay = _validDraft();
    expect(
      limousineRequestWizardGaps(
        step: LimousineRequestWizardStep.journey,
        draft: oneWay,
      ),
      isEmpty,
    );
    final missingReturn = oneWay.copyWith(roundtrip: true);
    expect(
      limousineRequestWizardGaps(
        step: LimousineRequestWizardStep.journey,
        draft: missingReturn,
      ).map((gap) => gap.code),
      contains('return_mode_required'),
    );
  });

  test('no HTTP from incomplete forms', () {
    expect(
      limousineRequestWizardAllowsHttp(
        step: LimousineRequestWizardStep.journey,
        draft: const LimousineQuoteCreateDraft(),
        action: 'discover',
      ),
      isFalse,
    );
    expect(
      limousineRequestWizardAllowsHttp(
        step: LimousineRequestWizardStep.review,
        draft: const LimousineQuoteCreateDraft(),
        action: 'submit',
      ),
      isFalse,
    );
    expect(
      limousineRequestWizardAllowsHttp(
        step: LimousineRequestWizardStep.review,
        draft: _validDraft(),
        offer: _offer(),
        hasProvider: true,
        action: 'submit',
      ),
      isTrue,
    );
  });

  test('review summary is structured and has no orphan arrow', () {
    final rows = buildLimousineRequestReviewRows(
      draft: _validDraft(),
      language: AppLanguage.nl,
      providerName: 'Coachline',
      offer: _offer(),
    );
    expect(rows.map((row) => row.id).toList(), contains('provider'));
    expect(rows.map((row) => row.id).toList(), contains('offer'));
    expect(rows.map((row) => row.id).toList(), contains('route'));
    expect(rows.map((row) => row.id).toList(), contains('pickup'));
    expect(rows.map((row) => row.id).toList(), contains('pax'));
    expect(rows.map((row) => row.id).toList(), contains('price_evidence'));
    for (final row in rows) {
      expect(limousineReviewContainsOrphanArrow(row.value), isFalse);
      expect(limousineReviewContainsOrphanArrow(row.label), isFalse);
    }
    expect(rows.any((row) => row.value.contains('450.00')), isTrue);
    expect(
      kLimousineCustomerForbiddenSubmitKeys.contains('total_incl_vat_cents'),
      isTrue,
    );
  });

  test('gates-off errors stay friendly and never expose raw exceptions', () {
    final message = limousineFriendlyCompanyError(Exception('not_found'));
    expect(message, kLimousinePricingSaveFailed.nl);
    expect(
      limousineFriendlyCompanyError(Exception('stale_source_revision')),
      kLimousinePricingStaleConflict.nl,
    );
    expect(limousineLooksLikeRawException(message), isFalse);
    expect(limousineLooksLikeRawException('Exception: not_found'), isTrue);
    expect(limousineLooksLikeRawException('LIMOUSINE_QUOTE_ENABLED'), isTrue);
    final confirmed = LimousineOffersEditorSnapshot(
      enabled: false,
      offers: [
        <String, dynamic>{'offer_id': 'off_1', 'enabled': false},
      ],
    );
    final optimistic = LimousineOffersEditorSnapshot(
      enabled: true,
      offers: [
        <String, dynamic>{'offer_id': 'off_1', 'enabled': true},
      ],
    );
    final rolled = limousineRollbackFailedPersistence(confirmed: confirmed);
    expect(rolled.enabled, isFalse);
    expect(rolled.offers.first['enabled'], isFalse);
    expect(identical(rolled.offers, optimistic.offers), isFalse);
    expect(
      limousineCompanySaveAllowed(
        dirty: true,
        saving: false,
        offerErrors: [
          <String>['missing_display_amount'],
        ],
      ),
      isFalse,
    );
  });

  test('no taxi fallback and no client-price authority', () {
    expect(
      limousinePricingForbidsTaxiFallback(LimousineServiceCategory.limousine),
      isTrue,
    );
    expect(
      resolveLimousinePricingMode(const LimousinePricingInputs()).failedClosed,
      isTrue,
    );
    expect(
      kLimousineCustomerForbiddenSubmitKeys.contains('taxi_price'),
      isTrue,
    );
  });

  test('partner limousine visibility stays server-authoritative', () {
    expect(
      limousinePublicShowroomShouldRender(
        entryEnabled: true,
        profile: <String, dynamic>{
          'services': <String>['taxi', 'airport'],
        },
      ),
      isFalse,
    );
    expect(
      limousinePublicShowroomShouldRender(
        entryEnabled: true,
        profile: <String, dynamic>{
          'limousine_available': true,
          'limousine_offers': <Map<String, dynamic>>[
            {
              'offer_id': 'off_1',
              'enabled': true,
              'published': true,
              'target_type': 'service_class',
              'service_class_id': 'executive_sedan',
              'price_presentation': 'quote_required',
              'title': {'nl': 'Executive'},
            },
          ],
        },
      ),
      isTrue,
    );
    expect(
      limousinePublicShowroomShouldRender(
        entryEnabled: true,
        profile: <String, dynamic>{
          'limousine_available': false,
          'limousine_offers': <Map<String, dynamic>>[
            {'offer_id': 'off_1', 'enabled': true, 'published': true},
          ],
        },
      ),
      isFalse,
    );
  });

  test('light/dark/blue/gold readability contracts', () {
    for (final variant in kLimousineUxContrastVariants) {
      final tokens = LimousineUxTokens.fromCustomer(
        paletteForCustomerTheme(variant),
      );
      expect(
        limousineHasReadableContrast(tokens.onSurface, tokens.surface),
        isTrue,
        reason: variant.name,
      );
      expect(
        limousineHasReadableContrast(tokens.onSurface, tokens.fieldFill),
        isTrue,
        reason: '${variant.name} field',
      );
      expect(
        limousineHasReadableContrast(tokens.onHero, tokens.heroScrim),
        isTrue,
        reason: '${variant.name} hero',
      );
    }
    final light = LimousineUxTokens.fromCustomer(
      paletteForCustomerTheme(CustomerThemeVariant.premiumLight),
    );
    expect(light.isDark, isFalse);
    expect(light.onSurface, isNot(const Color(0xFFFFFFFF)));
    expect(
      limousineHasReadableContrast(light.onSurface, light.fieldFill),
      isTrue,
    );
    final gold = LimousineUxTokens.fromBrandSignature(
      BrandSignaturePalette.defaults,
    );
    expect(limousineHasReadableContrast(gold.onSurface, gold.surface), isTrue);
  });

  testWidgets('wizard layouts and disabled Next on empty journey', (
    tester,
  ) async {
    final gateway = _FakeGateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    await tester.pumpWidget(
      _app(
        LimousineCustomerQuotePage(
          controller: controller,
          gateway: gateway,
          entryEnabled: true,
        ),
        size: kLimousineSmX400Portrait,
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineCustomerTabletLayoutKey), findsOneWidget);
    expect(find.byKey(kLimousineRequestWizardStepperKey), findsOneWidget);
    expect(find.byKey(kLimousineRequestWizardFooterKey), findsOneWidget);
    expect(find.byKey(kLimousineRequestWizardHintKey), findsOneWidget);
    final next = tester.widget<FilledButton>(
      find.byKey(kLimousineRequestWizardNextKey),
    );
    expect(next.onPressed, isNull);
    expect(gateway.discoverCalls, 0);
    expect(gateway.createCalls, 0);

    await tester.pumpWidget(
      _app(
        LimousineCustomerQuotePage(
          controller: controller,
          gateway: gateway,
          entryEnabled: true,
        ),
        size: kLimousineTabletLandscape,
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineCustomerTabletLayoutKey), findsOneWidget);

    await tester.pumpWidget(
      _app(
        LimousineCustomerQuotePage(
          controller: controller,
          gateway: gateway,
          entryEnabled: true,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineCustomerPhoneLayoutKey), findsOneWidget);
    controller.dispose();
  });

  testWidgets('review summary widget has no placeholder arrow', (tester) async {
    final gateway = _FakeGateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway)
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: _offer(),
        companyName: 'Coachline',
      )
      ..updateDraft(_validDraft())
      ..goTo(LimousineCustomerQuoteStep.reviewRequest);
    await tester.pumpWidget(
      _app(
        LimousineCustomerQuotePage(
          controller: controller,
          gateway: gateway,
          entryEnabled: true,
        ),
        size: kLimousineSmX400Portrait,
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineRequestReviewSummaryKey), findsOneWidget);
    expect(find.textContaining('→'), findsNothing);
    expect(find.text('Coachline'), findsWidgets);
    expect(find.byKey(kLimousineCustomerSubmitKey), findsOneWidget);
    controller.dispose();
  });

  testWidgets('gates-off submit stays fail-closed and polished', (
    tester,
  ) async {
    final gateway = _FakeGateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway)
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: _offer(),
        companyName: 'Coachline',
      )
      ..updateDraft(_validDraft())
      ..goTo(LimousineCustomerQuoteStep.reviewRequest);
    await tester.pumpWidget(
      _app(
        LimousineCustomerQuotePage(
          controller: controller,
          gateway: gateway,
          entryEnabled: true,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(kLimousineCustomerSubmitKey));
    await tester.pumpAndSettle();
    expect(gateway.createCalls, 1);
    expect(controller.request, isNull);
    expect(find.byKey(kLimousineCustomerUnavailableKey), findsOneWidget);
    expect(find.textContaining('Exception:'), findsNothing);
    expect(find.textContaining('not_found'), findsNothing);
    expect(
      find.text(kLimousineGatesOffFriendly.of(appLanguageNotifier.value)),
      findsOneWidget,
    );
    controller.dispose();
  });

  testWidgets('language tabs preserve NL/EN/FR/ES independently', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LimousineOfferEditorDialog(
          initialOffer: <String, dynamic>{
            'title': {
              'nl': 'NL titel',
              'en': 'EN title',
              'fr': 'FR titre',
              'es': 'ES titulo',
            },
            'description': {
              'nl': 'NL oms',
              'en': 'EN desc',
              'fr': 'FR desc',
              'es': 'ES desc',
            },
          },
          vehicles: const <VehicleProfile>[],
          currency: 'EUR',
          language: AppLanguage.nl,
          backgroundColor: const Color(0xFFFFFBF4),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineOfferEditorDialogKey), findsOneWidget);
    expect(find.byKey(kLimousineOfferEditorScrollKey), findsOneWidget);
    expect(find.byKey(kLimousineOfferEditorActionsKey), findsOneWidget);
    expect(find.byKey(kLimousineOfferEditorLanguageTabsKey), findsOneWidget);
    expect(find.text('NL titel'), findsOneWidget);
    await tester.tap(find.byKey(limousineOfferEditorLanguageTabKey('en')));
    await tester.pumpAndSettle();
    expect(find.text('EN title'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'EN title'),
      'EN new',
    );
    await tester.tap(find.byKey(limousineOfferEditorLanguageTabKey('nl')));
    await tester.pumpAndSettle();
    expect(find.text('NL titel'), findsOneWidget);
    await tester.tap(find.byKey(limousineOfferEditorLanguageTabKey('en')));
    await tester.pumpAndSettle();
    expect(find.text('EN new'), findsOneWidget);
    expect(find.text('Annuleren'), findsOneWidget);
    expect(find.text('Bewaren'), findsOneWidget);
  });

  test('offer editor source keeps language tabs and bounded menus', () {
    final editor = File(
      'lib/limousine/limousine_offer_editor.dart',
    ).readAsStringSync();
    expect(editor.contains('_localizedMatrix'), isTrue);
    expect(editor.contains('_languageTabs'), isTrue);
    expect(editor.contains('kLimousineOfferEditorMenuMaxHeight'), isTrue);
    expect(editor.contains('kLimousineOfferEditorActionsKey'), isTrue);
    expect(editor.contains('kLimousineOfferEditorScrollKey'), isTrue);
    expect(editor.contains('AlertDialog'), isFalse);
  });

  test('company settings map gates-off errors without raw exceptions', () {
    final settings = File('lib/business_settings_page.dart').readAsStringSync();
    expect(settings.contains('limousineFriendlyCompanyError'), isTrue);
    expect(settings.contains('kLimousineCompanyOffersStatusKey'), isTrue);
    expect(settings.contains('limousineRollbackFailedPersistence'), isTrue);
    expect(settings.contains('_limousineOffersError = e.toString()'), isFalse);
  });

  test('taxi/airport/RateHawk pages are not rewritten by this UX pass', () {
    expect(
      File(
        'lib/hotels/ratehawk_search.dart',
      ).readAsStringSync().contains('ratehawk_invocation_blocked'),
      isTrue,
    );
    expect(
      File(
        'lib/calculator_page.dart',
      ).readAsStringSync().contains('LimousineCustomerQuotePage'),
      isFalse,
    );
  });
}
