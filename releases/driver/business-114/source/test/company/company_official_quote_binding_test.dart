import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/customer_booking/official_address_payload.dart';

LimousineAddressValue address(String id,{String revision='revision'})=>LimousineAddressValue(
  displayText:'Teststraat 1, 9000 Gent',canonicalLabel:'Teststraat 1, 9000 Gent',lat:51,lon:4,
  acceptance:LimousineAddressAcceptance.selected,
  officialAddress:OfficialAddressIdentity(id:id,indexRevision:revision,source:'OFFICIAL_FIXTURE',sourceVersion:'v1'));
CompanyPlanQuoteRequest request(LimousineAddressValue from)=>companyPlanQuoteRequestFromAddresses(
  from:from,to:address('destination'),pickupLocal:DateTime(2026,10,16,12),options:const CompanyRideOptions(),passengers:1,
  returnEnabled:true,returnFrom:address('return-from'),returnTo:address('return-to'),
  stops:[address('stop')],returnStops:[address('return-stop')])!;
void main(){
 test('source identity survives ordinary quote, stops and return',(){
  final q=request(address('pickup'));
  expect(q.body['pickup_input']['official_address']['id'],'pickup');
  expect(q.body['destination_input']['official_address']['id'],'destination');
  expect(q.body['return_pickup_input']['official_address']['id'],'return-from');
  expect(q.body['return_destination_input']['official_address']['id'],'return-to');
  expect(q.body['stop_coordinates'][0]['input']['official_address']['id'],'stop');
  expect(q.body['return_stop_coordinates'][0]['input']['official_address']['id'],'return-stop');
  expect(q.body.containsKey('price_incl_vat'),isFalse);
 });
 test('same coordinates with different official identity or source revision invalidate quote cache',(){
  final original=request(address('pickup'));
  expect(request(address('different-house')).fingerprint,isNot(original.fingerprint));
  expect(request(address('pickup',revision:'new-revision')).fingerprint,isNot(original.fingerprint));
 });
 test('GPS never borrows official identity and no sensor accuracy is invented',(){
  final value=address('must-not-travel').copyWith(fromCurrentLocation:true);
  final payload=officialOperationalInput(value);
  expect(payload['kind'],'gps');expect(payload.containsKey('official_address'),isFalse);
  expect(payload.containsKey('accuracyMeters'),isFalse);expect(payload.containsKey('capturedAt'),isFalse);
 });
 test('editing selected label drops identity in existing field model',(){
  final changed=address('pickup').copyWith(canonicalLabel:'Andere straat 2, 9000 Gent');
  expect(changed.officialAddress,isNull);
 });
}
