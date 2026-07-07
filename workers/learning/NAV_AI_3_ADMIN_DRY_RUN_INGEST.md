# NAV-AI-3 — Admin dry-run nav complexity ingest (Learning Worker)

Status: **admin-only / protected** — not connected to Flutter live upload.

## Purpose

Prove end-to-end that Fluxidi Learning can:

1. Receive one sanitized `nav_complexity_event` (NAV-AI-1 shape)
2. Validate it and reject forbidden PII
3. Store it in D1 when `dryRunStore=true`
4. Query recent rows back (sanitized, truncated hashes)
5. Delete test/dry-run records on demand

This is **advisory/learning infrastructure only**. It does not change navigation,
routing, dispatch, or guard thresholds in the Flutter app.

## Auth

All `/admin/nav-complexity-events/*` routes require:

```
Authorization: Bearer <LEARNING_SERVICE_TOKEN>
```

Same service token as ride-lesson ingest. Token is a Worker secret — never in Git,
never logged, never echoed.

## Endpoints

### POST `/admin/nav-complexity-events/ingest-dry-run`

Request body:

```json
{
  "dryRunStore": true,
  "source": "test",
  "event": {
    "type": "nav_complexity_event",
    "version": 1,
    "reasonCode": "low_confidence",
    "severity": "warning",
    "confidenceBucket": "40-60",
    "snapDistBucket": "15-30",
    "speedBucket": "city",
    "maneuverType": "turn",
    "maneuverModifier": "right",
    "predictionRepeated": false,
    "trustBearing": true,
    "trustInstruction": false,
    "occurredAtMinuteBucket": "2026-07-07T10:12:00.000Z"
  }
}
```

| Field | Required | Notes |
|-------|----------|-------|
| `dryRunStore` | yes | `false` = validate only; `true` = validate + D1 insert |
| `source` | no | Default `test`; allowed: `test`, `manual_test`, `dry_run` |
| `event` | yes | NAV-AI-1 sanitized event only |

Responses always include `advisoryOnly: true`.

### GET `/admin/nav-complexity-events/recent`

Returns the last 20 stored rows. `sessionHash` in nested `sanitized` payload is
truncated (first 4 chars + `...`). No raw lat/lng or identity fields.

### DELETE `/admin/nav-complexity-events/test-data`

Deletes rows where `dry_run = 1` OR `source IN ('test', 'dry_run', 'manual_test')`.

## D1 schema

See `schema.sql` — table `nav_complexity_events`:

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PK | `navcx_*` |
| `created_at` | TEXT | ISO timestamp |
| `reason_code` … `trust_instruction` | typed columns | query-friendly |
| `dry_run` | INTEGER | always `1` for this ingest path |
| `source` | TEXT | test/manual_test/dry_run |
| `raw_json` | TEXT | sanitized event JSON only |

Apply locally:

```bash
cd workers/learning
npx wrangler d1 execute fluxidi-learning-db --remote --file=schema.sql
```

(Do not deploy until approved.)

## Files

| File | Role |
|------|------|
| `nav_complexity_event_schema.js` | Validation + PII guard + row mapping |
| `fluxidi_learning_worker.js` | Admin routes wired |
| `nav_complexity_event_schema.test.mjs` | Schema unit tests |
| `fluxidi_learning_worker_nav_complexity.test.mjs` | Endpoint tests (mock D1) |

## Relationship to NAV-AI-1 / NAV-AI-2

```
Flutter NavComplexityGuard (local, realtime)
        │
        ▼ local JSONL export (NAV-AI-1)
Sanitized nav_complexity_event files
        │
        ├── NAV-AI-2 offline analyzer (batch, advisory)
        │
        └── NAV-AI-3 admin dry-run ingest (manual curl / staging only)
                    │
                    ▼
              D1 nav_complexity_events
```

Flutter cloud upload remains **disabled**
(`kNavComplexityIntelligenceCloudUploadEnabled = false`).

## Manual smoke test (after deploy approval)

```bash
curl -sS -X POST "$LEARNING_URL/admin/nav-complexity-events/ingest-dry-run" \
  -H "Authorization: Bearer $LEARNING_SERVICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"dryRunStore":true,"source":"test","event":{...}}'

curl -sS "$LEARNING_URL/admin/nav-complexity-events/recent" \
  -H "Authorization: Bearer $LEARNING_SERVICE_TOKEN"

curl -sS -X DELETE "$LEARNING_URL/admin/nav-complexity-events/test-data" \
  -H "Authorization: Bearer $LEARNING_SERVICE_TOKEN"
```

## Diagnostics

Bounded logs only: `[NAV_AI_3] endpoint=... result=... reason=...` — no PII.
