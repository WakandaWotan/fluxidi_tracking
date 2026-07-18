import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart' as geo;

/// Idle / non-active-navigation tracking settings. Retained for the
/// non-navigation tracking path so unrelated screens are unaffected.
geo.LocationSettings buildDriverTrackingLocationSettings() {
  return const geo.LocationSettings(
    accuracy: geo.LocationAccuracy.bestForNavigation,
    distanceFilter: 3,
  );
}

/// FLUXIDI NAV-STREETLEVEL-FLUID-MOTION-2 (Phase 1, Part C): platforms the
/// active-navigation location profile is defined for. Exposed for testability
/// so unit tests can exercise the exact settings that will be handed to
/// Geolocator on each platform without needing the actual `Platform` singleton.
enum NavGpsPlatform { android, ios, other }

/// FLUXIDI NAV-STREETLEVEL-FLUID-MOTION-2 (Phase 1, Part C): active-navigation
/// location settings for [platform]. This is the ONLY profile the driver
/// tracking start uses while a ride is active; the previous 3 m distance-
/// filter idle profile silently fell back to the platform's default ~5 s
/// callback cadence, which was the observed source of gpsMedianMs ~5000 ms in
/// the field.
///
/// Android: requests bestForNavigation accuracy, intervalDuration 500 ms,
/// distanceFilter 0 so every sample is emitted (even at standstill) so
/// median callback cadence is sub-second and p95 stays under 1.5 s.
///
/// iOS: automotive activity type + distanceFilter 0 + no auto-pause.
///
/// Other platforms fall back to the plain bestForNavigation +
/// distanceFilter 0 profile.
geo.LocationSettings buildDriverActiveNavigationLocationSettingsFor(
  NavGpsPlatform platform,
) {
  switch (platform) {
    case NavGpsPlatform.android:
      return geo.AndroidSettings(
        accuracy: geo.LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(milliseconds: 500),
        forceLocationManager: false,
      );
    case NavGpsPlatform.ios:
      return geo.AppleSettings(
        accuracy: geo.LocationAccuracy.bestForNavigation,
        activityType: geo.ActivityType.automotiveNavigation,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
      );
    case NavGpsPlatform.other:
      return const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
  }
}

/// Runtime resolver: chooses [buildDriverActiveNavigationLocationSettingsFor]
/// for the current OS. Kept alongside the tracking-idle builder above so the
/// tracking start path can swap between the two profiles based on whether a
/// live ride is active.
geo.LocationSettings buildDriverActiveNavigationLocationSettings() {
  if (Platform.isAndroid) {
    return buildDriverActiveNavigationLocationSettingsFor(
      NavGpsPlatform.android,
    );
  }
  if (Platform.isIOS) {
    return buildDriverActiveNavigationLocationSettingsFor(NavGpsPlatform.ios);
  }
  return buildDriverActiveNavigationLocationSettingsFor(NavGpsPlatform.other);
}
