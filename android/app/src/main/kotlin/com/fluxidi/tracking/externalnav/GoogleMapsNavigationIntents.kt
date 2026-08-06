package com.fluxidi.tracking.externalnav

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri

/**
 * GOOGLE-MAPS-DIRECT-LAUNCH-ANDROID-1
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
        longitude!!.isFinite()

    fun hasAddress(): Boolean = !address.isNullOrBlank()
  }

  fun isGoogleMapsInstalled(packageManager: PackageManager): Boolean {
    return try {
      packageManager.getPackageInfo(GOOGLE_MAPS_PACKAGE, 0)
      true
    } catch (_: PackageManager.NameNotFoundException) {
      false
    }
  }

  /**
   * google.navigation URI with driving mode, always targeted at the Maps package.
   */
  fun buildGoogleNavigationIntent(destination: Destination): Intent? {
    val uri = buildGoogleNavigationUri(destination) ?: return null
    return Intent(Intent.ACTION_VIEW, uri).apply {
      setPackage(GOOGLE_MAPS_PACKAGE)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
  }

  /**
   * Pure string form for JVM unit tests (no Android Uri.encode dependency).
   * Spaces become '+'; production Intent path uses Uri.encode.
   */
  fun buildGoogleNavigationUriString(destination: Destination): String? {
    val destParam: String = when {
      destination.hasCoordinates() ->
        "${destination.latitude},${destination.longitude}"
      destination.hasAddress() ->
        destination.address!!.trim().replace(' ', '+')
      else -> return null
    }
    // mode=d forces driving navigation inside the Maps app.
    return "google.navigation:q=$destParam&mode=d"
  }

  fun buildGoogleNavigationUri(destination: Destination): Uri? {
    return when {
      destination.hasCoordinates() ->
        // Keep lat,lng unencoded so Maps receives a clean coordinate pair.
        Uri.parse(
          "google.navigation:q=${destination.latitude},${destination.longitude}&mode=d",
        )
      destination.hasAddress() ->
        Uri.parse(
          "google.navigation:q=${Uri.encode(destination.address!!.trim())}&mode=d",
        )
      else -> null
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
}
