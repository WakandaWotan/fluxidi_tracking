import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_plan_airport_cards.dart';
import 'package:fluxidi_tracking/company/company_plan_ride_mode.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_fallback.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/events/event_models.dart';
import 'package:fluxidi_tracking/limousine/limousine_service_capability.dart';
import 'package:fluxidi_tracking/payment/payment_method_logo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> expectAsset(String key) async {
    expect(
      (await rootBundle.load(key)).lengthInBytes,
      greaterThan(0),
      reason: key,
    );
  }

  test('dynamic customer resolvers load their assets without fallback files', () async {
    for (final category in CompanyPlanVehicleCategory.values) {
      await expectAsset(companyPlanVehicleFallbackAsset(category));
    }
    for (final iata in const <String>['BRU', 'CRL', 'ANR', 'OST', 'LGG', 'KJK']) {
      await expectAsset(companyPlanAirportCardAsset(iata));
    }
    await expectAsset(companyPlanAirportCardAsset('XXX'));
    await expectAsset(kCompanyPlanAirportModeAsset);
    await expectAsset(kLimousineMarketplaceHeroAsset);

    const categoryKeys = <String>[
      'all',
      EventCategoryKey.music,
      EventCategoryKey.sport,
      EventCategoryKey.theater,
      EventCategoryKey.comedy,
      EventCategoryKey.family,
      EventCategoryKey.food,
      EventCategoryKey.business,
      EventCategoryKey.culture,
      EventCategoryKey.other,
      EventCategoryKey.airport,
    ];
    for (final key in categoryKeys) {
      await expectAsset(_eventCategoryTileAssetPath(key));
    }

    for (final method in const <String>[
      'bancontact',
      'ideal',
      'creditcard',
      'paypal',
    ]) {
      final logo = paymentMethodLogoAssetForId(method);
      if (logo != null) await expectAsset(logo);
    }
  });

  test('Home, hotels, radar and header assets load from the customer bundle', () async {
    const keys = <String>[
      'assets/fluxidi/customer_home_airport_banner.webp',
      'assets/fluxidi/customer_home_hotel_bb_banner.webp',
      'assets/fluxidi/customer_home_events_banner.webp',
      'assets/fluxidi/customer_home_limousine_banner.webp',
      'assets/fluxidi/customer_home_hero_light.webp',
      'assets/fluxidi/customer_home_hero_dark.webp',
      'assets/fluxidi/customer_home_business_banner.webp',
      'assets/fluxidi/customer_home_business_banner_dark.webp',
      'assets/fluxidi/airport_portret_background_GSM.webp',
      'assets/fluxidi/Hotel&B&B_background.webp',
      'assets/fluxidi/evenementen_picture_landscape_tablet.webp',
      'assets/fluxidi/zakelijke_picture_landscape_tablet.webp',
      'assets/fluxidi/fluxidi_logo.png',
      'assets/fluxidi/fluxidi_logo_horizontal_gold.png',
      'assets/fluxidi/fluxidi_logo_horizontal_dark.png',
      'assets/fluxidi/fluxidi_logo_header_gold.png',
      'assets/fluxidi/fluxidi_logo_header_dark.png',
      'assets/fluxidi/fluxidi_radar_hero.jpg',
    ];
    for (final key in keys) {
      await expectAsset(key);
    }
  });

  test('bridged package copies of the same runtime keys remain loadable', () async {
    const keys = <String>[
      'packages/fluxidi_tracking/assets/fluxidi/customer_home_airport_banner.webp',
      'packages/fluxidi_tracking/assets/fluxidi/airport_portret_background_GSM.webp',
      'packages/fluxidi_tracking/assets/fluxidi/fluxidi_logo.png',
      'packages/fluxidi_tracking/assets/events/categories/all.webp',
      'packages/fluxidi_tracking/assets/booking/airports/v1/fluxidi_airport_bru_brussels_zaventem_v1.webp',
      'packages/fluxidi_tracking/assets/vehicles/fallback/v1/fluxidi_vehicle_sedan_v1.webp',
      'packages/fluxidi_tracking/assets/payment/logos/bancontact.png',
    ];
    for (final key in keys) {
      await expectAsset(key);
    }
  });
}

String _eventCategoryTileAssetPath(String categoryKey) {
  // Same resolver as EventsPage._categoryTileAssetPath.
  switch (categoryKey) {
    case 'all':
      return 'assets/events/categories/all.webp';
    case EventCategoryKey.music:
      return 'assets/events/categories/music.webp';
    case EventCategoryKey.sport:
      return 'assets/events/categories/sports.webp';
    case EventCategoryKey.theater:
      return 'assets/events/categories/theatre.webp';
    case EventCategoryKey.comedy:
      return 'assets/events/categories/comedy.webp';
    case EventCategoryKey.family:
      return 'assets/events/categories/family.webp';
    case EventCategoryKey.food:
      return 'assets/events/categories/food.webp';
    case EventCategoryKey.business:
      return 'assets/events/categories/business.webp';
    case EventCategoryKey.culture:
      return 'assets/events/categories/culture.webp';
    case EventCategoryKey.other:
      return 'assets/events/categories/event_category_other.webp';
    default:
      return 'assets/events/categories/all.webp';
  }
}
