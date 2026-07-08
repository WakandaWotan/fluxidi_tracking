import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_view_mode.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_controller.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_mode.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_state.dart';

void main() {
  const controller = NavigationPresentationController.instance;

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
      expect(
        state.vehiclePresentation,
        NavigationVehiclePresentation.mapAnnotation,
      );
      expect(state.navCameraViewMode, NavCameraViewMode.overview);
      expect(state.modeLabel, 'overview');
      expect(state.diagnosticsLabel, 'NAV_PRES_overview');
    });

    test('driver delegates to streetView camera path, no HUD yet', () {
      final state = controller.resolve(NavigationPresentationMode.driver);
      expect(state.markerVisible, isTrue);
      expect(state.hudVisible, isFalse);
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
}
