import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new leg clears pickup bearing and waits for its current accepted route',
      () async {
    // Execute the actual state methods with platform handles replaced by
    // controlled route completions. This exercises the START await boundary,
    // not a second implementation of the order or heading decision.
    final source = File('lib/main_parts/driver_home_page_state.dart')
        .readAsStringSync();
    String method(String first, String next) {
      final start = source.indexOf(first);
      final end = source.indexOf(next, start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      return source.substring(start, end);
    }

    final resetStart = source.indexOf('  void _resetNavProgressState(');
    final clearStart = source.indexOf('    if (clearRoute) {', resetStart);
    final clearEnd = source.indexOf('    }', clearStart) + '    }'.length;
    expect(clearStart, greaterThan(resetStart));
    final clear = source.substring(clearStart, clearEnd);
    final align = method(
      '  Future<void> _alignStartedLegNavigation(',
      '  Future<bool> _buildNavRouteToDestination(',
    );
    final dir = Directory.systemTemp.createTempSync('fluxidi-start-camera-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final program = File('${dir.path}/camera.dart');
    program.writeAsStringSync('''
import 'dart:async';
import 'dart:convert';
class BookingItem {}
class CameraFixture {
  List<Object> _routeCoords=[];
  double? _routeKm, _routeDurationSec, _lastSmoothedCameraBearing=90;
  Object? _latchedPrestartPreviewCameraTarget;
  bool _awaitingNewLegCameraBearing=false;
  void _resetExternalNavFallbackLatchForNewAttempt({required String reason}){}
  void _logNavBounded(String topic,String value,{required int intervalMs}){}
  void reset(bool clearRoute) { $clear }
  final route=Completer<bool>();
  bool ownerCurrent=true;
  final events=<String>[];
  Object _captureNavigationOperationOwner()=>Object();
  bool _navigationOperationIsCurrent(Object owner)=>ownerCurrent;
  Future<bool> _buildNavRouteToDestination(BookingItem b)=>route.future;
  Future<void> _forceFollowCameraNow({required String caller}) async {
    events.add('follow');
  }
  $align
}
Future<void> main() async {
  final active=CameraFixture();
  active.reset(true);
  final cleared=active._lastSmoothedCameraBearing;
  final start=active._alignStartedLegNavigation(BookingItem());
  await Future<void>.delayed(Duration.zero);
  final beforeReady=List<String>.of(active.events);
  active.route.complete(true);
  await start;
  active._lastSmoothedCameraBearing=17;
  final retainedDuringSameLeg=active._lastSmoothedCameraBearing;
  active.reset(false);
  final retainedDuringProgressReset=active._lastSmoothedCameraBearing;
  final stale=CameraFixture();
  final staleStart=stale._alignStartedLegNavigation(BookingItem());
  stale.ownerCurrent=false;
  stale.route.complete(true);
  await staleStart;
  final failed=CameraFixture();
  final failedStart=failed._alignStartedLegNavigation(BookingItem());
  failed.route.complete(false);
  await failedStart;
  print(jsonEncode({
    'cleared':cleared,'beforeReady':beforeReady,
    'activeFollow':active.events,'sameLeg':retainedDuringSameLeg,
    'progressReset':retainedDuringProgressReset,
    'staleFollow':stale.events,'failedFollow':failed.events,
  }));
}
''');
    var sdkParent = File(Platform.resolvedExecutable).parent;
    final executable = Platform.isWindows ? 'dart.exe' : 'dart';
    for (var i = 0; i < 6; i++) {
      if (File('${sdkParent.path}/dart-sdk/bin/$executable').existsSync()) break;
      sdkParent = sdkParent.parent;
    }
    final dart = File('${sdkParent.path}/dart-sdk/bin/$executable');
    expect(dart.existsSync(), isTrue);
    final result = await Process.run(dart.path, [program.path]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final actual = jsonDecode((result.stdout as String).trim()) as Map;
    expect(actual['cleared'], isNull);
    expect(actual['beforeReady'], isEmpty);
    expect(actual['activeFollow'], ['follow']);
    expect(actual['sameLeg'], 17);
    expect(actual['progressReset'], 17);
    expect(actual['staleFollow'], isEmpty);
    expect(actual['failedFollow'], isEmpty);
  });
}
