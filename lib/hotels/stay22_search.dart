import 'stay22_europe_countries.dart';

const String kStay22SearchbarHost = 'www.stay22.com';
const String kStay22SearchbarPath = '/allez/searchbar';

const String kStay22CampaignHotelsSearch = 'fluxidi_hotels_search';
const String kStay22CampaignFeaturedStay = 'fluxidi_featured_stay';
const String kStay22CampaignSavedStay = 'fluxidi_saved_stay';

const Set<String> kStay22AllowedQueryKeys = <String>{
  'aid',
  'address',
  'checkin',
  'checkout',
  'adults',
  'children',
  'lang',
  'currency',
  'campaign',
  'lat',
  'lng',
};

enum Stay22SearchKind { general, featured, saved }

enum Stay22SearchIssue {
  missingDestination,
  pastCheckin,
  checkoutNotAfterCheckin,
  adultsBelowOne,
  negativeChildren,
}

class Stay22SearchRequest {
  const Stay22SearchRequest({
    required this.address,
    required this.adults,
    required this.children,
    required this.languageCode,
    required this.currency,
    required this.campaign,
    this.checkin,
    this.checkout,
    this.latitude,
    this.longitude,
  });

  final String address;
  final int adults;
  final int children;
  final String languageCode;
  final String currency;
  final String campaign;
  final DateTime? checkin;
  final DateTime? checkout;
  final double? latitude;
  final double? longitude;
}

class Stay22SearchValidation {
  const Stay22SearchValidation({
    required this.issues,
    required this.requireDates,
  });

  final List<Stay22SearchIssue> issues;
  final bool requireDates;

  bool get canLaunch => issues.isEmpty;
}

String stay22CampaignFor(Stay22SearchKind kind) {
  switch (kind) {
    case Stay22SearchKind.general:
      return kStay22CampaignHotelsSearch;
    case Stay22SearchKind.featured:
      return kStay22CampaignFeaturedStay;
    case Stay22SearchKind.saved:
      return kStay22CampaignSavedStay;
  }
}

bool stay22CampaignUsesUnderscores(String campaign) {
  final value = campaign.trim();
  return value.isNotEmpty && !value.contains('-') && value.contains('_');
}

String stay22Ymd(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

DateTime stay22DateOnly(DateTime date) =>
    DateTime(date.year, date.month, date.day);

String stay22LangHint(String languageCode) {
  switch (languageCode.trim().toLowerCase()) {
    case 'fr':
      return 'fr';
    case 'es':
      return 'es';
    case 'en':
      return 'en';
    case 'nl':
    default:
      return 'nl';
  }
}

/// Safe currency policy: EUR for euro-area destinations, GBP for the UK,
/// otherwise the existing Fluxidi default EUR.
String stay22CurrencyForCountry(String? countryCode) {
  final code = (countryCode ?? '').trim().toUpperCase();
  if (code == 'GB') return 'GBP';
  if (code.isEmpty || kStay22EuroAreaCountryCodes.contains(code)) {
    return 'EUR';
  }
  return 'EUR';
}

String composeStay22Address({
  String? freeText,
  String? propertyName,
  String? city,
  String? region,
  String? country,
}) {
  final parts = <String>[];

  bool containsNormalized(String haystack, String needle) {
    final left = haystack.trim().toLowerCase();
    final right = needle.trim().toLowerCase();
    if (left.isEmpty || right.isEmpty) return false;
    return left == right || left.contains(right);
  }

  void add(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return;
    if (parts.any((part) => containsNormalized(part, value))) return;
    if (parts.any((part) => containsNormalized(value, part))) {
      final index = parts.indexWhere((part) => containsNormalized(value, part));
      if (index >= 0 && value.length > parts[index].length) {
        parts[index] = value;
      }
      return;
    }
    parts.add(value);
  }

  add(freeText);
  add(propertyName);
  add(city);
  add(region);
  add(country);
  return parts.join(', ');
}

Stay22SearchValidation validateStay22Search({
  required String address,
  required int adults,
  required int children,
  DateTime? checkin,
  DateTime? checkout,
  DateTime? now,
  bool requireDates = true,
}) {
  final issues = <Stay22SearchIssue>[];
  if (address.trim().isEmpty) {
    issues.add(Stay22SearchIssue.missingDestination);
  }
  if (adults < 1) issues.add(Stay22SearchIssue.adultsBelowOne);
  if (children < 0) issues.add(Stay22SearchIssue.negativeChildren);

  final today = stay22DateOnly(now ?? DateTime.now());
  final hasCheckin = checkin != null;
  final hasCheckout = checkout != null;
  if (hasCheckin != hasCheckout || (requireDates && !hasCheckin)) {
    issues.add(Stay22SearchIssue.checkoutNotAfterCheckin);
  }
  if (hasCheckin) {
    if (stay22DateOnly(checkin).isBefore(today)) {
      issues.add(Stay22SearchIssue.pastCheckin);
    }
  }
  if (hasCheckin && hasCheckout) {
    if (!stay22DateOnly(checkout).isAfter(stay22DateOnly(checkin))) {
      issues.add(Stay22SearchIssue.checkoutNotAfterCheckin);
    }
  }
  return Stay22SearchValidation(issues: issues, requireDates: requireDates);
}

bool stay22HasVerifiedCoordinates(double? latitude, double? longitude) {
  if (latitude == null || longitude == null) return false;
  if (!latitude.isFinite || !longitude.isFinite) return false;
  if (latitude < -90 || latitude > 90) return false;
  if (longitude < -180 || longitude > 180) return false;
  if (latitude == 0 && longitude == 0) return false;
  return true;
}

/// Builds a Stay22 Allez searchbar URI. [aid] must be supplied by the caller
/// from the existing runtime configuration. Tests inject a dummy value.
Uri buildStay22SearchbarUri({
  required String aid,
  required Stay22SearchRequest request,
}) {
  final affiliateId = aid.trim();
  if (affiliateId.isEmpty) {
    throw ArgumentError('Stay22 aid is required');
  }
  final params = <String, String>{
    'aid': affiliateId,
    'address': request.address.trim(),
    'adults': request.adults.toString(),
    'children': request.children.toString(),
    'lang': stay22LangHint(request.languageCode),
    'currency': request.currency.trim().toUpperCase(),
    'campaign': request.campaign.trim(),
  };
  if (request.checkin != null) {
    params['checkin'] = stay22Ymd(request.checkin!);
  }
  if (request.checkout != null) {
    params['checkout'] = stay22Ymd(request.checkout!);
  }
  if (stay22HasVerifiedCoordinates(request.latitude, request.longitude)) {
    params['lat'] = request.latitude!.toStringAsFixed(6);
    params['lng'] = request.longitude!.toStringAsFixed(6);
  }
  return Uri.https(kStay22SearchbarHost, kStay22SearchbarPath, params);
}

String redactStay22Sensitive(String raw) {
  return raw
      .replaceAllMapped(
        RegExp(r'([?&]aid=)[^&]+', caseSensitive: false),
        (match) => '${match[1]}[REDACTED_AID]',
      )
      .replaceAll(
        RegExp(r'https://www\.stay22\.com', caseSensitive: false),
        '[REDACTED_STAY22_HOST]',
      );
}

String stay22SearchIssueLabel(Stay22SearchIssue issue, String languageCode) {
  switch (issue) {
    case Stay22SearchIssue.missingDestination:
      return _label(
        languageCode,
        nl: 'Kies of typ eerst een bestemming.',
        en: 'Choose or type a destination first.',
        fr: 'Choisissez ou saisissez d’abord une destination.',
        es: 'Elige o escribe primero un destino.',
      );
    case Stay22SearchIssue.pastCheckin:
      return _label(
        languageCode,
        nl: 'De check-in kan niet in het verleden liggen.',
        en: 'Check-in cannot be in the past.',
        fr: 'L’arrivée ne peut pas être dans le passé.',
        es: 'La entrada no puede estar en el pasado.',
      );
    case Stay22SearchIssue.checkoutNotAfterCheckin:
      return _label(
        languageCode,
        nl: 'De check-out moet later zijn dan de check-in.',
        en: 'Check-out must be later than check-in.',
        fr: 'Le départ doit être postérieur à l’arrivée.',
        es: 'La salida debe ser posterior a la entrada.',
      );
    case Stay22SearchIssue.adultsBelowOne:
      return _label(
        languageCode,
        nl: 'Er is minstens 1 volwassene nodig.',
        en: 'At least 1 adult is required.',
        fr: 'Au moins 1 adulte est requis.',
        es: 'Se requiere al menos 1 adulto.',
      );
    case Stay22SearchIssue.negativeChildren:
      return _label(
        languageCode,
        nl: 'Het aantal kinderen kan niet negatief zijn.',
        en: 'Children cannot be negative.',
        fr: 'Le nombre d’enfants ne peut pas être négatif.',
        es: 'El número de niños no puede ser negativo.',
      );
  }
}

String stay22RoomsClarification(String languageCode) {
  return _label(
    languageCode,
    nl: 'Het aantal kamers bevestig je bij de aanbieder.',
    en: 'You confirm the number of rooms with the provider.',
    fr: 'Vous confirmez le nombre de chambres chez le prestataire.',
    es: 'Confirmas el número de habitaciones con el proveedor.',
  );
}

String stay22LiveSearchTitle(String languageCode) {
  return _label(
    languageCode,
    nl: 'Live verblijven zoeken',
    en: 'Search live stays',
    fr: 'Rechercher des hébergements en direct',
    es: 'Buscar alojamientos en vivo',
  );
}

String stay22LiveSearchCta(String languageCode) {
  return _label(
    languageCode,
    nl: 'Live verblijven zoeken',
    en: 'Search live stays',
    fr: 'Rechercher des hébergements en direct',
    es: 'Buscar alojamientos en vivo',
  );
}

String stay22FeaturedBrowseTitle(String languageCode) {
  return _label(
    languageCode,
    nl: 'Uitgelichte verblijven ter inspiratie',
    en: 'Featured stays for inspiration',
    fr: 'Hébergements en vedette pour s’inspirer',
    es: 'Alojamientos destacados de inspiración',
  );
}

String stay22LiveSearchSubtitle(String languageCode) {
  return _label(
    languageCode,
    nl: 'Hotels, B&B’s en vakantiewoningen openen bij Stay22-partners. Dit is live beschikbaarheid, geen Fluxidi-inventaris.',
    en: 'Hotels, B&Bs and vacation rentals open with Stay22 partners. This is live availability, not Fluxidi inventory.',
    fr: 'Hôtels, B&B et locations de vacances s’ouvrent chez les partenaires Stay22. Il s’agit de disponibilités en direct, pas de l’inventaire Fluxidi.',
    es: 'Hoteles, B&B y alojamientos vacacionales se abren con socios Stay22. Es disponibilidad en vivo, no inventario de Fluxidi.',
  );
}

String stay22FeaturedCountLabel(int count, String languageCode) {
  return _label(
    languageCode,
    nl: '$count uitgelichte verblijven',
    en: '$count featured stays',
    fr: '$count hébergements en vedette',
    es: '$count alojamientos destacados',
  );
}

String stay22FeaturedFilterLabel(int count, String languageCode) {
  return _label(
    languageCode,
    nl: '$count uitgelichte verblijven in deze selectie',
    en: '$count featured stays in this selection',
    fr: '$count hébergements en vedette dans cette sélection',
    es: '$count alojamientos destacados en esta selección',
  );
}

String stay22MoreFeaturedStaysLabel(String languageCode) {
  return _label(
    languageCode,
    nl: 'Meer uitgelichte verblijven',
    en: 'More featured stays',
    fr: 'Plus d’hébergements sélectionnés',
    es: 'Más alojamientos destacados',
  );
}

String stay22MoreFeaturedStaysWaitingLabel(String languageCode) {
  return _label(
    languageCode,
    nl: 'Nog even wachten om meer uitgelichte verblijven te laden',
    en: 'Please wait a moment to load more featured stays',
    fr: 'Patientez un instant pour charger plus d’hébergements sélectionnés',
    es: 'Espera un momento para cargar más alojamientos destacados',
  );
}

String stay22MoreFeaturedStaysLoadingLabel(String languageCode) {
  return _label(
    languageCode,
    nl: 'Meer uitgelichte verblijven laden…',
    en: 'Loading more featured stays…',
    fr: 'Chargement d’autres hébergements sélectionnés…',
    es: 'Cargando más alojamientos destacados…',
  );
}

String stay22MoreFeaturedStaysRetryLabel(String languageCode) {
  return _label(
    languageCode,
    nl: 'Opnieuw proberen',
    en: 'Try again',
    fr: 'Réessayer',
    es: 'Reintentar',
  );
}

String stay22MajorCitiesPickerTitle(String languageCode) {
  return _label(
    languageCode,
    nl: 'Grote steden',
    en: 'Major cities',
    fr: 'Grandes villes',
    es: 'Grandes ciudades',
  );
}

String stay22MajorCitiesFieldGuidance(String languageCode) {
  return _label(
    languageCode,
    nl: 'Kies een grote stad of typ een stad of regio. Dit is geen volledige stedenlijst.',
    en: 'Choose a major city or type a city or region. This is not a complete city list.',
    fr: 'Choisissez une grande ville ou saisissez une ville ou une région. Ce n’est pas une liste complète.',
    es: 'Elige una gran ciudad o escribe una ciudad o región. No es una lista completa.',
  );
}

String stay22FeaturedExplanation(String languageCode) {
  return _label(
    languageCode,
    nl: 'Deze kaarten zijn uitgelichte inspiratie. Live prijzen en beschikbaarheid openen bij Stay22-partners.',
    en: 'These cards are featured inspiration. Live prices and availability open with Stay22 partners.',
    fr: 'Ces fiches sont une inspiration mise en avant. Les prix et disponibilités en direct s’ouvrent chez les partenaires Stay22.',
    es: 'Estas fichas son inspiración destacada. Los precios y la disponibilidad en vivo se abren con socios Stay22.',
  );
}

String stay22EmptyFeaturedTitle(String languageCode) {
  return _label(
    languageCode,
    nl: 'Geen uitgelichte inspiratie voor deze selectie',
    en: 'No featured inspiration for this selection',
    fr: 'Aucune inspiration mise en avant pour cette sélection',
    es: 'No hay inspiración destacada para esta selección',
  );
}

String stay22EmptyFeaturedBody(String languageCode) {
  return _label(
    languageCode,
    nl: 'Er is geen uitgelichte Fluxidi-inspiratie voor deze keuze. Live verblijven zoeken kan nog via de Stay22-knop hierboven.',
    en: 'No featured Fluxidi inspiration is available for this selection. You can still search live stays with the Stay22 button above.',
    fr: 'Aucune inspiration Fluxidi n’est disponible pour cette sélection. Vous pouvez encore rechercher des hébergements en direct avec le bouton Stay22 ci-dessus.',
    es: 'No hay inspiración destacada de Fluxidi para esta selección. Aún puedes buscar alojamientos en vivo con el botón Stay22 de arriba.',
  );
}

String stay22CityRegionGuidance(String languageCode) {
  return _label(
    languageCode,
    nl: 'Vul een stad of regio in, bijvoorbeeld Lissabon.',
    en: 'Enter a city or region, for example Lisbon.',
    fr: 'Saisissez une ville ou une région, par exemple Lisbonne.',
    es: 'Introduce una ciudad o región, por ejemplo Lisboa.',
  );
}

String stay22UnseededGeoControlHint(String languageCode) {
  return _label(
    languageCode,
    nl: 'Geen vaste steden- of regio lijst. Gebruik het veld stad of regio.',
    en: 'No fixed city or region list. Use the city or region field.',
    fr: 'Pas de liste fixe de villes ou régions. Utilisez le champ ville ou région.',
    es: 'No hay una lista fija de ciudades o regiones. Usa el campo de ciudad o región.',
  );
}

String stay22BroadInspirationLabel(String languageCode) {
  return _label(
    languageCode,
    nl: 'Brede uitgelichte inspiratie voor dit land. Dit is geen volledige inventaris.',
    en: 'Broad featured inspiration for this country. This is not complete inventory.',
    fr: 'Inspiration mise en avant à l’échelle du pays. Ce n’est pas un inventaire complet.',
    es: 'Inspiración destacada amplia para este país. No es un inventario completo.',
  );
}

String stay22LaunchFailureLabel(String languageCode) {
  return _label(
    languageCode,
    nl: 'Kon de partnerbeschikbaarheid niet openen. Controleer je browser en probeer opnieuw.',
    en: 'Could not open partner availability. Check your browser and try again.',
    fr: 'Impossible d’ouvrir la disponibilité partenaire. Vérifiez votre navigateur et réessayez.',
    es: 'No se pudo abrir la disponibilidad del socio. Comprueba el navegador e inténtalo de nuevo.',
  );
}

String stay22ExternalActionSemantics(String languageCode) {
  return _label(
    languageCode,
    nl: 'Opent live beschikbaarheid bij een Stay22-partner in de browser.',
    en: 'Opens live availability with a Stay22 partner in the browser.',
    fr: 'Ouvre la disponibilité en direct chez un partenaire Stay22 dans le navigateur.',
    es: 'Abre la disponibilidad en vivo de un socio Stay22 en el navegador.',
  );
}

String _label(
  String languageCode, {
  required String nl,
  required String en,
  required String fr,
  required String es,
}) {
  switch (languageCode.trim().toLowerCase()) {
    case 'en':
      return en;
    case 'fr':
      return fr;
    case 'es':
      return es;
    case 'nl':
    default:
      return nl;
  }
}
