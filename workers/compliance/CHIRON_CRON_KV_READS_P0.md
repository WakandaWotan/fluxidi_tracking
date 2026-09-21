# CHIRON-CRON-KV-READS-P0 — repair of the Chiron cron KV read amplification

Prepared 2026-09-21. **Nothing is deployed and no live setting is changed by this
branch.** The Chiron cron keeps running exactly as it does today until someone
deploys this deliberately.

## 1. Provenance of the baseline

The repair is based on the source of the worker that is **actually live**, not on
the checkout in the main workspace.

| Fact | Value |
| --- | --- |
| Live worker | `fluxidi-compliance-api` |
| Live version | `16d11eeb-9f81-48a5-adb7-d98dbd8dc50f` (version number 89) |
| Version created | 2026-09-19T20:15:58Z |
| Deployed 100% | 2026-09-19T20:16:25Z, `workers/triggered_by: deployment` |
| Deploy annotation | `chiron plate normalization restored (release 331ffa95); rollback c6aa5380` |
| Source commit | `331ffa95` "fix(chiron): restore the production plate normalization and stop withholding rides" |
| Cron trigger | `*/5 * * * *`, created 2026-08-30T05:54:00Z, last modified 2026-08-30T06:02:01Z |
| Bundle read read-only | 2026-09-21, 422 859 JS chars, SHA-256 `e18242784a21bbb9e0ad182940fd6352a255386007ec5678ace4b7724c0dadbe` |

### Verification that `331ffa95` really is the live bundle

Bundle and source were compared per function after removing only bundler
artefacts (comments, `__name()` registrations, `undefined` → `void 0`, trailing
commas, prettier line wrapping), applied identically to both sides:

- 11 of 11 reconcile/cron/leg-type functions **byte-identical**, including
  `_chironCronReconcileAllScopesBestEffort`, `_chironAutoReconcileScopeBestEffort`,
  `_chironBuildOfficialDraftForSingleEvent`, `_chironLoadBookingLegTypeMap`,
  `_chironLoadScopedHydrationCache`, `_chironBuildBatchRitStatusIndex`,
  `_chironBuildBatchTrustedRideHydrationIndex`.
- 308 of 309 top-level function names present in both. The single absentee,
  `_chironResolveAssignedVehicleId`, is defined and never called in `331ffa95`,
  so esbuild tree-shakes it. No live function is missing from the source.
- Marker counts equal on both sides: `CHIRON_CRON_MAX_SCOPES_PER_TICK` 3/3,
  `CHIRON_AUTO_RECONCILE_MAX_PROCESS` 4/4, `CHIRON_AUTO_RECONCILE_MAX_WINDOW_MS`
  3/3, `CHIRON_EXPORT_LIST_SCAN_CAP` 2/2, `ch1211_assigned_vehicle_plate_invalid`
  2/2, `[CHIRON_CRON_RECONCILE]` 2/2.

### Why the main workspace must not be used as a release

`D:\Projecten\_flutter_work\fluxidi_tracking` is a detached checkout of
`4f61fa94` (2026-08-10). Its `workers/compliance/fluxidi_compliance_worker.js`
has **no `scheduled` handler and no cron reconcile at all**. Deploying it would
silently remove the Chiron drain. Work happens in a dedicated worktree instead:

```
worktree : D:\Projecten\_flutter_work\_fluxidi_chiron_cron_fix
branch   : fix/chiron-cron-kv-reads-p0
base     : 331ffa95
```

## 2. What was wrong

Per tick the cron lists up to 25 armed scopes and, per scope, reads every
compliance event in the 14-day window (`COMPLIANCE_KV`), then processes at most
`CHIRON_AUTO_RECONCILE_MAX_PROCESS = 20` of them. Two values were recomputed
inside that loop even though they cannot change within a pass:

1. the scoped hydration triple — business profile, fleet, driver index: 3
   `BOOKING_KV` reads **per considered event**;
2. the booking leg-type map — one `BOOKING_KV` read per distinct legless booking
   in the whole window, rebuilt **per considered event**.

Cost per pass was `considered × (3 + distinct_legless_bookings)`.

## 3. The patch

Three commits on `fix/chiron-cron-kv-reads-p0`:

| Commit | What |
| --- | --- |
| `e215384f` | `cherry-pick -x 6dd68220` — pass-scoped preload envelope, frozen, keyed by tenant/company **and** by the exact `contextEntries` array. Any mismatch falls back to the original per-event load. Ships its own 650-line suite. |
| `12f54cc8` | the leg-type map becomes an on-demand per-pass memo: one read per booking that actually reaches a draft build, at most once per booking per pass, misses recorded so they are never re-read. |
| `bb9b3b3c` | `chironCronEnabled(env)` — explicit, documented on/off gate, evaluated before any KV access. |

`e215384f` needed one conflict resolution: the deployed line added `nowMs` to the
`_chironAutoSubmitOneEvent` call site where the August patch added `scopePreload`.
Both are kept.

### Why narrowing the leg fetch is safe

Leg stamping only reaches a Chiron payload through `_chironBuildBatchRitStatusIndex`
and `_chironBuildBatchTrustedRideHydrationIndex`. Both are keyed per ritnummer and
per `booking_id`, and every consumer looks up **only the target event's own key**
(`batchRitStatuses.get(context.ritnummer)`, `_chironResolveTrustedRideForDraft`).
An unstamped entry of another booking can therefore never change the payload built
for a candidate. Sibling events of the same booking share one memo entry, so
roundtrip inference for legless `ride_start` events is unaffected.

### What is deliberately untouched

Candidate selection, the newest-booking-first ordering (which exists so a long
already-synced history cannot starve recent rides), departure-before-arrival
within a booking, the `CHIRON_AUTO_RECONCILE_MAX_PROCESS` budget, the
already-synced budget exemption, the duplicate guard, definitive-failure stop,
the 10-minute cooldown and the 15-second throttle marker.

### The gate

| `CHIRON_CRON_ENABLED` | Behaviour |
| --- | --- |
| unset, empty, or any other value | **enabled** — identical to production today |
| `0`, `false`, `off`, `no` (case/space-insensitive) | disabled: the tick returns before any KV access, logs `[CHIRON_CRON_RECONCILE][SKIPPED_DISABLED]`, costs zero reads |

Scope is the scheduled drain only. Status-poll reconcile, append-time
auto-submit and `/admin/chiron/testflow/auto-reconcile` keep working while it is
off. Parked candidates are picked up unchanged by the next enabled tick.
`wrangler.toml` documents the variable but leaves it commented out, so the live
configuration is untouched.

## 4. Measured result

Hermetic bench, in-memory KV with counted operations, outbound `fetch` trapped,
same fixture through both builds. Production-shaped: 317 distinct bookings, 634
events, 20 processed — chosen because it reproduces the measured live cost of
~6 400 `BOOKING_KV` reads per tick (77 000/hour ÷ 12 ticks).

| Metric, one scope pass | Live `331ffa95` | This branch |
| --- | --- | --- |
| `BOOKING_KV` reads | **6 400** | **13** |
| of which hydration | 60 | 3 |
| of which booking records | 6 340 | 10 |
| `COMPLIANCE_KV` reads | 696 | 696 (unchanged) |
| scanned / considered / processed | 634 / 20 / 20 | 634 / 20 / 20 (identical) |
| submitted / skipped / failed | 0 / 20 / 0 | 0 / 20 / 0 (identical) |
| outbound provider calls | 0 | 0 |

Two scopes in one tick: 1 720 → 26 `BOOKING_KV` reads, zero cross-scope reads in
both builds.

Projection at 288 ticks/day, one armed scope: **1 843 200 → 3 744**
`BOOKING_KV` reads/day. The remaining `COMPLIANCE_KV` event scan is unchanged at
roughly 1 580 reads/tick (~455 000/day) — see section 6.

## 5. Test results

```
node --test "workers/compliance/*.test.mjs"

baseline 331ffa95  : 330 tests, 330 pass, 0 fail
this branch        : 357 tests, 357 pass, 0 fail   (+14 cherry-picked, +13 new)
```

The 330 pre-existing tests cover the behaviour this repair must not break:
successful and failed submits, OAuth failure retryability, the duplicate guard
for `synced` / `verification_required` / `pending`, definitive-rejection
handling, bounded and throttled reconcile, offline arrival recovery, sequence
recovery and the plate rules. They run unmodified.

New in `chiron_cron_kv_reads_p0.test.mjs` (13 tests):

1. reads follow the processed events, not the window size (240 candidates, reads
   bounded by the process budget, window not pre-read);
2. a booking miss is not re-read for sibling events in the same pass;
3. nothing is memoized across passes;
4. official draft **byte-identical** to the unrestricted whole-window map, for
   every event in a fixture where booking records really resolve a leg type;
5. topping up every event yields exactly the unrestricted map;
6. two scopes in one tick never read each other's bookings, each loads its own
   profile exactly once;
7. a scope-A preload never leaks into a scope-B event and the foreign event never
   writes into scope A's memo;
8. candidate selection, ordering (newest booking first, departure before arrival)
   and the process budget are identical with and without resolvable leg records;
9. candidates beyond the budget are still there on the next tick;
10. gate defaults to enabled; only explicit off values disable it;
11. a disabled tick costs zero list, zero `COMPLIANCE_KV` read, zero `BOOKING_KV`
    read;
12. the gate does not block the status-poll / admin reconcile path;
13. an enabled tick still drains every armed scope.

No test performs a real Chiron submission: outbound `fetch` is trapped and
asserted to have been called zero times.

## 6. The remaining wide scan — investigated, deliberately not changed

What still happens every tick: `listScopedComplianceEventKeys` walks the whole
scoped key set (cap `CHIRON_EXPORT_LIST_SCAN_CAP = 10 000`) and value-reads every
event from `COMPLIANCE_KV` so the batch indexes can see sibling events. That is
~1 580 reads/tick on the live shape and it is the reason `contextEntries` exists.

A crash-safe due-index replacement is **already written and tested** in git but
was never merged into the deployed release line:

| Commit | Branch | What |
| --- | --- | --- |
| `068df75a` | `fix/chiron-compliance-due-index-p0` | replaces the full-history scan with ordered `COMPLIANCE_KV` due markers, migrating legacy events 25 per tick |
| `1b07e2e8` | `fix/chiron-missing-live-ride-p0` | newest-first due-at-0 selection plus `pending_build` cooldown, so historical retries cannot starve live exports |
| `74479590` | `fix/chiron-terminal-cleanup-p0` | persists a candidate-to-official pointer so synced rides leave the due index instead of being reselected forever |

This is a scan-strategy change with its own migration path, so per the brief it is
**not** part of this repair: the on-demand memo already removes 99.8% of the
`BOOKING_KV` cost, which is the reported problem. Treat the due-index series as a
prepared phase 2 for the `COMPLIANCE_KV` side, to be rebased onto the live line
and re-verified on its own.

## 7. Rollout

Read-only re-verification first, because the live version has already moved twice
since this analysis started (booking-api `v1159` on 21 Sept 07:34Z).

1. Confirm the live version is still the one this branch is based on:
   ```
   npx wrangler versions list --name fluxidi-compliance-api
   npx wrangler deployments list --name fluxidi-compliance-api
   ```
   Expect version `16d11eeb-9f81-48a5-adb7-d98dbd8dc50f` at 100%. If it is not,
   stop and rebase this branch onto the source of whatever is live.
2. Build without shipping and confirm the diff is only this repair:
   ```
   cd workers/compliance
   npx wrangler deploy --dry-run --outdir ..\..\_dryrun_compliance
   ```
3. Upload a version **without** routing traffic to it, then promote explicitly:
   ```
   npx wrangler versions upload --name fluxidi-compliance-api
   npx wrangler versions deploy <new-version-id>@100 --name fluxidi-compliance-api --yes
   ```
4. Watch for one full tick cycle (≥ 10 minutes):
   - `[CHIRON_CRON_RECONCILE] scopes= ran= throttled= failed=` — `ran` and
     `failed` must match the pre-deploy pattern;
   - `[CHIRON_AUTO_RECONCILE] ... scanned= considered= submitted= skipped= failed=`
     — `scanned` and `considered` must be unchanged, `submitted` must not drop to
     zero if it was non-zero before;
   - the `fluxidi-bookings` KV read graph must fall from ~77 000/hour towards a
     few hundred per hour.
5. Do not touch `CHIRON_CRON_ENABLED`. It stays unset, which keeps the cron on.

## 8. Rollback

- **Code:** `npx wrangler versions deploy 16d11eeb-9f81-48a5-adb7-d98dbd8dc50f@100 --name fluxidi-compliance-api --yes`.
  No KV migration is needed: this branch writes no new key shapes and changes no
  stored document, so a rollback needs no data repair.
- **Emergency brake without a code change:** add `CHIRON_CRON_ENABLED = 0` in the
  Cloudflare dashboard (Worker → Settings → Variables). That publishes a new
  version of the same code with the cron off, stops all cron KV cost immediately,
  and leaves status-poll, append-time auto-submit and the admin reconcile route
  working. Remove the variable to resume.
- Both paths leave candidates parked in the existing markers; the next enabled
  tick resumes with unchanged ordering, retries and cooldowns.

## 9. Out of scope

The customer-app migration is untouched. No live setting, trigger, secret or KV
value was modified while preparing this branch.
