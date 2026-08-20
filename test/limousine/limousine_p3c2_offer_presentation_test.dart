import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_offer_binding.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_pricing_overlay.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_offer_card.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_simple_offer_editor.dart';
import 'package:fluxidi_tracking/limousine/limousine_unified_intent.dart';

VehicleProfile _vehicle(String id, {String name = 'Party Limo'}) {
  return VehicleProfile(
    id: id,
    vehicleName: name,
    brandModel: name,
    licensePlate: 'TEST-$id',
    color: 'white',
    passengerCapacity: 8,
    luggageCapacity: 4,
    tierId: 'limousine',
    isActive: true,
    driverId: null,
    companyId: 'company_a',
    primaryPhotoRef: '',
    galleryPhotoRefs: const <String>[],
    publicPhotoUrl: 'https://cdn.example/$id.jpg',
    serviceCategory: 'limousine',
    serviceClassId: 'party_stretch',
  );
}

Map<String, dynamic> _offer({
  required String id,
  String presentation = LimousinePricePresentation.fromPrice,
  List<String> vehicleIds = const <String>[],
  bool appliesToAll = false,
  bool featured = false,
  Object? sortOrder,
  bool published = true,
  bool enabled = true,
  int amount = 25000,
  String title = 'Aanbod',
  Map<String, dynamic>? hourly,
  String tenant = 'tenant_a',
  String company = 'company_a',
}) {
  return <String, dynamic>{
    'offer_id': id,
    'tenant_id': tenant,
    'company_id': company,
    'partner_id': 'company:$tenant:$company',
    'enabled': enabled,
    'published': published,
    'target_type': (appliesToAll || vehicleIds.isEmpty)
        ? LimousineOfferTarget.serviceClass
        : LimousineOfferTarget.vehicle,
    'service_class_id': 'party_stretch',
    'vehicle_id': vehicleIds.isEmpty ? '' : vehicleIds.first,
    'vehicle_ids': vehicleIds,
    'applies_to_all_selected_vehicles': appliesToAll || vehicleIds.isEmpty,
    'featured': featured,
    'sort_order': sortOrder,
    'price_presentation': presentation,
    'display_amount_cents': amount,
    'currency': 'EUR',
    'journey_types': <String>['point_to_point'],
    'mobilisation': <String, dynamic>{'method': 'included'},
    'title': <String, String>{
      'nl': title,
      'en': title,
      'fr': title,
      'es': title,
    },
    'description': <String, String>{
      'nl': 'Beschrijving $title',
      'en': 'Description $title',
      'fr': 'Description $title',
      'es': 'Descripción $title',
    },
    if (hourly != null) 'hourly': hourly,
  };
}

LimousinePublishedOffer _pub(Map<String, dynamic> map) =>
    LimousinePublishedOffer.fromJson(map);

List<VehicleProfile> get _fleet => <VehicleProfile>[
  _vehicle('vh_party', name: 'Party Limo'),
  _vehicle('vh_hummer', name: 'Hummer white'),
];

void main() {
  test('1 default sort input is automatic, never 0', () {
    final parsed = parseLimousinePublicSortOrderInput('');
    expect(parsed.isAutomatic, isTrue);
    expect(parsed.value, isNull);
    expect(limousinePublicSortOrderOf(0), isNull);
    expect(limousinePublicSortOrderOf(null), isNull);
    expect(limousineOfferScopeOf(_offer(id: 'a', sortOrder: 0)).sortOrder, isNull);
    expect(
      kLimousineBusinessSetupOfferSortOrderAutomatic.of(AppLanguage.nl),
      'Automatisch',
    );
  });

  test('2 rejects 0, negative, decimal and text', () {
    expect(parseLimousinePublicSortOrderInput('0').isValid, isFalse);
    expect(parseLimousinePublicSortOrderInput('-1').isValid, isFalse);
    expect(parseLimousinePublicSortOrderInput('1.5').isValid, isFalse);
    expect(parseLimousinePublicSortOrderInput('abc').isValid, isFalse);
    expect(parseLimousinePublicSortOrderInput('01').isValid, isFalse);
    expect(parseLimousinePublicSortOrderInput('1').value, 1);
    expect(parseLimousinePublicSortOrderInput('3').value, 3);
  });

  test('3 public order 1,2,3 is applied', () {
    final ranked = limousineSortPublishedOffers([
      _pub(_offer(id: 'c', sortOrder: 3, title: 'Derde')),
      _pub(_offer(id: 'a', sortOrder: 1, title: 'Eerste')),
      _pub(_offer(id: 'b', sortOrder: 2, title: 'Tweede')),
    ]);
    expect(ranked.map((o) => o.offerId).toList(), <String>['a', 'b', 'c']);
  });

  test('4 equal values keep stable incoming order', () {
    final ranked = limousineSortPublishedOffers([
      _pub(_offer(id: 'first', sortOrder: 1)),
      _pub(_offer(id: 'second', sortOrder: 1)),
      _pub(_offer(id: 'third', sortOrder: 1)),
    ]);
    expect(ranked.map((o) => o.offerId).toList(), <String>[
      'first',
      'second',
      'third',
    ]);
  });

  test('5 automatic offers come after explicit values', () {
    final ranked = limousineSortPublishedOffers([
      _pub(_offer(id: 'auto_a')),
      _pub(_offer(id: 'two', sortOrder: 2)),
      _pub(_offer(id: 'auto_b')),
      _pub(_offer(id: 'one', sortOrder: 1)),
    ]);
    expect(ranked.map((o) => o.offerId).toList(), <String>[
      'one',
      'two',
      'auto_a',
      'auto_b',
    ]);
  });

  testWidgets('6 featured shows Aanbevolen badge', (tester) async {
    final offer = _pub(_offer(id: 'feat', featured: true, title: 'VIP'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LimousinePublicOfferCard(
            offer: offer,
            language: AppLanguage.nl,
            tokens: LimousineUxTokens.fromSurface(
              background: const Color(0xFFFFFFFF),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(limousineRecommendedBadgeKey('feat')), findsOneWidget);
    expect(find.text('Aanbevolen'), findsOneWidget);
  });

  test('7 featured does not change public order', () {
    final ranked = limousineSortPublishedOffers([
      _pub(_offer(id: 'plain', sortOrder: 1, featured: false)),
      _pub(_offer(id: 'star', sortOrder: 2, featured: true)),
      _pub(_offer(id: 'auto', featured: true)),
    ]);
    expect(ranked.map((o) => o.offerId).toList(), <String>[
      'plain',
      'star',
      'auto',
    ]);
  });

  testWidgets('8 non-featured shows no badge', (tester) async {
    final offer = _pub(_offer(id: 'plain', featured: false, title: 'Standaard'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LimousinePublicOfferCard(
            offer: offer,
            language: AppLanguage.nl,
            tokens: LimousineUxTokens.fromSurface(
              background: const Color(0xFFFFFFFF),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(limousineRecommendedBadgeKey('plain')), findsNothing);
    expect(find.text('Aanbevolen'), findsNothing);
  });

  test('9 settings preview and customer view share sort + card rules', () {
    final working = <Map<String, dynamic>>[
      _offer(id: 'auto', published: true, enabled: true, title: 'Automatisch'),
      _offer(
        id: 'one',
        sortOrder: 1,
        featured: true,
        published: true,
        title: 'Eerste',
        amount: 31000,
      ),
    ];
    final preview = buildSafePublicLimousineOffers(
      working,
      eligible: true,
      vehicles: _fleet,
      knownClassIds: const <String>['party_stretch'],
      readiness: true,
    );
    expect(preview.map((o) => o['offer_id']).toList(), <String>['one', 'auto']);
    expect(preview.first['featured'], isTrue);
    final customer = collectLimousineShowroomOffers(<String, dynamic>{
      'partner_id': 'company:tenant_a:company_a',
      'limousine_available': true,
      'limousine_service_enabled': true,
      'limousine_offers': working,
    });
    expect(customer.map((o) => o.offerId).toList(), <String>['one', 'auto']);
    expect(limousinePublishedOfferScope(customer.first).featured, isTrue);
  });

  test('10 working edits do not leak before publish', () {
    final published = _offer(id: 'off_1', sortOrder: 2, featured: false);
    final working = limousineApplySimpleOfferEdits(
      published,
      LimousineSimpleOfferDraft(
        mode: LimousineSimpleOfferMode.fromPrice,
        enabled: true,
        published: false,
        amountCents: 99000,
        appliesToAllSelected: true,
        featured: true,
        sortOrder: 1,
        title: 'Concept',
      ),
    );
    expect(working['published'], isFalse);
    expect(working['featured'], isTrue);
    expect(working['sort_order'], 1);
    final preview = buildSafePublicLimousineOffers(
      <Map<String, dynamic>>[working],
      eligible: true,
      vehicles: _fleet,
      knownClassIds: const <String>['party_stretch'],
      readiness: true,
    );
    expect(preview, isEmpty);
    final live = collectLimousineShowroomOffers(<String, dynamic>{
      'limousine_available': true,
      'limousine_offers': <Map<String, dynamic>>[published],
    });
    expect(live.single.offerId, 'off_1');
    expect(limousinePublishedOfferScope(live.single).sortOrder, 2);
    expect(limousinePublishedOfferScope(live.single).featured, isFalse);
  });

  test('11 published values survive overlay reopen', () {
    final published = _offer(
      id: 'off_keep',
      sortOrder: 3,
      featured: true,
      title: 'Gepubliceerd',
    );
    final overlay = <String, dynamic>{
      kLimousinePublishedOffersOverlayKey: <Map<String, dynamic>>[published],
    };
    final hydrated = limousineHydratePublicPartnerOverlay(
      <String, dynamic>{
        'partner_id': 'company:tenant_a:company_a',
        'limousine_available': true,
        'limousine_offers': <Map<String, dynamic>>[
          _offer(id: 'off_keep', sortOrder: 3, featured: true),
        ],
      },
    );
    final offers = collectLimousineShowroomOffers(hydrated);
    expect(offers, isNotEmpty);
    final stored = List<Map<String, dynamic>>.from(
      overlay[kLimousinePublishedOffersOverlayKey] as List,
    );
    expect(limousineOfferScopeOf(stored.first).sortOrder, 3);
    expect(limousinePublishedOfferScope(offers.single).sortOrder, 3);
    expect(limousinePublishedOfferScope(offers.single).featured, isTrue);
  });

  test('12 fresh customer context reads backend value without local overlay', () {
    final backend = <String, dynamic>{
      'partner_id': 'company:tenant_a:company_a',
      'limousine_available': true,
      'limousine_service_enabled': true,
      'limousine_offers': <Map<String, dynamic>>[
        _offer(id: 'backend_one', sortOrder: 1, featured: true, title: 'Backend een'),
        _offer(id: 'backend_auto', title: 'Backend auto', amount: 18000),
      ],
    };
    final offers = collectLimousineShowroomOffers(backend);
    expect(offers.map((o) => o.offerId).toList(), <String>[
      'backend_one',
      'backend_auto',
    ]);
    expect(limousinePublishedOfferScope(offers.first).sortOrder, 1);
    expect(limousinePublishedOfferScope(offers.first).featured, isTrue);
  });

  test('13 offer_id appears at most once per public list', () {
    final ranked = limousineRankPublicOffers([
      _pub(_offer(id: 'off_dup', vehicleIds: const <String>['vh_party'])),
      _pub(_offer(id: 'off_dup', vehicleIds: const <String>['vh_party'])),
    ]);
    expect(ranked.map((o) => o.offerId).toList(), <String>['off_dup']);
  });

  test('14 all-selected vs vehicle_ids, Party Limo and Hummer stay unique', () {
    final offers = <LimousinePublishedOffer>[
      _pub(
        _offer(
          id: 'off_all',
          appliesToAll: true,
          sortOrder: 2,
          title: 'Alle limousines',
          amount: 18000,
        ),
      ),
      _pub(
        _offer(
          id: 'off_party',
          vehicleIds: const <String>['vh_party'],
          sortOrder: 1,
          title: 'Party Limo rit',
          amount: 25000,
        ),
      ),
      _pub(
        _offer(
          id: 'off_hummer',
          vehicleIds: const <String>['vh_hummer'],
          title: 'Hummer white rit',
          amount: 32000,
        ),
      ),
    ];
    final data = buildLimousineProviderShowroomData(
      profile: <String, dynamic>{
        'partner_id': 'company:tenant_a:company_a',
        'company_name': 'Maison',
        'limousine_available': true,
        'vehicles': <Map<String, dynamic>>[
          <String, dynamic>{
            'vehicle_id': 'vh_party',
            'name': 'Party Limo',
            'service_category': 'limousine',
            'service_class': 'party_stretch',
            'pax': 8,
            'is_active': true,
            'photo_url': 'https://cdn.example/party.jpg',
          },
          <String, dynamic>{
            'vehicle_id': 'vh_hummer',
            'name': 'Hummer white',
            'service_category': 'limousine',
            'service_class': 'party_stretch',
            'pax': 8,
            'is_active': true,
            'photo_url': 'https://cdn.example/hummer.jpg',
          },
        ],
        'limousine_offers': [
          for (final offer in offers) offer.raw,
        ],
      },
    );
    final party = data.vehicles.firstWhere((v) => v.vehicleId == 'vh_party');
    final hummer = data.vehicles.firstWhere((v) => v.vehicleId == 'vh_hummer');
    expect(party.offers.map((o) => o.offerId).toList(), <String>[
      'off_party',
      'off_all',
    ]);
    expect(hummer.offers.map((o) => o.offerId).toList(), <String>[
      'off_all',
      'off_hummer',
    ]);
    expect(party.offers.map((o) => o.offerId).toSet().length, party.offers.length);
    expect(hummer.offers.map((o) => o.offerId).toSet().length, hummer.offers.length);
  });

  test('15 five price modes keep CTA and intent_kind', () {
    final quote = _pub(
      _offer(id: 'q', presentation: LimousinePricePresentation.quoteRequired),
    );
    final from = _pub(
      _offer(id: 'f', presentation: LimousinePricePresentation.fromPrice),
    );
    final fixed = _pub(
      _offer(id: 'x', presentation: LimousinePricePresentation.exactFixed),
    );
    final hourly = _pub(
      _offer(
        id: 'h',
        presentation: LimousinePricePresentation.fromPrice,
        featured: true,
        sortOrder: 1,
        hourly: <String, dynamic>{
          'enabled': true,
          'first_hour_cents': 12500,
          'minimum_duration_minutes': 180,
        },
      ),
    );
    final package = _pub(
      _offer(
        id: 'p',
        presentation: LimousinePricePresentation.exactFixed,
        featured: true,
        hourly: <String, dynamic>{
          'enabled': true,
          'package_amount_cents': 65000,
          'package_duration_minutes': 240,
        },
      ),
    );
    expect(limousineCustomerIntentKindOf(quote), LimousineCustomerIntentKind.quoteRequest);
    expect(limousineCustomerIntentKindOf(from), LimousineCustomerIntentKind.quoteRequest);
    expect(limousineCustomerIntentKindOf(fixed), LimousineCustomerIntentKind.bookingRequest);
    expect(limousineCustomerIntentKindOf(hourly), LimousineCustomerIntentKind.bookingRequest);
    expect(limousineCustomerIntentKindOf(package), LimousineCustomerIntentKind.bookingRequest);
    expect(limousineShowroomCtaFor(quote), LimousineShowroomCta.requestQuote);
    expect(limousineShowroomCtaFor(from), LimousineShowroomCta.requestQuote);
    expect(limousineShowroomCtaFor(fixed), LimousineShowroomCta.book);
    expect(limousineShowroomCtaFor(hourly), LimousineShowroomCta.book);
    expect(limousineShowroomCtaFor(package), LimousineShowroomCta.book);
    expect(
      limousineDiscoveryPriceFromOffers(<Map<String, dynamic>>[
        package.raw,
        from.raw,
      ]).kind,
      LimousineDiscoveryPriceKind.fromPrice,
    );
  });

  test('16 taxi/airport/street isolation and unavailable stay off public lists', () {
    final public = collectLimousineShowroomOffers(<String, dynamic>{
      'limousine_available': true,
      'limousine_offers': <Map<String, dynamic>>[
        _offer(id: 'live', sortOrder: 1),
        _offer(
          id: 'gone',
          presentation: LimousinePricePresentation.unavailable,
        ),
        _offer(id: 'off', enabled: false, sortOrder: 1),
        _offer(id: 'draft', published: false, featured: true),
      ],
    });
    expect(public.map((o) => o.offerId).toList(), <String>['live']);
    expect(limousineCustomerIntentKindOf(public.single).name.contains('street'), isFalse);
  });

  test('17 tenant/company isolation', () {
    final foreign = collectLimousineShowroomOffers(<String, dynamic>{
      'partner_id': 'company:tenant_b:company_b',
      'limousine_available': true,
      'limousine_offers': <Map<String, dynamic>>[
        _offer(
          id: 'foreign',
          tenant: 'tenant_b',
          company: 'company_b',
          sortOrder: 1,
        ),
      ],
    });
    final home = collectLimousineShowroomOffers(<String, dynamic>{
      'partner_id': 'company:tenant_a:company_a',
      'limousine_available': true,
      'limousine_offers': <Map<String, dynamic>>[
        _offer(id: 'home', sortOrder: 2),
      ],
    });
    expect(home.single.offerId, 'home');
    expect(foreign.single.offerId, 'foreign');
    expect(home.single.raw['tenant_id'], 'tenant_a');
    expect(foreign.single.raw['tenant_id'], 'tenant_b');
  });

  test('18 NL/EN/FR/DE labels and helper texts', () {
    for (final lang in <AppLanguage>[
      AppLanguage.nl,
      AppLanguage.en,
      AppLanguage.fr,
      AppLanguage.de,
    ]) {
      expect(kLimousineBusinessSetupOfferFeatured.of(lang), isNotEmpty);
      expect(kLimousineBusinessSetupOfferSortOrder.of(lang), isNotEmpty);
      expect(kLimousineBusinessSetupOfferSortOrderAutomatic.of(lang), isNotEmpty);
      expect(kLimousineBusinessSetupOfferSortOrderHelper.of(lang), isNotEmpty);
      expect(kLimousineOfferRecommendedBadge.of(lang), isNotEmpty);
      expect(
        kLimousineBusinessSetupOfferSortOrderAutomatic.of(lang).toLowerCase(),
        isNot(contains('0')),
      );
    }
    expect(kLimousineOfferRecommendedBadge.of(AppLanguage.nl), 'Aanbevolen');
    expect(kLimousineOfferRecommendedBadge.of(AppLanguage.en), 'Recommended');
    expect(kLimousineOfferRecommendedBadge.of(AppLanguage.fr), 'Recommandé');
    expect(kLimousineOfferRecommendedBadge.of(AppLanguage.de), 'Empfohlen');
    expect(
      kLimousineBusinessSetupOfferSortOrderHelper.of(AppLanguage.nl),
      contains('lager nummer'),
    );
  });

  testWidgets('editor defaults to Automatisch and rejects invalid sort input', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: LimousineSimpleOfferEditor(
          initialOffer: _offer(id: 'edit', sortOrder: null, amount: 25000),
          mode: LimousineSimpleOfferMode.fromPrice,
          vehicles: _fleet,
          knownClassIds: const <String>['party_stretch'],
          currency: 'EUR',
          language: AppLanguage.nl,
          tokens: LimousineUxTokens.fromSurface(
            background: const Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(kLimousineSimpleOfferSortOrderFieldKey),
    );
    expect(field.controller!.text, isEmpty);
    expect(field.decoration!.hintText, 'Automatisch');
    expect(
      find.byKey(kLimousineSimpleOfferSortOrderHelperKey),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(kLimousineSimpleOfferSortOrderFieldKey),
      '0',
    );
    await tester.tap(find.text(kLimousineBusinessSetupSave.of(AppLanguage.nl)));
    await tester.pump();
    expect(
      find.text(kLimousineBusinessSetupOfferSortOrderInvalid.of(AppLanguage.nl)),
      findsWidgets,
    );
    await tester.enterText(
      find.byKey(kLimousineSimpleOfferSortOrderFieldKey),
      'abc',
    );
    await tester.tap(find.text(kLimousineBusinessSetupSave.of(AppLanguage.nl)));
    await tester.pump();
    expect(
      find.text(kLimousineBusinessSetupOfferSortOrderInvalid.of(AppLanguage.nl)),
      findsWidgets,
    );
  });
}
