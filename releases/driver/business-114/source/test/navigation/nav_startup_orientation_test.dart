import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_startup_orientation.dart';

void main() {
  final selector = NavStartupOrientationSelector();

  group('NavStartupOrientationSelector', () {
    test('4. stale previous-session bearing cannot enter new session', () {
      // The selector is only ever given live evidence. With no live evidence
      // (stationary, no course, no route), it selects NONE rather than a value.
      final r = selector.select(
        const NavStartupOrientationInput(
          isNewSession: true,
          speedKmh: 0.0,
          gpsCourseDeg: null,
          movementBearingDeg: null,
          routeBearingDeg: null,
        ),
      );
      expect(r.source, NavOrientationSource.none);
      expect(r.bearingDeg, isNull);
      expect(r.event, NavOrientationEvent.sourceRejected);
    });

    test('5. stationary GPS course is not treated as reliable heading', () {
      final r = selector.select(
        const NavStartupOrientationInput(
          isNewSession: true,
          speedKmh: 0.0,
          gpsCourseDeg: 270.0, // parked, phone reports a course
          movementBearingDeg: null,
          routeBearingDeg: null,
        ),
      );
      expect(r.source, isNot(NavOrientationSource.gpsCourse));
    });

    test('stationary uses route bearing only as bounded support', () {
      final r = selector.select(
        const NavStartupOrientationInput(
          isNewSession: true,
          speedKmh: 0.0,
          gpsCourseDeg: 270.0,
          movementBearingDeg: null,
          routeBearingDeg: 90.0,
        ),
      );
      expect(r.source, NavOrientationSource.routeBearing);
      expect(r.bearingDeg, 90.0);
    });

    test('6. moving course smoothly takes ownership', () {
      final r = selector.select(
        const NavStartupOrientationInput(
          isNewSession: true,
          speedKmh: 25.0,
          gpsCourseDeg: 133.0,
          movementBearingDeg: 130.0,
          routeBearingDeg: 90.0,
        ),
      );
      expect(r.source, NavOrientationSource.gpsCourse);
      expect(r.bearingDeg, 133.0);
      expect(r.event, NavOrientationEvent.sourceSelected);
    });

    test('moving without usable course falls back to movement bearing', () {
      final r = selector.select(
        const NavStartupOrientationInput(
          isNewSession: true,
          speedKmh: 25.0,
          gpsCourseDeg: null,
          movementBearingDeg: 130.0,
          routeBearingDeg: 90.0,
        ),
      );
      expect(r.source, NavOrientationSource.movementBearing);
      expect(r.bearingDeg, 130.0);
    });

    test('moving course with poor accuracy is rejected', () {
      final r = selector.select(
        const NavStartupOrientationInput(
          isNewSession: true,
          speedKmh: 25.0,
          gpsCourseDeg: 133.0,
          movementBearingDeg: null,
          routeBearingDeg: 90.0,
          gpsCourseAccuracyDeg: 120.0,
        ),
      );
      expect(r.source, isNot(NavOrientationSource.gpsCourse));
    });

    test('diagnostic line is PII-free', () {
      final line = formatNavOrientationDiagnostic(
        event: NavOrientationEvent.sourceSelected,
        source: NavOrientationSource.gpsCourse,
      );
      expect(line, contains('[NAV_ORIENTATION]'));
      expect(line, contains('event=source_selected'));
      expect(line, contains('source=gpsCourse'));
    });
  });
}
