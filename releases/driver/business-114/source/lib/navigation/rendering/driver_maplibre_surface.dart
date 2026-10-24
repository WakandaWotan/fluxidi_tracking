import '../../maps/fluxidi_map_source_config.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as legacy;
import 'package:maplibre_gl/maplibre_gl.dart' as libre;
import 'driver_maplibre_camera_adapter.dart';
import 'driver_maplibre_annotations.dart';
import '../presentation/navigation_driver_cockpit_camera.dart';
export 'driver_maplibre_annotations.dart';

/// This widget replaces only the native map child in the ORIGINAL Driver
/// Stack. It owns no route, GPS, bearing, follow or viewport controller.
class DriverMapLibreSurface extends StatefulWidget {
  const DriverMapLibreSurface({super.key,required this.onMapCreated,
    required this.styleUri,required this.cameraOptions});
  final Future<void> Function(DriverMapLibreMap) onMapCreated;
  final String styleUri;
  final legacy.CameraOptions cameraOptions;
  @override State<DriverMapLibreSurface> createState()=>_DriverMapLibreSurfaceState();
}
class _DriverMapLibreSurfaceState extends State<DriverMapLibreSurface> {
  String? _style;
  DriverMapLibreMap? _map;
  bool _notified=false;
  bool _location=false;
  legacy.GesturesSettings _gestures=legacy.GesturesSettings();
  Completer<void>? _styleReady;
  @override void initState(){super.initState();libre.MapLibreMap.useHybridComposition=true;unawaited(_loadStyle(widget.styleUri));}
  Future<void> _loadStyle(String uri) async {
    final dark=uri.contains('dark')||uri.contains('night');
    // No Mapbox URL is sent to the map engine. Satellite preferences resolve
    // to the local light base; other app theme choices remain with the host.
    final data=jsonDecode(await rootBundle.loadString(
      'assets/fluxidi_maplibre/styles/${dark?'dark':'light'}.json')) as Map<String,dynamic>;
    final base=fluxidiMapAssetBase(const String.fromEnvironment('FLUXIDI_MAP_ASSET_BASE_URL'));
    data['glyphs']='$base/data/full/fonts/{fontstack}/{range}.pbf';
    data['sprite']='$base/data/full/sprites/${dark?'dark':'light'}';
    data['sources']={'osm':{'type':'vector',
      'tiles':['$base/country/releases/be-nl-20261013-rectangle-v1/tiles/{z}/{x}/{y}.mvt'],
      'minzoom':0,'maxzoom':15,'bounds':[2,49.1,7.8,54],
      'attribution':fluxidiMapAttribution}};
    final next=jsonEncode(data);
    // Light and perspective intentionally share the same native base style.
    // MapLibre emits no new style callback when styleString is unchanged.
    if(next==_style)return;
    _styleReady=Completer<void>();
    if(mounted)setState(()=>_style=next);
  }
  Future<void> _changeStyle(String uri) async {
    await _loadStyle(uri);
    await _styleReady!.future.timeout(const Duration(seconds:15));
  }
  @override Widget build(BuildContext context){
    if(_style==null)return const ColoredBox(color:Color(0xff050505));
    final c=widget.cameraOptions;
    return libre.MapLibreMap(styleString:_style!,
      initialCameraPosition:libre.CameraPosition(
        target:DriverMapLibreCameraAdapter.point(c.center!),zoom:c.zoom??0,
        bearing:c.bearing??0,tilt:c.pitch??0),
      trackCameraPosition:true,myLocationEnabled:_location,
      rotateGesturesEnabled:_gestures.rotateEnabled??true,
      scrollGesturesEnabled:_gestures.scrollEnabled??true,
      zoomGesturesEnabled:_gestures.pinchToZoomEnabled??true,
      tiltGesturesEnabled:_gestures.pitchEnabled??true,
      onMapCreated:(controller){_map=DriverMapLibreMap(controller,
        devicePixelRatio:()=>View.of(context).devicePixelRatio,
        changeStyle:_changeStyle,changeGestures:(v){setState(()=>_gestures=v);},
        changeLocation:(v){setState(()=>_location=v);});},
      onStyleLoadedCallback:() async {
        _map?.style.loaded=true;
        if(!(_styleReady?.isCompleted??true))_styleReady!.complete();
        if(!_notified&&_map!=null){
          _notified=true;
          await DriverMapLibreMap.native.invokeMethod('setPitchCapability',
              {'maxPitch':kDriverCockpitCameraMaxPitch});
          await widget.onMapCreated(_map!);
        }
      });
  }
}

class DriverMapLibreMap extends DriverMapLibreCameraAdapter {
  static const native=MethodChannel('fluxidi/maplibre_renderer');
  DriverMapLibreMap(super.controller,{required super.devicePixelRatio,
    required Future<void> Function(String) changeStyle,
    required void Function(legacy.GesturesSettings) changeGestures,
    required void Function(bool) changeLocation}) {
    style=DriverLibreStyle(controller,changeStyle);
    annotations=DriverLibreAnnotations(controller);
    gestures=DriverLibreGestures(changeGestures);
    location=DriverLibreLocation(changeLocation);
  }
  late final DriverLibreStyle style;
  late final DriverLibreAnnotations annotations;
  late final DriverLibreGestures gestures;
  late final DriverLibreLocation location;
  String get fluxidiMapInstanceId => throw UnsupportedError(
      'NativeFollow map registry must be bound to MapLibre before this feature is enabled');
  Future<legacy.CameraOptions> cameraForCoordinateBounds(
      legacy.CoordinateBounds bounds,legacy.MbxEdgeInsets padding,
      double? bearing,double? pitch,double? maxZoom,legacy.ScreenCoordinate? offset) async {
    if(offset!=null&&(offset.x!=0||offset.y!=0)){
      throw UnsupportedError('Nonzero bounds offset requires an explicit SDK mapping');
    }
    final camera=await native.invokeMapMethod<String,dynamic>('cameraForBounds',{
      'south':bounds.southwest.coordinates.lat,'west':bounds.southwest.coordinates.lng,
      'north':bounds.northeast.coordinates.lat,'east':bounds.northeast.coordinates.lng,
      'top':padding.top,'bottom':padding.bottom,'left':padding.left,'right':padding.right,
      'bearing':bearing,'pitch':pitch,'maxZoom':maxZoom});
    if(camera==null)throw StateError('Native bounds calculation unavailable');
    return legacy.CameraOptions(center:legacy.Point(coordinates:legacy.Position(
      camera['longitude'] as double,camera['latitude'] as double)),
      zoom:camera['zoom'] as double,bearing:camera['bearing'] as double,
      pitch:camera['pitch'] as double,padding:padding);
  }
}
class DriverLibreGestures {
  DriverLibreGestures(this.change);
  final void Function(legacy.GesturesSettings) change;
  Future<void> updateSettings(legacy.GesturesSettings value) async {change(value);}
}
class DriverLibreLocation {
  DriverLibreLocation(this.change);
  final void Function(bool) change;
  legacy.LocationComponentSettings _settings=legacy.LocationComponentSettings(enabled:false);
  Future<legacy.LocationComponentSettings> getSettings() async=>_settings;
  Future<void> updateSettings(legacy.LocationComponentSettings value) async {
    _settings=value;if(value.enabled!=null)change(value.enabled!);
  }
}

class DriverLibreStyle implements legacy.StyleManager {
  DriverLibreStyle(this.map,this.change);
  final libre.MapLibreMapController map;
  final Future<void> Function(String) change;
  bool loaded=false;
  @override Future<void> setStyleURI(String uri) async {loaded=false;await change(uri);loaded=true;}
  @override Future<bool> isStyleLoaded() async=>loaded;
  @override Future<void> setStyleLayerProperty(String id,String name,Object? value) async {
    if(name=='visibility'){await map.setLayerVisibility(id,value!='none');return;}
    throw UnsupportedError('Explicit layer property adapter required: $name');
  }
  // Unsupported Mapbox model/style operations fail explicitly. They must not
  // masquerade as successful restoration or change an engine feature flag.
  @override dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
      'MapLibre style capability not bound: ${invocation.memberName}');
}
