import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_vehicle_duty_recovery_panel.dart';

Map<String, dynamic> state({bool closed = false}) => {
  'version': 3,
  'duties': closed
      ? []
      : [
          {
            'driver_id': 'tom',
            'vehicle_id': 'tesla',
            'duty_id': 'shift-one',
            'started_at_ms': 1000,
            'ended_at_ms': null,
          },
        ],
};

void main() {
  testWidgets(
    'recovery requires reason and uncertain response retries the original command',
    (tester) async {
      final commands = <Map<String, dynamic>>[];
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompanyVehicleDutyRecoveryPanel(
              devices: const [
                {'device_id': 'old-device', 'status': 'revoked'},
              ],
              loadState: () async => state(closed: closed),
              recover: (command) async {
                commands.add(command);
                if (commands.length == 1) throw Exception('fixture lost reply');
                closed = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dienst herstellen · old-device'));
      await tester.pumpAndSettle();
      expect(commands, isEmpty);
      await tester.tap(find.text('Toestel verloren'));
      await tester.pumpAndSettle();
      expect(commands.single['driver_id'], 'tom');
      expect(commands.single['duty_id'], 'shift-one');
      expect(commands.single['reason'], 'device_lost');
      expect(commands.single['expected_version'], 3);
      await tester.tap(find.text('Afsluiting opnieuw proberen'));
      await tester.pumpAndSettle();
      expect(commands[1], commands[0]);
      expect(find.text('Open dienst van chauffeur tom'), findsNothing);
    },
  );
  testWidgets(
    'active ride rejection refreshes state and paired device has no recovery action',
    (tester) async {
      var reads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompanyVehicleDutyRecoveryPanel(
              devices: const [
                {'device_id': 'old', 'status': 'revoked'},
                {'device_id': 'live', 'status': 'paired'},
              ],
              loadState: () async {
                reads++;
                return state();
              },
              recover: (_) async => throw const VehicleDutyRecoveryException(
                'active_ride_blocks_duty_change',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dienst herstellen · live'), findsNothing);
      await tester.tap(find.text('Dienst herstellen · old'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Toestel vervangen'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('Afsluiting opnieuw proberen'), findsNothing);
      expect(
        find.text(
          'Afsluiten geblokkeerd. Controleer ritten, toestellen en dienststatus.',
        ),
        findsOneWidget,
      );
    },
  );
}
