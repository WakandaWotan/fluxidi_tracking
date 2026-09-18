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

  test('stored total and two 200 euro legs keep 400', () {
    expect(
      resolveCompanyBookingPriceInclVat(<String, dynamic>{
        'record': <String, dynamic>{
          'booking': <String, dynamic>{
            'price_incl_vat': 200,
            'total_price_incl_vat': 400,
            'return_price_incl_vat': 200,
          },
        },
      }),
      400,
    );
    expect(
      resolveCompanyBookingPriceInclVat(<String, dynamic>{
        'record': <String, dynamic>{
          'operational_legs': <Map<String, dynamic>>[
            <String, dynamic>{
              'leg_type': 'outbound',
              'price_incl_vat': 200,
            },
            <String, dynamic>{
              'leg_type': 'return',
              'price_incl_vat': 200,
            },
          ],
        },
      }),
      400,
    );
  });

  test('stored outbound plus return prices become the full total', () {
    expect(
      resolveCompanyBookingPriceInclVat(<String, dynamic>{
        'price_incl_vat': 200,
        'return_price_incl_vat': 200,
      }),
      400,
    );
    expect(
      resolveCompanyBookingPriceInclVat(<String, dynamic>{
        'record': <String, dynamic>{
          'quote': <String, dynamic>{
            'total_price_incl_vat': 400,
            'price_incl_vat': 200,
          },
        },
      }),
      400,
    );
    expect(
      resolveCompanyBookingPriceInclVat(<String, dynamic>{
        'record': <String, dynamic>{
          'operational_legs': <Map<String, dynamic>>[
            <String, dynamic>{
              'leg_type': 'outbound',
              'price_incl_vat': 200,
            },
            <String, dynamic>{
              'leg_type': 'return',
              'price_incl_vat': 200,
            },
          ],
        },
      }),
      400,
    );
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
              // Only an active driver is assignable.
              'is_active': true,
            },
          ],
          vehiclesLoader: () async => const <Map<String, dynamic>>[],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('46,70 EUR'), findsOneWidget);
    expect(find.text('29 min'), findsOneWidget);
    // The assign control is a search field; tapping its subtree key hits the
    // wrapper, so drive the field the operator actually touches.
    final assignField = find.descendant(
      of: find.byKey(kCompanyAgendaAssignDriverKey),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(assignField);
    await tester.pumpAndSettle();
    await tester.tap(assignField);
    await tester.pumpAndSettle();
    // The option label carries the crew combo (driver plus vehicle/plate), so
    // match on the driver name inside it.
    final option = find.textContaining('Karel Peeters').last;
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    await tester.tap(option, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(seenDuration, 29);
    expect(
      find.text(kCompanyAgendaAvailabilityUnknown.of(AppLanguage.nl)),
      findsNothing,
    );
  });

  testWidgets('stored quote breakdown is shown instead of an empty expander', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyBookingDetailPage(
          bookingId: 'PLN-2026-000418',
          language: AppLanguage.nl,
          loader: (id) async => <String, dynamic>{
            'ok': true,
            'record': <String, dynamic>{
              'booking': <String, dynamic>{
                'customer_name': 'Ada Lovelace',
                'from': 'Maarkedal',
                'to': 'Ronse',
                'pickup_iso': '2026-09-15T08:00:00.000Z',
                'duration_route_min': 86,
                'price_incl_vat': 104.6,
                'currency': 'EUR',
              },
              'quote': <String, dynamic>{
                'pricing': <String, dynamic>{
                  'price_incl_vat': 104.6,
                  'currency': 'EUR',
                  'breakdown': <String, dynamic>{
                    'start_fee_ex': 12.5,
                    'distance_cost_ex': 60,
                    'time_cost_ex': 14,
                    'total_incl': 104.6,
                  },
                },
              },
            },
          },
          driversLoader: () async => const <Map<String, dynamic>>[],
          vehiclesLoader: () async => const <Map<String, dynamic>>[],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('104,60 EUR'), findsOneWidget);
    expect(find.text('86 min'), findsOneWidget);
    await tester.ensureVisible(
      find.text(kCompanyAgendaPriceBreakdown.of(AppLanguage.nl)),
    );
    await tester.tap(find.text(kCompanyAgendaPriceBreakdown.of(AppLanguage.nl)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Starttarief'), findsOneWidget);
    expect(find.textContaining('Totaal'), findsWidgets);
    expect(
      find.byKey(kCompanyBookingDetailPriceBreakdownMissingKey),
      findsNothing,
    );
  });
}
