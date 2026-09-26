import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { __testInternals as api } from './fluxidi_compliance_worker.js';
import {
  armChironDueMarker, buildChironDueMarkerKey, applyChironDueMarkerTransition,
  ChironDueIndexTestCrash, markChironDueMigrationComplete, buildChironScopeRecoverKey,
  armChironWakeupHint, CHIRON_RECONCILE_DUE_PREFIX, CHIRON_RECONCILE_WAKEUP_PREFIX,
} from './chiron_reconcile_due_index.js';

const NOW = Date.parse('2026-09-26T06:25:20.801Z');
const T = 'marker_test', C = 'company';
const oldDue = [1787570755662, 1787571055661, 1787571055661, 1790028669013];
let savedFetch;
before(() => { savedFetch = globalThis.fetch; globalThis.fetch = async () => { throw new Error('network forbidden'); }; });
after(() => { globalThis.fetch = savedFetch; });

function harness() {
  const rows = new Map(), ops = [];
  const faults = { get: null, put: null, delete: null };
  const kv = {
    async get(key) {
      ops.push(['get', key]);
      if (faults.get === key) throw new Error('read failed');
      return rows.get(key)?.value ?? null;
    },
    async put(key, value, options = {}) {
      ops.push(['put', key]);
      if (faults.put === key) throw new Error('persist failed');
      rows.set(key, { value, metadata: options.metadata });
    },
    async delete(key) {
      ops.push(['delete', key]);
      if (faults.delete === key) throw new Error('retirement interrupted');
      rows.delete(key);
    },
    async list({ prefix = '', limit = 1000, cursor } = {}) {
      ops.push(['list', prefix]);
      const keys = [...rows.keys()].filter(k => k.startsWith(prefix)).sort();
      const offset = Number(cursor) || 0, page = keys.slice(offset, offset + limit);
      const list_complete = offset + page.length >= keys.length;
      return { keys: page.map(name => ({ name, metadata: rows.get(name).metadata })), list_complete,
        cursor: list_complete ? undefined : String(offset + page.length) };
    },
  };
  const env = { COMPLIANCE_KV: kv, BOOKING_KV: { async get() { throw new Error('unexpected BOOKING read'); } },
    CHIRON_EXPORT_MODE: 'test', CHIRON_EXPORT_BASE_URL: 'https://mow-acc.api.vlaanderen.be/chiron/taxirit' };
  const read = key => JSON.parse(rows.get(key)?.value ?? 'null');
  const counts = () => Object.fromEntries(['get', 'put', 'list', 'delete'].map(op => [op, ops.filter(x => x[0] === op).length]));
  return { rows, ops, faults, kv, env, read, counts };
}

async function fixture(h, i = 0) {
  const event = { tenant_id: T, company_id: C, event_id: `ride_stop:${T}:${C}:booking_${i}`,
    event_type: 'ride_stop', booking_id: `booking_${i}`, trip_id: `trip_${i}`,
    created_at_utc: '2026-08-10T07:04:58.008Z' };
  const eventKey = `compliance_event_v1/tenant/${T}/company/${C}/2026/08/10/1786345498008_${i}`;
  const statusKey = id => api.buildChironExportStatusKey(T, C, id);
  const candidateKey = statusKey(`candidate_v1:${event.event_id}`);
  const officialId = `arrival_${i}`, officialKey = statusKey(officialId), departureId = `departure_${i}`;
  const official = { tenant_id: T, company_id: C, event_id: event.event_id, official_idempotency_key: officialId,
    sync_state: 'waiting_for_departure', paired_departure_idempotency_key: departureId,
    last_attempt_at: i === 3 ? '2026-09-21T22:06:09.013Z' : null, attempt_count: 0 };
  await h.kv.put(eventKey, JSON.stringify(event));
  await h.kv.put(officialKey, JSON.stringify(official));
  await h.kv.put(candidateKey, JSON.stringify({ ...official, sync_state: 'blocked_by_failed_departure',
    failure_kind: 'definitive', reason_code: null, source_event_key: eventKey }));
  await h.kv.put(statusKey(departureId), JSON.stringify({ sync_state: 'failed', failure_kind: 'definitive',
    attempt_count: 6, outbound_fingerprint_definitive_attempts: 6 }));
  const refKey = api.buildChironOfficialEventRefKey(T, C, event.event_id);
  await h.kv.put(refKey, JSON.stringify({ v: 1, k: officialId }));
  const markerKey = await armChironDueMarker(h.kv, eventKey, oldDue[i]);
  const item = { eventKey, markerKey, dueAtMs: oldDue[i] };
  return { event, eventKey, candidateKey, officialKey, official, refKey, departureKey: statusKey(departureId), item };
}

for (let i = 0; i < 4; i++) test(`live-shaped arrival ${i + 1}: retire only selected stale marker after one terminal write`, async () => {
  const h = harness(), f = await fixture(h, i);
  // Exercise a new terminal transition; already-terminal candidates are now
  // protected without another status write (covered separately below).
  await h.kv.put(f.candidateKey, JSON.stringify(f.official));
  const wrongDue = api.computeChironReconcileDueAtMs(f.official, NOW);
  const wrongKey = await armChironDueMarker(h.kv, f.eventKey, wrongDue);
  const siblingKey = await armChironDueMarker(h.kv, f.eventKey, NOW + 86400000);
  const unrelated = await armChironDueMarker(h.kv, f.eventKey + '_other', 0);
  assert.notEqual(wrongKey, f.item.markerKey);
  h.ops.length = 0;
  const result = await api._chironResolveDueCandidate(h.env, f.item, NOW, null);
  assert.equal(result.kind, 'terminal');
  assert.equal(h.rows.has(f.item.markerKey), false);
  assert.deepEqual(h.ops.filter(x => x[0] === 'delete'), [['delete', f.item.markerKey]]);
  assert.deepEqual(h.ops.filter(x => x[0] === 'put'), [['put', f.candidateKey]]);
  assert.ok(h.rows.has(wrongKey) && h.rows.has(siblingKey) && h.rows.has(unrelated));
  const candidate = h.read(f.candidateKey);
  assert.equal(candidate.sync_state, 'blocked_by_failed_departure');
  assert.equal(candidate.reason_code, 'blocked_by_failed_departure');
  assert.equal(api.computeChironReconcileDueAtMs(candidate, NOW), null);
  assert.equal(candidate.official_idempotency_key, h.read(f.refKey).k);
  assert.deepEqual(h.read(f.officialKey), f.official, 'provider fact remains unchanged');
  assert.ok(h.ops.findIndex(x => x[0] === 'put') < h.ops.findIndex(x => x[0] === 'delete'));
});

test('terminal persist failure keeps selected marker and all other markers', async () => {
  const h = harness(), f = await fixture(h);
  await h.kv.put(f.candidateKey, JSON.stringify(f.official));
  h.faults.put = f.candidateKey;
  h.ops.length = 0;
  const result = await api._chironResolveDueCandidate(h.env, f.item, NOW, null);
  assert.notEqual(result.kind, 'terminal');
  assert.ok(h.rows.has(f.item.markerKey));
  assert.equal(h.counts().delete, 0);
});

test('retirement interruption after terminal persist is retryable', async () => {
  const h = harness(), f = await fixture(h);
  await h.kv.put(f.candidateKey, JSON.stringify(f.official));
  h.faults.delete = f.item.markerKey;
  await api._chironResolveDueCandidate(h.env, f.item, NOW, null);
  assert.equal(h.read(f.candidateKey).sync_state, 'blocked_by_failed_departure');
  assert.ok(h.rows.has(f.item.markerKey));
  h.faults.delete = null;
  await api._chironResolveDueCandidate(h.env, f.item, NOW + 300000, null);
  assert.equal(h.rows.has(f.item.markerKey), false);
});

for (const crashAfter of ['after_persist', 'before_retire']) test(`crash ${crashAfter} retains marker; replay retires it`, async () => {
  const h = harness(), f = await fixture(h);
  const transition = { eventKey: f.eventKey, selectedMarkerKey: f.item.markerKey, nextDueAtMs: null,
    previousDueAtMs: NOW + 900000, persist: () => h.kv.put(f.candidateKey, JSON.stringify({ sync_state: 'blocked_by_failed_departure' })) };
  await assert.rejects(applyChironDueMarkerTransition(h.kv, { ...transition, crashAfter }), ChironDueIndexTestCrash);
  assert.ok(h.rows.has(f.item.markerKey));
  assert.equal(h.read(f.candidateKey).sync_state, 'blocked_by_failed_departure');
  await applyChironDueMarkerTransition(h.kv, transition);
  assert.equal(h.rows.has(f.item.markerKey), false);
});

test('foreign or malformed selected marker fails closed before any mutation', async () => {
  const h = harness(), f = await fixture(h);
  for (const markerKey of [await buildChironDueMarkerKey(0, f.eventKey + '_foreign'), 'chiron_reconcile_due:v1:!done', 'malformed']) {
    h.ops.length = 0;
    await api._chironResolveDueCandidate(h.env, { ...f.item, markerKey }, NOW, null);
    assert.equal(h.counts().put, 0);
    assert.equal(h.counts().delete, 0);
    assert.ok(h.rows.has(f.item.markerKey));
  }
});

test('departure correction re-arms arrival through the existing paired-arrival mechanism', async () => {
  const h = harness(), f = await fixture(h);
  await api._chironResolveDueCandidate(h.env, f.item, NOW, null);
  assert.equal(h.rows.has(f.item.markerKey), false);
  await h.kv.put(f.departureKey, JSON.stringify({ sync_state: 'synced' }));
  const departure = { ...f.event, event_type: 'ride_start', event_id: f.event.event_id.replace('ride_stop:', 'ride_start:') };
  await api._chironReArmPairedArrivalAfterDeparture(h.env, departure, [{ event: f.event, key: f.eventKey }]);
  const markerKey = await buildChironDueMarkerKey(0, f.eventKey);
  assert.ok(h.rows.has(markerKey));
  const result = await api._chironResolveDueCandidate(h.env, { eventKey: f.eventKey, markerKey, dueAtMs: 0 }, NOW + 300000, null);
  assert.equal(result.kind, 'due', 'corrected departure makes arrival actionable again');
});

for (const completed of [false, true]) test(`four-arrival quiet cron (DONE=${completed}): following tick has no event writes/deletes and preserves retryable work`, async (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: NOW });
  const h = harness(), fixtures = [];
  for (let i = 0; i < 4; i++) fixtures.push(await fixture(h, i));
  if (completed) for (const [i, f] of fixtures.entries()) {
    await h.kv.put(f.candidateKey, JSON.stringify({ ...h.read(f.candidateKey),
      sync_state: i % 2 ? 'verification_required' : 'synced' }));
  }
  const connection = { enabled: true, environment: 'production', production_enabled: false,
    test_credentials_stored: true, production_credentials_stored: true, last_connection_status: 'test_passed',
    testflow_auto_submit_enabled: true, testflow_started_at: '2026-08-01T05:24:57.669Z',
    test_departure_sent_count: 5, test_arrival_sent_count: 5, test_messages_sent_count: 10,
    test_rides_completed_count: 5, testflow_status: 'complete' };
  await h.kv.put(`tenant:${T}:company:${C}:chiron_connection:v1`, JSON.stringify(connection));
  for (let i = 0; i < 3; i++) await h.kv.put(`tenant:${T}:company:gated_${i}:chiron_connection:v1`, JSON.stringify({ ...connection, enabled: false }));
  await api._chironMarkScopeDueMigrationComplete(h.env, T, C, NOW);
  await markChironDueMigrationComplete(h.kv, { now: new Date(NOW) });
  await h.kv.put(buildChironScopeRecoverKey(T, C), JSON.stringify({ version: 1, from_ms: 1790400000000, prefix: null, cursor: null, last_key: null }));
  const retryEvent = { ...fixtures[0].event, event_type: 'ride_start', event_id: 'retryable_other' };
  const retryKey = fixtures[0].eventKey + '_retry';
  await h.kv.put(retryKey, JSON.stringify(retryEvent));
  await h.kv.put(api._chironCandidateExportStatusKey(T, C, retryEvent, null), JSON.stringify({ sync_state: 'retryable_failed', last_attempt_at: new Date(NOW).toISOString(), attempt_count: 1 }));
  const retryMarker = await armChironDueMarker(h.kv, retryKey, NOW + 900000);
  h.ops.length = 0;
  await api._chironCronReconcileAllScopesBestEffort(h.env, { nowMs: NOW });
  for (const f of fixtures) assert.equal(h.rows.has(f.item.markerKey), false);
  const first = h.counts();
  h.ops.length = 0;
  t.mock.timers.setTime(NOW + 300000);
  await api._chironCronReconcileAllScopesBestEffort(h.env, { nowMs: NOW + 300000 });
  const second = h.counts();
  assert.equal(second.delete, 0);
  assert.deepEqual(second, { get: 6, put: 0, list: 4, delete: 0 });
  assert.equal(h.ops.some(([op, key]) => op === 'put' && key.startsWith('chiron_export_status_v1/')), false);
  assert.equal(h.ops.some(([op, key]) => op === 'get' && key.startsWith('compliance_event_v1/')), false);
  assert.ok(h.rows.has(retryMarker));
  assert.equal((await api._chironResolveDueCandidate(h.env, { eventKey: retryKey, markerKey: retryMarker, dueAtMs: NOW + 900000 }, NOW + 900001, null)).kind, 'due');
  assert.equal(first.put, 0, 'already durable terminal candidates need no rewrite');
  if (completed) for (const [i, f] of fixtures.entries()) {
    assert.equal(h.read(f.candidateKey).sync_state, i % 2 ? 'verification_required' : 'synced');
  }
  console.log('MARKER_REPEAT_FIX_COUNTS', JSON.stringify({ completed, first, second }));
});

const dueKeys = h => [...h.rows.keys()].filter(k => k.startsWith(CHIRON_RECONCILE_DUE_PREFIX));
const wakeupKeys = h => [...h.rows.keys()].filter(k => k.startsWith(CHIRON_RECONCILE_WAKEUP_PREFIX));
const recoveryStateKey = buildChironScopeRecoverKey(T, C);
async function rewindRecovery(h, f) {
  const timestamp = Number(f.eventKey.match(/\/(\d{13})_/)[1]);
  await h.kv.put(recoveryStateKey, JSON.stringify({ version: 1, from_ms: timestamp - 1, prefix: null, cursor: null, last_key: null }));
}
const recover = h => api._chironRecoverUnmarkedRecentForScope(h.env, T, C, NOW, {
  completed: true, state: { completed_at: new Date(NOW).toISOString() },
});

test('four terminal arrivals: passive wakeup and replayed markerless recovery never resurrect or rewrite', async () => {
  const h = harness(), fixtures = [];
  for (let i = 0; i < 4; i++) {
    const f = await fixture(h, i);
    fixtures.push(f);
    await api._chironResolveDueCandidate(h.env, f.item, NOW, null);
    await armChironWakeupHint(h.kv, f.eventKey);
  }
  const statuses = fixtures.map(f => h.rows.get(f.candidateKey).value);
  h.ops.length = 0;
  const wakeup = await api._chironDrainWakeupHints(h.env, NOW);
  const wakeupCounts = h.counts();
  assert.equal(wakeup.armed, 0);
  assert.equal(wakeup.examined, 4);
  assert.equal(wakeupKeys(h).length, 0);
  assert.equal(dueKeys(h).length, 0);
  assert.equal(wakeupCounts.put, 0);
  const recoveryCounts = [];
  for (let replay = 0; replay < 2; replay++) {
    await rewindRecovery(h, fixtures[0]);
    h.ops.length = 0;
    const result = await recover(h);
    recoveryCounts.push(h.counts());
    assert.equal(result.examined, 4);
    assert.equal(result.armed, 0);
    assert.equal(dueKeys(h).length, 0);
    assert.ok(h.ops.filter(([op]) => op === 'put').every(([, key]) => key === recoveryStateKey));
    assert.deepEqual(fixtures.map(f => h.rows.get(f.candidateKey).value), statuses);
    assert.equal(h.ops.some(([op, key]) => op === 'get' && fixtures.some(f => f.officialKey === key)), false);
  }
  console.log('TERMINAL_PASSIVE_RECOVERY_COUNTS', JSON.stringify({ wakeup: wakeupCounts, recovery: recoveryCounts }));
});

for (const status of [
  { sync_state: 'blocked_by_failed_departure', reason_code: null },
  { sync_state: 'blocked', reason_code: 'blocked_by_failed_departure' },
  { sync_state: 'blocked', sanitized_error: 'blocked_by_failed_departure' },
  ...['afstand', 'vertrekpunt_lengtegraad', 'vertrekpunt_breedtegraad', 'aankomstpunt_lengtegraad', 'aankomstpunt_breedtegraad', 'invalid_zero_coordinate_pair'].map(reason_code => ({ sync_state: 'blocked', reason_code })),
  ...['synced', 'verification_required', 'departure_confirmed_external'].map(sync_state => ({ sync_state })),
  { sync_state: 'failed', failure_kind: 'definitive', attempt_count: 6 },
  { sync_state: 'failed', external_status_code: 400, attempt_count: 6 },
  { sync_state: 'failed' },
  { sync_state: 'retryable_failed', attempt_count: 6 },
  { sync_state: 'queued', attempt_count: 6 },
]) test(`terminal candidate wins over stale waiting official in both passive paths: ${JSON.stringify(status)}`, async () => {
  const h = harness(), f = await fixture(h);
  h.rows.delete(f.item.markerKey);
  await h.kv.put(f.candidateKey, JSON.stringify({
    official_idempotency_key: f.official.official_idempotency_key,
    paired_departure_idempotency_key: f.official.paired_departure_idempotency_key,
    ...status,
  }));
  await armChironWakeupHint(h.kv, f.eventKey);
  assert.equal((await api._chironDrainWakeupHints(h.env, NOW)).armed, 0);
  await rewindRecovery(h, f);
  assert.equal((await recover(h)).armed, 0);
  assert.equal(dueKeys(h).length, 0);
});

for (const status of [
  { sync_state: 'retryable_failed', attempt_count: 1 },
  { sync_state: 'queued', attempt_count: 1 },
  { sync_state: 'failed', failure_kind: 'definitive', attempt_count: 1 },
  { sync_state: 'blocked', reason_code: 'temporary_credentials_unavailable' },
  { sync_state: 'pending' },
  { sync_state: 'pending_build' },
]) test(`nonterminal passive recovery retains existing due calculation: ${status.sync_state}`, async () => {
  const h = harness(), f = await fixture(h);
  h.rows.delete(f.item.markerKey);
  const current = { ...status, last_attempt_at: new Date(NOW).toISOString() };
  await h.kv.put(f.candidateKey, JSON.stringify(current));
  await h.kv.put(f.officialKey, JSON.stringify(current));
  await armChironWakeupHint(h.kv, f.eventKey);
  assert.equal((await api._chironDrainWakeupHints(h.env, NOW)).armed, 1);
  const armed = dueKeys(h);
  assert.deepEqual(armed, [await buildChironDueMarkerKey(api.computeChironReconcileDueAtMs(current, NOW), f.eventKey)]);
  // Compare wakeup to recovery as both retain the Worker's configured options.
  h.rows.delete(armed[0]);
  await rewindRecovery(h, f);
  assert.equal((await recover(h)).armed, 1);
  assert.deepEqual(dueKeys(h), armed);
});

for (const correctedState of ['synced', 'departure_confirmed_external']) test(`confirmed departure survives failed rearm marker write via wakeup: ${correctedState}`, async () => {
  const h = harness(), f = await fixture(h);
  await api._chironResolveDueCandidate(h.env, f.item, NOW, null);
  await h.kv.put(f.departureKey, JSON.stringify({ sync_state: correctedState }));
  const marker = await buildChironDueMarkerKey(0, f.eventKey);
  h.faults.put = marker;
  const departure = { ...f.event, event_type: 'ride_start' };
  assert.equal(await api._chironReArmPairedArrivalAfterDeparture(h.env, departure, [{ event: f.event, key: f.eventKey }]), 0);
  assert.equal(wakeupKeys(h).length, 1);
  h.faults.put = null;
  assert.equal((await api._chironDrainWakeupHints(h.env, NOW)).armed, 1);
  assert.ok(h.rows.has(marker));
  assert.equal((await api._chironResolveDueCandidate(h.env, { eventKey: f.eventKey, markerKey: marker, dueAtMs: 0 }, NOW, null)).kind, 'due');
  // Also recover when both writes were lost: the confirmed departure is evidence.
  h.rows.delete(marker);
  await rewindRecovery(h, f);
  assert.equal((await recover(h)).armed, 1);
});

for (const failedRead of ['candidateKey', 'departureKey']) test(`status read failure preserves wakeup and recovery checkpoint: ${failedRead}`, async () => {
  const h = harness(), f = await fixture(h);
  h.rows.delete(f.item.markerKey);
  await armChironWakeupHint(h.kv, f.eventKey);
  await rewindRecovery(h, f);
  const checkpoint = h.rows.get(recoveryStateKey).value;
  h.faults.get = f[failedRead];
  await assert.rejects(api._chironDrainWakeupHints(h.env, NOW), /read failed/);
  assert.equal(wakeupKeys(h).length, 1);
  await assert.rejects(recover(h), /read failed/);
  assert.equal(h.rows.get(recoveryStateKey).value, checkpoint);
  assert.equal(dueKeys(h).length, 0);
  h.faults.get = null;
  assert.equal((await api._chironDrainWakeupHints(h.env, NOW)).armed, 0);
  assert.equal((await recover(h)).armed, 0);
});

test('crash during terminal wakeup retirement retries without status writes or markers', async () => {
  const h = harness(), f = await fixture(h);
  h.rows.delete(f.item.markerKey);
  await armChironWakeupHint(h.kv, f.eventKey);
  h.faults.delete = wakeupKeys(h)[0];
  h.ops.length = 0;
  await api._chironDrainWakeupHints(h.env, NOW);
  assert.equal(wakeupKeys(h).length, 1);
  assert.equal(h.counts().put, 0);
  h.faults.delete = null;
  await api._chironDrainWakeupHints(h.env, NOW);
  assert.equal(wakeupKeys(h).length, 0);
  assert.equal(h.counts().put, 0);
  assert.equal(dueKeys(h).length, 0);
});

for (const departure of [
  { sync_state: 'pending' },
  { sync_state: 'failed', failure_kind: 'definitive', attempt_count: 1 },
  { sync_state: 'synced', tenant_id: 'another_tenant', company_id: C },
]) test(`departure without valid confirmation cannot lift terminality: ${JSON.stringify(departure)}`, async () => {
  const h = harness(), f = await fixture(h);
  h.rows.delete(f.item.markerKey);
  await h.kv.put(f.departureKey, JSON.stringify(departure));
  await armChironWakeupHint(h.kv, f.eventKey);
  assert.equal((await api._chironDrainWakeupHints(h.env, NOW)).armed, 0);
  await rewindRecovery(h, f);
  assert.equal((await recover(h)).armed, 0);
  assert.equal(dueKeys(h).length, 0);
});

test('confirmed departure cannot reactivate an arrival whose official status is already synced', async () => {
  const h = harness(), f = await fixture(h);
  h.rows.delete(f.item.markerKey);
  await h.kv.put(f.departureKey, JSON.stringify({ sync_state: 'synced' }));
  await h.kv.put(f.officialKey, JSON.stringify({ ...f.official, sync_state: 'synced' }));
  await armChironWakeupHint(h.kv, f.eventKey);
  assert.equal((await api._chironDrainWakeupHints(h.env, NOW)).armed, 0);
  await rewindRecovery(h, f);
  assert.equal((await recover(h)).armed, 0);
});

for (const candidateStatus of [
  { sync_state: 'synced' },
  { sync_state: 'verification_required' },
  { sync_state: 'departure_confirmed_external' },
  { sync_state: 'blocked_by_failed_departure' },
  { sync_state: 'blocked', reason_code: 'afstand' },
  { sync_state: 'failed', failure_kind: 'definitive', attempt_count: 6 },
]) for (const officialState of ['waiting_for_departure', 'pending', 'blocked']) {
  test(`ordinary due preserves ${JSON.stringify(candidateStatus)} over stale ${officialState}`, async () => {
    const h = harness(), f = await fixture(h);
    const candidate = { ...h.read(f.candidateKey), ...candidateStatus, last_attempt_at: new Date(NOW).toISOString() };
    await h.kv.put(f.candidateKey, JSON.stringify(candidate));
    await h.kv.put(f.officialKey, JSON.stringify({ ...f.official, sync_state: officialState }));
    const sibling = await armChironDueMarker(h.kv, f.eventKey, NOW + 86400000);
    const foreign = await armChironDueMarker(h.kv, f.eventKey + '_foreign', 0);
    const before = h.rows.get(f.candidateKey).value;
    h.ops.length = 0;
    assert.equal((await api._chironResolveDueCandidate(h.env, f.item, NOW, null)).kind, 'terminal');
    assert.equal(h.rows.get(f.candidateKey).value, before);
    assert.equal(h.counts().put, 0);
    assert.deepEqual(h.ops.filter(([op]) => op === 'delete'), [['delete', f.item.markerKey]]);
    assert.ok(h.rows.has(sibling) && h.rows.has(foreign));
    assert.equal(h.ops.some(([op, key]) => op === 'get' && key === f.officialKey), false);
  });
}

for (const status of [
  { sync_state: 'pending_build', last_attempt_at: new Date(NOW).toISOString() },
  { sync_state: 'retryable_failed', attempt_count: 1, last_attempt_at: new Date(NOW).toISOString() },
  { sync_state: 'waiting_for_departure', last_attempt_at: new Date(NOW).toISOString() },
  { sync_state: 'blocked', reason_code: 'temporary_credentials_unavailable' },
]) test(`ordinary due does not classify recoverable candidate as terminal: ${status.sync_state}`, async () => {
  const h = harness(), f = await fixture(h);
  await h.kv.put(f.candidateKey, JSON.stringify({ ...f.official, ...status }));
  await h.kv.put(f.departureKey, JSON.stringify({ sync_state: 'synced' }));
  const before = h.rows.get(f.candidateKey).value;
  h.ops.length = 0;
  const result = await api._chironResolveDueCandidate(h.env, f.item, NOW, null);
  assert.equal(result.kind, 'due', 'existing waiting official plus confirmed departure stays actionable');
  assert.equal(h.rows.get(f.candidateKey).value, before);
  assert.equal(h.counts().put, 0);
  assert.ok(h.rows.has(f.item.markerKey));
});

test('terminal candidate read failure keeps selected marker', async () => {
  const h = harness(), f = await fixture(h);
  h.faults.get = f.candidateKey;
  h.ops.length = 0;
  await assert.rejects(api._chironResolveDueCandidate(h.env, f.item, NOW, null), /read failed/);
  assert.equal(h.counts().delete, 0);
  assert.equal(h.counts().put, 0);
  assert.ok(h.rows.has(f.item.markerKey));
});
