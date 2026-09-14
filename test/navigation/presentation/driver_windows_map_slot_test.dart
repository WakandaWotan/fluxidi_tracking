import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_windows_map_slot.dart';

void main() {
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
