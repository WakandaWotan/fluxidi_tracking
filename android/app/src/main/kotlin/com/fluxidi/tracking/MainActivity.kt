package com.fluxidi.tracking

import com.fluxidi.tracking.nativefollow.FluxidiNativeFollowPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    // FLUXIDI NAV-STREETLEVEL-FLUID-MOTION-2 Phase 2A: app-local plugin that
    // exposes the typed Pigeon `NativeFollowHostApi` used by the Dart-side
    // NativeFollowController to feed route-snapped poses to a custom Mapbox
    // LocationProvider + FollowPuckViewportState + LocationPuck3D on the
    // exact FlutterMapView owned by mapbox_maps_flutter.
    flutterEngine.plugins.add(FluxidiNativeFollowPlugin())
  }
}
