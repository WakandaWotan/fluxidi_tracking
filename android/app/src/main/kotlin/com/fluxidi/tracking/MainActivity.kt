package com.fluxidi.tracking

import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import android.util.Log
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

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    // Cold-start return from PiP RemoteAction (idempotent / consume-once).
    externalNavigationPlugin?.handleReturnFromPipIntent(intent)
  }

  /**
   * PIP-ACTIVITY-RETURN-TO-FLUXIDI-P0-6: singleTop delivers return intents here
   * instead of spawning a duplicate MainActivity.
   */
  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    Log.i("FluxidiMainActivity", "on_new_intent_called=true")
    externalNavigationPlugin?.handleReturnFromPipIntent(intent)
  }

  override fun onResume() {
    super.onResume()
    Log.i("FluxidiMainActivity", "on_resume_called=true")
    // ANDROID-RECENTS-PIP-AUTOENTER-P0: clear sticky auto-enter when we are
    // full-screen again so Home/Recents regain normal Android task behavior.
    externalNavigationPlugin?.onActivityResumed()
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
