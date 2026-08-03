// FLUXIDI-OFFLINE-MAP-DOWNLOAD-SILENT-NOOP-P0-1
//
// Feedback contract for the driver offline map-tile download flow.
//
// The field failure was a silent no-op: the preview/confirm dialog sat behind an
// unbounded `await` on the Mapbox size estimate, so a hung estimate left every
// button disabled with nothing on screen. Everything here exists so a tap can
// only ever end in visible progress, a preview, a disabled-state reason or an
// actionable localized error.
//
// Pure and dependency-light on purpose: no Mapbox imports, no I/O, so the
// classification and wording can be tested deterministically.

import 'dart:async';
import 'dart:io';

import '../app_strings.dart';

/// Upper bound for the pre-preview estimate.
///
/// `TileRegionEstimateOptions.timeout` is an SDK resource hint, not a promise
/// that the future completes. Without this bound a stalled platform call keeps
/// the page busy forever, which is exactly the reported no-op.
const Duration kDriverOfflineMapEstimateTimeout = Duration(seconds: 12);

/// Upper bound for lazy offline-manager/tile-store creation.
const Duration kDriverOfflineMapInitTimeout = Duration(seconds: 8);

/// Every failure the driver can hit in the offline map-tile flow.
enum DriverOfflineMapFailureCategory {
  noSelection,
  noInternet,
  estimateUnavailable,
  invalidGeometry,
  regionTooLarge,
  insufficientStorage,
  wifiOnlyRestricted,
  mapboxConfiguration,
  stylePackFailure,
  tileRegionResourceError,
  interrupted,
  duplicateRegion,
  unknown,
}

/// Stable non-PII token for diagnostics.
String driverOfflineMapFailureCategoryToken(
  DriverOfflineMapFailureCategory category,
) {
  switch (category) {
    case DriverOfflineMapFailureCategory.noSelection:
      return 'no_selection';
    case DriverOfflineMapFailureCategory.noInternet:
      return 'no_internet';
    case DriverOfflineMapFailureCategory.estimateUnavailable:
      return 'estimate_unavailable';
    case DriverOfflineMapFailureCategory.invalidGeometry:
      return 'invalid_geometry';
    case DriverOfflineMapFailureCategory.regionTooLarge:
      return 'region_too_large';
    case DriverOfflineMapFailureCategory.insufficientStorage:
      return 'insufficient_storage';
    case DriverOfflineMapFailureCategory.wifiOnlyRestricted:
      return 'wifi_only_restricted';
    case DriverOfflineMapFailureCategory.mapboxConfiguration:
      return 'mapbox_configuration';
    case DriverOfflineMapFailureCategory.stylePackFailure:
      return 'style_pack_failure';
    case DriverOfflineMapFailureCategory.tileRegionResourceError:
      return 'tile_region_resource_error';
    case DriverOfflineMapFailureCategory.interrupted:
      return 'interrupted';
    case DriverOfflineMapFailureCategory.duplicateRegion:
      return 'duplicate_region';
    case DriverOfflineMapFailureCategory.unknown:
      return 'unknown';
  }
}

/// Redacts anything token-shaped or secret-shaped from diagnostic text.
///
/// Mapbox SDK failures routinely carry the request URL, and that URL carries
/// `access_token=pk...`. Nothing derived from an exception may reach a log or
/// the UI without passing through here.
String redactDriverOfflineMapDiagnostic(String input) {
  var out = input;
  out = out.replaceAll(
    RegExp(r'access_token=[^&\s"]*', caseSensitive: false),
    'access_token=[redacted]',
  );
  out = out.replaceAll(
    RegExp(r'\b(?:pk|sk|tk)\.[A-Za-z0-9._\-]{6,}', caseSensitive: false),
    '[redacted-token]',
  );
  out = out.replaceAll(
    RegExp(r'\b[Bb]earer\s+[A-Za-z0-9._\-]+'),
    'Bearer [redacted]',
  );
  return out;
}

bool _mentionsAny(String haystack, List<String> needles) {
  for (final needle in needles) {
    if (haystack.contains(needle)) return true;
  }
  return false;
}

/// Maps a thrown error plus the phase it came from onto one bounded category.
///
/// The error text is only ever inspected here and then discarded, so a raw SDK
/// message can never reach the driver.
DriverOfflineMapFailureCategory classifyDriverOfflineMapFailure({
  Object? error,
  String phase = '',
  bool mapboxConfigured = true,
  bool wifiOnlyRequested = false,
  bool hasNetwork = true,
}) {
  if (!mapboxConfigured) {
    return DriverOfflineMapFailureCategory.mapboxConfiguration;
  }
  if (error is SocketException) {
    return DriverOfflineMapFailureCategory.noInternet;
  }
  if (error is TimeoutException) {
    // A stalled estimate is the reported no-op; a stalled init is configuration.
    if (phase == 'init') {
      return DriverOfflineMapFailureCategory.mapboxConfiguration;
    }
    if (phase == 'download') return DriverOfflineMapFailureCategory.interrupted;
    return DriverOfflineMapFailureCategory.estimateUnavailable;
  }

  final text = redactDriverOfflineMapDiagnostic(
    (error?.toString() ?? '').toLowerCase(),
  );

  if (_mentionsAny(text, <String>[
    'access token',
    'accesstoken',
    'unauthorized',
    '401',
    '403',
    'not initialized',
    'could not initialize',
  ])) {
    return DriverOfflineMapFailureCategory.mapboxConfiguration;
  }
  // Deliberately narrow: broad words like "offline" also occur in the wrapping
  // exception's own class name, which would swallow every other category.
  if (_mentionsAny(text, <String>[
    'socketexception',
    'no address associated',
    'network is unreachable',
    'failed host lookup',
    'connection refused',
    'connection closed',
    'no internet',
    'not connected',
  ])) {
    return DriverOfflineMapFailureCategory.noInternet;
  }
  if (_mentionsAny(text, <String>[
    'no space',
    'insufficient storage',
    'disk full',
    'quota',
    'enospc',
  ])) {
    return DriverOfflineMapFailureCategory.insufficientStorage;
  }
  if (_mentionsAny(text, <String>[
    'too large',
    'tile count',
    'exceeds',
    'limit exceeded',
  ])) {
    return DriverOfflineMapFailureCategory.regionTooLarge;
  }
  if (_mentionsAny(text, <String>[
    'geometry',
    'invalid coordinate',
    'invalid bounds',
    'malformed',
  ])) {
    return DriverOfflineMapFailureCategory.invalidGeometry;
  }
  if (_mentionsAny(text, <String>[
    'expensive',
    'metered',
    'wifi',
    'wi-fi',
    'network restriction',
  ])) {
    return DriverOfflineMapFailureCategory.wifiOnlyRestricted;
  }
  if (_mentionsAny(text, <String>['stylepack', 'style pack'])) {
    return DriverOfflineMapFailureCategory.stylePackFailure;
  }
  if (_mentionsAny(text, <String>[
    'tileregion',
    'tile region',
    'resource error',
  ])) {
    return DriverOfflineMapFailureCategory.tileRegionResourceError;
  }
  if (_mentionsAny(text, <String>['canceled', 'cancelled', 'interrupted'])) {
    return DriverOfflineMapFailureCategory.interrupted;
  }

  if (!hasNetwork) return DriverOfflineMapFailureCategory.noInternet;
  if (wifiOnlyRequested && _mentionsAny(text, <String>['restricted'])) {
    return DriverOfflineMapFailureCategory.wifiOnlyRestricted;
  }

  switch (phase) {
    case 'init':
      return DriverOfflineMapFailureCategory.mapboxConfiguration;
    case 'estimate':
      return DriverOfflineMapFailureCategory.estimateUnavailable;
    case 'download':
      return DriverOfflineMapFailureCategory.interrupted;
    default:
      return DriverOfflineMapFailureCategory.unknown;
  }
}

/// Localized, bounded, actionable message for [category].
///
/// Never contains a token, a raw exception, a file path or customer data.
String driverOfflineMapFailureMessage({
  required DriverOfflineMapFailureCategory category,
  required AppLanguage language,
}) {
  String pick({
    required String nl,
    required String en,
    String? fr,
    String? es,
  }) {
    switch (language) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.fr:
        return fr ?? en;
      case AppLanguage.es:
        return es ?? en;
      case AppLanguage.en:
      case AppLanguage.de:
        return en;
    }
  }

  switch (category) {
    case DriverOfflineMapFailureCategory.noSelection:
      return pick(
        nl: 'Selecteer eerst een plaats.',
        en: 'Select a place first.',
        fr: 'Sélectionnez d’abord un lieu.',
        es: 'Selecciona primero un lugar.',
      );
    case DriverOfflineMapFailureCategory.noInternet:
      return pick(
        nl: 'Geen internetverbinding. Verbind met wifi en probeer opnieuw.',
        en: 'No internet connection. Connect to Wi-Fi and try again.',
        fr: 'Pas de connexion Internet. Connectez-vous au Wi-Fi et réessayez.',
        es: 'Sin conexión a internet. Conéctate al Wi-Fi e inténtalo de nuevo.',
      );
    case DriverOfflineMapFailureCategory.estimateUnavailable:
      return pick(
        nl:
            'Grootte kon niet worden geschat. Je kunt doorgaan of het later '
            'opnieuw proberen.',
        en: 'Size could not be estimated. You can continue or retry later.',
        fr:
            'La taille n’a pas pu être estimée. Continuez ou réessayez plus '
            'tard.',
        es:
            'No se pudo estimar el tamaño. Puedes continuar o reintentarlo más '
            'tarde.',
      );
    case DriverOfflineMapFailureCategory.invalidGeometry:
      return pick(
        nl: 'Dit gebied is ongeldig. Kies een andere plaats of straal.',
        en: 'This area is invalid. Choose another place or radius.',
        fr: 'Cette zone est invalide. Choisissez un autre lieu ou rayon.',
        es: 'Esta zona no es válida. Elige otro lugar o radio.',
      );
    case DriverOfflineMapFailureCategory.regionTooLarge:
      return pick(
        nl: 'Dit gebied is te groot. Kies een kleinere straal.',
        en: 'This area is too large. Choose a smaller radius.',
        fr: 'Cette zone est trop grande. Choisissez un rayon plus petit.',
        es: 'Esta zona es demasiado grande. Elige un radio menor.',
      );
    case DriverOfflineMapFailureCategory.insufficientStorage:
      return pick(
        nl:
            'Niet genoeg opslagruimte. Verwijder een regio of maak ruimte vrij.',
        en: 'Not enough storage. Delete a region or free up space.',
        fr: 'Espace insuffisant. Supprimez une région ou libérez de l’espace.',
        es: 'Espacio insuficiente. Elimina una región o libera espacio.',
      );
    case DriverOfflineMapFailureCategory.wifiOnlyRestricted:
      return pick(
        nl:
            'Download niet gestart: alleen-wifi staat aan en er is geen wifi. '
            'Zet alleen-wifi uit of verbind met wifi.',
        en:
            'Download did not start: Wi-Fi only is on and there is no Wi-Fi. '
            'Turn Wi-Fi only off or connect to Wi-Fi.',
        fr:
            'Téléchargement non démarré : Wi-Fi uniquement est activé sans '
            'Wi-Fi. Désactivez-le ou connectez-vous au Wi-Fi.',
        es:
            'La descarga no comenzó: solo Wi-Fi está activo y no hay Wi-Fi. '
            'Desactívalo o conéctate al Wi-Fi.',
      );
    case DriverOfflineMapFailureCategory.mapboxConfiguration:
      return pick(
        nl:
            'Kaartservice is niet beschikbaar op dit toestel. Neem contact op '
            'met support.',
        en: 'Map service is unavailable on this device. Please contact support.',
        fr:
            'Le service de cartes est indisponible sur cet appareil. '
            'Contactez le support.',
        es:
            'El servicio de mapas no está disponible en este dispositivo. '
            'Contacta con soporte.',
      );
    case DriverOfflineMapFailureCategory.stylePackFailure:
      return pick(
        nl: 'Kaartstijl kon niet worden gedownload. Probeer opnieuw.',
        en: 'Map style could not be downloaded. Please try again.',
        fr: 'Le style de carte n’a pas pu être téléchargé. Réessayez.',
        es: 'No se pudo descargar el estilo del mapa. Inténtalo de nuevo.',
      );
    case DriverOfflineMapFailureCategory.tileRegionResourceError:
      return pick(
        nl:
            'Sommige kaarttegels konden niet worden gedownload. Regio is niet '
            'als volledig gemarkeerd.',
        en:
            'Some map tiles could not be downloaded. The region is not marked '
            'complete.',
        fr:
            'Certaines tuiles n’ont pas pu être téléchargées. La région n’est '
            'pas marquée comme complète.',
        es:
            'Algunas teselas no se pudieron descargar. La región no se marca '
            'como completa.',
      );
    case DriverOfflineMapFailureCategory.interrupted:
      return pick(
        nl:
            'Download mislukt of onderbroken. Regio is niet als volledig '
            'gemarkeerd.',
        en:
            'Download failed or interrupted. Region is not marked complete.',
        fr:
            'Téléchargement échoué ou interrompu. La région n’est pas marquée '
            'comme complète.',
        es:
            'Descarga fallida o interrumpida. La región no se marca como '
            'completa.',
      );
    case DriverOfflineMapFailureCategory.duplicateRegion:
      return pick(
        nl: 'Deze regio is al gedownload.',
        en: 'This region is already downloaded.',
        fr: 'Cette région est déjà téléchargée.',
        es: 'Esta región ya está descargada.',
      );
    case DriverOfflineMapFailureCategory.unknown:
      return pick(
        nl: 'Downloaden kon niet worden gestart. Probeer het opnieuw.',
        en: 'The download could not be started. Please try again.',
        fr: 'Le téléchargement n’a pas pu démarrer. Réessayez.',
        es: 'No se pudo iniciar la descarga. Inténtalo de nuevo.',
      );
  }
}

/// Short stable non-reversible tag for a region id, safe for logs.
String driverOfflineMapRegionIdHash(String regionId) {
  final normalized = regionId.trim();
  if (normalized.isEmpty) return 'none';
  var hi = 0x811c9dc5;
  var lo = 0x1000193;
  for (final unit in normalized.codeUnits) {
    hi = (hi ^ unit) & 0xffffffff;
    hi = (hi * 0x01000193) & 0xffffffff;
    lo = (lo + ((unit + 7) * 0x27d4eb2d)) & 0xffffffff;
  }
  final digest =
      hi.toRadixString(16).padLeft(8, '0') + lo.toRadixString(16).padLeft(8, '0');
  return digest.substring(0, 12);
}

/// Builds the PII-safe diagnostic line for one offline-download phase.
///
/// Optional estimate fields are finite/non-finite classifications only — never
/// raw byte counts, tokens, URLs or SDK objects.
String buildDriverOfflineMapDiagnostic({
  required String phase,
  required String regionId,
  int? radiusKm,
  DriverOfflineMapFailureCategory? category,
  int? completedResourceCount,
  int? requiredResourceCount,
  int? erroredResourceCount,
  String completionState = '',
  bool? estimateAvailable,
  String estimateFinite = '',
  String marginFinite = '',
}) {
  final parts = <String>[
    'phase=${redactDriverOfflineMapDiagnostic(phase.trim()).replaceAll(' ', '_')}',
    'region=${driverOfflineMapRegionIdHash(regionId)}',
    'radius=${radiusKm == null ? '-' : '${radiusKm}km'}',
    'category=${category == null ? '-' : driverOfflineMapFailureCategoryToken(category)}',
    'completed=${completedResourceCount ?? '-'}',
    'required=${requiredResourceCount ?? '-'}',
    'errored=${erroredResourceCount ?? '-'}',
    'completion=${completionState.trim().isEmpty ? '-' : completionState.trim()}',
    'estimate=${estimateAvailable == null ? '-' : (estimateAvailable ? 'yes' : 'no')}',
    'estimate_finite=${estimateFinite.trim().isEmpty ? '-' : estimateFinite.trim()}',
    'margin_finite=${marginFinite.trim().isEmpty ? '-' : marginFinite.trim()}',
  ];
  return '[OFFLINE_MAPS] ${parts.join(' ')}';
}

/// What the primary Europe download button may do right now.
enum DriverOfflineMapCtaState {
  /// Tappable, but explains that a place must be picked first.
  needsSelection,

  /// Tappable and ready to open the preview.
  ready,

  /// A size estimate is running; the button reports progress instead.
  estimating,

  /// A download is running; the button reports progress instead.
  downloading,
}

DriverOfflineMapCtaState resolveDriverOfflineMapCtaState({
  required bool hasSelection,
  required bool estimateInProgress,
  required bool downloadInProgress,
}) {
  if (downloadInProgress) return DriverOfflineMapCtaState.downloading;
  if (estimateInProgress) return DriverOfflineMapCtaState.estimating;
  if (!hasSelection) return DriverOfflineMapCtaState.needsSelection;
  return DriverOfflineMapCtaState.ready;
}

/// A CTA in this state must never be tapped into a no-op.
bool driverOfflineMapCtaIsTappable(DriverOfflineMapCtaState state) =>
    state == DriverOfflineMapCtaState.ready ||
    state == DriverOfflineMapCtaState.needsSelection;

/// Whether a previously selected place is still present in fresh results.
///
/// Used to drop a stale selection when the query changes, so the radius controls
/// can never describe a place the driver can no longer see.
bool driverOfflineMapSelectionStillListed({
  required String selectedFeatureId,
  required String selectedPrimaryName,
  required Iterable<String> resultFeatureIds,
  required Iterable<String> resultPrimaryNames,
}) {
  final id = selectedFeatureId.trim();
  if (id.isNotEmpty) {
    for (final candidate in resultFeatureIds) {
      if (candidate.trim() == id) return true;
    }
    return false;
  }
  final name = selectedPrimaryName.trim().toLowerCase();
  if (name.isEmpty) return false;
  for (final candidate in resultPrimaryNames) {
    if (candidate.trim().toLowerCase() == name) return true;
  }
  return false;
}
