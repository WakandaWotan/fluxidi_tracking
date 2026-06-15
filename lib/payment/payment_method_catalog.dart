/// Stable payment method identifiers and country defaults for Fluxidi.
///
/// Pure Dart — no Flutter imports.
library;

enum PaymentProvider { mollie, manual }

/// Capability bucket for payment-option display vs. checkout creation.
enum PaymentMethodCapability {
  manual,
  offlineOrExternal,
  mollieOnline,
  futureOrConditional,
}

/// Stable provider tokens for payloads and persistence.
extension PaymentProviderWire on PaymentProvider {
  String get wireValue => switch (this) {
    PaymentProvider.mollie => 'mollie',
    PaymentProvider.manual => 'manual',
  };
}

/// Canonical public payment method id strings (snake_case).
abstract final class PaymentMethodIds {
  static const bancontact = 'bancontact';
  static const bancontactQr = 'bancontact_qr';
  static const ideal = 'ideal';
  static const cardPayment = 'card_payment';
  static const applePay = 'apple_pay';
  static const googlePay = 'google_pay';
  static const paypal = 'paypal';
  static const cartesBancaires = 'cartes_bancaires';
  static const bizum = 'bizum';
  static const cash = 'cash';
  static const qrCode = 'qr_code';
  static const payconiqWero = 'payconiq_wero';
  static const onlinePayment = 'online_payment';
  static const bankTransferBacs = 'bank_transfer_bacs';
  static const inVehicleCard = 'in_vehicle_card';
  static const invoice = 'invoice';

  static const all = <String>[
    bancontact,
    bancontactQr,
    ideal,
    cardPayment,
    applePay,
    googlePay,
    paypal,
    cartesBancaires,
    bizum,
    cash,
    qrCode,
    payconiqWero,
    onlinePayment,
    bankTransferBacs,
    inVehicleCard,
    invoice,
  ];
}

/// ISO 3166-1 alpha-2 country codes supported by default profiles.
abstract final class PaymentCountryCodes {
  static const belgium = 'BE';
  static const netherlands = 'NL';
  static const france = 'FR';
  static const spain = 'ES';
  static const greatBritain = 'GB';
  static const unitedKingdom = 'UK';

  static const supported = <String>{
    belgium,
    netherlands,
    france,
    spain,
    greatBritain,
    unitedKingdom,
  };
}

/// Immutable definition for a known payment method.
class PaymentMethodDefinition {
  const PaymentMethodDefinition({
    required this.id,
    required this.provider,
    required this.capability,
  });

  final String id;
  final PaymentProvider provider;
  final PaymentMethodCapability capability;

  bool get isMollie => provider == PaymentProvider.mollie;

  bool get isSupportedMollieCheckout =>
      capability == PaymentMethodCapability.mollieOnline;

  bool get isManual => provider == PaymentProvider.manual;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentMethodDefinition &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          provider == other.provider &&
          capability == other.capability;

  @override
  int get hashCode => Object.hash(id, provider, capability);

  @override
  String toString() =>
      'PaymentMethodDefinition(id: $id, provider: $provider, capability: $capability)';
}

/// Normalizes raw payment method tokens to canonical ids when recognized.
///
/// Unknown values are returned lowercased and trimmed; callers should pass
/// through [filterKnownPaymentMethodIds] when unknown ids must be dropped.
String normalizePaymentMethodId(String raw) {
  final token = raw.trim().toLowerCase().replaceAll('-', '_');
  if (token.isEmpty) return '';
  switch (token) {
    case 'qr':
      return PaymentMethodIds.qrCode;
    case 'online':
    case 'online_payments':
    case 'online-payments':
      return PaymentMethodIds.onlinePayment;
    case 'card':
    case 'cards':
    case 'creditcard':
    case 'credit_card':
      return PaymentMethodIds.cardPayment;
    case 'applepay':
      return PaymentMethodIds.applePay;
    case 'googlepay':
      return PaymentMethodIds.googlePay;
    case 'carte_bancaire':
    case 'cartes_bancaire':
    case 'carte_bancaires':
    case 'cartesbancaires':
    case 'cartes_bancaires_cb':
    case 'cb':
      return PaymentMethodIds.cartesBancaires;
    case 'wero':
    case 'payconiq':
    case 'payconiq_by_bancontact':
      return PaymentMethodIds.payconiqWero;
    case 'bancontact_qr':
    case 'bancontactqr':
    case 'bancontact_pay_qr':
    case 'payconiq_qr':
      return PaymentMethodIds.bancontactQr;
    case 'bacs':
    case 'bank_transfer':
    case 'bankoverschrijving':
      return PaymentMethodIds.bankTransferBacs;
    case 'in_car':
    case 'in_vehicle':
    case 'in-car':
    case 'manual':
    case 'pay_in_car':
    case 'cash_in_car':
      return PaymentMethodIds.inVehicleCard;
    default:
      return token;
  }
}

/// Normalizes country codes. [UK] is mapped to [GB] for profile lookup.
String normalizeCountryCode(String raw) {
  final token = raw.trim().toUpperCase();
  if (token.isEmpty) return '';
  if (token == PaymentCountryCodes.unitedKingdom) {
    return PaymentCountryCodes.greatBritain;
  }
  return token;
}

/// Keeps only ids that exist in [PaymentMethodCatalog.knownIds], preserving order.
List<String> filterKnownPaymentMethodIds(Iterable<String> rawIds) {
  final known = PaymentMethodCatalog.knownIds;
  final seen = <String>{};
  final out = <String>[];
  for (final raw in rawIds) {
    final id = normalizePaymentMethodId(raw);
    if (id.isEmpty || !known.contains(id) || seen.contains(id)) continue;
    seen.add(id);
    out.add(id);
  }
  return out;
}

/// Catalog of payment methods, providers, and country-default orderings.
abstract final class PaymentMethodCatalog {
  static final Map<String, PaymentMethodDefinition> _byId =
      Map<String, PaymentMethodDefinition>.unmodifiable(
        <String, PaymentMethodDefinition>{
          for (final def in _allDefinitions) def.id: def,
        },
      );

  static const Set<String> knownIds = <String>{
    PaymentMethodIds.bancontact,
    PaymentMethodIds.bancontactQr,
    PaymentMethodIds.ideal,
    PaymentMethodIds.cardPayment,
    PaymentMethodIds.applePay,
    PaymentMethodIds.googlePay,
    PaymentMethodIds.paypal,
    PaymentMethodIds.cartesBancaires,
    PaymentMethodIds.bizum,
    PaymentMethodIds.cash,
    PaymentMethodIds.qrCode,
    PaymentMethodIds.payconiqWero,
    PaymentMethodIds.onlinePayment,
    PaymentMethodIds.bankTransferBacs,
    PaymentMethodIds.inVehicleCard,
    PaymentMethodIds.invoice,
  };

  static List<PaymentMethodDefinition> get allDefinitions =>
      List<PaymentMethodDefinition>.unmodifiable(_allDefinitions);

  static PaymentMethodDefinition? definitionFor(String rawId) {
    final id = normalizePaymentMethodId(rawId);
    if (id.isEmpty) return null;
    return _byId[id];
  }

  static PaymentProvider? providerFor(String rawId) =>
      definitionFor(rawId)?.provider;

  /// Returns true when the method is collected via Mollie hosted checkout.
  static bool isMollieMethod(String rawId) =>
      providerFor(rawId) == PaymentProvider.mollie;

  static bool isSupportedMollieCheckoutMethod(String rawId) =>
      definitionFor(rawId)?.isSupportedMollieCheckout ?? false;

  /// Manual methods always shown in booking pickers (before country profile methods).
  ///
  /// Online ownership gating must not remove these; only an explicit future
  /// business setting may disable manual collection.
  static const List<String> alwaysVisibleManualMethodIds = <String>[
    PaymentMethodIds.inVehicleCard,
  ];

  static const Set<String> legacyManualEnablementIds = <String>{
    PaymentMethodIds.cash,
    PaymentMethodIds.qrCode,
    PaymentMethodIds.inVehicleCard,
    PaymentMethodIds.invoice,
  };

  /// Default visible method order for a market (before partner enablement filter).
  static List<String> defaultMethodOrderForCountry(String rawCountryCode) {
    final country = normalizeCountryCode(rawCountryCode);
    return List<String>.unmodifiable(
      _countryProfiles[country] ??
          _countryProfiles[PaymentCountryCodes.belgium]!,
    );
  }

  static const List<PaymentMethodDefinition> _allDefinitions =
      <PaymentMethodDefinition>[
        PaymentMethodDefinition(
          id: PaymentMethodIds.bancontact,
          provider: PaymentProvider.mollie,
          capability: PaymentMethodCapability.mollieOnline,
        ),
        PaymentMethodDefinition(
          id: PaymentMethodIds.bancontactQr,
          provider: PaymentProvider.mollie,
          capability: PaymentMethodCapability.mollieOnline,
        ),
        PaymentMethodDefinition(
          id: PaymentMethodIds.ideal,
          provider: PaymentProvider.mollie,
          capability: PaymentMethodCapability.mollieOnline,
        ),
        PaymentMethodDefinition(
          id: PaymentMethodIds.cardPayment,
          provider: PaymentProvider.mollie,
          capability: PaymentMethodCapability.mollieOnline,
        ),
        PaymentMethodDefinition(
          id: PaymentMethodIds.applePay,
          provider: PaymentProvider.mollie,
          capability: PaymentMethodCapability.mollieOnline,
        ),
        PaymentMethodDefinition(
          id: PaymentMethodIds.googlePay,
          provider: PaymentProvider.mollie,
          capability: PaymentMethodCapability.mollieOnline,
        ),
        PaymentMethodDefinition(
          id: PaymentMethodIds.paypal,
          provider: PaymentProvider.mollie,
          capability: PaymentMethodCapability.mollieOnline,
        ),
        PaymentMethodDefinition(
          id: PaymentMethodIds.cartesBancaires,
          provider: PaymentProvider.mollie,
          capability: PaymentMethodCapability.mollieOnline,
        ),
        PaymentMethodDefinition(
          id: PaymentMethodIds.bizum,
          provider: PaymentProvider.manual,
          capability: PaymentMethodCapability.futureOrConditional,
        ),
        PaymentMethodDefinition(
          id: PaymentMethodIds.payconiqWero,
          provider: PaymentProvider.manual,
          capability: PaymentMethodCapability.futureOrConditional,
        ),
        PaymentMethodDefinition(
          id: PaymentMethodIds.onlinePayment,
          provider: PaymentProvider.manual,
          capability: PaymentMethodCapability.offlineOrExternal,
        ),
        PaymentMethodDefinition(
          id: PaymentMethodIds.cash,
          provider: PaymentProvider.manual,
          capability: PaymentMethodCapability.manual,
        ),
        PaymentMethodDefinition(
          id: PaymentMethodIds.qrCode,
          provider: PaymentProvider.manual,
          capability: PaymentMethodCapability.offlineOrExternal,
        ),
        PaymentMethodDefinition(
          id: PaymentMethodIds.bankTransferBacs,
          provider: PaymentProvider.manual,
          capability: PaymentMethodCapability.offlineOrExternal,
        ),
        PaymentMethodDefinition(
          id: PaymentMethodIds.inVehicleCard,
          provider: PaymentProvider.manual,
          capability: PaymentMethodCapability.manual,
        ),
        PaymentMethodDefinition(
          id: PaymentMethodIds.invoice,
          provider: PaymentProvider.manual,
          capability: PaymentMethodCapability.offlineOrExternal,
        ),
      ];

  static const Map<String, List<String>> _countryProfiles =
      <String, List<String>>{
        PaymentCountryCodes.belgium: <String>[
          PaymentMethodIds.bancontactQr,
          PaymentMethodIds.bancontact,
          PaymentMethodIds.cardPayment,
          PaymentMethodIds.applePay,
          PaymentMethodIds.googlePay,
          PaymentMethodIds.paypal,
        ],
        PaymentCountryCodes.netherlands: <String>[
          PaymentMethodIds.ideal,
          PaymentMethodIds.cardPayment,
          PaymentMethodIds.applePay,
          PaymentMethodIds.googlePay,
          PaymentMethodIds.paypal,
        ],
        PaymentCountryCodes.france: <String>[
          PaymentMethodIds.cartesBancaires,
          PaymentMethodIds.cardPayment,
          PaymentMethodIds.applePay,
          PaymentMethodIds.googlePay,
          PaymentMethodIds.paypal,
        ],
        PaymentCountryCodes.spain: <String>[
          PaymentMethodIds.cardPayment,
          PaymentMethodIds.applePay,
          PaymentMethodIds.googlePay,
          PaymentMethodIds.paypal,
        ],
        PaymentCountryCodes.greatBritain: <String>[
          PaymentMethodIds.cardPayment,
          PaymentMethodIds.applePay,
          PaymentMethodIds.googlePay,
          PaymentMethodIds.paypal,
          PaymentMethodIds.bankTransferBacs,
        ],
      };
}
