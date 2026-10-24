import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_reliable_choice.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_vehicle_cards.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_vehicle_offers.dart';

Map<String, dynamic> evidence(String id, {bool scheduled = false, int? now, int seconds = 300}) => {
  'schema': 'fluxidi-reliable-choice-v1', 'vehicle_id': id, 'estimate': true, 'evidence_revision': 'fixture-v1',
  'valid_until_ms': (now ?? DateTime.now().millisecondsSinceEpoch) + 15000,
  'status': scheduled ? 'available_for_selected_time' : 'estimated_availability',
  'pickup_eta_seconds': scheduled ? null : seconds, 'pickup_distance_meters': scheduled ? null : 1100,
};
CustomerBookingVehicleOffer offer(String id, {bool scheduled = false, int seconds = 300, bool available = true, bool withEvidence = true}) =>
  CustomerBookingVehicleOffer(vehicle: {'vehicle_id': id, 'name': id == 'V' ? 'Mercedes Vito' : 'Toyota Corolla',
    'passenger_capacity': 8, 'luggage_capacity': 4, if (withEvidence) 'reliable_choice_v1': evidence(id, scheduled: scheduled, seconds: seconds)},
    available: available, passengerSeats: 8, baggageCapacity: 4);
void main() {
  test('public projection rejects expired, malformed and mismatched vehicle evidence', () {
    final good = evidence('V', now: 1000);
    expect(CustomerReliableChoiceEstimate.parse(good, vehicleId: 'V', nowMs: 1000), isNotNull);
    for (final bad in [ {...good, 'estimate': false}, {...good, 'pickup_eta_seconds': -1}, {...good, 'pickup_distance_meters': double.nan},
      {...good, 'valid_until_ms': 1000}, {...good, 'vehicle_id': 'OTHER'}, {...good, 'evidence_revision': ''}, {...good, 'status': 'live'} ]) {
      expect(CustomerReliableChoiceEstimate.parse(bad, vehicleId: 'V', nowMs: 1000), isNull);
    }
  });
  test('ASAP ETA is explicitly estimated in all supported languages', () {
    final model = CustomerReliableChoiceEstimate.parse(evidence('V', now: 1000), vehicleId: 'V', nowMs: 1000)!;
    for (final language in AppLanguage.values) { expect(model.etaLabel(language), '± 5 min'); }
    expect(model.distanceLabel(AppLanguage.nl), '1,1 km van jou');
    expect(model.distanceLabel(AppLanguage.en), '1.1 km away');
  });
  test('scheduled projection has no immediate ETA or distance', () {
    final model = CustomerReliableChoiceEstimate.parse(evidence('V', scheduled: true, now: 1000), vehicleId: 'V', nowMs: 1000)!;
    expect(model.etaLabel(AppLanguage.nl), 'Beschikbaar voor gekozen tijdstip');expect(model.distanceLabel(AppLanguage.nl), isNull);
    expect(CustomerReliableChoiceEstimate.parse({...evidence('V', scheduled: true, now: 1000), 'pickup_eta_seconds': 300}, vehicleId: 'V', nowMs: 1000), isNull);
  });
  test('confirmation, retry and dispatcher states never claim underway or live ETA', () {
    for (final state in ['waiting_driver_confirmation', 'finding_next_vehicle', 'dispatcher_review', 'driver_confirmed']) {
      final label = customerReliableChoiceStatus(state, AppLanguage.nl).toLowerCase();
      expect(label, isNot(contains('onderweg')));expect(label, isNot(contains('live')));
    }
  });
  for (final width in [390.0, 900.0]) {
    testWidgets('existing vehicle cards show ETA first and retain capacity and selection at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      String? selected;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: CustomerBookingVehiclePhotoCardGrid(
        offers: [offer('SLOW', seconds: 420), offer('V'), offer('BLOCKED', available: false), offer('UNKNOWN', withEvidence: false)],
        language: AppLanguage.nl, selectedVehicleId: null, reliableChoiceOnly: true,
        onSelected: (o) { selected = o.vehicleId; }))));
      await tester.pumpAndSettle();expect(tester.takeException(), isNull);
      expect(find.text('± 5 min'), findsOneWidget);expect(find.text('± 7 min'), findsOneWidget);expect(find.text('1,1 km van jou'), findsNWidgets(2));
      expect(find.byType(CustomerBookingVehiclePhotoCard), findsNWidgets(2));
      final widgets = tester.widgetList<CustomerBookingVehiclePhotoCard>(find.byType(CustomerBookingVehiclePhotoCard)).toList();
      expect(widgets.first.offer.vehicleId, 'V');expect(widgets.first.offer.passengerSeats, 8);expect(widgets.first.offer.baggageCapacity, 4);
      await tester.tap(find.text('± 5 min'));expect(selected, 'V');
      expect(find.textContaining('huidige rit'), findsNothing);
    });
  }
  testWidgets('scheduled vehicle card contains no now-distance label', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CustomerBookingVehiclePhotoCardGrid(
      offers: [offer('V', scheduled: true)], language: AppLanguage.nl, selectedVehicleId: null,
      reliableChoiceOnly: true, onSelected: (_) {}))));
    await tester.pumpAndSettle();expect(tester.takeException(), isNull);
    expect(find.text('Beschikbaar voor gekozen tijdstip'), findsOneWidget);expect(find.text('± 5 min'), findsNothing);expect(find.textContaining('km'), findsNothing);
  });
  testWidgets('legacy card mode retains original offers without a P12 projection', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CustomerBookingVehiclePhotoCardGrid(
      offers: [offer('V', withEvidence: false)], language: AppLanguage.nl, selectedVehicleId: null, onSelected: (_) {}))));
    await tester.pumpAndSettle();expect(find.byType(CustomerBookingVehiclePhotoCard), findsOneWidget);expect(find.textContaining('±'), findsNothing);
  });
}
