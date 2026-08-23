import '../app_strings.dart';
import 'limousine_accepted_booking.dart';

const LocalizedText kLimousineAcceptedBookingTitle = LocalizedText(
  nl: 'Boeking controleren',
  en: 'Review booking',
  fr: 'Vérifier la réservation',
  es: 'Revisar reserva',
);

const LocalizedText kLimousineAcceptedBookingConfirm = LocalizedText(
  nl: 'Ik bevestig deze boeking met de geaccepteerde prijs.',
  en: 'I confirm this booking at the accepted price.',
  fr: 'Je confirme cette réservation au prix accepté.',
  es: 'Confirmo esta reserva al precio aceptado.',
);

const LocalizedText kLimousineAcceptedBookingSubmit = LocalizedText(
  nl: 'Bevestig boeking',
  en: 'Confirm booking',
  fr: 'Confirmer la réservation',
  es: 'Confirmar reserva',
);

const LocalizedText kLimousineAcceptedBookingCreating = LocalizedText(
  nl: 'Boeking wordt aangemaakt…',
  en: 'Creating booking…',
  fr: 'Création de la réservation…',
  es: 'Creando la reserva…',
);

const LocalizedText kLimousineAcceptedBookingSuccess = LocalizedText(
  nl: 'Boeking bevestigd',
  en: 'Booking confirmed',
  fr: 'Réservation confirmée',
  es: 'Reserva confirmada',
);

const LocalizedText kLimousineAcceptedBookingReference = LocalizedText(
  nl: 'Boekingsreferentie',
  en: 'Booking reference',
  fr: 'Référence de réservation',
  es: 'Referencia de reserva',
);

const LocalizedText kLimousineAcceptedBookingOpenReview = LocalizedText(
  nl: 'Boeking afronden',
  en: 'Finish booking',
  fr: 'Finaliser la réservation',
  es: 'Finalizar reserva',
);

const LocalizedText kLimousineAcceptedBookingBackToQuote = LocalizedText(
  nl: 'Terug naar offerte',
  en: 'Return to quote',
  fr: 'Retour au devis',
  es: 'Volver al presupuesto',
);

const LocalizedText kLimousineAcceptedBookingBackToProfile = LocalizedText(
  nl: 'Terug naar profiel',
  en: 'Return to provider profile',
  fr: 'Retour au profil',
  es: 'Volver al perfil',
);

const LocalizedText kLimousineAcceptedBookingRetryable = LocalizedText(
  nl: 'De boeking is niet bevestigd. Probeer het later opnieuw.',
  en: 'The booking was not confirmed. Try again later.',
  fr: 'La réservation n’est pas confirmée. Réessayez plus tard.',
  es: 'La reserva no está confirmada. Inténtelo más tarde.',
);

const LocalizedText kLimousineAcceptedBookingProvider = LocalizedText(
  nl: 'Aanbieder',
  en: 'Provider',
  fr: 'Prestataire',
  es: 'Proveedor',
);

const LocalizedText kLimousineAcceptedBookingOffer = LocalizedText(
  nl: 'Aanbod',
  en: 'Offer',
  fr: 'Offre',
  es: 'Oferta',
);

const LocalizedText kLimousineAcceptedBookingClass = LocalizedText(
  nl: 'Serviceklasse',
  en: 'Service class',
  fr: 'Classe de service',
  es: 'Clase de servicio',
);

const LocalizedText kLimousineAcceptedBookingVehicle = LocalizedText(
  nl: 'Geselecteerd voertuig',
  en: 'Selected vehicle',
  fr: 'Véhicule sélectionné',
  es: 'Vehículo seleccionado',
);

const LocalizedText kLimousineAcceptedBookingPaymentTitle = LocalizedText(
  nl: 'Betaalmethode',
  en: 'Payment method',
  fr: 'Mode de paiement',
  es: 'Método de pago',
);

const LocalizedText kLimousineAcceptedBookingPaymentSubtitle = LocalizedText(
  nl: 'Kies hoe je deze rit wilt betalen.',
  en: 'Choose how you want to pay for this ride.',
  fr: 'Choisissez comment payer ce trajet.',
  es: 'Elige cómo quieres pagar este viaje.',
);

const LocalizedText kLimousineAcceptedBookingPaymentLoading = LocalizedText(
  nl: 'Betaalmogelijkheden van de aanbieder worden opgehaald…',
  en: 'Loading the provider’s payment options…',
  fr: 'Chargement des moyens de paiement du prestataire…',
  es: 'Cargando los métodos de pago del proveedor…',
);

const LocalizedText kLimousineAcceptedBookingPaymentRetry = LocalizedText(
  nl: 'Opnieuw proberen',
  en: 'Try again',
  fr: 'Réessayer',
  es: 'Intentar de nuevo',
);

const LocalizedText kLimousineAcceptedBookingBillingTitle = LocalizedText(
  nl: 'Factuurgegevens',
  en: 'Billing details',
  fr: 'Données de facturation',
  es: 'Datos de facturación',
);

const LocalizedText kLimousineAcceptedBookingBillingSubtitle = LocalizedText(
  nl:
      'Boek je privé, dan hoef je niets in te vullen. Heb je een '
      'bedrijfsfactuur nodig, vul dan de gegevens van je onderneming in.',
  en:
      'Booking privately needs nothing here. If you need a company invoice, '
      'fill in your business details.',
  fr:
      'Pour une réservation privée, rien à remplir. Si vous avez besoin '
      'd’une facture d’entreprise, indiquez les données de votre société.',
  es:
      'Si reservas como particular, no hace falta rellenar nada. Si necesitas '
      'una factura de empresa, introduce los datos de tu sociedad.',
);

/// Reassurance that asking for an invoice changes only the document, never the
/// accepted quote amount.
const LocalizedText kLimousineAcceptedBookingBillingPriceUnchanged =
    LocalizedText(
      nl: 'Het geaccepteerde totaalbedrag verandert hier niet door.',
      en: 'This does not change the accepted total.',
      fr: 'Cela ne modifie pas le montant total accepté.',
      es: 'Esto no cambia el total aceptado.',
    );

/// Shown when the server created the booking but the checkout page could not
/// be opened. The ride exists; only the payment still has to be finished.
const LocalizedText
kLimousineAcceptedBookingCheckoutUnavailable = LocalizedText(
  nl:
      'De boeking staat vast, maar de betaalpagina kon niet worden geopend. '
      'Tik op "Betaling hervatten" of rond de betaling af bij "Mijn boekingen".',
  en:
      'The booking is saved, but the payment page could not be opened. '
      'Tap "Resume payment" or finish it from "My bookings".',
  fr:
      'La réservation est enregistrée, mais la page de paiement n’a pas pu '
      's’ouvrir. Appuyez sur « Reprendre le paiement » ou finalisez-le dans '
      '« Mes réservations ».',
  es:
      'La reserva está guardada, pero no se pudo abrir la página de pago. '
      'Pulsa «Reanudar pago» o termínalo en «Mis reservas».',
);

const LocalizedText kLimousineAcceptedBookingResumeCheckout = LocalizedText(
  nl: 'Betaling hervatten',
  en: 'Resume payment',
  fr: 'Reprendre le paiement',
  es: 'Reanudar pago',
);

const Map<LimousineAcceptedBookingError, LocalizedText>
kLimousineAcceptedBookingErrors =
    <LimousineAcceptedBookingError, LocalizedText>{
      LimousineAcceptedBookingError.gateOff: LocalizedText(
        nl: 'Limousineboeking is momenteel niet beschikbaar.',
        en: 'Limousine booking is currently unavailable.',
        fr: 'La réservation limousine n’est pas disponible.',
        es: 'La reserva de limusina no está disponible.',
      ),
      LimousineAcceptedBookingError.missingAcceptanceReference: LocalizedText(
        nl: 'Er is geen geaccepteerde offerte om te boeken.',
        en: 'There is no accepted quote to book.',
        fr: 'Aucun devis accepté à réserver.',
        es: 'No hay presupuesto aceptado para reservar.',
      ),
      LimousineAcceptedBookingError.malformedAcceptanceReference: LocalizedText(
        nl: 'De acceptatiereferentie is ongeldig.',
        en: 'The acceptance reference is invalid.',
        fr: 'La référence d’acceptation est invalide.',
        es: 'La referencia de aceptación no es válida.',
      ),
      LimousineAcceptedBookingError.expiredAcceptanceReference: LocalizedText(
        nl: 'De acceptatie is verlopen. Vraag een nieuwe offerte.',
        en: 'The acceptance has expired. Request a new quote.',
        fr: 'L’acceptation a expiré. Demandez un nouveau devis.',
        es: 'La aceptación ha caducado. Solicite un nuevo presupuesto.',
      ),
      LimousineAcceptedBookingError.invalidAcceptanceReference: LocalizedText(
        nl: 'De acceptatie kan niet worden gebruikt.',
        en: 'The acceptance cannot be used.',
        fr: 'L’acceptation ne peut pas être utilisée.',
        es: 'La aceptación no se puede usar.',
      ),
      LimousineAcceptedBookingError.staleRevision: LocalizedText(
        nl: 'De offerte of voorwaarden zijn gewijzigd. Vernieuw eerst.',
        en: 'The quote or terms have changed. Refresh first.',
        fr: 'Le devis ou les conditions ont changé. Actualisez d’abord.',
        es: 'El presupuesto o las condiciones cambiaron. Actualice primero.',
      ),
      LimousineAcceptedBookingError.unauthorizedScope: LocalizedText(
        nl: 'Deze boeking hoort niet bij deze aanbieder.',
        en: 'This booking does not belong to this provider.',
        fr: 'Cette réservation n’appartient pas à ce prestataire.',
        es: 'Esta reserva no pertenece a este proveedor.',
      ),
      LimousineAcceptedBookingError.missingCustomerScope: LocalizedText(
        nl: 'Meld u aan om de boeking te bevestigen.',
        en: 'Sign in to confirm the booking.',
        fr: 'Connectez-vous pour confirmer la réservation.',
        es: 'Inicie sesión para confirmar la reserva.',
      ),
      LimousineAcceptedBookingError.providerUnavailable: LocalizedText(
        nl: 'Deze aanbieder neemt momenteel geen nieuwe boekingen aan.',
        en: 'This provider is not accepting new bookings.',
        fr: 'Ce prestataire n’accepte pas de nouvelles réservations.',
        es: 'Este proveedor no acepta nuevas reservas.',
      ),
      LimousineAcceptedBookingError.bookDisabled: LocalizedText(
        nl: 'Limousineboeking is tijdelijk uitgeschakeld.',
        en: 'Limousine booking is temporarily disabled.',
        fr: 'La réservation limousine est temporairement désactivée.',
        es: 'La reserva de limusina está temporalmente desactivada.',
      ),
      LimousineAcceptedBookingError.unknownResponse: LocalizedText(
        nl: 'De boeking is niet bevestigd.',
        en: 'The booking was not confirmed.',
        fr: 'La réservation n’est pas confirmée.',
        es: 'La reserva no está confirmada.',
      ),
      LimousineAcceptedBookingError.ambiguousTimeout: LocalizedText(
        nl: 'De status is onduidelijk. We dienen de boeking niet opnieuw in.',
        en: 'The status is unclear. The booking was not submitted again.',
        fr: 'Le statut est incertain. La réservation n’a pas été renvoyée.',
        es: 'El estado no es claro. No se reenvió la reserva.',
      ),
      LimousineAcceptedBookingError.network: LocalizedText(
        nl: 'De boeking kon niet worden verzonden. Probeer opnieuw.',
        en: 'The booking could not be sent. Try again.',
        fr: 'La réservation n’a pas pu être envoyée. Réessayez.',
        es: 'No se pudo enviar la reserva. Inténtelo de nuevo.',
      ),
      LimousineAcceptedBookingError.paymentCapabilityUnavailable: LocalizedText(
        nl:
            'De betaalmogelijkheden van deze aanbieder konden niet worden '
            'opgehaald. Probeer opnieuw.',
        en:
            'The payment options of this provider could not be loaded. '
            'Try again.',
        fr:
            'Les moyens de paiement de ce prestataire n’ont pas pu être '
            'chargés. Réessayez.',
        es:
            'No se pudieron cargar los métodos de pago de este proveedor. '
            'Inténtelo de nuevo.',
      ),
      LimousineAcceptedBookingError.paymentMethodRequired: LocalizedText(
        nl: 'Kies eerst een betaalmethode.',
        en: 'Choose a payment method first.',
        fr: 'Choisissez d’abord un mode de paiement.',
        es: 'Elija primero un método de pago.',
      ),
      LimousineAcceptedBookingError.paymentMethodUnavailable: LocalizedText(
        nl:
            'Deze betaalmethode wordt niet meer aangeboden. Kies een andere '
            'methode.',
        en: 'This payment method is no longer offered. Choose another method.',
        fr: 'Ce mode de paiement n’est plus proposé. Choisissez-en un autre.',
        es: 'Este método de pago ya no está disponible. Elija otro método.',
      ),
      LimousineAcceptedBookingError.billingIdentityIncomplete: LocalizedText(
        nl:
            'De factuurgegevens zijn nog niet compleet. Vul bedrijfsnaam, '
            'btw- of ondernemingsnummer en het volledige factuuradres in.',
        en:
            'The billing details are not complete yet. Fill in the company '
            'name, a VAT or company registration number and the full billing '
            'address.',
        fr:
            'Les données de facturation sont incomplètes. Indiquez le nom de '
            'l’entreprise, un numéro de TVA ou d’entreprise et l’adresse de '
            'facturation complète.',
        es:
            'Los datos de facturación aún no están completos. Introduzca el '
            'nombre de la empresa, un número de IVA o de registro y la '
            'dirección de facturación completa.',
      ),
      LimousineAcceptedBookingError.billingIdentityRejected: LocalizedText(
        nl:
            'De factuurgegevens werden niet aanvaard. Controleer de '
            'bedrijfsnaam, het btw-nummer en het factuuradres.',
        en:
            'The billing details were not accepted. Check the company name, '
            'the VAT number and the billing address.',
        fr:
            'Les données de facturation ont été refusées. Vérifiez le nom de '
            'l’entreprise, le numéro de TVA et l’adresse de facturation.',
        es:
            'Los datos de facturación no se aceptaron. Compruebe el nombre de '
            'la empresa, el número de IVA y la dirección de facturación.',
      ),
    };
