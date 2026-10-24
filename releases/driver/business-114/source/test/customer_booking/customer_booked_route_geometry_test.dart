import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booked_route_geometry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_live_tracking.dart';
void main(){
 const pickup=CustomerLivePoint(latitude:51,longitude:4),destination=CustomerLivePoint(latitude:51.1,longitude:4.1);
 Map<String,dynamic> archive()=>{'schema':'fluxidi-booked-route-geometry-v1','type':'LineString',
  'pickup':{'latitude':51.0,'longitude':4.0},'destination':{'latitude':51.1,'longitude':4.1},
  'coordinates':[[4.0,51.0],[4.05,51.07],[4.1,51.1]]};
 test('authorized planned line retains full road shape without asserting GPS or ETA',(){
  final points=customerBookedRoutePoints(archive(),pickup:pickup,destination:destination);expect(points.length,3);expect(points[1].latitude,51.07);expect(()=>points.add(pickup),throwsUnsupportedError);
 });
 test('changed/reversed target and incomplete/invalid geometry never show a previous route',(){
  expect(customerBookedRoutePoints(archive(),pickup:destination,destination:pickup),isEmpty);
  expect(customerBookedRoutePoints(archive(),pickup:pickup,destination:null),isEmpty);
  for(final change in <void Function(Map<String,dynamic>)>[(r)=>r['schema']='old',(r)=>r['coordinates']=[[4,51],[double.nan,51.1]],(r)=>r['coordinates']=[[4,51]],(r)=>r['pickup']={'latitude':double.nan,'longitude':4}]){final r=archive();change(r);expect(customerBookedRoutePoints(r,pickup:pickup,destination:destination),isEmpty);}
 });
}
