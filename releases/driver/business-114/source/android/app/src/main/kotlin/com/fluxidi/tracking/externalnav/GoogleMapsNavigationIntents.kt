package com.fluxidi.tracking.externalnav

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import java.util.Locale

/**
 * GOOGLE-MAPS-DIRECT-LAUNCH-ANDROID-1 /
 * GOOGLE-MAPS-LAUNCH-CONTRACT-NOOP-P0-2 /
 * GOOGLE-MAPS-OPAQUE-NAVIGATION-URI-P0-3
 *
 * Pure helpers that build an explicit Google Maps navigation Intent.
 * No browser chooser, no generic VIEW without package.
 *
 * `google.navigation:` URIs are opaque. Never call hierarchical-only Uri
 * APIs such as [Uri.getQueryParameter] on them (throws
 * UnsupportedOperationException: "This isn't a hierarchical URI.").
 */
object GoogleMapsNavigationIntents {
  const val GOOGLE_MAPS_PACKAGE = "com.google.android.apps.maps"
  const val PLAY_STORE_PACKAGE = "com.android.vending"
  const val NAVIGATION_SCHEME = "google.navigation"
  const val NAVIGATION_MODE_DRIVING = "d"
  /** Structured contract field stamped on intents we build ourselves. */
  const val EXTRA_NAVIGATION_MODE = "fluxidi_google_navigation_mode"

  // PIP-ACTIVITY-RETURN-TO-FLUXIDI-P0-6
  const val ACTION_RETURN_FROM_PIP = "com.fluxidi.tracking.action.RETURN_FROM_PIP"
  const val EXTRA_PIP_RETURN = "fluxidi_external_nav_return"
  const val EXTRA_PIP_SESSION = "fluxidi_external_nav_session"
  /** Set after an explicit PiP return was handled once — blocks replay. */
  const val EXTRA_PIP_RETURN_HANDLED = "fluxidi_external_nav_return_handled"

  data class Destination(
    val latitude: Double? = null,
    val longitude: Double? = null,
    val address: String? = null,
  ) {
    fun hasCoordinates(): Boolean =
      latitude != null &&
        longitude != null &&
        latitude!!.isFinite() &&
        longitude!!.isFinite() &&
        latitude!! >= -90.0 &&
        latitude!! <= 90.0 &&
        longitude!! >= -180.0 &&
        longitude!! <= 180.0

    fun hasAddress(): Boolean {
      val trimmed = address?.trim().orEmpty()
      if (trimmed.isEmpty()) return false
      val lower = trimmed.lowercase(Locale.US)
      return lower != "null" && lower != "undefined"
    }
  }

  fun isGoogleMapsInstalled(packageManager: PackageManager): Boolean {
    return try {
      packageManager.getPackageInfo(GOOGLE_MAPS_PACKAGE, 0)
      true
    } catch (_: PackageManager.NameNotFoundException) {
      false
    }
  }

  fun isGoogleMapsEnabled(packageManager: PackageManager): Boolean {
    return try {
      packageManager.getApplicationInfo(GOOGLE_MAPS_PACKAGE, 0).enabled
    } catch (_: PackageManager.NameNotFoundException) {
      false
    }
  }

  /**
   * Locale-invariant lat,lng for the navigation query (always '.' decimal).
   */
  fun formatCoordinatePair(latitude: Double, longitude: Double): String {
    return String.format(Locale.US, "%.6f,%.6f", latitude, longitude)
  }

  /**
   * google.navigation URI with driving mode, always targeted at the Maps package.
   * No FLAG_ACTIVITY_NEW_TASK — launched from the resumed Fluxidi Activity so
   * Maps can take the foreground before PiP handoff.
   */
  fun buildGoogleNavigationIntent(destination: Destination): Intent? {
    val uri = buildGoogleNavigationUri(destination) ?: return null
    return Intent(Intent.ACTION_VIEW, uri).apply {
      setPackage(GOOGLE_MAPS_PACKAGE)
      // Structured mode contract — avoids opaque Uri query parsing at launch.
      putExtra(EXTRA_NAVIGATION_MODE, NAVIGATION_MODE_DRIVING)
    }
  }

  /**
   * Pure string form for JVM unit tests (no Android Uri.encode dependency).
   * Spaces become '+'; production Intent path uses Uri.encode for addresses.
   */
  fun buildGoogleNavigationUriString(destination: Destination): String? {
    val destParam: String = when {
      destination.hasCoordinates() ->
        formatCoordinatePair(destination.latitude!!, destination.longitude!!)
      destination.hasAddress() ->
        destination.address!!.trim().replace(' ', '+')
      else -> return null
    }
    // mode=d forces driving navigation inside the Maps app.
    return "$NAVIGATION_SCHEME:q=$destParam&mode=$NAVIGATION_MODE_DRIVING"
  }

  fun buildGoogleNavigationUri(destination: Destination): Uri? {
    val uriString = buildGoogleNavigationUriString(destination) ?: return null
    return try {
      // Address path still needs Uri.encode for reserved characters.
      when {
        destination.hasCoordinates() -> Uri.parse(uriString)
        destination.hasAddress() ->
          Uri.parse(
            "$NAVIGATION_SCHEME:q=${Uri.encode(destination.address!!.trim())}" +
              "&mode=$NAVIGATION_MODE_DRIVING",
          )
        else -> null
      }
    } catch (_: Exception) {
      null
    }
  }

  fun canResolveNavigationIntent(
    packageManager: PackageManager,
    intent: Intent,
  ): Boolean {
    return try {
      intent.resolveActivity(packageManager) != null
    } catch (_: Exception) {
      false
    }
  }

  fun buildPlayStoreInstallIntent(): Intent {
    return Intent(
      Intent.ACTION_VIEW,
      Uri.parse("market://details?id=$GOOGLE_MAPS_PACKAGE"),
    ).apply {
      setPackage(PLAY_STORE_PACKAGE)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
  }

  fun buildPlayStoreWebFallbackIntent(): Intent {
    return Intent(
      Intent.ACTION_VIEW,
      Uri.parse(
        "https://play.google.com/store/apps/details?id=$GOOGLE_MAPS_PACKAGE",
      ),
    ).apply {
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
  }

  /**
   * Explicit Activity intent that brings the existing MainActivity task to the
   * foreground and expands out of PiP. Used by RemoteAction PendingIntent and
   * the MethodChannel return path.
   */
  fun buildReturnToFluxidiIntent(
    packageName: String,
    sessionToken: String? = null,
  ): Intent {
    return Intent().apply {
      setClassName(packageName, "$packageName.MainActivity")
      action = ACTION_RETURN_FROM_PIP
      // EXTERNAL-NAV-RETURN-LIFECYCLE-P0-7: prefer bringing the existing
      // singleTop MainActivity forward. CLEAR_TOP|NEW_TASK can recreate the
      // task/engine on Samsung PiP return and force a cold PIN gate.
      addFlags(
        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
          Intent.FLAG_ACTIVITY_SINGLE_TOP,
      )
      putExtra(EXTRA_PIP_RETURN, true)
      if (!sessionToken.isNullOrBlank()) {
        putExtra(EXTRA_PIP_SESSION, sessionToken)
      }
    }
  }

  /** Stable positive requestCode from an external-nav session token. */
  fun pipReturnRequestCode(sessionToken: String): Int {
    return sessionToken.hashCode() and 0x7fffffff
  }

  fun buildReturnToFluxidiPendingIntent(
    context: Context,
    sessionToken: String,
  ): PendingIntent {
    val requestCode = pipReturnRequestCode(sessionToken)
    val intent = buildReturnToFluxidiIntent(context.packageName, sessionToken)
    var flags = PendingIntent.FLAG_UPDATE_CURRENT
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      flags = flags or PendingIntent.FLAG_IMMUTABLE
    }
    return PendingIntent.getActivity(context, requestCode, intent, flags)
  }

  /**
   * ANDROID-RECENTS-PIP-AUTOENTER-P0: pure snapshot of return-intent gates
   * (JVM-testable without Robolectric).
   */
  data class PipReturnIntentSnapshot(
    val action: String? = null,
    val pipReturn: Boolean = false,
    val alreadyHandled: Boolean = false,
  )

  fun isExplicitPipReturnSnapshot(snapshot: PipReturnIntentSnapshot): Boolean {
    return snapshot.action == ACTION_RETURN_FROM_PIP || snapshot.pipReturn
  }

  fun shouldHandlePipReturnSnapshot(snapshot: PipReturnIntentSnapshot): Boolean {
    if (!isExplicitPipReturnSnapshot(snapshot)) return false
    if (snapshot.alreadyHandled) return false
    return true
  }

  fun consumePipReturnSnapshot(
    snapshot: PipReturnIntentSnapshot,
  ): PipReturnIntentSnapshot {
    if (!isExplicitPipReturnSnapshot(snapshot)) return snapshot
    return snapshot.copy(
      action = if (snapshot.action == ACTION_RETURN_FROM_PIP) {
        Intent.ACTION_MAIN
      } else {
        snapshot.action
      },
      pipReturn = false,
      alreadyHandled = true,
    )
  }

  /** Force-to-front only for an explicit, unconsumed PiP return. */
  fun isExplicitPipReturnIntent(intent: Intent?): Boolean {
    if (intent == null) return false
    return try {
      isExplicitPipReturnSnapshot(snapshotFromIntent(intent))
    } catch (_: Exception) {
      false
    }
  }

  fun wasPipReturnAlreadyHandled(intent: Intent?): Boolean {
    if (intent == null) return false
    return try {
      intent.getBooleanExtra(EXTRA_PIP_RETURN_HANDLED, false)
    } catch (_: Exception) {
      false
    }
  }

  /** True only for a fresh, explicit PiP return that has not been consumed. */
  fun shouldHandlePipReturn(intent: Intent?): Boolean {
    if (intent == null) return false
    return try {
      shouldHandlePipReturnSnapshot(snapshotFromIntent(intent))
    } catch (_: Exception) {
      false
    }
  }

  /**
   * Consume return extras in-place so onCreate/onNewIntent cannot replay
   * moveTaskToFront after Activity recreation.
   */
  fun consumePipReturnIntent(intent: Intent?): Boolean {
    if (intent == null) return false
    if (!isExplicitPipReturnIntent(intent)) return false
    return try {
      val consumed = consumePipReturnSnapshot(snapshotFromIntent(intent))
      intent.putExtra(EXTRA_PIP_RETURN, consumed.pipReturn)
      intent.putExtra(EXTRA_PIP_RETURN_HANDLED, consumed.alreadyHandled)
      intent.action = consumed.action
      true
    } catch (_: Exception) {
      false
    }
  }

  private fun snapshotFromIntent(intent: Intent): PipReturnIntentSnapshot {
    return PipReturnIntentSnapshot(
      action = intent.action,
      pipReturn = intent.getBooleanExtra(EXTRA_PIP_RETURN, false),
      alreadyHandled = intent.getBooleanExtra(EXTRA_PIP_RETURN_HANDLED, false),
    )
  }

  fun intentTargetsGoogleMapsOnly(intent: Intent): Boolean {
    return try {
      intent.`package` == GOOGLE_MAPS_PACKAGE &&
        intent.action == Intent.ACTION_VIEW &&
        intent.data != null &&
        (intent.data!!.scheme == NAVIGATION_SCHEME)
    } catch (_: Exception) {
      false
    }
  }

  /**
   * Pure SSP parser for opaque `google.navigation:` URIs.
   * Input example: `q=50.100000,3.200000&mode=d`
   * Never throws.
   */
  fun parseModeParameterFromNavigationSsp(ssp: String?): String? {
    if (ssp == null) return null
    return try {
      val normalized = ssp.trim().removePrefix("//")
      if (normalized.isEmpty()) return null
      for (segment in normalized.split('&')) {
        val idx = segment.indexOf('=')
        if (idx <= 0) continue
        val key = segment.substring(0, idx)
        if (key == "mode") {
          return segment.substring(idx + 1)
        }
      }
      null
    } catch (_: Exception) {
      null
    }
  }

  /**
   * Pure string validator for opaque navigation URIs. Never throws.
   * Never uses hierarchical Uri query APIs.
   */
  fun navigationUriStringUsesDrivingMode(uriString: String?): Boolean {
    if (uriString.isNullOrBlank()) return false
    return try {
      val trimmed = uriString.trim()
      val prefix = "$NAVIGATION_SCHEME:"
      if (!trimmed.startsWith(prefix)) return false
      val ssp = trimmed.substring(prefix.length)
      parseModeParameterFromNavigationSsp(ssp) == NAVIGATION_MODE_DRIVING
    } catch (_: Exception) {
      false
    }
  }

  /**
   * Driving-mode check that supports opaque google.navigation URIs.
   * Never throws. Prefer structured EXTRA, then opaque SSP parse.
   */
  fun intentUsesDrivingMode(intent: Intent): Boolean {
    return try {
      val extraMode = try {
        intent.getStringExtra(EXTRA_NAVIGATION_MODE)
      } catch (_: Exception) {
        null
      }
      if (extraMode == NAVIGATION_MODE_DRIVING) return true

      val data = intent.data ?: return false
      // Opaque URI: read scheme-specific part only. NEVER getQueryParameter.
      val ssp = try {
        data.encodedSchemeSpecificPart ?: data.schemeSpecificPart
      } catch (_: Exception) {
        null
      }
      if (parseModeParameterFromNavigationSsp(ssp) == NAVIGATION_MODE_DRIVING) {
        return true
      }
      navigationUriStringUsesDrivingMode(data.toString())
    } catch (_: Throwable) {
      false
    }
  }

  fun intentIsBrowserFallback(intent: Intent): Boolean {
    return try {
      val data = intent.data ?: return false
      val s = data.toString()
      s.startsWith("http://") ||
        s.startsWith("https://") ||
        s.contains("www.google.com/maps") ||
        s.contains("maps/dir")
    } catch (_: Exception) {
      false
    }
  }

  /**
   * Pre-launch intent contract validation. Never throws.
   * Returns null when valid, otherwise a failure_code.
   */
  fun validateNavigationIntentOrFailure(intent: Intent): String? {
    return try {
      if (intentIsBrowserFallback(intent)) return "browser_fallback"
      if (!intentTargetsGoogleMapsOnly(intent)) return "invalid_intent_target"
      if (!intentUsesDrivingMode(intent)) return "invalid_driving_mode"
      null
    } catch (t: Throwable) {
      "native_exception:${t.javaClass.simpleName}"
    }
  }
}
