import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as libre;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as legacy;
import 'package:fluxidi_tracking/navigation/rendering/driver_maplibre_annotations.dart';
class Port implements libre.MapLibreMapController {
 libre.SymbolLayerProperties? symbol;
 Map<String,dynamic>? source;
 int images=0;
 @override Future<void> addGeoJsonSource(String id,Map<String,dynamic> geojson,{String? promoteId}) async {}
 @override Future<void> addSymbolLayer(String sourceId,String layerId,libre.SymbolLayerProperties properties,{String? belowLayerId,String? sourceLayer,dynamic filter,double? minzoom,double? maxzoom,bool enableInteraction=true}) async {symbol=properties;}
 @override Future<void> setGeoJsonSource(String id,Map<String,dynamic> geojson) async {source=geojson;}
 @override Future<void> addImage(String name,Uint8List bytes,[bool sdf=false]) async {images++;}
 @override dynamic noSuchMethod(Invocation invocation)=>throw UnsupportedError('${invocation.memberName}');
}
void main(){
 test('Original marker size, direction, text and viewport pitch survive renderer mapping',() async {
 final port=Port(),manager=DriverLibrePointManager(Port(),'unused');
 final map=DriverLibrePointManager(port,'car');await map.initialize();
 await map.create(legacy.PointAnnotationOptions(geometry:legacy.Point(coordinates:legacy.Position(4.35,50.85)),iconSize:.5,iconRotate:123,textField:'Bestemming',textSize:13,textColor:0xffe0b63f));
 final props=((port.source!['features'] as List).single as Map)['properties'] as Map;
 expect(props['size'],.5);expect(props['rotate'],123);expect(props['text'],'Bestemming');expect(props['textSize'],13);
 expect(port.symbol!.iconPitchAlignment,'viewport');expect(port.symbol!.textField,['get','text']);
 expect(manager.id,'unused');
 });
 test('Repeated identical original assets upload once; changed asset updates in place',() async {
 final port=Port(),manager=DriverLibrePointManager(Port(),'unused');final map=DriverLibrePointManager(port,'car');await map.initialize();
 final o=legacy.PointAnnotationOptions(geometry:legacy.Point(coordinates:legacy.Position(4.35,50.85)),image:Uint8List.fromList([1,2,3]));
 final marker=await map.create(o);await map.deleteAll();final newer=await map.create(o);expect(port.images,1);
 newer.image=Uint8List.fromList([4,5,6]);await map.update(newer);expect(port.images,2);expect(newer.iconImage,isNot(marker.iconImage));expect(manager.id,'unused');
 });
}
