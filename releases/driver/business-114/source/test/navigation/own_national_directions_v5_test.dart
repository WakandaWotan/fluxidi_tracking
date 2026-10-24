import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_route_parser.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_navigation_worker_client.dart';

void main() {
  for (final region in ['BE-VLG','BE-BRU','BE-WAL','NL','NL-long']) {
    for (final reverse in [false,true]) {
      final name = '$region${reverse ? '-reverse' : ''}';
      test('actual own $name metadata preserves signs, exits and only proven lanes', () async {
        final body=File('test/navigation/fixtures/own-directions-v5/$name.json').readAsStringSync();
        final raw=jsonDecode(body) as Map<String,dynamic>;
        final geometry=raw['geometry']['coordinates'] as List;
        final client=DriverNavigationWorkerClient(baseUrl:'https://fixture.invalid',
          loadHeaders:()=>{'Authorization':'Bearer FIXTURE'},clock:()=>DateTime.fromMillisecondsSinceEpoch((raw['valid_until_ms'] as num).toInt()-1),httpClient:MockClient((request)async{
            expect(request.headers['Authorization'],'Bearer FIXTURE');
            return http.Response(body,200,headers:{'content-type':'application/json'});
          }));
        final result=await client.route(origin:DriverLonLat((geometry.first[0] as num).toDouble(),(geometry.first[1] as num).toDouble()),
          destination:DriverLonLat((geometry.last[0] as num).toDouble(),(geometry.last[1] as num).toDouble()),country:region.startsWith('NL')?'NL':'BE');
        expect(result,isNotNull);
        final parsed=parseDriverDirectionsResponse(response:result!.toMapboxDirectionsShape(),localizeInstruction:(s)=>s,distanceAlongRouteForCoords:(_,__)=>0);
        final sourceSteps=raw['legs'][0]['steps'] as List;
        expect(parsed.coords.length,geometry.length);expect(parsed.distanceMeters,raw['distance_m']);
        expect(parsed.navSteps.length,sourceSteps.length);expect(parsed.stepsWithBannerCount,sourceSteps.length);
        expect(parsed.navSteps.first.type,'depart');expect(parsed.navSteps.last.type,'arrive');
        expect(parsed.navSteps.every((s)=>s.instruction.isNotEmpty),isTrue);
        expect(parsed.stepsWithLaneGuidanceCount,name=='BE-VLG-reverse'?1:0);
        final expectedExits=sourceSteps.where((s)=>s['maneuver']['exit']!=null).map((s)=>s['maneuver']['exit'].toString()).toList();
        expect(parsed.navSteps.where((s)=>s.exitNumber!=null).map((s)=>s.exitNumber),expectedExits);
        expect(result.routeSessionUpdated,isFalse);
      });
    }
  }
}
