// VEHICLE-DELETE-DURABILITY-P0
//
// A deleted vehicle must never return via local cache, bootstrap merge, or
// inventory backfill. Mirrors the driver tombstone chain.
//
// Run:
//   flutter test test/company/vehicle_delete_durability_p0_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';

String _read(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) fail('Missing $relativePath');
  return file.readAsStringSync();
}

VehicleProfile _vehicle({
  required String id,
  required String name,
  String plate = 'X-000',
  String? companyId,
}) {
  return VehicleProfile(
    id: id,
    vehicleName: name,
    brandModel: '',
    licensePlate: plate,
    color: 'Blue',
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

void main() {
  group('reconcileBootstrapVehiclesWithTombstones', () {
    test('local tombstone wins over a stale local-only vehicle', () {
      // Backend already dropped Ferrari (only Tesla+Cadillac remote); Ferrari
      // lingers locally but is tombstoned -> it must not survive.
      final active = reconcileBootstrapVehiclesWithTombstones(
        remoteVehicles: [
          _vehicle(id: 'vh_tesla', name: 'Hoofdwagen'),
          _vehicle(id: 'vh_cadillac', name: 'Cadillac'),
        ],
        localVehicles: [
          _vehicle(id: 'vh_tesla', name: 'Hoofdwagen'),
          _vehicle(id: 'vh_cadillac', name: 'Cadillac'),
          _vehicle(id: 'vh_ferrari', name: 'Ferrari EV'),
        ],
        deletedVehicleIds: {'vh_ferrari'},
      );
      expect(active.map((v) => v.id).toSet(), {'vh_tesla', 'vh_cadillac'});
      expect(active.any((v) => v.id == 'vh_ferrari'), isFalse);
    });

    test('backend tombstone removes a stale local copy present in both', () {
      final active = reconcileBootstrapVehiclesWithTombstones(
        remoteVehicles: [
          _vehicle(id: 'vh_tesla', name: 'Hoofdwagen'),
          _vehicle(id: 'vh_cadillac', name: 'Cadillac'),
          _vehicle(id: 'vh_ferrari', name: 'Ferrari EV'),
        ],
        localVehicles: [
          _vehicle(id: 'vh_tesla', name: 'Hoofdwagen'),
          _vehicle(id: 'vh_ferrari', name: 'Ferrari EV'),
        ],
        deletedVehicleIds: {'vh_ferrari'},
      );
      expect(active.any((v) => v.id == 'vh_ferrari'), isFalse);
      expect(active.map((v) => v.id).toSet(), {'vh_tesla', 'vh_cadillac'});
    });

    test('genuine new local-only vehicle (not tombstoned) is retained', () {
      final active = reconcileBootstrapVehiclesWithTombstones(
        remoteVehicles: [_vehicle(id: 'vh_tesla', name: 'Hoofdwagen')],
        localVehicles: [
          _vehicle(id: 'vh_tesla', name: 'Hoofdwagen'),
          _vehicle(id: 'vh_new_van', name: 'Nieuwe Van'),
        ],
        deletedVehicleIds: const <String>{},
      );
      expect(active.map((v) => v.id).toSet(), {'vh_tesla', 'vh_new_van'});
    });

    test('effective active count for FLX-00001 is 2 (usage 2/3)', () {
      final active = reconcileBootstrapVehiclesWithTombstones(
        remoteVehicles: [
          _vehicle(id: 'vh_tesla', name: 'Hoofdwagen'),
          _vehicle(id: 'vh_cadillac', name: 'Cadillac'),
        ],
        localVehicles: [
          _vehicle(id: 'vh_tesla', name: 'Hoofdwagen'),
          _vehicle(id: 'vh_cadillac', name: 'Cadillac'),
          _vehicle(id: 'vh_ferrari', name: 'Ferrari EV'),
        ],
        deletedVehicleIds: {'vh_ferrari'},
      );
      // Two active vehicles against a capacity of three -> 2/3.
      const capacity = 3;
      expect(active.length, 2);
      expect('${active.length}/$capacity', '2/3');
    });

    test('matching remote+local prefers local edits via mergePreferLocal', () {
      final active = reconcileBootstrapVehiclesWithTombstones(
        remoteVehicles: [_vehicle(id: 'vh_tesla', name: 'RemoteName')],
        localVehicles: [_vehicle(id: 'vh_tesla', name: 'LocalName')],
        deletedVehicleIds: const <String>{},
        mergePreferLocal: (remote, local) => local,
      );
      expect(active.single.vehicleName, 'LocalName');
    });

    test('empty tombstones union remote + local-only without loss', () {
      final active = reconcileBootstrapVehiclesWithTombstones(
        remoteVehicles: [_vehicle(id: 'vh_tesla', name: 'Hoofdwagen')],
        localVehicles: [_vehicle(id: 'vh_local', name: 'Local-only')],
        deletedVehicleIds: const <String>{},
      );
      expect(active.map((v) => v.id).toSet(), {'vh_tesla', 'vh_local'});
    });
  });

  group('deleteVehicle', () {
    tearDown(() {
      vehiclesNotifier.value = const <VehicleProfile>[];
    });

    test('removes the vehicle from the active notifier immediately', () {
      vehiclesNotifier.value = <VehicleProfile>[
        _vehicle(id: 'vh_tesla', name: 'Hoofdwagen'),
        _vehicle(id: 'vh_ferrari', name: 'Ferrari EV'),
      ];
      deleteVehicle('vh_ferrari');
      expect(vehiclesNotifier.value.map((v) => v.id).toList(), ['vh_tesla']);
    });
  });

  group('source contracts — vehicle tombstone chain mirrors drivers', () {
    late String config;

    setUpAll(() {
      config = _read('lib/app_config.dart');
    });

    test('local vehicle tombstone store + helpers exist (scoped id-set)', () {
      expect(config.contains('_deletedVehicleIdsByScope'), isTrue);
      expect(config.contains('_isVehicleIdTombstonedForScope'), isTrue);
      expect(config.contains('_markDeletedVehicleForScope'), isTrue);
      expect(
        config.contains('_encodeDeletedVehicleTombstonesForPersistence'),
        isTrue,
      );
      expect(
        config.contains('_decodeDeletedVehicleTombstonesFromPersistence'),
        isTrue,
      );
    });

    test('tombstones are persisted and restored with the tenant state', () {
      expect(config.contains("'deletedVehicleIdsByScope':"), isTrue);
      expect(config.contains("map['deletedVehicleIdsByScope']"), isTrue);
      expect(config.contains('_deletedVehicleIdsByScope.clear()'), isTrue);
    });

    test('deleteVehicle writes the tombstone before syncing to Booking', () {
      final start = config.indexOf('void deleteVehicle(String id) {');
      expect(start, greaterThan(0));
      final chunk = config.substring(start, start + 1400);
      final markAt = chunk.indexOf('_markDeletedVehicleForScope');
      final syncAt = chunk.indexOf('syncFleetInventoryToBackend');
      expect(markAt, greaterThan(0));
      expect(
        syncAt,
        greaterThan(markAt),
        reason: 'tombstone must precede sync',
      );
    });

    test(
      'bootstrap merge parses remote deleted_vehicle_ids and reconciles',
      () {
        expect(config.contains("bootstrap['deleted_vehicle_ids']"), isTrue);
        expect(
          config.contains('reconcileBootstrapVehiclesWithTombstones('),
          isTrue,
        );
      },
    );

    test('fleet POST sends additive deleted_vehicle_ids, never a revision', () {
      expect(
        config.contains("'deleted_vehicle_ids': deletedVehicleIds"),
        isTrue,
      );
      // Client never forces the server-owned fleet revision.
      expect(config.contains("'source_revision':"), isFalse);
    });

    test('inventory backfill never re-uploads a tombstoned vehicle', () {
      expect(
        config.contains('!tombstonedVehicleIds.contains(vehicle.id.trim())'),
        isTrue,
      );
    });
  });
}
