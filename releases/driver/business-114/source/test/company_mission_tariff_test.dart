import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_mission_tariff_page.dart';

void main() {
  test(
    'profile persists company tariff and explicit clearing without creating a default tariff',
    () {
      final empty = BackendBusinessProfile.defaults();
      expect(empty.missionTariff, isNull);
      expect(empty.toJson().containsKey('mission_tariff'), isFalse);
      final draft = taxiMarioMissionTariffDraft();
      draft['route_provider'] = 'mapbox';
      draft['price_rounding'] = 'nearest_euro';
      final loaded = BackendBusinessProfile.fromJson({'mission_tariff': draft});
      expect(loaded.toJson()['mission_tariff'], draft);
      expect(loaded.copyWith(companyName: 'Same company').missionTariff, draft);
      final clear = loaded.copyWith(clearMissionTariff: true);
      expect(clear.toJson().containsKey('mission_tariff'), isTrue);
      expect(clear.toJson()['mission_tariff'], isNull);
      final explicit = BackendBusinessProfile.fromJson({
        'mission_tariff': null,
      });
      expect(explicit.missionTariff, isNull);
    },
  );
  test(
    'Taxi Mario draft stays disabled, has no assumed depot and preserves supplied rates and boundaries',
    () {
      final draft = taxiMarioMissionTariffDraft();
      expect(draft['enabled'], isFalse);
      expect(draft['depot'], isNull);
      expect(draft['local_minimum_applies'], isTrue);
      expect(draft['price_rounding'], 'nearest_euro');
      for (final category in (draft['categories'] as Map).values) {
        final bands = category['bands'] as List;
        expect(bands[0]['max_km'], 95);
        for (var i = 0; i < bands.length; i++) {
          expect(bands[i]['min_inclusive'], isTrue);
          expect(bands[i]['max_inclusive'], isFalse);
          if (i > 0) expect(bands[i]['min_km'], bands[i - 1]['max_km']);
        }
      }
      expect(draft['quote_only_month_days'], [
        '12-24',
        '12-25',
        '12-31',
        '01-01',
      ]);
      final categories = draft['categories'] as Map;
      expect(categories['car']['bands'][0]['per_km_eur'], 1.25);
      expect(categories['minibus']['bands'][0]['per_km_eur'], 1.35);
      expect(categories['minibus']['bands'][3]['max_km'], 215);
      expect(categories['car']['vehicle_ids'], isEmpty);
      final next = taxiMarioMissionTariffDraft();
      categories['car']['bands'][0]['per_km_eur'] = 99;
      expect(next['categories']['car']['bands'][0]['per_km_eur'], 1.25);
    },
  );
  testWidgets('another company is not offered or assigned Taxi Mario rates', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CompanyMissionTariffPage(
          companyName: 'Other taxi company',
          language: AppLanguage.nl,
          vehicleLabels: {},
        ),
      ),
    );
    expect(find.byKey(const Key('mission_mario_template')), findsNothing);
    expect(find.text('Other taxi company'), findsOneWidget);
    expect(find.text('Eigen opdrachttarief gebruiken'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mission_route_provider_0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('mission_price_rounding_0')),
      findsOneWidget,
    );
  });
  testWidgets(
    'editing is a local draft and selected vehicle keeps its original label',
    (tester) async {
      final draft = taxiMarioMissionTariffDraft();
      draft['depot'] = {
        'lat': 51.17,
        'lng': 4.14,
        'label': 'Station Sint-Niklaas',
      };
      draft['categories']['car']['vehicle_ids'] = ['original-car-id'];
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyMissionTariffPage(
            companyName: 'Taxi Mario',
            language: AppLanguage.nl,
            vehicleLabels: const {'original-car-id': 'Original brand · Plate'},
            value: draft,
          ),
        ),
      );
      expect(find.text('Station Sint-Niklaas'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pump();
      expect(draft['enabled'], isFalse);
      await tester.scrollUntilVisible(
        find.text('Original brand · Plate'),
        450,
        maxScrolls: 30,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Original brand · Plate'), findsOneWidget);
      expect(draft['categories']['car']['vehicle_ids'], ['original-car-id']);
    },
  );
  testWidgets(
    'a company with only car tariffs keeps its category and vehicle labels',
    (tester) async {
      final draft = taxiMarioMissionTariffDraft();
      (draft['categories'] as Map).remove('minibus');
      draft['categories']['car']['vehicle_ids'] = ['car1'];
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyMissionTariffPage(
            companyName: 'Other taxi',
            language: AppLanguage.nl,
            vehicleLabels: const {'car1': 'Existing brand'},
            value: draft,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Existing brand'),
        450,
        maxScrolls: 30,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Minibus'), findsNothing);
      expect((draft['categories'] as Map).keys, ['car']);
    },
  );
}
