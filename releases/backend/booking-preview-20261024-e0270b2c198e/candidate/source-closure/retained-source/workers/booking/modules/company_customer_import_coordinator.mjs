import { withBookingCutoverMaintenance, verifyBookingCutoverRequest } from './booking_cutover_maintenance.mjs';
import {recoverCustomerProjection,runCustomerProjection}from'./customer_projection_journal.mjs';
import {readBoundedJson}from'./bounded_json_storage.mjs';
import { bookingWritersPaused, bookingWriterPauseResponse, allowsPausedCoordinatorAction, deferPausedBookingAlarm } from './booking_writer_pause.mjs';
import { createCompanyFleetDelta } from './company_fleet_delta.mjs';
import { emitTenantCostMetric, meterTenantBindings } from './tenant_cost_metrics.mjs';
// COMPANY-CUSTOMER-OPS-P0B — company-scoped import write coordinator.
//
// Workers KV has no compare-and-swap. A process lock or read-check-write is
// not a server guarantee across isolates. This Durable Object is single-threaded
// per tenant+company, so same-key and different-row import batches serialize
// before they touch customer records or packed list pages. Manual create,
// PATCH, archive and restore use the same instance so they cannot overwrite
// those pages while an import batch is in flight.
//
// The DO ledger outlives the 72h KV progress document. After expiry the
// coordinator refuses new creates for that import_id instead of silently
// opening a blank meta document.
//
// Production activation requires the wrangler binding + sqlite migration.
// Tests use the in-memory binding. Missing binding fails closed for batches.

import {
  archiveCompanyCustomer,
  createCompanyCustomer,
  normalizeCustomerScope,
  restoreCompanyCustomer,
  updateCompanyCustomer,
} from "./company_customers.mjs";
import {
  getCompanyCustomerImport,
  processImportBatch,
} from "./company_customers_import.mjs";
import { canonicalBookingOperation, canonicalBookingAuthorityEnabled, withCanonicalBookingAuthority,
  recoverCanonicalBookings } from './canonical_booking_authority.mjs';
import { withInitialBookingIntentState } from './initial_booking_intent.mjs';
import {withOperationalRoutingV1} from './reliable_operational_routes_v1.mjs';
import {reliableChoiceEnabled} from './reliable_prebooking_v1.mjs';
import { initializeNewCompanyCapacity } from './new_company_capacity.mjs';
import {stagingTrialDoMarkedV1,stagingTrialDoRefusalV1} from './staging_trial_do_fence_v1.mjs';

export const COMPANY_CUSTOMER_IMPORT_DO_BINDING =
  "COMPANY_CUSTOMER_IMPORT_COORDINATOR";

export function companyCustomerImportCoordinatorInstanceName(scope) {
  const s = normalizeCustomerScope(scope);
  if (!s.hasScope) return "";
  return `${s.tenant_id}:${s.company_id}`;
}

export function createMemoryImportCoordinatorStorage(seed = {}) {
  const store = new Map(Object.entries(seed));
  let alarm = null;
  let transactionGate = Promise.resolve();
  return {
    async get(key) {
      return store.has(key) ? store.get(key) : undefined;
    },
    transaction(fn) {
      const run = transactionGate.then(async () => {
        const copy = structuredClone(store);
        const result = await fn({ get: async key => structuredClone(copy.get(key)),
          put: async (key, value) => copy.set(key, structuredClone(value)), delete: async key => copy.delete(key) });
        store.clear(); for (const [key, value] of copy) store.set(key, value);
        return result;
      });
      transactionGate = run.then(() => {}, () => {}); return run;
    },
    async put(key, value) {
      store.set(key, value);
    },
    async delete(key) { return store.delete(key); },
    async list({ prefix = '', startAfter = '', limit = 1000 } = {}) {
      return new Map([...store].filter(([key]) => key.startsWith(prefix) && key > startAfter)
        .sort(([a], [b]) => a.localeCompare(b)).slice(0, limit));
    },
    async getAlarm() { return alarm; },
    async setAlarm(at) { alarm = at; },
    async deleteAlarm() { alarm = null; },
    _store: store,
  };
}

export class CompanyCustomerImportCoordinatorDO {
  constructor(stateOrCtx, env) {
    this.state = stateOrCtx;
    this.env = env;
  }

  async fetch(request, init) {
    const stagingRefusal=stagingTrialDoRefusalV1(this.env);
    if(stagingRefusal)return stagingRefusal;
    this._gate = this._gate || Promise.resolve();
    const req = request instanceof Request ? request : new Request(String(request), init);
    const inspectionBody = await req.clone().json().catch(() => null);
    if (inspectionBody?.action === 'navigation_authority_read_v1') {
      const run = this._gate.then(async () => {
        const {readCanonicalNavigationAuthorityV1} = await import('./national_navigation_authorization_v1.mjs');
        return readCanonicalNavigationAuthorityV1(this.state, this.env, req, inspectionBody);
      });
      this._gate = run.then(() => undefined, () => undefined);
      return run;
    }
    if (inspectionBody?.action === 'canonical_booking_inspection') {
      const run = this._gate.then(async () => {
        const {inspectCanonicalWithoutMutation} = await import('./canonical_booking_inspection.mjs');
        return inspectCanonicalWithoutMutation(this.state, this.env, req, inspectionBody);
      });
      this._gate = run.then(() => undefined, () => undefined);
      return run;
    }
    let preparation = null;
    if (this.env.ENTERPRISE_DISPATCH_PREPARE_ENABLED === '1' && !bookingWritersPaused(this.env)) {
      const body = await req.clone().json().catch(() => ({}));
      this._requestBodies ||= new WeakMap();
      this._requestBodies.set(req, body);
      if (body.action === 'tracking_booking_mutation' && body.kind === 'dispatch_offer') {
        // Snapshot reads share the company gate. Pure advisory computation
        // then runs outside it; this request owns its immutable version fence.
        const captured = this._gate.then(async () => {
          const local = withCanonicalBookingAuthority(this.env, { state: this.state, scope: body.scope });
          return local.BOOKING_KV.get(`booking:${body.bookingId}`, { type: 'json' });
        });
        this._gate = captured.then(() => undefined, () => undefined);
        const record = await captured;
        if (record?.pickup_mode === 'asap' && !record.p12_reliable_choice && !record.dispatch_offer && !record.assigned_driver_id
          && !record.assigned_vehicle_id && record.tenant_id === body.scope?.tenant_id && record.company_id === body.scope?.company_id) {
          const { dispatchOfferBasis } = await import('./dispatch_offer_basis.mjs');
          const key = JSON.stringify([body.scope, await dispatchOfferBasis(record), record.dispatch_exclusions || [], record.vehicle_dispatch_attempts || []]);
          this._prepareFlights ||= new Map();
          const started = performance.now();
          let flight = this._prepareFlights.get(key);
          if (!flight) {
            const { prepareEnterpriseDispatchCandidates } = await import('../fluxidi_booking_worker.js');
            // Wait for bounded advisory capacity outside the company gate.
            // Completion failures still propagate to their owning requests;
            // a waiter needs only notification that a preparation slot freed.
            while (this._prepareFlights.size >= 16 && !this._prepareFlights.has(key))
              await Promise.race([...this._prepareFlights.values()].map(task => task.then(() => undefined, () => undefined)));
            flight = this._prepareFlights.get(key);
            if (!flight) {
              flight = prepareEnterpriseDispatchCandidates(meterTenantBindings(this.env, body.scope), body, record);
              this._prepareFlights.set(key, flight);
              flight.finally(() => { if (this._prepareFlights.get(key) === flight) this._prepareFlights.delete(key); }).catch(() => {});
            }
          }
          const proposed = await flight;
          if (proposed) preparation = { ...proposed, record_json: JSON.stringify(record),
            record_revision: Number(record.revision) || 0, canonical_version: Number(record._canonical_version) || 0,
            prepare_ms: performance.now() - started };
        }
      }
    }
    this._preparations ||= new WeakMap();
    if (preparation) this._preparations.set(req, preparation);
    const enqueued = performance.now();
    const run = this._gate.then(async () => {
      const scope = this._requestBodies?.get(req)?.scope;
      const started = performance.now();
      await emitTenantCostMetric(this.env, scope, 'queue_ms', started - enqueued);
      if (preparation) await emitTenantCostMetric(this.env, scope, 'prepare_ms', preparation.prepare_ms);
      try { return await this._fetchBody(req, init); }
      finally { await emitTenantCostMetric(this.env, scope, 'commit_ms', performance.now() - started); }
    }).catch(error => {
      if (!canonicalBookingAuthorityEnabled(this.env)) throw error;
      return this._json({ ok: false, error: error.code || 'canonical_booking_storage_failed', failure_kind: /subrequests/i.test(error.message || '') ? 'subrequest_limit' : /cutover_operation_forbidden/.test(error.message || '') ? 'maintenance_operation_denied' : /alarm/i.test(error.message || '') ? 'alarm_storage' : 'storage_or_transport' }, error.status || 503);
    });
    this._gate = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }

  async alarm() {
    if(stagingTrialDoMarkedV1(this.env))return;
    this._gate = this._gate || Promise.resolve();
    const run = this._gate.then(async () => {
      if (await deferPausedBookingAlarm(this.state, this.env)) return;
      const customerScope=await this.state.storage.get('customer-projection-scope-v1');
      if(customerScope){try{await recoverCustomerProjection(this.state.storage,this.env,customerScope);this._customerJournalKnownEmpty=true;}catch{await this.state.storage.setAlarm(Date.now()+60000);throw Error('customer_projection_recovery_pending');}}
      return recoverCanonicalBookings(this.state, this.env,
      async (env, scope, bookingId) => {
        const { executeTrackingBookingMutation } = await import('../fluxidi_booking_worker.js');
        return executeTrackingBookingMutation(env, { kind: 'dispatch_offer', scope, bookingId });
      });
    });
    this._gate = run.then(() => undefined, () => undefined);
    return run;
  }

  async _fetchBody(request, init) {
    const req =
      request instanceof Request ? request : new Request(String(request), init);
    const maintenance = await verifyBookingCutoverRequest(this.env, req, 'company');
    let body = {};
    try {
      body = this._requestBodies?.get(req) || await req.json();
    } catch {
      body = {};
    }
    if (bookingWritersPaused(this.env) && !allowsPausedCoordinatorAction(body) && !maintenance) return bookingWriterPauseResponse();
    const operationEnv = meterTenantBindings(maintenance ? withBookingCutoverMaintenance(this.env, maintenance.scope, maintenance.bookingId) : this.env, body.scope);
    const action = String(body?.action || "").trim().toLowerCase();
    if(!this._customerJournalKnownEmpty){
      try{const recovered=await recoverCustomerProjection(this.state.storage,this.env,body.scope,body);this._customerJournalKnownEmpty=true;if(recovered)return recovered;}
      catch{return this._json({ok:false,error:'customer_projection_recovery_pending'},503);}
    }
    const customerMethods={process_batch:'_processBatch',create_customer:'_createCustomer',update_customer:'_updateCustomer',archive_customer:'_archiveCustomer',restore_customer:'_restoreCustomer'};
    if(customerMethods[action]){
      this._customerJournalKnownEmpty=false;
      try{const result=await runCustomerProjection(this.state.storage,this.env,body,(env,storage)=>this[customerMethods[action]](body,env,storage));this._customerJournalKnownEmpty=true;return result;}
      catch{return this._json({ok:false,error:'customer_projection_recovery_pending'},503);}
    }
    if(action==='fleet_sync_probe'){
      return this._json({ok:true,unchanged:this._fleetSyncProbe?.probe(body.scope,body.fingerprint,body.since,Date.now())===true});
    }
    if (action === 'fleet_sync') {
      this._fleetDelta ||= createCompanyFleetDelta();
      const result = await this._fleetDelta.resolve(body.scope, body.payload || {}, body.since || '');
      const {createFleetSyncProbe}=await import('./company_fleet_sync_guard.mjs');
      this._fleetSyncProbe ||= createFleetSyncProbe();
      this._fleetSyncProbe.remember(body.scope,body.fingerprint,result.revision,body.payload?.drivers||[],Number.isFinite(body.rendered_at_ms)?body.rendered_at_ms:Date.now());
      return this._json(result);
    }
    if (action === 'new_company_capacity') {
      const result = await initializeNewCompanyCapacity(this.state, this.env, body);
      return this._json(result, result.status || 200);
    }
    if(action==='canonical_booking_page'){
      const {readCanonicalCompanyPage}=await import('./canonical_booking_authority.mjs');
      const result=await readCanonicalCompanyPage(this.state,operationEnv,body);
      return this._json(result,result.status||200);
    }
    if (action === 'canonical_booking') {
      try {
        const result = await canonicalBookingOperation(this.state, operationEnv, body);
        return this._json(result, result.status || 200);
      } catch (error) {
        return this._json({ ok: false, error: error.code || 'canonical_booking_storage_failed', failure_kind: /subrequests/i.test(error.message || '') ? 'subrequest_limit' : /cutover_operation_forbidden/.test(error.message || '') ? 'maintenance_operation_denied' : /alarm/i.test(error.message || '') ? 'alarm_storage' : 'storage_or_transport' }, error.status || 503);
      }
    }
    if (action === 'monthly_invoice_index_prepare') {
      const pin=await this.state.storage.get('canonical-booking-scope');
      if(!pin||pin.tenant_id!==body.scope?.tenant_id||pin.company_id!==body.scope?.company_id)return this._json({ok:false,error:'invoice_source_scope_unverified'},403);
      const {indexedInvoiceSources}=await import('./company_invoice_source_index.mjs');
      const result=await indexedInvoiceSources(this.state.storage,{scope:body.scope,customerId:body.customerId,month:body.month,prepare:true,indexOnly:true});
      return this._json(result||{ok:false,error:'invoice_source_authority_required'},result?.ok?200:409);
    }
    if (['monthly_invoice_job_begin','monthly_invoice_job_advance','monthly_invoice_job_status','monthly_invoice_job_page','monthly_invoice_job_publish','monthly_invoice_job_abort'].includes(action)) {
      const {beginInvoiceJob,advanceInvoiceJob,readInvoiceJob,readInvoiceJobPage,publishInvoiceJob,abortInvoiceJob}=await import('./company_monthly_invoice_job.mjs');
      const {deriveServerSideInvoiceContext,resolveCompanyMonthlyInvoiceSeller,allocateCompanyMonthlyInvoiceReference}=await import('../fluxidi_booking_worker.js');
      const input={scope:body.scope,customerId:body.customerId,month:body.month,requestId:body.requestId,jobId:body.jobId,expectedStep:body.expectedStep,expectedContentHash:body.expectedContentHash,index:body.index,chunkSize:body.chunkSize};
      const deps={deriveInvoiceContext:deriveServerSideInvoiceContext,resolveSeller:resolveCompanyMonthlyInvoiceSeller,allocateReference:args=>allocateCompanyMonthlyInvoiceReference(operationEnv,args.scope,args)};
      const result=action==='monthly_invoice_job_begin'?await beginInvoiceJob(this.state.storage,operationEnv,input,deps):action==='monthly_invoice_job_advance'?await advanceInvoiceJob(this.state.storage,operationEnv,input,deps):action==='monthly_invoice_job_page'?await readInvoiceJobPage(this.state.storage,input):action==='monthly_invoice_job_publish'?await publishInvoiceJob(this.state.storage,operationEnv,input,deps):action==='monthly_invoice_job_abort'?await abortInvoiceJob(this.state.storage,operationEnv,input):await readInvoiceJob(this.state.storage,input);
      return this._json(result,result.status||(result.ok?200:409));
    }
    if (action === 'monthly_invoice_preview') {
      const { previewCompanyMonthlyInvoice } = await import('./company_monthly_invoice_preview.mjs');
      const { deriveServerSideInvoiceContext } = await import('../fluxidi_booking_worker.js');
      const result = await previewCompanyMonthlyInvoice(this.state, operationEnv,
        { scope: body.scope, customerId: body.customerId, month: body.month }, deriveServerSideInvoiceContext);
      return this._json(result, result.status || (result.ok ? 200 : 409));
    }
    if (action === 'monthly_invoice_issue') {
      const { issueCompanyMonthlyInvoice } = await import('./company_monthly_invoice_runtime.mjs');
      const { deriveServerSideInvoiceContext, resolveCompanyMonthlyInvoiceSeller, allocateCompanyMonthlyInvoiceReference } = await import('../fluxidi_booking_worker.js');
      const result = await issueCompanyMonthlyInvoice(this.state, operationEnv,
        { scope: body.scope, customerId: body.customerId, month: body.month, expectedContentHash: body.expectedContentHash },
        { deriveInvoiceContext: deriveServerSideInvoiceContext, resolveSeller: resolveCompanyMonthlyInvoiceSeller, allocateReference: allocateCompanyMonthlyInvoiceReference });
      return this._json(result, result.status || (result.ok ? 200 : 409));
    }
    if (['monthly_invoice_list', 'monthly_invoice_detail', 'monthly_invoice_pdf', 'monthly_invoice_send'].includes(action)) {
      const { listCompanyMonthlyInvoices, readCompanyMonthlyInvoice, companyMonthlyInvoicePdf, sendCompanyMonthlyInvoice } = await import('./company_monthly_invoice_delivery.mjs');
      const { recordCompanyMonthlyInvoicePdfUsage } = await import('../fluxidi_booking_worker.js');
      const input = { scope: body.scope, customerId: body.customerId, month: body.month };
      const result = action === 'monthly_invoice_list' ? await listCompanyMonthlyInvoices(this.state, operationEnv, { ...input, cursor: body.cursor || '' }) :
        action === 'monthly_invoice_detail' ? await readCompanyMonthlyInvoice(this.state, operationEnv, input) :
        action === 'monthly_invoice_pdf' ? await companyMonthlyInvoicePdf(this.state, operationEnv, input, { prepare: body.prepare === true, recordUsage: recordCompanyMonthlyInvoicePdfUsage }) :
        await sendCompanyMonthlyInvoice(this.state, operationEnv, input);
      return this._json(result, result.status || (result.ok ? 200 : 409));
    }
    const bookingEnv = withOperationalRoutingV1(withCanonicalBookingAuthority(operationEnv, { state: this.state, scope: body.scope }));
    if(reliableChoiceEnabled(bookingEnv)&&typeof bookingEnv.__reliableRegionalRoutes==='function'){
      const {createReliableOperationalRuntimeV1}=await import('../fluxidi_booking_worker.js');
      bookingEnv.__reliableChoiceRuntime=(scope,options)=>createReliableOperationalRuntimeV1(bookingEnv,scope,this,options);
    }
    if(action==='reliable_public_command'){
      const {executeReliablePublicCommandV1}=await import('../fluxidi_booking_worker.js');
      const result=await executeReliablePublicCommandV1(bookingEnv,this,body);return this._json(result,result.ok===false?409:200);
    }
    if (action === 'initial_customer_booking') {
      const { executeInitialCustomerBooking } = await import('../fluxidi_booking_worker.js');
      const result = await executeInitialCustomerBooking(withInitialBookingIntentState(bookingEnv, this.state, body.scope), body);
      const {resolveCompletedFinancialResultV1}=await import('./financial_intent_resolution_v1.mjs');
      await resolveCompletedFinancialResultV1(this.state,bookingEnv,body.scope,result,body);
      return this._json(result, Number.isInteger(result.status) ? result.status : (result.ok ? 200 : 409));
    }
    if(action==='financial_intent_recovery'){
      const {executeFinancialIntentRecoveryV1}=await import('../fluxidi_booking_worker.js');
      const result=await executeFinancialIntentRecoveryV1(bookingEnv,this.state,body);
      return this._json(result,result.status||(result.ok?200:503));
    }
    if (action === 'initial_payment_reconcile') {
      const { executeInitialPaymentReconciliation } = await import('../fluxidi_booking_worker.js');
      const result = await executeInitialPaymentReconciliation(withInitialBookingIntentState(bookingEnv, this.state, body.scope), body);
      return this._json(result, result.status || (result.ok ? 200 : 503));
    }
    if (action === 'initial_paid_finalize') {
      const { executeInitialPaidFinalize } = await import('../fluxidi_booking_worker.js');
      const result = await executeInitialPaidFinalize(bookingEnv, body);
      const {resolveCompletedFinancialResultV1}=await import('./financial_intent_resolution_v1.mjs');
      await resolveCompletedFinancialResultV1(this.state,bookingEnv,body.scope,result,body);
      return this._json(result, Number.isInteger(result.status) ? result.status : (result.ok ? 200 : 409));
    }
    if (action === "tracking_booking_mutation") {
      const { executeTrackingBookingMutation } = await import("../fluxidi_booking_worker.js");
      const result = await executeTrackingBookingMutation(bookingEnv, body, this._preparations?.get(req));
      return this._json(result, Number.isInteger(result.status) ? result.status : (result.ok ? 200 : 409));
    }
    if (action === "process_batch") return this._processBatch(body);
    if (action === "get_import") return this._getImport(body);
    if (action === "create_customer") return this._createCustomer(body);
    if (action === "update_customer") return this._updateCustomer(body);
    if (action === "archive_customer") return this._archiveCustomer(body);
    if (action === "restore_customer") return this._restoreCustomer(body);
    if (action === "assign_booking") return this._assignBooking(body, bookingEnv);
    if (action === "unassign_booking") return this._unassignBooking(body, bookingEnv);
    if (action === "reschedule_booking") return this._rescheduleBooking(body, bookingEnv);
    if (action === 'operational_route_booking') {
      const { executeTrackingBookingMutation } = await import('../fluxidi_booking_worker.js');
      const result = await executeTrackingBookingMutation(bookingEnv, { kind: 'operational_route', scope: body.scope,
        bookingId: body.bookingId, body: body.body || {}, options: { actor: { role: 'company' } } });
      return this._json(result, result.status || (result.ok ? 200 : 409));
    }
    if (action === "phone_confirm_booking") return this._phoneConfirmBooking(body, bookingEnv);
    if (action === "create_booking") return this._createBooking(body, bookingEnv);
    return this._json({ ok: false, error: "unknown_action" }, 400);
  }

  _ledgerKey(importId) {
    return `import:${String(importId || "").trim()}`;
  }

  async _processBatch(body, env = this.env, storage = this.state.storage) {
    const importId = String(body?.importId || body?.import_id || "").trim();
    const ledger = (await readBoundedJson(storage,this._ledgerKey(importId))) || null;
    const result = await processImportBatch(env, {
      scope: body.scope,
      importId,
      rows: body.rows,
      ledger,
    });
    if (result?.ledger?.import_id) {
      await storage.put(this._ledgerKey(importId), result.ledger);
    }
    return this._json(result, result?.status || 500);
  }

  async _getImport(body) {
    const importId = String(body?.importId || body?.import_id || "").trim();
    const ledger = (await readBoundedJson(this.state.storage,this._ledgerKey(importId))) || null;
    const result = await getCompanyCustomerImport(this.env, {
      scope: body.scope,
      importId,
      ledger,
    });
    return this._json(result, result?.status || 500);
  }

  async _createCustomer(body, env = this.env, storage = this.state.storage) {
    const result = await createCompanyCustomer(env, {
      scope: body.scope,
      body: body.body || {},
      idempotencyKey: body.idempotencyKey,
    });
    return this._json(result, result?.status || 500);
  }

  async _updateCustomer(body, env = this.env, storage = this.state.storage) {
    const result = await updateCompanyCustomer(env, {
      scope: body.scope,
      customerId: body.customerId || body.customer_id,
      body: body.body || {},
    });
    return this._json(result, result?.status || 500);
  }

  async _archiveCustomer(body, env = this.env, storage = this.state.storage) {
    const result = await archiveCompanyCustomer(env, {
      scope: body.scope,
      customerId: body.customerId || body.customer_id,
      idempotencyKey: body.idempotencyKey,
    });
    return this._json(result, result?.status || 500);
  }

  async _restoreCustomer(body, env = this.env, storage = this.state.storage) {
    const result = await restoreCompanyCustomer(env, {
      scope: body.scope,
      customerId: body.customerId || body.customer_id,
      idempotencyKey: body.idempotencyKey,
    });
    return this._json(result, result?.status || 500);
  }

  async _createBooking(body, env = this.env) {
    const { createAgendaRide } = await import("./company_agenda.mjs");
    const result = await createAgendaRide(env, {
      scope: body.scope,
      body: body.body || {},
      idempotencyKey: body.idempotencyKey,
    });
    return this._json(result, result.ok ? (result.idempotent ? 200 : 201) : 400);
  }

  async _assignBooking(body, env = this.env) {
    const { assignAgendaRide } = await import("./company_agenda.mjs");
    const result = await assignAgendaRide(env, {
      scope: body.scope,
      bookingId: body.bookingId || body.booking_id,
      body: body.body || {},
    });
    return this._json(result, result.ok ? 200 : 409);
  }

  async _unassignBooking(body, env = this.env) {
    const { unassignAgendaRide } = await import("./company_agenda.mjs");
    const result = await unassignAgendaRide(env, {
      scope: body.scope,
      bookingId: body.bookingId || body.booking_id,
      body: body.body || {},
    });
    return this._json(result, result.ok ? 200 : 409);
  }

  async _rescheduleBooking(body, env = this.env) {
    const { rescheduleAgendaRide } = await import("./company_agenda.mjs");
    const result = await rescheduleAgendaRide(env, {
      scope: body.scope,
      bookingId: body.bookingId || body.booking_id,
      body: body.body || {},
    });
    return this._json(result, result.ok ? 200 : 409);
  }

  async _phoneConfirmBooking(body, env = this.env) {
    const { phoneConfirmAgendaRide } = await import("./company_agenda.mjs");
    const result = await phoneConfirmAgendaRide(env, {
      scope: body.scope,
      bookingId: body.bookingId || body.booking_id,
      body: body.body || {},
    });
    return this._json(result, result.ok ? 200 : 409);
  }

  _json(obj, status = 200) {
    return new Response(JSON.stringify(obj || {}), {
      status,
      headers: { "content-type": "application/json" },
    });
  }
}

/** Test helper: one serialized DO instance per company. */
export function createMemoryCompanyCustomerImportCoordinatorBinding(env = {}) {
  const instances = new Map();
  return {
    idFromName(name) {
      return { name: String(name || "") };
    },
    get(id) {
      const name = String(id?.name || "");
      if (!instances.has(name)) {
        const storage = createMemoryImportCoordinatorStorage();
        const dob = new CompanyCustomerImportCoordinatorDO({ storage }, env);
        let chain = Promise.resolve();
        const originalFetch = dob.fetch.bind(dob);
        dob.fetch = (req, init) => {
          const run = chain.then(() => originalFetch(req, init));
          chain = run.then(
            () => undefined,
            () => undefined,
          );
          return run;
        };
        instances.set(name, dob);
      }
      return instances.get(name);
    },
    _instances: instances,
  };
}

export function hasCompanyCustomerImportCoordinator(env) {
  const binding = env?.[COMPANY_CUSTOMER_IMPORT_DO_BINDING];
  return !!(binding?.idFromName && binding?.get);
}

export async function callCompanyCustomerImportCoordinator(env, body) {
  const binding = env?.[COMPANY_CUSTOMER_IMPORT_DO_BINDING];
  if (!binding?.idFromName || !binding?.get) {
    return {
      ok: false,
      status: 503,
      error: "import_coordinator_unavailable",
      next_step: "configure_import_coordinator",
    };
  }
  const name = companyCustomerImportCoordinatorInstanceName(body?.scope);
  if (!name) {
    return { ok: false, status: 400, error: "missing_tenant_scope" };
  }
  const stub = binding.get(binding.idFromName(name));
  stub.env = env;
  const resp = await stub.fetch(
    new Request("https://do/company-customer-import", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    }),
  );
  const json = await resp.json().catch(() => ({}));
  if (json && typeof json === "object") {
    if (json.status == null) json.status = resp.status;
    return json;
  }
  return { ok: false, status: resp.status || 500, error: "import_coordinator_failed" };
}
