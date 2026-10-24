// LIMOUSINE-MARKETPLACE-P0 (addendum) — accepted-price snapshot contract.
//
// This is a TYPED CONTRACT only. It does not introduce a new snapshot store.
// It maps onto the existing booking snapshot seam (the frozen `quote` block +
// per-leg `_buildOperationalLegRecord` on the booking worker record) so a later
// phase adds a narrow typed extension rather than a parallel store.
//
// It preserves enough authoritative facts for dispute handling and stores no
// unnecessary customer-private data.

import 'limousine_dimensions.dart';

class LimousineAcceptedPriceSnapshot {
  const LimousineAcceptedPriceSnapshot({
    required this.companyId,
    required this.serviceCategory,
    required this.journeyType,
    required this.serviceClass,
    required this.pricingMode,
    required this.totalInclVat,
    required this.currency,
    this.matchedPricingRuleRef,
    this.pricingSourceRevision,
    this.routeReference,
    this.direction,
    this.zoneReference,
    this.vatTreatment,
    this.includedOptions = const <String>[],
    this.separatelyDisclosedCharges = const <String>[],
    this.quotedAtIso,
    this.acceptedAtIso,
    this.cancellationTerms,
    this.waitingTerms,
  });

  final String companyId;
  final LimousineServiceCategory serviceCategory;
  final LimousineJourneyType journeyType;
  final LimousineServiceClassRef serviceClass;
  final LimousinePricingMode pricingMode;

  /// Reference to the matched fixed-fare/package rule (maps to existing
  /// `fixed_fare_rule_id` when a fixed fare applied).
  final String? matchedPricingRuleRef;

  /// Monotonic pricing/profile revision (maps to the existing `source_revision`
  /// discipline) so a later price change cannot silently mutate this snapshot.
  final int? pricingSourceRevision;

  final String? routeReference;
  final String? direction;
  final String? zoneReference;

  final num totalInclVat;
  final String currency;

  /// e.g. `incl` or `excl` (maps to existing `vat_mode`).
  final String? vatTreatment;

  final List<String> includedOptions;
  final List<String> separatelyDisclosedCharges;

  final String? quotedAtIso;
  final String? acceptedAtIso;
  final String? cancellationTerms;
  final String? waitingTerms;

  /// Fail-closed: a manual quote or unavailable outcome may not be snapshotted
  /// as an accepted, resolved price.
  static const Set<LimousinePricingMode> _resolvedModes = {
    LimousinePricingMode.fixedRouteOrAirportFare,
    LimousinePricingMode.hourlyOrPackage,
    LimousinePricingMode.limousineDistanceTime,
  };

  List<String> missingRequiredFields() {
    final missing = <String>[];
    if (companyId.trim().isEmpty) missing.add('companyId');
    if (!serviceClass.isValid) missing.add('serviceClass');
    if (!_resolvedModes.contains(pricingMode)) missing.add('pricingMode');
    if (!(totalInclVat > 0)) missing.add('totalInclVat');
    if (currency.trim().isEmpty) missing.add('currency');
    if ((acceptedAtIso ?? '').trim().isEmpty) missing.add('acceptedAtIso');
    if (pricingMode == LimousinePricingMode.fixedRouteOrAirportFare &&
        (matchedPricingRuleRef ?? '').trim().isEmpty) {
      missing.add('matchedPricingRuleRef');
    }
    return missing;
  }

  bool get isComplete => missingRequiredFields().isEmpty;

  /// Maps to the existing booking snapshot field names so a later phase can
  /// extend the current `quote`/operational-leg record rather than add a store.
  Map<String, dynamic> toBookingSnapshotJson() {
    return <String, dynamic>{
      'company_id': companyId,
      'service_category': serviceCategory.name,
      'journey_type': journeyType.name,
      'service_class': serviceClass.id,
      'pricing_mode': pricingMode.name,
      if (matchedPricingRuleRef != null)
        'fixed_fare_rule_id': matchedPricingRuleRef,
      if (pricingSourceRevision != null)
        'source_revision': pricingSourceRevision,
      if (routeReference != null) 'route_reference': routeReference,
      if (direction != null) 'airport_direction': direction,
      if (zoneReference != null) 'fixed_fare_zone_value': zoneReference,
      'price_incl_vat': totalInclVat,
      'currency': currency,
      if (vatTreatment != null) 'vat_mode': vatTreatment,
      'included_options': includedOptions,
      'separately_disclosed_charges': separatelyDisclosedCharges,
      if (quotedAtIso != null) 'quoted_at': quotedAtIso,
      if (acceptedAtIso != null) 'accepted_at': acceptedAtIso,
      if (cancellationTerms != null) 'cancellation_terms': cancellationTerms,
      if (waitingTerms != null) 'waiting_terms': waitingTerms,
    };
  }
}
