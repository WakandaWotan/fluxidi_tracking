// GOOGLE-MAPS-LAUNCH-CONTRACT-NOOP-P0-2
//
// Structured Google Maps launch contract. Flutter must never treat an unknown
// or failed native result as success, and must never silently no-op.

import 'external_navigation_host.dart';

/// Canonical native/Flutter launch statuses.
enum GoogleMapsLaunchStatus {
  launched,
  mapsNotInstalled,
  mapsDisabled,
  invalidDestination,
  intentNotResolved,
  activityNotFound,
  securityException,
  nativeException,
  cancelled,
  unsupportedPlatform,
}

/// UI action derived from a launch attempt (pure; no Flutter widgets).
enum GoogleMapsLaunchUiAction {
  none,
  showInstallDialog,
  showInvalidDestination,
  showFailureDialog,
  showCancelledToast,
  proceedWithPip,
  proceedWithoutPip,
}

class GoogleMapsLaunchResult {
  const GoogleMapsLaunchResult({
    required this.status,
    this.failureCode,
    this.pipSupported = false,
    this.launchDispatched = false,
    this.mapsPackageInstalled,
    this.mapsPackageEnabled,
    this.mapsIntentResolved,
    this.message,
    this.uri,
  });

  final GoogleMapsLaunchStatus status;
  final String? failureCode;
  final bool pipSupported;
  final bool launchDispatched;
  final bool? mapsPackageInstalled;
  final bool? mapsPackageEnabled;
  final bool? mapsIntentResolved;
  final String? message;
  final String? uri;

  bool get isSuccess =>
      status == GoogleMapsLaunchStatus.launched && launchDispatched;

  Map<String, Object?> toDebugMap() => <String, Object?>{
        'status': status.name,
        'failure_code': failureCode,
        'pip_supported': pipSupported,
        'launch_dispatched': launchDispatched,
        'maps_package_installed': mapsPackageInstalled,
        'maps_package_enabled': mapsPackageEnabled,
        'maps_intent_resolved': mapsIntentResolved,
      };

  static GoogleMapsLaunchStatus parseStatus(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'launched':
        return GoogleMapsLaunchStatus.launched;
      case 'maps_not_installed':
        return GoogleMapsLaunchStatus.mapsNotInstalled;
      case 'maps_disabled':
        return GoogleMapsLaunchStatus.mapsDisabled;
      case 'invalid_destination':
        return GoogleMapsLaunchStatus.invalidDestination;
      case 'intent_not_resolved':
        return GoogleMapsLaunchStatus.intentNotResolved;
      case 'activity_not_found':
        return GoogleMapsLaunchStatus.activityNotFound;
      case 'security_exception':
        return GoogleMapsLaunchStatus.securityException;
      case 'cancelled':
        return GoogleMapsLaunchStatus.cancelled;
      case 'unsupported_platform':
        return GoogleMapsLaunchStatus.unsupportedPlatform;
      case 'native_exception':
      default:
        return GoogleMapsLaunchStatus.nativeException;
    }
  }

  /// Parse native/host channel map into a strict contract result.
  static GoogleMapsLaunchResult fromChannelMap(Map<String, dynamic> raw) {
    final statusRaw = (raw['status'] ?? '').toString();
    final ok = raw['ok'] == true;
    final dispatched = raw['launch_dispatched'] == true ||
        raw['maps_launch_dispatched'] == true;
    GoogleMapsLaunchStatus status;
    if (statusRaw.isNotEmpty) {
      status = parseStatus(statusRaw);
    } else if (ok && dispatched) {
      status = GoogleMapsLaunchStatus.launched;
    } else {
      status = _statusFromLegacyError((raw['error'] ?? '').toString());
    }
    // Never treat launched without dispatch as success.
    if (status == GoogleMapsLaunchStatus.launched && !dispatched) {
      status = GoogleMapsLaunchStatus.nativeException;
    }
    return GoogleMapsLaunchResult(
      status: status,
      failureCode: (raw['failure_code'] ?? raw['error'])?.toString(),
      pipSupported: raw['pip_supported'] == true,
      launchDispatched: dispatched && status == GoogleMapsLaunchStatus.launched,
      mapsPackageInstalled: raw['maps_package_installed'] as bool?,
      mapsPackageEnabled: raw['maps_package_enabled'] as bool?,
      mapsIntentResolved: raw['maps_intent_resolved'] as bool?,
      message: raw['message']?.toString(),
      uri: raw['uri']?.toString() ?? raw['maps_intent_uri']?.toString(),
    );
  }

  static GoogleMapsLaunchStatus _statusFromLegacyError(String error) {
    switch (error) {
      case 'google_maps_not_installed':
      case 'maps_not_installed':
        return GoogleMapsLaunchStatus.mapsNotInstalled;
      case 'maps_disabled':
        return GoogleMapsLaunchStatus.mapsDisabled;
      case 'missing_destination':
      case 'invalid_destination':
        return GoogleMapsLaunchStatus.invalidDestination;
      case 'intent_not_resolved':
        return GoogleMapsLaunchStatus.intentNotResolved;
      case 'activity_not_found':
        return GoogleMapsLaunchStatus.activityNotFound;
      case 'security_exception':
        return GoogleMapsLaunchStatus.securityException;
      case 'unsupported_platform':
        return GoogleMapsLaunchStatus.unsupportedPlatform;
      default:
        return GoogleMapsLaunchStatus.nativeException;
    }
  }
}

/// Destination validation independent of locale formatting.
class GoogleMapsDestinationValidator {
  static bool isValidLatitude(double? lat) =>
      lat != null && lat.isFinite && lat >= -90.0 && lat <= 90.0;

  static bool isValidLongitude(double? lng) =>
      lng != null && lng.isFinite && lng >= -180.0 && lng <= 180.0;

  static bool hasValidCoordinates(ExternalNavigationDestination dest) =>
      isValidLatitude(dest.latitude) && isValidLongitude(dest.longitude);

  static bool hasUsableAddress(String? address) {
    final trimmed = (address ?? '').trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if (lower == 'null' || lower == 'undefined') return false;
    return true;
  }

  static bool isLaunchable(ExternalNavigationDestination dest) =>
      hasValidCoordinates(dest) || hasUsableAddress(dest.address);

  /// Locale-invariant lat,lng pair (always '.' decimals).
  static String formatCoordinatePair(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';
  }
}

/// Pure mapping from launch outcome + PiP choice to UI/session effects.
class GoogleMapsLaunchDecision {
  const GoogleMapsLaunchDecision({
    required this.uiAction,
    required this.activateExternalSession,
    required this.requestPip,
    required this.keepNativeGuidanceActive,
  });

  final GoogleMapsLaunchUiAction uiAction;
  final bool activateExternalSession;
  final bool requestPip;
  final bool keepNativeGuidanceActive;

  static GoogleMapsLaunchDecision fromResult({
    required GoogleMapsLaunchResult result,
    required bool userWantsPip,
  }) {
    if (result.status == GoogleMapsLaunchStatus.cancelled) {
      return const GoogleMapsLaunchDecision(
        uiAction: GoogleMapsLaunchUiAction.showCancelledToast,
        activateExternalSession: false,
        requestPip: false,
        keepNativeGuidanceActive: true,
      );
    }
    if (!result.isSuccess) {
      final ui = switch (result.status) {
        GoogleMapsLaunchStatus.mapsNotInstalled ||
        GoogleMapsLaunchStatus.mapsDisabled =>
          GoogleMapsLaunchUiAction.showInstallDialog,
        GoogleMapsLaunchStatus.invalidDestination =>
          GoogleMapsLaunchUiAction.showInvalidDestination,
        _ => GoogleMapsLaunchUiAction.showFailureDialog,
      };
      return GoogleMapsLaunchDecision(
        uiAction: ui,
        activateExternalSession: false,
        requestPip: false,
        keepNativeGuidanceActive: true,
      );
    }
    return GoogleMapsLaunchDecision(
      uiAction: userWantsPip
          ? GoogleMapsLaunchUiAction.proceedWithPip
          : GoogleMapsLaunchUiAction.proceedWithoutPip,
      activateExternalSession: true,
      requestPip: userWantsPip,
      keepNativeGuidanceActive: false,
    );
  }
}

/// Re-entrancy gate so a stale busy flag cannot permanently block the button.
class GoogleMapsLaunchBusyGate {
  bool _inFlight = false;
  int _generation = 0;

  bool get inFlight => _inFlight;

  /// Returns a generation token when acquired; null if already in flight.
  int? tryBegin() {
    if (_inFlight) return null;
    _inFlight = true;
    return ++_generation;
  }

  void end(int generation) {
    if (generation == _generation) {
      _inFlight = false;
    }
  }

  /// Test/helper: force-clear a stuck busy state.
  void forceClear() {
    _inFlight = false;
  }
}
