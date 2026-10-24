import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:maplibre_gl/maplibre_gl.dart' as libre;
import 'package:fluxidi_tracking/navigation/rendering/driver_maplibre_camera_adapter.dart';

class RendererPort implements libre.MapLibreMapController {
  @override libre.CameraPosition? get cameraPosition => const libre.CameraPosition(
      target: libre.LatLng(50.85,4.35), zoom: 16, bearing: 123, tilt: 60);
  int paddingCalls=0;
  Point? inversePixel;
  Duration? duration;
  @override Future<Point> toScreenLocation(libre.LatLng point) async => const Point(500.0,900.0);
  @override Future<libre.LatLng> toLatLng(Point pixel) async {
    inversePixel=pixel;return const libre.LatLng(50.85,4.35);
  }
  @override Future<void> setPadding({double left=0,double top=0,double right=0,double bottom=0,bool animated=false}) async {paddingCalls++;}
  @override Future<bool?> moveCamera(libre.CameraUpdate update) async => true;
  @override Future<bool?> animateCamera(libre.CameraUpdate update,{Duration? duration}) async {this.duration=duration;return true;}
  @override dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('${invocation.memberName}');
}
void main(){
  test('Native projection preserves logical vehicle-anchor pixels at phone and tablet densities',() async {
    for(final density in [1.0,2.0,2.5,3.0]){
      final port=RendererPort(),adapter=DriverMapLibreCameraAdapter(port,devicePixelRatio:()=>density);
      final point=mb.Point(coordinates:mb.Position(4.35,50.85));
      final screen=await adapter.pixelForCoordinate(point);
      expect(screen.x,500/density);expect(screen.y,900/density);
      final restored=await adapter.coordinateForPixel(screen);
      expect(port.inversePixel,const Point(500.0,900.0));
      expect(restored.coordinates.lng,closeTo(4.35,1e-10));
      expect(restored.coordinates.lat,closeTo(50.85,1e-10));
    }
  });
  test('Repeated original panel padding is deduplicated; animation timing and camera state remain caller-owned',() async {
    final port=RendererPort(),adapter=DriverMapLibreCameraAdapter(port,devicePixelRatio:()=>2.5);
    final options=mb.CameraOptions(padding:mb.MbxEdgeInsets(top:100,left:0,bottom:300,right:0));
    await adapter.setCamera(options);await adapter.setCamera(options);
    await adapter.flyTo(options,mb.MapAnimationOptions(duration:450));
    expect(port.paddingCalls,1);expect(port.duration,const Duration(milliseconds:450));
    final camera=await adapter.getCameraState();
    expect(camera.bearing,123);expect(camera.pitch,60);expect(camera.padding.bottom,300);
  });
}
