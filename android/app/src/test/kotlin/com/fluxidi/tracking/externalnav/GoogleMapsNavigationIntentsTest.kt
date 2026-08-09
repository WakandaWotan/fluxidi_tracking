package com.fluxidi.tracking.externalnav

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.Locale

/**
 * GOOGLE-MAPS-DIRECT-LAUNCH-ANDROID-1 /
 * GOOGLE-MAPS-LAUNCH-CONTRACT-NOOP-P0-2 /
 * GOOGLE-MAPS-OPAQUE-NAVIGATION-URI-P0-3
 */
class GoogleMapsNavigationIntentsTest {

  @Test
  fun buildsDrivingUriWithCoordinates() {
    val uri = GoogleMapsNavigationIntents.buildGoogleNavigationUriString(
      GoogleMapsNavigationIntents.Destination(latitude = 51.05, longitude = 3.72),
    )
    assertNotNull(uri)
    assertTrue(uri!!.startsWith("google.navigation:"))
    assertTrue(uri.contains("51.050000"))
    assertTrue(uri.contains("3.720000"))
    assertTrue(uri.contains("mode=d"))
    assertFalse(uri.startsWith("http"))
  }

  @Test
  fun decimalPointIndependentOfLocale() {
    val previous = Locale.getDefault()
    try {
      Locale.setDefault(Locale.GERMANY)
      val pair = GoogleMapsNavigationIntents.formatCoordinatePair(51.05, 3.72)
      assertEquals("51.050000,3.720000", pair)
      assertEquals(1, pair.count { it == ',' })
      assertTrue(pair.contains('.'))
      assertFalse(pair.contains("51,05"))
    } finally {
      Locale.setDefault(previous)
    }
  }

  @Test
  fun buildsUriFromAddressWhenCoordinatesMissing() {
    val uri = GoogleMapsNavigationIntents.buildGoogleNavigationUriString(
      GoogleMapsNavigationIntents.Destination(address = "Korenmarkt Gent"),
    )
    assertNotNull(uri)
    assertTrue(uri!!.contains("Korenmarkt"))
    assertTrue(uri.contains("mode=d"))
  }

  @Test
  fun returnsNullWhenDestinationEmpty() {
    assertNull(
      GoogleMapsNavigationIntents.buildGoogleNavigationUriString(
        GoogleMapsNavigationIntents.Destination(),
      ),
    )
  }

  @Test
  fun rejectsOutOfRangeCoordinates() {
    assertFalse(
      GoogleMapsNavigationIntents.Destination(latitude = 91.0, longitude = 3.0)
        .hasCoordinates(),
    )
    assertFalse(
      GoogleMapsNavigationIntents.Destination(latitude = 51.0, longitude = 181.0)
        .hasCoordinates(),
    )
    assertNull(
      GoogleMapsNavigationIntents.buildGoogleNavigationUriString(
        GoogleMapsNavigationIntents.Destination(latitude = 91.0, longitude = 3.0),
      ),
    )
  }

  @Test
  fun rejectsStringNullAddress() {
    assertFalse(
      GoogleMapsNavigationIntents.Destination(address = "null").hasAddress(),
    )
  }

  @Test
  fun googleMapsPackageConstantIsExplicit() {
    assertEquals("com.google.android.apps.maps", GoogleMapsNavigationIntents.GOOGLE_MAPS_PACKAGE)
  }

  @Test
  fun playStorePackageTargetsVending() {
    assertEquals("com.android.vending", GoogleMapsNavigationIntents.PLAY_STORE_PACKAGE)
  }

  @Test
  fun uriIsNotBrowserHttps() {
    val uri = GoogleMapsNavigationIntents.buildGoogleNavigationUriString(
      GoogleMapsNavigationIntents.Destination(latitude = 50.85, longitude = 4.35),
    )
    assertNotNull(uri)
    assertFalse(uri!!.contains("http"))
    assertFalse(uri.contains("www.google.com"))
    assertFalse(uri.contains("maps/dir"))
  }

  @Test
  fun coordinatesPreferredOverAddressInUri() {
    val uri = GoogleMapsNavigationIntents.buildGoogleNavigationUriString(
      GoogleMapsNavigationIntents.Destination(
        latitude = 51.05,
        longitude = 3.72,
        address = "ShouldNotAppear",
      ),
    )
    assertNotNull(uri)
    assertTrue(uri!!.contains("51.050000,3.720000"))
    assertFalse(uri.contains("ShouldNotAppear"))
  }

  @Test
  fun structuredStatusConstantsExist() {
    assertEquals("launched", ExternalNavigationPlugin.STATUS_LAUNCHED)
    assertEquals("maps_not_installed", ExternalNavigationPlugin.STATUS_MAPS_NOT_INSTALLED)
    assertEquals("maps_disabled", ExternalNavigationPlugin.STATUS_MAPS_DISABLED)
    assertEquals("invalid_destination", ExternalNavigationPlugin.STATUS_INVALID_DESTINATION)
    assertEquals("intent_not_resolved", ExternalNavigationPlugin.STATUS_INTENT_NOT_RESOLVED)
    assertEquals("activity_not_found", ExternalNavigationPlugin.STATUS_ACTIVITY_NOT_FOUND)
    assertEquals("security_exception", ExternalNavigationPlugin.STATUS_SECURITY_EXCEPTION)
    assertEquals("native_exception", ExternalNavigationPlugin.STATUS_NATIVE_EXCEPTION)
  }

  @Test
  fun latLngOrderIsLatitudeThenLongitude() {
    val pair = GoogleMapsNavigationIntents.formatCoordinatePair(50.850000, 4.350000)
    assertEquals("50.850000,4.350000", pair)
    assertFalse(pair.startsWith("4.350000"))
  }

  // --- GOOGLE-MAPS-OPAQUE-NAVIGATION-URI-P0-3 ---

  @Test
  fun opaqueCoordinateUriWithModeDIsValid() {
    val uri = "google.navigation:q=50.100000,3.200000&mode=d"
    assertTrue(GoogleMapsNavigationIntents.navigationUriStringUsesDrivingMode(uri))
    assertEquals(
      "d",
      GoogleMapsNavigationIntents.parseModeParameterFromNavigationSsp(
        "q=50.100000,3.200000&mode=d",
      ),
    )
  }

  @Test
  fun opaqueAddressUriWithModeDIsValid() {
    val uri = GoogleMapsNavigationIntents.buildGoogleNavigationUriString(
      GoogleMapsNavigationIntents.Destination(address = "Korenmarkt Gent"),
    )
    assertNotNull(uri)
    assertTrue(GoogleMapsNavigationIntents.navigationUriStringUsesDrivingMode(uri))
  }

  @Test
  fun missingModeReturnsFalseWithoutException() {
    assertFalse(
      GoogleMapsNavigationIntents.navigationUriStringUsesDrivingMode(
        "google.navigation:q=50.1,3.2",
      ),
    )
    assertNull(
      GoogleMapsNavigationIntents.parseModeParameterFromNavigationSsp("q=50.1,3.2"),
    )
  }

  @Test
  fun walkingModeReturnsFalseWithoutException() {
    assertFalse(
      GoogleMapsNavigationIntents.navigationUriStringUsesDrivingMode(
        "google.navigation:q=50.1,3.2&mode=w",
      ),
    )
    assertEquals(
      "w",
      GoogleMapsNavigationIntents.parseModeParameterFromNavigationSsp("q=50.1,3.2&mode=w"),
    )
  }

  @Test
  fun malformedUriReturnsStructuredFalseWithoutThrow() {
    assertFalse(GoogleMapsNavigationIntents.navigationUriStringUsesDrivingMode(null))
    assertFalse(GoogleMapsNavigationIntents.navigationUriStringUsesDrivingMode(""))
    assertFalse(GoogleMapsNavigationIntents.navigationUriStringUsesDrivingMode("not-a-uri"))
    assertFalse(
      GoogleMapsNavigationIntents.navigationUriStringUsesDrivingMode("http://example.com?mode=d"),
    )
    assertNull(GoogleMapsNavigationIntents.parseModeParameterFromNavigationSsp(null))
    assertNull(GoogleMapsNavigationIntents.parseModeParameterFromNavigationSsp("&&&"))
  }

  @Test
  fun sourceDoesNotCallGetQueryParameterOnOpaqueNavigationUris() {
    // Guard against reintroducing the hierarchical Uri API that crashes opaque
    // google.navigation: URIs with UnsupportedOperationException.
    val candidates = listOf(
      File("src/main/kotlin/com/fluxidi/tracking/externalnav/GoogleMapsNavigationIntents.kt"),
      File(
        "../src/main/kotlin/com/fluxidi/tracking/externalnav/GoogleMapsNavigationIntents.kt",
      ),
      File(
        "android/app/src/main/kotlin/com/fluxidi/tracking/externalnav/GoogleMapsNavigationIntents.kt",
      ),
    )
    val sourceFile = candidates.firstOrNull { it.isFile }
      ?: error("GoogleMapsNavigationIntents.kt not found for source guard")
    val source = sourceFile.readText()
    assertFalse(
      "getQueryParameter must not be used on google.navigation URIs",
      source.contains("getQueryParameter("),
    )
    assertFalse(source.contains("queryParameterNames"))
    assertTrue(source.contains("encodedSchemeSpecificPart") || source.contains("schemeSpecificPart"))
    assertTrue(source.contains("EXTRA_NAVIGATION_MODE"))
  }

  @Test
  fun builtUriStringKeepsDirectNavigationContract() {
    // Existing direct-intent shape remains: google.navigation:q=...&mode=d
    val uri = GoogleMapsNavigationIntents.buildGoogleNavigationUriString(
      GoogleMapsNavigationIntents.Destination(latitude = 51.0543, longitude = 3.7174),
    )
    assertEquals("google.navigation:q=51.054300,3.717400&mode=d", uri)
    assertTrue(GoogleMapsNavigationIntents.navigationUriStringUsesDrivingMode(uri))
  }

  @Test
  fun drivingModeExtraConstantIsStructuredContract() {
    assertEquals("fluxidi_google_navigation_mode", GoogleMapsNavigationIntents.EXTRA_NAVIGATION_MODE)
    assertEquals("d", GoogleMapsNavigationIntents.NAVIGATION_MODE_DRIVING)
  }

  @Test
  fun returnToFluxidiIntentSourceReordersExistingTask() {
    // PIP-ACTIVITY-RETURN-TO-FLUXIDI-P0-6 — JVM unit tests cannot call
    // setClassName / PendingIntent (not mocked). Guard source contract.
    val candidates = listOf(
      File("src/main/kotlin/com/fluxidi/tracking/externalnav/GoogleMapsNavigationIntents.kt"),
      File(
        "../src/main/kotlin/com/fluxidi/tracking/externalnav/GoogleMapsNavigationIntents.kt",
      ),
      File(
        "android/app/src/main/kotlin/com/fluxidi/tracking/externalnav/GoogleMapsNavigationIntents.kt",
      ),
    )
    val sourceFile = candidates.firstOrNull { it.isFile }
      ?: error("GoogleMapsNavigationIntents.kt not found for return guard")
    val source = sourceFile.readText()
    assertTrue(source.contains("buildReturnToFluxidiIntent"))
    assertTrue(source.contains("buildReturnToFluxidiPendingIntent"))
    assertTrue(source.contains("FLAG_ACTIVITY_REORDER_TO_FRONT"))
    assertTrue(source.contains("FLAG_ACTIVITY_SINGLE_TOP"))
    // EXTERNAL-NAV-RETURN-LIFECYCLE-P0-7: CLEAR_TOP|NEW_TASK removed from
    // return intent to avoid Samsung PiP cold-task recreation.
    assertTrue(!source.contains("FLAG_ACTIVITY_CLEAR_TOP"))
    assertTrue(source.contains("FLAG_UPDATE_CURRENT"))
    assertTrue(source.contains("FLAG_IMMUTABLE"))
    assertTrue(source.contains("ACTION_RETURN_FROM_PIP"))
    assertTrue(source.contains("fluxidi_external_nav_return"))
    assertTrue(source.contains("MainActivity"))
  }

  @Test
  fun pipReturnRequestCodeIsStablePerSessionToken() {
    val a = GoogleMapsNavigationIntents.pipReturnRequestCode("pip_session_1")
    val b = GoogleMapsNavigationIntents.pipReturnRequestCode("pip_session_1")
    val c = GoogleMapsNavigationIntents.pipReturnRequestCode("pip_session_2")
    assertEquals(a, b)
    assertTrue(a != c)
    assertTrue(a >= 0)
  }

  @Test
  fun pluginSourceRegistersRemoteActionAndOnNewIntentPath() {
    val pluginCandidates = listOf(
      File("src/main/kotlin/com/fluxidi/tracking/externalnav/ExternalNavigationPlugin.kt"),
      File(
        "../src/main/kotlin/com/fluxidi/tracking/externalnav/ExternalNavigationPlugin.kt",
      ),
      File(
        "android/app/src/main/kotlin/com/fluxidi/tracking/externalnav/ExternalNavigationPlugin.kt",
      ),
    )
    val mainCandidates = listOf(
      File("src/main/kotlin/com/fluxidi/tracking/MainActivity.kt"),
      File("../src/main/kotlin/com/fluxidi/tracking/MainActivity.kt"),
      File("android/app/src/main/kotlin/com/fluxidi/tracking/MainActivity.kt"),
    )
    val plugin = pluginCandidates.firstOrNull { it.isFile }
      ?: error("ExternalNavigationPlugin.kt missing")
    val main = mainCandidates.firstOrNull { it.isFile }
      ?: error("MainActivity.kt missing")
    val pluginSrc = plugin.readText()
    val mainSrc = main.readText()
    assertTrue(pluginSrc.contains("RemoteAction"))
    assertTrue(pluginSrc.contains("setActions"))
    assertTrue(pluginSrc.contains("moveTaskToFront"))
    assertTrue(pluginSrc.contains("handleReturnFromPipIntent"))
    assertTrue(pluginSrc.contains("pip_remote_action_created"))
    assertTrue(pluginSrc.contains("pip_remote_action_clicked"))
    assertTrue(pluginSrc.contains("pip_return_intent_received"))
    assertTrue(pluginSrc.contains("pip_task_brought_to_front"))
    assertTrue(pluginSrc.contains("pip_return_failed"))
    assertTrue(pluginSrc.contains("setEnabled(true)"))
    assertTrue(mainSrc.contains("onNewIntent"))
    assertTrue(mainSrc.contains("handleReturnFromPipIntent"))
  }

  // ANDROID-RECENTS-PIP-AUTOENTER-P0

  @Test
  fun explicitPipReturnSnapshotIsHandledOnce() {
    val fresh = GoogleMapsNavigationIntents.PipReturnIntentSnapshot(
      action = GoogleMapsNavigationIntents.ACTION_RETURN_FROM_PIP,
      pipReturn = true,
      alreadyHandled = false,
    )
    assertTrue(GoogleMapsNavigationIntents.shouldHandlePipReturnSnapshot(fresh))
    val consumed = GoogleMapsNavigationIntents.consumePipReturnSnapshot(fresh)
    assertTrue(consumed.alreadyHandled)
    assertFalse(consumed.pipReturn)
    assertFalse(GoogleMapsNavigationIntents.shouldHandlePipReturnSnapshot(consumed))
  }

  @Test
  fun genericLifecycleSnapshotDoesNotForceToFront() {
    val generic = GoogleMapsNavigationIntents.PipReturnIntentSnapshot(
      action = "android.intent.action.MAIN",
      pipReturn = false,
      alreadyHandled = false,
    )
    assertFalse(GoogleMapsNavigationIntents.isExplicitPipReturnSnapshot(generic))
    assertFalse(GoogleMapsNavigationIntents.shouldHandlePipReturnSnapshot(generic))
  }

  @Test
  fun alreadyHandledReturnCannotReplay() {
    val handled = GoogleMapsNavigationIntents.PipReturnIntentSnapshot(
      action = GoogleMapsNavigationIntents.ACTION_RETURN_FROM_PIP,
      pipReturn = true,
      alreadyHandled = true,
    )
    assertFalse(GoogleMapsNavigationIntents.shouldHandlePipReturnSnapshot(handled))
  }

  @Test
  fun pluginSourceClearsStickyAutoEnterAndGatesForceToFront() {
    val pluginCandidates = listOf(
      File("src/main/kotlin/com/fluxidi/tracking/externalnav/ExternalNavigationPlugin.kt"),
      File(
        "../src/main/kotlin/com/fluxidi/tracking/externalnav/ExternalNavigationPlugin.kt",
      ),
      File(
        "android/app/src/main/kotlin/com/fluxidi/tracking/externalnav/ExternalNavigationPlugin.kt",
      ),
    )
    val mainCandidates = listOf(
      File("src/main/kotlin/com/fluxidi/tracking/MainActivity.kt"),
      File("../src/main/kotlin/com/fluxidi/tracking/MainActivity.kt"),
      File("android/app/src/main/kotlin/com/fluxidi/tracking/MainActivity.kt"),
    )
    val pluginSrc = pluginCandidates.first { it.isFile }.readText()
    val mainSrc = mainCandidates.first { it.isFile }.readText()

    assertTrue(pluginSrc.contains("fun clearPipAutoEnter"))
    assertTrue(pluginSrc.contains("setAutoEnterEnabled(autoEnter)"))
    assertTrue(pluginSrc.contains("autoEnter = true"))
    assertTrue(pluginSrc.contains("clearPipAutoEnter(reason = \"maps_launch_failed"))
    assertTrue(pluginSrc.contains("clearPipAutoEnter(reason = \"pip_enter_failed\")"))
    assertTrue(pluginSrc.contains("clearPipAutoEnter(reason = \"pip_mode_exited\")"))
    assertTrue(pluginSrc.contains("clearPipAutoEnter(reason = \"activity_resumed_not_in_pip\")"))
    assertTrue(pluginSrc.contains("clearPipAutoEnter(reason = \"exit_fluxidi_pip_cleanup\")"))
    assertTrue(pluginSrc.contains("shouldHandlePipReturn"))
    assertTrue(pluginSrc.contains("consumeReturnIntentOnActivity"))
    assertTrue(pluginSrc.contains("force_to_front=false"))
    assertTrue(pluginSrc.contains("method_channel_explicit_return"))
    // exitFluxidiPip must not unconditionally call returnToFluxidi/bringToFront.
    val exitIdx = pluginSrc.indexOf("private fun exitFluxidiPip")
    assertTrue(exitIdx > 0)
    val exitChunk = pluginSrc.substring(exitIdx, exitIdx + 900)
    assertTrue(exitChunk.contains("force_to_front=false"))
    assertFalse(exitChunk.contains("bringFluxidiTaskToFront"))
    // enterFluxidiPip must not re-arm sticky autoEnter=true.
    val enterIdx = pluginSrc.indexOf("private fun enterFluxidiPip")
    assertTrue(enterIdx > 0)
    val enterChunk = pluginSrc.substring(enterIdx, enterIdx + 1600)
    assertFalse(enterChunk.contains("autoEnter = true"))
    assertTrue(mainSrc.contains("onActivityResumed"))
  }
}
