import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as legacy;
import 'package:maplibre_gl/maplibre_gl.dart' as libre;
import 'package:fluxidi_tracking/navigation/rendering/driver_maplibre_surface.dart';

class NoNativeCalls implements libre.MapLibreMapController {
  @override dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected native call: ${invocation.memberName}');
}

void main() {
  setUp(() => rootBundle.clear());
  Future<DriverMapLibreMap> open(WidgetTester tester) async {
    final ready = Completer<DriverMapLibreMap>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      DriverMapLibreMap.native, (_) async => null);
    await tester.pumpWidget(MaterialApp(home: DriverMapLibreSurface(
      styleUri: 'fluxidi-maplibre://light',
      cameraOptions: legacy.CameraOptions(center: legacy.Point(coordinates: legacy.Position(4, 51))),
      onMapCreated: (map) async { ready.complete(map); })));
    for(var i=0;i<80 && find.byType(libre.MapLibreMap).evaluate().isEmpty;i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    final widget = tester.widget<libre.MapLibreMap>(find.byType(libre.MapLibreMap));
    widget.onMapCreated!(NoNativeCalls()); widget.onStyleLoadedCallback!();
    await tester.pump();
    return ready.future;
  }
  testWidgets('light to perspective uses identical local style and must not wait for absent native callback', (tester) async {
    final map = await open(tester);
    final before = tester.widget<libre.MapLibreMap>(find.byType(libre.MapLibreMap)).styleString;
    var done = false;
    final request = map.style.setStyleURI('fluxidi-maplibre://3d').then((_) { done=true; });
    for(var i=0;i<20;i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    expect(tester.widget<libre.MapLibreMap>(find.byType(libre.MapLibreMap)).styleString, before);
    expect(done, isTrue, reason: 'No new styleString means no new onStyleLoaded callback from the engine');
    expect(await map.style.isStyleLoaded(), isTrue);
    await request;
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('changed style requires genuine callback before readiness', (tester) async {
    final map = await open(tester);
    var done=false;
    final request=map.style.setStyleURI('fluxidi-maplibre://dark').then((_){done=true;});
    for(var i=0;i<20;i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    expect(done,isFalse); expect(await map.style.isStyleLoaded(),isFalse);
    tester.widget<libre.MapLibreMap>(find.byType(libre.MapLibreMap)).onStyleLoadedCallback!();
    await tester.pump(); await request;
    expect(done,isTrue); expect(await map.style.isStyleLoaded(),isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('missing native callback fails within a bound without pretending the style loaded', (tester) async {
    final map=await open(tester);
    final failure=expectLater(map.style.setStyleURI('fluxidi-maplibre://dark'), throwsA(isA<TimeoutException>()));
    for(var i=0;i<20;i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 16)); await failure;
    expect(await map.style.isStyleLoaded(),isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
