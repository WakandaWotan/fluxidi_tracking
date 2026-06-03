/// Maps a selected payment method id to additive booking payload fields.
///
/// Pure Dart — no Flutter imports.
library;

import 'payment_method_catalog.dart';

/// Immutable booking payment selection derived from a catalog method id.
class BookingPaymentSelection {
  const BookingPaymentSelection({
    required this.paymentMethodId,
    required this.paymentMode,
    required this.paymentProvider,
    required this.isMollieCheckout,
    required this.isTikkieRequest,
    required this.isManualCollection,
  });

  /// Canonical payment method id (e.g. [PaymentMethodIds.ideal]).
  final String paymentMethodId;

  /// Worker checkout gate: `mollie` or `manual`.
  final String paymentMode;

  /// Collection channel: `mollie`, `manual`, or `tikkie_manual`.
  final String paymentProvider;

  /// True when Mollie hosted checkout should be triggered.
  final bool isMollieCheckout;

  /// True when the Tikkie payment-request channel applies.
  final bool isTikkieRequest;

  /// True when payment is collected manually during or after the ride.
  final bool isManualCollection;

  /// Default manual method for unknown or empty input ("pay in the car").
  static const String defaultManualMethodId = PaymentMethodIds.inVehicleCard;

  /// Resolves [rawMethodId] via [PaymentMethodCatalog] to booking fields.
  factory BookingPaymentSelection.fromMethodId(String rawMethodId) {
    final definition = PaymentMethodCatalog.definitionFor(rawMethodId);
    if (definition == null) {
      return BookingPaymentSelection._manualFallback();
    }
    return BookingPaymentSelection._fromDefinition(definition);
  }

  factory BookingPaymentSelection._manualFallback() {
    return BookingPaymentSelection(
      paymentMethodId: defaultManualMethodId,
      paymentMode: PaymentProvider.manual.wireValue,
      paymentProvider: PaymentProvider.manual.wireValue,
      isMollieCheckout: false,
      isTikkieRequest: false,
      isManualCollection: true,
    );
  }

  factory BookingPaymentSelection._fromDefinition(
    PaymentMethodDefinition definition,
  ) {
    final provider = definition.provider;
    final String mode;
    final String providerWire;

    switch (provider) {
      case PaymentProvider.mollie:
        mode = PaymentProvider.mollie.wireValue;
        providerWire = PaymentProvider.mollie.wireValue;
      case PaymentProvider.tikkieManual:
        mode = PaymentProvider.manual.wireValue;
        providerWire = PaymentProvider.tikkieManual.wireValue;
      case PaymentProvider.manual:
        mode = PaymentProvider.manual.wireValue;
        providerWire = PaymentProvider.manual.wireValue;
    }

    return BookingPaymentSelection(
      paymentMethodId: definition.id,
      paymentMode: mode,
      paymentProvider: providerWire,
      isMollieCheckout: provider == PaymentProvider.mollie,
      isTikkieRequest: provider == PaymentProvider.tikkieManual,
      isManualCollection: provider == PaymentProvider.manual,
    );
  }

  /// Additive booking payload fields (snake_case and camelCase mirrors).
  Map<String, String> toPayloadFields() => {
    'payment_mode': paymentMode,
    'paymentMode': paymentMode,
    'payment_provider': paymentProvider,
    'paymentProvider': paymentProvider,
    'payment_method': paymentMethodId,
    'paymentMethod': paymentMethodId,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookingPaymentSelection &&
          runtimeType == other.runtimeType &&
          paymentMethodId == other.paymentMethodId &&
          paymentMode == other.paymentMode &&
          paymentProvider == other.paymentProvider &&
          isMollieCheckout == other.isMollieCheckout &&
          isTikkieRequest == other.isTikkieRequest &&
          isManualCollection == other.isManualCollection;

  @override
  int get hashCode => Object.hash(
    paymentMethodId,
    paymentMode,
    paymentProvider,
    isMollieCheckout,
    isTikkieRequest,
    isManualCollection,
  );

  @override
  String toString() =>
      'BookingPaymentSelection(method: $paymentMethodId, mode: $paymentMode, '
      'provider: $paymentProvider, mollie: $isMollieCheckout, '
      'tikkie: $isTikkieRequest, manual: $isManualCollection)';
}
