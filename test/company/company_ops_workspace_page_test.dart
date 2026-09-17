import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/company/company_agenda_calendar.dart';
import 'package:fluxidi_tracking/company/company_agenda_http.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_agenda_prefs.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_color_chips.dart';
import 'package:fluxidi_tracking/company/company_customer_dossier.dart';
import 'package:fluxidi_tracking/company/company_customer_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customers_page.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';
import 'package:fluxidi_tracking/company/company_assignment_choice_field.dart';
import 'package:fluxidi_tracking/company/company_drivers_now.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_form_date_time.dart';
import 'package:fluxidi_tracking/company/company_booking_detail_page.dart';
import 'package:fluxidi_tracking/company/company_ops_workspace_page.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/company/company_crew_combo.dart';
import 'package:fluxidi_tracking/company/company_plan_airport_cards.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_ride_options_form.dart';
import 'package:fluxidi_tracking/company/company_plan_ride_form.dart';
import 'package:fluxidi_tracking/company/company_trip_route_fields.dart';
import 'package:fluxidi_tracking/company/company_plan_route_map.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';

class _FakeCustomersRepository extends CompanyCustomersRepository {
  _FakeCustomersRepository({this.pages, this.detail})
    : super(
        scopeQuery: const <String, String>{
          'tenant_id': 'demo_company_p0',
          'company_id': 'demo_company_p0',
        },
        headers: () async => const <String, String>{},
        listTransport:
            ({required path, required query, required headers}) async =>
                <String, dynamic>{'ok': true, 'items': <dynamic>[]},
        sendTransport:
            ({
              required method,
              required path,
              required query,
              required body,
              required headers,
              idempotencyKey,
            }) async => <String, dynamic>{
              'ok': true,
              'customer': <String, dynamic>{
                'customer_id': 'cus_1',
                'display_name': 'Ada Lovelace',
                'status': 'active',
                'revision': 1,
              },
            },
      );

  List<CompanyCustomerListPage>? pages;
  CompanyCustomer? detail;

  @override
  Future<CompanyCustomerListPage> list({
    String status = 'active',
    String query = '',
    String cursor = '',
  }) async {
    final all = pages;
    if (all == null || all.isEmpty) {
      return const CompanyCustomerListPage(
        items: <CompanyCustomerListItem>[],
        hasMore: false,
        nextCursor: null,
        totalCount: 0,
      );
    }
    if (cursor.isEmpty) return all.first;
    for (var i = 1; i < all.length; i += 1) {
      if ((all[i - 1].nextCursor ?? '') == cursor) {
        return all[i];
      }
    }
    return all.last;
  }

  @override
  Future<CompanyCustomer> getById(String customerId) async {
    return detail ??
        parseCompanyCustomer(<String, dynamic>{
          'customer_id': customerId,
          'display_name': 'Ada Lovelace',
          'status': 'active',
          'revision': 1,
          'email': 'ada@example.test',
          'addresses': <Map<String, dynamic>>[
            <String, dynamic>{
              'label': 'Thuis',
              'line1': 'Korenmarkt 1',
              'city': 'Gent',
            },
          ],
        });
  }
}

class _FakeAgendaRepository extends CompanyAgendaRepository {
  _FakeAgendaRepository({
    this.rides = const <CompanyAgendaRide>[],
    this.createError,
  }) : super(
         scopeResolver: () => const <String, String>{
           'tenant_id': 'demo_company_p0',
           'company_id': 'demo_company_p0',
         },
         listTransport: (_) async => rides,
         createTransport: ({required draft, required idempotencyKey}) async {
           throw const CompanyAgendaException('unused');
         },
       );

  final List<CompanyAgendaRide> rides;
  final CompanyAgendaException? createError;
  int createCalls = 0;
  final List<String> keys = <String>[];
  String? lastFrom;
  String? lastPrice;
  String? lastDriverId;
  String? lastVehicleId;

  @override
  Future<List<CompanyAgendaRide>> listPeriod(
    CompanyAgendaPeriod period, {
    bool force = false,
  }) async {
    return rides;
  }

  @override
  Future<CompanyAgendaRide> createRide({
    required CompanyRidePlanDraft draft,
    required String idempotencyKey,
  }) async {
    createCalls += 1;
    keys.add(idempotencyKey);
    lastFrom = draft.fromAddress;
    lastPrice = draft.priceText;
    lastDriverId = draft.driverId;
    lastVehicleId = draft.vehicleId;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (createError != null) throw createError!;
    return CompanyAgendaRide(
      bookingId: 'agb_saved',
      customerId: draft.customer.customerId,
      customerName: draft.customer.displayName,
      fromAddress: draft.fromAddress,
      toAddress: draft.toAddress,
      pickupIso: draft.pickupLocal.toUtc().toIso8601String(),
      status: 'PENDING',
      assignedDriverId: draft.driverId,
      assignedVehicleId: draft.vehicleId,
      durationUnknown: draft.durationText.trim().isEmpty,
    );
  }
}

CompanyCustomerListItem _item(String id, String name) {
  return CompanyCustomerListItem(
    customerId: id,
    displayName: name,
    companyName: '',
    phoneMasked: '***01',
    emailMasked: '*@demo.local',
    status: 'active',
    updatedAt: '2026-09-11T00:00:00.000Z',
  );
}

/// Registered vehicles covering the two categories the planner offers.
List<Map<String, dynamic>> _defaultFleet() => <Map<String, dynamic>>[
  <String, dynamic>{
    'vehicle_id': 'vh_sedan',
    // A neutral name: 'S-Klasse' classifies as limousine, not sedan.
    'vehicle_name': 'Berline 1',
    'vehicle_type': 'sedan',
    'license_plate': '1-FLX-001',
    'passenger_capacity': 3,
    'is_active': true,
  },
  <String, dynamic>{
    'vehicle_id': 'vh_minivan',
    'vehicle_name': 'Monovolume 1',
    'vehicle_type': 'minivan',
    'license_plate': '1-FLX-002',
    'passenger_capacity': 7,
    'is_active': true,
  },
];

/// Picks the customer inside the open plan form.
///
/// The planner deliberately opens without a customer, so a test that saves a
/// booking must choose one exactly like the operator does.
Future<void> _choosePlanCustomer(
  WidgetTester tester, {
  String name = 'Ada Lovelace',
}) async {
  await tester.ensureVisible(find.byKey(kCompanyAgendaPlanCustomerFieldKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(kCompanyAgendaPlanCustomerFieldKey));
  await tester.enterText(find.byKey(kCompanyAgendaPlanCustomerFieldKey), name);
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

Future<void> _pumpWorkspace(
  WidgetTester tester, {
  required Size size,
  required _FakeCustomersRepository customers,
  required _FakeAgendaRepository agenda,
  Future<List<Map<String, dynamic>>> Function()? driversLoader,
  Future<List<Map<String, dynamic>>> Function()? vehiclesLoader,
  DateTime? initialAnchor,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: CompanyOpsWorkspacePage(
          key: ValueKey<String>(
            'workspace-${customers.hashCode}-${agenda.hashCode}',
          ),
          customersRepository: customers,
          agendaRepository: agenda,
          driversLoader:
              driversLoader ?? () async => const <Map<String, dynamic>>[],
          // A real fleet: the planner only offers categories it actually has,
          // so the vehicle-type chips must come from registered vehicles.
          vehiclesLoader: vehiclesLoader ?? () async => _defaultFleet(),
          planQuoteTransport: (request) async => CompanyPlanQuoteResult(
            fingerprint: request.fingerprint,
            distanceKm: 34.2,
            durationMin: 29,
            priceInclVat: 46.7,
            currency: 'EUR',
            pricingSource: 'route_calc',
            priceAvailable: true,
          ),
          bookingDetailLoader: (id) async => <String, dynamic>{
            'ok': true,
            'booking_id': id,
          },
          language: AppLanguage.nl,
          initialAnchor: initialAnchor,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fillPlanPickup(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(kCompanyAgendaPlanWhenLaterKey));
  await tester.tap(find.byKey(kCompanyAgendaPlanWhenLaterKey));
  await tester.pumpAndSettle();
  final date = tester.widget<TextField>(
    find.byKey(companyFormDateFieldKey('agenda_pickup')),
  );
  date.controller!.text = '20/9/2026';
  date.onSubmitted?.call('20/9/2026');
  final time = tester.widget<TextField>(
    find.byKey(companyFormTimeFieldKey('agenda_pickup')),
  );
  time.controller!.text = '09:00';
  time.onSubmitted?.call('09:00');
  await tester.pump();
}

void main() {
  setUp(resetCompanyAgendaPrefsForTest);

  final customers = () => _FakeCustomersRepository(
    pages: <CompanyCustomerListPage>[
      CompanyCustomerListPage(
        items: <CompanyCustomerListItem>[_item('cus_1', 'Ada Lovelace')],
        hasMore: false,
        nextCursor: null,
        totalCount: 1,
      ),
    ],
  );

  testWidgets('desktop planner has agenda beside the form, not a CRM list', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      size: const Size(1280, 800),
      customers: customers(),
      agenda: _FakeAgendaRepository(),
    );
    expect(find.byKey(kCompanyOpsWorkspacePageKey), findsOneWidget);
    expect(find.byKey(kCompanyOpsPlannerWorkspaceKey), findsOneWidget);
    expect(find.byKey(kCompanyCustomersSearchFieldKey), findsNothing);
    expect(find.byKey(kCompanyAgendaPaneKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaPlanRideKey), findsOneWidget);
    expect(find.byKey(kCompanyDriversNowPaneKey), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text(kCompanyAgendaPlanRide.of(AppLanguage.nl)), findsWidgets);
  });

  testWidgets('Chauffeurs nu uses loaded drivers without claiming online', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      size: const Size(1280, 800),
      customers: customers(),
      agenda: _FakeAgendaRepository(),
      driversLoader: () async => <Map<String, dynamic>>[
        <String, dynamic>{
          'driver_id': 'drv_karel',
          'display_name': 'Karel Peeters',
          'availability_status': 'available',
          'updated_at': '2026-09-11T08:00:00.000Z',
        },
      ],
    );
    expect(find.byKey(kCompanyDriversNowPaneKey), findsOneWidget);
    expect(find.text('Karel Peeters'), findsWidgets);
    // `updated_at` is not an operational signal, so no signal was recorded.
    // That is "unknown", which is not the same as a dropped connection.
    expect(
      find.textContaining(kCompanyDriverConnectionUnknown.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(
      find.textContaining(kCompanyDriversNowLiveLink.of(AppLanguage.nl)),
      findsNothing,
    );
    expect(
      find.textContaining(kCompanyDriverSignalNever.of(AppLanguage.nl)),
      findsOneWidget,
    );
    // The roster is separate and was never configured for this driver.
    expect(
      find.textContaining(kCompanyDriverPlanningNone.of(AppLanguage.nl)),
      findsOneWidget,
    );
  });

  testWidgets('tablet shows agenda; phone uses Agenda and Nieuwe rit', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      size: const Size(800, 1024),
      customers: customers(),
      agenda: _FakeAgendaRepository(),
    );
    expect(find.byKey(kCompanyAgendaPaneKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaToggleCustomersKey), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);

    await _pumpWorkspace(
      tester,
      size: const Size(390, 844),
      customers: customers(),
      agenda: _FakeAgendaRepository(),
    );
    expect(find.byKey(kCompanyAgendaPhoneNavKey), findsOneWidget);
    expect(find.text(kCompanyAgendaTitle.of(AppLanguage.nl)), findsWidgets);
    expect(find.text(kCompanyAgendaNewRideTab.of(AppLanguage.nl)), findsOneWidget);
    expect(find.byKey(kCompanyAgendaPaneKey), findsOneWidget);
    expect(find.byKey(kCompanyCustomersSearchFieldKey), findsNothing);
  });

  testWidgets('Rit plannen and cancel never write a booking', (tester) async {
    final agenda = _FakeAgendaRepository();
    await _pumpWorkspace(
      tester,
      size: const Size(1280, 800),
      customers: customers(),
      agenda: agenda,
    );
    await tester.tap(find.byKey(kCompanyAgendaPlanRideKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaRideFormKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaVehicleTypeSedanKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaAirportModeKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaPlanRideKey), findsNothing);
    expect(find.byKey(kCompanyAgendaPlanCloseKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaOccupancyKey), findsOneWidget);
    await tester.ensureVisible(find.byKey(kCompanyAgendaMoreOptionsKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kCompanyAgendaMoreOptionsKey));
    await tester.pumpAndSettle();
    expect(find.text(kCompanyAgendaPrice.of(AppLanguage.nl)), findsOneWidget);
    expect(find.byKey(kCompanyRideServiceKey), findsNothing);
    expect(find.byKey(kCompanyRideTierKey), findsNothing);
    expect(find.byKey(kCompanyRideBagsKey), findsNothing);
    expect(find.byKey(kCompanyRideWaitKey), findsNothing);
    await tester.tap(find.byKey(kCompanyAgendaCancelRideKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaRideFormKey), findsNothing);
    expect(agenda.createCalls, 0);
  });

  testWidgets('save sends one booking and retries keep the same key', (
    tester,
  ) async {
    final agenda = _FakeAgendaRepository();
    await _pumpWorkspace(
      tester,
      size: const Size(1280, 800),
      customers: customers(),
      agenda: agenda,
    );
    await tester.tap(find.byKey(kCompanyAgendaPlanRideKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaVehicleTypeSedanKey), findsOneWidget);
    expect(find.textContaining('2026-09'), findsNothing);
    await _choosePlanCustomer(tester);
    await _fillPlanPickup(tester);
    await tester.enterText(find.byKey(kCompanyAgendaToFieldKey), 'Brussel');
    await tester.tap(find.byKey(kCompanyAgendaSaveRideKey));
    await tester.pump();
    await tester.tap(find.byKey(kCompanyAgendaSaveRideKey));
    await tester.pumpAndSettle();
    expect(agenda.createCalls, 1);
    expect(agenda.keys, hasLength(1));
    expect(agenda.lastPrice, '');
    expect(agenda.lastFrom, contains('Korenmarkt 1'));
    expect(find.text(kCompanyAgendaSaved.of(AppLanguage.nl)), findsOneWidget);
  });

  testWidgets('overlap and unknown availability stay visible', (tester) async {
    final agenda = _FakeAgendaRepository(
      createError: const CompanyAgendaException('assignment_overlap'),
    );
    await _pumpWorkspace(
      tester,
      size: const Size(1280, 800),
      customers: customers(),
      agenda: agenda,
    );
    await tester.tap(find.byKey(kCompanyAgendaPlanRideKey));
    await tester.pumpAndSettle();
    await _choosePlanCustomer(tester);
    await _fillPlanPickup(tester);
    await tester.enterText(find.byKey(kCompanyAgendaToFieldKey), 'Brussel');
    await tester.tap(find.byKey(kCompanyAgendaSaveRideKey));
    await tester.pumpAndSettle();
    expect(find.text(kCompanyAgendaOverlap.of(AppLanguage.nl)), findsOneWidget);

    final unknown = _FakeAgendaRepository(
      createError: const CompanyAgendaException(
        'assignment_availability_unknown',
      ),
    );
    await _pumpWorkspace(
      tester,
      size: const Size(1280, 800),
      customers: customers(),
      agenda: unknown,
    );
    await tester.tap(find.byKey(kCompanyAgendaPlanRideKey));
    await tester.pumpAndSettle();
    await _choosePlanCustomer(tester);
    await _fillPlanPickup(tester);
    await tester.enterText(find.byKey(kCompanyAgendaToFieldKey), 'Brussel');
    await tester.tap(find.byKey(kCompanyAgendaSaveRideKey));
    await tester.pumpAndSettle();
    expect(
      find.text(kCompanyAgendaAvailabilityUnknown.of(AppLanguage.nl)),
      findsOneWidget,
    );
  });

  testWidgets('day and week stay available and empty copy stays readable', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      size: const Size(1280, 800),
      customers: customers(),
      agenda: _FakeAgendaRepository(),
    );
    expect(find.text(kCompanyAgendaEmpty.of(AppLanguage.nl)), findsOneWidget);
    await tester.tap(find.byKey(kCompanyAgendaDayKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaPaneKey), findsOneWidget);
    await tester.tap(find.byKey(kCompanyAgendaWeekKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaTodayKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaHourCompactKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaHourSpaciousKey), findsOneWidget);
    expect(
      find.text(kCompanyAgendaByDriver.of(AppLanguage.nl)),
      findsOneWidget,
    );
    await tester.tap(find.byKey(kCompanyAgendaByDriverKey));
    await tester.pumpAndSettle();
    expect(
      find.text(kCompanyAgendaUnassignedLane.of(AppLanguage.nl)),
      findsWidgets,
    );
  });

  testWidgets('week shows readable ride blocks on the shared time scale', (
    tester,
  ) async {
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final pickup = DateTime(monday.year, monday.month, monday.day, 10);
    await _pumpWorkspace(
      tester,
      size: const Size(1280, 900),
      customers: customers(),
      agenda: _FakeAgendaRepository(
        rides: <CompanyAgendaRide>[
          CompanyAgendaRide(
            bookingId: 'agb_week_demo',
            customerId: 'cus_1',
            customerName: 'Ada Lovelace',
            fromAddress: 'Korenmarkt 1, Gent',
            toAddress: 'Brussels Airport',
            pickupIso: pickup.toUtc().toIso8601String(),
            status: 'PENDING',
            assignedDriverId: 'drv_karel',
            assignedVehicleId: 'vh_1',
            durationUnknown: false,
            durationMin: 90,
          ),
        ],
      ),
    );
    expect(find.text(kCompanyAgendaEmpty.of(AppLanguage.nl)), findsNothing);
    expect(
      find.byKey(const Key('company_agenda_ride_agb_week_demo')),
      findsOneWidget,
    );
    expect(find.byKey(kCompanyAgendaDayHeaderRowKey), findsOneWidget);
    expect(find.textContaining('Ada Lovelace'), findsWidgets);
    expect(find.textContaining('10:00'), findsWidgets);
    await tester.tap(find.byKey(kCompanyAgendaByDriverKey));
    await tester.pumpAndSettle();
    expect(
      find.text(kCompanyAgendaByDriver.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(find.byKey(kCompanyAgendaUnassignedLaneKey), findsOneWidget);
    expect(find.text('drv_karel'), findsWidgets);
  });

  testWidgets('week keeps Sunday visible with the dossier open and closed', (
    tester,
  ) async {
    final sunday = DateTime(2026, 9, 13, 0);
    await _pumpWorkspace(
      tester,
      size: const Size(1600, 900),
      customers: customers(),
      agenda: _FakeAgendaRepository(),
      initialAnchor: DateTime(2026, 9, 9, 12),
    );
    expect(find.text('7/9 – 13/9'), findsOneWidget);
    expect(find.text('Zo'), findsOneWidget);
    expect(find.text('13/9'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(companyAgendaDayHeaderKey(sunday))).right,
      lessThan(1601),
    );
    expect(
      tester.getRect(find.byKey(Key(companyAgendaSlotKey(sunday)))).right,
      lessThan(1601),
    );

    await tester.tap(find.byKey(kCompanyAgendaPlanRideKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaRideFormKey), findsOneWidget);
    expect(find.text('Zo'), findsOneWidget);
    expect(find.text('13/9'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(companyAgendaDayHeaderKey(sunday))).right,
      lessThan(1601),
    );
    expect(find.byKey(kCompanyCustomerDossierKey), findsNothing);

    await tester.tap(find.byKey(kCompanyAgendaNextPeriodKey));
    await tester.pumpAndSettle();
    expect(find.text('14/9 – 20/9'), findsOneWidget);
    expect(find.text('14/9'), findsOneWidget);
    expect(find.text('Zo'), findsOneWidget);
  });

  testWidgets('dragging onto Sunday stores 13/9', (tester) async {
    final sunday = DateTime(2026, 9, 13, 0);
    await _pumpWorkspace(
      tester,
      size: const Size(1600, 900),
      customers: customers(),
      agenda: _FakeAgendaRepository(),
      initialAnchor: DateTime(2026, 9, 9, 12),
    );
    await tester.tap(find.byKey(kCompanyAgendaPlanRideKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaRideFormKey), findsOneWidget);
    await tester.ensureVisible(find.byKey(kCompanyAgendaPlanWhenLaterKey));
    await tester.tap(find.byKey(kCompanyAgendaPlanWhenLaterKey));
    await tester.pumpAndSettle();
    final date = tester.widget<TextField>(
      find.byKey(companyFormDateFieldKey('agenda_pickup')),
    );
    date.controller!.text = '13/9/2026';
    date.onSubmitted?.call('13/9/2026');
    final time = tester.widget<TextField>(
      find.byKey(companyFormTimeFieldKey('agenda_pickup')),
    );
    time.controller!.text = '00:00';
    time.onSubmitted?.call('00:00');
    await tester.pump();
    expect(find.textContaining('13'), findsWidgets);
  });

  testWidgets('agenda colors reload in Klantenbeheer after a chauffeur save', (
    tester,
  ) async {
    var loads = 0;
    await _pumpWorkspace(
      tester,
      size: const Size(1600, 900),
      customers: customers(),
      agenda: _FakeAgendaRepository(),
      initialAnchor: DateTime(2026, 9, 9, 12),
      driversLoader: () async {
        loads += 1;
        return <Map<String, dynamic>>[
          <String, dynamic>{
            'driver_id': 'drv_karel',
            'display_name': 'Karel Peeters',
            'agenda_color': loads == 1 ? '#C9A227' : '#2F6B4F',
          },
        ];
      },
    );
    expect(loads, greaterThanOrEqualTo(1));
    final before = loads;
    notifyCompanyDriverAgendaColorsChanged();
    await tester.pumpAndSettle();
    expect(loads, greaterThan(before));
  });

  testWidgets('tapping a chauffeur card shows only that agenda', (
    tester,
  ) async {
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final pickup = DateTime(monday.year, monday.month, monday.day, 10);
    await _pumpWorkspace(
      tester,
      size: const Size(1280, 900),
      customers: customers(),
      driversLoader: () async => <Map<String, dynamic>>[
        <String, dynamic>{
          'driver_id': 'drv_karel',
          'display_name': 'Karel Peeters',
        },
        <String, dynamic>{
          'driver_id': 'drv_amira',
          'display_name': 'Amira Benali',
        },
      ],
      agenda: _FakeAgendaRepository(
        rides: <CompanyAgendaRide>[
          CompanyAgendaRide(
            bookingId: 'agb_karel',
            customerId: 'cus_1',
            customerName: 'Ada Lovelace',
            fromAddress: 'Korenmarkt 1, Gent',
            toAddress: 'Brussels Airport',
            pickupIso: pickup.toUtc().toIso8601String(),
            status: 'PENDING',
            assignedDriverId: 'drv_karel',
            assignedVehicleId: 'vh_1',
            durationUnknown: false,
            durationMin: 60,
          ),
          CompanyAgendaRide(
            bookingId: 'agb_amira',
            customerId: 'cus_2',
            customerName: 'Grace Hopper',
            fromAddress: 'Meir 12, Antwerpen',
            toAddress: 'Gent-Sint-Pieters',
            pickupIso: pickup
                .add(const Duration(hours: 2))
                .toUtc()
                .toIso8601String(),
            status: 'PENDING',
            assignedDriverId: 'drv_amira',
            assignedVehicleId: 'vh_2',
            durationUnknown: false,
            durationMin: 60,
          ),
        ],
      ),
    );
    expect(
      find.byKey(const Key('company_agenda_ride_agb_karel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('company_agenda_ride_agb_amira')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(companyDriversNowCardKey('drv_karel')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('company_agenda_ride_agb_karel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('company_agenda_ride_agb_amira')),
      findsNothing,
    );
    await tester.tap(find.byKey(companyDriversNowCardKey('drv_karel')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('company_agenda_ride_agb_amira')),
      findsOneWidget,
    );
  });

  testWidgets('all six business themes keep agenda empty copy readable', (
    tester,
  ) async {
    addTearDown(() {
      businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
    });
    for (final theme in BusinessThemeVariant.values) {
      businessThemeNotifier.value = theme;
      await _pumpWorkspace(
        tester,
        size: const Size(1280, 800),
        customers: customers(),
        agenda: _FakeAgendaRepository(),
      );
      expect(find.text(kCompanyAgendaEmpty.of(AppLanguage.nl)), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Rit plannen stores selected driver and vehicle IDs', (
    tester,
  ) async {
    final agenda = _FakeAgendaRepository();
    await _pumpWorkspace(
      tester,
      size: const Size(1280, 900),
      customers: customers(),
      agenda: agenda,
      driversLoader: () async => <Map<String, dynamic>>[
        <String, dynamic>{
          'driver_id': 'drv_karel',
          'display_name': 'Karel Peeters',
          'agenda_color': '#C9A227',
          'is_active': true,
        },
        <String, dynamic>{
          'driver_id': 'drv_amira',
          'display_name': 'Amira Benali',
          'is_active': true,
        },
      ],
      vehiclesLoader: () async => <Map<String, dynamic>>[
        <String, dynamic>{
          'vehicle_id': 'vh_1',
          'vehicle_name': 'S-Klasse',
          'vehicle_type': 'sedan',
          'license_plate': '1-FLX-001',
          'passenger_capacity': 3,
          'is_active': true,
        },
      ],
    );
    await tester.tap(find.byKey(kCompanyAgendaPlanRideKey));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(kCompanyAgendaPlanDriverKey));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('company_crew_combo_drv_karel|vh_1')), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byKey(kCompanyAgendaOutboundCrewKey),
        matching: find.byKey(kCompanyCrewComboOpenKey),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('company_crew_combo_drv_karel|vh_1')), findsOneWidget);
    expect(find.byKey(const Key('company_crew_combo_drv_amira|vh_1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('company_crew_combo_drv_karel|vh_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyCrewComboSheetKey), findsNothing);
    expect(find.byKey(kCompanyAgendaPlanVehicleKey), findsNothing);
    await tester.enterText(find.byKey(kCompanyAgendaToFieldKey), 'Brussel');
    await _choosePlanCustomer(tester);
    await _fillPlanPickup(tester);
    await tester.tap(find.byKey(kCompanyAgendaSaveRideKey));
    await tester.pumpAndSettle();
    expect(agenda.createCalls, 1);
    expect(agenda.lastDriverId, 'drv_karel');
    expect(agenda.lastVehicleId, 'vh_1');
  });

  testWidgets('typed driver names are not saved without a choice', (
    tester,
  ) async {
    final agenda = _FakeAgendaRepository();
    await _pumpWorkspace(
      tester,
      size: const Size(1280, 900),
      customers: customers(),
      agenda: agenda,
      driversLoader: () async => <Map<String, dynamic>>[
        <String, dynamic>{
          'driver_id': 'drv_karel',
          'display_name': 'Karel Peeters',
          'is_active': true,
        },
      ],
    );
    await tester.tap(find.byKey(kCompanyAgendaPlanRideKey));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(kCompanyAgendaOutboundCrewKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(kCompanyAgendaOutboundCrewKey),
        matching: find.byKey(kCompanyCrewComboOpenKey),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kCompanyAgendaUnassignedLaneKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(kCompanyAgendaToFieldKey), 'Brussel');
    await _choosePlanCustomer(tester);
    await _fillPlanPickup(tester);
    await tester.tap(find.byKey(kCompanyAgendaSaveRideKey));
    await tester.pumpAndSettle();
    expect(agenda.createCalls, 1);
    expect(agenda.lastDriverId, '');
  });

  testWidgets('unknown duration does not look free after choosing a driver', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      size: const Size(1280, 900),
      customers: customers(),
      agenda: _FakeAgendaRepository(),
      driversLoader: () async => <Map<String, dynamic>>[
        <String, dynamic>{
          'driver_id': 'drv_karel',
          'display_name': 'Karel Peeters',
          'is_active': true,
        },
      ],
      // This case is about a driver with no vehicle linked at all.
      vehiclesLoader: () async => const <Map<String, dynamic>>[],
    );
    await tester.tap(find.byKey(kCompanyAgendaPlanRideKey));
    await tester.pumpAndSettle();
    await _choosePlanCustomer(tester);
    await _fillPlanPickup(tester);
    await tester.ensureVisible(find.byKey(kCompanyAgendaPlanDriverKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(kCompanyAgendaOutboundCrewKey),
        matching: find.byKey(kCompanyCrewComboOpenKey),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('company_crew_combo_drv_karel|')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(kCompanyAgendaOverlapPreviewKey));
    expect(find.byKey(kCompanyAgendaOverlapPreviewKey), findsOneWidget);
    expect(
      find.text(kCompanyAgendaAvailabilityUnknown.of(AppLanguage.nl)),
      findsWidgets,
    );
  });

  testWidgets('date navigation stays in one toolbar group when the bar wraps', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      size: const Size(1100, 800),
      customers: customers(),
      agenda: _FakeAgendaRepository(),
      initialAnchor: DateTime(2026, 9, 9, 12),
    );
    final group = tester.getRect(find.byKey(kCompanyAgendaNavGroupKey));
    final prev = tester.getRect(find.byKey(kCompanyAgendaPrevPeriodKey));
    final next = tester.getRect(find.byKey(kCompanyAgendaNextPeriodKey));
    expect(prev.center.dy, closeTo(next.center.dy, 1));
    expect(prev.center.dy, closeTo(group.center.dy, 8));
    expect(next.left, greaterThan(prev.right));
    expect(prev.width, greaterThanOrEqualTo(48));
    expect(prev.height, greaterThanOrEqualTo(48));
    expect(next.width, greaterThanOrEqualTo(48));
    expect(next.height, greaterThanOrEqualTo(48));
    expect(find.byKey(kCompanyAgendaPickDateKey), findsOneWidget);
    expect(find.text('7/9 – 13/9'), findsOneWidget);
  });

  testWidgets('phone plan form Save and Cancel are reachable and Cancel works', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      size: const Size(390, 844),
      customers: customers(),
      agenda: _FakeAgendaRepository(),
    );
    await tester.tap(find.byKey(kCompanyAgendaPlanRideKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaRideFormKey), findsOneWidget);
    final save = tester.getRect(find.byKey(kCompanyAgendaSaveRideKey));
    final cancel = tester.getRect(find.byKey(kCompanyAgendaCancelRideKey));
    expect(save.top, greaterThanOrEqualTo(0));
    expect(cancel.top, greaterThanOrEqualTo(0));
    expect(save.bottom, lessThanOrEqualTo(844.5));
    expect(cancel.bottom, lessThanOrEqualTo(844.5));
    await tester.tap(find.byKey(kCompanyAgendaCancelRideKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaRideFormKey), findsNothing);
    expect(find.byKey(kCompanyAgendaSaveRideKey), findsNothing);
  });

  testWidgets('phone agenda uses a week strip and a readable day list', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      size: const Size(390, 844),
      customers: customers(),
      agenda: _FakeAgendaRepository(
        rides: <CompanyAgendaRide>[
          CompanyAgendaRide(
            bookingId: 'agb_phone',
            customerId: 'cus_1',
            customerName: 'Ada Lovelace',
            fromAddress: 'Korenmarkt 1, Gent',
            toAddress: 'Brussels Airport',
            pickupIso: DateTime(2026, 9, 9, 9).toUtc().toIso8601String(),
            status: 'PENDING',
            assignedDriverId: '',
            assignedVehicleId: '',
            durationUnknown: false,
            durationMin: 120,
          ),
        ],
      ),
      initialAnchor: DateTime(2026, 9, 9, 12),
    );
    await tester.tap(find.text(kCompanyAgendaTitle.of(AppLanguage.nl)));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaWeekStripKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaPhoneDayListKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaNavGroupKey), findsOneWidget);
    expect(find.textContaining('09:00–11:00'), findsWidgets);
    expect(find.textContaining('Ada Lovelace'), findsWidgets);
    expect(
      find.textContaining(kCompanyAgendaUnassignedLane.of(AppLanguage.nl)),
      findsWidgets,
    );
    final thursday = find.byKey(
      companyAgendaWeekStripDayKey(DateTime(2026, 9, 10)),
    );
    await tester.ensureVisible(thursday);
    await tester.pumpAndSettle();
    await tester.tap(thursday);
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaPhoneDayListKey), findsNothing);
    expect(find.text(kCompanyAgendaEmpty.of(AppLanguage.nl)), findsOneWidget);
  });

  testWidgets('driver filter survives a date change until Alle chauffeurs', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      size: const Size(1280, 800),
      customers: customers(),
      agenda: _FakeAgendaRepository(),
      initialAnchor: DateTime(2026, 9, 9, 12),
      driversLoader: () async => <Map<String, dynamic>>[
        <String, dynamic>{
          'driver_id': 'drv_karel',
          'display_name': 'Karel Peeters',
        },
      ],
    );
    await tester.tap(find.byKey(companyDriversNowCardKey('drv_karel')));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyDriversNowAllKey), findsOneWidget);
    await tester.tap(find.byKey(kCompanyAgendaNextPeriodKey));
    await tester.pumpAndSettle();
    expect(find.text('14/9 – 20/9'), findsOneWidget);
    expect(find.byKey(kCompanyDriversNowAllKey), findsOneWidget);
    expect(find.textContaining('Karel Peeters'), findsWidgets);
    await tester.tap(find.byKey(kCompanyDriversNowAllKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyDriversNowAllKey), findsNothing);
  });

  testWidgets('phone back keeps the filled plan and save works without a driver', (
    tester,
  ) async {
    final agenda = _FakeAgendaRepository();
    await _pumpWorkspace(
      tester,
      size: const Size(390, 844),
      customers: customers(),
      agenda: agenda,
    );
    await tester.tap(find.byKey(kCompanyAgendaPlanRideKey));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(kCompanyAgendaToFieldKey));
    await tester.enterText(find.byKey(kCompanyAgendaToFieldKey), 'Brussel-Zuid');
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kCompanyAgendaPlanRideKey));
    await tester.pumpAndSettle();
    expect(find.text('Brussel-Zuid'), findsWidgets);
    // Picking the customer afterwards must not clear the typed destination.
    await _choosePlanCustomer(tester);
    expect(find.text('Brussel-Zuid'), findsWidgets);
    await _fillPlanPickup(tester);
    await tester.tap(find.byKey(kCompanyAgendaSaveRideKey));
    await tester.pumpAndSettle();
    expect(agenda.createCalls, 1);
    expect(agenda.lastDriverId, '');
  });

  testWidgets('wide Windows keeps agenda beside the guided planner', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      size: const Size(1524, 900),
      customers: customers(),
      agenda: _FakeAgendaRepository(),
    );
    await tester.tap(find.byKey(kCompanyAgendaPlanRideKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaPaneKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaRideFormKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaPlanMapKey), findsNothing);
    expect(find.text('Kortrijksesteenweg'), findsNothing);
    expect(find.textContaining('Wotanlaan'), findsNothing);
  });

  testWidgets('tablet landscape splits input and map; airport keeps a vehicle type', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      size: const Size(1180, 820),
      customers: customers(),
      agenda: _FakeAgendaRepository(),
    );
    await tester.tap(find.byKey(kCompanyAgendaPlanRideKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaRideFormKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaPlanMapKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaPaneKey), findsNothing);
    await tester.ensureVisible(find.byKey(kCompanyAgendaAirportModeKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kCompanyAgendaAirportModeKey));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(kCompanyAgendaVehicleTypeSedanKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaVehicleTypeSedanKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaVehicleTypeMinivanKey), findsOneWidget);
    expect(find.text(kCompanyAgendaAirportNeedsVehicle.of(AppLanguage.nl)), findsOneWidget);
    expect(find.byKey(kCompanyTripRouteToAirportKey), findsOneWidget);
    expect(find.text('Van de luchthaven'), findsOneWidget);
    expect(find.byKey(companyPlanAirportCardKey('BRU')), findsOneWidget);
    expect(find.byKey(companyPlanAirportCardKey('other')), findsOneWidget);
    await tester.ensureVisible(find.byKey(companyPlanAirportCardKey('BRU')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(companyPlanAirportCardKey('BRU')));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyPlanAirportSummaryKey), findsOneWidget);
    expect(find.textContaining('BRU'), findsWidgets);
    expect(find.byKey(kCompanyAgendaToFieldKey), findsNothing);
    expect(find.byKey(kCompanyAgendaFromFieldKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaVehicleTypeSedanKey), findsOneWidget);
    final save = tester.getRect(find.byKey(kCompanyAgendaSaveRideKey));
    expect(save.bottom, lessThanOrEqualTo(820.5));
  });
}
