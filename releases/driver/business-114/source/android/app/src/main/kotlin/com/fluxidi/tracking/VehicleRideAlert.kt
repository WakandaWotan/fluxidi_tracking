package com.fluxidi.tracking

import android.content.Context
import android.Manifest
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.app.NotificationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Foreground alerts use Android's ride channel, including its sound/DND settings. */
class VehicleRideAlert(private val context: Context, messenger: BinaryMessenger,
  private val isForeground: () -> Boolean) {
  private val channel = MethodChannel(messenger, "fluxidi/vehicle_ride_alert")
  private val handler = Handler(Looper.getMainLooper())
  private var torchId: String? = null
  private var alertKey: List<String>? = null
  private var resumeAttention = true
  private val torchTasks = mutableListOf<Runnable>()

  private fun torchAvailable() = Build.VERSION.SDK_INT >= 23 &&
    context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_FLASH)

  private fun flashBriefly() {
    if (!torchAvailable() || !isForeground() ||
      context.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) return
    val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    if (notifications.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL) return
    try {
      val cameras = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
      val id = cameras.cameraIdList.firstOrNull { cameras.getCameraCharacteristics(it)
        .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true } ?: return
      torchId = id
      // Two slow, brief pulses; no strobe, repetition or background service.
      for ((delay, enabled) in listOf(0L to true, 150L to false, 1200L to true, 1350L to false)) {
        val task = Runnable {
          if (torchId == id && (!enabled || isForeground())) {
            try {
              cameras.setTorchMode(id, enabled)
              if (delay == 1350L) { torchId = null; torchTasks.clear() }
            } catch (_: Exception) { stopTorch() }
          }
        }
        torchTasks.add(task); handler.postDelayed(task, delay)
      }
    } catch (_: Exception) { stopTorch() }
  }

  private fun stopTorch() {
    for (task in torchTasks) handler.removeCallbacks(task)
    torchTasks.clear()
    val id = torchId; torchId = null
    if (id != null && Build.VERSION.SDK_INT >= 23) {
      try { (context.getSystemService(Context.CAMERA_SERVICE) as CameraManager).setTorchMode(id, false) }
      catch (_: Exception) { /* Camera taken by another app/hardware unavailable. */ }
    }
  }

  init {
    channel.setMethodCallHandler { call, result ->
      when (call.method) {
        "play", "sync" -> {
          try {
            if (!isForeground()) {
              handoff()
              result.success(null)
              return@setMethodCallHandler
            }
            val keys = listOf("tenant_id", "company_id", "driver_id", "vehicle_id", "offer_id")
              .map { call.argument<String>(it) ?: "" }
            val version = call.argument<Number>("version")?.toLong() ?: 0
            val deadline = call.argument<Number>("deadline_ms")?.toLong() ?: 0
            val key = keys + version.toString()
            if (version < 1 || keys.any { it.isBlank() } || deadline <= System.currentTimeMillis()) {
              stop(); result.success(null); return@setMethodCallHandler
            }
            if (alertKey != null && alertKey != key) stop()
            val admission = DriverRideNotifications.foreground(context, key, deadline, resumeAttention || alertKey == null)
            if (admission != null) {
              alertKey = key
              resumeAttention = false
              if (admission.first && call.argument<Boolean>("flashlight") == true) flashBriefly()
            }
            result.success(null)
          } catch (_: Exception) { stop(); result.error("alert_unavailable", "Ride alert unavailable", null) }
        }
        "stop" -> { stop(); result.success(null) }
        "stopOffer" -> {
          val key = listOf("tenant_id", "company_id", "driver_id", "vehicle_id", "offer_id")
            .map { call.argument<String>(it) ?: "" } + (call.argument<Number>("version")?.toLong() ?: 0).toString()
          if (key.all { it.isNotBlank() } && key.last() != "0") {
            DriverRideNotifications.stopAttention(context, key)
            if (alertKey == key) { alertKey = null; stopTorch() }
          }
          result.success(null)
        }
        "handoff" -> { handoff(); result.success(null) }
        "torchAvailable" -> result.success(torchAvailable())
        "backgroundReady" -> result.success(DriverDutyService.notificationReady(call.argument<String>("token") ?: ""))
        "refreshOffers" -> result.success(DriverDutyService.refreshOffers(call.argument<String>("token") ?: ""))
        "presented" -> { result.success(null) } // Display is not a confirmed decision; keep its alarm.
        "takeInboxRequest" -> {
          val intent = (context as? android.app.Activity)?.intent
          val requested = intent?.getBooleanExtra("fluxidi_open_driver_offers", false) == true
          if (requested) intent?.removeExtra("fluxidi_open_driver_offers")
          result.success(requested)
        }
        else -> result.notImplemented()
      }
    }
  }
  fun handoff() {
    stopTorch()
    val key = alertKey
    if (key != null && !DriverDutyService.retainsOfferAttention(key)) stop()
    else resumeAttention = true
  }
  fun stop() {
    stopTorch()
    val key = alertKey; alertKey = null
    if (key != null) DriverRideNotifications.stopAttention(context, key)
    DriverRideNotifications.channel(context).cancel(DriverRideNotifications.FOREGROUND_ID)
  }
  fun dispose() { handoff(); channel.setMethodCallHandler(null) }
}
