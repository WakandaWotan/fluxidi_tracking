import { companyTrackingObjectName } from '../../tracking/modules/company_tracking_room.mjs';

export async function commitCompanyCapacity(env, scope, input, recovered = false) {
  if (!env?.COMPANY_TRACKING) return { ok: true, skipped: true };
  const tenant_id = scope?.tenant_id ?? scope?.tenantId;
  const company_id = scope?.company_id ?? scope?.companyId;
  if (!tenant_id || !company_id) return { ok: false, error: 'capacity_scope_required' };
  try {
    const room = env.COMPANY_TRACKING.get(env.COMPANY_TRACKING.idFromName(companyTrackingObjectName(tenant_id, company_id)));
    const response = await room.fetch('https://room/capacity', { method: 'POST',
      headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ...input, tenant_id, company_id }) });
    const result = await response.json();
    if (!recovered && result?.error === 'capacity_update_pending' && env.BOOKING_KV && Number.isInteger(result.pending_version)) {
      // Only positive, persisted canonical evidence can finish a prior write.
      // A missing record or read failure never frees either held resource.
      const record = await env.BOOKING_KV.get(`booking:${input.owner_id}`, { type: 'json' });
      // Re-dispatch must first revoke the old public grant/indexes. A different
      // writer may not skip that handoff by confirming its empty checkpoint.
      if (record?.dispatch_assignment_revalidation) return { ok: false, error: 'capacity_update_pending' };
      const checkpoint = record?.dispatch_capacity_checkpoint;
      if (record?.tenant_id === tenant_id && record?.company_id === company_id
        && checkpoint?.version === result.pending_version && Array.isArray(checkpoint.claims)) {
        const confirmed = await commitCompanyCapacity(env, scope, { action: 'confirm', owner_id: input.owner_id,
          version: checkpoint.version, canonical_claims: checkpoint.claims }, true);
        if (confirmed.ok) return commitCompanyCapacity(env, scope, input, true);
      }
    }
    if (!response.ok || result?.ok !== true || result?.committed !== true) {
      return { ok: false, error: result?.error || 'capacity_commit_unavailable' };
    }
    return { ok: true };
  } catch (_) { return { ok: false, error: 'capacity_commit_unavailable' }; }
}
