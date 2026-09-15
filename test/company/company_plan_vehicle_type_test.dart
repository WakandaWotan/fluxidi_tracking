import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_plan_assignment.dart';
import 'package:fluxidi_tracking/company/company_plan_ride_layout.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:flutter/widgets.dart';

void main() {
  test('sedan and minivan classify from capacity or class, not airport', () {
    expect(
      companyPlanVehicleLooksLikeSedan(<String, dynamic>{
        'vehicle_id': 'vh_1',
        'passenger_capacity': 3,
        'is_active': true,
      }),
      isTrue,
    );
    expect(
      companyPlanVehicleLooksLikeMinivan(<String, dynamic>{
        'vehicle_id': 'vh_2',
        'vehicle_name': 'Vito',
        'passenger_capacity': 7,
        'is_active': true,
      }),
      isTrue,
    );
    expect(
      parseCompanyPlanVehicleType('airport'),
      isNull,
    );
  });

  test('proposal uses a single linked suitable vehicle and leaves several empty', () {
    final drivers = <Map<String, dynamic>>[
      <String, dynamic>{
        'driver_id': 'drv_1',
        'display_name': 'A',
        'is_active': true,
        'linked_vehicle_id': 'vh_1',
      },
    ];
    final one = proposeCompanyPlanAssignment(
      drivers: drivers,
      vehicles: <Map<String, dynamic>>[
        <String, dynamic>{
          'vehicle_id': 'vh_1',
          'passenger_capacity': 3,
          'is_active': true,
        },
      ],
      type: CompanyPlanVehicleType.sedan,
      passengers: 2,
      userPickedDriver: false,
      userPickedVehicle: false,
      currentDriverId: '',
      currentVehicleId: '',
    );
    expect(one.driverId, 'drv_1');
    expect(one.vehicleId, 'vh_1');

    final several = proposeCompanyPlanAssignment(
      drivers: <Map<String, dynamic>>[
        <String, dynamic>{
          'driver_id': 'drv_1',
          'is_active': true,
          'vehicle_ids': <String>['vh_1', 'vh_2'],
        },
      ],
      vehicles: <Map<String, dynamic>>[
        <String, dynamic>{
          'vehicle_id': 'vh_1',
          'passenger_capacity': 3,
          'is_active': true,
        },
        <String, dynamic>{
          'vehicle_id': 'vh_2',
          'passenger_capacity': 3,
          'is_active': true,
        },
      ],
      type: CompanyPlanVehicleType.sedan,
      passengers: 1,
      userPickedDriver: false,
      userPickedVehicle: false,
      currentDriverId: '',
      currentVehicleId: '',
    );
    expect(several.driverId, 'drv_1');
    expect(several.vehicleId, isEmpty);
  });

  test('wide Windows keeps agenda beside the planner; tablet can split', () {
    expect(
      companyOpsShowAgendaBesidePlanner(const Size(1524, 900)),
      isTrue,
    );
    expect(
      companyOpsShowAgendaBesidePlanner(const Size(1100, 720)),
      isTrue,
    );
    expect(
      companyOpsShowAgendaBesidePlanner(const Size(1180, 820)),
      isFalse,
    );
    expect(
      companyOpsShowAgendaBesidePlanner(const Size(800, 1280)),
      isFalse,
    );
    expect(
      companyPlanRideLayoutFor(const BoxConstraints(maxWidth: 1180, maxHeight: 820)),
      CompanyPlanRideLayout.split,
    );
    expect(
      companyPlanRideLayoutFor(const BoxConstraints(maxWidth: 390, maxHeight: 844)),
      CompanyPlanRideLayout.stacked,
    );
    expect(
      companyOpsPlannerPaneWidth(
        totalWidth: 1524,
        customersCollapsed: false,
        planning: true,
        dossierOpen: true,
      ),
      inInclusiveRange(360, 520),
    );
  });
}
