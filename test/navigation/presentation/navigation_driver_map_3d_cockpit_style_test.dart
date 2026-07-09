import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';

void main() {
  group('NAV-PRES-3I driver map 3D cockpit style resolver', () {
    test('non-cockpit resolve returns existing navigation-day style', () {
      expect(
        resolveDriverMapStyleUri(
          isLightTheme: true,
          visualMode: DriverMapVisualMode.street,
          cockpit3dSceneActive: false,
        ),
        kDriverMapStyleNavStreetLight,
      );
    });

    test('non-cockpit resolve returns existing navigation-night style', () {
      expect(
        resolveDriverMapStyleUri(
          isLightTheme: false,
          visualMode: DriverMapVisualMode.street,
          cockpit3dSceneActive: false,
        ),
        kDriverMapStyleNavStreetDark,
      );
    });

    test('non-cockpit resolve returns existing satellite-streets style', () {
      expect(
        resolveDriverMapStyleUri(
          isLightTheme: true,
          visualMode: DriverMapVisualMode.satellite,
          cockpit3dSceneActive: false,
        ),
        kDriverMapStyleSatellite,
      );
    });

    test(
      'cockpit active with compile flag off keeps baseline navigation style',
      () {
        expect(kNavigation3dCockpitSceneEnabled, isFalse);
        expect(
          resolveDriverMapStyleUri(
            isLightTheme: true,
            visualMode: DriverMapVisualMode.street,
            cockpit3dSceneActive: true,
          ),
          kDriverMapStyleNavStreetLight,
        );
      },
    );

    test(
      'explicit light choice uses navigation-day in cockpit context',
      () {
        expect(
          driverMapStyleForExplicitCockpitChoice(
            choice: DriverCockpitMapVisualStyle.light,
            isLightTheme: false,
          ),
          kDriverMapStyleNavStreetLight,
        );
      },
    );

    test(
      'explicit dark choice uses navigation-night in cockpit context',
      () {
        expect(
          driverMapStyleForExplicitCockpitChoice(
            choice: DriverCockpitMapVisualStyle.dark,
            isLightTheme: true,
          ),
          kDriverMapStyleNavStreetDark,
        );
      },
    );

    test('explicit 3D choice uses Standard when not rejected', () {
      expect(
        driverMapStyleForExplicitCockpitChoice(
          choice: DriverCockpitMapVisualStyle.standard3d,
          isLightTheme: true,
        ),
        kDriverMapStyleStandard,
      );
    });

    test('explicit satellite choice uses Standard Satellite when not rejected', () {
      expect(
        driverMapStyleForExplicitCockpitChoice(
          choice: DriverCockpitMapVisualStyle.satellite,
          isLightTheme: true,
        ),
        kDriverMapStyleStandardSatellite,
      );
    });

    test('explicit 3D rejected Standard falls back to navigation-day', () {
      expect(
        driverMapStyleForExplicitCockpitChoice(
          choice: DriverCockpitMapVisualStyle.standard3d,
          isLightTheme: true,
          rejectedExperimentalUris: {kDriverMapStyleStandard},
        ),
        kDriverMapStyleNavStreetLight,
      );
    });

    test('explicit 3D rejected Standard falls back to navigation-night', () {
      expect(
        driverMapStyleForExplicitCockpitChoice(
          choice: DriverCockpitMapVisualStyle.standard3d,
          isLightTheme: false,
          rejectedExperimentalUris: {kDriverMapStyleStandard},
        ),
        kDriverMapStyleNavStreetDark,
      );
    });

    test('explicit satellite rejected Standard Satellite falls back to satellite-streets', () {
      expect(
        driverMapStyleForExplicitCockpitChoice(
          choice: DriverCockpitMapVisualStyle.satellite,
          isLightTheme: true,
          rejectedExperimentalUris: {kDriverMapStyleStandardSatellite},
        ),
        kDriverMapStyleSatellite,
      );
    });

    test('resolve with explicit 3D choice uses Standard when cockpit active', () {
      expect(
        resolveDriverMapStyleUri(
          isLightTheme: true,
          visualMode: DriverMapVisualMode.street,
          cockpit3dSceneActive: true,
          cockpitVisualStyle: DriverCockpitMapVisualStyle.standard3d,
        ),
        kNavigation3dCockpitSceneEnabled
            ? kDriverMapStyleStandard
            : kDriverMapStyleNavStreetLight,
      );
    });

    test('resolve with explicit satellite choice uses Standard Satellite when cockpit active', () {
      expect(
        resolveDriverMapStyleUri(
          isLightTheme: true,
          visualMode: DriverMapVisualMode.satellite,
          cockpit3dSceneActive: true,
          cockpitVisualStyle: DriverCockpitMapVisualStyle.satellite,
        ),
        kNavigation3dCockpitSceneEnabled
            ? kDriverMapStyleStandardSatellite
            : kDriverMapStyleSatellite,
      );
    });

    test('resolve with explicit light switches away from 3D', () {
      expect(
        resolveDriverMapStyleUri(
          isLightTheme: true,
          visualMode: DriverMapVisualMode.street,
          cockpit3dSceneActive: true,
          cockpitVisualStyle: DriverCockpitMapVisualStyle.light,
        ),
        kNavigation3dCockpitSceneEnabled
            ? kDriverMapStyleNavStreetLight
            : kDriverMapStyleNavStreetLight,
      );
    });

    test('resolve with explicit dark switches away from 3D when flag enabled', () {
      expect(
        resolveDriverMapStyleUri(
          isLightTheme: true,
          visualMode: DriverMapVisualMode.street,
          cockpit3dSceneActive: true,
          cockpitVisualStyle: DriverCockpitMapVisualStyle.dark,
        ),
        kNavigation3dCockpitSceneEnabled
            ? kDriverMapStyleNavStreetDark
            : kDriverMapStyleNavStreetLight,
      );
    });

    test('driverMapStyleForCockpit3d prefers Standard for street cockpit', () {
      expect(
        driverMapStyleForCockpit3d(
          preferSatellite: false,
          isLightTheme: true,
        ),
        kDriverMapStyleStandard,
      );
    });

    test(
      'driverMapStyleForCockpit3d prefers Standard Satellite for satellite cockpit',
      () {
        expect(
          driverMapStyleForCockpit3d(
            preferSatellite: true,
            isLightTheme: true,
          ),
          kDriverMapStyleStandardSatellite,
        );
      },
    );

    test('rejected Standard falls back to navigation-day', () {
      expect(
        driverMapStyleForCockpit3d(
          preferSatellite: false,
          isLightTheme: true,
          rejectedExperimentalUris: {kDriverMapStyleStandard},
        ),
        kDriverMapStyleNavStreetLight,
      );
    });

    test('rejected Standard Satellite falls back to satellite-streets', () {
      expect(
        driverMapStyleForCockpit3d(
          preferSatellite: true,
          isLightTheme: true,
          rejectedExperimentalUris: {kDriverMapStyleStandardSatellite},
        ),
        kDriverMapStyleSatellite,
      );
    });

    test('isExperimentalCockpit3dMapStyleUri identifies Standard family only', () {
      expect(isExperimentalCockpit3dMapStyleUri(kDriverMapStyleStandard), isTrue);
      expect(
        isExperimentalCockpit3dMapStyleUri(kDriverMapStyleStandardSatellite),
        isTrue,
      );
      expect(
        isExperimentalCockpit3dMapStyleUri(kDriverMapStyleNavStreetLight),
        isFalse,
      );
      expect(isExperimentalCockpit3dMapStyleUri(kDriverMapStyleSatellite), isFalse);
    });
  });

  group('NAV-PRES-3I DriverCockpitMap3dCapability', () {
    test('navigation-day reports flat style', () {
      final cap = DriverCockpitMap3dCapability.resolve(
        styleUri: kDriverMapStyleNavStreetLight,
        visualMode: DriverMapVisualMode.street,
      );
      expect(cap.styleFamily, 'navigation-v1');
      expect(cap.likelyFlatNavStyle, isTrue);
      expect(cap.is3dCandidate, isFalse);
      expect(cap.terrainLikelyAvailable, isFalse);
    });

    test('navigation-night reports flat style', () {
      final cap = DriverCockpitMap3dCapability.resolve(
        styleUri: kDriverMapStyleNavStreetDark,
        visualMode: DriverMapVisualMode.street,
      );
      expect(cap.likelyFlatNavStyle, isTrue);
      expect(cap.is3dCandidate, isFalse);
    });

    test('satellite-streets reports flat raster high-pitch limitation', () {
      final cap = DriverCockpitMap3dCapability.resolve(
        styleUri: kDriverMapStyleSatellite,
        visualMode: DriverMapVisualMode.satellite,
      );
      expect(cap.styleFamily, 'satellite-streets');
      expect(cap.likelyFlatNavStyle, isTrue);
      expect(cap.is3dCandidate, isFalse);
      expect(cap.note, contains('raster_satellite'));
    });

    test('standard reports 3d candidate without terrain claim', () {
      final cap = DriverCockpitMap3dCapability.resolve(
        styleUri: kDriverMapStyleStandard,
        visualMode: DriverMapVisualMode.street,
      );
      expect(cap.styleFamily, 'standard');
      expect(cap.likelyFlatNavStyle, isFalse);
      expect(cap.is3dCandidate, isTrue);
      expect(cap.terrainLikelyAvailable, isFalse);
    });

    test('standard-satellite reports 3d candidate without terrain claim', () {
      final cap = DriverCockpitMap3dCapability.resolve(
        styleUri: kDriverMapStyleStandardSatellite,
        visualMode: DriverMapVisualMode.satellite,
      );
      expect(cap.styleFamily, 'standard-satellite');
      expect(cap.likelyFlatNavStyle, isFalse);
      expect(cap.is3dCandidate, isTrue);
      expect(cap.terrainLikelyAvailable, isFalse);
    });

    test('diagnostic line includes 3dCandidate flag', () {
      final cap = DriverCockpitMap3dCapability.resolve(
        styleUri: kDriverMapStyleStandard,
        visualMode: DriverMapVisualMode.street,
      );
      expect(cap.toDiagnosticLine(), contains('3dCandidate=true'));
      expect(cap.toDiagnosticLine(), contains('flat=false'));
    });
  });
}
