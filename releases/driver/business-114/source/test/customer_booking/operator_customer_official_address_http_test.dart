import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/customer_booking/official_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

final cases =
    (jsonDecode(
              File(
                'test/customer_booking/fixtures/official_text_http_native.json',
              ).readAsStringSync(),
            )
            as Map)['cases']
        as Map;
http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final name in cases.keys)
    test(
      'native official DTO $name survives suggest/select/reverify without Mapbox',
      () async {
        final fixture = cases[name] as Map,
            body = Map<String, dynamic>.from(fixture['response']);
        final requests = <http.Request>[];
        final lookup = OfficialAddressLookup(
          baseUrl: 'https://fixture.invalid',
          tokenLoader: () async => 'fixture-token',
          sessionRevision: () => 1,
          client: MockClient((request) async {
            requests.add(request);
            expect(request.url.host, 'fixture.invalid');
            expect(
              request.url.path,
              '/company/official-address-search',
            );
            expect(request.followRedirects, false);
            expect(request.headers['authorization'], 'Bearer fixture-token');
            final input = jsonDecode(request.body);
            if (input['mode'] == 'suggest') return json(body);
            final candidate = (body['candidates'] as List).firstWhere(
              (c) =>
                  c['official_address']['id'] ==
                  input['official_address']['id'],
            );
            return json({
              'schema': OfficialAddressLookup.schema,
              'ok': true,
              'index_revision': body['index_revision'],
              'candidate': candidate,
              'accessProven': false,
              'routeProven': false,
            });
          }),
        );
        final result = await lookup.search(fixture['request']['query']);
        final s = result.suggestions.firstWhere(
          (c) => c.officialAddress?.id == fixture['targetId'],
        );
        final verified = await lookup.verifySuggestion(s);
        expect(verified.officialAddress!.toJson(), s.officialAddress!.toJson());
        expect(verified.label, s.label);
        final value = LimousineAddressValue(
          displayText: s.label,
          lat: s.lat,
          lon: s.lon,
          officialAddress: s.officialAddress,
        );
        if (s.officialUsable) {
          await lookup.reverifyAddress(value);
        } else {
          await expectLater(lookup.reverifyAddress(value), throwsStateError);
        }
        expect(requests.map((r) => jsonDecode(r.body)['mode']), [
          'suggest',
          'select',
          'reverify',
        ]);
        lookup.dispose();
      },
    );
  for (final status in [401, 404, 409, 429, 503, 302])
    test(
      'HTTP$status never restores a provider or reports empty catalog',
      () async {
        var calls = 0;
        final lookup = OfficialAddressLookup(
          baseUrl: 'https://fixture.invalid',
          tokenLoader: () async => 'fixture',
          sessionRevision: () => 1,
          client: MockClient((r) async {
            calls++;
            return json({'ok': false}, status);
          }),
        );
        await expectLater(
          lookup.search('Kerkstraat 15 Gent'),
          throwsStateError,
        );
        expect(calls, 1);
        lookup.dispose();
      },
    );
  test('session replacement rejects a delayed response', () async {
    var revision = 1;
    final reply = Completer<http.Response>();
    final lookup = OfficialAddressLookup(
      baseUrl: 'https://fixture.invalid',
      tokenLoader: () async => 'fixture',
      sessionRevision: () => revision,
      client: MockClient((_) => reply.future),
    );
    final future = lookup.search('Kerkstraat 15 Gent');
    await Future<void>.delayed(Duration.zero);
    revision = 2;
    reply.complete(json(cases['requested-Gent']['response']));
    await expectLater(future, throwsStateError);
    lookup.dispose();
  });
  test(
    'field applies only selected canonical official data after verification',
    () async {
      final b = cases['BE-VLG-box']['response'];
      final lookup = OfficialAddressLookup(
        baseUrl: 'https://fixture.invalid',
        tokenLoader: () async => 'fixture',
        sessionRevision: () => 1,
        client: MockClient((r) async {
          final input = jsonDecode(r.body);
          return json(
            input['mode'] == 'suggest'
                ? b
                : {
                    'schema': OfficialAddressLookup.schema,
                    'ok': true,
                    'index_revision': b['index_revision'],
                    'candidate': b['candidates'][0],
                    'accessProven': false,
                    'routeProven': false,
                  },
          );
        }),
      );
      final s = (await lookup.search('Bus adres')).suggestions[0];
      final controller = LimousineAddressFieldController(
        lookup: lookup,
        fieldId: 'fixture',
      );
      controller.seedText('Wrong typed house 999');
      await controller.selectSuggestion(s);
      expect(controller.value.canonicalLabel, s.label);
      expect(
        controller.value.officialAddress!.toJson(),
        s.officialAddress!.toJson(),
      );
      expect(controller.confirmManualFallback(), false);
      controller.dispose();
      lookup.dispose();
    },
  );
  test(
    'ordinary booking provider counter: legacy forward/reverse 2 to official Mapbox 0',
    () async {
      var mapbox = 0, official = 0;
      final legacy = LimousinePlaceLookup(
        token: 'fixture',
        client: MockClient((r) async {
          expect(r.url.host, 'api.mapbox.com');
          mapbox++;
          return json({'features': []});
        }),
      );
      await legacy.search('Kerkstraat 15 Gent');
      await legacy.reverseGeocode(51, 3);
      expect(mapbox, 2);
      mapbox = 0;
      final b = cases['requested-Gent']['response'];
      final lookup = OfficialAddressLookup(
        baseUrl: 'https://fixture.invalid',
        tokenLoader: () async => 'fixture',
        sessionRevision: () => 1,
        client: MockClient((r) async {
          if (r.url.host == 'api.mapbox.com') mapbox++;
          official++;
          final input = jsonDecode(r.body);
          return json(
            input['mode'] == 'suggest'
                ? b
                : {
                    'schema': OfficialAddressLookup.schema,
                    'ok': true,
                    'index_revision': b['index_revision'],
                    'candidate': b['candidates'][0],
                    'accessProven': false,
                    'routeProven': false,
                  },
          );
        }),
      );
      final selected = await lookup.verifySuggestion(
        (await lookup.search('Kerkstraat 15 Gent')).suggestions[0],
      );
      await lookup.reverifyAddress(
        LimousineAddressValue(
          displayText: selected.label,
          officialAddress: selected.officialAddress,
        ),
      );
      await lookup.reverseGeocode(51, 3);
      expect(mapbox, 0);
      expect(official, 3);
      lookup.dispose();
      legacy.dispose();
    },
  );
  test('a delayed official selection cannot replace edited text', () async {
    final reply = Completer<http.Response>(),
        b = cases['requested-Gent']['response'];
    final lookup = OfficialAddressLookup(
      baseUrl: 'https://fixture.invalid',
      tokenLoader: () async => 'fixture',
      sessionRevision: () => 1,
      client: MockClient(
        (r) async =>
            jsonDecode(r.body)['mode'] == 'suggest' ? json(b) : reply.future,
      ),
    );
    final s = (await lookup.search('Kerkstraat 15 Gent')).suggestions[0];
    final field = LimousineAddressFieldController(
      lookup: lookup,
      fieldId: 'delayed',
    );
    field.seedText('Kerkstraat 15 Gent');
    final selection = field.selectSuggestion(s);
    field.seedText('Andere straat 20');
    reply.complete(
      json({
        'schema': OfficialAddressLookup.schema,
        'ok': true,
        'index_revision': b['index_revision'],
        'candidate': b['candidates'][0],
        'accessProven': false,
        'routeProven': false,
      }),
    );
    await selection;
    expect(field.value.officialAddress, isNull);
    expect(field.textController.text, 'Andere straat 20');
    field.dispose();
    lookup.dispose();
  });
  test('missing session does not start infrastructure calls', () async {
    var calls = 0;
    final lookup = OfficialAddressLookup(
      baseUrl: 'https://fixture.invalid',
      tokenLoader: () async => '',
      sessionRevision: () => 1,
      client: MockClient((r) async {
        calls++;
        return json({});
      }),
    );
    await expectLater(lookup.search('Kerkstraat 15 Gent'), throwsStateError);
    expect(calls, 0);
    lookup.dispose();
  });
  test(
    'select fails closed when the official source version changes',
    () async {
      final b = cases['requested-Gent']['response'];
      var select = false;
      final lookup = OfficialAddressLookup(
        baseUrl: 'https://fixture.invalid',
        tokenLoader: () async => 'fixture',
        sessionRevision: () => 1,
        client: MockClient((r) async {
          if (!select) return json(b);
          final c = jsonDecode(jsonEncode(b['candidates'][0]));
          c['official_address']['source_version'] = 'changed';
          return json({
            'schema': OfficialAddressLookup.schema,
            'ok': true,
            'index_revision': b['index_revision'],
            'candidate': c,
            'accessProven': false,
            'routeProven': false,
          });
        }),
      );
      final s = (await lookup.search('Kerkstraat 15 Gent')).suggestions[0];
      select = true;
      await expectLater(lookup.verifySuggestion(s), throwsStateError);
      lookup.dispose();
    },
  );
}
