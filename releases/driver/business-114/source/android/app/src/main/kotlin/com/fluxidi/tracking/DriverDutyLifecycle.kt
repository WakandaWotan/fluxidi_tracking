package com.fluxidi.tracking

/** Server heartbeat decides whether this exact publishing lease may continue. */
internal object DriverDutyHeartbeatPolicy {
  fun terminationReason(code: Int, isActive: Boolean, availability: String): String? {
    if (code == 401 || code == 403) return "session_revoked"
    // Booking's canonical active-ride value is busy. Retaining GPS does not
    // publish available status or change the allocator's active capacity hold.
    if (code == 200 && (!isActive || availability !in listOf("available", "busy", "on_trip"))) return "availability_ended"
    return null
  }
}

/** A retired publication may never keep sending or silently reclaim another device. */
internal object DriverDutyLocationPolicy {
  fun terminationReason(code: Int, error: String, cleared: Boolean, reason: String = ""): String? {
    if (code == 401 || code == 403) return "session_revoked"
    // The authenticated presence wrapper exposes Room errors as reason;
    // direct/legacy responses can still carry error. Both are coded values.
    if (code == 409 && reason.ifBlank { error } == "location_owner_retired") return "location_owner_retired"
    if (code == 200 && cleared) return "availability_ended"
    return null
  }
}

internal data class DriverDutyActor(
  val tenantId: String = "", val companyId: String = "", val driverId: String = "", val vehicleId: String = "",
)

/** Caller-provided expected credentials are only compared, never returned. */
internal class DriverDutyExpectedConfig(
  val token: String, val booking: String, val tracking: String, val actor: DriverDutyActor,
  val title: String? = null, val text: String? = null,
) {
  companion object {
    fun fromMap(values: Map<*, *>?): DriverDutyExpectedConfig? {
      val map = values ?: return null
      val required = listOf("token", "tenant_id", "company_id", "driver_id", "vehicle_id", "booking", "tracking")
      if (required.any { (map[it] as? String)?.isNotEmpty() != true }) return null
      if (listOf("title", "text").any { map.containsKey(it) && map[it] !is String }) return null
      return DriverDutyExpectedConfig(map["token"] as String, map["booking"] as String, map["tracking"] as String,
        DriverDutyActor(map["tenant_id"] as String, map["company_id"] as String, map["driver_id"] as String, map["vehicle_id"] as String),
        map["title"] as? String, map["text"] as? String)
    }
  }
}

/** Immutable credentials for one activation; never render this object in logs. */
internal class DriverDutyLease(
  val activationId: String,
  val token: String,
  val booking: String,
  val tracking: String,
  val generation: Long,
  val nativeDeviceId: String,
  val actor: DriverDutyActor,
  val title: String,
  val text: String,
)

internal data class DriverDutyStatus(
  val activationId: String = "",
  val state: String = "stopped",
  val reason: String = "",
  val nativeDeviceId: String = "",
) {
  val running: Boolean get() = state == "ready"
}

/** Also owns queued starts: a STOP before onStartCommand must cancel that start. */
internal class DriverDutyLifecycle {
  private var generation = 0L
  private var requested = false
  private var lease: DriverDutyLease? = null
  private var status = DriverDutyStatus()

  @Synchronized fun begin(activationId: String, token: String, booking: String, tracking: String, nativeDeviceId: String = "",
    actor: DriverDutyActor = DriverDutyActor(), title: String = "Fluxidi", text: String = ""): DriverDutyLease {
    requested = true
    return DriverDutyLease(activationId, token, booking, tracking, ++generation, nativeDeviceId, actor, title, text).also {
      lease = it
      status = DriverDutyStatus(activationId, "starting")
    }
  }

  @Synchronized fun acceptCommand(activationId: String, commandGeneration: Long, token: String, booking: String, tracking: String,
    nativeDeviceId: String = "", actor: DriverDutyActor = DriverDutyActor(), title: String = "Fluxidi", text: String = ""): DriverDutyLease? {
    val current = lease
    if (current != null) return current.takeIf {
      it.activationId == activationId && it.generation == commandGeneration
        && it.token == token && it.booking == booking && it.tracking == tracking && it.nativeDeviceId == nativeDeviceId
        && it.actor == actor && it.title == title && it.text == text
    }
    // Android may redeliver the last Intent after process death. A cancelled
    // command in this same process must never be restored by this branch.
    if (requested) return null
    return begin(activationId, token, booking, tracking, nativeDeviceId, actor, title, text)
  }

  @Synchronized fun current(readyOnly: Boolean = true): DriverDutyLease? =
    lease.takeIf { !readyOnly || status.running }

  @Synchronized fun isCurrent(candidate: DriverDutyLease, readyOnly: Boolean = true): Boolean =
    lease === candidate && (!readyOnly || status.running)

  @Synchronized fun ready(candidate: DriverDutyLease): Boolean {
    if (!isCurrent(candidate, false)) return false
    status = DriverDutyStatus(candidate.activationId, "ready", nativeDeviceId = candidate.nativeDeviceId)
    return true
  }

  @Synchronized fun finish(candidate: DriverDutyLease, reason: String, failed: Boolean = false): Boolean {
    if (!isCurrent(candidate, false)) return false
    lease = null
    ++generation
    status = DriverDutyStatus(candidate.activationId, if (failed) "failed" else "stopped", reason)
    return true
  }

  @Synchronized fun cancel(activationId: String?, reason: String): DriverDutyLease? {
    val current = lease ?: return null
    if (!activationId.isNullOrEmpty() && current.activationId != activationId) return null
    finish(current, reason)
    return current
  }

  @Synchronized fun status(activationId: String? = null, expected: DriverDutyExpectedConfig? = null): DriverDutyStatus {
    if (expected != null) {
      val current = lease
      if (current == null || current.token != expected.token || current.booking != expected.booking
        || current.tracking != expected.tracking || current.actor != expected.actor
        || (expected.title != null && current.title != expected.title)
        || (expected.text != null && current.text != expected.text)) {
        return DriverDutyStatus(reason = "owner_not_current")
      }
    }
    if (!activationId.isNullOrEmpty() && status.activationId != activationId) {
      return DriverDutyStatus(activationId, reason = "activation_not_current")
    }
    return status
  }
}
