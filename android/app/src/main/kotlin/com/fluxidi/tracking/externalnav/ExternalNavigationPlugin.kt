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
 * GOOGLE-MAPS-DIRECT-LAUNCH-ANDROID-1 /
 * GOOGLE-MAPS-LAUNCH-CONTRACT-NOOP-P0-2 /
 * GOOGLE-MAPS-OPAQUE-NAVIGATION-URI-P0-3
 *
 * Platform channel: fluxidi.external_navigation
 *
 * Launch contract always returns a structured map with:
 * status, failure_code, pip_supported, launch_dispatched.
 *
 * Correct handoff: prepare PiP params → dispatch Maps → enter PiP only after
 * launch_dispatched=true (PiP support never blocks Maps launch).
 * Opaque google.navigation URI validation never escapes the MethodChannel.
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

    const val STATUS_LAUNCHED = "launched"
    const val STATUS_MAPS_NOT_INSTALLED = "maps_not_installed"
    const val STATUS_MAPS_DISABLED = "maps_disabled"
    const val STATUS_INVALID_DESTINATION = "invalid_destination"
    const val STATUS_INTENT_NOT_RESOLVED = "intent_not_resolved"
    const val STATUS_ACTIVITY_NOT_FOUND = "activity_not_found"
    const val STATUS_SECURITY_EXCEPTION = "security_exception"
    const val STATUS_NATIVE_EXCEPTION = "native_exception"
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
        // Contract: "installed" means package present (enabled checked separately).
        result.success(installed)
      }
      "probeGoogleMapsAvailability" -> {
        val act = activity
        if (act == null) {
          result.success(
            mapOf(
              "installed" to false,
              "enabled" to false,
              "error" to "no_activity",
            ),
          )
          return
        }
        val pm = act.packageManager
        val installed = GoogleMapsNavigationIntents.isGoogleMapsInstalled(pm)
        val enabled =
          installed && GoogleMapsNavigationIntents.isGoogleMapsEnabled(pm)
        result.success(
          mapOf(
            "installed" to installed,
            "enabled" to enabled,
          ),
        )
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

  private fun launchResult(
    status: String,
    failureCode: String? = null,
    launchDispatched: Boolean = false,
    mapsPackageInstalled: Boolean? = null,
    mapsPackageEnabled: Boolean? = null,
    mapsIntentResolved: Boolean? = null,
    uri: String? = null,
    message: String? = null,
    destinationSource: String? = null,
  ): Map<String, Any?> {
    val ok = status == STATUS_LAUNCHED && launchDispatched
    return mapOf(
      "ok" to ok,
      "status" to status,
      "failure_code" to failureCode,
      "error" to failureCode,
      "pip_supported" to isPipSupported(),
      "launch_dispatched" to launchDispatched,
      "maps_launch_dispatched" to launchDispatched,
      "maps_package_installed" to mapsPackageInstalled,
      "maps_package_enabled" to mapsPackageEnabled,
      "maps_intent_resolved" to mapsIntentResolved,
      "uri" to uri,
      "maps_intent_uri" to uri,
      "message" to message,
      "maps_destination_source" to destinationSource,
      "package" to if (ok) GoogleMapsNavigationIntents.GOOGLE_MAPS_PACKAGE else null,
      "drivingMode" to if (ok) true else null,
    )
  }

  /**
   * Prepare PiP params (Android 12+ auto-enter) WITHOUT entering PiP yet.
   * Maps must be dispatched first. PiP failure must never block Maps.
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
    // GOOGLE-MAPS-OPAQUE-NAVIGATION-URI-P0-3: every pre-launch validator path
    // must stay inside this try/catch so opaque-URI / MethodChannel faults
    // never escape as uncaught platform exceptions.
    try {
      val act = activity
      if (act == null) {
        Log.w(TAG, "maps_launch_failure_code=no_activity")
        result.success(
          launchResult(
            status = STATUS_NATIVE_EXCEPTION,
            failureCode = "no_activity",
          ),
        )
        return
      }
      val pm = act.packageManager
      val installed = GoogleMapsNavigationIntents.isGoogleMapsInstalled(pm)
      val enabled = installed && GoogleMapsNavigationIntents.isGoogleMapsEnabled(pm)
      Log.i(TAG, "maps_package_installed=$installed maps_package_enabled=$enabled")
      if (!installed) {
        Log.w(TAG, "maps_launch_failure_code=maps_not_installed")
        result.success(
          launchResult(
            status = STATUS_MAPS_NOT_INSTALLED,
            failureCode = "maps_not_installed",
            mapsPackageInstalled = false,
            mapsPackageEnabled = false,
          ),
        )
        return
      }
      if (!enabled) {
        Log.w(TAG, "maps_launch_failure_code=maps_disabled")
        result.success(
          launchResult(
            status = STATUS_MAPS_DISABLED,
            failureCode = "maps_disabled",
            mapsPackageInstalled = true,
            mapsPackageEnabled = false,
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
      Log.i(
        TAG,
        "destination_source=$destinationSource " +
          "destination_lat_valid=${destination.hasCoordinates() && lat != null} " +
          "destination_lng_valid=${destination.hasCoordinates() && lon != null} " +
          "destination_address_present=${destination.hasAddress()}",
      )
      val intent = GoogleMapsNavigationIntents.buildGoogleNavigationIntent(destination)
      if (intent == null) {
        Log.w(TAG, "maps_launch_failure_code=invalid_destination")
        result.success(
          launchResult(
            status = STATUS_INVALID_DESTINATION,
            failureCode = "invalid_destination",
            mapsPackageInstalled = true,
            mapsPackageEnabled = true,
            destinationSource = destinationSource,
          ),
        )
        return
      }
      val validationFailure =
        GoogleMapsNavigationIntents.validateNavigationIntentOrFailure(intent)
      if (validationFailure != null) {
        Log.w(TAG, "maps_launch_failure_code=$validationFailure")
        result.success(
          launchResult(
            status = STATUS_NATIVE_EXCEPTION,
            failureCode = validationFailure,
            mapsPackageInstalled = true,
            mapsPackageEnabled = true,
            destinationSource = destinationSource,
            uri = intent.data?.toString(),
          ),
        )
        return
      }
      val uriString = intent.data?.toString().orEmpty()
      val resolved = GoogleMapsNavigationIntents.canResolveNavigationIntent(pm, intent)
      Log.i(TAG, "maps_intent_uri_present=${uriString.isNotEmpty()} maps_intent_resolved=$resolved")
      if (!resolved) {
        Log.w(TAG, "maps_launch_failure_code=intent_not_resolved")
        result.success(
          launchResult(
            status = STATUS_INTENT_NOT_RESOLVED,
            failureCode = "intent_not_resolved",
            mapsPackageInstalled = true,
            mapsPackageEnabled = true,
            mapsIntentResolved = false,
            uri = uriString,
            destinationSource = destinationSource,
          ),
        )
        return
      }
      Log.i(TAG, "maps_start_activity_called=true")
      act.startActivity(intent)
      Log.i(TAG, "maps_start_activity_result=ok launch_dispatched=true")
      result.success(
        launchResult(
          status = STATUS_LAUNCHED,
          launchDispatched = true,
          mapsPackageInstalled = true,
          mapsPackageEnabled = true,
          mapsIntentResolved = true,
          uri = uriString,
          destinationSource = destinationSource,
        ),
      )
    } catch (_: ActivityNotFoundException) {
      Log.w(TAG, "maps_start_activity_result=activity_not_found")
      result.success(
        launchResult(
          status = STATUS_ACTIVITY_NOT_FOUND,
          failureCode = "activity_not_found",
          launchDispatched = false,
        ),
      )
    } catch (e: SecurityException) {
      Log.w(TAG, "maps_start_activity_result=security_exception msg=${e.message}")
      result.success(
        launchResult(
          status = STATUS_SECURITY_EXCEPTION,
          failureCode = "security_exception",
          launchDispatched = false,
          message = e.message,
        ),
      )
    } catch (e: Exception) {
      Log.w(TAG, "maps_start_activity_result=native_exception msg=${e.message}")
      result.success(
        launchResult(
          status = STATUS_NATIVE_EXCEPTION,
          failureCode = "native_exception",
          launchDispatched = false,
          message = e.message,
        ),
      )
    } catch (t: Throwable) {
      // Catch UnsupportedOperationException / Error subclasses from Uri APIs.
      Log.w(TAG, "maps_start_activity_result=native_throwable msg=${t.message}")
      result.success(
        launchResult(
          status = STATUS_NATIVE_EXCEPTION,
          failureCode = "native_exception",
          launchDispatched = false,
          message = t.message,
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
