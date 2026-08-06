package com.fluxidi.tracking.externalnav

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * GOOGLE-MAPS-DIRECT-LAUNCH-ANDROID-1 / FLUXIDI-PIP-METER-EXTERNAL-NAV-1
 *
 * Platform channel: fluxidi.external_navigation
 */
class ExternalNavigationPlugin :
  FlutterPlugin,
  MethodChannel.MethodCallHandler,
  EventChannel.StreamHandler,
  ActivityAware {

  companion object {
    const val CHANNEL = "fluxidi.external_navigation"
    const val EVENTS = "fluxidi.external_navigation/events"
  }

  private var methodChannel: MethodChannel? = null
  private var eventChannel: EventChannel? = null
  private var eventSink: EventChannel.EventSink? = null
  private var activity: Activity? = null
  private var pipActive: Boolean = false

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
        result.success(
          GoogleMapsNavigationIntents.isGoogleMapsInstalled(act.packageManager),
        )
      }
      "isPipSupported" -> result.success(isPipSupported())
      "launchGoogleNavigation" -> launchGoogleNavigation(call, result)
      "enterFluxidiPip" -> enterFluxidiPip(result)
      "exitFluxidiPip" -> exitFluxidiPip(result)
      "updateFluxidiPip" -> {
        // Aspect ratio / actions refresh — no-op payload update for now.
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

  private fun launchGoogleNavigation(call: MethodCall, result: MethodChannel.Result) {
    val act = activity
    if (act == null) {
      result.success(mapOf("ok" to false, "error" to "no_activity"))
      return
    }
    if (!GoogleMapsNavigationIntents.isGoogleMapsInstalled(act.packageManager)) {
      result.success(
        mapOf(
          "ok" to false,
          "error" to "google_maps_not_installed",
        ),
      )
      return
    }
    val lat = (call.argument<Number>("latitude"))?.toDouble()
    val lon = (call.argument<Number>("longitude"))?.toDouble()
    val address = call.argument<String>("address")
    val destination = GoogleMapsNavigationIntents.Destination(
      latitude = lat,
      longitude = lon,
      address = address,
    )
    val intent = GoogleMapsNavigationIntents.buildGoogleNavigationIntent(destination)
    if (intent == null) {
      result.success(mapOf("ok" to false, "error" to "missing_destination"))
      return
    }
    if (!GoogleMapsNavigationIntents.intentTargetsGoogleMapsOnly(intent) ||
      !GoogleMapsNavigationIntents.intentUsesDrivingMode(intent)
    ) {
      result.success(mapOf("ok" to false, "error" to "invalid_intent"))
      return
    }
    try {
      act.startActivity(intent)
      result.success(
        mapOf(
          "ok" to true,
          "package" to GoogleMapsNavigationIntents.GOOGLE_MAPS_PACKAGE,
          "drivingMode" to true,
        ),
      )
    } catch (_: ActivityNotFoundException) {
      result.success(
        mapOf(
          "ok" to false,
          "error" to "google_maps_not_installed",
        ),
      )
    } catch (e: Exception) {
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
          // Android 12+: prepare auto-enter style params, then enter explicitly
          // so launch→PiP remains deterministic from Flutter.
          val autoParams = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .setAutoEnterEnabled(true)
            .build()
          act.setPictureInPictureParams(autoParams)
        }
        val entered = act.enterPictureInPictureMode(params)
        pipActive = entered
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
    // Leaving PiP is done by moving the task to front / finishing PiP mode.
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
