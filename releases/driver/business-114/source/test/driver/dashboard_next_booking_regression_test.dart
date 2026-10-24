import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dashboard retains the current assigned agenda after pickup is delayed',
      () async {
    // Execute the actual dashboard selector, isolated from Android/Mapbox.
    // Its input is the already scoped, current-day, nonterminal assigned list.
    // Only the wall clock is injected for the real 15:32 -> 15:46 incident.
    final source = File('lib/main_parts/driver_home_page_state.dart')
        .readAsStringSync();
    final start = source.indexOf('  BookingItem? _nextVisibleBookingForDashboard()');
    final end = source.indexOf('  String _dashboardDriverName()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final selector = source.substring(start, end)
        .replaceAll('DateTime.now()', '_fixtureNow');
    final dir = Directory.systemTemp.createTempSync('fluxidi-dashboard-agenda-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final program = File('${dir.path}/selector.dart');
    program.writeAsStringSync('''
import 'dart:convert';
class BookingItem {
  const BookingItem(this.id, this.pickupIso);
  final String id;
  final String? pickupIso;
}
class DashboardFixture {
  DashboardFixture(this._myAssignedVisibleBookings);
  final List<BookingItem> _myAssignedVisibleBookings;
  final DateTime _fixtureNow = DateTime(2026, 10, 4, 15, 46);
$selector
  String? next() => _nextVisibleBookingForDashboard()?.id;
}
void main() {
  const delayed = BookingItem('2026-10-017', '2026-10-04T15:32:44');
  const later = BookingItem('later', '2026-10-04T16:00:00');
  const overnightActive = BookingItem('physical-active', '2026-10-03T23:30:00');
  const unknown = BookingItem('unresolved-date', null);
  Object? result(List<BookingItem> rows) {
    try { return DashboardFixture(rows).next(); }
    catch (error) { return {'error': error.toString()}; }
  }
  print(jsonEncode({
    'delayedOnly': result([delayed]),
    'delayedBeforeFuture': result([later, delayed]),
    'physicalOvernight': result([later, overnightActive]),
    'excludedAgenda': result([]),
    'knownBeforeUnknown': result([unknown, later]),
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
    final actual = jsonDecode((result.stdout as String).trim());
    expect(actual, {
      'delayedOnly': '2026-10-017',
      'delayedBeforeFuture': '2026-10-017',
      'physicalOvernight': 'physical-active',
      'excludedAgenda': null,
      'knownBeforeUnknown': 'later',
    });
  });
}
