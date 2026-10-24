import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/limousine/fluxidi_endpoint_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_event_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_event_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_hotel_lookup.dart';
import 'package:fluxidi_tracking/hotels/hotel_data_source.dart';
import 'package:fluxidi_tracking/hotels/hotel_model.dart';
import 'package:fluxidi_tracking/events/event_data_source.dart';

const identity=OfficialAddressIdentity(id:'official-local-fixture',source:'S',sourceVersion:'V',indexRevision:'R');
const candidate=LimousinePlaceSuggestion(label:'Fixturestraat 1, 1000 Fixture',lat:50.9,lon:4.3,officialAddress:identity);
class Addresses extends LimousinePlaceLookup {
 Addresses(this.rows):super(token:'');
 final List<LimousinePlaceSuggestion> rows;int selects=0;
 @override Future<LimousinePlaceLookupResult> search(String rawQuery,{String language='nl',double? proximityLat,double? proximityLon,String? contextCountry}) async => LimousinePlaceLookupResult(suggestions:rows);
 @override Future<LimousinePlaceSuggestion> verifySuggestion(LimousinePlaceSuggestion s)async{selects++;return s;}
}
class Hotels extends HotelDataSource {
 @override Future<List<HotelStay>> fetchStays({HotelStayQuery query=const HotelStayQuery()})async{
 expect(query.source,'approved-local');
 return [for(final approved in [true,false]) HotelStay(id:'$approved',name:'Catalogue hotel',type:'hotel',city:'Fixture',region:'',country:'BE',address:candidate.label,description:'',imageRef:'',lat:1,lng:2,isRealApproved:approved)];
 }
}
class PendingVenue extends LimousineEventLookup {
 PendingVenue():super(token:'');
 final pending=Completer<LimousineEventVenueSuggestion?>();
 @override Future<LimousineEventVenueSuggestion?> resolveSuggestion(LimousineEventVenueSuggestion suggestion)=>pending.future;
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('hotel catalogue never borrows catalogue GPS and verifies only selected exact official address',()async{
  final a=Addresses([candidate]);final lookup=FluxidiHotelEndpointLookup(addresses:a,hotels:Hotels());
  expect(lookup.token,isEmpty);final result=await lookup.search('hotel');expect(result.suggestions,hasLength(1));expect(a.selects,0);
  expect(result.suggestions.single.latitude,isNull);final selected=await lookup.resolveSuggestion(result.suggestions.single);
  expect(a.selects,1);expect(selected!.latitude,candidate.lat);expect(selected.toEndpoint().officialAddress,identity);
 });
 test('ranked nearest or ambiguous address never becomes selected property identity',()async{
  for(final rows in [[candidate,candidate],[const LimousinePlaceSuggestion(label:'Other 2',lat:51,lon:4,officialAddress:identity)]]){
   final a=Addresses(rows);final lookup=FluxidiHotelEndpointLookup(addresses:a,hotels:Hotels());
   expect(await lookup.resolveSuggestion(LimousineHotelSuggestion(name:'Hotel',formattedAddress: candidate.label)),isNull);expect(a.selects,0);
  }
 });
 test('event seed fallback does not become real venue and manual exact selection uses own address identity',()async{
  final a=Addresses([candidate]);final lookup=FluxidiEventEndpointLookup(addresses:a,events:const LocalSeedEventDataSource());
  expect(lookup.token,isEmpty);expect((await lookup.search('venue')).suggestions,isEmpty);
  final endpoint=await lookup.resolveManual(candidate.label,eventName:'Event');expect(endpoint.officialAddress,identity);expect(endpoint.eventName,'Event');
  final unresolved=await lookup.resolveManual('Incomplete venue');expect(unresolved.officialAddress,isNull);expect(unresolved.latitude,isNull);
 });
 test('changed and disposed event selection cannot restore stale official endpoint',()async{
  final s=LimousineEventVenueSuggestion(name:'Venue',formattedAddress: candidate.label,latitude:50.9,longitude:4.3,officialAddress:identity);
  final lookup=PendingVenue();final controller=LimousineEventFieldController(lookup:lookup);
  final pending=controller.accept(s);controller.onTextChanged('x');lookup.pending.complete(s);await pending;expect(controller.selected,isNull);controller.dispose();
  final second=PendingVenue();final disposed=LimousineEventFieldController(lookup:second);
  final work=disposed.accept(s);disposed.dispose();second.pending.complete(s);await work;
 });
}
