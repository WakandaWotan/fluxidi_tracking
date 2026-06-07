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
    if (mode == 'company_mollie' && !mollieConnected) {
      switch (languageCode.toLowerCase()) {
        case 'en':
          return 'Online payments are unavailable until Mollie is connected.';
        case 'fr':
          return 'Les paiements en ligne sont indisponibles tant que Mollie n’est pas connecté.';
        case 'es':
          return 'Los pagos en línea no están disponibles hasta que Mollie esté conectado.';
        default:
          return 'Online betalingen zijn niet beschikbaar tot Mollie is gekoppeld.';
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
  /// When provided, only methods present in both the country profile and the
  /// normalized enabled set are returned (country profile order preserved).
  /// Unknown enabled ids are ignored safely.
  ///
  /// When [ownershipGate] blocks online payments, Mollie-hosted methods are
  /// omitted while manual collection methods remain visible.
  static ResolvedPaymentMethods resolve({
    required String countryCode,
    Iterable<String>? enabledPublicPaymentOptionIds,
    PaymentOwnershipGate? ownershipGate,
    String languageCode = 'nl',
  }) {
    final gate = ownershipGate ?? const PaymentOwnershipGate();
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
    for (final id in profileOrder) {
      if (enabledSet != null && !enabledSet.contains(id)) continue;
      final def = PaymentMethodCatalog.definitionFor(id);
      if (def == null) continue;
      if (!onlineAllowed && def.isMollie) continue;
      methods.add(def);
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
    String languageCode = 'nl',
  }) => resolve(
    countryCode: countryCode,
    enabledPublicPaymentOptionIds: enabledPublicPaymentOptionIds,
    ownershipGate: ownershipGate,
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
