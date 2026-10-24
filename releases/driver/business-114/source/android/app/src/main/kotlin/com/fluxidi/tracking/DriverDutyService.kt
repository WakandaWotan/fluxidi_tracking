package com.fluxidi.tracking

import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.location.*
import android.os.*
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import java.util.UUID

/** Driver's explicit availability task. No Flutter engine, booking polling or GPS history. */
class DriverDutyService : Service() {
  companion object {
    private val lifecycle = DriverDutyLifecycle()
    // Independent of Service.worker: stopping the publisher must not cancel its
    // bounded, immutable retirement request. Nothing is persisted to disk.
    private val retirementWorker = Executors.newSingleThreadScheduledExecutor()
    private val withdrawals = DriverDutyWithdrawal(
      { SystemClock.elapsedRealtime() },
      { delay, job -> retirementWorker.schedule({ job() }, delay, TimeUnit.MILLISECONDS); Unit },
      { lease -> sendWithdrawal(lease) },
    )
    @Volatile private var instance: DriverDutyService? = null
    val running: Boolean get() = lifecycle.status().running
    internal fun notificationReady(token: String): Boolean {
      val service = instance ?: return false
      val lease = lifecycle.current() ?: return false
      return lease.token == token && DriverRideNotifications.allowed(service)
    }
    internal fun refreshOffers(token: String): Boolean {
      val service = instance ?: return false
      val lease = lifecycle.current() ?: return false
      if (!notificationReady(token)) return false
      try { service.worker.execute { if (lifecycle.isCurrent(lease)) service.tick() } }
      catch (_: java.util.concurrent.RejectedExecutionException) { return false }
      return true
    }
    internal fun retainsOfferAttention(key: List<String>): Boolean {
      val service = instance ?: return false
      val lease = lifecycle.current() ?: return false
      return key.size == 6 && key.take(4) == listOf(lease.actor.tenantId, lease.actor.companyId,
        lease.actor.driverId, lease.actor.vehicleId) && DriverRideNotifications.allowed(service)
    }
    internal fun clearOffer(id: String) { instance?.rideNotifications?.clearOffer(id) }

    internal fun ensureNativeDeviceId(context: Context): String {
      val prefs = context.getSharedPreferences("driver_duty", Context.MODE_PRIVATE)
      return prefs.getString("duty_device_id", null)?.takeIf { validOwnerLabel(it) }
        ?: UUID.randomUUID().toString().also { prefs.edit().putString("duty_device_id", it).apply() }
    }

    private fun validOwnerLabel(value: String): Boolean = value.matches(Regex("[A-Za-z0-9_-]{1,128}"))
    private fun secure(value: String): Boolean = try {
      val u = URL(value); u.protocol == "https" && u.userInfo == null && u.query == null && u.ref == null
    } catch (_: Exception) { false }

    internal fun prepareStart(activationId: String?, token: String, booking: String, tracking: String, nativeDeviceId: String,
      actor: DriverDutyActor, title: String, text: String): DriverDutyLease {
      val id = activationId?.takeIf { validOwnerLabel(it) } ?: "legacy-${UUID.randomUUID()}"
      val previous = lifecycle.current(false)
      val lease = lifecycle.begin(id, token, booking, tracking, nativeDeviceId, actor, title, text)
      instance?.resetSubscriptions()
      previous?.let { withdrawals.retire(it) }
      return lease
    }

    private fun sendWithdrawal(lease: DriverDutyLease): DriverDutyWithdrawalResult {
      if (!secure(lease.tracking) || !validOwnerLabel(lease.activationId)) return DriverDutyWithdrawalResult(400)
      val connection = URL(lease.tracking.trimEnd('/') + "/track/driver/location/withdraw").openConnection() as HttpURLConnection
      try {
        connection.requestMethod = "POST"; connection.connectTimeout = 5000; connection.readTimeout = 5000
        connection.instanceFollowRedirects = false; connection.doOutput = true
        connection.setRequestProperty("Authorization", "Bearer ${lease.token}")
        connection.setRequestProperty("Content-Type", "application/json")
        val body = JSONObject().put("activation_id", lease.activationId)
        if (lease.nativeDeviceId.isNotEmpty()) body.put("native_device_id", lease.nativeDeviceId)
        connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
        val code = connection.responseCode
        val stream = if (code in 200..299) connection.inputStream else connection.errorStream
        val raw = stream?.bufferedReader()?.use { reader ->
          val chars = CharArray(16384); val count = reader.read(chars)
          if (count > 0) String(chars, 0, count) else "{}"
        } ?: "{}"
        val retry = if (code == 429) try { JSONObject(raw).optLong("retry_after_seconds", 0) } catch (_: Exception) { 0 } else 0
        return DriverDutyWithdrawalResult(code, maxOf(retry, connection.getHeaderField("Retry-After")?.toLongOrNull() ?: 0))
      } finally { connection.disconnect() }
    }

    internal fun status(activationId: String? = null, expected: DriverDutyExpectedConfig? = null): DriverDutyStatus = lifecycle.status(activationId, expected)
    internal fun isReady(lease: DriverDutyLease): Boolean = lifecycle.isCurrent(lease)

    // Read-only, debug-app only, in-memory and cleared on owner/service changes.
    internal fun gpsSampleEvidence(): List<Map<String, Any?>> = instance?.readSampleEvidence() ?: emptyList()

    internal fun failedStart(context: Context, lease: DriverDutyLease, reason: String) {
      if (lifecycle.finish(lease, reason, true)) {
        instance?.resetSubscriptions()
        withdrawals.retire(lease)
        context.stopService(Intent(context, DriverDutyService::class.java))
      }
    }

    internal fun stopOwned(context: Context, activationId: String?): Boolean {
      val stopped = lifecycle.cancel(activationId, "requested_stop")
      if (stopped == null && !activationId.isNullOrEmpty()) return false
      instance?.resetSubscriptions()
      stopped?.let { withdrawals.retire(it) }
      context.stopService(Intent(context, DriverDutyService::class.java))
      return true
    }
  }
  private val worker = Executors.newSingleThreadScheduledExecutor()
  private val rideNotifications by lazy { DriverRideNotifications(this) }
  private class OwnedLocation(val lease: DriverDutyLease, val location: Location)
  private var sampleSelector = DriverDutySampleSelector<Location>()
  private val sampleEvidence = ArrayDeque<Map<String, Any?>>()
  private var lastUploadAttempt: OwnedLocation? = null
  private var cadence = DriverDutyCadence()
  private val deferredUpload = DriverDutyDeferredUpload<DriverDutyLease>(
    isCurrent = { lifecycle.isCurrent(it) },
    scheduleTask = { delay, task ->
      val future = worker.schedule(Runnable { task() }, delay, TimeUnit.MILLISECONDS)
      val cancel: () -> Unit = { future.cancel(false); Unit }
      cancel
    },
    attempt = { uploadLocation(it) },
  )
  private val uploadQueued = AtomicLong(0)
  private val connections = ConcurrentHashMap<HttpURLConnection, DriverDutyLease>()
  @Volatile private var applied: DriverDutyLease? = null
  private var listener: LocationListener? = null
  private var failures = 0
  private var wake: PowerManager.WakeLock? = null
  private val manager by lazy { getSystemService(LOCATION_SERVICE) as LocationManager }
  override fun onBind(intent: Intent?) = null
  override fun onCreate() {
    super.onCreate()
    instance = this
    val notifications = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
    if(Build.VERSION.SDK_INT >= 26) notifications.createNotificationChannel(NotificationChannel("driver_duty", "Fluxidi", NotificationManager.IMPORTANCE_LOW))
    worker.scheduleWithFixedDelay({ tick() }, 0, 90, TimeUnit.SECONDS)
  }
  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    if(intent == null) { stopSelf(); return START_NOT_STICKY }
    @Suppress("DEPRECATION") val receiver = intent.getParcelableExtra<ResultReceiver>("ready_receiver")
    val lease = lifecycle.acceptCommand(
      intent.getStringExtra("activation_id") ?: "legacy-${UUID.randomUUID()}",
      intent.getLongExtra("generation", -1), intent.getStringExtra("token") ?: "",
      intent.getStringExtra("booking") ?: "", intent.getStringExtra("tracking") ?: "",
      intent.getStringExtra("native_device_id") ?: ensureNativeDeviceId(this),
      DriverDutyActor(intent.getStringExtra("tenant_id") ?: "", intent.getStringExtra("company_id") ?: "",
        intent.getStringExtra("driver_id") ?: "", intent.getStringExtra("vehicle_id") ?: ""),
      intent.getStringExtra("title") ?: "Fluxidi", intent.getStringExtra("text") ?: "",
    )
    if (lease == null) {
      receiver?.send(0, null)
      if (lifecycle.current(false) == null) stopSelf(startId)
      return START_NOT_STICKY
    }
    resetSubscriptions()
    applied = lease
    fun fail(reason: String): Int {
      if (lifecycle.finish(lease, reason, true)) withdrawals.retire(lease)
      resetSubscriptions()
      receiver?.send(0, null)
      stopSelf(startId)
      return START_NOT_STICKY
    }
    if(lease.token.isEmpty() || !secure(lease.booking) || !secure(lease.tracking)) return fail("invalid_configuration")
    val launch = packageManager.getLaunchIntentForPackage(packageName)
    val pending = launch?.let { PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT) }
    val builder = if(Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "driver_duty") else Notification.Builder(this)
    val notification = builder
      .setSmallIcon(applicationInfo.icon)
      .setContentTitle(lease.title)
      .setContentText(lease.text)
      .setContentIntent(pending).setOngoing(true).build()
    try {
      startForeground(754, notification)
      if(checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
        return fail("location_permission_missing")
      }
      val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
        .filter { manager.isProviderEnabled(it) }
      if (providers.isEmpty()) return fail("location_disabled")
      val ownedListener = object : LocationListener {
        override fun onLocationChanged(location: Location) = acceptLocation(lease, location)
      }
      listener = ownedListener
      var subscribed = 0
      for (provider in providers) {
        try {
          manager.requestLocationUpdates(provider, 25000L, 0f, ownedListener, Looper.getMainLooper())
          subscribed++
        } catch (_: Exception) { /* Another enabled provider may still work. */ }
      }
      if (subscribed == 0) return fail("location_subscribe_failed")
      wake = (getSystemService(POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Fluxidi:DriverDuty").apply { acquire(12 * 60 * 60 * 1000L) }
      if (!lifecycle.ready(lease)) return fail("activation_not_current")
      receiver?.send(1, null)
      // The periodic task may have run before onStartCommand. Do not leave
      // the first authenticated heartbeat waiting for the next 90s interval.
      worker.execute { tick() }
    } catch(_: Exception) { return fail("start_failed") }
    return START_REDELIVER_INTENT
  }
  @Synchronized private fun acceptLocation(lease: DriverDutyLease, location: Location) {
    if (!lifecycle.isCurrent(lease)) return
    val wall = System.currentTimeMillis()
    val elapsed = SystemClock.elapsedRealtimeNanos()
    val copied = Location(location)
    val incoming = DriverDutyLocationSample(copied, copied.latitude, copied.longitude,
      copied.time, copied.elapsedRealtimeNanos, if (copied.hasAccuracy()) copied.accuracy else Float.NaN,
      copied.provider ?: "unknown", wall)
    val decision = sampleSelector.offer(incoming, wall, elapsed)
    recordSampleEvidence("callback", wall, elapsed, incoming, decision.before, decision.selected, decision.reason)
    if (!decision.accepted) return
    if (decision.before?.elapsedRealtimeNanos != decision.selected?.elapsedRealtimeNanos) deferredUpload.cancelPending(lease)
    if(!uploadQueued.compareAndSet(0, lease.generation)) return
    try {
      worker.execute {
        try { uploadLocation(lease, deferNewFix = true) } finally {
          synchronized(this@DriverDutyService) {
            // A callback can arrive after uploadLocation's final check. Release
            // its queue claim and retain that new sample under the same lock.
            if (uploadQueued.compareAndSet(lease.generation, 0)) deferNewerRealFix(lease, cadence)
          }
        }
      }
    } catch (_: java.util.concurrent.RejectedExecutionException) { uploadQueued.compareAndSet(lease.generation, 0) }
  }
  private class DutyCancelled : Exception()
  private fun post(lease: DriverDutyLease, base: String, path: String, body: JSONObject): Pair<Int, JSONObject> {
    if (!lifecycle.isCurrent(lease)) throw DutyCancelled()
    val connection=URL(base.trimEnd('/')+path).openConnection() as HttpURLConnection
    connections[connection] = lease
    try {
      if (!lifecycle.isCurrent(lease)) throw DutyCancelled()
      connection.requestMethod="POST"; connection.connectTimeout=8000; connection.readTimeout=8000
      connection.instanceFollowRedirects=false; connection.doOutput=true
      connection.setRequestProperty("Authorization", "Bearer ${lease.token}")
      connection.setRequestProperty("Content-Type", "application/json")
      if (!lifecycle.isCurrent(lease)) throw DutyCancelled()
      connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
      val code=connection.responseCode
      val stream=if(code in 200..299) connection.inputStream else connection.errorStream
      val raw=stream?.bufferedReader()?.use { it.readText().take(16384) } ?: "{}"
      return code to try { JSONObject(raw) } catch(_:Exception){ JSONObject() }
    } finally { connections.remove(connection); connection.disconnect() }
  }
  private fun tick() {
    val lease = lifecycle.current() ?: return
    try {
      val capability = JSONObject()
      if (DriverRideNotifications.allowed(this)) capability.put("dispatch_protocol", 1)
      val (code,result)=post(lease, lease.booking, "/public/driver/heartbeat", capability)
      if(!lifecycle.isCurrent(lease))return
      val stopReason = DriverDutyHeartbeatPolicy.terminationReason(code, result.optBoolean("is_active",true), result.optString("availability_status"))
      if(stopReason != null) {
        terminate(lease, stopReason); return
      }
      if(code in 200..299) failures=0 else failures++
      // Fresh cached fix also keeps stationary drivers in the realtime room.
      if(failures==0) {
        uploadLocation(lease)
        val offers = result.optJSONArray("dispatch_offers")
        if(result.optInt("dispatch_protocol") == 1 && offers != null) {
          for (index in 0 until minOf(offers.length(), 8)) {
            if (!lifecycle.isCurrent(lease)) return
            val row = offers.optJSONObject(index) ?: continue
            val values = row.keys().asSequence().associateWith { key -> row.opt(key).takeUnless { it == JSONObject.NULL } }
            DriverRideNotificationOffer.read(values, lease.actor, System.currentTimeMillis())?.let { offer ->
              rideNotifications.present(lease, offer) { lifecycle.isCurrent(lease) }
            }
          }
          val receipts = (0 until minOf(offers.length(), 8)).mapNotNull { index ->
            offers.optJSONObject(index)?.let { offer -> DriverHeartbeatOfferReceipt(
              offer.optString("offer_id"), offer.optInt("version"),
              offer.optBoolean("human_acceptance_required", false)) }
          }
          acknowledgeHeartbeatOffers(receipts, { lifecycle.isCurrent(lease) }, { id, version ->
            post(lease, lease.booking, "/public/driver/dispatch/ack",
              JSONObject().put("offer_id", id).put("version", version)).first
          }, { terminate(lease, "session_revoked") })
        }
      }
    } catch(_:Exception){ if(lifecycle.isCurrent(lease)) failures++ }
  }
  @Synchronized private fun deferNewerRealFix(lease: DriverDutyLease, policy: DriverDutyCadence) {
    if (!lifecycle.isCurrent(lease) || cadence !== policy) return
    val attempted = lastUploadAttempt?.takeIf { it.lease === lease }
    val delay = sampleSelector.pendingSelectionDelayMs(attempted?.location?.elapsedRealtimeNanos,
      System.currentTimeMillis(), SystemClock.elapsedRealtimeNanos()) ?: return
    deferredUpload.defer(lease, maxOf(delay, policy.remainingDelayMs(SystemClock.elapsedRealtime())))
  }
  private fun uploadLocation(lease: DriverDutyLease, deferNewFix: Boolean = false) {
    if (!lifecycle.isCurrent(lease)) return
    val (sample, policy) = synchronized(this) {
      if (!lifecycle.isCurrent(lease)) return
      sampleSelector.selected(System.currentTimeMillis(), SystemClock.elapsedRealtimeNanos())?.let { it to cadence }
    } ?: return
    val location = Location(sample.value)
    val age=SystemClock.elapsedRealtimeNanos()-location.elapsedRealtimeNanos
    if(age<0 || age>150000000000L)return
    val waitingForBetterExpiry = synchronized(this) {
      val attempted = lastUploadAttempt?.takeIf { it.lease === lease }
      if (attempted != null && sample.elapsedRealtimeNanos <= attempted.location.elapsedRealtimeNanos)
        sampleSelector.pendingSelectionDelayMs(attempted.location.elapsedRealtimeNanos,
          System.currentTimeMillis(), SystemClock.elapsedRealtimeNanos()) else null
    }
    if (waitingForBetterExpiry != null && waitingForBetterExpiry > 0) {
      // Do not consume a cadence slot re-sending an unchanged precise fix while
      // a real newer fallback waits for its expiry. The same timer handles it.
      deferNewerRealFix(lease, policy)
      return
    }
    val uploadStartedAt = SystemClock.elapsedRealtime()
    if (!policy.due(uploadStartedAt)) {
      if (deferNewFix) deferNewerRealFix(lease, policy)
      return
    }
    synchronized(this) {
      if (!lifecycle.isCurrent(lease) || cadence !== policy) return
      deferredUpload.cancelPending(lease)
      lastUploadAttempt = OwnedLocation(lease, Location(location))
      val wall = System.currentTimeMillis()
      recordSampleEvidence("send", wall, SystemClock.elapsedRealtimeNanos(), null, sample, sample, "chosen_state")
    }
    try {
      val (code,result)=post(lease, lease.tracking,"/track/driver/location",JSONObject()
        .put("activation_id", lease.activationId).put("native_device_id", lease.nativeDeviceId)
        .put("lat",location.latitude).put("lon",location.longitude).put("accuracy_m",location.accuracy)
        .put("speed",if(location.hasSpeed())location.speed else 0).put("heading",if(location.hasBearing())location.bearing else 0)
        .put("captured_at",SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",Locale.US).apply { timeZone=TimeZone.getTimeZone("UTC") }.format(Date(location.time))))
      if(!lifecycle.isCurrent(lease))return
      val ended = DriverDutyLocationPolicy.terminationReason(code, result.optString("error"), result.optBoolean("cleared"), result.optString("reason"))
      if (ended != null) { terminate(lease, ended); return }
      synchronized(this) {
        if (lifecycle.isCurrent(lease) && cadence === policy) policy.completed(SystemClock.elapsedRealtime(),location.speed,if(code==429)result.optLong("retry_after_seconds",120) else if(code>=500)120 else 0,uploadStartedAt)
      }
    } catch(_:Exception) {
      synchronized(this) {
        if (lifecycle.isCurrent(lease) && cadence === policy) policy.completed(SystemClock.elapsedRealtime(),0f,120)
      }
    } finally {
      // A real callback received during a request remains newest; a heartbeat
      // or replayed cached sample alone never creates another deferred attempt.
      deferNewerRealFix(lease, policy)
    }
  }
  private fun terminate(lease: DriverDutyLease, reason: String) {
    if (!lifecycle.finish(lease, reason)) return
    withdrawals.retire(lease)
    for (connection in connections.keys) connection.disconnect()
    Handler(Looper.getMainLooper()).post {
      if (applied === lease) { resetSubscriptions(); stopSelf() }
    }
  }
  private fun debugSampleEvidenceEnabled(): Boolean =
    (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0

  @Synchronized private fun recordSampleEvidence(event: String, wall: Long, elapsed: Long,
    incoming: DriverDutyLocationSample<Location>?, before: DriverDutyLocationSample<Location>?,
    after: DriverDutyLocationSample<Location>?, reason: String) {
    if (!debugSampleEvidenceEnabled()) return
    pruneSampleEvidence(elapsed / 1_000_000L)
    fun fields(sample: DriverDutyLocationSample<Location>?): Map<String, Any?>? = sample?.let {
      mapOf("captured_at_ms" to it.capturedAtMillis, "received_at_ms" to it.receivedAtMillis,
        "lat" to it.latitude, "lng" to it.longitude, "accuracy_m" to it.accuracyMeters,
        "source" to it.source, "delivery_kind" to it.deliveryKind,
        "age_ms" to it.ageMillis(wall, elapsed), "confidence" to it.quality(wall, elapsed))
    }
    while (sampleEvidence.size >= 16) sampleEvidence.removeFirst()
    val process = ActivityManager.RunningAppProcessInfo()
    ActivityManager.getMyMemoryState(process)
    sampleEvidence.addLast(mapOf("observed_at_ms" to wall, "observed_elapsed_ms" to elapsed / 1_000_000L, "event" to event,
      "execution" to "location_foreground_service", "reason" to reason,
      "host_app_state" to if (process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) "foreground" else "background_or_not_top",
      "incoming" to fields(incoming), "selected_before" to fields(before), "selected_after" to fields(after)))
  }

  @Synchronized private fun readSampleEvidence(): List<Map<String, Any?>> {
    if (!debugSampleEvidenceEnabled()) return emptyList()
    pruneSampleEvidence(SystemClock.elapsedRealtime())
    return sampleEvidence.toList()
  }
  private fun pruneSampleEvidence(nowElapsedMillis: Long) {
    val cutoff = nowElapsedMillis - 120_000L
    while (sampleEvidence.isNotEmpty() && (sampleEvidence.first()["observed_elapsed_ms"] as Long) < cutoff)
      sampleEvidence.removeFirst()
  }
  override fun onTaskRemoved(rootIntent: Intent?) {
    // Explicitly dismissing the app ends this task's live dispatch publisher.
    // Keep stopWithTask=false so Android calls us and the exact-owner retirement
    // can run. Ordinary backgrounding, screen-off and external navigation do
    // not call this hook. Never end a booking or replace another actor's lease.
    val lease = applied ?: lifecycle.current(false)
    if (lease != null && lifecycle.finish(lease, "task_removed")) {
      resetSubscriptions()
      withdrawals.retire(lease)
      stopForeground(STOP_FOREGROUND_REMOVE)
      stopSelf()
    }
    super.onTaskRemoved(rootIntent)
  }
  @Synchronized private fun resetSubscriptions() {
    applied?.let { DriverRideNotifications.stopActor(this, it.actor) }
    rideNotifications.clear()
    deferredUpload.cancelPending()
    listener?.let { try { manager.removeUpdates(it) } catch(_:Exception){} }
    listener = null
    applied = null
    sampleSelector = DriverDutySampleSelector()
    sampleEvidence.clear()
    lastUploadAttempt = null
    cadence = DriverDutyCadence()
    failures = 0
    uploadQueued.set(0)
    for (connection in connections.keys) connection.disconnect()
    wake?.let { if(it.isHeld)it.release() }; wake=null
  }
  override fun onDestroy() {
    applied?.let { if (lifecycle.finish(it, "service_stopped")) withdrawals.retire(it) }
    resetSubscriptions()
    if (instance === this) instance = null
    worker.shutdownNow()
    stopForeground(STOP_FOREGROUND_REMOVE)
    super.onDestroy()
  }
}
