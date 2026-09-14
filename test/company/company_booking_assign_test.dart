import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_http.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_booking_detail_page.dart';
import 'package:fluxidi_tracking/company/company_dispatch.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';

class _AssignAgendaRepository extends CompanyAgendaRepository {
  _AssignAgendaRepository({this.assignError})
    : super(
        scopeResolver: () => const <String, String>{
          'tenant_id': 'demo_company_p0',
          'company_id': 'demo_company_p0',
        },
        listTransport: (_) async => const <CompanyAgendaRide>[],
        createTransport: ({required draft, required idempotencyKey}) async {
          throw const CompanyAgendaException('unused');
        },
      );

  final CompanyAgendaException? assignError;
  int assignCalls = 0;
  String? lastDriverId;
  String? lastVehicleId;
  void Function(String driverId, String vehicleId)? onAssigned;

  @override
  Future<CompanyAgendaRide> assignRide({
    required String bookingId,
    required String driverId,
    String vehicleId = '',
    int? revision,
    String legId = '',
    String legType = '',
  }) async {
    assignCalls += 1;
    lastDriverId = driverId;
    lastVehicleId = vehicleId;
    onAssigned?.call(driverId, vehicleId);
    if (assignError != null) throw assignError!;
    return CompanyAgendaRide(
      bookingId: bookingId,
      customerId: 'cus_1',
      customerName: 'Ada Lovelace',
      fromAddress: 'Gent',
      toAddress: 'Brussel',
      pickupIso: '2026-09-11T08:00:00.000Z',
      status: 'PENDING',
      assignedDriverId: driverId,
      assignedVehicleId: vehicleId,
      durationUnknown: false,
      durationMin: 90,
    );
  }
}

void main() {
  testWidgets('Toewijzen stays visible and overlap is shown', (tester) async {
    final agenda = _AssignAgendaRepository(
      assignError: const CompanyAgendaException('assignment_overlap'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyBookingDetailPage(
          bookingId: 'agb_assign',
          language: AppLanguage.nl,
          agendaRepository: agenda,
          loader: (id) async => <String, dynamic>{
            'ok': true,
            'status': 'PENDING',
            'record': <String, dynamic>{
              'booking_id': id,
              'customer_name': 'Grace Hopper',
              'from': 'Brussel Zuid',
              'to': 'Charleroi Airport',
              'pickup_iso': '2026-09-09T08:00:00.000Z',
              'revision': 1,
              'duration_min': 90,
            },
          },
          driversLoader: () async => <Map<String, dynamic>>[
            <String, dynamic>{
              'driver_id': 'drv_karel',
              'display_name': 'Karel Peeters',
              'agenda_color': '#C9A227',
            },
          ],
          vehiclesLoader: () async => <Map<String, dynamic>>[
            <String, dynamic>{
              'vehicle_id': 'vh_1',
              'vehicle_name': 'S-Klasse',
              'license_plate': '1-FLX-001',
              'passenger_capacity': 3,
            },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaAssignButtonKey), findsOneWidget);
    expect(
      find.text(kCompanyCustomerQuoteAssignmentPending.of(AppLanguage.nl)),
      findsOneWidget,
    );
    await tester.tap(find.byKey(kCompanyAgendaAssignDriverKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Karel Peeters').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kCompanyAgendaAssignButtonKey));
    await tester.pumpAndSettle();
    expect(agenda.assignCalls, 1);
    expect(agenda.lastDriverId, 'drv_karel');
    expect(find.text(kCompanyAgendaOverlap.of(AppLanguage.nl)), findsOneWidget);
    expect(find.text(kCompanyAgendaByDriver.of(AppLanguage.nl)), findsNothing);
  });

  testWidgets('saved assignment stays visible after reload', (tester) async {
    final assigned = <String, String>{};
    final agenda = _AssignAgendaRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyBookingDetailPage(
          bookingId: 'agb_grace',
          language: AppLanguage.nl,
          agendaRepository: agenda,
          loader: (id) async => <String, dynamic>{
            'ok': true,
            'status': 'PENDING',
            'record': <String, dynamic>{
              'booking_id': id,
              'customer_name': 'Grace Hopper',
              'from': 'Brussel Zuid',
              'to': 'Charleroi Airport',
              'pickup_iso': '2026-09-09T12:00:00.000Z',
              'revision': assigned.isEmpty ? 1 : 2,
              'duration_min': 75,
              if (assigned['driver'] != null)
                'assigned_driver_id': assigned['driver'],
              if (assigned['vehicle'] != null)
                'assigned_vehicle_id': assigned['vehicle'],
            },
          },
          driversLoader: () async => <Map<String, dynamic>>[
            <String, dynamic>{
              'driver_id': 'drv_karel',
              'display_name': 'Karel Peeters',
              'is_active': true,
            },
          ],
          vehiclesLoader: () async => <Map<String, dynamic>>[
            <String, dynamic>{
              'vehicle_id': 'vh_1',
              'vehicle_name': 'S-Klasse',
              'license_plate': '1-FLX-001',
              'passenger_capacity': 3,
              'is_active': true,
            },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kCompanyAgendaAssignDriverKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Karel Peeters').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kCompanyAgendaAssignVehicleKey));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('S-Klasse').last);
    await tester.pumpAndSettle();
    agenda.onAssigned = (driverId, vehicleId) {
      assigned['driver'] = driverId;
      assigned['vehicle'] = vehicleId;
    };
    await tester.tap(find.byKey(kCompanyAgendaAssignButtonKey));
    await tester.pumpAndSettle();
    expect(agenda.assignCalls, 1);
    expect(assigned['driver'], 'drv_karel');
    expect(assigned['vehicle'], 'vh_1');
    expect(find.textContaining(kCompanyAgendaAssigned.of(AppLanguage.nl)), findsOneWidget);
    expect(find.textContaining('Karel Peeters'), findsWidgets);
    expect(find.textContaining('S-Klasse'), findsWidgets);
  });

  testWidgets('missing choices show loading then no registered drivers', (
    tester,
  ) async {
    final gate = Completer<List<Map<String, dynamic>>>();
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyBookingDetailPage(
          bookingId: 'agb_empty',
          language: AppLanguage.nl,
          loader: (id) async => <String, dynamic>{
            'ok': true,
            'record': <String, dynamic>{
              'booking_id': id,
              'customer_name': 'Grace Hopper',
              'from': 'A',
              'to': 'B',
            },
          },
          driversLoader: () => gate.future,
          vehiclesLoader: () async => const <Map<String, dynamic>>[],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.text(kCompanyAgendaChoicesLoading.of(AppLanguage.nl)),
      findsOneWidget,
    );
    gate.complete(const <Map<String, dynamic>>[]);
    await tester.pumpAndSettle();
    expect(
      find.text(kCompanyAgendaNoRegisteredDrivers.of(AppLanguage.nl)),
      findsWidgets,
    );
  });

  testWidgets('load error and no suitable drivers stay distinct', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyBookingDetailPage(
          bookingId: 'agb_err',
          language: AppLanguage.nl,
          loader: (id) async => <String, dynamic>{
            'ok': true,
            'record': <String, dynamic>{
              'booking_id': id,
              'customer_name': 'Grace Hopper',
              'from': 'A',
              'to': 'B',
            },
          },
          driversLoader: () async => throw Exception('fleet'),
          vehiclesLoader: () async => const <Map<String, dynamic>>[],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(kCompanyAgendaChoicesLoadFailed.of(AppLanguage.nl)),
      findsOneWidget,
    );
  });

  testWidgets('overlap preview appears before save', (tester) async {
    final agenda = CompanyAgendaRepository(
      scopeResolver: () => const <String, String>{
        'tenant_id': 'demo_company_p0',
        'company_id': 'demo_company_p0',
      },
      listTransport: (_) async => const <CompanyAgendaRide>[],
      createTransport: ({required draft, required idempotencyKey}) async {
        throw const CompanyAgendaException('unused');
      },
      overlapTransport:
          ({
            required driverId,
            vehicleId = '',
            required pickupIso,
            durationMin,
            excludeBookingId = '',
            returnPickupIso = '',
            returnDurationMin,
            roundtripMode = '',
          }) async {
            return const CompanyAgendaOverlapCheck.error(
              'assignment_overlap',
              conflictingBookingId: 'agb_other',
            );
          },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyBookingDetailPage(
          bookingId: 'agb_preview',
          language: AppLanguage.nl,
          agendaRepository: agenda,
          loader: (id) async => <String, dynamic>{
            'ok': true,
            'record': <String, dynamic>{
              'booking_id': id,
              'customer_name': 'Grace Hopper',
              'from': 'A',
              'to': 'B',
              'pickup_iso': '2026-09-09T12:00:00.000Z',
              'duration_min': 75,
            },
          },
          driversLoader: () async => <Map<String, dynamic>>[
            <String, dynamic>{
              'driver_id': 'drv_karel',
              'display_name': 'Karel Peeters',
              'is_active': true,
            },
          ],
          vehiclesLoader: () async => const <Map<String, dynamic>>[],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kCompanyAgendaAssignDriverKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Karel Peeters').last);
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaOverlapPreviewKey), findsOneWidget);
    expect(
      find.text(kCompanyAgendaOverlapPreview.of(AppLanguage.nl)),
      findsOneWidget,
    );
  });

  testWidgets('no suitable drivers is distinct from none registered', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyBookingDetailPage(
          bookingId: 'agb_inactive',
          language: AppLanguage.nl,
          loader: (id) async => <String, dynamic>{
            'ok': true,
            'record': <String, dynamic>{
              'booking_id': id,
              'customer_name': 'Grace Hopper',
              'from': 'A',
              'to': 'B',
              'pax': 1,
            },
          },
          driversLoader: () async => <Map<String, dynamic>>[
            <String, dynamic>{
              'driver_id': 'drv_old',
              'display_name': 'Inactieve Chauffeur',
              'is_active': false,
            },
          ],
          vehiclesLoader: () async => <Map<String, dynamic>>[
            <String, dynamic>{
              'vehicle_id': 'vh_tiny',
              'vehicle_name': 'Smart',
              'passenger_capacity': 1,
              'is_active': true,
            },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(kCompanyAgendaNoSuitableDrivers.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(
      find.text(kCompanyAgendaNoRegisteredDrivers.of(AppLanguage.nl)),
      findsNothing,
    );
  });

  testWidgets('current driver is shown separately and not as an alternative', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyBookingDetailPage(
          bookingId: 'agb_current',
          language: AppLanguage.nl,
          loader: (id) async => <String, dynamic>{
            'ok': true,
            'record': <String, dynamic>{
              'booking_id': id,
              'customer_name': 'Grace Hopper',
              'from': 'A',
              'to': 'B',
              'assigned_driver_id': 'drv_karel',
              'duration_min': 40,
            },
          },
          driversLoader: () async => <Map<String, dynamic>>[
            <String, dynamic>{
              'driver_id': 'drv_karel',
              'display_name': 'Karel Peeters',
              'is_active': true,
            },
            <String, dynamic>{
              'driver_id': 'drv_amira',
              'display_name': 'Amira Hassan',
              'is_active': true,
            },
          ],
          vehiclesLoader: () async => const <Map<String, dynamic>>[],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaCurrentDriverKey), findsOneWidget);
    expect(find.textContaining('Karel Peeters'), findsWidgets);
    await tester.tap(find.byKey(kCompanyAgendaAssignDriverKey));
    await tester.pumpAndSettle();
    expect(find.text('Amira Hassan').hitTestable(), findsWidgets);
    expect(find.text(kCompanyAgendaNoOtherDriver.of(AppLanguage.nl)), findsNothing);
  });
}
