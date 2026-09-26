import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker, { __testInternals as api } from './fluxidi_compliance_worker.js';

const NOW = Date.parse('2026-09-26T06:25:20.801Z');
const T = 'idle_throttle', C = 'company';
const key = `tenant:${T}:company:${C}:chiron_connection:v1`;
const active = {
  enabled: true, environment: 'production', production_enabled: false,
  test_credentials_stored: true, production_credentials_stored: true,
  last_connection_status: 'test_passed', testflow_auto_submit_enabled: true,
  testflow_started_at: '2026-08-01T05:24:57.669Z',
  test_departure_sent_count: 5, test_arrival_sent_count: 5,
  test_messages_sent_count: 10, test_rides_completed_count: 5, testflow_status: 'complete',
};

function setup(t, overrides = {}) {
  t.mock.timers.enable({ apis: ['Date'], now: NOW });
  t.mock.method(globalThis, 'fetch', async () => { throw new Error('network forbidden'); });
  const rows = new Map([[key, JSON.stringify({ ...active, ...overrides })]]);
  const ops = [], scheduled = [];
  const env = {
    ADMIN_TOKEN: 'fixture-only', CHIRON_EXPORT_MODE: 'test',
    CHIRON_EXPORT_BASE_URL: 'https://mow-acc.api.vlaanderen.be/chiron/taxirit',
    COMPLIANCE_KV: {
      async get(k) { ops.push(['get', k]); return rows.get(k) ?? null; },
      async put(k, v) { ops.push(['put', k]); rows.set(k, v); },
      async delete(k) { ops.push(['delete', k]); rows.delete(k); },
      async list({ prefix = '' } = {}) {
        ops.push(['list', prefix]);
        return { keys: [...rows.keys()].filter(k => k.startsWith(prefix)).sort().map(name => ({ name })), list_complete: true };
      },
    },
  };
  const poll = () => worker.fetch(new Request(
    `https://compliance.internal/admin/chiron/config/status?tenant_id=${T}&company_id=${C}`,
    { headers: { 'x-admin-token': 'fixture-only' } },
  ), env, { waitUntil(p) { scheduled.push(p); } });
  const writes = () => ops.filter(([op]) => op === 'put');
  return { rows, ops, scheduled, env, poll, writes };
}

test('closed cron gate never stamps throttle, including five minutes later', async t => {
  const h = setup(t, { enabled: false });
  const before = h.rows.get(key);
  for (const nowMs of [NOW, NOW + 300000]) {
    t.mock.timers.setTime(nowMs);
    const result = await api._chironCronReconcileAllScopesBestEffort(h.env, { nowMs });
    assert.equal(result.gated, 1);
    assert.equal(result.ran, 0);
    assert.equal(h.rows.get(key), before);
    assert.equal(h.writes().length, 0);
  }
});

for (const overrides of [
  { enabled: false },
  { testflow_auto_submit_enabled: false, environment: 'test' },
  { testflow_started_at: null },
  { testflow_started_at: 'invalid' },
  { test_credentials_stored: false, production_credentials_stored: false },
]) {
  test(`rapid simultaneous polls of closed scope do not schedule reconcile: ${JSON.stringify(overrides)}`, async t => {
    const h = setup(t, overrides);
    await api._chironCronReconcileAllScopesBestEffort(h.env, { nowMs: NOW });
    h.ops.length = 0;
    const responses = await Promise.all(Array.from({ length: 10 }, () => h.poll()));
    assert.ok(responses.every(r => r.status === 200));
    assert.equal(h.scheduled.length, 0);
    assert.equal(h.writes().length, 0);
    assert.equal(h.ops.some(([op]) => op === 'list'), false);
  });
}

test('re-enabled scope starts reconcile; subsequent rapid polls retain 15-second throttle', async t => {
  const h = setup(t, { enabled: false });
  await h.poll();
  assert.equal(h.scheduled.length, 0);
  h.rows.set(key, JSON.stringify(active));
  await api._chironMarkScopeDueMigrationComplete(h.env, T, C, NOW);
  h.ops.length = 0;
  await h.poll();
  assert.equal(h.scheduled.length, 1);
  const result = await h.scheduled[0];
  assert.equal(result.ok, true);
  assert.equal(result.source, 'status_poll');
  assert.equal(JSON.parse(h.rows.get(key)).testflow_auto_reconcile_last_at, new Date(NOW).toISOString());
  assert.equal(h.writes().filter(([, k]) => k === key).length, 1);
  h.ops.length = 0;
  t.mock.timers.setTime(NOW + 14999);
  await Promise.all(Array.from({ length: 10 }, () => h.poll()));
  assert.equal(h.scheduled.length, 1);
  assert.equal(h.writes().length, 0);
  assert.equal(h.ops.some(([op]) => op === 'list'), false);
  t.mock.timers.setTime(NOW + 15000);
  await h.poll();
  assert.equal(h.scheduled.length, 2);
  await h.scheduled[1];
  assert.equal(JSON.parse(h.rows.get(key)).testflow_auto_reconcile_last_at, new Date(NOW + 15000).toISOString());
});
