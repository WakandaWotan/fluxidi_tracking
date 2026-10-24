import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/driver_creator_dialog.dart';

void main() {
  testWidgets('private chauffeur choice can be changed without a vehicle', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => showDriverCreatorDialog(context, companyId: 'test-company'),
        child: const Text('Open')),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final choice = find.byKey(const Key('driver_private_chauffeur_without_vehicle'));
    await tester.ensureVisible(choice);
    expect(tester.widget<CheckboxListTile>(choice).value, false);
    await tester.tap(choice);
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(choice).value, true);
    expect(tester.takeException(), isNull);
  });

  test('unrelated profile edits retain private chauffeur role without a vehicle', () {
    const driver = DriverProfile(id: 'private', fullName: 'Test', employeeNumber: '123',
      phone: '', isActive: true, privateChauffeurEnabled: true);
    final renamed = driver.copyWith(fullName: 'Updated');
    expect(renamed.privateChauffeurEnabled, true);
    expect(renamed.assignedVehicleId, isNull);
    expect(renamed.publicProfileEnabled, false);
    expect(renamed.copyWith(privateChauffeurEnabled: false).privateChauffeurEnabled, false);
  });

  test('private role allows a scoped driver session without a company vehicle', () {
    const driver = DriverProfile(id: 'private-real', fullName: 'Private', employeeNumber: '123',
      phone: '', isActive: true, privateChauffeurEnabled: true, companyId: 'role-company');
    String? reason(DriverProfile value) => standaloneDriverSessionOperationalBlockReason(
      driverId: value.id, assignedVehicleId: null, tenantId: 'role-company', companyId: 'role-company',
      activeCompanyId: 'role-company', drivers: [value]);
    expect(reason(driver), isNull);
    expect(reason(driver.copyWith(privateChauffeurEnabled: false)), 'no_vehicle_assigned');
  });
}
