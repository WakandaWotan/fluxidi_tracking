import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_agenda_http.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';

CompanyAgendaRide _ride(String id) {
  return CompanyAgendaRide(
    bookingId: id,
    customerId: 'cus_$id',
    customerName: id,
    fromAddress: 'Gent',
    toAddress: 'Brussel',
    pickupIso: '2026-10-01T08:00:00.000Z',
    status: 'PENDING',
    assignedDriverId: '',
    assignedVehicleId: '',
    durationUnknown: true,
  );
}

CompanyAgendaRidesPage _page({
  required List<String> ids,
  List<String> unscheduled = const <String>[],
  bool hasMore = false,
  String? nextCursor,
}) {
  return CompanyAgendaRidesPage(
    items: ids.map(_ride).toList(),
    unscheduled: unscheduled.map(_ride).toList(),
    hasMore: hasMore,
    nextCursor: nextCursor,
  );
}

void main() {
  test('has_more without a Worker cursor does not request another page', () {
    final parsed = parseCompanyAgendaRidesPage(<String, dynamic>{
      'ok': true,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{'booking_id': 'agb_1'},
      ],
      'has_more': true,
      'next_cursor': null,
    });
    expect(parsed.hasMore, isFalse);
    expect(parsed.nextCursor, isNull);
  });

  test('has_more is never inferred from item count', () {
    final parsed = parseCompanyAgendaRidesPage(<String, dynamic>{
      'ok': true,
      'items': List<Map<String, dynamic>>.generate(
        200,
        (index) => <String, dynamic>{'booking_id': 'agb_$index'},
      ),
    });
    expect(parsed.items.length, 200);
    expect(parsed.hasMore, isFalse);
    expect(parsed.nextCursor, isNull);
  });

  test('collect follows a real cursor past 200 rides without duplicates', () async {
    final seenCursors = <String>[];
    final collected = await collectCompanyAgendaRidePages(
      fetchPage: (cursor) async {
        seenCursors.add(cursor);
        if (cursor.isEmpty) {
          return _page(
            ids: List<String>.generate(200, (index) => 'agb_$index'),
            unscheduled: const <String>['agb_open'],
            hasMore: true,
            nextCursor: 'page-2',
          );
        }
        expect(cursor, 'page-2');
        return _page(
          ids: List<String>.generate(5, (index) => 'agb_${200 + index}'),
          unscheduled: const <String>['agb_open'],
        );
      },
    );
    expect(seenCursors, <String>['', 'page-2']);
    expect(collected.incomplete, isFalse);
    expect(collected.rides.length, 206);
    expect(collected.rides.map((ride) => ride.bookingId).toSet().length, 206);
    expect(collected.rides.last.bookingId, 'agb_204');
  });

  test('collect stops at the hard page cap', () async {
    var fetches = 0;
    final collected = await collectCompanyAgendaRidePages(
      fetchPage: (cursor) async {
        fetches += 1;
        final start = cursor.isEmpty ? 0 : int.parse(cursor);
        return _page(
          ids: List<String>.generate(
            200,
            (index) => 'agb_${start + index}',
          ),
          hasMore: true,
          nextCursor: '${start + 200}',
        );
      },
    );
    expect(fetches, kCompanyAgendaHttpMaxPages);
    expect(collected.incomplete, isTrue);
    expect(
      collected.rides.length,
      kCompanyAgendaHttpMaxPages * kCompanyAgendaHttpPageLimit,
    );
  });

  test('split outbound and return stay distinct in one collection', () async {
    final collected = await collectCompanyAgendaRidePages(
      fetchPage: (cursor) async {
        return CompanyAgendaRidesPage(
          items: <CompanyAgendaRide>[
            CompanyAgendaRide(
              bookingId: 'agb_rt',
              customerId: 'cus',
              customerName: 'Retour',
              fromAddress: 'Gent',
              toAddress: 'Brussel',
              pickupIso: '2026-09-18T08:00:00.000Z',
              status: 'PENDING',
              assignedDriverId: '',
              assignedVehicleId: '',
              durationUnknown: false,
              durationMin: 40,
              agendaItemId: 'agb_rt:OUTBOUND',
              parentBookingId: 'agb_rt',
              legType: 'outbound',
            ),
            CompanyAgendaRide(
              bookingId: 'agb_rt',
              customerId: 'cus',
              customerName: 'Retour',
              fromAddress: 'Brussel',
              toAddress: 'Gent',
              pickupIso: '2026-09-18T14:00:00.000Z',
              status: 'PENDING',
              assignedDriverId: '',
              assignedVehicleId: '',
              durationUnknown: false,
              durationMin: 40,
              agendaItemId: 'agb_rt:RETURN',
              parentBookingId: 'agb_rt',
              legType: 'return',
            ),
          ],
          unscheduled: const <CompanyAgendaRide>[],
          hasMore: false,
        );
      },
    );
    expect(collected.rides.length, 2);
    expect(
      collected.rides.map((ride) => ride.collectionId).toSet(),
      <String>{'agb_rt:OUTBOUND', 'agb_rt:RETURN'},
    );
  });
}
