import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/maplibre_offline_preview_lease.dart';

void main() {
  test(
    'overlapping screens stay offline until the last owner closes',
    () async {
      final calls = <bool>[];
      final lease = MapLibreOfflinePreviewLease(
        setOffline: (v) async {
          calls.add(v);
        },
      );
      final first = Object(), second = Object();
      await lease.acquire(first);
      await lease.acquire(second);
      await lease.release(first);
      expect(calls, [true]);
      await lease.release(second);
      expect(calls, [true, false]);
    },
  );
  test('pop during delayed arm cannot reconnect a newer preview', () async {
    final arm = Completer<void>();
    final calls = <bool>[];
    final lease = MapLibreOfflinePreviewLease(
      setOffline: (v) async {
        calls.add(v);
        if (v && calls.length == 1) await arm.future;
      },
    );
    final first = Object(), second = Object();
    final a = lease.acquire(first),
        b = lease.acquire(second),
        close = lease.release(first);
    arm.complete();
    await Future.wait([a, b, close]);
    expect(calls, [true]);
    await lease.release(second);
    expect(calls, [true, false]);
  });
  test(
    'failed arm does not poison the queue or claim a usable offline pack',
    () async {
      var failures = 1;
      final calls = <bool>[];
      final lease = MapLibreOfflinePreviewLease(
        setOffline: (v) async {
          calls.add(v);
          if (v && failures-- > 0) throw StateError('native failure');
        },
      );
      final first = Object(), second = Object();
      await expectLater(lease.acquire(first), throwsStateError);
      await lease.release(first);
      await lease.acquire(second);
      await lease.release(second);
      expect(calls, [true, true, false]);
    },
  );
}
