// Local release preparation only. No default network client, persistence, cache,
// route fallback, or production switch. The caller must supply authenticated
// admission and an atomic shared cost reservation BEFORE any paid request.
const contexts = new WeakMap();
const previews = new WeakMap();
const areaPoints = new WeakMap();
const fail = code => { throw Object.assign(new Error(code), {route_error_code:code}); };
const finite = n => typeof n === 'number' && Number.isFinite(n) && n >= 0;
const point = p => p && typeof p.lat === 'number' && typeof p.lng === 'number'
  && Number.isFinite(p.lat) && Number.isFinite(p.lng) && Math.abs(p.lat)<=90 && Math.abs(p.lng)<=180;
const sameScope = (a,b) => a?.tenant_id===b?.tenant_id && a?.company_id===b?.company_id;
const metersBetween = (a,b) => {
  const rad=Math.PI/180,dlat=(b.lat-a.lat)*rad,dlng=(b.lng-a.lng)*rad;
  const h=Math.sin(dlat/2)**2+Math.cos(a.lat*rad)*Math.cos(b.lat*rad)*Math.sin(dlng/2)**2;
  return 6371008.8*2*Math.asin(Math.sqrt(Math.min(1,Math.max(0,h))));
};

export function createMapboxQuoteTransportV1({scope,send,reserve,expiresAt,maxRequests=4,timeoutMs=10000,maxBytes=2097152,clock=Date.now,pointPolicy='proven_anchor_v1'}) {
  if (!scope?.tenant_id || !scope?.company_id || typeof send!=='function' || typeof reserve!=='function'
    || !Number.isSafeInteger(expiresAt) || expiresAt<=clock()
    || !Number.isSafeInteger(maxRequests) || maxRequests<1 || maxRequests>8
    || !Number.isSafeInteger(timeoutMs) || timeoutMs<1 || timeoutMs>10000
    || !Number.isSafeInteger(maxBytes) || maxBytes<1 || maxBytes>2097152
    || !['proven_anchor_v1','customer_selected_v1'].includes(pointPolicy)
    || pointPolicy==='customer_selected_v1'&&maxRequests>4) fail('mapbox_quote_transport_not_configured');
  const context=Object.freeze({});
  contexts.set(context,{scope:{...scope},send,reserve,expiresAt,maxRequests,timeoutMs,maxBytes,clock,pointPolicy,
    reserved:0,directionsRequests:0,geocodingRequests:0,matrixElements:0,responseBytes:0});
  return context;
}
export function mapboxQuoteTransportMetricsV1(context) {
  const c=contexts.get(context);if(!c)fail('mapbox_quote_context_required');
  return {directions_requests:c.directionsRequests,...(c.geocodingRequests?{geocoding_requests:c.geocodingRequests}:{}),matrix_elements:c.matrixElements,response_bytes:c.responseBytes,reservations:c.reserved};
}

// Only a server-created Customer request may register an exact selected point.
// This opaque capability attests lookup binding, never road or driver access.
export function bindMapboxQuoteAreaPointV1({context,scope,point:selected}) {
  const c=contexts.get(context);
  if(!c||!sameScope(c.scope,scope)||c.pointPolicy!=='customer_selected_v1')fail('mapbox_quote_area_context_required');
  if(c.clock()>=c.expiresAt)fail('mapbox_quote_context_expired');
  if(!point(selected)||selected.lat===0&&selected.lng===0)fail('mapbox_quote_points_invalid');
  const capability=Object.freeze({});
  areaPoints.set(capability,{context,scope:{...c.scope},point:{lat:selected.lat,lng:selected.lng}});
  return capability;
}
const areaText=value=>typeof value==='string'&&value.length<=120&&!/[\x00-\x1f\x7f]/.test(value)?value.normalize('NFC').trim().replace(/\s+/g,' '):'';
function mapboxAreaFields(data,selected) {
  if(data?.type!=='FeatureCollection'||!Array.isArray(data.features)||!data.features.length||data.features.length>20)fail('mapbox_quote_area_unavailable');
  const candidates=[];
  const bbox=(value,position)=>{
    if(value==null)return;
    if(!Array.isArray(value)||value.length!==4||!value.every(Number.isFinite)||value[0]<-180||value[2]>180||value[1]<-90||value[3]>90||value[0]>value[2]||value[1]>value[3]
      ||position.lng<value[0]-1e-7||position.lng>value[2]+1e-7||position.lat<value[1]-1e-7||position.lat>value[3]+1e-7)fail('mapbox_quote_area_point_mismatch');
  };
  for(const feature of data.features){
    if(!Array.isArray(feature?.place_type)||!feature.place_type.some(kind=>kind==='address'||kind==='poi'))continue;
    if(feature.type!=='Feature')fail('mapbox_quote_area_unavailable');
    const center=feature.center;
    if(!Array.isArray(center)||center.length!==2||!point({lng:center[0],lat:center[1]}))fail('mapbox_quote_area_point_mismatch');
    const position={lng:center[0],lat:center[1]};
    if(metersBetween(selected,position)>500)fail('mapbox_quote_area_point_mismatch');
    if(feature.geometry!=null&&(feature.geometry.type!=='Point'||!Array.isArray(feature.geometry.coordinates)||feature.geometry.coordinates.length!==2
      ||!point({lng:feature.geometry.coordinates[0],lat:feature.geometry.coordinates[1]})
      ||metersBetween(position,{lng:feature.geometry.coordinates[0],lat:feature.geometry.coordinates[1]})>1))fail('mapbox_quote_area_point_mismatch');
    bbox(feature.bbox,selected);bbox(feature.bbox,position);
    if(!Array.isArray(feature.context)||feature.context.length>32)fail('mapbox_quote_area_unavailable');
    const context=feature.context;
    const entries=prefix=>context.filter(row=>typeof row?.id==='string'&&row.id.startsWith(prefix+'.'));
    const unique=(values,reason)=>{const normalized=[...new Set(values.map(areaText).filter(Boolean))];if(normalized.length!==1)fail(reason);return normalized[0];};
    const country=unique(entries('country').map(row=>row.short_code??row.shortCode),'mapbox_quote_area_country_invalid').toUpperCase();
    if(!['BE','NL'].includes(country))fail('mapbox_quote_area_country_invalid');
    const postcodeValues=[...entries('postcode').map(row=>row.text??row.text_en),...(feature.properties?.postcode!=null?[feature.properties.postcode]:[])];
    const postcode=unique(postcodeValues.map(value=>areaText(value).replace(/\s/g,'').toUpperCase()),'mapbox_quote_area_postcode_invalid');
    if(!(country==='BE'?/^[1-9]\d{3}$/:/^[1-9]\d{3}[A-Z]{2}$/).test(postcode))fail('mapbox_quote_area_postcode_invalid');
    const places=entries('place'),localities=entries('locality');
    const city=unique((places.length?places:localities).map(row=>row.text??row.text_en),'mapbox_quote_area_city_unavailable');
    for(const row of [...entries('postcode'),...entries('country'),...places,...localities])bbox(row.bbox,selected);
    // A nearby building's postcode is not the selected point's postcode.
    // Only a provider postcode-area bound covering BOTH positions, or the
    // same returned point within serialization tolerance, grants this field.
    // A POI/building bbox cannot stand in for a postcode-area boundary.
    const postcodeBounds=entries('postcode').filter(row=>row.bbox!=null);
    for(const row of postcodeBounds)bbox(row.bbox,position);
    if(!postcodeBounds.length&&metersBetween(selected,position)>1)fail('mapbox_quote_area_point_mismatch');
    candidates.push({postcode,country,city});
  }
  if(!candidates.length)fail('mapbox_quote_area_unavailable');
  if(new Set(candidates.map(value=>JSON.stringify(value))).size!==1)fail('mapbox_quote_area_ambiguous');
  return {source:'mapbox_reverse_area_v1',...candidates[0]};
}

// The same request-private lease, shared slot, four-call budget and response
// bounds as Directions. No unbounded/global geocoder or national fallback.
export async function boundedMapboxQuoteAreaV1({context,scope,point:selected,token,pointCapability}) {
  const c=contexts.get(context),proof=areaPoints.get(pointCapability);
  if(!c||!sameScope(c.scope,scope)||c.pointPolicy!=='customer_selected_v1')fail('mapbox_quote_area_context_required');
  if(!proof||proof.context!==context||!sameScope(proof.scope,scope)||!point(selected)||proof.point.lat!==selected.lat||proof.point.lng!==selected.lng)fail('mapbox_quote_area_point_unbound');
  if(c.clock()>=c.expiresAt)fail('mapbox_quote_context_expired');
  if(typeof token!=='string'||!token.trim())fail('route_config_missing');
  selected={...proof.point};
  if(c.reserved>=c.maxRequests)fail('mapbox_quote_request_limit');
  c.reserved++;
  const url=new URL(`https://api.mapbox.com/geocoding/v5/mapbox.places/${selected.lng},${selected.lat}.json`);
  url.search=new URLSearchParams({limit:'1',types:'address,poi',language:'nl',country:'be,nl',access_token:token.trim()}).toString();
  const controller=new AbortController();let timer;
  const work=async()=>{
    let admitted;
    try{admitted=await c.reserve({scope:{...c.scope},directionsRequests:0,geocodingRequests:1,matrixElements:0});}
    catch{fail('mapbox_quote_shared_budget_denied');}
    if(controller.signal.aborted)fail('mapbox_quote_timeout');
    if(c.clock()>=c.expiresAt)fail('mapbox_quote_context_expired');
    if(admitted!==true)fail('mapbox_quote_shared_budget_denied');
    c.geocodingRequests++;
    let response;
    try{response=await c.send(url.toString(),{signal:controller.signal,redirect:'manual',cache:'no-store'});}
    catch{fail(controller.signal.aborted?'mapbox_quote_timeout':'mapbox_quote_transport_error');}
    if(!response.ok){await response.body?.cancel();fail(response.status===429?'mapbox_quote_provider_limited':'mapbox_quote_provider_http_error');}
    const announced=response.headers.get('content-length');
    if(announced!=null&&(!/^\d+$/.test(announced)||Number(announced)>c.maxBytes)){await response.body?.cancel();fail('mapbox_quote_response_limit');}
    const reader=response.body?.getReader();if(!reader)fail('mapbox_quote_response_invalid');
    const chunks=[];let size=0;
    try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;c.responseBytes+=value.byteLength;if(size>c.maxBytes)fail('mapbox_quote_response_limit');chunks.push(value);}}
    finally{if(controller.signal.aborted||size>c.maxBytes)await reader.cancel();reader.releaseLock();}
    const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
    let data;try{data=JSON.parse(new TextDecoder().decode(bytes));}catch{fail('mapbox_quote_response_invalid');}
    if(controller.signal.aborted)fail('mapbox_quote_timeout');
    if(c.clock()>=c.expiresAt)fail('mapbox_quote_context_expired');
    return mapboxAreaFields(data,selected);
  };
  try{return await Promise.race([work(),new Promise((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(Object.assign(new Error('mapbox_quote_timeout'),{route_error_code:'mapbox_quote_timeout'}));},Math.min(c.timeoutMs,c.expiresAt-c.clock()));})]);}
  catch(error){if(/^mapbox_quote_[a-z_]+$/.test(error?.message??''))throw error;fail('mapbox_quote_transport_error');}
  finally{clearTimeout(timer);controller.abort();}
}
export function mapboxQuotePreviewV1(routeOut) {
  const value=previews.get(routeOut);if(!value)return null;
  if(value.distance_m!==routeOut.route?.distance||value.duration_s!==routeOut.route?.duration
    ||JSON.stringify(value.geometry)!==JSON.stringify(routeOut.route?.geometry)
    ||JSON.stringify(value.points)!==JSON.stringify(routeOut.financial_route?.points)
    ||routeOut.financial_route?.source!=='mapbox')fail('mapbox_quote_context_changed');
  return structuredClone(value);
}

// Same Directions v5 driving endpoint/leg units as directionsMultiUnobserved.
// This opt-in branch adds geometry in that ONE response, not a second route.
export async function boundedMapboxQuoteDirectionsV1({context,scope,coords,token,radiuses,bearings=null}) {
  const c=contexts.get(context);
  if(!c || !sameScope(c.scope,scope))fail('mapbox_quote_scope_mismatch');
  if(c.clock()>=c.expiresAt)fail('mapbox_quote_context_expired');
  if(typeof token!=='string'||!token.trim())fail('route_config_missing');
  if(!Array.isArray(coords)||coords.length<2||coords.length>10||!coords.every(point))fail('mapbox_quote_points_invalid');
  // Customer selections use the existing Directions default snap in ONE
  // request. This private policy cannot be selected by booking JSON. Other
  // callers still require their independently proven road-anchor radii.
  const customerSelection=c.pointPolicy==='customer_selected_v1'&&radiuses===null;
  if(!customerSelection&&(!Array.isArray(radiuses)||radiuses.length!==coords.length||radiuses.some(r=>!finite(r)||r<=0||r>50)))fail('mapbox_quote_access_radius_invalid');
  // Freeze the validated request before the asynchronous shared reservation.
  // A caller mutation must not change the coordinates which were admitted.
  coords=coords.map(p=>({lat:p.lat,lng:p.lng}));radiuses=customerSelection?null:[...radiuses];
  if(bearings!=null&&(!Array.isArray(bearings)||bearings.length!==coords.length||bearings.some(b=>b!=null&&(!Array.isArray(b)||b.length!==2||!finite(b[0])||b[0]>=360||!finite(b[1])||b[1]>35))))fail('mapbox_quote_bearing_invalid');
  if(bearings)bearings=structuredClone(bearings);
  if(c.reserved>=c.maxRequests)fail('mapbox_quote_request_limit');
  c.reserved++;
  if(await c.reserve({scope:{...c.scope},directionsRequests:1,matrixElements:0})!==true)fail('mapbox_quote_shared_budget_denied');
  if(c.clock()>=c.expiresAt)fail('mapbox_quote_context_expired');
  const path=coords.map(p=>`${p.lng},${p.lat}`).join(';');
  const url=new URL(`https://api.mapbox.com/directions/v5/mapbox/driving/${path}`);
  url.search=new URLSearchParams({overview:'full',geometries:'geojson',steps:'false',alternatives:'false',
    access_token:token.trim()}).toString();
  if(radiuses)url.searchParams.set('radiuses',radiuses.join(';'));
  if(bearings)url.searchParams.set('bearings',bearings.map(b=>b?b.join(','):'').join(';'));
  const controller=new AbortController();let timer;
  const work=async()=>{
    c.directionsRequests++;
    let response;
    // Workers supports manual/follow only. Manual never forwards our token;
    // the existing non-2xx guard below rejects every redirect response.
    try { response=await c.send(url.toString(),{signal:controller.signal,redirect:'manual',cache:'no-store'}); }
    catch { fail(controller.signal.aborted?'mapbox_quote_timeout':'mapbox_quote_transport_error'); }
    if(!response.ok){await response.body?.cancel();fail(response.status===429?'mapbox_quote_provider_limited':'mapbox_quote_provider_http_error');}
    const announced=response.headers.get('content-length');
    if(announced!=null&&(!/^\d+$/.test(announced)||Number(announced)>c.maxBytes)){await response.body?.cancel();fail('mapbox_quote_response_limit');}
    const reader=response.body?.getReader();if(!reader)fail('mapbox_quote_response_invalid');
    const chunks=[];let size=0;
    try { for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;c.responseBytes+=value.byteLength;
      if(size>c.maxBytes)fail('mapbox_quote_response_limit');chunks.push(value);} }
    finally {if(controller.signal.aborted||size>c.maxBytes)await reader.cancel();reader.releaseLock();}
    const bytes=new Uint8Array(size);let offset=0;for(const b of chunks){bytes.set(b,offset);offset+=b.length;}
    let data;try{data=JSON.parse(new TextDecoder().decode(bytes));}catch{fail('mapbox_quote_response_invalid');}
    if(data?.code!=='Ok')fail(data?.code==='NoSegment'?'mapbox_quote_no_segment':'mapbox_quote_no_route');
    const r=data.routes?.[0],w=data.waypoints;
    if(!r||!finite(r.distance)||!finite(r.duration)||!Array.isArray(r.legs)||r.legs.length!==coords.length-1
      ||r.legs.some(l=>!finite(l.distance)||!finite(l.duration))
      ||Math.abs(r.legs.reduce((s,l)=>s+l.distance,0)-r.distance)>1
      ||Math.abs(r.legs.reduce((s,l)=>s+l.duration,0)-r.duration)>1)fail('mapbox_quote_route_inconsistent');
    // Same maximum as the existing bounded legacy retry, without retries.
    // Preserve the selected address; provider waypoints are route geometry.
    const waypointLimits=customerSelection?coords.map(()=>500):radiuses;
    if(!Array.isArray(w)||w.length!==coords.length||w.some((p,i)=>!finite(p.distance)||p.distance>waypointLimits[i]
      ||!Array.isArray(p.location)||p.location.length!==2||!point({lng:p.location[0],lat:p.location[1]})
      ||metersBetween(coords[i],{lng:p.location[0],lat:p.location[1]})>waypointLimits[i]))fail('mapbox_quote_waypoints_unproven');
    const g=r.geometry;
    if(g?.type!=='LineString'||!Array.isArray(g.coordinates)||g.coordinates.length<2||g.coordinates.length>100000
      ||g.coordinates.some(p=>!Array.isArray(p)||p.length!==2||!point({lng:p[0],lat:p[1]})))fail('mapbox_quote_geometry_invalid');
    // Full geometry must begin/end on the returned snapped waypoints. One
    // metre accommodates coordinate serialization; this is NOT access proof.
    for(const [gpos,wpos] of [[g.coordinates[0],w[0].location],[g.coordinates.at(-1),w.at(-1).location]]){
      if(metersBetween({lng:gpos[0],lat:gpos[1]},{lng:wpos[0],lat:wpos[1]})>1)fail('mapbox_quote_geometry_binding');
    }
    if(c.clock()>=c.expiresAt)fail('mapbox_quote_context_expired');
    // Only the fields already consumed by the price engine. Drop raw waypoint
    // names, provider UUIDs, manoeuvres and all other response data here.
    return {distance:r.distance,duration:r.duration,geometry:structuredClone(g),
      legs:r.legs.map(l=>({distance:l.distance,duration:l.duration}))};
  };
  try { return await Promise.race([work(),new Promise((_,reject)=>{timer=setTimeout(()=>{
    controller.abort();reject(Object.assign(new Error('mapbox_quote_timeout'),{route_error_code:'mapbox_quote_timeout'}));},c.timeoutMs);})]); }
  catch(error){if(/^mapbox_quote_[a-z_]+$/.test(error?.message??''))throw error;fail('mapbox_quote_transport_error');}
  finally {clearTimeout(timer);controller.abort();}
}

// Transient route presentation only; does not approve financial persistence.
export function bindMapboxQuotePreviewV1(routeOut) {
  const p=routeOut?.financial_route,r=routeOut?.route;
  if(p?.source!=='mapbox'||p.source_version!=='directions/v5'||p.profile!=='mapbox/driving'||p.duration_basis!=='provider_driving'
    ||!Array.isArray(p.points)||!p.points.every(point)||p.points.length<2||p.points.length>10
    ||!Array.isArray(p.legs)||p.legs.length!==p.points.length-1
    ||!finite(r?.distance)||!finite(r?.duration)||!Array.isArray(r.legs)||r.legs.length!==p.legs.length
    ||p.legs.some((l,i)=>!finite(l.distance_m)||!finite(l.duration_s)||l.distance_m!==r.legs[i].distance||l.duration_s!==r.legs[i].duration)
    ||Math.abs(p.legs.reduce((s,l)=>s+l.distance_m,0)-r.distance)>1||Math.abs(p.legs.reduce((s,l)=>s+l.duration_s,0)-r.duration)>1
    ||r.geometry?.type!=='LineString'||!Array.isArray(r.geometry.coordinates)||r.geometry.coordinates.length<2||r.geometry.coordinates.length>100000
    ||r.geometry.coordinates.some(p=>!Array.isArray(p)||p.length!==2||!point({lng:p[0],lat:p[1]})))fail('mapbox_quote_preview_invalid');
  previews.set(routeOut,{schema:'fluxidi-quote-route-preview-v1',source:'mapbox',source_version:'directions/v5',profile:'mapbox/driving',
    duration_basis:'provider_driving',points:structuredClone(p.points),geometry:structuredClone(r.geometry),distance_m:r.distance,duration_s:r.duration});
  return routeOut;
}
