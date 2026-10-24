import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_pricing_local_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_detail_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_public_copy.dart';

final Uint8List _kTinyPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

const String _kPartyId = 'vh_party';
const String _kHummerId = 'vh_hummer';
const String _kPartyNl = 'Party Limo voor een avond uit.';
const String _kPartyEn = 'Party Limo for a night out.';
const String _kHummerNl = 'Hummer white voor een opvallende aankomst.';
const String _kPartnerId = 'limo_1';

VehicleProfile _fleetVehicle({
  required String id,
  required String name,
  String classId = 'stretch_limousine',
}) {
  return VehicleProfile(
    id: id,
    vehicleName: name,
    brandModel: name,
    licensePlate: '1-ABC-123',
    color: 'white',
    passengerCapacity: 16,
    luggageCapacity: 3,
    tierId: 'premium',
    isActive: true,
    driverId: null,
    primaryPhotoRef: 'https://cdn.example/$id.jpg',
    galleryPhotoRefs: const <String>[],
    publicPhotoUrl: 'https://cdn.example/$id.jpg',
    serviceCategory: 'limousine',
    serviceClassId: classId,
  );
}

Map<String, dynamic> _publishedOffer() {
  return <String, dynamic>{
    'offer_id': 'off_1',
    'enabled': true,
    'published': true,
    'target_type': LimousineOfferTarget.serviceClass,
    'service_class_id': 'stretch_limousine',
    'price_presentation': LimousinePricePresentation.fromPrice,
    'display_amount_cents': 25000,
    'currency': 'EUR',
    'title': <String, String>{
      'nl': 'Avond',
      'en': 'Evening',
      'fr': 'Soiree',
      'es': 'Noche',
    },
    'description': <String, String>{
      'nl': 'Avondrit',
      'en': 'Evening ride',
      'fr': 'Soiree',
      'es': 'Noche',
    },
  };
}

Map<String, dynamic> _serverSection({
  bool enabled = true,
  int revision = 1,
  Map<String, dynamic>? extra,
}) {
  return <String, dynamic>{
    'limousine': <String, dynamic>{
      'enabled': enabled,
      'source_revision': revision,
      'offers': <Map<String, dynamic>>[_publishedOffer()],
      ...?extra,
    },
  };
}

Map<String, dynamic> _stripCopy(Map<String, dynamic> section) {
  return limousineStripVehiclePublicCopyKeys(section);
}

Widget _app(Widget child, {Size size = kLimousineTabletLandscape}) {
  return MaterialApp(
    home: MediaQuery(data: MediaQueryData(size: size), child: child),
  );
}

Future<void> _openCopy(WidgetTester tester, String vehicleId) async {
  final key = limousineBusinessSetupEditPublicDetailsKey(vehicleId);
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> _typeAndSave(
  WidgetTester tester, {
  required String text,
  String? langField,
}) async {
  await tester.enterText(
    find.byKey(
      langField == null
          ? kLimousineVehiclePublicCopyFieldKey
          : limousineVehiclePublicCopyLangFieldKey(langField),
    ),
    text,
  );
  await tester.pump();
  await tester.tap(find.byKey(kLimousineVehiclePublicCopySaveKey));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester) {
  return tester
          .widget<TextField>(find.byKey(kLimousineVehiclePublicCopyFieldKey))
          .controller
          ?.text ??
      '';
}

void main() {
  late MemoryLimousinePricingLocalStore store;
  late List<Map<String, dynamic>> saves;
  late AppLanguage language;
  var persistCalls = 0;
  var failNextPublish = false;
  var serverRevision = 1;

  final party = _fleetVehicle(id: _kPartyId, name: 'Party Limo');
  final hummer = _fleetVehicle(
    id: _kHummerId,
    name: 'Hummer white',
    classId: 'luxury_van',
  );

  setUp(() {
    store = MemoryLimousinePricingLocalStore();
    limousinePricingLocalStore = store;
    saves = <Map<String, dynamic>>[];
    persistCalls = 0;
    failNextPublish = false;
    serverRevision = 1;
    language = appLanguageNotifier.value;
    appLanguageNotifier.value = AppLanguage.nl;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  tearDown(() {
    limousinePricingLocalStore = FileLimousinePricingLocalStore();
    appLanguageNotifier.value = language;
  });

  Future<Map<String, dynamic>> loadStripped() async {
    return _serverSection(revision: serverRevision);
  }

  Future<Map<String, dynamic>> saveStripped(Map<String, dynamic> section) async {
    saves.add(Map<String, dynamic>.from(section));
    if (section['enabled'] == true &&
        section.containsKey(kLimousinePublishedVehiclePublicCopyKey) &&
        failNextPublish) {
      failNextPublish = false;
      throw Exception('publish_failed');
    }
    serverRevision += 1;
    return <String, dynamic>{
      'ok': true,
      'limousine': _stripCopy(section),
    };
  }

  Widget setupPage({LimousinePricingLoader? load}) {
    return _app(
      LimousineBusinessSetupPage(
        loadPricing: load ?? loadStripped,
        savePricing: saveStripped,
        persistVehicles: (_) async => persistCalls += 1,
        vehicles: <VehicleProfile>[party, hummer],
        knownClassIds: const <String>['stretch_limousine', 'luxury_van'],
        entryEnabled: true,
        language: AppLanguage.nl,
      ),
    );
  }

  Future<void> pumpSetup(
    WidgetTester tester, {
    LimousinePricingLoader? load,
  }) async {
    await tester.binding.setSurfaceSize(kLimousineTabletLandscape);
    await tester.pumpWidget(setupPage(load: load));
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> publicProfile({
    Map<String, dynamic>? publishedCopy,
    Map<String, dynamic>? workingCopy,
  }) {
    return <String, dynamic>{
      'partner_id': _kPartnerId,
      'company_name': 'Maison Noire',
      'limousine_available': true,
      'vehicles': <Map<String, dynamic>>[
        <String, dynamic>{
          'vehicle_id': _kPartyId,
          'name': 'Party Limo',
          'service_category': 'limousine',
          'service_class_id': 'stretch_limousine',
          'is_active': true,
          'photo_url': 'https://cdn.example/party.jpg',
          'passenger_capacity': 16,
          'luggage_capacity': 3,
        },
        <String, dynamic>{
          'vehicle_id': _kHummerId,
          'name': 'Hummer white',
          'service_category': 'limousine',
          'service_class_id': 'luxury_van',
          'is_active': true,
          'photo_url': 'https://cdn.example/hummer.jpg',
          'passenger_capacity': 8,
          'luggage_capacity': 4,
        },
      ],
      'limousine_offers': <Map<String, dynamic>>[_publishedOffer()],
      if (workingCopy != null) kLimousineVehiclePublicCopyKey: workingCopy,
      if (publishedCopy != null)
        kLimousinePublishedVehiclePublicCopyKey: publishedCopy,
    };
  }

  Widget detailFromCatalog(
    Map<String, Map<String, String>> catalog, {
    String vehicleId = _kPartyId,
  }) {
    final data = buildLimousineProviderShowroomData(
      profile: publicProfile(),
    );
    final vehicle = data.vehicles.firstWhere((item) => item.vehicleId == vehicleId);
    final resolved = data.vehicles
        .firstWhere((item) => item.vehicleId == vehicleId)
        .publicDescription
        .isNotEmpty
        ? vehicle
        : LimousineShowroomVehicle(
            key: vehicle.key,
            name: vehicle.name,
            brandModel: vehicle.brandModel,
            serviceClassId: vehicle.serviceClassId,
            photoUrls: vehicle.photoUrls,
            passengerCapacity: vehicle.passengerCapacity,
            luggageCapacity: vehicle.luggageCapacity,
            vehicleId: vehicle.vehicleId,
            publicDescription: catalog[vehicleId] ?? const <String, String>{},
            offers: vehicle.offers,
          );
    return _app(
      LimousineVehicleDetailPage(
        vehicle: resolved,
        companyName: 'Maison Noire',
        partnerId: _kPartnerId,
        logoImage: MemoryImage(_kTinyPng),
        photoImages: [for (final _ in resolved.photoUrls) MemoryImage(_kTinyPng)],
      ),
    );
  }

  testWidgets(
    '1-6 Bewaren persists per canonical vehicle id and reloads the editor',
    (tester) async {
      await pumpSetup(tester);
      await _openCopy(tester, _kPartyId);
      await _typeAndSave(tester, text: _kPartyNl);

      expect(saves, isNotEmpty);
      final working = limousineVehiclePublicCopyById(
        saves.last[kLimousineVehiclePublicCopyKey],
      );
      expect(working[_kPartyId]?['nl'], _kPartyNl);
      expect(working.containsKey(_kHummerId), isFalse);
      expect(
        limousineVehiclePublicCopyById(
          saves.last[kLimousinePublishedVehiclePublicCopyKey],
        ),
        isEmpty,
      );
      expect(
        store.workingCopyFor(kLimousinePricingLocalDefaultScope)[_kPartyId]?['nl'],
        _kPartyNl,
      );
      expect(find.byKey(kLimousineBusinessSetupDirtyKey), findsNothing);
      expect(
        find.text(kLimousineBusinessSetupDraftSaved.of(AppLanguage.nl)),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(kLimousineBusinessSetupDraftSaveKey),
            )
            .onPressed,
        isNull,
      );

      await _openCopy(tester, _kPartyId);
      expect(_fieldText(tester), _kPartyNl);
      await tester.tap(find.byKey(kLimousineVehiclePublicCopyCancelKey));
      await tester.pumpAndSettle();

      await _openCopy(tester, _kHummerId);
      expect(_fieldText(tester), isEmpty);
      await _typeAndSave(tester, text: _kHummerNl);
      expect(
        store.workingCopyFor(kLimousinePricingLocalDefaultScope)[_kPartyId]?['nl'],
        _kPartyNl,
      );
      expect(
        store.workingCopyFor(kLimousinePricingLocalDefaultScope)[_kHummerId]?['nl'],
        _kHummerNl,
      );
      expect(party.vehicleName, 'Party Limo');
      expect(hummer.vehicleName, 'Hummer white');
    },
  );

  testWidgets(
    '3-4 disposing the page and a repository reload keep the working draft',
    (tester) async {
      await pumpSetup(tester);
      await _openCopy(tester, _kPartyId);
      await _typeAndSave(tester, text: _kPartyNl);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      await pumpSetup(tester);
      await _openCopy(tester, _kPartyId);
      expect(_fieldText(tester), _kPartyNl);
      await tester.tap(find.byKey(kLimousineVehiclePublicCopyCancelKey));
      await tester.pumpAndSettle();

      final encoded = jsonEncode(store.snapshot());
      final restarted = MemoryLimousinePricingLocalStore(
        (jsonDecode(encoded) as Map).map(
          (key, value) => MapEntry(
            key.toString(),
            Map<String, dynamic>.from(value as Map),
          ),
        ),
      );
      limousinePricingLocalStore = restarted;
      await pumpSetup(tester);
      await _openCopy(tester, _kPartyId);
      expect(_fieldText(tester), _kPartyNl);
    },
  );

  test('4 file overlay survives a new store instance', () async {
    final dir = Directory.systemTemp.createTempSync('limo_copy_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final first = FileLimousinePricingLocalStore(root: dir);
    first.writeVehiclePublicCopy(
      scopeKeys: const <String>[kLimousinePricingLocalDefaultScope],
      working: <String, Map<String, String>>{
        _kPartyId: <String, String>{'nl': _kPartyNl, 'en': _kPartyEn},
      },
      published: const {},
      updatePublished: false,
      revision: 2,
    );
    final second = FileLimousinePricingLocalStore(root: dir);
    await second.warm();
    expect(second.workingCopyFor(kLimousinePricingLocalDefaultScope)[_kPartyId]?['nl'], _kPartyNl);
    expect(second.workingCopyFor(kLimousinePricingLocalDefaultScope)[_kPartyId]?['en'], _kPartyEn);
  });

  testWidgets('7 older stripped refresh does not clobber a newer local draft', (
    tester,
  ) async {
    await pumpSetup(tester);
    await _openCopy(tester, _kPartyId);
    await _typeAndSave(tester, text: _kPartyNl);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await pumpSetup(
      tester,
      load: () async => _serverSection(
        revision: 0,
        extra: <String, dynamic>{
          kLimousineVehiclePublicCopyKey: <String, dynamic>{},
        },
      ),
    );
    await _openCopy(tester, _kPartyId);
    expect(_fieldText(tester), _kPartyNl);
  });

  testWidgets(
    '8-12 publish copies working to the public payload and real detail widget',
    (tester) async {
      await pumpSetup(tester);
      await _openCopy(tester, _kPartyId);
      await tester.enterText(
        find.byKey(kLimousineVehiclePublicCopyFieldKey),
        _kPartyNl,
      );
      await tester.tap(find.byKey(kLimousineVehiclePublicCopyOtherLanguagesKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(limousineVehiclePublicCopyLangFieldKey('en')),
        _kPartyEn,
      );
      await tester.tap(find.byKey(kLimousineVehiclePublicCopySaveKey));
      await tester.pumpAndSettle();

      expect(
        limousinePublishedVehiclePublicCopyOf(publicProfile()),
        isEmpty,
      );
      final draftShowroom = buildLimousineProviderShowroomData(
        profile: publicProfile(),
      );
      expect(
        limousinePublicCopyHasText(
          draftShowroom.vehicles
              .firstWhere((item) => item.vehicleId == _kPartyId)
              .publicDescription,
        ),
        isFalse,
      );

      tester
          .widget<ButtonStyleButton>(find.byKey(kLimousineBusinessSetupPublishKey))
          .onPressed!();
      await tester.pumpAndSettle();

      final publishedPayload = limousineVehiclePublicCopyById(
        saves.last[kLimousinePublishedVehiclePublicCopyKey],
      );
      expect(publishedPayload[_kPartyId]?['nl'], _kPartyNl);
      expect(publishedPayload[_kPartyId]?['en'], _kPartyEn);
      expect(
        store.publishedCopyFor(kLimousinePricingLocalDefaultScope)[_kPartyId]?['nl'],
        _kPartyNl,
      );

      final encoded = jsonEncode(saves.last);
      final decoded = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
      final roundtrip = limousineVehiclePublicCopyById(
        decoded[kLimousinePublishedVehiclePublicCopyKey],
      );
      expect(roundtrip[_kPartyId]?['nl'], _kPartyNl);
      expect(roundtrip[_kPartyId]?['en'], _kPartyEn);
      expect(roundtrip[_kPartyId]?['fr'], isEmpty);

      final showroom = buildLimousineProviderShowroomData(
        profile: publicProfile(),
      );
      final partyVehicle = showroom.vehicles.firstWhere(
        (item) => item.vehicleId == _kPartyId,
      );
      final hummerVehicle = showroom.vehicles.firstWhere(
        (item) => item.vehicleId == _kHummerId,
      );
      expect(partyVehicle.publicDescription['nl'], _kPartyNl);
      expect(hummerVehicle.publicDescription['nl'], isEmpty);
      expect(
        limousinePublishedVehiclePublicCopyOf(
          limousineAttachPublishedVehiclePublicCopy(
            publicProfile(),
            store.publishedCopyFor(kLimousinePricingLocalDefaultScope),
          ),
        )[_kPartyId]?['nl'],
        _kPartyNl,
      );

      await tester.pumpWidget(
        _app(
          LimousineVehicleDetailPage(
            vehicle: partyVehicle,
            companyName: 'Maison Noire',
            partnerId: _kPartnerId,
            logoImage: MemoryImage(_kTinyPng),
            photoImages: [
              for (final _ in partyVehicle.photoUrls) MemoryImage(_kTinyPng),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.text(kLimousineDetailAboutHeading.nl), findsOneWidget);
      expect(find.text(_kPartyNl), findsOneWidget);
      final aboutTop = tester.getTopLeft(find.byKey(kLimousineDetailAboutSectionKey)).dy;
      final pricesTop = tester.getTopLeft(find.byKey(kLimousineDetailPricesSectionKey)).dy;
      expect(aboutTop, lessThan(pricesTop));
    },
  );

  testWidgets('13 missing Dutch uses the agreed language fallback', (
    tester,
  ) async {
    store.writeVehiclePublicCopy(
      scopeKeys: const <String>[kLimousinePricingLocalDefaultScope],
      working: const {},
      published: <String, Map<String, String>>{
        _kPartyId: <String, String>{'en': _kPartyEn, 'nl': ''},
      },
      updatePublished: true,
    );
    final vehicle = buildLimousineProviderShowroomData(
      profile: publicProfile(),
    ).vehicles.firstWhere((item) => item.vehicleId == _kPartyId);
    appLanguageNotifier.value = AppLanguage.nl;
    await tester.pumpWidget(
      _app(
        LimousineVehicleDetailPage(
          vehicle: vehicle,
          companyName: 'Maison Noire',
          partnerId: _kPartnerId,
          logoImage: MemoryImage(_kTinyPng),
          photoImages: [for (final _ in vehicle.photoUrls) MemoryImage(_kTinyPng)],
        ),
      ),
    );
    await tester.pump();
    expect(find.text(_kPartyEn), findsOneWidget);
    expect(
      limousineResolvePublicCopyText(vehicle.publicDescription, AppLanguage.fr),
      _kPartyEn,
    );
  });

  testWidgets('14 empty published copy hides the whole about section', (
    tester,
  ) async {
    await tester.pumpWidget(detailFromCatalog(const {}));
    await tester.pump();
    expect(find.byKey(kLimousineDetailAboutSectionKey), findsNothing);
    expect(find.text(kLimousineDetailAboutHeading.nl), findsNothing);
    expect(find.text(kLimousineDetailPricesHeading.nl), findsOneWidget);
  });

  testWidgets('15 draft copy stays invisible until publish', (tester) async {
    await pumpSetup(tester);
    await _openCopy(tester, _kPartyId);
    await _typeAndSave(tester, text: _kPartyNl);
    final data = buildLimousineProviderShowroomData(profile: publicProfile());
    expect(
      limousinePublicCopyHasText(
        data.vehicles
            .firstWhere((item) => item.vehicleId == _kPartyId)
            .publicDescription,
      ),
      isFalse,
    );
    await tester.pumpWidget(
      _app(
        LimousineVehicleDetailPage(
          vehicle: data.vehicles.firstWhere((item) => item.vehicleId == _kPartyId),
          companyName: 'Maison Noire',
          partnerId: _kPartnerId,
          logoImage: MemoryImage(_kTinyPng),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(_kPartyNl), findsNothing);
    expect(find.byKey(kLimousineDetailAboutSectionKey), findsNothing);
  });

  testWidgets(
    '16-17 failed publish keeps the previous snapshot; republish does not wipe',
    (tester) async {
      await pumpSetup(tester);
      await _openCopy(tester, _kPartyId);
      await _typeAndSave(tester, text: _kPartyNl);
      tester
          .widget<ButtonStyleButton>(find.byKey(kLimousineBusinessSetupPublishKey))
          .onPressed!();
      await tester.pumpAndSettle();
      expect(
        store.publishedCopyFor(kLimousinePricingLocalDefaultScope)[_kPartyId]?['nl'],
        _kPartyNl,
      );

      await _openCopy(tester, _kPartyId);
      await _typeAndSave(tester, text: 'Nieuw concept dat nog niet live mag.');
      failNextPublish = true;
      tester
          .widget<ButtonStyleButton>(find.byKey(kLimousineBusinessSetupPublishKey))
          .onPressed!();
      await tester.pumpAndSettle();
      expect(
        store.publishedCopyFor(kLimousinePricingLocalDefaultScope)[_kPartyId]?['nl'],
        _kPartyNl,
      );
      expect(
        store.workingCopyFor(kLimousinePricingLocalDefaultScope)[_kPartyId]?['nl'],
        'Nieuw concept dat nog niet live mag.',
      );
      expect(
        buildLimousineProviderShowroomData(profile: publicProfile())
            .vehicles
            .firstWhere((item) => item.vehicleId == _kPartyId)
            .publicDescription['nl'],
        _kPartyNl,
      );

      tester
          .widget<ButtonStyleButton>(find.byKey(kLimousineBusinessSetupPublishKey))
          .onPressed!();
      await tester.pumpAndSettle();
      expect(
        store.publishedCopyFor(kLimousinePricingLocalDefaultScope)[_kPartyId]?['nl'],
        'Nieuw concept dat nog niet live mag.',
      );
    },
  );

  test('18 taxi and internal vehicle notes stay untouched', () {
    final payload = limousineVehiclePublicCopyPayload(
      publish: true,
      working: <String, Map<String, String>>{
        party.id: const <String, String>{'nl': _kPartyNl},
      },
      published: const {},
    );
    expect(limousinePublicCopyTouchesPrivateVehicleFields(payload), isFalse);
    expect(payload.containsKey('notes'), isFalse);
    expect(payload.containsKey('internal_notes'), isFalse);
    expect(party.vehicleName, 'Party Limo');
    expect(party.licensePlate, '1-ABC-123');
    final source = File('lib/app_config.dart').readAsStringSync();
    final start = source.indexOf('class VehicleProfile {');
    final end = source.indexOf('class DriverProfile {');
    final body = source.substring(start, end);
    expect(body.contains('notes'), isFalse);
    expect(body.contains('publicDescription'), isFalse);
  });
}
