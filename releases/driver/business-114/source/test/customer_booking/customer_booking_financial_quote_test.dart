import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_financial_journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_book_payload.dart';

void main() {
  test('P21 financial acceptance preserves reliable choice without changing frozen price inputs', () {
    final choice={'selection_token':'11111111-1111-4111-8111-111111111111','vehicle_id':'VD','kind':'type'};
    final frozen={'from':'Original','to':'Pickup','pickup_mode':'asap','pax':2,'tier':'comfort','vehicle_id':'VD'};
    final quote=parseCompanyPlanQuote({'ok':true,'financial_quote_id':'p21-frozen','financial_quote_expires_at':DateTime.now().add(const Duration(minutes:15)).millisecondsSinceEpoch,'price_incl_vat':119},fingerprint:'p21',financialRequestBody:frozen);
    final accepted=customerBookingBindFinancialQuote({'reliable_choice':choice,'pax':9,'tier':'premium','from':'Changed','payment_mode':'mollie'},quote);
    expect(accepted['reliable_choice'],choice);
    for(final entry in frozen.entries) expect(accepted[entry.key],entry.value,reason:entry.key);
    expect(accepted['financial_quote_id'],'p21-frozen');
    expect(accepted['payment_mode'],'mollie');
  });

  test('unresolved white label partners keep separate acceptance journals', () {
    final client = CustomerBookingQuoteClient(bookingBaseUrl:'https://fixture.test');
    const mario = CustomerBookingEntryContext(kind:CustomerBookingKind.taxi,
      company:CustomerBookingCompany(partnerId:'mario'));
    const other = CustomerBookingEntryContext(kind:CustomerBookingKind.taxi,
      company:CustomerBookingCompany(partnerId:'other'));
    expect(client.acceptanceKey(mario,'guest_device'),
      isNot(client.acceptanceKey(other,'guest_device')));
  });

  test('double tap shares one acceptance and original body survives caller mutation', () async {
    final disk = <String, String>{};
    final response = Completer<http.Response>();
    var calls = 0;
    final client = CustomerBookingQuoteClient(bookingBaseUrl: 'https://fixture.test',
      financialJournal: CustomerFinancialAcceptanceJournal(read: (k) async => disk[k],
        write: (k,v) async { disk[k]=v; }),
      httpPost: (url, headers, raw) { calls++; expect(jsonDecode(raw)['pax'], 2); return response.future; });
    const entry = CustomerBookingEntryContext(kind: CustomerBookingKind.airport,
      company: CustomerBookingCompany(tenantId: 't', companyId: 'c'));
    final body = <String,dynamic>{'financial_quote_id':'id','tenant_id':'t','company_id':'c','pax':2};
    final first = client.book(body: body, entry: entry, recoveryOwner: 'customer');
    final second = client.book(body: body, entry: entry, recoveryOwner: 'customer');
    body['pax']=8;
    response.complete(http.Response('{"ok":true,"booking_id":"same"}',200));
    expect(await first, await second); expect(calls,1);
    expect((await client.pendingAcceptance(entry,'customer'))!['body']['pax'],2);
  });
  test('timeout after server accept and app restart replay exact body; booked response survives another restart', () async {
    final disk = <String, String>{};
    CustomerFinancialAcceptanceJournal journal() => CustomerFinancialAcceptanceJournal(
      read: (k) async => disk[k], write: (k, v) async { disk[k] = v; });
    const entry = CustomerBookingEntryContext(kind: CustomerBookingKind.taxi,
      company: CustomerBookingCompany(tenantId: 'tenant', companyId: 'mario'));
    final body = <String, dynamic>{'tenant_id': 'tenant', 'company_id': 'mario',
      'financial_quote_id': 'quote-id', 'idempotency_key': 'attempt',
      'from': 'Hulst', 'to': 'Antwerpen', 'date': '2026-10-10', 'time': '12:00',
      'pickup_mode': 'asap', 'payment_mode': 'mollie'};
    var calls = 0;
    Future<http.Response> post(Uri url, Map<String, String> headers, String raw) async {
      expect(url.path, '/book'); expect(jsonDecode(raw), body); calls++;
      if (calls == 1) throw TimeoutException('server processed, response lost');
      return http.Response(jsonEncode({'ok': true, 'booking_id': 'same-booking',
        'checkout_url': 'https://checkout.fixture.test/same-payment'}), 200);
    }
    CustomerBookingQuoteClient client() => CustomerBookingQuoteClient(
      bookingBaseUrl: 'https://backend.fixture.test', financialJournal: journal(), httpPost: post);
    await expectLater(client().book(body: body, entry: entry, recoveryOwner: 'customer'), throwsA(isA<TimeoutException>()));
    final restarted = client();
    final checkpoint = await restarted.pendingAcceptance(entry, 'customer');
    expect(checkpoint!['status'], 'pending');
    final result = await restarted.book(body: Map<String, dynamic>.from(checkpoint['body'] as Map),
      entry: entry, recoveryOwner: 'customer');
    expect(result['booking_id'], 'same-booking'); expect(calls, 2);
    final restoredResult = await client().book(body: body, entry: entry, recoveryOwner: 'customer');
    expect(restoredResult, result); expect(calls, 2);
    expect(await client().pendingAcceptance(entry, 'other-customer'), isNull);
    expect(() => restarted.book(body: {...body, 'financial_quote_id': 'new-quote'},
      entry: entry, recoveryOwner: 'customer'), throwsStateError);
  });

  test('accepted request keeps quote ID, original clock, coordinates and return', () {
    final request = <String, dynamic>{'from': 'Hulst', 'to': 'Antwerpen',
      'date': '2026-10-10', 'time': '13:00', 'pax': 2,
      'return_enabled': true, 'return_vehicle_id': 'bus',
      'stops': ['Stop'], 'pickup_mode': 'scheduled'};
    final quote = parseCompanyPlanQuote(<String, dynamic>{'ok': true,
      'financial_quote_id': 'immutable-id', 'financial_quote_expires_at':
        DateTime.now().add(const Duration(minutes: 15)).millisecondsSinceEpoch,
      'price_incl_vat': 119}, fingerprint: 'draft', financialRequestBody: request);
    final accepted = customerBookingBindFinancialQuote(<String, dynamic>{
      'from': 'new coordinates', 'time': '14:00', 'from_lat': 1,
      'name': 'Customer', 'idempotency_key': 'same-attempt',
      'payment_mode': 'mollie', 'mollie_method': 'bancontact'}, quote);
    expect(accepted['financial_quote_id'], 'immutable-id');
    expect(accepted['from'], 'Hulst');
    expect(accepted['time'], '13:00');
    expect(accepted.containsKey('from_lat'), false);
    expect(accepted['return_vehicle_id'], 'bus');
    expect(accepted['stops'], ['Stop']);
    expect(accepted['mollie_method'], 'bancontact');
    expect(accepted['idempotency_key'], 'same-attempt');
    expect(customerBookingQuoteBookFields(quote)['financial_quote_id'], 'immutable-id');
  });
  test('expired quote cannot enter book and legacy remains compatible', () {
    final expired = CompanyPlanQuoteResult(fingerprint: 'x', financialQuoteId: 'id',
      financialRequestBody: const {}, financialQuoteExpiresAt: DateTime(2000));
    expect(() => customerBookingBindFinancialQuote({}, expired), throwsStateError);
    expect(customerBookingBindFinancialQuote({'from': 'legacy'}, null), {'from': 'legacy'});
  });
  test('a merged pair of separately priced legs is never one accepted quote', () {
    const outbound = CompanyPlanQuoteResult(fingerprint: 'out', financialQuoteId: 'out-id', priceInclVat: 10);
    const inbound = CompanyPlanQuoteResult(fingerprint: 'in', financialQuoteId: 'in-id', priceInclVat: 20);
    final merged = companyPlanMergeLegQuotes(outbound: outbound, inbound: inbound);
    expect(merged.financialQuoteId, isEmpty);
  });
}
