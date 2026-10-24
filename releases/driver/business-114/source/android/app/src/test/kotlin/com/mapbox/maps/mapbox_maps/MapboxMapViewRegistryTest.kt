package com.mapbox.maps.mapbox_maps

import com.mapbox.maps.MapView
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.mock
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue
import kotlin.test.assertFalse

/**
 * FLUXIDI NAV-STREETLEVEL-FLUID-MOTION-2 Phase 2A — unit tests for the
 * vendored plugin's `MapboxMapViewRegistry` patch.
 *
 * The registry is thin data-structure code that owns MapView WeakReferences
 * keyed by the plugin's `channelSuffix`. These tests exercise the four
 * hard-acceptance behaviors the Phase 2A architecture depends on:
 *
 *   1. Register + `get()` returns the exact instance and `unregister()`
 *      deterministically removes it.
 *   2. Two live map ids are isolated.
 *   3. Late listeners receive a replay of currently-live registrations.
 *   4. Unknown / already-disposed ids do not throw and return `null`.
 */
class MapboxMapViewRegistryTest {

  // clearForTest() is internal to the plugin module; clean via public APIs.
  @Before
  fun setUp() {
    for (id in MapboxMapViewRegistry.activeMapInstanceIds().toList()) {
      MapboxMapViewRegistry.unregister(id)
    }
  }

  @After
  fun tearDown() {
    for (id in MapboxMapViewRegistry.activeMapInstanceIds().toList()) {
      MapboxMapViewRegistry.unregister(id)
    }
  }

  @Test fun registerAndGetReturnsSameInstance() {
    val fake = mock(MapView::class.java)
    MapboxMapViewRegistry.register("0", fake)
    assertSame(fake, MapboxMapViewRegistry.get("0"))
    assertTrue(MapboxMapViewRegistry.activeMapInstanceIds().contains("0"))
  }

  @Test fun unregisterRemovesEntryDeterministically() {
    val fake = mock(MapView::class.java)
    MapboxMapViewRegistry.register("7", fake)
    MapboxMapViewRegistry.unregister("7")
    assertNull(MapboxMapViewRegistry.get("7"))
    assertFalse(MapboxMapViewRegistry.activeMapInstanceIds().contains("7"))
  }

  @Test fun unregisterUnknownIdIsSilent() {
    // Must not throw, must not notify listeners spuriously.
    var notified = 0
    val listener = object : MapboxMapViewRegistry.Listener {
      override fun onMapViewRegistered(mapInstanceId: String, mapView: MapView) { notified += 1 }
      override fun onMapViewUnregistered(mapInstanceId: String) { notified += 1 }
    }
    MapboxMapViewRegistry.addListener(listener)
    MapboxMapViewRegistry.unregister("nope")
    assertEquals(0, notified)
    MapboxMapViewRegistry.removeListener(listener)
  }

  @Test fun twoSimultaneousMapsRemainIsolated() {
    val a = mock(MapView::class.java)
    val b = mock(MapView::class.java)
    MapboxMapViewRegistry.register("0", a)
    MapboxMapViewRegistry.register("1", b)
    assertSame(a, MapboxMapViewRegistry.get("0"))
    assertSame(b, MapboxMapViewRegistry.get("1"))
    // Unregistering one must NOT affect the other.
    MapboxMapViewRegistry.unregister("0")
    assertNull(MapboxMapViewRegistry.get("0"))
    assertSame(b, MapboxMapViewRegistry.get("1"))
  }

  @Test fun listenerReceivesRegisterAndUnregisterEvents() {
    val a = mock(MapView::class.java)
    val events = mutableListOf<String>()
    val listener = object : MapboxMapViewRegistry.Listener {
      override fun onMapViewRegistered(mapInstanceId: String, mapView: MapView) {
        events.add("reg:$mapInstanceId")
      }
      override fun onMapViewUnregistered(mapInstanceId: String) {
        events.add("unreg:$mapInstanceId")
      }
    }
    MapboxMapViewRegistry.addListener(listener)
    MapboxMapViewRegistry.register("0", a)
    MapboxMapViewRegistry.unregister("0")
    MapboxMapViewRegistry.removeListener(listener)
    assertEquals(listOf("reg:0", "unreg:0"), events)
  }

  @Test fun lateAttachedListenerGetsReplayOfLiveRegistrations() {
    val a = mock(MapView::class.java)
    val b = mock(MapView::class.java)
    MapboxMapViewRegistry.register("0", a)
    MapboxMapViewRegistry.register("1", b)
    val received = mutableSetOf<String>()
    val listener = object : MapboxMapViewRegistry.Listener {
      override fun onMapViewRegistered(mapInstanceId: String, mapView: MapView) {
        received.add(mapInstanceId)
      }
      override fun onMapViewUnregistered(mapInstanceId: String) {}
    }
    MapboxMapViewRegistry.addListener(listener)
    assertEquals(setOf("0", "1"), received)
    MapboxMapViewRegistry.removeListener(listener)
  }

  @Test fun repeatedRegisterReplacesEntry() {
    val a = mock(MapView::class.java)
    val b = mock(MapView::class.java)
    MapboxMapViewRegistry.register("0", a)
    MapboxMapViewRegistry.register("0", b)
    assertSame(b, MapboxMapViewRegistry.get("0"))
  }

  @Test fun removeListenerStopsNotifications() {
    val a = mock(MapView::class.java)
    val received = mutableListOf<String>()
    val listener = object : MapboxMapViewRegistry.Listener {
      override fun onMapViewRegistered(mapInstanceId: String, mapView: MapView) {
        received.add("reg:$mapInstanceId")
      }
      override fun onMapViewUnregistered(mapInstanceId: String) {
        received.add("unreg:$mapInstanceId")
      }
    }
    MapboxMapViewRegistry.addListener(listener)
    MapboxMapViewRegistry.removeListener(listener)
    MapboxMapViewRegistry.register("0", a)
    MapboxMapViewRegistry.unregister("0")
    assertEquals(emptyList(), received)
  }

  @Test fun activeMapInstanceIdsAreSorted() {
    val a = mock(MapView::class.java)
    val b = mock(MapView::class.java)
    val c = mock(MapView::class.java)
    MapboxMapViewRegistry.register("2", a)
    MapboxMapViewRegistry.register("0", b)
    MapboxMapViewRegistry.register("1", c)
    assertEquals(listOf("0", "1", "2"), MapboxMapViewRegistry.activeMapInstanceIds())
  }
}
