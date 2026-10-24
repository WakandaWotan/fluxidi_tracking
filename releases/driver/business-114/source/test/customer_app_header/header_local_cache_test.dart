import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_app_header/customer_app_header_branding.dart';
import 'package:fluxidi_tracking/customer_app_header/header_local_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a fresh reader restores company presentation and cannot cross company scope', () async {
    final directory = await Directory.systemTemp.createTemp('header-cache-test');
    addTearDown(() => directory.delete(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (_) async => directory.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), null));
    await cacheHeaderBranding('api|company-A', const CustomerAppHeaderBranding(companyName: 'A', logoUrl: 'https://example.org/a.png', mediaRevision: '7', useOnDriverApp: true));
    final restored = await loadCachedHeaderBranding('api|company-A');
    expect(restored?.companyName, 'A');
    expect(restored?.mediaRevision, '7');
    expect(restored?.useOnDriverApp, isTrue);
    expect(await loadCachedHeaderBranding('api|company-B'), isNull);
    expect(await loadCachedHeaderBranding('another-api|company-A'), isNull);
    expect(await readHeaderPresentation('api|company-A'), isNotNull);
  });
}
