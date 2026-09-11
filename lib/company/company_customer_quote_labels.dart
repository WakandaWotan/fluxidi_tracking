// COMPANY-CUSTOMER-OPS-P0

import 'package:fluxidi_tracking/app_strings.dart';

const LocalizedText kCompanyCustomerQuoteCreate = LocalizedText(
  nl: 'Offerte maken',
  en: 'Create quote',
  fr: 'Créer un devis',
  es: 'Crear presupuesto',
);

const LocalizedText kCompanyCustomerQuoteTitle = LocalizedText(
  nl: 'Offerte',
  en: 'Quote',
  fr: 'Devis',
  es: 'Presupuesto',
);

const LocalizedText kCompanyCustomerQuoteIssuer = LocalizedText(
  nl: 'Offerte namens',
  en: 'Quote on behalf of',
  fr: 'Devis au nom de',
  es: 'Presupuesto en nombre de',
);

const LocalizedText kCompanyCustomerQuotePickup = LocalizedText(
  nl: 'Vertrek',
  en: 'Pickup',
  fr: 'Départ',
  es: 'Salida',
);

const LocalizedText kCompanyCustomerQuoteDropoff = LocalizedText(
  nl: 'Bestemming',
  en: 'Destination',
  fr: 'Destination',
  es: 'Destino',
);

const LocalizedText kCompanyCustomerQuoteStart = LocalizedText(
  nl: 'Datum en tijd',
  en: 'Date and time',
  fr: 'Date et heure',
  es: 'Fecha y hora',
);

const LocalizedText kCompanyCustomerQuotePassengers = LocalizedText(
  nl: 'Passagiers',
  en: 'Passengers',
  fr: 'Passagers',
  es: 'Pasajeros',
);

const LocalizedText kCompanyCustomerQuoteDescription = LocalizedText(
  nl: 'Omschrijving',
  en: 'Description',
  fr: 'Description',
  es: 'Descripción',
);

const LocalizedText kCompanyCustomerQuotePrice = LocalizedText(
  nl: 'Prijs (bedrijfstarief)',
  en: 'Price (company rate)',
  fr: 'Prix (tarif entreprise)',
  es: 'Precio (tarifa de empresa)',
);

const LocalizedText kCompanyCustomerQuoteValidUntil = LocalizedText(
  nl: 'Geldig tot',
  en: 'Valid until',
  fr: 'Valable jusqu’au',
  es: 'Válido hasta',
);

const LocalizedText kCompanyCustomerQuoteSaveDraft = LocalizedText(
  nl: 'Concept bewaren',
  en: 'Save draft',
  fr: 'Enregistrer le brouillon',
  es: 'Guardar borrador',
);

const LocalizedText kCompanyCustomerQuoteReview = LocalizedText(
  nl: 'Controleren',
  en: 'Review',
  fr: 'Vérifier',
  es: 'Revisar',
);

const LocalizedText kCompanyCustomerQuoteSend = LocalizedText(
  nl: 'Verzenden',
  en: 'Send',
  fr: 'Envoyer',
  es: 'Enviar',
);

const LocalizedText kCompanyCustomerQuoteEmailRequired = LocalizedText(
  nl: 'Voor verzending is een geldig e-mailadres nodig. Een concept mag zonder.',
  en: 'Sending needs a valid email address. A draft may be saved without one.',
  fr: 'L’envoi exige un e-mail valide. Un brouillon peut être enregistré sans.',
  es: 'El envío necesita un correo válido. El borrador puede guardarse sin él.',
);

const LocalizedText kCompanyCustomerQuotePriceRequired = LocalizedText(
  nl: 'Voor verzending is een expliciete prijs en valuta nodig. Een concept mag zonder prijs.',
  en: 'Sending needs an explicit price and currency. A draft may be saved without a price.',
  fr: 'L’envoi exige un prix et une devise explicites. Un brouillon peut être enregistré sans prix.',
  es: 'El envío necesita un precio y una moneda explícitos. El borrador puede guardarse sin precio.',
);

const LocalizedText kCompanyCustomerQuoteMailNotConfigured = LocalizedText(
  nl: 'Geen verzendadapter. De offerte is niet naar de klant verzonden.',
  en: 'No send adapter. The quote was not sent to the customer.',
  fr: 'Aucun adaptateur d’envoi. Le devis n’a pas été envoyé au client.',
  es: 'Sin adaptador de envío. El presupuesto no se envió al cliente.',
);

const LocalizedText kCompanyCustomerQuoteSendFailed = LocalizedText(
  nl: 'Verzenden is mislukt. De offerte blijft een concept.',
  en: 'Sending failed. The quote stays a draft.',
  fr: 'L’envoi a échoué. Le devis reste un brouillon.',
  es: 'El envío falló. El presupuesto sigue siendo un borrador.',
);

const LocalizedText kCompanyCustomerQuoteAdapterAccepted = LocalizedText(
  nl: 'Verzendadapter heeft de offerte aangenomen. Bezorging is niet bewezen.',
  en: 'The send adapter accepted the quote. Delivery is not proven.',
  fr: 'L’adaptateur d’envoi a accepté le devis. La livraison n’est pas prouvée.',
  es: 'El adaptador de envío aceptó el presupuesto. La entrega no está demostrada.',
);

const LocalizedText kCompanyCustomerQuoteSent = LocalizedText(
  nl: 'Offerte klaargezet voor lokale testverzending. Geen echte klantmail.',
  en: 'Quote queued for local test delivery. No real customer email was sent.',
  fr: 'Devis préparé pour un envoi de test local. Aucun e-mail client réel.',
  es: 'Presupuesto preparado para envío de prueba local. No se envió correo real.',
);

const LocalizedText kCompanyCustomerQuoteAccepted = LocalizedText(
  nl: 'Geaccepteerd. Er is geen rit gestart.',
  en: 'Accepted. No ride was started.',
  fr: 'Accepté. Aucune course n’a été démarrée.',
  es: 'Aceptado. No se inició ningún viaje.',
);
