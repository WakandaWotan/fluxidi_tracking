// Release transport boundary. No provider fallback may escape a missing owned
// route. Native service bindings keep their own .fetch and are unchanged.
export function ownedReleaseFetchV1(input,init){
 const url=new URL(typeof input==='string'||input instanceof URL?String(input):input.url);
 const host=url.hostname.toLowerCase().replace(/\.$/,'');
 if(host==='mapbox.com'||host.endsWith('.mapbox.com')||host==='mapbox.cn'||host.endsWith('.mapbox.cn')){
  const error=Error('mapbox_runtime_disabled');error.providerRequestMade=false;
  throw error;
 }
 return globalThis.fetch(input,init);
}
