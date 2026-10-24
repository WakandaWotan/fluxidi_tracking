import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_route_geometry.dart';
import 'package:fluxidi_tracking/maps/fluxidi_static_route_preview.dart';

void main(){
 const from=FluxidiMapLonLat(4,51),to=FluxidiMapLonLat(4.1,51.1);
 Map<String,dynamic> preview()=>{'schema':'fluxidi-quote-route-preview-v1','source':'fluxidi-national','graph_checksum':'a'*64,
  'points':[{'lat':51.0,'lng':4.0},{'lat':51.1,'lng':4.1}],
  'geometry':{'type':'LineString','coordinates':[[4.0,51.0],[4.05,51.07],[4.1,51.1]]},'distance_m':10000.123,'duration_s':900.456};
 CompanyPlanQuoteResult quote(Map<String,dynamic>? route)=>CompanyPlanQuoteResult(fingerprint:'same-server-quote',distanceKm:10,durationMin:15,priceInclVat:20.10,routePreview:route);
 test('same quote draws full server geometry and metrics with zero extra provider requests',()async{
  var calls=0;final client=CustomerBookingRouteGeometryClient(httpGet:(_)async{calls++;return http.Response('',500);});
  final q=quote(preview()),result=await client.fetch(pickup:from,dropoff:to,quote:q);
  expect(result.points.length,3);expect(result.points[1].lat,51.07);expect(result.distanceKm,10.000123);expect(result.durationMin,15);
  expect(q.priceInclVat,20.10);expect(calls,0);expect(()=>result.points.add(from),throwsUnsupportedError);
 });
 test('missing own preview never falls back to Mapbox for a supplied quote',()async{
  var calls=0;final client=CustomerBookingRouteGeometryClient(httpGet:(_)async{calls++;return http.Response('',200);});
  await expectLater(client.fetch(pickup:from,dropoff:to,quote:quote(null)),throwsStateError);expect(calls,0);
 });
 test('changed endpoints, reversed journey and missing/extra stops never reuse old geometry',()async{
  final client=CustomerBookingRouteGeometryClient();final q=quote(preview());
  await expectLater(client.fetch(pickup:to,dropoff:from,quote:q),throwsStateError);
  await expectLater(client.fetch(pickup:const FluxidiMapLonLat(4.00001,51),dropoff:to,quote:q),throwsStateError);
  await expectLater(client.fetch(pickup:from,dropoff:to,stops:const[FluxidiMapLonLat(4.05,51.07)],quote:q),throwsStateError);
 });
 test('wrong source/hash, invalid geometry and conflicting route units fail closed',()async{
  for(final change in <void Function(Map<String,dynamic>)>[
   (r)=>r['source']='mapbox',(r)=>r['graph_checksum']='bad',(r)=>r['duration_s']=1,(r)=>r['distance_m']=-1,
   (r)=>(r['geometry'] as Map)['coordinates']=[[4,51],[double.nan,51.1]],
  ]){final raw=preview();change(raw);await expectLater(CustomerBookingRouteGeometryClient().fetch(pickup:from,dropoff:to,quote:quote(raw)),throwsStateError);}
 });
}
