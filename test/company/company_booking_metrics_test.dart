import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_http.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_booking_detail_page.dart';
import 'package:fluxidi_tracking/company/company_booking_metrics.dart';

void main() {
  test('customer-app aliases keep price and duration', () {
    final raw = <String, dynamic>{
      'ok': true,
      'record': <String, dynamic>{
        'booking': <String, dynamic>{
          'duration_route_min': 29,
          'currency': 'EUR',
        },
        'quote': <String, dynamic>{
          'duration_min': 29,
          'pricing': <String, dynamic>{
            'price_incl_vat': '46.70',
            'currency': 'EUR',
            'pricing_source': 'route_calc',
          },
        },
        'operational_legs': <Map<String, dynamic>>[
          <String, dynamic>{
            'duration_min': 29,
            'price_incl_vat': 46.7,
          },
        ],
      },
    };
    expect(resolveCompanyBookingDurationMin(raw), 29);
    expect(resolveCompanyBookingPriceInclVat(raw), 46.7);
    expect(formatCompanyBookingMoney(46.7), '46,70 EUR');
    expect(formatCompanyBookingDurationMin(29), '29 min');
    final ride = CompanyAgendaRide.fromMap(<String, dynamic>{
      'booking_id': '2026-09-012',
      'duration_route_min': 29,
      'price_incl_vat': '46.70',
      'currency': 'EUR',
      'pickup_iso': '2026-09-15T08:00:00.000Z',
    });
    expect(ride.durationUnknown, isFalse);
    expect(ride.durationMin, 29);
    expect(ride.priceInclVat, 46.7);
  });

  test('live FLX-00001 bookings keep known duration and price', () {
    const cases = <(String, int, num)>[
      ('2026-09-012', 29, 46.7),
      ('2026-09-008', 41, 104.6),
      ('2026-09-011', 33, 58.4),
    ];
    for (final row in cases) {
      final raw = <String, dynamic>{
        'booking_id': row.$1,
        'record': <String, dynamic>{
          'booking': <String, dynamic>{
            'duration_route_min': row.$2,
            'currency': 'EUR',
          },
          'quote': <String, dynamic>{
            'duration_min': row.$2,
            'pricing': <String, dynamic>{
              'price_incl_vat': row.$3.toStringAsFixed(2),
              'currency': 'EUR',
              'pricing_source': 'route_calc',
            },
          },
          'operational_legs': <Map<String, dynamic>>[
            <String, dynamic>{
              'duration_min': row.$2,
              'price_incl_vat': row.$3,
            },
          ],
        },
      };
      expect(resolveCompanyBookingDurationMin(raw), row.$2, reason: row.$1);
      expect(resolveCompanyBookingPriceInclVat(raw), row.$3, reason: row.$1);
      expect(resolveCompanyBookingCurrency(raw), 'EUR', reason: row.$1);
      final ride = CompanyAgendaRide.fromMap(<String, dynamic>{
        'booking_id': row.$1,
        'duration_route_min': row.$2,
        'price_incl_vat': row.$3.toStringAsFixed(2),
        'currency': 'EUR',
        'pricing_source': 'route_calc',
        'pickup_iso': '2026-09-15T08:00:00.000Z',
      });
      expect(ride.durationUnknown, isFalse, reason: row.$1);
      expect(ride.durationMin, row.$2, reason: row.$1);
      expect(ride.priceInclVat, row.$3, reason: row.$1);
    }
  });

  test('legacy booking without duration stays readable', () {
    final ride = CompanyAgendaRide.fromMap(<String, dynamic>{
      'booking_id': 'legacy',
      'pickup_iso': '2026-09-15T08:00:00.000Z',
      'duration_unknown': true,
    });
    expect(ride.durationUnknown, isTrue);
    expect(ride.durationMin, isNull);
    expect(ride.priceInclVat, isNull);
    expect(resolveCompanyBookingDurationMin(const <String, dynamic>{}), isNull);
  });

  testWidgets('detail shows aliases and overlap uses booking duration', (
    tester,
  ) async {
    int? seenDuration;
    final agenda = CompanyAgendaRepository(
      scopeResolver: () => const <String, String>{
        'tenant_id': 'fluxidi_fluxidi_ddmh9g',
        'company_id': 'fluxidi_fluxidi_ddmh9g',
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
            seenDuration = durationMin;
            return const CompanyAgendaOverlapCheck.ok();
          },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyBookingDetailPage(
          bookingId: '2026-09-012',
          language: AppLanguage.nl,
          agendaRepository: agenda,
          loader: (id) async => <String, dynamic>{
            'ok': true,
            'record': <String, dynamic>{
              'booking': <String, dynamic>{
                'customer_name': 'Ada Lovelace',
                'from': 'Maarkedal',
                'to': 'Ronse',
                'pickup_iso': '2026-09-15T08:00:00.000Z',
                'duration_route_min': 29,
                'currency': 'EUR',
              },
              'quote': <String, dynamic>{
                'duration_min': 29,
                'pricing': <String, dynamic>{
                  'price_incl_vat': '46.70',
                  'currency': 'EUR',
                },
              },
            },
          },
          driversLoader: () async => <Map<String, dynamic>>[
            <String, dynamic>{
              'driver_id': 'drv_karel',
              'display_name': 'Karel Peeters',
            },
          ],
          vehiclesLoader: () async => const <Map<String, dynamic>>[],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('46,70 EUR'), findsOneWidget);
    expect(find.text('29 min'), findsOneWidget);
    await tester.tap(find.byKey(kCompanyAgendaAssignDriverKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Karel Peeters').last);
    await tester.pumpAndSettle();
    expect(seenDuration, 29);
    expect(
      find.text(kCompanyAgendaAvailabilityUnknown.of(AppLanguage.nl)),
      findsNothing,
    );
  });
}
