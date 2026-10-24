import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/company/active_company_booking_link_view.dart';
import 'package:fluxidi_tracking/company/company_public_booking_link_view.dart';
import 'package:fluxidi_tracking/company/driver_booking_link_trace.dart';
import 'company_public_booking_link_fixtures.dart';

const secret='never-log-personal-bearer-or-pin';
const deviceSecret='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
ActiveDriverSession actor(String company,String code,{bool expired=false})=>ActiveDriverSession(
 driverId:'synthetic-driver',employeeNumber:'synthetic',fullName:'Synthetic private name',phone:'private-phone',
 loggedInAt:'',updatedAt:'',tenantId:company,companyId:company,companyCode:code,assignedVehicleId:'vehicle-own',
 driverSessionToken:secret,linkMethod:'driver_pairing_code',driverSessionExpiresAtUtc:
 DateTime.now().add(Duration(hours:expired?-1:1)).toUtc().toIso8601String());

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 final records=<Map<String,dynamic>>[];
 late DebugPrintCallback oldPrint;
 setUp((){
  records.clear();oldPrint=debugPrint;
  debugPrint=(String? message,{int? wrapWidth}){if(message?.startsWith('[PUBLIC_BOOKING_LINK] ')==true){records.add(jsonDecode(message!.substring('[PUBLIC_BOOKING_LINK] '.length)) as Map<String,dynamic>);}};
  activeCompanySessionNotifier.value=null;
 });
 tearDown((){
  debugPrint=oldPrint;activeDriverSessionNotifier.value=null;activeCompanySessionNotifier.value=null;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/share'),null);
 });

 for(final fault in ['none','expired','expired_device','status401','status_vehicle','status_tenant',
   'directory401','directory_vehicle','missing_code','missing_code_wrong_session',
   'provided_code_invalid','provided_code_foreign','alias404','context_tenant','changed_session','changed_binding','malformed_status']){
  for(final company in (fault=='none'||fault=='missing_code')?[marioCompanyId,fluxidiCompanyId]:[marioCompanyId]){
   testWidgets('actual personal loader $fault $company',(tester)async{
    try {
    final code=company==marioCompanyId?'FLX-00028':'FLX-00001';
    final slug=company==marioCompanyId?'taxi-mario':'fluxidi-taxi';
    final name=company==marioCompanyId?'Taxi Mario':'Fluxidi';
    activeDriverSessionNotifier.value=actor(company,fault=='missing_code_wrong_session'?'FLX-00001':code,expired:fault=='expired');
    FlutterSecureStorage.setMockInitialValues({'vehicle_device_binding_v1':jsonEncode({
      'tenant_id':company,'company_id':company,'vehicle_id':'vehicle-own','device_id':'device-private',
      'device_token':deviceSecret,'expires_at_ms':DateTime.now().add(Duration(hours:fault=='expired_device'?-1:1)).millisecondsSinceEpoch,
    })});
    final requests=<http.Request>[];String? copied,shared;
    final messenger=TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform,(call)async{
      if(call.method=='Clipboard.setData')copied=(call.arguments as Map)['text'] as String;return null;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/share'),(call)async{
      if(call.method=='share')shared=(call.arguments as Map)['text'] as String;return 'synthetic-success';
    });
    final transport=MockClient((request)async{
      requests.add(request);
      final headers={'x-request-id':requests.length.toRadixString(16).padLeft(32,'0'),'cf-ray':'1234567890abcdef-BRU','content-type':'application/json'};
      switch(request.url.path){
        case '/public/driver/status':
          expect(request.headers['Authorization'], 'Bearer $secret');
          if(fault=='status401')return http.Response(jsonEncode({'error':'unauthorized'}),401,headers:headers);
          if(fault=='malformed_status')return http.Response('bad JSON $secret',200,headers:headers);
          return http.Response(jsonEncode({'ok':true,'tenant_id':fault=='status_tenant'?'other':company,
            'company_id':company,'driver_id':'synthetic-driver','driver':{'driver_id':'synthetic-driver','is_active':true,
            'assigned_vehicle_id':fault=='status_vehicle'?'other':'vehicle-own'}}),200,headers:headers);
        case '/public/vehicle-device/drivers':
          expect(request.headers.containsKey('authorization'),false);
          expect(jsonDecode(request.body)['device_token'],deviceSecret);
          if(fault=='directory401')return http.Response(jsonEncode({'error':'unauthorized','reason':secret,'pin':'123456','name':'Synthetic private name'}),401,headers:headers);
          return http.Response(jsonEncode({'ok':true,'tenant_id':company,'company_id':company,
            'vehicle_id':fault=='directory_vehicle'?'other':'vehicle-own',
            if(!fault.startsWith('missing_code'))'company_code':fault=='provided_code_invalid'?'invalid-code':fault=='provided_code_foreign'?'FLX-00001':code,
            'drivers':[{'driver_id':'synthetic-driver','name':'Synthetic private name'}]}),200,headers:headers);
        case '/book':
          expect(request.method,'HEAD');expect(request.headers.containsKey('authorization'),false);
          expect(request.followRedirects,false);
          final aliasCode=request.url.queryParameters['company_code'];
          expect(aliasCode,isIn(['FLX-00028','FLX-00001']));
          if(fault=='alias404')return http.Response('',404,headers:headers);
          return http.Response('',308,headers:{...headers,'location':'https://booking.fluxidi.com/${aliasCode=='FLX-00001'?'fluxidi-taxi':'taxi-mario'}'});
        case '/api/taxi-mario/app-context':
        case '/api/fluxidi-taxi/app-context':
          expect(request.headers.containsKey('authorization'),false);
          if(fault=='changed_session')activeDriverSessionNotifier.value=actor('other','FLX-90000');
          if(fault=='changed_binding')FlutterSecureStorage.setMockInitialValues({'vehicle_device_binding_v1':jsonEncode({
            'tenant_id':company,'company_id':company,'vehicle_id':'vehicle-own','device_id':'changed-private',
            'device_token':deviceSecret,'expires_at_ms':DateTime.now().add(const Duration(hours:1)).millisecondsSinceEpoch})});
          final publicSlug=request.url.path.split('/')[2];
          final context=bookingContext(company:publicSlug=='taxi-mario'?marioCompanyId:fluxidiCompanyId,
            slug:publicSlug,name:publicSlug=='taxi-mario'?'Taxi Mario':'Fluxidi');
          if(fault=='context_tenant')(context['company'] as Map)['tenant_id']='other';
          return http.Response(jsonEncode(context),200,headers:headers);
        default:fail('Unexpected route ${request.url.path}');
      }
    });
    await http.runWithClient(()async{
      await tester.pumpWidget(const MaterialApp(home:Scaffold(body:SingleChildScrollView(
        child:ActiveCompanyBookingLinkView(language:AppLanguage.en,driverOnly:true)))));
      await tester.pumpAndSettle();
      if(fault=='none'||fault=='missing_code'){
        expect(find.byType(QrImageView),findsOneWidget);expect(find.text(name),findsOneWidget);
        final url='https://booking.fluxidi.com/$slug';
        expect(find.text(url),findsWidgets);
        final evidence=Platform.environment['DIAGNOSTIC_EVIDENCE_DIR'];
        if(evidence!=null){await tester.runAsync(()async{
          final boundary=tester.element(find.byKey(companyBookingQrCardKey)).findAncestorRenderObjectOfType<RenderRepaintBoundary>()!;
          final image=await boundary.toImage(pixelRatio:2);
          final png=await image.toByteData(format:ui.ImageByteFormat.png);image.dispose();
          Directory(evidence).createSync(recursive:true);File('$evidence/$slug-driver-qr.png').writeAsBytesSync(png!.buffer.asUint8List());
        });}
        for(final key in [companyBookingCopyKey,companyBookingShareKey]){
          await tester.ensureVisible(find.byKey(key));await tester.tap(find.byKey(key));await tester.pumpAndSettle();
        }
        expect(copied,url);expect(shared,url);
        expect(requests.map((r)=>r.url.path),['/public/driver/status','/public/vehicle-device/drivers','/book','/api/$slug/app-context']);
        expect(records.last['stage'],'complete');expect(records.last['event'],'pass');
      }else{
        expect(find.byType(QrImageView),findsNothing);expect(find.byKey(companyBookingShareKey),findsNothing);
        expect(records.any((r)=>r['event']=='fail'),true);
        final expectedStage={'expired':'driver_status','expired_device':'local_binding','status401':'driver_status',
          'status_vehicle':'driver_status','status_tenant':'driver_status','directory401':'device_directory',
          'directory_vehicle':'device_directory','provided_code_invalid':'public_alias',
          'provided_code_foreign':'app_context','missing_code_wrong_session':'app_context','alias404':'public_alias',
          'context_tenant':'app_context','changed_binding':'final_binding','malformed_status':'driver_status'}[fault];
        if(expectedStage!=null)expect(records.where((r)=>r['event']=='fail').last['stage'],expectedStage);
        if(fault=='directory401'){
          final response=records.singleWhere((r)=>r['stage']=='device_directory'&&r['event']=='http');
          expect(response['http_status'],401);expect(response['error'],'unauthorized');
          expect(response['reason_redacted'],true);expect(response['cf_ray'],'1234567890abcdef-BRU');
          expect(response['request_id'],isNotEmpty);
        }
        if(fault=='status_vehicle')expect(records.any((r)=>r['stage']=='driver_status'&&r['vehicle_equal']==false),true);
        if(fault=='missing_code'){
          expect(records.any((r)=>r['stage']=='public_alias'&&r['company_code_present']==false),true);
          expect(requests.any((r)=>r.url.path=='/book'),false);
        }
      }
    },()=>transport);
    final serialized=jsonEncode(records);
    for(final private in [secret,deviceSecret,'Synthetic private name','private-phone','device-private','123456"']){
      expect(serialized.contains(private),false,reason:'No private data in diagnostics');
    }
    final evidence=Platform.environment['DIAGNOSTIC_EVIDENCE_DIR'];
    if(evidence!=null){Directory(evidence).createSync(recursive:true);
      File('$evidence/$fault-${company==marioCompanyId?'mario':'fluxidi'}.json').writeAsStringSync(jsonEncode({'synthetic':true,'events':records}));}
    expect(tester.takeException(),isNull);
    } finally {debugPrint=oldPrint;}
   });
  }
 }

 test('log failure does not change result or exception identity',()async{
   final trace=DriverBookingLinkTrace(log:(_)=>throw StateError(secret));
   expect(await trace.run(()=>Future.value(42),transport:MockClient((_)async=>http.Response('',200))),42);
   final original=StateError('original');
   await expectLater(trace.run<int>(()async=>throw original,transport:MockClient((_)async=>http.Response('',200))),throwsA(same(original)));
 });
 test('failure response bytes headers and bounded logs are preserved',()async{
   final lines=<String>[];final payload=jsonEncode({'error':secret,'code':deviceSecret,'reason':'x'*9000});
   final trace=DriverBookingLinkTrace(log:lines.add);
   final response=await trace.run(()=>trace.step('device_directory',()=>http.post(Uri.parse('https://synthetic.test/never-live'))),
     transport:MockClient((_)async=>http.Response(payload,401,headers:{'x-request-id':deviceSecret,'cf-ray':secret})));
   expect(response.body,payload);expect(response.statusCode,401);expect(response.headers['x-request-id'],deviceSecret);
   expect(lines.join().contains(secret),false);expect(lines.join().contains(deviceSecret),false);
   expect(lines.join().contains('body_truncated":true'),true);
 });
 test('unknown error strings and malformed IDs are redacted',()async{
   final lines=<String>[];final trace=DriverBookingLinkTrace(log:lines.add);
   await trace.run(()=>trace.step('device_directory',()=>http.get(Uri.parse('https://synthetic.test/never-live'))),
     transport:MockClient((_)async=>http.Response(jsonEncode({'error':secret,'code':deviceSecret,'reason':'verification_failed'}),401,
       headers:{'x-request-id':deviceSecret,'cf-ray':secret})));
   final output=lines.join();expect(output.contains(secret),false);expect(output.contains(deviceSecret),false);
   expect(output.contains('verification_failed'),true);expect(output.contains('error_redacted'),true);
 });
 test('transport failures remain transport failures without raw error text',()async{
   final lines=<String>[];final trace=DriverBookingLinkTrace(log:lines.add);
   final error=http.ClientException(secret);
   await expectLater(trace.run(()=>trace.step('driver_status',()=>http.get(Uri.parse('https://synthetic.test/never-live'))),
     transport:MockClient((_)async=>throw error)),throwsA(same(error)));
   expect(lines.join().contains(secret),false);expect(lines.join().contains('transport'),true);
 });
}
