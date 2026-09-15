import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_http.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_booking_detail_page.dart';
import 'package:fluxidi_tracking/company/company_crew_combo.dart';
import 'package:fluxidi_tracking/company/company_plan_presence.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';

class _SilentAgenda extends CompanyAgendaRepository {
  _SilentAgenda()
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
}

CompanyCrewCombo _combo({
  required String driverId,
  required String name,
  required String vehicleId,
  required String vehicleName,
}) {
  return CompanyCrewCombo(
    driverId: driverId,
    vehicleId: vehicleId,
    driver: <String, dynamic>{
      'driver_id': driverId,
      'display_name': name,
      'is_active': true,
    },
    vehicle: <String, dynamic>{
      'vehicle_id': vehicleId,
      'vehicle_name': vehicleName,
      'license_plate': '1-FLX-001',
      'is_active': true,
    },
    presence: const CompanyPlanPresence(
      tone: CompanyPlanPresenceTone.available,
      code: 'available',
      icon: Icons.check_circle_outline,
    ),
  );
}

Future<void> _golden(WidgetTester tester, Size size, String name, Widget child) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/company_plan_visual_$name.png'),
  );
}

void main() {
  tearDown(() async {
    // Surface size is reset per test.
  });

  testWidgets('visual split assignment cards', (tester) async {
    await _golden(
      tester,
      const Size(390, 844),
      'split_assignment_phone',
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CompanyCrewComboCard(
            language: AppLanguage.nl,
            title: kCompanyAgendaAssignmentOutbound.of(AppLanguage.nl),
            combo: _combo(
              driverId: 'drv_karel',
              name: 'Karel Peeters',
              vehicleId: 'vh_1',
              vehicleName: 'S-Klasse',
            ),
            plannedLocal: DateTime(2026, 9, 15, 11, 5),
            statusText: 'Beschikbaar',
            includePlate: true,
          ),
          const SizedBox(height: 12),
          CompanyCrewComboCard(
            language: AppLanguage.nl,
            title: kCompanyAgendaAssignmentReturn.of(AppLanguage.nl),
            combo: _combo(
              driverId: 'drv_amira',
              name: 'Amira Hassan',
              vehicleId: 'vh_2',
              vehicleName: 'E-Klasse',
            ),
            plannedLocal: DateTime(2026, 9, 15, 16, 30),
            statusText: 'Beschikbaar',
            includePlate: true,
          ),
          const SizedBox(height: 16),
          Text(
            formatCompanyPlanQuoteLegLine(
              label: kCompanyRoundtripOutbound.of(AppLanguage.nl),
              result: const CompanyPlanQuoteResult(
                fingerprint: 'v',
                durationMin: 41,
                distanceKm: 40.6,
                priceInclVat: 81.7,
                outboundPriceInclVat: 81.7,
                returnDurationMin: 38,
                returnDistanceKm: 39.2,
                returnPriceInclVat: 74.2,
                currency: 'EUR',
                priceAvailable: true,
              ),
              inbound: false,
              language: AppLanguage.nl,
              pickupLocal: DateTime(2026, 9, 15, 11, 5),
            ),
          ),
          Text(
            formatCompanyPlanQuoteLegLine(
              label: kCompanyRoundtripReturn.of(AppLanguage.nl),
              result: const CompanyPlanQuoteResult(
                fingerprint: 'v',
                durationMin: 41,
                distanceKm: 40.6,
                priceInclVat: 155.9,
                outboundPriceInclVat: 81.7,
                returnDurationMin: 38,
                returnDistanceKm: 39.2,
                returnPriceInclVat: 74.2,
                currency: 'EUR',
                priceAvailable: true,
              ),
              inbound: true,
              language: AppLanguage.nl,
              pickupLocal: DateTime(2026, 9, 15, 16, 30),
            ),
          ),
          const Text('Totaal · €155,90'),
        ],
      ),
    );
  });

  testWidgets('visual booking detail with coordinates', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyBookingDetailPage(
          bookingId: 'agb_visual',
          language: AppLanguage.nl,
          agendaRepository: _SilentAgenda(),
          loader: (id) async => <String, dynamic>{
            'ok': true,
            'status': 'PENDING',
            'record': <String, dynamic>{
              'booking_id': id,
              'customer_name': 'Founder Fluxidi',
              'from': 'Koekamerstraat 48A, 9688 Schorisse',
              'to': 'Brussels South Charleroi Airport',
              'pickup_iso': '2026-09-15T09:05:00.000Z',
              'pickup_lat': 50.7701,
              'pickup_lon': 3.6612,
              'dropoff_lat': 50.4592,
              'dropoff_lon': 4.4537,
              'duration_min': 71,
              'distance_km': 85.6,
              'amount_incl_vat': 346.7,
              'currency': 'EUR',
              'pax': 3,
              'bags': 2,
              'assigned_driver_id': 'drv_karel',
              'assigned_vehicle_id': 'vh_1',
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
              'vehicle_type': 'sedan',
            },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Vul een geldig vertrek'), findsNothing);
    expect(find.textContaining('Koekamerstraat 48A'), findsWidgets);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/company_plan_visual_booking_detail_phone.png'),
    );
  });
}
