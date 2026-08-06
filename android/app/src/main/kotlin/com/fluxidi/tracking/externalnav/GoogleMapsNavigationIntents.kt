package com.fluxidi.tracking.externalnav

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import java.util.Locale

/**
 * GOOGLE-MAPS-DIRECT-LAUNCH-ANDROID-1 / GOOGLE-MAPS-LAUNCH-CONTRACT-NOOP-P0-2
 *
 * Pure helpers that build an explicit Google Maps navigation Intent.
 * No browser chooser, no generic VIEW without package.
 */
object GoogleMapsNavigationIntents {
  const val GOOGLE_MAPS_PACKAGE = "com.google.android.apps.maps"
  const val PLAY_STORE_PACKAGE = "com.android.vending"

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
    return "google.navigation:q=$destParam&mode=d"
  }

  fun buildGoogleNavigationUri(destination: Destination): Uri? {
    return when {
      destination.hasCoordinates() -> {
        val pair = formatCoordinatePair(destination.latitude!!, destination.longitude!!)
        Uri.parse("google.navigation:q=$pair&mode=d")
      }
      destination.hasAddress() ->
        Uri.parse(
          "google.navigation:q=${Uri.encode(destination.address!!.trim())}&mode=d",
        )
      else -> null
    }
  }

  fun canResolveNavigationIntent(
    packageManager: PackageManager,
    intent: Intent,
  ): Boolean {
    return intent.resolveActivity(packageManager) != null
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

  fun buildReturnToFluxidiIntent(packageName: String): Intent {
    return Intent().apply {
      setClassName(packageName, "$packageName.MainActivity")
      addFlags(
        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
          Intent.FLAG_ACTIVITY_SINGLE_TOP or
          Intent.FLAG_ACTIVITY_NEW_TASK,
      )
      putExtra("fluxidi_external_nav_return", true)
    }
  }

  fun intentTargetsGoogleMapsOnly(intent: Intent): Boolean {
    return intent.`package` == GOOGLE_MAPS_PACKAGE &&
      intent.action == Intent.ACTION_VIEW &&
      intent.data != null &&
      (intent.data!!.scheme == "google.navigation")
  }

  fun intentUsesDrivingMode(intent: Intent): Boolean {
    val data = intent.data ?: return false
    return data.getQueryParameter("mode") == "d" ||
      data.toString().contains("mode=d")
  }

  fun intentIsBrowserFallback(intent: Intent): Boolean {
    val data = intent.data ?: return false
    val s = data.toString()
    return s.startsWith("http://") ||
      s.startsWith("https://") ||
      s.contains("www.google.com/maps") ||
      s.contains("maps/dir")
  }
}
