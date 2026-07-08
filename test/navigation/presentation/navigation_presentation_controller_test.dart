import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_view_mode.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_controller.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_mode.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_state.dart';

void main() {
  const controller = NavigationPresentationController.instance;
  const controllerWithHud = NavigationPresentationController(
    driverHudOverlayEnabled: true,
  );
  const controllerWithHudAndHideMarker = NavigationPresentationController(
    driverHudOverlayEnabled: true,
    hideMapboxTaxiMarkerWithDriverHudEnabled: true,
  );
  const controllerWithCockpitCamera = NavigationPresentationController(
    driverCockpitCameraEnabled: true,
  );

  group('NAV-PRES-1 NavigationPresentationController', () {
    test('maps NavCameraViewMode to NavigationPresentationMode', () {
      expect(
        navigationPresentationModeFromNavCameraViewMode(
          NavCameraViewMode.northUp,
        ),
        NavigationPresentationMode.northUp,
      );
      expect(
        navigationPresentationModeFromNavCameraViewMode(
          NavCameraViewMode.overview,
        ),
        NavigationPresentationMode.overview,
      );
      expect(
        navigationPresentationModeFromNavCameraViewMode(
          NavCameraViewMode.streetView,
        ),
        NavigationPresentationMode.driver,
      );
    });

    test('maps NavigationPresentationMode back to NavCameraViewMode', () {
      expect(
        navCameraViewModeFromNavigationPresentationMode(
          NavigationPresentationMode.northUp,
        ),
        NavCameraViewMode.northUp,
      );
      expect(
        navCameraViewModeFromNavigationPresentationMode(
          NavigationPresentationMode.overview,
        ),
        NavCameraViewMode.overview,
      );
      expect(
        navCameraViewModeFromNavigationPresentationMode(
          NavigationPresentationMode.driver,
        ),
        NavCameraViewMode.streetView,
      );
    });

    test('toggle cycles north up -> overview -> driver -> north up', () {
      expect(
        toggleNavigationPresentationMode(NavigationPresentationMode.northUp),
        NavigationPresentationMode.overview,
      );
      expect(
        toggleNavigationPresentationMode(NavigationPresentationMode.overview),
        NavigationPresentationMode.driver,
      );
      expect(
        toggleNavigationPresentationMode(NavigationPresentationMode.driver),
        NavigationPresentationMode.northUp,
      );
    });

    test('northUp keeps map annotation, no HUD', () {
      final state = controller.resolve(NavigationPresentationMode.northUp);
      expect(state.markerVisible, isTrue);
      expect(state.hudVisible, isFalse);
      expect(state.showDriverHudOverlay, isFalse);
      expect(state.hideMapboxTaxiMarker, isFalse);
      expect(state.useDriverCockpitCamera, isFalse);
      expect(
        state.vehiclePresentation,
        NavigationVehiclePresentation.mapAnnotation,
      );
      expect(state.navCameraViewMode, NavCameraViewMode.northUp);
      expect(state.modeLabel, 'north_up');
      expect(state.diagnosticsLabel, 'NAV_PRES_north_up');
    });

    test('overview keeps map annotation, no HUD', () {
      final state = controller.resolve(NavigationPresentationMode.overview);
      expect(state.markerVisible, isTrue);
      expect(state.hudVisible, isFalse);
      expect(state.showDriverHudOverlay, isFalse);
      expect(state.hideMapboxTaxiMarker, isFalse);
      expect(state.useDriverCockpitCamera, isFalse);
      expect(
        state.vehiclePresentation,
        NavigationVehiclePresentation.mapAnnotation,
      );
      expect(state.navCameraViewMode, NavCameraViewMode.overview);
      expect(state.modeLabel, 'overview');
      expect(state.diagnosticsLabel, 'NAV_PRES_overview');
    });

    test('driver delegates to streetView camera path with HUD off by default',
        () {
      final state = controller.resolve(NavigationPresentationMode.driver);
      expect(state.markerVisible, isTrue);
      expect(state.hudVisible, isFalse);
      expect(state.showDriverHudOverlay, isFalse);
      expect(state.hideMapboxTaxiMarker, isFalse);
      expect(state.useDriverCockpitCamera, isFalse);
      expect(
        state.vehiclePresentation,
        NavigationVehiclePresentation.mapAnnotation,
      );
      expect(state.navCameraViewMode, NavCameraViewMode.streetView);
      expect(state.modeLabel, 'driver');
      expect(state.diagnosticsLabel, 'NAV_PRES_driver');
    });

    test('resolveForNavCameraViewMode mirrors legacy enum', () {
      for (final viewMode in NavCameraViewMode.values) {
        final state = controller.resolveForNavCameraViewMode(viewMode);
        expect(state.navCameraViewMode, viewMode);
      }
    });

    test('labels are stable across repeated resolves', () {
      for (final mode in NavigationPresentationMode.values) {
        final first = controller.resolve(mode);
        final second = controller.resolve(mode);
        expect(first, equals(second));
        expect(first.modeLabel, second.modeLabel);
        expect(first.diagnosticsLabel, second.diagnosticsLabel);
      }
    });

    test('state does not carry camera zoom/tilt/bearing fields', () {
      final state = controller.resolve(NavigationPresentationMode.driver);
      expect(state, isA<NavigationPresentationState>());
      // Guard against accidental behavior-changing camera payloads in PRES-1.
      expect(state.toString(), isNot(contains('zoom')));
      expect(state.toString(), isNot(contains('tilt')));
      expect(state.toString(), isNot(contains('bearing')));
    });
  });

  group('NAV-PRES-2A driver HUD overlay visibility', () {
    test('default flag false => driver mode does not show HUD', () {
      final state = controller.resolve(NavigationPresentationMode.driver);
      expect(state.showDriverHudOverlay, isFalse);
      expect(state.hideMapboxTaxiMarker, isFalse);
    });

    test('flag true + driver mode => showDriverHudOverlay true', () {
      final state = controllerWithHud.resolve(NavigationPresentationMode.driver);
      expect(state.showDriverHudOverlay, isTrue);
      expect(state.navCameraViewMode, NavCameraViewMode.streetView);
      expect(state.markerVisible, isTrue);
      expect(state.hideMapboxTaxiMarker, isFalse);
    });

    test('flag true + northUp => showDriverHudOverlay false', () {
      final state = controllerWithHud.resolve(NavigationPresentationMode.northUp);
      expect(state.showDriverHudOverlay, isFalse);
      expect(state.navCameraViewMode, NavCameraViewMode.northUp);
      expect(state.hideMapboxTaxiMarker, isFalse);
    });

    test('flag true + overview => showDriverHudOverlay false', () {
      final state =
          controllerWithHud.resolve(NavigationPresentationMode.overview);
      expect(state.showDriverHudOverlay, isFalse);
      expect(state.navCameraViewMode, NavCameraViewMode.overview);
      expect(state.hideMapboxTaxiMarker, isFalse);
    });

    test('switching out of driver hides HUD', () {
      expect(
        controllerWithHud.resolve(NavigationPresentationMode.driver)
            .showDriverHudOverlay,
        isTrue,
      );
      expect(
        controllerWithHud.resolve(NavigationPresentationMode.overview)
            .showDriverHudOverlay,
        isFalse,
      );
      expect(
        controllerWithHud.resolve(NavigationPresentationMode.northUp)
            .showDriverHudOverlay,
        isFalse,
      );
    });

    test('camera mode mapping unchanged when HUD flag enabled', () {
      for (final viewMode in NavCameraViewMode.values) {
        final state = controllerWithHud.resolveForNavCameraViewMode(viewMode);
        expect(state.navCameraViewMode, viewMode);
      }
    });

    test('resolveForNavCameraViewMode accepts injectable HUD flag override', () {
      final enabled = controller.resolveForNavCameraViewMode(
        NavCameraViewMode.streetView,
        driverHudOverlayEnabled: true,
      );
      expect(enabled.showDriverHudOverlay, isTrue);
      expect(enabled.hideMapboxTaxiMarker, isFalse);

      final disabled = controller.resolveForNavCameraViewMode(
        NavCameraViewMode.streetView,
        driverHudOverlayEnabled: false,
      );
      expect(disabled.showDriverHudOverlay, isFalse);
      expect(disabled.hideMapboxTaxiMarker, isFalse);
    });
  });

  group('NAV-PRES-2B Mapbox taxi marker suppression', () {
    test('default flags false + driver mode', () {
      final state = controller.resolve(NavigationPresentationMode.driver);
      expect(state.showDriverHudOverlay, isFalse);
      expect(state.hideMapboxTaxiMarker, isFalse);
    });

    test('HUD flag true + hide marker flag false + driver mode', () {
      final state = controllerWithHud.resolve(NavigationPresentationMode.driver);
      expect(state.showDriverHudOverlay, isTrue);
      expect(state.hideMapboxTaxiMarker, isFalse);
    });

    test('HUD flag true + hide marker flag true + driver mode', () {
      final state =
          controllerWithHudAndHideMarker.resolve(NavigationPresentationMode.driver);
      expect(state.showDriverHudOverlay, isTrue);
      expect(state.hideMapboxTaxiMarker, isTrue);
      expect(state.markerVisible, isTrue);
    });

    test('HUD flag true + hide marker flag true + northUp', () {
      final state =
          controllerWithHudAndHideMarker.resolve(NavigationPresentationMode.northUp);
      expect(state.showDriverHudOverlay, isFalse);
      expect(state.hideMapboxTaxiMarker, isFalse);
    });

    test('HUD flag true + hide marker flag true + overview', () {
      final state = controllerWithHudAndHideMarker
          .resolve(NavigationPresentationMode.overview);
      expect(state.showDriverHudOverlay, isFalse);
      expect(state.hideMapboxTaxiMarker, isFalse);
    });

    test('switching out of driver hides HUD and marker suppression', () {
      expect(
        controllerWithHudAndHideMarker.resolve(NavigationPresentationMode.driver)
            .hideMapboxTaxiMarker,
        isTrue,
      );
      expect(
        controllerWithHudAndHideMarker.resolve(NavigationPresentationMode.overview)
            .hideMapboxTaxiMarker,
        isFalse,
      );
      expect(
        controllerWithHudAndHideMarker.resolve(NavigationPresentationMode.driver)
            .showDriverHudOverlay,
        isTrue,
      );
      expect(
        controllerWithHudAndHideMarker.resolve(NavigationPresentationMode.overview)
            .showDriverHudOverlay,
        isFalse,
      );
    });

    test('hide marker flag alone does not suppress without HUD', () {
      const hideOnly = NavigationPresentationController(
        hideMapboxTaxiMarkerWithDriverHudEnabled: true,
      );
      final state = hideOnly.resolve(NavigationPresentationMode.driver);
      expect(state.showDriverHudOverlay, isFalse);
      expect(state.hideMapboxTaxiMarker, isFalse);
    });

    test('resolveForNavCameraViewMode accepts injectable hide-marker override',
        () {
      final hidden = controllerWithHud.resolveForNavCameraViewMode(
        NavCameraViewMode.streetView,
        hideMapboxTaxiMarkerWithDriverHudEnabled: true,
      );
      expect(hidden.showDriverHudOverlay, isTrue);
      expect(hidden.hideMapboxTaxiMarker, isTrue);

      final visible = controllerWithHud.resolveForNavCameraViewMode(
        NavCameraViewMode.streetView,
        hideMapboxTaxiMarkerWithDriverHudEnabled: false,
      );
      expect(visible.showDriverHudOverlay, isTrue);
      expect(visible.hideMapboxTaxiMarker, isFalse);
    });
  });

  group('NAV-PRES-3A driver cockpit camera profile', () {
    test('default flag false + driver => useDriverCockpitCamera false', () {
      final state = controller.resolve(NavigationPresentationMode.driver);
      expect(state.useDriverCockpitCamera, isFalse);
      expect(state.navCameraViewMode, NavCameraViewMode.streetView);
    });

    test('cockpit flag true + driver => useDriverCockpitCamera true', () {
      final state =
          controllerWithCockpitCamera.resolve(NavigationPresentationMode.driver);
      expect(state.useDriverCockpitCamera, isTrue);
      expect(state.navCameraViewMode, NavCameraViewMode.streetView);
    });

    test('cockpit flag true + northUp => useDriverCockpitCamera false', () {
      final state =
          controllerWithCockpitCamera.resolve(NavigationPresentationMode.northUp);
      expect(state.useDriverCockpitCamera, isFalse);
      expect(state.navCameraViewMode, NavCameraViewMode.northUp);
    });

    test('cockpit flag true + overview => useDriverCockpitCamera false', () {
      final state = controllerWithCockpitCamera
          .resolve(NavigationPresentationMode.overview);
      expect(state.useDriverCockpitCamera, isFalse);
      expect(state.navCameraViewMode, NavCameraViewMode.overview);
    });

    test('switching out of driver disables cockpit camera', () {
      expect(
        controllerWithCockpitCamera.resolve(NavigationPresentationMode.driver)
            .useDriverCockpitCamera,
        isTrue,
      );
      expect(
        controllerWithCockpitCamera.resolve(NavigationPresentationMode.overview)
            .useDriverCockpitCamera,
        isFalse,
      );
      expect(
        controllerWithCockpitCamera.resolve(NavigationPresentationMode.northUp)
            .useDriverCockpitCamera,
        isFalse,
      );
    });

    test('HUD and hide-marker flags remain independent from cockpit camera',
        () {
      const allFlags = NavigationPresentationController(
        driverHudOverlayEnabled: true,
        hideMapboxTaxiMarkerWithDriverHudEnabled: true,
        driverCockpitCameraEnabled: false,
      );
      final driverOnlyHud = allFlags.resolve(NavigationPresentationMode.driver);
      expect(driverOnlyHud.showDriverHudOverlay, isTrue);
      expect(driverOnlyHud.hideMapboxTaxiMarker, isTrue);
      expect(driverOnlyHud.useDriverCockpitCamera, isFalse);

      const cockpitOnly = NavigationPresentationController(
        driverCockpitCameraEnabled: true,
      );
      final driverOnlyCockpit =
          cockpitOnly.resolve(NavigationPresentationMode.driver);
      expect(driverOnlyCockpit.useDriverCockpitCamera, isTrue);
      expect(driverOnlyCockpit.showDriverHudOverlay, isFalse);
      expect(driverOnlyCockpit.hideMapboxTaxiMarker, isFalse);
    });

    test('resolveForNavCameraViewMode accepts injectable cockpit flag override',
        () {
      final enabled = controller.resolveForNavCameraViewMode(
        NavCameraViewMode.streetView,
        driverCockpitCameraEnabled: true,
      );
      expect(enabled.useDriverCockpitCamera, isTrue);

      final disabled = controller.resolveForNavCameraViewMode(
        NavCameraViewMode.streetView,
        driverCockpitCameraEnabled: false,
      );
      expect(disabled.useDriverCockpitCamera, isFalse);
    });
  });
}
