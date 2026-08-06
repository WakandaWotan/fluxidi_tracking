package com.fluxidi.tracking.externalnav

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

/**
 * GOOGLE-MAPS-DIRECT-LAUNCH-ANDROID-1 / GOOGLE-MAPS-LAUNCH-CONTRACT-NOOP-P0-2
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
    // Never swapped to lng,lat.
    assertFalse(pair.startsWith("4.350000"))
  }
}
