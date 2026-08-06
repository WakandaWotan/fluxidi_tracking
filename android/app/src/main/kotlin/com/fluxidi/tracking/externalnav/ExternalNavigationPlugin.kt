package com.fluxidi.tracking.externalnav

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import android.util.Rational
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * GOOGLE-MAPS-DIRECT-LAUNCH-ANDROID-1 / GOOGLE-MAPS-PIP-HANDOFF-P0-1
 *
 * Platform channel: fluxidi.external_navigation
 *
 * Correct handoff: prepare PiP params → dispatch Maps → enter PiP only after
 * a successful startActivity (or via Android 12+ auto-enter on leave).
 */
class ExternalNavigationPlugin :
  FlutterPlugin,
  MethodChannel.MethodCallHandler,
  EventChannel.StreamHandler,
  ActivityAware {

  companion object {
    const val CHANNEL = "fluxidi.external_navigation"
    const val EVENTS = "fluxidi.external_navigation/events"
    private const val TAG = "FluxidiExternalNav"
  }

  private var methodChannel: MethodChannel? = null
  private var eventChannel: EventChannel? = null
  private var eventSink: EventChannel.EventSink? = null
  private var activity: Activity? = null
  private var pipActive: Boolean = false
  private var handoffPrepared: Boolean = false

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
      it.setMethodCallHandler(this)
    }
    eventChannel = EventChannel(binding.binaryMessenger, EVENTS).also {
      it.setStreamHandler(this)
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel?.setMethodCallHandler(null)
    methodChannel = null
    eventChannel?.setStreamHandler(null)
    eventChannel = null
    eventSink = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    activity = null
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
    pipActive = isInPictureInPictureMode
    if (isInPictureInPictureMode) {
      Log.i(TAG, "pip_entered_after_handoff=true")
    }
    eventSink?.success(
      mapOf(
        "type" to "pipModeChanged",
        "pipActive" to isInPictureInPictureMode,
      ),
    )
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "isGoogleMapsInstalled" -> {
        val act = activity
        if (act == null) {
          result.success(false)
          return
        }
        val installed =
          GoogleMapsNavigationIntents.isGoogleMapsInstalled(act.packageManager)
        val enabled =
          installed &&
            GoogleMapsNavigationIntents.isGoogleMapsEnabled(act.packageManager)
        Log.i(TAG, "maps_package_installed=$installed maps_package_enabled=$enabled")
        result.success(installed && enabled)
      }
      "isPipSupported" -> result.success(isPipSupported())
      "prepareFluxidiPipForHandoff" -> prepareFluxidiPipForHandoff(result)
      "launchGoogleNavigation" -> launchGoogleNavigation(call, result)
      "enterFluxidiPip" -> enterFluxidiPip(result)
      "exitFluxidiPip" -> exitFluxidiPip(result)
      "updateFluxidiPip" -> {
        result.success(
          mapOf(
            "ok" to true,
            "pipActive" to pipActive,
          ),
        )
      }
      "returnToFluxidi" -> returnToFluxidi(result)
      "openGoogleMapsInstallPage" -> openInstallPage(result)
      else -> result.notImplemented()
    }
  }

  private fun isPipSupported(): Boolean {
    val act = activity ?: return false
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
    return act.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
  }

  /**
   * Prepare PiP params (Android 12+ auto-enter) WITHOUT entering PiP yet.
   * Maps must be dispatched first.
   */
  private fun prepareFluxidiPipForHandoff(result: MethodChannel.Result) {
    val act = activity
    if (act == null) {
      result.success(mapOf("ok" to false, "error" to "no_activity"))
      return
    }
    if (!isPipSupported()) {
      result.success(mapOf("ok" to false, "error" to "pip_unsupported"))
      return
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val autoParams = PictureInPictureParams.Builder()
          .setAspectRatio(Rational(16, 9))
          .setAutoEnterEnabled(true)
          .build()
        act.setPictureInPictureParams(autoParams)
        handoffPrepared = true
        result.success(mapOf("ok" to true, "autoEnterPrepared" to true))
      } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val params = PictureInPictureParams.Builder()
          .setAspectRatio(Rational(16, 9))
          .build()
        act.setPictureInPictureParams(params)
        handoffPrepared = true
        result.success(mapOf("ok" to true, "autoEnterPrepared" to false))
      } else {
        result.success(mapOf("ok" to false, "error" to "pip_unsupported"))
      }
    } catch (e: Exception) {
      result.success(
        mapOf(
          "ok" to false,
          "error" to "pip_prepare_failed",
          "message" to (e.message ?: "unknown"),
        ),
      )
    }
  }

  private fun launchGoogleNavigation(call: MethodCall, result: MethodChannel.Result) {
    val act = activity
    if (act == null) {
      Log.w(TAG, "maps_launch_failure_code=no_activity")
      result.success(mapOf("ok" to false, "error" to "no_activity"))
      return
    }
    val pm = act.packageManager
    val installed = GoogleMapsNavigationIntents.isGoogleMapsInstalled(pm)
    val enabled = installed && GoogleMapsNavigationIntents.isGoogleMapsEnabled(pm)
    Log.i(TAG, "maps_package_installed=$installed maps_package_enabled=$enabled")
    if (!installed || !enabled) {
      Log.w(TAG, "maps_launch_failure_code=google_maps_not_installed")
      result.success(
        mapOf(
          "ok" to false,
          "error" to "google_maps_not_installed",
          "maps_package_installed" to installed,
          "maps_package_enabled" to enabled,
        ),
      )
      return
    }
    val lat = (call.argument<Number>("latitude"))?.toDouble()
    val lon = (call.argument<Number>("longitude"))?.toDouble()
    val address = call.argument<String>("address")
    val destinationSource = call.argument<String>("destinationSource") ?: "unknown"
    val destination = GoogleMapsNavigationIntents.Destination(
      latitude = lat,
      longitude = lon,
      address = address,
    )
    Log.i(TAG, "maps_destination_source=$destinationSource hasCoords=${destination.hasCoordinates()}")
    val intent = GoogleMapsNavigationIntents.buildGoogleNavigationIntent(destination)
    if (intent == null) {
      Log.w(TAG, "maps_launch_failure_code=missing_destination")
      result.success(mapOf("ok" to false, "error" to "missing_destination"))
      return
    }
    if (!GoogleMapsNavigationIntents.intentTargetsGoogleMapsOnly(intent) ||
      !GoogleMapsNavigationIntents.intentUsesDrivingMode(intent)
    ) {
      Log.w(TAG, "maps_launch_failure_code=invalid_intent")
      result.success(mapOf("ok" to false, "error" to "invalid_intent"))
      return
    }
    val resolved = GoogleMapsNavigationIntents.canResolveNavigationIntent(pm, intent)
    Log.i(TAG, "maps_intent_resolved=$resolved uri=${intent.data}")
    if (!resolved) {
      Log.w(TAG, "maps_launch_failure_code=intent_not_resolved")
      result.success(
        mapOf(
          "ok" to false,
          "error" to "intent_not_resolved",
          "maps_intent_resolved" to false,
        ),
      )
      return
    }
    try {
      act.startActivity(intent)
      Log.i(TAG, "maps_launch_dispatched=true")
      result.success(
        mapOf(
          "ok" to true,
          "package" to GoogleMapsNavigationIntents.GOOGLE_MAPS_PACKAGE,
          "drivingMode" to true,
          "maps_package_installed" to true,
          "maps_intent_resolved" to true,
          "maps_launch_dispatched" to true,
          "maps_destination_source" to destinationSource,
          "uri" to (intent.data?.toString() ?: ""),
        ),
      )
    } catch (_: ActivityNotFoundException) {
      Log.w(TAG, "maps_launch_failure_code=google_maps_not_installed")
      result.success(
        mapOf(
          "ok" to false,
          "error" to "google_maps_not_installed",
        ),
      )
    } catch (e: Exception) {
      Log.w(TAG, "maps_launch_failure_code=launch_failed msg=${e.message}")
      result.success(
        mapOf(
          "ok" to false,
          "error" to "launch_failed",
          "message" to (e.message ?: "unknown"),
        ),
      )
    }
  }

  private fun enterFluxidiPip(result: MethodChannel.Result) {
    val act = activity
    if (act == null) {
      result.success(mapOf("ok" to false, "error" to "no_activity"))
      return
    }
    if (!isPipSupported()) {
      result.success(mapOf("ok" to false, "error" to "pip_unsupported"))
      return
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val params = PictureInPictureParams.Builder()
          .setAspectRatio(Rational(16, 9))
          .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
          val autoParams = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .setAutoEnterEnabled(true)
            .build()
          act.setPictureInPictureParams(autoParams)
        }
        val entered = act.enterPictureInPictureMode(params)
        pipActive = entered
        Log.i(TAG, "pip_entered_after_handoff=$entered prepared=$handoffPrepared")
        result.success(mapOf("ok" to entered, "pipActive" to entered))
      } else {
        result.success(mapOf("ok" to false, "error" to "pip_unsupported"))
      }
    } catch (e: Exception) {
      result.success(
        mapOf(
          "ok" to false,
          "error" to "pip_enter_failed",
          "message" to (e.message ?: "unknown"),
        ),
      )
    }
  }

  private fun exitFluxidiPip(result: MethodChannel.Result) {
    val act = activity
    if (act == null) {
      result.success(mapOf("ok" to false, "error" to "no_activity"))
      return
    }
    handoffPrepared = false
    returnToFluxidi(result)
  }

  private fun returnToFluxidi(result: MethodChannel.Result) {
    val act = activity
    if (act == null) {
      result.success(mapOf("ok" to false, "error" to "no_activity"))
      return
    }
    try {
      val intent = GoogleMapsNavigationIntents.buildReturnToFluxidiIntent(act.packageName)
      act.startActivity(intent)
      result.success(mapOf("ok" to true, "pipActive" to false))
    } catch (e: Exception) {
      result.success(
        mapOf(
          "ok" to false,
          "error" to "return_failed",
          "message" to (e.message ?: "unknown"),
        ),
      )
    }
  }

  private fun openInstallPage(result: MethodChannel.Result) {
    val act = activity
    if (act == null) {
      result.success(mapOf("ok" to false, "error" to "no_activity"))
      return
    }
    try {
      act.startActivity(GoogleMapsNavigationIntents.buildPlayStoreInstallIntent())
      result.success(mapOf("ok" to true, "via" to "market"))
    } catch (_: ActivityNotFoundException) {
      try {
        act.startActivity(GoogleMapsNavigationIntents.buildPlayStoreWebFallbackIntent())
        result.success(mapOf("ok" to true, "via" to "web"))
      } catch (e: Exception) {
        result.success(
          mapOf(
            "ok" to false,
            "error" to "install_page_failed",
            "message" to (e.message ?: "unknown"),
          ),
        )
      }
    }
  }
}
