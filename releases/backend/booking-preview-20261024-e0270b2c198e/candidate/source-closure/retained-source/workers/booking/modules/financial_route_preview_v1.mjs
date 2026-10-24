import {mapboxQuotePreviewV1} from './mapbox_quote_transport_v1.mjs';
// Presentation of the SAME completed server route; never a second route,
// customer ETA certificate, financial authority or provider fallback.
export function financialRoutePreviewV1(routeOut){
 const mapbox=mapboxQuotePreviewV1(routeOut);if(mapbox)return mapbox;
 const proof=routeOut?.financial_route,route=routeOut?.route;
 if(proof?.source!=='fluxidi-national')return null;
 const point=p=>p&&typeof p.lat==='number'&&typeof p.lng==='number'&&Number.isFinite(p.lat)&&Number.isFinite(p.lng)&&Math.abs(p.lat)<=90&&Math.abs(p.lng)<=180;
 const geometry=route?.geometry;
 if(!/^[a-f0-9]{64}$/.test(proof.graph_checksum??'')||!Array.isArray(proof.points)||proof.points.length<2||proof.points.length>10||!proof.points.every(point)
  ||geometry?.type!=='LineString'||!Array.isArray(geometry.coordinates)||geometry.coordinates.length<2||geometry.coordinates.length>100000
  ||geometry.coordinates.some(p=>!Array.isArray(p)||p.length!==2||!point({lng:p[0],lat:p[1]}))
  ||typeof route.distance!=='number'||!Number.isFinite(route.distance)||route.distance<0||typeof route.duration!=='number'||!Number.isFinite(route.duration)||route.duration<0)throw Error('national_route_preview_invalid');
 return {schema:'fluxidi-quote-route-preview-v1',source:'fluxidi-national',graph_checksum:proof.graph_checksum,
  points:proof.points.map(p=>({lat:p.lat,lng:p.lng})),geometry:structuredClone(geometry),distance_m:route.distance,duration_s:route.duration};
}
