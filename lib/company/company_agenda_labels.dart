import 'package:fluxidi_tracking/app_strings.dart';

const LocalizedText kCompanyAgendaTitle = LocalizedText(
  nl: 'Agenda',
  en: 'Agenda',
  fr: 'Agenda',
  es: 'Agenda',
);

const LocalizedText kCompanyAgendaCustomersTab = LocalizedText(
  nl: 'Klanten',
  en: 'Customers',
  fr: 'Clients',
  es: 'Clientes',
);

const LocalizedText kCompanyAgendaDay = LocalizedText(
  nl: 'Dag',
  en: 'Day',
  fr: 'Jour',
  es: 'Día',
);

const LocalizedText kCompanyAgendaWeek = LocalizedText(
  nl: 'Week',
  en: 'Week',
  fr: 'Semaine',
  es: 'Semana',
);

const LocalizedText kCompanyAgendaHourCompact = LocalizedText(
  nl: 'Compact',
  en: 'Compact',
  fr: 'Compact',
  es: 'Compacto',
);

const LocalizedText kCompanyAgendaHourSpacious = LocalizedText(
  nl: 'Ruim',
  en: 'Spacious',
  fr: 'Aéré',
  es: 'Holgado',
);

const LocalizedText kCompanyAgendaMore = LocalizedText(
  nl: 'meer',
  en: 'more',
  fr: 'plus',
  es: 'más',
);

const LocalizedText kCompanyAgendaMoreRides = LocalizedText(
  nl: 'Gelijktijdige ritten',
  en: 'Overlapping rides',
  fr: 'Courses simultanées',
  es: 'Viajes simultáneos',
  de: 'Gleichzeitige Fahrten',
);

const LocalizedText kCompanyAgendaContinues = LocalizedText(
  nl: 'Vervolg',
  en: 'Continuation',
  fr: 'Suite',
  es: 'Continuación',
  de: 'Fortsetzung',
);

const LocalizedText kCompanyAgendaAllDrivers = LocalizedText(
  nl: 'Alle chauffeurs',
  en: 'All drivers',
  fr: 'Tous les chauffeurs',
  es: 'Todos los conductores',
  de: 'Alle Fahrer',
);

const List<LocalizedText> kCompanyAgendaWeekdayLabels = <LocalizedText>[
  LocalizedText(nl: 'Ma', en: 'Mon', fr: 'Lun', es: 'Lun', de: 'Mo'),
  LocalizedText(nl: 'Di', en: 'Tue', fr: 'Mar', es: 'Mar', de: 'Di'),
  LocalizedText(nl: 'Wo', en: 'Wed', fr: 'Mer', es: 'Mié', de: 'Mi'),
  LocalizedText(nl: 'Do', en: 'Thu', fr: 'Jeu', es: 'Jue', de: 'Do'),
  LocalizedText(nl: 'Vr', en: 'Fri', fr: 'Ven', es: 'Vie', de: 'Fr'),
  LocalizedText(nl: 'Za', en: 'Sat', fr: 'Sam', es: 'Sáb', de: 'Sa'),
  LocalizedText(nl: 'Zo', en: 'Sun', fr: 'Dim', es: 'Dom', de: 'So'),
];

String companyAgendaWeekdayLabel(DateTime day, AppLanguage language) {
  return kCompanyAgendaWeekdayLabels[(day.weekday - 1).clamp(0, 6)].of(
    language,
  );
}

String companyAgendaConcurrentLabel(int count, AppLanguage language) {
  final n = count < 1 ? 1 : count;
  switch (language) {
    case AppLanguage.nl:
      return '$n gelijktijdige ritten';
    case AppLanguage.fr:
      return n == 1 ? '1 course simultanée' : '$n courses simultanées';
    case AppLanguage.es:
      return n == 1 ? '1 viaje simultáneo' : '$n viajes simultáneos';
    case AppLanguage.de:
      return n == 1 ? '1 gleichzeitige Fahrt' : '$n gleichzeitige Fahrten';
    case AppLanguage.en:
      return n == 1 ? '1 overlapping ride' : '$n overlapping rides';
  }
}

const LocalizedText kCompanyAgendaByDriver = LocalizedText(
  nl: 'Per chauffeur',
  en: 'By driver',
  fr: 'Par chauffeur',
  es: 'Por conductor',
);

const LocalizedText kCompanyAgendaUnassignedLane = LocalizedText(
  nl: 'Nog toe te wijzen',
  en: 'Still to assign',
  fr: 'Encore à attribuer',
  es: 'Pendiente de asignar',
);

const LocalizedText kCompanyAgendaUnscheduled = LocalizedText(
  nl: 'Nog in te plannen',
  en: 'Still to schedule',
  fr: 'Encore à planifier',
  es: 'Pendiente de planificar',
);

const LocalizedText kCompanyAgendaAssign = LocalizedText(
  nl: 'Toewijzen',
  en: 'Assign',
  fr: 'Attribuer',
  es: 'Asignar',
);

const LocalizedText kCompanyAgendaUnassign = LocalizedText(
  nl: 'Vrijmaken',
  en: 'Unassign',
  fr: 'Libérer',
  es: 'Liberar',
);

const LocalizedText kCompanyAgendaAssigned = LocalizedText(
  nl: 'Toegewezen',
  en: 'Assigned',
  fr: 'Attribué',
  es: 'Asignado',
);

const LocalizedText kCompanyAgendaAccepted = LocalizedText(
  nl: 'Aanvaard',
  en: 'Accepted',
  fr: 'Accepté',
  es: 'Aceptado',
);

const LocalizedText kCompanyAgendaNotAccepted = LocalizedText(
  nl: 'Nog niet aanvaard',
  en: 'Not yet accepted',
  fr: 'Pas encore accepté',
  es: 'Aún no aceptado',
);

const LocalizedText kCompanyAgendaPhoneConfirmed = LocalizedText(
  nl: 'Telefonisch bevestigd',
  en: 'Confirmed by phone',
  fr: 'Confirmé par téléphone',
  es: 'Confirmado por teléfono',
);

const LocalizedText kCompanyAgendaMarkPhoneConfirm = LocalizedText(
  nl: 'Telefonisch bevestigen',
  en: 'Confirm by phone',
  fr: 'Confirmer par téléphone',
  es: 'Confirmar por teléfono',
);

const LocalizedText kCompanyAgendaReschedule = LocalizedText(
  nl: 'Tijdstip wijzigen',
  en: 'Change time',
  fr: 'Modifier l’horaire',
  es: 'Cambiar hora',
);

const LocalizedText kCompanyAgendaRescheduleConfirm = LocalizedText(
  nl: 'Deze rit naar het nieuwe tijdstip verplaatsen?',
  en: 'Move this ride to the new time?',
  fr: 'Déplacer cette course vers le nouvel horaire ?',
  es: '¿Mover este viaje a la nueva hora?',
);

const LocalizedText kCompanyAgendaPickDate = LocalizedText(
  nl: 'Datum kiezen',
  en: 'Pick date',
  fr: 'Choisir la date',
  es: 'Elegir fecha',
);

const LocalizedText kCompanyAgendaPreviousPeriod = LocalizedText(
  nl: 'Vorige periode',
  en: 'Previous period',
  fr: 'Période précédente',
  es: 'Periodo anterior',
);

const LocalizedText kCompanyAgendaNextPeriod = LocalizedText(
  nl: 'Volgende periode',
  en: 'Next period',
  fr: 'Période suivante',
  es: 'Periodo siguiente',
);

const LocalizedText kCompanyAgendaPickTime = LocalizedText(
  nl: 'Tijd kiezen',
  en: 'Pick time',
  fr: 'Choisir l’heure',
  es: 'Elegir hora',
);

const LocalizedText kCompanyAgendaOnlineNowHint = LocalizedText(
  nl: 'Nu online betekent niet dat de chauffeur op het geplande tijdstip vrij is.',
  en: 'Online now does not mean the driver is free at the planned time.',
  fr: 'En ligne maintenant ne signifie pas que le chauffeur est libre à l’heure prévue.',
  es: 'Estar en línea ahora no significa que el conductor esté libre a la hora prevista.',
);

const LocalizedText kCompanyAgendaPhoneConfirmHint = LocalizedText(
  nl: 'Dit is een telefonische bevestiging door het bedrijf, geen offerte-acceptatie.',
  en: 'This is a phone confirmation by the company, not a quote acceptance.',
  fr: 'Ceci est une confirmation téléphonique de l’entreprise, pas une acceptation de devis.',
  es: 'Esto es una confirmación telefónica de la empresa, no una aceptación de presupuesto.',
);

const LocalizedText kCompanyAgendaToday = LocalizedText(
  nl: 'Vandaag',
  en: 'Today',
  fr: 'Aujourd’hui',
  es: 'Hoy',
);

const LocalizedText kCompanyAgendaPlanRide = LocalizedText(
  nl: 'Rit plannen',
  en: 'Plan ride',
  fr: 'Planifier une course',
  es: 'Planificar viaje',
);

const LocalizedText kCompanyAgendaEmpty = LocalizedText(
  nl: 'Geen ritten in deze periode.',
  en: 'No rides in this period.',
  fr: 'Aucune course dans cette période.',
  es: 'No hay viajes en este periodo.',
);

const LocalizedText kCompanyAgendaLoading = LocalizedText(
  nl: 'Agenda wordt geladen…',
  en: 'Loading agenda…',
  fr: 'Chargement de l’agenda…',
  es: 'Cargando la agenda…',
);

const LocalizedText kCompanyAgendaError = LocalizedText(
  nl: 'Agenda kon niet worden geladen.',
  en: 'The agenda could not be loaded.',
  fr: 'Impossible de charger l’agenda.',
  es: 'No se pudo cargar la agenda.',
);

const LocalizedText kCompanyAgendaUnassigned = LocalizedText(
  nl: 'Niet toegewezen',
  en: 'Unassigned',
  fr: 'Non attribué',
  es: 'Sin asignar',
);

const LocalizedText kCompanyAgendaDurationUnknown = LocalizedText(
  nl: 'Duur onbekend',
  en: 'Duration unknown',
  fr: 'Durée inconnue',
  es: 'Duración desconocida',
);

const LocalizedText kCompanyAgendaSelectCustomer = LocalizedText(
  nl: 'Kies eerst een actieve klant.',
  en: 'Select an active customer first.',
  fr: 'Choisissez d’abord un client actif.',
  es: 'Elige primero un cliente activo.',
);

const LocalizedText kCompanyAgendaPickup = LocalizedText(
  nl: 'Vertrek',
  en: 'Pickup',
  fr: 'Départ',
  es: 'Salida',
);

const LocalizedText kCompanyAgendaDropoff = LocalizedText(
  nl: 'Bestemming',
  en: 'Drop-off',
  fr: 'Destination',
  es: 'Destino',
);

const LocalizedText kCompanyAgendaPassengers = LocalizedText(
  nl: 'Passagiers',
  en: 'Passengers',
  fr: 'Passagers',
  es: 'Pasajeros',
);

const LocalizedText kCompanyAgendaPrice = LocalizedText(
  nl: 'Prijs (optioneel)',
  en: 'Price (optional)',
  fr: 'Prix (facultatif)',
  es: 'Precio (opcional)',
);

const LocalizedText kCompanyAgendaDuration = LocalizedText(
  nl: 'Duur in minuten (leeg = onbekend)',
  en: 'Duration in minutes (empty = unknown)',
  fr: 'Durée en minutes (vide = inconnue)',
  es: 'Duración en minutos (vacío = desconocida)',
);

const LocalizedText kCompanyAgendaDriver = LocalizedText(
  nl: 'Chauffeur (optioneel)',
  en: 'Driver (optional)',
  fr: 'Chauffeur (facultatif)',
  es: 'Conductor (opcional)',
);

const LocalizedText kCompanyAgendaVehicle = LocalizedText(
  nl: 'Voertuig (optioneel)',
  en: 'Vehicle (optional)',
  fr: 'Véhicule (facultatif)',
  es: 'Vehículo (opcional)',
);

const LocalizedText kCompanyAgendaSave = LocalizedText(
  nl: 'Rit bewaren',
  en: 'Save ride',
  fr: 'Enregistrer la course',
  es: 'Guardar viaje',
);

const LocalizedText kCompanyAgendaCancel = LocalizedText(
  nl: 'Annuleren',
  en: 'Cancel',
  fr: 'Annuler',
  es: 'Cancelar',
);

const LocalizedText kCompanyAgendaSaved = LocalizedText(
  nl: 'Rit bewaard.',
  en: 'Ride saved.',
  fr: 'Course enregistrée.',
  es: 'Viaje guardado.',
);

const LocalizedText kCompanyAgendaOverlap = LocalizedText(
  nl: 'Deze toewijzing botst met een bestaande rit.',
  en: 'This assignment overlaps an existing ride.',
  fr: 'Cette attribution chevauche une course existante.',
  es: 'Esta asignación se solapa con un viaje existente.',
);

const LocalizedText kCompanyAgendaAvailabilityUnknown = LocalizedText(
  nl: 'Beschikbaarheid kan niet worden bevestigd zonder ritduur.',
  en: 'Availability cannot be confirmed without a ride duration.',
  fr: 'La disponibilité ne peut pas être confirmée sans durée.',
  es: 'No se puede confirmar la disponibilidad sin duración.',
);

const LocalizedText kCompanyAgendaPriceChanged = LocalizedText(
  nl: 'De prijs is gewijzigd. Bekijk het nieuwe totaal en bewaar opnieuw.',
  en: 'The price changed. Review the new total and save again.',
  fr: 'Le prix a changé. Vérifiez le nouveau total et enregistrez à nouveau.',
  es: 'El precio cambió. Revisa el nuevo total y guarda de nuevo.',
);

const LocalizedText kCompanyAgendaSaveFailed = LocalizedText(
  nl: 'Rit kon niet worden bewaard.',
  en: 'The ride could not be saved.',
  fr: 'Impossible d’enregistrer la course.',
  es: 'No se pudo guardar el viaje.',
);

const LocalizedText kCompanyAgendaPickupRequired = LocalizedText(
  nl: 'Kies een ophaaldatum en -tijd.',
  en: 'Choose a pickup date and time.',
  fr: 'Choisissez une date et une heure de prise en charge.',
  es: 'Elija fecha y hora de recogida.',
);

const LocalizedText kCompanyAgendaChoicesLoading = LocalizedText(
  nl: 'Chauffeurs en voertuigen worden geladen…',
  en: 'Loading drivers and vehicles…',
  fr: 'Chargement des chauffeurs et véhicules…',
  es: 'Cargando conductores y vehículos…',
);

const LocalizedText kCompanyAgendaChoicesLoadFailed = LocalizedText(
  nl: 'Chauffeurs of voertuigen konden niet worden geladen.',
  en: 'Drivers or vehicles could not be loaded.',
  fr: 'Impossible de charger les chauffeurs ou les véhicules.',
  es: 'No se pudieron cargar conductores o vehículos.',
);

const LocalizedText kCompanyAgendaNoRegisteredDrivers = LocalizedText(
  nl: 'Geen geregistreerde chauffeurs voor dit bedrijf.',
  en: 'No registered drivers for this company.',
  fr: 'Aucun chauffeur enregistré pour cette entreprise.',
  es: 'No hay conductores registrados para esta empresa.',
);

const LocalizedText kCompanyAgendaNoSuitableDrivers = LocalizedText(
  nl: 'Geen geschikte chauffeurs voor deze rit.',
  en: 'No suitable drivers for this ride.',
  fr: 'Aucun chauffeur adapté pour cette course.',
  es: 'No hay conductores adecuados para este viaje.',
);

const LocalizedText kCompanyAgendaNoRegisteredVehicles = LocalizedText(
  nl: 'Geen geregistreerde voertuigen voor dit bedrijf.',
  en: 'No registered vehicles for this company.',
  fr: 'Aucun véhicule enregistré pour cette entreprise.',
  es: 'No hay vehículos registrados para esta empresa.',
);

const LocalizedText kCompanyAgendaNoSuitableVehicles = LocalizedText(
  nl: 'Geen geschikt voertuig voor het aantal passagiers.',
  en: 'No vehicle fits this passenger count.',
  fr: 'Aucun véhicule ne convient à ce nombre de passagers.',
  es: 'Ningún vehículo cabe para este número de pasajeros.',
);

const LocalizedText kCompanyAgendaDriverInactive = LocalizedText(
  nl: 'niet actief',
  en: 'inactive',
  fr: 'inactif',
  es: 'inactivo',
);

const LocalizedText kCompanyAgendaHint = LocalizedText(
  nl: 'Sleep een actieve klant naar een tijdstip of gebruik Rit plannen.',
  en: 'Drag an active customer onto a time or use Plan ride.',
  fr: 'Glissez un client actif sur un horaire ou utilisez Planifier.',
  es: 'Arrastra un cliente activo a una hora o usa Planificar.',
);

const LocalizedText kCompanyAgendaCustomerPane = LocalizedText(
  nl: 'Klantenlijst',
  en: 'Customer list',
  fr: 'Liste clients',
  es: 'Lista de clientes',
);

const LocalizedText kCompanyAgendaDossierPane = LocalizedText(
  nl: 'Klantdossier',
  en: 'Customer file',
  fr: 'Dossier client',
  es: 'Ficha del cliente',
);

const LocalizedText kCompanyAgendaShowPane = LocalizedText(
  nl: 'Tonen',
  en: 'Show',
  fr: 'Afficher',
  es: 'Mostrar',
);

const LocalizedText kCompanyAgendaHidePane = LocalizedText(
  nl: 'Verbergen',
  en: 'Hide',
  fr: 'Masquer',
  es: 'Ocultar',
);

const LocalizedText kCompanyDriversNowTitle = LocalizedText(
  nl: 'Chauffeurs nu',
  en: 'Drivers now',
  fr: 'Chauffeurs maintenant',
  es: 'Conductores ahora',
);

const LocalizedText kCompanyDriversNowHint = LocalizedText(
  nl: 'Tik een chauffeur om alleen die ritten te zien. Nogmaals tikken toont iedereen. Zonder livebron: onbekend.',
  en: 'Tap a driver to see only that agenda. Tap again to show everyone. Without a live source: unknown.',
  fr: 'Touchez un chauffeur pour voir uniquement ses courses. Toucher à nouveau affiche tout le monde. Sans source live : inconnu.',
  es: 'Toca un conductor para ver solo sus viajes. Tocar de nuevo muestra a todos. Sin fuente en vivo: desconocido.',
);

const LocalizedText kCompanyDriversNowShowAgenda = LocalizedText(
  nl: 'Toon agenda',
  en: 'Show agenda',
  fr: 'Afficher l’agenda',
  es: 'Mostrar agenda',
);

const LocalizedText kCompanyDriversNowPrevious = LocalizedText(
  nl: 'Vorige chauffeurs',
  en: 'Previous drivers',
  fr: 'Chauffeurs précédents',
  es: 'Conductores anteriores',
);

const LocalizedText kCompanyDriversNowNext = LocalizedText(
  nl: 'Volgende chauffeurs',
  en: 'Next drivers',
  fr: 'Chauffeurs suivants',
  es: 'Siguientes conductores',
);

const LocalizedText kCompanyDriversNowNoLiveLink = LocalizedText(
  nl: 'Geen live-verbinding',
  en: 'No live connection',
  fr: 'Pas de connexion en direct',
  es: 'Sin conexión en vivo',
);

const LocalizedText kCompanyDriversNowStatusNotCurrent = LocalizedText(
  nl: 'Onbekend',
  en: 'Unknown',
  fr: 'Inconnu',
  es: 'Desconocido',
);

const LocalizedText kCompanyDriversNowNoLiveData = LocalizedText(
  nl: 'Geen livegegevens',
  en: 'No live data',
  fr: 'Pas de données en direct',
  es: 'Sin datos en vivo',
);

const LocalizedText kCompanyDriversNowWorkAvailable = LocalizedText(
  nl: 'Werkstatus: beschikbaar',
  en: 'Work status: available',
  fr: 'Statut: disponible',
  es: 'Estado: disponible',
);

const LocalizedText kCompanyDriversNowWorkBusy = LocalizedText(
  nl: 'Werkstatus: bezet',
  en: 'Work status: busy',
  fr: 'Statut: occupé',
  es: 'Estado: ocupado',
);

const LocalizedText kCompanyDriversNowWorkUnavailable = LocalizedText(
  nl: 'Werkstatus: niet inzetbaar',
  en: 'Work status: not dispatchable',
  fr: 'Statut: non disponible',
  es: 'Estado: no disponible',
);

const LocalizedText kCompanyDriversNowCurrentRide = LocalizedText(
  nl: 'Huidige rit',
  en: 'Current ride',
  fr: 'Course en cours',
  es: 'Viaje actual',
);

const LocalizedText kCompanyDriversNowNextRide = LocalizedText(
  nl: 'Volgende geplande rit',
  en: 'Next planned ride',
  fr: 'Prochaine course planifiée',
  es: 'Siguiente viaje planificado',
);

const LocalizedText kCompanyDriversNowNoRide = LocalizedText(
  nl: 'geen',
  en: 'none',
  fr: 'aucune',
  es: 'ninguno',
);

const LocalizedText kCompanyDriversNowLastUpdated = LocalizedText(
  nl: 'Laatst bijgewerkt',
  en: 'Last updated',
  fr: 'Dernière mise à jour',
  es: 'Última actualización',
);

const LocalizedText kCompanyDriversNowUpdatedUnknown = LocalizedText(
  nl: 'onbekend',
  en: 'unknown',
  fr: 'inconnu',
  es: 'desconocido',
);

const LocalizedText kCompanyDriversNowOpenRide = LocalizedText(
  nl: 'Open rit',
  en: 'Open ride',
  fr: 'Ouvrir la course',
  es: 'Abrir viaje',
);

const LocalizedText kCompanyAgendaOverlapPreview = LocalizedText(
  nl: 'Deze keuze botst met een bestaande rit.',
  en: 'This choice overlaps an existing ride.',
  fr: 'Ce choix chevauche une course existante.',
  es: 'Esta elección se solapa con un viaje existente.',
);

const LocalizedText kCompanyAgendaColorLabel = LocalizedText(
  nl: 'Agendakleur',
  en: 'Agenda color',
  fr: 'Couleur d’agenda',
  es: 'Color de agenda',
);

const LocalizedText kCompanyAgendaColorChange = LocalizedText(
  nl: 'Agendakleur wijzigen',
  en: 'Change agenda color',
  fr: 'Modifier la couleur d’agenda',
  es: 'Cambiar color de agenda',
);

const LocalizedText kCompanyAgendaColorSave = LocalizedText(
  nl: 'Bewaren',
  en: 'Save',
  fr: 'Enregistrer',
  es: 'Guardar',
);

const LocalizedText kCompanyAgendaColorSaved = LocalizedText(
  nl: 'Agendakleur bewaard.',
  en: 'Agenda color saved.',
  fr: 'Couleur d’agenda enregistrée.',
  es: 'Color de agenda guardado.',
);

const LocalizedText kCompanyAgendaColorSaveFailed = LocalizedText(
  nl: 'Agendakleur kon niet worden bewaard.',
  en: 'The agenda color could not be saved.',
  fr: 'Impossible d’enregistrer la couleur d’agenda.',
  es: 'No se pudo guardar el color de agenda.',
);

const LocalizedText kCompanyAgendaColorCustom = LocalizedText(
  nl: 'Eigen kleur',
  en: 'Custom color',
  fr: 'Couleur perso',
  es: 'Color propio',
);

const LocalizedText kCompanyAgendaColorCustomHex = LocalizedText(
  nl: 'Hexkleur',
  en: 'Hex color',
  fr: 'Couleur hex',
  es: 'Color hex',
);

const LocalizedText kCompanyAgendaColorPreview = LocalizedText(
  nl: 'Voorbeeld',
  en: 'Preview',
  fr: 'Aperçu',
  es: 'Vista previa',
);

const LocalizedText kCompanyAgendaColorUsedBy = LocalizedText(
  nl: 'Al in gebruik bij',
  en: 'Already used by',
  fr: 'Déjà utilisée par',
  es: 'Ya usada por',
);

const LocalizedText kCompanyAgendaColorIdentityHint = LocalizedText(
  nl: 'Kleur helpt scannen. Naam en foto of initialen blijven de herkenning.',
  en: 'Color helps scanning. Name and photo or initials remain the recognition.',
  fr: 'La couleur aide à balayer. Le nom et la photo ou les initiales restent la reconnaissance.',
  es: 'El color ayuda a localizar. El nombre y la foto o las iniciales siguen siendo el reconocimiento.',
);

const LocalizedText kCompanyDriverAccountOn = LocalizedText(
  nl: 'Account actief',
  en: 'Account enabled',
  fr: 'Compte actif',
  es: 'Cuenta activa',
);

const LocalizedText kCompanyDriverAccountOff = LocalizedText(
  nl: 'Account uit',
  en: 'Account disabled',
  fr: 'Compte désactivé',
  es: 'Cuenta desactivada',
);

const LocalizedText kCompanyDriverAccountToggleHint = LocalizedText(
  nl: 'Dit is de accountstatus van de chauffeur, geen online-beschikbaarheid.',
  en: 'This is the driver’s account status, not online availability.',
  fr: 'Ceci est le statut du compte du chauffeur, pas la disponibilité en ligne.',
  es: 'Este es el estado de la cuenta del conductor, no la disponibilidad en línea.',
);

const LocalizedText kCompanyDriversCountTotal = LocalizedText(
  nl: 'Chauffeurs',
  en: 'Drivers',
  fr: 'Chauffeurs',
  es: 'Conductores',
);

const LocalizedText kCompanyDriversAccountsOn = LocalizedText(
  nl: 'Accounts actief',
  en: 'Accounts enabled',
  fr: 'Comptes actifs',
  es: 'Cuentas activas',
);

const LocalizedText kCompanyDriversAccountsOff = LocalizedText(
  nl: 'Accounts uit',
  en: 'Accounts disabled',
  fr: 'Comptes désactivés',
  es: 'Cuentas desactivadas',
);

const LocalizedText kCompanyDriversPaused = LocalizedText(
  nl: 'Pauze',
  en: 'Paused',
  fr: 'Pause',
  es: 'Pausa',
);

const LocalizedText kCompanyDriversDocsAction = LocalizedText(
  nl: 'Documenten',
  en: 'Documents',
  fr: 'Documents',
  es: 'Documentos',
);

const LocalizedText kCompanyDriversExpiring = LocalizedText(
  nl: 'Vervalt',
  en: 'Expiring',
  fr: 'Expire',
  es: 'Caduca',
);

const LocalizedText kCompanyRoundtripSingle = LocalizedText(
  nl: 'Enkele rit',
  en: 'One-way ride',
  fr: 'Trajet simple',
  es: 'Viaje sencillo',
);

const LocalizedText kCompanyRoundtripSplit = LocalizedText(
  nl: 'Heen en terug — chauffeur wacht niet',
  en: 'Out and back — driver does not wait',
  fr: 'Aller-retour — le chauffeur n’attend pas',
  es: 'Ida y vuelta — el conductor no espera',
);

const LocalizedText kCompanyRoundtripContinuous = LocalizedText(
  nl: 'Heen en terug — chauffeur blijft wachten',
  en: 'Out and back — driver stays and waits',
  fr: 'Aller-retour — le chauffeur reste attendre',
  es: 'Ida y vuelta — el conductor espera',
);

const LocalizedText kCompanyRoundtripOutbound = LocalizedText(
  nl: 'Heenrit',
  en: 'Outbound',
  fr: 'Aller',
  es: 'Ida',
);

const LocalizedText kCompanyRoundtripReturn = LocalizedText(
  nl: 'Terugrit',
  en: 'Return',
  fr: 'Retour',
  es: 'Vuelta',
);

const LocalizedText kCompanyRoundtripContinuousShort = LocalizedText(
  nl: 'Heen en terug met wachten',
  en: 'Out and back with waiting',
  fr: 'Aller-retour avec attente',
  es: 'Ida y vuelta con espera',
);

const LocalizedText kCompanyRoundtripReturnWhen = LocalizedText(
  nl: 'Terugrit: datum en tijd',
  en: 'Return: date and time',
  fr: 'Retour : date et heure',
  es: 'Vuelta: fecha y hora',
);

const LocalizedText kCompanyRoundtripReturnFrom = LocalizedText(
  nl: 'Vertrek terugrit',
  en: 'Return pickup',
  fr: 'Départ du retour',
  es: 'Salida de vuelta',
);

const LocalizedText kCompanyRoundtripReturnTo = LocalizedText(
  nl: 'Bestemming terugrit',
  en: 'Return drop-off',
  fr: 'Destination du retour',
  es: 'Destino de vuelta',
);

const LocalizedText kCompanyRoundtripReturnDuration = LocalizedText(
  nl: 'Duur terugrit (minuten)',
  en: 'Return duration (minutes)',
  fr: 'Durée du retour (minutes)',
  es: 'Duración de la vuelta (minutos)',
);

const LocalizedText kCompanyRoundtripReturnDriver = LocalizedText(
  nl: 'Chauffeur terugrit',
  en: 'Return driver',
  fr: 'Chauffeur du retour',
  es: 'Conductor de vuelta',
);

const LocalizedText kCompanyRoundtripReturnVehicle = LocalizedText(
  nl: 'Voertuig terugrit',
  en: 'Return vehicle',
  fr: 'Véhicule du retour',
  es: 'Vehículo de vuelta',
);

const LocalizedText kCompanyRoundtripReturnRequired = LocalizedText(
  nl: 'Kies datum en tijd van de terugrit.',
  en: 'Choose the return date and time.',
  fr: 'Choisissez la date et l’heure du retour.',
  es: 'Elija la fecha y hora de la vuelta.',
);

const LocalizedText kCompanyRoundtripOccupancyUnknown = LocalizedText(
  nl: 'Bezetting tijdens het wachten is onbekend zolang tijden of duur ontbreken.',
  en: 'Occupancy while waiting is unknown until times or duration are filled in.',
  fr: 'L’occupation pendant l’attente est inconnue tant que les heures ou la durée manquent.',
  es: 'La ocupación durante la espera es desconocida hasta completar horas o duración.',
);

const LocalizedText kCompanyRoundtripPriceCovers = LocalizedText(
  nl: 'Het ingevulde bedrag geldt voor de volledige opdracht, niet per ritdeel.',
  en: 'The entered amount covers the full assignment, not each ride separately.',
  fr: 'Le montant saisi couvre toute la mission, pas chaque trajet.',
  es: 'El importe cubre el encargo completo, no cada viaje.',
);

const LocalizedText kCompanyRoundtripOpenLinked = LocalizedText(
  nl: 'Open gekoppelde rit',
  en: 'Open linked ride',
  fr: 'Ouvrir la course liée',
  es: 'Abrir el viaje vinculado',
);

const LocalizedText kCompanyAgendaCancelRideAction = LocalizedText(
  nl: 'Annuleren',
  en: 'Cancel ride',
  fr: 'Annuler',
  es: 'Cancelar',
);

const LocalizedText kCompanyAgendaCancelThisLeg = LocalizedText(
  nl: 'Alleen dit ritdeel',
  en: 'This ride only',
  fr: 'Ce trajet seulement',
  es: 'Solo este viaje',
);

const LocalizedText kCompanyAgendaCancelFullReturn = LocalizedText(
  nl: 'Volledige heen- en terugrit',
  en: 'Full out-and-back assignment',
  fr: 'Aller-retour complet',
  es: 'Ida y vuelta completa',
);

const LocalizedText kCompanyAgendaCancelConfirm = LocalizedText(
  nl: 'Deze rit annuleren via de bestaande annuleringsflow?',
  en: 'Cancel this ride through the existing cancellation flow?',
  fr: 'Annuler cette course via le flux d’annulation existant ?',
  es: '¿Cancelar este viaje con el flujo de anulación existente?',
);

const LocalizedText kCompanyAgendaCancelFailed = LocalizedText(
  nl: 'Annuleren is niet gelukt.',
  en: 'Cancellation failed.',
  fr: 'L’annulation a échoué.',
  es: 'La cancelación falló.',
);

const LocalizedText kCompanyAgendaIncompleteOverview = LocalizedText(
  nl: 'Dit overzicht is onvolledig. Kies een kleinere periode. Gebruik het niet als bewijs dat een chauffeur vrij is.',
  en: 'This overview is incomplete. Choose a smaller period. Do not treat it as proof that a driver is free.',
  fr: 'Cet aperçu est incomplet. Choisissez une période plus courte. Ne l’utilisez pas comme preuve qu’un chauffeur est libre.',
  es: 'Este resumen está incompleto. Elija un periodo más corto. No lo use como prueba de que un conductor está libre.',
);

const LocalizedText kCompanyAgendaSmallerPeriod = LocalizedText(
  nl: 'Naar dagweergave',
  en: 'Switch to day view',
  fr: 'Vue quotidienne',
  es: 'Vista diaria',
);
