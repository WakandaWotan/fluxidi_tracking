import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer.dart';

Map<String,dynamic> receipt() => {'schema':'fluxidi-scheduled-readiness-v1',
  'readiness_type':'scheduled_readiness','human_acceptance_required':false,
  'tenant_id':'T','company_id':'C','driver_id':'D','vehicle_id':'V',
  'booking_id':'B','offer_id':'O','version':1,
  'ack_deadline_ms':DateTime.now().millisecondsSinceEpoch+30000,
  'pickup_iso':DateTime.now().add(const Duration(hours:1)).toUtc().toIso8601String()};

void main() {
  for(final field in ['tenant_id','company_id','driver_id','vehicle_id',
    'schema','readiness_type','human_acceptance_required','version','pickup_iso']) {
    test('readiness rejects malformed or foreign $field before any ACK', () async {
      final row=receipt(); row[field]=field=='human_acceptance_required'?true:field=='version'?0:'foreign';
      final paths=<String>[];
      final client=DriverRideOfferClient(baseUrl:'https://fixture.invalid',token:'fixture',
        vehicleId:'V',driverId:'D',tenantId:'T',companyId:'C',client:MockClient((r)async {
          paths.add(r.url.path);
          return http.Response(jsonEncode({'ok':true,'vehicle_id':'V','offers':[],'legacy_receipts':[row]}),200);
        }));
      await expectLater(client.offers(), throwsFormatException);
      expect(paths, ['/public/driver/dispatch/offers']);
      expect(client.scheduledReadiness,isEmpty);
      client.close();
    });
  }
  test('paired receipt has no human offer, alert or decision; explicit readiness ACK uses current owner', () async {
    final paths=<String>[], bodies=<Map<String,dynamic>>[];
    final client=DriverRideOfferClient(baseUrl:'https://fixture.invalid',token:'fixture',
      vehicleId:'V',driverId:'D',tenantId:'T',companyId:'C',client:MockClient((r)async {
        paths.add(r.url.path); bodies.add(jsonDecode(r.body));
        return http.Response(jsonEncode(r.url.path.endsWith('/offers')
          ? {'ok':true,'vehicle_id':'V','offers':[],'legacy_receipts':[receipt()]}
          : {'ok':true}),200);
      }));
    expect(await client.offers(),isEmpty);
    expect(paths.length,1);
    final readiness=client.scheduledReadiness.single;
    await client.acknowledgeScheduledReadiness(readiness,isCurrent:()=>false);
    expect(paths.length,1,reason:'Driver switch retires the previous receipt');
    await client.acknowledgeScheduledReadiness(readiness,isCurrent:()=>true);
    expect(paths.last,'/public/driver/dispatch/ack');
    expect(bodies.last,{'offer_id':'O','version':1});
    expect(paths.where((p)=>p.endsWith('/decision')),isEmpty);
    client.close();
  });
  test('expired readiness never ACKs; missing optional channel preserves older servers', () async {
    final row=receipt()..['ack_deadline_ms']=0;
    var calls=0;
    final client=DriverRideOfferClient(baseUrl:'https://fixture.invalid',token:'fixture',
      vehicleId:'V',driverId:'D',tenantId:'T',companyId:'C',client:MockClient((r)async {
        calls++;
        return http.Response(jsonEncode({'ok':true,'vehicle_id':'V','offers':[],
          if(calls==1)'legacy_receipts':[row]}),200);
      }));
    await client.offers();
    await client.acknowledgeScheduledReadiness(client.scheduledReadiness.single,isCurrent:()=>true);
    expect(calls,1);
    expect(await client.offers(),isEmpty);
    expect(client.scheduledReadiness,isEmpty);
    client.close();
  });
}
