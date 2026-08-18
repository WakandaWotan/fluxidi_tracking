// LIMOUSINE-MARKETPLACE-P2D4C1A — pickup current location.
// Reuses Geolocator (permission + one GPS fix) and Mapbox Geocoding v5 reverse
// from CalculatorPage / airport. No second provider, key, or background track.

import 'dart:async';

import 'package:geolocator/geolocator.dart' as geo;

import '../app_strings.dart';
import 'limousine_address_lookup.dart';

const Duration kLimousineCurrentLocationTimeout = Duration(seconds: 12);

const LocalizedText kLimousineCurrentLocationTooltip = LocalizedText(
  nl: 'Huidige locatie',
  en: 'Current location',
  fr: 'Position actuelle',
  es: 'Ubicación actual',
);

const LocalizedText kLimousineCurrentLocationLoading = LocalizedText(
  nl: 'Huidige locatie ophalen…',
  en: 'Getting current location…',
  fr: 'Récupération de la position actuelle…',
  es: 'Obteniendo la ubicación actual…',
);

const LocalizedText kLimousineCurrentLocationServicesOff = LocalizedText(
  nl: 'Locatieservices staan uit op dit toestel.',
  en: 'Location services are turned off on this device.',
  fr: 'Les services de localisation sont désactivés sur cet appareil.',
  es: 'Los servicios de ubicación están desactivados en este dispositivo.',
);

const LocalizedText kLimousineCurrentLocationDenied = LocalizedText(
  nl: 'Locatietoegang geweigerd. Tik opnieuw om het nog eens te proberen.',
  en: 'Location access denied. Tap again to retry.',
  fr: 'Accès à la localisation refusé. Appuyez à nouveau pour réessayer.',
  es: 'Acceso a la ubicación denegado. Pulse de nuevo para reintentar.',
);

const LocalizedText kLimousineCurrentLocationDeniedForever = LocalizedText(
  nl: 'Locatietoegang is permanent geweigerd. Open Instellingen → Apps → Fluxidi → Machtigingen en sta locatie toe.',
  en: 'Location access is permanently denied. Open Settings → Apps → Fluxidi → Permissions and allow location.',
  fr: 'L’accès à la localisation est refusé de façon permanente. Ouvrez Paramètres → Applications → Fluxidi → Autorisations et autorisez la localisation.',
  es: 'El acceso a la ubicación está denegado de forma permanente. Abra Ajustes → Apps → Fluxidi → Permisos y permita la ubicación.',
);

const LocalizedText kLimousineCurrentLocationOpenSettings = LocalizedText(
  nl: 'App-instellingen openen',
  en: 'Open app settings',
  fr: 'Ouvrir les paramètres de l’application',
  es: 'Abrir la configuración de la app',
);

const LocalizedText kLimousineCurrentLocationTimeoutMessage = LocalizedText(
  nl: 'Locatie ophalen duurde te lang. Probeer het opnieuw.',
  en: 'Getting the location took too long. Try again.',
  fr: 'La localisation a pris trop de temps. Réessayez.',
  es: 'Obtener la ubicación tardó demasiado. Inténtelo de nuevo.',
);

const LocalizedText kLimousineCurrentLocationUnavailable = LocalizedText(
  nl: 'Dit adres kon niet worden bepaald. Probeer het opnieuw of typ het adres.',
  en: 'This address could not be determined. Try again or type the address.',
  fr: 'Cette adresse n’a pas pu être déterminée. Réessayez ou saisissez l’adresse.',
  es: 'No se pudo determinar esta dirección. Inténtelo de nuevo o escriba la dirección.',
);

enum LimousineLocationPermission { granted, denied, deniedForever }

enum LimousineCurrentLocationFailure {
  servicesDisabled,
  permissionDenied,
  permissionPermanentlyDenied,
  timeout,
  unavailable,
}

class LimousineCurrentLocationException implements Exception {
  const LimousineCurrentLocationException(this.failure);

  final LimousineCurrentLocationFailure failure;
}

class LimousineCurrentLocationFix {
  const LimousineCurrentLocationFix({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

LocalizedText limousineCurrentLocationMessage(
  LimousineCurrentLocationFailure failure,
) {
  switch (failure) {
    case LimousineCurrentLocationFailure.servicesDisabled:
      return kLimousineCurrentLocationServicesOff;
    case LimousineCurrentLocationFailure.permissionDenied:
      return kLimousineCurrentLocationDenied;
    case LimousineCurrentLocationFailure.permissionPermanentlyDenied:
      return kLimousineCurrentLocationDeniedForever;
    case LimousineCurrentLocationFailure.timeout:
      return kLimousineCurrentLocationTimeoutMessage;
    case LimousineCurrentLocationFailure.unavailable:
      return kLimousineCurrentLocationUnavailable;
  }
}

LimousineLocationPermission limousineMapGeolocatorPermission(
  geo.LocationPermission permission,
) {
  switch (permission) {
    case geo.LocationPermission.always:
    case geo.LocationPermission.whileInUse:
      return LimousineLocationPermission.granted;
    case geo.LocationPermission.deniedForever:
      return LimousineLocationPermission.deniedForever;
    case geo.LocationPermission.denied:
    case geo.LocationPermission.unableToDetermine:
      return LimousineLocationPermission.denied;
  }
}

class LimousineCurrentLocationPlatform {
  const LimousineCurrentLocationPlatform({
    Future<bool> Function()? isLocationServiceEnabled,
    Future<LimousineLocationPermission> Function()? checkPermission,
    Future<LimousineLocationPermission> Function()? requestPermission,
    Future<LimousineCurrentLocationFix> Function(Duration timeLimit)?
        getCurrentPosition,
    Future<bool> Function()? openAppSettings,
  }) : _isLocationServiceEnabled = isLocationServiceEnabled,
       _checkPermission = checkPermission,
       _requestPermission = requestPermission,
       _getCurrentPosition = getCurrentPosition,
       _openAppSettings = openAppSettings;

  final Future<bool> Function()? _isLocationServiceEnabled;
  final Future<LimousineLocationPermission> Function()? _checkPermission;
  final Future<LimousineLocationPermission> Function()? _requestPermission;
  final Future<LimousineCurrentLocationFix> Function(Duration timeLimit)?
      _getCurrentPosition;
  final Future<bool> Function()? _openAppSettings;

  Future<bool> isLocationServiceEnabled() {
    return (_isLocationServiceEnabled ??
        geo.Geolocator.isLocationServiceEnabled)();
  }

  Future<LimousineLocationPermission> checkPermission() async {
    if (_checkPermission != null) return _checkPermission();
    return limousineMapGeolocatorPermission(
      await geo.Geolocator.checkPermission(),
    );
  }

  Future<LimousineLocationPermission> requestPermission() async {
    if (_requestPermission != null) return _requestPermission();
    return limousineMapGeolocatorPermission(
      await geo.Geolocator.requestPermission(),
    );
  }

  Future<LimousineCurrentLocationFix> getCurrentPosition(
    Duration timeLimit,
  ) async {
    if (_getCurrentPosition != null) return _getCurrentPosition(timeLimit);
    final pos = await geo.Geolocator.getCurrentPosition(
      desiredAccuracy: geo.LocationAccuracy.best,
      timeLimit: timeLimit,
    );
    return LimousineCurrentLocationFix(
      latitude: pos.latitude,
      longitude: pos.longitude,
    );
  }

  Future<bool> openAppSettings() {
    return (_openAppSettings ?? geo.Geolocator.openAppSettings)();
  }
}

class LimousineCurrentLocationResolver {
  LimousineCurrentLocationResolver({
    required this.lookup,
    LimousineCurrentLocationPlatform? platform,
    this.positionTimeout = kLimousineCurrentLocationTimeout,
  }) : platform = platform ?? const LimousineCurrentLocationPlatform();

  final LimousinePlaceLookup lookup;
  final LimousineCurrentLocationPlatform platform;
  final Duration positionTimeout;

  Future<LimousinePlaceSuggestion?>? _inFlight;
  int positionsStarted = 0;
  int suppressedTaps = 0;
  int reverseGeocodesStarted = 0;

  bool get isResolving => _inFlight != null;

  Future<bool> openAppSettings() => platform.openAppSettings();

  Future<LimousinePlaceSuggestion?> resolve({String language = 'nl'}) {
    final existing = _inFlight;
    if (existing != null) {
      suppressedTaps += 1;
      return Future<LimousinePlaceSuggestion?>.value(null);
    }
    final future = _resolveOnce(language);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
  }

  Future<LimousinePlaceSuggestion?> _resolveOnce(String language) async {
    try {
      if (!await platform.isLocationServiceEnabled()) {
        throw const LimousineCurrentLocationException(
          LimousineCurrentLocationFailure.servicesDisabled,
        );
      }
      var permission = await platform.checkPermission();
      if (permission == LimousineLocationPermission.denied) {
        permission = await platform.requestPermission();
      }
      if (permission == LimousineLocationPermission.deniedForever) {
        throw const LimousineCurrentLocationException(
          LimousineCurrentLocationFailure.permissionPermanentlyDenied,
        );
      }
      if (permission != LimousineLocationPermission.granted) {
        throw const LimousineCurrentLocationException(
          LimousineCurrentLocationFailure.permissionDenied,
        );
      }

      positionsStarted += 1;
      final fix = await platform.getCurrentPosition(positionTimeout);
      if (!limousineCoordinatesAreValid(fix.latitude, fix.longitude)) {
        throw const LimousineCurrentLocationException(
          LimousineCurrentLocationFailure.unavailable,
        );
      }

      reverseGeocodesStarted += 1;
      final result = await lookup.reverseGeocode(
        fix.latitude,
        fix.longitude,
        language: language,
      );
      if (result.hadError || result.suggestions.isEmpty) {
        throw const LimousineCurrentLocationException(
          LimousineCurrentLocationFailure.unavailable,
        );
      }
      final suggestion = result.suggestions.first;
      if (suggestion.label.trim().isEmpty) {
        throw const LimousineCurrentLocationException(
          LimousineCurrentLocationFailure.unavailable,
        );
      }
      return suggestion;
    } on LimousineCurrentLocationException {
      rethrow;
    } on TimeoutException {
      throw const LimousineCurrentLocationException(
        LimousineCurrentLocationFailure.timeout,
      );
    } on geo.LocationServiceDisabledException {
      throw const LimousineCurrentLocationException(
        LimousineCurrentLocationFailure.servicesDisabled,
      );
    } catch (_) {
      throw const LimousineCurrentLocationException(
        LimousineCurrentLocationFailure.unavailable,
      );
    }
  }
}
