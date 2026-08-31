// Shared in-vehicle payment-method availability for street and planned rides.
// Online / QR / cash use the same eligibility surface; this never starts a
// poll or retry loop.

import 'package:fluxidi_tracking/payment/mollie_street_checkout.dart';

class InVehiclePaymentMethodAvailability {
  const InVehiclePaymentMethodAvailability({
    required this.online,
    required this.qr,
    required this.cash,
    this.onlineBlockedMessage,
  });

  final bool online;
  final bool qr;
  final bool cash;
  final String? onlineBlockedMessage;

  List<String> get visibleMethodIds {
    return <String>[
      if (online) 'online',
      if (qr) 'qr',
      if (cash) 'cash',
    ];
  }
}

InVehiclePaymentMethodAvailability resolveInVehiclePaymentMethodAvailability({
  required bool alreadyPaid,
  required bool qrConfigured,
  required bool onlineCheckoutEligible,
  String? onlineBlockedMessage,
}) {
  if (alreadyPaid) {
    return const InVehiclePaymentMethodAvailability(
      online: false,
      qr: false,
      cash: false,
    );
  }
  return InVehiclePaymentMethodAvailability(
    online: onlineCheckoutEligible,
    qr: qrConfigured,
    cash: true,
    onlineBlockedMessage: onlineCheckoutEligible ? null : onlineBlockedMessage,
  );
}

bool resolveInVehicleOnlineCheckoutEligible({
  required String bookingId,
  required bool isPaid,
  required bool isCancelled,
  double? amount,
  String? source,
  String? bookingSource,
  String? rideType,
  String? kind,
}) {
  return resolveMollieStreetCheckoutEligible(
    bookingId: bookingId,
    isPaid: isPaid,
    isCancelled: isCancelled,
    amount: amount,
    source: source,
    bookingSource: bookingSource,
    rideType: rideType,
    kind: kind,
  );
}

String inVehicleOnlineUnavailableMessage({String languageCode = 'nl'}) {
  switch (languageCode.toLowerCase()) {
    case 'fr':
      return 'Le paiement en ligne n’est pas disponible pour cette course.';
    case 'en':
      return 'Online payment is not available for this ride.';
    case 'es':
      return 'El pago en línea no está disponible para este viaje.';
    default:
      return 'Online betalen is niet beschikbaar voor deze rit.';
  }
}
