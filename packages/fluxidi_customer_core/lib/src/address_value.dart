/// Address identity for a ride endpoint.
///
/// Ported from golden commit 9df7e7b92ecc86a11184ee995e255da7b8f6fb68:
/// - `lib/limousine/limousine_address_lookup.dart` — `LimousineAddressAcceptance`,
///   `LimousineAddressValue`
/// - `lib/company/company_plan_quote.dart` — `companyPlanAddressIsQuoteReady`,
///   `companyPlanPostcodeFromAddress`
library;

/// How far the customer got with confirming an address.
enum FluxidiAddressAcceptance {
  /// Nothing typed.
  empty,

  /// Typed but not usable as a route endpoint yet.
  incomplete,

  /// Picked from lookup suggestions.
  selected,

  /// Accepted as typed, because it is complete enough to route on.
  manualFallback,
}

class FluxidiAddressValue {
  const FluxidiAddressValue({
    this.displayText = '',
    this.canonicalLabel = '',
    this.lat,
    this.lon,
    this.placeId,
    this.acceptance = FluxidiAddressAcceptance.empty,
    this.fromCurrentLocation = false,
  });

  /// What the customer sees in the field.
  final String displayText;

  /// Canonical label from the lookup, including a house number when known.
  final String canonicalLabel;

  final double? lat;
  final double? lon;
  final String? placeId;
  final FluxidiAddressAcceptance acceptance;
  final bool fromCurrentLocation;

  bool get isEmpty => displayText.trim().isEmpty;

  bool get hasCoordinates =>
      lat != null && lon != null && lat!.isFinite && lon!.isFinite;

  bool get isRouteReady =>
      acceptance == FluxidiAddressAcceptance.selected ||
      acceptance == FluxidiAddressAcceptance.manualFallback;

  /// The text the route and quote are built on. The canonical label wins so a
  /// house number or addition is never dropped in favour of typed shorthand.
  String get routeText {
    if (!isRouteReady) return '';
    final canonical = canonicalLabel.trim();
    if (canonical.isNotEmpty) return canonical;
    return displayText.trim();
  }

  FluxidiAddressValue copyWith({
    String? displayText,
    String? canonicalLabel,
    double? lat,
    double? lon,
    String? placeId,
    FluxidiAddressAcceptance? acceptance,
    bool? fromCurrentLocation,
    bool clearCoordinates = false,
  }) {
    return FluxidiAddressValue(
      displayText: displayText ?? this.displayText,
      canonicalLabel: canonicalLabel ?? this.canonicalLabel,
      lat: clearCoordinates ? null : (lat ?? this.lat),
      lon: clearCoordinates ? null : (lon ?? this.lon),
      placeId: placeId ?? this.placeId,
      acceptance: acceptance ?? this.acceptance,
      fromCurrentLocation: fromCurrentLocation ?? this.fromCurrentLocation,
    );
  }
}

/// An endpoint is only quote-ready when it is accepted, has coordinates and has
/// route text. Unchanged from the existing flow: no coordinates means no quote.
bool fluxidiAddressIsQuoteReady(FluxidiAddressValue value) {
  if (!value.isRouteReady) return false;
  if (!value.hasCoordinates) return false;
  return value.routeText.isNotEmpty;
}

/// Four-digit postcode read from the route text, used for fixed-fare zones.
String fluxidiPostcodeFromAddress(FluxidiAddressValue address) {
  final match = RegExp(r'\b(\d{4})\b').firstMatch(address.routeText);
  return match?.group(1) ?? '';
}

/// Minimum length before an address query means anything.
///
/// Ported with `fluxidiAddressLooksLikeIncompleteFragment` and
/// `fluxidiAddressAllowsManualFallback` from golden
/// `lib/limousine/limousine_address_lookup.dart`
/// (`kLimousineAddressMinQueryLength`,
/// `limousineAddressLooksLikeIncompleteFragment`,
/// `limousineAddressAllowsManualFallback`).
const int kFluxidiAddressMinQueryLength = 3;

bool fluxidiLooksLikeBelgianPostcode(String input) =>
    RegExp(r'^[1-9]\d{3}$').hasMatch(input.trim());

/// A fragment that cannot be routed on, such as a bare street or postcode.
bool fluxidiAddressLooksLikeIncompleteFragment(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return true;
  if (text.length < kFluxidiAddressMinQueryLength) return true;
  if (fluxidiLooksLikeBelgianPostcode(text)) return true;
  if (!RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(text)) return true;
  if (!RegExp(r'[\s,]').hasMatch(text) && text.length < 12) return true;
  return false;
}

/// True when typed text is complete enough to accept without a lookup hit.
bool fluxidiAddressAllowsManualFallback(String raw) {
  if (fluxidiAddressLooksLikeIncompleteFragment(raw)) return false;
  final text = raw.trim();
  if (text.length < 8) return false;
  return RegExp(r'[\s,]').hasMatch(text);
}

/// Classifies typed text without geocoding it.
///
/// Keeps the typed text as the canonical label, so a house number or addition
/// is never dropped. Coordinates stay null: only a lookup may add those.
FluxidiAddressValue fluxidiAddressFromTypedText(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const FluxidiAddressValue();
  return FluxidiAddressValue(
    displayText: text,
    canonicalLabel: text,
    acceptance: fluxidiAddressAllowsManualFallback(text)
        ? FluxidiAddressAcceptance.manualFallback
        : FluxidiAddressAcceptance.incomplete,
  );
}
