// LIMOUSINE-MARKETPLACE-P0 (addendum) — first-class capability/state composition.
//
// Public Limousine availability is NOT one `is_limousine` boolean. It is a
// composition of company lifecycle, subscription state, entitlement, company
// opt-in, public profile publication, public booking acceptance, market
// coverage, eligible vehicle/service configuration, and operational
// availability. Missing/stale/contradictory state fails closed.
//
// Reuses the existing subscription source of truth (BackendSubscriptionProfile
// `subscription_status` + `features` map). It does NOT invent a plan, add-on
// SKU, limit, or hardcoded entitlement.

import 'limousine_provider_eligibility.dart';
import 'limousine_service_capability.dart';

/// Subscription lifecycle, normalized from the worker's allowed statuses
/// (`trialing`, `payment_required`, `active`, `past_due`, `grace_period`,
/// `suspended`, `cancelled`; plus legacy `valid`/`canceled`).
enum LimousineSubscriptionState { active, trial, grace, cancelled, expired }

/// Whether the current subscription may carry the Limousine entitlement.
enum LimousineEntitlement { available, unavailable }

/// The six distinguishable business-settings states the company owner sees.
enum LimousinePublicAvailabilityState {
  suspendedOrBlocked,
  unavailableUnderSubscription,
  entitledButDisabledByCompany,
  enabledButProfileNotPublished,
  publishedButTemporarilyUnavailable,
  publiclyAvailable,
}

/// Commercial policy toggle so P0 stays compatible with either later decision:
/// Limousine included in the plan, or an additional paid capability. Default is
/// the fail-closed choice: an explicit entitlement is required.
class LimousineEntitlementPolicy {
  const LimousineEntitlementPolicy({this.includedInSubscription = false});

  /// When true, a permitting subscription implies entitlement even without an
  /// explicit `features['limousine']` flag. When false (default), entitlement
  /// requires an explicit flag and otherwise fails closed.
  final bool includedInSubscription;

  static const LimousineEntitlementPolicy requiresExplicitEntitlement =
      LimousineEntitlementPolicy();
  static const LimousineEntitlementPolicy includedInPlan =
      LimousineEntitlementPolicy(includedInSubscription: true);
}

LimousineSubscriptionState normalizeSubscriptionState(String? raw) {
  final token = normalizePublicServiceToken(raw);
  switch (token) {
    case 'active':
    case 'valid':
      return LimousineSubscriptionState.active;
    case 'trialing':
    case 'trial':
      return LimousineSubscriptionState.trial;
    case 'grace_period':
    case 'grace':
    case 'past_due':
      return LimousineSubscriptionState.grace;
    case 'cancelled':
    case 'canceled':
      return LimousineSubscriptionState.cancelled;
    // suspended / payment_required / expired / unknown all fail closed.
    default:
      return LimousineSubscriptionState.expired;
  }
}

/// active / trial / grace permit Limousine; cancelled / expired do not.
bool subscriptionStatePermitsLimousine(LimousineSubscriptionState state) {
  return state == LimousineSubscriptionState.active ||
      state == LimousineSubscriptionState.trial ||
      state == LimousineSubscriptionState.grace;
}

/// Resolves entitlement from the subscription `features` map (existing seam),
/// honoring the commercial policy. Explicit flags always win; a `false` flag
/// fails closed even under `includedInPlan`.
LimousineEntitlement resolveLimousineEntitlement(
  Map<String, dynamic> subscriptionFeatures, {
  LimousineEntitlementPolicy policy =
      LimousineEntitlementPolicy.requiresExplicitEntitlement,
}) {
  for (final key in const [
    'limousine',
    'limousine_module',
    'limousine_service',
  ]) {
    final value = subscriptionFeatures[key];
    if (looksTruthyPublicFlag(value)) return LimousineEntitlement.available;
    if (looksFalseyPublicFlag(value)) return LimousineEntitlement.unavailable;
  }
  if (policy.includedInSubscription) return LimousineEntitlement.available;
  return LimousineEntitlement.unavailable;
}

class LimousineAvailabilityComposition {
  const LimousineAvailabilityComposition({
    required this.state,
    required this.subscriptionState,
    required this.entitlement,
  });

  final LimousinePublicAvailabilityState state;
  final LimousineSubscriptionState subscriptionState;
  final LimousineEntitlement entitlement;

  bool get isPubliclyAvailable =>
      state == LimousinePublicAvailabilityState.publiclyAvailable;
}

/// Company self-state composition (request-independent). Evaluated in a strict
/// fail-closed order so the owner always sees one authoritative state.
LimousineAvailabilityComposition composeLimousinePublicAvailability(
  Map<String, dynamic> company, {
  LimousineEntitlementPolicy policy =
      LimousineEntitlementPolicy.requiresExplicitEntitlement,
}) {
  final subscriptionState = normalizeSubscriptionState(
    (company['subscription_status'] ?? company['subscriptionStatus'])
        ?.toString(),
  );
  final entitlement = resolveLimousineEntitlement(
    _subscriptionFeaturesFrom(company),
    policy: policy,
  );

  LimousineAvailabilityComposition result(
    LimousinePublicAvailabilityState state,
  ) {
    return LimousineAvailabilityComposition(
      state: state,
      subscriptionState: subscriptionState,
      entitlement: entitlement,
    );
  }

  if (_companyBlocked(company)) {
    return result(LimousinePublicAvailabilityState.suspendedOrBlocked);
  }
  final permits =
      entitlement == LimousineEntitlement.available &&
      subscriptionStatePermitsLimousine(subscriptionState);
  if (!permits) {
    return result(
      LimousinePublicAvailabilityState.unavailableUnderSubscription,
    );
  }
  if (!partnerHasExplicitLimousineCapability(company)) {
    return result(
      LimousinePublicAvailabilityState.entitledButDisabledByCompany,
    );
  }
  if (!_profilePublished(company)) {
    return result(
      LimousinePublicAvailabilityState.enabledButProfileNotPublished,
    );
  }
  // Transaction / bookable gates never hide a published profile. Temporary
  // unavailability is only a real operational pause, never a missing CTA gate.
  if (_temporarilyUnavailable(company)) {
    return result(
      LimousinePublicAvailabilityState.publishedButTemporarilyUnavailable,
    );
  }
  if (!_hasEligibleActiveLimousineVehicle(company) ||
      !_hasPublishedPublicLimousineOffer(company)) {
    return result(
      LimousinePublicAvailabilityState.publishedButTemporarilyUnavailable,
    );
  }
  if (_serverMarksLimousineAvailable(company) ||
      _discoveryListable(company)) {
    return result(LimousinePublicAvailabilityState.publiclyAvailable);
  }
  return result(
    LimousinePublicAvailabilityState.publishedButTemporarilyUnavailable,
  );
}

/// Full public marketplace eligibility: the company self-state must be
/// `publiclyAvailable` AND (when a request is supplied) the requested market
/// must be covered. Delegates market matching to the existing provider gate.
bool isPubliclyEligibleLimousineProvider(
  Map<String, dynamic> company, {
  LimousineMarketRequest? request,
  LimousineEntitlementPolicy policy =
      LimousineEntitlementPolicy.requiresExplicitEntitlement,
}) {
  final composition = composeLimousinePublicAvailability(
    company,
    policy: policy,
  );
  if (!composition.isPubliclyAvailable) return false;
  return isEligibleLimousineProvider(company, request: request);
}

Map<String, dynamic> _subscriptionFeaturesFrom(Map<String, dynamic> company) {
  final direct = asStringKeyedMap(company['features']);
  if (direct.isNotEmpty) return direct;
  final subscription = asStringKeyedMap(
    company['subscription'] ?? company['subscription_profile'],
  );
  if (subscription.isNotEmpty) {
    return asStringKeyedMap(subscription['features']);
  }
  return const <String, dynamic>{};
}

bool _companyBlocked(Map<String, dynamic> company) {
  for (final key in const [
    'deleted',
    'is_deleted',
    'tombstoned',
    'is_tombstoned',
    'suspended',
    'is_suspended',
  ]) {
    if (looksTruthyPublicFlag(company[key])) return true;
  }
  final status = normalizePublicServiceToken(
    (company['status'] ?? company['company_status'] ?? company['companyStatus'])
        ?.toString(),
  );
  if (status == 'deleted' ||
      status == 'suspended' ||
      status == 'tombstoned' ||
      status == 'tombstone') {
    return true;
  }
  if (looksFalseyPublicFlag(company['is_active']) ||
      looksFalseyPublicFlag(company['isActive'])) {
    return true;
  }
  final availability = normalizePublicServiceToken(
    (company['availability_status'] ?? company['availabilityStatus'])
        ?.toString(),
  );
  return availability == 'suspended' || availability == 'deleted';
}

bool _profilePublished(Map<String, dynamic> company) {
  if (looksFalseyPublicFlag(company['profile_enabled']) ||
      looksFalseyPublicFlag(company['profileEnabled'])) {
    return false;
  }
  if (looksTruthyPublicFlag(company['profile_enabled']) ||
      looksTruthyPublicFlag(company['profileEnabled']) ||
      looksTruthyPublicFlag(company['public_profile_published']) ||
      looksTruthyPublicFlag(company['publicProfilePublished'])) {
    return true;
  }
  for (final key in const [
    'published_at',
    'publishedAt',
    'public_partner_profile_published_at',
    'publicPartnerProfilePublishedAt',
  ]) {
    if ((company[key] ?? '').toString().trim().isNotEmpty) return true;
  }
  return false;
}

bool _serverMarksLimousineAvailable(Map<String, dynamic> company) {
  if (looksTruthyPublicFlag(company['limousine_available'])) return true;
  final projection = asStringKeyedMap(company['limousine_projection']);
  if (looksTruthyPublicFlag(projection['limousine_available'])) return true;
  final reason = normalizePublicServiceToken(projection['reason']?.toString());
  return reason == 'eligible';
}

bool _publicBookingsAccepted(Map<String, dynamic> company) {
  // Explicit false fails closed; missing signal defers to bookability.
  if (looksFalseyPublicFlag(company['public_bookings_accepted']) ||
      looksFalseyPublicFlag(company['publicBookingsAccepted']) ||
      looksFalseyPublicFlag(company['bookable'])) {
    return false;
  }
  final availability = normalizePublicServiceToken(
    (company['availability_status'] ?? company['availabilityStatus'])
        ?.toString(),
  );
  if (availability == 'inactive') return false;
  return true;
}

bool _temporarilyUnavailable(Map<String, dynamic> company) {
  if (looksTruthyPublicFlag(company['temporarily_unavailable']) ||
      looksTruthyPublicFlag(company['temporarilyUnavailable'])) {
    return true;
  }
  final availability = normalizePublicServiceToken(
    (company['availability_status'] ?? company['availabilityStatus'])
        ?.toString(),
  );
  return availability == 'paused' || availability == 'offline';
}

bool _discoveryListable(Map<String, dynamic> company) {
  return looksTruthyPublicFlag(company['discovery_listable']) ||
      looksTruthyPublicFlag(company['discoveryListable']);
}

bool _hasPublishedPublicLimousineOffer(Map<String, dynamic> company) {
  final raw =
      company['limousine_offers'] ??
      company['limousineOffers'] ??
      company['offers'];
  if (raw is! List) return false;
  for (final item in raw) {
    if (item is! Map) continue;
    final offer = asStringKeyedMap(item);
    if (looksFalseyPublicFlag(offer['published'])) continue;
    if (looksFalseyPublicFlag(offer['enabled'])) continue;
    if (looksTruthyPublicFlag(offer['draft']) ||
        looksTruthyPublicFlag(offer['is_draft'])) {
      continue;
    }
    return true;
  }
  return false;
}

bool _hasEligibleActiveLimousineVehicle(Map<String, dynamic> company) {
  final raw =
      company['vehicles'] ??
      company['fleet'] ??
      company['public_vehicles'] ??
      company['publicVehicles'];
  if (raw is! List) return false;
  for (final item in raw) {
    if (item is Map && isEligibleLimousineVehicle(asStringKeyedMap(item))) {
      return true;
    }
  }
  return false;
}
