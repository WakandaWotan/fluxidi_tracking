import {test} from 'node:test'; import assert from 'node:assert/strict';
import fs from 'node:fs';
import worker, {FleetAllocatorDO} from './backend/retained-source/workers/booking/quote_handler_candidate.js';
import {createMemoryDriverIndexCoordinatorBinding} from './backend/retained-source/workers/booking/modules/driver_index_mutation.mjs';
import {createMemoryCompanyCustomerImportCoordinatorBinding,CompanyCustomerImportCoordinatorDO} from './backend/retained-source/workers/booking/modules/company_customer_import_coordinator.mjs';
import {createMemoryCanonicalBookingDirectoryBinding} from './backend/retained-source/workers/booking/modules/canonical_booking_directory.mjs';
import {CompanyTrackingRoom,companyTrackingObjectName} from './backend/retained-source/workers/tracking/modules/company_tracking_room.mjs';
import {prepareCanonicalDispatchOffer,consumeCanonicalDispatchEvent} from './backend/retained-source/workers/booking/modules/company_dispatch_delivery.mjs';
globalThis.fetch=async()=>{throw Error('External requests forbidden');};
async function personalHumanFixture(){
 const f=await fixture({vehicleOperations:true}),hash=Buffer.from(await crypto.subtle.digest('SHA-256',new TextEncoder().encode('token-D'))).toString('hex');
 const key=`public_driver:session:${hash}:v1`,session=JSON.parse(f.records.get(key));session.assigned_vehicle_id='VD';f.records.set(key,JSON.stringify(session));
 const ehash=Buffer.from(await crypto.subtle.digest('SHA-256',new TextEncoder().encode('token-E'))).toString('hex'),ekey=`public_driver:session:${ehash}:v1`;
 const es=JSON.parse(f.records.get(ekey));es.assigned_vehicle_id='VE';f.records.set(ekey,JSON.stringify(es));
 const r=await f.read();r.p12_reliable_choice={schema:'fluxidi-reliable-choice-v1',kind:'exact',vehicle_id:'VD',passengers:1,luggage:0};
 f.records.set('booking:B',JSON.stringify(r));assert.equal((await f.prepare()).ok,true);return {f,key,hash};
}

const scope = { tenant_id: 'T', company_id: 'C' };
const ADMIN = 'fixture-admin';
async function fixture({ automaticDelivery = false, authority = false, extraDrivers = [], vehicleOperations = false } = {}) {
  const driverIds = ['D', 'E', ...extraDrivers];
  const records = new Map(); let failKey = null, publishFail = false, published = 0, lastBridge = null, candidateAvailable = true;
  const tasks = [];
  const allocatorRequests = [];
  const kv = { get: async (key, opts) => opts?.type === 'json' ? JSON.parse(records.get(key) || 'null') : records.get(key) || null,
    put: async (key, value) => { if (key === failKey) throw Error('simulated write outage'); records.set(key, value); },
    delete: async key => records.delete(key),
    list: async ({ prefix = '' } = {}) => ({ keys: [...records.keys()].filter(key => key.startsWith(prefix)).map(name => ({ name })), list_complete: true }) };
  const rooms = new Map();
  const env = { ADMIN_TOKEN: ADMIN, BOOKING_KV: kv, DISPATCH_DEVICE_ACK_ENABLED: '1', FLEET_AVAILABILITY_MODE: 'multi_vehicle' };
  if (vehicleOperations) env.COMPANY_VEHICLE_OPERATIONS_ENABLED = '1';
  if (authority) env.BOOKING_RECORD_AUTHORITY_ENABLED = '1';
  env.CANONICAL_BOOKING_DIRECTORY = createMemoryCanonicalBookingDirectoryBinding(env);
  env.COMPANY_TRACKING = { idFromName: name => name, get(name) {
    if (!rooms.has(name)) {
      const data = new Map(); const slot = { data, alarmAt: null, room: null };
      slot.storage = { get: async key => structuredClone(data.get(key)),
        put: async (key, value) => data.set(key, structuredClone(value)),
        setAlarm: async at => { slot.alarmAt = at; }, deleteAlarm: async () => { slot.alarmAt = null; } };
      slot.state = { storage: slot.storage, ...(automaticDelivery ? { waitUntil: task => tasks.push(task) } : {}) };
      slot.room = new CompanyTrackingRoom(slot.state, { ADMIN_TOKEN: ADMIN,
        ...(vehicleOperations ? { COMPANY_VEHICLE_OPERATIONS_ENABLED: '1' } : {}),
        BOOKING_API: { fetch: async request => { const response = await worker.fetch(request, env, {});
          lastBridge = await response.clone().json(); return response; } } });
      rooms.set(name, slot);
    }
    return { fetch: (request, init) => rooms.get(name).room.fetch(request instanceof Request ? request : new Request(request, init)) };
  } };
  env.COMPANY_CUSTOMER_IMPORT_COORDINATOR = createMemoryCompanyCustomerImportCoordinatorBinding(env);
  // Isolate delivery from road ranking. Road ETA selection has its own suite;
  // this allocator fixture checks suggestion-only and failed-driver exclusion.
  env.FLEET_ALLOCATOR = { idFromName: name => name, get() { return { fetch: async (request, init) => {
    const body = await (request instanceof Request ? request : new Request(request, init)).json(); allocatorRequests.push(body);
    if (body.action === 'release') return Response.json({ ok: true, released: true });
    assert.equal(body.action, 'suggest');
    if (!candidateAvailable) return Response.json({ ok: true, allowed: false, reason: 'no_candidate' });
    const driver = body.excluded_driver_ids?.includes('D') ? 'E' : 'D';
    return Response.json({ ok: true, allowed: true, assigned_vehicle_id: `V${driver}`, assigned_driver_id: driver,
      assigned_driver: { driver_id: driver, display_name: `TEST ${driver}` } });
  } }; } };
  const people = Object.fromEntries(driverIds.map(id => [id, { driver_id: id, ...scope, is_active: true,
    availability_status: 'available', assigned_vehicle_id: `V${id}`, display_name: `TEST ${id}`, public_profile_enabled: true }]));
  records.set('tenant:T:company:C:drivers:index:v1', JSON.stringify({ drivers: people }));
  records.set('tenant:T:company:C:fleet:vehicles:v1', JSON.stringify({ vehicles: driverIds.map(id => ({
    vehicle_id: `V${id}`, ...scope, is_active: true, passenger_capacity: 4, assigned_driver_id: id, name: `TEST ${id}` })) }));
  for (const id of driverIds) {
    const hash = Buffer.from(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`token-${id}`))).toString('hex');
    records.set(`public_driver:session:${hash}:v1`, JSON.stringify({ role: 'driver', ...scope, driver_id: id,
      expires_at: new Date(Date.now() + 3_600_000).toISOString() }));
  }
  const record = { ...scope, booking_id: 'B', revision: 1, status: 'CONFIRMED', customer_id: 'customer',
    pickup_iso: new Date(Date.now() + 600_000).toISOString(), duration_min: 20, duration_route_min: 20,
    payment_mode: 'cash', from: 'Sint-Niklaas', to: 'Gent', pax: 1, bags: 0,
    booking: { from: 'Sint-Niklaas', to: 'Gent', duration_route_min: 20, pickup_lat: 51.165, pickup_lng: 4.142 } };
  record.booking.pickup_iso = record.pickup_iso;
  records.set('booking:B', JSON.stringify(record));
  const slot = () => rooms.get(companyTrackingObjectName('T', 'C'));
  async function roomPost(path, body) { return env.COMPANY_TRACKING.get(companyTrackingObjectName('T', 'C')).fetch(`https://room/${path}`, {
    method: 'POST', body: JSON.stringify({ ...scope, ...body }) }); }
  await roomPost('capacity-baseline', { inventory_verified: true, bookings: [], inventory_digest: 'fixture-empty-assigned-inventory' });
  for (const id of driverIds) {
    const device_key = Buffer.from(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`token-${id}`))).toString('hex');
    await roomPost('dispatch-device', { driver_id: id, device_key, protocol: 1, session_expires_ms: Date.now() + 3_600_000 });
  }
  for (const id of driverIds) await roomPost('location', { driver_id: id, vehicle_id: `V${id}`,
    latitude: 51.165, longitude: 4.142, accuracy: 8, captured_at: new Date().toISOString() });
  const hooks = { selectCandidate: async (rec) => { if (!candidateAvailable) return { ok: false, error: 'no_candidate' };
    const id = rec.dispatch_exclusions?.some(row => row.driver_id === 'D' && row.until_ms > Date.now()) ? 'E' : 'D';
    return { ok: true, assignedDriverId: id, assignedVehicleId: `V${id}` }; },
    publishAssignment: async () => { if (publishFail) return { ok: false }; published++; return { ok: true }; } };
  return { env, records, hooks, slot, roomPost, allocatorRequests, get published() { return published; }, get lastBridge() { return lastBridge; },
    failPut: key => { failKey = key; }, failPublish: value => { publishFail = value; },
    candidates: value => { candidateAvailable = value; },
    read: () => kv.get('booking:B', { type: 'json' }),
    restart: () => { slot().room = new CompanyTrackingRoom(slot().state, slot().room.env); },
    restartCoordinator: () => { const binding = env.COMPANY_CUSTOMER_IMPORT_COORDINATOR;
      for (const [name, instance] of binding._instances) binding._instances.set(name,
        new CompanyCustomerImportCoordinatorDO(instance.state, env)); },
    coordinator: () => env.COMPANY_CUSTOMER_IMPORT_COORDINATOR.get(
      env.COMPANY_CUSTOMER_IMPORT_COORDINATOR.idFromName('T:C')),
    async settle() { let timer; try {
      await Promise.race([(async () => { while (tasks.length) await tasks.shift(); })(),
        new Promise((_, reject) => { timer = setTimeout(() => reject(Error('dispatch delivery deadlocked')), 2000); })]);
    } finally { clearTimeout(timer); } },
    async http(path, body, token = ADMIN) {
      if (path === '/public/driver/heartbeat' || path === '/public/driver/availability')
        env.DRIVER_INDEX_COORDINATOR ||= createMemoryDriverIndexCoordinatorBinding();
      return worker.fetch(new Request(`https://booking${path}`, {
      method: 'POST', headers: { 'content-type': 'application/json', ...(token === ADMIN ? { 'x-admin-token': token } : token ? { authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify(body) }), env, {}); },
    async prepare() { return prepareCanonicalDispatchOffer(env, scope, 'B', hooks); },
    async receipt(driver = 'D') { const intent = (await this.read()).dispatch_offer;
      return this.http('/public/driver/dispatch/ack', { offer_id: intent.offer_id, version: intent.version }, `token-${driver}`); },
    async consume() { const intent = (await this.read()).dispatch_offer;
      return consumeCanonicalDispatchEvent(env, scope, { event_id: `${intent.offer_id}:commit` }, hooks); },
  };
}

export {fixture,personalHumanFixture,scope};
