import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/company/company_dispatch.dart';

void main() {
  test('a heartbeat with no offers makes no extra requests', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      expect(jsonDecode(request.body), {'dispatch_protocol': 1});
      return http.Response(
        jsonEncode({'ok': true, 'dispatch_protocol': 1, 'dispatch_offers': []}),
        200,
      );
    });
    final result = await syncPublicDriverHeartbeat(
      driverSessionToken: 'fixture-session',
      client: client,
    );
    expect(result.ok, true);
    expect(paths, ['/public/driver/heartbeat']);
  });

  test(
    'receipt forwards exact offer identity using the authenticated session',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('heartbeat')
                ? {
                    'ok': true,
                    'dispatch_protocol': 1,
                    'dispatch_offers': [
                      {
                        'offer_id': 'offer:B:2',
                        'version': 3,
                        'driver_id': 'untrusted',
                      },
                    ],
                  }
                : {'ok': true},
          ),
          200,
        );
      });
      await syncPublicDriverHeartbeat(
        driverSessionToken: 'fixture-session',
        client: client,
      );
      expect(requests.length, 2);
      expect(requests.last.url.path, '/public/driver/dispatch/ack');
      expect(requests.last.headers['Authorization'], 'Bearer fixture-session');
      expect(jsonDecode(requests.last.body), {
        'offer_id': 'offer:B:2',
        'version': 3,
      });
    },
  );

  test(
    'a connection failure retries the same receipt on the next heartbeat',
    () async {
      var receipts = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/ack')) {
          receipts++;
          if (receipts == 1) throw http.ClientException('network interrupted');
          return http.Response('{"ok":true}', 200);
        }
        return http.Response(
          '{"ok":true,"dispatch_protocol":1,"dispatch_offers":[{"offer_id":"O","version":1}]}',
          200,
        );
      });
      expect(
        (await syncPublicDriverHeartbeat(
          driverSessionToken: 'fixture-session',
          client: client,
        )).ok,
        true,
      );
      expect(
        (await syncPublicDriverHeartbeat(
          driverSessionToken: 'fixture-session',
          client: client,
        )).ok,
        true,
      );
      expect(receipts, 2);
    },
  );

  test('legacy protocol and invalid offers never send a receipt', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response(
        '{"ok":true,"dispatch_offers":[{"offer_id":"O","version":1}]}',
        200,
      );
    });
    await syncPublicDriverHeartbeat(
      driverSessionToken: 'fixture-session',
      client: client,
    );
    await acknowledgeDriverDispatchReceipts(
      driverSessionToken: 'fixture-session',
      offers: [
        {'offer_id': '', 'version': 1},
        {'offer_id': 'O', 'version': '1'},
        {'offer_id': 'O', 'version': 0},
        null,
      ],
      client: client,
    );
    expect(requests, 1);
  });
}
