// Operator-installed execution hold, not settlement, close, owner adoption or
// release of an accepted claim. Original quote/claim/frozen rows remain intact.
const table='financial_route_evidence_v1';
export const HISTORICAL_HOLD_PREFIX='historical-hold:';
export function validHistoricalExecutionHoldV1(hold,{quote,claim,frozen}){
 return !!hold&&hold.schema==='fluxidi-historical-execution-hold-v1'&&hold.effect==='deny_execution_preserve_evidence'&&hold.payment_settled===false
  &&/^[a-f0-9]{64}$/.test(hold.source_capture_sha256??'')&&hold.financial_quote_id===quote?.id&&hold.booking_id===claim?.booking_id&&hold.booking_id===frozen?.booking_id
  &&frozen?.evidence?.id===quote?.id&&claim?.state==null&&claim?._owner_key==null&&quote?.inputs?.financial_context?.customer_id==null
  &&hold.scope?.tenant_id===quote?.scope?.tenant_id&&hold.scope?.company_id===quote?.scope?.company_id;
}
export const historicalHoldExistsSql=(quoteId,bookingId)=>`EXISTS(SELECT 1 FROM ${table} h WHERE h.evidence_key='historical-hold:'||${quoteId} AND json_extract(h.payload_json,'$.schema')='fluxidi-historical-execution-hold-v1' AND json_extract(h.payload_json,'$.financial_quote_id')=${quoteId} AND json_extract(h.payload_json,'$.booking_id')=${bookingId})`;
const historical="substr(NEW.evidence_key,1,16)='historical-hold:'";
const id='substr(NEW.evidence_key,17)';
export const FINANCIAL_HISTORICAL_HOLD_OBJECTS_V1=[
 {name:'financial_fence_historical_insert_v1',type:'trigger',sql:`CREATE TRIGGER IF NOT EXISTS financial_fence_historical_insert_v1 BEFORE INSERT ON ${table} BEGIN
 SELECT (CASE WHEN ${historical} AND (json_valid(NEW.payload_json)=0 OR json_extract(NEW.payload_json,'$.schema') IS NOT 'fluxidi-historical-execution-hold-v1' OR json_extract(NEW.payload_json,'$.financial_quote_id') IS NOT ${id} OR json_extract(NEW.payload_json,'$.effect') IS NOT 'deny_execution_preserve_evidence' OR json_extract(NEW.payload_json,'$.payment_settled') IS NOT 0 OR length(json_extract(NEW.payload_json,'$.source_capture_sha256')) IS NOT 64 OR NOT EXISTS(SELECT 1 FROM ${table} a JOIN ${table} q ON q.evidence_key='quote:'||${id} JOIN ${table} b ON substr(b.evidence_key,1,8)='booking:' AND json_extract(b.payload_json,'$.evidence.id')=${id} WHERE a.evidence_key='acceptance:'||${id} AND json_extract(a.payload_json,'$.state') IS NULL AND json_extract(a.payload_json,'$._owner_key') IS NULL AND json_extract(q.payload_json,'$.inputs.financial_context.customer_id') IS NULL AND json_extract(a.payload_json,'$.booking_id')=json_extract(NEW.payload_json,'$.booking_id') AND json_extract(b.payload_json,'$.booking_id')=json_extract(a.payload_json,'$.booking_id') AND json_extract(q.payload_json,'$.scope.tenant_id')=json_extract(NEW.payload_json,'$.scope.tenant_id') AND json_extract(q.payload_json,'$.scope.company_id')=json_extract(NEW.payload_json,'$.scope.company_id'))) THEN RAISE(ABORT,'financial_historical_hold_binding_invalid') END);
 SELECT (CASE WHEN ${historical} AND EXISTS(SELECT 1 FROM ${table} h WHERE h.evidence_key=NEW.evidence_key AND h.payload_json<>NEW.payload_json) THEN RAISE(ABORT,'financial_historical_hold_immutable') END);
 SELECT (CASE WHEN substr(NEW.evidence_key,1,11)='acceptance:' AND EXISTS(SELECT 1 FROM ${table} h WHERE h.evidence_key='historical-hold:'||substr(NEW.evidence_key,12)) THEN RAISE(ABORT,'financial_historical_execution_held') END);
 SELECT (CASE WHEN substr(NEW.evidence_key,1,8)='booking:' AND EXISTS(SELECT 1 FROM ${table} h WHERE h.evidence_key='historical-hold:'||json_extract(NEW.payload_json,'$.evidence.id')) THEN RAISE(ABORT,'financial_historical_execution_held') END);
 END`},
 {name:'financial_fence_historical_update_v1',type:'trigger',sql:`CREATE TRIGGER IF NOT EXISTS financial_fence_historical_update_v1 BEFORE UPDATE ON ${table} BEGIN
 SELECT (CASE WHEN substr(OLD.evidence_key,1,16)='historical-hold:' OR substr(NEW.evidence_key,1,16)='historical-hold:' THEN RAISE(ABORT,'financial_historical_hold_immutable') END);
 SELECT (CASE WHEN substr(OLD.evidence_key,1,11)='acceptance:' AND EXISTS(SELECT 1 FROM ${table} h WHERE h.evidence_key='historical-hold:'||substr(OLD.evidence_key,12)) AND NEW.payload_json<>OLD.payload_json THEN RAISE(ABORT,'financial_historical_execution_held') END);
 END`},
 {name:'financial_fence_historical_delete_v1',type:'trigger',sql:`CREATE TRIGGER IF NOT EXISTS financial_fence_historical_delete_v1 BEFORE DELETE ON ${table} BEGIN
 SELECT (CASE WHEN substr(OLD.evidence_key,1,16)='historical-hold:' THEN RAISE(ABORT,'financial_historical_hold_immutable') END);
 END`},
];
