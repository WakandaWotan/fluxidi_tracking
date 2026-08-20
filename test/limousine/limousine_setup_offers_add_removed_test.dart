import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_offer_binding.dart';
import 'package:fluxidi_tracking/limousine/limousine_offer_editor.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_simple_offer_editor.dart';

VehicleProfile _vehicle({
  required String id,
  required String name,
  String category = 'limousine',
  String classId = 'first_class_sedan',
  bool active = true,
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
    isActive: active,
    driverId: null,
    primaryPhotoRef: '',
    galleryPhotoRefs: const <String>[],
    serviceCategory: category,
    serviceClassId: classId,
  );
}

Map<String, dynamic> _quoteOffer({
  String id = 'off_quote',
  String vehicleId = '',
  String target = LimousineOfferTarget.serviceClass,
  String classId = 'first_class_sedan',
}) {
  return <String, dynamic>{
    'offer_id': id,
    'enabled': true,
    'published': true,
    'target_type': target,
    'vehicle_id': vehicleId,
    'vehicle_ids': vehicleId.isEmpty ? <String>[] : <String>[vehicleId],
    'applies_to_all_selected_vehicles': vehicleId.isEmpty,
    'service_class_id': classId,
    'price_presentation': LimousinePricePresentation.quoteRequired,
    'currency': 'EUR',
    'title': <String, String>{
      'nl': 'Prijs op aanvraag',
      'en': 'Quote',
      'fr': 'Devis',
      'es': 'Presupuesto',
    },
    'description': <String, String>{'nl': 'Beschrijving'},
    'hourly': <String, dynamic>{'enabled': false, 'currency': 'EUR'},
    'distance_time': <String, dynamic>{'enabled': false, 'currency': 'EUR'},
  };
}

Map<String, dynamic> _customOffer() {
  return <String, dynamic>{
    'offer_id': 'off_custom_night',
    'enabled': true,
    'published': true,
    'target_type': LimousineOfferTarget.serviceClass,
    'service_class_id': 'first_class_sedan',
    'price_presentation': LimousinePricePresentation.fromPrice,
    'display_amount_cents': 18000,
    'currency': 'EUR',
    'title': <String, String>{'nl': 'Nachtelijk maatwerk'},
    'description': <String, String>{'nl': 'Historisch extra aanbod'},
    'hourly': <String, dynamic>{'enabled': false, 'currency': 'EUR'},
    'distance_time': <String, dynamic>{
      'enabled': true,
      'currency': 'EUR',
      'base_fee_cents': 2500,
      'per_km_cents': 180,
      'per_minute_cents': 90,
    },
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
    180,
    scrollable: find
        .descendant(
          of: find.byKey(kLimousineBusinessSetupPageKey),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final limo = _vehicle(id: 'veh_limo', name: 'Cadillac');

  test('setup page no longer exposes the add-offer create entrypoint', () {
    final page = File(
      'lib/limousine/limousine_business_setup_page.dart',
    ).readAsStringSync();
    expect(page.contains('kLimousineBusinessSetupAddOffer'), isFalse);
    expect(page.contains('_editOffer()'), isFalse);
    expect(page.contains('Icons.add'), isFalse);
    expect(page.contains('LimousineOfferEditorDialog('), isTrue);
    expect(page.contains('_editOffer(index:'), isTrue);
  });

  test('stale vehicle ids stay on the offer until the user repairs them', () {
    final stale = _quoteOffer(
      vehicleId: 'gone_vh',
      target: LimousineOfferTarget.vehicle,
    );
    expect(
      limousineOfferMissingLinkedIds(
        offer: stale,
        vehicles: <VehicleProfile>[limo],
      ),
      <String>['gone_vh'],
    );
    expect(
      limousinePreparePublishOffers(
        <Map<String, dynamic>>[stale, _customOffer()],
        vehicles: <VehicleProfile>[limo],
        knownClassIds: const <String>['first_class_sedan'],
      ).map((offer) => offer['offer_id']).toList(),
      <String>['off_quote', 'off_custom_night'],
    );
    expect(
      limousinePreparePublishOffers(
        <Map<String, dynamic>>[stale],
        vehicles: <VehicleProfile>[limo],
        knownClassIds: const <String>['first_class_sedan'],
      ).single['published'],
      isFalse,
    );
    final repaired = limousineApplySimpleOfferEdits(
      stale,
      LimousineSimpleOfferDraft(
        mode: LimousineSimpleOfferMode.quote,
        enabled: true,
        vehicleIds: const <String>['veh_limo'],
        serviceClassId: 'first_class_sedan',
        appliesToAllSelected: false,
      ),
    );
    expect(repaired['offer_id'], 'off_quote');
    expect(repaired['vehicle_id'], 'veh_limo');
    expect(repaired['vehicle_ids'], <String>['veh_limo']);
  });

  test(
    'public price helpers stay available after the create-button removal',
    () {
      final data = buildLimousineProviderShowroomData(
        profile: <String, dynamic>{
          'partner_id': 'limo_1',
          'company_name': 'Maison Noire',
          'vehicles': <Map<String, dynamic>>[
            <String, dynamic>{
              'vehicle_id': 'veh_limo',
              'name': 'Cadillac',
              'service_category': 'limousine',
              'service_class': 'first_class_sedan',
              'is_active': true,
            },
          ],
          'limousine_offers': <Map<String, dynamic>>[_customOffer()],
        },
      );
      expect(data.vehicles, isNotEmpty);
      expect(
        limousineShowroomVehiclePriceLabel(data.vehicles.first, AppLanguage.nl),
        isNotEmpty,
      );
      expect(limousineCustomerQuoteCtaEnabled(), isFalse);
    },
  );

  testWidgets('add offer is gone, five models and advanced stay', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LimousineBusinessSetupPage(
          loadPricing: () async => <String, dynamic>{
            'limousine': <String, dynamic>{
              'offers': <dynamic>[_quoteOffer(), _customOffer()],
            },
          },
          savePricing: (_) async => <String, dynamic>{},
          vehicles: <VehicleProfile>[limo],
          knownClassIds: const <String>['first_class_sedan'],
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(kLimousineBusinessSetupOffersKey));
    expect(
      find.text(kLimousineBusinessSetupAddOffer.of(AppLanguage.nl)),
      findsNothing,
    );
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byType(LimousineOfferEditorDialog), findsNothing);
    expect(
      find.byKey(
        limousineBusinessSetupOfferCardKey(
          LimousinePricePresentation.quoteRequired,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        limousineBusinessSetupOfferCardKey(
          LimousinePricePresentation.fromPrice,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        limousineBusinessSetupOfferCardKey(
          LimousinePricePresentation.exactFixed,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        limousineBusinessSetupOfferCardKey(
          LimousineJourneyTypeId.hourlyPackage,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(limousineBusinessSetupOfferCardKey('package')),
      findsOneWidget,
    );
    expect(
      find.text(kLimousineBusinessSetupEdit.of(AppLanguage.nl)),
      findsWidgets,
    );
    expect(
      find.text(kLimousineBusinessSetupAdvanced.of(AppLanguage.nl)),
      findsOneWidget,
    );
  });

  testWidgets('existing custom offers stay and can still be edited', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LimousineBusinessSetupPage(
          loadPricing: () async => <String, dynamic>{
            'limousine': <String, dynamic>{
              'offers': <dynamic>[_quoteOffer(), _customOffer()],
            },
          },
          savePricing: (_) async => <String, dynamic>{},
          vehicles: <VehicleProfile>[limo],
          knownClassIds: const <String>['first_class_sedan'],
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(kLimousineBusinessSetupAdvancedKey));
    await tester.tap(find.byKey(kLimousineBusinessSetupAdvancedKey));
    await tester.pumpAndSettle();
    expect(find.text('Nachtelijk maatwerk'), findsOneWidget);
    expect(find.text('off_custom_night'), findsNothing);
    final editButtons = find.descendant(
      of: find.byKey(kLimousineBusinessSetupAdvancedKey),
      matching: find.text(kLimousineBusinessSetupEdit.of(AppLanguage.nl)),
    );
    expect(editButtons, findsWidgets);
    await tester.tap(editButtons.last);
    await tester.pumpAndSettle();
    expect(find.byType(LimousineOfferEditorDialog), findsOneWidget);
    expect(find.text('Nachtelijk maatwerk'), findsWidgets);
  });

  testWidgets(
    'stale vehicle reference can be repaired without deleting the offer',
    (tester) async {
      await tester.pumpWidget(
        _app(
          LimousineBusinessSetupPage(
            loadPricing: () async => <String, dynamic>{
              'limousine': <String, dynamic>{
                'offers': <dynamic>[
                  _quoteOffer(
                    vehicleId: 'gone_vh',
                    target: LimousineOfferTarget.vehicle,
                  ),
                  _customOffer(),
                ],
              },
            },
            savePricing: (_) async => <String, dynamic>{},
            vehicles: <VehicleProfile>[limo],
            knownClassIds: const <String>['first_class_sedan'],
            language: AppLanguage.nl,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _reveal(
        tester,
        find.byKey(
          limousineBusinessSetupOfferCardKey(
            LimousinePricePresentation.quoteRequired,
          ),
        ),
      );
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
      expect(find.text('Het gekozen voertuig bestaat niet.'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byKey(
            limousineBusinessSetupOfferCardKey(
              LimousinePricePresentation.quoteRequired,
            ),
          ),
          matching: find.text(kLimousineBusinessSetupEdit.of(AppLanguage.nl)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LimousineSimpleOfferEditor), findsOneWidget);
      expect(find.byType(LimousineOfferEditorDialog), findsNothing);
      expect(
        find.byKey(kLimousineSimpleOfferMissingVehicleKey),
        findsOneWidget,
      );
      expect(find.byKey(kLimousineSimpleOfferVehiclePickerKey), findsOneWidget);
      expect(
        find.byKey(limousineSimpleOfferVehicleTileKey('veh_limo')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(limousineSimpleOfferVehicleTileKey('veh_limo')),
      );
      await tester.pump();
      await tester.tap(
        find.text(kLimousineBusinessSetupSave.of(AppLanguage.nl)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LimousineSimpleOfferEditor), findsNothing);
      expect(find.text('Het gekozen voertuig bestaat niet.'), findsNothing);
      await _reveal(tester, find.byKey(kLimousineBusinessSetupAdvancedKey));
      await tester.tap(find.byKey(kLimousineBusinessSetupAdvancedKey));
      await tester.pumpAndSettle();
      expect(find.text('Nachtelijk maatwerk'), findsOneWidget);
      expect(find.text('Prijs op aanvraag'), findsWidgets);
    },
  );
}
