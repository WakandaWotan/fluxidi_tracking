import '../app_strings.dart';
import 'limousine_marketplace_labels.dart';
import 'limousine_service_capability.dart';

/// Build-time gate for a live Customers-page limousine card.
///
/// Default off. Nearby discovery exists (`GET /partners/nearby`) but does not
/// filter by limousine, does not return vehicles, and the worker drops
/// capability booleans on persist. Showing a card now would either list taxi
/// companies or an empty invented marketplace.
const String kLimousineMarketplaceCustomerEntryDefineKey =
    'FLUXIDI_LIMOUSINE_MARKETPLACE_ENTRY';

const bool kLimousineMarketplaceCustomerEntryEnabled = bool.fromEnvironment(
  kLimousineMarketplaceCustomerEntryDefineKey,
  defaultValue: false,
);

/// Missing backend contract that blocks a live customer entry in P0.
const String kLimousineMarketplaceMissingBackendContract = '''
Limousine P0 does not invent fixture providers. A live Customers-page card
stays gated until these authoritative seams exist:

1. GET /partners/nearby has no service=limousine (or equivalent) filter.
   Vertical filtering is client-side today and airport-only.
2. _normalizePublicPartnerProfileEntry persists services[] but drops
   capabilities, limousine_service_enabled, and booking_capabilities extras.
   The durable company opt-in is therefore services[] containing "limousine".
3. _normalizePublicVehicles has no limousine service token; VehicleProfile
   has no limousine service configuration field. Eligibility therefore
   requires an explicit vehicle/service token and fails closed when the
   nearby payload omits vehicles.
4. Worker normalizeService() has no limousine service. Shared-engine booking
   still uses CalculatorPage + POST /quote; do not copy the taxi engine or
   add a second payment path.

P1 may show the gated card only when published services[] + explicit
limousine vehicle/service configuration are queryable from a real partner
payload, without hardcoded FLX company codes.
''';

/// Prepared Customers-page entry. Not wired onto the page while the gate is
/// off and provider discovery cannot prove limousine eligibility.
abstract final class LimousineCustomerEntryContract {
  static const String publicServiceId = kLimousinePublicServiceId;
  static const String visualAsset = kLimousineMarketplaceHeroAsset;
  static const String sharedEngineSeam = kLimousineSharedEngineSeam;
  static const String missingBackendContract =
      kLimousineMarketplaceMissingBackendContract;

  static const LocalizedText bookLabel = kLimousineBookLabel;

  static bool get isVisible => kLimousineMarketplaceCustomerEntryEnabled;
}
