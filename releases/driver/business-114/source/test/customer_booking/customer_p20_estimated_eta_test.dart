import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/customer_booking/reliable_choice_api.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_booking/customer_reliable_choice.dart';
import 'package:fluxidi_tracking/customer_booking/customer_reliable_choice_panel.dart';
Map<String,dynamic> row()=>{'schema':'fluxidi-reliable-choice-v1','vehicle_id':'V','vehicle_name':'Mercedes Vito','vehicle_type':'van','vehicle_category':'comfort','photo_url':null,'passenger_capacity':8,'luggage_capacity':4,'estimate':true,'status':'estimated_availability','pickup_eta_seconds':318,'pickup_eta_range_seconds':[300,420],'pickup_distance_meters':1100,'valid_until_ms':DateTime.now().millisecondsSinceEpoch+15000,'evidence_revision':'r','graph_version':'g','route_evidence_id':'e'};
void main(){
 test('P20 scheduled public vehicle needs no current km or ETA route',()async{final client=MockClient((_)async=>http.Response(jsonEncode({'ok':true,'schema':'fluxidi-reliable-choice-v1','vehicles':[{...row(),'status':'available_for_selected_time','pickup_eta_seconds':null,'pickup_eta_range_seconds':null,'pickup_distance_meters':null,'route_evidence_id':null}]}),200));final api=ReliableChoiceApiV1(base:Uri.parse('https://local-fixture'),token:'session',client:client);expect((await api.vehicles('B')).single['status'],'available_for_selected_time');client.close();});

 test('P20 range parsed and conservative minutes localised without driver details',(){final r=row();for(final lang in AppLanguage.values){final m=CustomerReliableChoiceEstimate.parse(r,vehicleId:'V')!;expect(m.etaLabel(lang),'± 5–7 min');}expect(CustomerReliableChoiceEstimate.parse(r,vehicleId:'V')!.distanceLabel(AppLanguage.nl),'1,1 km van jou');});
 for(final range in [<dynamic>[300],<dynamic>[420,300],<dynamic>[300,'bad'],<dynamic>[300,310],<dynamic>[-1,420],<dynamic>[300,double.nan]])test('P20 malformed/reversed/excluding estimate range hidden $range',()=>expect(CustomerReliableChoiceEstimate.parse({...row(),'pickup_eta_range_seconds':range},vehicleId:'V'),isNull));
 test('P20 shared API fixed auth/path/choice and public field whitelist',()async{final seen=<http.Request>[];final client=MockClient((req)async{seen.add(req);return http.Response(jsonEncode({'ok':true,'schema':'fluxidi-reliable-choice-v1','vehicles':[{...row(),'driver_id':'private','current_trip':'private'}]}),200);});final api=ReliableChoiceApiV1(base:Uri.parse('https://local-fixture'),token:'customer-session',client:client);final rows=await api.vehicles('B');expect(rows.single.containsKey('driver_id'),false);expect(rows.single.containsKey('current_trip'),false);expect(seen.single.headers['authorization'],'Bearer customer-session');expect(seen.single.url.path,'/public/customer/reliable-choice/B/vehicles');expect(()=>api.choose('B','V',kind:'downgrade'),throwsStateError);expect(()=>api.status('../foreign'),throwsStateError);client.close();});
 testWidgets('P20 existing cards preserve selection, range/km and confirmed estimated boundary',(tester)async{
  var selected=false;final client=MockClient((req)async{if(req.url.path.endsWith('vehicles'))return http.Response(jsonEncode({'ok':true,'schema':'fluxidi-reliable-choice-v1','vehicles':[row()]}),200);if(req.url.path.endsWith('choice')){selected=true;return http.Response('{"ok":true}',200);}return http.Response('{"ok":true,"state":"driver_confirmed","live_tracking":false}',200);});
  final api=ReliableChoiceApiV1(base:Uri.parse('https://local-fixture'),token:'customer-session',client:client);
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:CustomerReliableChoicePanelV1(api:api,bookingId:'B',language:AppLanguage.nl,palette:paletteForCustomerTheme(CustomerThemeVariant.nightGold)))));await tester.pumpAndSettle();expect(find.text('Mercedes Vito'),findsOneWidget);expect(find.text('± 5–7 min'),findsOneWidget);expect(find.text('1,1 km van jou'),findsOneWidget);expect(find.textContaining('huidige rit'),findsNothing);await tester.tap(find.text('± 5–7 min'));await tester.pumpAndSettle();expect(selected,true);expect(find.text('Chauffeur bevestigd · ETA geschat'),findsOneWidget);expect(find.text('Live tracking gestart'),findsNothing);expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());client.close();
 });

 testWidgets('P21 dispatcher review keeps customer status fresh through manual confirmation and NAV',(tester)async{
  var state='dispatcher_review',live=false,fail=false,calls=0;
  final client=MockClient((req)async{calls++;return http.Response(jsonEncode(fail?{'ok':false,'error':'temporary'}:{'ok':true,'state':state,'live_tracking':live}),fail?503:200);});
  final api=ReliableChoiceApiV1(base:Uri.parse('https://local-fixture'),token:'customer-session',client:client);
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:CustomerReliableChoicePanelV1(api:api,bookingId:'B',statusOnly:true,language:AppLanguage.nl,palette:paletteForCustomerTheme(CustomerThemeVariant.nightGold)))));
  await tester.pumpAndSettle();expect(find.text(customerReliableChoiceStatus('dispatcher_review',AppLanguage.nl)),findsOneWidget);expect(find.text('Live tracking gestart'),findsNothing);
  fail=true;await tester.pump(const Duration(seconds:2));await tester.pumpAndSettle();expect(find.text('Beschikbaarheid kon niet worden geladen'),findsOneWidget);
  fail=false;state='driver_confirmed';await tester.pump(const Duration(seconds:2));await tester.pumpAndSettle();expect(find.text('Chauffeur bevestigd · ETA geschat'),findsOneWidget);expect(find.text('Beschikbaarheid kon niet worden geladen'),findsNothing);expect(find.text('Live tracking gestart'),findsNothing);expect(calls,greaterThanOrEqualTo(3));
  live=true;await tester.pump(const Duration(seconds:2));await tester.pumpAndSettle();expect(find.text('Live tracking gestart'),findsOneWidget);final afterNav=calls;await tester.pump(const Duration(seconds:4));expect(calls,afterNav);expect(tester.takeException(),isNull);
  await tester.pumpWidget(const SizedBox());client.close();
 });
}
