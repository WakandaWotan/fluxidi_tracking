/// Isolated Brand Signature Gold artwork. Existing business themes never
/// resolve through this file.
const String kBrandSignatureGoldAssetDir =
    'assets/business_themes/brand_signature_gold';

const String kBrandSignatureGoldPackMarker = 'brand_signature_gold';

const List<String> kBrandSignatureGoldAssetKeys = <String>[
  'customers',
  'chiron',
  'documents',
  'drivers',
  'more',
  'navigation',
  'payments',
  'planning',
  'vehicles',
  'settings',
  'booking_link',
  'demand_radar',
  'theme',
  'ai_dispatch',
];

const Map<String, String> kBrandSignatureGoldActionAssetKeys = <String, String>{
  'settings': 'settings',
  'payments': 'payments',
  'vehicles': 'vehicles',
  'chiron': 'chiron',
  'documents': 'documents',
  'customers': 'customers',
  'drivers': 'drivers',
  'demand_radar': 'demand_radar',
  'booking_link': 'booking_link',
  'planning': 'planning',
  'ai_dispatch': 'ai_dispatch',
  'theme': 'theme',
  'more': 'more',
  'navigation': 'navigation',
};

String brandSignatureGoldAssetPath(String key) =>
    '$kBrandSignatureGoldAssetDir/fluxidi_gold_$key.webp';

const String kBrandSignatureGoldThemeAsset =
    '$kBrandSignatureGoldAssetDir/fluxidi_gold_theme.webp';

const String kBrandSignatureGoldSettingsAsset =
    '$kBrandSignatureGoldAssetDir/fluxidi_gold_settings.webp';

bool isBrandSignatureGoldAssetPath(String asset) =>
    asset.toLowerCase().contains(kBrandSignatureGoldPackMarker);

bool isPhotographicBusinessDashboardAsset(String asset) {
  final lower = asset.toLowerCase();
  return lower.contains('zakelijke_tablet_header_foto') ||
      lower.contains('_background_company') ||
      lower.contains('company_header_') ||
      lower.contains('company_bookings_') ||
      lower.contains('company_settings_') ||
      lower.contains('company_vehicles_') ||
      lower.contains('company_drivers_') ||
      lower.contains('company_driver_view_') ||
      lower.contains('company_demand_radar_') ||
      lower.contains('company_share_booking') ||
      lower.contains('company_ai_dispatch_') ||
      lower.contains('company_chiron_') ||
      lower.contains('company_plan_') ||
      lower.contains('company_subscriptions_') ||
      lower.contains('company_header_fleet');
}
