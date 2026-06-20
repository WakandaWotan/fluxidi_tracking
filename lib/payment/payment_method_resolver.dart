/// Resolves country-aware, partner-enabled payment methods for display and UX.
///
/// Pure Dart — no Flutter imports.
library;

import 'payment_method_catalog.dart';

/// Backend payment ownership fields used for UX gating only.
///
/// The worker remains authoritative for online payment creation.
class PaymentOwnershipGate {
  const PaymentOwnershipGate({
    this.paymentOwnerMode = 'fluxidi_central_demo',
    this.paymentDemoMode = true,
    this.mollieConnected = false,
  });

  final String paymentOwnerMode;
  final bool paymentDemoMode;
  final bool mollieConnected;

  bool get onlinePaymentsAvailable {
    switch (paymentOwnerMode.trim().toLowerCase()) {
      case 'manual_only':
        return false;
      case 'company_mollie':
        // UX gate only. Surface online Mollie checkout options once Mollie
        // Connect is linked for this company. The backend worker remains
        // authoritative for the actual payment create and will block when
        // MOLLIE_COMPANY_PAYMENTS_ENABLED is not enabled.
        return mollieConnected;
      case 'fluxidi_central_demo':
        return true;
      default:
        return false;
    }
  }

  String? onlinePaymentsBlockedMessage({String languageCode = 'nl'}) {
    if (onlinePaymentsAvailable) return null;
    final mode = paymentOwnerMode.trim().toLowerCase();
    if (mode == 'company_mollie') {
      // Reached only when Mollie Connect is not linked yet for this company.
      switch (languageCode.toLowerCase()) {
        case 'en':
          return 'Online payments require linking the company Mollie account first.';
        case 'fr':
          return 'Les paiements en ligne nécessitent d’abord la liaison du compte Mollie de l’entreprise.';
        case 'es':
          return 'Los pagos en línea requieren vincular primero la cuenta Mollie de la empresa.';
        default:
          return 'Online betalingen vereisen eerst dat het Mollie-account van het bedrijf gekoppeld wordt.';
      }
    }
    switch (languageCode.toLowerCase()) {
      case 'en':
        return 'Online payment methods are not available for this company.';
      case 'fr':
        return 'Les modes de paiement en ligne ne sont pas disponibles pour cette entreprise.';
      case 'es':
        return 'Los métodos de pago en línea no están disponibles para esta empresa.';
      default:
        return 'Online betaalmethoden zijn niet beschikbaar voor dit bedrijf.';
    }
  }
}

/// Client/runtime capability hints for wallet methods in the payment picker.
///
/// Catalog entries stay intact; this only affects visible/selectable methods.
class PaymentMethodClientContext {
  const PaymentMethodClientContext({
    this.supportsApplePay = true,
    this.supportsGooglePayCheckout = true,
  });

  /// Apple Pay may be offered (typically iOS only).
  final bool supportsApplePay;

  /// Google Pay checkout may be selected (disabled in Mollie forced testmode).
  final bool supportsGooglePayCheckout;

  factory PaymentMethodClientContext.forPlatform({
    required bool isApplePlatform,
    bool supportsGooglePayCheckout = true,
  }) {
    return PaymentMethodClientContext(
      supportsApplePay: isApplePlatform,
      supportsGooglePayCheckout: supportsGooglePayCheckout,
    );
  }

  /// Whether the method may appear in the picker at all.
  bool allowsMethodId(String rawId) {
    final id = normalizePaymentMethodId(rawId);
    if (id == PaymentMethodIds.applePay && !supportsApplePay) return false;
    return true;
  }

  /// Whether the customer may confirm checkout with this method.
  bool isSelectableMethodId(String rawId) {
    final id = normalizePaymentMethodId(rawId);
    if (id == PaymentMethodIds.googlePay && !supportsGooglePayCheckout) {
      return false;
    }
    return allowsMethodId(rawId);
  }
}

/// Result of [PaymentMethodResolver.resolve].
class ResolvedPaymentMethods {
  const ResolvedPaymentMethods({
    required this.countryCode,
    required this.methods,
    this.enabledFilterApplied = false,
    this.onlinePaymentsAvailable = true,
    this.onlinePaymentsBlockedMessage,
  });

  /// Normalized ISO country code used for profile lookup ([GB] for UK input).
  final String countryCode;

  /// Methods in display order.
  final List<PaymentMethodDefinition> methods;

  /// True when [enabledPublicPaymentOptionIds] was non-empty and used to filter.
  final bool enabledFilterApplied;

  /// False when ownership gate blocks online Mollie methods.
  final bool onlinePaymentsAvailable;

  /// UX hint when online methods are hidden/disabled.
  final String? onlinePaymentsBlockedMessage;

  List<String> get ids => methods.map((m) => m.id).toList(growable: false);

  @override
  String toString() =>
      'ResolvedPaymentMethods(country: $countryCode, methods: $ids, '
      'enabledFilterApplied: $enabledFilterApplied, '
      'onlinePaymentsAvailable: $onlinePaymentsAvailable)';
}

/// Country-aware payment method resolution.
abstract final class PaymentMethodResolver {
  /// Returns ordered, visible payment methods for [countryCode].
  ///
  /// When [enabledPublicPaymentOptionIds] is null or empty, all methods from
  /// the country profile are returned.
  ///
  /// When provided, known enabled methods remain visible even when they are not
  /// part of the country profile. The country profile only controls ordering.
  /// Unknown enabled ids are ignored safely.
  ///
  /// When [ownershipGate] blocks online payments, Mollie-hosted methods are
  /// omitted while manual collection methods remain visible.
  static bool inferMollieForcedTestMode({
    required PaymentOwnershipGate gate,
    bool? livePaymentsEnabled,
    bool? mollieForcedTestMode,
  }) {
    if (mollieForcedTestMode == true) return true;
    if (livePaymentsEnabled == false) return true;
    if (gate.paymentOwnerMode.trim().toLowerCase() == 'company_mollie' &&
        livePaymentsEnabled != true) {
      return true;
    }
    return false;
  }

  static bool isGooglePayMethodId(String rawId) =>
      normalizePaymentMethodId(rawId) == PaymentMethodIds.googlePay;

  static bool blocksGooglePayBookSubmit({
    required PaymentOwnershipGate gate,
    bool? livePaymentsEnabled,
    bool? mollieForcedTestMode,
  }) => inferMollieForcedTestMode(
    gate: gate,
    livePaymentsEnabled: livePaymentsEnabled,
    mollieForcedTestMode: mollieForcedTestMode,
  );

  static String googlePayTestModeUnavailableMessage({
    String languageCode = 'nl',
  }) {
    switch (languageCode.toLowerCase()) {
      case 'en':
        return 'Google Pay is not available in test mode. Use card payment, Bancontact, or PayPal.';
      case 'fr':
        return 'Google Pay n’est pas disponible en mode test. Utilisez la carte, Bancontact ou PayPal.';
      case 'es':
        return 'Google Pay no está disponible en modo de prueba. Usa tarjeta, Bancontact o PayPal.';
      default:
        return 'Google Pay is niet beschikbaar in testmodus. Gebruik kaartbetaling, Bancontact of PayPal.';
    }
  }

  static ResolvedPaymentMethods resolve({
    required String countryCode,
    Iterable<String>? enabledPublicPaymentOptionIds,
    PaymentOwnershipGate? ownershipGate,
    PaymentMethodClientContext? clientContext,
    String languageCode = 'nl',
  }) {
    final gate = ownershipGate ?? const PaymentOwnershipGate();
    final client = clientContext ?? const PaymentMethodClientContext();
    final normalizedCountry = normalizeCountryCode(countryCode);
    final profileOrder = PaymentMethodCatalog.defaultMethodOrderForCountry(
      normalizedCountry.isEmpty
          ? PaymentCountryCodes.belgium
          : normalizedCountry,
    );

    final enabled = enabledPublicPaymentOptionIds == null
        ? const <String>[]
        : filterKnownPaymentMethodIds(enabledPublicPaymentOptionIds);

    final enabledFilterApplied = enabled.isNotEmpty;
    final enabledSet = enabledFilterApplied ? enabled.toSet() : null;
    final onlineAllowed = gate.onlinePaymentsAvailable;

    final methods = <PaymentMethodDefinition>[];
    final includedIds = <String>{};
    final manualEnabledByFilter =
        !enabledFilterApplied ||
        enabled.any(PaymentMethodCatalog.legacyManualEnablementIds.contains);

    void addIfVisible(String id) {
      if (includedIds.contains(id)) return;
      if (!client.allowsMethodId(id)) return;
      if (PaymentMethodCatalog.hiddenPickerMethodIds.contains(id)) return;
      if (enabledSet != null && !enabledSet.contains(id)) return;
      final def = PaymentMethodCatalog.definitionFor(id);
      if (def == null) return;
      if (!onlineAllowed && def.isSupportedMollieCheckout) return;
      methods.add(def);
      includedIds.add(def.id);
    }

    if (enabledFilterApplied) {
      final profileSet = profileOrder.toSet();

      for (final id in profileOrder) {
        final def = PaymentMethodCatalog.definitionFor(id);
        if (def == null || !def.isSupportedMollieCheckout) continue;
        addIfVisible(id);
      }

      for (final id in enabled) {
        if (profileSet.contains(id)) continue;
        final def = PaymentMethodCatalog.definitionFor(id);
        if (def == null || !def.isSupportedMollieCheckout) continue;
        addIfVisible(id);
      }

      for (final id in profileOrder) {
        final def = PaymentMethodCatalog.definitionFor(id);
        if (def == null || def.isSupportedMollieCheckout) continue;
        addIfVisible(id);
      }

      for (final id in enabled) {
        if (profileSet.contains(id)) continue;
        final def = PaymentMethodCatalog.definitionFor(id);
        if (def == null || def.isSupportedMollieCheckout) continue;
        addIfVisible(id);
      }
    } else {
      for (final id in profileOrder) {
        addIfVisible(id);
      }
    }

    // Pay in the car / manual in-vehicle collection is not in every country
    // profile (e.g. BE lists online methods only). Pre-P3A.1 UI prepended it
    // explicitly; retain that contract here so ownership gating only affects
    // online Mollie methods.
    if (manualEnabledByFilter) {
      for (final manualId
          in PaymentMethodCatalog.alwaysVisibleManualMethodIds.reversed) {
        if (includedIds.contains(manualId)) continue;
        final def = PaymentMethodCatalog.definitionFor(manualId);
        if (def == null) continue;
        methods.insert(0, def);
        includedIds.add(def.id);
      }
    }

    return ResolvedPaymentMethods(
      countryCode: normalizedCountry.isEmpty
          ? PaymentCountryCodes.belgium
          : normalizedCountry,
      methods: methods,
      enabledFilterApplied: enabledFilterApplied,
      onlinePaymentsAvailable: onlineAllowed,
      onlinePaymentsBlockedMessage: onlineAllowed
          ? null
          : gate.onlinePaymentsBlockedMessage(languageCode: languageCode),
    );
  }

  /// Same as [resolve] but returns only canonical method id strings.
  static List<String> resolveIds({
    required String countryCode,
    Iterable<String>? enabledPublicPaymentOptionIds,
    PaymentOwnershipGate? ownershipGate,
    PaymentMethodClientContext? clientContext,
    String languageCode = 'nl',
  }) => resolve(
    countryCode: countryCode,
    enabledPublicPaymentOptionIds: enabledPublicPaymentOptionIds,
    ownershipGate: ownershipGate,
    clientContext: clientContext,
    languageCode: languageCode,
  ).ids;

  /// Filters [candidateIds] to known methods and reorders them according to
  /// the country profile (unknown ids dropped).
  static List<String> reorderByCountryProfile({
    required String countryCode,
    required Iterable<String> candidateIds,
  }) {
    final normalizedCountry = normalizeCountryCode(countryCode);
    final profileOrder = PaymentMethodCatalog.defaultMethodOrderForCountry(
      normalizedCountry.isEmpty
          ? PaymentCountryCodes.belgium
          : normalizedCountry,
    );
    final candidates = filterKnownPaymentMethodIds(candidateIds).toSet();
    final out = <String>[];
    for (final id in profileOrder) {
      if (candidates.contains(id)) out.add(id);
    }
    for (final id in candidates) {
      if (!out.contains(id)) out.add(id);
    }
    return out;
  }
}
