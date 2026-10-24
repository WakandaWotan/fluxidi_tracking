import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/chiron_context_hydration_retry.dart';

class _FlagListenable extends ChangeNotifier {
  void bump() => notifyListeners();
}

void main() {
  group('ChironContextLoadCoordinator', () {
    late _FlagListenable sessionL;
    late _FlagListenable profileL;
    late bool sessionReady;
    late String companyId;
    late List<String> diags;
    late List<int> loadGens;
    late List<Completer<void>> loadGates;

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
      sessionReady = false;
      companyId = '';
      diags = <String>[];
      loadGens = <int>[];
      loadGates = <Completer<void>>[];
    });

    test('1. opens before hydration and loads automatically later', () async {
      final c = build();
      c.attach();
      expect(diags, contains(ChironLoadDiag.waitingForSession));
      expect(loadGens, isEmpty);

      sessionReady = true;
      companyId = 'co-1';
      sessionL.bump();
      await Future<void>.delayed(Duration.zero);

      expect(diags, contains(ChironLoadDiag.prerequisitesReady));
      expect(diags, contains(ChironLoadDiag.initialLoadStarted));
      expect(diags, contains(ChironLoadDiag.initialLoadCompleted));
      expect(loadGens, [1]);
      c.dispose();
    });

    test('2. session ready before profile company id', () async {
      final c = build();
      c.attach();
      sessionReady = true;
      sessionL.bump();
      expect(diags, contains(ChironLoadDiag.waitingForCompanyProfile));
      expect(loadGens, isEmpty);

      companyId = 'from-profile';
      profileL.bump();
      await Future<void>.delayed(Duration.zero);
      expect(loadGens, [1]);
      c.dispose();
    });

    test('3. profile company id before session', () async {
      final c = build();
      companyId = 'from-profile';
      c.attach();
      expect(diags, contains(ChironLoadDiag.waitingForSession));
      expect(loadGens, isEmpty);

      sessionReady = true;
      sessionL.bump();
      await Future<void>.delayed(Duration.zero);
      expect(loadGens, [1]);
      c.dispose();
    });

    test('4. rapid prerequisite changes launch one latest load', () async {
      final gate = Completer<void>();
      loadGates.add(gate);
      final c = build();
      sessionReady = true;
      companyId = 'co-1';
      c.attach();
      // In flight; further bumps coalesce.
      companyId = 'co-2';
      profileL.bump();
      profileL.bump();
      expect(diags, contains(ChironLoadDiag.loadCoalesced));
      expect(loadGens, [1]);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      // Pending coalesced load runs as generation 2.
      expect(loadGens, [1, 2]);
      c.dispose();
    });

    test('5. manual refresh does not overlap an in-flight load', () async {
      final gate = Completer<void>();
      loadGates.add(gate);
      final c = build();
      sessionReady = true;
      companyId = 'co-1';
      c.attach();
      expect(loadGens, [1]);
      c.requestManualRefresh();
      expect(diags, contains(ChironLoadDiag.loadCoalesced));
      expect(loadGens, [1]);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(loadGens.length, 2);
      c.dispose();
    });

    test('6. stale completion after dispose is ignored', () async {
      final gate = Completer<void>();
      loadGates.add(gate);
      final c = build();
      sessionReady = true;
      companyId = 'co-1';
      c.attach();
      final gen = c.generation;
      c.dispose();
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(c.shouldApplyGeneration(gen), isFalse);
      expect(diags, contains(ChironLoadDiag.staleCompletionIgnored));
    });
  });
}
