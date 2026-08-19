import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_simple_offer_editor.dart';

VehicleProfile _vehicle({
  required String id,
  required String name,
  String category = 'limousine',
  String classId = 'first_class_sedan',
}) {
  return VehicleProfile(
    id: id,
    vehicleName: name,
    brandModel: name,
    licensePlate: '1-ABC-123',
    color: 'black',
    passengerCapacity: 4,
    luggageCapacity: 2,
    tierId: 'comfort',
    isActive: true,
    driverId: null,
    primaryPhotoRef: '',
    galleryPhotoRefs: const <String>[],
    serviceCategory: category,
    serviceClassId: classId,
  );
}

final _limo = _vehicle(id: 'veh_limo', name: 'Cadillac');

Map<String, dynamic> _hourlyOffer({
  Object? first = 25000,
  Object? additional = 10000,
  Object? minimum = 60,
  Object? packageAmount,
  Object? packageDuration,
  String id = 'off_hourly',
  bool published = true,
}) {
  return <String, dynamic>{
    'offer_id': id,
    'enabled': true,
    'published': published,
    'target_type': LimousineOfferTarget.serviceClass,
    'service_class_id': 'first_class_sedan',
    'applies_to_all_selected_vehicles': true,
    'price_presentation': LimousinePricePresentation.fromPrice,
    'display_amount_cents': first,
    'currency': 'EUR',
    'title': <String, String>{'nl': 'Uurhuur'},
    'description': <String, String>{'nl': 'Beschrijving'},
    'hourly': <String, dynamic>{
      'enabled': true,
      'currency': 'EUR',
      'first_hour_cents': first,
      'additional_hour_cents': additional,
      'minimum_duration_minutes': minimum,
      if (packageAmount != null) 'package_amount_cents': packageAmount,
      if (packageDuration != null) 'package_duration_minutes': packageDuration,
    },
    'distance_time': <String, dynamic>{'enabled': false, 'currency': 'EUR'},
  };
}

Map<String, dynamic> _quoteOffer() {
  return <String, dynamic>{
    'offer_id': 'off_quote',
    'enabled': true,
    'published': true,
    'target_type': LimousineOfferTarget.serviceClass,
    'service_class_id': 'first_class_sedan',
    'applies_to_all_selected_vehicles': true,
    'price_presentation': LimousinePricePresentation.quoteRequired,
    'currency': 'EUR',
    'title': <String, String>{'nl': 'Prijs op aanvraag'},
    'description': <String, String>{'nl': 'Beschrijving'},
    'hourly': <String, dynamic>{'enabled': false, 'currency': 'EUR'},
    'distance_time': <String, dynamic>{'enabled': false, 'currency': 'EUR'},
  };
}

Widget _app(Widget child, {Size size = kLimousinePhonePortrait}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    220,
    scrollable: find
        .descendant(
          of: find.byKey(kLimousineBusinessSetupPageKey),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Finder _hourlyCard() => find.byKey(
  limousineBusinessSetupOfferCardKey(LimousineJourneyTypeId.hourlyPackage),
);

Finder _hourlyDot({required bool valid}) => find.descendant(
  of: _hourlyCard(),
  matching: find.byKey(
    limousineBusinessSetupOfferValidityKey(
      LimousineJourneyTypeId.hourlyPackage,
      valid: valid,
    ),
  ),
);

LimousineSimpleOfferValidation _hourlyValidation(Map<String, dynamic> offer) {
  return limousineValidateSimpleOffer(
    offer,
    mode: LimousineSimpleOfferMode.hourly,
    vehicles: <VehicleProfile>[_limo],
    knownClassIds: const <String>['first_class_sedan'],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('250.00 + 100.00 + 60 is valid hourly hire', () {
    final offer = _hourlyOffer();
    expect(_hourlyValidation(offer).isValid, isTrue);
    expect(_hourlyValidation(offer).errors, isEmpty);
    expect(
      limousineBusinessSetupOfferErrors(
        offer,
        mode: LimousineSimpleOfferMode.hourly,
        vehicles: <VehicleProfile>[_limo],
        knownClassIds: const <String>['first_class_sedan'],
      ),
      isEmpty,
    );
  });

  test('locale comma input normalizes to the same stored cents', () {
    final draft = limousineSimpleOfferDraft(
      presentation: limousineSimpleOfferPresentation(
        LimousineSimpleOfferMode.hourly,
      ),
      currency: 'EUR',
      serviceClassId: 'first_class_sedan',
      hourlyEnabled: true,
    );
    final next = limousineApplySimpleOfferEdits(
      draft,
      LimousineSimpleOfferDraft(
        mode: LimousineSimpleOfferMode.hourly,
        enabled: true,
        published: true,
        currency: 'EUR',
        serviceClassId: 'first_class_sedan',
        firstHourCents: limousineCentsFromMajorUnitText('250,00'),
        additionalHourCents: limousineCentsFromMajorUnitText('100,00'),
        minimumDurationMinutes: limousineMinutesOf('60,0'),
        appliesToAllSelected: true,
      ),
    );
    expect((next['hourly'] as Map)['first_hour_cents'], 25000);
    expect((next['hourly'] as Map)['additional_hour_cents'], 10000);
    expect((next['hourly'] as Map)['minimum_duration_minutes'], 60);
    expect(_hourlyValidation(next).isValid, isTrue);
  });

  test('empty first hour, extra hour or minimum each fail closed', () {
    expect(_hourlyValidation(_hourlyOffer(first: null)).isValid, isFalse);
    expect(
      _hourlyValidation(_hourlyOffer(first: null)).fieldErrors['first_hour'],
      LimousineOfferError.hourlyIncomplete,
    );
    expect(_hourlyValidation(_hourlyOffer(additional: null)).isValid, isFalse);
    expect(
      _hourlyValidation(
        _hourlyOffer(additional: null),
      ).fieldErrors['additional_hour'],
      LimousineOfferError.hourlyIncomplete,
    );
    expect(_hourlyValidation(_hourlyOffer(minimum: null)).isValid, isFalse);
    expect(
      _hourlyValidation(
        _hourlyOffer(minimum: null),
      ).fieldErrors['min_duration'],
      LimousineOfferError.hourlyMissingMinimumDuration,
    );
  });

  test('empty optional package fields do not invalidate hourly', () {
    final offer = _hourlyOffer();
    expect(
      (offer['hourly'] as Map).containsKey('package_amount_cents'),
      isFalse,
    );
    expect(_hourlyValidation(offer).isValid, isTrue);
    expect(
      _hourlyValidation(offer).errors,
      isNot(contains(LimousineOfferError.packageIncomplete)),
    );
  });

  test('publication uses the same simple-offer validation as the card', () {
    final valid = _hourlyOffer();
    final invalid = _hourlyOffer(first: null, additional: null, minimum: null);
    final vehicles = <VehicleProfile>[_limo];
    const classes = <String>['first_class_sedan'];
    expect(
      limousineBusinessSetupOfferErrors(
        valid,
        vehicles: vehicles,
        knownClassIds: classes,
      ),
      _hourlyValidation(valid).errors,
    );
    expect(
      limousineOfferIsValidPublished(
        valid,
        vehicles: vehicles,
        knownClassIds: classes,
      ),
      isTrue,
    );
    expect(
      limousinePreparePublishOffers(
        <Map<String, dynamic>>[valid, invalid],
        vehicles: vehicles,
        knownClassIds: classes,
      ).map((offer) => offer['published']),
      <bool>[true, false],
    );
  });

  Future<void> pumpSetup(
    WidgetTester tester, {
    required List<Map<String, dynamic>> offers,
    Size size = kLimousinePhonePortrait,
  }) async {
    await tester.pumpWidget(
      _app(
        LimousineBusinessSetupPage(
          loadPricing: () async => <String, dynamic>{
            'limousine': <String, dynamic>{'offers': offers},
          },
          savePricing: (_) async => <String, dynamic>{},
          vehicles: <VehicleProfile>[_limo],
          knownClassIds: const <String>['first_class_sedan'],
          language: AppLanguage.nl,
        ),
        size: size,
      ),
    );
    await tester.pumpAndSettle();
    await _reveal(tester, _hourlyCard());
  }

  testWidgets('green and red dots stay on the matching offer card', (
    tester,
  ) async {
    await pumpSetup(tester, offers: <Map<String, dynamic>>[_hourlyOffer()]);
    expect(_hourlyDot(valid: true), findsOneWidget);
    expect(_hourlyDot(valid: false), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(
          limousineBusinessSetupOfferCardKey(
            LimousinePricePresentation.quoteRequired,
          ),
        ),
        matching: find.byKey(
          limousineBusinessSetupOfferValidityKey(
            LimousinePricePresentation.quoteRequired,
            valid: false,
          ),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('invalid hourly is red on its card without a global error list', (
    tester,
  ) async {
    await pumpSetup(
      tester,
      offers: <Map<String, dynamic>>[
        _hourlyOffer(first: null, additional: null, minimum: null),
      ],
    );
    expect(_hourlyDot(valid: false), findsOneWidget);
    expect(find.text(kLimousineOfferHourlyIncompleteNl), findsNothing);
    expect(find.text('Uurhuur vereist een minimumduur.'), findsNothing);
    await tester.tap(
      find.descendant(
        of: _hourlyCard(),
        matching: find.text(kLimousineBusinessSetupEdit.of(AppLanguage.nl)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LimousineSimpleOfferEditor), findsOneWidget);
    expect(
      find.text('Vul het eerste uur en het bijkomende uur in.'),
      findsWidgets,
    );
    expect(find.text('Uurhuur vereist een minimumduur.'), findsOneWidget);
  });

  testWidgets(
    'successful save clears a stale hourly error and reopens values',
    (tester) async {
      await pumpSetup(
        tester,
        offers: <Map<String, dynamic>>[
          _hourlyOffer(first: null, additional: null, minimum: null),
        ],
      );
      expect(_hourlyDot(valid: false), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: _hourlyCard(),
          matching: find.text(kLimousineBusinessSetupEdit.of(AppLanguage.nl)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(kLimousineSimpleOfferFirstHourKey),
        '250.00',
      );
      await tester.enterText(
        find.byKey(kLimousineSimpleOfferExtraHourKey),
        '100.00',
      );
      await tester.enterText(
        find.byKey(kLimousineSimpleOfferMinDurationKey),
        '60',
      );
      await tester.tap(
        find.text(kLimousineBusinessSetupSave.of(AppLanguage.nl)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LimousineSimpleOfferEditor), findsNothing);
      expect(_hourlyDot(valid: true), findsOneWidget);
      expect(
        find.text('Vul het eerste uur en het bijkomende uur in.'),
        findsNothing,
      );
      expect(find.text('Uurhuur vereist een minimumduur.'), findsNothing);
      await tester.tap(
        find.descendant(
          of: _hourlyCard(),
          matching: find.text(kLimousineBusinessSetupEdit.of(AppLanguage.nl)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(kLimousineSimpleOfferFirstHourKey))
            .controller!
            .text,
        '250.00',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(kLimousineSimpleOfferExtraHourKey))
            .controller!
            .text,
        '100.00',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(kLimousineSimpleOfferMinDurationKey))
            .controller!
            .text,
        '60',
      );
    },
  );

  testWidgets('comma decimals save as the same hourly configuration', (
    tester,
  ) async {
    await pumpSetup(tester, offers: <Map<String, dynamic>>[]);
    await tester.tap(
      find.descendant(
        of: _hourlyCard(),
        matching: find.text(kLimousineBusinessSetupEdit.of(AppLanguage.nl)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(kLimousineSimpleOfferFirstHourKey),
      '250,00',
    );
    await tester.enterText(
      find.byKey(kLimousineSimpleOfferExtraHourKey),
      '100,00',
    );
    await tester.enterText(
      find.byKey(kLimousineSimpleOfferMinDurationKey),
      '60',
    );
    await tester.tap(find.text(kLimousineBusinessSetupSave.of(AppLanguage.nl)));
    await tester.pumpAndSettle();
    expect(_hourlyDot(valid: true), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: _hourlyCard(),
        matching: find.text(kLimousineBusinessSetupEdit.of(AppLanguage.nl)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(kLimousineSimpleOfferFirstHourKey))
          .controller!
          .text,
      '250.00',
    );
  });

  testWidgets(
    'leftover incomplete hourly offer does not keep a global banner',
    (tester) async {
      await pumpSetup(
        tester,
        offers: <Map<String, dynamic>>[
          _hourlyOffer(
            id: 'off_stale',
            first: null,
            additional: null,
            minimum: null,
            packageDuration: 180,
          ),
          _hourlyOffer(),
          _quoteOffer(),
        ],
      );
      expect(_hourlyDot(valid: true), findsOneWidget);
      expect(
        find.text('Vul het eerste uur en het bijkomende uur in.'),
        findsNothing,
      );
      expect(find.text('Uurhuur vereist een minimumduur.'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(
            limousineBusinessSetupOfferCardKey(
              LimousinePricePresentation.quoteRequired,
            ),
          ),
          matching: find.byKey(
            limousineBusinessSetupOfferValidityKey(
              LimousinePricePresentation.quoteRequired,
              valid: true,
            ),
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('phone and tablet hourly cards do not overflow', (tester) async {
    for (final size in <Size>[
      kLimousinePhonePortrait,
      kLimousineTabletLandscape,
    ]) {
      await pumpSetup(
        tester,
        offers: <Map<String, dynamic>>[_hourlyOffer(), _quoteOffer()],
        size: size,
      );
      expect(tester.takeException(), isNull);
    }
  });
}

const String kLimousineOfferHourlyIncompleteNl =
    'Vul het eerste uur en het bijkomende uur in.';
