package com.fluxidi.tracking.nativefollow

import android.util.Log
import com.mapbox.maps.MapView
import com.mapbox.maps.mapbox_maps.MapboxMapViewRegistry
import com.mapbox.maps.plugin.LocationPuck3D
import com.mapbox.maps.plugin.PuckBearing
import com.mapbox.maps.plugin.locationcomponent.location
import com.mapbox.maps.plugin.viewport.data.FollowPuckViewportStateBearing
import com.mapbox.maps.plugin.viewport.data.FollowPuckViewportStateOptions
import com.mapbox.maps.plugin.viewport.state.FollowPuckViewportState
import com.mapbox.maps.plugin.viewport.transition.DefaultViewportTransition
import com.mapbox.maps.plugin.viewport.viewport
import java.util.concurrent.ConcurrentHashMap

/**
 * FLUXIDI NAV-STREETLEVEL-FLUID-MOTION-2 Phase 2A — orchestrator for the
 * native FollowPuck + custom LocationProvider pipeline.
 *
 * One [FluxidiNativeFollowManager] instance lives per FlutterEngine (owned
 * by [FluxidiNativeFollowPlugin]). It:
 *
 *   1. Subscribes to [MapboxMapViewRegistry] to observe every MapView the
 *      plugin creates or disposes.
 *   2. Holds one [Session] per registered map id, keyed by the plugin's
 *      own `channelSuffix` (the same `mapInstanceId` the Dart controller
 *      addresses).
 *   3. Fulfils the [NativeFollowHostApi] Pigeon contract on the Flutter
 *      platform thread. Every Mapbox side-effect happens synchronously in
 *      that thread — the manager never crosses to a background thread.
 *
 * Bounded diagnostics counters live on each session so a Dart client can
 * poll them via [readNativeFollowDiagnostics] to prove the acceptance
 * criteria (zero passive Dart writes while native follow is active, no
 * queue growth, bounded submission rate).
 *
 * Startup race: `setNativeFollowEnabled(mapId, true)` can arrive before
 * [MapboxMapViewRegistry] emits `onMapViewRegistered(mapId, view)` — the
 * pending intent is latched in [pendingEnable] and re-applied on the next
 * registration.
 */
class FluxidiNativeFollowManager : NativeFollowHostApi, MapboxMapViewRegistry.Listener {

  private val sessions = ConcurrentHashMap<String, Session>()
  private val pendingEnable = ConcurrentHashMap<String, Boolean>()
  private val pendingPreset = ConcurrentHashMap<String, NativeVehiclePreset>()
  private val pendingViewport = ConcurrentHashMap<String, NativeFollowViewport>()
  private val pendingOwner = ConcurrentHashMap<String, NativeFollowOwner>()

  fun attach() {
    MapboxMapViewRegistry.addListener(this)
  }

  fun detach() {
    MapboxMapViewRegistry.removeListener(this)
    sessions.values.forEach { it.teardown(NativeFollowProviderLifecycle.MAP_DISPOSED) }
    sessions.clear()
    pendingEnable.clear()
    pendingPreset.clear()
    pendingViewport.clear()
    pendingOwner.clear()
  }

  // -----------------------------------------------------------------------
  //   MapboxMapViewRegistry.Listener
  // -----------------------------------------------------------------------

  override fun onMapViewRegistered(mapInstanceId: String, mapView: MapView) {
    val session = sessions.getOrPut(mapInstanceId) { Session(mapInstanceId, mapView) }
    session.updateMapView(mapView)
    pendingEnable.remove(mapInstanceId)?.let { session.setEnabled(it) }
    pendingPreset.remove(mapInstanceId)?.let { session.setVehiclePreset(it) }
    pendingViewport.remove(mapInstanceId)?.let { session.setViewport(it) }
    pendingOwner.remove(mapInstanceId)?.let { session.setOwner(it) }
  }

  override fun onMapViewUnregistered(mapInstanceId: String) {
    sessions.remove(mapInstanceId)?.teardown(NativeFollowProviderLifecycle.MAP_DISPOSED)
  }

  // -----------------------------------------------------------------------
  //   NativeFollowHostApi
  // -----------------------------------------------------------------------

  override fun setNativeFollowEnabled(
    mapInstanceId: String,
    enabled: Boolean,
    callback: (Result<Boolean>) -> Unit,
  ) {
    val session = sessions[mapInstanceId]
    if (session == null) {
      pendingEnable[mapInstanceId] = enabled
      callback(Result.success(false))
      return
    }
    session.setEnabled(enabled)
    callback(Result.success(true))
  }

  override fun submitNavigationPose(
    pose: NativeFollowPose,
    callback: (Result<NativeFollowSubmitOutcome>) -> Unit,
  ) {
    val session = sessions[pose.mapInstanceId]
    if (session == null) {
      callback(Result.success(NativeFollowSubmitOutcome.REJECTED_UNKNOWN_MAP))
      return
    }
    callback(Result.success(session.submitPose(pose)))
  }

  override fun setNativeFollowViewport(
    viewport: NativeFollowViewport,
    callback: (Result<Boolean>) -> Unit,
  ) {
    val session = sessions[viewport.mapInstanceId]
    if (session == null) {
      pendingViewport[viewport.mapInstanceId] = viewport
      callback(Result.success(false))
      return
    }
    session.setViewport(viewport)
    callback(Result.success(true))
  }

  override fun setNativeVehiclePreset(
    preset: NativeVehiclePreset,
    callback: (Result<Boolean>) -> Unit,
  ) {
    val session = sessions[preset.mapInstanceId]
    if (session == null) {
      pendingPreset[preset.mapInstanceId] = preset
      callback(Result.success(false))
      return
    }
    session.setVehiclePreset(preset)
    callback(Result.success(true))
  }

  override fun setNativeFollowOwner(
    mapInstanceId: String,
    owner: NativeFollowOwner,
    callback: (Result<Boolean>) -> Unit,
  ) {
    val session = sessions[mapInstanceId]
    if (session == null) {
      pendingOwner[mapInstanceId] = owner
      callback(Result.success(false))
      return
    }
    session.setOwner(owner)
    callback(Result.success(true))
  }

  override fun transitionToFollowPuck(
    mapInstanceId: String,
    callback: (Result<Boolean>) -> Unit,
  ) {
    val session = sessions[mapInstanceId]
    if (session == null) {
      callback(Result.success(false))
      return
    }
    callback(Result.success(session.transitionToFollowPuck()))
  }

  override fun readNativeFollowDiagnostics(
    mapInstanceId: String,
    callback: (Result<NativeFollowDiagnostics?>) -> Unit,
  ) {
    val session = sessions[mapInstanceId]
    callback(Result.success(session?.snapshotDiagnostics()))
  }

  // -----------------------------------------------------------------------
  //   Per-map session
  // -----------------------------------------------------------------------

  private class Session(
    private val mapInstanceId: String,
    initialMapView: MapView,
  ) {
    private var mapView: MapView = initialMapView
    private var sessionEnabled: Boolean = false
    private var owner: NativeFollowOwner = NativeFollowOwner.DISABLED
    private var provider: FluxidiRouteSnappedLocationProvider? = null
    private var currentPreset: NativeVehiclePreset? = null
    private var currentViewport: NativeFollowViewport? = null
    private var currentRouteGeneration: Long = 0
    private var puckReady: Boolean = false
    private var awaitingFirstPoseAtInstall: Boolean = false

    // Bounded diagnostics counters (never grow queues; snapshot-only)
    private var acceptedPoseCount: Long = 0
    private var coalescedPoseCount: Long = 0
    private var rejectedPoseCount: Long = 0
    private var viewportTransitionCount: Long = 0
    private var providerInstallCount: Long = 0
    private var providerUninstallCount: Long = 0

    fun updateMapView(newMapView: MapView) {
      if (mapView === newMapView) return
      // MapView replaced (rare — typically a hot restart); tear down old
      // provider state so the new MapView starts clean.
      teardown(NativeFollowProviderLifecycle.MAP_DISPOSED)
      mapView = newMapView
    }

    fun setEnabled(newEnabled: Boolean) {
      if (sessionEnabled == newEnabled) return
      sessionEnabled = newEnabled
      if (newEnabled) {
        installProvider()
        owner = NativeFollowOwner.FOLLOW_PUCK
        currentPreset?.let { installVehiclePreset(it) }
        currentViewport?.let { applyViewportSize(it) }
        transitionToFollowPuck()
      } else {
        teardown(NativeFollowProviderLifecycle.UNINSTALLED)
        owner = NativeFollowOwner.DISABLED
      }
    }

    fun setVehiclePreset(preset: NativeVehiclePreset) {
      currentPreset = preset
      if (sessionEnabled) installVehiclePreset(preset)
    }

    fun setViewport(viewport: NativeFollowViewport) {
      currentViewport = viewport
      if (sessionEnabled && owner == NativeFollowOwner.FOLLOW_PUCK) {
        applyViewportSize(viewport)
        transitionToFollowPuck()
      }
    }

    fun setOwner(newOwner: NativeFollowOwner) {
      val previous = owner
      if (previous == newOwner) return
      owner = newOwner
      when (newOwner) {
        NativeFollowOwner.FOLLOW_PUCK -> {
          if (sessionEnabled) transitionToFollowPuck()
        }
        NativeFollowOwner.TEMPORARY -> {
          // Do not touch the viewport; Dart / user is driving explicitly.
        }
        NativeFollowOwner.DISABLED -> {
          teardown(NativeFollowProviderLifecycle.UNINSTALLED)
        }
      }
    }

    fun submitPose(pose: NativeFollowPose): NativeFollowSubmitOutcome {
      if (!sessionEnabled) {
        rejectedPoseCount += 1
        return NativeFollowSubmitOutcome.REJECTED_NOT_ENABLED
      }
      if (!isPoseValid(pose)) {
        rejectedPoseCount += 1
        return NativeFollowSubmitOutcome.REJECTED_INVALID_POSE
      }
      if (pose.routeGeneration < currentRouteGeneration) {
        rejectedPoseCount += 1
        return NativeFollowSubmitOutcome.REJECTED_STALE_GENERATION
      }
      if (pose.routeGeneration > currentRouteGeneration) {
        currentRouteGeneration = pose.routeGeneration
      }
      val activeProvider = provider ?: run {
        rejectedPoseCount += 1
        return NativeFollowSubmitOutcome.REJECTED_NOT_ENABLED
      }
      val delivered = activeProvider.submit(
        latitude = pose.latitude,
        longitude = pose.longitude,
        courseDegrees = pose.courseDegrees,
        horizontalAccuracyMeters = pose.horizontalAccuracyMeters,
      )
      return if (delivered) {
        acceptedPoseCount += 1
        if (awaitingFirstPoseAtInstall) {
          awaitingFirstPoseAtInstall = false
          puckReady = true
        }
        NativeFollowSubmitOutcome.ACCEPTED
      } else {
        // No consumer registered yet — the provider latched the pose so the
        // next consumer registration replays it. Report as coalesced so the
        // Dart controller counters stay meaningful.
        coalescedPoseCount += 1
        NativeFollowSubmitOutcome.COALESCED
      }
    }

    fun transitionToFollowPuck(): Boolean {
      if (!sessionEnabled) return false
      val view = mapView
      val options = buildFollowPuckOptions(currentViewport)
      return try {
        val state: FollowPuckViewportState =
          view.viewport.makeFollowPuckViewportState(options)
        val transition: DefaultViewportTransition =
          view.viewport.makeDefaultViewportTransition()
        view.viewport.transitionTo(state, transition) { _ -> }
        viewportTransitionCount += 1
        owner = NativeFollowOwner.FOLLOW_PUCK
        true
      } catch (t: Throwable) {
        Log.w(TAG, "transitionToFollowPuck failed on $mapInstanceId", t)
        false
      }
    }

    fun snapshotDiagnostics(): NativeFollowDiagnostics {
      return NativeFollowDiagnostics(
        mapInstanceId = mapInstanceId,
        owner = owner,
        acceptedPoseCount = acceptedPoseCount,
        coalescedPoseCount = coalescedPoseCount,
        rejectedPoseCount = rejectedPoseCount,
        viewportTransitionCount = viewportTransitionCount,
        providerInstallCount = providerInstallCount,
        providerUninstallCount = providerUninstallCount,
        currentRouteGeneration = currentRouteGeneration,
        puckReady = puckReady,
      )
    }

    fun teardown(lifecycle: NativeFollowProviderLifecycle) {
      val currentProvider = provider ?: return
      currentProvider.teardown()
      try {
        // Restore the default provider (mapbox_maps_flutter's stock behavior
        // is to fall back to the SDK's DefaultLocationProvider whenever a
        // custom one is unset). Calling setLocationProvider(null) is not
        // supported; instead we recreate the default by not calling
        // setLocationProvider at all after teardown. The location component
        // will simply stop receiving custom updates.
        mapView.location.updateSettings {
          enabled = false
        }
      } catch (t: Throwable) {
        Log.w(TAG, "teardown updateSettings failed", t)
      }
      provider = null
      providerUninstallCount += 1
      puckReady = false
      awaitingFirstPoseAtInstall = false
      if (lifecycle == NativeFollowProviderLifecycle.MAP_DISPOSED) {
        sessionEnabled = false
      }
    }

    // -------------------------------------------------------------------
    //   Internal helpers
    // -------------------------------------------------------------------

    private fun installProvider() {
      if (provider != null) return
      val newProvider = FluxidiRouteSnappedLocationProvider()
      try {
        mapView.location.setLocationProvider(newProvider)
        mapView.location.updateSettings {
          enabled = true
          puckBearingEnabled = true
          puckBearing = PuckBearing.COURSE
        }
      } catch (t: Throwable) {
        Log.w(TAG, "installProvider failed on $mapInstanceId", t)
        return
      }
      provider = newProvider
      providerInstallCount += 1
      awaitingFirstPoseAtInstall = true
    }

    private fun installVehiclePreset(preset: NativeVehiclePreset) {
      if (!sessionEnabled) return
      try {
        val scale = preset.modelScale.toFloat()
        val yaw = preset.yawOffsetDegrees.toFloat()
        val puck = LocationPuck3D(preset.assetUri).apply {
          modelScale = listOf(scale, scale, scale)
          modelRotation = listOf(0f, 0f, yaw)
        }
        mapView.location.updateSettings {
          locationPuck = puck
        }
      } catch (t: Throwable) {
        Log.w(TAG, "installVehiclePreset failed on $mapInstanceId", t)
      }
    }

    private fun applyViewportSize(viewport: NativeFollowViewport) {
      // Zoom + pitch are applied when we build FollowPuckViewportStateOptions
      // in transitionToFollowPuck(); padding likewise. No standalone camera
      // write is issued here.
    }

    private fun buildFollowPuckOptions(
      viewport: NativeFollowViewport?,
    ): FollowPuckViewportStateOptions {
      val builder = FollowPuckViewportStateOptions.Builder()
        .bearing(FollowPuckViewportStateBearing.SyncWithLocationPuck)
      if (viewport != null) {
        builder.zoom(viewport.zoom)
        builder.pitch(viewport.pitch)
      } else {
        builder.zoom(FALLBACK_ZOOM)
        builder.pitch(FALLBACK_PITCH)
      }
      return builder.build()
    }

    private fun isPoseValid(pose: NativeFollowPose): Boolean {
      if (pose.latitude.isNaN() || pose.longitude.isNaN()) return false
      if (pose.latitude !in -90.0..90.0) return false
      if (pose.longitude !in -180.0..180.0) return false
      if (pose.courseDegrees.isNaN() || !pose.courseDegrees.isFinite()) return false
      if (pose.horizontalAccuracyMeters.isNaN()) return false
      if (pose.horizontalAccuracyMeters < 0.0) return false
      if (pose.timestampMillis <= 0) return false
      return true
    }
  }

  companion object {
    private const val TAG = "FluxidiNativeFollow"
    private const val FALLBACK_ZOOM: Double = 17.5
    private const val FALLBACK_PITCH: Double = 60.0
  }
}
