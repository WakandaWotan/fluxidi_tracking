import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:fluxidi_tracking/maps/fluxidi_maplibre_points_map.dart';

class Port implements MapLibreMapController {
  @override final onCircleTapped = ArgumentCallbacks<Circle>();
  List<Circle> renderedCircles = [];
  List<Line> renderedLines = [];
  Completer<void>? hold;
  int cameraCalls = 0, serial = 0;
  @override Future<void> clearCircles() async { renderedCircles = []; }
  @override Future<void> clearLines() async { renderedLines = []; }
  @override Future<List<Circle>> addCircles(List<CircleOptions> options,
      [List<Map<String, dynamic>>? data]) async {
    final pause = hold;
    hold = null;
    if (pause != null) await pause.future;
    return renderedCircles = [for (final o in options) Circle('${serial++}', o)];
  }
  @override Future<Line> addLine(LineOptions options, [Map<String, dynamic>? data]) async {
    final line = Line('${serial++}', options);
    renderedLines.add(line);
    return line;
  }
  @override Future<bool?> animateCamera(CameraUpdate update, {Duration? duration}) async {
    cameraCalls++;
    return true;
  }
  @override dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('${invocation.memberName}');
}

void main() {
  setUp(() => rootBundle.clear());
  Widget view(Map<String, LatLng> points, List<String> selected,
      {bool dark = true, List<LatLng> ring = const []}) => MaterialApp(home: Scaffold(
        body: FluxidiMapLibrePointsMap(points: points, center: const LatLng(51, 4),
          zoom: 10, dark: dark, ring: ring, onTap: selected.add)));
  Future<MapLibreMap> ready(WidgetTester tester, {String? sprite}) async {
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      if (find.byType(MapLibreMap).evaluate().isNotEmpty &&
          (sprite == null || tester.widget<MapLibreMap>(find.byType(MapLibreMap)).styleString.contains(sprite))) break;
    }
    return tester.widget<MapLibreMap>(find.byType(MapLibreMap));
  }

  testWidgets('own style, correct event tap, no camera reset for unchanged rebuild', (tester) async {
    final selected = <String>[], port = Port();
    const points = {'event': LatLng(51, 4)};
    await tester.pumpWidget(view(points, selected));
    final map = await ready(tester);
    expect(map.styleString, isNot(contains('mapbox')));
    expect(map.styleString, contains('/country/releases/be-nl-20261013-rectangle-v1/tiles/'));
    map.onMapCreated!(port);
    map.onStyleLoadedCallback!();
    await tester.pumpAndSettle();
    port.onCircleTapped(port.renderedCircles.single);
    expect(selected, ['event']);
    final cameraCalls = port.cameraCalls;
    await tester.pumpWidget(view(Map.of(points), selected));
    await tester.pumpAndSettle();
    expect(port.cameraCalls, cameraCalls);
    await tester.pumpWidget(const SizedBox());
    expect(port.onCircleTapped.isEmpty, isTrue);
  });

  testWidgets('late old markers cannot select a removed event; latest list wins', (tester) async {
    final selected = <String>[], port = Port(), hold = Completer<void>();
    port.hold = hold;
    await tester.pumpWidget(view({'old': const LatLng(51, 4)}, selected));
    final map = await ready(tester);
    map.onMapCreated!(port);
    map.onStyleLoadedCallback!();
    await tester.pump();
    await tester.pumpWidget(view({'new': const LatLng(52, 5)}, selected));
    hold.complete();
    await tester.pumpAndSettle();
    expect(port.renderedCircles.single.options.geometry, const LatLng(52, 5));
    port.onCircleTapped(Circle('0', const CircleOptions()));
    expect(selected, isEmpty);
    port.onCircleTapped(port.renderedCircles.single);
    expect(selected, ['new']);
    await tester.pumpWidget(view({}, selected));
    await tester.pumpAndSettle();
    expect(port.renderedCircles, isEmpty);
  });

  testWidgets('a failed superseded annotation update cannot hide the newest points', (tester) async {
    final selected = <String>[], port = Port(), hold = Completer<void>();
    port.hold = hold;
    await tester.pumpWidget(view({'old': const LatLng(51, 4)}, selected));
    final map = await ready(tester);
    map.onMapCreated!(port);
    map.onStyleLoadedCallback!();
    await tester.pump();
    await tester.pumpWidget(view({'new': const LatLng(52, 5)}, selected));
    hold.completeError(StateError('obsolete renderer operation'));
    await tester.pumpAndSettle();
    expect(find.text('Kaart tijdelijk niet beschikbaar'), findsNothing);
    expect(port.renderedCircles.single.options.geometry, const LatLng(52, 5));
    port.onCircleTapped(port.renderedCircles.single);
    expect(selected, ['new']);
  });

  testWidgets('radius geometry preserved and restored after light/dark style reload', (tester) async {
    final selected = <String>[], port = Port();
    const ring = [LatLng(51, 4), LatLng(52, 5), LatLng(51, 4)];
    await tester.pumpWidget(view({'company': const LatLng(51, 4)}, selected, ring: ring));
    var map = await ready(tester);
    map.onMapCreated!(port);
    map.onStyleLoadedCallback!();
    await tester.pumpAndSettle();
    expect(port.renderedLines.single.options.geometry, ring);
    await tester.pumpWidget(view({'company': const LatLng(51, 4)}, selected, ring: ring, dark: false));
    map = await ready(tester, sprite: '/sprites/light');
    map.onStyleLoadedCallback!();
    await tester.pumpAndSettle();
    expect(map.styleString, contains('/sprites/light'));
    expect(port.renderedLines.single.options.geometry, ring);
    expect(port.renderedCircles, hasLength(1));
  });
}
