import 'dart:async';
import 'package:flutter/painting.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// Drain both Flutter fake microtasks and real filesystem completion. An
// awaited runAsync alone can deadlock a queue started in the fake zone.
Future<T> p13SettleFileWork<T>(WidgetTester tester, Future<T> Function() work) async {
  var done = false;
  final result = await tester.runAsync(() async {
    final value = await work();
    done = true;
    return value;
  });
  await tester.pump();
  expect(done, isTrue, reason: 'Fixture filesystem operation must finish; test timeouts remain unchanged');
  return result as T;
}

// Windows may still release a completed background write's handle. Only
// fixture-created directories below the system temp root may be removed.
Future<void> p13DeleteTemp(Directory directory) async {
  final temp = Directory.systemTemp.resolveSymbolicLinksSync().toLowerCase();
  final target = directory.absolute.path.toLowerCase();
  if (!target.startsWith('$temp'+Platform.pathSeparator) || target == temp) throw StateError('Unsafe fixture cleanup');
  for (var i=0; i<30; i++) {
    try { if (await directory.exists()) await directory.delete(recursive:true); return; }
    on FileSystemException catch (e) {
      if (e.osError?.errorCode != 32 || i == 29) rethrow;
      await Future<void>.delayed(const Duration(milliseconds:10));
    }
  }
}

Future<void> p13SettleImage(WidgetTester tester, ImageProvider provider, {void Function()? trigger, ImageStream? existingStream}) async {
  final complete = Completer<void>();
  final stream = existingStream ?? provider.resolve(ImageConfiguration.empty);
  final listener = ImageStreamListener((info, synchronous) {
    info.dispose();
    if (!complete.isCompleted) complete.complete();
  }, onError: (Object error, StackTrace? stack) {
    if (!complete.isCompleted) complete.complete();
  });
  stream.addListener(listener);
  try {
    trigger?.call();
    while (!complete.isCompleted) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
  } finally { stream.removeListener(listener); }
  await tester.pump();
}
