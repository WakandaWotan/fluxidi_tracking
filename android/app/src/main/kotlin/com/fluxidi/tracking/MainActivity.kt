package com.fluxidi.tracking

import android.content.res.Configuration
import com.fluxidi.tracking.externalnav.ExternalNavigationPlugin
import com.fluxidi.tracking.nativefollow.FluxidiNativeFollowPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
  private var externalNavigationPlugin: ExternalNavigationPlugin? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    // FLUXIDI NAV-STREETLEVEL-FLUID-MOTION-2 Phase 2A: app-local plugin that
    // exposes the typed Pigeon `NativeFollowHostApi` used by the Dart-side
    // NativeFollowController to feed route-snapped poses to a custom Mapbox
    // LocationProvider + FollowPuckViewportState + LocationPuck3D on the
    // exact FlutterMapView owned by mapbox_maps_flutter.
    flutterEngine.plugins.add(FluxidiNativeFollowPlugin())

    // GOOGLE-MAPS-DIRECT-LAUNCH-ANDROID-1: explicit Maps package launch + PiP.
    val plugin = ExternalNavigationPlugin()
    externalNavigationPlugin = plugin
    flutterEngine.plugins.add(plugin)
  }

  override fun onPictureInPictureModeChanged(
    isInPictureInPictureMode: Boolean,
    newConfig: Configuration,
  ) {
    super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
    externalNavigationPlugin?.onPictureInPictureModeChanged(isInPictureInPictureMode)
  }

  @Deprecated("Deprecated in Java")
  override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
    super.onPictureInPictureModeChanged(isInPictureInPictureMode)
    externalNavigationPlugin?.onPictureInPictureModeChanged(isInPictureInPictureMode)
  }
}
