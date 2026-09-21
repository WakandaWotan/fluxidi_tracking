# CHIRON-CRON-KV-READS-P0 — repair of the Chiron cron KV read amplification

Prepared and **deployed to production on 2026-09-21**. See section 10 for the
deployment record and the measured live result.

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

Comparing a bundle against unbundled source is unreliable: esbuild rewrites inner
arrow functions into `__name(...)` wrappers, so normalisation can never be made
watertight in that direction. The check is therefore **bundle against bundle**,
same toolchain (wrangler 4.61.0, `deploy --dry-run`):

| Artefact | Normalised SHA-256 (16) |
| --- | --- |
| live download of version 89 | `852a6f752c8c7e9e` |
| local build of `331ffa95` | `852a6f752c8c7e9e` |

Whole-body identical after removing bundler artefacts only, and 308 of 308
functions identical with nothing present on only one side. The live worker is a
build of `331ffa95`.

The same comparison against the build of this branch is the pre-deploy surface:
303 of 308 functions identical, **0 removed**, 4 added
(`_chironBuildScopePreload`, `_chironPreloadForScope`,
`_chironEnsureBookingLegTypeForEvent`, `chironCronEnabled`) and exactly 5 changed
(`_chironLoadBookingLegTypeMap`, `_chironBuildOfficialDraftForSingleEvent`,
`_chironAutoSubmitOneEvent`, `_chironAutoReconcileScopeBestEffort`,
`_chironCronReconcileAllScopesBestEffort`).

Note for anyone re-running this: a naive extractor that looks for the first `{`
after a function name stops inside a default parameter such as
`options = {}` and then only compares signatures, which silently hides real
differences. The extractor must walk the parameter list to its matching `)`
first.

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

The customer app is untouched. No trigger, secret or KV value was modified.

## 10. Deployment record — 2026-09-21

### Pre-flight

| Check | Result |
| --- | --- |
| Newest version before deploy | `16d11eeb-9f81-48a5-adb7-d98dbd8dc50f` at 100%, unchanged since 19 Sept 20:16Z — no newer compliance fix existed, so nothing had to be rebased |
| Live bundle == build of `331ffa95` | yes, same normalised SHA `852a6f752c8c7e9e`, 308/308 functions identical |
| Deploy surface (live vs pending build) | 303/308 identical, 0 removed, 4 added, 5 changed |
| Bindings in the dry run | `COMPLIANCE_KV`, `BOOKING_KV`, `CHIRON_EXPORT_MODE`, `CHIRON_EXPORT_BASE_URL` — identical to live, both secrets untouched |
| `CHIRON_CRON_ENABLED` | deliberately NOT set, so the cron stays enabled |

### Deploy

```
wrangler versions upload   -> 85f70b04-adf9-474e-86bb-279ac6f35917
                              tag chiron-cron-kv-reads-p0, created 12:38:18Z
wrangler versions deploy 85f70b04...@100
                           -> deployment 12:38:44Z, "rollback 16d11eeb-..."
```

**Rollback target: `16d11eeb-9f81-48a5-adb7-d98dbd8dc50f`.** No KV migration is
needed for a rollback; this version writes no new key shapes.

### Post-deploy state

- cron schedule still `*/5 * * * *`, `modified_on` still 2026-08-30T06:02:01Z —
  untouched. `wrangler versions upload/deploy` does not manage triggers.
- bindings unchanged: `BOOKING_KV`, `COMPLIANCE_KV`,
  `CHIRON_CREDENTIALS_ENCRYPTION_KEY`, `COMPLIANCE_ADMIN_TOKEN`,
  `CHIRON_EXPORT_BASE_URL`, `CHIRON_EXPORT_MODE`. Nothing added or dropped.
- `observability.logs.enabled` remains `true` with `persist: true`. The deploy
  output line `observability: enabled: false` refers to the separate top-level
  traces switch, which was already false.
- handlers still `scheduled` + `fetch`.

### Measured live result — `fluxidi-bookings` reads per 5-minute cron cycle

| 5-min bucket (UTC) | BOOKING_KV reads | COMPLIANCE_KV reads |
| --- | ---: | ---: |
| 12:00 | 6 588 | 1 670 |
| 12:05 | 9 080 | 1 560 |
| 12:10 | 8 076 | 1 533 |
| 12:15 | 7 794 | 1 735 |
| 12:20 | 8 375 | 1 580 |
| 12:25 | 8 183 | 1 761 |
| 12:30 | 8 397 | 1 560 |
| 12:35 | 8 256 | 1 700 |
| **deploy 12:38:44Z** | | |
| 12:40 | **11** | 1 691 |
| 12:45 | **0** | (tick had no draft build needing a booking) |
| 12:50 | **11** | 1 733 |
| 12:55 | **11** | 1 609 |
| 13:00 | **11** | 1 492 |
| 13:05 | **11** | 1 787 |

Eight pre-deploy cycles average **8 094** reads; six post-deploy cycles sit at
**11 or 0**. That is a **~736x** reduction, 99.86%. Projected over 288 cycles:
**2.33M/day to ~3.2k/day**.

`COMPLIANCE_KV` is deliberately unchanged at ~1 600 reads/cycle, which is also the
proof that the event scan and candidate selection were not altered.

### Processing correctness over consecutive cycles

Identical on every observed tick (12:45:03, 12:50:03, 12:55:03 and on), all on
version `85f70b04`:

```
[CHIRON_AUTO_RECONCILE] scanned=1552 considered=21 submitted=0 waiting=3 skipped=3 failed=0 source=cron
[CHIRON_CRON_RECONCILE] scopes=4 ran=2 throttled=2 failed=1 source=cron
```

- `outcome: ok`, zero exceptions on every tick.
- `scanned=1552` is consistent with the unchanged ~1 600 `COMPLIANCE_KV` reads
  per cycle, so the full scan still happens and no candidate is skipped.
- `submitted=0` with `[CHIRON_AUTO_SUBMIT][ALREADY_SYNCED_COUNTER_REPAIR]` per
  already-synced ritnummer: the duplicate guard recognises every synced ride and
  nothing is re-POSTed. **No duplicate submissions, and no submission was
  triggered artificially.**
- `[CHIRON_AUTO_SUBMIT][WAITING] ... paired_dep_state=failed` for three rides:
  pre-existing state, arrivals correctly parked behind a failed departure.
- `failed=1` at cron level is constant on every tick and the per-scope pass
  reports `failed=0`. It is one of the four scopes bailing on its own routing
  gate before the pass logs, which happens before any code this branch touches.

### Evidence gap

The wrangler OAuth token has no Workers Observability read scope
(`/workers/observability/telemetry/query` returns 403), so pre-deploy log lines
could not be retrieved for a log-to-log comparison. The before/after evidence is
therefore the KV analytics (which do cover both periods) plus live `wrangler
tail` on the new version. `scanned` / `considered` have no pre-deploy log
counterpart; the unchanged `COMPLIANCE_KV` read rate stands in for it.

## 11. Source line

`release/compliance-worker-d03` is the line the live worker is built from
(`origin/main` is a January baseline, 1 808 commits behind, and does not contain
the deployed compliance state at all). The branch was fast-forwarded onto that
release line and both were pushed, so every future release cut from it carries
this fix. Advancing `origin/main` is a pre-existing, unrelated divergence and was
deliberately not attempted here.
