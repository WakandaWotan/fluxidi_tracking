import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/airport_price_policy.dart';
import 'package:fluxidi_tracking/company/airport_price_policy_section.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_labels.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_place.dart';
import 'package:fluxidi_tracking/company/company_fixed_prices_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final font = File(r'C:\Windows\Fonts\segoeui.ttf');
    if (!font.existsSync()) return;
    final bytes = await font.readAsBytes();
    final loader = FontLoader('Segoe UI')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  });

  Map<String, dynamic> isolatedProfile() => <String, dynamic>{
        'companyName': 'Testbedrijf Isolatie',
        'legalName': 'Testbedrijf Isolatie BV',
        'phone': '03 000 00 00',
        'email': 'ops@example.test',
        'country': 'BE',
        'website': 'https://example.test',
      };

  test('missing policy stays omitted and other profile fields stay put', () {
    final stored = isolatedProfile();
    final unchanged = buildAirportPricePolicyProfile(
      stored: stored,
      autoCalcEnabled: true,
      leadText: '',
    );
    expect(unchanged.unchanged, isTrue);
    expect(unchanged.profile, isNull);

    final off = buildAirportPricePolicyProfile(
      stored: stored,
      autoCalcEnabled: false,
      leadText: '',
    );
    final profile = off.profile!;
    expect(profile['companyName'], 'Testbedrijf Isolatie');
    expect(profile['legalName'], 'Testbedrijf Isolatie BV');
    expect(profile['phone'], '03 000 00 00');
    expect(profile['email'], 'ops@example.test');
    expect(profile['website'], 'https://example.test');
    expect(profile[kAirportAutoCalcOutsideFixedFaresField], isFalse);
    expect(profile.containsKey(kAirportFixedFareMinLeadHoursField), isFalse);
    expect(profile.containsKey('pending_price_conditions'), isFalse);

    final invalid = buildAirportPricePolicyProfile(
      stored: stored,
      autoCalcEnabled: false,
      leadText: 'abc',
    );
    expect(invalid.invalidLead, isTrue);
    expect(invalid.profile, isNull);
    expect(
      buildAirportPricePolicyProfile(
        stored: stored,
        autoCalcEnabled: true,
        leadText: '721',
      ).invalidLead,
      isTrue,
    );
    expect(
      buildAirportPricePolicyProfile(
        stored: stored,
        autoCalcEnabled: true,
        leadText: '-1',
      ).invalidLead,
      isTrue,
    );

    final zero = buildAirportPricePolicyProfile(
      stored: stored,
      autoCalcEnabled: true,
      leadText: '0',
    ).profile!;
    expect(zero[kAirportFixedFareMinLeadHoursField], 0);
    expect(zero.containsKey(kAirportAutoCalcOutsideFixedFaresField), isFalse);

    final hours = buildAirportPricePolicyProfile(
      stored: stored,
      autoCalcEnabled: true,
      leadText: '36',
    ).profile!;
    expect(hours[kAirportFixedFareMinLeadHoursField], 36);
    expect(hours['companyName'], 'Testbedrijf Isolatie');

    final cleared = buildAirportPricePolicyProfile(
      stored: hours,
      autoCalcEnabled: true,
      leadText: '',
    ).profile!;
    expect(cleared[kAirportFixedFareMinLeadHoursField], isNull);
    expect(cleared['companyName'], 'Testbedrijf Isolatie');
  });

  test('typed profile save keeps a stored policy and omits a missing term', () {
    final missing = BackendBusinessProfile.fromJson(<String, dynamic>{
      'companyName': 'Testbedrijf Isolatie',
      'legalName': 'Testbedrijf Isolatie BV',
      'phone': '03 000 00 00',
      'email': 'ops@example.test',
    });
    final missingJson = missing.toJson();
    expect(missingJson['companyName'], 'Testbedrijf Isolatie');
    expect(
      missingJson.containsKey(kAirportAutoCalcOutsideFixedFaresField),
      isFalse,
    );
    expect(
      missingJson.containsKey(kAirportFixedFareMinLeadHoursField),
      isFalse,
    );

    final stored = BackendBusinessProfile.fromJson(<String, dynamic>{
      'companyName': 'Testbedrijf Isolatie',
      'legalName': 'Testbedrijf Isolatie BV',
      'phone': '03 000 00 00',
      'email': 'ops@example.test',
      kAirportAutoCalcOutsideFixedFaresField: false,
      kAirportFixedFareMinLeadHoursField: 0,
    });
    final roundTrip = stored.copyWith(companyName: 'Testbedrijf Isolatie').toJson();
    expect(roundTrip['companyName'], 'Testbedrijf Isolatie');
    expect(roundTrip['phone'], '03 000 00 00');
    expect(roundTrip[kAirportAutoCalcOutsideFixedFaresField], isFalse);
    expect(roundTrip[kAirportFixedFareMinLeadHoursField], 0);
  });

  testWidgets('airport price policy reads, saves and reloads on an isolated profile', (
    tester,
  ) async {
    final store = isolatedProfile();
    var saves = 0;
    Future<Map<String, dynamic>> load() async =>
        Map<String, dynamic>.from(store);
    Future<Map<String, dynamic>> save(Map<String, dynamic> profile) async {
      saves += 1;
      store
        ..clear()
        ..addAll(profile);
      return Map<String, dynamic>.from(store);
    }

    Future<void> pumpSection(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size),
          child: MaterialApp(
            theme: ThemeData(fontFamily: 'Segoe UI'),
            home: Scaffold(
              body: ListView(
                children: [
                  AirportPricePolicySection(
                    language: AppLanguage.nl,
                    loader: load,
                    saver: save,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpSection(const Size(390, 844));
    expect(tester.widget<SwitchListTile>(find.byKey(kAirportAutoCalcSwitchKey)).value, isTrue);
    expect(tester.widget<TextFormField>(find.byKey(kAirportMinLeadFieldKey)).controller?.text, isEmpty);
    expect(find.text('48'), findsNothing);
    await _shoot(tester, 'phone_missing_policy');

    await tester.tap(find.byKey(kAirportAutoCalcSwitchKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kAirportPricePolicySaveKey));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(store[kAirportAutoCalcOutsideFixedFaresField], isFalse);
    expect(store.containsKey(kAirportFixedFareMinLeadHoursField), isFalse);
    expect(store['companyName'], 'Testbedrijf Isolatie');
    expect(store['phone'], '03 000 00 00');
    expect(find.byKey(kAirportPricePolicyStatusKey), findsOneWidget);
    expect(find.byKey(kAirportPricePolicyErrorKey), findsNothing);

    await pumpSection(const Size(800, 1280));
    expect(tester.widget<SwitchListTile>(find.byKey(kAirportAutoCalcSwitchKey)).value, isFalse);
    expect(tester.widget<TextFormField>(find.byKey(kAirportMinLeadFieldKey)).controller?.text, isEmpty);
    await _shoot(tester, 'tablet_auto_calc_off');

    await tester.enterText(find.byKey(kAirportMinLeadFieldKey), '36');
    await tester.tap(find.byKey(kAirportPricePolicySaveKey));
    await tester.pumpAndSettle();
    expect(store[kAirportFixedFareMinLeadHoursField], 36);
    expect(store[kAirportAutoCalcOutsideFixedFaresField], isFalse);
    expect(store['email'], 'ops@example.test');
    expect(store['website'], 'https://example.test');

    await pumpSection(const Size(1280, 800));
    expect(tester.widget<TextFormField>(find.byKey(kAirportMinLeadFieldKey)).controller?.text, '36');
    await _shoot(tester, 'windows_lead_36');

    await tester.enterText(find.byKey(kAirportMinLeadFieldKey), '0');
    await tester.tap(find.byKey(kAirportPricePolicySaveKey));
    await tester.pumpAndSettle();
    expect(store[kAirportFixedFareMinLeadHoursField], 0);
    expect(store['companyName'], 'Testbedrijf Isolatie');

    final savesBeforeInvalid = saves;
    await tester.enterText(find.byKey(kAirportMinLeadFieldKey), '721');
    await tester.tap(find.byKey(kAirportPricePolicySaveKey));
    await tester.pumpAndSettle();
    expect(saves, savesBeforeInvalid);
    expect(store[kAirportFixedFareMinLeadHoursField], 0);
    expect(find.byKey(kAirportPricePolicyErrorKey), findsOneWidget);
    expect(find.byKey(kAirportPricePolicyStatusKey), findsNothing);
    expect(find.text(kAirportPricePolicySaved.of(AppLanguage.nl)), findsNothing);
  });

  testWidgets('a failed save stays visible as a failure', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(390, 844)),
        child: MaterialApp(
          home: Scaffold(
            body: AirportPricePolicySection(
              language: AppLanguage.nl,
              loader: _loadExplicitOff,
              saver: _failingSave,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byKey(kAirportAutoCalcSwitchKey)).value, isFalse);
    await tester.tap(find.byKey(kAirportAutoCalcSwitchKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kAirportPricePolicySaveKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kAirportPricePolicyErrorKey), findsOneWidget);
    expect(find.text(kAirportPricePolicySaveFailed.of(AppLanguage.nl)), findsOneWidget);
    expect(find.byKey(kAirportPricePolicyStatusKey), findsNothing);
    expect(find.text(kAirportPricePolicySaved.of(AppLanguage.nl)), findsNothing);
  });

  testWidgets('the policy sits on the airport prices page', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1280, 800)),
        child: MaterialApp(
          home: CompanyFixedPricesPage(
            language: AppLanguage.nl,
            catalog: CompanyFixedPricesCatalog.airport,
            manageAirportPricePolicy: true,
            loader: () async => <String, dynamic>{
              'fallback': 'calculator',
              'rules': <dynamic>[],
            },
            saver: (doc) async => doc,
            profileLoader: () async => isolatedProfile(),
            profileSaver: (profile) async => profile,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kAirportPricePolicyCardKey), findsOneWidget);
    expect(find.text(kAirportAutoCalcTitle.of(AppLanguage.nl)), findsWidgets);
    expect(find.text(kCompanyFixedPricesAirports.of(AppLanguage.nl)), findsOneWidget);
    await _shoot(tester, 'windows_airport_prices_page');
  });
}

Future<Map<String, dynamic>> _loadExplicitOff() async {
  return <String, dynamic>{
    'companyName': 'Testbedrijf Isolatie',
    'phone': '03 000 00 00',
    'email': 'ops@example.test',
    kAirportAutoCalcOutsideFixedFaresField: false,
  };
}

Future<Map<String, dynamic>> _failingSave(Map<String, dynamic> profile) async {
  throw StateError('isolated-save-failed');
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(kAirportPricePolicyCardKey),
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  final file = File(
    "${Platform.environment['FLUXIDI_TEST_ARTIFACT_ROOT'] ?? 'D:/Projecten/_flutter_work/fluxidi_customer_ops_client_p0/.qa-local/airport_price_policy'}/$name.png",
  );
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
}
