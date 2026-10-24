import 'dart:async';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'fluxidi_static_route_preview.dart';
import 'fluxidi_maplibre_preview_style.dart';
import 'fluxidi_maplibre_preview_markers.dart';

Map<String,dynamic> fluxidiPreviewRouteGeoJson(List<List<FluxidiMapLonLat>> routes)=>{'type':'FeatureCollection','features':[
 for(final route in routes) if(route.length>=2&&route.every((p)=>p.lon.isFinite&&p.lat.isFinite&&p.lon.abs()<=180&&p.lat.abs()<=85.0511))
 {'type':'Feature','properties':{},'geometry':{'type':'LineString','coordinates':[for(final p in route)[p.lon,p.lat]]}}
]};
/// Renderer only. Caller keeps existing Directions, ETA, price and session rules.
class FluxidiMapLibreRoutePreview extends StatefulWidget {
 const FluxidiMapLibreRoutePreview({super.key,required this.pickup,required this.dropoff,required this.routes});
 final FluxidiMapLonLat pickup,dropoff;
 final List<List<FluxidiMapLonLat>> routes;
 @override State<FluxidiMapLibreRoutePreview> createState()=>_PreviewState();
}
class _PreviewState extends State<FluxidiMapLibreRoutePreview> {
 MapLibreMapController? _map;String? _style;
 bool _loaded=false,_busy=false,_pending=false,_failed=false;
 int _epoch=0;
 @override void initState(){super.initState();unawaited(_load());}
 Future<void> _load() async {try{final style=await customerBookingBasemapStyle(true);if(mounted)setState(()=>_style=style);}catch(_){if(mounted)setState(()=>_failed=true);}}
 @override void didUpdateWidget(FluxidiMapLibreRoutePreview old){super.didUpdateWidget(old);_epoch++;unawaited(_render());}
 Future<void> _ready() async {
 try{final map=_map!;await map.addGeoJsonSource('fluxidi-preview-route',fluxidiPreviewRouteGeoJson(const []));
 await map.addLineLayer('fluxidi-preview-route','fluxidi-preview-route',const LineLayerProperties(lineWidth:5,lineColor:'#2d8cff',lineOpacity:0.86));
 await map.addImage('fluxidi-preview-pickup',await customerRideTargetMarker(destination:false));
 await map.addImage('fluxidi-preview-destination',await customerRideTargetMarker(destination:true));
 _loaded=true;await _render();}catch(_){if(mounted)setState(()=>_failed=true);}
 }
 Future<void> _render() async {
 _pending=true;if(!_loaded||_busy||!mounted)return;_busy=true;
 try{while(_pending&&mounted&&_loaded){_pending=false;final epoch=_epoch;final map=_map!;
 await map.setGeoJsonSource('fluxidi-preview-route',fluxidiPreviewRouteGeoJson(widget.routes));
 if(!mounted||epoch!=_epoch)continue;
 await map.clearSymbols();
 await map.addSymbol(SymbolOptions(geometry:LatLng(widget.pickup.lat,widget.pickup.lon),iconImage:'fluxidi-preview-pickup',iconSize:.5,iconAnchor:'bottom'));
 await map.addSymbol(SymbolOptions(geometry:LatLng(widget.dropoff.lat,widget.dropoff.lon),iconImage:'fluxidi-preview-destination',iconSize:.5,iconAnchor:'bottom'));
 final pts=[widget.pickup,widget.dropoff,...widget.routes.expand((r)=>r)].where((p)=>p.lat.isFinite&&p.lon.isFinite&&p.lat.abs()<=85.0511&&p.lon.abs()<=180).toList();
 if(pts.isNotEmpty&&mounted&&epoch==_epoch){
 var west=pts.first.lon,east=west,south=pts.first.lat,north=south;
 for(final p in pts){if(p.lon<west)west=p.lon;if(p.lon>east)east=p.lon;if(p.lat<south)south=p.lat;if(p.lat>north)north=p.lat;}
 if(west==east&&south==north){await map.moveCamera(CameraUpdate.newLatLngZoom(LatLng(south,west),15));}
 else{await map.moveCamera(CameraUpdate.newLatLngBounds(LatLngBounds(southwest:LatLng(south,west),northeast:LatLng(north,east)),top:34,bottom:34,left:22,right:22));}
 }
 }}catch(_){if(mounted)setState(()=>_failed=true);}finally{_busy=false;}
 }
 @override void dispose(){_epoch++;_loaded=false;super.dispose();}
 @override Widget build(BuildContext context){
 if(_failed)return const Center(child:Text('Kaart tijdelijk niet beschikbaar'));
 if(_style==null)return const SizedBox.expand();
 return IgnorePointer(child:MapLibreMap(styleString:_style!,initialCameraPosition:CameraPosition(target:LatLng(widget.pickup.lat,widget.pickup.lon),zoom:8),myLocationEnabled:false,scrollGesturesEnabled:false,zoomGesturesEnabled:false,rotateGesturesEnabled:false,tiltGesturesEnabled:false,onMapCreated:(map)=>_map=map,onStyleLoadedCallback:()=>unawaited(_ready())));
 }
}
