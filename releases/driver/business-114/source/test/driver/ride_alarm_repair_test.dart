import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/driver/driver_ride_alert_controller.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer_host.dart';
import 'fixtures/driver_ride_offer_host_before.dart' as old;
import 'package:fluxidi_tracking/driver/driver_ride_frame_border.dart';
import 'fixtures/driver_ride_frame_border_before.dart' as old;
import 'package:fluxidi_tracking/driver/driver_ride_decision_memory.dart';
import 'driver_ride_offer_host_lifecycle_test.dart' show actor, offers;

const baseline=bool.fromEnvironment('ALARM_BEFORE');
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUp((){
  FlutterSecureStorage.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('fluxidi/vehicle_ride_alert'),(_)async=>null);
 });
 tearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
   const MethodChannel('fluxidi/vehicle_ride_alert'),null));
 for(final action in ['accept','decline']){
  for(final reply in [200,503]){
   testWidgets('$action $reply keeps alarm until confirmed response',(t)async{
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final gate=Completer<http.Response>();final sessions=ValueNotifier<ActiveDriverSession?>(actor('A'));
    var plays=0,decisionCalls=0,acceptanceRefreshes=0;
    final alerts=DriverRideAlertController(play:(_)async{plays++;},stop:()async{});
    final memory=DriverRideDecisionMemory();
    DriverRideOfferClient client(String token,String vehicle)=>DriverRideOfferClient(
      baseUrl:'https://fixture.invalid',token:token,vehicleId:vehicle,driverId:'A',tenantId:'tenant',companyId:'company',
      client:MockClient((r)async{
        if(r.url.path.endsWith('/offers'))return offers();
        if(r.url.path.endsWith('/decision')){decisionCalls++;return gate.future;}
        return http.Response('{"ok":true}',200);
      }));
    final host=baseline?old.DriverRideOfferHost(baseUrl:'https://fixture.invalid',alertController:alerts,decisionMemory:memory,
      sessionListenable:sessions,loadSession:()async=>sessions.value,clientFactory:client,child:const Scaffold())
      :DriverRideOfferHost(baseUrl:'https://fixture.invalid',alertController:alerts,decisionMemory:memory,onAcceptanceReceived:(_,__)=>acceptanceRefreshes++,
      sessionListenable:sessions,loadSession:()async=>sessions.value,clientFactory:client,child:const Scaffold());
    await t.pumpWidget(MaterialApp(home:host));await t.pump(const Duration(seconds:2));
    for(var i=0;i<8;i++){await t.pump();}
    expect(alerts.active,true);expect(plays,1);
    final button=find.byKey(ValueKey('${action}_ride'));await t.ensureVisible(button);await t.tap(button);
    await t.pump();await t.pump();expect(decisionCalls,1);
    final during=alerts.active;
    gate.complete(http.Response(reply==200?'{"ok":true}':'{"ok":false}',reply));
    for(var i=0;i<8;i++){await t.pump();}
    final after=alerts.active;
    await t.pumpWidget(const SizedBox());alerts.dispose();sessions.dispose();
    expect(during,true,reason:'Sending is not server confirmation');
    expect(after,reply!=200,reason:'A failed response must not claim confirmation');
    if(!baseline)expect(acceptanceRefreshes,action=='accept'&&reply==200?1:0);
   });
  }
 }
 for(final reduced in [false,true]){
  testWidgets('immediate red pulse has bounded cadence reduced=$reduced',(t)async{
   final c=DriverRideAlertController(play:(_)async{},stop:()async{});
   const original=BoxDecoration(border:Border.fromBorderSide(BorderSide(color:Colors.amber,width:8)));
   final frame=baseline?old.DriverRideFrameBorder(decoration:original,controller:c,child:const SizedBox(width:200,height:300))
     :DriverRideFrameBorder(decoration:original,controller:c,child:const SizedBox(width:200,height:300));
   await t.pumpWidget(MaterialApp(home:MediaQuery(data:MediaQueryData(disableAnimations:reduced),child:frame)));
   final owner=Object();c.present(owner:owner,identity:'new-offer',deadlineMs:DateTime.now().millisecondsSinceEpoch+60000);
   await t.pump();
   final builder=t.widget<AnimatedBuilder>(find.byType(AnimatedBuilder).last);
   final animation=builder.animation as AnimationController;
   final duration=animation.duration!;
   final colors=<Color>[];
   for(var i=0;i<12;i++){
    final boxes=t.widgetList<DecoratedBox>(find.byType(DecoratedBox));
    colors.add(((boxes.last.decoration as BoxDecoration).border as Border).top.color);
    await t.pump(const Duration(milliseconds:100));
   }
   c.stop(owner:owner);await t.pump();
   final restored=(t.widgetList<DecoratedBox>(find.byType(DecoratedBox)).last.decoration as BoxDecoration).border;
   await t.pumpWidget(const SizedBox());c.dispose();
   expect(duration.inMilliseconds,inInclusiveRange(450,750));
   expect(colors.every((c)=>c.a==1&&c.r>c.g&&c.r>c.b),true);
    if(!reduced)expect(colors.first.r,greaterThan(.95),reason:'First frame must already be conspicuous');
   if(reduced)expect(colors.toSet(),hasLength(1));else expect(colors.toSet().length,greaterThan(3));
   expect(restored,original.border);
  });
 }
 testWidgets('background handoff and ordinary stop are distinct',(t)async{
  var handed=0,stopped=0;
  final c=DriverRideAlertController(play:(_)async{},stop:()async{stopped++;},handoff:()async{handed++;});
  final owner=Object();c.present(owner:owner,identity:'offer',deadlineMs:DateTime.now().millisecondsSinceEpoch+60000);await t.pump();
  final n=stopped;c.stop(owner:owner,retainBackground:true);await t.pump();
  expect(c.active,false);expect(handed,greaterThan(0));expect(stopped,n);
  c.dispose();
 });
 testWidgets('repeated proposal syncs deadline without second play',(t)async{
  final calls=<String>[];const channel=MethodChannel('fluxidi/vehicle_ride_alert');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(m)async{calls.add(m.method);return null;});
  final c=DriverRideAlertController();final owner=Object();
  c.present(owner:owner,identity:'same',deadlineMs:DateTime.now().millisecondsSinceEpoch+60000);await t.pump();
  c.present(owner:owner,identity:'same',deadlineMs:DateTime.now().millisecondsSinceEpoch+65000);await t.pump();
  expect(calls.where((c)=>c=='play'),hasLength(1));expect(calls,contains('sync'));
  c.stop(owner:owner);await t.pump();c.dispose();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);
 });
 testWidgets('late old-actor confirmation cannot stop the new actor alarm',(t)async{
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final sessions=ValueNotifier<ActiveDriverSession?>(actor('A'));
  final gate=Completer<http.Response>();final c=DriverRideAlertController(play:(_)async{},stop:()async{});
  final seen=<String>[];
  final memory=DriverRideDecisionMemory();
  DriverRideOfferClient client(String token,String vehicle)=>DriverRideOfferClient(
    baseUrl:'https://fixture.invalid',token:token,vehicleId:vehicle,driverId:sessions.value!.driverId,
    tenantId:'tenant',companyId:'company',client:MockClient((r)async{
      seen.add('${sessions.value?.driverId}:${r.url.path}');
      if(r.url.path.endsWith('/decision'))return gate.future;
      if(r.url.path.endsWith('/offers')){
        final body=jsonDecode(offers().body) as Map<String,dynamic>;
        for(final offer in body['offers'] as List){offer['driver_id']=sessions.value!.driverId;offer['offer_id']='proposal-${sessions.value!.driverId}';}
        return http.Response(jsonEncode(body),200);
      }
      return http.Response('{"ok":true}',200);
    }));
  await t.pumpWidget(MaterialApp(home:DriverRideOfferHost(baseUrl:'https://fixture.invalid',alertController:c,
    decisionMemory:memory,sessionListenable:sessions,loadSession:()async=>sessions.value,clientFactory:client,child:const Scaffold())));
  await t.pump(const Duration(seconds:2));for(var i=0;i<8;i++){await t.pump();}
  await t.ensureVisible(find.byKey(const ValueKey('accept_ride')));await t.tap(find.byKey(const ValueKey('accept_ride')));
  await t.pump();sessions.value=actor('B',token:'new-token');await t.pump(const Duration(seconds:1));for(var i=0;i<12;i++){await t.pump();}
  expect(seen.any((request)=>request=='B:/public/driver/dispatch/ack'),true);
  expect(c.active,true);gate.complete(http.Response('{"ok":true}',200));for(var i=0;i<8;i++){await t.pump();}
  expect(c.active,true,reason:'The old ACK must not stop a newer session');
  await t.pumpWidget(const SizedBox());c.dispose();sessions.dispose();
 });
}
