import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/customer_booking/reliable_choice_api.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_vehicles.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';

/// Synthetic public-contract fixture for existing UI/payment regressions.
/// Eligibility and route correctness are tested through the real Node worker.
ReliableChoiceApiV1 p21UiFixture(CustomerBookingEntryContext entry,CustomerBookingProfileGet profileGet,{String bookingMode='reliable_choice',void Function(String path)? onRequest}){
 return ReliableChoiceApiV1(base:Uri.parse('http://127.0.0.1:8788'),token:'fixture-customer',client:MockClient((request)async{
  onRequest?.call(request.url.path);
  if(request.url.path=='/public/customer/booking-capabilities')return http.Response(jsonEncode({'ok':true,'schema':'fluxidi-public-booking-capabilities-v1','booking_mode':bookingMode,'booking_allowed':bookingMode!='unavailable','automatic_dispatch':bookingMode=='reliable_choice','customer_live_tracking':bookingMode=='reliable_choice'}),200);
  if(request.url.path.endsWith('/status'))return http.Response(jsonEncode({'ok':true,'state':'waiting_driver_confirmation','eta_is_estimate':true,'live_tracking':false}),200);
  final input=jsonDecode(request.body) as Map<String,dynamic>;
  final legacy=await profileGet(Uri.parse('http://127.0.0.1:8788/public/partners/fixture/availability'));
  Map raw={};try{raw=jsonDecode(legacy.body) as Map;}catch(_){}
  final available=(raw['vehicles'] as List? ?? []).whereType<Map>().where((r)=>r['available']==true).map((r)=>r['vehicle_id']).toSet();
  final now=DateTime.now().millisecondsSinceEpoch;
  return http.Response(jsonEncode({'ok':true,'schema':'fluxidi-reliable-choice-v1','selection_token':'11111111-1111-4111-8111-111111111111','vehicles':[
   for(final v in entry.company.vehicles)if(available.contains(companyAgendaVehicleId(v))) {
    'schema':'fluxidi-reliable-choice-v1','vehicle_id':companyAgendaVehicleId(v),'vehicle_name':companyAgendaVehicleName(v),'vehicle_type':v['vehicle_type']??'sedan','vehicle_category':v['category']??v['tier']??'comfort','photo_url':v['photo_url'],
    'passenger_capacity':companyAgendaVehiclePassengerSeats(v)??4,'luggage_capacity':v['luggage_capacity']??2,
    'pickup_eta_seconds':300,'pickup_eta_range_seconds':[240,420],'pickup_distance_meters':1100,'estimate':true,'status':'estimated_availability',
    'graph_version':'synthetic-ui-graph','route_evidence_id':'synthetic-ui-route','evidence_revision':'synthetic-ui-r1','valid_until_ms':now+15000,
   }
  ]}),200);
 }));
}
