import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_booking_detail_page.dart';
import 'package:fluxidi_tracking/company/company_booking_metrics.dart';
import 'package:fluxidi_tracking/company/company_plan_assignment.dart';
import 'package:fluxidi_tracking/company/company_plan_ride_form.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/company/company_plan_when.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';

void main() {
  test('detail 60 min ride duration stays available for assignment', () {
    final raw = <String, dynamic>{
      'ok': true,
      'record': <String, dynamic>{
        'booking_id': 'agb_premium',
        'duration_min': 60,
        'duration_route_min': 60,
        'duration_unknown': false,
        'booking': <String, dynamic>{
          'duration_min': 60,
          'duration_route_min': 60,
          'tier': 'premium',
          'ride_options': <String, dynamic>{
            'tier': 'premium',
            'wait_min': 0,
          },
        },
        'quote': <String, dynamic>{
          'duration_min': 60,
        },
      },
    };
    expect(resolveCompanyBookingDurationMin(raw), 60);
    expect(
      companyPlanCanonicalDurationMin(
        quoteDurationMin: 60,
        durationRouteMin: 60,
        durationText: '',
      ),
      60,
    );
    expect(raw.toString(), isNot(contains('1970')));
  });

  test('wait-only premium summary is not used as assignment duration', () {
    const options = CompanyRideOptions(tier: 'premium', waitMin: 60);
    expect(
      formatCompanyRideOptionsSummary(options, language: AppLanguage.nl),
      contains('wacht 60 min'),
    );
    expect(
      resolveCompanyBookingDurationMin(<String, dynamic>{
        'ride_options': options.toJson(),
        'booking': <String, dynamic>{'tier': 'premium', 'wait_min': 60},
      }),
      isNull,
    );
  });

  test('picked driver with one linked vehicle is auto-selected', () {
    final proposal = proposeCompanyPlanAssignment(
      drivers: const <Map<String, dynamic>>[
        <String, dynamic>{
          'driver_id': 'drv_1',
          'display_name': 'Karel',
          'is_active': true,
          'linked_vehicle_id': 'vh_1',
        },
      ],
      vehicles: const <Map<String, dynamic>>[
        <String, dynamic>{
          'vehicle_id': 'vh_1',
          'passenger_capacity': 3,
          'is_active': true,
        },
      ],
      type: CompanyPlanVehicleType.sedan,
      passengers: 2,
      userPickedDriver: true,
      userPickedVehicle: false,
      currentDriverId: 'drv_1',
      currentVehicleId: '',
    );
    expect(proposal.driverId, 'drv_1');
    expect(proposal.vehicleId, 'vh_1');
  });

  testWidgets('customer confirmation hides dispatch internals', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyBookingDetailPage(
          bookingId: 'agb_customer',
          language: AppLanguage.nl,
          audience: CompanyPlanAudience.customer,
          loader: (id) async => <String, dynamic>{
            'ok': true,
            'status': 'PENDING',
            'record': <String, dynamic>{
              'booking_id': id,
              'customer_name': 'Ada Lovelace',
              'from': 'Gent',
              'to': 'BRU',
              'pickup_iso': '2026-09-16T07:00:00.000Z',
              'duration_min': 60,
              'price_incl_vat': 85,
              'assigned_driver_id': 'drv_1',
              'assigned_vehicle_id': 'vh_1',
            },
          },
          driversLoader: () async => const <Map<String, dynamic>>[
            <String, dynamic>{
              'driver_id': 'drv_1',
              'display_name': 'Karel Peeters',
            },
          ],
          vehiclesLoader: () async => const <Map<String, dynamic>>[
            <String, dynamic>{
              'vehicle_id': 'vh_1',
              'vehicle_name': 'S-Klasse',
              'license_plate': '1-FLX-001',
            },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaAssignButtonKey), findsNothing);
    expect(find.byKey(kCompanyAgendaAssignDriverKey), findsNothing);
    expect(find.textContaining('1-FLX-001'), findsNothing);
    expect(find.textContaining('agb_customer'), findsNothing);
    expect(find.textContaining('2026-09-16T07:00:00.000Z'), findsNothing);
    expect(find.byKey(const Key('company_booking_detail_duration')), findsOneWidget);
  });
}
