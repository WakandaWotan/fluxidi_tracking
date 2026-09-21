# CHIRON-CRON-KV-SCAN-P1 — COMPLIANCE_KV due-index and write reduction

Prepared in worktree `D:\Projecten\_flutter_work\_fluxidi_chiron_due_index` on
branch `fix/chiron-compliance-due-index-p1`. **Not deployed.** Live remains
`85f70b04-adf9-474e-86bb-279ac6f35917` (BOOKING_KV P0) until an operator
deploys this branch.

The customer app and the Mollie refund repair are out of scope.

## 1. Provenance

Re-checked on 2026-09-21 (not assumed from the earlier report):

| Fact | Value |
| --- | --- |
| Live worker | `fluxidi-compliance-api` |
| Live version | `85f70b04-adf9-474e-86bb-279ac6f35917` @ 100% |
| Live created | 2026-09-21T12:38:18Z |
| Deployed 100% | 2026-09-21T12:38:44Z |
| Tag | `chiron-cron-kv-reads-p0` |
| Rollback of live | `16d11eeb-9f81-48a5-adb7-d98dbd8dc50f` |
| Release line | `origin/release/compliance-worker-d03` = `780800ee` |
| This worktree HEAD | `fix/chiron-compliance-due-index-p1` (P1 commit on `780800ee`) |
| Prior BOOKING_KV worktree | `D:\Projecten\_flutter_work\_fluxidi_chiron_cron_fix` @ `fix/chiron-cron-kv-reads-p0` |

August commits evaluated, not cherry-picked (they conflict with the live
lazy-leg-map / `nowMs` / `CHIRON_CRON_ENABLED` line):

| Commit | Reused as |
| --- | --- |
| `068df75a` | due-marker key, crash-ordered arm→persist→retire, 25/tick watchdog |
| `1b07e2e8` | newest-first due-at-0, pending_build cooldown, sibling preload |
| `74479590` | candidate→official pointer so synced rides leave the index |

Hole in the August switch (`useDueIndex = hasDone \|\| selected.length > 0`)
is not reused. This branch uses per-scope one-shot scan, then `!done`.

## 2. Measured COMPLIANCE_KV background (live, before this patch)

GraphQL `kvOperationsAdaptiveGroups` / `datetimeFiveMinutes`, namespace
`04313c4521454b909293208d738471a1` (COMPLIANCE_KV).

| Window (UTC) | Reads | Writes | Lists | Deletes |
| --- | ---: | ---: | ---: | ---: |
| 2026-09-21T06:15–18:05 (143 buckets, 11h50) | 236 755 | 5 731 | 730 | 0 |
| Per 5-minute bucket (average) | 1 656 | 40.1 | 5.1 | 0 |
| Screenshot (~12 h, slightly different edges) | ~258.9k | ~6.1k | ~803 | — |

`fluxidi-compliance-api` in the same window: **145 requests, 0 errors** ≈ 144
cron ticks and almost no HTTP. The cron is the background consumer.

### Code paths that produce that plateau

| Op | Path | Idle behaviour today (`85f70b04`) |
| --- | --- | --- |
| ~1 552 reads | scoped `compliance_event_v1/…` full scan (Fluxidi) | every 5 min, including already-synced history |
| ~4 lists | paginated event prefix (page 500) | every tick |
| 1 list | `tenant:` connection scopes | every tick |
| ~4 reads | connection docs | every tick |
| ~15 writes | `ALREADY_SYNCED_COUNTER_REPAIR` | `recordChironTestflowSubmitResult` always stamped `testflow_updated_at` even when the rit was already counted |
| ~3 writes | `waiting_for_departure` status | rewritten every tick with the same fields |
| 1 write | `testflow_auto_reconcile_last_at` | Fluxidi throttle |
| extra | JOUW DRIVER | routing gate used to return `failed` **before** the throttle stamp, so the scope ran every tick (`chiron_not_enabled`). Not a ride failure. |

Normal ride activity in this window: none submitted. The writes are
unchanged-document rewrites, not new Chiron traffic.

BOOKING_KV in the same 12 h is still high **because the window includes the
pre-12:38Z P0 period**. Post-P0 live cycles were 0–11 BOOKING_KV reads/tick.

## 3. What this patch changes

1. **Durable due-index** (`chiron_reconcile_due:v1:<16-digit-due-at>:<32-hex-ref>`,
   metadata `{v, ek}`). Finished history is not value-read every five minutes.
2. **Cron after `!done`**: one due-prefix list, process at most 20 due events
   (newest-first), no `tenant:` scan, no event-prefix list.
3. **Before `!done`**: process any already-due markers, 25/tick global
   watchdog, then one full scoped scan per unmigrated **armed** company (same
   10k cap as today). When every armed scope has a per-scope mig doc, write
   `!done`.
4. **Append** arms due-at-0 on a new canonical+date write only (not on pure
   dedup). Sibling context is one keyed canonical get, not a history list.
5. **Writes only when functional fields change.** Waiting and already-synced
   counter repair skip identical documents. Throttle stamp skipped when still
   fresh.
6. **Gated / disabled connections** exit before the event scan. Settings are
   not changed. Testdossiers are not deleted.
7. **Waiting arrivals** stay on a 5-minute due-at. A successful or
   already-synced departure re-arms the paired arrival at due-at-0.
8. **BOOKING_KV P0 is kept**: on-demand leg memo + `CHIRON_CRON_ENABLED`.

Unchanged rules: newest-booking-first, departure before arrival inside one
booking, process budget 20, already-synced / waiting do not burn the budget,
duplicate guard, definitive cooldown / max attempts, company isolation.

## 4. Hermetic proof (no live Chiron, booking or payment)

```
node --test workers/compliance/*.test.mjs
# 427 tests, 427 pass, 0 fail
# cwd: D:\Projecten\_flutter_work\_fluxidi_chiron_due_index
```

P1 scenarios in `chiron_cron_kv_scan_p1.test.mjs` (counted KV ops per pass):

| Scenario | Events processed | Lasting COMPLIANCE_KV |
| --- | --- | --- |
| Idle after `!done`, 40 historical events | 0 | 1 due list, 0 event reads, 0 writes, 0 provider |
| New ride + 40 history | 1 | 1 event read (the new key only) |
| Retryable fail | due-at 0 | stays selectable |
| Definitive fail (young) | future due-at | not selected this tick |
| Waiting arrival | future due-at = last + 5 min | departure success writes due-at-0 |
| Restart after `!done` | same due marker | no `compliance_event_v1/` list |
| Overlapping duplicate markers | 1 event | extra marker deleted |
| Two companies | A only | B event never read |
| Already-synced counters | — | no rewrite when rit already tracked |
| Gated `enabled=false` | 0 | no event list/read |
| First-tick migration vs later | history read once | later tick event-reads << history |
| `CHIRON_CRON_ENABLED=0` | 0 | 0 lists, 0 reads, 0 writes |

Counted comparison from `node workers/compliance/chiron_cron_kv_scan_p1_bench.mjs`
(80 events, outbound fetch trapped):

| Pass | Reads | Writes | Lists | Deletes | Event value reads |
| --- | ---: | ---: | ---: | ---: | ---: |
| Old full scoped scan, every tick | 345 | 202 | 1 | 40 | 80 |
| First tick, unsynced history (migration + drain) | 423 | 230 | 4 | 40 | 105 |
| Next tick, leftover unsynced due-at-0 | 80 | 20 | 1 | 40 | 20 |
| Idle after `!done`, no markers | 0 | 0 | 1 | 0 | 0 |
| Production-shaped first tick (77 synced + 3 waiting) | 423 | 91 | 4 | 20 | 105 |
| Production-shaped lasting tick | **0** | **0** | **1** | **0** | **0** |

Temporary migration (first armed tick) still pays one scoped scan. That cost
is one-shot per company, not per five minutes.

## 5. Cost model (units, not invented euros)

Assumption set (explicit):

- Cloudflare Workers **Paid**, catalog rates from
  `audit/cost_profitability_20260918/rates.json` (docs read 2026-09-18).
- Included, **account-wide** (all KV namespaces, all workers): 10M reads,
  1M writes, 1M lists, 1M deletes, 10M worker requests.
- Overage USD: $0.50 / M reads, $5 / M writes, $5 / M lists.
- FX and the real invoice are **unknown**. No euro figure is claimed.
- Extrapolation: the measured 5-minute average continues 24/7 (288 ticks/day,
  30 days). Other account KV traffic is **not** subtracted.

### Current COMPLIANCE_KV cron plateau (measured → month)

| Op | Per tick | Per day | Per 30 days |
| --- | ---: | ---: | ---: |
| Reads | 1 656 | 476 813 | 14.30 M |
| Writes | 40.1 | 11 549 | 0.35 M |
| Lists | 5.1 | 1 469 | 0.044 M |
| Worker invocations | ~1 | ~288 | 8 640 |

14.3 M reads from this cron **alone** already exceeds the 10 M account-wide
included read quota. Whether the invoice already shows overage depends on the
rest of the account (BOOKING_KV, other workers). That remainder was not
re-measured for this note.

### Expected lasting usage after `!done` (idle, no new rides)

| Op | Per tick | Per 30 days |
| --- | ---: | ---: |
| Reads | 0 event values | 0 from this scan |
| Writes | 0 | 0 |
| Lists | 1 due prefix | 8 640 |
| Deletes | 0 | 0 |
| Worker invocations | 1 cron | 8 640 |

A real new ride adds: 1 append arm-write, 1 due list, 1 event read, status /
marker writes only when the official state changes, plus BOOKING_KV only if a
draft is built (P0 memo). A waiting arrival adds one future marker and one
recheck every 5 minutes **only after its due-at**, not a full history scan.

### Temporary migration (first armed Fluxidi tick)

Live Fluxidi prefix is ~1 552 events. First tick may read those once, arm
markers only where `computeChironReconcileDueAtMs` is non-null (synced history
gets no marker), write one per-scope mig doc and `!done`. That is a one-off,
not a monthly run-rate.

## 6. Rollout and rollback

**Not live-verified:** first-tick migration on production KV, post-deploy
COMPLIANCE_KV analytics, account-wide invoice, delayed KV list visibility of
new markers.

### Rollout

1. Keep `CHIRON_CRON_ENABLED` unset (cron stays on).
2. `wrangler versions upload` from this worktree (same bindings as live:
   `COMPLIANCE_KV`, `BOOKING_KV`, ACC URL, no new secrets).
3. Deploy to a small percentage, then 100%, only when an operator asks.
4. Watch one tick for `[CHIRON_DUE_INDEX]` and the scoped
   `[CHIRON_AUTO_RECONCILE]` line. Expect a one-shot Fluxidi scan, then idle
   ticks with `due_selected=0` and no `compliance_event_v1/` list.
5. Do not delete testdossiers to improve the graph.

### Rollback (safe with the new index)

- Redeploy live `85f70b04` (or `16d11eeb`). The old worker ignores
  `chiron_reconcile_due:*` keys; they are disposable hints.
- Authoritative state remains `compliance_event_*` + export-status docs.
- To **resume this patch later** after the old cron has run: delete only
  `chiron_reconcile_due:v1:!done`, `chiron_reconcile_due_mig:v1`, and
  `chiron_reconcile_due_mig:v1/tenant/…/company/…`. Do **not** delete
  compliance events. The next P1 tick remigrates from the authoritative
  records.
- Overlapping ticks: duplicate markers are retired; the duplicate guard
  still blocks a second Chiron submit.

## 7. What is still live

Production is still the P0 BOOKING_KV repair. COMPLIANCE_KV still full-scans
every five minutes until this branch is deployed.
