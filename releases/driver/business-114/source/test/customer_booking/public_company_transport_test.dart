import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/public_company_transport.dart';

void main() {
  test('concurrent availability reads share one request but completed availability is never reused', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) async {
      requests++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      request.response.write('{"ok":true}'); await request.response.close();
    });
    final uri = Uri.parse('http://127.0.0.1:${server.port}/partners/availability?partner_id=A');
    await Future.wait([publicCompanyGet(uri), publicCompanyGet(uri)]);
    expect(requests, 1);
    await publicCompanyGet(uri);
    expect(requests, 2);
    await publicCompanyGet(uri.replace(query: 'partner_id=B'));
    expect(requests, 3);
  });
  test('public fleet profile reuse is confined to exact company and API URL', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) async { requests++; request.response.write('public-profile'); await request.response.close(); });
    final uri = Uri.parse('http://127.0.0.1:${server.port}/partners/profile?partner_id=A');
    await publicCompanyGet(uri); await publicCompanyGet(uri);
    expect(requests, 1);
    await publicCompanyGet(uri.replace(query: 'partner_id=B'));
    expect(requests, 2);
  });
}
