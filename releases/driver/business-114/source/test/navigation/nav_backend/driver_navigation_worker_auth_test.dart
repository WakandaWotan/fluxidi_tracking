import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_navigation_worker_client.dart';

void main(){
  const a=DriverLonLat(4,51),b=DriverLonLat(4.001,51.001);
  final fixture=jsonDecode(File('test/navigation/fixtures/own-directions-v5/BE-VLG.json').readAsStringSync()) as Map<String,dynamic>;
  String freshResponse()=>jsonEncode({...fixture,'valid_until_ms':DateTime.now().millisecondsSinceEpoch+15000});
  test('missing driver session sends no route or provider request',()async{
    var calls=0;
    final client=DriverNavigationWorkerClient(baseUrl:'https://fixture.invalid',httpClient:MockClient((_)async{calls++;throw StateError('must not run');}));
    expect(await client.route(origin:a,destination:b,country:'BE'),isNull);expect(calls,0);
  });
  test('logout or actor switch during response cannot revive previous route',()async{
    var bearer='Bearer DRIVER_A';
    final client=DriverNavigationWorkerClient(baseUrl:'https://fixture.invalid',loadHeaders:()=>{'Authorization':bearer},httpClient:MockClient((_)async{
      bearer='Bearer DRIVER_B';return http.Response(freshResponse(),200);
    }));
    expect(await client.route(origin:a,destination:b,country:'NL'),isNull);
  });
  for(final patch in [<String,dynamic>{'source':'mapbox'},{'provider_source':'mapbox'},{'route_basis':'provider_cache'},{'navigation_metadata_sha256':null},{'valid_until_ms':1}]){
    test('unbound, provider or expired route is not usable: ${patch.keys.first}',()async{
      var calls=0;
      final client=DriverNavigationWorkerClient(baseUrl:'https://fixture.invalid',loadHeaders:()=>{'Authorization':'Bearer DRIVER'},httpClient:MockClient((request)async{
        calls++;return http.Response(jsonEncode({...fixture,'valid_until_ms':DateTime.now().millisecondsSinceEpoch+15000,...patch}),200);
      }));
      expect(await client.route(origin:a,destination:b,country:'BE'),isNull);expect(calls,1);
    });
  }
  test('measured GPS and official destination are passed without synthesized values',()async{
    final input={'kind':'gps','capturedAt':1800000000000,'accuracyMeters':7.5};
    final destination={'kind':'address','official_address':{'id':'FIXTURE','source':'BE-VLG','source_version':'V','index_revision':'R'}};
    final client=DriverNavigationWorkerClient(baseUrl:'https://fixture.invalid',loadHeaders:()=>{'Authorization':'Bearer DRIVER'},httpClient:MockClient((request)async{
      final body=jsonDecode(request.body);expect(body['origin_input'],input);expect(body['origin_input'].containsKey('speedMetersPerSecond'),isFalse);
      expect(body['destination_input'],destination);expect(body['destination_label'],'Teststraat 1, 9000 Gent');
      return http.Response(freshResponse(),200);
    }));
    expect(await client.reroute(current:a,destination:b,country:'BE',originInput:input,destinationInput:destination,destinationLabel:'Teststraat 1, 9000 Gent'),isNotNull);
  });
  for(final country in ['BE','NL','FR','DE','LU']){
    test('$country hint is preserved; graph and company policy decide coverage',()async{
      final client=DriverNavigationWorkerClient(baseUrl:'https://fixture.invalid',loadHeaders:()=>{'Authorization':'Bearer DRIVER'},httpClient:MockClient((request)async{
        expect(jsonDecode(request.body)['country'],country);return http.Response(freshResponse(),200);
      }));
      expect(await client.route(origin:a,destination:b,country:country),isNotNull);
    });
  }
}
