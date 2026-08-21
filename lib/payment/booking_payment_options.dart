/// Which payment methods a customer may choose for a booking, and how each of
/// them behaves in the picker.
///
/// Taxi, airport and limousine all ask the same questions here: what can this
/// company accept, which of those may the customer actually confirm with, and
/// which are shown for information only. Keeping that in one place is what lets
/// a new booking surface offer the same choices without restating the rules.
///
/// Each surface still renders its own themed tiles; only the decisions live
/// here. The worker stays authoritative for actually creating a payment.
///
/// Pure Dart — no Flutter imports.
library;

import 'payment_method_catalog.dart';
import 'payment_method_resolver.dart';

/// Market whose payment method ordering applies, from a free-form country.
///
/// Companies record their country as a code or as a name in their own
/// language, so both have to resolve to the same market. Returns `''` when the
/// value names no market this app has payment rules for.
String normalizePaymentMarketCountry(String raw) {
  final normalized = normalizeCountryCode(raw);
  if (normalized.isNotEmpty &&
      PaymentCountryCodes.supported.contains(normalized)) {
    return normalized;
  }
  switch (raw.trim().toLowerCase()) {
    case 'belgie':
    case 'belgië':
    case 'belgium':
      return PaymentCountryCodes.belgium;
    case 'nederland':
    case 'netherlands':
      return PaymentCountryCodes.netherlands;
    case 'frankrijk':
    case 'france':
      return PaymentCountryCodes.france;
    case 'spanje':
    case 'spain':
    case 'españa':
    case 'espana':
      return PaymentCountryCodes.spain;
    default:
      return '';
  }
}

/// Market to hand the resolver, falling back to the home market.
String paymentMarketCountryCode(String raw) {
  final resolved = normalizePaymentMarketCountry(raw);
  return resolved.isEmpty ? PaymentCountryCodes.belgium : resolved;
}

/// Payment capability of the company that will perform the ride.
///
/// For taxi and airport this is the company operating the app. For a
/// marketplace booking it is the partner the customer selected, which is a
/// different company than the one on this device.
class BookingPaymentCapability {
  const BookingPaymentCapability({
    required this.paymentOwnerMode,
    required this.paymentDemoMode,
    required this.mollieConnected,
    this.livePaymentsEnabled,
    this.mollieForcedTestMode,
    this.publicPaymentOptions = const <String>[],
    this.qrTransferAvailable = false,
    this.countryCode = '',
  });

  /// No company capability is known yet.
  ///
  /// Mirrors the default [PaymentOwnershipGate] so a surface whose profile has
  /// not loaded behaves exactly as it did before this seam existed.
  const BookingPaymentCapability.unknown()
    : paymentOwnerMode = 'fluxidi_central_demo',
      paymentDemoMode = true,
      mollieConnected = false,
      livePaymentsEnabled = null,
      mollieForcedTestMode = null,
      publicPaymentOptions = const <String>[],
      qrTransferAvailable = false,
      countryCode = '';

  /// A company whose capability could not be established.
  ///
  /// The unrecognised owner mode makes the ownership gate refuse online
  /// methods, leaving only the manual options visible.
  const BookingPaymentCapability.unavailable()
    : paymentOwnerMode = '',
      paymentDemoMode = true,
      mollieConnected = false,
      livePaymentsEnabled = null,
      mollieForcedTestMode = null,
      publicPaymentOptions = const <String>[],
      qrTransferAvailable = false,
      countryCode = '';

  /// Reads the capability a worker published for a partner the customer is
  /// booking with.
  ///
  /// An absent or malformed projection yields a capability that offers no
  /// online methods, so a customer is never shown a checkout the partner
  /// cannot honour.
  factory BookingPaymentCapability.fromPublicJson(Object? source) {
    if (source is! Map) return const BookingPaymentCapability.unavailable();
    bool? optionalBool(Object? value) => value is bool ? value : null;
    final rawOptions = source['public_payment_options'];
    return BookingPaymentCapability(
      paymentOwnerMode: (source['payment_owner_mode'] ?? '')
          .toString()
          .trim()
          .toLowerCase(),
      paymentDemoMode: optionalBool(source['payment_demo_mode']) ?? true,
      mollieConnected: optionalBool(source['mollie_connected']) ?? false,
      livePaymentsEnabled: optionalBool(source['live_payments_enabled']),
      mollieForcedTestMode: optionalBool(source['mollie_forced_test_mode']),
      publicPaymentOptions: rawOptions is List
          ? rawOptions.map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      qrTransferAvailable:
          optionalBool(source['qr_transfer_available']) ?? false,
      countryCode: (source['country'] ?? '').toString(),
    );
  }

  final String paymentOwnerMode;
  final bool paymentDemoMode;
  final bool mollieConnected;
  final bool? livePaymentsEnabled;
  final bool? mollieForcedTestMode;

  /// Payment options the company published for customer-facing surfaces.
  final List<String> publicPaymentOptions;

  /// Whether the company has bank details behind the QR transfer option.
  final bool qrTransferAvailable;

  /// Country the company operates in, as the company itself recorded it.
  ///
  /// Empty when a surface resolves the market itself instead of taking it from
  /// the capability. Free-form on purpose: normalise it with
  /// [paymentMarketCountryCode] before handing it to the resolver.
  final String countryCode;

  PaymentOwnershipGate get ownershipGate => PaymentOwnershipGate(
    paymentOwnerMode: paymentOwnerMode,
    paymentDemoMode: paymentDemoMode,
    mollieConnected: mollieConnected,
  );

  /// Known, publishable option ids, in the order the company published them.
  List<String> get enabledPaymentOptionIds =>
      filterPublicPartnerPaymentOptionIds(publicPaymentOptions);

  bool get qrPaymentConfigured => qrTransferAvailable;
}

/// Resolved payment picker state for one booking surface.
class BookingPaymentOptions {
  const BookingPaymentOptions({
    required this.capability,
    required this.countryCode,
    required this.languageCode,
    required this.isApplePlatform,
  });

  final BookingPaymentCapability capability;

  /// Market whose method ordering applies.
  final String countryCode;

  final String languageCode;

  /// Apple Pay may only be offered on Apple platforms.
  final bool isApplePlatform;

  bool get mollieForcedTestMode =>
      PaymentMethodResolver.inferMollieForcedTestMode(
        gate: capability.ownershipGate,
        livePaymentsEnabled: capability.livePaymentsEnabled,
        mollieForcedTestMode: capability.mollieForcedTestMode,
      );

  PaymentMethodClientContext get clientContext =>
      PaymentMethodClientContext.forPlatform(
        isApplePlatform: isApplePlatform,
        supportsGooglePayCheckout: !mollieForcedTestMode,
      );

  bool get blocksGooglePayBookSubmit =>
      PaymentMethodResolver.blocksGooglePayBookSubmit(
        gate: capability.ownershipGate,
        livePaymentsEnabled: capability.livePaymentsEnabled,
        mollieForcedTestMode: capability.mollieForcedTestMode,
      );

  ResolvedPaymentMethods get resolved => PaymentMethodResolver.resolve(
    countryCode: countryCode,
    enabledPublicPaymentOptionIds: capability.enabledPaymentOptionIds,
    ownershipGate: capability.ownershipGate,
    clientContext: clientContext,
    languageCode: languageCode,
  );

  /// Methods to show, in display order.
  List<String> get visibleMethodIds => resolved.ids;

  /// Set when online methods are hidden and the customer deserves to know why.
  String? get onlinePaymentsBlockedMessage =>
      resolved.onlinePaymentsBlockedMessage;

  bool get qrPaymentConfigured => capability.qrPaymentConfigured;

  /// True when QR transfer is offered but the company never filled in an IBAN.
  bool get qrPaymentMissingBankDetails =>
      visibleMethodIds.contains(PaymentMethodIds.qrCode) &&
      !qrPaymentConfigured;

  bool isGooglePaySubmitBlocked(String methodId) =>
      PaymentMethodResolver.isGooglePayMethodId(methodId) &&
      blocksGooglePayBookSubmit;

  String googlePayBlockedMessage() =>
      PaymentMethodResolver.googlePayTestModeUnavailableMessage(
        languageCode: languageCode,
      );

  /// Shown, but the customer cannot confirm a booking with it.
  bool isDisplayOnly(String methodId) {
    final id = normalizePaymentMethodId(methodId);
    final def = PaymentMethodCatalog.definitionFor(id);
    if (def == null) return true;
    if (id == PaymentMethodIds.inVehicleCard) return false;
    if (id == PaymentMethodIds.qrCode) return !qrPaymentConfigured;
    if (PaymentMethodResolver.isGooglePayMethodId(id) &&
        blocksGooglePayBookSubmit) {
      return true;
    }
    return !def.isSupportedMollieCheckout;
  }

  /// Selecting it sends the customer straight to a hosted checkout.
  bool isDirectCheckout(String methodId) {
    if (isDisplayOnly(methodId)) return false;
    return PaymentMethodCatalog.definitionFor(
          methodId,
        )?.isSupportedMollieCheckout ??
        false;
  }

  /// Confirmable, but collected outside a hosted checkout.
  bool isSelectableExternal(String methodId) {
    final id = normalizePaymentMethodId(methodId);
    final def = PaymentMethodCatalog.definitionFor(id);
    if (def == null) return false;
    if (def.isSupportedMollieCheckout) return false;
    if (id == PaymentMethodIds.inVehicleCard) return true;
    if (id == PaymentMethodIds.qrCode) return qrPaymentConfigured;
    return false;
  }
}
