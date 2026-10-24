const finite = p => p && Number.isFinite(p.latitude) && Number.isFinite(p.longitude)
  && Math.abs(p.latitude) <= 90 && Math.abs(p.longitude) <= 180;
export function sphericalDistance(a, b) {
  const rad = Math.PI / 180, dy = (b.latitude-a.latitude)*rad, dx = (b.longitude-a.longitude)*rad;
  const h = Math.sin(dy/2)**2 + Math.cos(a.latitude*rad)*Math.cos(b.latitude*rad)*Math.sin(dx/2)**2;
  return 6371008.8 * 2 * Math.asin(Math.sqrt(Math.min(1,Math.max(0,h))));
}
// This is derived advisory state. A bounded index may omit entries at its
// memory limit; complete=false requires callers to use exhaustive discovery.
export function createActiveSpatialIndex(scope, { maxEntries = 4096, cellDegrees = .01, freshnessMs = 180000 } = {}) {
  if (!scope?.tenant_id || !scope.company_id || !Number.isInteger(maxEntries) || maxEntries < 1 || maxEntries > 16384
    || !(cellDegrees > 0 && cellDegrees <= 1) || !(freshnessMs > 0)) throw Error('spatial_index_options_invalid');
  const rows = new Map(), cells = new Map(); let overflow = false;
  const cell = p => `${Math.floor(p.latitude/cellDegrees)}:${Math.floor(p.longitude/cellDegrees)}`;
  const remove = id => { const old=rows.get(id);if(!old)return;const set=cells.get(old.cell);set.delete(id);if(!set.size)cells.delete(old.cell);rows.delete(id); };
  const update = (row, nowMs = Date.now()) => {
    const id=row?.driver_id;if(typeof id!=='string'||!id||id.length>128)return false;
    if(row.tenant_id!==scope.tenant_id||row.company_id!==scope.company_id) return false;
    const at=Date.parse(row.position_captured_at||row.captured_at||row.updated_at||row.last_seen_at||'');
    const old=rows.get(id);if(old&&Number.isFinite(at)&&at<old.at)return false;
    if(!finite(row)||!row.vehicle_id||!Number.isFinite(at)||nowMs-at>freshnessMs||at>nowMs+120000
      ||row.location_withdrawn===true||row.availability_status==='offline'||row.availability_status==='paused'||row.is_active===false){remove(id);return true;}
    if(!old&&rows.size>=maxEntries){overflow=true;return false;}
    const key=cell(row);if(old?.cell!==key){remove(id);if(!cells.has(key))cells.set(key,new Set());cells.get(key).add(id);}
    rows.set(id,{...row,at,cell:key});return true;
  };
  return { update, remove, get size(){return rows.size;}, get cellCount(){return cells.size;},
    rebuild(values,nowMs=Date.now()){rows.clear();cells.clear();overflow=false;for(const row of values)update(row,nowMs);},
    ordered(target,nowMs=Date.now()){
      if(!finite(target))return{rows:[],complete:false,cells_visited:0};
      const visited=[];for(const [key,ids]of cells){const candidates=[...ids].map(id=>rows.get(id)).filter(row=>nowMs-row.at<=freshnessMs);
        if(candidates.length)visited.push({key,rows:candidates,distance:Math.min(...candidates.map(row=>sphericalDistance(row,target)))});}
      visited.sort((a,b)=>a.distance-b.distance||a.key.localeCompare(b.key));
      const ordered=visited.flatMap(cell=>cell.rows).sort((a,b)=>sphericalDistance(a,target)-sphericalDistance(b,target)||a.driver_id.localeCompare(b.driver_id));
      return{rows:ordered,complete:!overflow,cells_visited:visited.length};
    },
  };
}
