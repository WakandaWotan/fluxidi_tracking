import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer.dart';
import 'package:fluxidi_tracking/company/booking_list_mutation_reload.dart';
import 'driver_ride_offer_host_lifecycle_test.dart' show actor;
import 'fixtures/assignment_refresh_home.dart';

DriverRideOffer proposal({String? owner='booking-487'})=>DriverRideOffer.parse({
 'offer_id':'opaque-not-a-booking','version':4,'owner_id':owner,
 'vehicle_id':'vehicle','driver_id':'A','tenant_id':'tenant','company_id':'company',
 'human_acceptance_required':true,'currency':'EUR',
 'ack_deadline_ms':DateTime.now().millisecondsSinceEpoch+60000,
},'vehicle',driverId:'A',tenantId:'tenant',companyId:'company');
Map<String,dynamic> assigned()=>{'booking_id':'booking-487','leg_id':'canonical-outbound',
 'assigned_driver_id':'A','assigned_vehicle_id':'vehicle','status':'ASSIGNED'};

void main(){
 setUp(()=>activeDriverSessionNotifier.value=actor('A'));
 tearDown(()=>activeDriverSessionNotifier.value=null);
 test('explicit owner is retained, opaque offer id is never decoded',(){
  expect(proposal().bookingId,'booking-487');
  expect(proposal(owner:null).bookingId,isNull);
 });
 test('assignment refresh bypasses old repository cache',(){
  expect(bookingListRefreshBypassesRepositoryCache('ride_offer_assignment'),true);
 });
 test('real host wires acceptance only after confirmed decision and both entrances share callback',(){
  const sourceRoot=String.fromEnvironment('ASSIGNMENT_SOURCE_ROOT');
  final host=File('${sourceRoot}lib/driver/driver_ride_offer_host.dart').readAsStringSync();
  final home=File('${sourceRoot}lib/main_parts/driver_home_page_state.dart').readAsStringSync();
  expect(host.indexOf('widget.onAcceptanceReceived?.call'),greaterThan(host.indexOf('await client.decide')));
  expect(host,contains("action == 'accept' && _sameOwner(owner, _sessions.value)"));
  expect(RegExp('onAcceptanceReceived: _onRideOfferAcceptanceReceived').allMatches(home),hasLength(2));
  expect(home,contains('useDriverEndpoint && !nextPage && !bookingPage.degraded'));
 });
 testWidgets('delayed canonical assignment refreshes and opens My rides without role change',(t)async{
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final key=GlobalKey<AssignmentHarnessState>();
  await t.pumpWidget(MaterialApp(home:AssignmentHarness(key:key)));
  final state=key.currentState!;state.accept(actor('A'),proposal());await t.pump();
  expect(state.reads,1);expect(state.myRides,false);expect(state.pending,1);
  await t.pump(const Duration(seconds:2));expect(state.reads,2);expect(state.myRides,false);
  state.page=[BookingItem(assigned())];
  await t.pump(const Duration(seconds:2));await t.pump();
  expect(state.reads,3);expect(state.myRides,true);expect(state.pending,0);expect(state.navigations,1);
  await t.pump(const Duration(seconds:6));expect(state.reads,3);
  expect(activeDriverSessionNotifier.value?.driverId,'A');
  await t.pumpWidget(const SizedBox());
 });
 for(final fault in ['wrong booking','wrong driver','wrong vehicle','unassigned','terminal','missing leg']){
  testWidgets('$fault never promotes an ACK to canonical assignment',(t)async{
   t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
   final key=GlobalKey<AssignmentHarnessState>();await t.pumpWidget(MaterialApp(home:AssignmentHarness(key:key)));
   final row=assigned();switch(fault){
    case 'wrong booking':row['booking_id']='foreign';
    case 'wrong driver':row['assigned_driver_id']='B';
    case 'wrong vehicle':row['assigned_vehicle_id']='foreign';
    case 'unassigned':row['available_unassigned']=true;
    case 'terminal':row['status']='CANCELLED';
    case 'missing leg':row.remove('leg_id');
   }
   final state=key.currentState!..page=[BookingItem(row)];state.accept(actor('A'),proposal());
   await t.pump();await t.pump();expect(state.myRides,false);expect(state.pending,1);
   await t.pumpWidget(const SizedBox());
  });
 }
 testWidgets('changed chauffeur while canonical read waits cannot navigate or accept foreign row',(t)async{
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final key=GlobalKey<AssignmentHarnessState>();await t.pumpWidget(MaterialApp(home:AssignmentHarness(key:key)));
  final gate=Completer<void>();final state=key.currentState!..readGate=(()=>gate.future)..page=[BookingItem(assigned())];
  state.accept(actor('A'),proposal());await t.pump();
  activeDriverSessionNotifier.value=actor('B');gate.complete();await t.pump();await t.pump();
  expect(state.myRides,false);expect(state.pending,0);
  await t.pumpWidget(const SizedBox());
 });
 testWidgets('bounded reads and pause while backgrounded, no fabricated assignment',(t)async{
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final key=GlobalKey<AssignmentHarnessState>();await t.pumpWidget(MaterialApp(home:AssignmentHarness(key:key)));
  final state=key.currentState!;state.accept(actor('A'),proposal());await t.pump();
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await t.pump(const Duration(seconds:8));expect(state.reads,1);
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  for(var i=0;i<18;i++){await t.pump(const Duration(seconds:2));}
  expect(state.reads,15);expect(state.myRides,false);expect(state.pending,1);
  await t.pumpWidget(const SizedBox());
 });
 testWidgets('company preview and wrong tenant cannot start personal canonical reads',(t)async{
  final key=GlobalKey<AssignmentHarnessState>();await t.pumpWidget(MaterialApp(home:AssignmentHarness(key:key,openedFromBusinessHome:true)));
  key.currentState!.accept(actor('A'),proposal());await t.pump();expect(key.currentState!.reads,0);
  await t.pumpWidget(const SizedBox());
  final other=GlobalKey<AssignmentHarnessState>();await t.pumpWidget(MaterialApp(home:AssignmentHarness(key:other)));
  other.currentState!.accept(actor('A',tenant:'foreign'),proposal());await t.pump();expect(other.currentState!.reads,0);
  await t.pumpWidget(const SizedBox());
 });
}
