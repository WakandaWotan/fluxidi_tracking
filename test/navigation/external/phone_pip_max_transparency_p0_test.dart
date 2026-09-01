// PHONE-PIP-MAX-TRANSPARENCY-P0
//
// Phone PiP floats over Google Maps — light glass plate, outlined KPIs,
// no duplicate Fare/status heading. Tablet path stays opaque.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_pip_meter.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_session.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

ExternalNavPipMeterModel _nlActive() {
  return buildExternalNavPipMeterModel(
    phase: ExternalNavPhase.activeRide,
    isStreetRide: true,
    isFixedPrice: false,
    language: AppLanguage.nl,
    liveFareText: '€ 5,30',
    kmText: '1.2 km',
    durationText: '00:35:00',
    waitText: '00:00:20',
  );
}

void main() {
  group('phone PiP surface tokens', () {
    test('outer floor stays in the 15–22% band; KPI cells clear', () {
      expect(PhonePipSurfaceOpacity.outer, inInclusiveRange(0.15, 0.22));
      expect(PhonePipSurfaceOpacity.kpiCell, 0.0);
      expect(PhonePipSurfaceOpacity.plate.a, closeTo(0.18, 0.02));
    });

    test('compact duration drops trailing zero seconds', () {
      expect(compactPipDurationText('00:35:00'), '00:35');
      expect(compactPipDurationText('01:05:12'), '01:05:12');
      expect(compactPipDurationText(''), '');
    });

    test('large grid gate vs compact line', () {
      expect(
        resolvePhonePipUsesLargeGrid(maxWidth: 240, maxHeight: 135),
        isTrue,
      );
      expect(
        resolvePhonePipUsesLargeGrid(maxWidth: 140, maxHeight: 78),
        isFalse,
      );
      expect(resolvePhonePipMetricTier(80), 1);
      expect(resolvePhonePipMetricTier(100), 2);
      expect(resolvePhonePipMetricTier(130), 4);
    });
  });

  group('phone PiP widget chrome', () {
    testWidgets('large phone PiP: 2×2 labels, no title/status/Fare heading', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(240, 135));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(240, 135)),
          child: MaterialApp(
            home: ExternalNavPipMeterCard(
              model: _nlActive(),
              hostIsTablet: false,
            ),
          ),
        ),
      );
      await tester.pump();

      // Outlined glyphs paint stroke+fill Text pairs.
      expect(find.text('Tarief'), findsWidgets);
      expect(find.text('Ritduur'), findsWidgets);
      expect(find.text('Afstand'), findsWidgets);
      expect(find.text('Wachttijd'), findsWidgets);
      expect(find.text('€ 5,30'), findsWidgets);
      expect(find.text('Naar bestemming'), findsNothing);
      expect(find.text('Rit actief'), findsNothing);
      expect(find.text('Ride active'), findsNothing);

      final material = tester.widget<Material>(find.byType(Material).first);
      expect(material.type, MaterialType.transparency);
    });

    testWidgets('small phone PiP: fare · duration line without labels', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(140, 78));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(140, 78)),
          child: MaterialApp(
            home: ExternalNavPipMeterCard(
              model: _nlActive(),
              hostIsTablet: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('€ 5,30 · 00:35'), findsWidgets);
      expect(find.text('Tarief'), findsNothing);
      expect(find.text('Ritduur'), findsNothing);
      expect(find.text('Naar bestemming'), findsNothing);
    });

    testWidgets('tablet PiP stays opaque dark plate', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 180));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(320, 180)),
          child: MaterialApp(
            home: ExternalNavPipMeterCard(
              model: _nlActive(),
              hostIsTablet: true,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Naar bestemming'), findsOneWidget);
      final materials = tester.widgetList<Material>(find.byType(Material));
      expect(
        materials.any((m) => m.color == const Color(0xFF0B0F14)),
        isTrue,
      );
    });
  });

  group('source contracts', () {
    test('Android disables seamless resize; phone surface alpha logged', () {
      final plugin = _read(
        'android/app/src/main/kotlin/com/fluxidi/tracking/externalnav/ExternalNavigationPlugin.kt',
      );
      expect(plugin, contains('setSeamlessResizeEnabled(false)'));
      expect(plugin, contains('pip_phone_surface_alpha=0.18'));
      expect(plugin, contains('applyPhonePipWindowSurface'));
    });

    test('host scaffold transparent only for phone PiP', () {
      final home = _read('lib/main_parts/driver_home_page_state.dart');
      expect(home, contains('pipHostTablet'));
      expect(
        RegExp(
          r'pipHostTablet\s*\?\s*const Color\(0xFF0B0F14\)\s*:\s*'
          r'Colors\.transparent',
        ).hasMatch(home),
        isTrue,
        reason:
            'Phone PiP scaffold must be transparent; tablet stays opaque. '
            'The ternary may be wrapped across lines.',
      );
    });
  });
}
