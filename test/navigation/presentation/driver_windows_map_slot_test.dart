import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_windows_map_slot.dart';

void main() {
  test('Dutch dashboard price uses a comma decimal', () {
    expect(formatDriverDashboardMoney(46.7), '€ 46,70');
    expect(formatDriverDashboardMoney(46.70, 'EUR'), '€ 46,70');
  });

  test('wide Windows layout fills unused height above the bottom nav', () {
    const topChrome = 72.0;
    const bottomNav = 64.0;
    const rideInfo = 88.0;
    const actions = 56.0;
    final mapHeight = driverWindowsMapSlotHeight(
      viewportHeight: kDriverWindowsWideHeight,
      topChrome: topChrome,
      bottomNav: bottomNav,
      rideInfoHeight: rideInfo,
      actionsHeight: actions,
    );
    expect(mapHeight, greaterThan(500));
    expect(
      driverWindowsMapOverflows(
        viewportHeight: kDriverWindowsWideHeight,
        topChrome: topChrome,
        mapHeight: mapHeight,
        rideInfoHeight: rideInfo,
        actionsHeight: actions,
        bottomNav: bottomNav,
      ),
      isFalse,
    );
  });

  test(
    'landscape next-ride map fills leftover card height without overflow',
    () {
      const pane = 520.0;
      const summary = 80.0;
      const rideInfo = 148.0;
      const actions = 48.0;
      final mapHeight = driverWindowsNextRideMapHeight(
        paneHeight: pane,
        summaryHeight: summary,
        rideInfoHeight: rideInfo,
        actionsHeight: actions,
      );
    expect(mapHeight, greaterThan(180));
    expect(
      summary + 10 + 32 + rideInfo + mapHeight + actions,
      lessThanOrEqualTo(pane + 0.5),
    );
    },
  );

  test('wide 1524x869 next-ride map grows past the old 220 cap', () {
    const header = 165.0;
    const bottomNav = 72.0;
    const padding = 20.0;
    const pane = kDriverWindowsWideHeight - header - bottomNav - padding - 8;
    final mapHeight = driverWindowsNextRideMapHeight(
      paneHeight: pane,
      summaryHeight: 80,
      rideInfoHeight: 170,
      actionsHeight: 48,
    );
    expect(mapHeight, greaterThan(220));
    expect(mapHeight + 80 + 10 + 170 + 48 + 32, lessThanOrEqualTo(pane + 0.5));
  });

  test('compact 1100x720 next-ride map stays bounded without overflow', () {
    const header = 140.0;
    const bottomNav = 72.0;
    const padding = 20.0;
    const pane = kDriverWindowsCompactHeight - header - bottomNav - padding - 8;
    final mapHeight = driverWindowsNextRideMapHeight(
      paneHeight: pane,
      summaryHeight: 70,
      rideInfoHeight: 170,
      actionsHeight: 48,
    );
    expect(mapHeight, greaterThanOrEqualTo(136));
    expect(mapHeight + 70 + 10 + 170 + 48 + 32, lessThanOrEqualTo(pane + 0.5));
  });

  test('smaller window still keeps a usable map without overflow', () {
    const topChrome = 64.0;
    const bottomNav = 56.0;
    final mapHeight = driverWindowsMapSlotHeight(
      viewportHeight: kDriverWindowsCompactHeight,
      topChrome: topChrome,
      bottomNav: bottomNav,
      rideInfoHeight: 80,
      actionsHeight: 52,
    );
    expect(mapHeight, greaterThanOrEqualTo(kDriverWindowsMapMinHeight));
    expect(
      driverWindowsMapOverflows(
        viewportHeight: kDriverWindowsCompactHeight,
        topChrome: topChrome,
        mapHeight: mapHeight,
        rideInfoHeight: 80,
        actionsHeight: 52,
        bottomNav: bottomNav,
      ),
      isFalse,
    );
  });
}
