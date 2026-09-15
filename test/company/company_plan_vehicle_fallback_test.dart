import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_ride_mode.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_fallback.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_visual.dart';

void main() {
  test('manifest aliases map to the eight category assets', () {
    expect(
      companyPlanVehicleFallbackAsset(CompanyPlanVehicleCategory.compact),
      kCompanyPlanFallbackCompact,
    );
    expect(
      companyPlanVehicleCategoryFromAlias('hatchback'),
      CompanyPlanVehicleCategory.compact,
    );
    expect(
      companyPlanVehicleCategoryFromAlias('estate'),
      CompanyPlanVehicleCategory.breakWagon,
    );
    expect(
      companyPlanVehicleCategoryFromAlias('van_8_plus'),
      CompanyPlanVehicleCategory.minibus,
    );
    expect(companyPlanVehicleCategoryFromAlias('airport_ride'), isNull);
    expect(companyPlanVehicleCategoryFromAlias('electric'), isNull);
    expect(parseCompanyPlanVehicleType('airport'), isNull);
    expect(companyPlanRideModeIsAirport('airport_ride'), isTrue);
  });

  test('capacity chooses minivan or minibus unless type is explicit', () {
    expect(
      companyPlanVehicleFallbackCategory(<String, dynamic>{
        'passenger_capacity': 7,
      }),
      CompanyPlanVehicleCategory.minivan,
    );
    expect(
      companyPlanVehicleFallbackCategory(<String, dynamic>{
        'passenger_capacity': 8,
      }),
      CompanyPlanVehicleCategory.minibus,
    );
    expect(
      companyPlanVehicleFallbackCategory(<String, dynamic>{
        'vehicle_type': 'sedan',
        'passenger_capacity': 8,
      }),
      CompanyPlanVehicleCategory.sedan,
    );
  });

  test('ops bookable list is only active company vehicle types', () {
    final empty = companyPlanBookableCategories(
      vehicles: const <Map<String, dynamic>>[],
      passengers: 1,
    );
    expect(empty, isEmpty);
    final fleet = companyPlanBookableCategories(
      vehicles: const <Map<String, dynamic>>[
        <String, dynamic>{
          'vehicle_id': 'vh_1',
          'vehicle_name': 'E-Klasse',
          'passenger_capacity': 3,
          'is_active': true,
        },
        <String, dynamic>{
          'vehicle_id': 'vh_2',
          'vehicle_name': 'Vito',
          'passenger_capacity': 7,
          'is_active': true,
        },
        <String, dynamic>{
          'vehicle_id': 'vh_x',
          'vehicle_name': 'Ghost',
          'tier': 'premium',
          'is_active': false,
        },
      ],
      passengers: 1,
    );
    expect(fleet, contains(CompanyPlanVehicleCategory.sedan));
    expect(fleet, contains(CompanyPlanVehicleCategory.minivan));
    expect(fleet, isNot(contains(CompanyPlanVehicleCategory.premium)));
    expect(fleet, isNot(contains(null)));
  });

  testWidgets('generic category cards use contain and bundled webp', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: [
              for (final category in CompanyPlanVehicleCategory.values)
                SizedBox(
                  width: 160,
                  child: CompanyPlanVehicleVisual(
                    type: companyPlanVehicleTypeForCategory(category),
                    category: category,
                    semanticLabel: companyPlanVehicleCategoryLabel(
                      category,
                      AppLanguage.nl,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(8));
    for (final image in images) {
      expect(image.fit, BoxFit.contain);
      expect(image.image, isA<AssetImage>());
      final asset = image.image as AssetImage;
      expect(asset.assetName, startsWith(kCompanyPlanVehicleFallbackDir));
    }
  });

  testWidgets('airport ride card uses the mode webp with contain', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompanyPlanAirportModeVisual(
            semanticLabel: 'Luchthavenrit',
            height: 120,
          ),
        ),
      ),
    );
    await tester.pump();
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);
    expect(image.image, isA<AssetImage>());
    expect(
      (image.image as AssetImage).assetName,
      kCompanyPlanAirportModeAsset,
    );
    expect(find.byIcon(kCompanyPlanAirportModeIcon), findsNothing);
  });

  testWidgets('compact airport control stays a vector icon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompanyPlanAirportModeVisual(
            semanticLabel: 'Luchthavenrit',
            compact: true,
          ),
        ),
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(kCompanyPlanAirportModeIcon), findsOneWidget);
  });
}
