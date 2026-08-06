// GOOGLE-MAPS-LAUNCH-CONTRACT-NOOP-P0-2

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_host.dart';
import 'package:fluxidi_tracking/navigation/external/google_maps_launch_contract.dart';

void main() {
  group('GoogleMapsDestinationValidator', () {
    test('valid lat/lng accepted', () {
      expect(
        GoogleMapsDestinationValidator.isLaunchable(
          const ExternalNavigationDestination(latitude: 51.05, longitude: 3.72),
        ),
        isTrue,
      );
    });

    test('out-of-range coords rejected; address fallback ok', () {
      expect(
        GoogleMapsDestinationValidator.hasValidCoordinates(
          const ExternalNavigationDestination(latitude: 91, longitude: 3.72),
        ),
        isFalse,
      );
      expect(
        GoogleMapsDestinationValidator.isLaunchable(
          const ExternalNavigationDestination(address: 'Korenmarkt Gent'),
        ),
        isTrue,
      );
    });

    test('rejects empty and string null address', () {
      expect(
        GoogleMapsDestinationValidator.hasUsableAddress(null),
        isFalse,
      );
      expect(
        GoogleMapsDestinationValidator.hasUsableAddress('null'),
        isFalse,
      );
      expect(
        GoogleMapsDestinationValidator.hasUsableAddress('  '),
        isFalse,
      );
    });

    test('coordinate pair uses decimal point', () {
      final pair =
          GoogleMapsDestinationValidator.formatCoordinatePair(51.05, 3.72);
      expect(pair, '51.050000,3.720000');
      expect(pair.contains(','), isTrue);
      expect(pair.contains('51,05'), isFalse);
    });
  });

  group('GoogleMapsLaunchResult', () {
    test('structured launched result requires launch_dispatched', () {
      final ok = GoogleMapsLaunchResult.fromChannelMap(<String, dynamic>{
        'status': 'launched',
        'launch_dispatched': true,
        'pip_supported': true,
      });
      expect(ok.isSuccess, isTrue);

      final bad = GoogleMapsLaunchResult.fromChannelMap(<String, dynamic>{
        'status': 'launched',
        'launch_dispatched': false,
      });
      expect(bad.isSuccess, isFalse);
      expect(bad.status, GoogleMapsLaunchStatus.nativeException);
    });

    test('maps failure statuses', () {
      expect(
        GoogleMapsLaunchResult.fromChannelMap(
          <String, dynamic>{'status': 'maps_not_installed'},
        ).status,
        GoogleMapsLaunchStatus.mapsNotInstalled,
      );
      expect(
        GoogleMapsLaunchResult.fromChannelMap(
          <String, dynamic>{'status': 'maps_disabled'},
        ).status,
        GoogleMapsLaunchStatus.mapsDisabled,
      );
      expect(
        GoogleMapsLaunchResult.fromChannelMap(
          <String, dynamic>{'status': 'intent_not_resolved'},
        ).status,
        GoogleMapsLaunchStatus.intentNotResolved,
      );
      expect(
        GoogleMapsLaunchResult.fromChannelMap(
          <String, dynamic>{'status': 'activity_not_found'},
        ).status,
        GoogleMapsLaunchStatus.activityNotFound,
      );
      expect(
        GoogleMapsLaunchResult.fromChannelMap(
          <String, dynamic>{'status': 'security_exception'},
        ).status,
        GoogleMapsLaunchStatus.securityException,
      );
    });
  });

  group('GoogleMapsLaunchDecision', () {
    test('launched with pip → session + pip', () {
      final d = GoogleMapsLaunchDecision.fromResult(
        result: const GoogleMapsLaunchResult(
          status: GoogleMapsLaunchStatus.launched,
          launchDispatched: true,
          pipSupported: true,
        ),
        userWantsPip: true,
      );
      expect(d.activateExternalSession, isTrue);
      expect(d.requestPip, isTrue);
      expect(d.keepNativeGuidanceActive, isFalse);
      expect(d.uiAction, GoogleMapsLaunchUiAction.proceedWithPip);
    });

    test('launched without pip → Maps opens, no meter', () {
      final d = GoogleMapsLaunchDecision.fromResult(
        result: const GoogleMapsLaunchResult(
          status: GoogleMapsLaunchStatus.launched,
          launchDispatched: true,
          pipSupported: false,
        ),
        userWantsPip: false,
      );
      expect(d.activateExternalSession, isTrue);
      expect(d.requestPip, isFalse);
      expect(d.uiAction, GoogleMapsLaunchUiAction.proceedWithoutPip);
    });

    test('failed launch → no session, guidance stays active', () {
      final d = GoogleMapsLaunchDecision.fromResult(
        result: const GoogleMapsLaunchResult(
          status: GoogleMapsLaunchStatus.nativeException,
          failureCode: 'boom',
        ),
        userWantsPip: true,
      );
      expect(d.activateExternalSession, isFalse);
      expect(d.requestPip, isFalse);
      expect(d.keepNativeGuidanceActive, isTrue);
      expect(d.uiAction, GoogleMapsLaunchUiAction.showFailureDialog);
    });

    test('invalid destination → visible failure action', () {
      final d = GoogleMapsLaunchDecision.fromResult(
        result: const GoogleMapsLaunchResult(
          status: GoogleMapsLaunchStatus.invalidDestination,
        ),
        userWantsPip: true,
      );
      expect(d.uiAction, GoogleMapsLaunchUiAction.showInvalidDestination);
    });

    test('maps_not_installed → install dialog', () {
      final d = GoogleMapsLaunchDecision.fromResult(
        result: const GoogleMapsLaunchResult(
          status: GoogleMapsLaunchStatus.mapsNotInstalled,
        ),
        userWantsPip: true,
      );
      expect(d.uiAction, GoogleMapsLaunchUiAction.showInstallDialog);
    });
  });

  group('GoogleMapsLaunchBusyGate', () {
    test('stale busy state does not block permanently', () {
      final gate = GoogleMapsLaunchBusyGate();
      final g1 = gate.tryBegin();
      expect(g1, isNotNull);
      expect(gate.tryBegin(), isNull);
      gate.end(g1!);
      expect(gate.inFlight, isFalse);
      expect(gate.tryBegin(), isNotNull);
      gate.forceClear();
      expect(gate.inFlight, isFalse);
    });

    test('busy state always released after native_exception path', () {
      final gate = GoogleMapsLaunchBusyGate();
      final gen = gate.tryBegin();
      expect(gen, isNotNull);
      // Mimic finally after structured native_exception (no silent stuck busy).
      final decision = GoogleMapsLaunchDecision.fromResult(
        result: const GoogleMapsLaunchResult(
          status: GoogleMapsLaunchStatus.nativeException,
          failureCode: 'native_exception',
          launchDispatched: false,
        ),
        userWantsPip: true,
      );
      expect(decision.activateExternalSession, isFalse);
      expect(decision.requestPip, isFalse);
      expect(decision.uiAction, GoogleMapsLaunchUiAction.showFailureDialog);
      gate.end(gen!);
      expect(gate.inFlight, isFalse);
      expect(gate.tryBegin(), isNotNull);
    });
  });

  group('opaque URI launch contract', () {
    test('launched result opens external session; native_exception is visible', () {
      final launched = GoogleMapsLaunchDecision.fromResult(
        result: const GoogleMapsLaunchResult(
          status: GoogleMapsLaunchStatus.launched,
          launchDispatched: true,
          pipSupported: true,
        ),
        userWantsPip: true,
      );
      expect(launched.activateExternalSession, isTrue);
      expect(launched.requestPip, isTrue);

      final failed = GoogleMapsLaunchDecision.fromResult(
        result: const GoogleMapsLaunchResult(
          status: GoogleMapsLaunchStatus.nativeException,
          failureCode: 'This isn\'t a hierarchical URI.',
          launchDispatched: false,
        ),
        userWantsPip: true,
      );
      expect(failed.activateExternalSession, isFalse);
      expect(failed.requestPip, isFalse);
      expect(failed.uiAction, isNot(GoogleMapsLaunchUiAction.none));
      expect(failed.keepNativeGuidanceActive, isTrue);
    });
  });
}
