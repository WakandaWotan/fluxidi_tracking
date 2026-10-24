import {sha256Hex} from './crypto_utils.js';
export async function fleetSyncFingerprint(metadata,vehicles){if(!metadata||!Number.isSafeInteger(metadata.generation)||!Number.isSafeInteger(metadata.presence_revision))return null;return sha256Hex(JSON.stringify([metadata.generation,metadata.presence_revision,vehicles]));}
export function fleetSyncValidUntil(drivers,now){
 let until=(Math.floor(now/60000)+1)*60000;
 for(const driver of drivers){const seen=Date.parse(driver.last_seen_at||'');if(Number.isFinite(seen)){for(const boundary of [seen-120000,seen+180001])if(boundary>now)until=Math.min(until,boundary);}
  const override=Date.parse(driver.manual_override?.until||'');if(Number.isFinite(override)&&override>now)until=Math.min(until,override);
 }
 return until;
}
export function createFleetSyncProbe(){let saved=null;return{
 remember(scope,fingerprint,revision,drivers,now){saved=fingerprint?{scope:JSON.stringify([scope.tenant_id,scope.company_id]),fingerprint,revision,at:now,until:fleetSyncValidUntil(drivers,now)}:null;},
 probe(scope,fingerprint,since,now){return Boolean(saved&&saved.scope===JSON.stringify([scope.tenant_id,scope.company_id])&&saved.fingerprint===fingerprint&&saved.revision===since&&now>=saved.at&&now<saved.until);}
};}
