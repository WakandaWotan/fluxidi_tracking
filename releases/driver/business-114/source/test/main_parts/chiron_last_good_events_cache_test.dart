import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/chiron_context_hydration_retry.dart';
import 'package:fluxidi_tracking/main_parts/chiron_last_good_events_cache.dart';

class _FlagListenable extends ChangeNotifier {
  void bump() => notifyListeners();
}

/// Minimal stand-in for RemoteComplianceEventsResponse presentation data.
class _FakeEvents {
  const _FakeEvents({
    required this.tenantId,
    required this.companyId,
    required this.count,
    this.label = '',
  });

  final String tenantId;
  final String companyId;
  final int count;
  final String label;
}

void main() {
  group('initialChironEventsPresentation', () {
    test('first mount with no cache shows loading, not unavailable', () {
      final p = initialChironEventsPresentation<_FakeEvents>(
        cachedForActiveScope: null,
      );
      expect(p.showLoading, isTrue);
      expect(p.display, isNull);
      expect(p.showStaleWarning, isFalse);
      expect(p.hardErrorMessage, isNull);
    });

    test('remount restores last-good without stale warning', () {
      const cached = _FakeEvents(
        tenantId: 't1',
        companyId: 'c1',
        count: 100,
        label: 'first',
      );
      final p = initialChironEventsPresentation<_FakeEvents>(
        cachedForActiveScope: cached,
      );
      expect(p.showLoading, isFalse);
      expect(p.display?.count, 100);
      expect(p.showStaleWarning, isFalse);
      expect(p.hardErrorMessage, isNull);
    });
  });

  group('applyChironEventsLoadResult', () {
    test('timeout after success preserves events and shows stale warning', () {
      const cached = _FakeEvents(
        tenantId: 't1',
        companyId: 'c1',
        count: 100,
        label: 'good',
      );
      final p = applyChironEventsLoadResult<_FakeEvents>(
        resultOk: false,
        successPayload: null,
        resultErrorMessage: 'Cannot load backend compliance events.',
        cachedForActiveScope: cached,
        defaultHardError: 'unavailable',
      );
      expect(p.showLoading, isFalse);
      expect(p.showStaleWarning, isTrue);
      expect(p.display?.count, 100);
      expect(p.display?.label, 'good');
      expect(p.hardErrorMessage, isNull);
    });

    test('later success replaces cached data and clears warning', () {
      const previous = _FakeEvents(
        tenantId: 't1',
        companyId: 'c1',
        count: 100,
        label: 'old',
      );
      const newer = _FakeEvents(
        tenantId: 't1',
        companyId: 'c1',
        count: 100,
        label: 'new',
      );
      final p = applyChironEventsLoadResult<_FakeEvents>(
        resultOk: true,
        successPayload: newer,
        resultErrorMessage: '',
        cachedForActiveScope: previous,
        defaultHardError: 'unavailable',
      );
      expect(p.showStaleWarning, isFalse);
      expect(p.display?.label, 'new');
      expect(p.hardErrorMessage, isNull);
    });

    test('first-load failure without cache shows hard error', () {
      final p = applyChironEventsLoadResult<_FakeEvents>(
        resultOk: false,
        successPayload: null,
        resultErrorMessage: '',
        cachedForActiveScope: null,
        defaultHardError: 'unavailable',
      );
      expect(p.showLoading, isFalse);
      expect(p.showStaleWarning, isFalse);
      expect(p.display, isNull);
      expect(p.hardErrorMessage, 'unavailable');
    });
  });

  group('ChironLastGoodEventsCache isolation', () {
    test('company change cannot reuse previous company cached data', () {
      final cache = ChironLastGoodEventsCache<_FakeEvents>();
      cache.remember(
        tenantId: 'tA',
        companyId: 'cA',
        payload: const _FakeEvents(
          tenantId: 'tA',
          companyId: 'cA',
          count: 100,
          label: 'A',
        ),
      );
      expect(
        cache.peek(tenantId: 'tA', companyId: 'cA')?.label,
        'A',
      );
      expect(cache.peek(tenantId: 'tB', companyId: 'cB'), isNull);

      cache.remember(
        tenantId: 'tB',
        companyId: 'cB',
        payload: const _FakeEvents(
          tenantId: 'tB',
          companyId: 'cB',
          count: 3,
          label: 'B',
        ),
      );
      expect(cache.peek(tenantId: 'tA', companyId: 'cA'), isNull);
      expect(cache.peek(tenantId: 'tB', companyId: 'cB')?.label, 'B');

      cache.clearIfScopeMismatch(tenantId: 'tC', companyId: 'cC');
      expect(cache.hasEntry, isFalse);
    });

    test('successful 100-event load is retained for remount peek', () {
      final cache = ChironLastGoodEventsCache<_FakeEvents>();
      cache.remember(
        tenantId: 't1',
        companyId: 'c1',
        payload: const _FakeEvents(
          tenantId: 't1',
          companyId: 'c1',
          count: 100,
        ),
      );
      // Simulate section dispose + remount: new presentation from cache.
      final remount = initialChironEventsPresentation<_FakeEvents>(
        cachedForActiveScope: cache.peek(tenantId: 't1', companyId: 'c1'),
      );
      expect(remount.display?.count, 100);
      expect(remount.showLoading, isFalse);
    });
  });

  group('coordinator + last-good apply (stale / coalesce / dispose)', () {
    late _FlagListenable sessionL;
    late _FlagListenable profileL;
    late bool sessionReady;
    late String companyId;
    late List<String> diags;
    late List<int> loadGens;
    late List<Completer<void>> loadGates;
    late List<ChironLastGoodPresentation<_FakeEvents>> applied;

    final cache = ChironLastGoodEventsCache<_FakeEvents>();

    ChironContextLoadCoordinator build() {
      return ChironContextLoadCoordinator(
        listenables: [sessionL, profileL],
        hasCompanySession: () => sessionReady,
        companyId: () => companyId,
        runLoad: (gen) async {
          loadGens.add(gen);
          if (loadGates.isNotEmpty) {
            await loadGates.removeAt(0).future;
          }
        },
        onDiag: diags.add,
      );
    }

    setUp(() {
      sessionL = _FlagListenable();
      profileL = _FlagListenable();
      sessionReady = true;
      companyId = 'c1';
      diags = <String>[];
      loadGens = <int>[];
      loadGates = <Completer<void>>[];
      applied = <ChironLastGoodPresentation<_FakeEvents>>[];
      cache.clear();
    });

    test('stale completion cannot overwrite newer data', () async {
      final c = build();
      final gate1 = Completer<void>();
      final gate2 = Completer<void>();
      loadGates.addAll([gate1, gate2]);
      c.attach();
      expect(loadGens, [1]);

      // Complete gen1 and apply as the current last-good.
      gate1.complete();
      await Future<void>.delayed(Duration.zero);
      expect(c.shouldApplyGeneration(1), isTrue);
      const first = _FakeEvents(
        tenantId: 't1',
        companyId: 'c1',
        count: 50,
        label: 'first',
      );
      cache.remember(tenantId: 't1', companyId: 'c1', payload: first);
      applied.add(
        applyChironEventsLoadResult(
          resultOk: true,
          successPayload: first,
          resultErrorMessage: '',
          cachedForActiveScope: null,
          defaultHardError: 'unavailable',
        ),
      );

      // Start a newer generation (manual refresh).
      c.requestManualRefresh();
      expect(loadGens, [1, 2]);
      expect(c.generation, 2);

      // An older generation must not be allowed to mutate UI / cache.
      expect(c.shouldApplyGeneration(1), isFalse);
      expect(diags, contains(ChironLoadDiag.staleCompletionIgnored));

      // Complete gen2 and replace last-good atomically.
      gate2.complete();
      await Future<void>.delayed(Duration.zero);
      expect(c.shouldApplyGeneration(2), isTrue);
      const fresh = _FakeEvents(
        tenantId: 't1',
        companyId: 'c1',
        count: 100,
        label: 'fresh',
      );
      cache.remember(tenantId: 't1', companyId: 'c1', payload: fresh);
      applied.add(
        applyChironEventsLoadResult(
          resultOk: true,
          successPayload: fresh,
          resultErrorMessage: '',
          cachedForActiveScope: first,
          defaultHardError: 'unavailable',
        ),
      );

      expect(applied.last.display?.label, 'fresh');
      expect(applied.last.showStaleWarning, isFalse);
      expect(cache.peek(tenantId: 't1', companyId: 'c1')?.label, 'fresh');
      c.dispose();
    });

    test('manual refresh coalesces and does not overlap in-flight load', () async {
      final c = build();
      final gate = Completer<void>();
      loadGates.add(gate);
      c.attach();
      expect(loadGens, [1]);
      expect(c.loadInFlight, isTrue);

      c.requestManualRefresh();
      c.requestManualRefresh();
      expect(loadGens, [1]);
      expect(diags.where((d) => d == ChironLoadDiag.loadCoalesced).length, 2);
      expect(c.pendingAfterInFlight, isTrue);

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      // Coalesced follow-up starts as generation 2.
      expect(loadGens, [1, 2]);
      c.dispose();
    });

    test('disposal prevents stale UI mutation', () async {
      final c = build();
      final gate = Completer<void>();
      loadGates.add(gate);
      c.attach();
      c.dispose();

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(c.shouldApplyGeneration(1), isFalse);
      expect(diags, contains(ChironLoadDiag.staleCompletionIgnored));
    });
  });
}
