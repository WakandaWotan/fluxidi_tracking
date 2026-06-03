/// Resolves country-aware, partner-enabled payment methods for display and UX.
///
/// Pure Dart — no Flutter imports.
library;

import 'payment_method_catalog.dart';

/// Result of [PaymentMethodResolver.resolve].
class ResolvedPaymentMethods {
  const ResolvedPaymentMethods({
    required this.countryCode,
    required this.methods,
    this.enabledFilterApplied = false,
  });

  /// Normalized ISO country code used for profile lookup ([GB] for UK input).
  final String countryCode;

  /// Methods in display order.
  final List<PaymentMethodDefinition> methods;

  /// True when [enabledPublicPaymentOptionIds] was non-empty and used to filter.
  final bool enabledFilterApplied;

  List<String> get ids => methods.map((m) => m.id).toList(growable: false);

  @override
  String toString() =>
      'ResolvedPaymentMethods(country: $countryCode, methods: $ids, '
      'enabledFilterApplied: $enabledFilterApplied)';
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
  static ResolvedPaymentMethods resolve({
    required String countryCode,
    Iterable<String>? enabledPublicPaymentOptionIds,
  }) {
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

    final methods = <PaymentMethodDefinition>[];
    for (final id in profileOrder) {
      if (enabledSet != null && !enabledSet.contains(id)) continue;
      final def = PaymentMethodCatalog.definitionFor(id);
      if (def != null) methods.add(def);
    }

    return ResolvedPaymentMethods(
      countryCode: normalizedCountry.isEmpty
          ? PaymentCountryCodes.belgium
          : normalizedCountry,
      methods: methods,
      enabledFilterApplied: enabledFilterApplied,
    );
  }

  /// Same as [resolve] but returns only canonical method id strings.
  static List<String> resolveIds({
    required String countryCode,
    Iterable<String>? enabledPublicPaymentOptionIds,
  }) => resolve(
    countryCode: countryCode,
    enabledPublicPaymentOptionIds: enabledPublicPaymentOptionIds,
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
