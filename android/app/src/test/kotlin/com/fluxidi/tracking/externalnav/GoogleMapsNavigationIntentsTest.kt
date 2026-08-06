package com.fluxidi.tracking.externalnav

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

/**
 * GOOGLE-MAPS-DIRECT-LAUNCH-ANDROID-1 / GOOGLE-MAPS-PIP-HANDOFF-P0-1
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
      Locale.setDefault(Locale.GERMANY) // uses comma as decimal separator
      val pair = GoogleMapsNavigationIntents.formatCoordinatePair(51.05, 3.72)
      assertEquals("51.050000,3.720000", pair)
      // Separator between lat/lng is ',', decimals stay '.' (never "51,05").
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
}
