import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';

const hit = LimousinePlaceSuggestion(label: 'Sint-Niklaas', lat: 51.165, lon: 4.141);
const success = LimousinePlaceLookupResult(suggestions: [hit]);

void main() {
  for (final consumers in [2, 10]) {
    test('$consumers identical concurrent consumers share one upstream and completed cache', () async {
      var calls = 0;
      final gate = Completer<LimousinePlaceLookupResult>();
      final lookup = LimousinePlaceLookup(searchOverride: (q, l) { calls++; return gate.future; });
      final requests = List.generate(consumers, (_) => lookup.search('  Sint-Niklaas  '));
      expect(calls, 1);
      expect(lookup.inFlightCoalescedCallers, consumers - 1);
      gate.complete(success);
      final results = await Future.wait(requests);
      expect(results.every((r) => identical(r, success)), isTrue);
      expect(await lookup.search('Sint-Niklaas'), same(success));
      expect(calls, 1);
      expect(lookup.sessionCacheHits, 1);
    });
  }
  test('different query, country, language and proximity contexts are isolated', () async {
    final gates = <Completer<LimousinePlaceLookupResult>>[];
    final lookup = LimousinePlaceLookup(searchOverride: (q, l) {
      final gate = Completer<LimousinePlaceLookupResult>(); gates.add(gate); return gate.future;
    });
    final requests = [
      lookup.search('Sint-Niklaas', contextCountry: 'be'),
      lookup.search('Gent', contextCountry: 'be'),
      lookup.search('Sint-Niklaas', contextCountry: 'nl'),
      lookup.search('Sint-Niklaas', contextCountry: 'be', language: 'en'),
      lookup.search('Sint-Niklaas', contextCountry: 'be', proximityLat: 51, proximityLon: 4),
    ];
    expect(gates.length, 5);
    for (var i = 0; i < gates.length; i++) {
      gates[i].complete(LimousinePlaceLookupResult(suggestions: [LimousinePlaceSuggestion(label: 'context $i')]));
    }
    final results = await Future.wait(requests);
    expect(results.map((r) => r.suggestions.single.label), ['context 0','context 1','context 2','context 3','context 4']);
  });
  test('separate lookup instances cannot share provider or company-owned context', () async {
    var calls = 0;
    final gate = Completer<LimousinePlaceLookupResult>();
    Future<LimousinePlaceLookupResult> upstream(String q, String l) { calls++; return gate.future; }
    final a = LimousinePlaceLookup(token: 'company-a', searchOverride: upstream);
    final b = LimousinePlaceLookup(token: 'company-b', searchOverride: upstream);
    final requests = [a.search('Gent'), b.search('Gent')];
    expect(calls, 2); gate.complete(success); await Future.wait(requests);
  });
  test('upstream error result is shared but never poisons retry or cache', () async {
    var calls = 0;
    final failed = Completer<LimousinePlaceLookupResult>();
    final lookup = LimousinePlaceLookup(searchOverride: (q,l) { calls++; return calls == 1 ? failed.future : Future.value(success); });
    final a = lookup.search('Gent'), b = lookup.search('Gent');
    failed.complete(const LimousinePlaceLookupResult(hadError: true));
    expect((await a).hadError, isTrue); expect((await b).hadError, isTrue);
    expect(calls, 1); expect(await lookup.search('Gent'), same(success)); expect(calls, 2);
    await lookup.search('Gent'); expect(calls, 2);
  });
  test('thrown upstream failure reaches both consumers; next call retries', () async {
    var calls = 0;
    final failed = Completer<LimousinePlaceLookupResult>();
    final lookup = LimousinePlaceLookup(searchOverride: (q,l) { calls++; return calls == 1 ? failed.future : Future.value(success); });
    final a = lookup.search('Gent'), b = lookup.search('Gent');
    final checks = [expectLater(a, throwsStateError), expectLater(b, throwsStateError)];
    failed.completeError(StateError('upstream')); await Future.wait(checks);
    expect(await lookup.search('Gent'), same(success)); expect(calls, 2);
  });
  test('synchronous upstream failure also clears pending entry', () async {
    var calls = 0;
    final lookup = LimousinePlaceLookup(searchOverride: (q,l) { if (++calls == 1) throw StateError('sync'); return Future.value(success); });
    await expectLater(lookup.search('Gent'), throwsStateError);
    expect(await lookup.search('Gent'), same(success)); expect(calls, 2);
  });
  testWidgets('real HTTP timeout is shared and retry succeeds without increasing timeout', (tester) async {
    var calls = 0;
    final stalled = Completer<http.Response>();
    final client = MockClient((request) { calls++; return calls == 1 ? stalled.future : Future.value(http.Response(jsonEncode({'features': []}), 200)); });
    final lookup = LimousinePlaceLookup(token: 'test', client: client);
    final a = lookup.search('Gent'), b = lookup.search('Gent');
    await tester.pump(); expect(calls, 1);
    await tester.pump(kLimousineAddressLookupTimeout);
    expect((await a).hadError, isTrue); expect((await b).hadError, isTrue);
    final retry = lookup.search('Gent'); await tester.pump(); expect((await retry).hadError, isFalse);
    expect(calls, 2); stalled.complete(http.Response('{}', 200)); await tester.pump(); client.close();
  });
  testWidgets('cleared/disposed consumer does not cancel other consumer or display stale result', (tester) async {
    var calls = 0; final gate = Completer<LimousinePlaceLookupResult>();
    final lookup = LimousinePlaceLookup(searchOverride: (q,l) { calls++; return gate.future; });
    final a = LimousineAddressFieldController(lookup: lookup, fieldId: 'a');
    final b = LimousineAddressFieldController(lookup: lookup, fieldId: 'b');
    for (final c in [a,b]) { c.textController.text = 'Gent'; c.onTextChanged('Gent'); }
    await tester.pump(kLimousineAddressDebounce); expect(calls, 1);
    a.textController.clear(); a.onTextChanged(''); a.dispose();
    gate.complete(success); await tester.pump(); expect(b.suggestions, [hit]); b.dispose();
  });
}
