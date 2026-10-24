// Fails the Play AAB build when unused bridge ballast is still inside the
// bundle, or when a customer-facing runtime asset is missing.
//
// Usage:
//   dart run tool/verify_customer_release_assets.dart [path/to/app-release.aab]

import 'dart:io';

import 'unused_bridge_package_assets.dart';

const _requiredInApp = <String>[
  'assets/fluxidi/customer_home_airport_banner.webp',
  'assets/fluxidi/customer_home_hotel_bb_banner.webp',
  'assets/fluxidi/customer_home_events_banner.webp',
  'assets/fluxidi/customer_home_limousine_banner.webp',
  'assets/fluxidi/customer_home_hero_light.webp',
  'assets/fluxidi/customer_home_hero_dark.webp',
  'assets/fluxidi/customer_home_business_banner.webp',
  'assets/fluxidi/airport_portret_background_GSM.webp',
  'assets/fluxidi/Hotel&B&B_background.webp',
  'assets/fluxidi/fluxidi_logo.png',
  'assets/fluxidi/fluxidi_logo_horizontal_gold.png',
  'assets/fluxidi/fluxidi_logo_horizontal_dark.png',
  'assets/fluxidi/fluxidi_logo_header_gold.png',
  'assets/fluxidi/fluxidi_logo_header_dark.png',
  'assets/fluxidi/fluxidi_radar_hero.jpg',
  'assets/events/categories/all.webp',
  'assets/events/categories/music.webp',
  'assets/events/categories/sports.webp',
  'assets/events/categories/theatre.webp',
  'assets/events/categories/comedy.webp',
  'assets/events/categories/family.webp',
  'assets/events/categories/food.webp',
  'assets/events/categories/business.webp',
  'assets/events/categories/culture.webp',
  'assets/events/categories/event_category_other.webp',
  'assets/booking/modes/v1/fluxidi_mode_airport_ride_v1.webp',
  'assets/booking/airports/v1/fluxidi_airport_bru_brussels_zaventem_v1.webp',
  'assets/booking/airports/v1/fluxidi_airport_crl_charleroi_v1.webp',
  'assets/booking/airports/v1/fluxidi_airport_anr_antwerp_v1.webp',
  'assets/booking/airports/v1/fluxidi_airport_ost_ostend_bruges_v1.webp',
  'assets/booking/airports/v1/fluxidi_airport_lgg_liege_v1.webp',
  'assets/booking/airports/v1/fluxidi_airport_kjk_kortrijk_wevelgem_v1.webp',
  'assets/vehicles/fallback/v1/fluxidi_vehicle_compact_hatchback_v1.webp',
  'assets/vehicles/fallback/v1/fluxidi_vehicle_sedan_v1.webp',
  'assets/vehicles/fallback/v1/fluxidi_vehicle_station_wagon_v1.webp',
  'assets/vehicles/fallback/v1/fluxidi_vehicle_suv_crossover_v1.webp',
  'assets/vehicles/fallback/v1/fluxidi_vehicle_mpv_minivan_v1.webp',
  'assets/vehicles/fallback/v1/fluxidi_vehicle_passenger_minibus_v1.webp',
  'assets/vehicles/fallback/v1/fluxidi_vehicle_premium_limousine_v1.webp',
  'assets/vehicles/fallback/v1/fluxidi_vehicle_wheelchair_accessible_v1.webp',
  'assets/payment/logos/bancontact.png',
  'assets/payment/badges/payments_by_mollie_light.png',
  'assets/payment/providers/mollie_logo_black.png',
];

const _requiredInPackage = <String>[
  'assets/fluxidi/customer_home_airport_banner.webp',
  'assets/fluxidi/airport_portret_background_GSM.webp',
  'assets/fluxidi/fluxidi_logo.png',
  'assets/fluxidi/Hotel&B&B_background.webp',
  'assets/events/categories/all.webp',
  'assets/booking/airports/v1/fluxidi_airport_bru_brussels_zaventem_v1.webp',
  'assets/vehicles/fallback/v1/fluxidi_vehicle_sedan_v1.webp',
  'assets/payment/logos/bancontact.png',
];

void main(List<String> args) {
  final aab = File(
    args.isEmpty
        ? 'build/app/outputs/bundle/release/app-release.aab'
        : args.first,
  );
  if (!aab.existsSync()) {
    stderr.writeln('AAB not found: ${aab.path}');
    exit(2);
  }

  final listed = Process.runSync('jar', <String>['tf', aab.path]);
  if (listed.exitCode != 0) {
    stderr.writeln(listed.stderr);
    stderr.writeln('jar tf failed for ${aab.path}');
    exit(2);
  }

  final names = listed.stdout
      .toString()
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim().replaceAll('\\', '/'))
      .where((line) => line.isNotEmpty && !line.endsWith('/'))
      .toList();

  const flutterPrefix = 'base/assets/flutter_assets/';
  final flutterFiles = names
      .where((name) => name.startsWith(flutterPrefix))
      .map((name) => name.substring(flutterPrefix.length))
      .toList();

  var failed = 0;
  for (final name in flutterFiles) {
    if (name.startsWith('packages/fluxidi_tracking/')) {
      final relative = name.substring('packages/fluxidi_tracking/'.length);
      if (isUnusedBridgePackageAsset(relative)) {
        stderr.writeln('ballast still packaged: $name');
        failed++;
      }
    } else if (isUnusedCustomerAppAsset(name)) {
      stderr.writeln('ballast still packaged: $name');
      failed++;
    }
  }

  for (final key in _requiredInApp) {
    if (!flutterFiles.contains(key)) {
      stderr.writeln('missing app asset: $key');
      failed++;
    }
  }
  for (final key in _requiredInPackage) {
    final packaged = 'packages/fluxidi_tracking/$key';
    if (!flutterFiles.contains(packaged)) {
      stderr.writeln('missing bridged asset: $packaged');
      failed++;
    }
  }

  if (failed > 0) {
    stderr.writeln('$failed customer release asset checks failed');
    exit(1);
  }
  stdout.writeln(
    'customer release assets verified '
    '(${flutterFiles.length} flutter_assets files, no unused bridge ballast)',
  );
}
