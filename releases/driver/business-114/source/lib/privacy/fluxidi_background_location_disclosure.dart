/// GOOGLE-PLAY-PRIVACY-READINESS-P0
///
/// Active-trip (foreground) location explanation and permission gates.
///
/// Audit outcome for the release binary:
///   * `ACCESS_BACKGROUND_LOCATION` is intentionally NOT declared in
///     `android/app/src/main/AndroidManifest.xml`.
///   * The release code path uses only `Geolocator.getPositionStream` with an
///     `AndroidSettings` that does not set `foregroundNotificationConfig`, so
///     the geolocator plugin never starts its `GeolocatorLocationService`
///     foreground service.
///   * Only `Geolocator.checkPermission` / `Geolocator.requestPermission` are
///     called; no `Permission.locationAlways` request exists in `lib/`.
///   * Therefore location updates run only while the Activity is visible.
///
/// The Play Data Safety declaration for location must reflect
/// **foreground-only** collection during an active trip. This module carries:
///   * localized foreground-only trip-location explanation (NL/EN/FR/ES);
///   * a hard gate so that if a future change ever wires the "Always" runtime
///     request, it cannot fire before a prominent disclosure was accepted.
///
/// The gate is dormant while [kFluxidiRuntimeRequestsBackgroundLocationToday]
/// is false — it must be preserved so a regression cannot silently reintroduce
/// unannounced background collection.
library;

/// Prominent, foreground-only active-trip location explanation. Explicitly
/// scoped to "while the app is open and the trip is active" and states no
/// advertising use or sale.
String fluxidiBackgroundLocationDisclosureBody({
  required String languageCode,
}) {
  switch (languageCode) {
    case 'en':
      return 'Fluxidi uses your location during an active trip to provide '
          'navigation, measure distance and calculate the fare. Location is '
          'used only while the Fluxidi app is open and the trip is active. '
          'It is not used for advertising and is not sold.';
    case 'fr':
      return 'Fluxidi utilise votre position pendant une course active pour la '
          'navigation, mesurer la distance et calculer le tarif. La position '
          'est utilisée uniquement lorsque l’application Fluxidi est ouverte '
          'et qu’une course est active. Elle n’est pas utilisée pour la '
          'publicité et n’est pas vendue.';
    case 'es':
      return 'Fluxidi utiliza su ubicación durante un viaje activo para la '
          'navegación, medir la distancia y calcular la tarifa. La ubicación '
          'se usa únicamente mientras la app Fluxidi está abierta y hay un '
          'viaje activo. No se usa para publicidad ni se vende.';
    case 'nl':
    default:
      return 'Fluxidi gebruikt uw locatie tijdens een actieve rit voor '
          'navigatie, afstandsmeting en tariefberekening. Locatie wordt alleen '
          'gebruikt terwijl de Fluxidi-app open is en er een rit actief is. '
          'Locatie wordt niet gebruikt voor reclame en wordt niet verkocht.';
  }
}

String fluxidiBackgroundLocationDisclosureTitle({
  required String languageCode,
}) {
  switch (languageCode) {
    case 'en':
      return 'Location during active trips';
    case 'fr':
      return 'Localisation pendant les courses actives';
    case 'es':
      return 'Ubicación durante viajes activos';
    case 'nl':
    default:
      return 'Locatie tijdens actieve ritten';
  }
}

/// Hard gate retained for defense-in-depth: background / "Always" location
/// must not be requested unless a prominent disclosure was accepted. Dormant
/// today because the release path never calls the Always request.
bool mayRequestBackgroundLocationPermission({
  required bool disclosureAccepted,
}) {
  return disclosureAccepted;
}

/// Invokes [requestAlways] only after disclosure acceptance. Declining the
/// disclosure returns false and never calls [requestAlways].
Future<bool> requestBackgroundLocationAfterDisclosure({
  required bool disclosureAccepted,
  required Future<bool> Function() requestAlways,
}) async {
  if (!mayRequestBackgroundLocationPermission(
    disclosureAccepted: disclosureAccepted,
  )) {
    return false;
  }
  return requestAlways();
}

/// Post-audit release manifest no longer declares background location.
/// A manifest test enforces this constant matches on-disk state.
const bool kFluxidiAndroidManifestDeclaresBackgroundLocation = false;

/// Runtime code path (audited) never requests `Permission.locationAlways` and
/// never sets `foregroundNotificationConfig`, so no location foreground
/// service is started. Kept as a machine-checkable audit anchor.
const bool kFluxidiRuntimeRequestsBackgroundLocationToday = false;
