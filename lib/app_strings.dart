enum AppLanguage { nl, en, fr, es }

class LocalizedText {
  final String nl;
  final String en;
  final String fr;
  final String es;

  const LocalizedText({
    required this.nl,
    required this.en,
    required this.fr,
    required this.es,
  });

  String of(AppLanguage lang) {
    switch (lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
    }
  }
}

class AppStrings {
  final LocalizedText calculatorTitle;
  final LocalizedText calculatorQuoteTitle;
  final LocalizedText bookingsTitle;
  final LocalizedText liveRideTitle;
  final LocalizedText activeRideTitle;
  final LocalizedText refreshBookingsLabel;
  final LocalizedText centerOnMeLabel;
  final LocalizedText drawerDriverIdLabel;
  final LocalizedText drawerWorkerLabel;
  final LocalizedText drawerMapboxTokenLabel;
  final LocalizedText drawerLanguageLabel;
  final LocalizedText drawerBusinessSettingsLabel;
  final LocalizedText drawerBusinessSettingsSubtitle;
  final LocalizedText drawerVehiclesLabel;
  final LocalizedText drawerVehiclesSubtitle;
  final LocalizedText followCarLabel;
  final LocalizedText followCarSubtitle;
  final LocalizedText bookingsMenuSubtitle;
  final LocalizedText liveRideMenuSubtitle;
  final LocalizedText calculatorMenuSubtitle;
  final LocalizedText activeRideMenuSubtitle;
  final LocalizedText availableBookingsTitle;
  final LocalizedText refreshShortLabel;
  final LocalizedText bookingsEmptyLabel;
  final LocalizedText stopShortLabel;
  final LocalizedText rideActionCompletedLabel;
  final LocalizedText rideActionCancelledLabel;
  final LocalizedText rideGoToRideLabel;
  final LocalizedText rideDeleteLabel;
  final LocalizedText rideStatusPendingLabel;
  final LocalizedText pickupLabel;
  final LocalizedText dropoffLabel;
  final LocalizedText calculatorFromLabel;
  final LocalizedText calculatorToLabel;
  final LocalizedText calculatorBagsLabel;
  final LocalizedText calculatorPassengersLabel;
  final LocalizedText calculatorPickupTimeLabel;
  final LocalizedText calculatorServiceLabel;
  final LocalizedText calculatorTierLabel;
  final LocalizedText calculatorReturnLabel;
  final LocalizedText calculatorWaitTimeLabel;
  final LocalizedText calculatorBreakdownTitle;
  final LocalizedText calculatorButtonLabel;
  final LocalizedText calculatorButtonBusyLabel;
  final LocalizedText calculatorBookNowLabel;
  final LocalizedText bookingConfirmationTitle;
  final LocalizedText bookingFinalActionPlaceholderLabel;
  final LocalizedText bookingSummaryRouteLabel;
  final LocalizedText bookingSummaryServiceTierLabel;
  final LocalizedText bookingSummaryPassengersBagsLabel;
  final LocalizedText bookingSummaryQuoteLabel;
  final LocalizedText bookingSummaryPickupLabel;
  final LocalizedText bookingSummaryWaitTimeLabel;
  final LocalizedText bookingSummaryReturnLabel;
  final LocalizedText bookingSummaryExtraServiceLabel;
  final LocalizedText bookingCustomerSectionTitle;
  final LocalizedText bookingFullNameLabel;
  final LocalizedText bookingPhoneLabel;
  final LocalizedText bookingEmailLabel;
  final LocalizedText bookingCompanyNameOptionalLabel;
  final LocalizedText bookingVatNumberOptionalLabel;
  final LocalizedText bookingVatNumberHelpText;
  final LocalizedText bookingMessageOptionalLabel;
  final LocalizedText bookingConfirmButtonLabel;
  final LocalizedText bookingSubmitPlaceholderMessage;
  final LocalizedText bookingRequiredFieldsError;
  final LocalizedText bookingSubmittingLabel;
  final LocalizedText bookingSubmitFailedPrefix;
  final LocalizedText bookingSuccessReferencePrefix;
  final LocalizedText bookingSuccessCashMessage;
  final LocalizedText bookingSuccessPaymentRequiredMessage;
  final LocalizedText bookingSuccessPaidConfirmedMessage;
  final LocalizedText bookingPaymentSuccessTitle;
  final LocalizedText bookingPaymentRequiredMessage;
  final LocalizedText bookingPayNowLabel;
  final LocalizedText bookingCopyPaymentLinkLabel;
  final LocalizedText bookingCloseLabel;
  final LocalizedText bookingPaymentLinkCopiedMessage;
  final LocalizedText bookingPaymentOpenFailedCopiedMessage;
  final LocalizedText commonYesLabel;
  final LocalizedText commonNoLabel;
  final LocalizedText calculatorExtraServiceOptionalLabel;
  final LocalizedText calculatorReturnSubtitle;
  final LocalizedText calculatorVatRateLabel;
  final LocalizedText calculatorAddressHint;
  final LocalizedText calculatorUseCurrentLocationTooltip;
  final LocalizedText calculatorSuggestionTapHint;
  final LocalizedText calculatorChoosePickupTimeLabel;
  final LocalizedText calculatorWaitStepHint;
  final LocalizedText calculatorQuoteTipText;
  final LocalizedText calculatorPriceInclVatLabel;
  final LocalizedText calculatorPriceExVatLabel;
  final LocalizedText calculatorVatLabel;
  final LocalizedText calculatorDistanceLabel;
  final LocalizedText calculatorDurationLabel;
  final LocalizedText calculatorErrorPrefix;
  final LocalizedText calculatorFillFromToError;
  final LocalizedText calculatorLocationServiceOffError;
  final LocalizedText calculatorNoLocationPermissionError;
  final LocalizedText calculatorCurrentLocationFailedError;
  final LocalizedText calculatorCurrentLocationFallbackLabel;
  final LocalizedText calculatorMaxBagsHint;
  final LocalizedText calculatorMaxPassengersHint;
  final LocalizedText breakdownStartFeeEx;
  final LocalizedText breakdownPerKmEx;
  final LocalizedText breakdownPerMinEx;
  final LocalizedText breakdownDistanceKm;
  final LocalizedText breakdownDurationMin;
  final LocalizedText breakdownBaseDriveEx;
  final LocalizedText breakdownExtraStopsEx;
  final LocalizedText breakdownWaitingEx;
  final LocalizedText breakdownSurchargeRate;
  final LocalizedText breakdownSurchargeBaseEx;
  final LocalizedText breakdownSurchargeAmountEx;
  final LocalizedText breakdownBagsEx;
  final LocalizedText breakdownTier;
  final LocalizedText breakdownTierFeeEx;
  final LocalizedText breakdownTotalEx;
  final LocalizedText breakdownVatRate;
  final LocalizedText breakdownVatAmount;
  final LocalizedText breakdownTotalIncl;

  const AppStrings({
    required this.calculatorTitle,
    required this.calculatorQuoteTitle,
    required this.bookingsTitle,
    required this.liveRideTitle,
    required this.activeRideTitle,
    required this.refreshBookingsLabel,
    required this.centerOnMeLabel,
    required this.drawerDriverIdLabel,
    required this.drawerWorkerLabel,
    required this.drawerMapboxTokenLabel,
    required this.drawerLanguageLabel,
    required this.drawerBusinessSettingsLabel,
    required this.drawerBusinessSettingsSubtitle,
    required this.drawerVehiclesLabel,
    required this.drawerVehiclesSubtitle,
    required this.followCarLabel,
    required this.followCarSubtitle,
    required this.bookingsMenuSubtitle,
    required this.liveRideMenuSubtitle,
    required this.calculatorMenuSubtitle,
    required this.activeRideMenuSubtitle,
    required this.availableBookingsTitle,
    required this.refreshShortLabel,
    required this.bookingsEmptyLabel,
    required this.stopShortLabel,
    required this.rideActionCompletedLabel,
    required this.rideActionCancelledLabel,
    required this.rideGoToRideLabel,
    required this.rideDeleteLabel,
    required this.rideStatusPendingLabel,
    required this.pickupLabel,
    required this.dropoffLabel,
    required this.calculatorFromLabel,
    required this.calculatorToLabel,
    required this.calculatorBagsLabel,
    required this.calculatorPassengersLabel,
    required this.calculatorPickupTimeLabel,
    required this.calculatorServiceLabel,
    required this.calculatorTierLabel,
    required this.calculatorReturnLabel,
    required this.calculatorWaitTimeLabel,
    required this.calculatorBreakdownTitle,
    required this.calculatorButtonLabel,
    required this.calculatorButtonBusyLabel,
    required this.calculatorBookNowLabel,
    required this.bookingConfirmationTitle,
    required this.bookingFinalActionPlaceholderLabel,
    required this.bookingSummaryRouteLabel,
    required this.bookingSummaryServiceTierLabel,
    required this.bookingSummaryPassengersBagsLabel,
    required this.bookingSummaryQuoteLabel,
    required this.bookingSummaryPickupLabel,
    required this.bookingSummaryWaitTimeLabel,
    required this.bookingSummaryReturnLabel,
    required this.bookingSummaryExtraServiceLabel,
    required this.bookingCustomerSectionTitle,
    required this.bookingFullNameLabel,
    required this.bookingPhoneLabel,
    required this.bookingEmailLabel,
    required this.bookingCompanyNameOptionalLabel,
    required this.bookingVatNumberOptionalLabel,
    required this.bookingVatNumberHelpText,
    required this.bookingMessageOptionalLabel,
    required this.bookingConfirmButtonLabel,
    required this.bookingSubmitPlaceholderMessage,
    required this.bookingRequiredFieldsError,
    required this.bookingSubmittingLabel,
    required this.bookingSubmitFailedPrefix,
    required this.bookingSuccessReferencePrefix,
    required this.bookingSuccessCashMessage,
    required this.bookingSuccessPaymentRequiredMessage,
    required this.bookingSuccessPaidConfirmedMessage,
    required this.bookingPaymentSuccessTitle,
    required this.bookingPaymentRequiredMessage,
    required this.bookingPayNowLabel,
    required this.bookingCopyPaymentLinkLabel,
    required this.bookingCloseLabel,
    required this.bookingPaymentLinkCopiedMessage,
    required this.bookingPaymentOpenFailedCopiedMessage,
    required this.commonYesLabel,
    required this.commonNoLabel,
    required this.calculatorExtraServiceOptionalLabel,
    required this.calculatorReturnSubtitle,
    required this.calculatorVatRateLabel,
    required this.calculatorAddressHint,
    required this.calculatorUseCurrentLocationTooltip,
    required this.calculatorSuggestionTapHint,
    required this.calculatorChoosePickupTimeLabel,
    required this.calculatorWaitStepHint,
    required this.calculatorQuoteTipText,
    required this.calculatorPriceInclVatLabel,
    required this.calculatorPriceExVatLabel,
    required this.calculatorVatLabel,
    required this.calculatorDistanceLabel,
    required this.calculatorDurationLabel,
    required this.calculatorErrorPrefix,
    required this.calculatorFillFromToError,
    required this.calculatorLocationServiceOffError,
    required this.calculatorNoLocationPermissionError,
    required this.calculatorCurrentLocationFailedError,
    required this.calculatorCurrentLocationFallbackLabel,
    required this.calculatorMaxBagsHint,
    required this.calculatorMaxPassengersHint,
    required this.breakdownStartFeeEx,
    required this.breakdownPerKmEx,
    required this.breakdownPerMinEx,
    required this.breakdownDistanceKm,
    required this.breakdownDurationMin,
    required this.breakdownBaseDriveEx,
    required this.breakdownExtraStopsEx,
    required this.breakdownWaitingEx,
    required this.breakdownSurchargeRate,
    required this.breakdownSurchargeBaseEx,
    required this.breakdownSurchargeAmountEx,
    required this.breakdownBagsEx,
    required this.breakdownTier,
    required this.breakdownTierFeeEx,
    required this.breakdownTotalEx,
    required this.breakdownVatRate,
    required this.breakdownVatAmount,
    required this.breakdownTotalIncl,
  });

  static AppStrings forLanguage(AppLanguage language) {
    switch (language) {
      case AppLanguage.nl:
        return _nl;
      case AppLanguage.en:
        return _en;
      case AppLanguage.fr:
        return _fr;
      case AppLanguage.es:
        return _es;
    }
  }

  String breakdownLabel(String key, AppLanguage language) {
    final map = <String, LocalizedText>{
      'start_fee_ex': breakdownStartFeeEx,
      'per_km_ex': breakdownPerKmEx,
      'per_min_ex': breakdownPerMinEx,
      'distance_km': breakdownDistanceKm,
      'duration_min': breakdownDurationMin,
      'base_drive_ex': breakdownBaseDriveEx,
      'extra_stops_ex': breakdownExtraStopsEx,
      'waiting_ex': breakdownWaitingEx,
      'surcharge_rate': breakdownSurchargeRate,
      'surcharge_base_ex': breakdownSurchargeBaseEx,
      'surcharge_amount_ex': breakdownSurchargeAmountEx,
      'bags_ex': breakdownBagsEx,
      'tier': breakdownTier,
      'tier_fee_ex': breakdownTierFeeEx,
      'total_ex': breakdownTotalEx,
      'vat_rate': breakdownVatRate,
      'vat_amount': breakdownVatAmount,
      'total_incl': breakdownTotalIncl,
    };
    final hit = map[key];
    return (hit == null) ? key : hit.of(language);
  }
}

const AppStrings _nl = AppStrings(
  calculatorTitle: LocalizedText(
    nl: 'Calculator',
    en: 'Calculator',
    fr: 'Calculateur',
    es: 'Calculadora',
  ),
  calculatorQuoteTitle: LocalizedText(
    nl: 'Jouw ritprijs',
    en: 'Your ride price',
    fr: 'Prix de votre trajet',
    es: 'Precio de tu viaje',
  ),
  bookingsTitle: LocalizedText(
    nl: 'Ritten',
    en: 'Bookings',
    fr: 'Courses',
    es: 'Reservas',
  ),
  liveRideTitle: LocalizedText(
    nl: 'Live rit',
    en: 'Live ride',
    fr: 'Course en direct',
    es: 'Viaje en vivo',
  ),
  activeRideTitle: LocalizedText(
    nl: 'Actieve rit',
    en: 'Active ride',
    fr: 'Course active',
    es: 'Viaje activo',
  ),
  refreshBookingsLabel: LocalizedText(
    nl: 'Vernieuw ritten',
    en: 'Refresh bookings',
    fr: 'Rafraichir les courses',
    es: 'Actualizar reservas',
  ),
  centerOnMeLabel: LocalizedText(
    nl: 'Centreer op mij',
    en: 'Center on me',
    fr: 'Centrer sur moi',
    es: 'Centrar en mi',
  ),
  drawerDriverIdLabel: LocalizedText(
    nl: 'Driver ID',
    en: 'Driver ID',
    fr: 'ID chauffeur',
    es: 'ID conductor',
  ),
  drawerWorkerLabel: LocalizedText(
    nl: 'Worker',
    en: 'Worker',
    fr: 'Worker',
    es: 'Worker',
  ),
  drawerMapboxTokenLabel: LocalizedText(
    nl: 'Mapbox REST token',
    en: 'Mapbox REST token',
    fr: 'Token REST Mapbox',
    es: 'Token REST Mapbox',
  ),
  drawerLanguageLabel: LocalizedText(
    nl: 'Taal',
    en: 'Language',
    fr: 'Langue',
    es: 'Idioma',
  ),
  drawerBusinessSettingsLabel: LocalizedText(
    nl: 'Bedrijfsinstellingen',
    en: 'Business settings',
    fr: 'Parametres entreprise',
    es: 'Configuracion de empresa',
  ),
  drawerBusinessSettingsSubtitle: LocalizedText(
    nl: 'Profiel, branding en defaults',
    en: 'Profile, branding and defaults',
    fr: 'Profil, branding et defaults',
    es: 'Perfil, marca y valores',
  ),
  drawerVehiclesLabel: LocalizedText(
    nl: 'Voertuigen',
    en: 'Vehicles',
    fr: 'Vehicules',
    es: 'Vehiculos',
  ),
  drawerVehiclesSubtitle: LocalizedText(
    nl: 'Beheer wagenpark',
    en: 'Manage fleet',
    fr: 'Gerer la flotte',
    es: 'Gestionar flota',
  ),
  followCarLabel: LocalizedText(
    nl: 'Auto volgen',
    en: 'Follow car',
    fr: 'Suivre la voiture',
    es: 'Seguir coche',
  ),
  followCarSubtitle: LocalizedText(
    nl: 'Tesla-stijl camera tijdens rijden',
    en: 'Tesla-style camera in driving mode',
    fr: 'Camera style Tesla en conduite',
    es: 'Camara estilo Tesla en conduccion',
  ),
  bookingsMenuSubtitle: LocalizedText(
    nl: 'Bekijk & beheer ritten',
    en: 'View and manage rides',
    fr: 'Voir et gerer les courses',
    es: 'Ver y gestionar viajes',
  ),
  liveRideMenuSubtitle: LocalizedText(
    nl: 'Start een rit (A → B)',
    en: 'Start a ride (A → B)',
    fr: 'Demarrer une course (A → B)',
    es: 'Iniciar viaje (A → B)',
  ),
  calculatorMenuSubtitle: LocalizedText(
    nl: 'Prijsberekening',
    en: 'Price estimate',
    fr: 'Estimation du prix',
    es: 'Estimacion de precio',
  ),
  activeRideMenuSubtitle: LocalizedText(
    nl: 'Cockpit',
    en: 'Cockpit',
    fr: 'Cockpit',
    es: 'Cabina',
  ),
  availableBookingsTitle: LocalizedText(
    nl: 'Beschikbare ritten',
    en: 'Available bookings',
    fr: 'Courses disponibles',
    es: 'Reservas disponibles',
  ),
  refreshShortLabel: LocalizedText(
    nl: 'Vernieuw',
    en: 'Refresh',
    fr: 'Rafraichir',
    es: 'Actualizar',
  ),
  bookingsEmptyLabel: LocalizedText(
    nl: 'Geen ritten gevonden.',
    en: 'No bookings found.',
    fr: 'Aucune course trouvee.',
    es: 'No se encontraron reservas.',
  ),
  stopShortLabel: LocalizedText(
    nl: 'Stop',
    en: 'Stop',
    fr: 'Arreter',
    es: 'Detener',
  ),
  rideActionCompletedLabel: LocalizedText(
    nl: 'Voltooid',
    en: 'Completed',
    fr: 'Terminée',
    es: 'Completado',
  ),
  rideActionCancelledLabel: LocalizedText(
    nl: 'Geannuleerd',
    en: 'Cancelled',
    fr: 'Annulée',
    es: 'Cancelado',
  ),
  rideGoToRideLabel: LocalizedText(
    nl: 'Ga naar rit',
    en: 'Go to ride',
    fr: 'Aller au trajet',
    es: 'Ir al viaje',
  ),
  rideDeleteLabel: LocalizedText(
    nl: 'Verwijderen',
    en: 'Delete',
    fr: 'Supprimer',
    es: 'Eliminar',
  ),
  rideStatusPendingLabel: LocalizedText(
    nl: 'In afwachting',
    en: 'Pending',
    fr: 'En attente',
    es: 'Pendiente',
  ),
  pickupLabel: LocalizedText(
    nl: 'Ophaalpunt',
    en: 'Pickup',
    fr: 'Prise en charge',
    es: 'Recogida',
  ),
  dropoffLabel: LocalizedText(
    nl: 'Bestemming',
    en: 'Dropoff',
    fr: 'Dépose',
    es: 'Destino',
  ),
  calculatorFromLabel: LocalizedText(
    nl: 'VAN',
    en: 'FROM',
    fr: 'DEPART',
    es: 'ORIGEN',
  ),
  calculatorToLabel: LocalizedText(
    nl: 'NAAR',
    en: 'TO',
    fr: 'ARRIVEE',
    es: 'DESTINO',
  ),
  calculatorBagsLabel: LocalizedText(
    nl: 'Bagage',
    en: 'Luggage',
    fr: 'Bagages',
    es: 'Equipaje',
  ),
  calculatorPassengersLabel: LocalizedText(
    nl: 'Passagiers',
    en: 'Passengers',
    fr: 'Passagers',
    es: 'Pasajeros',
  ),
  calculatorPickupTimeLabel: LocalizedText(
    nl: 'Ophaaltijd',
    en: 'Pickup time',
    fr: 'Heure de prise en charge',
    es: 'Hora de recogida',
  ),
  calculatorServiceLabel: LocalizedText(
    nl: 'Service',
    en: 'Service',
    fr: 'Service',
    es: 'Servicio',
  ),
  calculatorTierLabel: LocalizedText(
    nl: 'Tier',
    en: 'Tier',
    fr: 'Categorie',
    es: 'Categoria',
  ),
  calculatorReturnLabel: LocalizedText(
    nl: 'Retour',
    en: 'Return',
    fr: 'Retour',
    es: 'Vuelta',
  ),
  calculatorWaitTimeLabel: LocalizedText(
    nl: 'Wachttijd (min)',
    en: 'Waiting time (min)',
    fr: 'Temps d attente (min)',
    es: 'Tiempo de espera (min)',
  ),
  calculatorBreakdownTitle: LocalizedText(
    nl: 'Overzicht',
    en: 'Breakdown',
    fr: 'Detail',
    es: 'Desglose',
  ),
  calculatorButtonLabel: LocalizedText(
    nl: 'Bereken mijn ritprijs',
    en: 'Calculate my ride price',
    fr: 'Calculer mon prix de trajet',
    es: 'Calcular el precio de mi viaje',
  ),
  calculatorButtonBusyLabel: LocalizedText(
    nl: 'Berekenen…',
    en: 'Calculating…',
    fr: 'Calcul…',
    es: 'Calculando…',
  ),
  calculatorBookNowLabel: LocalizedText(
    nl: 'Boek nu',
    en: 'Book now',
    fr: 'Reserver maintenant',
    es: 'Reservar ahora',
  ),
  bookingConfirmationTitle: LocalizedText(
    nl: 'Boekingsbevestiging',
    en: 'Booking confirmation',
    fr: 'Confirmation de reservation',
    es: 'Confirmacion de reserva',
  ),
  bookingFinalActionPlaceholderLabel: LocalizedText(
    nl: 'Bevestig boeking (binnenkort)',
    en: 'Confirm booking (coming soon)',
    fr: 'Confirmer la reservation (bientot)',
    es: 'Confirmar reserva (proximamente)',
  ),
  bookingSummaryRouteLabel: LocalizedText(
    nl: 'Route',
    en: 'Route',
    fr: 'Trajet',
    es: 'Ruta',
  ),
  bookingSummaryServiceTierLabel: LocalizedText(
    nl: 'Service en klasse',
    en: 'Service and tier',
    fr: 'Service et categorie',
    es: 'Servicio y categoria',
  ),
  bookingSummaryPassengersBagsLabel: LocalizedText(
    nl: 'Passagiers en bagage',
    en: 'Passengers and luggage',
    fr: 'Passagers et bagages',
    es: 'Pasajeros y equipaje',
  ),
  bookingSummaryQuoteLabel: LocalizedText(
    nl: 'Offerte',
    en: 'Quote',
    fr: 'Devis',
    es: 'Cotizacion',
  ),
  bookingSummaryPickupLabel: LocalizedText(
    nl: 'Ophaalmoment',
    en: 'Pickup date/time',
    fr: 'Date/heure de prise en charge',
    es: 'Fecha/hora de recogida',
  ),
  bookingSummaryWaitTimeLabel: LocalizedText(
    nl: 'Wachttijd',
    en: 'Waiting time',
    fr: 'Temps d attente',
    es: 'Tiempo de espera',
  ),
  bookingSummaryReturnLabel: LocalizedText(
    nl: 'Retour',
    en: 'Return',
    fr: 'Retour',
    es: 'Vuelta',
  ),
  bookingSummaryExtraServiceLabel: LocalizedText(
    nl: 'Extra service',
    en: 'Extra service',
    fr: 'Service supplementaire',
    es: 'Servicio extra',
  ),
  bookingCustomerSectionTitle: LocalizedText(
    nl: 'Klantgegevens',
    en: 'Customer details',
    fr: 'Coordonnees client',
    es: 'Datos del cliente',
  ),
  bookingFullNameLabel: LocalizedText(
    nl: 'Volledige naam',
    en: 'Full name',
    fr: 'Nom complet',
    es: 'Nombre completo',
  ),
  bookingPhoneLabel: LocalizedText(
    nl: 'Telefoonnummer',
    en: 'Phone number',
    fr: 'Numero de telephone',
    es: 'Numero de telefono',
  ),
  bookingEmailLabel: LocalizedText(
    nl: 'E-mailadres',
    en: 'Email address',
    fr: 'Adresse e-mail',
    es: 'Correo electronico',
  ),
  bookingCompanyNameOptionalLabel: LocalizedText(
    nl: 'Bedrijfsnaam (optioneel)',
    en: 'Company name (optional)',
    fr: 'Nom de l’entreprise (optionnel)',
    es: 'Nombre de empresa (opcional)',
  ),
  bookingVatNumberOptionalLabel: LocalizedText(
    nl: 'BTW-nummer (optioneel)',
    en: 'VAT number (optional)',
    fr: 'Numéro de TVA (optionnel)',
    es: 'Número de IVA (opcional)',
  ),
  bookingVatNumberHelpText: LocalizedText(
    nl: 'Vul je BTW-nummer in voor zakelijke facturatie.',
    en: 'Enter your VAT number for business invoicing.',
    fr: 'Saisissez votre numéro de TVA pour la facturation professionnelle.',
    es: 'Introduce tu número de IVA para facturación empresarial.',
  ),
  bookingMessageOptionalLabel: LocalizedText(
    nl: 'Bericht (optioneel)',
    en: 'Message (optional)',
    fr: 'Message (optionnel)',
    es: 'Mensaje (opcional)',
  ),
  bookingConfirmButtonLabel: LocalizedText(
    nl: 'Bevestig boeking',
    en: 'Confirm booking',
    fr: 'Confirmer la reservation',
    es: 'Confirmar reserva',
  ),
  bookingSubmitPlaceholderMessage: LocalizedText(
    nl: 'Boeking is klaar om te versturen zodra de app-booking API is gekoppeld.',
    en: 'Booking is ready to submit once app booking API is connected.',
    fr: 'La reservation est prete a etre envoyee des que l API de reservation app est connectee.',
    es: 'La reserva esta lista para enviar cuando se conecte la API de reservas de la app.',
  ),
  bookingRequiredFieldsError: LocalizedText(
    nl: 'Vul naam, telefoon en e-mail in.',
    en: 'Please fill in name, phone, and email.',
    fr: 'Veuillez remplir le nom, le telephone et l e-mail.',
    es: 'Por favor completa nombre, telefono y correo.',
  ),
  bookingSubmittingLabel: LocalizedText(
    nl: 'Boeking wordt aangemaakt…',
    en: 'Creating booking…',
    fr: 'Creation de la reservation…',
    es: 'Creando reserva…',
  ),
  bookingSubmitFailedPrefix: LocalizedText(
    nl: 'Boeking mislukt',
    en: 'Booking failed',
    fr: 'Echec de la reservation',
    es: 'La reserva fallo',
  ),
  bookingSuccessReferencePrefix: LocalizedText(
    nl: 'Referentie',
    en: 'Reference',
    fr: 'Reference',
    es: 'Referencia',
  ),
  bookingSuccessCashMessage: LocalizedText(
    nl: 'Boeking bevestigd. Betaling gebeurt in de auto.',
    en: 'Booking confirmed. Payment happens in the car.',
    fr: 'Reservation confirmee. Le paiement se fait dans la voiture.',
    es: 'Reserva confirmada. El pago se realiza en el coche.',
  ),
  bookingSuccessPaymentRequiredMessage: LocalizedText(
    nl: 'Bijna klaar. Rond de betaling af om je rit definitief te bevestigen.',
    en: 'Almost done. Complete payment to confirm your ride.',
    fr: 'Presque termine. Finalisez le paiement pour confirmer votre course.',
    es: 'Casi listo. Completa el pago para confirmar tu viaje.',
  ),
  bookingSuccessPaidConfirmedMessage: LocalizedText(
    nl: 'Boeking bevestigd. Je rit is betaald en succesvol vastgelegd.',
    en: 'Booking confirmed. Your ride is paid and successfully secured.',
    fr: 'Reservation confirmee. Votre course est payee et enregistree avec succes.',
    es: 'Reserva confirmada. Tu viaje esta pagado y registrado correctamente.',
  ),
  bookingPaymentSuccessTitle: LocalizedText(
    nl: 'Betaling gestart',
    en: 'Payment started',
    fr: 'Paiement demarre',
    es: 'Pago iniciado',
  ),
  bookingPaymentRequiredMessage: LocalizedText(
    nl: 'Je betaling is gestart. Je rit wordt pas bevestigd nadat de betaling is voltooid.',
    en: 'Your payment has started. Your ride is only confirmed after payment completes.',
    fr: 'Votre paiement a commence. Votre course est confirmee uniquement apres la finalisation du paiement.',
    es: 'Tu pago se ha iniciado. Tu viaje solo se confirma cuando el pago se completa.',
  ),
  bookingPayNowLabel: LocalizedText(
    nl: 'Betaal nu',
    en: 'Pay now',
    fr: 'Payer maintenant',
    es: 'Pagar ahora',
  ),
  bookingCopyPaymentLinkLabel: LocalizedText(
    nl: 'Kopieer betaallink',
    en: 'Copy payment link',
    fr: 'Copier le lien de paiement',
    es: 'Copiar enlace de pago',
  ),
  bookingCloseLabel: LocalizedText(
    nl: 'Sluiten',
    en: 'Close',
    fr: 'Fermer',
    es: 'Cerrar',
  ),
  bookingPaymentLinkCopiedMessage: LocalizedText(
    nl: 'Betaallink gekopieerd.',
    en: 'Payment link copied.',
    fr: 'Lien de paiement copie.',
    es: 'Enlace de pago copiado.',
  ),
  bookingPaymentOpenFailedCopiedMessage: LocalizedText(
    nl: 'Kon betaallink niet openen. Link gekopieerd.',
    en: 'Could not open payment link. Link copied.',
    fr: 'Impossible d ouvrir le lien de paiement. Lien copie.',
    es: 'No se pudo abrir el enlace de pago. Enlace copiado.',
  ),
  commonYesLabel: LocalizedText(nl: 'Ja', en: 'Yes', fr: 'Oui', es: 'Si'),
  commonNoLabel: LocalizedText(nl: 'Nee', en: 'No', fr: 'Non', es: 'No'),
  calculatorExtraServiceOptionalLabel: LocalizedText(
    nl: 'Extra service (optioneel)',
    en: 'Extra service (optional)',
    fr: 'Service supplementaire (optionnel)',
    es: 'Servicio extra (opcional)',
  ),
  calculatorReturnSubtitle: LocalizedText(
    nl: 'Heen + terug',
    en: 'Outbound + return',
    fr: 'Aller + retour',
    es: 'Ida + vuelta',
  ),
  calculatorVatRateLabel: LocalizedText(
    nl: 'Belastingtarief',
    en: 'Tax rate',
    fr: 'Taux de taxe',
    es: 'Tasa de impuesto',
  ),
  calculatorAddressHint: LocalizedText(
    nl: 'Typ een adres…',
    en: 'Type an address…',
    fr: 'Saisissez une adresse…',
    es: 'Escribe una direccion…',
  ),
  calculatorUseCurrentLocationTooltip: LocalizedText(
    nl: 'Gebruik mijn huidige locatie',
    en: 'Use my current location',
    fr: 'Utiliser ma position actuelle',
    es: 'Usar mi ubicacion actual',
  ),
  calculatorSuggestionTapHint: LocalizedText(
    nl: 'Tik om te selecteren',
    en: 'Tap to select',
    fr: 'Touchez pour selectionner',
    es: 'Pulsa para seleccionar',
  ),
  calculatorChoosePickupTimeLabel: LocalizedText(
    nl: 'Kies…',
    en: 'Choose…',
    fr: 'Choisir…',
    es: 'Elegir…',
  ),
  calculatorWaitStepHint: LocalizedText(
    nl: 'In stappen van 5 min.',
    en: 'In steps of 5 min.',
    fr: 'Par pas de 5 min.',
    es: 'En pasos de 5 min.',
  ),
  calculatorQuoteTipText: LocalizedText(
    nl: 'Tip: de Worker blijft de source-of-truth. Deze UI is puur input + weergave.',
    en: 'Tip: the Worker remains the source of truth. This UI only handles input and display.',
    fr: 'Astuce: le Worker reste la source de verite. Cette interface gere seulement la saisie et l affichage.',
    es: 'Consejo: el Worker sigue siendo la fuente de verdad. Esta interfaz solo gestiona entrada y visualizacion.',
  ),
  calculatorPriceInclVatLabel: LocalizedText(
    nl: 'Prijs incl. btw',
    en: 'Price incl. tax',
    fr: 'Prix TTC',
    es: 'Precio incl. impuesto',
  ),
  calculatorPriceExVatLabel: LocalizedText(
    nl: 'Prijs excl. btw',
    en: 'Price excl. tax',
    fr: 'Prix HT',
    es: 'Precio sin impuesto',
  ),
  calculatorVatLabel: LocalizedText(
    nl: 'Belasting',
    en: 'Tax',
    fr: 'Taxe',
    es: 'Impuesto',
  ),
  calculatorDistanceLabel: LocalizedText(
    nl: 'Afstand',
    en: 'Distance',
    fr: 'Distance',
    es: 'Distancia',
  ),
  calculatorDurationLabel: LocalizedText(
    nl: 'Duur',
    en: 'Duration',
    fr: 'Duree',
    es: 'Duracion',
  ),
  calculatorErrorPrefix: LocalizedText(
    nl: 'Fout',
    en: 'Error',
    fr: 'Erreur',
    es: 'Error',
  ),
  calculatorFillFromToError: LocalizedText(
    nl: 'Vul zowel VAN als NAAR in.',
    en: 'Please fill both FROM and TO.',
    fr: 'Veuillez remplir DEPART et ARRIVEE.',
    es: 'Complete ORIGEN y DESTINO.',
  ),
  calculatorLocationServiceOffError: LocalizedText(
    nl: 'Locatie staat uit op je toestel.',
    en: 'Location services are turned off on your device.',
    fr: 'La localisation est desactivee sur votre appareil.',
    es: 'La ubicacion esta desactivada en tu dispositivo.',
  ),
  calculatorNoLocationPermissionError: LocalizedText(
    nl: 'Geen locatie-permissie.',
    en: 'No location permission.',
    fr: 'Aucune permission de localisation.',
    es: 'Sin permiso de ubicacion.',
  ),
  calculatorCurrentLocationFailedError: LocalizedText(
    nl: 'Kon huidige locatie niet ophalen.',
    en: 'Could not fetch current location.',
    fr: 'Impossible de recuperer la position actuelle.',
    es: 'No se pudo obtener la ubicacion actual.',
  ),
  calculatorCurrentLocationFallbackLabel: LocalizedText(
    nl: 'Huidige locatie',
    en: 'Current location',
    fr: 'Position actuelle',
    es: 'Ubicacion actual',
  ),
  calculatorMaxBagsHint: LocalizedText(
    nl: 'Max 3 koffers.',
    en: 'Max 3 suitcases.',
    fr: 'Max 3 valises.',
    es: 'Max 3 maletas.',
  ),
  calculatorMaxPassengersHint: LocalizedText(
    nl: 'Max 3 passagiers.',
    en: 'Max 3 passengers.',
    fr: 'Max 3 passagers.',
    es: 'Max 3 pasajeros.',
  ),
  breakdownStartFeeEx: LocalizedText(
    nl: 'Starttarief',
    en: 'Start fee',
    fr: 'Frais de depart',
    es: 'Tarifa inicial',
  ),
  breakdownPerKmEx: LocalizedText(
    nl: 'Tarief per km',
    en: 'Rate per km',
    fr: 'Tarif par km',
    es: 'Tarifa por km',
  ),
  breakdownPerMinEx: LocalizedText(
    nl: 'Tarief per minuut',
    en: 'Rate per minute',
    fr: 'Tarif par minute',
    es: 'Tarifa por minuto',
  ),
  breakdownDistanceKm: LocalizedText(
    nl: 'Afstand',
    en: 'Distance',
    fr: 'Distance',
    es: 'Distancia',
  ),
  breakdownDurationMin: LocalizedText(
    nl: 'Duur',
    en: 'Duration',
    fr: 'Duree',
    es: 'Duracion',
  ),
  breakdownBaseDriveEx: LocalizedText(
    nl: 'Basisrit',
    en: 'Base drive',
    fr: 'Course de base',
    es: 'Trayecto base',
  ),
  breakdownExtraStopsEx: LocalizedText(
    nl: 'Extra stops',
    en: 'Extra stops',
    fr: 'Arrets supplementaires',
    es: 'Paradas extra',
  ),
  breakdownWaitingEx: LocalizedText(
    nl: 'Wachttijd',
    en: 'Waiting time',
    fr: 'Temps d attente',
    es: 'Tiempo de espera',
  ),
  breakdownSurchargeRate: LocalizedText(
    nl: 'Toeslagpercentage',
    en: 'Surcharge rate',
    fr: 'Taux de surcharge',
    es: 'Tasa de recargo',
  ),
  breakdownSurchargeBaseEx: LocalizedText(
    nl: 'Toeslagbasis',
    en: 'Surcharge base',
    fr: 'Base de surcharge',
    es: 'Base de recargo',
  ),
  breakdownSurchargeAmountEx: LocalizedText(
    nl: 'Toeslagbedrag',
    en: 'Surcharge amount',
    fr: 'Montant surcharge',
    es: 'Importe recargo',
  ),
  breakdownBagsEx: LocalizedText(
    nl: 'Bagagetoeslag',
    en: 'Luggage surcharge',
    fr: 'Supplement bagages',
    es: 'Recargo equipaje',
  ),
  breakdownTier: LocalizedText(
    nl: 'Voertuigklasse',
    en: 'Vehicle tier',
    fr: 'Categorie vehicule',
    es: 'Categoria vehiculo',
  ),
  breakdownTierFeeEx: LocalizedText(
    nl: 'Klassetoeslag',
    en: 'Tier surcharge',
    fr: 'Supplement categorie',
    es: 'Recargo de categoria',
  ),
  breakdownTotalEx: LocalizedText(
    nl: 'Totaal excl. belasting',
    en: 'Total excl. tax',
    fr: 'Total HT',
    es: 'Total sin impuesto',
  ),
  breakdownVatRate: LocalizedText(
    nl: 'Belastingtarief',
    en: 'Tax rate',
    fr: 'Taux de taxe',
    es: 'Tasa de impuesto',
  ),
  breakdownVatAmount: LocalizedText(
    nl: 'Belastingbedrag',
    en: 'Tax amount',
    fr: 'Montant taxe',
    es: 'Importe de impuesto',
  ),
  breakdownTotalIncl: LocalizedText(
    nl: 'Totaal incl. belasting',
    en: 'Total incl. tax',
    fr: 'Total TTC',
    es: 'Total con impuesto',
  ),
);

const AppStrings _en = _nl;
const AppStrings _fr = _nl;
const AppStrings _es = _nl;
