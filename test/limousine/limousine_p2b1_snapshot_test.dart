import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_entry.dart';
import 'package:fluxidi_tracking/limousine/limousine_dimensions.dart';
import 'package:fluxidi_tracking/limousine/limousine_price_snapshot.dart';
import 'package:fluxidi_tracking/limousine/limousine_pricing_separation.dart';

/// Maps a worker resolver-shaped result (JSON) into the accepted-price snapshot
/// contract, proving the /book recompute seam can consume the resolved quote.
LimousineAcceptedPriceSnapshot _snapshotFromResolved(
  Map<String, dynamic> r, {
  required String acceptedAtIso,
}) {
  return LimousineAcceptedPriceSnapshot(
    companyId: 'cmp_x',
    serviceCategory: normalizeServiceCategory(r['service_category'])!,
    journeyType: normalizeJourneyType(r['journey_type'])!,
    serviceClass: LimousineServiceClassRef.fromAuthoritativeId(
      r['service_class_id'] as String?,
    ),
    pricingMode: normalizePricingMode(r['pricing_mode'])!,
    matchedPricingRuleRef: r['matched_rule_ref'] as String?,
    pricingSourceRevision: r['source_revision'] as int?,
    totalInclVat: r['price_incl_vat'] as num,
    currency: r['currency'] as String,
    vatTreatment: r['vat_mode'] as String?,
    direction: r['direction'] as String?,
    acceptedAtIso: acceptedAtIso,
  );
}

void main() {
  group('20) resolved worker result maps to a complete snapshot', () {
    test('fixed airport fare result -> complete snapshot', () {
      final resolved = <String, dynamic>{
        'resolved': true,
        'service_category': 'limousine',
        'journey_type': 'airport_transfer',
        'service_class_id': 'executive_sedan',
        'pricing_mode': 'fixed_route_or_airport_fare',
        'matched_rule_ref': 'fx_airport_to',
        'source_revision': 3,
        'price_incl_vat': 120.0,
        'price_ex_vat': 113.21,
        'price_vat': 6.79,
        'currency': 'EUR',
        'vat_mode': 'incl',
        'direction': 'to_airport',
      };
      final snapshot = _snapshotFromResolved(
        resolved,
        acceptedAtIso: '2026-08-17T12:00:00Z',
      );
      expect(snapshot.isComplete, isTrue);
      expect(snapshot.missingRequiredFields(), isEmpty);
      final json = snapshot.toBookingSnapshotJson();
      expect(json['service_category'], 'limousine');
      expect(json['journey_type'], 'airportTransfer');
      expect(json['service_class'], 'executive_sedan');
      expect(json['pricing_mode'], 'fixedRouteOrAirportFare');
      expect(json['fixed_fare_rule_id'], 'fx_airport_to');
      expect(json['source_revision'], 3);
      expect(json['price_incl_vat'], 120.0);
      expect(json['currency'], 'EUR');
    });

    test('distance/time result -> complete snapshot', () {
      final resolved = <String, dynamic>{
        'service_category': 'limousine',
        'journey_type': 'point_to_point',
        'service_class_id': 'executive_sedan',
        'pricing_mode': 'limousine_distance_time',
        'matched_rule_ref': 'distance_time:executive_sedan',
        'source_revision': 3,
        'price_incl_vat': 120.0,
        'currency': 'EUR',
        'vat_mode': 'incl',
      };
      final snapshot = _snapshotFromResolved(
        resolved,
        acceptedAtIso: '2026-08-17T12:00:00Z',
      );
      expect(snapshot.isComplete, isTrue);
    });
  });

  group('21) manual/unavailable cannot become a resolved snapshot', () {
    test('manual quote is rejected (no numeric price, non-resolved mode)', () {
      final manual = LimousineAcceptedPriceSnapshot(
        companyId: 'cmp_x',
        serviceCategory: LimousineServiceCategory.limousine,
        journeyType: LimousineJourneyType.pointToPoint,
        serviceClass: LimousineServiceClassRef.fromAuthoritativeId(
          'executive_sedan',
        ),
        pricingMode: LimousinePricingMode.manualQuote,
        totalInclVat: 0,
        currency: 'EUR',
        acceptedAtIso: '',
      );
      expect(manual.isComplete, isFalse);
      expect(manual.missingRequiredFields(), contains('pricingMode'));
      expect(manual.missingRequiredFields(), contains('totalInclVat'));
    });

    test('unavailable is rejected', () {
      final unavailable = LimousineAcceptedPriceSnapshot(
        companyId: 'cmp_x',
        serviceCategory: LimousineServiceCategory.limousine,
        journeyType: LimousineJourneyType.airportTransfer,
        serviceClass: LimousineServiceClassRef.fromAuthoritativeId(
          'executive_sedan',
        ),
        pricingMode: LimousinePricingMode.unavailable,
        totalInclVat: 0,
        currency: 'EUR',
        acceptedAtIso: '',
      );
      expect(unavailable.isComplete, isFalse);
    });
  });

  group('13) scheduled limousine never uses the street meter', () {
    test('street-meter finalization forbidden for scheduled limousine', () {
      expect(
        isStreetMeterFinalizationForbidden(
          category: LimousineServiceCategory.limousine,
          isScheduled: true,
        ),
        isTrue,
      );
      // Taxi street ride meter finalization stays allowed (unchanged).
      expect(
        canFinalizeWithStreetMeter(
          category: LimousineServiceCategory.taxi,
          isScheduled: false,
        ),
        isTrue,
      );
    });

    test('12) no taxi fallback is a hard invariant', () {
      expect(
        limousinePricingForbidsTaxiFallback(LimousineServiceCategory.limousine),
        isTrue,
      );
    });
  });

  group('25) customer-entry gate remains default OFF', () {
    test('gate off', () {
      expect(LimousineCustomerEntryContract.isVisible, isFalse);
    });
  });
}
