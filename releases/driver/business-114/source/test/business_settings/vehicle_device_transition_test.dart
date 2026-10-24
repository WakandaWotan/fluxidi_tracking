import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/driver/vehicle_device_store.dart';
void main() {
 TestWidgetsFlutterBinding.ensureInitialized();
 final old={'tenant_id':'T','company_id':'C','vehicle_id':'V0','device_id':'old','device_token':'a'*64,'expires_at_ms':DateTime.now().millisecondsSinceEpoch+86400000};
 String qr(String op,{String tenant='T'})=>jsonEncode({'kind':'fluxidi_vehicle_device_transition','version':1,'tenant_id':tenant,'company_id':'C','device_id':'old','operation':op,'vehicle_id':'V1','challenge_id':'grant','pairing_token':'b'*64});
 setUp(()=>FlutterSecureStorage.setMockInitialValues({'vehicle_device_binding_v1':jsonEncode(old)}));
 http.Response success(http.Request r){final b=jsonDecode(r.body);return http.Response(jsonEncode({'ok':true,'tenant_id':'T','company_id':'C','operation':b['operation'],'revoked_device_id':'old',if(b['operation']=='switch')...{'device_id':b['replacement_device_id'],'vehicle_id':'V1','expires_at_ms':DateTime.now().millisecondsSinceEpoch+86400000}}),200);}
 for(final op in ['switch','unlink'])test('$op preserves local binding until server confirmation and cleanup',()async{
  final store=VehicleDeviceStore();var cleaned=false;
  final client=MockClient((r)async{expect(cleaned,false);expect(jsonDecode((await const FlutterSecureStorage().read(key:'vehicle_device_binding_v1'))!)['device_id'],'old');return success(r);});
  await store.transition(qr(op),'https://synthetic.invalid',operation:op,client:client,afterServerConfirmed:(scope)async{expect(scope['device_id'],'old');cleaned=true;});
  expect(cleaned,true);expect(await store.hasPendingTransition(),false);expect((await store.pinScope())?['vehicle_id'],op=='switch'?'V1':null);client.close();
 });
 test('lost response retains exact encrypted retry and blocks login',()async{
  final store=VehicleDeviceStore();String? first;var calls=0;
  final client=MockClient((r)async{calls++;if(calls==1){first=r.body;throw http.ClientException('synthetic transport loss');}expect(r.body,first);return success(r);});
  await expectLater(store.transition(qr('switch'),'https://synthetic.invalid',operation:'switch',client:client,afterServerConfirmed:(_)async=>fail('premature cleanup')),throwsA(isA<http.ClientException>()));
  await expectLater(store.loginIdentity(),throwsStateError);
  await store.transition(null,'https://synthetic.invalid',operation:'switch',client:client,afterServerConfirmed:(_)async{});
  expect((await store.pinScope())?['vehicle_id'],'V1');client.close();
 });
 test('wrong tenant makes no request and preserves old binding',()async{
  final client=MockClient((_)async=>throw StateError('NETWORK_FORBIDDEN'));final store=VehicleDeviceStore();
  await expectLater(store.transition(qr('unlink',tenant:'FOREIGN'),'https://synthetic.invalid',operation:'unlink',client:client,afterServerConfirmed:(_)async=>fail('cleanup')),throwsStateError);
  expect((await store.pinScope())?['vehicle_id'],'V0');client.close();
 });
 test('active duty denial permits login to safely end duty',()async{
  final store=VehicleDeviceStore();final client=MockClient((_)async=>http.Response('{"ok":false,"error":"active_duty_blocks_device_change"}',409));
  await expectLater(store.transition(qr('unlink'),'https://synthetic.invalid',operation:'unlink',client:client,afterServerConfirmed:(_)async=>fail('cleanup')),throwsStateError);
  expect(await store.hasPendingTransition(),false);expect((await store.pinScope())?['vehicle_id'],'V0');client.close();
 });
 test('cleanup failure keeps binding and recoverable receipt command',()async{
  final store=VehicleDeviceStore();final client=MockClient((r)async=>success(r));
  await expectLater(store.transition(qr('unlink'),'https://synthetic.invalid',operation:'unlink',client:client,afterServerConfirmed:(_)async=>throw StateError('cleanup failed')),throwsStateError);
  expect(await store.hasPendingTransition(),true);expect(jsonDecode((await const FlutterSecureStorage().read(key:'vehicle_device_binding_v1'))!)['device_id'],'old');client.close();
 });
 test('concurrent transition requests serialize with one cleanup and no duplicate binding',()async{
  final store=VehicleDeviceStore();var calls=0;final client=MockClient((r)async{calls++;return success(r);});
  final results=await Future.wait([store.transition(qr('unlink'),'https://synthetic.invalid',operation:'unlink',client:client,afterServerConfirmed:(_)async{}).then((_)=>true).catchError((_)=>false),store.transition(qr('switch'),'https://synthetic.invalid',operation:'switch',client:client,afterServerConfirmed:(_)async{}).then((_)=>true).catchError((_)=>false)]);
  expect(results.where((v)=>v).length,1);expect(calls,1);expect(await store.loginIdentity(),null);client.close();
 });
 test('unlink then authorized first pairing at another company inherits no old scope',()async{
  final store=VehicleDeviceStore();final client=MockClient((r)async{
   if(r.url.path.endsWith('/transition'))return success(r);
   expect(jsonDecode(r.body)['company_id'],'NEW');
   return http.Response(jsonEncode({'ok':true,'tenant_id':'NEW-T','company_id':'NEW','device_id':'new-company-device','device_token':'d'*64,'vehicle_id':'NEW-V','expires_at_ms':DateTime.now().millisecondsSinceEpoch+600000}),200);
  });
  await store.transition(qr('unlink'),'https://synthetic.invalid',operation:'unlink',client:client,afterServerConfirmed:(_)async{});
  expect(await store.loginIdentity(),null);
  await store.pair(jsonEncode({'kind':'fluxidi_vehicle_device','version':1,'tenant_id':'NEW-T','company_id':'NEW','challenge_id':'new','pairing_token':'e'*64}),'https://synthetic.invalid',client:client);
  expect((await store.pinScope())?['company_id'],'NEW');expect((await store.loginIdentity())?['device_token'],'d'*64);client.close();
 });

}
