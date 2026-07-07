# NAV-AI-2 — Navigation Complexity Analyzer (read-only / dry-run)

Status: **advisory-only tooling** — not connected to live ingest or production
navigation behavior.

## Purpose

Analyze batches of sanitized `nav_complexity_event` records (NAV-AI-1 shape)
and produce:

- Event counts and bucket distributions
- Signal rates (`repeatedPrediction`, `trustBearing` false, `trustInstruction` false)
- Top combined patterns
- **Advisory** threshold tuning recommendations

This tool helps engineers review exported diagnostics offline. It does **not**
change routing, snapping, dispatch, guard thresholds, or any Flutter runtime
behavior.

## Non-goals (explicit)

| Out of scope | Reason |
|--------------|--------|
| Live ingest / HTTP upload | NAV-AI-1 cloud path remains disabled |
| Worker production endpoint | No automatic threshold application |
| Raw coordinates or addresses | Privacy / safety |
| Driver or customer identity | Privacy |
| Realtime guard changes | Local `NavComplexityGuard` stays authoritative |

## Files

| File | Role |
|------|------|
| `nav_complexity_analyzer.js` | Pure analyzer module (CommonJS) |
| `analyze_nav_complexity_cli.js` | Dry-run CLI (stdout JSON report) |
| `nav_complexity_analyzer.test.js` | Node built-in test suite |
| `fixtures/nav_complexity_events_sample.json` | Fake sanitized events for local runs |

## Input

Accepted formats:

1. JSON array of events
2. JSONL (one JSON object per line)
3. Mixed diagnostics JSONL — non-`nav_complexity_event` lines are ignored

Each event must match the NAV-AI-1 sanitized schema documented in
`NAV_AI_1_NAV_COMPLEXITY.md`. Events containing forbidden PII keys are dropped.

### Allowed fields

`type`, `version`, `app`, `platform`, `reasonCode`, `severity`,
`confidenceBucket`, `snapDistBucket`, `speedBucket`, `maneuverType`,
`maneuverModifier`, `predictionRepeated`, `trustBearing`, `trustInstruction`,
`occurredAtMinuteBucket`, `sessionHash` (optional, hashed session only).

## Output

Example report shape:

```json
{
  "advisoryOnly": true,
  "dryRun": true,
  "connectedToLiveIngest": false,
  "totalEvents": 12,
  "distributions": {
    "reasonCode": { "repeated_prediction": 3, "low_confidence": 3 },
    "severity": { "warning": 7, "info": 5 },
    "confidenceBucket": { "60-80": 4 },
    "snapDistBucket": { "30+": 3 },
    "speedBucket": { "city": 3, "slow": 3 }
  },
  "rates": {
    "repeatedPrediction": 0.25,
    "trustBearingFalse": 0.417,
    "trustInstructionFalse": 0.417
  },
  "topPatterns": [
    {
      "pattern": "repeated_prediction|warning|40-60|15-30|city|turn|right|predRepeat|bearingLow|instrOk",
      "count": 1,
      "share": 0.083
    }
  ],
  "recommendations": [
    {
      "id": "snap_bearing_conflict",
      "priority": "high",
      "message": "Advisory: high_snap_distance often coincides with trustBearing=false — ..."
    }
  ]
}
```

Output never includes raw lat/lng, addresses, booking ids, or driver/customer
identity. `sessionHash` from input is not echoed in the report.

## Advisory recommendation heuristics

Recommendations are rule-based hints for human review:

| ID | Trigger (summary) | Suggested review area |
|----|-------------------|------------------------|
| `prediction_duration_city_urban` | High `repeated_prediction` at city/urban speeds | Prediction / gap-bridge duration |
| `snap_bearing_conflict` | High snap distance + `trustBearing=false` | Snap vs bearing conflict logic |
| `ambiguous_roundabout_fork` | `ambiguous_instruction` near roundabout/fork/merge | Maneuver selection / banner copy |
| `low_confidence_slow_speed` | `low_confidence` mostly at stopped/slow | Low-speed hold / caution delay |
| `warning_mid_confidence_sensitive` | Many warnings in confidence 60–80 | Guard sensitivity |
| `prediction_repeat_global` | High global repeated prediction rate | Gap-bridge frequency / cooldown |

All messages are prefixed with **Advisory:** and require manual validation
before any threshold change.

## Usage

### Run tests

```bash
node --test workers/learning/nav_complexity_analyzer.test.js
```

### Analyze sample fixture

```bash
node workers/learning/analyze_nav_complexity_cli.js
```

### Analyze exported JSONL from device diagnostics

```bash
node workers/learning/analyze_nav_complexity_cli.js /path/to/nav_diagnostics.jsonl
```

## Relationship to NAV-AI-1

```
Flutter NavComplexityGuard (local, realtime)
        │
        ▼ (activation edge only)
Sanitized nav_complexity_event → local JSONL export
        │
        ▼ (manual / batch, offline)
NAV-AI-2 analyzer (this tool) → advisory report
        │
        ✗ (not wired)
Cloud worker ingest / auto threshold changes
```

## Future work (not in NAV-AI-2)

- Optional admin-only worker endpoint behind auth (still dry-run)
- Batch ingest from R2 / D1 after privacy review
- Correlation with anonymous zone tiles (hashed geohash only)

Until those are explicitly approved, keep cloud upload disabled in Flutter
(`kNavComplexityIntelligenceCloudUploadEnabled = false`).
