import 'dart:convert';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/company/company_vehicle_pairing_page.dart';

void main() {
 for(final lang in ['nl','en','fr','es','de']) {
  for(final action in ['switch','unlink']) {
   testWidgets('admin QR explanation and payload agree $lang $action',(tester) async {
    final client=CompanyVehiclePairingClient(baseUrl:'https://synthetic.invalid',token:'SYNTHETIC',tenantId:'T',companyId:'C',vehicleId:'V0',client:MockClient((r) async {
     if(r.url.path.endsWith('/list'))return http.Response(jsonEncode({'ok':true,'vehicle_id':'V0','items':[{'device_id':'old','vehicle_id':'V0','expires_at_ms':DateTime.now().millisecondsSinceEpoch+300000,'revoked':false,'status':'paired'}]}),200);
     if(r.url.path.endsWith('/create-transition'))return http.Response(jsonEncode({'ok':true,'expires_at_ms':DateTime.now().millisecondsSinceEpoch+300000,'qr_payload':{'kind':'fluxidi_vehicle_device_transition','version':1,'tenant_id':'T','company_id':'C','device_id':'old','operation':action,'vehicle_id':action=='switch'?'V1':null,'challenge_id':'challenge','pairing_token':'a'*64}}),200);
     return http.Response('{}',503);
    }));
    await tester.pumpWidget(MaterialApp(home:CompanyVehiclePairingPage(client:client,vehicleLabel:'Synthetic vehicle',language:lang,targetVehicles:const {'V1':'Target'})));
    await tester.pumpAndSettle();
    final menu=tester.widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>));
    menu.onSelected!(action);await tester.pumpAndSettle();
    if(action=='switch'){await tester.tap(find.text('Target'));await tester.pumpAndSettle();}
    await tester.tap(find.widgetWithText(FilledButton,'OK'));await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    final instruction=tester.widget<Text>(find.byKey(const ValueKey('device_qr_instructions'))).data!;
    expect(instruction,contains({'nl':'overeenkomstige actie','en':'matching action','fr':'action correspondante','es':'acción correspondiente','de':'passenden Aktion'}[lang]!));
    expect(find.text({'nl':action=='switch'?'Voertuigwissel toestaan':'Toestelontkoppeling toestaan','en':action=='switch'?'Authorize vehicle switch':'Authorize device unlink','fr':action=='switch'?'Autoriser le changement de véhicule':'Autoriser la dissociation','es':action=='switch'?'Autorizar cambio de vehículo':'Autorizar desvinculación','de':action=='switch'?'Fahrzeugwechsel autorisieren':'Gerätetrennung autorisieren'}[lang]!),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
   });
  }
 }

 for(final operation in ['switch','unlink'])test('transition QR is scoped and never exports an admin credential: $operation',()async{
  final transport=MockClient((r)async{
   expect(r.headers['authorization'],'Bearer SYNTHETIC_ADMIN');expect(r.url.path,'/admin/company/vehicle-device/create-transition');
   expect(jsonDecode(r.body)['operation'],operation);
   return http.Response(jsonEncode({'ok':true,'expires_at_ms':DateTime.now().millisecondsSinceEpoch+300000,'qr_payload':{'kind':'fluxidi_vehicle_device_transition','version':1,'tenant_id':'T','company_id':'C','device_id':'old','operation':operation,'vehicle_id':operation=='switch'?'V1':null,'challenge_id':'challenge','pairing_token':'a'*64,'admin_token':'MUST_NOT_EXPORT','url':'https://foreign.invalid'}}),200);
  });
  final client=CompanyVehiclePairingClient(baseUrl:'https://synthetic.invalid',token:'SYNTHETIC_ADMIN',tenantId:'T',companyId:'C',vehicleId:'V0',client:transport);
  final grant=await client.authorizeTransition('old',operation,targetVehicle:'V1');expect(grant['qr_payload']['operation'],operation);expect(jsonEncode(grant).contains('MUST_NOT_EXPORT'),false);expect(jsonEncode(grant).contains('foreign.invalid'),false);client.close();
 });

  test(
    'recovery client verifies original chauffeur and ending instead of accepting bare ok',
    () async {
      var valid = false;
      final command = {
        'driver_id': 'tom',
        'duty_id': 'shift',
        'device_id': 'old',
        'command_id': 'same-command',
        'expected_version': 2,
        'reason': 'device_lost',
        'role': 'untrusted',
      };
      final client = CompanyVehiclePairingClient(
        baseUrl: 'https://fixture.invalid',
        token: 'company-fixture',
        tenantId: '',
        companyId: 'c',
        vehicleId: 'v',
        client: MockClient((request) async {
          expect(request.url.path, '/admin/company/vehicle-duty-recover');
          final body = jsonDecode(request.body);
          expect(body.containsKey('role'), false);
          expect(body['command_id'], 'same-command');
          return http.Response(
            jsonEncode({
              'ok': true,
              if (valid) ...{
                'version': 3,
                'duty': {
                  'duty_id': 'shift',
                  'driver_id': 'tom',
                  'vehicle_id': 'v',
                  'ended_at_ms': 1000,
                  'recovery': {
                    'role': 'company_admin',
                    'reason': 'device_lost',
                    'device_id': 'old',
                  },
                },
              },
            }),
            200,
          );
        }),
      );
      await expectLater(client.recoverDuty(command), throwsA(isA<Exception>()));
      valid = true;
      await client.recoverDuty(command);
      client.close();
    },
  );
  test(
    'company QR derives tenant server-side and excludes admin bearer and supplied URL',
    () async {
      final transport = MockClient((request) async {
        final body = jsonDecode(request.body);
        expect(body.containsKey('tenant_id'), false);
        expect(body['vehicle_id'], 'existing-v');
        expect(request.headers['authorization'], 'Bearer company-fixture');
        return http.Response(
          jsonEncode({
            'ok': true,
            'vehicle_id': 'existing-v',
            'expires_at_ms': 123456,
            'qr_payload': {
              'kind': 'fluxidi_vehicle_device',
              'version': 1,
              'tenant_id': 'separate-tenant',
              'company_id': 'c',
              'challenge_id': 'challenge',
              'pairing_token': 'a' * 64,
              'url': 'https://untrusted.invalid',
              'admin_token': 'forbidden',
            },
          }),
          200,
        );
      });
      final client = CompanyVehiclePairingClient(
        baseUrl: 'https://fixture.invalid',
        token: 'company-fixture',
        tenantId: '',
        companyId: 'c',
        vehicleId: 'existing-v',
        client: transport,
      );
      final result = await client.create();
      expect(result['qr_payload']['tenant_id'], 'separate-tenant');
      expect(jsonEncode(result).contains('forbidden'), false);
      expect(jsonEncode(result).contains('untrusted'), false);
      client.close();
    },
  );
  test('foreign company QR is rejected', () async {
    final transport = MockClient(
      (_) async => http.Response(
        '{"ok":true,"vehicle_id":"v","expires_at_ms":1,"qr_payload":{"company_id":"foreign"}}',
        200,
      ),
    );
    final client = CompanyVehiclePairingClient(
      baseUrl: 'https://fixture.invalid',
      token: 'company-fixture',
      tenantId: 't',
      companyId: 'c',
      vehicleId: 'v',
      client: transport,
    );
    await expectLater(client.create(), throwsStateError);
    client.close();
  });
  test(
    'inventory is scoped metadata only and revoke includes selected vehicle',
    () async {
      final transport = MockClient((request) async {
        final body = jsonDecode(request.body);
        expect(body['company_id'], 'c');
        expect(body['vehicle_id'], 'v');
        if (request.url.path.endsWith('/revoke')) {
          expect(body['device_id'], 'device');
          return http.Response('{"ok":true}', 200);
        }
        return http.Response(
          jsonEncode({
            'ok': true,
            'vehicle_id': 'v',
            'cursor': null,
            'items': [
              {
                'device_id': 'device',
                'vehicle_id': 'v',
                'expires_at_ms': 123456,
                'revoked': false,
                'status': 'paired',
                'token_hash': 'must-not-retain',
              },
            ],
          }),
          200,
        );
      });
      final client = CompanyVehiclePairingClient(
        baseUrl: 'https://fixture.invalid',
        token: 'company-fixture',
        tenantId: '',
        companyId: 'c',
        vehicleId: 'v',
        client: transport,
      );
      expect(
        jsonEncode(await client.devices()).contains('must-not-retain'),
        false,
      );
      await client.revoke('device');
      client.close();
    },
  );
  testWidgets(
    'unpair requires confirmation and refreshes server-confirmed status',
    (tester) async {
      var revoked = false;
      final transport = MockClient((request) async {
        if (request.url.path.endsWith('/revoke')) {
          revoked = true;
          return http.Response('{"ok":true}', 200);
        }
        return http.Response(
          jsonEncode({
            'ok': true,
            'vehicle_id': 'v',
            'cursor': null,
            'items': [
              {
                'device_id': 'device',
                'vehicle_id': 'v',
                'expires_at_ms': 123456,
                'revoked': revoked,
                'status': revoked ? 'revoked' : 'paired',
              },
            ],
          }),
          200,
        );
      });
      final client = CompanyVehiclePairingClient(
        baseUrl: 'https://fixture.invalid',
        token: 'company-fixture',
        tenantId: '',
        companyId: 'c',
        vehicleId: 'v',
        client: transport,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyVehiclePairingPage(
            client: client,
            vehicleLabel: 'Tesla',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Ontkoppelen'));
      await tester.tap(find.byTooltip('Ontkoppelen'));
      await tester.pumpAndSettle();
      expect(revoked, false);
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();
      expect(revoked, false);
      await tester.tap(find.byTooltip('Ontkoppelen'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Ontkoppelen'));
      await tester.pumpAndSettle();
      expect(revoked, true);
      expect(find.text('Ontkoppeld'), findsOneWidget);
      expect(find.byTooltip('Ontkoppelen'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
