import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_navigation_worker_client.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_route_apply.dart';
void main(){
 for(final status in [401,403,409,429,503])test('owned navigation HTTP $status does not contact a paid provider or Tracking proxy',()async{
  final calls=<Uri>[];final client=DriverNavigationWorkerClient(baseUrl:'https://navigation.local',loadHeaders:()=>{'Authorization':'Bearer LOCAL_FIXTURE'},httpClient:MockClient((request)async{calls.add(request.url);return http.Response('{"ok":false,"error":"navigation_unavailable"}',status);}));
  expect(await client.route(origin:const DriverLonLat(4,51),destination:const DriverLonLat(4.1,51.1),country:'BE'),isNull);
  expect(calls.length,1);expect(calls.single.host,'navigation.local');expect(calls.single.path,'/route');
 });
 const context=DriverRouteRequestContext(requestGeneration:3,cleanupEpoch:2,purpose:DriverRouteApplyPurpose.destination,expectedBookingId:'CURRENT_BOOKING',expectedTripId:'CURRENT_TRIP');
 DriverRouteAcceptanceSnapshot snapshot({int generation=3,int epoch=2,String booking='CURRENT_BOOKING',String trip='CURRENT_TRIP',bool mounted=true})=>DriverRouteAcceptanceSnapshot(mounted:mounted,latestRequestGeneration:generation,cleanupEpoch:epoch,activeBookingId:booking,activeTripId:trip,directRideActive:false,liveRideActive:true);
 test('failure UI ownership cannot revive stale booking/session/generation or authorize an absent route',(){
  expect(evaluateDriverRouteRequestOwnership(context:context,snapshot:snapshot()).accepted,true);
  for(final stale in [snapshot(generation:4),snapshot(epoch:3),snapshot(booking:'OTHER'),snapshot(trip:'OTHER'),snapshot(mounted:false)])expect(evaluateDriverRouteRequestOwnership(context:context,snapshot:stale).accepted,false);
  expect(evaluateDriverRouteAcceptance(context:context,snapshot:snapshot(),package:null).accepted,false);
 });
}
