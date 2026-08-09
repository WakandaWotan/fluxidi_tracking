package com.fluxidi.tracking.externalnav

import android.app.Activity
import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
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
 * GOOGLE-MAPS-OPAQUE-NAVIGATION-URI-P0-3 /
 * ANDROID-RECENTS-PIP-AUTOENTER-P0
 *
 * Platform channel: fluxidi.external_navigation
 *
 * Launch contract always returns a structured map with:
 * status, failure_code, pip_supported, launch_dispatched.
 *
 * Correct handoff: prepare PiP params → dispatch Maps → enter PiP only after
 * launch_dispatched=true (PiP support never blocks Maps launch).
 * Opaque google.navigation URI validation never escapes the MethodChannel.
 *
 * Auto-enter PiP is a bounded transient for the Maps handoff window only.
 * Force-to-front is reserved for an explicit, unconsumed PiP return action.
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
  /** True only while Android S+ auto-enter is intentionally armed for Maps. */
  private var autoEnterArmed: Boolean = false
  /** Unique per external Maps/PiP session — PendingIntent requestCode owner. */
  private var pipSessionToken: String = ""
  private var lastPipReturnRequestCode: Int = -1

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

  /**
   * Called from MainActivity.onResume. If we are full-screen again, sticky
   * auto-enter must never survive to hijack the next Home/Recents press.
   */
  fun onActivityResumed() {
    if (pipActive) {
      Log.i(TAG, "pip_auto_enter_resume_skip=true reason=currently_in_pip")
      return
    }
    clearPipAutoEnter(reason = "activity_resumed_not_in_pip")
  }

  fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
    pipActive = isInPictureInPictureMode
    if (isInPictureInPictureMode) {
      Log.i(TAG, "pip_entered_after_handoff=true")
      handoffPrepared = false
      // Refresh system RemoteAction; always leave auto-enter disabled while
      // inside PiP so exiting PiP cannot poison future Recents/Home.
      refreshPipReturnAction(reason = "pip_entered")
      autoEnterArmed = false
    } else {
      Log.i(TAG, "pip_exit_requested=system_or_expand flutter_resumed=pending")
      // FIX: leaving PiP must clear sticky auto-enter. Do NOT force-to-front.
      clearPipAutoEnter(reason = "pip_mode_exited")
    }
    eventSink?.success(
      mapOf(
        "type" to "pipModeChanged",
        "pipActive" to isInPictureInPictureMode,
      ),
    )
  }

  /**
   * NAV-PIP-PLANNED-COMPLETION-EVIDENCE-FIX-P0 /
   * ANDROID-RECENTS-PIP-AUTOENTER-P0:
   * handle Activity PendingIntent / onNewIntent return from the system PiP
   * RemoteAction. Force-to-front only for an explicit, unconsumed return.
   */
  fun handleReturnFromPipIntent(intent: Intent?) {
    if (!GoogleMapsNavigationIntents.shouldHandlePipReturn(intent)) {
      Log.i(
        TAG,
        "pip_return_ignored=true reason=not_explicit_or_already_consumed " +
          "explicit=${GoogleMapsNavigationIntents.isExplicitPipReturnIntent(intent)} " +
          "handled=${GoogleMapsNavigationIntents.wasPipReturnAlreadyHandled(intent)}",
      )
      return
    }
    val act = activity
    val session = intent?.getStringExtra(GoogleMapsNavigationIntents.EXTRA_PIP_SESSION)
    Log.i(
      TAG,
      "pip_return_intent_received=true pip_remote_action_clicked=true " +
        "on_new_intent_called=true " +
        "session=${session ?: pipSessionToken} " +
        "current_task_id=${act?.taskId ?: -1} " +
        "main_activity_task_id=${act?.taskId ?: -1} " +
        "duplicate_activity_created=false",
    )
    // Consume BEFORE force-to-front so recreation cannot replay.
    consumeReturnIntentOnActivity(intent)
    bringFluxidiTaskToFront(source = "pip_remote_action")
    clearPipAutoEnter(reason = "pip_return_handled")
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
        refreshPipReturnAction(reason = "pip_update")
        result.success(
          mapOf(
            "ok" to true,
            "pipActive" to pipActive,
            "session" to pipSessionToken,
            "request_code" to lastPipReturnRequestCode,
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
   * ANDROID-RECENTS-PIP-AUTOENTER-P0: idempotent clear of sticky auto-enter.
   * Safe on pre-S / unsupported devices (no-op).
   */
  fun clearPipAutoEnter(reason: String) {
    handoffPrepared = false
    autoEnterArmed = false
    val act = activity
    if (act == null) {
      Log.i(TAG, "pip_auto_enter_cleared=true reason=$reason activity=null")
      return
    }
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    if (!isPipSupported()) return
    try {
      ensurePipSessionToken()
      act.setPictureInPictureParams(buildPipParams(act, autoEnter = false))
      Log.i(TAG, "pip_auto_enter_cleared=true reason=$reason")
    } catch (e: Exception) {
      Log.w(TAG, "pip_auto_enter_clear_failed=true reason=$reason msg=${e.message}")
    }
  }

  /**
   * Prepare PiP params (Android 12+ auto-enter) WITHOUT entering PiP yet.
   * Transient only — cleared on resume / fail / PiP exit / session cleanup.
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
      // Fresh session token per handoff so return PendingIntent cannot reopen
      // a previous ride's stale action.
      pipSessionToken = "pip_${System.currentTimeMillis()}"
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        act.setPictureInPictureParams(buildPipParams(act, autoEnter = true))
        handoffPrepared = true
        autoEnterArmed = true
        Log.i(TAG, "pip_auto_enter_armed=true reason=prepare_handoff")
        result.success(mapOf("ok" to true, "autoEnterPrepared" to true))
      } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        act.setPictureInPictureParams(buildPipParams(act, autoEnter = false))
        handoffPrepared = true
        autoEnterArmed = false
        result.success(mapOf("ok" to true, "autoEnterPrepared" to false))
      } else {
        result.success(mapOf("ok" to false, "error" to "pip_unsupported"))
      }
    } catch (e: Exception) {
      clearPipAutoEnter(reason = "pip_prepare_failed")
      result.success(
        mapOf(
          "ok" to false,
          "error" to "pip_prepare_failed",
          "message" to (e.message ?: "unknown"),
        ),
      )
    }
  }

  private fun ensurePipSessionToken() {
    if (pipSessionToken.isBlank()) {
      pipSessionToken = "pip_${System.currentTimeMillis()}"
    }
  }

  private fun refreshPipReturnAction(reason: String) {
    val act = activity ?: return
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    if (!isPipSupported()) return
    try {
      ensurePipSessionToken()
      act.setPictureInPictureParams(buildPipParams(act, autoEnter = false))
      autoEnterArmed = false
      Log.i(TAG, "pip_return_action_refreshed=true reason=$reason")
    } catch (e: Exception) {
      Log.w(TAG, "pip_return_action_refresh_failed=${e.message}")
    }
  }

  private fun buildPipParams(act: Activity, autoEnter: Boolean): PictureInPictureParams {
    ensurePipSessionToken()
    val builder = PictureInPictureParams.Builder()
      .setAspectRatio(Rational(16, 9))
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      builder.setAutoEnterEnabled(autoEnter)
    }
    val pending = GoogleMapsNavigationIntents.buildReturnToFluxidiPendingIntent(
      act,
      pipSessionToken,
    )
    lastPipReturnRequestCode =
      GoogleMapsNavigationIntents.pipReturnRequestCode(pipSessionToken)
    // ic_menu_revert is a standard system control icon — Samsung PiP chrome
    // shows RemoteAction icons in the PiP window (title = accessibility label).
    val icon = Icon.createWithResource(act, android.R.drawable.ic_menu_revert)
    val action = RemoteAction(
      icon,
      "Terug naar Fluxidi",
      "Terug naar Fluxidi",
      pending,
    )
    action.setEnabled(true)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      action.setShouldShowIcon(true)
    }
    builder.setActions(listOf(action))
    Log.i(
      TAG,
      "pip_remote_action_created=true pip_return_action_created=true " +
        "request_code=$lastPipReturnRequestCode " +
        "session=$pipSessionToken " +
        "auto_enter=$autoEnter " +
        "title=Terug naar Fluxidi enabled=true show_icon=true " +
        "target_component=${act.packageName}.MainActivity " +
        "intent_flags=REORDER_TO_FRONT|SINGLE_TOP " +
        "pending_intent_update_current=true",
    )
    return builder.build()
  }

  private fun consumeReturnIntentOnActivity(handled: Intent?) {
    if (handled == null) return
    GoogleMapsNavigationIntents.consumePipReturnIntent(handled)
    val act = activity ?: return
    try {
      // Replace Activity.intent so a later recreate cannot replay return.
      val cleaned = Intent(handled)
      GoogleMapsNavigationIntents.consumePipReturnIntent(cleaned)
      act.intent = cleaned
      Log.i(TAG, "pip_return_intent_consumed=true")
    } catch (e: Exception) {
      Log.w(TAG, "pip_return_intent_consume_failed=${e.message}")
    }
  }

  /**
   * Force-to-front for an explicit user Return-to-Fluxidi action only.
   * Never call from generic PiP exit / resume / Home / Recents cleanup.
   */
  private fun bringFluxidiTaskToFront(source: String) {
    val act = activity
    if (act == null) {
      Log.w(TAG, "pip_return_failed=true reason=no_activity source=$source")
      return
    }
    if (source != "pip_remote_action" && source != "method_channel_explicit_return") {
      Log.w(TAG, "pip_return_blocked=true reason=source_not_explicit source=$source")
      return
    }
    try {
      Log.i(
        TAG,
        "pip_remote_action_clicked=true pip_return_pressed=true source=$source " +
          "current_task_id=${act.taskId} main_activity_task_id=${act.taskId}",
      )
      val intent = GoogleMapsNavigationIntents.buildReturnToFluxidiIntent(
        act.packageName,
        pipSessionToken.ifBlank { null },
      )
      // Mark the synthetic startActivity intent handled immediately so it
      // cannot be re-processed as a second return by onNewIntent/onCreate.
      GoogleMapsNavigationIntents.consumePipReturnIntent(intent)
      act.startActivity(intent)
      Log.i(TAG, "pending_intent_sent=channel_startActivity")
      @Suppress("DEPRECATION")
      val am = act.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
      am.moveTaskToFront(act.taskId, 0)
      Log.i(
        TAG,
        "pip_task_brought_to_front=true move_task_to_front_result=ok " +
          "task=${act.taskId} duplicate_activity_created=false",
      )
      // Match manual PiP expand: leave the Flutter PiP meter immediately.
      // Active ride / meter / external-nav session state stays in Flutter.
      pipActive = false
      eventSink?.success(
        mapOf(
          "type" to "pipModeChanged",
          "pipActive" to false,
          "source" to source,
        ),
      )
      Log.i(TAG, "pip_exit_requested=true on_resume_called=pending flutter_resumed=true")
    } catch (e: Exception) {
      Log.w(
        TAG,
        "pip_return_failed=true move_task_to_front_result=fail " +
          "source=$source msg=${e.message}",
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
        clearPipAutoEnter(reason = "maps_launch_failed_no_activity")
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
        clearPipAutoEnter(reason = "maps_launch_failed_not_installed")
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
        clearPipAutoEnter(reason = "maps_launch_failed_disabled")
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
        clearPipAutoEnter(reason = "maps_launch_failed_invalid_destination")
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
        clearPipAutoEnter(reason = "maps_launch_failed_validation")
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
        clearPipAutoEnter(reason = "maps_launch_failed_not_resolved")
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
      clearPipAutoEnter(reason = "maps_launch_failed_activity_not_found")
      result.success(
        launchResult(
          status = STATUS_ACTIVITY_NOT_FOUND,
          failureCode = "activity_not_found",
          launchDispatched = false,
        ),
      )
    } catch (e: SecurityException) {
      Log.w(TAG, "maps_start_activity_result=security_exception msg=${e.message}")
      clearPipAutoEnter(reason = "maps_launch_failed_security")
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
      clearPipAutoEnter(reason = "maps_launch_failed_exception")
      result.success(
        launchResult(
          status = STATUS_NATIVE_EXCEPTION,
          failureCode = "native_exception",
          launchDispatched = false,
          message = e.message,
        ),
      )
    } catch (t: Throwable) {
      Log.w(TAG, "maps_start_activity_result=native_throwable msg=${t.message}")
      clearPipAutoEnter(reason = "maps_launch_failed_throwable")
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
      clearPipAutoEnter(reason = "pip_enter_unsupported")
      result.success(mapOf("ok" to false, "error" to "pip_unsupported"))
      return
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        // New session token per enter so PendingIntent cannot target a stale ride.
        pipSessionToken = "pip_${System.currentTimeMillis()}"
        // ANDROID-RECENTS-PIP-AUTOENTER-P0: never re-arm sticky autoEnter=true
        // here. Manual enter uses autoEnter=false; prepare() already covered
        // the Maps-background auto-enter window.
        val params = buildPipParams(act, autoEnter = false)
        val entered = act.enterPictureInPictureMode(params)
        pipActive = entered
        handoffPrepared = false
        Log.i(TAG, "pip_entered_after_handoff=$entered prepared=$handoffPrepared")
        if (!entered) {
          clearPipAutoEnter(reason = "pip_enter_failed")
        } else {
          // Ensure auto-enter is disabled even if the mode callback is delayed.
          clearPipAutoEnter(reason = "pip_enter_succeeded")
          pipActive = true
        }
        result.success(
          mapOf(
            "ok" to entered,
            "pipActive" to entered,
            "session" to pipSessionToken,
            "request_code" to lastPipReturnRequestCode,
          ),
        )
      } else {
        clearPipAutoEnter(reason = "pip_enter_unsupported_sdk")
        result.success(mapOf("ok" to false, "error" to "pip_unsupported"))
      }
    } catch (e: Exception) {
      clearPipAutoEnter(reason = "pip_enter_exception")
      result.success(
        mapOf(
          "ok" to false,
          "error" to "pip_enter_failed",
          "message" to (e.message ?: "unknown"),
        ),
      )
    }
  }

  /**
   * Cleanup / disable PiP handoff state. Must NOT steal foreground — that is
   * reserved for explicit user Return-to-Fluxidi.
   */
  private fun exitFluxidiPip(result: MethodChannel.Result) {
    val act = activity
    if (act == null) {
      result.success(mapOf("ok" to false, "error" to "no_activity"))
      return
    }
    handoffPrepared = false
    clearPipAutoEnter(reason = "exit_fluxidi_pip_cleanup")
    pipActive = false
    eventSink?.success(
      mapOf(
        "type" to "pipModeChanged",
        "pipActive" to false,
        "source" to "exit_fluxidi_pip_cleanup",
      ),
    )
    Log.i(TAG, "pip_exit_cleanup=true force_to_front=false")
    result.success(
      mapOf(
        "ok" to true,
        "pipActive" to false,
        "session" to pipSessionToken,
        "request_code" to lastPipReturnRequestCode,
        "force_to_front" to false,
      ),
    )
  }

  /** Explicit Flutter/user Return-to-Fluxidi (not generic cleanup). */
  private fun returnToFluxidi(result: MethodChannel.Result) {
    val act = activity
    if (act == null) {
      result.success(mapOf("ok" to false, "error" to "no_activity"))
      return
    }
    try {
      bringFluxidiTaskToFront(source = "method_channel_explicit_return")
      clearPipAutoEnter(reason = "explicit_return_to_fluxidi")
      result.success(
        mapOf(
          "ok" to true,
          "pipActive" to false,
          "session" to pipSessionToken,
          "request_code" to lastPipReturnRequestCode,
          "force_to_front" to true,
        ),
      )
    } catch (e: Exception) {
      clearPipAutoEnter(reason = "explicit_return_failed")
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
