// Classifies assets that Flutter copies from the fluxidi_tracking package
// into the standalone customer app. The golden app still declares chauffeur,
// company, navigation and orientation artwork in its own pubspec; depending
// on that package therefore ships those files unless this filter removes
// them from the customer bundle only.
//
// Source files in the repo-root assets/ tree are never deleted.
//
// Keep-list is based on runtime resolvers, not only literal strings:
//   companyPlanVehicleFallbackAsset(category)
//   companyPlanAirportCardAsset(iata) + kCompanyPlanAirportModeAsset
//   EventsPage._categoryTileAssetPath(categoryKey)
//   HotelsPage._approvedAssetPath (approved_asset:<path>)
//   paymentMethodLogoAssetForId / Mollie badge+provider
//   kLimousineMarketplaceHeroAsset
//   kPackagedFluxidiLogoAsset and header/radar marks
// Customer themes are Color palettes only (CustomerThemeVariant).

/// Package-relative prefixes that the customer app never shows.
const unusedBridgePackagePrefixes = <String>[
  'assets/Midday Gold Chauffeur/',
  'assets/Midnight Bleu Chauffeur/',
  'assets/Light Emerald Chauffeur/',
  'assets/Corporate BLEU Compagny/',
  'assets/Clean & Professional Compagny/',
  'assets/Emerald_Ivory_Company/',
  'assets/business_themes/',
  'assets_card5_themes/',
  'assets/fluxidi_navigation_signs_v3/',
  'assets/navigation/',
  'assets/fluxidi/onboarding/',
  'assets/fluxidi/manuals/',
  'assets/fluxidi/brochures/',
  'assets/payment/png/',
  'assets/fluxidi/payments/',
];

/// Customer-facing files under packages/fluxidi_tracking/assets/fluxidi/.
const keptBridgeFluxidiFiles = <String>{
  'fluxidi_logo.png',
  'fluxidi_logo_horizontal_dark.png',
  'fluxidi_logo_horizontal_gold.png',
  'fluxidi_logo_header_dark.png',
  'fluxidi_logo_header_gold.png',
  'fluxidi_hero_taxi.png',
  'fluxidi_start_background.png',
  'fluxidi_customer_home_hero.webp',
  'fluxidi_customer_header_picture_landscape_tablet.webp',
  'customer_home_hero_light.webp',
  'customer_home_hero_dark.webp',
  'customer_home_airport_banner.webp',
  'customer_home_hotel_bb_banner.webp',
  'customer_home_events_banner.webp',
  'customer_home_limousine_banner.webp',
  'customer_home_business_banner.webp',
  'customer_home_business_banner_dark.webp',
  'airport_portret_background_GSM.webp',
  'Hotel&B&B_background.webp',
  'evenementen_picture_landscape_tablet.webp',
  'fluxidi_event_crowd_night.jpg',
  'fluxidi_business_briefcase_night.jpg',
  'zakelijke_picture_landscape_tablet.webp',
  'zakelijke_tablet_header_foto.webp',
  'zakelijke_tablet_header_foto_landscape.webp',
  'zakelijke_tablet_header_foto_landscape_daytime.webp',
  'fluxidi_radar_hero.jpg',
};

/// Event images the events pages actually resolve.
const keptEventCategoryFiles = <String>{
  'all.webp',
  'music.webp',
  'sports.webp',
  'theatre.webp',
  'comedy.webp',
  'family.webp',
  'food.webp',
  'business.webp',
  'culture.webp',
  'event_category_other.webp',
};

bool isUnusedNeonRushPath(String relativePosix) {
  return relativePosix.contains('Fluxidi Neon Rush');
}

/// [relativePosix] is the path under `packages/fluxidi_tracking/`.
bool isUnusedBridgePackageAsset(String relativePosix) {
  final path = relativePosix.replaceAll('\\', '/');
  if (isUnusedNeonRushPath(path)) return true;
  for (final prefix in unusedBridgePackagePrefixes) {
    if (path == prefix.substring(0, prefix.length - 1) ||
        path.startsWith(prefix)) {
      return true;
    }
  }
  const fluxidiDir = 'assets/fluxidi/';
  if (path.startsWith(fluxidiDir) && !path.substring(fluxidiDir.length).contains('/')) {
    return !keptBridgeFluxidiFiles.contains(path.substring(fluxidiDir.length));
  }
  const eventsDir = 'assets/events/categories/';
  if (path.startsWith(eventsDir) && !path.substring(eventsDir.length).contains('/')) {
    return !keptEventCategoryFiles.contains(path.substring(eventsDir.length));
  }
  return false;
}

/// App-owned copies that Flutter also bundles next to the package assets.
bool isUnusedCustomerAppAsset(String relativePosix) {
  final path = relativePosix.replaceAll('\\', '/');
  if (path.startsWith('assets/payment/png/')) return true;
  const eventsDir = 'assets/events/categories/';
  if (path.startsWith(eventsDir) && !path.substring(eventsDir.length).contains('/')) {
    return !keptEventCategoryFiles.contains(path.substring(eventsDir.length));
  }
  return false;
}
