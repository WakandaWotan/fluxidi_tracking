import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_background_dispatcher.dart';

// NAV-MOBILE-DATA-MINIMAL-SAFE-RELEASE-P0-1 Parts A/B/C — deterministic
// tests for the bounded latest-wins background dispatcher used by the ping
// and route-presentation owners.

void main() {
  group('NavBackgroundDispatcher', () {
    test(
      'at most one runner in flight; second enqueue becomes pending latest',
      () async {
        final events = <NavBackgroundDispatchEvent>[];
        final startedInputs = <int>[];
        Completer<void>? gate;
        final dispatcher = NavBackgroundDispatcher<int>(
          runner: (input) async {
            startedInputs.add(input);
            gate = Completer<void>();
            await gate!.future;
          },
          observer: events.add,
        );

        dispatcher.enqueue(1);
        // Let the microtask start the runner.
        await Future<void>.value();
        expect(dispatcher.inFlight, isTrue);
        expect(startedInputs, [1]);

        dispatcher.enqueue(2);
        dispatcher.enqueue(3);
        dispatcher.enqueue(4);
        // Still only one in flight, latest pending is 4.
        expect(dispatcher.inFlight, isTrue);
        expect(dispatcher.hasPending, isTrue);
        expect(startedInputs, [1]);

        // Complete the first runner and let the pump run.
        gate!.complete();
        await Future<void>.value();
        await Future<void>.value();
        // Latest pending must have been picked up.
        expect(startedInputs, [1, 4]);
        // Now a second runner is in flight for input 4.
        expect(dispatcher.inFlight, isTrue);
        gate!.complete();
        await Future<void>.value();
        await Future<void>.value();

        // Observer must have emitted a replaced_pending token when the
        // pending was replaced twice.
        expect(events, contains(NavBackgroundDispatchEvent.replacedPending));
        expect(events, contains(NavBackgroundDispatchEvent.enqueuedStart));
        expect(events, contains(NavBackgroundDispatchEvent.completed));
      },
    );

    test('runner exception is contained; future inputs still run', () async {
      final events = <NavBackgroundDispatchEvent>[];
      final startedInputs = <int>[];
      final dispatcher = NavBackgroundDispatcher<int>(
        runner: (input) async {
          startedInputs.add(input);
          if (input == 1) throw StateError('boom');
        },
        observer: events.add,
        onError: (_, __) {},
      );

      dispatcher.enqueue(1);
      // Let the runner start and throw.
      await Future<void>.value();
      await Future<void>.value();
      expect(events, contains(NavBackgroundDispatchEvent.failed));
      expect(dispatcher.inFlight, isFalse);

      dispatcher.enqueue(2);
      await Future<void>.value();
      await Future<void>.value();
      expect(startedInputs, [1, 2]);
      expect(events, contains(NavBackgroundDispatchEvent.completed));
    });

    test('timeout releases ownership so the next input can run', () async {
      final events = <NavBackgroundDispatchEvent>[];
      final startedInputs = <int>[];
      final dispatcher = NavBackgroundDispatcher<int>(
        runner: (input) async {
          startedInputs.add(input);
          if (input == 1) {
            await Future<void>.delayed(const Duration(seconds: 10));
          }
        },
        observer: events.add,
        onError: (_, __) {},
        timeout: const Duration(milliseconds: 40),
      );

      dispatcher.enqueue(1);
      // Advance real time enough for the timeout to fire.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(events, contains(NavBackgroundDispatchEvent.timedOut));
      expect(dispatcher.inFlight, isFalse);

      dispatcher.enqueue(2);
      await Future<void>.value();
      await Future<void>.value();
      expect(startedInputs, [1, 2]);
    });

    test('dispose drops pending input and rejects further enqueues', () async {
      final events = <NavBackgroundDispatchEvent>[];
      Completer<void>? gate;
      final dispatcher = NavBackgroundDispatcher<int>(
        runner: (input) async {
          gate = Completer<void>();
          await gate!.future;
        },
        observer: events.add,
      );

      dispatcher.enqueue(1);
      await Future<void>.value();
      dispatcher.enqueue(2);
      expect(dispatcher.hasPending, isTrue);

      dispatcher.dispose();
      expect(dispatcher.hasPending, isFalse);
      expect(events, contains(NavBackgroundDispatchEvent.disposed));

      dispatcher.enqueue(3);
      expect(events, contains(NavBackgroundDispatchEvent.rejectedDisposed));
      // Existing in-flight can still resolve; it's the runner's
      // responsibility to guard side effects with `if (!mounted) return`.
      gate!.complete();
      await Future<void>.value();
    });

    test(
      'eligibility=false rejects without starting or replacing pending',
      () async {
        final events = <NavBackgroundDispatchEvent>[];
        final startedInputs = <int>[];
        final dispatcher = NavBackgroundDispatcher<int>(
          runner: (input) async {
            startedInputs.add(input);
          },
          eligibility: (input) => input.isEven,
          observer: events.add,
        );

        dispatcher.enqueue(1);
        dispatcher.enqueue(3);
        dispatcher.enqueue(5);
        await Future<void>.value();
        await Future<void>.value();
        expect(startedInputs, isEmpty);
        expect(
          events.where((e) => e == NavBackgroundDispatchEvent.rejectedIneligible),
          hasLength(3),
        );

        dispatcher.enqueue(2);
        await Future<void>.value();
        await Future<void>.value();
        expect(startedInputs, [2]);
      },
    );
  });
}
