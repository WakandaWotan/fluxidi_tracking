import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote_wire.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

void main() {
  test('when_now copies the live clock onto date and time', () {
    final body = <String, dynamic>{
      'from': 'Koekamerstraat 48, Maarkedal',
      'to': 'Brussels Airport',
      'when_now': true,
    };
    customerBookingEnsurePublicScheduleFields(
      body,
      clock: () => DateTime(2026, 9, 16, 8, 47),
    );
    expect(body['date'], '2026-09-16');
    expect(body['time'], '08:47');
    expect(body['from'], 'Koekamerstraat 48, Maarkedal');
    expect(body['to'], 'Brussels Airport');
  });

  test('return_pickup_iso becomes return_date and return_time', () {
    final body = <String, dynamic>{
      'from': 'A',
      'to': 'B',
      'pickup_iso': DateTime(2026, 9, 27, 12).toUtc().toIso8601String(),
      'return_enabled': true,
      'return_pickup_iso': DateTime(2026, 9, 30, 23).toUtc().toIso8601String(),
    };
    customerBookingEnsurePublicScheduleFields(body);
    expect(body['return_date'], customerBookingFormatDateYmd(DateTime(2026, 9, 30, 23)));
    expect(body['return_time'], customerBookingFormatTimeHm(DateTime(2026, 9, 30, 23)));
  });

  test('later pickup_iso becomes local date and time', () {
    final local = DateTime(2026, 9, 16, 14, 5);
    final body = <String, dynamic>{
      'from': 'A',
      'to': 'B',
      'pickup_iso': local.toUtc().toIso8601String(),
    };
    customerBookingEnsurePublicScheduleFields(body);
    expect(body['date'], customerBookingFormatDateYmd(local));
    expect(body['time'], customerBookingFormatTimeHm(local));
  });

  test('never copies flight time onto the public quote schedule', () {
    final body = <String, dynamic>{
      'from': 'A',
      'to': 'B',
      'flight_at': '2026-09-16T18:00:00.000',
      'ride_options': <String, dynamic>{'flightAt': '2026-09-16T18:00:00.000'},
    };
    customerBookingEnsurePublicScheduleFields(
      body,
      clock: () => DateTime(2026, 1, 1, 0, 0),
    );
    expect(body.containsKey('date'), isFalse);
    expect(body.containsKey('time'), isFalse);
  });

  test('does not invent a date when later has no pickup', () {
    final body = <String, dynamic>{'from': 'A', 'to': 'B'};
    customerBookingEnsurePublicScheduleFields(body);
    expect(body.containsKey('date'), isFalse);
    expect(body.containsKey('time'), isFalse);
  });

  test('maps the worker missing-fields error for the customer', () {
    expect(
      customerBookingQuoteIssueFromRaw(
        'StateError: Missing fields: from, to, date, time',
      ),
      kCustomerBookingIssueNeedWhen,
    );
    expect(
      customerBookingQuoteErrorText(
        'Missing fields: from, to, date, time',
        AppLanguage.nl,
      ),
      contains('ophaaltijd'),
    );
    expect(
      customerBookingQuoteErrorText('mapbox_down', AppLanguage.nl),
      contains('opnieuw'),
    );
    expect(
      customerBookingQuoteIssueFromRaw('need_company'),
      kCustomerBookingIssueNeedCompany,
    );
    expect(
      customerBookingQuoteErrorText('need_company', AppLanguage.nl),
      contains('taxibedrijf'),
    );
    expect(
      customerBookingQuoteIssueFromRaw('quote_failed'),
      isNot(kCustomerBookingIssueNeedCompany),
    );
  });

  test('incomplete later ride asks for pickup time only when addresses exist', () {
    const ready = LimousineAddressValue(
      displayText: 'A',
      canonicalLabel: 'A',
      acceptance: LimousineAddressAcceptance.selected,
    );
    expect(
      customerBookingIncompleteQuoteIssue(
        from: ready,
        to: ready,
        whenNow: false,
        pickupLocal: null,
      ),
      kCustomerBookingIssueNeedWhen,
    );
    expect(
      customerBookingIncompleteQuoteIssue(
        from: const LimousineAddressValue(),
        to: ready,
        whenNow: true,
        pickupLocal: null,
      ),
      isNull,
    );
  });

  test('return_pickup_iso becomes return_date and return_time', () {
    final local = DateTime(2026, 9, 30, 23, 0);
    final body = <String, dynamic>{
      'from': 'A',
      'to': 'B',
      'return_enabled': true,
      'return_pickup_iso': local.toUtc().toIso8601String(),
    };
    customerBookingEnsurePublicScheduleFields(body);
    expect(body['return_date'], customerBookingFormatDateYmd(local));
    expect(body['return_time'], customerBookingFormatTimeHm(local));
  });

  test('customer quote client decorates when_now onto public date and time', () {
    final client = CustomerBookingQuoteClient(
      clock: () => DateTime(2026, 9, 16, 9, 15),
    );
    final body = client.decorateBody(
      <String, dynamic>{
        'from': 'A Straat 1',
        'to': 'B Straat 2',
        'when_now': true,
      },
      const CustomerBookingEntryContext(kind: CustomerBookingKind.taxi),
    );
    expect(body['date'], '2026-09-16');
    expect(body['time'], '09:15');
    expect(body['from'], 'A Straat 1');
    expect(body['to'], 'B Straat 2');
  });
}
