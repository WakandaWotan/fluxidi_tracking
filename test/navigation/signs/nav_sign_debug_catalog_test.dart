import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_maneuver_sign.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_sign_debug_catalog.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_sign_resolver.dart';

/// NAV-SIGNAGE-VISUAL-RELEASE-GATE: renders the debug catalog for every
/// language and writes a contact sheet per language into `test_reports/`.
///
/// The sheets are review artifacts, not golden fixtures — nothing fails on a
/// pixel diff. What is asserted is that every card resolves the expected
/// maneuver id and that its plate really loaded and decoded.
const String _reportDir = 'test_reports/nav_signage_visual_release_gate';

/// Card plate size and the catalog's device pixel ratio, which together give
/// the exact decode key the sign widget will ask the image cache for.
const double _cardSignSize = 128;
const double _catalogPixelRatio = 1.0;

void main() {
  const boundaryKey = ValueKey<String>('nav_sign_catalog_boundary');

  setUpAll(() {
    Directory(_reportDir).createSync(recursive: true);
  });

  /// Loads and decodes every plate for [language] for real, then returns which
  /// paths succeeded.
  ///
  /// Widget tests run inside a fake-async zone, so a bundle read started during
  /// a normal build never completes. Doing the work in `runAsync` and priming
  /// the image cache is what makes the cards resolve and the plates paint.
  Future<Map<String, bool>> primeLanguage(
    WidgetTester tester,
    BuildContext context,
    String language,
  ) async {
    final results = <String, bool>{};
    await tester.runAsync(() async {
      for (final entry in kNavSignReferenceEntries) {
        final path = navSignAssetPath(
          languageCode: language,
          maneuver: entry.expected!,
        );
        try {
          final data = await rootBundle.load(path);
          results[path] = data.lengthInBytes > 0;
        } on Object {
          results[path] = false;
          continue;
        }
        final decodeEdge = navSignDecodeEdge(
          size: _cardSignSize,
          devicePixelRatio: _catalogPixelRatio,
        );
        await precacheImage(
          ResizeImage(AssetImage(path), width: decodeEdge, height: decodeEdge),
          context,
        );
      }
    });
    return results;
  }

  Widget catalogApp({
    required String language,
    Map<String, bool>? loadResults,
  }) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        child: RepaintBoundary(
          key: boundaryKey,
          child: NavSignDebugCatalog(
            languageCode: language,
            entries: kNavSignReferenceEntries,
            probeAsset: loadResults == null
                ? null
                : (path) => Future<bool>.value(loadResults[path] ?? false),
            title:
                'Fluxidi navigation signs v3 — $language — '
                'input event / resolved id / language / asset path / PASS',
          ),
        ),
      ),
    );
  }

  for (final language in kNavSignLanguageCodes) {
    testWidgets('catalog $language: 34 cards resolve, load and paint', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1900);
      tester.view.devicePixelRatio = _catalogPixelRatio;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(catalogApp(language: language));
      final context = tester.element(find.byType(NavSignDebugCatalog));
      final loadResults = await primeLanguage(tester, context, language);

      expect(loadResults.values.where((ok) => ok), hasLength(34));
      expect(
        loadResults.entries.where((e) => !e.value).map((e) => e.key),
        isEmpty,
      );

      await tester.pumpWidget(
        catalogApp(language: language, loadResults: loadResults),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(NavManeuverSign),
        findsNWidgets(kNavSignReferenceEntries.length),
      );
      expect(find.text('PASS'), findsNWidgets(kNavSignReferenceEntries.length));
      expect(find.text('FAIL'), findsNothing);
      expect(find.textContaining('load: missing'), findsNothing);
      expect(find.textContaining('load: pending'), findsNothing);
      expect(find.text('lang: $language'), findsNWidgets(34));

      await tester.runAsync(() async {
        final boundary =
            tester.renderObject(find.byKey(boundaryKey))
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        expect(bytes, isNotNull);
        File(
          '$_reportDir/catalog_$language.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      });

      expect(
        File('$_reportDir/catalog_$language.png').lengthSync(),
        greaterThan(0),
      );
    });
  }

  testWidgets('every catalog card names its own asset path', (tester) async {
    tester.view.physicalSize = const Size(1400, 1900);
    tester.view.devicePixelRatio = _catalogPixelRatio;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(catalogApp(language: 'en'));
    await tester.pump();

    for (final entry in kNavSignReferenceEntries) {
      final path = navSignAssetPath(
        languageCode: 'en',
        maneuver: entry.expected!,
      );
      expect(find.text('path: $path'), findsOneWidget, reason: path);
      expect(find.text('id: ${entry.expected!.id}'), findsOneWidget);
      expect(find.text('in: ${entry.inputLabel}'), findsOneWidget);
    }
  });

  testWidgets('an unsupported catalog language renders the nl set only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1900);
    tester.view.devicePixelRatio = _catalogPixelRatio;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(catalogApp(language: 'de'));
    await tester.pump();

    expect(find.text('lang: nl'), findsNWidgets(34));
    expect(find.textContaining('/png/de/'), findsNothing);
  });
}
