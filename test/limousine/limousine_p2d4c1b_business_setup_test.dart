import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_offer_editor.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';

VehicleProfile _vehicle({
  required String id,
  required String name,
  String category = '',
  String classId = '',
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

Map<String, dynamic> _quoteOffer({
  bool published = false,
  bool enabled = true,
  String titleNl = 'Offerte',
}) {
  return <String, dynamic>{
    'offer_id': 'off_quote',
    'enabled': enabled,
    'published': published,
    'target_type': LimousineOfferTarget.serviceClass,
    'service_class_id': 'executive_sedan',
    'price_presentation': LimousinePricePresentation.quoteRequired,
    'currency': 'EUR',
    'title': <String, String>{
      'nl': titleNl,
      'en': 'Quote',
      'fr': 'Devis',
      'es': 'Presupuesto',
    },
    'description': <String, String>{
      'nl': 'Beschrijving',
      'en': 'Description',
      'fr': 'Description',
      'es': 'Descripción',
    },
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
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final taxi = _vehicle(id: 'veh_taxi', name: 'Tesla Model 3');
  final limo = _vehicle(
    id: 'veh_limo',
    name: 'Cadillac',
    category: 'limousine',
    classId: 'first_class_sedan',
  );

  test(
    'full-page route exists and settings no longer rely on the modal alone',
    () {
      final settings = File(
        'lib/business_settings_page.dart',
      ).readAsStringSync();
      expect(settings.contains('openLimousineBusinessSetup('), isTrue);
      expect(settings.contains('LimousineOfferEditorDialog('), isFalse);
      expect(settings.contains('kLimousineBusinessSetupOpenKey'), isTrue);
      final page = File(
        'lib/limousine/limousine_business_setup_page.dart',
      ).readAsStringSync();
      expect(page.contains('kLimousineBusinessSetupPageKey'), isTrue);
      expect(page.contains('AlertDialog'), isFalse);
      expect(
        File(
          'lib/limousine/limousine_offer_editor.dart',
        ).readAsStringSync().contains('_localizedMatrix'),
        isTrue,
      );
      expect(
        File(
          'lib/limousine/limousine_address_field.dart',
        ).readAsStringSync().contains('showCurrentLocation'),
        isTrue,
      );
    },
  );

  test('vehicle taxi and limousine isolation uses the committed category', () {
    expect(limousineVehicleAppearsInTaxiPreview(taxi), isTrue);
    expect(limousineVehicleAppearsInLimousinePreview(taxi), isFalse);
    expect(limousineVehicleAppearsInTaxiPreview(limo), isFalse);
    expect(limousineVehicleAppearsInLimousinePreview(limo), isTrue);
    expect(
      limousineSetupTaxiVehicles(<VehicleProfile>[taxi, limo]).single.id,
      'veh_taxi',
    );
    expect(
      limousineSetupLimousineVehicles(<VehicleProfile>[taxi, limo]).single.id,
      'veh_limo',
    );
  });

  test(
    'conditional hourly validation stays off until hourly hire is enabled',
    () {
      final quote = _quoteOffer();
      expect(
        limousineBusinessSetupOfferErrors(
          quote,
          knownClassIds: const <String>['executive_sedan'],
        ),
        isEmpty,
      );
      final hourly = <String, dynamic>{
        ...quote,
        'hourly': <String, dynamic>{'enabled': true, 'currency': 'EUR'},
      };
      expect(
        limousineBusinessSetupOfferErrors(
          hourly,
          knownClassIds: const <String>['executive_sedan'],
        ),
        contains(LimousineOfferError.hourlyIncomplete),
      );
    },
  );

  test('draft save may keep incomplete publication data unpublished', () {
    final draft = limousinePrepareDraftOffer(<String, dynamic>{
      'offer_id': 'off_1',
      'published': true,
      'target_type': LimousineOfferTarget.serviceClass,
      'service_class_id': 'executive_sedan',
      'price_presentation': LimousinePricePresentation.fromPrice,
      'currency': 'EUR',
    });
    expect(draft['published'], isFalse);
    expect(
      limousineBusinessSetupDraftSaveAllowed(dirty: true, saving: false),
      isTrue,
    );
    expect(
      limousineBusinessSetupDraftSaveAllowed(dirty: true, saving: true),
      isFalse,
    );
  });

  test('public preview never includes unpublished offers', () {
    final preview = limousineSafeSetupPreviewOffers(
      offers: <Map<String, dynamic>>[
        _quoteOffer(published: false),
        _quoteOffer(published: true)..['offer_id'] = 'off_live',
      ],
      vehicles: <VehicleProfile>[limo],
      knownClassIds: const <String>['executive_sedan', 'first_class_sedan'],
      sectionEnabled: true,
    );
    expect(preview.map((offer) => offer['offer_id']), <String>['off_live']);
    expect(
      limousinePreviewContainsUnpublished(preview, <Map<String, dynamic>>[
        _quoteOffer(published: false),
        _quoteOffer(published: true)..['offer_id'] = 'off_live',
      ]),
      isFalse,
    );
  });

  test('gates-off mapping never leaks raw backend text', () {
    expect(limousineLooksLikeRawException('Exception: not_found 404'), isTrue);
    expect(
      limousineBusinessSetupFriendlyStatus(
        gatesOff: true,
        language: AppLanguage.nl,
        raw: 'Exception: not_found',
      ),
      kLimousineGatesOffFriendly.of(AppLanguage.nl),
    );
    expect(
      limousineLooksLikeRawException(
        kLimousineGatesOffFriendly.of(AppLanguage.nl),
      ),
      isFalse,
    );
  });

  testWidgets('tablet and phone layouts host the full page', (tester) async {
    Future<Map<String, dynamic>> load() async => <String, dynamic>{
      'limousine': <String, dynamic>{'enabled': false, 'offers': <dynamic>[]},
    };
    await tester.pumpWidget(
      _app(
        LimousineBusinessSetupPage(
          loadPricing: load,
          savePricing: (_) async => <String, dynamic>{},
          vehicles: <VehicleProfile>[taxi, limo],
          knownClassIds: const <String>['executive_sedan', 'first_class_sedan'],
          language: AppLanguage.nl,
        ),
        size: kLimousineSmX400Portrait,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineBusinessSetupPageKey), findsOneWidget);
    expect(find.byKey(kLimousineBusinessSetupTabletLayoutKey), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(LimousineOfferEditorDialog), findsNothing);

    await tester.pumpWidget(
      _app(
        LimousineBusinessSetupPage(
          loadPricing: load,
          savePricing: (_) async => <String, dynamic>{},
          vehicles: <VehicleProfile>[taxi, limo],
          knownClassIds: const <String>['executive_sedan'],
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineBusinessSetupPhoneLayoutKey), findsOneWidget);
  });

  testWidgets('interface labels follow NL EN FR ES', (tester) async {
    Future<Map<String, dynamic>> load() async => <String, dynamic>{
      'limousine': <String, dynamic>{'offers': <dynamic>[]},
    };
    for (final language in const [
      AppLanguage.nl,
      AppLanguage.en,
      AppLanguage.fr,
      AppLanguage.es,
    ]) {
      await tester.pumpWidget(
        _app(
          LimousineBusinessSetupPage(
            loadPricing: load,
            savePricing: (_) async => <String, dynamic>{},
            vehicles: const <VehicleProfile>[],
            language: language,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(kLimousineBusinessSetupTitle.of(language)),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: find.byKey(kLimousineBusinessSetupDraftSaveKey),
          matching: find.text(kLimousineBusinessSetupDraftSave.of(language)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(kLimousineBusinessSetupPublishKey),
          matching: find.text(kLimousineBusinessSetupPublish.of(language)),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('public language tabs retain all values', (tester) async {
    await tester.pumpWidget(
      _app(
        LimousineBusinessSetupPage(
          loadPricing: () async => <String, dynamic>{
            'limousine': <String, dynamic>{'offers': <dynamic>[]},
          },
          savePricing: (_) async => <String, dynamic>{},
          vehicles: <VehicleProfile>[limo],
          knownClassIds: const <String>['executive_sedan', 'first_class_sedan'],
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _reveal(
      tester,
      find.byKey(limousineBusinessSetupPublicLangKey('nl')),
    );
    await tester.enterText(
      find.byKey(kLimousineBusinessSetupPublicTitleKey),
      'NL titel',
    );
    await tester.pump();
    await _reveal(
      tester,
      find.byKey(limousineBusinessSetupPublicLangKey('en')),
    );
    await tester.tap(find.byKey(limousineBusinessSetupPublicLangKey('en')));
    await tester.pump();
    await tester.enterText(
      find.byKey(kLimousineBusinessSetupPublicTitleKey),
      'EN title',
    );
    await tester.pump();
    await _reveal(
      tester,
      find.byKey(limousineBusinessSetupPublicLangKey('fr')),
    );
    await tester.tap(find.byKey(limousineBusinessSetupPublicLangKey('fr')));
    await tester.pump();
    await tester.enterText(
      find.byKey(kLimousineBusinessSetupPublicTitleKey),
      'Titre FR',
    );
    await tester.pump();
    await _reveal(
      tester,
      find.byKey(limousineBusinessSetupPublicLangKey('es')),
    );
    await tester.tap(find.byKey(limousineBusinessSetupPublicLangKey('es')));
    await tester.pump();
    await tester.enterText(
      find.byKey(kLimousineBusinessSetupPublicTitleKey),
      'Título ES',
    );
    await tester.pump();
    await _reveal(
      tester,
      find.byKey(limousineBusinessSetupPublicLangKey('nl')),
    );
    await tester.tap(find.byKey(limousineBusinessSetupPublicLangKey('nl')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(kLimousineBusinessSetupPublicTitleKey))
          .controller!
          .text,
      'NL titel',
    );
    await _reveal(
      tester,
      find.byKey(limousineBusinessSetupPublicLangKey('en')),
    );
    await tester.tap(find.byKey(limousineBusinessSetupPublicLangKey('en')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(kLimousineBusinessSetupPublicTitleKey))
          .controller!
          .text,
      'EN title',
    );
    await _reveal(
      tester,
      find.byKey(limousineBusinessSetupPublicLangKey('fr')),
    );
    await tester.tap(find.byKey(limousineBusinessSetupPublicLangKey('fr')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(kLimousineBusinessSetupPublicTitleKey))
          .controller!
          .text,
      'Titre FR',
    );
    await _reveal(
      tester,
      find.byKey(limousineBusinessSetupPublicLangKey('es')),
    );
    await tester.tap(find.byKey(limousineBusinessSetupPublicLangKey('es')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(kLimousineBusinessSetupPublicTitleKey))
          .controller!
          .text,
      'Título ES',
    );
  });

  testWidgets('preview keeps taxi-only vehicles out of Limousine', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LimousineBusinessSetupPage(
          loadPricing: () async => <String, dynamic>{
            'limousine': <String, dynamic>{
              'enabled': true,
              'offers': <dynamic>[_quoteOffer(published: true)],
            },
          },
          savePricing: (_) async => <String, dynamic>{},
          vehicles: <VehicleProfile>[taxi, limo],
          knownClassIds: const <String>['executive_sedan', 'first_class_sedan'],
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _reveal(
      tester,
      find.byKey(
        limousineBusinessSetupPreviewTabKey(
          LimousineBusinessSetupPreviewTab.limousine,
        ),
      ),
    );
    await tester.tap(
      find.byKey(
        limousineBusinessSetupPreviewTabKey(
          LimousineBusinessSetupPreviewTab.limousine,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Cadillac'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(kLimousineBusinessSetupPreviewKey),
        matching: find.text('Tesla Model 3'),
      ),
      findsNothing,
    );
    await _reveal(
      tester,
      find.byKey(
        limousineBusinessSetupPreviewTabKey(
          LimousineBusinessSetupPreviewTab.taxi,
        ),
      ),
    );
    await tester.tap(
      find.byKey(
        limousineBusinessSetupPreviewTabKey(
          LimousineBusinessSetupPreviewTab.taxi,
        ),
      ),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(kLimousineBusinessSetupPreviewKey),
        matching: find.text('Tesla Model 3'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(kLimousineBusinessSetupPreviewKey),
        matching: find.text('Cadillac'),
      ),
      findsNothing,
    );
  });

  testWidgets('simple cards stay visible and advanced stays collapsed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LimousineBusinessSetupPage(
          loadPricing: () async => <String, dynamic>{
            'limousine': <String, dynamic>{'offers': <dynamic>[]},
          },
          savePricing: (_) async => <String, dynamic>{},
          vehicles: <VehicleProfile>[limo],
          knownClassIds: const <String>['executive_sedan', 'first_class_sedan'],
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        limousineBusinessSetupOfferCardKey(
          LimousinePricePresentation.quoteRequired,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text(kLimousineBusinessSetupAdvanced.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(find.text('operating_base_address'), findsNothing);
  });

  testWidgets('draft save, dirty restore, double-save and stale completion', (
    tester,
  ) async {
    var saves = 0;
    final hold = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      _app(
        LimousineBusinessSetupPage(
          loadPricing: () async => <String, dynamic>{
            'limousine': <String, dynamic>{
              'offers': <dynamic>[_quoteOffer()],
            },
          },
          savePricing: (section) async {
            saves += 1;
            if (saves == 1) return hold.future;
            return <String, dynamic>{
              'limousine': <String, dynamic>{
                'source_revision': 2,
                'offers': section['offers'],
              },
            };
          },
          vehicles: <VehicleProfile>[limo],
          knownClassIds: const <String>['first_class_sedan', 'executive_sedan'],
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(kLimousineBusinessSetupPublicTitleKey));
    await tester.enterText(
      find.byKey(kLimousineBusinessSetupPublicTitleKey),
      'Nieuwe titel',
    );
    await tester.pump();
    expect(find.byKey(kLimousineBusinessSetupDirtyKey), findsOneWidget);
    final draft = find.byKey(kLimousineBusinessSetupDraftSaveKey);
    await tester.tap(draft);
    await tester.tap(draft);
    await tester.pump();
    expect(saves, 1);
    await tester.enterText(
      find.byKey(kLimousineBusinessSetupPublicTitleKey),
      'Nog nieuwer',
    );
    await tester.pump();
    hold.complete(<String, dynamic>{
      'limousine': <String, dynamic>{'source_revision': 1},
    });
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(kLimousineBusinessSetupPublicTitleKey))
          .controller!
          .text,
      'Nog nieuwer',
    );
    expect(find.byKey(kLimousineBusinessSetupDirtyKey), findsOneWidget);
    await tester.tap(draft);
    await tester.pumpAndSettle();
    expect(saves, 2);
    expect(find.byKey(kLimousineBusinessSetupDirtyKey), findsNothing);
    expect(
      find.text(kLimousineBusinessSetupDraftSaved.of(AppLanguage.nl)),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(kLimousineBusinessSetupPublicTitleKey),
      'Na opslaan',
    );
    await tester.pump();
    expect(find.byKey(kLimousineBusinessSetupDirtyKey), findsOneWidget);
  });

  testWidgets('gates-off save shows a calm message and no raw error', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LimousineBusinessSetupPage(
          loadPricing: () async => <String, dynamic>{
            'limousine': <String, dynamic>{
              'offers': <dynamic>[_quoteOffer()],
            },
          },
          savePricing: (_) async => throw Exception('not_found 404'),
          vehicles: <VehicleProfile>[limo],
          knownClassIds: const <String>['first_class_sedan', 'executive_sedan'],
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(kLimousineBusinessSetupPublicTitleKey));
    await tester.enterText(
      find.byKey(kLimousineBusinessSetupPublicTitleKey),
      'Draft',
    );
    await tester.pump();
    await tester.tap(find.byKey(kLimousineBusinessSetupDraftSaveKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineBusinessSetupErrorKey), findsOneWidget);
    expect(
      find.text(kLimousineGatesOffFriendly.of(AppLanguage.nl)),
      findsWidgets,
    );
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('404'), findsNothing);
    expect(find.textContaining('not_found'), findsNothing);
    expect(
      find.text(kLimousineBusinessSetupDraftSaved.of(AppLanguage.nl)),
      findsNothing,
    );
  });

  test('dark light blue and gold tokens keep readable contrast', () {
    for (final variant in kLimousineUxContrastVariants) {
      final palette = paletteForCustomerTheme(variant);
      final tokens = LimousineUxTokens.fromCustomer(palette);
      expect(
        limousineHasReadableContrast(tokens.onSurface, tokens.background),
        isTrue,
      );
      expect(
        limousineHasReadableContrast(tokens.onSurface, tokens.surface),
        isTrue,
      );
    }
    final gold = LimousineUxTokens.fromSurface(
      background: const Color(0xFF14110C),
      gold: const Color(0xFFC49A45),
    );
    expect(
      limousineHasReadableContrast(gold.onSurface, gold.background),
      isTrue,
    );
  });
}
