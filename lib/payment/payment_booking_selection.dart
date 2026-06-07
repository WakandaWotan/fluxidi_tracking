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
    this.mollieMethod,
    this.qrPreferred = false,
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

  /// Mollie API method token when applicable (e.g. `bancontact`, `ideal`).
  final String? mollieMethod;

  /// True when the customer prefers an in-app QR flow (Belgian Bancontact QR).
  final bool qrPreferred;

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

    final mollieExtras = _mollieExtrasForMethodId(definition.id);

    return BookingPaymentSelection(
      paymentMethodId: definition.id,
      paymentMode: mode,
      paymentProvider: providerWire,
      isMollieCheckout: provider == PaymentProvider.mollie,
      isTikkieRequest: provider == PaymentProvider.tikkieManual,
      isManualCollection: provider == PaymentProvider.manual,
      mollieMethod: mollieExtras.$1,
      qrPreferred: mollieExtras.$2,
    );
  }

  static (String?, bool) _mollieExtrasForMethodId(String methodId) {
    switch (methodId) {
      case PaymentMethodIds.bancontactQr:
        return ('bancontact', true);
      case PaymentMethodIds.bancontact:
        return ('bancontact', false);
      case PaymentMethodIds.ideal:
        return ('ideal', false);
      case PaymentMethodIds.cardPayment:
        return ('creditcard', false);
      case PaymentMethodIds.applePay:
        return ('applepay', false);
      case PaymentMethodIds.googlePay:
        return ('googlepay', false);
      case PaymentMethodIds.paypal:
        return ('paypal', false);
      case PaymentMethodIds.cartesBancaires:
        return ('creditcard', false);
      case PaymentMethodIds.bizum:
        return ('creditcard', false);
      case PaymentMethodIds.payconiqWero:
        return ('bancontact', false);
      case PaymentMethodIds.onlinePayment:
        return (null, false);
      default:
        return (null, false);
    }
  }

  /// Additive booking payload fields (snake_case and camelCase mirrors).
  Map<String, dynamic> toPayloadFields() {
    final fields = <String, dynamic>{
      'payment_mode': paymentMode,
      'paymentMode': paymentMode,
      'payment_provider': paymentProvider,
      'paymentProvider': paymentProvider,
      'payment_method': paymentMethodId,
      'paymentMethod': paymentMethodId,
    };
    final mollie = mollieMethod?.trim();
    if (mollie != null && mollie.isNotEmpty) {
      fields['mollie_method'] = mollie;
      fields['mollieMethod'] = mollie;
    }
    if (qrPreferred) {
      fields['qr_preferred'] = true;
      fields['qrPreferred'] = true;
    }
    return fields;
  }

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
          isManualCollection == other.isManualCollection &&
          mollieMethod == other.mollieMethod &&
          qrPreferred == other.qrPreferred;

  @override
  int get hashCode => Object.hash(
    paymentMethodId,
    paymentMode,
    paymentProvider,
    isMollieCheckout,
    isTikkieRequest,
    isManualCollection,
    mollieMethod,
    qrPreferred,
  );

  @override
  String toString() =>
      'BookingPaymentSelection(method: $paymentMethodId, mode: $paymentMode, '
      'provider: $paymentProvider, mollie: $isMollieCheckout, '
      'tikkie: $isTikkieRequest, manual: $isManualCollection, '
      'mollieMethod: $mollieMethod, qrPreferred: $qrPreferred)';
}
