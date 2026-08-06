// FLUXIDI-PIP-METER-EXTERNAL-NAV-1
// PIP-COMPACT-KPI-READABILITY-P1

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_pip_meter.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_session.dart';

void main() {
  group('ExternalNavDestinationResolver', () {
    test('1) pickup A before START', () {
      final d = ExternalNavDestinationResolver.resolve(
        phase: ExternalNavPhase.toPickup,
        pickupLat: 51.0,
        pickupLon: 3.7,
        pickupAddress: 'Pickup',
        dropoffLat: 50.0,
        dropoffLon: 4.0,
        dropoffAddress: 'Drop',
      );
      expect(d.latitude, 51.0);
      expect(d.longitude, 3.7);
    });

    test('2) destination B after START', () {
      final d = ExternalNavDestinationResolver.resolve(
        phase: ExternalNavPhase.activeRide,
        pickupLat: 51.0,
        pickupLon: 3.7,
        dropoffLat: 50.85,
        dropoffLon: 4.35,
        dropoffAddress: 'Brussel',
      );
      expect(d.latitude, 50.85);
      expect(d.longitude, 4.35);
    });

    test('3) address fallback when coords missing', () {
      final d = ExternalNavDestinationResolver.resolve(
        phase: ExternalNavPhase.activeRide,
        dropoffAddress: 'Korenmarkt Gent',
      );
      expect(d.hasCoordinates, isFalse);
      expect(d.address, 'Korenmarkt Gent');
    });

    test('3b) out-of-range pickup falls back to address', () {
      final d = ExternalNavDestinationResolver.resolve(
        phase: ExternalNavPhase.toPickup,
        pickupLat: 99.0,
        pickupLon: 3.7,
        pickupAddress: 'Pickup Street',
      );
      expect(d.hasCoordinates, isFalse);
      expect(d.hasAddress, isTrue);
    });
  });

  group('PiP meter models', () {
    test('4) planned fixed price', () {
      final m = buildExternalNavPipMeterModel(
        phase: ExternalNavPhase.activeRide,
        isStreetRide: false,
        isFixedPrice: true,
        fixedPriceText: '€12,20',
        kmText: '3.1 km',
        durationText: '00:12:01',
        waitText: '00:01:00',
      );
      expect(m.kind, PipMeterKind.fixedPrice);
      expect(m.title, 'Naar bestemming');
      expect(m.primaryValue, '€12,20');
      expect(m.secondaryLines.length, 3);
    });

    test('5) street live tariff', () {
      final m = buildExternalNavPipMeterModel(
        phase: ExternalNavPhase.activeRide,
        isStreetRide: true,
        isFixedPrice: false,
        liveFareText: '€17,60',
        kmText: '5.2 km',
        durationText: '00:18:00',
        waitText: '00:00:00',
      );
      expect(m.kind, PipMeterKind.liveTariff);
      expect(m.title, 'Naar bestemming');
    });

    test('5b) tablet PiP typography larger than phone', () {
      final phone = PipMeterTypography.forSize(
        const Size(390, 844),
        compact: true,
      );
      final tablet = PipMeterTypography.forSize(
        const Size(800, 1280),
        compact: true,
      );
      expect(phone.primarySize, 34);
      expect(tablet.titleSize, inInclusiveRange(18, 22));
      expect(tablet.primarySize, inInclusiveRange(38, 48));
      expect(tablet.metricSize, inInclusiveRange(22, 28));
      expect(tablet.labelSize, inInclusiveRange(15, 18));
      expect(tablet.horizontalPadding, inInclusiveRange(14, 20));
      expect(tablet.primarySize, greaterThan(phone.primarySize));
      expect(tablet.metricSize, greaterThan(phone.metricSize));
    });

    test('6) pre-start shows no tariff', () {
      final m = buildExternalNavPipMeterModel(
        phase: ExternalNavPhase.toPickup,
        isStreetRide: false,
        isFixedPrice: true,
        fixedPriceText: '€12,20',
        liveFareText: '€0,00',
        etaText: '6 min',
        remainingDistanceText: '2.4 km',
      );
      expect(m.kind, PipMeterKind.toCustomer);
      expect(m.title, 'Naar ophaalpunt');
      expect(m.primaryValue, isNot(contains('€12')));
      expect(m.primaryValue, isNot(contains('€0')));
    });
  });

  group('session + suppression', () {
    test('7) session JSON roundtrip', () {
      final s = ExternalNavigationSession(
        provider: ExternalNavProvider.googleMaps,
        bookingId: 'bk1',
        legId: 'leg1',
        phase: ExternalNavPhase.toPickup,
        destination: const ExternalNavigationDestinationPoint(
          latitude: 1,
          longitude: 2,
        ),
        launchedAt: DateTime.utc(2026, 8, 6, 8),
        pipActive: true,
      );
      final again = ExternalNavigationSession.fromJson(
        s.toJson().cast<String, dynamic>(),
      );
      expect(again.bookingId, 'bk1');
      expect(again.pipActive, isTrue);
      expect(again.phase, ExternalNavPhase.toPickup);
    });

    test('8) native guidance suppressed while session active', () {
      expect(shouldSuppressNativeGuidance(null), isFalse);
      expect(
        shouldSuppressNativeGuidance(
          ExternalNavigationSession(
            provider: ExternalNavProvider.googleMaps,
            bookingId: 'b',
            phase: ExternalNavPhase.activeRide,
            destination: const ExternalNavigationDestinationPoint(),
            launchedAt: DateTime.now(),
          ),
        ),
        isTrue,
      );
    });

    test('9) START phase switch updates destination role', () {
      final before = ExternalNavigationSession(
        provider: ExternalNavProvider.googleMaps,
        bookingId: 'street_1',
        phase: ExternalNavPhase.toPickup,
        destination: const ExternalNavigationDestinationPoint(
          latitude: 51,
          longitude: 3,
        ),
        launchedAt: DateTime.now(),
      );
      final after = before.copyWith(
        phase: ExternalNavPhase.activeRide,
        destination: const ExternalNavigationDestinationPoint(
          latitude: 50.8,
          longitude: 4.3,
        ),
      );
      expect(after.phase, ExternalNavPhase.activeRide);
      expect(after.destination.latitude, 50.8);
      expect(after.bookingId, before.bookingId);
    });

    test('10) launch failure contract: suppressed only when active', () {
      final pending = ExternalNavigationSession(
        provider: ExternalNavProvider.googleMaps,
        bookingId: 'b',
        phase: ExternalNavPhase.toPickup,
        destination: const ExternalNavigationDestinationPoint(
          latitude: 51,
          longitude: 3.7,
        ),
        launchedAt: DateTime.now(),
        nativeGuidanceSuppressed: false,
      );
      expect(shouldSuppressNativeGuidance(pending), isFalse);
      final active = pending.copyWith(nativeGuidanceSuppressed: true);
      expect(shouldSuppressNativeGuidance(active), isTrue);
    });
  });
}
