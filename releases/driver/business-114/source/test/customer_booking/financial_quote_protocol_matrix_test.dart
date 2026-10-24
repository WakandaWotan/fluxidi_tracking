import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_book_payload.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_financial_journal.dart';

void main() {
  for (final service in ['taxi','mario','airport']) {
    for (final returned in [false,true]) {
      test('actual app API protocol $service return=$returned preserves one quote and payment identity after restart', () async {
        final disk=<String,String>{}; var quotes=0,books=0;
        Map<String,dynamic>? priced;
        final entry=CustomerBookingEntryContext(
          kind:service=='airport'?CustomerBookingKind.airport:CustomerBookingKind.taxi,
          company:CustomerBookingCompany(tenantId:'tenant',companyId:service=='taxi'?'other':'mario',partnerId:service));
        CustomerBookingQuoteClient client() => CustomerBookingQuoteClient(
          bookingBaseUrl:'https://fixture.test',
          financialJournal:CustomerFinancialAcceptanceJournal(read:(k) async=>disk[k],write:(k,v) async{disk[k]=v;}),
          httpPost:(url,headers,raw) async {
            final body=Map<String,dynamic>.from(jsonDecode(raw) as Map);
            if(url.path=='/quote') {
              quotes++; priced=body;
              return http.Response(jsonEncode({'ok':true,'financial_quote_id':'frozen-$service-$returned',
                'financial_quote_expires_at':DateTime.now().add(const Duration(minutes:15)).millisecondsSinceEpoch,
                'price_incl_vat':119}),200);
            }
            expect(url.path,'/book');books++;
            expect(body['financial_quote_id'],'frozen-$service-$returned');
            for(final key in priced!.keys) expect(body[key],priced![key],reason:'financial request '+key);
            return http.Response(jsonEncode({'ok':true,'booking_id':'one-booking',
              'financial_quote_id':body['financial_quote_id'],
              'checkout_url':'https://checkout.fixture.test/one-payment',
              'financial_snapshot':{'money':{'gross_cents':11900,'currency':'EUR'}}}),200);
          });
        final original=client();
        final quote=await original.quote(entry:entry,request:CompanyPlanQuoteRequest(fingerprint:'draft',body:{
          'from':'Hulst','to':'Antwerpen','date':'2026-10-10','time':'13:00','pickup_mode':'scheduled',
          'vehicle_id':'car','pax':2,'bags':1,'stops':['Stop One'],
          'return_enabled':returned,if(returned)...{'return_date':'2026-10-11','return_time':'14:00','return_vehicle_id':'bus'},
          'airport_transfer':service=='airport',
        }));
        expect(quote.financialQuoteId,'frozen-$service-$returned');
        final acceptance=customerBookingBindFinancialQuote({'payment_mode':'mollie','name':'Customer'},quote);
        // Simulate app death after persisting acceptance, before receiving /book.
        await original.financialJournal.save(original.acceptanceKey(entry,'customer:owner'),{'status':'pending','body':acceptance});
        final restarted=client();
        final saved=await restarted.pendingAcceptance(entry,'customer:owner');
        final booked=await restarted.book(entry:entry,body:Map<String,dynamic>.from(saved!['body'] as Map),recoveryOwner:'customer:owner');
        final reopened=await client().book(entry:entry,body:acceptance,recoveryOwner:'customer:owner');
        expect(reopened,booked); expect(quotes,1);expect(books,1);
        expect(reopened['booking_id'],'one-booking');
        expect(reopened['checkout_url'],'https://checkout.fixture.test/one-payment');
        expect(reopened['financial_snapshot']['money']['gross_cents'],11900);
      });
    }
  }
}
