package com.mapbox.maps.mapbox_maps

import com.mapbox.maps.MapView
import java.lang.ref.WeakReference
import java.util.Collections

/**
 * FLUXIDI Phase 2A patch — NOT part of upstream mapbox_maps_flutter.
 *
 * Purpose:
 *   Exposes each live [MapView] instance created inside a [MapboxMapController]
 *   to companion Kotlin code so a custom Mapbox `LocationProvider` +
 *   `FollowPuckViewportState` + `LocationPuck3D` can be installed on the
 *   *exact* MapView owned by the plugin, without reflection, without a
 *   global view search, and without creating a second MapView.
 *
 * Lifecycle:
 *   * [register] is called from `MapboxMapController.init` immediately after
 *     `FlutterMapView` construction. The key is the plugin's own
 *     `channelSuffix` (per-controller monotonic id already used for every
 *     other Pigeon subchannel on that map).
 *   * [unregister] is called from `MapboxMapController.dispose()` as the
 *     first side effect so late listener callbacks always observe a
 *     deterministic teardown.
 *   * The registry holds each MapView through a [WeakReference] so a caller
 *     that misses a dispose call cannot leak the view — but explicit
 *     unregister on dispose is the primary cleanup path.
 *
 * Isolation:
 *   Two live controllers register under two independent channel suffixes
 *   and produce two independent listener notifications; a pose intended for
 *   one map cannot reach the other.
 *
 * Thread-safety:
 *   All public methods are synchronized against `internalLock`. Listener
 *   callbacks fire on the caller thread (the Flutter platform thread for
 *   register/unregister calls made from `MapboxMapController`).
 */
object MapboxMapViewRegistry {
  private val internalLock = Any()
  private val entries: MutableMap<String, WeakReference<MapView>> =
    Collections.synchronizedMap(mutableMapOf())
  private val listeners: MutableSet<Listener> =
    Collections.synchronizedSet(mutableSetOf())

  /**
   * Listener contract implemented by companion plugins (e.g. Fluxidi's
   * native-follow bridge) that want to be notified when the plugin creates
   * or disposes a MapView.
   *
   * Late attachment is supported: [addListener] replays the currently-live
   * registration set to the newly-added listener so attachment order does
   * not matter.
   */
  interface Listener {
    fun onMapViewRegistered(mapInstanceId: String, mapView: MapView)
    fun onMapViewUnregistered(mapInstanceId: String)
  }

  fun register(mapInstanceId: String, mapView: MapView) {
    val snapshotListeners: List<Listener>
    synchronized(internalLock) {
      entries[mapInstanceId] = WeakReference(mapView)
      snapshotListeners = listeners.toList()
    }
    snapshotListeners.forEach { it.onMapViewRegistered(mapInstanceId, mapView) }
  }

  fun unregister(mapInstanceId: String) {
    val removed: WeakReference<MapView>?
    val snapshotListeners: List<Listener>
    synchronized(internalLock) {
      removed = entries.remove(mapInstanceId)
      snapshotListeners = listeners.toList()
    }
    if (removed != null) {
      snapshotListeners.forEach { it.onMapViewUnregistered(mapInstanceId) }
    }
  }

  fun get(mapInstanceId: String): MapView? {
    val ref: WeakReference<MapView>? = synchronized(internalLock) {
      entries[mapInstanceId]
    }
    val view = ref?.get()
    if (ref != null && view == null) {
      // Defense in depth: the plugin somehow died without calling dispose.
      // Notify listeners so they can drop stale state deterministically.
      unregister(mapInstanceId)
    }
    return view
  }

  fun activeMapInstanceIds(): List<String> {
    val snapshot = synchronized(internalLock) { entries.toMap() }
    return snapshot.entries
      .filter { it.value.get() != null }
      .map { it.key }
      .sorted()
  }

  fun addListener(listener: Listener) {
    val replay: List<Pair<String, MapView>>
    synchronized(internalLock) {
      listeners.add(listener)
      replay = entries.entries
        .mapNotNull { (id, ref) -> ref.get()?.let { id to it } }
    }
    replay.forEach { (id, view) -> listener.onMapViewRegistered(id, view) }
  }

  fun removeListener(listener: Listener) {
    synchronized(internalLock) { listeners.remove(listener) }
  }

  /**
   * Test-only: clears every entry and listener. Only exercised from the
   * plugin's own unit tests; never called from production code paths.
   */
  internal fun clearForTest() {
    synchronized(internalLock) {
      entries.clear()
      listeners.clear()
    }
  }
}
