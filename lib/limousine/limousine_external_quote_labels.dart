import '../app_strings.dart';
import 'limousine_quote_inbox.dart';

const LocalizedText kLimousineExternalQuoteCreateAction = LocalizedText(
  nl: 'Nieuwe offerte voor eigen klant',
  en: 'New quotation for own customer',
  fr: 'Nouveau devis pour un client propre',
  es: 'Nuevo presupuesto para cliente propio',
);

const LocalizedText kLimousineExternalQuoteCreateSubtitle = LocalizedText(
  nl: 'Maak een offerte voor een klant zonder Fluxidi-app.',
  en: 'Create a quotation for a customer without the Fluxidi app.',
  fr: 'Créez un devis pour un client sans l’application Fluxidi.',
  es: 'Cree un presupuesto para un cliente sin la app Fluxidi.',
);

const LocalizedText kLimousineExternalContactSection = LocalizedText(
  nl: 'Klant',
  en: 'Customer',
  fr: 'Client',
  es: 'Cliente',
);

const LocalizedText kLimousineExternalContactName = LocalizedText(
  nl: 'Naam',
  en: 'Name',
  fr: 'Nom',
  es: 'Nombre',
);

const LocalizedText kLimousineExternalContactEmail = LocalizedText(
  nl: 'E-mail',
  en: 'Email',
  fr: 'E-mail',
  es: 'Correo',
);

const LocalizedText kLimousineExternalContactMobile = LocalizedText(
  nl: 'Mobiel nummer',
  en: 'Mobile number',
  fr: 'Numéro de mobile',
  es: 'Número de móvil',
);

const LocalizedText kLimousineExternalContactLocale = LocalizedText(
  nl: 'Voorkeurstaal',
  en: 'Preferred language',
  fr: 'Langue préférée',
  es: 'Idioma preferido',
);

const LocalizedText kLimousineExternalContactCompany = LocalizedText(
  nl: 'Bedrijfsnaam (optioneel)',
  en: 'Company name (optional)',
  fr: 'Nom de l’entreprise (facultatif)',
  es: 'Nombre de empresa (opcional)',
);

const LocalizedText kLimousineExternalContactRequired = LocalizedText(
  nl: 'Vul een naam en e-mail of mobiel nummer in.',
  en: 'Enter a name and an email or mobile number.',
  fr: 'Saisissez un nom et un e-mail ou un numéro de mobile.',
  es: 'Introduzca un nombre y un correo o número de móvil.',
);

const LocalizedText kLimousineExternalCopyLink = LocalizedText(
  nl: 'Kopieer beveiligde link',
  en: 'Copy secure link',
  fr: 'Copier le lien sécurisé',
  es: 'Copiar enlace seguro',
);

const LocalizedText kLimousineExternalShareLink = LocalizedText(
  nl: 'Delen',
  en: 'Share',
  fr: 'Partager',
  es: 'Compartir',
);

const LocalizedText kLimousineExternalLinkCopied = LocalizedText(
  nl: 'Beveiligde link gekopieerd.',
  en: 'Secure link copied.',
  fr: 'Lien sécurisé copié.',
  es: 'Enlace seguro copiado.',
);

const LocalizedText kLimousineExternalTimelineTitle = LocalizedText(
  nl: 'Klantstatus',
  en: 'Customer status',
  fr: 'Statut client',
  es: 'Estado del cliente',
);

const LocalizedText kLimousineExternalBekeken = LocalizedText(
  nl: 'Bekeken',
  en: 'Opened',
  fr: 'Consulté',
  es: 'Visto',
);

const Map<String, LocalizedText> kLimousineExternalDeliveryLabels =
    <String, LocalizedText>{
      LimousineExternalDeliveryState.linkCreated: LocalizedText(
        nl: 'Link aangemaakt',
        en: 'Link created',
        fr: 'Lien créé',
        es: 'Enlace creado',
      ),
      LimousineExternalDeliveryState.invitationShared: LocalizedText(
        nl: 'Uitnodiging gedeeld',
        en: 'Invitation shared',
        fr: 'Invitation partagée',
        es: 'Invitación compartida',
      ),
      LimousineExternalDeliveryState.customerOpened: LocalizedText(
        nl: 'Bekeken',
        en: 'Opened',
        fr: 'Consulté',
        es: 'Visto',
      ),
      LimousineExternalDeliveryState.quotationAccepted: LocalizedText(
        nl: 'Offerte geaccepteerd',
        en: 'Quotation accepted',
        fr: 'Devis accepté',
        es: 'Presupuesto aceptado',
      ),
      LimousineExternalDeliveryState.bookingCreated: LocalizedText(
        nl: 'Boeking aangemaakt',
        en: 'Booking created',
        fr: 'Réservation créée',
        es: 'Reserva creada',
      ),
    };

String limousineExternalDeliveryLabel(String state, AppLanguage language) {
  final token = LimousineExternalDeliveryState.normalize(state);
  return (kLimousineExternalDeliveryLabels[token] ??
          kLimousineExternalTimelineTitle)
      .of(language);
}
