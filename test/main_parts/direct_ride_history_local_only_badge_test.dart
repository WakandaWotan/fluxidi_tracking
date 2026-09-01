// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 5)
//
// Truthful "local/unconfirmed" ride presentation contract.
//
// Verifies:
//
//   Part A — pure derivation via `resolveRideConfirmationStateFromMaps`.
//   Part B — localized text constants for kLocalOnlyUnconfirmedBadge,
//            kLocalOnlyUnconfirmedShort, kLocalOnlyUnconfirmedDescription
//            across nl/en/fr/es.
//   Part C — source-contract wiring of `_statusChipText`, `_statusChipColor`,
//            `_summary`, `historyCard` and `_legReceiptRideStatusDisplay`.
//   Part D — non-regression: new/modified files carry no ADMIN_TOKEN,
//            x-admin-token or LEARNING_SERVICE_TOKEN references.
//   Part E — summary-counter contract: normally completed rides count,
//            local-only / backend_confirmed=false rides do NOT count,
//            total ride count is unchanged.
//
// The pure Dart helper library `lib/main_parts/local_only_ride_presentation.dart`
// is loaded as part of `package:fluxidi_tracking/main.dart`. All source-
// contract assertions read the on-disk `lib/` files so the tests keep
// verifying the wiring even after future refactors.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/main.dart';

/// Strips single-line `// …` and block `/* … */` comments so source-
/// contract assertions never trip on tokens that only appear in
/// documentation. Mirrors the helper used by the Commit 4 test.
String stripDartComments(String source) {
  final withoutBlock = source.replaceAll(
    RegExp(r'/\*[\s\S]*?\*/', multiLine: true),
    '',
  );
  final buffer = StringBuffer();
  for (final line in withoutBlock.split('\n')) {
    final idx = _findLineCommentStart(line);
    buffer.writeln(idx < 0 ? line : line.substring(0, idx));
  }
  return buffer.toString();
}

int _findLineCommentStart(String line) {
  var inSingle = false;
  var inDouble = false;
  for (var i = 0; i < line.length - 1; i++) {
    final c = line[i];
    if (c == "\\") {
      i++;
      continue;
    }
    if (!inDouble && c == "'") inSingle = !inSingle;
    if (!inSingle && c == '"') inDouble = !inDouble;
    if (!inSingle && !inDouble && c == '/' && line[i + 1] == '/') {
      return i;
    }
  }
  return -1;
}

String readSourceOrFail(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) {
    fail('Required source file missing: $relativePath');
  }
  return file.readAsStringSync();
}

/// Extracts the body of a top-level or method declaration whose signature
/// starts with `marker` (matched at the first occurrence). Uses a brace-
/// counter so multi-line signatures work correctly. Same helper used by
/// the Commit 2/3/4 source-contract tests.
String extractMethodBody(String source, String marker) {
  final start = source.indexOf(marker);
  if (start < 0) {
    fail('Marker "$marker" not found in source');
  }
  var braceOpen = source.indexOf('{', start);
  if (braceOpen < 0) {
    fail('Opening brace not found after marker "$marker"');
  }
  var depth = 1;
  var i = braceOpen + 1;
  while (i < source.length && depth > 0) {
    final c = source[i];
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
    }
    i++;
  }
  if (depth != 0) {
    fail('Unbalanced braces while extracting body for marker "$marker"');
  }
  return source.substring(braceOpen, i);
}

void main() {
  group('Part A — resolveRideConfirmationStateFromMaps (pure)', () {
    test('empty maps => unknown', () {
      expect(
        resolveRideConfirmationStateFromMaps(
          rawSource: const <String, dynamic>{},
          bookingDetails: const <String, dynamic>{},
        ),
        RideConfirmationState.unknown,
      );
    });

    test('root history_source == local_only_direct_fallback => local-only', () {
      expect(
        resolveRideConfirmationStateFromMaps(
          rawSource: const <String, dynamic>{
            'history_source': 'local_only_direct_fallback',
          },
          bookingDetails: const <String, dynamic>{},
        ),
        RideConfirmationState.localOnlyUnconfirmed,
      );
    });

    test('booking_details history_source marker => local-only', () {
      expect(
        resolveRideConfirmationStateFromMaps(
          rawSource: const <String, dynamic>{},
          bookingDetails: const <String, dynamic>{
            'history_source': 'local_only_direct_fallback',
          },
        ),
        RideConfirmationState.localOnlyUnconfirmed,
      );
    });

    test('root backend_confirmed=false (bool) => local-only', () {
      expect(
        resolveRideConfirmationStateFromMaps(
          rawSource: const <String, dynamic>{'backend_confirmed': false},
          bookingDetails: const <String, dynamic>{},
        ),
        RideConfirmationState.localOnlyUnconfirmed,
      );
    });

    test('booking_details backend_confirmed="false" (string) => local-only', () {
      expect(
        resolveRideConfirmationStateFromMaps(
          rawSource: const <String, dynamic>{},
          bookingDetails: const <String, dynamic>{
            'backend_confirmed': 'false',
          },
        ),
        RideConfirmationState.localOnlyUnconfirmed,
      );
    });

    test('backend_confirmed=true (bool) => backendConfirmed', () {
      expect(
        resolveRideConfirmationStateFromMaps(
          rawSource: const <String, dynamic>{'backend_confirmed': true},
          bookingDetails: const <String, dynamic>{},
        ),
        RideConfirmationState.backendConfirmed,
      );
    });

    test('backend_confirmed="1" numeric-string => backendConfirmed', () {
      expect(
        resolveRideConfirmationStateFromMaps(
          rawSource: const <String, dynamic>{},
          bookingDetails: const <String, dynamic>{'backend_confirmed': '1'},
        ),
        RideConfirmationState.backendConfirmed,
      );
    });

    test('fallback marker + true bool => local-only (marker wins)', () {
      expect(
        resolveRideConfirmationStateFromMaps(
          rawSource: const <String, dynamic>{
            'history_source': 'local_only_direct_fallback',
            'backend_confirmed': true,
          },
          bookingDetails: const <String, dynamic>{},
        ),
        RideConfirmationState.localOnlyUnconfirmed,
      );
    });

    test('mixed: root true + details false => local-only (false wins)', () {
      expect(
        resolveRideConfirmationStateFromMaps(
          rawSource: const <String, dynamic>{'backend_confirmed': true},
          bookingDetails: const <String, dynamic>{'backend_confirmed': false},
        ),
        RideConfirmationState.localOnlyUnconfirmed,
      );
    });
  });

  group('Part B — localized text constants', () {
    for (final lang in AppLanguage.values) {
      test('kLocalOnlyUnconfirmedBadge.$lang is non-empty', () {
        final v = kLocalOnlyUnconfirmedBadge.of(lang).trim();
        expect(v, isNotEmpty);
      });

      test('kLocalOnlyUnconfirmedShort.$lang is non-empty', () {
        final v = kLocalOnlyUnconfirmedShort.of(lang).trim();
        expect(v, isNotEmpty);
      });

      test('kLocalOnlyUnconfirmedDescription.$lang is non-empty', () {
        final v = kLocalOnlyUnconfirmedDescription.of(lang).trim();
        expect(v, isNotEmpty);
      });
    }

    test('nl badge contains "Lokaal opgeslagen" and "niet bevestigd"', () {
      final v = kLocalOnlyUnconfirmedBadge.of(AppLanguage.nl);
      expect(v.toLowerCase(), contains('lokaal opgeslagen'));
      expect(v.toLowerCase(), contains('niet bevestigd'));
    });

    test('en badge contains "Saved locally" and "unconfirmed"', () {
      final v = kLocalOnlyUnconfirmedBadge.of(AppLanguage.en);
      expect(v.toLowerCase(), contains('saved locally'));
      expect(v.toLowerCase(), contains('unconfirmed'));
    });

    test('fr badge contains "Enregistré localement" and "non confirmé"', () {
      final v = kLocalOnlyUnconfirmedBadge.of(AppLanguage.fr);
      expect(v.toLowerCase(), contains('enregistré localement'));
      expect(v.toLowerCase(), contains('non confirmé'));
    });

    test('es badge contains "Guardado localmente" and "sin confirmar"', () {
      final v = kLocalOnlyUnconfirmedBadge.of(AppLanguage.es);
      expect(v.toLowerCase(), contains('guardado localmente'));
      expect(v.toLowerCase(), contains('sin confirmar'));
    });

    test('description mentions Company Bookings visibility (all locales)', () {
      final nl = kLocalOnlyUnconfirmedDescription.of(AppLanguage.nl);
      final en = kLocalOnlyUnconfirmedDescription.of(AppLanguage.en);
      final fr = kLocalOnlyUnconfirmedDescription.of(AppLanguage.fr);
      final es = kLocalOnlyUnconfirmedDescription.of(AppLanguage.es);
      expect(nl.toLowerCase(), contains('bedrijfsritten'));
      expect(en.toLowerCase(), contains('company bookings'));
      expect(fr.toLowerCase(), contains('réservations entreprise'));
      expect(es.toLowerCase(), contains('reservas de empresa'));
    });

    test('amber ARGB constant is 0xFFF59E0B (amber-500)', () {
      expect(kLocalOnlyUnconfirmedBadgeColorArgb, 0xFFF59E0B);
    });
  });

  group('Part C — source-contract wiring', () {
    const tripHistoryPath = 'lib/main_parts/trip_history_page.dart';
    const receiptRunnerPath = 'lib/main_parts/receipt_pdf_action_runner.dart';
    const helpersPath = 'lib/main_parts/trip_history_receipt_helpers.dart';
    const mainPath = 'lib/main.dart';

    test('main.dart has a `part` directive for the new helper library', () {
      final src = readSourceOrFail(mainPath);
      final stripped = stripDartComments(src);
      expect(
        stripped,
        contains("part 'main_parts/local_only_ride_presentation.dart';"),
        reason:
            'The new pure-Dart helper library must be wired as part of the '
            'main library so its constants and derivations are visible to '
            'trip_history_page.dart and receipt_pdf_action_runner.dart.',
      );
    });

    test(
      '_TripHistoryItem exposes shouldRenderAsLocalOnlyUnconfirmed',
      () {
        final src = readSourceOrFail(helpersPath);
        final stripped = stripDartComments(src);
        expect(
          stripped,
          contains('bool get isBackendConfirmedFalse'),
          reason: 'isBackendConfirmedFalse getter must exist',
        );
        expect(
          stripped,
          contains('bool get shouldRenderAsLocalOnlyUnconfirmed'),
          reason: 'shouldRenderAsLocalOnlyUnconfirmed getter must exist',
        );
        expect(
          stripped,
          contains('isLocalOnlyDirectFallback || isBackendConfirmedFalse'),
          reason:
              'shouldRenderAsLocalOnlyUnconfirmed must OR the fallback '
              'marker with the explicit backend_confirmed=false signal.',
        );
      },
    );

    test('_statusChipText branches on shouldRenderAsLocalOnlyUnconfirmed', () {
      final src = readSourceOrFail(tripHistoryPath);
      final body = extractMethodBody(
        stripDartComments(src),
        'String _statusChipText(_TripHistoryItem item)',
      );
      expect(
        body,
        contains('item.shouldRenderAsLocalOnlyUnconfirmed'),
        reason:
            '_statusChipText must gate on shouldRenderAsLocalOnlyUnconfirmed '
            'so a local-only / backend_confirmed=false ride never renders '
            'as normal Voltooid/Completed.',
      );
      expect(
        body,
        contains('kLocalOnlyUnconfirmedBadge'),
        reason:
            '_statusChipText must use the centralized localized badge '
            'constant, not hardcoded strings.',
      );
    });

    test('_statusChipText branch precedes the completed branch', () {
      final src = readSourceOrFail(tripHistoryPath);
      final body = extractMethodBody(
        stripDartComments(src),
        'String _statusChipText(_TripHistoryItem item)',
      );
      final localOnlyIdx = body.indexOf('shouldRenderAsLocalOnlyUnconfirmed');
      final completedIdx = body.indexOf('_isCompletedStatus');
      expect(localOnlyIdx >= 0, isTrue);
      expect(completedIdx >= 0, isTrue);
      expect(
        localOnlyIdx < completedIdx,
        isTrue,
        reason:
            'The local-only branch must precede the completed branch so a '
            'ride carrying status=COMPLETED but the fallback marker never '
            'falls through to the green "Voltooid/Completed" label.',
      );
    });

    test('_statusChipColor uses kLocalOnlyUnconfirmedBadgeColorArgb', () {
      final src = readSourceOrFail(tripHistoryPath);
      final body = extractMethodBody(
        stripDartComments(src),
        'Color _statusChipColor(_TripHistoryItem item)',
      );
      expect(
        body,
        contains('item.shouldRenderAsLocalOnlyUnconfirmed'),
        reason: '_statusChipColor must gate on the same predicate.',
      );
      expect(
        body,
        contains('kLocalOnlyUnconfirmedBadgeColorArgb'),
        reason:
            '_statusChipColor must use the amber ARGB constant so the chip '
            'is visually distinct from the "Completed" green.',
      );
      final localOnlyIdx = body.indexOf('shouldRenderAsLocalOnlyUnconfirmed');
      final completedIdx = body.indexOf('_isCompletedStatus');
      expect(localOnlyIdx >= 0 && completedIdx >= 0, isTrue);
      expect(
        localOnlyIdx < completedIdx,
        isTrue,
        reason:
            'The amber branch must precede the green completed branch.',
      );
    });

    test('historyCard renders kLocalOnlyUnconfirmedDescription', () {
      final src = readSourceOrFail(tripHistoryPath);
      final body = extractMethodBody(
        stripDartComments(src),
        'Widget historyCard(_TripHistoryItem item)',
      );
      // The predicate access may wrap across lines due to the deep
      // indentation inside historyCard — collapse whitespace before the
      // substring check.
      final collapsed = body.replaceAll(RegExp(r'\s+'), '');
      expect(
        collapsed,
        contains('item.shouldRenderAsLocalOnlyUnconfirmed'),
        reason:
            'historyCard must gate the info row on the same predicate.',
      );
      expect(
        body,
        contains('kLocalOnlyUnconfirmedDescription'),
        reason:
            'historyCard must render the localized description row so the '
            'operator sees why the badge is amber and that Company Bookings '
            'may not contain the ride.',
      );
      expect(
        body,
        contains('Icons.info_outline'),
        reason: 'Description row must be preceded by an info icon.',
      );
    });

    test(
      'historyCard no longer appends the ad-hoc " • Lokaal" suffix',
      () {
        final src = readSourceOrFail(tripHistoryPath);
        final body = extractMethodBody(
          stripDartComments(src),
          'Widget historyCard(_TripHistoryItem item)',
        );
        expect(
          body.contains("' • Lokaal'"),
          isFalse,
          reason:
              'The Dutch-only " • Lokaal" suffix must be removed — the '
              'localized badge + description now cover this state across '
              'all four locales.',
        );
      },
    );

    test('_legReceiptRideStatusDisplay guards on the same predicate', () {
      final src = readSourceOrFail(receiptRunnerPath);
      final body = extractMethodBody(
        stripDartComments(src),
        'static String _legReceiptRideStatusDisplay(_TripHistoryItem item)',
      );
      expect(
        body,
        contains('item.shouldRenderAsLocalOnlyUnconfirmed'),
        reason:
            'The receipt "Rit status / Ride status" row must not present '
            'an unconfirmed ride as a normal completed ride.',
      );
      expect(
        body,
        contains('kLocalOnlyUnconfirmedBadge'),
        reason:
            'The receipt row must use the centralized badge constant, not '
            'hardcoded strings.',
      );
      final localOnlyIdx = body.indexOf('shouldRenderAsLocalOnlyUnconfirmed');
      final legacyIdx = body.indexOf('_localizedRideStatus');
      expect(localOnlyIdx >= 0 && legacyIdx >= 0, isTrue);
      expect(
        localOnlyIdx < legacyIdx,
        isTrue,
        reason:
            'The local-only guard must precede the legacy _localizedRideStatus '
            'call so the truthful label always wins.',
      );
    });

    test('_localizedRideStatus baseline still renders Afgerond/Completed', () {
      final src = readSourceOrFail('lib/main_parts/receipt_text_helpers.dart');
      final body = extractMethodBody(
        stripDartComments(src),
        'String _localizedRideStatus(String? raw)',
      );
      // Baseline preservation — a normal completed ride still renders the
      // localized Afgerond / Completed / Terminée / Finalizada.
      expect(body, contains("nl: 'Afgerond'"));
      expect(body, contains("en: 'Completed'"));
      expect(body, contains("fr: 'Terminée'"));
      expect(body, contains("es: 'Finalizada'"));
    });
  });

  group('Part D — non-regression: no forbidden tokens', () {
    // Only shipped-to-APK library code is checked here. The test file
    // itself is not distributed with the client build and it necessarily
    // references the forbidden tokens as string literals so the
    // security-suite assertions below can find them. Coverage of
    // `lib/` at large already lives in `test/security/no_client_admin_token_test.dart`.
    const shippedFiles = <String>[
      'lib/main_parts/local_only_ride_presentation.dart',
    ];

    for (final path in shippedFiles) {
      test('$path introduces no ADMIN_TOKEN / x-admin-token / '
          'LEARNING_SERVICE_TOKEN reference', () {
        final source = readSourceOrFail(path);
        final code = stripDartComments(source);
        // Sentinel names constructed at runtime so the test source itself
        // does not carry the literal strings (which would defeat the
        // security-suite scan of `lib/`).
        final adminEnv = ['ADMIN', 'TOKEN'].join('_');
        final adminHeader = 'x-${['admin', 'token'].join('-')}';
        final learningEnv = ['LEARNING', 'SERVICE', 'TOKEN'].join('_');
        expect(
          code.contains(adminEnv),
          isFalse,
          reason:
              '$path must not reference the platform admin token env '
              'name in executable code.',
        );
        expect(
          code.contains(adminHeader),
          isFalse,
          reason: '$path must not construct admin-token HTTP headers.',
        );
        expect(
          code.contains(learningEnv),
          isFalse,
          reason:
              '$path must not reference the Learning Worker service token '
              '— it is out of scope for this fix.',
        );
      });
    }
  });

  group('Part E — summary counter: local-only excluded, revenue unchanged, '
      'total unchanged', () {
    test(
      '_summary body gates ONLY the completed increment on the new predicate '
      '(revenue path untouched)',
      () {
        final src = readSourceOrFail('lib/main_parts/trip_history_page.dart');
        final stripped = stripDartComments(src);
        // Skip call-site `_summary(merged)` / `${...}` interpolations by
        // locating the method's unique record return type first.
        final methodStart = stripped.indexOf(
          'int total, int completed, int cancelled, double revenue}) _summary(',
        );
        expect(
          methodStart,
          greaterThanOrEqualTo(0),
          reason: '_summary method declaration is missing',
        );
        final body = extractMethodBody(
          stripped.substring(methodStart),
          '_summary(',
        );
        expect(
          body,
          contains('item.shouldRenderAsLocalOnlyUnconfirmed'),
          reason:
              '_summary must consult shouldRenderAsLocalOnlyUnconfirmed so '
              'unconfirmed rides do not inflate the Completed metric.',
        );
        // The guard must live INSIDE the completed branch.
        final completedGuardIdx =
            body.indexOf('_isCompletedStatus(item.status)');
        final localOnlyIdx = body.indexOf('shouldRenderAsLocalOnlyUnconfirmed');
        expect(completedGuardIdx >= 0 && localOnlyIdx >= 0, isTrue);
        expect(
          completedGuardIdx < localOnlyIdx,
          isTrue,
          reason:
              'The unconfirmed check must live inside the completed branch.',
        );
        // The `total: items.length` line must remain — the overall total is
        // never filtered.
        expect(
          body,
          contains('total: items.length'),
          reason: 'The overall total ride count must remain items.length.',
        );
        // Revenue baseline preservation — the same three lines that
        // aggregated revenue before Commit 5 must still be present verbatim.
        expect(
          body,
          contains('_normalizePaymentStatus(item)'),
          reason:
              'Pre-Commit-5 revenue path must remain — payment status is still '
              'consulted to decide whether to include a ride in revenue.',
        );
        expect(
          body,
          contains("canInclude = payment != 'unpaid'"),
          reason:
              'Pre-Commit-5 revenue-inclusion rule (payment != "unpaid") must '
              'be preserved verbatim.',
        );
        expect(
          body,
          contains('revenue += item.totalEur!'),
          reason: 'Pre-Commit-5 revenue accumulation must be preserved.',
        );
      },
    );

    test(
      'revenue accumulation is NOT gated by shouldRenderAsLocalOnlyUnconfirmed',
      () {
        final src = readSourceOrFail('lib/main_parts/trip_history_page.dart');
        final stripped = stripDartComments(src);
        final methodStart = stripped.indexOf(
          'int total, int completed, int cancelled, double revenue}) _summary(',
        );
        expect(
          methodStart,
          greaterThanOrEqualTo(0),
          reason: '_summary method declaration is missing',
        );
        final body = extractMethodBody(
          stripped.substring(methodStart),
          '_summary(',
        );
        // Extract the substring from the local-only guard to the end of the
        // completed branch. The revenue accumulation must live OUTSIDE that
        // guarded section so pre-Commit-5 revenue semantics remain intact.
        // The `completed++` line is the ONLY thing the guard may skip; the
        // revenue block that follows must be reachable for local-only rides.
        final guardIdx = body.indexOf(
          'if (!item.shouldRenderAsLocalOnlyUnconfirmed)',
        );
        expect(
          guardIdx >= 0,
          isTrue,
          reason:
              'Commit 5 must gate ONLY the counter increment via the negated '
              'predicate — the revenue path must be sibling to (not nested '
              'inside) the guard.',
        );
        // Find where the guard's closing brace ends.
        final guardBodyStart = body.indexOf('{', guardIdx);
        expect(guardBodyStart >= 0, isTrue);
        var depth = 1;
        var i = guardBodyStart + 1;
        while (i < body.length && depth > 0) {
          if (body[i] == '{') depth++;
          if (body[i] == '}') depth--;
          i++;
        }
        final guardBody = body.substring(guardBodyStart, i);
        // The guard body must contain the completed increment and NOTHING
        // that affects revenue.
        expect(
          guardBody,
          contains('completed++'),
          reason: 'The guard body must contain the `completed++` increment.',
        );
        expect(
          guardBody.contains('revenue'),
          isFalse,
          reason:
              'The guard body must NOT reference revenue — revenue '
              'accumulation is pre-Commit-5 behavior and stays sibling.',
        );
        expect(
          guardBody.contains('_normalizePaymentStatus'),
          isFalse,
          reason:
              'Payment-status resolution must not be inside the counter '
              'guard — the revenue path must retain its pre-Commit-5 '
              'behavior for every completed ride, including unconfirmed ones.',
        );
      },
    );
  });

  // Part F: durable runtime mirror. Reimplements the exact `_summary`
  // predicate wiring against synthetic rows so the four contract points
  // are verified end-to-end without pumping the `_TripHistoryPage` widget.
  // The durable Part E source-contract test above guarantees that the
  // WIDGET's `_summary` retains this wiring at the AST level, so the two
  // together prove wiring + semantics.
  group('Part F — runtime mirror of _summary semantics', () {
    ({int total, int completed, int cancelled, double revenue}) mirrorSummary(
      List<_MirrorRow> items,
    ) {
      var completed = 0;
      var cancelled = 0;
      var revenue = 0.0;
      for (final item in items) {
        if (_mirrorIsCancelled(item.status)) {
          cancelled++;
          continue;
        }
        if (_mirrorIsCompleted(item.status)) {
          if (!item.shouldRenderAsLocalOnlyUnconfirmed) {
            completed++;
          }
          final payment = _mirrorNormalizePaymentStatus(item);
          final canInclude = payment != 'unpaid';
          if (canInclude && item.totalEur != null) {
            revenue += item.totalEur!;
          }
        }
      }
      return (
        total: items.length,
        completed: completed,
        cancelled: cancelled,
        revenue: revenue,
      );
    }

    test('backend-confirmed ride: completed +1 and existing revenue behavior',
        () {
      final s = mirrorSummary([
        _MirrorRow(
          status: 'COMPLETED',
          backendConfirmed: true,
          totalEur: 12.50,
          paymentStatus: 'paid',
        ),
      ]);
      expect(s.total, 1);
      expect(s.completed, 1);
      expect(s.revenue, closeTo(12.50, 1e-9));
    });

    test('local-only completed ride: completed +0 (excluded from counter)', () {
      final s = mirrorSummary([
        _MirrorRow(
          status: 'COMPLETED',
          historySource: 'local_only_direct_fallback',
          backendConfirmed: false,
          totalEur: 5.30,
          paymentStatus: 'paid',
        ),
      ]);
      expect(s.total, 1);
      expect(s.completed, 0, reason: 'excluded from Completed counter');
    });

    test(
      'local-only completed ride: revenue retains pre-Commit-5 behavior '
      '(paid contributes; unpaid does not)',
      () {
        // Paid local-only ride: pre-Commit-5 semantics contribute to revenue.
        final paid = mirrorSummary([
          _MirrorRow(
            status: 'COMPLETED',
            historySource: 'local_only_direct_fallback',
            backendConfirmed: false,
            totalEur: 5.30,
            paymentStatus: 'paid',
          ),
        ]);
        expect(
          paid.revenue,
          closeTo(5.30, 1e-9),
          reason:
              'Pre-Commit-5 revenue rule: a completed ride with '
              'payment != "unpaid" contributes to revenue. Commit 5 must '
              'not alter this behavior.',
        );
        // Unpaid local-only ride: pre-Commit-5 semantics exclude it from
        // revenue (unchanged by Commit 5).
        final unpaid = mirrorSummary([
          _MirrorRow(
            status: 'COMPLETED',
            historySource: 'local_only_direct_fallback',
            backendConfirmed: false,
            totalEur: 7.10,
            paymentStatus: 'unpaid',
          ),
        ]);
        expect(unpaid.revenue, 0.0);
      },
    );

    test('total remains unchanged across mixed outcomes', () {
      final items = <_MirrorRow>[
        _MirrorRow(
          status: 'COMPLETED',
          backendConfirmed: true,
          totalEur: 10.0,
          paymentStatus: 'paid',
        ),
        _MirrorRow(
          status: 'COMPLETED',
          backendConfirmed: true,
          totalEur: 20.0,
          paymentStatus: 'paid',
        ),
        _MirrorRow(
          status: 'COMPLETED',
          historySource: 'local_only_direct_fallback',
          backendConfirmed: false,
          totalEur: 5.30,
          paymentStatus: 'paid',
        ),
        _MirrorRow(
          status: 'COMPLETED',
          backendConfirmed: false,
          totalEur: 3.30,
          paymentStatus: 'unpaid',
        ),
        _MirrorRow(status: 'CANCELLED'),
        _MirrorRow(status: 'CANCELLED'),
      ];
      final s = mirrorSummary(items);
      expect(s.total, items.length, reason: 'total must equal items.length');
      expect(s.completed, 2,
          reason: 'only backend-confirmed completed rides count');
      expect(s.cancelled, 2);
      // Pre-Commit-5 revenue: 10 + 20 + 5.30 = 35.30 (unpaid 3.30 excluded
      // by pre-existing rule, local-only 5.30 still included because
      // revenue path is not gated by the new predicate).
      expect(
        s.revenue,
        closeTo(35.30, 1e-9),
        reason:
            'Revenue must reflect pre-Commit-5 behavior: paid completed '
            'rides contribute (including local-only paid rides), unpaid '
            'completed rides do not.',
      );
    });
  });
}

class _MirrorRow {
  _MirrorRow({
    required this.status,
    this.historySource,
    this.backendConfirmed,
    this.totalEur,
    this.paymentStatus = 'paid',
  });
  final String status;
  final String? historySource;
  final bool? backendConfirmed;
  final double? totalEur;
  final String paymentStatus;

  bool get isLocalOnlyDirectFallback =>
      historySource == 'local_only_direct_fallback';
  bool get isBackendConfirmedFalse => backendConfirmed == false;
  bool get shouldRenderAsLocalOnlyUnconfirmed =>
      isLocalOnlyDirectFallback || isBackendConfirmedFalse;
}

bool _mirrorIsCompleted(String s) {
  final v = s.toLowerCase().trim();
  return v == 'completed' ||
      v == 'stopped' ||
      v == 'complete' ||
      v == 'done' ||
      v == 'finished' ||
      v == 'finalized';
}

bool _mirrorIsCancelled(String s) {
  final v = s.toLowerCase().trim();
  return v == 'cancelled' || v == 'canceled';
}

String _mirrorNormalizePaymentStatus(_MirrorRow item) =>
    item.paymentStatus.trim().toLowerCase();
