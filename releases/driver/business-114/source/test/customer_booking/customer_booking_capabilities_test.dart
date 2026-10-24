import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/customer_booking/reliable_choice_api.dart';

void main() {
  for (final mode in ['manual','reliable_choice','unavailable']) {
    test('authenticated server capabilities preserve $mode rights', () async {
      var requests=0;
      final api=ReliableChoiceApiV1(base:Uri.parse('https://booking.example'),token:'customer-session',client:MockClient((request) async {
        requests++;
        expect(request.method,'POST');
        expect(request.url.path,'/public/customer/booking-capabilities');
        expect(request.headers['authorization'],'Bearer customer-session');
        expect(jsonDecode(request.body),{'public_partner_id':'partner-A'});
        return http.Response(jsonEncode({'ok':true,'schema':'fluxidi-public-booking-capabilities-v1','booking_mode':mode,
          'booking_allowed':mode!='unavailable','automatic_dispatch':mode=='reliable_choice','customer_live_tracking':mode=='reliable_choice'}),200);
      }));
      final rights=await api.capabilities('partner-A');
      expect(rights.mode,mode);expect(rights.liveTracking,mode=='reliable_choice');expect(requests,1);
    });
  }
  test('missing or inconsistent server rights fail without a legacy retry', () async {
    for (final body in [<String,dynamic>{},
      {'booking_mode':'manual','booking_allowed':true,'automatic_dispatch':true,'customer_live_tracking':false},
      {'booking_mode':'manual','booking_allowed':true,'automatic_dispatch':false,'customer_live_tracking':true},
      {'booking_mode':'reliable_choice','booking_allowed':false,'automatic_dispatch':true,'customer_live_tracking':true},
      {'booking_mode':'reliable_choice','booking_allowed':true,'automatic_dispatch':false,'customer_live_tracking':true}]) {
      var calls=0;
      final api=ReliableChoiceApiV1(base:Uri.parse('https://booking.example'),token:'session',client:MockClient((request)async {
        calls++;return http.Response(jsonEncode({'ok':true,'schema':'fluxidi-public-booking-capabilities-v1',...body}),200);
      }));
      await expectLater(api.capabilities('partner-A'),throwsStateError);expect(calls,1);
    }
  });
  test('unavailable server never falls back to ordinary vehicle availability', () async {
    var calls=0;
    final api=ReliableChoiceApiV1(base:Uri.parse('https://booking.example'),token:'session',client:MockClient((request)async {
      calls++;return http.Response('unavailable',503);
    }));
    await expectLater(api.capabilities('partner-A'),throwsStateError);expect(calls,1);
  });
}
