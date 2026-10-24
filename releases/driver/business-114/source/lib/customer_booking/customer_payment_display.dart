/// Customer-facing payment display tokens and classification.
///
/// Paid is only a confirmed server payment status. A chosen method is not a
/// payment. Missing method/provider must not become "pay in vehicle" or
/// "online outstanding". A payment booking id alone is never treated as Mollie.
library;

import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';

abstract final class CustomerPaymentDisplayTokens {
  static const paid = 'paid';
  static const partiallyPaid = 'partially_paid';
  static const onlinePending = 'online_pending';
  static const payInCar = 'pay_in_car';
  static const qrChosen = 'qr_chosen';
  static const invoice = 'invoice';
  static const unknown = 'unknown';
}

class CustomerPaymentChannel {
  const CustomerPaymentChannel({
    this.method = '',
    this.mode = '',
    this.provider = '',
  });

  final String method;
  final String mode;
  final String provider;

  bool get isEmpty => method.isEmpty && mode.isEmpty && provider.isEmpty;
}

String normalizeCustomerPaymentDisplayToken(String? raw) {
  return (raw ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
}

bool isPaidCustomerPaymentDisplayToken(String token) {
  return normalizeCustomerPaymentDisplayToken(token) ==
      CustomerPaymentDisplayTokens.paid;
}

bool isPartialCustomerPaymentDisplayToken(String token) {
  final normalized = normalizeCustomerPaymentDisplayToken(token);
  return normalized == CustomerPaymentDisplayTokens.partiallyPaid ||
      normalized == 'partial_paid' ||
      normalized == 'partial';
}

bool isOnlinePendingCustomerPaymentDisplayToken(String token) {
  return normalizeCustomerPaymentDisplayToken(token) ==
      CustomerPaymentDisplayTokens.onlinePending;
}

bool isPayInCarCustomerPaymentDisplayToken(String token) {
  return normalizeCustomerPaymentDisplayToken(token) ==
      CustomerPaymentDisplayTokens.payInCar;
}

bool isQrChosenCustomerPaymentDisplayToken(String token) {
  return normalizeCustomerPaymentDisplayToken(token) ==
      CustomerPaymentDisplayTokens.qrChosen;
}

bool isInvoiceCustomerPaymentDisplayToken(String token) {
  return normalizeCustomerPaymentDisplayToken(token) ==
      CustomerPaymentDisplayTokens.invoice;
}

bool isUnknownCustomerPaymentDisplayToken(String token) {
  final normalized = normalizeCustomerPaymentDisplayToken(token);
  return normalized.isEmpty ||
      normalized == CustomerPaymentDisplayTokens.unknown ||
      normalized == 'unpaid' ||
      normalized == 'not_paid';
}

bool isPendingLikeCustomerPaymentStatus(String token) {
  switch (normalizeCustomerPaymentDisplayToken(token)) {
    case 'pending':
    case 'open':
    case 'authorized':
    case 'unpaid':
    case 'not_paid':
      return true;
    default:
      return false;
  }
}

bool isMollieCustomerPaymentChannel({String? provider, String? mode}) {
  final providerToken = normalizeCustomerPaymentDisplayToken(provider);
  final modeToken = normalizeCustomerPaymentDisplayToken(mode);
  if (providerToken == 'mollie' || modeToken == 'mollie') return true;
  const onlineTokens = <String>{
    'online',
    'online_payment',
    'online_payments',
  };
  return onlineTokens.contains(providerToken) ||
      onlineTokens.contains(modeToken);
}

bool isManualCustomerPaymentChannel({String? provider, String? mode}) {
  final providerToken = normalizeCustomerPaymentDisplayToken(provider);
  final modeToken = normalizeCustomerPaymentDisplayToken(mode);
  if (providerToken.isEmpty && modeToken.isEmpty) return false;
  const manualTokens = <String>{'manual', 'cash', 'invoice'};
  return manualTokens.contains(providerToken) ||
      manualTokens.contains(modeToken);
}

String firstCustomerPaymentFieldFromMaps(
  Iterable<Map<String, dynamic>> maps,
  List<String> keys,
) {
  for (final map in maps) {
    for (final key in keys) {
      final value = map[key]?.toString().trim() ?? '';
      if (value.isNotEmpty &&
          value.toLowerCase() != 'null' &&
          value.toLowerCase() != 'undefined' &&
          value != '-') {
        return value;
      }
    }
  }
  return '';
}

Iterable<Map<String, dynamic>> customerPaymentMapsWithNestedQuote(
  Iterable<Map<String, dynamic>> maps,
) sync* {
  for (final map in maps) {
    yield map;
    final quote = map['quote'];
    if (quote is Map) {
      yield Map<String, dynamic>.from(quote);
    }
    final payload = map['payload'];
    if (payload is Map) {
      yield Map<String, dynamic>.from(payload);
      final payloadQuote = payload['quote'];
      if (payloadQuote is Map) {
        yield Map<String, dynamic>.from(payloadQuote);
      }
    }
    final booking = map['booking'];
    if (booking is Map) {
      yield Map<String, dynamic>.from(booking);
    }
  }
}

CustomerPaymentChannel extractCustomerPaymentChannel(
  Iterable<Map<String, dynamic>> maps,
) {
  final sources = customerPaymentMapsWithNestedQuote(maps);
  final rawMethod = firstCustomerPaymentFieldFromMaps(sources, const [
    'payment_method',
    'paymentMethod',
  ]);
  final method = normalizePaymentMethodId(rawMethod);
  var mode = firstCustomerPaymentFieldFromMaps(sources, const [
    'payment_mode',
    'paymentMode',
  ]);
  var provider = firstCustomerPaymentFieldFromMaps(sources, const [
    'payment_provider',
    'paymentProvider',
  ]);
  final definition = method.isEmpty
      ? null
      : PaymentMethodCatalog.definitionFor(method);
  if (definition != null) {
    if (provider.isEmpty) {
      provider = definition.provider.wireValue;
    }
    if (mode.isEmpty) {
      mode = definition.provider.wireValue;
    }
  }
  return CustomerPaymentChannel(
    method: method,
    mode: mode,
    provider: provider,
  );
}

Map<String, dynamic> mergeCustomerPaymentChannelIntoQuote(
  Map<String, dynamic> quote,
  CustomerPaymentChannel channel,
) {
  final next = Map<String, dynamic>.from(quote);
  if (channel.method.isNotEmpty) {
    next['payment_method'] = channel.method;
    next['paymentMethod'] = channel.method;
  }
  if (channel.mode.isNotEmpty) {
    next['payment_mode'] = channel.mode;
    next['paymentMode'] = channel.mode;
  }
  if (channel.provider.isNotEmpty) {
    next['payment_provider'] = channel.provider;
    next['paymentProvider'] = channel.provider;
  }
  return next;
}

/// Converts stored payment fields into a list/detail display token.
///
/// [paymentMethod] wins over provider/mode. A payment booking id is ignored
/// here on purpose: callers must not invent Mollie from that id.
String resolveCustomerPaymentDisplayToken({
  required String paymentStatus,
  String? paymentProvider,
  String? paymentMode,
  String? paymentMethod,
}) {
  final status = normalizeCustomerPaymentDisplayToken(paymentStatus);
  if (isPaidCustomerPaymentDisplayToken(status)) {
    return CustomerPaymentDisplayTokens.paid;
  }
  if (isPartialCustomerPaymentDisplayToken(status)) {
    return CustomerPaymentDisplayTokens.partiallyPaid;
  }
  if (status == CustomerPaymentDisplayTokens.onlinePending) {
    return CustomerPaymentDisplayTokens.onlinePending;
  }
  if (status == CustomerPaymentDisplayTokens.payInCar) {
    return CustomerPaymentDisplayTokens.payInCar;
  }
  if (status == CustomerPaymentDisplayTokens.qrChosen) {
    return CustomerPaymentDisplayTokens.qrChosen;
  }
  if (status == CustomerPaymentDisplayTokens.invoice) {
    return CustomerPaymentDisplayTokens.invoice;
  }

  final method = normalizePaymentMethodId(paymentMethod ?? '');
  final provider = normalizeCustomerPaymentDisplayToken(paymentProvider);
  final mode = normalizeCustomerPaymentDisplayToken(paymentMode);
  final definition = method.isEmpty
      ? null
      : PaymentMethodCatalog.definitionFor(method);
  final pendingLike = isPendingLikeCustomerPaymentStatus(status) || status.isEmpty;

  if (pendingLike) {
    if (method == PaymentMethodIds.qrCode ||
        method == PaymentMethodIds.inVehicleCard ||
        method == PaymentMethodIds.cash) {
      return CustomerPaymentDisplayTokens.payInCar;
    }
    if (method == PaymentMethodIds.invoice) {
      return CustomerPaymentDisplayTokens.invoice;
    }
    if (definition?.provider == PaymentProvider.mollie ||
        definition?.capability == PaymentMethodCapability.mollieOnline) {
      return CustomerPaymentDisplayTokens.onlinePending;
    }
    if (method.isEmpty) {
      if (isMollieCustomerPaymentChannel(provider: provider, mode: mode)) {
        return CustomerPaymentDisplayTokens.onlinePending;
      }
      return CustomerPaymentDisplayTokens.unknown;
    }
    if (definition?.capability == PaymentMethodCapability.manual) {
      return CustomerPaymentDisplayTokens.payInCar;
    }
    return CustomerPaymentDisplayTokens.unknown;
  }

  if (status.isEmpty || status == 'unpaid' || status == 'not_paid') {
    return CustomerPaymentDisplayTokens.unknown;
  }
  return status;
}

({String nl, String en, String fr, String es, String de}) customerPaymentStatusLabel(
  String token,
) {
  final normalized = normalizeCustomerPaymentDisplayToken(token);
  if (isPaidCustomerPaymentDisplayToken(normalized)) {
    return (nl: 'Betaald', en: 'Paid', fr: 'Paye', es: 'Pagado',
      de: 'Bezahlt');
  }
  if (isPartialCustomerPaymentDisplayToken(normalized)) {
    return (
      nl: 'Deels betaald',
      en: 'Partially paid',
      fr: 'Partiellement paye',
      es: 'Parcialmente pagado',
      de: 'Teilweise bezahlt',
    );
  }
  if (isOnlinePendingCustomerPaymentDisplayToken(normalized)) {
    return (
      nl: 'Online betaling openstaand',
      en: 'Online payment pending',
      fr: 'Paiement en ligne en attente',
      es: 'Pago online pendiente',
      de: 'Online-Zahlung ausstehend',
    );
  }
  if (isPayInCarCustomerPaymentDisplayToken(normalized)) {
    return (
      nl: 'Te betalen in het voertuig',
      en: 'To pay in the vehicle',
      fr: 'À payer dans le véhicule',
      es: 'A pagar en el vehículo',
      de: 'Im Fahrzeug zu zahlen',
    );
  }
  if (isQrChosenCustomerPaymentDisplayToken(normalized)) {
    return (
      nl: 'Te betalen in het voertuig',
      en: 'To pay in the vehicle',
      fr: 'À payer dans le véhicule',
      es: 'A pagar en el vehículo',
      de: 'Im Fahrzeug zu zahlen',
    );
  }
  if (isInvoiceCustomerPaymentDisplayToken(normalized)) {
    return (nl: 'Factuur', en: 'Invoice', fr: 'Facture', es: 'Factura',
      de: 'Rechnung');
  }
  return (nl: 'Onbekend', en: 'Unknown', fr: 'Inconnu', es: 'Desconocido',
      de: 'Unbekannt');
}

({String nl, String en, String fr, String es, String de}) customerPaymentStatusDescription(
  String token,
) {
  final normalized = normalizeCustomerPaymentDisplayToken(token);
  if (isPaidCustomerPaymentDisplayToken(normalized)) {
    return (
      nl: 'Je betaling is bevestigd.',
      en: 'Your payment has been confirmed.',
      fr: 'Votre paiement est confirme.',
      es: 'Tu pago esta confirmado.',
      de: 'Ihre Zahlung wurde bestätigt.',
    );
  }
  if (isPartialCustomerPaymentDisplayToken(normalized)) {
    return (
      nl: 'Een deel is betaald, resterend bedrag staat nog open.',
      en: 'Part of this booking is paid, remaining amount is still open.',
      fr: 'Une partie est payee, le montant restant est encore ouvert.',
      es: 'Una parte esta pagada, el monto restante sigue abierto.',
      de: 'Ein Teil dieser Buchung ist bezahlt, der Restbetrag ist noch offen.',
    );
  }
  if (isOnlinePendingCustomerPaymentDisplayToken(normalized)) {
    return (
      nl: 'Rond de online betaling af of annuleer de aanvraag indien toegestaan.',
      en: 'Complete the online payment or cancel the request if allowed.',
      fr: 'Finalisez le paiement en ligne ou annulez la demande si autorise.',
      es: 'Completa el pago online o cancela la solicitud si esta permitido.',
      de: 'Schließen Sie die Online-Zahlung ab oder stornieren Sie die Anfrage, wenn das erlaubt ist.',
    );
  }
  if (isPayInCarCustomerPaymentDisplayToken(normalized)) {
    return (
      nl: 'Voldoe het bedrag bij de chauffeur. In het voertuig kan dit contant, via QR of met kaart zijn, afhankelijk van wat het bedrijf heeft ingeschakeld.',
      en: 'Pay the driver during your ride. In the vehicle this may be cash, QR or card, depending on what the company has enabled.',
      fr: 'Réglez le chauffeur pendant la course. Dans le véhicule, cela peut être espèces, QR ou carte, selon ce que l’entreprise a activé.',
      es: 'Paga al conductor durante el viaje. En el vehículo puede ser efectivo, QR o tarjeta, según lo que la empresa haya activado.',
      de: 'Zahlen Sie während der Fahrt beim Fahrer. Im Fahrzeug kann das Bargeld, QR oder Karte sein, je nachdem, was das Unternehmen aktiviert hat.',
    );
  }
  if (isQrChosenCustomerPaymentDisplayToken(normalized)) {
    return (
      nl: 'Je koos betalen via QR. Dat is nog geen bevestigde betaling.',
      en: 'You chose to pay by QR. That is not a confirmed payment yet.',
      fr: 'Vous avez choisi de payer par QR. Ce n’est pas encore un paiement confirmé.',
      es: 'Elegiste pagar por QR. Eso aún no es un pago confirmado.',
      de: 'Sie haben QR-Zahlung gewählt. Das ist noch keine bestätigte Zahlung.',
    );
  }
  if (isInvoiceCustomerPaymentDisplayToken(normalized)) {
    return (
      nl: 'Deze boeking wordt via factuur afgerekend.',
      en: 'This booking is settled by invoice.',
      fr: 'Cette réservation est réglée par facture.',
      es: 'Esta reserva se liquida por factura.',
      de: 'Diese Buchung wird per Rechnung abgerechnet.',
    );
  }
  return (
    nl: 'De betaalmethode is hier niet bekend. Vernieuw voor de laatste status als je bent aangemeld.',
    en: 'The payment method is not known here. Refresh for the latest status if you are signed in.',
    fr: 'Le mode de paiement n’est pas connu ici. Actualisez pour le dernier statut si vous êtes connecté.',
    es: 'El método de pago no se conoce aquí. Actualiza para el último estado si has iniciado sesión.',
      de: 'Die Zahlungsart ist hier nicht bekannt. Aktualisieren Sie den Status, wenn Sie angemeldet sind.',
  );
}
