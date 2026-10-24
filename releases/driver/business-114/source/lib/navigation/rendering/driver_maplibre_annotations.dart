import 'dart:typed_data';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as legacy;
import 'package:maplibre_gl/maplibre_gl.dart' as libre;

bool _sameBytes(List<int>? a,List<int>? b){if(identical(a,b))return true;if(a==null||b==null||a.length!=b.length)return false;for(var i=0;i<a.length;i++){if(a[i]!=b[i])return false;}return true;}
String _color(int value) => 'rgba(${(value >> 16) & 255},${(value >> 8) & 255},${value & 255},${((value >> 24) & 255) / 255})';
Map<String,dynamic> _collection(Iterable<Map<String,dynamic>> features) =>
    {'type':'FeatureCollection','features':features.toList()};

/// Renderer-owned identifiers only. Existing navigation gates retain ownership
/// of creation, update, deletion, route progress and stale generations.
class DriverLibrePointManager {
  DriverLibrePointManager(this.map,this.id);
  final libre.MapLibreMapController map;
  final String id;
  final Map<String,legacy.PointAnnotation> _points={};
  int _next=0;
  final Map<String,List<int>> _images={};
  Future<String> _image(List<int> bytes) async {
    for(final image in _images.entries){if(_sameBytes(image.value,bytes))return image.key;}
    final key='$id-image-${_images.length+1}';
    await map.addImage(key,Uint8List.fromList(bytes));_images[key]=List<int>.of(bytes);return key;
  }
  Future<void> initialize() async {
    await map.addGeoJsonSource(id,_collection([]));
    await map.addSymbolLayer(id,id,libre.SymbolLayerProperties(
      iconImage:['get','image'],iconSize:['get','size'],
      iconRotate:['get','rotate'],iconOpacity:['get','opacity'],
      iconAnchor:['get','anchor'],iconOffset:['get','offset'],
      iconAllowOverlap:true,iconIgnorePlacement:true,
      iconPitchAlignment:'viewport',iconRotationAlignment:'map',
      textFont:['Noto Sans Regular'],textField:['get','text'],textSize:['get','textSize'],textColor:['get','textColor'],
      textAllowOverlap:true,textIgnorePlacement:true));
  }
  Future<void> _refresh() => map.setGeoJsonSource(id,_collection(_points.values.map((p)=>{
    'type':'Feature','id':p.id,'geometry':p.geometry.toJson(),
    'properties':{'image':p.iconImage ?? '', 'size':p.iconSize ?? 1.0,
      'rotate':p.iconRotate ?? 0.0,'opacity':p.iconOpacity ?? 1.0,
      'anchor':(p.iconAnchor ?? legacy.IconAnchor.CENTER).name.toLowerCase().replaceAll('_','-'),
      'offset':p.iconOffset ?? [0.0,0.0],
      'text':p.textField ?? '', 'textSize':p.textSize ?? 16,
      'textColor':_color(p.textColor ?? 0xff000000)}})));
  Future<legacy.PointAnnotation> create(legacy.PointAnnotationOptions o) async {
    final key='$id-${++_next}';String? image=o.iconImage;
    if(o.image!=null){image=await _image(o.image!);}
    final p=legacy.PointAnnotation(id:key,geometry:o.geometry,image:o.image,
      iconImage:image,iconSize:o.iconSize,iconRotate:o.iconRotate,
      iconAnchor:o.iconAnchor,iconOffset:o.iconOffset,iconOpacity:o.iconOpacity,
      textField:o.textField,textSize:o.textSize,textColor:o.textColor);
    _points[key]=p;await _refresh();return p;
  }
  Future<void> update(legacy.PointAnnotation p) async {
    if(!_points.containsKey(p.id))throw StateError('Unknown marker generation');
    if(p.image!=null){p.iconImage=await _image(p.image!);}
    _points[p.id]=p;await _refresh();
  }
  Future<void> delete(legacy.PointAnnotation p) async {_points.remove(p.id);await _refresh();}
  Future<void> deleteAll() async {_points.clear();await _refresh();}
  Future<void> setIconRotationAlignment(legacy.IconRotationAlignment value) =>
      map.setLayerProperties(id,libre.SymbolLayerProperties(iconRotationAlignment:value.name.toLowerCase()));
  Future<void> setIconPitchAlignment(legacy.IconPitchAlignment value) =>
      map.setLayerProperties(id,libre.SymbolLayerProperties(iconPitchAlignment:value.name.toLowerCase()));
  Future<void> remove() async {await map.removeLayer(id);await map.removeSource(id);}
}

class DriverLibreLineManager {
  DriverLibreLineManager(this.map,this.id);
  final libre.MapLibreMapController map;
  final String id;
  final Map<String,legacy.PolylineAnnotation> _lines={};
  int _next=0;
  final Map<String,List<int>> _images={};
  Future<String> _image(List<int> bytes) async {
    for(final image in _images.entries){if(_sameBytes(image.value,bytes))return image.key;}
    final key='$id-image-${_images.length+1}';
    await map.addImage(key,Uint8List.fromList(bytes));_images[key]=List<int>.of(bytes);return key;
  }
  Future<void> initialize() async {
    await map.addGeoJsonSource(id,_collection([]));
    await map.addLineLayer(id,id,libre.LineLayerProperties(
      lineColor:['get','color'],lineWidth:['get','width'],
      lineOpacity:['get','opacity'],lineJoin:'round',lineCap:'round'));
  }
  Future<void> _refresh() => map.setGeoJsonSource(id,_collection(_lines.values.map((l)=>{
    'type':'Feature','id':l.id,'geometry':l.geometry.toJson(),
    'properties':{'color':_color(l.lineColor ?? 0xff000000),'width':l.lineWidth ?? 1.0,
      'opacity':l.lineOpacity ?? 1.0}})));
  Future<legacy.PolylineAnnotation> create(legacy.PolylineAnnotationOptions o) async {
    final p=legacy.PolylineAnnotation(id:'$id-${++_next}',geometry:o.geometry,
      lineColor:o.lineColor,lineWidth:o.lineWidth,lineOpacity:o.lineOpacity,
      lineJoin:o.lineJoin,lineSortKey:o.lineSortKey);
    _lines[p.id]=p;await _refresh();return p;
  }
  Future<void> update(legacy.PolylineAnnotation p) async {
    if(!_lines.containsKey(p.id))throw StateError('Unknown route generation');
    _lines[p.id]=p;await _refresh();
  }
  Future<void> delete(legacy.PolylineAnnotation p) async {_lines.remove(p.id);await _refresh();}
  Future<void> deleteAll() async {_lines.clear();await _refresh();}
  Future<void> remove() async {await map.removeLayer(id);await map.removeSource(id);}
}

class DriverLibreAnnotations {
  DriverLibreAnnotations(this.map);
  final libre.MapLibreMapController map;
  int _next=0;
  Future<DriverLibrePointManager> createPointAnnotationManager() async {
    final manager=DriverLibrePointManager(map,'fluxidi-points-${++_next}');
    await manager.initialize();return manager;
  }
  Future<DriverLibreLineManager> createPolylineAnnotationManager() async {
    final manager=DriverLibreLineManager(map,'fluxidi-lines-${++_next}');
    await manager.initialize();return manager;
  }
  Future<void> removeAnnotationManager(Object manager) async {
    if(manager is DriverLibrePointManager){await manager.remove();return;}
    if(manager is DriverLibreLineManager){await manager.remove();return;}
    throw ArgumentError('Foreign annotation manager');
  }
}
