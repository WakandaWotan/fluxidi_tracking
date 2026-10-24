package com.fluxidi.tracking

import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ResultReceiver
import android.util.Log
import com.fluxidi.tracking.externalnav.ExternalNavigationPlugin
import com.fluxidi.tracking.nativefollow.FluxidiNativeFollowPlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
  private var externalNavigationPlugin: ExternalNavigationPlugin? = null
  private var vehicleRideAlert: VehicleRideAlert? = null
  private var offlineDownloadBridge: FluxidiOfflineDownloadBridge? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MapLibreRendererBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    offlineDownloadBridge = FluxidiOfflineDownloadBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    vehicleRideAlert = VehicleRideAlert(this, flutterEngine.dartExecutor.binaryMessenger) {
      lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED) && hasWindowFocus()
    }
    io.flutter.plugin.common.MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fluxidi/driver_duty").setMethodCallHandler { call, result ->
      when(call.method) {
        "running" -> result.success(DriverDutyService.status(call.argument<String>("activation_id")).running)
        "status" -> {
          val arguments = call.arguments as? Map<*, *>
          val expected = DriverDutyExpectedConfig.fromMap(arguments?.get("expected_config") as? Map<*, *>)
          val status = if (arguments?.containsKey("expected_config") == true && expected == null) DriverDutyStatus(reason = "owner_not_current")
            else DriverDutyService.status(call.argument<String>("activation_id"), expected)
          result.success(mapOf("running" to status.running, "activation_id" to status.activationId,
            "native_device_id" to if (expected != null && status.running) status.nativeDeviceId else "",
            "state" to status.state, "reason" to status.reason))
        }
        "consent" -> result.success(getPreferences(MODE_PRIVATE).getBoolean("duty_consent", false))
        "stop" -> result.success(DriverDutyService.stopOwned(this, call.argument<String>("activation_id")))
        "start" -> {
          if(!lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)) { result.success(false) }
          else try {
            if(call.argument<Boolean>("accepted") != true) { result.success(false) }
            else {
              getPreferences(MODE_PRIVATE).edit().putBoolean("duty_consent", true).apply()
              val lease = DriverDutyService.prepareStart(call.argument<String>("activation_id"),
                call.argument<String>("token") ?: "", call.argument<String>("booking") ?: "",
                call.argument<String>("tracking") ?: "", DriverDutyService.ensureNativeDeviceId(this),
                DriverDutyActor(call.argument<String>("tenant_id") ?: "", call.argument<String>("company_id") ?: "",
                  call.argument<String>("driver_id") ?: "", call.argument<String>("vehicle_id") ?: ""),
                call.argument<String>("title") ?: "Fluxidi", call.argument<String>("text") ?: "")
              val handler = Handler(Looper.getMainLooper())
              var completed = false
              val timeout = Runnable {
                if (!completed) {
                  completed = true
                  DriverDutyService.failedStart(this, lease, "start_timeout")
                  result.success(false)
                }
              }
              val ready = object : ResultReceiver(handler) {
                override fun onReceiveResult(resultCode: Int, data: Bundle?) {
                  if (completed) return
                  completed = true
                  handler.removeCallbacks(timeout)
                  result.success(resultCode == 1 && DriverDutyService.isReady(lease))
                }
              }
              val service = Intent(this, DriverDutyService::class.java)
              service.putExtra("token", lease.token).putExtra("booking", lease.booking).putExtra("tracking", lease.tracking)
                .putExtra("title", lease.title).putExtra("text", lease.text)
                .putExtra("tenant_id", lease.actor.tenantId).putExtra("company_id", lease.actor.companyId)
                .putExtra("driver_id", lease.actor.driverId).putExtra("vehicle_id", lease.actor.vehicleId)
              service.putExtra("activation_id", lease.activationId)
                .putExtra("native_device_id", lease.nativeDeviceId)
                .putExtra("generation", lease.generation).putExtra("ready_receiver", ready)
              handler.postDelayed(timeout, 8000L)
              try {
                if(android.os.Build.VERSION.SDK_INT >= 26) startForegroundService(service) else startService(service)
              } catch (_: Exception) {
                completed = true
                handler.removeCallbacks(timeout)
                DriverDutyService.failedStart(this, lease, "start_failed")
                result.success(false)
              }
            }
          } catch(_: Exception) { result.success(false) }
        }
        "gpsSampleEvidence" -> {
          if ((applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0)
            result.success(DriverDutyService.gpsSampleEvidence()) else result.notImplemented()
        }
        else -> result.notImplemented()
      }
    }
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
    // Must precede super: FlutterFragment reads shell args while creating engine.
    if (NavigationRendererCompatibility.useLegacyRenderer(
        android.os.Build.MANUFACTURER, android.os.Build.MODEL, android.os.Build.VERSION.SDK_INT)) {
      intent.putExtra(io.flutter.embedding.engine.FlutterShellArgs.ARG_KEY_TOGGLE_IMPELLER, false)
      Log.i("FluxidiRenderer", "compatibility=sm_x400_android16 renderer=skia_opengl")
    }
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

  override fun onPause() {
    vehicleRideAlert?.handoff()
    super.onPause()
  }

  override fun onDestroy() {
    offlineDownloadBridge?.dispose()
    offlineDownloadBridge = null
    vehicleRideAlert?.dispose()
    vehicleRideAlert = null
    super.onDestroy()
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
