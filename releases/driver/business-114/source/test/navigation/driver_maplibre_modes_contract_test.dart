import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';

void main() {
  test('Only light dark and 3D resolve to new renderer styles', () {
    expect(kDriverMapSatelliteToggleEnabled, isFalse);
    expect(driverMapStyleForExplicitCockpitChoice(
        choice: DriverCockpitMapVisualStyle.light, isLightTheme: true),
        'fluxidi-maplibre://light');
    expect(driverMapStyleForExplicitCockpitChoice(
        choice: DriverCockpitMapVisualStyle.dark, isLightTheme: false),
        'fluxidi-maplibre://dark');
    expect(driverMapStyleForExplicitCockpitChoice(
        choice: DriverCockpitMapVisualStyle.standard3d, isLightTheme: true),
        'fluxidi-maplibre://3d');
  });
  test('Legacy satellite preference always resolves to Light', () {
    for (final light in [true, false]) {
      expect(driverMapStyleForExplicitCockpitChoice(
          choice: DriverCockpitMapVisualStyle.satellite, isLightTheme: light),
          kDriverMapStyleNavStreetLight);
      expect(driverMapStyleForTheme(isLightTheme: light,
          visualMode: DriverMapVisualMode.satellite), kDriverMapStyleNavStreetLight);
    }
    expect(isExperimentalCockpit3dMapStyleUri(kDriverMapStyleNavStreetLight), isFalse);
    expect(isExperimentalCockpit3dMapStyleUri(kDriverMapStyleStandard), isTrue);
  });
}
