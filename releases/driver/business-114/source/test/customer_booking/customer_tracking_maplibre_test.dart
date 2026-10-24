import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_live_tracking.dart';
import 'package:fluxidi_tracking/customer_booking/customer_live_tracking_panel.dart';
import 'package:fluxidi_tracking/customer_booking/customer_tracking_maplibre.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/maps/fluxidi_static_driver_map_frame.dart';
import 'package:fluxidi_tracking/maps/fluxidi_static_route_preview.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';

const palette=CustomerThemePalette(background:Colors.black,surface:Colors.black,
    surfaceAlt:Colors.black,textPrimary:Colors.white,textMuted:Colors.grey,
    gold:Colors.yellow,bronze:Colors.brown,border:Colors.grey,danger:Colors.red,
    success:Colors.green,shadow:Colors.black,isDark:true);
CustomerLiveTrackingView live({CustomerLivePhase phase=CustomerLivePhase.enRoutePickup,
    CustomerLiveFeedHealth feed=CustomerLiveFeedHealth.live,
    CustomerLiveTrackingAvailability availability=CustomerLiveTrackingAvailability.tracking,
    List<CustomerLivePoint> route=const []})=>CustomerLiveTrackingView(
      availability:availability,snapshot:CustomerLiveSnapshot(phase:phase,feed:feed,
      position:const CustomerLivePoint(latitude:50.85,longitude:4.35,heading:90),
      routePoints:route));
void main(){
  test('Own public map configuration refuses Mapbox, remote HTTP and token-bearing origins',(){
    expect(customerTrackingMapAssetBase('http://127.0.0.1:8803/'),'http://127.0.0.1:8803');
    for(final value in ['https://api.mapbox.com','https://tiles.mapbox.com',
        'http://remote.invalid','https://user:secret@own.invalid',
        'https://own.invalid?token=fixture']){
      expect(()=>customerTrackingMapAssetBase(value),throwsArgumentError);
    }
  });
  test('Renderer refuses every controller-hidden position, including terminal and stale feeds',(){
    for(final feed in [CustomerLiveFeedHealth.closed,CustomerLiveFeedHealth.missing,
        CustomerLiveFeedHealth.stale,CustomerLiveFeedHealth.unknown]){
      expect(CustomerTrackingMapData.fromView(live(feed:feed),CustomerTrackingMapMode.light),isNull);
    }
    for(final availability in [CustomerLiveTrackingAvailability.idle,
        CustomerLiveTrackingAvailability.unavailable,CustomerLiveTrackingAvailability.ended]){
      expect(CustomerTrackingMapData.fromView(live(availability:availability),CustomerTrackingMapMode.light),isNull);
    }
    for(final phase in [CustomerLivePhase.stopped,CustomerLivePhase.cancelled,CustomerLivePhase.expired]){
      expect(CustomerTrackingMapData.fromView(live(phase:phase),CustomerTrackingMapMode.dark),isNull);
    }
  });
  test('Renderer receives only supplied geometry; missing or invalid route creates no line',(){
    for(final route in [<CustomerLivePoint>[],[const CustomerLivePoint(latitude:50.85,longitude:4.35)],
      [const CustomerLivePoint(latitude:50.85,longitude:4.35),CustomerLivePoint(latitude:double.nan,longitude:4.4),const CustomerLivePoint(latitude:50.9,longitude:4.5)]]){
      final data=CustomerTrackingMapData.fromView(live(route:route),CustomerTrackingMapMode.light)!;
      expect(data.route,isEmpty);expect(data.routeGeoJson['features'],isEmpty);
    }
    const route=[CustomerLivePoint(latitude:50.85,longitude:4.35),CustomerLivePoint(latitude:50.86,longitude:4.36)];
    final data=CustomerTrackingMapData.fromView(live(route:route),CustomerTrackingMapMode.light)!;
    expect(data.routeGeoJson['features'][0]['geometry']['coordinates'],[[4.35,50.85],[4.36,50.86]]);
  });
  test('Token-free camera geometry preserves the existing static framing calculations',(){
    const driver=FluxidiMapLonLat(4.35,50.85),route=[FluxidiMapLonLat(4.35,50.85),FluxidiMapLonLat(4.38,50.87)];
    final before=fluxidiStaticDriverMapFrame(driver:driver,route:route,token:'fixture-only')!;
    final after=fluxidiDriverMapFrameGeometry(driver:driver,route:route)!;
    expect(after.url,isEmpty);expect(after.driverX,before.driverX);expect(after.driverY,before.driverY);
    expect(after.cameraLongitude,before.cameraLongitude);expect(after.cameraLatitude,before.cameraLatitude);expect(after.cameraZoom,before.cameraZoom);
  });
  test('Metadata-only view updates do not require another camera or route update',(){
    final before=CustomerTrackingMapData.fromView(live(),CustomerTrackingMapMode.light)!;
    final after=CustomerTrackingMapData.fromView(live(),CustomerTrackingMapMode.light)!;
    expect(before.sameGeometry(after),isTrue);
    final moved=CustomerTrackingMapData.fromView(const CustomerLiveTrackingView(
      availability:CustomerLiveTrackingAvailability.tracking,
      snapshot:CustomerLiveSnapshot(phase:CustomerLivePhase.enRoutePickup,
          feed:CustomerLiveFeedHealth.live,
          position:CustomerLivePoint(latitude:50.851,longitude:4.35))),CustomerTrackingMapMode.light)!;
    expect(before.sameGeometry(moved),isFalse);
  });
  test('Locally pinned image dependency supports the actual MapLibre web PNG-to-RGBA API',() async {
    final bytes=await rootBundle.load(kDriverTaxiMarkerAssetPath);
    final photo=image.decodeImage(bytes.buffer.asUint8List())!;
    final rgba=photo.convert(numChannels:4).getBytes();
    expect(photo.width,greaterThan(0));expect(photo.height,greaterThan(0));
    expect(rgba.length,photo.width*photo.height*4);
  });
  testWidgets('Empty Mapbox token does not gate authorized tracking; revocation unmounts the renderer in all modes',(tester) async {
    final seen=<CustomerTrackingMapData>[];
    for(final mode in CustomerTrackingMapMode.values){
      await tester.pumpWidget(MaterialApp(home:CustomerLiveTrackingPanel(view:live(),
          language:AppLanguage.nl,palette:palette,mapToken:'',mapMode:mode,
          mapBuilder:(data){seen.add(data);return const SizedBox(key:ValueKey('fixture-renderer'));})));
      expect(find.byKey(const ValueKey('fixture-renderer')),findsOneWidget);
      expect(seen.last.mode,mode);expect(seen.last.frame.url,isEmpty);
      await tester.pumpWidget(MaterialApp(home:CustomerLiveTrackingPanel(view:live(
          availability:CustomerLiveTrackingAvailability.ended),language:AppLanguage.nl,
          palette:palette,mapBuilder:(_)=>throw StateError('Revoked render invoked'))));
      expect(find.byKey(const ValueKey('fixture-renderer')),findsNothing);
      expect(tester.takeException(),isNull);
    }
  });
  testWidgets('A GPS update during style asset loading cannot leave the renderer blank',(tester) async {
    final style=Completer<String>();
    Widget host({bool moved=false})=>MaterialApp(home:CustomerTrackingMapLibre(
      data:CustomerTrackingMapData.fromView(moved?const CustomerLiveTrackingView(
          availability:CustomerLiveTrackingAvailability.tracking,
          snapshot:CustomerLiveSnapshot(phase:CustomerLivePhase.enRoutePickup,
            feed:CustomerLiveFeedHealth.live,
            position:CustomerLivePoint(latitude:50.851,longitude:4.35))):live(),CustomerTrackingMapMode.light)!,
      styleLoader:(_)=>style.future,surfaceBuilder:(value)=>Text(value)));
    await tester.pumpWidget(host());
    await tester.pumpWidget(host(moved:true));
    style.complete('loaded-style');await tester.pumpAndSettle();
    expect(find.text('loaded-style'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('An older style completion cannot overwrite the latest requested mode',(tester) async {
    final light=Completer<String>(),dark=Completer<String>();
    Widget host(CustomerTrackingMapMode mode)=>MaterialApp(home:CustomerTrackingMapLibre(
      data:CustomerTrackingMapData.fromView(live(),mode)!,
      styleLoader:(mode)=>mode==CustomerTrackingMapMode.dark?dark.future:light.future,
      surfaceBuilder:(value)=>Text(value)));
    await tester.pumpWidget(host(CustomerTrackingMapMode.light));
    await tester.pumpWidget(host(CustomerTrackingMapMode.dark));
    dark.complete('dark-style');await tester.pump();
    light.complete('old-light');await tester.pump();
    expect(find.text('dark-style'),findsOneWidget);expect(find.text('old-light'),findsNothing);
    expect(tester.takeException(),isNull);
  });
  testWidgets('A later authorized update can recover a renderer failure without a tracking request',(tester) async {
    var attempts=0;
    Widget host()=>MaterialApp(home:CustomerTrackingMapLibre(
      data:CustomerTrackingMapData.fromView(live(),CustomerTrackingMapMode.light)!,
      styleLoader:(_){attempts++;return attempts==1?Future.error(StateError('fixture load failure')):Future.value('recovered');},
      surfaceBuilder:(value)=>Text(value)));
    await tester.pumpWidget(host());await tester.pumpAndSettle();
    expect(find.text('Kaart tijdelijk niet beschikbaar'),findsOneWidget);
    await tester.pumpWidget(host());await tester.pumpAndSettle();
    expect(find.text('recovered'),findsOneWidget);expect(attempts,2);
    expect(tester.takeException(),isNull);
  });
  testWidgets('A failed superseded style cannot hide the current successful style',(tester) async {
    final light=Completer<String>(),dark=Completer<String>();
    Widget host(CustomerTrackingMapMode mode)=>MaterialApp(home:CustomerTrackingMapLibre(
      data:CustomerTrackingMapData.fromView(live(),mode)!,
      styleLoader:(mode)=>mode==CustomerTrackingMapMode.dark?dark.future:light.future,
      surfaceBuilder:(value)=>Text(value)));
    await tester.pumpWidget(host(CustomerTrackingMapMode.light));
    await tester.pumpWidget(host(CustomerTrackingMapMode.dark));
    dark.complete('current-dark');await tester.pumpAndSettle();
    light.completeError(StateError('old failed load'));await tester.pumpAndSettle();
    expect(find.text('current-dark'),findsOneWidget);
    expect(find.text('Kaart tijdelijk niet beschikbaar'),findsNothing);
    expect(tester.takeException(),isNull);
  });
}
