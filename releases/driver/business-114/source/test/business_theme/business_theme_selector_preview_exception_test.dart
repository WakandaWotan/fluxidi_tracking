import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/main.dart';
import 'package:fluxidi_tracking/widgets/business_theme_selector_sheet.dart';

void main() {
  late Directory tempDir;
  void Function(FlutterErrorDetails)? previousOnError;
  final captured = <FlutterErrorDetails>[];

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    captured.clear();
    previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      captured.add(details);
      previousOnError?.call(details);
    };
    tempDir = await Directory.systemTemp.createTemp('fluxidi_theme_preview_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    resetBusinessThemePersistenceLatchForTest();
    businessThemeNotifier.value = BusinessThemeVariant.cleanProfessional;
    brandSignaturePaletteNotifier.value = BrandSignaturePalette.defaults;
    businessShellFrameActiveNotifier.value = true;
  });

  tearDown(() async {
    FlutterError.onError = previousOnError;
    resetBusinessThemePersistenceLatchForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  ThemeData productionRootTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(primary: Color(0xFFE5B641)),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFE5B641),
          foregroundColor: Colors.black,
          textStyle: Typography.whiteMountainView.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          textStyle: Typography.whiteMountainView.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(
      buildFluxidiRootMaterialApp(
        theme: productionRootTheme(),
        home: FluxidiFrame(
          child: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => unawaited(
                          showBusinessThemeSelectorSheet(context),
                        ),
                        child: const Text('open-theme'),
                      ),
                      const SizedBox(height: 12),
                      const SizedBox(
                        width: 360,
                        child: OutlinedButton(
                          onPressed: null,
                          child: Text('Back to start page'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const SizedBox(
                        width: 360,
                        child: FilledButton(
                          onPressed: null,
                          child: Text('Unlock'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  void expectNoPreviewCrash({required String reason}) {
    expect(find.byType(ErrorWidget), findsNothing, reason: reason);
    if (captured.isNotEmpty) {
      final first = captured.first;
      fail(
        '$reason\n${first.exception}\n${first.stack}',
      );
    }
  }

  testWidgets(
    'rapid preset switching does not paint ErrorWidget or throw',
    (tester) async {
      await pumpHost(tester);
      await tester.tap(find.text('open-theme'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(kBusinessThemeSelectorSheetKey), findsOneWidget);

      for (var pass = 0; pass < 4; pass++) {
        for (final variant in BusinessThemeVariant.values) {
          previewBusinessTheme(variant);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expectNoPreviewCrash(
            reason: 'preview ${variant.name} on pass $pass',
          );
        }
      }

      previewBrandSignatureColor(const Color(0xFF1D4ED8));
      previewBusinessTheme(BusinessThemeVariant.brandSignatureGold);
      await tester.pump();
      previewBrandSignatureColor(const Color(0xFF111827));
      previewBusinessTheme(BusinessThemeVariant.executiveGold);
      await tester.pump();
      previewBusinessTheme(BusinessThemeVariant.brandSignatureGold);
      await tester.pump();
      expectNoPreviewCrash(reason: 'gold custom background preview');
      expect(isBusinessThemePreviewActive, isTrue);
      expect(
        businessThemeNotifier.value,
        BusinessThemeVariant.brandSignatureGold,
      );
    },
  );

  testWidgets('Cancel restores the saved preset without writing it', (
    tester,
  ) async {
    businessThemeNotifier.value = BusinessThemeVariant.cleanProfessional;
    await tester.binding.setSurfaceSize(const Size(800, 1280));
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: kFluxidiLocalizationsDelegates,
        supportedLocales: kFluxidiSupportedLocales,
        home: Scaffold(body: BusinessThemeSelectorSheet()),
      ),
    );
    await tester.pump();
    previewBusinessTheme(BusinessThemeVariant.fluxidiNeonRush);
    await tester.pump();
    expect(isBusinessThemePreviewActive, isTrue);
    await tester.ensureVisible(find.byKey(kBusinessThemeSelectorCancelKey));
    await tester.tap(find.byKey(kBusinessThemeSelectorCancelKey));
    await tester.pump();
    // The sheet only pops; the host route is responsible for cancel.
    cancelBusinessThemePreview();
    expect(isBusinessThemePreviewActive, isFalse);
    expect(
      businessThemeNotifier.value,
      BusinessThemeVariant.cleanProfessional,
    );
    expectNoPreviewCrash(reason: 'cancel preview');
  });

  testWidgets('Apply keeps the previewed preset and ends preview', (
    tester,
  ) async {
    businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
    await tester.binding.setSurfaceSize(const Size(800, 1280));
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: kFluxidiLocalizationsDelegates,
        supportedLocales: kFluxidiSupportedLocales,
        home: Scaffold(body: BusinessThemeSelectorSheet()),
      ),
    );
    await tester.pump();
    previewBusinessTheme(BusinessThemeVariant.emeraldIvory);
    await tester.pump();
    await tester.ensureVisible(find.byKey(kBusinessThemeSelectorApplyKey));
    await tester.tap(find.byKey(kBusinessThemeSelectorApplyKey));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    expect(isBusinessThemePreviewActive, isFalse);
    expect(
      businessThemeNotifier.value,
      BusinessThemeVariant.emeraldIvory,
    );
    expectNoPreviewCrash(reason: 'apply preview');
  });
}
