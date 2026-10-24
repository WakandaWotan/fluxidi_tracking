// retained-source/workers/booking/modules/reliable_national_publication_policy_v1.mjs
var sealedRuntimeSha256 = false ? null : "e0270b2c198e17fedbe094bd1073655594f2b3f6632d6ea62632be9529103087";
var hash = (s) => typeof s === "string" && /^[a-f0-9]{64}$/.test(s);
var fail = (reason) => {
  throw Error(reason);
};
var manifestHashes = /* @__PURE__ */ new WeakMap();
var NATIONAL_PRODUCTION_MODE = "until_replaced_or_revoked";
function object(value, label) {
  if (typeof value === "string") {
    if (new TextEncoder().encode(value).byteLength > 5120) fail(label);
    try {
      value = JSON.parse(value);
    } catch {
      fail(label);
    }
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) fail(label);
  return value;
}
async function manifestHash(manifest) {
  if (!manifest || typeof manifest !== "object") fail("national_production_manifest");
  const digest = () => crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(manifest))).then((b) => Array.from(new Uint8Array(b), (v) => v.toString(16).padStart(2, "0")).join(""));
  if (!Object.isFrozen(manifest)) return digest();
  if (!manifestHashes.has(manifest)) manifestHashes.set(manifest, digest());
  return manifestHashes.get(manifest);
}
function nationalPublicationPolicyCurrentV1(policy, now) {
  return Number.isFinite(now) && Number.isFinite(policy?.publishedAt) && policy.publishedAt <= now && (policy.mode === NATIONAL_PRODUCTION_MODE && policy.state === "active" || policy.mode === "temporary" && Number.isFinite(policy.validUntil) && policy.validUntil > now);
}
async function validateNationalPublicationPolicyV1({ publication: p, reference, activation, required, now, runtimeSha256 = sealedRuntimeSha256 }) {
  if (p?.schema === "fluxidi-national-publication-v1" && activation == null) {
    const policy2 = { mode: "temporary", publishedAt: p.publishedAt, validUntil: p.validUntil };
    if (!nationalPublicationPolicyCurrentV1(policy2, now)) fail("national_publication_invalid");
    return Object.freeze(policy2);
  }
  if (p?.schema !== "fluxidi-national-production-publication-v1") fail("national_publication_invalid");
  if (required !== true || reference == null) fail("national_production_reference_required");
  const ref = object(reference, "national_production_reference"), a = object(activation, "national_production_activation");
  if (a.schema !== "fluxidi-national-activation-v1" || a.state !== "active") fail("national_production_inactive");
  const approval = p.approval;
  if (approval?.mode !== NATIONAL_PRODUCTION_MODE || approval.state !== "approved" || Object.hasOwn(p, "validUntil")) fail("national_production_approval");
  if (!hash(runtimeSha256) || a.runtimeSha256 !== runtimeSha256 || approval.runtimeSha256 !== runtimeSha256) fail("national_production_runtime_mismatch");
  if (!hash(ref.sha256) || ref.sha256 !== a.publicationSha256) fail("national_production_reference_mismatch");
  if (a.graphVersion !== p.region?.graphVersion || a.graphVersion !== p.manifest?.graphVersion || a.evidenceRevision !== p.region?.evidenceRevision || a.evidenceRevision !== p.manifest?.accessContext?.revision) fail("national_production_graph_mismatch");
  if (!hash(a.manifestSha256) || a.manifestSha256 !== approval.manifestSha256 || await manifestHash(p.manifest) !== a.manifestSha256) fail("national_production_manifest_mismatch");
  const policy = { mode: NATIONAL_PRODUCTION_MODE, state: "active", publishedAt: p.publishedAt, publicationSha256: ref.sha256, runtimeSha256, graphVersion: a.graphVersion, evidenceRevision: a.evidenceRevision, manifestSha256: a.manifestSha256 };
  if (!nationalPublicationPolicyCurrentV1(policy, now)) fail("national_production_publication_time");
  return Object.freeze(policy);
}
export {
  NATIONAL_PRODUCTION_MODE,
  nationalPublicationPolicyCurrentV1,
  validateNationalPublicationPolicyV1
};
