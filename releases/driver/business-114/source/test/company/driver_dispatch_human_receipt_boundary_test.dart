import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/company/company_dispatch.dart';

void main() {
  test('heartbeat never acknowledges an undisplayed human proposal', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode({
          'ok': true,
          'dispatch_protocol': 1,
          'dispatch_offers': [
            {
              'offer_id': 'human-fixture',
              'version': 2,
              'human_acceptance_required': true,
            },
          ],
        }),
        200,
      );
    });
    addTearDown(client.close);
    expect(
      (await syncPublicDriverHeartbeat(
        driverSessionToken: 'local-fixture',
        client: client,
      )).ok,
      true,
    );
    expect(requests.map((r) => r.url.path), ['/public/driver/heartbeat']);
  });

  test(
    'mixed heartbeat retains legacy receipts without acknowledging human or malformed flags',
    () async {
      final receipts = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        receipts.add(jsonDecode(request.body) as Map<String, dynamic>);
        expect(request.url.path, '/public/driver/dispatch/ack');
        expect(request.headers['Authorization'], 'Bearer local-fixture');
        return http.Response('{"ok":true}', 200);
      });
      addTearDown(client.close);
      await acknowledgeDriverDispatchReceipts(
        driverSessionToken: 'local-fixture',
        client: client,
        offers: [
          {'offer_id': 'legacy-absent', 'version': 1},
          {
            'offer_id': 'human',
            'version': 2,
            'human_acceptance_required': true,
          },
          {
            'offer_id': 'legacy-false',
            'version': 3,
            'human_acceptance_required': false,
          },
          {
            'offer_id': 'bad-string',
            'version': 4,
            'human_acceptance_required': 'true',
          },
          {
            'offer_id': 'bad-null',
            'version': 5,
            'human_acceptance_required': null,
          },
          {
            'offer_id': 'bad-number',
            'version': 6,
            'human_acceptance_required': 0,
          },
        ],
      );
      expect(receipts, [
        {'offer_id': 'legacy-absent', 'version': 1},
        {'offer_id': 'legacy-false', 'version': 3},
      ]);
    },
  );
}
