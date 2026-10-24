import '../maps/fluxidi_map_source_config.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../maps/fluxidi_static_driver_map_frame.dart';
import '../maps/fluxidi_static_route_preview.dart';
import 'customer_live_tracking.dart';
import 'customer_live_tracking_taxi_map.dart';

enum CustomerTrackingMapMode { light, dark, threeD }
typedef CustomerTrackingMapBuilder = Widget Function(CustomerTrackingMapData data);

String customerTrackingMapAssetBase(String value) => fluxidiMapAssetBase(value);

/// Presentation input only. The existing view decides authority and freshness.
class CustomerTrackingMapData {
  CustomerTrackingMapData._(this.position,this.route,this.frame,this.mode);
  final CustomerLivePoint position;
  final List<CustomerLivePoint> route;
  final FluxidiStaticDriverMapFrame frame;
  final CustomerTrackingMapMode mode;
  bool sameGeometry(CustomerTrackingMapData other)=>
      position.latitude==other.position.latitude&&
      position.longitude==other.position.longitude&&route.length==other.route.length&&
      List.generate(route.length,(i)=>i).every((i)=>
          route[i].latitude==other.route[i].latitude&&
          route[i].longitude==other.route[i].longitude);
  static CustomerTrackingMapData? fromView(CustomerLiveTrackingView view,
      CustomerTrackingMapMode mode) {
    if(!view.showLivePosition)return null;
    final p=view.snapshot.position;
    if(p==null)return null;
    final frame=fluxidiDriverMapFrameGeometry(
        driver:FluxidiMapLonLat(p.longitude,p.latitude),route:[
          for(final point in view.snapshot.routePoints)
            FluxidiMapLonLat(point.longitude,point.latitude)]);
    if(frame==null)return null;
    final route=view.snapshot.routePoints;
    final valid=route.length>=2&&route.every((p)=>p.longitude.isFinite&&
        p.latitude.isFinite&&p.longitude.abs()<=180&&p.latitude.abs()<=85.0511);
    return CustomerTrackingMapData._(p,
        List.unmodifiable(valid?route:<CustomerLivePoint>[]),frame,mode);
  }
  Map<String,dynamic> get routeGeoJson=>{'type':'FeatureCollection','features':[
    if(route.length>=2){'type':'Feature','geometry':{'type':'LineString',
      'coordinates':[for(final p in route)[p.longitude,p.latitude]]},'properties':{}}]};
}

/// No token, HTTP client, location stream, ETA calculation or polling timer.
/// The native map projects the original 72px Fluxidi taxi overlay.
class CustomerTrackingMapLibre extends StatefulWidget {
  const CustomerTrackingMapLibre({super.key,required this.data,this.styleLoader,this.surfaceBuilder});
  final CustomerTrackingMapData data;
  final Future<String> Function(CustomerTrackingMapMode)? styleLoader;
  final Widget Function(String)? surfaceBuilder;
  @override State<CustomerTrackingMapLibre> createState()=>_CustomerTrackingMapLibreState();
}
class _CustomerTrackingMapLibreState extends State<CustomerTrackingMapLibre> {
  MapLibreMapController? _map;
  String? _style;
  FluxidiStaticDriverMapFrame? _projected;
  int _generation=0;
  int _styleGeneration=0;
  bool _loaded=false;
  bool _busy=false;
  bool _pending=false;
  Size _size=Size.zero;
  int _projectionGeneration=0;
  bool _failed=false;
  Future<void> _safe(Future<void> Function() work,{bool style=false}) async {
    int? generation;
    try {
      final pending=work();generation=style?_styleGeneration:_generation;
      await pending;
    } catch (_) {
      if(mounted&&(generation==null||generation==(style?_styleGeneration:_generation))){
        setState((){_failed=true;_loaded=false;_projected=null;});
      }
    }
  }
  double _zoom(CustomerTrackingMapData data)=>data.frame.cameraZoom+
      math.log((_size.width>0?_size.width:data.frame.width)/data.frame.width)/math.ln2;
  @override void initState(){super.initState();unawaited(_safe(_loadStyle,style:true));}
  @override void didUpdateWidget(CustomerTrackingMapLibre old){
    super.didUpdateWidget(old);
    if(old.data.mode!=widget.data.mode||_failed){
      _generation++;unawaited(_safe(_loadStyle,style:true));
    }else if(!old.data.sameGeometry(widget.data)){
      _generation++;unawaited(_safe(_render));
    }
  }
  Future<void> _loadStyle() async {
    final version=++_styleGeneration;_generation++;_loaded=false;
    if(widget.styleLoader!=null){
      final style=await widget.styleLoader!(widget.data.mode);
      if(mounted&&version==_styleGeneration)setState((){_style=style;_failed=false;_projected=null;});
      return;
    }
    final dark=widget.data.mode==CustomerTrackingMapMode.dark;
    final data=jsonDecode(await rootBundle.loadString(
        'assets/fluxidi_maplibre/styles/${dark?'dark':'light'}.json')) as Map<String,dynamic>;
    // Match the already validated country-server style/license scope.
    data['layers']=(data['layers'] as List).where(
        (layer)=>layer['source-layer']!='landcover').toList();
    final base=customerTrackingMapAssetBase(const String.fromEnvironment(
        'FLUXIDI_MAP_ASSET_BASE_URL',defaultValue:''));
    data['glyphs']='$base/data/full/fonts/{fontstack}/{range}.pbf';
    data['sprite']='$base/data/full/sprites/${dark?'dark':'light'}';
    data['sources']={'osm':{'type':'vector','tiles':[
      '$base/country/releases/be-nl-20261013-rectangle-v1/tiles/{z}/{x}/{y}.mvt'],
      'minzoom':0,'maxzoom':15,'bounds':[2,49.1,7.8,54],
      'attribution':fluxidiMapAttribution}};
    if(mounted&&version==_styleGeneration)setState((){_style=jsonEncode(data);_failed=false;_projected=null;});
  }
  Future<void> _onStyleLoaded() async {
    final map=_map;if(map==null||!mounted)return;
    final version=_styleGeneration;
    await map.addGeoJsonSource('fluxidi-tracking-route',{'type':'FeatureCollection','features':[]});
    if(!mounted||version!=_styleGeneration)return;
    await map.addLineLayer('fluxidi-tracking-route','fluxidi-tracking-route',
        const LineLayerProperties(lineColor:'#2d8cff',lineOpacity:0.86,
            lineWidth:5,lineJoin:'round',lineCap:'round'));
    if(!mounted||version!=_styleGeneration)return;
    _loaded=true;await _render();
  }
  Future<void> _render() async {
    if(!_loaded||!mounted)return;
    _pending=true;if(_busy)return;_busy=true;
    try {
      while(_pending&&mounted&&_loaded){
        _pending=false;final version=_generation,data=widget.data,map=_map!;
        await map.setGeoJsonSource('fluxidi-tracking-route',data.routeGeoJson);
        if(!mounted||version!=_generation)continue;
        await map.setLayerProperties('fluxidi-tracking-route',
            LineLayerProperties(lineWidth:5*(_size.width/data.frame.width)));
        if(!mounted||version!=_generation)continue;
        await map.moveCamera(CameraUpdate.newCameraPosition(CameraPosition(
            target:LatLng(data.frame.cameraLatitude,data.frame.cameraLongitude),
            zoom:_zoom(data),bearing:0,
            tilt:data.mode==CustomerTrackingMapMode.threeD?60:0)));
        if(mounted&&version==_generation)await _project();
      }
    } finally {_busy=false;}
  }
  Future<void> _project() async {
    if(!mounted||!_loaded||_size.isEmpty||_map==null)return;
    final version=_generation,data=widget.data;
    final projection=++_projectionGeneration;
    final screen=await _map!.toScreenLocation(LatLng(data.position.latitude,data.position.longitude));
    if(!mounted||version!=_generation||projection!=_projectionGeneration)return;
    final density=!kIsWeb&&defaultTargetPlatform==TargetPlatform.android
        ?View.of(context).devicePixelRatio:1.0;
    setState(()=>_projected=FluxidiStaticDriverMapFrame(url:'',
        driverX:screen.x/density/_size.width,driverY:screen.y/density/_size.height));
  }
  @override void dispose(){_generation++;_styleGeneration++;super.dispose();}
  @override Widget build(BuildContext context)=>AspectRatio(aspectRatio:2,
    child:LayoutBuilder(builder:(context,size){
      final nextSize=Size(size.maxWidth,size.maxHeight);
      if(nextSize!=_size){
        _size=nextSize;_generation++;_projectionGeneration++;
        WidgetsBinding.instance.addPostFrameCallback((_){
          if(mounted)unawaited(_safe(_render));
        });
      }
      final data=widget.data;
      return CustomerLiveTrackingTaxiMap(frame:_projected??data.frame,
          showVehicle:_projected!=null&&!_failed,
          heading:(data.position.heading??0)-(_map?.cameraPosition?.bearing??0),
          mapImage:_failed?const Center(child:Text('Kaart tijdelijk niet beschikbaar')):
            _style==null?const SizedBox.shrink():widget.surfaceBuilder?.call(_style!)??MapLibreMap(
            key:const ValueKey('fluxidi-authorized-tracking-map'),styleString:_style!,
            initialCameraPosition:CameraPosition(
              target:LatLng(data.frame.cameraLatitude,data.frame.cameraLongitude),
              zoom:_zoom(data),tilt:data.mode==CustomerTrackingMapMode.threeD?60:0),
            trackCameraPosition:true,myLocationEnabled:false,
            onMapCreated:(map){_map=map;},
            onStyleLoadedCallback:()=>unawaited(_safe(_onStyleLoaded,style:true)),
            onCameraMove:(_)=>unawaited(_safe(_project)),
            onCameraIdle:()=>unawaited(_safe(_project))));
    }));
}
