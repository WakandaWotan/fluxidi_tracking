import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_drivers_now.dart';

CompanyAgendaRide _ride({
  required String id,
  required String driverId,
  required String customer,
  required String pickupIso,
  int? durationMin,
}) {
  return CompanyAgendaRide(
    bookingId: id,
    customerId: 'cus_$id',
    customerName: customer,
    fromAddress: 'A',
    toAddress: 'B',
    pickupIso: pickupIso,
    status: 'PENDING',
    assignedDriverId: driverId,
    assignedVehicleId: 'vh_1',
    durationUnknown: durationMin == null,
    durationMin: durationMin,
  );
}

void main() {
  final now = DateTime.utc(2026, 9, 11, 12, 0);

  test('stale or missing updates are not shown as current work status', () {
    final rows = companyDriverNowRows(
      nowUtc: now,
      drivers: <Map<String, dynamic>>[
        <String, dynamic>{
          'driver_id': 'drv_karel',
          'display_name': 'Karel Peeters',
          'availability_status': 'available',
          'work_status_updated_at': '2026-09-11T08:00:00.000Z',
        },
        <String, dynamic>{
          'driver_id': 'drv_amira',
          'display_name': 'Amira Hassan',
          'availability_status': 'available',
          'updated_at': '2026-09-11T11:55:00.000Z',
        },
      ],
      rides: const <CompanyAgendaRide>[],
    );
    expect(rows, hasLength(2));
    expect(rows.first.freshness, CompanyDriverNowFreshness.stale);
    expect(rows.first.workStatusIsCurrent, isFalse);
    expect(rows.first.hasLiveConnection, isFalse);
    expect(rows.last.freshness, CompanyDriverNowFreshness.missing);
    expect(rows.last.workStatusIsCurrent, isFalse);
  });

  test('profile updated_at is not treated as an operational source', () {
    final rows = companyDriverNowRows(
      nowUtc: now,
      drivers: <Map<String, dynamic>>[
        <String, dynamic>{
          'driver_id': 'drv_karel',
          'display_name': 'Karel Peeters',
          'availability_status': 'busy',
          'updated_at': '2026-09-11T11:55:00.000Z',
        },
      ],
      rides: <CompanyAgendaRide>[
        _ride(
          id: 'agb_now',
          driverId: 'drv_karel',
          customer: 'Grace Hopper',
          pickupIso: '2026-09-11T11:30:00.000Z',
          durationMin: 75,
        ),
      ],
    );
    expect(rows.single.freshness, CompanyDriverNowFreshness.missing);
    expect(rows.single.workStatusIsCurrent, isFalse);
    expect(rows.single.currentRide, isNull);
  });

  test(
    'scheduled ride is not current execution; next planned ride stays visible',
    () {
      final rows = companyDriverNowRows(
        nowUtc: now,
        drivers: <Map<String, dynamic>>[
          <String, dynamic>{
            'driver_id': 'drv_karel',
            'display_name': 'Karel Peeters',
            'availability_status': 'busy',
            'work_status_updated_at': '2026-09-11T11:55:00.000Z',
          },
        ],
        rides: <CompanyAgendaRide>[
          _ride(
            id: 'agb_now',
            driverId: 'drv_karel',
            customer: 'Grace Hopper',
            pickupIso: '2026-09-11T11:30:00.000Z',
            durationMin: 75,
          ),
          _ride(
            id: 'agb_next',
            driverId: 'drv_karel',
            customer: 'Ada Lovelace',
            pickupIso: '2026-09-11T14:00:00.000Z',
            durationMin: 60,
          ),
        ],
      );
      expect(rows.single.workStatusIsCurrent, isTrue);
      expect(rows.single.currentRide, isNull);
      expect(rows.single.nextRide?.customerName, 'Ada Lovelace');
    },
  );

  test('executing status can mark the current ride', () {
    final rows = companyDriverNowRows(
      nowUtc: now,
      drivers: <Map<String, dynamic>>[
        <String, dynamic>{
          'driver_id': 'drv_karel',
          'display_name': 'Karel Peeters',
          'work_status_updated_at': '2026-09-11T11:55:00.000Z',
        },
      ],
      rides: <CompanyAgendaRide>[
        CompanyAgendaRide(
          bookingId: 'agb_now',
          customerId: 'cus_now',
          customerName: 'Grace Hopper',
          fromAddress: 'A',
          toAddress: 'B',
          pickupIso: '2026-09-11T11:30:00.000Z',
          status: 'IN_PROGRESS',
          assignedDriverId: 'drv_karel',
          assignedVehicleId: 'vh_1',
          durationUnknown: false,
          durationMin: 75,
        ),
      ],
    );
    expect(rows.single.currentRide?.customerName, 'Grace Hopper');
  });

  test('unknown duration is never treated as a current ride', () {
    final rows = companyDriverNowRows(
      nowUtc: now,
      drivers: <Map<String, dynamic>>[
        <String, dynamic>{
          'driver_id': 'drv_karel',
          'display_name': 'Karel Peeters',
          'work_status_updated_at': '2026-09-11T11:55:00.000Z',
        },
      ],
      rides: <CompanyAgendaRide>[
        _ride(
          id: 'agb_unknown',
          driverId: 'drv_karel',
          customer: 'Ada Lovelace',
          pickupIso: '2026-09-11T11:00:00.000Z',
        ),
      ],
    );
    expect(rows.single.currentRide, isNull);
    expect(rows.single.nextRide, isNull);
  });

  testWidgets('strip never claims a live connection', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyDriversNowStrip(
            language: AppLanguage.nl,
            rows: companyDriverNowRows(
              nowUtc: now,
              drivers: <Map<String, dynamic>>[
                <String, dynamic>{
                  'driver_id': 'drv_karel',
                  'display_name': 'Karel Peeters',
                  'availability_status': 'available',
                  'updated_at': '2026-09-11T11:55:00.000Z',
                },
              ],
              rides: const <CompanyAgendaRide>[],
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(kCompanyDriversNowPaneKey), findsOneWidget);
    expect(
      find.text(kCompanyDriversNowTitle.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(
      find.text(kCompanyDriversNowNoLiveLink.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(find.textContaining('online'), findsNothing);
  });

  testWidgets('next arrow reveals later chauffeur cards', (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 520,
            child: CompanyDriversNowStrip(
              language: AppLanguage.nl,
              rows: companyDriverNowRows(
                nowUtc: now,
                drivers: <Map<String, dynamic>>[
                  for (var i = 1; i <= 8; i++)
                    <String, dynamic>{
                      'driver_id': 'drv_$i',
                      'display_name': 'Chauffeur $i',
                    },
                ],
                rides: const <CompanyAgendaRide>[],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chauffeur 1'), findsOneWidget);
    expect(find.text('Chauffeur 8'), findsNothing);
    expect(find.byKey(kCompanyDriversNowNextKey), findsOneWidget);
    expect(find.byKey(kCompanyDriversNowPrevKey), findsOneWidget);
    await tester.tap(find.byKey(kCompanyDriversNowNextKey));
    await tester.pumpAndSettle();
    expect(find.text('Chauffeur 3'), findsOneWidget);
    await tester.tap(find.byKey(kCompanyDriversNowPrevKey));
    await tester.pumpAndSettle();
    expect(find.text('Chauffeur 1'), findsOneWidget);
  });

  testWidgets('tapping a chauffeur card selects that driver', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyDriversNowStrip(
            language: AppLanguage.nl,
            onSelectDriver: (id) => selected = id,
            rows: companyDriverNowRows(
              nowUtc: now,
              drivers: <Map<String, dynamic>>[
                <String, dynamic>{
                  'driver_id': 'drv_karel',
                  'display_name': 'Karel Peeters',
                },
              ],
              rides: const <CompanyAgendaRide>[],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(companyDriversNowCardKey('drv_karel')));
    await tester.pump();
    expect(selected, 'drv_karel');
  });

  testWidgets('Chauffeurs nu can collapse and hide the card strip', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyDriversNowStrip(
            language: AppLanguage.nl,
            rows: companyDriverNowRows(
              nowUtc: now,
              drivers: <Map<String, dynamic>>[
                <String, dynamic>{
                  'driver_id': 'drv_karel',
                  'display_name': 'Karel Peeters',
                },
              ],
              rides: const <CompanyAgendaRide>[],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyDriversNowListKey), findsOneWidget);
    await tester.tap(find.byKey(kCompanyDriversNowToggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyDriversNowListKey), findsNothing);
    expect(find.text(kCompanyDriversNowTitle.of(AppLanguage.nl)), findsOneWidget);
    await tester.tap(find.byKey(kCompanyDriversNowToggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyDriversNowListKey), findsOneWidget);
  });

  testWidgets('Alle chauffeurs clears a selected chauffeur', (tester) async {
    String? selected = 'drv_karel';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyDriversNowStrip(
            language: AppLanguage.nl,
            selectedDriverId: selected,
            onSelectDriver: (id) => selected = id,
            onClearDriver: () => selected = null,
            rows: companyDriverNowRows(
              nowUtc: now,
              drivers: const <Map<String, dynamic>>[
                <String, dynamic>{
                  'driver_id': 'drv_karel',
                  'display_name': 'Karel Peeters',
                },
              ],
              rides: const <CompanyAgendaRide>[],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyDriversNowAllKey), findsOneWidget);
    expect(find.textContaining('Karel Peeters'), findsWidgets);
    await tester.tap(find.byKey(kCompanyDriversNowAllKey));
    await tester.pump();
    expect(selected, isNull);
  });
}
