import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_traffic_banner.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_traffic_controller.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_traffic_renderer.dart';
import 'traffic_fixtures.dart';

Map<String, dynamic> distribution(List<int> micros) {
  micros.sort();
  double percentile(double fraction) =>
      micros[((micros.length - 1) * fraction).round()] / 1000;
  return {
    'samples': micros.length,
    'p50_ms': percentile(.5),
    'p95_ms': percentile(.95),
    'p99_ms': percentile(.99),
    'max_ms': micros.last / 1000,
  };
}

void main() {
  testWidgets(
    'measured preparation, refresh, progress writes, RSS and widget pumps',
    (tester) async {
      final route = List.generate(
        6001,
        (i) => DriverLonLat(4.4 + i * .00001, 51.2 + (i % 300) * .000001),
      );
      final wire = trafficWire(
        geometry: route,
        segments: [
          for (var i = 0; i < 24; i++)
            trafficSegment(
              start: i * 250,
              end: (i + 1) * 250,
              traffic: i % 3 == 0
                  ? 'normal'
                  : i % 3 == 1
                  ? 'light'
                  : 'heavy',
            ),
        ],
      );
      final controller = NavigationTrafficController();
      final theme = ValueNotifier(DriverThemeVariant.nightGold);
      addTearDown(controller.dispose);
      addTearDown(theme.dispose);
      final basePrep = <int>[], trafficPrep = <int>[], refresh = <int>[];
      final watch = Stopwatch();
      // Warm JIT/cache before collecting preparation timings.
      for (var i = 0; i < 20; i++) {
        mb.LineString(
          coordinates: route.map((p) => mb.Position(p.lon, p.lat)).toList(),
        );
        controller.install(
          geometry: route,
          snapshot: decodeFixture(wire, geometry: route),
          now: trafficNow,
        );
      }
      final rssBefore = ProcessInfo.currentRss;
      for (var i = 0; i < 100; i++) {
        watch
          ..reset()
          ..start();
        final geometry = mb.LineString(
          coordinates: route.map((p) => mb.Position(p.lon, p.lat)).toList(),
        );
        mb.PolylineAnnotationOptions(
          geometry: geometry,
          lineColor: 0xFF2B6CB0,
          lineWidth: 11,
        );
        watch.stop();
        basePrep.add(watch.elapsedMicroseconds);
        watch
          ..reset()
          ..start();
        controller.spansAt(trafficNow);
        watch.stop();
        trafficPrep.add(watch.elapsedMicroseconds);
        watch
          ..reset()
          ..start();
        controller.install(
          geometry: route,
          snapshot: decodeFixture(wire, geometry: route),
          now: trafficNow,
        );
        watch.stop();
        refresh.add(watch.elapsedMicroseconds);
      }
      final rssAfter = ProcessInfo.currentRss;
      final renderer = NavigationTrafficRenderer<int>();
      var creates = 0, updates = 0, deletes = 0, maxHandles = 0;
      final projection = <int>[];
      for (var i = 0; i < 600; i++) {
        watch
          ..reset()
          ..start();
        controller.updateProgress(i * 5.0, trusted: true, now: trafficNow);
        final spans = controller.spansAt(trafficNow);
        watch.stop();
        projection.add(watch.elapsedMicroseconds);
        await renderer.sync(
          spans: spans,
          isCurrent: () => true,
          create: (_) async => ++creates,
          update: (_, __) async {
            updates++;
          },
          delete: (_) async {
            deletes++;
          },
        );
        if (renderer.handleCount > maxHandles)
          maxHandles = renderer.handleCount;
      }
      final stableUpdatesBefore = updates;
      for (var i = 0; i < 100; i++) {
        await renderer.sync(
          spans: controller.spansAt(trafficNow),
          isCurrent: () => true,
          create: (_) async => ++creates,
          update: (_, __) async {
            updates++;
          },
          delete: (_) async {
            deletes++;
          },
        );
      }
      final stableExtraUpdates = updates - stableUpdatesBefore;
      expect(creates, 24);
      expect(maxHandles, lessThanOrEqualTo(24));
      expect(stableExtraUpdates, 0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NavigationTrafficBannerHost(
              alertListenable: controller.alert,
              themeListenable: theme,
              languageCode: 'nl',
              child: const SizedBox(height: 60, child: Text('Volg de route')),
            ),
          ),
        ),
      );
      final pumps = <int>[];
      for (var i = 0; i < 120; i++) {
        controller.updateProgress(
          3000.0 + i * 5,
          trusted: true,
          now: trafficNow,
        );
        watch
          ..reset()
          ..start();
        await tester.pump(const Duration(milliseconds: 320));
        watch.stop();
        pumps.add(watch.elapsedMicroseconds);
        expect(tester.takeException(), isNull);
      }
      final evidence = {
        'environment':
            'Flutter automated widget test, Windows, debug/JIT, 6001 vertices, 24 segments',
        'route_render_preparation': distribution(basePrep),
        'traffic_overlay_preparation': distribution(trafficPrep),
        'route_traffic_refresh_decode_and_install': distribution(refresh),
        'progress_and_overlay_projection': distribution(projection),
        'widget_pump_wall_time': distribution(pumps),
        'memory': {
          'process_rss_before_bytes': rssBefore,
          'process_rss_after_bytes': rssAfter,
          'delta_bytes': rssAfter - rssBefore,
          'attribution':
              'Whole test process; not retained heap or native annotation memory',
        },
        'renderer_mock': {
          'progress_inputs': 600,
          'creates': creates,
          'updates': updates,
          'deletes': deletes,
          'max_handles': maxHandles,
          'unchanged_frame_extra_native_writes': stableExtraUpdates,
        },
        'native_mapbox_render_time': 'NOT_MEASURED',
        'native_frame_stability': 'NOT_MEASURED',
        'native_memory': 'NOT_MEASURED',
        'battery_consumption': 'NOT_MEASURED',
        'interpretation':
            'Preparation and test-process measurements only; no handset FPS, native rendering or battery certification',
      };
      Directory('artifacts/navigation_traffic_visuals').createSync(recursive: true);
      File(
        'artifacts/navigation_traffic_visuals/performance.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(evidence));
    },
  );
}
