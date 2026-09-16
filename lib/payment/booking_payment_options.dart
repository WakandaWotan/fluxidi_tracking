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
enum BookingPaymentCapabilityStatus {
  ok,
  loadFailed,
  missing,
  notOffered,
  unknown,
}

BookingPaymentCapabilityStatus parseBookingPaymentCapabilityStatus(Object? raw) {
  switch ((raw ?? '').toString().trim().toLowerCase()) {
    case 'ok':
    case 'available':
      return BookingPaymentCapabilityStatus.ok;
    case 'load_failed':
    case 'loadfailed':
      return BookingPaymentCapabilityStatus.loadFailed;
    case 'missing':
      return BookingPaymentCapabilityStatus.missing;
    case 'not_offered':
    case 'notoffered':
      return BookingPaymentCapabilityStatus.notOffered;
    default:
      return BookingPaymentCapabilityStatus.unknown;
  }
}

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
    this.capabilityProjectionPresent = true,
    this.projectionStatus = BookingPaymentCapabilityStatus.unknown,
  });

  /// The Fluxidi demo payment account.
  ///
  /// Only for demo and test surfaces. A real customer-facing booking flow must
  /// use [BookingPaymentCapability.unavailable] while the company profile is
  /// unknown, so an unverified company can never present a hosted checkout.
  const BookingPaymentCapability.unknown()
    : paymentOwnerMode = 'fluxidi_central_demo',
      paymentDemoMode = true,
      mollieConnected = false,
      livePaymentsEnabled = null,
      mollieForcedTestMode = null,
      publicPaymentOptions = const <String>[],
      qrTransferAvailable = false,
      countryCode = '',
      capabilityProjectionPresent = false,
      projectionStatus = BookingPaymentCapabilityStatus.unknown;

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
      countryCode = '',
      capabilityProjectionPresent = false,
      projectionStatus = BookingPaymentCapabilityStatus.missing;

  /// Reads the capability a worker published for a partner the customer is
  /// booking with.
  ///
  /// An absent or malformed projection yields a capability that offers no
  /// online methods, so a customer is never shown a checkout the partner
  /// cannot honour.
  factory BookingPaymentCapability.fromPublicJson(Object? source) {
    if (source is! Map) return const BookingPaymentCapability.unavailable();
    // A worker may publish the capability nested (limousine does) or flat on
    // the profile. The public partner profile currently carries neither, which
    // is why [capabilityProjectionPresent] is reported rather than guessed.
    final nested = source['payment_capability'];
    final projection = nested is Map ? nested : source;
    bool? optionalBool(Object? value) => value is bool ? value : null;
    Object? read(String snake, String camel) =>
        projection[snake] ?? projection[camel];

    final rawOptions = read('public_payment_options', 'publicPaymentOptions');
    // Fall back to the list the company actually published on its public
    // profile, so enabled methods are not silently dropped. This only affects
    // which known ids may be shown; it never grants online capability.
    final publishedMethods = source['payment_methods'] ?? source['paymentMethods'];
    final options = rawOptions is List
        ? rawOptions.map((e) => e.toString()).toList(growable: false)
        : (publishedMethods is List
              ? publishedMethods.map((e) => e.toString()).toList(growable: false)
              : const <String>[]);

    final ownerMode = (read('payment_owner_mode', 'paymentOwnerMode') ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final status = parseBookingPaymentCapabilityStatus(
      source['payment_capability_status'] ??
          source['paymentCapabilityStatus'] ??
          projection['payment_capability_status'] ??
          projection['status'],
    );
    final hasProjection =
        status == BookingPaymentCapabilityStatus.ok ||
        status == BookingPaymentCapabilityStatus.notOffered ||
        ((status == BookingPaymentCapabilityStatus.unknown) &&
            (ownerMode.isNotEmpty ||
                read('mollie_connected', 'mollieConnected') != null ||
                read('qr_transfer_available', 'qrTransferAvailable') != null));

    return BookingPaymentCapability(
      paymentOwnerMode: ownerMode,
      paymentDemoMode:
          optionalBool(read('payment_demo_mode', 'paymentDemoMode')) ?? true,
      mollieConnected:
          optionalBool(read('mollie_connected', 'mollieConnected')) ?? false,
      livePaymentsEnabled: optionalBool(
        read('live_payments_enabled', 'livePaymentsEnabled'),
      ),
      mollieForcedTestMode: optionalBool(
        read('mollie_forced_test_mode', 'mollieForcedTestMode'),
      ),
      publicPaymentOptions: options,
      qrTransferAvailable:
          optionalBool(read('qr_transfer_available', 'qrTransferAvailable')) ??
          false,
      countryCode: (read('country', 'countryCode') ?? '').toString(),
      capabilityProjectionPresent: hasProjection,
      projectionStatus: status == BookingPaymentCapabilityStatus.unknown && hasProjection
          ? BookingPaymentCapabilityStatus.ok
          : status,
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

  /// Whether the response actually carried a payment capability projection.
  ///
  /// False means the API said nothing about payments — a different situation
  /// from a company that deliberately offers only manual methods, and the
  /// reason online checkout must stay hidden until the API reports it.
  final bool capabilityProjectionPresent;

  /// Server-reported reason the projection is present, missing, or failed.
  final BookingPaymentCapabilityStatus projectionStatus;

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
  ///
  /// Requires a real capability projection: an API that said nothing about
  /// payments is not evidence that bank details are missing.
  bool get qrPaymentMissingBankDetails =>
      visibleMethodIds.contains(PaymentMethodIds.qrCode) &&
      !qrPaymentConfigured &&
      capability.capabilityProjectionPresent;

  /// True when QR cannot be confirmed because the company's payment settings
  /// are simply not known yet.
  bool get qrPaymentDetailsUnknown =>
      visibleMethodIds.contains(PaymentMethodIds.qrCode) &&
      !qrPaymentConfigured &&
      !capability.capabilityProjectionPresent;

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
