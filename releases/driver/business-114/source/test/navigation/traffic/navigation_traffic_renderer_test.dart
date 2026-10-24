import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_traffic_controller.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_traffic_model.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_traffic_renderer.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_annotation_manager_lifecycle.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_polyline_annotation_delete.dart';

NavigationTrafficSpan span(String id, [String key = 'full']) =>
    NavigationTrafficSpan(
      id: id,
      coordinates: const [DriverLonLat(4.4, 51.2), DriverLonLat(4.5, 51.2)],
      traffic: NavigationTrafficClass.heavy,
      geometryKey: key,
    );

void main() {
  test(
    'failed stale-create cleanup is retained and retried by the latest request',
    () async {
      final renderer = NavigationTrafficRenderer<int>();
      final started = Completer<void>(), finish = Completer<int>();
      var deletes = 0;
      Future<void> delete(int id) async {
        deletes++;
        if (deletes == 1) throw StateError('temporary native failure');
      }

      final old = renderer.sync(
        spans: [span('old')],
        isCurrent: () => true,
        create: (_) {
          started.complete();
          return finish.future;
        },
        update: (_, __) async {},
        delete: delete,
      );
      await started.future;
      final oldFailure = expectLater(old, throwsStateError);
      final latest = renderer.sync(
        spans: [],
        isCurrent: () => true,
        create: (_) async => 2,
        update: (_, __) async {},
        delete: delete,
      );
      finish.complete(1);
      await oldFailure;
      await latest;
      expect(deletes, 2);
      expect(renderer.hasHandles, isFalse);
    },
  );
  test(
    'a superseded in-flight update cannot leave the latest native geometry stale',
    () async {
      final renderer = NavigationTrafficRenderer<int>();
      final started = Completer<void>(), finish = Completer<void>();
      final updates = <String>[];
      Future<void> sync(String key) => renderer.sync(
        spans: [span('a', key)],
        isCurrent: () => true,
        create: (_) async => 1,
        update: (_, s) async {
          updates.add(s.geometryKey);
          if (s.geometryKey == 'new') {
            started.complete();
            await finish.future;
          }
        },
        delete: (_) async {},
      );
      await sync('original');
      final pending = sync('new');
      await started.future;
      final latest = sync('original');
      finish.complete();
      await pending;
      await latest;
      expect(updates, ['new', 'original']);
    },
  );
  test(
    'existing nonthrowing delete result retains failed overlay for retry',
    () async {
      final renderer = NavigationTrafficRenderer<int>();
      final coordinator = NavPolylineDeleteCoordinator()..onManagerActivated(1);
      const owner = NavPolylineDeleteOwnership(
        managerGeneration: 1,
        renderEpoch: 1,
        sessionGeneration: 1,
        styleGeneration: 1,
      );
      var fail = true;
      Future<void> delete(int id) async => ensureNavigationTrafficDeletion(
        await coordinator.delete(
          annotationId: '$id',
          ownership: owner,
          currentManagerGeneration: () => 1,
          currentRenderEpoch: () => 1,
          currentSessionGeneration: () => 1,
          currentStyleGeneration: () => 1,
          nativeDelete: () async {
            if (fail) throw StateError('native unavailable');
          },
        ),
      );
      Future<void> sync(List<NavigationTrafficSpan> spans) => renderer.sync(
        spans: spans,
        isCurrent: () => true,
        create: (_) async => 1,
        update: (_, __) async {},
        delete: delete,
      );
      await sync([span('a')]);
      await expectLater(sync([]), throwsStateError);
      expect(renderer.handleCount, 1);
      fail = false;
      await sync([]);
      expect(renderer.handleCount, 0);
      expect(coordinator.wasDeleted('1'), isTrue);
      ensureNavigationTrafficDeletion(
        const NavPolylineDeleteResult(
          outcome: NavPolylineDeleteOutcome.alreadyGone,
          ownershipStillCurrent: true,
        ),
      );
    },
  );
  test(
    'existing manager drain waits for the overlay lease and rejects new native work',
    () async {
      final gate = NavAnnotationManagerGate(NavAnnotationManagerRole.route);
      final owner = gate.activate(
        styleGeneration: 1,
        sessionGeneration: 1,
        renderEpoch: 1,
      );
      final renderer = NavigationTrafficRenderer<int>();
      final started = Completer<void>(), nativeFinish = Completer<int>();
      final work = gate.runGuarded<void>(
        ownership: owner,
        kind: NavAnnotationOperationKind.update,
        nativeOp: () => renderer.sync(
          spans: [span('a')],
          isCurrent: () => true,
          create: (_) {
            started.complete();
            return nativeFinish.future;
          },
          update: (_, __) async {},
          delete: (_) async {},
        ),
      );
      await started.future;
      gate.beginDrain();
      var drained = false;
      final drain = gate.awaitDrained().then((_) {
        drained = true;
      });
      await Future<void>.value();
      expect(drained, isFalse);
      var touched = false;
      final rejected = await gate.runGuarded<void>(
        ownership: owner,
        kind: NavAnnotationOperationKind.update,
        nativeOp: () async {
          touched = true;
        },
      );
      expect(rejected.ran, isFalse);
      expect(touched, isFalse);
      nativeFinish.complete(1);
      await work;
      await drain;
      expect(drained, isTrue);
      renderer.forgetManager();
      expect(renderer.hasHandles, isFalse);
    },
  );
  test(
    'failed native deletion retains the handle for a later safe retry',
    () async {
      final renderer = NavigationTrafficRenderer<int>();
      await renderer.sync(
        spans: [span('a')],
        isCurrent: () => true,
        create: (_) async => 1,
        update: (_, __) async {},
        delete: (_) async {},
      );
      await expectLater(
        renderer.sync(
          spans: [],
          isCurrent: () => true,
          create: (_) async => 2,
          update: (_, __) async {},
          delete: (_) async => throw StateError('delete failed'),
        ),
        throwsStateError,
      );
      expect(renderer.handleCount, 1);
      await renderer.sync(
        spans: [],
        isCurrent: () => true,
        create: (_) async => 2,
        update: (_, __) async {},
        delete: (_) async {},
      );
      expect(renderer.handleCount, 0);
    },
  );
  test(
    'stable spans do not recreate or rerender; only progress geometry updates',
    () async {
      final renderer = NavigationTrafficRenderer<int>();
      var creates = 0, updates = 0, deletes = 0;
      Future<void> sync(
        List<NavigationTrafficSpan> spans, {
        bool recreate = false,
      }) => renderer.sync(
        spans: spans,
        isCurrent: () => true,
        recreate: recreate,
        create: (_) async => ++creates,
        update: (_, __) async {
          updates++;
        },
        delete: (_) async {
          deletes++;
        },
      );
      await sync([span('a'), span('b')]);
      for (var i = 0; i < 100; i++) {
        await sync([span('a'), span('b')]);
      }
      expect([creates, updates, deletes], [2, 0, 0]);
      await sync([span('a', 'progress'), span('b')]);
      expect([creates, updates, deletes], [2, 1, 0]);
      await sync([span('b')]);
      expect(deletes, 1);
      await sync([]);
      expect(renderer.handleCount, 0);
      expect(deletes, 2);
    },
  );
  test(
    'stale async create is deleted and cannot commit into a newer route',
    () async {
      final renderer = NavigationTrafficRenderer<int>();
      final createStarted = Completer<void>(), finish = Completer<int>();
      final deleted = <int>[];
      final old = renderer.sync(
        spans: [span('old')],
        isCurrent: () => true,
        create: (_) {
          createStarted.complete();
          return finish.future;
        },
        update: (_, __) async {},
        delete: (id) async {
          deleted.add(id);
        },
      );
      await createStarted.future;
      final fresh = renderer.sync(
        spans: [],
        isCurrent: () => true,
        create: (_) async => 2,
        update: (_, __) async {},
        delete: (id) async {
          deleted.add(id);
        },
      );
      finish.complete(1);
      await old;
      await fresh;
      expect(deleted, [1]);
      expect(renderer.hasHandles, isFalse);
    },
  );
  test(
    'manager disposal invalidates pending work and native failures do not poison the queue',
    () async {
      final renderer = NavigationTrafficRenderer<int>();
      await expectLater(
        renderer.sync(
          spans: [span('a')],
          isCurrent: () => true,
          create: (_) async => throw StateError('native failure'),
          update: (_, __) async {},
          delete: (_) async {},
        ),
        throwsStateError,
      );
      await renderer.sync(
        spans: [span('b')],
        isCurrent: () => true,
        create: (_) async => 2,
        update: (_, __) async {},
        delete: (_) async {},
      );
      expect(renderer.handleCount, 1);
      renderer.forgetManager();
      expect(renderer.handleCount, 0);
      var called = false;
      await renderer.sync(
        spans: [span('c')],
        isCurrent: () => false,
        create: (_) async {
          called = true;
          return 3;
        },
        update: (_, __) async {},
        delete: (_) async {},
      );
      expect(called, isFalse);
    },
  );
  test(
    'base-route replacement recreates overlays above the new primary line',
    () async {
      final renderer = NavigationTrafficRenderer<int>();
      final operations = <String>[];
      var id = 0;
      Future<void> sync(bool recreate) => renderer.sync(
        spans: [span('a')],
        recreate: recreate,
        isCurrent: () => true,
        create: (_) async {
          operations.add('create');
          return ++id;
        },
        update: (_, __) async {
          operations.add('update');
        },
        delete: (_) async {
          operations.add('delete');
        },
      );
      await sync(false);
      await sync(true);
      expect(operations, ['create', 'delete', 'create']);
      expect(renderer.handleCount, 1);
    },
  );
}
