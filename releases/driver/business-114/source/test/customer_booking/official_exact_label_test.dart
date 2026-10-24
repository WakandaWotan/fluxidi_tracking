import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/customer_booking/official_address_lookup.dart';

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 final fixtures=(jsonDecode(File('test/customer_booking/fixtures/official_text_http_native.json').readAsStringSync()) as Map)['cases'] as Map;
 final sample=fixtures['requested-Gent'] as Map;
 final response=Map<String,dynamic>.from(sample['response']);
 final raw=(response['candidates'] as List).firstWhere((c)=>c['official_address']['id']==sample['targetId']);
 for(final mode in ['exact','ambiguous','different_house','changed_source','not_current']){
  test('exact official coordinate lookup: $mode',()async{
   final modes=<String>[];
   final lookup=OfficialAddressLookup(baseUrl:'https://fixture.invalid',tokenLoader:()async=>'FIXTURE',sessionRevision:()=>1,client:MockClient((request)async{
    expect(request.url.host,'fixture.invalid');final input=jsonDecode(request.body);modes.add(input['mode']);
    final candidate=Map<String,dynamic>.from(jsonDecode(jsonEncode(raw)));
    if(input['mode']=='select' && mode=='changed_source')candidate['official_address']['source_version']='CHANGED';
    if(mode=='not_current')candidate['source_status']='retired';
    final result=input['mode']=='suggest'?{...response,'candidates':[candidate,if(mode=='ambiguous')candidate]}:
      {'schema':OfficialAddressLookup.schema,'ok':true,'index_revision':response['index_revision'],'candidate':candidate,'accessProven':false,'routeProven':false};
    return http.Response(jsonEncode(result),200,headers:{'content-type':'application/json; charset=utf-8'});
   }));
   final label=raw['canonical_label'] as String;
   if(mode=='exact'){
    final resolved=await lookup.resolveExactLabel('  ${label.toUpperCase()}  ');expect(resolved.officialAddress!.id,sample['targetId']);expect(modes,['suggest','select']);
   }else{
    await expectLater(lookup.resolveExactLabel(mode=='different_house'?'Onbekende straat 999, 9000 Gent, BE':label),throwsStateError);
    expect(modes,mode=='changed_source'?['suggest','select']:['suggest']);
   }
   lookup.dispose();
  });
 }
}
