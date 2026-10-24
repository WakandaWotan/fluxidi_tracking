import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

// Widget regressions exercise Flutter booking/camera state, not an Android
// embedder. Native renderer/gesture acceptance remains a separate device gate.
class SurfaceOnlyMapLibrePlatform extends MapLibrePlatform {
  @override
  Widget buildView(Map<String, dynamic> creationParams,
      OnPlatformViewCreatedCallback onPlatformViewCreated,
      Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers) =>
      const SizedBox.expand(key: ValueKey('fixture_maplibre_native_surface'));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  MapLibrePlatform.createInstance = () => SurfaceOnlyMapLibrePlatform();
  await testMain();
}
