// Persisted identity of company code FLX-00001. The legacy worker-wide
// Pushbullet token may be used only for this pair. Another company, including
// Taxi Mario, never receives that token.
export const FLUXIDI_LEGACY_PUSHBULLET_TENANT_ID = "fluxidi_fluxidi_ddmh9g";
export const FLUXIDI_LEGACY_PUSHBULLET_COMPANY_ID = "fluxidi_fluxidi_ddmh9g";

function bookingScope(booking) {
  return {
    tenantId: String(booking?.tenant_id ?? booking?.tenantId ?? "").trim(),
    companyId: String(booking?.company_id ?? booking?.companyId ?? "").trim(),
  };
}

export function isFluxidiLegacyPushbulletCompany(booking) {
  const { tenantId, companyId } = bookingScope(booking);
  return tenantId === FLUXIDI_LEGACY_PUSHBULLET_TENANT_ID
    && companyId === FLUXIDI_LEGACY_PUSHBULLET_COMPANY_ID;
}

function configuredEntry(booking, rawConfiguration) {
  const { tenantId, companyId } = bookingScope(booking);
  if (!tenantId || !companyId ||
      tenantId.toLowerCase() === "global" ||
      companyId.toLowerCase() === "global") {
    return { kind: "invalid" };
  }
  if (rawConfiguration == null) return { kind: "absent" };
  if (typeof rawConfiguration === "string" && !rawConfiguration.trim()) return { kind: "absent" };
  let configured;
  try {
    configured = typeof rawConfiguration === "string"
      ? JSON.parse(rawConfiguration) : rawConfiguration;
  } catch (_) {
    return { kind: "invalid" };
  }
  if (configured == null) return { kind: "absent" };
  if (typeof configured !== "object" || Array.isArray(configured)) return { kind: "invalid" };
  const tenant = configured[tenantId];
  if (!tenant || typeof tenant !== "object" || Array.isArray(tenant)) return { kind: "absent" };
  if (!Object.prototype.hasOwnProperty.call(tenant, companyId)) return { kind: "absent" };
  const entry = tenant[companyId];
  if (!entry || typeof entry !== "object" || Array.isArray(entry) || entry.enabled !== true) {
    return { kind: "disabled" };
  }
  const token = String(entry.token ?? "").trim();
  if (!token) return { kind: "disabled" };
  return {
    kind: "selected",
    recipient: { token, deviceIden: String(entry.device_iden ?? "").trim() },
  };
}

// A booking uses its own enabled company entry when one exists. Only the
// persisted FLX-00001 company may use the legacy worker token, and only when
// that company has no explicit entry. A disabled entry does not fall through.
export function bookingPushbulletTarget(booking, rawConfiguration, legacy = null) {
  const configured = configuredEntry(booking, rawConfiguration);
  if (configured.kind === "selected") return configured.recipient;
  if (configured.kind === "disabled" || configured.kind === "invalid") return null;
  if (!isFluxidiLegacyPushbulletCompany(booking)) return null;
  const token = String(legacy?.token ?? "").trim();
  if (!token) return null;
  return {
    token,
    deviceIden: String(legacy?.deviceIden ?? legacy?.device_iden ?? "").trim(),
  };
}

export async function sendCompanyPushbulletNote({
  booking, configuration, legacyToken = "", legacyDeviceIden = "", title, body, fetchImpl = fetch,
}) {
  const recipient = bookingPushbulletTarget(booking, configuration, {
    token: legacyToken,
    deviceIden: legacyDeviceIden,
  });
  if (!recipient) {
    return { enabled: false, sent: false, reason: 'no_scoped_recipient' };
  }
  const payload = {
    type: 'note',
    title: String(title || 'Fluxidi Taxi'),
    body: String(body || ''),
  };
  if (recipient.deviceIden) payload.device_iden = recipient.deviceIden;
  try {
    const response = await fetchImpl('https://api.pushbullet.com/v2/pushes', {
      method: 'POST',
      headers: {
        'Access-Token': recipient.token,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(result?.error?.message || result?.error || 'Pushbullet push failed');
    }
    return { enabled: true, sent: true, iden: result?.iden || null };
  } catch (error) {
    return { enabled: true, sent: false, error: String(error?.message || error) };
  }
}
