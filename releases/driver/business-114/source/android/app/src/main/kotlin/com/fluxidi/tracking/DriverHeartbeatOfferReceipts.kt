package com.fluxidi.tracking

internal data class DriverHeartbeatOfferReceipt(
  val id: String,
  val version: Int,
  val humanAcceptanceRequired: Boolean,
)

/** Legacy readiness receipts cannot stand in for a displayed human proposal. */
internal fun acknowledgeHeartbeatOffers(
  offers: List<DriverHeartbeatOfferReceipt>,
  isCurrent: () -> Boolean,
  acknowledge: (String, Int) -> Int,
  revoked: () -> Unit,
) {
  for (offer in offers.take(8)) {
    if (!isCurrent()) return
    if (offer.humanAcceptanceRequired || offer.id.isBlank() || offer.id.length > 200 || offer.version < 1) continue
    val code = acknowledge(offer.id, offer.version)
    if (code == 401 || code == 403) { revoked(); return }
  }
}
