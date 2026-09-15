import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_form_date_time.dart';
import 'package:fluxidi_tracking/company/company_plan_ride_form.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';

Widget _form({
  required Size size,
  CompanyPlanAudience audience = CompanyPlanAudience.companyOps,
  int passengers = 1,
  int bags = 0,
  String? capacityWarning,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(
        body: SizedBox(
          width: size.width,
          height: size.height,
          child: CompanyPlanRideForm(
            language: AppLanguage.nl,
            title: 'Rit plannen',
            audience: audience,
            whenNow: true,
            onWhenNowChanged: (_) {},
            customer: null,
            customers: const <CompanyCustomerListItem>[],
            onCustomerSelected: (_) {},
            onAddCustomer: () {},
            vehicleType: CompanyPlanVehicleType.sedan,
            airportMode: false,
            onVehicleTypeChanged: (_) {},
            onAirportModeChanged: (_) {},
            routeFields: const Text('route-slot'),
            whenLaterFields: CompanyDateTimeFields(
              fieldId: 'agenda_pickup',
              language: AppLanguage.nl,
              value: DateTime(2026, 9, 16, 9),
              onChanged: (_) {},
            ),
            roundtripFields: const Text('roundtrip-slot'),
            passengers: passengers,
            onPassengersChanged: (_) {},
            bags: bags,
            onBagsChanged: (_) {},
            quote: const Text('quote-slot'),
            proposedAssignment: const Text('driver-slot'),
            moreOptions: const <Widget>[Text('more-slot')],
            primary: const Text('primary-slot'),
            secondary: const Text('secondary-slot'),
            map: const ColoredBox(color: Color(0xFF111111)),
            capacityWarning: capacityWarning,
            unsuitableCategories: capacityWarning == null
                ? const <CompanyPlanVehicleCategory>{}
                : const <CompanyPlanVehicleCategory>{
                    CompanyPlanVehicleCategory.sedan,
                  },
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('ops flow keeps one occupancy row and hides customer for riders', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_form(size: const Size(390, 844)));
    expect(find.byKey(kCompanyAgendaOccupancyKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaPlanCustomerFieldKey), findsOneWidget);
    expect(find.text('driver-slot'), findsOneWidget);
    expect(find.text('roundtrip-slot'), findsOneWidget);

    await tester.pumpWidget(
      _form(
        size: const Size(390, 844),
        audience: CompanyPlanAudience.customer,
      ),
    );
    expect(find.byKey(kCompanyAgendaPlanCustomerFieldKey), findsNothing);
    expect(find.text('driver-slot'), findsNothing);
    expect(find.byKey(kCompanyAgendaOccupancyKey), findsOneWidget);
  });

  testWidgets('over-capacity marks the type and explains the alternative', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1280));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _form(
        size: const Size(800, 1280),
        passengers: 5,
        bags: 4,
        capacityWarning: kCompanyAgendaCapacityUnsuitable.of(AppLanguage.nl),
      ),
    );
    expect(find.byKey(kCompanyAgendaCapacityWarningKey), findsOneWidget);
  });

  testWidgets('guided flow fits phone, tablet and Windows sizes', (
    tester,
  ) async {
    for (final size in const <Size>[
      Size(390, 844),
      Size(800, 1280),
      Size(1100, 720),
      Size(1180, 820),
      Size(1280, 800),
      Size(1524, 900),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(_form(size: size));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(kCompanyAgendaOccupancyKey), findsOneWidget);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/company_plan_guided_flow_${size.width.toInt()}x${size.height.toInt()}.png',
        ),
      );
    }
    await tester.binding.setSurfaceSize(null);
  });
}
