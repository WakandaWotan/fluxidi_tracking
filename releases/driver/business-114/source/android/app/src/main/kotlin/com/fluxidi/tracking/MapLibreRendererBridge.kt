package com.fluxidi.tracking

import android.app.Activity
import android.view.View
import android.view.ViewGroup
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.maps.MapView

/** Native renderer primitives only. No GPS, pose, follow, heading or timers. */
class MapLibreRendererBridge(private val activity: Activity, messenger: BinaryMessenger) {
  init {
    MethodChannel(messenger, "fluxidi/maplibre_renderer").setMethodCallHandler { call, result ->
      val views = mutableListOf<MapView>()
      fun collect(view: View) {
        if (view is MapView) views.add(view)
        if (view is ViewGroup) for (i in 0 until view.childCount) collect(view.getChildAt(i))
      }
      collect(activity.window.decorView)
      // Fail closed rather than sending a camera operation to another map.
      if (views.size != 1) {
        result.error("map_instance_ambiguous", "Expected one own MapLibre surface", null)
        return@setMethodCallHandler
      }
      val density = activity.resources.displayMetrics.density.toDouble()
      views.single().getMapAsync { map ->
        try {
          when (call.method) {
            "setPitchCapability" -> {
              map.setMaxPitchPreference((call.argument<Number>("maxPitch")!!).toDouble())
              result.success(map.maxPitch)
            }
            "cameraForBounds" -> {
              val bounds = LatLngBounds.from(
                call.argument<Number>("north")!!.toDouble(),
                call.argument<Number>("east")!!.toDouble(),
                call.argument<Number>("south")!!.toDouble(),
                call.argument<Number>("west")!!.toDouble())
              val padding = arrayOf("left", "top", "right", "bottom")
                .map { (call.argument<Number>(it)!!.toDouble() * density).toInt() }.toIntArray()
              val camera = map.getCameraForLatLngBounds(bounds, padding,
                call.argument<Number>("bearing")?.toDouble() ?: 0.0,
                call.argument<Number>("pitch")?.toDouble() ?: 0.0)
                ?: throw IllegalStateException("SDK bounds calculation unavailable")
              val target = camera.target ?: throw IllegalStateException("SDK target unavailable")
              val maxZoom = call.argument<Number>("maxZoom")?.toDouble()
              result.success(mapOf("latitude" to target.latitude, "longitude" to target.longitude,
                "zoom" to if (maxZoom == null) camera.zoom else minOf(camera.zoom, maxZoom),
                "bearing" to camera.bearing, "pitch" to camera.tilt))
            }
            else -> result.notImplemented()
          }
        } catch (failure: Exception) {
          result.error("renderer_primitive_failed", failure.javaClass.simpleName, null)
        }
      }
    }
  }
}
