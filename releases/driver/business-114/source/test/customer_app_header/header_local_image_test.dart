import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_app_header/header_local_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a cached revision decodes on restart without a network request', (
    tester,
  ) async {
    late Directory root;
    const url = 'https://offline.invalid/company.png?revision=7';
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('header-image');
      addTearDown(() => root.delete(recursive: true));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => root.path,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        ),
      );
      final dir = await Directory('${root.path}/company_header_v1').create();
      await File(
        '${dir.path}/${sha256.convert(utf8.encode('image:$url'))}',
      ).writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
        ),
      );
    });
    final provider = headerImageProvider(url);
    expect(provider, isNot(headerImageProvider('$url-new')));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Image(image: provider),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    for (
      var i = 0;
      i < 30 && tester.widget<RawImage>(find.byType(RawImage)).image == null;
      i++
    ) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    final raw = tester.widget<RawImage>(find.byType(RawImage));
    expect(raw.image?.width, 1);
    await tester.pumpWidget(const SizedBox());
    await provider.evict();
  });
}
