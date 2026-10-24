import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_operational_base.dart';
import 'package:fluxidi_tracking/company/company_operational_base_editor.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

const base = CompanyOperationalBase(address: 'Koekamerstraat 48A, 9688 Schorisse, BE',
  latitude: 50.77205, longitude: 3.66942);

void main() {
  test('profile round trip and unrelated copy retain explicit operational base', () {
    final p = BackendBusinessProfile.defaults().copyWith(operationalBase: base);
    final r = BackendBusinessProfile.fromJson(p.toJson()).copyWith(phone: 'changed');
    expect(r.operationalBase!.toJson(), base.toJson());
    expect(r.toJson()['base_lat'], 50.77205);
  });
  test('coverage and legal address alone never become departure coordinates', () {
    final p = BackendBusinessProfile.fromJson({'address': base.address,
      'publicCoverageLat': '50.77205', 'publicCoverageLng': '3.66942'});
    expect(p.operationalBase, isNull);
    expect(p.toJson().containsKey('base_lat'), false);
  });
  test('camel aliases retain explicit address and valid numeric coordinates', () {
    final b = CompanyOperationalBase.fromJson({'baseAddress': base.address,
      'baseLat': '50.77205', 'baseLng': 3.66942});
    expect(b!.toJson(), base.toJson());
  });
  for (final coordinates in [[true, 3.6], [null, 3.6], [91, 3.6],
    [50, double.nan], [0, 0], [50, 181]]) {
    test('invalid base cannot be a valid origin: $coordinates', () {
      final b = CompanyOperationalBase.fromJson({'base_address': base.address,
        'base_lat': coordinates[0], 'base_lng': coordinates[1]});
      expect(b!.isValid, false);
    });
  }
  test('explicit removal clears canonical and legacy coordinate aliases', () {
    final json = BackendBusinessProfile.defaults().copyWith(
      operationalBase: const CompanyOperationalBase.cleared()).toJson();
    for (final key in ['base_lat', 'base_lng', 'baseLat', 'baseLng']) {
      expect(json.containsKey(key), true);
      expect(json[key], null);
    }
    expect(BackendBusinessProfile.fromJson(json).operationalBase!.isValid, false);
  });

  final lookup = LimousinePlaceLookup(searchOverride: (_, __) async =>
    const LimousinePlaceLookupResult(suggestions: [LimousinePlaceSuggestion(
      label: 'Basisstraat 8, 9688 Schorisse, BE', lat: 50.77, lon: 3.66,
      placeType: 'address', placeId: 'address.test')]));
  Widget editor({Key? key, CompanyOperationalBase? initial,
    required ValueChanged<CompanyOperationalBase?> changed,
    required ValueChanged<bool> validity}) => MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: CompanyOperationalBaseEditor(key: key,
        initialValue: initial, language: AppLanguage.nl, lookup: lookup,
        onChanged: changed, onValidityChanged: validity))));

  testWidgets('editing a stored base invalidates old coordinates until suggestion is selected', (t) async {
    CompanyOperationalBase? selected = base; bool valid = true;
    await t.pumpWidget(editor(initial: base, changed: (v) => selected = v,
      validity: (v) => valid = v));
    await t.enterText(find.byKey(const Key('company_operational_base_address')), 'Basisstraat 8');
    await t.pump(const Duration(milliseconds: 300)); await t.pump();
    expect(valid, false); expect(selected!.address, base.address);
    await t.tap(find.text('Basisstraat 8, 9688 Schorisse, BE').first);
    await t.pump();
    expect(valid, true); expect(selected!.latitude, 50.77);
    expect(selected!.longitude, 3.66);
  });
  testWidgets('clearing the input explicitly removes the previous base', (t) async {
    CompanyOperationalBase? selected = base;
    await t.pumpWidget(editor(initial: base, changed: (v) => selected = v,
      validity: (_) {}));
    await t.enterText(find.byKey(const Key('company_operational_base_address')), '');
    await t.pump(); expect(selected!.isValid, false);
    expect(selected!.toJson()['base_lat'], null);
  });
  testWidgets('company hydration key prevents a previous tenant base from leaking', (t) async {
    await t.pumpWidget(editor(key: const ValueKey('Mario'), initial: base,
      changed: (_) {}, validity: (_) {}));
    expect(find.text(base.address), findsOneWidget);
    await t.pumpWidget(editor(key: const ValueKey('Fluxidi'),
      changed: (_) {}, validity: (_) {}));
    expect(find.text(base.address), findsNothing);
  });
  for (final size in [const Size(390, 844), const Size(800, 1280), const Size(1408, 880)]) {
    testWidgets('base editor has no overflow at $size', (t) async {
      t.view.physicalSize = size; t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(editor(initial: base, changed: (_) {}, validity: (_) {}));
      expect(find.text('Vertrekbasis voor geplande ritten'), findsOneWidget);
      expect(t.takeException(), null);
    });
  }
}
