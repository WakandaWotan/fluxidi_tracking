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

const LocalizedText kCompanyAgendaNewRideTab = LocalizedText(
  nl: 'Nieuwe rit',
  en: 'New ride',
  fr: 'Nouvelle course',
  es: 'Nuevo viaje',
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
  nl: 'Toewijzing verwijderen',
  en: 'Remove assignment',
  fr: 'Retirer l’attribution',
  es: 'Quitar asignación',
);

const LocalizedText kCompanyAgendaCurrentDriver = LocalizedText(
  nl: 'Huidige chauffeur',
  en: 'Current driver',
  fr: 'Chauffeur actuel',
  es: 'Conductor actual',
);

const LocalizedText kCompanyAgendaNoOtherDriver = LocalizedText(
  nl: 'Geen andere chauffeur beschikbaar voor dit tijdstip',
  en: 'No other driver is available at this time',
  fr: 'Aucun autre chauffeur n’est disponible à cet horaire',
  es: 'No hay otro conductor disponible a esta hora',
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

const LocalizedText kCompanyAgendaNeedCustomerAddress = LocalizedText(
  nl: 'Deze klant heeft nog geen opgeslagen adres. Vul het vertrekadres in of bewaar er een op de klantfiche.',
  en: 'This customer has no saved address yet. Enter the pickup or save one on the customer record.',
  fr: 'Ce client n’a pas encore d’adresse enregistrée. Saisissez le départ ou enregistrez-en une.',
  es: 'Este cliente aún no tiene dirección guardada. Introduce la salida o guarda una en la ficha.',
);

const LocalizedText kCompanyAgendaChooseCustomerAddress = LocalizedText(
  nl: 'Kies het klantadres voor deze rit',
  en: 'Choose the customer address for this ride',
  fr: 'Choisissez l’adresse du client pour cette course',
  es: 'Elige la dirección del cliente para este viaje',
);

const LocalizedText kCompanyAgendaVehiclesLoading = LocalizedText(
  nl: 'Voertuigen worden geladen…',
  en: 'Loading vehicles…',
  fr: 'Chargement des véhicules…',
  es: 'Cargando vehículos…',
);

const LocalizedText kCompanyAgendaNoFleetVehicles = LocalizedText(
  nl: 'Dit bedrijf heeft geen boekbare voertuigen voor deze rit.',
  en: 'This company has no bookable vehicles for this ride.',
  fr: 'Cette entreprise n’a pas de véhicules pour cette course.',
  es: 'Esta empresa no tiene vehículos para este viaje.',
);

const LocalizedText kCompanyAgendaVehiclesLoadFailed = LocalizedText(
  nl: 'Voertuigen konden niet worden geladen. Probeer opnieuw.',
  en: 'Vehicles could not be loaded. Try again.',
  fr: 'Les véhicules n’ont pas pu être chargés. Réessayez.',
  es: 'No se pudieron cargar los vehículos. Inténtalo de nuevo.',
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
  nl: 'Handmatige totaalprijs',
  en: 'Manual total price',
  fr: 'Prix total manuel',
  es: 'Precio total manual',
);

const LocalizedText kCompanyAgendaDuration = LocalizedText(
  nl: 'Berekende ritduur',
  en: 'Calculated duration',
  fr: 'Durée calculée',
  es: 'Duración calculada',
);

const LocalizedText kCompanyAgendaRouteCalculating = LocalizedText(
  nl: 'Route berekenen…',
  en: 'Calculating route…',
  fr: 'Calcul de l’itinéraire…',
  es: 'Calculando la ruta…',
);

const LocalizedText kCompanyAgendaRouteRetry = LocalizedText(
  nl: 'Route opnieuw berekenen',
  en: 'Recalculate route',
  fr: 'Recalculer l’itinéraire',
  es: 'Recalcular la ruta',
);

const LocalizedText kCompanyAgendaManualDuration = LocalizedText(
  nl: 'Handmatige ritduur (uitzondering)',
  en: 'Manual duration (exception)',
  fr: 'Durée manuelle (exception)',
  es: 'Duración manual (excepción)',
);

const LocalizedText kCompanyAgendaManualDurationHint = LocalizedText(
  nl: 'Alleen gebruiken wanneer de berekende ritduur aantoonbaar fout is. Dit overschrijft de route-engine niet stilzwijgend.',
  en: 'Use only when the calculated duration is clearly wrong. This does not silently replace the routing engine.',
  fr: 'À utiliser seulement si la durée calculée est clairement fausse.',
  es: 'Úselo solo cuando la duración calculada sea claramente incorrecta.',
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

const LocalizedText kCompanyAgendaDriverInactiveAssign = LocalizedText(
  nl: 'Deze chauffeur is niet actief.',
  en: 'This driver is not active.',
  fr: 'Ce chauffeur n’est pas actif.',
  es: 'Este conductor no está activo.',
);

const LocalizedText kCompanyAgendaDriverBlocked = LocalizedText(
  nl: 'Deze chauffeur is geblokkeerd.',
  en: 'This driver is blocked.',
  fr: 'Ce chauffeur est bloqué.',
  es: 'Este conductor está bloqueado.',
);

const LocalizedText kCompanyAgendaDriverNotScheduled = LocalizedText(
  nl: 'Deze chauffeur werkt niet op het geplande tijdstip.',
  en: 'This driver is not scheduled at the planned time.',
  fr: 'Ce chauffeur n’est pas planifié à l’heure prévue.',
  es: 'Este conductor no está programado a esa hora.',
);

const LocalizedText kCompanyAgendaDriverPaused = LocalizedText(
  nl: 'Deze chauffeur staat op pauze.',
  en: 'This driver is paused.',
  fr: 'Ce chauffeur est en pause.',
  es: 'Este conductor está en pausa.',
);

const LocalizedText kCompanyAgendaDriverOnTrip = LocalizedText(
  nl: 'Deze chauffeur is al bezig met een rit.',
  en: 'This driver is already on a ride.',
  fr: 'Ce chauffeur est déjà en course.',
  es: 'Este conductor ya está en un viaje.',
);

const LocalizedText kCompanyAgendaDriverNotLive = LocalizedText(
  nl: 'Deze chauffeur heeft geen recente live verbinding.',
  en: 'This driver has no recent live connection.',
  fr: 'Ce chauffeur n’a pas de connexion live récente.',
  es: 'Este conductor no tiene conexión en vivo reciente.',
);

const LocalizedText kCompanyAgendaDriverNoVehicle = LocalizedText(
  nl: 'Deze chauffeur heeft geen vrij gekoppeld voertuig.',
  en: 'This driver has no free linked vehicle.',
  fr: 'Ce chauffeur n’a pas de véhicule lié libre.',
  es: 'Este conductor no tiene un vehículo vinculado libre.',
);

const LocalizedText kCompanyAgendaVehicleBusy = LocalizedText(
  nl: 'Dit voertuig hoort bij een andere actieve shift of rit.',
  en: 'This vehicle belongs to another active shift or ride.',
  fr: 'Ce véhicule appartient à une autre vacation ou course active.',
  es: 'Este vehículo pertenece a otro turno o viaje activo.',
);

const LocalizedText kCompanyAgendaVehicleChoiceRequired = LocalizedText(
  nl: 'Kies een van de vrije voertuigen van deze chauffeur.',
  en: 'Choose one of this driver’s free vehicles.',
  fr: 'Choisissez un des véhicules libres de ce chauffeur.',
  es: 'Elige uno de los vehículos libres de este conductor.',
);

const LocalizedText kCompanyAgendaRouteRequired = LocalizedText(
  nl: 'Vul een geldig vertrek en bestemming in.',
  en: 'Enter a valid pickup and destination.',
  fr: 'Saisissez un départ et une destination valides.',
  es: 'Introduce un origen y un destino válidos.',
);

const LocalizedText kCompanyAgendaCustomerRequired = LocalizedText(
  nl: 'Kies eerst een klant.',
  en: 'Choose a customer first.',
  fr: 'Choisissez d’abord un client.',
  es: 'Elige primero un cliente.',
);

const LocalizedText kCompanyAgendaSavedUnassigned = LocalizedText(
  nl: 'Rit bewaard zonder chauffeur. De toewijzing is niet doorgegaan.',
  en: 'Ride saved without a driver. The assignment did not go through.',
  fr: 'Course enregistrée sans chauffeur. L’attribution n’a pas abouti.',
  es: 'Viaje guardado sin conductor. La asignación no se aplicó.',
);

const LocalizedText kCompanyDriverPresenceAvailable = LocalizedText(
  nl: 'Beschikbaar',
  en: 'Available',
  fr: 'Disponible',
  es: 'Disponible',
);

const LocalizedText kCompanyDriverPresenceOnTrip = LocalizedText(
  nl: 'Bezig met rit',
  en: 'On a ride',
  fr: 'En course',
  es: 'En viaje',
);

const LocalizedText kCompanyDriverPresenceScheduledNoLive = LocalizedText(
  nl: 'Gepland actief · geen live verbinding',
  en: 'Scheduled active · no live connection',
  fr: 'Actif planifié · pas de connexion live',
  es: 'Activo planificado · sin conexión en vivo',
);

const LocalizedText kCompanyDriverPresencePaused = LocalizedText(
  nl: 'Pauze',
  en: 'Paused',
  fr: 'Pause',
  es: 'Pausa',
);

const LocalizedText kCompanyDriverPresenceOfflineWork = LocalizedText(
  nl: 'Niet aan het werk',
  en: 'Not working',
  fr: 'Pas en service',
  es: 'Fuera de servicio',
);

const LocalizedText kCompanyDriverPresenceLost = LocalizedText(
  nl: 'Verbinding verloren',
  en: 'Connection lost',
  fr: 'Connexion perdue',
  es: 'Conexión perdida',
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

const LocalizedText kCompanyAgendaLaterPickupInvalid = LocalizedText(
  nl: 'Kies een datum en tijd die niet in het verleden liggen.',
  en: 'Choose a date and time that are not in the past.',
  fr: 'Choisissez une date et une heure qui ne sont pas passées.',
  es: 'Elija una fecha y hora que no estén en el pasado.',
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
  nl: 'Kies Nieuwe rit of een tijdstip om te plannen.',
  en: 'Choose New ride or a time slot to plan.',
  fr: 'Choisissez Nouvelle course ou un horaire.',
  es: 'Elige Nuevo viaje o una hora para planificar.',
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

const LocalizedText kCompanyDriversNowLiveLink = LocalizedText(
  nl: 'Live-verbinding',
  en: 'Live connection',
  fr: 'Connexion en direct',
  es: 'Conexión en vivo',
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

/// Makes explicit that the timestamp is the driver's own last signal, not the
/// moment the screen was refreshed.
const LocalizedText kCompanyDriverSignalAt = LocalizedText(
  nl: 'Laatste signaal chauffeur',
  en: 'Last driver signal',
  fr: 'Dernier signal chauffeur',
  es: 'Última señal del conductor',
);

const LocalizedText kCompanyDriverSignalNever = LocalizedText(
  nl: 'nog geen signaal',
  en: 'no signal yet',
  fr: 'aucun signal',
  es: 'sin señal',
);

const LocalizedText kCompanyDriverConnectionLost = LocalizedText(
  nl: 'Verbinding verouderd',
  en: 'Connection stale',
  fr: 'Connexion obsolète',
  es: 'Conexión obsoleta',
);

const LocalizedText kCompanyDriverConnectionUnknown = LocalizedText(
  nl: 'Verbinding onbekend',
  en: 'Connection unknown',
  fr: 'Connexion inconnue',
  es: 'Conexión desconocida',
);

const LocalizedText kCompanyDriverDutyLabel = LocalizedText(
  nl: 'Dienst',
  en: 'Duty',
  fr: 'Service',
  es: 'Servicio',
);

const LocalizedText kCompanyDriverDutyWorking = LocalizedText(
  nl: 'Aan het werk',
  en: 'Working',
  fr: 'En service',
  es: 'Trabajando',
);

const LocalizedText kCompanyDriverDutyEnded = LocalizedText(
  nl: 'Dienst beëindigd',
  en: 'Duty ended',
  fr: 'Service terminé',
  es: 'Servicio finalizado',
);

const LocalizedText kCompanyDriverDutyUnknown = LocalizedText(
  nl: 'Dienst onbekend',
  en: 'Duty unknown',
  fr: 'Service inconnu',
  es: 'Servicio desconocido',
);

const LocalizedText kCompanyDriverPlanningLabel = LocalizedText(
  nl: 'Planning',
  en: 'Schedule',
  fr: 'Planning',
  es: 'Horario',
);

const LocalizedText kCompanyDriverPlanningNone = LocalizedText(
  nl: 'Geen rooster ingesteld',
  en: 'No schedule set',
  fr: 'Aucun horaire défini',
  es: 'Sin horario definido',
);

const LocalizedText kCompanyDriverPlanningOffHours = LocalizedText(
  nl: 'Buiten werkuren',
  en: 'Outside working hours',
  fr: 'Hors heures de travail',
  es: 'Fuera del horario',
);

const LocalizedText kCompanyDriverPlanningAbsent = LocalizedText(
  nl: 'Afwezig vandaag',
  en: 'Absent today',
  fr: 'Absent aujourd’hui',
  es: 'Ausente hoy',
);

const LocalizedText kCompanyDriverPlanningBreak = LocalizedText(
  nl: 'Geplande pauze',
  en: 'Planned break',
  fr: 'Pause planifiée',
  es: 'Pausa planificada',
);

const LocalizedText kCompanyDriverScheduleTitle = LocalizedText(
  nl: 'Uurrooster',
  en: 'Working hours',
  fr: 'Horaire',
  es: 'Horario',
);

const LocalizedText kCompanyDriverScheduleTimezone = LocalizedText(
  nl: 'Bedrijfstijdzone',
  en: 'Company timezone',
  fr: 'Fuseau horaire',
  es: 'Zona horaria',
);

const LocalizedText kCompanyDriverScheduleTimezoneUnresolved = LocalizedText(
  nl: 'Deze tijdzone wordt niet ondersteund. De werkuren worden niet gebruikt '
      'voor beschikbaarheid of toewijzing.',
  en: 'This timezone is not supported. The working hours are not used for '
      'availability or assignment.',
  fr: 'Ce fuseau horaire n’est pas pris en charge. Les heures ne servent pas '
      'à la disponibilité ni à l’affectation.',
  es: 'Esta zona horaria no es compatible. El horario no se usa para la '
      'disponibilidad ni la asignación.',
);

const LocalizedText kCompanyDriverScheduleReadOnly = LocalizedText(
  nl: 'Je bekijkt je eigen rooster. Alleen de bedrijfsbeheerder kan het '
      'aanpassen.',
  en: 'You are viewing your own schedule. Only the company administrator can '
      'change it.',
  fr: 'Vous consultez votre propre horaire. Seul l’administrateur peut le '
      'modifier.',
  es: 'Estás viendo tu propio horario. Solo el administrador puede cambiarlo.',
);

const LocalizedText kCompanyDriverScheduleSave = LocalizedText(
  nl: 'Rooster bewaren',
  en: 'Save schedule',
  fr: 'Enregistrer l’horaire',
  es: 'Guardar horario',
);

const LocalizedText kCompanyDriverScheduleSaveUnavailable = LocalizedText(
  nl: 'Bewaren is nog niet beschikbaar. Het rooster kan hier al worden '
      'opgesteld, maar wordt nog nergens opgeslagen.',
  en: 'Saving is not available yet. The schedule can be composed here, but it '
      'is not stored anywhere.',
  fr: 'L’enregistrement n’est pas encore disponible. L’horaire peut être '
      'composé ici, mais il n’est stocké nulle part.',
  es: 'Guardar aún no está disponible. El horario puede componerse aquí, pero '
      'no se almacena en ningún sitio.',
);

const LocalizedText kCompanyDriverScheduleAddBlock = LocalizedText(
  nl: 'Werkblok',
  en: 'Add block',
  fr: 'Ajouter un bloc',
  es: 'Añadir bloque',
);

const LocalizedText kCompanyDriverScheduleRemoveBlock = LocalizedText(
  nl: 'Werkblok verwijderen',
  en: 'Remove block',
  fr: 'Supprimer le bloc',
  es: 'Eliminar bloque',
);

const LocalizedText kCompanyDriverScheduleDayOff = LocalizedText(
  nl: 'Geen werkuren',
  en: 'No working hours',
  fr: 'Pas d’heures de travail',
  es: 'Sin horas de trabajo',
);

const LocalizedText kCompanyDriverScheduleOvernight = LocalizedText(
  nl: 'nachtdienst',
  en: 'overnight',
  fr: 'de nuit',
  es: 'nocturno',
);

const LocalizedText kCompanyDriverScheduleExceptions = LocalizedText(
  nl: 'Uitzonderingen',
  en: 'Exceptions',
  fr: 'Exceptions',
  es: 'Excepciones',
);

const LocalizedText kCompanyDriverScheduleStartTime = LocalizedText(
  nl: 'Starttijd',
  en: 'Start time',
  fr: 'Heure de début',
  es: 'Hora de inicio',
);

const LocalizedText kCompanyDriverScheduleEndTime = LocalizedText(
  nl: 'Eindtijd',
  en: 'End time',
  fr: 'Heure de fin',
  es: 'Hora de fin',
);

const LocalizedText kCompanyDriverScheduleMonday = LocalizedText(
  nl: 'Maandag', en: 'Monday', fr: 'Lundi', es: 'Lunes');
const LocalizedText kCompanyDriverScheduleTuesday = LocalizedText(
  nl: 'Dinsdag', en: 'Tuesday', fr: 'Mardi', es: 'Martes');
const LocalizedText kCompanyDriverScheduleWednesday = LocalizedText(
  nl: 'Woensdag', en: 'Wednesday', fr: 'Mercredi', es: 'Miércoles');
const LocalizedText kCompanyDriverScheduleThursday = LocalizedText(
  nl: 'Donderdag', en: 'Thursday', fr: 'Jeudi', es: 'Jueves');
const LocalizedText kCompanyDriverScheduleFriday = LocalizedText(
  nl: 'Vrijdag', en: 'Friday', fr: 'Vendredi', es: 'Viernes');
const LocalizedText kCompanyDriverScheduleSaturday = LocalizedText(
  nl: 'Zaterdag', en: 'Saturday', fr: 'Samedi', es: 'Sábado');
const LocalizedText kCompanyDriverScheduleSunday = LocalizedText(
  nl: 'Zondag', en: 'Sunday', fr: 'Dimanche', es: 'Domingo');

/// Shown beside the stored assignment while a different crew is selected but
/// the server has not accepted the change yet.
const LocalizedText kCompanyAgendaAssignmentPendingChange = LocalizedText(
  nl: 'Nog te bevestigen keuze',
  en: 'Selected, not confirmed yet',
  fr: 'Choix à confirmer',
  es: 'Selección sin confirmar',
);

const LocalizedText kCompanyDriverScheduleUndeterminable = LocalizedText(
  nl: 'Roosterbeschikbaarheid niet vast te stellen',
  en: 'Schedule availability cannot be determined',
  fr: 'Disponibilité horaire indéterminable',
  es: 'No se puede determinar la disponibilidad del horario',
);

const LocalizedText kCompanyDriverConflictOutsideHours = LocalizedText(
  nl: 'Buiten werkuren',
  en: 'Outside working hours',
  fr: 'Hors heures de travail',
  es: 'Fuera del horario',
);

const LocalizedText kCompanyDriverConflictBreak = LocalizedText(
  nl: 'Overlapt met geplande pauze',
  en: 'Overlaps a planned break',
  fr: 'Chevauche une pause planifiée',
  es: 'Se solapa con una pausa planificada',
);

const LocalizedText kCompanyDriverConflictAbsent = LocalizedText(
  nl: 'Afwezig op die datum',
  en: 'Absent on that date',
  fr: 'Absent à cette date',
  es: 'Ausente en esa fecha',
);

const LocalizedText kCompanyDriverConflictEndsAfterHours = LocalizedText(
  nl: 'Rit eindigt na de werkuren',
  en: 'Ride ends after working hours',
  fr: 'La course finit après les heures',
  es: 'El viaje termina fuera del horario',
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
  nl: 'Terug naar',
  en: 'Return to',
  fr: 'Retour vers',
  es: 'Vuelta a',
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

const LocalizedText kCompanyAgendaWaitTime = LocalizedText(
  nl: 'Wachttijd',
  en: 'Waiting time',
  fr: 'Temps d’attente',
  es: 'Tiempo de espera',
);

const LocalizedText kCompanyAgendaDriverWaitsAbout = LocalizedText(
  nl: 'Chauffeur wacht ongeveer {min} minuten',
  en: 'Driver waits about {min} minutes',
  fr: 'Le chauffeur attend environ {min} minutes',
  es: 'El conductor espera unos {min} minutos',
);

const LocalizedText kCompanyAgendaAddStop = LocalizedText(
  nl: 'Tussenstop toevoegen',
  en: 'Add a stop',
  fr: 'Ajouter un arrêt',
  es: 'Añadir una parada',
);

const LocalizedText kCompanyAgendaWaitManual = LocalizedText(
  nl: 'Andere wachttijd (minuten)',
  en: 'Other waiting time (minutes)',
  fr: 'Autre temps d’attente (minutes)',
  es: 'Otro tiempo de espera (minutos)',
);

const LocalizedText kCompanyAgendaEstimatedArrival = LocalizedText(
  nl: 'Geschatte aankomst',
  en: 'Estimated arrival',
  fr: 'Arrivée estimée',
  es: 'Llegada estimada',
);

const LocalizedText kCompanyAgendaTypeUnavailable = LocalizedText(
  nl: 'Niet beschikbaar',
  en: 'Unavailable',
  fr: 'Indisponible',
  es: 'No disponible',
);

const LocalizedText kCompanyAgendaCustomerConfirmTitle = LocalizedText(
  nl: 'Uw rit',
  en: 'Your ride',
  fr: 'Votre trajet',
  es: 'Su viaje',
);

const LocalizedText kCompanyAgendaTechnicalDetails = LocalizedText(
  nl: 'Technische details',
  en: 'Technical details',
  fr: 'Détails techniques',
  es: 'Detalles técnicos',
);

const LocalizedText kCompanyAgendaBackToQuoteHint = LocalizedText(
  nl: 'Terug gaat naar de offerte',
  en: 'Back returns to the quote',
  fr: 'Retour ouvre le devis',
  es: 'Atrás vuelve al presupuesto',
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

const LocalizedText kCompanyAgendaWhenNow = LocalizedText(
  nl: 'Nu',
  en: 'Now',
  fr: 'Maintenant',
  es: 'Ahora',
);

const LocalizedText kCompanyAgendaWhenLater = LocalizedText(
  nl: 'Later',
  en: 'Later',
  fr: 'Plus tard',
  es: 'Más tarde',
);

const LocalizedText kCompanyAgendaCustomer = LocalizedText(
  nl: 'Klant',
  en: 'Customer',
  fr: 'Client',
  es: 'Cliente',
);

const LocalizedText kCompanyAgendaCustomerSearch = LocalizedText(
  nl: 'Zoek of voeg een klant toe',
  en: 'Search or add a customer',
  fr: 'Rechercher ou ajouter un client',
  es: 'Buscar o añadir un cliente',
);

const LocalizedText kCompanyAgendaCustomerAdd = LocalizedText(
  nl: 'Klant toevoegen',
  en: 'Add customer',
  fr: 'Ajouter un client',
  es: 'Añadir cliente',
);

const LocalizedText kCompanyAgendaPickupPlace = LocalizedText(
  nl: 'Vertrek',
  en: 'Pickup',
  fr: 'Départ',
  es: 'Salida',
);

const LocalizedText kCompanyAgendaDropoffPlace = LocalizedText(
  nl: 'Bestemming',
  en: 'Destination',
  fr: 'Destination',
  es: 'Destino',
);

const LocalizedText kCompanyRoundtripReturnToPlace = LocalizedText(
  nl: 'Terug naar',
  en: 'Return to',
  fr: 'Retour vers',
  es: 'Vuelta a',
);

const LocalizedText kCompanyAgendaAddReturnStop = LocalizedText(
  nl: 'Tussenstop terugrit toevoegen',
  en: 'Add a return stop',
  fr: 'Ajouter un arrêt au retour',
  es: 'Añadir parada de vuelta',
);

const LocalizedText kCompanyAgendaStopLabel = LocalizedText(
  nl: 'Tussenstop {n}',
  en: 'Stop {n}',
  fr: 'Arrêt {n}',
  es: 'Parada {n}',
);

const LocalizedText kCompanyAgendaStopCount = LocalizedText(
  nl: '{n}/10 tussenstops',
  en: '{n}/10 stops',
  fr: '{n}/10 arrêts',
  es: '{n}/10 paradas',
);

const LocalizedText kCompanyAgendaRestoreRoute = LocalizedText(
  nl: 'Route herstellen',
  en: 'Restore route',
  fr: 'Rétablir l’itinéraire',
  es: 'Restaurar ruta',
);

const LocalizedText kCompanyAgendaRouteMissingCompact = LocalizedText(
  nl: 'Geen bruikbare routecoördinaten voor deze adressen.',
  en: 'No usable route coordinates for these addresses.',
  fr: 'Pas de coordonnées d’itinéraire utilisables pour ces adresses.',
  es: 'No hay coordenadas de ruta utilizables para estas direcciones.',
);

const LocalizedText kCompanyAgendaSameCrewIfAvailable = LocalizedText(
  nl: 'Zelfde chauffeur en voertuig indien beschikbaar',
  en: 'Same driver and vehicle if available',
  fr: 'Même chauffeur et véhicule si disponible',
  es: 'Mismo conductor y vehículo si está disponible',
);

const LocalizedText kCompanyAgendaAssignmentOutbound = LocalizedText(
  nl: 'Heenrit A → B',
  en: 'Outbound A → B',
  fr: 'Aller A → B',
  es: 'Ida A → B',
);

const LocalizedText kCompanyAgendaAssignmentReturn = LocalizedText(
  nl: 'Terugrit B → A',
  en: 'Return B → A',
  fr: 'Retour B → A',
  es: 'Vuelta B → A',
);

const LocalizedText kCompanyAgendaAssignmentSingle = LocalizedText(
  nl: 'Toewijzing rit A → B',
  en: 'Assignment A → B',
  fr: 'Attribution A → B',
  es: 'Asignación A → B',
);

const LocalizedText kCompanyAgendaRouteCard = LocalizedText(
  nl: 'Route',
  en: 'Route',
  fr: 'Itinéraire',
  es: 'Ruta',
);

const LocalizedText kCompanyAgendaRideFacts = LocalizedText(
  nl: 'Ritgegevens',
  en: 'Ride details',
  fr: 'Détails du trajet',
  es: 'Datos del viaje',
);

const LocalizedText kCompanyAgendaPriceCard = LocalizedText(
  nl: 'Prijs',
  en: 'Price',
  fr: 'Prix',
  es: 'Precio',
);

const LocalizedText kCompanyAgendaQuoteTotal = LocalizedText(
  nl: 'Totaal',
  en: 'Total',
  fr: 'Total',
  es: 'Total',
);

const LocalizedText kCompanyAgendaVehicleType = LocalizedText(
  nl: 'Voertuigtype',
  en: 'Vehicle type',
  fr: 'Type de véhicule',
  es: 'Tipo de vehículo',
);

const LocalizedText kCompanyAgendaVehicleTypeSedan = LocalizedText(
  nl: 'Sedan',
  en: 'Sedan',
  fr: 'Berline',
  es: 'Sedán',
);

const LocalizedText kCompanyAgendaVehicleTypeMinivan = LocalizedText(
  nl: 'Minivan',
  en: 'Minivan',
  fr: 'Minivan',
  es: 'Monovolumen',
);

const LocalizedText kCompanyAgendaAirportMode = LocalizedText(
  nl: 'Luchthavenrit',
  en: 'Airport ride',
  fr: 'Course aéroport',
  es: 'Viaje al aeropuerto',
);

const LocalizedText kCompanyAgendaAirportModeHint = LocalizedText(
  nl: 'Vlucht en bagage',
  en: 'Flight and baggage',
  fr: 'Vol et bagages',
  es: 'Vuelo y equipaje',
);

const LocalizedText kCompanyAgendaAirportNeedsVehicle = LocalizedText(
  nl: 'Kies nog een voertuigtype voor deze luchthavenrit.',
  en: 'Still choose a vehicle type for this airport ride.',
  fr: 'Choisissez encore un type de véhicule pour cette course aéroport.',
  es: 'Elige todavía un tipo de vehículo para este viaje de aeropuerto.',
);

const LocalizedText kCompanyAgendaFromAirport = LocalizedText(
  nl: 'Van de luchthaven',
  en: 'From the airport',
  fr: 'Depuis l’aéroport',
  es: 'Desde el aeropuerto',
);

const LocalizedText kCompanyAgendaOtherAirport = LocalizedText(
  nl: 'Andere luchthaven',
  en: 'Other airport',
  fr: 'Autre aéroport',
  es: 'Otro aeropuerto',
);

const LocalizedText kCompanyAgendaProposedDriver = LocalizedText(
  nl: 'Voorgestelde chauffeur',
  en: 'Suggested driver',
  fr: 'Chauffeur proposé',
  es: 'Conductor propuesto',
);

const LocalizedText kCompanyAgendaMoreOptions = LocalizedText(
  nl: 'Meer opties',
  en: 'More options',
  fr: 'Plus d’options',
  es: 'Más opciones',
);

const LocalizedText kCompanyAgendaBusyUntil = LocalizedText(
  nl: 'Bezig tot',
  en: 'Busy until',
  fr: 'Occupé jusqu’à',
  es: 'Ocupado hasta',
);

const LocalizedText kCompanyAgendaOffDuty = LocalizedText(
  nl: 'Buiten dienst',
  en: 'Off duty',
  fr: 'Hors service',
  es: 'Fuera de servicio',
);

const LocalizedText kCompanyAgendaVehicleOccupied = LocalizedText(
  nl: 'Voertuig bezet',
  en: 'Vehicle occupied',
  fr: 'Véhicule occupé',
  es: 'Vehículo ocupado',
);

const LocalizedText kCompanyAgendaCapacityShort = LocalizedText(
  nl: 'Onvoldoende capaciteit',
  en: 'Not enough capacity',
  fr: 'Capacité insuffisante',
  es: 'Capacidad insuficiente',
);

const LocalizedText kCompanyAgendaCannotReachPickup = LocalizedText(
  nl: 'Kan ophaallocatie niet tijdig bereiken',
  en: 'Cannot reach the pickup in time',
  fr: 'Ne peut pas rejoindre la prise en charge à temps',
  es: 'No puede llegar a tiempo al punto de recogida',
);

const LocalizedText kCompanyAgendaUnsuitableDrivers = LocalizedText(
  nl: 'Niet-inzetbare chauffeurs',
  en: 'Unavailable drivers',
  fr: 'Chauffeurs non disponibles',
  es: 'Conductores no disponibles',
);

const LocalizedText kCompanyAgendaVehicleCategoryCompact = LocalizedText(
  nl: 'Compact',
  en: 'Compact',
  fr: 'Compacte',
  es: 'Compacto',
);

const LocalizedText kCompanyAgendaVehicleCategoryBreak = LocalizedText(
  nl: 'Break',
  en: 'Estate',
  fr: 'Break',
  es: 'Familiar',
);

const LocalizedText kCompanyAgendaVehicleCategorySuv = LocalizedText(
  nl: 'SUV',
  en: 'SUV',
  fr: 'SUV',
  es: 'SUV',
);

const LocalizedText kCompanyAgendaVehicleCategoryMinibus = LocalizedText(
  nl: 'Minibus',
  en: 'Minibus',
  fr: 'Minibus',
  es: 'Minibús',
);

const LocalizedText kCompanyAgendaVehicleCategoryPremium = LocalizedText(
  nl: 'Premium',
  en: 'Premium',
  fr: 'Premium',
  es: 'Premium',
);

const LocalizedText kCompanyAgendaVehicleCategoryWheelchair = LocalizedText(
  nl: 'Toegankelijk',
  en: 'Accessible',
  fr: 'Accessible',
  es: 'Accesible',
);

const LocalizedText kCompanyAgendaBadgeElectric = LocalizedText(
  nl: 'Elektrisch',
  en: 'Electric',
  fr: 'Électrique',
  es: 'Eléctrico',
);

const LocalizedText kCompanyAgendaBadgeBags = LocalizedText(
  nl: 'Extra bagage',
  en: 'Extra luggage',
  fr: 'Bagages extra',
  es: 'Equipaje extra',
);

const LocalizedText kCompanyAgendaBadgeChildSeat = LocalizedText(
  nl: 'Kinderstoel',
  en: 'Child seat',
  fr: 'Siège enfant',
  es: 'Silla infantil',
);

const LocalizedText kCompanyAgendaBadgePets = LocalizedText(
  nl: 'Huisdieren',
  en: 'Pets',
  fr: 'Animaux',
  es: 'Mascotas',
);

const LocalizedText kCompanyAgendaBadgePremium = LocalizedText(
  nl: 'Premium',
  en: 'Premium',
  fr: 'Premium',
  es: 'Premium',
);

const LocalizedText kCompanyAgendaBadgeAccessible = LocalizedText(
  nl: 'Toegankelijk',
  en: 'Accessible',
  fr: 'Accessible',
  es: 'Accesible',
);

const LocalizedText kCompanyAgendaSearchOtherAirport = LocalizedText(
  nl: 'Zoek andere luchthaven',
  en: 'Search another airport',
  fr: 'Rechercher un autre aéroport',
  es: 'Buscar otro aeropuerto',
);

const LocalizedText kCompanyAgendaConfirmRide = LocalizedText(
  nl: 'Bevestig rit',
  en: 'Confirm ride',
  fr: 'Confirmer la course',
  es: 'Confirmar viaje',
);

const LocalizedText kCompanyAgendaPriceBreakdown = LocalizedText(
  nl: 'Bekijk prijsopbouw',
  en: 'View price breakdown',
  fr: 'Voir le détail du prix',
  es: 'Ver desglose del precio',
);

const LocalizedText kCompanyAgendaPriceBreakdownUnavailable = LocalizedText(
  nl: 'Geen prijsopbouw beschikbaar voor deze rit. Het overeengekomen bedrag blijft ongewijzigd.',
  en: 'No price breakdown is available for this ride. The agreed amount is unchanged.',
  fr: 'Aucun détail de prix n’est disponible pour cette course. Le montant convenu reste inchangé.',
  es: 'No hay desglose de precio para este viaje. El importe acordado no cambia.',
);

const LocalizedText kCompanyAgendaPriceAmountMissing = LocalizedText(
  nl: 'Geen opgeslagen prijs gevonden voor deze rit.',
  en: 'No stored price was found for this ride.',
  fr: 'Aucun prix enregistré n’a été trouvé pour cette course.',
  es: 'No se encontró un precio guardado para este viaje.',
);

const LocalizedText kCompanyAgendaDriverFallback = LocalizedText(
  nl: 'Chauffeur',
  en: 'Driver',
  fr: 'Chauffeur',
  es: 'Conductor',
);

const LocalizedText kCompanyAgendaVehicleFallback = LocalizedText(
  nl: 'Voertuig',
  en: 'Vehicle',
  fr: 'Véhicule',
  es: 'Vehículo',
);

const LocalizedText kCompanyAgendaFlightAfterPickup = LocalizedText(
  nl: 'De ophaaltijd ligt na het vluchtvertrek.',
  en: 'Pickup is after the flight departure.',
  fr: 'L’heure de prise en charge est après le départ du vol.',
  es: 'La recogida es posterior a la salida del vuelo.',
);

const LocalizedText kCompanyAgendaLandingNotPickup = LocalizedText(
  nl: 'Landingstijd is niet automatisch de ophaaltijd.',
  en: 'Landing time is not automatically the pickup time.',
  fr: 'L’heure d’atterrissage n’est pas automatiquement l’heure de prise en charge.',
  es: 'La hora de aterrizaje no es automáticamente la hora de recogida.',
);

const LocalizedText kCompanyAgendaCapacityUnsuitable = LocalizedText(
  nl: 'Dit voertuigtype past niet bij het aantal passagiers of bagage.',
  en: 'This vehicle type does not fit the passenger or baggage count.',
  fr: 'Ce type de véhicule ne convient pas au nombre de passagers ou de bagages.',
  es: 'Este tipo de vehículo no cabe con el número de pasajeros o maletas.',
);

const LocalizedText kCompanyAgendaSuggestedPickup = LocalizedText(
  nl: 'Geadviseerde ophaaltijd: {time}',
  en: 'Suggested pickup time: {time}',
  fr: 'Heure de prise en charge conseillée : {time}',
  es: 'Hora de recogida aconsejada: {time}',
);

const LocalizedText kCompanyAgendaCapacitySuggest = LocalizedText(
  nl: 'Kies {type} voor dit aantal passagiers of bagage.',
  en: 'Choose {type} for this passenger or baggage count.',
  fr: 'Choisissez {type} pour ce nombre de passagers ou de bagages.',
  es: 'Elija {type} para este número de pasajeros o maletas.',
);

const LocalizedText kCompanyAgendaRegularRide = LocalizedText(
  nl: 'Gewoon vervoer',
  en: 'Regular ride',
  fr: 'Course classique',
  es: 'Viaje normal',
);

const LocalizedText kCompanyAgendaReturnSummary = LocalizedText(
  nl: 'Terugrit: {from} → {to}',
  en: 'Return: {from} → {to}',
  fr: 'Retour : {from} → {to}',
  es: 'Vuelta: {from} → {to}',
);

const LocalizedText kCompanyAgendaFreeAt = LocalizedText(
  nl: 'Vrij om {time}',
  en: 'Free at {time}',
  fr: 'Libre à {time}',
  es: 'Libre a las {time}',
);

const LocalizedText kCompanyAgendaBusyMaybeFree = LocalizedText(
  nl: 'Bezig, mogelijk vrij om {time}',
  en: 'Busy, possibly free at {time}',
  fr: 'Occupé, éventuellement libre à {time}',
  es: 'Ocupado, posiblemente libre a las {time}',
);

const LocalizedText kCompanyAgendaOverlapBlocked = LocalizedText(
  nl: 'Niet beschikbaar — overlappende rit',
  en: 'Unavailable — overlapping ride',
  fr: 'Indisponible — course en chevauchement',
  es: 'No disponible — viaje solapado',
);

const LocalizedText kCompanyAgendaWaitPrice = LocalizedText(
  nl: 'Wachttijd',
  en: 'Waiting time',
  fr: 'Temps d’attente',
  es: 'Tiempo de espera',
);

const LocalizedText kCompanyAgendaBagsPrice = LocalizedText(
  nl: 'Bagage',
  en: 'Baggage',
  fr: 'Bagages',
  es: 'Equipaje',
);

const LocalizedText kCompanyAgendaStartFee = LocalizedText(
  nl: 'Starttarief',
  en: 'Start fare',
  fr: 'Tarif de départ',
  es: 'Tarifa de salida',
);

const LocalizedText kCompanyAgendaPriceInvalid = LocalizedText(
  nl: 'De prijsberekening is ongeldig. Boeken is geblokkeerd tot de quote klopt.',
  en: 'The price calculation is invalid. Booking is blocked until the quote is correct.',
  fr: 'Le calcul du prix est invalide. La réservation est bloquée tant que le devis n’est pas correct.',
  es: 'El cálculo del precio no es válido. La reserva queda bloqueada hasta que la cotización sea correcta.',
);

const LocalizedText kCompanyAgendaQuoteUnavailable = LocalizedText(
  nl: 'De route is berekend, maar er is geen prijs beschikbaar. Een afstand is geen offerte.',
  en: 'The route was calculated, but no price is available. A distance is not a quote.',
  fr: 'L’itinéraire a été calculé, mais aucun prix n’est disponible. Une distance n’est pas un devis.',
  es: 'La ruta se calculó, pero no hay precio disponible. Una distancia no es un presupuesto.',
);

const LocalizedText kCompanyAgendaSameCrewUnavailable = LocalizedText(
  nl: 'Dezelfde combinatie is niet beschikbaar voor de terugrit.',
  en: 'The same combination is not available for the return ride.',
  fr: 'La même combinaison n’est pas disponible pour le retour.',
  es: 'La misma combinación no está disponible para la vuelta.',
);

const LocalizedText kCompanyAgendaAssignmentContinuous = LocalizedText(
  nl: 'Heenrit + wachten + terugrit',
  en: 'Outbound + wait + return',
  fr: 'Aller + attente + retour',
  es: 'Ida + espera + vuelta',
);

const LocalizedText kCompanyAgendaCrewSearch = LocalizedText(
  nl: 'Zoek chauffeur of voertuig',
  en: 'Search driver or vehicle',
  fr: 'Rechercher chauffeur ou véhicule',
  es: 'Buscar conductor o vehículo',
);

const LocalizedText kCompanyAgendaCrewChoose = LocalizedText(
  nl: 'Kies chauffeur en voertuig',
  en: 'Choose driver and vehicle',
  fr: 'Choisir chauffeur et véhicule',
  es: 'Elegir conductor y vehículo',
);

const LocalizedText kCompanyAgendaCrewVehicleCount = LocalizedText(
  nl: '{count} voertuigen',
  en: '{count} vehicles',
  fr: '{count} véhicules',
  es: '{count} vehículos',
);
