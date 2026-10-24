// PRIVACY-P0-4-CORRECT-CANONICAL-EMAIL
//
// Regression guard for the central privacy contact mailbox.
//
// Contract:
//   * `kFluxidiPrivacyContactEmail` is exactly "info@fluxidi.com"
//   * every mailto: URI built by the privacy layer uses that mailbox
//   * every user-visible privacy surface (customer, business, driver) shows
//     the canonical email in NL, EN, FR and ES
//   * NO forbidden address is hardcoded anywhere under `lib/privacy/` or
//     `test/privacy/`. The typo `info@fluxity.com` in particular must never
//     reappear — it is a wrong domain (`fluxity` vs. `fluxidi`) and is not
//     a Fluxidi mailbox:
//        - info@fluxity.com          (domain typo — never valid)
//        - support@fluxidi.com       (not a Fluxidi privacy mailbox)
//        - support@fluxity.com       (not a Fluxidi privacy mailbox)
//        - fluxidi.booking@gmail.com (legacy operational address, never
//                                      a privacy contact)
//
// Run:
//   flutter test test/privacy/privacy_email_regression_p0_4_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/privacy/fluxidi_legal_urls.dart';
import 'package:fluxidi_tracking/privacy/fluxidi_privacy_account.dart';
import 'package:fluxidi_tracking/privacy/fluxidi_privacy_ui.dart';

const String _kCanonicalEmail = 'info@fluxidi.com';

const List<String> _kForbiddenAddresses = <String>[
  'info@fluxity.com',
  'support@fluxidi.com',
  'support@fluxity.com',
  'fluxidi.booking@gmail.com',
];

Iterable<File> _dartFilesUnder(String relativeDir) sync* {
  final dir = Directory(relativeDir);
  if (!dir.existsSync()) return;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.dart')) {
      yield entity;
    }
  }
}

Widget _host(Widget child) {
  return MaterialApp(
    // Force a non-EU system locale so the privacy UI is proven to use the
    // Fluxidi app language, not the device locale.
    locale: const Locale('en', 'US'),
    supportedLocales: const [
      Locale('en', 'US'),
      Locale('nl', 'NL'),
      Locale('fr', 'FR'),
      Locale('es', 'ES'),
    ],
    home: child,
  );
}

Future<void> _openBusiness(WidgetTester tester) async {
  await tester.pumpWidget(
    _host(
      const FluxidiPrivacyAccountPage(
        audience: FluxidiPrivacyAudience.business,
        isCompanyOwnerOrAdmin: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openCustomer(WidgetTester tester) async {
  await tester.pumpWidget(
    _host(
      const FluxidiPrivacyAccountPage(
        audience: FluxidiPrivacyAudience.customer,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openDriver(WidgetTester tester) async {
  await tester.pumpWidget(
    _host(
      const FluxidiPrivacyAccountPage(
        audience: FluxidiPrivacyAudience.driver,
        sessionDriverId: 'D1',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => setAppLanguage(AppLanguage.nl));
  tearDown(() => setAppLanguage(AppLanguage.en));

  group('PRIVACY-P0-4 email constant', () {
    test('kFluxidiPrivacyContactEmail is exactly info@fluxidi.com', () {
      expect(kFluxidiPrivacyContactEmail, _kCanonicalEmail);
    });

    test('fluxidiPrivacyMailtoUri uses the canonical mailbox', () {
      final u = fluxidiPrivacyMailtoUri(subject: 'Fluxidi test');
      expect(u.scheme, 'mailto');
      expect(u.path, _kCanonicalEmail);
      expect(u.toString().startsWith('mailto:$_kCanonicalEmail'), isTrue);
    });
  });

  group('PRIVACY-P0-4 privacy UI shows the canonical email', () {
    testWidgets('NL business surface shows the canonical email (Terugval)',
        (tester) async {
      setAppLanguage(AppLanguage.nl);
      await _openBusiness(tester);
      expect(find.text('Terugval: $_kCanonicalEmail'), findsOneWidget);
      expect(find.text(_kCanonicalEmail), findsWidgets);
      for (final forbidden in _kForbiddenAddresses) {
        expect(find.textContaining(forbidden), findsNothing,
            reason: 'NL business must not surface forbidden address '
                '"$forbidden"');
      }
    });

    testWidgets('EN business surface shows the canonical email (Fallback)',
        (tester) async {
      setAppLanguage(AppLanguage.en);
      await _openBusiness(tester);
      expect(find.text('Fallback: $_kCanonicalEmail'), findsOneWidget);
    });

    testWidgets('FR business surface shows the canonical email '
        '(Solution de secours)', (tester) async {
      setAppLanguage(AppLanguage.fr);
      await _openBusiness(tester);
      expect(
        find.text('Solution de secours : $_kCanonicalEmail'),
        findsOneWidget,
      );
    });

    testWidgets('ES business surface shows the canonical email (Alternativa)',
        (tester) async {
      setAppLanguage(AppLanguage.es);
      await _openBusiness(tester);
      expect(find.text('Alternativa: $_kCanonicalEmail'), findsOneWidget);
    });

    testWidgets('customer surface shows only the canonical email',
        (tester) async {
      setAppLanguage(AppLanguage.nl);
      await _openCustomer(tester);
      expect(find.text('Terugval: $_kCanonicalEmail'), findsOneWidget);
      for (final forbidden in _kForbiddenAddresses) {
        expect(find.textContaining(forbidden), findsNothing,
            reason:
                'Customer surface must not surface forbidden address '
                '"$forbidden"');
      }
    });

    testWidgets('driver surface shows only the canonical email',
        (tester) async {
      setAppLanguage(AppLanguage.nl);
      await _openDriver(tester);
      expect(find.text('Terugval: $_kCanonicalEmail'), findsOneWidget);
      for (final forbidden in _kForbiddenAddresses) {
        expect(find.textContaining(forbidden), findsNothing,
            reason:
                'Driver surface must not surface forbidden address '
                '"$forbidden"');
      }
    });
  });

  group('PRIVACY-P0-4 confirmation dialog uses the canonical email', () {
    testWidgets('NL customer dialog body references info@fluxidi.com',
        (tester) async {
      setAppLanguage(AppLanguage.nl);
      await _openCustomer(tester);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      // The dialog body ends with a period; the page's small footer text
      // does not. Both may live in the widget tree while the dialog is open.
      expect(
        find.textContaining('Terugval: $_kCanonicalEmail.'),
        findsOneWidget,
      );
      for (final forbidden in _kForbiddenAddresses) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });

    testWidgets('FR business dialog body references info@fluxidi.com',
        (tester) async {
      setAppLanguage(AppLanguage.fr);
      await _openBusiness(tester);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Solution de secours : $_kCanonicalEmail.'),
        findsOneWidget,
      );
    });
  });

  group('PRIVACY-P0-4 lib/privacy/ contains no forbidden address', () {
    test('no forbidden privacy address is used as a Dart string literal in '
        'lib/privacy/ production code', () {
      // Only the canonical legal-URL config may mention forbidden addresses
      // in doc comments (never as a live literal). Any Dart string literal
      // with a forbidden address is a regression.
      final allowList = <String>{
        'lib/privacy/fluxidi_legal_urls.dart',
      };
      final offenders = <String>[];
      for (final file in _dartFilesUnder('lib/privacy')) {
        final normalized = file.path.replaceAll('\\', '/');
        if (allowList.contains(normalized)) continue;
        final text = file.readAsStringSync();
        for (final forbidden in _kForbiddenAddresses) {
          if (text.contains(forbidden)) {
            offenders.add('${file.path} :: $forbidden');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Forbidden privacy addresses must not appear anywhere under '
            'lib/privacy/ outside the canonical legal-URL config. The '
            'single source of truth is '
            'kFluxidiPrivacyContactEmail = "$_kCanonicalEmail". '
            'Offenders: $offenders',
      );
    });

    test('forbidden addresses in the canonical legal-URL config only appear '
        'inside documentation comments', () {
      final path = 'lib/privacy/fluxidi_legal_urls.dart';
      final text = File(path).readAsStringSync();
      for (final forbidden in _kForbiddenAddresses) {
        expect(
          text.contains("'$forbidden'"),
          isFalse,
          reason:
              '$path must never use "$forbidden" as a Dart string literal. '
              'It may only appear inside a documentation comment.',
        );
        expect(
          text.contains('"$forbidden"'),
          isFalse,
          reason:
              '$path must never use "$forbidden" as a Dart string literal.',
        );
      }
    });
  });

  group('PRIVACY-P0-4 test/privacy/ contains no forbidden address as a '
      'positive expectation', () {
    test('no forbidden privacy address appears in test/privacy/ outside '
        'this regression guard file', () {
      // This test file legitimately references the forbidden addresses to
      // enforce the ban; it is the only allowed source of those literals.
      final allowList = <String>{
        'test/privacy/privacy_email_regression_p0_4_test.dart',
      };
      final offenders = <String>[];
      for (final file in _dartFilesUnder('test/privacy')) {
        final normalized = file.path.replaceAll('\\', '/');
        if (allowList.contains(normalized)) continue;
        final text = file.readAsStringSync();
        for (final forbidden in _kForbiddenAddresses) {
          if (text.contains(forbidden)) {
            offenders.add('${file.path} :: $forbidden');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Forbidden privacy addresses must not appear in test/privacy/ '
            'outside the regression guard file. Any expectation on a '
            'forbidden address is a regression. Offenders: $offenders',
      );
    });
  });
}
