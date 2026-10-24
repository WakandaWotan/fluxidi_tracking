// Explicit local migration only. Existing immutable evidence table and keys;
// no replacement ledger, prices, provider calls or new booking identities.
import {historicalHoldExistsSql,FINANCIAL_HISTORICAL_HOLD_OBJECTS_V1} from './financial_historical_hold_v1.mjs';
const table='financial_route_evidence_v1';
const extract=(row,path)=>`json_extract(${row},'$.${path}')`;
const owner=q=>`CASE WHEN ${extract(q,'inputs.financial_context.schema')}='fluxidi-vehicle-financial-context-v1' AND json_type(${q},'$.inputs.financial_context.customer_id')='text' AND length(${extract(q,'inputs.financial_context.customer_id')})>0 THEN json_array(${extract(q,'scope.tenant_id')},${extract(q,'scope.company_id')},${extract(q,'inputs.financial_context.customer_id')}) END`;
const scope=q=>`json_array(${extract(q,'scope.tenant_id')},${extract(q,'scope.company_id')})`;
const claimQuote=`(SELECT payload_json FROM ${table} WHERE evidence_key='quote:'||substr(NEW.evidence_key,12))`;
const bookingQuote=`json_extract(NEW.payload_json,'$.evidence.id')`;
const active=`coalesce(json_extract(a.payload_json,'$.state'),'legacy') NOT IN ('closed','resolved')`;
const ownerBlocked=(q,id)=>`EXISTS(SELECT 1 FROM ${table} a WHERE substr(a.evidence_key,1,11)='acceptance:' AND a.evidence_key<>'acceptance:'||${id} AND ${active} AND NOT ${historicalHoldExistsSql('substr(a.evidence_key,12)',"json_extract(a.payload_json,'$.booking_id')")} AND (json_extract(a.payload_json,'$._owner_key')=${owner(q)} OR json_extract(a.payload_json,'$._owner_key') IS NULL AND json_extract(a.payload_json,'$._scope_key')=${scope(q)}))`;
const frozen=id=>`EXISTS(SELECT 1 FROM ${table} b WHERE substr(b.evidence_key,1,8)='booking:' AND json_extract(b.payload_json,'$.evidence.id')=${id})`;
const trigger=(name,event,body)=>({name,type:'trigger',sql:`CREATE TRIGGER IF NOT EXISTS ${name} ${event} ON ${table} BEGIN ${body} END`});
const insertion=trigger('financial_fence_insert_v1','BEFORE INSERT',`
 SELECT (CASE WHEN json_valid(NEW.payload_json)=0 THEN RAISE(ABORT,'financial_payload_invalid') END);
 SELECT (CASE WHEN NEW.evidence_key='fence:old-writer-v1' AND EXISTS(SELECT 1 FROM ${table} a WHERE substr(a.evidence_key,1,11)='acceptance:' AND json_extract(a.payload_json,'$.state')='closed' AND (json_extract(a.payload_json,'$.storage_fence_version') IS NOT 1 OR ${frozen('substr(a.evidence_key,12)')})) THEN RAISE(ABORT,'financial_migration_closed_unproven') END);
 SELECT (CASE WHEN NEW.evidence_key='fence:old-writer-v1' AND EXISTS(SELECT 1 FROM ${table} a WHERE substr(a.evidence_key,1,11)='acceptance:' AND ${active} AND json_extract(a.payload_json,'$._owner_key') IS NOT NULL GROUP BY json_extract(a.payload_json,'$._owner_key') HAVING count(*)>1) THEN RAISE(ABORT,'financial_migration_owner_conflict') END);
 SELECT (CASE WHEN substr(NEW.evidence_key,1,6)='quote:' AND EXISTS(SELECT 1 FROM ${table} a WHERE a.evidence_key='acceptance:'||substr(NEW.evidence_key,7) AND json_extract(a.payload_json,'$.state')='closed') THEN RAISE(ABORT,'financial_intent_closed') END);
 SELECT (CASE WHEN substr(NEW.evidence_key,1,6)='quote:' AND NOT EXISTS(SELECT 1 FROM ${table} WHERE evidence_key=NEW.evidence_key) AND (${owner('NEW.payload_json')} IS NULL OR ${ownerBlocked('NEW.payload_json','substr(NEW.evidence_key,7)')}) THEN RAISE(ABORT,'financial_owner_replay_required') END);
 SELECT (CASE WHEN substr(NEW.evidence_key,1,11)='acceptance:' AND NOT EXISTS(SELECT 1 FROM ${table} WHERE evidence_key='quote:'||substr(NEW.evidence_key,12)) THEN RAISE(ABORT,'financial_quote_missing') END);
 SELECT (CASE WHEN substr(NEW.evidence_key,1,11)='acceptance:' AND NOT EXISTS(SELECT 1 FROM ${table} WHERE evidence_key=NEW.evidence_key) AND coalesce(json_extract(NEW.payload_json,'$.state'),'legacy')<>'closed' AND (${owner(claimQuote)} IS NULL OR ${ownerBlocked(claimQuote,'substr(NEW.evidence_key,12)')}) THEN RAISE(ABORT,'financial_owner_replay_required') END);
 SELECT (CASE WHEN substr(NEW.evidence_key,1,11)='acceptance:' AND json_extract(NEW.payload_json,'$.state')='closed' AND (json_extract(NEW.payload_json,'$.storage_fence_version') IS NOT 1 OR ${frozen('substr(NEW.evidence_key,12)')}) THEN RAISE(ABORT,'financial_acceptance_started') END);
 SELECT (CASE WHEN substr(NEW.evidence_key,1,8)='booking:' AND NOT EXISTS(SELECT 1 FROM ${table} a WHERE a.evidence_key='acceptance:'||${bookingQuote} AND json_extract(a.payload_json,'$.booking_id')=json_extract(NEW.payload_json,'$.booking_id') AND coalesce(json_extract(a.payload_json,'$.state'),'legacy') NOT IN ('closed','resolved')) AND NOT EXISTS(SELECT 1 FROM ${table} b WHERE b.evidence_key=NEW.evidence_key AND json_extract(b.payload_json,'$.evidence.id')=${bookingQuote} AND json_extract(b.payload_json,'$.booking_id')=json_extract(NEW.payload_json,'$.booking_id')) THEN RAISE(ABORT,'financial_closed_or_identity_conflict') END);
`);
const update=trigger('financial_fence_update_v1','BEFORE UPDATE',`
 SELECT (CASE WHEN NEW.evidence_key<>OLD.evidence_key THEN RAISE(ABORT,'financial_key_immutable') END);
 SELECT (CASE WHEN (substr(OLD.evidence_key,1,6)='quote:' OR substr(OLD.evidence_key,1,8)='booking:' OR OLD.evidence_key='fence:old-writer-v1') AND NEW.payload_json<>OLD.payload_json THEN RAISE(ABORT,'financial_evidence_immutable') END);
 SELECT (CASE WHEN substr(OLD.evidence_key,1,11)='acceptance:' AND json_extract(OLD.payload_json,'$.state')='closed' AND NEW.payload_json<>OLD.payload_json THEN RAISE(ABORT,'financial_closed_immutable') END);
 SELECT (CASE WHEN substr(OLD.evidence_key,1,11)='acceptance:' AND json_extract(OLD.payload_json,'$.state')='resolved' AND NEW.payload_json<>OLD.payload_json THEN RAISE(ABORT,'financial_resolved_immutable') END);
 SELECT (CASE WHEN substr(OLD.evidence_key,1,11)='acceptance:' AND json_extract(OLD.payload_json,'$._scope_key') IS NOT NULL AND json_extract(NEW.payload_json,'$._scope_key') IS NOT json_extract(OLD.payload_json,'$._scope_key') THEN RAISE(ABORT,'financial_scope_immutable') END);
 SELECT (CASE WHEN substr(OLD.evidence_key,1,11)='acceptance:' AND json_extract(OLD.payload_json,'$._owner_key') IS NOT NULL AND (json_extract(NEW.payload_json,'$._owner_key') IS NOT json_extract(OLD.payload_json,'$._owner_key') OR json_extract(NEW.payload_json,'$._scope_key') IS NOT json_extract(OLD.payload_json,'$._scope_key')) THEN RAISE(ABORT,'financial_owner_immutable') END);
 SELECT (CASE WHEN substr(OLD.evidence_key,1,11)='acceptance:' AND json_extract(NEW.payload_json,'$.state')='closed' AND (json_extract(OLD.payload_json,'$.state') IS NOT 'reserved' OR json_extract(NEW.payload_json,'$.storage_fence_version') IS NOT 1 OR json_extract(NEW.payload_json,'$.booking_id') IS NOT json_extract(OLD.payload_json,'$.booking_id') OR json_extract(NEW.payload_json,'$.closed_booking_id') IS NOT json_extract(OLD.payload_json,'$.booking_id') OR ${frozen('substr(OLD.evidence_key,12)')}) THEN RAISE(ABORT,'financial_acceptance_started') END);
 SELECT (CASE WHEN substr(OLD.evidence_key,1,11)='acceptance:' AND json_extract(NEW.payload_json,'$.state') IS NOT 'closed' AND json_extract(NEW.payload_json,'$.booking_id') IS NOT json_extract(OLD.payload_json,'$.booking_id') THEN RAISE(ABORT,'financial_booking_identity_immutable') END);
 SELECT (CASE WHEN substr(OLD.evidence_key,1,11)='acceptance:' AND json_extract(OLD.payload_json,'$.state') IN ('executing','resolved') AND coalesce(json_extract(NEW.payload_json,'$.state'),'legacy') NOT IN ('executing','resolved') THEN RAISE(ABORT,'financial_execution_monotonic') END);
 SELECT (CASE WHEN substr(OLD.evidence_key,1,11)='acceptance:' AND json_extract(NEW.payload_json,'$.state')='resolved' AND (NOT ${frozen('substr(OLD.evidence_key,12)')} OR json_extract(NEW.payload_json,'$.resolution.booking_id') IS NOT json_extract(OLD.payload_json,'$.booking_id') OR json_extract(NEW.payload_json,'$.resolution.financial_quote_id') IS NOT substr(OLD.evidence_key,12) OR json_extract(NEW.payload_json,'$.resolution.stage') IS NOT 'BOOKED' OR json_extract(NEW.payload_json,'$.resolution.payment_resolved') IS NOT 1) THEN RAISE(ABORT,'financial_resolution_unproven') END);
`);
const stamp=trigger('financial_fence_stamp_v1','AFTER INSERT',`
 UPDATE ${table} SET payload_json=json_set(payload_json,'$._owner_key',${owner(claimQuote)},'$._scope_key',${scope(claimQuote)}) WHERE evidence_key=NEW.evidence_key AND substr(NEW.evidence_key,1,11)='acceptance:' AND coalesce(json_extract(NEW.payload_json,'$.state'),'legacy') NOT IN ('closed','resolved');
 UPDATE ${table} SET payload_json=json_set(payload_json,'$.state','executing','$.revision',coalesce(json_extract(payload_json,'$.revision'),0)+1) WHERE evidence_key='acceptance:'||${bookingQuote} AND substr(NEW.evidence_key,1,8)='booking:' AND coalesce(json_extract(payload_json,'$.state'),'legacy') NOT IN ('closed','resolved','executing');
`);
const deletion=trigger('financial_fence_delete_v1','BEFORE DELETE',`
 SELECT (CASE WHEN substr(OLD.evidence_key,1,6)='quote:' OR substr(OLD.evidence_key,1,11)='acceptance:' OR substr(OLD.evidence_key,1,8)='booking:' OR OLD.evidence_key='fence:old-writer-v1' THEN RAISE(ABORT,'financial_audit_immutable') END);
`);
export const FINANCIAL_FENCE_OBJECTS_V1=[
 {name:'financial_fence_owner_idx_v1',type:'index',sql:`CREATE INDEX IF NOT EXISTS financial_fence_owner_idx_v1 ON ${table}(json_extract(payload_json,'$._owner_key'),json_extract(payload_json,'$.state')) WHERE substr(evidence_key,1,11)='acceptance:'`},
 {name:'financial_fence_scope_idx_v1',type:'index',sql:`CREATE INDEX IF NOT EXISTS financial_fence_scope_idx_v1 ON ${table}(json_extract(payload_json,'$._scope_key')) WHERE substr(evidence_key,1,11)='acceptance:'`},
 {name:'financial_fence_booking_idx_v1',type:'index',sql:`CREATE INDEX IF NOT EXISTS financial_fence_booking_idx_v1 ON ${table}(json_extract(payload_json,'$.evidence.id')) WHERE substr(evidence_key,1,8)='booking:'`},insertion,update,stamp,deletion,...FINANCIAL_HISTORICAL_HOLD_OBJECTS_V1];
const backfill=`UPDATE ${table} SET payload_json=json_set(payload_json,'$._owner_key',(SELECT ${owner('q.payload_json')} FROM ${table} q WHERE q.evidence_key='quote:'||substr(${table}.evidence_key,12)),'$._scope_key',(SELECT ${scope('q.payload_json')} FROM ${table} q WHERE q.evidence_key='quote:'||substr(${table}.evidence_key,12))) WHERE substr(evidence_key,1,11)='acceptance:' AND json_extract(payload_json,'$.state') IS NOT 'closed' AND json_extract(payload_json,'$._scope_key') IS NULL`;
export const FINANCIAL_FENCE_MIGRATION_V1=[...FINANCIAL_FENCE_OBJECTS_V1.slice(0,3).map(x=>x.sql),backfill,...FINANCIAL_FENCE_OBJECTS_V1.slice(3).map(x=>x.sql),`INSERT OR IGNORE INTO ${table}(evidence_key,payload_json) VALUES('fence:old-writer-v1','{"version":1}')`];
const normalized=sql=>sql.replace(/IF NOT EXISTS\s+/gi,'').replace(/\s+/g,' ').replace(/;\s*$/,'').trim();
export async function assertFinancialAcceptanceFenceV1(db){
 const row=await db.prepare("SELECT json_group_array(json_object('name',name,'sql',sql,'type',type)) AS objects FROM sqlite_master WHERE name LIKE 'financial_fence_%_v1'").bind().first();
 const actual=JSON.parse(row?.objects??'[]');
 if(FINANCIAL_FENCE_OBJECTS_V1.some(x=>!actual.some(a=>a.name===x.name&&a.type===x.type&&normalized(a.sql??'')===normalized(x.sql))))throw Error('financial_recovery_storage_fence_required');
 const marker=await db.prepare(`SELECT payload_json FROM ${table} WHERE evidence_key='fence:old-writer-v1'`).bind().first();
 if(marker?.payload_json!=='{"version":1}')throw Error('financial_recovery_storage_fence_required');
}
export async function installFinancialAcceptanceFenceV1(db){
 if(typeof db?.batch!=='function')throw Error('financial_fence_atomic_migration_required');
 const row=await db.prepare("SELECT json_group_array(json_object('name',name,'sql',sql,'type',type)) AS objects FROM sqlite_master WHERE name LIKE 'financial_fence_%_v1'").bind().first();
 const existing=JSON.parse(row?.objects??'[]');
 if(existing.some(a=>!FINANCIAL_FENCE_OBJECTS_V1.some(x=>a.name===x.name&&a.type===x.type&&normalized(a.sql??'')===normalized(x.sql))))throw Error('financial_fence_existing_definition_conflict');
 await db.batch(FINANCIAL_FENCE_MIGRATION_V1.map(sql=>db.prepare(sql)));await assertFinancialAcceptanceFenceV1(db);
}
