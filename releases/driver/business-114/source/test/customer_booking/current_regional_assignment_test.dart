import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/customer_booking/official_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 final cases=(jsonDecode(File('test/customer_booking/fixtures/current_bru_wal_assignment.json').readAsStringSync()) as Map)['cases'] as List;
 for(final fixture in cases){test('actual current ${fixture['region']} ${fixture['targetId']} suggest/select/reverify retains unknown assignment',()async{
  final modes=<String>[];final source=fixture['selected']['candidate'];
  final lookup=OfficialAddressLookup(baseUrl:'https://fixture.invalid',tokenLoader:()async=>'fixture',sessionRevision:()=>1,client:MockClient((r)async{
   expect(r.url.host,'fixture.invalid');final input=jsonDecode(r.body) as Map;final mode=input['mode'];modes.add(mode);
   expect(input['schema'],OfficialAddressLookup.schema);
   return http.Response(jsonEncode(mode=='suggest'?fixture['response']:mode=='select'?fixture['selected']:fixture['reverified']),200,headers:{'content-type':'application/json; charset=utf-8'});
  }));
  final result=await lookup.search(source['canonical_label']);
  final selected=result.suggestions.firstWhere((r)=>r.officialAddress?.id==fixture['targetId']);expect(selected.officialUsable,isTrue);
  final verified=await lookup.verifySuggestion(selected);expect(verified.officialUsable,isTrue);
  await lookup.reverifyAddress(LimousineAddressValue(displayText:verified.label,canonicalLabel:verified.label,lat:verified.lat,lon:verified.lon,officialAddress:verified.officialAddress,acceptance:LimousineAddressAcceptance.selected));
  expect(modes,['suggest','select','reverify']);expect(source['officially_assigned'],isNull);expect(source['source_status'],'current');expect(source['accessProven'],isFalse);expect(source['routeProven'],isFalse);lookup.dispose();
 });}
}
