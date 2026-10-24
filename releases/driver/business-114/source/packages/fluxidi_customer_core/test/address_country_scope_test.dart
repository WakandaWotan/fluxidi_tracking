import 'dart:convert';
import 'package:fluxidi_customer_core/fluxidi_customer_core.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
void main() {
 test('Dutch street lookup and reverse are not restricted to Belgium', () async {
  final urls=<Uri>[];
  final client=FluxidiAddressSearchClient(token:'pk.test',httpGet:(url) async {
   urls.add(url);
   return http.Response(jsonEncode({'features':[{
    'id':'address.hulst','place_name':'Tivoliweg 115, Hulst, Nederland',
    'place_type':['address'],'center':[4.05,51.28]
   }]}),200);
  });
  final found=await client.search('Nederland Tivoliweg 115');
  final reverse=await client.reverse(lat:51.28,lon:4.05);
  expect(urls.every((url)=>!url.queryParameters.containsKey('country')),isTrue);
  expect(Uri.decodeComponent(urls.first.path),contains('Nederland Tivoliweg 115'));
  expect(urls.first.queryParameters['types'],'address');
  expect(found.single.label,contains('115'));
  expect(found.single.lon,4.05);
  expect(reverse,isNotNull);
 });
 test('an explicitly configured company country filter is retained', () async {
  Uri? request;
  final client=FluxidiAddressSearchClient(token:'pk.test',country:'be,nl',httpGet:(url) async {
   request=url;return http.Response('{"features":[]}',200);
  });
  await client.search('Tivoliweg 115');
  expect(request!.queryParameters['country'],'be,nl');
 });
}
