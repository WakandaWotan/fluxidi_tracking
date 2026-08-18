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
    };
