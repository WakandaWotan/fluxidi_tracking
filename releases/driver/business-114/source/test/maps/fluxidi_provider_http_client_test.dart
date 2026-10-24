import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/maps/fluxidi_provider_http_client.dart';
void main() {
 test('all default HTTP callers are denied before paid transport, without leaking URL or token',() async {
  var transports=0;
  await http.runWithClient(() async {
   for(final host in ['api.mapbox.com','events.mapbox.com','a.tiles.mapbox.com','mapbox.com','api.mapbox.cn','API.MAPBOX.COM.']) {
    try {await http.get(Uri.https(host,'/directions/v5/private',{'access_token':'SECRET_FIXTURE'}));fail('provider escaped');}
    on http.ClientException catch(e){expect(e.toString(),isNot(contains('SECRET_FIXTURE')));expect(e.toString(),isNot(contains('/directions')));}
   }
  },()=>FluxidiProviderHttpClient(MockClient((r)async{transports++;return http.Response('unexpected',200);})));expect(transports,0);
 });
 test('own BE/NL APIs and genuine non-Mapbox domains remain available',()async{
  final hosts=<String>[];
  await http.runWithClient(()async{
   for(final host in ['fluxidi-maplibre-be-nl.fluxidi.workers.dev','fluxidi-booking.fluxidi.workers.dev','fluxidi-navigation.fluxidi.workers.dev','mapbox.com.example.invalid']) {
    expect((await http.get(Uri.https(host,'/existing'))).statusCode,200);
   }
  },()=>FluxidiProviderHttpClient(MockClient((r)async{hosts.add(r.url.host);return http.Response('ok',200);})));expect(hosts,hasLength(4));
 });
}
