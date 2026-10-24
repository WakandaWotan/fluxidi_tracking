import 'dart:async';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'customer_booking_route_camera.dart';
import 'customer_booking_maplibre_style.dart';

// The existing booking controller owns fit, pan, zoom, bearing and route paint.
// This renderer receives its camera; native gestures and GPS remain disabled.
double customerBookingNativeZoom(double zoom) => zoom - 1;
class CustomerBookingMapLibreBasemap extends StatefulWidget {
 const CustomerBookingMapLibreBasemap({super.key,required this.camera,required this.size,required this.dark});
 final CustomerBookingMapCamera camera;
 final Size size;
 final bool dark;
 @override State<CustomerBookingMapLibreBasemap> createState()=>_BasemapState();
}
class _BasemapState extends State<CustomerBookingMapLibreBasemap> {
 MapLibreMapController? _map;
 String? _style;
 int _epoch=0;
 bool _ready=false,_busy=false,_pending=false,_failed=false;
 CameraPosition get _camera=>CameraPosition(target:LatLng(widget.camera.center.lat,widget.camera.center.lon),zoom:customerBookingNativeZoom(widget.camera.zoom));
 @override void initState(){super.initState();unawaited(_load());}
 @override void didUpdateWidget(CustomerBookingMapLibreBasemap old){
 super.didUpdateWidget(old);
 if(old.dark!=widget.dark){unawaited(_load());}else{unawaited(_sync());}
 }
 Future<void> _load() async {
 final epoch=++_epoch;_ready=false;
 try{final style=await customerBookingBasemapStyle(widget.dark);
 if(mounted&&epoch==_epoch)setState((){_style=style;_failed=false;});
 }catch(_){if(mounted&&epoch==_epoch)setState(()=>_failed=true);}
 }
 Future<void> _sync() async {
 _pending=true;if(_busy||!_ready||_map==null)return;_busy=true;
 try{while(mounted&&_ready&&_pending){_pending=false;await _map!.moveCamera(CameraUpdate.newCameraPosition(_camera));}}
 catch(_){if(mounted)setState(()=>_failed=true);}
 finally{_busy=false;}
 }
 @override void dispose(){_epoch++;_ready=false;super.dispose();}
 @override Widget build(BuildContext context){
 if(_failed)return const Center(child:Text('Kaart tijdelijk niet beschikbaar'));
 if(_style==null||widget.size.isEmpty)return const SizedBox.expand();
 return IgnorePointer(child:MapLibreMap(styleString:_style!,initialCameraPosition:_camera,
 rotateGesturesEnabled:false,scrollGesturesEnabled:false,zoomGesturesEnabled:false,tiltGesturesEnabled:false,myLocationEnabled:false,
 onMapCreated:(map){_map=map;},onStyleLoadedCallback:(){_ready=true;unawaited(_sync());}));
 }
}
