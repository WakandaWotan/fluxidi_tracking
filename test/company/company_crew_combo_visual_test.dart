import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_crew_combo.dart';
import 'package:fluxidi_tracking/company/company_plan_presence.dart';

Future<void> _loadReadableFonts() async {
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    final bytes = await file.readAsBytes();
    final loader = FontLoader(family)
      ..addFont(
        Future<ByteData>.value(ByteData.sublistView(Uint8List.fromList(bytes))),
      );
    await loader.load();
  }

  await load('Roboto', r'C:\Windows\Fonts\segoeui.ttf');
  await load(
    'MaterialIcons',
    r'C:\dev\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
  );
}

CompanyCrewCombo _karel() {
  return CompanyCrewCombo(
    driverId: 'drv_karel',
    vehicleId: 'vh_1',
    driver: const <String, dynamic>{
      'driver_id': 'drv_karel',
      'display_name': 'Karel Peeters',
      'is_active': true,
    },
    vehicle: const <String, dynamic>{
      'vehicle_id': 'vh_1',
      'vehicle_name': 'S-Klasse',
      'vehicle_type': 'sedan',
      'is_active': true,
    },
    presence: const CompanyPlanPresence(
      tone: CompanyPlanPresenceTone.available,
      code: 'available',
      icon: Icons.check_circle_outline,
    ),
  );
}

CompanyCrewCombo _amira() {
  return CompanyCrewCombo(
    driverId: 'drv_amira',
    vehicleId: 'vh_3',
    driver: const <String, dynamic>{
      'driver_id': 'drv_amira',
      'display_name': 'Amira Benali',
      'is_active': true,
    },
    vehicle: const <String, dynamic>{
      'vehicle_id': 'vh_3',
      'vehicle_name': 'E-Klasse',
      'vehicle_type': 'sedan',
      'is_active': true,
    },
    presence: const CompanyPlanPresence(
      tone: CompanyPlanPresenceTone.available,
      code: 'available',
      icon: Icons.check_circle_outline,
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Size size,
  String selectedId,
) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: size.width < 600 ? size.width : 520),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CompanyCrewComboPicker(
                  key: kCompanyAgendaOutboundCrewKey,
                  language: AppLanguage.nl,
                  title: 'Heenrit Koekamerstraat 48A → Korenmarkt 1',
                  combos: <CompanyCrewCombo>[_karel(), _amira()],
                  selectedId: selectedId,
                  plannedLocal: DateTime(2026, 9, 16, 13, 38),
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_loadReadableFonts);

  testWidgets('phone closed crew field', (tester) async {
    await _pump(tester, const Size(390, 844), '');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/company_crew_combo_phone_closed.png'),
    );
  });

  testWidgets('phone open crew sheet', (tester) async {
    await _pump(tester, const Size(390, 844), '');
    await tester.tap(find.byKey(kCompanyCrewComboOpenKey));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/company_crew_combo_phone_open.png'),
    );
  });

  testWidgets('desktop closed crew field', (tester) async {
    await _pump(tester, const Size(1524, 900), 'drv_karel|vh_1');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/company_crew_combo_desktop_closed.png'),
    );
  });

  testWidgets('desktop open crew dialog', (tester) async {
    await _pump(tester, const Size(1524, 900), 'drv_karel|vh_1');
    await tester.tap(find.byKey(kCompanyCrewComboOpenKey));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/company_crew_combo_desktop_open.png'),
    );
  });
}
