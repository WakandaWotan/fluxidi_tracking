import 'dart:convert';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_customer_core/fluxidi_customer_core.dart';
void main(){
 Map<String,dynamic> row()=>{'schema':'fluxidi-reliable-choice-v1','vehicle_id':'V','estimate':true,'status':'estimated_availability','pickup_eta_seconds':318,'pickup_eta_range_seconds':[300,420],'pickup_distance_meters':1100,'valid_until_ms':20000,'evidence_revision':'r','graph_version':'g','route_evidence_id':'e'};
 Future<List<Map<String,dynamic>>> parse(Map<String,dynamic> r)async{final client=MockClient((_)async=>http.Response(jsonEncode({'ok':true,'schema':'fluxidi-reliable-choice-v1','vehicles':[r]}),200));try{return await ReliableChoiceApiV1(base:Uri.parse('https://local-fixture'),token:'session',client:client).vehicles('B',nowMs:10000);}finally{client.close();}}
 test('P20 public core preserves versioned range and excludes private trip',()async{final result=(await parse({...row(),'driver_id':'private','current_trip':'private'})).single;expect(result['pickup_eta_range_seconds'],[300,420]);expect(result.containsKey('driver_id'),false);expect(result.containsKey('current_trip'),false);});
 test('P20 public core scheduled booking preserves no current distance',()async{expect((await parse({...row(),'status':'available_for_selected_time','pickup_eta_seconds':null,'pickup_eta_range_seconds':null,'pickup_distance_meters':null,'route_evidence_id':null})).single['pickup_distance_meters'],null);});
 test('P20 public core rejects missing version, stale evidence and reversed range',()async{for(final r in [{...row(),'graph_version':''},{...row(),'valid_until_ms':9999},{...row(),'pickup_eta_range_seconds':[420,300]},{...row(),'route_evidence_id':null}])await expectLater(parse(r),throwsStateError);});
 test('P20 public core rejects nonlocal cleartext and malformed scope',()async{final client=MockClient((_)async=>http.Response('{}',200));final api=ReliableChoiceApiV1(base:Uri.parse('http://example.com'),token:'session',client:client);await expectLater(api.status('B'),throwsStateError);expect(()=>api.status('../other'),throwsStateError);await expectLater(api.dispatcherQueue('T/other','C'),throwsStateError);client.close();});
}
