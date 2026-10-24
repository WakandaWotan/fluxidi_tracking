import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/company/company_trip_route.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

void main() {
  final a=companyAirportAddressValue(airportByIata('BRU')!);
  final b=companyAirportAddressValue(airportByIata('AMS')!);
  CompanyPlanQuoteRequest request(LimousineAddressValue from,LimousineAddressValue to,{bool roundtrip=false})=>companyPlanQuoteRequestFromAddresses(
    from:from,to:to,pickupLocal:DateTime(2026,10,20,12),options:CompanyRideOptions(service:'airport',airportIata:'AMS',airportDirection:'to_airport'),passengers:1,
    returnEnabled:roundtrip,returnPickupLocal:DateTime(2026,10,21,12),returnFrom:roundtrip?to:null,returnTo:roundtrip?from:null,
    stops:roundtrip?[from]:[],returnStops:roundtrip?[to]:[])!;
  test('company request carries exact indexed identities for both legs and stops',(){
    final body=request(a,b,roundtrip:true).body;
    expect((body['pickup_input'] as Map)['official_address'],a.officialAddress!.toJson());
    expect((body['destination_input'] as Map)['official_address'],b.officialAddress!.toJson());
    expect((body['return_pickup_input'] as Map)['official_address'],b.officialAddress!.toJson());
    expect((body['return_destination_input'] as Map)['official_address'],a.officialAddress!.toJson());
    expect(body['stop_coordinates'][0]['input']['official_address'],a.officialAddress!.toJson());
    expect(body['return_stop_coordinates'][0]['input']['official_address'],b.officialAddress!.toJson());
    expect(body.containsKey('price_incl_vat'),false);
    expect(body.containsKey('priceInclVat'),false);
  });
  test('same coordinates with changed official source cannot reuse quote fingerprint',(){
    final first=request(a,b);
    final changed=LimousineAddressValue(displayText:a.displayText,canonicalLabel:a.canonicalLabel,lat:a.lat,lon:a.lon,placeId:a.placeId,
      acceptance:a.acceptance,officialAddress:OfficialAddressIdentity(id:a.officialAddress!.id,indexRevision:a.officialAddress!.indexRevision,source:a.officialAddress!.source,sourceVersion:'changed-requires-reverify'));
    expect(request(changed,b).fingerprint,isNot(first.fingerprint));
  });
  test('legacy address is not relabeled as an official airport identity',(){
    const legacy=LimousineAddressValue(displayText:'Old street 1',canonicalLabel:'Old street 1',lat:51,lon:4,acceptance:LimousineAddressAcceptance.selected);
    final body=request(legacy,legacy).body;
    expect(body.containsKey('pickup_input'),false);
    expect(body.containsKey('destination_input'),false);
    expect(body.containsKey('stop_coordinates'),false);
  });
}
