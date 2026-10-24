import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1c_journey.dart';
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

LimousineQuoteCreateDraft _validDraft({
  bool roundtrip = false,
  String returnPickupIso = '',
}) {
  return LimousineQuoteCreateDraft(
    publicPartnerId: 'p1',
    offerId: 'off_1',
    journeyType: 'point_to_point',
    from: 'Korenmarkt 1, 9000 Gent, Belgium',
    to: 'Grote Markt, 1000 Brussel, Belgium',
    scheduledPickupIso: '2026-09-01T10:00:00Z',
    roundtrip: roundtrip,
    returnPickupIso: returnPickupIso,
    pax: 2,
    bags: 1,
  );
}

LimousineAddressValue _selected(String label) => LimousineAddressValue(
  displayText: label,
  canonicalLabel: label,
  lat: 51.0,
  lon: 3.7,
  acceptance: LimousineAddressAcceptance.selected,
);

LimousinePlaceSuggestion _gent() => const LimousinePlaceSuggestion(
  label: 'Korenmarkt 1, 9000 Gent, Belgium',
  lat: 51.0543,
  lon: 3.7174,
  placeId: 'address.1',
);

LimousinePlaceSuggestion _brussels() => const LimousinePlaceSuggestion(
  label: 'Grote Markt, 1000 Brussel, Belgium',
  lat: 50.8467,
  lon: 4.3525,
  placeId: 'address.2',
);

class _Lookup extends LimousinePlaceLookup {
  _Lookup()
    : super(
        searchOverride: (query, language) async {
          if (query.toLowerCase().contains('brussel') ||
              query.toLowerCase().contains('brussels')) {
            return LimousinePlaceLookupResult(suggestions: [_brussels()]);
          }
          return LimousinePlaceLookupResult(suggestions: [_gent()]);
        },
      );
}

class _FakeGateway with LimousineCustomerQuoteGateway {
  int discoverCalls = 0;
  int createCalls = 0;
  LimousineQuoteCreateDraft? lastDraft;

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
    lastDraft = draft;
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

Future<void> _selectAddress(
  WidgetTester tester,
  String fieldId,
  String query,
) async {
  await tester.enterText(find.byKey(limousineAddressInputKey(fieldId)), query);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 230));
  tester
      .widget<ListTile>(find.byKey(limousineAddressSuggestionKey(fieldId, 0)))
      .onTap!();
  await tester.pump();
}

void _toggleRoundtrip(WidgetTester tester, {required bool value}) {
  tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(value);
}

void _pressKeyedButton(WidgetTester tester, Key key) {
  tester.widget<ButtonStyleButton>(find.byKey(key)).onPressed!();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    appLanguageNotifier.value = AppLanguage.nl;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  test('wait duration is not a live Worker field', () {
    expect(kLimousineReturnWaitDurationSupported, isFalse);
    expect(
      limousineReturnWaitDurationGaps(supported: false, minutes: 30),
      <String>['return_wait_unavailable'],
    );
    expect(
      limousineReturnWaitDurationGaps(supported: true, minutes: null),
      <String>['return_wait_required'],
    );
    expect(
      limousineReturnWaitDurationGaps(supported: true, minutes: 30),
      isEmpty,
    );
    expect(kLimousineCustomerCreateAllowedKeys.contains('roundtrip'), isTrue);
    expect(
      kLimousineCustomerCreateAllowedKeys.contains('return_pickup_iso'),
      isTrue,
    );
    expect(
      kLimousineCustomerCreateAllowedKeys.contains('return_wait_minutes'),
      isFalse,
    );
    expect(
      kLimousineCustomerCreateAllowedKeys.contains('wait_minutes'),
      isFalse,
    );
    final source = File(
      'lib/limousine/limousine_customer_quote.dart',
    ).readAsStringSync();
    expect(source.contains('return_wait_minutes'), isFalse);
    expect(source.contains("'wait_minutes'"), isFalse);
  });

  test('enabling round trip requires an explicit return mode', () {
    final ready = _validDraft(roundtrip: true);
    expect(
      limousineRequestWizardGaps(
        step: LimousineRequestWizardStep.journey,
        draft: ready,
        pickupAddress: _selected(ready.from),
        destinationAddress: _selected(ready.to),
      ).map((gap) => gap.code),
      contains('return_mode_required'),
    );
    expect(
      limousineRequestWizardGaps(
        step: LimousineRequestWizardStep.journey,
        draft: ready,
        pickupAddress: _selected(ready.from),
        destinationAddress: _selected(ready.to),
        returnKind: LimousineReturnTripKind.wait,
      ).map((gap) => gap.code),
      contains('return_wait_unavailable'),
    );
    expect(
      limousineRequestWizardGaps(
        step: LimousineRequestWizardStep.journey,
        draft: ready,
        pickupAddress: _selected(ready.from),
        destinationAddress: _selected(ready.to),
        returnKind: LimousineReturnTripKind.wait,
        waitDurationSupported: true,
      ).map((gap) => gap.code),
      contains('return_wait_required'),
    );
    expect(
      limousineRequestWizardGaps(
        step: LimousineRequestWizardStep.journey,
        draft: ready,
        pickupAddress: _selected(ready.from),
        destinationAddress: _selected(ready.to),
        returnKind: LimousineReturnTripKind.wait,
        waitDurationSupported: true,
        waitMinutes: 45,
      ),
      isEmpty,
    );
    expect(
      limousineRequestWizardGaps(
        step: LimousineRequestWizardStep.journey,
        draft: ready,
        pickupAddress: _selected(ready.from),
        destinationAddress: _selected(ready.to),
        returnKind: LimousineReturnTripKind.later,
      ).map((gap) => gap.code),
      contains('return_time_required'),
    );
    expect(
      limousineRequestWizardGaps(
        step: LimousineRequestWizardStep.journey,
        draft: ready.copyWith(returnPickupIso: '2026-09-01T09:00:00Z'),
        pickupAddress: _selected(ready.from),
        destinationAddress: _selected(ready.to),
        returnKind: LimousineReturnTripKind.later,
      ).map((gap) => gap.code),
      contains('return_time_order'),
    );
    expect(
      limousineRequestWizardGaps(
        step: LimousineRequestWizardStep.journey,
        draft: ready.copyWith(returnPickupIso: '2026-09-01T18:00:00Z'),
        pickupAddress: _selected(ready.from),
        destinationAddress: _selected(ready.to),
        returnKind: LimousineReturnTripKind.later,
      ),
      isEmpty,
    );
  });

  test('wait and later modes are mutually exclusive in gaps', () {
    final later = _validDraft(
      roundtrip: true,
      returnPickupIso: '2026-09-01T18:00:00Z',
    );
    final laterGaps = limousineRequestWizardGaps(
      step: LimousineRequestWizardStep.journey,
      draft: later,
      pickupAddress: _selected(later.from),
      destinationAddress: _selected(later.to),
      returnKind: LimousineReturnTripKind.later,
    ).map((gap) => gap.code);
    expect(laterGaps, isNot(contains('return_wait_required')));
    expect(laterGaps, isNot(contains('return_wait_unavailable')));
    final waitGaps = limousineRequestWizardGaps(
      step: LimousineRequestWizardStep.journey,
      draft: later,
      pickupAddress: _selected(later.from),
      destinationAddress: _selected(later.to),
      returnKind: LimousineReturnTripKind.wait,
    ).map((gap) => gap.code);
    expect(waitGaps, isNot(contains('return_time_required')));
    expect(waitGaps, contains('return_wait_unavailable'));
  });

  test('outbound pickup stays independently required', () {
    final draft = _validDraft(
      roundtrip: true,
      returnPickupIso: '2026-09-01T18:00:00Z',
    ).copyWith(scheduledPickupIso: '');
    expect(
      limousineRequestWizardGaps(
        step: LimousineRequestWizardStep.journey,
        draft: draft,
        pickupAddress: _selected(draft.from),
        destinationAddress: _selected(draft.to),
        returnKind: LimousineReturnTripKind.later,
      ).map((gap) => gap.code),
      contains('pickup_time_required'),
    );
  });

  test('disabling round trip drops return payload fields', () {
    final stale = _validDraft(
      roundtrip: false,
      returnPickupIso: '2026-09-01T18:00:00Z',
    );
    final body = limousineCustomerCreateBody(stale);
    expect(body.containsKey('roundtrip'), isFalse);
    expect(body.containsKey('return_pickup_iso'), isFalse);
    expect(body.containsKey('return_wait_minutes'), isFalse);
    expect(body.containsKey('taxi_price'), isFalse);
    expect(body.containsKey('total_incl_vat_cents'), isFalse);
    final live = limousineCustomerCreateBody(
      _validDraft(roundtrip: true, returnPickupIso: '2026-09-01T18:00:00Z'),
    );
    expect(live['roundtrip'], isTrue);
    expect(live['return_pickup_iso'], '2026-09-01T18:00:00Z');
    expect(
      limousineRequestWizardGaps(
        step: LimousineRequestWizardStep.journey,
        draft: stale,
        pickupAddress: _selected(stale.from),
        destinationAddress: _selected(stale.to),
        returnKind: LimousineReturnTripKind.later,
      ),
      isEmpty,
    );
  });

  test('round trip does not invent a blank intermediate stop', () {
    expect(
      limousineRequestWizardGaps(
        step: LimousineRequestWizardStep.journey,
        draft: _validDraft(roundtrip: true),
        pickupAddress: _selected('A'),
        destinationAddress: _selected('B'),
        stopAddresses: const [],
        returnKind: LimousineReturnTripKind.later,
        returnPickupAddress: _selected('B'),
        returnDestinationAddress: _selected('A'),
      ).map((gap) => gap.code),
      contains('return_time_required'),
    );
    expect(
      limousineRequestWizardGaps(
        step: LimousineRequestWizardStep.journey,
        draft: _validDraft(roundtrip: true),
        pickupAddress: _selected('A'),
        destinationAddress: _selected('B'),
        stopAddresses: const [LimousineAddressValue()],
        returnKind: LimousineReturnTripKind.later,
        returnPickupAddress: _selected('B'),
        returnDestinationAddress: _selected('A'),
      ).map((gap) => gap.code),
      contains('stop_address_required'),
    );
  });

  test('precise validation exists in NL/EN/FR/ES', () {
    expect(limousineP2d4c1cLabelsComplete(), isTrue);
    const codes = <String>[
      'pickup_time_required',
      'return_mode_required',
      'return_wait_required',
      'return_time_required',
      'stop_address_required',
    ];
    for (final language in const [
      AppLanguage.nl,
      AppLanguage.en,
      AppLanguage.fr,
      AppLanguage.es,
    ]) {
      for (final code in codes) {
        final text = limousineRequestGapLabel(code).of(language);
        expect(text.trim(), isNotEmpty, reason: '$code $language');
        if (language != AppLanguage.en) {
          expect(
            text,
            isNot('Complete the required fields to continue'),
            reason: '$code $language',
          );
        }
      }
    }
    expect(kLimousineGapPickupTime.nl, 'Kies de ophaaldatum en -tijd.');
    expect(kLimousineGapReturnMode.nl, 'Kies hoe u wilt terugkeren.');
    expect(kLimousineGapReturnWait.nl, 'Kies de wachttijd van de chauffeur.');
    expect(
      kLimousineGapReturnTime.nl,
      'Kies de datum en tijd van de terugrit.',
    );
    expect(kLimousineGapStop.nl, 'Vul de tussenstop in of verwijder hem.');
  });

  test('review rows never expose a raw ISO or client booking total', () {
    final rows = buildLimousineRequestReviewRows(
      draft: _validDraft(
        roundtrip: true,
        returnPickupIso: '2026-09-01T18:00:00Z',
      ),
      language: AppLanguage.nl,
      providerName: 'Coachline',
      offer: _offer(),
      returnKind: LimousineReturnTripKind.later,
    );
    for (final row in rows) {
      expect(limousineCustomerLooksLikeRawIso(row.value), isFalse);
      expect(row.value.toLowerCase(), isNot(contains('taxi')));
    }
    expect(rows.any((row) => row.id == 'price_evidence'), isTrue);
    expect(
      limousineCustomerCreateBody(_validDraft()).containsKey('taxi_price'),
      isFalse,
    );
  });

  test('themes keep readable contrast including brand gold', () {
    for (final variant in CustomerThemeVariant.values) {
      final tokens = LimousineUxTokens.fromCustomer(
        paletteForCustomerTheme(variant),
      );
      expect(
        limousineHasReadableContrast(tokens.onSurface, tokens.surface),
        isTrue,
        reason: variant.name,
      );
    }
    final gold = LimousineUxTokens.fromBrandSignature(
      BrandSignaturePalette.defaults,
    );
    expect(limousineHasReadableContrast(gold.onSurface, gold.surface), isTrue);
  });

  testWidgets(
    'round trip reverses structured addresses and keeps them editable',
    (tester) async {
      final gateway = _FakeGateway();
      final lookup = _Lookup();
      final controller = LimousineCustomerQuoteController(gateway: gateway);
      await tester.pumpWidget(
        _app(
          LimousineCustomerQuotePage(
            controller: controller,
            gateway: gateway,
            placeLookup: lookup,
            entryEnabled: true,
          ),
          size: kLimousineSmX400Portrait,
        ),
      );
      await tester.pump();
      await _selectAddress(tester, 'pickup', 'Korenmarkt');
      await tester.ensureVisible(
        find.byKey(limousineAddressInputKey('destination')),
      );
      await _selectAddress(tester, 'destination', 'Brussel');
      controller.updateDraft(
        controller.draft.copyWith(scheduledPickupIso: '2026-09-01T10:00:00Z'),
      );
      await tester.pump();
      _toggleRoundtrip(tester, value: true);
      await tester.pump();
      expect(find.byKey(kLimousineReturnCardKey), findsOneWidget);
      expect(find.byKey(limousineAddressFieldKey('stop_0')), findsNothing);
      expect(
        tester
            .widget<TextField>(
              find.byKey(limousineAddressInputKey('return_pickup')),
            )
            .controller!
            .text,
        _brussels().label,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(limousineAddressInputKey('return_destination')),
            )
            .controller!
            .text,
        _gent().label,
      );
      await tester.ensureVisible(
        find.byKey(limousineAddressInputKey('return_pickup')),
      );
      await _selectAddress(tester, 'return_pickup', 'Korenmarkt');
      expect(
        tester
            .widget<TextField>(
              find.byKey(limousineAddressInputKey('return_pickup')),
            )
            .controller!
            .text,
        _gent().label,
      );
      expect(find.byKey(kLimousineReturnWaitModeKey), findsOneWidget);
      expect(find.byKey(kLimousineReturnLaterModeKey), findsOneWidget);
      final waitInk = tester.widget<InkWell>(
        find.descendant(
          of: find.byKey(kLimousineReturnWaitModeKey),
          matching: find.byType(InkWell),
        ),
      );
      expect(waitInk.onTap, isNull);
      expect(find.text(kLimousineReturnWaitUnavailable.nl), findsOneWidget);
      expect(find.text(kLimousineRequestIncompleteHint.en), findsNothing);
      expect(find.text(kLimousineGapReturnMode.nl), findsOneWidget);
      tester
          .widget<InkWell>(
            find.descendant(
              of: find.byKey(kLimousineReturnLaterModeKey),
              matching: find.byType(InkWell),
            ),
          )
          .onTap!();
      await tester.pump();
      expect(find.byKey(kLimousineReturnPickupTimeKey), findsOneWidget);
      expect(find.text(kLimousineGapReturnTime.nl), findsOneWidget);
      _toggleRoundtrip(tester, value: false);
      await tester.pump();
      expect(find.byKey(kLimousineReturnCardKey), findsNothing);
      expect(find.text(kLimousineGapReturnMode.nl), findsNothing);
      expect(controller.draft.roundtrip, isFalse);
      expect(controller.draft.returnPickupIso, isEmpty);
      controller.dispose();
      lookup.dispose();
    },
  );

  testWidgets('added stop can be removed and does not appear from round trip', (
    tester,
  ) async {
    final gateway = _FakeGateway();
    final lookup = _Lookup();
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    await tester.pumpWidget(
      _app(
        LimousineCustomerQuotePage(
          controller: controller,
          gateway: gateway,
          placeLookup: lookup,
          entryEnabled: true,
        ),
        size: kLimousineSmX400Portrait,
      ),
    );
    await tester.pump();
    await _selectAddress(tester, 'pickup', 'Korenmarkt');
    await _selectAddress(tester, 'destination', 'Brussel');
    controller.updateDraft(
      controller.draft.copyWith(scheduledPickupIso: '2026-09-01T10:00:00Z'),
    );
    await tester.pump();
    _pressKeyedButton(tester, kLimousineRequestAddStopKey);
    await tester.pump();
    expect(find.byKey(limousineAddressFieldKey('stop_0')), findsOneWidget);
    expect(find.byKey(limousineRequestRemoveStopKey(0)), findsOneWidget);
    expect(find.text(kLimousineGapStop.nl), findsOneWidget);
    tester
        .widget<IconButton>(find.byKey(limousineRequestRemoveStopKey(0)))
        .onPressed!();
    await tester.pump();
    expect(find.byKey(limousineAddressFieldKey('stop_0')), findsNothing);
    controller.dispose();
    lookup.dispose();
  });

  testWidgets(
    'phone, tablet and large text host the journey without overflow',
    (tester) async {
      final gateway = _FakeGateway();
      final lookup = _Lookup();
      final controller = LimousineCustomerQuoteController(gateway: gateway);
      await tester.pumpWidget(
        _app(
          LimousineCustomerQuotePage(
            controller: controller,
            gateway: gateway,
            placeLookup: lookup,
            entryEnabled: true,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(kLimousineCustomerPhoneLayoutKey), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: kLimousineSmX400Portrait,
              textScaler: TextScaler.linear(1.3),
            ),
            child: LimousineCustomerQuotePage(
              controller: controller,
              gateway: gateway,
              placeLookup: lookup,
              entryEnabled: true,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(kLimousineCustomerTabletLayoutKey), findsOneWidget);
      expect(tester.takeException(), isNull);
      controller.dispose();
      lookup.dispose();
    },
  );

  testWidgets('all customer themes render the wizard', (tester) async {
    final gateway = _FakeGateway();
    final lookup = _Lookup();
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    for (final variant in CustomerThemeVariant.values) {
      customerThemeNotifier.value = variant;
      await tester.pumpWidget(
        _app(
          LimousineCustomerQuotePage(
            controller: controller,
            gateway: gateway,
            placeLookup: lookup,
            entryEnabled: true,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(kLimousineRequestWizardKey), findsOneWidget);
    }
    controller.dispose();
    lookup.dispose();
  });

  testWidgets('FR and ES use precise disabled Continue copy', (tester) async {
    final gateway = _FakeGateway();
    final lookup = _Lookup();
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    for (final language in const [AppLanguage.fr, AppLanguage.es]) {
      appLanguageNotifier.value = language;
      await tester.pumpWidget(
        _app(
          LimousineCustomerQuotePage(
            controller: controller,
            gateway: gateway,
            placeLookup: lookup,
            entryEnabled: true,
          ),
        ),
      );
      await tester.pump();
      expect(find.text(kLimousineRequestIncompleteHint.en), findsNothing);
      expect(
        find.text(limousineRequestGapLabel('pickup_required').of(language)),
        findsOneWidget,
      );
    }
    controller.dispose();
    lookup.dispose();
  });

  testWidgets('review submit never books and never shows raw ISO', (
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
    expect(find.textContaining('2026-09-01T10:00:00'), findsNothing);
    expect(find.text(kLimousineReviewQuoteOnRequest.nl), findsOneWidget);
    expect(find.text(kLimousineReviewNoPayment.nl), findsOneWidget);
    await tester.tap(find.byKey(kLimousineCustomerSubmitKey));
    await tester.pumpAndSettle();
    expect(gateway.createCalls, 1);
    expect(controller.request, isNull);
    final page = File(
      'lib/limousine/limousine_customer_quote_page.dart',
    ).readAsStringSync();
    final api = File(
      'lib/limousine/limousine_customer_quote_api.dart',
    ).readAsStringSync();
    expect(page.contains('/book'), isFalse);
    expect(api.contains('/limousine/quote-requests'), isTrue);
    expect(api.contains("Uri.parse('\$_base/book')"), isTrue);
    expect(page.toLowerCase().contains('taxi_price'), isFalse);
    controller.dispose();
  });
}
