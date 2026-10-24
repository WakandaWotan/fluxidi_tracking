import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/customer_app_header/driver_session_branding.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

ActiveDriverSession session(String company) => ActiveDriverSession(
  driverId: 'driver-$company', employeeNumber: '', fullName: '', phone: '',
  loggedInAt: '', updatedAt: '', tenantId: company, companyId: company,
  companyCode: company,
);
http.Response response(String company, {bool enabled = true, String revision = '3'}) => http.Response(jsonEncode({
  'ok': true, 'company_code': company, 'display_name': company,
  'customer_app_header_mode': 'header_and_logo',
  'public_logo_url': 'https://example.org/$company-logo.png',
  'public_hero_photo_url': 'https://example.org/$company-cover.png',
  'customer_app_header_media_revision': revision,
  'driver_app_use_company_header': enabled,
}), 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('QR session loads full own header through public resolve without owner auth', () async {
    final store = DriverSessionBranding(baseUrl: 'https://example.org', client: MockClient((request) async {
      expect(request.url.path, '/public/company/resolve');
      expect(request.url.queryParameters['code'], 'FLUXIDI');
      expect(request.headers.containsKey('authorization'), isFalse);
      return response('FLUXIDI');
    }));
    addTearDown(store.dispose);
    store.updateSession(session('FLUXIDI'));
    await Future<void>.delayed(Duration.zero);
    final header = store.forSession(session('FLUXIDI'))!;
    expect(header.hasCover, isTrue);
    expect(header.hasLogo, isTrue);
    expect(header.useOnDriverApp, isTrue);
    expect(header.displayLogoUrl, contains('FLUXIDI-logo'));
    expect(store.forSession(session('MARIO')), isNull);
  });
  test('company switch and logout reject delayed responses from the old driver', () async {
    final pending = <String, Completer<http.Response>>{};
    final store = DriverSessionBranding(baseUrl: 'https://example.org', client: MockClient((request) {
      final code = request.url.queryParameters['code']!;
      return (pending[code] = Completer<http.Response>()).future;
    }));
    addTearDown(store.dispose);
    store.updateSession(session('MARIO'));
    await Future<void>.delayed(Duration.zero);
    store.updateSession(session('FLUXIDI'));
    await Future<void>.delayed(Duration.zero);
    pending['FLUXIDI']!.complete(response('FLUXIDI'));
    await Future<void>.delayed(Duration.zero);
    pending['MARIO']!.complete(response('MARIO'));
    await Future<void>.delayed(Duration.zero);
    expect(store.branding!.companyName, 'FLUXIDI');
    store.updateSession(null);
    expect(store.branding, isNull);
    expect(store.forSession(session('FLUXIDI')), isNull);
  });
  test('wrong company response is rejected', () async {
    final store = DriverSessionBranding(baseUrl: 'https://example.org', client: MockClient((_) async => response('MARIO')));
    addTearDown(store.dispose);
    store.updateSession(session('FLUXIDI'));
    await Future<void>.delayed(Duration.zero);
    expect(store.branding, isNull);
  });
  test('resume refreshes saved cover mode, opt-out and media revision', () async {
    var enabled = true;
    final store = DriverSessionBranding(baseUrl: 'https://example.org', client: MockClient((_) async => response('FLUXIDI', enabled: enabled, revision: enabled ? '3' : '4')));
    addTearDown(store.dispose);
    store.updateSession(session('FLUXIDI'));
    await Future<void>.delayed(Duration.zero);
    expect(store.branding!.mediaRevision, '3');
    enabled = false;
    store.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(store.branding!.useOnDriverApp, isFalse);
    expect(store.branding!.mediaRevision, '4');
    // Turning off the company cover keeps its logo available to navigation.
    expect(store.branding!.hasLogo, isTrue);
  });
}
