package com.fluxidi.tracking.externalnav

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * GOOGLE-MAPS-DIRECT-LAUNCH-ANDROID-1 — pure JVM URI/contract tests.
 * Avoids Robolectric so CI/local can run without long Android framework boot.
 */
class GoogleMapsNavigationIntentsTest {

  @Test
  fun buildsDrivingUriWithCoordinates() {
    val uri = GoogleMapsNavigationIntents.buildGoogleNavigationUriString(
      GoogleMapsNavigationIntents.Destination(latitude = 51.05, longitude = 3.72),
    )
    assertNotNull(uri)
    assertTrue(uri!!.startsWith("google.navigation:"))
    assertTrue(uri.contains("51.05"))
    assertTrue(uri.contains("3.72"))
    assertTrue(uri.contains("mode=d"))
    assertFalse(uri.startsWith("http"))
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
    assertTrue(uri!!.contains("51.05,3.72"))
    assertFalse(uri.contains("ShouldNotAppear"))
  }
}
