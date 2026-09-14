import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';

void main() {
  test('week period starts Monday and stays closed at the far end', () {
    final wednesday = DateTime(2026, 9, 9, 15, 30);
    final period = companyAgendaPeriodFor(
      view: CompanyAgendaView.week,
      anchorLocal: wednesday,
    );
    final from = period.fromUtc.toLocal();
    expect(from.weekday, DateTime.monday);
    expect(from.hour, 0);
    expect(period.toUtc.difference(period.fromUtc), const Duration(days: 7));
    expect(period.cacheKey.contains('week'), isTrue);
  });

  test('by-driver period is the local calendar day', () {
    final day = DateTime(2026, 9, 11, 19, 45);
    final period = companyAgendaPeriodFor(
      view: CompanyAgendaView.byDriver,
      anchorLocal: day,
    );
    expect(period.fromUtc.toLocal(), DateTime(2026, 9, 11));
    expect(period.toUtc.toLocal(), DateTime(2026, 9, 12));
    expect(period.cacheKey.contains('byDriver'), isTrue);
  });

  test('next week from 7-13 September starts Monday 14/9', () {
    final current = companyAgendaPeriodFor(
      view: CompanyAgendaView.week,
      anchorLocal: DateTime(2026, 9, 12, 16),
    );
    expect(current.fromUtc.toLocal(), DateTime(2026, 9, 7));
    expect(
      current.toUtc.toLocal().subtract(const Duration(minutes: 1)).day,
      13,
    );
    final next = companyAgendaPeriodFor(
      view: CompanyAgendaView.week,
      anchorLocal: DateTime(2026, 9, 12).add(const Duration(days: 7)),
    );
    expect(next.fromUtc.toLocal(), DateTime(2026, 9, 14));
    expect(next.fromUtc.toLocal().weekday, DateTime.monday);
  });

  test('linked bookings period covers three weeks around today', () {
    final period = companyAgendaLinkedBookingsPeriod(DateTime(2026, 9, 13, 8));
    expect(period.fromUtc.toLocal(), DateTime(2026, 8, 23));
    expect(period.toUtc.toLocal(), DateTime(2026, 10, 4));
  });

  test('day period is the local calendar day', () {
    final day = DateTime(2026, 9, 11, 19, 45);
    final period = companyAgendaPeriodFor(
      view: CompanyAgendaView.day,
      anchorLocal: day,
    );
    expect(period.fromUtc.toLocal(), DateTime(2026, 9, 11));
    expect(period.toUtc.toLocal(), DateTime(2026, 9, 12));
  });

  test('ride parser keeps unknown duration and unassigned visible', () {
    final ride = CompanyAgendaRide.fromMap(<String, dynamic>{
      'booking_id': 'agb_1',
      'customer_name': 'Ada Lovelace',
      'from': 'Gent',
      'to': 'Brussel',
      'pickup_iso': '2026-09-11T08:00:00.000Z',
      'status': 'PENDING',
      'duration_unknown': true,
      'do_not_dispatch': true,
    });
    expect(ride.bookingId, 'agb_1');
    expect(ride.durationUnknown, isTrue);
    expect(ride.durationMin, isNull);
    expect(ride.isUnassigned, isTrue);
    expect(ride.doNotDispatch, isTrue);
    expect(ride.pickupUtc, DateTime.parse('2026-09-11T08:00:00.000Z').toUtc());
  });

  test('address line uses reusable customer fields', () {
    const address = CompanyCustomerAddress(
      label: 'Thuis',
      line1: 'Korenmarkt 1',
      city: 'Gent',
    );
    expect(companyCustomerAddressLine(address), 'Thuis · Korenmarkt 1 · Gent');
  });
}
