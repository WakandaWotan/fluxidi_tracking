package com.fluxidi.tracking

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper

/** Attention dedupe only; never grants a booking or changes delivery receipts. */
internal class DriverRideAlertClaimCache {
  private val claims = linkedMapOf<List<String>, Long>()
  @Synchronized fun take(key: List<String>, deadlineMs: Long, nowMs: Long): Boolean {
    claims.entries.removeAll { it.value <= nowMs }
    if (key.size != 6 || key.any { it.isBlank() } || deadlineMs <= nowMs ||
      claims.containsKey(key) || claims.size >= 64) return false
    // Dedupe history only, never permission to display an expired proposal.
    // UI receipt can legitimately replace a short initial display deadline.
    claims[key.toList()] = maxOf(deadlineMs, nowMs + 300000)
    return true
  }
  @Synchronized fun releaseUnposted(key: List<String>) { claims.remove(key) }
}

internal data class DriverRideNotificationOffer(
  val id: String, val version: Int, val deadlineMs: Long,
  val pickup: String, val destination: String, val pickupIso: String?,
  val price: Double?,
) {
  companion object {
    fun read(row: Map<String, Any?>, actor: DriverDutyActor, nowMs: Long): DriverRideNotificationOffer? {
      if (row["human_acceptance_required"] != true || row["currency"] != "EUR" ||
        row["tenant_id"] != actor.tenantId || row["company_id"] != actor.companyId ||
        row["driver_id"] != actor.driverId || row["vehicle_id"] != actor.vehicleId ||
        listOf(actor.tenantId, actor.companyId, actor.driverId, actor.vehicleId).any { it.isBlank() }) return null
      val id = (row["offer_id"] as? String)?.takeIf { it.isNotBlank() && it.length <= 200 } ?: return null
      val version = (row["version"] as? Number)?.toLong() ?: return null
      val deadline = (row["ack_deadline_ms"] as? Number)?.toLong() ?: return null
      if (version < 1 || version > Int.MAX_VALUE || row["version"].toString() != version.toString() ||
        deadline <= nowMs || row["ack_deadline_ms"].toString() != deadline.toString()) return null
      fun address(field: String) = (row[field] as? String)?.takeIf { it.isNotBlank() && it.length <= 500 }
      val pickup = address("pickup_address") ?: return null
      val destination = address("dropoff_address") ?: return null
      val time = row["pickup_iso"] as? String
      val price = (row["price_incl_vat"] as? Number)?.toDouble()
      if (row["price_incl_vat"] != null && (price == null || !price.isFinite() || price < 0)) return null
      return DriverRideNotificationOffer(id, version.toInt(), deadline, pickup, destination, time?.take(80), price)
    }
  }
}

/** Uses the existing availability heartbeat; this is not an external push transport. */
internal class DriverRideNotifications(private val context: Context) {
  companion object {
    const val CHANNEL = "driver_ride_offers_v3"
    const val FOREGROUND_ID = 755 // Cancel only the retired one-shot notification.
    val VIBRATION = longArrayOf(0, 350, 200, 350, 900)
    private val attention = DriverRideAlertClaimCache()
    private val alarmHandler by lazy { Handler(Looper.getMainLooper()) }
    private data class ActiveAttention(val id: Int, var deadline: Long, var timeout: Runnable? = null)
    internal data class Admission(val id: Int, val first: Boolean)
    private val active = linkedMapOf<List<String>, ActiveAttention>()
    private var nextAttentionId = 800
    fun claimAttention(key: List<String>, deadlineMs: Long) = attention.take(key, deadlineMs, System.currentTimeMillis())

    fun channel(context: Context): NotificationManager {
      val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(CHANNEL) == null) {
        val previous = manager.getNotificationChannel("driver_ride_offers_v2")
          ?: manager.getNotificationChannel("driver_ride_offers_v1")
        val sound = Uri.parse("android.resource://${context.packageName}/raw/fluxidi_ride_chime")
        val old = previous?.let { DriverRideChannelSnapshot(it.importance, it.sound?.toString(),
          it.shouldVibrate(), it.vibrationPattern,
          if (Build.VERSION.SDK_INT >= 30) it.hasUserSetSound() else null,
          if (Build.VERSION.SDK_INT >= 29) it.hasUserSetImportance() else null) }
        val policy = driverRideChannelPolicy(old, sound.toString())
        val channel = NotificationChannel(CHANNEL, "Ritaanbiedingen", policy.importance)
        channel.description = "Nieuwe ritten voor de aangemelde chauffeur"
        channel.enableVibration(policy.vibrate)
        channel.vibrationPattern = policy.pattern
        channel.setSound(policy.sound?.let(Uri::parse),
          if (previous != null && policy.sound == previous.sound?.toString()) previous.audioAttributes
          else AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
        channel.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        manager.createNotificationChannel(channel)
      }
      return manager
    }
    fun allowed(context: Context): Boolean {
      if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
      val manager = channel(context)
      return manager.areNotificationsEnabled() && (Build.VERSION.SDK_INT < 26 ||
        manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)
    }
    fun builder(context: Context): Notification.Builder {
      val builder = (if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else Notification.Builder(context))
        .setSmallIcon(com.fluxidi.tracking.R.drawable.ic_ride_notification)
        .setCategory(Notification.CATEGORY_EVENT).setVisibility(Notification.VISIBILITY_PRIVATE)
        .setPriority(Notification.PRIORITY_HIGH).setOngoing(true)
      if (Build.VERSION.SDK_INT < 26) builder
        .setSound(Uri.parse("android.resource://${context.packageName}/raw/fluxidi_ride_chime"),
          AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT).build())
        .setVibrate(VIBRATION)
      return builder
    }
    private fun launch(context: Context, id: Int): PendingIntent? {
      val intent = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
      intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
      intent.putExtra("fluxidi_open_driver_offers", true)
      return PendingIntent.getActivity(context, id, intent,
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }
    @Synchronized internal fun stopAttention(context: Context, key: List<String>) {
      val current = active.remove(key) ?: return
      current.timeout?.let(alarmHandler::removeCallbacks)
      channel(context).cancel(current.id)
    }
    @Synchronized internal fun stopActor(context: Context, actor: DriverDutyActor, offerId: String? = null) {
      val scope = listOf(actor.tenantId, actor.companyId, actor.driverId, actor.vehicleId)
      for (key in active.keys.filter { it.take(4) == scope && (offerId == null || it[4] == offerId) }) stopAttention(context, key)
    }
    @Synchronized private fun post(context: Context, key: List<String>, deadline: Long,
      rearm: Boolean = false, build: (Int, Long) -> Notification?): Admission? {
      val now = System.currentTimeMillis()
      if (key.size != 6 || key.any { it.isBlank() } || deadline <= now || !allowed(context)) return null
      val previous = active[key]
      if (previous != null && previous.deadline == deadline && !rearm) return Admission(previous.id, false)
      if (previous == null && !claimAttention(key, deadline)) return null
      val record = previous ?: ActiveAttention(nextAttentionId++, deadline)
      val notification = build(record.id, deadline - now)
      if (notification == null) {
        if (previous == null) attention.releaseUnposted(key)
        return null
      }
      notification.flags = notification.flags or Notification.FLAG_INSISTENT
      try { channel(context).notify(record.id, notification) }
      catch (_: Exception) { if (previous == null) attention.releaseUnposted(key); return null }
      if (previous == null && active.size >= 8) stopAttention(context, active.keys.first())
      active[key.toList()] = record
      record.timeout?.let(alarmHandler::removeCallbacks)
      record.deadline = deadline
      val app = context.applicationContext
      val timeout = Runnable { synchronized(this) {
        if (active[key] === record && record.deadline == deadline) stopAttention(app, key)
      } }
      record.timeout = timeout
      alarmHandler.postDelayed(timeout, (deadline - System.currentTimeMillis()).coerceAtLeast(1))
      return Admission(record.id, previous == null)
    }
    internal fun foreground(context: Context, key: List<String>, deadline: Long, rearm: Boolean): Admission? =
      post(context, key, deadline, rearm) { id, remaining ->
        val pending = launch(context, id) ?: return@post null
        val builder = builder(context).setContentTitle("Nieuwe rit")
          .setContentText("Bekijk het ritvoorstel in Fluxidi").setContentIntent(pending)
        if (Build.VERSION.SDK_INT >= 26) builder.setTimeoutAfter(remaining)
        builder.build()
      }
  }

  private val shown = mutableMapOf<String, Int>()
  private var owner: DriverDutyLease? = null

  @Synchronized fun present(lease: DriverDutyLease, offer: DriverRideNotificationOffer, isCurrent: () -> Boolean): Boolean {
    if (!isCurrent() || !allowed(context) || offer.deadlineMs <= System.currentTimeMillis()) return false
    if (owner !== lease) { clear(); owner = lease }
    val key = "${offer.id}:${offer.version}"
    val text = buildString {
      append("${offer.pickup} → ${offer.destination}")
      offer.pickupIso?.let { iso ->
        for (pattern in listOf("yyyy-MM-dd'T'HH:mm:ss.SSSX", "yyyy-MM-dd'T'HH:mm:ssX")) {
          val parser = java.text.SimpleDateFormat(pattern, java.util.Locale.ROOT).apply { isLenient = false }
          val position = java.text.ParsePosition(0)
          val date = parser.parse(iso, position)
          if (date != null && position.index == iso.length) {
            append("\nOphaaltijd: ${java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.SHORT, java.text.DateFormat.SHORT).format(date)}")
            break
          }
        }
      }
      offer.price?.let { append("\n€ ${String.format(java.util.Locale.getDefault(), "%.2f", it)}") }
    }
    val attentionKey = listOf(lease.actor.tenantId, lease.actor.companyId,
      lease.actor.driverId, lease.actor.vehicleId, offer.id, offer.version.toString())
    val admission = post(context, attentionKey, offer.deadlineMs) { id, remaining ->
      if (!isCurrent()) return@post null
      val pending = launch(context, id) ?: return@post null
      val notification = builder(context).setContentTitle("Nieuwe rit").setContentText(text)
        .setStyle(Notification.BigTextStyle().bigText(text)).setContentIntent(pending)
        .setPublicVersion(builder(context).setContentTitle("Nieuwe rit")
          .setContentText("Open Fluxidi om het aanbod te bekijken").build())
      if (Build.VERSION.SDK_INT >= 26) notification.setTimeoutAfter(remaining)
      notification.build()
    } ?: return false
    shown[key] = admission.id
    if (shown.size > 8) shown.remove(shown.keys.first())
    return true // Receipt/acceptance remain separate server operations after actual UI display.
  }

  @Synchronized fun clearOffer(id: String) {
    owner?.let { stopActor(context, it.actor, id) }
    for (key in shown.keys.filter { it.substringBeforeLast(':') == id }) shown.remove(key)
  }
  @Synchronized fun clear() {
    owner?.let { stopActor(context, it.actor) }
    shown.clear(); owner = null
  }
}

internal data class DriverRideChannelSnapshot(val importance: Int, val sound: String?,
  val vibrate: Boolean, val pattern: LongArray?, val userSound: Boolean?, val userImportance: Boolean?)
internal data class DriverRideChannelPolicy(val importance: Int, val sound: String?,
  val vibrate: Boolean, val pattern: LongArray)
internal fun driverRideChannelPolicy(old: DriverRideChannelSnapshot?, sound: String): DriverRideChannelPolicy {
  val oldPattern = longArrayOf(0, 180, 120, 180)
  val pattern = old?.pattern?.takeUnless { it.contentEquals(oldPattern) }
    ?: longArrayOf(0, 350, 200, 350, 900)
  return DriverRideChannelPolicy(
    if (old == null || old.userImportance == false && old.importance != 0) 4 else old.importance,
    if (old == null || old.userSound == false) sound else old.sound,
    old?.vibrate ?: true, pattern)
}
