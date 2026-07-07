# NAV-AI-1 — Navigation Complexity Intelligence (foundation)

Status: **design / foundation only** — no production cloud dependency for driver warnings.

## Purpose

Allow a future Fluxidi Learning / AI worker to ingest **sanitized** navigation
complexity events from Driver OS and:

- Cluster repeated complexity patterns (junctions, roundabouts, bad GPS zones)
- Recommend threshold tuning for `NavComplexityGuard`
- Detect recurring maneuver ambiguity
- Eventually feed anonymous "known complex zone" hints **only after** enough
  sanitized evidence (never as a realtime safety gate)

## Realtime safety rule

**Driver warnings remain 100% local.** `NavComplexityGuard` in Flutter decides
whether to show the caution banner. Cloud AI must never be required for
realtime safety.

## Flutter client (implemented)

| File | Role |
|------|------|
| `lib/navigation/nav_engine/nav_complexity_guard.dart` | Local guard (NAV-R14A) |
| `lib/navigation/nav_engine/nav_complexity_intelligence.dart` | Sanitized event builder + local export |

Feature flags (defaults):

- `kNavComplexityIntelligenceLocalExportEnabled = true` — append to nav diagnostics JSONL
- `kNavComplexityIntelligenceCloudUploadEnabled = false` — no HTTP upload

Events are recorded on **caution activation edge** (when `active` becomes true),
not on every GPS tick.

## Event shape (version 1)

```json
{
  "type": "nav_complexity_event",
  "version": 1,
  "app": "driver",
  "platform": "flutter",
  "reasonCode": "low_confidence",
  "severity": "info",
  "confidenceBucket": "40-60",
  "snapDistBucket": "15-30",
  "speedBucket": "city",
  "maneuverType": "turn",
  "maneuverModifier": "right",
  "predictionRepeated": false,
  "trustBearing": true,
  "trustInstruction": false,
  "occurredAtMinuteBucket": "2026-07-07T18:12:00.000Z",
  "sessionHash": "a1b2c3d4"
}
```

### Allowed fields only

No raw lat/lng, no addresses, no customer/driver identity, no booking id
(unless a future approved hashed pattern is added separately).

### Buckets

| Field | Values |
|-------|--------|
| `confidenceBucket` | `0-20`, `20-40`, `40-60`, `60-80`, `80-100`, `unknown` |
| `snapDistBucket` | `0-5`, `5-15`, `15-30`, `30+`, `unknown` |
| `speedBucket` | `stopped`, `slow`, `city`, `urban`, `fast`, `unknown` |
| `maneuverType` | `turn`, `roundabout`, `arrive`, `depart`, `unknown` |
| `maneuverModifier` | `left`, `right`, `straight`, `uturn`, `unknown` |
| `severity` | `info`, `warning` |

### Reason codes (align with guard)

- `low_confidence`
- `offroute_uncertain`
- `repeated_prediction`
- `ambiguous_instruction`
- `high_snap_distance`
- `heading_route_conflict`
- `dense_maneuver_area`

## Admin dry-run ingest (NAV-AI-3 — implemented, not live from Flutter)

Protected admin-only endpoints in `fluxidi_learning_worker.js`:

```
POST   /admin/nav-complexity-events/ingest-dry-run
GET    /admin/nav-complexity-events/recent
DELETE /admin/nav-complexity-events/test-data
Authorization: Bearer <LEARNING_SERVICE_TOKEN>
```

See `NAV_AI_3_ADMIN_DRY_RUN_INGEST.md`. Flutter cloud upload remains disabled.

## Integration with existing Learning Worker

The existing `fluxidi_learning_worker.js` (`workers/learning/`) handles ride
lessons today. NAV-AI-1 complexity events are a **separate ingest path** so
navigation learning does not mix with booking/ride lesson payloads.

When ready:

1. Add `nav_complexity_events.js` validator module (mirror PII guard from ride lessons)
2. Wire route in `fluxidi_learning_worker.js`
3. Enable `kNavComplexityIntelligenceCloudUploadEnabled` only after staging validation

## Diagnostics tags

| Tag | Layer |
|-----|-------|
| `NAV_R14_COMPLEXITY` | Local guard decision (bounded, no PII) |
| `nav_complexity_event` | Sanitized JSONL export for AI foundation |
