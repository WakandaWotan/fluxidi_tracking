import {boundedMapboxQuoteDirectionsV1,boundedMapboxQuoteAreaV1,bindMapboxQuoteAreaPointV1} from './mapbox_quote_transport_v1.mjs';

// Customer-selected locations only. The parent creates the private request
// capability after resolving company authority and cost admission. Neither a
// public JSON flag nor an official-looking address reference grants authority.
// This adapter deliberately performs no national-index, graph or storage read.
const fail=reason=>{throw Error(reason);};
const text=value=>typeof value==='string'?value.normalize('NFC').trim().replace(/\s+/g,' '):'';
const canonical=value=>JSON.stringify(value,(_,v)=>v&&typeof v==='object'&&!Array.isArray(v)
  ?Object.fromEntries(Object.keys(v).sort().map(k=>[k,v[k]])):v);
const point=value=>value&&typeof value.lat==='number'&&typeof value.lng==='number'
  &&Number.isFinite(value.lat)&&Math.abs(value.lat)<=90&&Number.isFinite(value.lng)&&Math.abs(value.lng)<=180
  &&!(value.lat===0&&value.lng===0);
const same=(a,b)=>a?.lat===b?.lat&&a?.lng===b?.lng;
const wire=value=>({lat:value.lat,lng:value.lng});
const label=value=>typeof value==='string'&&value.length<=500&&!/[\r\n\0]/.test(value)&&text(value).length>0;

export function createCustomerMapboxQuoteApiV1({scope,body,locations,transport,token,
  clock=Date.now,expiresAt=clock()+15000,reuseDirections=(_,resolve)=>resolve(),reuseArea=(_,resolve)=>resolve(),missionDepot=null,sealMissionProof=null}){
  const now=clock();
  if(!scope?.tenant_id||!scope?.company_id||!body||typeof body!=='object'||Array.isArray(body)
    ||!Array.isArray(locations)||locations.length<2||locations.length>17||typeof reuseDirections!=='function'||typeof reuseArea!=='function'
    ||!Number.isSafeInteger(expiresAt)||expiresAt<=now||expiresAt>now+15000)fail('mapbox_quote_request_configuration');
  scope=structuredClone(scope);
  body=structuredClone(body);
  const depot=missionDepot==null?null:structuredClone(missionDepot);
  if(depot&&(!point(depot)||typeof sealMissionProof!=='function'))fail('mission_depot_required');
  const registered=structuredClone(locations).map(location=>{
    if(!label(location?.label)||!point(location))fail('mapbox_quote_location_required');
    const input=location.input;
    // Existing fully scoped requests may carry an opaque official reference
    // without a repeated label. Keep it as immutable input only; this provider
    // adapter neither verifies nor derives authority from that reference.
    const legacyReferenceLabel=input?.kind==='address'&&input.official_address!=null&&input.label==null;
    if(!input||!['address','gps'].includes(input.kind)||!legacyReferenceLabel&&(!label(input.label)||text(input.label)!==text(location.label)))fail('mapbox_quote_location_unbound');
    if((Object.hasOwn(input,'lat')||Object.hasOwn(input,'lng'))&&(!point(input)||!same(input,location)))fail('mapbox_quote_location_unbound');
    if(input.kind==='gps'&&(input.official_address!=null||input.address!=null))fail('mapbox_quote_location_unbound');
    return {label:text(location.label),original:wire(location),input};
  });
  const assertGps=record=>{
    if(record.input.kind!=='gps')return;
    const {capturedAt,accuracyMeters}=record.input,current=clock();
    if(typeof capturedAt!=='number'||!Number.isFinite(capturedAt)||capturedAt>current||current-capturedAt>30000
      ||typeof accuracyMeters!=='number'||!Number.isFinite(accuracyMeters)||accuracyMeters<=0||accuracyMeters>25)fail('access_gps_stale_or_accuracy');
  };
  const guard=()=>{if(clock()>=expiresAt)fail('mapbox_quote_context_expired');registered.forEach(assertGps);};
  guard();
  function find(value){
    if(!point(value))fail('mapbox_quote_points_invalid');
    const found=registered.filter(record=>same(record.original,value));
    if(!found.length)fail('mapbox_quote_location_unbound');
    if(new Set(found.map(record=>canonical({label:record.label,input:record.input}))).size>1)fail('mapbox_quote_location_ambiguous');
    return found[0];
  }
  const routes=new Map(),areas=new Map(),pendingAreas=new Map();let missionPoints=null;
  const api={
    financialRouteRetention:'sale_only',
    async geocode(value){
      guard();if(!label(value))fail('mapbox_quote_text_unbound');
      const found=registered.filter(record=>record.label===text(value));
      if(!found.length||new Set(found.map(record=>canonical(record.original))).size!==1)fail('mapbox_quote_text_unbound');
      return wire(found[0].original);
    },
    async selectedAddressForArea(value,{requirePostcode=false}={}){
      guard();const record=find(value);
      // Requested coordinates establish a position for the existing published
      // company-radius check. They do not attest a postcode or official ID.
      const result={point:{latitude:record.original.lat,longitude:record.original.lng},address:{}};
      if(!requirePostcode)return result;
      if(requirePostcode!==true)fail('mapbox_quote_area_unavailable');
      const key=canonical(record.original);
      if(areas.has(key)){guard();return structuredClone(areas.get(key));}
      if(pendingAreas.has(key)){const area=await pendingAreas.get(key);guard();return structuredClone(area);}
      const pending=(async()=>{
        const pointCapability=bindMapboxQuoteAreaPointV1({context:transport,scope,point:record.original});
        const area=await reuseArea({point:wire(record.original)},()=>{guard();return boundedMapboxQuoteAreaV1({context:transport,scope,point:record.original,token,pointCapability});});
        guard();
        if(area?.source!=='mapbox_reverse_area_v1'||!['BE','NL'].includes(area.country)||typeof area.postcode!=='string'
          ||!(area.country==='BE'?/^[1-9]\d{3}$/:/^[1-9]\d{3}[A-Z]{2}$/).test(area.postcode)
          ||!label(area.city))fail('mapbox_quote_area_unavailable');
        const answer={...result,address:{postcode:area.postcode,country:area.country,city:area.city},source:'mapbox_reverse_area_v1'};
        areas.set(key,structuredClone(answer));return answer;
      })();
      pendingAreas.set(key,pending);
      try{return structuredClone(await pending);}finally{pendingAreas.delete(key);}
    },
    async municipality(points){
      guard();if(!depot)fail('official_municipality_required');
      if(!Array.isArray(points)||points.length!==2)fail('mapbox_quote_points_invalid');
      return Promise.all(points.map(async p=>(await api.selectedAddressForArea(p,{requirePostcode:true})).address.city));
    },
    async proveMissionArea({scope:requestedScope=scope,depot:requestedDepot,body:journey,readStops}){
      guard();if(!depot)fail('customer_mapbox_mission_not_supported');
      if(!same(depot,requestedDepot))fail('mission_depot_required');
      if(requestedScope?.tenant_id!==scope.tenant_id||requestedScope?.company_id!==scope.company_id)fail('mapbox_quote_scope_mismatch');
      if(typeof readStops!=='function'||canonical(journey)!==canonical(body))fail('mapbox_quote_endpoint_binding');
      const names=readStops(journey);
      if(!Array.isArray(names)||names.length>6||(journey.stop_coordinates??[]).length!==names.length)fail('mapbox_quote_stop_binding');
      const from=await api.geocode(journey.from),to=await api.geocode(journey.to),stops=[];
      for(const [i,name]of names.entries()){
        const p=await api.geocode(name),stored=journey.stop_coordinates?.[i];
        if(stored?.address!==name||!same(p,stored)||stored.invalidated===true||stored.confirmed===false||stored.needs_confirmation===true||stored.needs_address_confirmation===true||stored.coordinates_valid===false||stored.coordinate_valid===false)fail('mapbox_quote_stop_binding');
        if(stored.input!=null&&canonical(stored.input)!==canonical(find(p).input))fail('mapbox_quote_stop_binding');
        stops.push(p);
      }
      const coords=[wire(depot),from,...stops,to,wire(depot)];
      missionPoints=canonical(coords);
      const r=await api.directions(coords);
      guard();return sealMissionProof(Object.freeze({ok:true,route_profile:'mapbox/driving',route_used_geocode_fallback:false,route_validation_unavailable:false,
        distance_meters:r.legs[0].distance,route_valid_until_ms:expiresAt,source:'mapbox',source_version:'directions/v5',access_proven:true}));
    },
    async directions(points){
      guard();if(!Array.isArray(points)||points.length<2||points.length>10)fail('mapbox_quote_points_invalid');
      const mission=depot&&points.length>=4&&same(points[0],depot)&&same(points.at(-1),depot);
      if(mission&&canonical(points.map(wire))!==missionPoints)fail('mapbox_quote_endpoint_binding');
      const coords=points.map((value,i)=>mission&&(i===0||i===points.length-1)?wire(depot):wire(find(value).original)),key=canonical(coords);
      if(routes.has(key)){guard();return structuredClone(routes.get(key));}
      const route=await reuseDirections({coords:structuredClone(coords),radiuses:null},()=>{
        guard();return boundedMapboxQuoteDirectionsV1({context:transport,scope,coords,token,radiuses:null});
      });
      guard();routes.set(key,structuredClone(route));return structuredClone(route);
    },
    async itinerary(args,build){
      guard();if(!args||typeof build!=='function')fail('mapbox_quote_endpoint_binding');
      args=structuredClone(args);
      const {fromText,toText,fromPoint,toPoint,stopsTexts=[],stopCoordinates=[]}=args;
      const from=await api.geocode(fromText),to=await api.geocode(toText);
      if(fromPoint&&!same(from,fromPoint)||toPoint&&!same(to,toPoint)||!Array.isArray(stopsTexts)||stopsTexts.length>6
        ||!Array.isArray(stopCoordinates)||stopCoordinates.length!==stopsTexts.length)fail('mapbox_quote_endpoint_binding');
      const stops=[];
      for(const [index,name]of stopsTexts.entries()){
        const stored=stopCoordinates[index],location=await api.geocode(name);
        if(stored?.address!==name||stored.invalidated===true||stored.confirmed===false||stored.needs_confirmation===true||stored.needs_address_confirmation===true
          ||stored.coordinates_valid===false||stored.coordinate_valid===false||!same(location,stored))fail('mapbox_quote_stop_binding');
        const registeredStop=find(location);
        if(stored.input!=null&&canonical(stored.input)!==canonical(registeredStop.input))fail('mapbox_quote_stop_binding');
        stops.push(location);
      }
      const route=await api.directions([from,...stops,to]);
      const result=await build({...args,fromPoint:from,toPoint:to,route});guard();return result;
    },
    diagnostics:()=>({source:'mapbox',nationalRouteCalculations:0,distinctRoutes:routes.size}),
  };
  return Object.freeze(api);
}
