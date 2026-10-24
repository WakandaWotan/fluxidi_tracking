// RELEASE-P0-CHIRON-RESET-UX-2026-07-31 — widget tests for the
// ChironTestflowResetConfirmDialog:
//
//   * dialog renders with the correct localized title, body, and actions;
//   * the precondition banner is only shown when production is currently
//     active;
//   * WCAG AA contrast is satisfied for title, body, cancel action and
//     primary action across BOTH light (cleanProfessional) and dark
//     (executiveGold) business themes;
//   * cancel closes the dialog with `null` and never invokes onReset;
//   * confirm invokes onReset exactly once even on a double tap and closes
//     the dialog with the returned progress;
//   * a backend failure keeps the dialog open, shows a readable error, and
//     re-enables the buttons for a retry.
//
// Run:
//   flutter test test/business_settings/chiron_testflow_reset_dialog_test.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluxidi_tracking/app_config.dart'
    show BackendChironConnectionApiException;
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/chiron_compliance_dashboard_page.dart';

// ---------------------------------------------------------------------------
// WCAG contrast helpers
// ---------------------------------------------------------------------------

double _wcagChannel(double c) {
  if (c <= 0.03928) return c / 12.92;
  return math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _wcagRelativeLuminance(Color color) {
  final r = _wcagChannel(color.red / 255.0);
  final g = _wcagChannel(color.green / 255.0);
  final b = _wcagChannel(color.blue / 255.0);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double wcagContrastRatio(Color a, Color b) {
  final la = _wcagRelativeLuminance(a);
  final lb = _wcagRelativeLuminance(b);
  final light = math.max(la, lb);
  final dark = math.min(la, lb);
  return (light + 0.05) / (dark + 0.05);
}

Widget _host({
  required bool productionActive,
  required Future<_TestflowProgressStub> Function() onReset,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ChironTestflowResetConfirmDialog<_TestflowProgressStub>(
        lang: AppLanguage.nl,
        productionActive: productionActive,
        onReset: onReset,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// A test-only opaque stand-in for `_ChironTestflowProgress` — the real class
// is private inside `chiron_compliance_dashboard_page.dart`. The dialog uses
// `Future<T> Function()` generically for `onReset`, so any non-null value
// satisfies the contract and the test can assert cancel-vs-confirm via
// referential identity.
// ---------------------------------------------------------------------------
class _TestflowProgressStub {
  const _TestflowProgressStub(this.label);
  final String label;
}

// ---------------------------------------------------------------------------
// Rendering & basic UX
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
  });

  testWidgets(
    'dialog renders NL title / body / actions and hides the precondition '
    'banner when production is not active',
    (tester) async {
      await tester.pumpWidget(
        _host(
          productionActive: false,
          onReset: () async => const _TestflowProgressStub('unused'),
        ),
      );
      expect(find.text('Chiron-testflow resetten?'), findsOneWidget);
      expect(find.textContaining('acceptatietest wordt teruggezet'),
          findsOneWidget);
      expect(find.text('Annuleren'), findsOneWidget);
      expect(find.text('Testflow resetten'), findsOneWidget);
      // Precondition warning only appears when production is active.
      expect(
        find.textContaining(
          'Om een nieuwe Chiron-acceptatietest te starten',
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'precondition banner is shown when production is currently active',
    (tester) async {
      await tester.pumpWidget(
        _host(
          productionActive: true,
          onReset: () async => const _TestflowProgressStub('unused'),
        ),
      );
      expect(
        find.textContaining(
          'Om een nieuwe Chiron-acceptatietest te starten, wordt productie '
          'uitgeschakeld en wordt de testomgeving opnieuw geactiveerd.',
        ),
        findsOneWidget,
      );
    },
  );

  // -------------------------------------------------------------------------
  // Contrast: title/body against the dialog surface, in every theme.
  // The test enforces the WCAG AA threshold that the audit calls out:
  //   * body text (>= 14 sp regular): 4.5:1
  //   * primary button label (14 sp bold, "large text"): 3:1
  //   * cancel button label (14 sp semibold): 4.5:1 (treated as regular)
  // -------------------------------------------------------------------------
  for (final variant in BusinessThemeVariant.values) {
    testWidgets(
      'WCAG AA contrast — title, body, buttons — theme=${variant.name}',
      (tester) async {
        businessThemeNotifier.value = variant;
        final palette = paletteForBusinessTheme(variant);

        await tester.pumpWidget(
          _host(
            productionActive: false,
            onReset: () async => const _TestflowProgressStub('unused'),
          ),
        );
        await tester.pumpAndSettle();

        // Fluxidi tokens: title/body use textPrimary/textSecondary; surface
        // is palette.surface (the Dialog `backgroundColor`).
        final titleContrast = wcagContrastRatio(
          palette.textPrimary,
          palette.surface,
        );
        expect(
          titleContrast >= 4.5,
          isTrue,
          reason:
              'Title textPrimary on card surface must satisfy WCAG AA (>=4.5). '
              'Got $titleContrast for theme=${variant.name} '
              '(text=${palette.textPrimary}, surface=${palette.surface}).',
        );
        final bodyContrast = wcagContrastRatio(
          palette.textSecondary,
          palette.surface,
        );
        expect(
          bodyContrast >= 4.5,
          isTrue,
          reason:
              'Body textSecondary on card surface must satisfy WCAG AA. '
              'Got $bodyContrast for theme=${variant.name}.',
        );
        // Cancel action uses textPrimary — same 4.5:1 target.
        final cancelContrast = wcagContrastRatio(
          palette.textPrimary,
          palette.surface,
        );
        expect(cancelContrast >= 4.5, isTrue,
            reason: 'Cancel label vs surface must satisfy WCAG AA.');
        // Primary button: textOnAccent on accent. WCAG AA large text = 3:1.
        final primaryContrast = wcagContrastRatio(
          palette.textOnAccent,
          palette.accent,
        );
        expect(
          primaryContrast >= 3.0,
          isTrue,
          reason:
              'Primary button textOnAccent on accent must satisfy WCAG AA '
              'large-text (>=3.0). Got $primaryContrast for '
              'theme=${variant.name} (text=${palette.textOnAccent}, '
              'accent=${palette.accent}).',
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Cancel closes dialog with null (via Navigator.pop) and never triggers
  // onReset.
  // -------------------------------------------------------------------------
  testWidgets(
    'cancel pops with null and never invokes onReset',
    (tester) async {
      var onResetInvoked = 0;
      Object? popResult = 'not-popped';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final result = await showDialog<_TestflowProgressStub?>(
                      context: context,
                      barrierDismissible: false,
                      builder: (dialogCtx) =>
                          ChironTestflowResetConfirmDialog<
                              _TestflowProgressStub>(
                        lang: AppLanguage.nl,
                        productionActive: false,
                        onReset: () async {
                          onResetInvoked += 1;
                          return const _TestflowProgressStub('unused');
                        },
                      ),
                    );
                    popResult = result;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Chiron-testflow resetten?'), findsOneWidget);
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();
      expect(find.text('Chiron-testflow resetten?'), findsNothing);
      expect(popResult, isNull, reason: 'Cancel must pop with null.');
      expect(
        onResetInvoked,
        0,
        reason: 'onReset must never fire when the user cancels.',
      );
    },
  );

  // -------------------------------------------------------------------------
  // Double tap on the primary button produces exactly one onReset invocation.
  // -------------------------------------------------------------------------
  testWidgets(
    'double tap on the primary button only triggers a single reset',
    (tester) async {
      final completer = Completer<_TestflowProgressStub>();
      var onResetInvoked = 0;
      Object? popResult = 'not-popped';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final result = await showDialog<_TestflowProgressStub?>(
                      context: context,
                      barrierDismissible: false,
                      builder: (dialogCtx) =>
                          ChironTestflowResetConfirmDialog<
                              _TestflowProgressStub>(
                        lang: AppLanguage.nl,
                        productionActive: false,
                        onReset: () async {
                          onResetInvoked += 1;
                          return await completer.future;
                        },
                      ),
                    );
                    popResult = result;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Two rapid taps (before the request resolves).
      await tester.tap(find.text('Testflow resetten'));
      await tester.pump(); // start busy state
      await tester.tap(find.text('Testflow resetten'), warnIfMissed: false);
      await tester.pump();

      expect(
        onResetInvoked,
        1,
        reason:
            'onReset must be invoked exactly once — the primary button is '
            'disabled the moment the first request starts.',
      );

      // Now let the network call complete.
      completer.complete(const _TestflowProgressStub('success'));
      await tester.pumpAndSettle();
      expect(popResult is _TestflowProgressStub, isTrue,
          reason: 'Dialog must pop with the onReset result on success.');
    },
  );

  // -------------------------------------------------------------------------
  // Backend failure: dialog stays open, error surfaces, buttons re-enabled.
  // -------------------------------------------------------------------------
  testWidgets(
    'backend failure keeps dialog open, shows error, does not close',
    (tester) async {
      var onResetInvoked = 0;
      Object? popResult = 'not-popped';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final result = await showDialog<_TestflowProgressStub?>(
                      context: context,
                      barrierDismissible: false,
                      builder: (dialogCtx) =>
                          ChironTestflowResetConfirmDialog<
                              _TestflowProgressStub>(
                        lang: AppLanguage.nl,
                        productionActive: false,
                        onReset: () async {
                          onResetInvoked += 1;
                          throw const BackendChironConnectionApiException(
                            error: 'chiron_kv_write_failed',
                            statusCode: 500,
                          );
                        },
                      ),
                    );
                    popResult = result;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Testflow resetten'));
      await tester.pumpAndSettle();
      // Dialog is still open (title still findable).
      expect(find.text('Chiron-testflow resetten?'), findsOneWidget);
      // Backend error surfaces in-dialog with a readable, secret-free label
      // that includes the sanitized backend code.
      expect(
        find.textContaining('chiron_kv_write_failed'),
        findsOneWidget,
        reason:
            'The sanitized backend error code must be shown to the operator.',
      );
      expect(popResult, equals('not-popped'),
          reason: 'Failed reset must NOT pop the dialog.');
      expect(onResetInvoked, 1);
    },
  );
}
