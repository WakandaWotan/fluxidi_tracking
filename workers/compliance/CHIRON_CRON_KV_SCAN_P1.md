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
| This worktree HEAD | `fix/chiron-compliance-due-index-p1` (P1 + recovery follow-up; not deployed) |
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
2. **Cron after `!done`**: due-prefix list (max 20 due events, newest-first)
   plus a cheap `tenant:` connection list so a later-enabled company without a
   per-scope mig doc is still scanned. Finished history is not value-read.
3. **Before `!done`**: process any already-due markers, then **one** armed
   scope page of 80 event keys per tick. `!done` is written only when every
   armed scope has `completed=true` and no page failed. A full 1552-event
   prefix therefore resumes across ticks instead of running in one invocation.
4. **Due-marker write paths:** new canonical+date append; date-index
   recovery; legacy single write; append dedup **confirm** if the marker is
   missing; `_chironWriteExportStatus` via `applyChironDueMarkerTransition`;
   paired-arrival re-arm after departure success / already_synced; scoped
   migration pages. Pure dedup without a missing marker does not add a
   second event. Sibling context is one keyed canonical get.
5. **Writes only when functional fields change.** Waiting and already-synced
   counter repair skip identical documents. Throttle stamp skipped when still
   fresh.
6. **Gated / disabled connections** exit before the event scan. Settings are
   not changed. Testdossiers are not deleted.
7. **Waiting arrivals** stay on a 5-minute due-at. A successful or
   already-synced departure re-arms the paired arrival at due-at-0.
8. **BOOKING_KV P0 is kept**: on-demand leg memo + `CHIRON_CRON_ENABLED`.
9. **Bounded unmarked-event recovery** (no full five-minute history scan):
   each cron tick drains `chiron_reconcile_wakeup:v1:` and walks date-index
   prefixes from a durable per-scope watermark
   (`chiron_reconcile_recover:v1/tenant/…/company/…`). Selection is
   oldest-first, max 20 keys and two prefix lists per tick. The watermark
   starts at the scope's `completed_at` minus 2 h (or `now − 2 h` while
   migrating) and only advances after those keys were examined. A sliding
   30 min / “20 newest” window is **not** used as the floor, so newer keys
   and a clock jump cannot hide an unexamined event. A P1 append still
   writes the wakeup hint before the due marker. Events older than the
   initial watermark still remigrate via the existing `!done`/mig-key
   delete.

Unchanged rules: newest-booking-first, departure before arrival inside one
booking, process budget 20, already-synced / waiting do not burn the budget,
duplicate guard, definitive cooldown / max attempts, company isolation.

## 4. Hermetic proof (no live Chiron, booking or payment)

```
node --test workers/compliance/chiron_cron_kv_scan_p1.test.mjs
# 28 tests, 28 pass, 0 fail
# cwd: D:\Projecten\_flutter_work\_fluxidi_chiron_due_index
```

Test 21 still proves a later cron can arm a stored markerless event when
few newer keys exist. It does **not** prove the “20 newest in a recent
window” case. That remaining gap is tests 22 and 23 (one pinned clock for
`nowMs` and `Date.now()`):

* **22:** one markerless event, no wakeup / auto-submit / producer retry,
  25 newer unmarked keys, and a fresh armed ride on every tick. The older
  event is found (`recovered_unmarked=20`, `recover_examined=20` on the
  first tick). Armed new work still runs (`due_selected=20`). No remigration.
* **23:** the same markerless persist sits through an interrupt of
  2 h 31 min (longer than the 2 h catch-up and the old 30 min window).
  After resume the event is found on the first bounded tick
  (`recovered_unmarked=1`, `recover_examined=1`) while `!done` and the
  per-scope mig key stay in place.

P1 scenarios in `chiron_cron_kv_scan_p1.test.mjs` (counted KV ops per pass):

| Scenario | Events processed | Lasting COMPLIANCE_KV |
| --- | --- | --- |
| Idle after `!done`, 40 historical events | 0 | 1 due list, 0 event reads, recover cursor write only, 0 provider |
| New ride + 40 history | 1 | 1 event read (the new key only) |
| Retryable fail | due-at 0 | stays selectable |
| Definitive fail (young) | future due-at | not selected this tick |
| Waiting arrival | future due-at = last + 5 min | departure success writes due-at-0 |
| Restart after `!done` | same due marker | no full-scope `compliance_event_v1/tenant/…/company/…/` list |
| Overlapping duplicate markers | 1 event | extra marker deleted |
| Two companies | A only | B event never read |
| Already-synced counters | — | no rewrite when rit already tracked |
| Gated `enabled=false` | 0 | no event list/read |
| First-tick migration vs later | history read once | later tick event-reads << history |
| `CHIRON_CRON_ENABLED=0` | 0 | 0 lists, 0 reads, 0 writes |

Counted comparison from `node workers/compliance/chiron_cron_kv_scan_p1_bench.mjs`
(outbound fetch trapped). The **old 80-event bench is not the live plateau**:
that fixture has no export-status docs, so the old scan rewrites counters,
waiting-shaped statuses and due markers (202 writes / 40 deletes). Live
COMPLIANCE_KV over 11h50 was **1 656 reads / 40 writes / 5.1 lists / 0 deletes**
per 5 min — reads of already-synced history, not a delete storm.

| Pass | Reads | Writes | Lists | Deletes | Event value reads |
| --- | ---: | ---: | ---: | ---: | ---: |
| Old full scoped scan, every tick (unsynced 80) | 344 | 202 | 1 | 40 | 80 |
| Migration (unsynced 80, first tick) | 346 | 204 | 6 | 40 | 80 |
| Quiet, no due work (80 synced, after `!done`) | **2** | **0** | **5** | **0** | **0** |
| Quiet repeat tick | 2 | 0 | 5 | 0 | 0 |
| 3 waiting arrivals, migration | 346 | 87 | 6 | 20 | 80 |
| 3 waiting arrivals, T+60 s (not yet due) | **2** | **0** | **5** | **0** | **0** |
| 3 waiting arrivals, first due-at (T+5 min) | 33 | 18 | 5 | 6 | 3 |
| 3 waiting arrivals, second due-at (T+10 min) | 27 | 6 | 5 | 6 | 3 |
| New work after quiet `!done` | 17 | 7 | 5 | 2 | 2 |
| Scale first tick (1552 + 80) | 348 | 202 | 8 | 40 | 80 |
| New ride during migration | 439 | 227 | 8 | 80 | 101 |
| Scale complete | **21 ticks, 547 ms, examined 1633 ≥ 1632, `migration_done=true`** | | | | |

Scale first-tick KV ops = **598** (Workers Paid subrequest budget 1000). Cron
migrates **one** armed scope page of 80 per tick. 1552+80 keys ⇒ 21 ticks,
`!done` only on the last tick, `finished=true`. A timeout with partial
counters is not treated as success.

The extra lasting lists are the due prefix, `tenant:`, wakeup prefix, and
one current date-index **seek** prefix (a first catch-up tick may list two
seek prefixes). They are not a full-scope history list. Quiet ticks still
do **0** event value reads. The recover watermark is written once while
empty prefixes are walked, then **0** writes.

T+60 s with three waiting arrivals is **not** a due-at: `due_selected=0`.
The same fixture at T+5 min and T+10 min selects those three events
(`due_selected=3`, 3 event reads). The second due-at restamps
`last_attempt` to the simulated tick because process writes use `Date.now()`;
the 5-minute cadence is otherwise unchanged.

A new ride written while the 1552-key migration is still running is recovered
and selected on the next tick (`due_selected=1`, `recovered_unmarked=1`,
`waited_for_full_history=false`). New work does not wait for `!done`.

Temporary migration still pays one scoped page per tick. That cost is
one-shot per company, not per five minutes.

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

Counted after the recover watermark exists (second quiet tick):

| Op | Per tick | Per 30 days |
| --- | ---: | ---: |
| Reads | 3 (connection + per-scope mig + recover cursor) | ~26k |
| Writes | 0 | 0 |
| Lists | 4 (due, `tenant:`, wakeup, 1 current seek) | 34 560 |
| Deletes | 0 | 0 |
| Worker invocations | 1 cron | 8 640 |

First quiet tick after `!done`: **3 reads / 1 recover-cursor write / 5 lists
/ 0 deletes**. That write is the watermark, not an event rewrite.

### Unmarked-event recovery (tests 22–23, same clock)

| Pass | Reads | Writes | Lists | Deletes | Recovered / examined |
| --- | ---: | ---: | ---: | ---: | ---: |
| >20 newer keys + new armed work same tick | 284 | 141 | 5 | 40 | 20 / 20 (old event in the oldest-first batch; process budget 20) |
| Resume after 2 h 31 min interrupt, one markerless event | 18 | 8 | 5 | 2 | 1 / 1 |
| Lasting idle after watermark | 3 | 0 | 4 | 0 | 0 / 0 |

Recovery work itself is the watermark write plus at most 20 event examines
and two seek lists. The 284/141 tick is mostly the existing due-index
processor handling the newly armed plus already-due work, not a history
rescan. No remigration keys were deleted.

A real new ride adds: 1 append arm-write, 1 due list, 1 event read, status /
marker writes only when the official state changes, plus BOOKING_KV only if a
draft is built (P0 memo). A waiting arrival adds one future marker and one
recheck every 5 minutes **only after its due-at**, not a full history scan.

### Temporary migration (Fluxidi ~1 552 events)

Not one tick. Cron reads **80** event keys per armed scope per tick, arms only
where `computeChironReconcileDueAtMs` is non-null (synced history gets no
marker), and writes `!done` only after every armed scope page succeeded.
Hermetic 1552+80: first tick 598 KV ops, **21 ticks to `!done`**, examined
1633 keys, `finished=true`. One-off, not a monthly run-rate.

## 6. Rollout and rollback

**Not live-verified:** first production migration pages, post-deploy
COMPLIANCE_KV analytics, account-wide invoice, delayed KV list visibility of
new markers.

### Mixed versions

Cloudflare gradual-deployment docs (retrieved 2026-09-21) split **HTTP**
traffic by percentage and warn about version skew. They do **not** pin Cron
Triggers to a single version. Live `85f70b04` does not write due markers.
If that HTTP handler still stores events after P1 has written `!done`, the
durable recover finds them from the per-scope watermark (test 21–23),
including after a pause longer than the old 30 min / 2 h windows. Events
older than the initial watermark (`completed_at − 2 h`) still need
remigration. **Do not use a percentage rollout.**

### Rollout (100% cutover only)

1. Keep `CHIRON_CRON_ENABLED` unset (cron stays on).
2. `wrangler versions upload` from this worktree (same bindings as live:
   `COMPLIANCE_KV`, `BOOKING_KV`, ACC URL, no new secrets).
3. `wrangler versions deploy` the new version to **100%**. No 1%/10% split.
4. Watch `[CHIRON_DUE_INDEX]` / `[CHIRON_AUTO_RECONCILE]`. Expect ~20 Fluxidi
   pages (80 keys, one scope per tick), `migration_done=false` until the last
   armed scope completes, then idle ticks with `due_selected=0` and no
   full-scope `compliance_event_v1/tenant/…/company/…/` history list. Recent
   timestamp-seek lists are expected and stay empty when there is no new work.
5. Do not delete testdossiers to improve the graph.

### Rollback (primary = current live)

- Primary rollback is the **immediately preceding production version**:
  `85f70b04-adf9-474e-86bb-279ac6f35917` (BOOKING_KV on-demand memo).
- `16d11eeb` is **not** an equivalent rollback: it reintroduces the
  BOOKING_KV window scan.
- The old worker ignores `chiron_reconcile_due:*` keys; they are disposable
  hints. Authoritative state remains `compliance_event_*` + export-status.
- To **resume this patch later** after `85f70b04` has written new events
  without markers: delete only `chiron_reconcile_due:v1:!done`,
  `chiron_reconcile_due_mig:v1`, and
  `chiron_reconcile_due_mig:v1/tenant/…/company/…`. Do **not** delete
  compliance events. The next P1 tick remigrates from the authoritative
  records. Hermetic proof: P1 → old-style put without marker → delete those
  three key classes → P1 finds the event (`chiron_cron_kv_scan_p1.test.mjs`
  test 18).
- Overlapping ticks: duplicate markers are retired; the duplicate guard
  still blocks a second Chiron submit.

## 7. What is still live

Production is still the P0 BOOKING_KV repair (`85f70b04` @ 100%).
COMPLIANCE_KV still full-scans every five minutes until this branch is
deployed. The other namespace graph (~4.35 M reads / 178 k lists) is
BOOKING_KV and is out of this patch's scope.

## 8. Review-point closeout

| # | Point | Evidence / repair | Remaining limit |
| --- | --- | --- | --- |
| 1 | New events after `!done`; later-enabled company | Append (canonical, date recovery, legacy) arms then confirms. Status writes use `applyChironDueMarkerTransition`. Global `!done` no longer skips an unmigrated scope. Tests 13–14. | Company that was migrated, then written only by old HTTP, needs remigration or append retry. |
| 2 | Event saved, marker missing; no producer retry | Durable oldest-first watermark, 20 keys / 2 prefix lists per tick. Test 21: basic later-cron find. Test 22: found despite 25 newer keys and new work each tick. Test 23: found after a 2 h 31 min interrupt without remigration. | Date keys older than the initial watermark (`completed_at − 2 h`) still remigrate. Not a full 5-minute history scan. |
| 3 | Waiting arrivals over full cycles | T+60 s: 2/0/5/0, `due_selected=0`. T+5 min and T+10 min: `due_selected=3`, 3 event reads. Quiet synced idle stays 2/0/5/0. | Process stamps `last_attempt` with `Date.now()`; the bench restamps to the simulated tick for the second due-at. |
| 4 | ~1552 scale | One 80-key page, one armed scope per tick. Scale run **finished**: 21 ticks, 547 ms, examined 1633 ≥ 1632, `migration_done=true`. New ride during migration: `due_selected=1` before `!done`. | ~100 minutes at `*/5` for 1552 keys. Worker 1000-subrequest budget is the reason. |
| 5 | Mixed versions | Gradual-deploy docs do not pin cron. Old HTTP has no markers. **100% only.** | Not live-verified on a split deploy (intentionally unused). |
| 6 | Rollback / remigrate | Primary rollback `85f70b04`. `16d11eeb` rejected. Test 18 remigrates an old-writer event without deleting compliance events. | Operator must delete the three mig/`!done` keys to resume P1 after rollback. |

