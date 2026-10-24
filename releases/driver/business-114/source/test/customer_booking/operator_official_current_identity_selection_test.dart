import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/customer_booking/official_address_lookup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cases = (jsonDecode(File('test/customer_booking/fixtures/official_text_http_native.json').readAsStringSync()) as Map)['cases'] as Map;
  for (final name in ['BE-BRU', 'BE-BRU-multilingual', 'requested-Bruxelles', 'official-German']) {
    test('current native official identity $name can be selected without inventing assignment or road access', () async {
      final fixture = cases[name] as Map;
      final body = Map<String, dynamic>.from(fixture['response']);
      final raw = (body['candidates'] as List).firstWhere((r) => r['official_address']['id'] == fixture['targetId']);
      expect(raw['officially_assigned'], isNull);
      final modes = <String>[];
      final lookup = OfficialAddressLookup(
        baseUrl: 'https://fixture.invalid', tokenLoader: () async => 'fixture', sessionRevision: () => 1,
        client: MockClient((r) async {
          expect(r.url.host, 'fixture.invalid');
          final input = jsonDecode(r.body) as Map; modes.add(input['mode']);
          return http.Response(jsonEncode(input['mode'] == 'suggest' ? body : {
            'schema': OfficialAddressLookup.schema, 'ok': true, 'index_revision': body['index_revision'],
            'candidate': raw, 'accessProven': false, 'routeProven': false,
          }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );
      final result = await lookup.search(fixture['request']['query']);
      final selected = result.suggestions.firstWhere((s) => s.officialAddress?.id == fixture['targetId']);
      expect(selected.officialUsable, isTrue);
      final verified = await lookup.verifySuggestion(selected);
      expect(verified.officialUsable, isTrue);
      expect(verified.officialAddress!.toJson(), raw['official_address']);
      expect(raw['officially_assigned'], isNull);
      expect(raw['accessProven'], isFalse); expect(raw['routeProven'], isFalse);
      expect(modes, ['suggest','select']); lookup.dispose();
    });
  }
  for (final name in ['BE-WAL-not-current','BE-VLG-not-current','NL-not-current','BE-WAL-missing-position','NL-research','NL-letter']) {
    test('native invalid/noncurrent/missing/research record $name remains unselectable', () async {
      final fixture = cases[name] as Map; final body = fixture['response'];
      final lookup = OfficialAddressLookup(
        baseUrl: 'https://fixture.invalid', tokenLoader: () async => 'fixture', sessionRevision: () => 1,
        client: MockClient((r) async => http.Response(jsonEncode(body),200,headers:{'content-type':'application/json; charset=utf-8'})),
      );
      final result = await lookup.search(fixture['request']['query']);
      expect(result.suggestions.firstWhere((s) => s.officialAddress?.id == fixture['targetId']).officialUsable,isFalse);
      lookup.dispose();
    });
  }
}
