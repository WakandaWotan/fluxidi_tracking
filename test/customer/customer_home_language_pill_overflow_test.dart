import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main.dart';

void main() {
  test('language pill keeps a 44px tap floor without clamping width', () {
    final source = File('lib/main_parts/customer_home_page.dart').readAsStringSync();
    final start = source.indexOf('Widget _customerLanguagePill(');
    expect(start, greaterThanOrEqualTo(0));
    final end = source.indexOf('void _openCalculator(', start);
    final body = source.substring(start, end > start ? end : start + 4000);
    expect(RegExp(r'SizedBox\(\s*width:\s*44').hasMatch(body), isFalse);
    expect(body.contains('minWidth: 44'), isTrue);
    expect(
      body.contains("key: const ValueKey<String>('customer_home_language_pill')"),
      isTrue,
    );
  });

  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('fluxidi_customer_home_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('Windows landscape language pill does not overflow', (
    tester,
  ) async {
    FlutterError.onError = (details) {
      if (details.exception is FlutterError &&
          details.exception.toString().contains('overflowed')) {
        fail('${details.exception}');
      }
      FlutterError.presentError(details);
    };
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildFluxidiRootMaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          colorScheme: const ColorScheme.dark(primary: Color(0xFFE5B641)),
        ),
        home: const CustomerHomePage(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.language_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('customer_home_language_pill')), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
    final size = tester.getSize(
      find.byKey(const ValueKey<String>('customer_home_language_pill')),
    );
    expect(size.width, greaterThan(44));
    expect(tester.takeException(), isNull);
  });
}
