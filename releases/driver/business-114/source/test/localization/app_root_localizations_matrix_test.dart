// GLOBAL-APP-WASHOUT-OVERLAY-REGRESSION-P0-2
//
// Root-cause regression guard for the global grey/white washout observed in the
// field on 3137d6b (RELEASE-LANGUAGE-CONSISTENCY-NL-EN-FR-ES-P0).
//
// That commit pinned `MaterialApp.locale` to the Fluxidi app language and listed
// nl/en/fr/es/de in `supportedLocales`, but shipped no `localizationsDelegates`.
// The framework defaults only cover English, so under nl/fr/es/de there was no
// MaterialLocalizations in the tree and every consumer (Tooltip,
// PopupMenuButton, TextField, Scaffold, ...) threw during build. Release builds
// paint a failed subtree as a translucent grey ErrorWidget, which read in the
// field as a washed-out layer over hero images and whole pages.
//
// These tests pump the production app-root factory `buildFluxidiRootMaterialApp`
// so the contract under test cannot drift from `FluxidiDriverApp`.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/main.dart';

/// Every locale the Fluxidi language selector can activate.
///
/// Release acceptance focus is nl/en/fr/es; `de` is covered because
/// [AppLanguage] already exposes it and [kFluxidiSupportedLocales] must not
/// regress.
const Map<AppLanguage, String> _localeMatrix = <AppLanguage, String>{
  AppLanguage.nl: 'nl',
  AppLanguage.en: 'en',
  AppLanguage.fr: 'fr',
  AppLanguage.es: 'es',
  AppLanguage.de: 'de',
};

/// Snapshot of what the framework localization lookups returned inside the
/// pumped subtree.
class _ResolvedLocalizations {
  const _ResolvedLocalizations({
    required this.locale,
    required this.material,
    required this.widgets,
    required this.cupertino,
  });

  final Locale locale;
  final MaterialLocalizations material;
  final WidgetsLocalizations widgets;
  final CupertinoLocalizations cupertino;
}

/// Home widget that both records the resolved localizations and mounts the
/// concrete widgets that threw in the field.
///
/// [Tooltip], [PopupMenuButton] and [TextField] all call
/// `MaterialLocalizations.of(context)` during build, so if the delegates ever
/// disappear again this subtree throws instead of silently degrading.
class _LocalizationProbePage extends StatelessWidget {
  const _LocalizationProbePage({required this.onResolved});

  final void Function(_ResolvedLocalizations) onResolved;

  @override
  Widget build(BuildContext context) {
    onResolved(
      _ResolvedLocalizations(
        locale: Localizations.localeOf(context),
        material: MaterialLocalizations.of(context),
        widgets: WidgetsLocalizations.of(context),
        cupertino: CupertinoLocalizations.of(context),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('probe'),
        actions: <Widget>[
          // Mirrors the language pill on the role/start page and Driver Home.
          PopupMenuButton<String>(
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'nl', child: Text('NL')),
            ],
          ),
        ],
      ),
      body: const Column(
        children: <Widget>[
          Tooltip(message: 'probe-tooltip', child: Text('tooltip-child')),
          TextField(),
        ],
      ),
    );
  }
}

Future<_ResolvedLocalizations> _pumpAppRoot(WidgetTester tester) async {
  _ResolvedLocalizations? resolved;
  await tester.pumpWidget(
    buildFluxidiRootMaterialApp(
      theme: ThemeData.dark(),
      home: _LocalizationProbePage(onResolved: (r) => resolved = r),
    ),
  );
  await tester.pump();
  expect(
    resolved,
    isNotNull,
    reason: 'app-root subtree never built; localization lookup did not run',
  );
  return resolved!;
}

void main() {
  tearDown(() => setAppLanguage(AppLanguage.en));

  group('app-root locale matrix', () {
    for (final entry in _localeMatrix.entries) {
      final language = entry.key;
      final code = entry.value;

      testWidgets('$code: framework localizations resolve without error', (
        tester,
      ) async {
        setAppLanguage(language);

        final resolved = await _pumpAppRoot(tester);

        // The washout was a build exception rendered as ErrorWidget in release.
        expect(
          tester.takeException(),
          isNull,
          reason: 'app root threw while building under locale "$code"',
        );
        expect(
          find.byType(ErrorWidget),
          findsNothing,
          reason: 'ErrorWidget rendered under locale "$code"',
        );

        // Fluxidi app language owns the active locale.
        expect(resolved.locale, Locale(code));

        // Proof the *Global* delegates supplied the localizations rather than
        // the English-only framework defaults. Under the regression these
        // lookups threw outright for nl/fr/es/de.
        expect(resolved.material, isNot(isA<DefaultMaterialLocalizations>()));
        expect(resolved.widgets, isNot(isA<DefaultWidgetsLocalizations>()));
        expect(
          resolved.cupertino,
          isNot(isA<DefaultCupertinoLocalizations>()),
        );

        // Sanity: the tables actually carry content for this locale.
        expect(resolved.material.okButtonLabel, isNotEmpty);
        expect(resolved.material.cancelButtonLabel, isNotEmpty);
        expect(resolved.widgets.reorderItemUp, isNotEmpty);
        expect(resolved.cupertino.todayLabel, isNotEmpty);
      });
    }

    testWidgets('non-English locales get distinct Material translations', (
      tester,
    ) async {
      final labelsByCode = <String, String>{};
      for (final entry in _localeMatrix.entries) {
        setAppLanguage(entry.key);
        final resolved = await _pumpAppRoot(tester);
        expect(tester.takeException(), isNull);
        labelsByCode[entry.value] = resolved.material.cancelButtonLabel;
      }

      // If the Global delegates were dropped and something fell back to the
      // English-only defaults, every locale would report the same label.
      expect(
        labelsByCode.values.toSet().length,
        greaterThan(1),
        reason: 'Material labels identical across locales: $labelsByCode',
      );
      expect(labelsByCode['nl'], isNot(labelsByCode['en']));
      expect(labelsByCode['fr'], isNot(labelsByCode['en']));
      expect(labelsByCode['es'], isNot(labelsByCode['en']));
    });
  });

  group('app-root localization contract', () {
    test('canonical delegates include the three Flutter SDK delegates', () {
      expect(
        kFluxidiLocalizationsDelegates,
        containsAll(<LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ]),
      );
    });

    test('canonical supported locales keep nl/en/fr/es/de', () {
      expect(
        kFluxidiSupportedLocales.map((l) => l.languageCode).toList(),
        containsAll(<String>['nl', 'en', 'fr', 'es', 'de']),
      );
      for (final language in AppLanguage.values) {
        setAppLanguage(language);
        expect(
          kFluxidiSupportedLocales.map((l) => l.languageCode),
          contains(currentLanguageCode),
          reason:
              'AppLanguage.${language.name} has no matching supported locale',
        );
      }
      setAppLanguage(AppLanguage.en);
    });

    testWidgets('the real app root wires the canonical localization config', (
      tester,
    ) async {
      setAppLanguage(AppLanguage.es);
      await _pumpAppRoot(tester);

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.locale, const Locale('es'));
      expect(app.supportedLocales, kFluxidiSupportedLocales);
      expect(app.localizationsDelegates, isNotNull);
      expect(
        app.localizationsDelegates!.toList(),
        kFluxidiLocalizationsDelegates,
      );
    });
  });

  group('Fluxidi app language wins over device locale', () {
    tearDown(_resetPlatformLocale);

    testWidgets('device locale is ignored by the resolution callback', (
      tester,
    ) async {
      // Device says German, Fluxidi app language says French.
      tester.platformDispatcher.localesTestValue = const <Locale>[
        Locale('de'),
      ];
      setAppLanguage(AppLanguage.fr);

      final resolved = await _pumpAppRoot(tester);

      expect(tester.takeException(), isNull);
      expect(resolved.locale, const Locale('fr'));

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        app.localeResolutionCallback!(
          const Locale('de'),
          kFluxidiSupportedLocales,
        ),
        const Locale('fr'),
      );
    });

    test('unsupported app locale falls back to en', () {
      setAppLanguage(AppLanguage.es);
      expect(
        resolveFluxidiAppLocale(const <Locale>[Locale('en')]),
        const Locale('en'),
      );
      setAppLanguage(AppLanguage.en);
    });
  });

  group('negative control: reproduce the field regression', () {
    testWidgets('pinning a non-English locale without delegates throws', (
      tester,
    ) async {
      // This is exactly what 3137d6b shipped: `locale` + `supportedLocales`
      // with no `localizationsDelegates`. It must still throw, otherwise the
      // matrix tests above would pass for the wrong reason and could not
      // detect the delegates being dropped again.
      _ResolvedLocalizations? resolved;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          supportedLocales: kFluxidiSupportedLocales,
          home: _LocalizationProbePage(onResolved: (r) => resolved = r),
        ),
      );

      expect(
        tester.takeException(),
        isNotNull,
        reason:
            'a non-English pinned locale without Global delegates must fail '
            'loudly; if this ever passes the washout guard is toothless',
      );
      expect(resolved, isNull);
    });

    testWidgets('the same tree with the canonical delegates does not throw', (
      tester,
    ) async {
      setAppLanguage(AppLanguage.es);
      await _pumpAppRoot(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('language switch rebuilds without error', () {
    testWidgets('es -> fr -> nl keeps the tree exception free', (tester) async {
      for (final language in <AppLanguage>[
        AppLanguage.es,
        AppLanguage.fr,
        AppLanguage.nl,
      ]) {
        setAppLanguage(language);
        final resolved = await _pumpAppRoot(tester);
        expect(
          tester.takeException(),
          isNull,
          reason: 'switch to ${language.name} threw',
        );
        expect(find.byType(ErrorWidget), findsNothing);
        expect(resolved.locale.languageCode, currentLanguageCode);
      }
    });
  });
}

/// Restores the platform locale override installed by the device-locale test.
void _resetPlatformLocale() {
  TestWidgetsFlutterBinding.instance.platformDispatcher.clearLocalesTestValue();
}
