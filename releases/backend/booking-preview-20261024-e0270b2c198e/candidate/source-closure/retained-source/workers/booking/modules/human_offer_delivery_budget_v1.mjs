// Selection budget is distinct from the existing Room's bounded delivery and
// response deadlines. This cannot revive a closed/expired Room offer.
export function humanOfferDeliveryWindowV1(record,bookingId,nowMs){
 const o=record?.dispatch_offer,created=Date.parse(o?.created_at);
 if(!['prepared','offered','committing'].includes(o?.state)||o.owner_id!==bookingId
  ||o.human_acceptance_required!==true||o.response_starts_on_display!==true||o.claims?.length!==1
  ||!Number.isSafeInteger(o.ack_timeout_ms)||o.ack_timeout_ms<=0||o.ack_timeout_ms>30000
  ||!Number.isFinite(created)||created>nowMs)return false;
 const end=Math.min(created+150000+o.ack_timeout_ms,o.asap_search_expires_ms??Infinity);
 return Number.isFinite(nowMs)&&nowMs<end;
}
