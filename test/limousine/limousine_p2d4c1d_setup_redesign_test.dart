import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_settings_page.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_entry.dart';
import 'package:fluxidi_tracking/limousine/limousine_offer_editor.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_simple_offer_editor.dart';

VehicleProfile _vehicle({
  required String id,
  required String name,
  String category = '',
  String classId = '',
  String photo = '',
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
    primaryPhotoRef: photo,
    galleryPhotoRefs: const <String>[],
    serviceCategory: category,
    serviceClassId: classId,
  );
}

Map<String, dynamic> _quoteOffer({
  bool published = false,
  bool enabled = true,
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
      'nl': 'Offerte',
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
    photo: 'assets/fluxidi/fluxidi_logo.png',
  );

  test('inline business settings keep one CTA and no old controls', () {
    final settings = File('lib/business_settings_page.dart').readAsStringSync();
    expect(settings.contains('openLimousineBusinessSetup('), isTrue);
    expect(settings.contains('kLimousineBusinessSetupOpenKey'), isTrue);
    expect(settings.contains('LimousineOfferEditorDialog('), isFalse);
    expect(settings.contains('Aanbod toevoegen'), isFalse);
    expect(settings.contains('Limousineaanbod actief'), isFalse);
  });

  test('quote on request does not require an amount', () {
    expect(
      limousineBusinessSetupOfferErrors(
        _quoteOffer(),
        knownClassIds: const <String>['executive_sedan'],
      ),
      isEmpty,
    );
  });

  test('disabled hourly mode does not block a draft', () {
    final offer = <String, dynamic>{
      ..._quoteOffer(),
      'hourly': <String, dynamic>{'enabled': false, 'currency': 'EUR'},
    };
    expect(limousinePrepareDraftOffer(offer)['published'], isFalse);
    expect(
      limousineBusinessSetupDraftSaveAllowed(dirty: true, saving: false),
      isTrue,
    );
  });

  test('simple quote edits keep the existing DTO and skip amounts', () {
    final next = limousineApplySimpleOfferEdits(
      _quoteOffer(),
      const LimousineSimpleOfferDraft(
        mode: LimousineSimpleOfferMode.quote,
        enabled: true,
        terms: 'Persoonlijke prijs',
        serviceClassId: 'executive_sedan',
      ),
    );
    expect(
      next['price_presentation'],
      LimousinePricePresentation.quoteRequired,
    );
    expect(next['display_amount_cents'], isNull);
    expect((next['description'] as Map)['nl'], 'Persoonlijke prijs');
  });

  test('primary public text falls back for missing translations', () {
    expect(
      limousineBusinessSetupTextFallback(
        <String, String>{'nl': 'Hoofdtitel', 'en': '', 'fr': '', 'es': ''},
        AppLanguage.en,
        primaryLang: 'nl',
      ),
      'Hoofdtitel',
    );
  });

  test('readiness uses real photo and live-status items', () {
    final ready = limousineBusinessSetupReadiness(
      vehicles: <VehicleProfile>[limo],
      offers: <Map<String, dynamic>>[_quoteOffer()],
      publicTitle: const <String, String>{'nl': 'Titel'},
      publicDescription: const <String, String>{'nl': 'Tekst'},
      knownClassIds: const <String>['first_class_sedan', 'executive_sedan'],
      entryEnabled: false,
      sectionEnabled: false,
    );
    expect(ready.items.map((item) => item.code), contains('public_photo'));
    expect(ready.items.map((item) => item.code), contains('live_status'));
    expect(
      ready.items.singleWhere((item) => item.code == 'public_photo').complete,
      isTrue,
    );
    expect(
      ready.items.singleWhere((item) => item.code == 'live_status').complete,
      isFalse,
    );
    expect(ready.progress, closeTo(0.8, 0.01));
  });

  test('taxi and limousine stay isolated', () {
    expect(limousineVehicleAppearsInTaxiPreview(taxi), isTrue);
    expect(limousineVehicleAppearsInLimousinePreview(taxi), isFalse);
    expect(limousineVehicleAppearsInLimousinePreview(limo), isTrue);
    expect(limousineVehicleAppearsInTaxiPreview(limo), isFalse);
  });

  test('unpublished and private fields stay out of preview', () {
    final preview = limousineSafeSetupPreviewOffers(
      offers: <Map<String, dynamic>>[
        _quoteOffer(published: false),
        <String, dynamic>{
          ..._quoteOffer(published: true),
          'offer_id': 'off_live',
          'mobilisation': <String, dynamic>{
            'operating_base_address': 'Geheimstraat 1',
            'method': 'included',
          },
        },
      ],
      vehicles: <VehicleProfile>[limo],
      knownClassIds: const <String>['executive_sedan', 'first_class_sedan'],
      sectionEnabled: true,
    );
    expect(preview.map((offer) => offer['offer_id']), <String>['off_live']);
    expect(preview.toString().contains('Geheimstraat'), isFalse);
    expect(preview.toString().contains('operating_base_address'), isFalse);
  });

  testWidgets('full route opens and old inline controls stay gone', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const BusinessSettingsPage(
          stepMode: true,
          initialFocus: 'limousine_offers_pricing',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(kLimousineBusinessSetupOpenKey), findsOneWidget);
    expect(find.text('Aanbod toevoegen'), findsNothing);
    expect(find.text('Vernieuwen'), findsNothing);
    tester
        .widget<ButtonStyleButton>(find.byKey(kLimousineBusinessSetupOpenKey))
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(kLimousineBusinessSetupPageKey), findsOneWidget);
    expect(find.byType(LimousineOfferEditorDialog), findsNothing);
  });

  testWidgets('phone and tablet host the rebuilt page', (tester) async {
    Future<Map<String, dynamic>> load() async => <String, dynamic>{
      'limousine': <String, dynamic>{'offers': <dynamic>[]},
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
    expect(find.byKey(kLimousineBusinessSetupTabletLayoutKey), findsOneWidget);
    expect(
      find.byKey(limousineBusinessSetupVehiclePhotoKey(limo.id)),
      findsOneWidget,
    );
    expect(find.text('4'), findsWidgets);
    expect(find.text('2'), findsWidgets);
    await tester.pumpWidget(
      _app(
        LimousineBusinessSetupPage(
          loadPricing: load,
          savePricing: (_) async => <String, dynamic>{},
          vehicles: <VehicleProfile>[limo],
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineBusinessSetupPhoneLayoutKey), findsOneWidget);
  });

  testWidgets('business themes keep the setup chrome readable', (tester) async {
    for (final variant in BusinessThemeVariant.values) {
      businessThemeNotifier.value = variant;
      await tester.pumpWidget(
        _app(
          LimousineBusinessSetupPage(
            loadPricing: () async => <String, dynamic>{
              'limousine': <String, dynamic>{'offers': <dynamic>[]},
            },
            savePricing: (_) async => <String, dynamic>{},
            vehicles: <VehicleProfile>[limo],
            language: AppLanguage.nl,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(kLimousineBusinessSetupPageKey), findsOneWidget);
    }
    businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
    for (final variant in kLimousineUxContrastVariants) {
      final tokens = LimousineUxTokens.fromCustomer(
        paletteForCustomerTheme(variant),
      );
      expect(
        limousineHasReadableContrast(tokens.onSurface, tokens.background),
        isTrue,
      );
    }
  });

  testWidgets('NL EN FR ES chrome stays translated', (tester) async {
    for (final language in const [
      AppLanguage.nl,
      AppLanguage.en,
      AppLanguage.fr,
      AppLanguage.es,
    ]) {
      await tester.pumpWidget(
        _app(
          LimousineBusinessSetupPage(
            loadPricing: () async => <String, dynamic>{
              'limousine': <String, dynamic>{'offers': <dynamic>[]},
            },
            savePricing: (_) async => <String, dynamic>{},
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
        find.text(kLimousineBusinessSetupDraftSave.of(language)),
        findsOneWidget,
      );
      expect(
        find.text(kLimousineBusinessSetupPublish.of(language)),
        findsOneWidget,
      );
    }
  });

  testWidgets('quote card opens the simple editor, not the full dialog', (
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
          knownClassIds: const <String>['first_class_sedan', 'executive_sedan'],
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final quoteCard = find.byKey(
      limousineBusinessSetupOfferCardKey(
        LimousinePricePresentation.quoteRequired,
      ),
    );
    await _reveal(tester, quoteCard);
    tester
        .widget<InkWell>(
          find.descendant(of: quoteCard, matching: find.byType(InkWell)),
        )
        .onTap!();
    await tester.pumpAndSettle();
    expect(find.byType(LimousineSimpleOfferEditor), findsOneWidget);
    expect(find.byType(LimousineOfferEditorDialog), findsNothing);
    expect(find.byKey(kLimousineSimpleOfferAmountKey), findsNothing);
    expect(find.byKey(kLimousineSimpleOfferEnabledKey), findsOneWidget);
  });

  testWidgets('dirty, double-save and stale completion stay protected', (
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
    await tester.tap(draft);
    await tester.pumpAndSettle();
    expect(saves, 2);
    expect(find.byKey(kLimousineBusinessSetupDirtyKey), findsNothing);
    await tester.enterText(
      find.byKey(kLimousineBusinessSetupPublicTitleKey),
      'Na opslaan',
    );
    await tester.pump();
    expect(find.byKey(kLimousineBusinessSetupDirtyKey), findsOneWidget);
  });

  testWidgets('gates-off stays calm and does not claim publication success', (
    tester,
  ) async {
    expect(LimousineCustomerEntryContract.isVisible, isFalse);
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
    expect(find.byKey(kLimousineBusinessSetupTestBadgeKey), findsOneWidget);
    await _reveal(tester, find.byKey(kLimousineBusinessSetupPublicTitleKey));
    await tester.enterText(
      find.byKey(kLimousineBusinessSetupPublicTitleKey),
      'Draft',
    );
    await tester.pump();
    await tester.tap(find.byKey(kLimousineBusinessSetupDraftSaveKey));
    await tester.pumpAndSettle();
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
    expect(
      find.text(kLimousineBusinessSetupPublishedLocal.of(AppLanguage.nl)),
      findsNothing,
    );
  });
}
