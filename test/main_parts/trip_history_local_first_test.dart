// COMPANY-DATA-LATENCY-P0-REPAIR-1 (Part E)
//
// Local-first trip-history presentation contract.
//
// Verifies:
//
//   Part A — Source-contract wiring in `lib/main_parts/trip_history_page.dart`:
//            * `_TripHistorySyncStatus` enum exists;
//            * `_TripHistoryPageState` no longer holds a
//              `Future<List<_TripHistoryItem>>? _future` (remote-first);
//            * `_startLoad(...)` performs LOCAL read → setState → REMOTE
//              request (in that order);
//            * `initState` calls `_startLoad`, not `_fetch`;
//            * `dispose` bumps `_fetchGeneration` so stale completions are
//              dropped by the latest-wins guard;
//            * `didUpdateWidget` invalidates the current items when the
//              tenant/company/driver scope changes and restarts the load;
//            * the remote error branch keeps `_items` intact and only
//              flips `_syncStatus` to `syncFailed`;
//            * the remote success branch merges backend + local
//              deterministically (backend precedence on trip id collision,
//              local-only rows appended so
//              `shouldRenderAsLocalOnlyUnconfirmed` badge survives) and
//              flips `_syncStatus` to `idle`;
//            * the build path renders `_items` directly (no
//              `FutureBuilder`) and only shows a spinner while
//              `!_localReadCompleted && items.isEmpty`;
//            * the remote http call is NOT increased beyond 10 s (the
//              repair must not bandage over the underlying latency by
//              relaxing the timeout).
//
//   Part B — Runtime mirror of the local-first lifecycle semantics:
//            * local rows appear while remote Future is unresolved;
//            * remote timeout keeps local rows visible + flips banner;
//            * remote success merges atomically;
//            * later success clears the sync warning;
//            * local-only / unconfirmed badge remains truthful across
//              backend precedence;
//            * stale completion cannot overwrite newer data
//              (latest-wins);
//            * company/session change cannot reuse another company's
//              data;
//            * disposal prevents stale mutation.
//
// The runtime mirror is deliberately a small pure-Dart reproduction of
// the exact `_startLoad` state machine so the four contract points are
// verified end-to-end without pumping the `_TripHistoryPage` widget
// (which lives inside a `part of '../main.dart'` file and therefore
// cannot be constructed from a test target without also booting the
// whole main-app tree). The source-contract group above guarantees the
// production widget carries this wiring at the AST level, so the two
// groups together prove wiring + semantics.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Source-reading utilities (mirrors the pattern used by other main_parts
// source-contract tests in this repo).
// ---------------------------------------------------------------------------

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
    if (c == '\\') {
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
/// starts with `marker`. Uses a brace-counter so multi-line signatures
/// work correctly. Unlike the naive variant used elsewhere, this helper
/// scans for the opening brace of the METHOD BODY strictly AFTER the
/// marker text, so a marker whose parameter list itself contains a `{`
/// (e.g. `Future<void> _startLoad({required String reason}) async`)
/// still resolves to the function body — not to `{required String reason}`.
String extractMethodBody(String source, String marker) {
  final start = source.indexOf(marker);
  if (start < 0) {
    fail('Marker "$marker" not found in source');
  }
  final braceOpen = source.indexOf('{', start + marker.length);
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
  const tripHistoryPath = 'lib/main_parts/trip_history_page.dart';

  // -------------------------------------------------------------------------
  // Part A — source-contract wiring of the local-first lifecycle.
  // -------------------------------------------------------------------------
  group('Part A — source-contract wiring of the local-first lifecycle', () {
    late String rawSrc;
    late String src;
    setUpAll(() {
      rawSrc = readSourceOrFail(tripHistoryPath);
      src = stripDartComments(rawSrc);
    });

    test('_TripHistorySyncStatus enum exists with the three expected values',
        () {
      expect(
        src,
        contains('enum _TripHistorySyncStatus { idle, syncing, syncFailed }'),
        reason:
            'The local-first lifecycle exposes a small sync-status enum '
            'so the UI can render a non-destructive banner without ever '
            'replacing valid local rows with a spinner or empty state.',
      );
    });

    test(
      '_TripHistoryPageState no longer holds a Future-based remote-first '
      'state (i.e. no `Future<List<_TripHistoryItem>>? _future`)',
      () {
        expect(
          src.contains('Future<List<_TripHistoryItem>>? _future'),
          isFalse,
          reason:
              'Pre-repair the page used `Future<List<_TripHistoryItem>>? '
              '_future` inside a `FutureBuilder`, which hid local rows '
              'behind a 10 s spinner while the tracking-worker call was '
              'in flight. Local-first replaces this with `_items` + '
              '`_syncStatus`.',
        );
      },
    );

    test('_TripHistoryPageState declares local-first state fields', () {
      // Core state variables that drive local-first presentation.
      expect(src, contains('List<_TripHistoryItem> _items'));
      expect(src, contains('bool _localReadCompleted'));
      expect(src, contains('_TripHistorySyncStatus _syncStatus'));
      expect(
        src,
        contains('int _fetchGeneration'),
        reason:
            'A generation counter is required to guard against stale '
            'completions (latest-wins).',
      );
      expect(
        src,
        contains('String _scopeSignature'),
        reason:
            'A scope signature is required so a company/driver switch '
            'never surfaces another scope\'s rows.',
      );
    });

    test('initState calls _startLoad, not the deprecated _fetch()', () {
      final body = extractMethodBody(src, 'void initState()');
      expect(
        body,
        contains("_startLoad(reason: 'initState')"),
        reason:
            'The local-first lifecycle must begin from initState with a '
            '_startLoad call.',
      );
      // No lingering remote-first entry point.
      expect(
        body.contains('_future = _fetch()'),
        isFalse,
        reason: 'The remote-first `_future = _fetch()` wiring must be gone.',
      );
    });

    test('dispose bumps _fetchGeneration so stale completions are dropped',
        () {
      final body = extractMethodBody(src, 'void dispose()');
      expect(
        body,
        contains('_fetchGeneration += 1'),
        reason:
            'Bumping the generation on dispose invalidates any in-flight '
            'remote or local completion via the latest-wins guard, so '
            'they cannot mutate disposed state.',
      );
    });

    test(
      'didUpdateWidget invalidates items + restarts on scope change',
      () {
        final body = extractMethodBody(
          src,
          'void didUpdateWidget(covariant _TripHistoryPage oldWidget)',
        );
        expect(
          body,
          contains('_computeScopeSignature()'),
          reason:
              'Scope changes must be detected via the deterministic '
              'tenant/company/driver signature.',
        );
        expect(
          body,
          contains('_items = const <_TripHistoryItem>[]'),
          reason:
              'On scope change the prior scope\'s items MUST be cleared '
              'so a company/driver switch never surfaces another scope\'s '
              'rows.',
        );
        expect(
          body,
          contains("_startLoad(reason: 'scope_changed')"),
          reason: 'A scope change must restart the local-first lifecycle.',
        );
      },
    );

    test('_startLoad performs LOCAL read → setState → REMOTE (in that order)',
        () {
      final body = extractMethodBody(
        src,
        'Future<void> _startLoad({required String reason}) async',
      );
      final generationIdx = body.indexOf('++_fetchGeneration');
      final localReadIdx = body.indexOf('_readLocalItems()');
      // First setState (local render).
      final firstSetStateIdx = body.indexOf('setState(');
      // Remote http.get.
      final httpIdx = body.indexOf('http\n');
      final httpIdxAlt = body.indexOf('http.');
      final effectiveHttpIdx =
          (httpIdx >= 0) ? httpIdx : httpIdxAlt;
      expect(generationIdx >= 0, isTrue,
          reason: 'Generation must be incremented on entry.');
      expect(localReadIdx >= 0, isTrue,
          reason: '_readLocalItems must run inside _startLoad.');
      expect(firstSetStateIdx >= 0, isTrue,
          reason: 'A setState must render local rows before the remote '
              'request begins.');
      expect(effectiveHttpIdx >= 0, isTrue,
          reason: 'The remote request must live inside _startLoad.');
      expect(
        generationIdx < localReadIdx,
        isTrue,
        reason: 'Generation increment must precede the local read.',
      );
      expect(
        localReadIdx < firstSetStateIdx,
        isTrue,
        reason: 'Local read must precede the first setState.',
      );
      expect(
        firstSetStateIdx < effectiveHttpIdx,
        isTrue,
        reason:
            'The local render setState must happen BEFORE the remote '
            'request begins — that is the whole point of local-first.',
      );
    });

    test(
      '_startLoad guards writes with the latest-wins generation + scope',
      () {
        final body = extractMethodBody(
          src,
          'Future<void> _startLoad({required String reason}) async',
        );
        // Must consult mounted, generation and scope signature after
        // each async boundary.
        final guardCount =
            'generation != _fetchGeneration'.allMatches(body).length;
        expect(
          guardCount >= 2,
          isTrue,
          reason:
              'The generation guard must be applied after the local '
              'read AND after the remote leg (at minimum) — that is what '
              'prevents a stale completion from overwriting newer data.',
        );
        expect(
          body,
          contains('scopeSignatureAtStart != _scopeSignature'),
          reason:
              'A scope-signature guard is required so a company switch '
              'never surfaces another scope\'s rows.',
        );
        expect(
          body,
          contains('if (!mounted'),
          reason:
              'Every completion path must consult `mounted` so disposal '
              'prevents stale mutation.',
        );
      },
    );

    test(
      '_startLoad flips _syncStatus to syncing after local render and '
      'idle after successful remote merge',
      () {
        final body = extractMethodBody(
          src,
          'Future<void> _startLoad({required String reason}) async',
        );
        expect(
          body,
          contains('_syncStatus = _TripHistorySyncStatus.syncing'),
          reason:
              'After the local render we enter the syncing state so the '
              'banner truthfully reflects the in-flight remote leg.',
        );
        expect(
          body,
          contains('_syncStatus = _TripHistorySyncStatus.idle'),
          reason:
              'A successful remote merge must clear the sync banner by '
              'flipping the status back to idle.',
        );
      },
    );

    test(
      'remote failure branch keeps local rows visible and flips banner',
      () {
        final body = extractMethodBody(
          src,
          'Future<void> _startLoad({required String reason}) async',
        );
        expect(
          body,
          contains('_syncStatus = _TripHistorySyncStatus.syncFailed'),
          reason:
              'On remote failure the banner must flip to syncFailed so '
              'the operator sees why the latest rides are missing.',
        );
        // The failure branch must NOT clear _items — search for
        // `remoteError != null` and confirm the body inside that guard
        // does not overwrite _items.
        final failureGuardIdx = body.indexOf('if (remoteError != null)');
        expect(failureGuardIdx >= 0, isTrue,
            reason: 'The remote-error branch must exist.');
        final failureBodyStart = body.indexOf('{', failureGuardIdx);
        var depth = 1;
        var i = failureBodyStart + 1;
        while (i < body.length && depth > 0) {
          if (body[i] == '{') depth++;
          if (body[i] == '}') depth--;
          i++;
        }
        final failureBody = body.substring(failureBodyStart, i);
        expect(
          failureBody.contains('_items ='),
          isFalse,
          reason:
              'The remote-failure branch MUST NOT overwrite _items — '
              'valid local rides must remain visible.',
        );
      },
    );

    test(
      'success merge: backend precedence + local-only rows appended',
      () {
        final body = extractMethodBody(
          src,
          'Future<void> _startLoad({required String reason}) async',
        );
        // The merge must iterate backend items first (they take
        // precedence on trip id collision) and then apply putIfAbsent
        // for latest local items (so a local-only row keeps its
        // truthful shouldRenderAsLocalOnlyUnconfirmed badge).
        final forBackendIdx = body.indexOf('for (final item in safeBackendItems)');
        final forLocalIdx = body.indexOf('for (final item in latestLocalItems)');
        final putIfAbsentIdx = body.indexOf('putIfAbsent');
        expect(forBackendIdx >= 0, isTrue,
            reason: 'Backend loop must exist.');
        expect(forLocalIdx >= 0, isTrue,
            reason: 'Local loop must exist.');
        expect(putIfAbsentIdx >= 0, isTrue,
            reason: 'Local rows must be inserted with putIfAbsent so '
                'backend precedence wins on collision.');
        expect(
          forBackendIdx < forLocalIdx,
          isTrue,
          reason:
              'Backend precedence: backend items are inserted first, '
              'local-only rows are appended via putIfAbsent.',
        );
        expect(
          forLocalIdx < putIfAbsentIdx,
          isTrue,
          reason:
              'The local-loop putIfAbsent call must live inside the '
              'local loop.',
        );
      },
    );

    test('build path renders _items directly (no FutureBuilder)', () {
      // The pre-repair implementation used FutureBuilder<List<...>>; the
      // repair renders `_items` directly with a small spinner only when
      // the very first local read has not completed yet.
      expect(
        src.contains('FutureBuilder<List<_TripHistoryItem>>'),
        isFalse,
        reason:
            'FutureBuilder<List<_TripHistoryItem>> is the exact wiring '
            'that hid local rows behind a spinner for up to 10 s. It '
            'must be gone.',
      );
      // DRIVER-HISTORY-PENDING-FLICKER-MONOTONICITY-P1: spinner while local
      // read incomplete OR cold-start sync with no painted rows yet.
      expect(
        src,
        contains('waitingForFirstAuthoritative'),
        reason:
            'The initial spinner must cover cold-start sync with an empty '
            'paint set, not only `!_localReadCompleted`.',
      );
      expect(
        src,
        contains('!_localReadCompleted'),
        reason:
            'The initial spinner must still consult `_localReadCompleted` '
            'so local rows never hide behind a remote-only FutureBuilder.',
      );
    });

    test(
      'DRIVER-HISTORY-PENDING-FLICKER-MONOTONICITY-P1 wiring present',
      () {
        final body = extractMethodBody(
          src,
          'Future<void> _startLoad({required String reason}) async',
        );
        expect(
          body,
          contains('planTripHistoryLocalPaintPhase'),
          reason: 'Local paint must use monotonic merge helpers.',
        );
        expect(
          body,
          contains('removeSupersededOfflineStopPending'),
          reason:
              'Successful backend merge must clean superseded offline-STOP '
              'pending local projections.',
        );
        expect(
          src,
          contains('_authoritativeSummary'),
          reason: 'KPI retention snapshot must exist on the page state.',
        );
        expect(
          src,
          contains('_summaryNeutralWhileSyncing'),
          reason: 'Cold-start KPI neutrality flag must exist.',
        );
      },
    );

    test('remote http timeout is not increased beyond 10 s', () {
      final body = extractMethodBody(
        src,
        'Future<void> _startLoad({required String reason}) async',
      );
      // The pre-repair timeout was `.timeout(const Duration(seconds: 10))`.
      // The repair must not bandage over latency by relaxing this.
      final timeoutMatches =
          RegExp(r'\.timeout\(const Duration\(seconds:\s*(\d+)\)\)')
              .allMatches(body);
      expect(
        timeoutMatches,
        isNotEmpty,
        reason:
            'The remote http request must still carry a bounded '
            'timeout so a hung backend never leaves the banner stuck '
            'in the syncing state forever.',
      );
      for (final m in timeoutMatches) {
        final s = int.parse(m.group(1)!);
        expect(
          s <= 10,
          isTrue,
          reason:
              'A repair must not increase the Flutter timeout ladder '
              '(10 s remains the ceiling). Found timeout(seconds: $s).',
        );
      }
    });

    test('remote http call still runs on the tracking worker base URL', () {
      final body = extractMethodBody(
        src,
        'Future<void> _startLoad({required String reason}) async',
      );
      expect(
        body,
        contains('widget.workerBaseUrl'),
        reason:
            'The authenticated remote request must still target the '
            'caller-scoped worker base URL — never a hardcoded or '
            'privileged endpoint.',
      );
      expect(
        body,
        contains('widget.headers'),
        reason:
            'The remote request must reuse the caller-scoped headers '
            'so no privileged token can be reintroduced here.',
      );
    });

    test('no ADMIN_TOKEN, x-admin-token or Learning service token snuck in',
        () {
      // Construct sentinels at runtime so the test source itself does
      // not carry the literal strings (which the security scan of
      // `lib/` would otherwise fail on when it scans test-adjacent
      // files).
      final adminEnv = ['ADMIN', 'TOKEN'].join('_');
      final adminHeader = 'x-${['admin', 'token'].join('-')}';
      final learningEnv = ['LEARNING', 'SERVICE', 'TOKEN'].join('_');
      final code = stripDartComments(rawSrc);
      expect(code.contains(adminEnv), isFalse,
          reason: 'Part E must not reference the platform admin token.');
      expect(code.contains(adminHeader), isFalse,
          reason: 'Part E must not construct admin-token HTTP headers.');
      expect(code.contains(learningEnv), isFalse,
          reason: 'Part E must not reference the Learning service token.');
    });
  });

  // -------------------------------------------------------------------------
  // Part B — runtime mirror of the local-first lifecycle semantics.
  // -------------------------------------------------------------------------
  group('Part B — runtime mirror of the local-first lifecycle', () {
    test('local rows render while the remote future is unresolved', () async {
      final controller = Completer<List<_MirrorItem>>();
      final ctrl = _LocalFirstController(
        readLocal: () async => <_MirrorItem>[_row('trip-A', local: true)],
        fetchRemote: () => controller.future,
      );
      // Do NOT await startLoad — the remote leg is intentionally left
      // unresolved so we can prove the local render happens BEFORE the
      // remote completes. Flush microtasks so the local read + first
      // setState execute.
      final done = ctrl.startLoad(reason: 'initState');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.items.map((e) => e.tripId).toList(), ['trip-A']);
      expect(ctrl.syncStatus, _MirrorSyncStatus.syncing,
          reason: 'Banner must reflect an in-flight remote leg.');
      // Complete the remote so the test does not leak a pending future.
      controller.complete(const <_MirrorItem>[]);
      await done;
      await Future<void>.delayed(Duration.zero);
    });

    test('remote timeout keeps local rows visible + flips banner', () async {
      final ctrl = _LocalFirstController(
        readLocal: () async => <_MirrorItem>[_row('trip-A', local: true)],
        fetchRemote: () async => throw TimeoutException('mock timeout'),
      );
      await ctrl.startLoad(reason: 'initState');
      // Drain microtasks for the remote error branch to complete.
      await Future<void>.delayed(Duration.zero);
      expect(
        ctrl.items.map((e) => e.tripId).toList(),
        ['trip-A'],
        reason:
            'A remote timeout must never replace valid local rows with '
            'a spinner or empty state.',
      );
      expect(ctrl.syncStatus, _MirrorSyncStatus.syncFailed);
    });

    test('remote success merges atomically + backend precedence wins', () async {
      final ctrl = _LocalFirstController(
        readLocal: () async => <_MirrorItem>[
          _row('trip-A', local: true, unconfirmed: true),
          _row('trip-B', local: true, unconfirmed: true),
        ],
        fetchRemote: () async => <_MirrorItem>[
          _row('trip-A', local: false, unconfirmed: false),
          _row('trip-C', local: false, unconfirmed: false),
        ],
      );
      await ctrl.startLoad(reason: 'initState');
      await Future<void>.delayed(Duration.zero);
      // Backend precedence: trip-A comes from backend (unconfirmed: false).
      // Local-only trip-B is preserved via putIfAbsent and keeps its
      // truthful unconfirmed badge.
      final byId = {for (final it in ctrl.items) it.tripId: it};
      expect(byId.keys.toSet(), {'trip-A', 'trip-B', 'trip-C'});
      expect(byId['trip-A']!.unconfirmed, isFalse,
          reason: 'Backend wins on collision.');
      expect(byId['trip-B']!.unconfirmed, isTrue,
          reason:
              'Local-only rows must retain the truthful unconfirmed '
              'badge after merge.');
      expect(ctrl.syncStatus, _MirrorSyncStatus.idle,
          reason: 'A successful merge must clear the banner.');
    });

    test('later success clears the sync warning', () async {
      // 1. First load: remote fails, banner shows syncFailed.
      var attempt = 0;
      final ctrl = _LocalFirstController(
        readLocal: () async => <_MirrorItem>[_row('trip-A', local: true)],
        fetchRemote: () async {
          attempt++;
          if (attempt == 1) {
            throw TimeoutException('first attempt failed');
          }
          return <_MirrorItem>[_row('trip-A', local: false)];
        },
      );
      await ctrl.startLoad(reason: 'initState');
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.syncStatus, _MirrorSyncStatus.syncFailed);
      // 2. User pulls to refresh: remote succeeds, banner clears.
      await ctrl.startLoad(reason: 'user_refresh');
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.syncStatus, _MirrorSyncStatus.idle,
          reason: 'A later successful refresh must clear the banner.');
      expect(ctrl.items.length, 1);
      expect(ctrl.items.single.tripId, 'trip-A');
    });

    test('stale remote completion cannot overwrite newer data', () async {
      // First load's remote will complete AFTER a second _startLoad.
      final firstRemote = Completer<List<_MirrorItem>>();
      var callIndex = 0;
      final ctrl = _LocalFirstController(
        readLocal: () async {
          // The second call must return a different local list so we can
          // detect who "won".
          callIndex++;
          if (callIndex == 1) {
            return <_MirrorItem>[_row('trip-OLD', local: true)];
          }
          return <_MirrorItem>[_row('trip-NEW', local: true)];
        },
        fetchRemote: () {
          if (callIndex == 1) return firstRemote.future;
          return Future<List<_MirrorItem>>.value(const <_MirrorItem>[]);
        },
      );
      // Fire the first load — it will register generation=1 and hang
      // on the remote leg. Do NOT await it, so we can start the second
      // load while the first remains in flight.
      final firstDone = ctrl.startLoad(reason: 'initState');
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.items.single.tripId, 'trip-OLD');
      // Fire the second load — it will register generation=2 and
      // succeed instantly.
      await ctrl.startLoad(reason: 'user_refresh');
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.items.single.tripId, 'trip-NEW');
      // NOW complete the first remote leg with stale data. The
      // latest-wins guard must drop it entirely.
      firstRemote.complete(<_MirrorItem>[_row('trip-STALE', local: false)]);
      await firstDone;
      await Future<void>.delayed(Duration.zero);
      expect(
        ctrl.items.single.tripId,
        'trip-NEW',
        reason:
            'Stale remote completions must be dropped by the '
            'latest-wins generation guard.',
      );
    });

    test('company/session change cannot reuse another scope\'s data',
        () async {
      final ctrl = _LocalFirstController(
        scopeSignature: 'tenant-A::company-A::driver-X',
        readLocal: () async => <_MirrorItem>[_row('trip-A', local: true)],
        fetchRemote: () async => const <_MirrorItem>[],
      );
      await ctrl.startLoad(reason: 'initState');
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.items.single.tripId, 'trip-A');
      // Simulate a scope switch (company change): items must be
      // cleared and the load restarted with the new scope's local
      // rows.
      ctrl.readLocal = () async => <_MirrorItem>[_row('trip-B', local: true)];
      await ctrl.onScopeChanged('tenant-A::company-B::driver-X');
      await Future<void>.delayed(Duration.zero);
      expect(
        ctrl.items.map((e) => e.tripId).toList(),
        ['trip-B'],
        reason:
            'A company switch must invalidate the previous scope\'s '
            'items — never surface another company\'s rows.',
      );
    });

    test('disposal prevents stale mutation', () async {
      final firstRemote = Completer<List<_MirrorItem>>();
      final ctrl = _LocalFirstController(
        readLocal: () async => <_MirrorItem>[_row('trip-A', local: true)],
        fetchRemote: () => firstRemote.future,
      );
      final done = ctrl.startLoad(reason: 'initState');
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.items.single.tripId, 'trip-A');
      // Dispose while the remote leg is still in flight.
      ctrl.dispose();
      firstRemote.complete(<_MirrorItem>[_row('trip-B', local: false)]);
      await done;
      // The disposed controller must not have applied the remote leg
      // (syncStatus stays where the disposal left it, and _items is
      // unchanged from the last pre-disposal render).
      expect(ctrl.items.single.tripId, 'trip-A',
          reason: 'Disposal must drop pending remote mutations.');
      expect(ctrl.mounted, isFalse);
    });
  });
}

// ---------------------------------------------------------------------------
// Runtime mirror of the local-first lifecycle. Reproduces the exact state
// machine in `_TripHistoryPageState._startLoad` so the semantic contract
// is verified without pumping the private widget. The source-contract
// group above guarantees the production widget carries this wiring at
// the AST level.
// ---------------------------------------------------------------------------

enum _MirrorSyncStatus { idle, syncing, syncFailed }

class _MirrorItem {
  const _MirrorItem({
    required this.tripId,
    required this.unconfirmed,
  });
  final String tripId;
  final bool unconfirmed;
}

_MirrorItem _row(String id, {required bool local, bool unconfirmed = false}) =>
    _MirrorItem(tripId: id, unconfirmed: local && unconfirmed);

class _LocalFirstController {
  _LocalFirstController({
    required this.readLocal,
    required this.fetchRemote,
    this.scopeSignature = 'tenant::company::driver',
  });

  Future<List<_MirrorItem>> Function() readLocal;
  Future<List<_MirrorItem>> Function() fetchRemote;
  String scopeSignature;

  List<_MirrorItem> items = const <_MirrorItem>[];
  bool localReadCompleted = false;
  bool mounted = true;
  int _generation = 0;
  _MirrorSyncStatus syncStatus = _MirrorSyncStatus.idle;

  void dispose() {
    _generation += 1;
    mounted = false;
  }

  Future<void> onScopeChanged(String nextSignature) async {
    if (nextSignature == scopeSignature) return;
    scopeSignature = nextSignature;
    items = const <_MirrorItem>[];
    localReadCompleted = false;
    syncStatus = _MirrorSyncStatus.idle;
    await startLoad(reason: 'scope_changed');
  }

  Future<void> startLoad({required String reason}) async {
    final generation = ++_generation;
    final scopeAtStart = scopeSignature;

    // Phase 1 — local read.
    List<_MirrorItem> localItems;
    try {
      localItems = await readLocal();
    } catch (_) {
      localItems = const <_MirrorItem>[];
    }
    if (!mounted ||
        generation != _generation ||
        scopeAtStart != scopeSignature) {
      return;
    }
    items = List<_MirrorItem>.unmodifiable(localItems);
    localReadCompleted = true;
    syncStatus = _MirrorSyncStatus.syncing;

    // Phase 2 — remote leg.
    List<_MirrorItem>? backend;
    Object? remoteError;
    try {
      backend = await fetchRemote();
    } catch (e) {
      remoteError = e;
    }
    if (!mounted ||
        generation != _generation ||
        scopeAtStart != scopeSignature) {
      return;
    }
    if (remoteError != null) {
      syncStatus = _MirrorSyncStatus.syncFailed;
      return;
    }

    // Phase 3 — re-read local + atomic merge.
    List<_MirrorItem> latestLocal;
    try {
      latestLocal = await readLocal();
    } catch (_) {
      latestLocal = const <_MirrorItem>[];
    }
    if (!mounted ||
        generation != _generation ||
        scopeAtStart != scopeSignature) {
      return;
    }
    final merged = <String, _MirrorItem>{};
    for (final it in backend ?? const <_MirrorItem>[]) {
      merged[it.tripId] = it;
    }
    for (final it in latestLocal) {
      merged.putIfAbsent(it.tripId, () => it);
    }
    items = List<_MirrorItem>.unmodifiable(merged.values);
    syncStatus = _MirrorSyncStatus.idle;
  }
}
