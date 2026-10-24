import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_crew_combo.dart';
import 'package:fluxidi_tracking/company/company_dispatch.dart';
import 'package:fluxidi_tracking/company/company_dispatch_advice.dart';
import 'package:fluxidi_tracking/company/company_plan_presence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const available = CompanyPlanPresence(
    tone: CompanyPlanPresenceTone.available,
    code: 'available',
    icon: Icons.check_circle_outline,
  );

  CompanyCrewCombo combo(String driverId, String name, String vehicle) {
    return CompanyCrewCombo(
      driverId: driverId,
      vehicleId: vehicle,
      driver: <String, dynamic>{'driver_id': driverId, 'display_name': name},
      vehicle: <String, dynamic>{
        'vehicle_id': vehicle,
        'display_name': vehicle,
        'vehicle_type': 'van',
      },
      presence: available,
    );
  }

  CompanyDispatchAdvice liveAdvice({
    required String recommended,
    required List<CompanyDispatchCandidate> candidates,
  }) {
    return CompanyDispatchAdvice(
      mode: 'live_eta',
      recommendedDriverId: recommended,
      candidates: candidates,
    );
  }

  test('240 seconds becomes 4 minutes and only a live candidate shows it', () {
    final advice = parseCompanyDispatchAdvice(<String, dynamic>{
      'assigned': false,
      'dispatch_mode': 'live_eta',
      'recommended_driver_id': 'a',
      'dispatch_candidates': [
        {
          'driver_id': 'a',
          'vehicle_id': 'TEST-VITO-1',
          'eta_seconds': 240,
          'location_feed': 'live',
          'reliable_for_eta': true,
          'latitude': 51.2,
          'longitude': 4.4,
        },
        {
          'driver_id': 'b',
          'eta_seconds': 540,
          'location_feed': 'live',
          'reliable_for_eta': true,
        },
        {
          'driver_id': 'c',
          'eta_seconds': 90,
          'location_feed': 'stale',
          'reliable_for_eta': false,
        },
      ],
    });
    final a = companyDispatchDriverNote(
      advice: advice,
      driverId: 'a',
      language: AppLanguage.nl,
    );
    final b = companyDispatchDriverNote(
      advice: advice,
      driverId: 'b',
      language: AppLanguage.nl,
    );
    final c = companyDispatchDriverNote(
      advice: advice,
      driverId: 'c',
      language: AppLanguage.nl,
    );
    expect(a.recommended, isTrue);
    expect(a.etaLine, '± 4 min naar ophaalpunt');
    expect(b.recommended, isFalse);
    expect(b.etaLine, '± 9 min');
    expect(c.etaLine, isEmpty);
    expect(c.recommended, isFalse);
    expect('${a.etaLine} ${b.etaLine}', isNot(contains('51.2')));
    expect(advice!.candidates.first.driverId, 'a');
  });

  test('schedule fallback and a payload without dispatch fields invent no ETA', () {
    final fallback = parseCompanyDispatchAdvice(<String, dynamic>{
      'dispatch_mode': 'schedule_fallback',
      'recommended_driver_id': 'a',
      'dispatch_candidates': [
        {
          'driver_id': 'a',
          'eta_seconds': 240,
          'location_feed': 'live',
          'reliable_for_eta': true,
        },
      ],
    });
    expect(
      companyDispatchDriverNote(
        advice: fallback,
        driverId: 'a',
        language: AppLanguage.nl,
      ).etaLine,
      isEmpty,
    );
    expect(
      companyDispatchAdviceNotice(fallback, AppLanguage.nl),
      'Planning beschikbaar — live ETA niet beschikbaar',
    );
    expect(
      parseCompanyDispatchAdvice(<String, dynamic>{
        'ok': true,
        'drivers': [
          {'driver_id': 'a'},
        ],
      }),
      isNull,
    );
    expect(
      companyDispatchAdviceNotice(
        const CompanyDispatchAdvice.unavailable(),
        AppLanguage.nl,
      ),
      isNotEmpty,
    );
  });

  test('an older advice token cannot replace a newer one', () {
    final slot = CompanyDispatchAdviceSlot();
    final first = slot.begin();
    final second = slot.begin();
    expect(
      slot.apply(
        second,
        liveAdvice(
          recommended: 'b',
          candidates: const [
            CompanyDispatchCandidate(
              driverId: 'b',
              vehicleId: 'v',
              etaSeconds: 120,
              locationFeed: 'live',
              reliableForEta: true,
            ),
          ],
        ),
      ),
      isTrue,
    );
    expect(
      slot.apply(
        first,
        liveAdvice(recommended: 'a', candidates: const []),
      ),
      isFalse,
    );
    expect(slot.advice!.recommendedDriverId, 'b');
  });

  test('choices without new fields keep the existing driver list', () {
    final parsed = parseCompanyDispatchAdvice(<String, dynamic>{
      'ok': true,
      'soon': true,
      'drivers': [
        {'driver_id': 'keep'},
      ],
    });
    expect(parsed, isNull);
    const choices = CompanyAssignmentChoices(
      drivers: [
        {'driver_id': 'keep'},
      ],
    );
    expect(choices.drivers.single['driver_id'], 'keep');
    expect(choices.advice, isNull);
  });

  testWidgets('manual choice stays put while the recommendation moves', (
    tester,
  ) async {
    await _pumpPlanner(
      tester,
      size: const Size(1280, 800),
      advice: liveAdvice(
        recommended: 'a',
        candidates: const [
          CompanyDispatchCandidate(
            driverId: 'a',
            vehicleId: 'TEST-VITO-1',
            etaSeconds: 360,
            locationFeed: 'live',
            reliableForEta: true,
          ),
          CompanyDispatchCandidate(
            driverId: 'b',
            vehicleId: 'TEST-PW-2',
            etaSeconds: 540,
            locationFeed: 'live',
            reliableForEta: true,
          ),
          CompanyDispatchCandidate(
            driverId: 'c',
            vehicleId: 'TEST-OLD',
            etaSeconds: 60,
            locationFeed: 'stale',
            reliableForEta: false,
          ),
        ],
      ),
      combos: [
        combo('a', 'TEST-chauffeur 8', 'TEST-VITO-1'),
        combo('b', 'TEST-chauffeur 3', 'TEST-PW-2'),
        combo('c', 'TEST-chauffeur 1', 'TEST-OLD'),
      ],
    );
    await tester.tap(find.byKey(kCompanyCrewComboOpenKey));
    await tester.pumpAndSettle();
    expect(find.text('Aanbevolen'), findsOneWidget);
    expect(find.text('± 6 min naar ophaalpunt'), findsOneWidget);
    expect(find.text('± 9 min'), findsOneWidget);
    expect(find.textContaining('51.'), findsNothing);
    expect(find.byKey(const Key('company_dispatch_eta_c')), findsNothing);

    await tester.tap(find.byKey(const Key('company_crew_combo_b|TEST-PW-2')));
    await tester.pumpAndSettle();
    final state = tester.state<_AdviceHarnessState>(find.byType(_AdviceHarness));
    expect(state.selectedId, 'b|TEST-PW-2');

    state.advice = liveAdvice(
      recommended: 'b',
      candidates: const [
        CompanyDispatchCandidate(
          driverId: 'a',
          vehicleId: 'TEST-VITO-1',
          etaSeconds: 360,
          locationFeed: 'live',
          reliableForEta: true,
        ),
        CompanyDispatchCandidate(
          driverId: 'b',
          vehicleId: 'TEST-PW-2',
          etaSeconds: 300,
          locationFeed: 'live',
          reliableForEta: true,
        ),
      ],
    );
    state.rebuild();
    await tester.pumpAndSettle();
    expect(state.selectedId, 'b|TEST-PW-2');

    await tester.tap(find.byKey(kCompanyCrewComboOpenKey));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('company_dispatch_recommended_b')), findsOneWidget);
    expect(find.byKey(const Key('company_dispatch_recommended_a')), findsNothing);
    expect(state.selectedId, 'b|TEST-PW-2');
  });

  testWidgets('phone tablet and windows layouts keep the advice readable', (
    tester,
  ) async {
    final advice = liveAdvice(
      recommended: 'a',
      candidates: const [
        CompanyDispatchCandidate(
          driverId: 'a',
          vehicleId: 'TEST-VITO-1',
          etaSeconds: 360,
          locationFeed: 'live',
          reliableForEta: true,
        ),
        CompanyDispatchCandidate(
          driverId: 'b',
          vehicleId: 'TEST-PW-2',
          etaSeconds: 540,
          locationFeed: 'live',
          reliableForEta: true,
        ),
      ],
    );
    final combos = [
      combo('a', 'TEST-chauffeur 8', 'TEST-VITO-1'),
      combo('b', 'TEST-chauffeur 3', 'TEST-PW-2'),
    ];
    for (final shot in const <(Size, String)>[
      (Size(390, 844), 'phone'),
      (Size(800, 1280), 'tablet'),
      (Size(1280, 800), 'windows'),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await _pumpPlanner(
        tester,
        size: shot.$1,
        advice: advice,
        combos: combos,
      );
      await tester.tap(find.byKey(kCompanyCrewComboOpenKey));
      await tester.pumpAndSettle();
      expect(find.text('Aanbevolen'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => _writeShot(tester, shot.$2));
    }
  });

  testWidgets('schedule fallback shows no invented ETA', (tester) async {
    await _pumpPlanner(
      tester,
      size: const Size(390, 844),
      advice: const CompanyDispatchAdvice(mode: 'schedule_fallback'),
      combos: [combo('a', 'TEST-chauffeur 8', 'TEST-VITO-1')],
    );
    await tester.tap(find.byKey(kCompanyCrewComboOpenKey));
    await tester.pumpAndSettle();
    expect(
      find.text('Planning beschikbaar — live ETA niet beschikbaar'),
      findsOneWidget,
    );
    expect(find.textContaining('min naar ophaalpunt'), findsNothing);
    expect(find.byKey(const Key('company_crew_combo_a|TEST-VITO-1')), findsOneWidget);
  });
}

Future<void> _pumpPlanner(
  WidgetTester tester, {
  required Size size,
  required CompanyDispatchAdvice? advice,
  required List<CompanyCrewCombo> combos,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: _AdviceHarness(advice: advice, combos: combos),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _AdviceHarness extends StatefulWidget {
  const _AdviceHarness({required this.advice, required this.combos});

  final CompanyDispatchAdvice? advice;
  final List<CompanyCrewCombo> combos;

  @override
  State<_AdviceHarness> createState() => _AdviceHarnessState();
}

class _AdviceHarnessState extends State<_AdviceHarness> {
  late CompanyDispatchAdvice? advice = widget.advice;
  String selectedId = '';

  void rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return CompanyCrewComboPicker(
      language: AppLanguage.nl,
      title: 'Chauffeur',
      combos: widget.combos,
      selectedId: selectedId,
      advice: advice,
      onSelected: (id) => setState(() => selectedId = id),
    );
  }
}

Future<void> _writeShot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('company_dispatch_advice_shot')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('.qa-local/dispatch_advice/$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
}
