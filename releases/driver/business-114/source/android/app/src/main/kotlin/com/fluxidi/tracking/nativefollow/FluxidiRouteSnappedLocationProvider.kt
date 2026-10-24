package com.fluxidi.tracking.nativefollow

import com.mapbox.geojson.Point
import com.mapbox.maps.plugin.locationcomponent.LocationConsumer
import com.mapbox.maps.plugin.locationcomponent.LocationProvider
import java.util.concurrent.CopyOnWriteArraySet

/**
 * FLUXIDI NAV-STREETLEVEL-FLUID-MOTION-2 Phase 2A — custom Mapbox
 * `LocationProvider` (`com.mapbox.maps.plugin.locationcomponent.*`) that
 * publishes Fluxidi's authoritative route-snapped / predicted pose to the
 * map's location component.
 *
 * Course bearing is fed via [LocationConsumer.onBearingUpdated] on every
 * pose so `FollowPuckViewportState` (configured with
 * `puckBearing = PuckBearing.COURSE`) can drive the camera bearing from
 * the route course, NOT from the compass heading.
 *
 * Concurrency:
 *   * [submit] is called from the Flutter platform thread (Pigeon handler
 *     thread). It captures the latest pose, then forwards the update to
 *     every registered consumer synchronously on that thread; Mapbox
 *     internal animators pick the value up on the next frame.
 *   * Consumer registration / unregistration uses
 *     `CopyOnWriteArraySet` so concurrent submit + register is safe
 *     without external locking.
 *
 * The provider does NOT enforce validity, generation, or rate limits — the
 * `FluxidiNativeFollowManager` is the single point where those policies
 * are applied.
 */
class FluxidiRouteSnappedLocationProvider : LocationProvider {
  private val consumers: CopyOnWriteArraySet<LocationConsumer> =
    CopyOnWriteArraySet()

  @Volatile
  private var lastPoint: Point? = null

  @Volatile
  private var lastCourseDegrees: Double = 0.0

  @Volatile
  private var lastHorizontalAccuracyM: Double = 0.0

  override fun registerLocationConsumer(locationConsumer: LocationConsumer) {
    consumers.add(locationConsumer)
    // Emit the currently-latched pose to the newly-attached consumer so
    // FollowPuck does not spend a frame at 0,0 waiting for the next Dart
    // submission.
    lastPoint?.let { p ->
      locationConsumer.onLocationUpdated(p)
      locationConsumer.onBearingUpdated(lastCourseDegrees)
      if (lastHorizontalAccuracyM > 0.0) {
        locationConsumer.onHorizontalAccuracyRadiusUpdated(
          lastHorizontalAccuracyM
        )
      }
    }
  }

  override fun unRegisterLocationConsumer(locationConsumer: LocationConsumer) {
    consumers.remove(locationConsumer)
  }

  /**
   * Publishes one pose. Called from [FluxidiNativeFollowManager] after
   * validity + generation checks. Returns `true` if the pose was
   * broadcast to at least one consumer.
   */
  fun submit(
    latitude: Double,
    longitude: Double,
    courseDegrees: Double,
    horizontalAccuracyMeters: Double,
  ): Boolean {
    val point = Point.fromLngLat(longitude, latitude)
    lastPoint = point
    lastCourseDegrees = courseDegrees
    lastHorizontalAccuracyM = horizontalAccuracyMeters
    if (consumers.isEmpty()) return false
    val safeAccuracy = if (horizontalAccuracyMeters > 0.0) {
      horizontalAccuracyMeters
    } else {
      null
    }
    consumers.forEach { consumer ->
      consumer.onLocationUpdated(point)
      consumer.onBearingUpdated(courseDegrees)
      if (safeAccuracy != null) {
        consumer.onHorizontalAccuracyRadiusUpdated(safeAccuracy)
      }
    }
    return true
  }

  fun teardown() {
    consumers.clear()
    lastPoint = null
    lastCourseDegrees = 0.0
    lastHorizontalAccuracyM = 0.0
  }

  /** Number of currently-registered consumers. Diagnostics only. */
  fun consumerCount(): Int = consumers.size

  /** Test-only accessor for the latched point. */
  internal fun lastPointForTest(): Point? = lastPoint

  /** Test-only accessor for the latched course. */
  internal fun lastCourseDegreesForTest(): Double = lastCourseDegrees
}
