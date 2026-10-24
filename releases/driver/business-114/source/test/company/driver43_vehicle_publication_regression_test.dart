import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_fallback.dart';
import 'package:fluxidi_tracking/vehicle_fleet_card_media.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_service_persist.dart';
import 'package:fluxidi_tracking/private_chauffeur/private_chauffeur_capability.dart';

void main() {
  const vehicle = VehicleProfile(
    id: 'fixture_vito',
    vehicleName: 'Vito 3',
    brandModel: 'Mercedes Vito',
    licensePlate: 'FIXTURE',
    color: 'black',
    passengerCapacity: 8,
    luggageCapacity: 8,
    tierId: 'comfort',
    isActive: true,
    driverId: null,
    primaryPhotoRef: '',
    galleryPhotoRefs: [],
    fallbackAsset: kCompanyPlanFallbackMinibus,
    serviceCategory: 'taxi',
  );
  test(
    'chosen illustration survives save and reopen without changing capacity or assigning a driver',
    () {
      final saved = encodeVehicleForPersistence(vehicle);
      final reopened = decodeVehicleFromPersistence(
        saved,
        fallback: vehicle.copyWith(fallbackAsset: ''),
      );
      expect(reopened.fallbackAsset, kCompanyPlanFallbackMinibus);
      expect(reopened.passengerCapacity, 8);
      expect(reopened.luggageCapacity, 8);
      expect(reopened.driverId, isNull);
      expect(reopened.serviceCategory, 'taxi');
      final wire = encodeVehicleForBackendFleet(
        reopened,
        tenantId: 'fixture',
        companyId: 'fixture',
      );
      expect(wire['fallback_asset'], kCompanyPlanFallbackMinibus);
      expect(wire['passenger_capacity'], 8);
      expect(wire['luggage_capacity'], 8);
      expect(wire.containsKey('assigned_driver_id'), isFalse);
    },
  );
  test('arbitrary local paths or URLs cannot become bundled illustrations', () {
    for (final value in [
      '../../private.png',
      'https://example.com/car.jpg',
      'minivan',
    ]) {
      expect(normalizeVehicleFallbackAsset(value), '');
    }
    expect(
      normalizeVehicleFallbackAsset(kCompanyPlanFallbackSedan),
      kCompanyPlanFallbackSedan,
    );
  });
  testWidgets('vehicle without photo renders chosen existing asset', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 400,
          child: FleetVehicleCardMedia(
            photoRef: '',
            fallbackAsset: kCompanyPlanFallbackMinibus,
            placeholderText: 'Geen voertuigfoto',
            background: Colors.black,
            gold: Colors.amber,
          ),
        ),
      ),
    );
    await tester.pump();
    final images = tester.widgetList<Image>(find.byType(Image));
    expect(
      images.any((i) {
        final provider = i.image is ResizeImage
            ? (i.image as ResizeImage).imageProvider
            : i.image;
        return provider is AssetImage &&
            provider.assetName == kCompanyPlanFallbackMinibus;
      }),
      isTrue,
    );
  });
  test('private chauffeur save reopen retains all other public services', () {
    final selected = ['taxi_vvb', 'airport_transfer', 'private_chauffeur'];
    final profile = BackendBusinessProfile.fromJson({
      'public_service_ids': selected,
      'public_services_configured': true,
    });
    final reopened = BackendBusinessProfile.fromJson(profile.toJson());
    requirePublicServicesAcknowledged(selected, reopened.publicServiceIds);
    expect(reopened.publicServiceIds, selected);
    expect(
      partnerExplicitlyOffersPrivateChauffeur({
        'services': reopened.publicServiceIds,
      }),
      isTrue,
    );
  });
  test(
    'a successful response stripping private chauffeur is a visible publish failure',
    () {
      expect(
        () => requirePublicServicesAcknowledged(
          ['taxi_vvb', 'private_chauffeur'],
          ['taxi_vvb'],
        ),
        throwsStateError,
      );
      expect(
        () => requirePublicServicesAcknowledged(
          ['taxi_vvb'],
          ['taxi_vvb', 'private_chauffeur'],
        ),
        throwsStateError,
      );
    },
  );
}
