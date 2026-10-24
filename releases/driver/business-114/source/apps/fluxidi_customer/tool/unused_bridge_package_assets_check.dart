import 'dart:io';

import 'unused_bridge_package_assets.dart';

void main() {
  const kept = <String>[
    'assets/fluxidi/customer_home_airport_banner.webp',
    'assets/fluxidi/airport_portret_background_GSM.webp',
    'assets/fluxidi/fluxidi_logo.png',
    'assets/fluxidi/Hotel&B&B_background.webp',
    'assets/events/categories/all.webp',
    'assets/events/categories/event_category_other.webp',
    'assets/booking/airports/v1/fluxidi_airport_bru_brussels_zaventem_v1.webp',
    'assets/vehicles/fallback/v1/fluxidi_vehicle_sedan_v1.webp',
    'assets/payment/logos/bancontact.png',
    'assets/payment/badges/payments_by_mollie_light.png',
  ];
  const unused = <String>[
    'assets/Midday Gold Chauffeur/driver_my_rides_midday_gold.webp',
    'assets/Corporate BLEU Compagny/company_ai_dispatch_corporate_blue.webp',
    'assets/\u{1F947} Fluxidi Neon Rush/company_header_fleet_neon_rush.webp',
    'assets/business_themes/brand_signature_gold/fluxidi_gold_chiron.webp',
    'assets_card5_themes/card5.webp',
    'assets/fluxidi_navigation_signs_v3/png/nl/turn_left.png',
    'assets/navigation/driver_taxi_top.png',
    'assets/fluxidi/onboarding/card1_welcome_tablet_portrait_bg.mp4',
    'assets/fluxidi/manuals/fluxidi_bedrijfspagina_handleiding_nl_v1_0_final.pdf',
    'assets/fluxidi/role_driver_bg.webp',
    'assets/fluxidi/driver_action_street_ride.webp',
    'assets/fluxidi/background_sign_in_page_phone.webp',
    'assets/fluxidi/bookings_background_company.webp',
    'assets/events/categories/event_category_all.webp',
    'assets/payment/png/cash.png',
  ];
  var failed = 0;
  for (final path in kept) {
    if (isUnusedBridgePackageAsset(path)) {
      stderr.writeln('expected keep: $path');
      failed++;
    }
  }
  for (final path in unused) {
    if (!isUnusedBridgePackageAsset(path)) {
      stderr.writeln('expected drop: $path');
      failed++;
    }
  }
  if (failed > 0) {
    stderr.writeln('$failed unused-bridge-asset checks failed');
    exit(1);
  }
  stdout.writeln('unused-bridge-asset checks passed');
}
