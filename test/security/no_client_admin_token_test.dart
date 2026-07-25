// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Phase C — contract test)
//
// Source-contract test that proves distributable Flutter builds and native run
// scripts never carry the platform ADMIN_TOKEN, and that no driver-facing
// Flutter code path constructs an `x-admin-token` header.
//
// Scope:
//   * `lib/` (production Flutter code) must not embed the constant
//     `String.fromEnvironment('ADMIN_TOKEN', ...)` inside any file, must not
//     construct `x-admin-token` headers on driver-facing surfaces, and must
//     not resurrect `_headers(admin: true)` shortcuts.
//   * `scripts/run_fluxidi_phone_native.ps1` and
//     `scripts/run_fluxidi_tablet_native.ps1` must not pass
//     `--dart-define=ADMIN_TOKEN=` and must not fail startup on
//     `ADMIN_TOKEN` being absent.
//
// Deliberate exemptions:
//   * `lib/chiron_compliance_dashboard_page.dart` and
//     `lib/compliance_ledger_reader.dart` are operator-only compliance
//     surfaces that still accept a locally-typed admin token and are outside
//     the P0-1 scope (tracked separately as P0-2).
//   * `lib/main_parts/ride_receipt_body_state.dart` still contains admin-
//     header call sites in unstaged working-tree WIP; the migration of that
//     file is deferred. The scripts + main.dart contract still keeps those
//     call sites inert at runtime because `ADMIN_TOKEN` is never provided
//     via `--dart-define` and their `kAdminToken.trim().isNotEmpty` guards
//     always evaluate to `false` in production builds.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<String> _libExemptions = <String>[
  'lib/chiron_compliance_dashboard_page.dart',
  'lib/compliance_ledger_reader.dart',
  'lib/main_parts/ride_receipt_body_state.dart',
];

bool _isExempt(String path) {
  final normalized = path.replaceAll('\\', '/');
  for (final exempt in _libExemptions) {
    if (normalized.endsWith(exempt)) return true;
  }
  return false;
}

Iterable<File> _dartFilesUnder(Directory dir) sync* {
  if (!dir.existsSync()) return;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.dart')) {
      yield entity;
    }
  }
}

void main() {
  test(
    'lib/ only references String.fromEnvironment ADMIN_TOKEN in the '
    "documented main.dart stub with defaultValue: ''",
    () {
      final adminTokenEnvPattern = RegExp(
        r"String\.fromEnvironment\s*\(\s*['\x22]ADMIN_TOKEN['\x22]"
        r"\s*,\s*defaultValue\s*:\s*['\x22]['\x22]\s*,?\s*\)",
        multiLine: true,
      );
      final anyAdminTokenEnvPattern = RegExp(
        r"String\.fromEnvironment\s*\(\s*['\x22]ADMIN_TOKEN['\x22]",
        multiLine: true,
      );
      final offenders = <String>[];
      var mainStubOk = false;
      for (final file in _dartFilesUnder(Directory('lib'))) {
        if (_isExempt(file.path)) continue;
        final text = file.readAsStringSync();
        final hasAny = anyAdminTokenEnvPattern.hasMatch(text);
        final normalizedPath = file.path.replaceAll('\\', '/');
        final isMainStub = normalizedPath.endsWith('lib/main.dart');
        if (hasAny) {
          if (isMainStub && adminTokenEnvPattern.hasMatch(text)) {
            mainStubOk = true;
            continue;
          }
          offenders.add(file.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            "Only lib/main.dart may reference String.fromEnvironment('ADMIN_TOKEN', "
            "defaultValue: '') as a documented no-op stub. Offenders: $offenders",
      );
      expect(
        mainStubOk,
        isTrue,
        reason:
            'lib/main.dart must retain the documented `kAdminToken` stub with '
            "defaultValue: ''; the run scripts must never inject ADMIN_TOKEN "
            'via --dart-define, so the stub always evaluates to the empty '
            'string in distributable builds.',
      );
    },
  );

  test(
    "lib/ contains no active driver-surface 'x-admin-token' header "
    'construction',
    () {
      // The only files allowed to reference `x-admin-token` are the operator
      // compliance surfaces (Chiron + compliance ledger) that are tracked
      // separately, and the unstaged ride-receipt WIP whose migration is
      // deferred. Any other file adding an `x-admin-token` header is a
      // regression of the P0-1 fix.
      final offenders = <String>[];
      for (final file in _dartFilesUnder(Directory('lib'))) {
        if (_isExempt(file.path)) continue;
        final text = file.readAsStringSync();
        if (text.contains("'x-admin-token'") ||
            text.contains('"x-admin-token"')) {
          offenders.add(file.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Flutter driver-facing surfaces must never construct '
            "'x-admin-token' headers. Offenders: $offenders",
      );
    },
  );

  test('lib/ contains no _headers(admin: true) shortcut', () {
    // The historical `_headers(admin: true)` shortcut in
    // `driver_home_page_state.dart` embedded the platform ADMIN_TOKEN. The
    // Phase C migration replaced every call site with `_driverBearerHeaders`
    // or with a public/no-auth variant. Regressing to `admin: true` would
    // re-embed a client-side platform token.
    final offenders = <String>[];
    for (final file in _dartFilesUnder(Directory('lib'))) {
      if (_isExempt(file.path)) continue;
      final text = file.readAsStringSync();
      if (text.contains('_headers(admin: true)') ||
          text.contains('_headers(admin:true)')) {
        offenders.add(file.path);
      }
    }
    expect(offenders, isEmpty,
        reason: '_headers(admin: true) must never re-appear. Offenders: $offenders');
  });

  for (final script in const <String>[
    'scripts/run_fluxidi_phone_native.ps1',
    'scripts/run_fluxidi_tablet_native.ps1',
  ]) {
    test('$script does not inject ADMIN_TOKEN into the build', () {
      final file = File(script);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Run script $script must exist so this contract is enforced.',
      );
      final text = file.readAsStringSync();
      expect(
        text.contains('--dart-define=ADMIN_TOKEN'),
        isFalse,
        reason:
            '$script must not pass --dart-define=ADMIN_TOKEN=... into the '
            'Flutter build.',
      );
      expect(
        text.contains(RegExp(r'"ADMIN_TOKEN"\s*,')),
        isFalse,
        reason:
            '$script must not require ADMIN_TOKEN as a startup environment '
            'variable.',
      );
    });
  }

  // SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 5):
  // extend the run-script contract so the Learning Worker service token is
  // never baked into a distributable APK. The `lib/` reference in
  // `nav_complexity_learning_uploader.dart` stays exempt (the uploader
  // reads `String.fromEnvironment('LEARNING_SERVICE_TOKEN')` for
  // dev/staging bench builds) — but the production run scripts MUST both
  // scrub the environment variable AND never pass it into
  // `--dart-define`, so the token resolves to '' at runtime in every
  // distributable build.
  /// Strips PowerShell single-line `# …` comments so the security
  /// assertions below only inspect executable lines. Preserves the
  /// original line count so error messages stay useful.
  String stripPowerShellComments(String source) {
    final buffer = StringBuffer();
    for (final line in source.split('\n')) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('#')) {
        buffer.writeln('');
      } else {
        final hashIdx = line.indexOf('#');
        if (hashIdx > 0) {
          // Best-effort: only strip a `#` that follows whitespace so we
          // don't accidentally clip inside a `$env:foo` or a URL. This
          // is sufficient for the run scripts because every code
          // comment in them starts either at column 0 or after leading
          // whitespace.
          final priorChar = line[hashIdx - 1];
          if (priorChar == ' ' || priorChar == '\t') {
            buffer.writeln(line.substring(0, hashIdx));
          } else {
            buffer.writeln(line);
          }
        } else {
          buffer.writeln(line);
        }
      }
    }
    return buffer.toString();
  }

  for (final script in const <String>[
    'scripts/run_fluxidi_phone_native.ps1',
    'scripts/run_fluxidi_tablet_native.ps1',
  ]) {
    test(
      '$script does not inject LEARNING_SERVICE_TOKEN into the build',
      () {
        final file = File(script);
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'Run script $script must exist so this contract is enforced.',
        );
        // Strip PowerShell comments so a documentation comment that
        // narrates the removal (e.g. `# --dart-define=... has been
        // removed`) does not spuriously trip the assertion.
        final code = stripPowerShellComments(file.readAsStringSync());
        expect(
          code.contains('--dart-define=LEARNING_SERVICE_TOKEN'),
          isFalse,
          reason:
              '$script must not pass --dart-define=LEARNING_SERVICE_TOKEN=... '
              'into the Flutter build in executable code — the Learning '
              'Worker service token is a privileged secret and must never '
              'be embedded in a distributable APK.',
        );
      },
    );

    test(
      '$script scrubs Env:LEARNING_SERVICE_TOKEN before the Flutter build',
      () {
        final file = File(script);
        expect(file.existsSync(), isTrue);
        final code = stripPowerShellComments(file.readAsStringSync());
        // The scripts must scrub the ambient environment variable so it
        // cannot leak into any downstream tool that inspects
        // `$env:LEARNING_SERVICE_TOKEN` during the build.
        expect(
          code.contains(RegExp(r'Remove-Item\s+(-Path\s+)?Env:LEARNING_SERVICE_TOKEN')),
          isTrue,
          reason:
              '$script must contain a `Remove-Item Env:LEARNING_SERVICE_TOKEN` '
              'call before invoking `flutter run` / `flutter build`.',
        );
      },
    );
  }
}
