import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_assignment_choice_field.dart';
import 'package:fluxidi_tracking/company/company_crew_combo.dart';
import 'package:fluxidi_tracking/company/company_plan_presence.dart';
import 'package:fluxidi_tracking/company/company_roundtrip.dart';
import 'package:fluxidi_tracking/company/company_roundtrip_fields.dart';

CompanyCrewCombo _combo({
  required String driverId,
  required String name,
  required String vehicleId,
  required String vehicleName,
  String vehicleType = 'sedan',
  CompanyPlanPresenceTone tone = CompanyPlanPresenceTone.available,
  String code = 'available',
}) {
  return CompanyCrewCombo(
    driverId: driverId,
    vehicleId: vehicleId,
    driver: <String, dynamic>{
      'driver_id': driverId,
      'display_name': name,
      'is_active': true,
    },
    vehicle: <String, dynamic>{
      'vehicle_id': vehicleId,
      'vehicle_name': vehicleName,
      'vehicle_type': vehicleType,
      'is_active': true,
    },
    presence: CompanyPlanPresence(
      tone: tone,
      code: code,
      icon: Icons.check_circle_outline,
    ),
  );
}

Future<void> _pumpPicker(
  WidgetTester tester, {
  required Size size,
  required List<CompanyCrewCombo> combos,
  String selectedId = '',
  String title = 'Heenrit A → B',
  ValueChanged<String>? onSelected,
  CompanyRoundtripChoice? roundtrip,
}) async {
  var current = selectedId;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (roundtrip != null)
                    CompanyRoundtripChoiceControl(
                      language: AppLanguage.nl,
                      choice: roundtrip,
                      onChoiceChanged: (_) {},
                    ),
                  CompanyCrewComboPicker(
                    key: kCompanyAgendaOutboundCrewKey,
                    language: AppLanguage.nl,
                    title: title,
                    combos: combos,
                    selectedId: current,
                    plannedLocal: DateTime(2026, 9, 16, 13, 38),
                    onSelected: (id) {
                      setState(() => current = id);
                      onSelected?.call(id);
                    },
                  ),
                  if (roundtrip == CompanyRoundtripChoice.splitNoWait)
                    CompanyCrewComboPicker(
                      key: kCompanyAgendaReturnCrewKey,
                      language: AppLanguage.nl,
                      title: 'Terugrit B → A',
                      combos: combos,
                      selectedId: '',
                      onSelected: (_) {},
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openOutbound(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(kCompanyAgendaOutboundCrewKey),
      matching: find.byKey(kCompanyCrewComboOpenKey),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final karel = _combo(
    driverId: 'drv_karel',
    name: 'Karel Peeters',
    vehicleId: 'vh_1',
    vehicleName: 'S-Klasse',
  );
  final karelVan = _combo(
    driverId: 'drv_karel',
    name: 'Karel Peeters',
    vehicleId: 'vh_2',
    vehicleName: 'V-Klasse',
    vehicleType: 'minivan',
  );
  final amira = _combo(
    driverId: 'drv_amira',
    name: 'Amira Benali',
    vehicleId: 'vh_3',
    vehicleName: 'E-Klasse',
  );
  final overlap = _combo(
    driverId: 'drv_busy',
    name: 'Tom Janssen',
    vehicleId: 'vh_4',
    vehicleName: 'C-Klasse',
    tone: CompanyPlanPresenceTone.blocked,
    code: 'assignment_overlap',
  );

  testWidgets('chooser stays closed until the compact field is opened', (
    tester,
  ) async {
    await _pumpPicker(
      tester,
      size: const Size(390, 844),
      combos: [karel, amira],
    );
    expect(find.byKey(kCompanyCrewComboSheetKey), findsNothing);
    expect(
      find.byKey(const Key('company_crew_combo_drv_karel|vh_1')),
      findsNothing,
    );
    expect(find.textContaining('drv_'), findsNothing);
    await _openOutbound(tester);
    expect(find.byKey(kCompanyCrewComboSheetKey), findsOneWidget);
    expect(
      find.byKey(const Key('company_crew_combo_drv_karel|vh_1')),
      findsOneWidget,
    );
  });

  testWidgets('selecting a combination closes the list and keeps the card', (
    tester,
  ) async {
    await _pumpPicker(
      tester,
      size: const Size(1180, 820),
      combos: [karel, amira],
    );
    await _openOutbound(tester);
    await tester.tap(
      find.byKey(const Key('company_crew_combo_drv_karel|vh_1')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyCrewComboSheetKey), findsNothing);
    expect(find.byKey(kCompanyCrewComboSelectedCardKey), findsOneWidget);
    expect(find.text('Karel Peeters'), findsWidgets);
    expect(find.textContaining('drv_karel'), findsNothing);
    await _openOutbound(tester);
    await tester.tap(
      find.byKey(const Key('company_crew_combo_drv_amira|vh_3')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Amira Benali'), findsWidgets);
  });

  testWidgets('waiting return keeps one picker; split shows exactly two', (
    tester,
  ) async {
    await _pumpPicker(
      tester,
      size: const Size(390, 844),
      combos: [karel],
      roundtrip: CompanyRoundtripChoice.continuousWait,
      title: kCompanyAgendaAssignmentContinuous.of(AppLanguage.nl),
    );
    expect(find.byKey(kCompanyAgendaOutboundCrewKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaReturnCrewKey), findsNothing);
    expect(
      find.text(kCompanyAgendaAssignmentContinuous.of(AppLanguage.nl)),
      findsOneWidget,
    );

    await _pumpPicker(
      tester,
      size: const Size(1524, 900),
      combos: [karel, amira],
      roundtrip: CompanyRoundtripChoice.splitNoWait,
    );
    expect(find.byKey(kCompanyAgendaOutboundCrewKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaReturnCrewKey), findsOneWidget);
    expect(find.byKey(kCompanyCrewComboOpenKey), findsNWidgets(2));
  });

  testWidgets('multiple vehicles for one driver stay grouped', (tester) async {
    await _pumpPicker(
      tester,
      size: const Size(800, 1280),
      combos: [karel, karelVan, amira],
    );
    await _openOutbound(tester);
    expect(find.text('Karel Peeters'), findsWidgets);
    expect(find.textContaining('S-Klasse'), findsWidgets);
    expect(find.textContaining('V-Klasse'), findsWidgets);
    expect(
      find.byKey(const Key('company_crew_combo_drv_karel|vh_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('company_crew_combo_drv_karel|vh_2')),
      findsOneWidget,
    );
  });

  testWidgets('overlap is never labeled available', (tester) async {
    await _pumpPicker(
      tester,
      size: const Size(390, 844),
      combos: [karel, overlap],
    );
    await _openOutbound(tester);
    expect(
      find.text(kCompanyDriverPresenceAvailable.of(AppLanguage.nl)),
      findsNothing,
    );
    await tester.tap(find.byKey(kCompanyCrewComboUnsuitableKey));
    await tester.pumpAndSettle();
    expect(find.text('Tom Janssen'), findsWidgets);
    expect(
      find.text(kCompanyAgendaOverlapBlocked.of(AppLanguage.nl)),
      findsWidgets,
    );
    expect(
      find.text(kCompanyDriverPresenceAvailable.of(AppLanguage.nl)),
      findsNothing,
    );
  });

  testWidgets('chooser stays usable with 500 combinations', (tester) async {
    final combos = [
      for (var i = 0; i < 500; i += 1)
        _combo(
          driverId: 'drv_$i',
          name: 'Chauffeur $i',
          vehicleId: 'vh_$i',
          vehicleName: 'Wagen $i',
        ),
    ];
    await _pumpPicker(tester, size: const Size(1100, 720), combos: combos);
    await _openOutbound(tester);
    expect(find.byKey(kCompanyCrewComboListKey), findsOneWidget);
    await tester.enterText(
      find.byKey(kCompanyCrewComboSearchKey),
      'Chauffeur 499',
    );
    await tester.pumpAndSettle();
    expect(find.text('Chauffeur 499'), findsWidgets);
    await tester.tap(
      find.byKey(const Key('company_crew_combo_drv_499|vh_499')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyCrewComboSheetKey), findsNothing);
    expect(find.text('Chauffeur 499'), findsWidgets);
  });

  testWidgets('trigger and options expose semantics for assistive use', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpPicker(tester, size: const Size(390, 844), combos: [karel]);
    final trigger = tester.getSemantics(find.byKey(kCompanyCrewComboOpenKey));
    expect(trigger.label, contains('Heenrit'));
    expect(trigger.hasFlag(SemanticsFlag.isButton), isTrue);
    await tester.tap(find.byKey(kCompanyCrewComboOpenKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyCrewComboSheetKey), findsOneWidget);
    expect(find.byKey(kCompanyCrewComboSearchKey), findsOneWidget);
    final option = tester.getSemantics(
      find.byKey(const Key('company_crew_combo_drv_karel|vh_1')),
    );
    expect(option.label, contains('Karel Peeters'));
    expect(option.hasFlag(SemanticsFlag.isButton), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyCrewComboSheetKey), findsNothing);
    handle.dispose();
  });

  test('leg titles stay compact and never leak driver ids', () {
    expect(
      companyPlanCrewLegTitle(
        prefix: 'Heenrit',
        from: 'Koekamerstraat 48A, 9688 Schorisse, België',
        to: 'Korenmarkt 1, 9000 Gent, België',
      ),
      'Heenrit Koekamerstraat 48A → Korenmarkt 1',
    );
    expect(companyCrewComboGroups([karel, karelVan, amira]).length, 2);
    expect(companyCrewComboGroups([karel, karelVan]).first.combos.length, 2);
  });
}
