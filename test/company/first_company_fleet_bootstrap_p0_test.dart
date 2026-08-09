// FIRST-COMPANY-UX-P0 — first-run fleet bootstrap + drivers/vehicles UX.
//
// Run:
//   flutter test test/company/first_company_fleet_bootstrap_p0_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company/company_fleet_operational.dart';

String _read(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) fail('Missing $relativePath');
  return file.readAsStringSync();
}

VehicleProfile _vehicle({
  required String id,
  required String name,
  required String brand,
  required String plate,
  String? companyId,
  String color = 'Blue',
}) {
  return VehicleProfile(
    id: id,
    vehicleName: name,
    brandModel: brand,
    licensePlate: plate,
    color: color,
    passengerCapacity: 3,
    luggageCapacity: 3,
    tierId: 'comfort',
    isActive: true,
    driverId: null,
    companyId: companyId,
    primaryPhotoRef: '',
    galleryPhotoRefs: const <String>[],
  );
}

DriverProfile _driver({
  required String id,
  required String name,
  String? companyId,
}) {
  return DriverProfile(
    id: id,
    fullName: name,
    employeeNumber: 'DRV-$id',
    phone: '+32 000 00 00 00',
    isActive: true,
    companyId: companyId,
  );
}

void main() {
  group('FIRST-COMPANY-UX-P0 bootstrap step machine', () {
    test('0 drivers → firstDriver step', () {
      expect(
        resolveFirstRunFleetBootstrapStep(hasDriver: false, hasVehicle: false),
        FirstRunFleetBootstrapStep.firstDriver,
      );
    });

    test('existing driver + 0 vehicles → firstVehicle step (no duplicate driver)',
        () {
      expect(
        resolveFirstRunFleetBootstrapStep(hasDriver: true, hasVehicle: false),
        FirstRunFleetBootstrapStep.firstVehicle,
      );
    });

    test('driver + vehicle → readyToStart', () {
      expect(
        resolveFirstRunFleetBootstrapStep(hasDriver: true, hasVehicle: true),
        FirstRunFleetBootstrapStep.readyToStart,
      );
    });
  });

  group('FIRST-COMPANY-UX-P0 seed / operational fleet filters', () {
    test('seeded Tesla Model 3 vh_1 is placeholder', () {
      final seed = _vehicle(
        id: 'vh_1',
        name: 'Hoofdwagen',
        brand: 'Tesla Model 3',
        plate: '1-ABC-123',
        color: 'Zwart',
      );
      expect(isSeededOrPlaceholderVehicle(seed), isTrue);
      expect(
        companyOperationalVehicles(source: [seed]),
        isEmpty,
      );
    });

    test('real non-seed vehicle counts as operational (legacy/companyless)', () {
      final real = _vehicle(
        id: 'vh_real_1',
        name: 'Van 1',
        brand: 'Mercedes Vito',
        plate: '2-XYZ-999',
        companyId: null,
      );
      expect(isSeededOrPlaceholderVehicle(real), isFalse);
      expect(companyHasOperationalVehicle(source: [real]), isTrue);
    });

    test('seeded driver is not operational', () {
      final seed = _driver(id: 'drv_1', name: 'Standaard chauffeur');
      expect(isSeededOrPlaceholderDriver(seed), isTrue);
      expect(companyOperationalDrivers(source: [seed]), isEmpty);
    });
  });

  group('FIRST-COMPANY-UX-P0 source contracts — onboarding chain', () {
    test('wizard finish inserts fleet bootstrap before home/orientation', () {
      final role = _read('lib/main_parts/role_entry_page.dart');
      expect(role.contains('BusinessFirstRunFleetBootstrapPage'), isTrue);
      expect(role.contains('-> fleet_bootstrap'), isTrue);
      expect(role.contains('_continueAfterFirstRunFleetBootstrap'), isTrue);
      // Phone / tablet destinations preserved after bootstrap.
      expect(role.contains('phone -> business_home (tour skipped)'), isTrue);
      expect(role.contains('-> orientation_flow'), isTrue);
      // Wizard skip still bypasses bootstrap (lands home directly).
      expect(role.contains('first_run_wizard_skipped'), isTrue);
      expect(
        role.indexOf('BusinessFirstRunFleetBootstrapPage') <
            role.indexOf('first_run_wizard_skipped'),
        isTrue,
      );
    });

    test('bootstrap uses canonical driver + vehicle create flows', () {
      final boot = _read(
        'lib/company/business_first_run_fleet_bootstrap_page.dart',
      );
      expect(boot.contains('showDriverCreatorDialog'), isTrue);
      expect(boot.contains('VehicleManagementPage('), isTrue);
      expect(boot.contains('autoOpenNewVehicleEditor: true'), isTrue);
      expect(boot.contains('Voeg je eerste chauffeur toe'), isTrue);
      expect(boot.contains('Voeg je eerste voertuig toe'), isTrue);
      expect(boot.contains('Klaar om te starten'), isTrue);
      expect(boot.contains('Je bedrijf gebruiksklaar maken'), isTrue);
      // Localized EN/FR/ES counterparts present.
      expect(boot.contains('Add your first driver'), isTrue);
      expect(boot.contains('Ajoutez votre premier chauffeur'), isTrue);
      expect(boot.contains('Añade tu primer conductor'), isTrue);
      expect(boot.contains('Ready to start'), isTrue);
      expect(boot.contains('Prêt à démarrer'), isTrue);
      expect(boot.contains('Listo para empezar'), isTrue);
      // Soft skip — not a hard lock.
      expect(boot.contains("'Later'"), isTrue);
    });

    test('settings wizard itself is not altered with fleet CRUD steps', () {
      final wizard = _read('lib/business_first_run_wizard_page.dart');
      expect(wizard.contains('showDriverCreatorDialog'), isFalse);
      expect(wizard.contains('VehicleManagementPage'), isFalse);
      expect(wizard.contains('Voeg je eerste chauffeur toe'), isFalse);
    });
  });

  group('FIRST-COMPANY-UX-P0 source contracts — drivers page', () {
    test('zero-driver empty state exposes Chauffeur toevoegen CTA', () {
      final body = _read(
        'lib/main_parts/company_driver_management_page_body.dart',
      );
      expect(body.contains('Nog geen chauffeurs'), isTrue);
      expect(body.contains('Voeg je eerste chauffeur toe.'), isTrue);
      expect(body.contains('Chauffeur toevoegen'), isTrue);
      expect(body.contains('_openAddDriverFlow(context)'), isTrue);
      // Ambiguous "Nieuw" dock label replaced.
      expect(
        body.contains("nl: 'Nieuw',\n                                  en: 'New'"),
        isFalse,
      );
    });

    test('entitlement gate still wraps canonical add flow', () {
      final body = _read(
        'lib/main_parts/company_driver_management_page_body.dart',
      );
      expect(body.contains('_confirmDriverAddGate'), isTrue);
      expect(body.contains('showDriverCreatorDialog'), isTrue);
      expect(body.contains('maxDrivers'), isTrue);
      expect(body.contains('Chauffeurlimiet bereikt'), isTrue);
    });
  });

  group('FIRST-COMPANY-UX-P0 source contracts — vehicle form', () {
    test('new vehicle identity controllers start empty (no Tesla defaults)', () {
      final page = _read('lib/vehicle_management_page.dart');
      // Create path uses ?? '' for identity fields.
      expect(
        page.contains("text: resolvedExisting?.vehicleName ?? ''"),
        isTrue,
      );
      expect(
        page.contains("text: resolvedExisting?.brandModel ?? ''"),
        isTrue,
      );
      expect(
        page.contains("text: resolvedExisting?.licensePlate ?? ''"),
        isTrue,
      );
      expect(page.contains("text: resolvedExisting?.color ?? ''"), isTrue);
      // Must not hardcode Tesla/Model 3 into controller text for create.
      expect(
        page.contains("TextEditingController(text: 'Tesla"),
        isFalse,
      );
      expect(
        page.contains("TextEditingController(\n      text: 'Tesla"),
        isFalse,
      );
      // Placeholders allowed; must not be initial values.
      expect(page.contains('Bijv. Tesla Model 3'), isTrue);
      expect(page.contains('hintText: isNewVehicle'), isTrue);
      // Seed vehicle filtered from management UI.
      expect(page.contains('isSeededOrPlaceholderVehicle'), isTrue);
      // Linked driver dropdown preserved.
      expect(page.contains('Gekoppelde chauffeur'), isTrue);
      expect(page.contains('linkedDriverId'), isTrue);
    });

    test('demo seed source remains only the app_config vh_1 notifier seed', () {
      final config = _read('lib/app_config.dart');
      expect(config.contains("id: 'vh_1'"), isTrue);
      expect(config.contains("brandModel: 'Tesla Model 3'"), isTrue);
      expect(config.contains("licensePlate: '1-ABC-123'"), isTrue);
    });
  });
}
