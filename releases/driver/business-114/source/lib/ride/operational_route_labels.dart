import '../app_strings.dart';

const kOperationalRouteEdit = LocalizedText(
  nl: 'Bestemming wijzigen',
  en: 'Change destination',
  fr: 'Modifier la destination',
  es: 'Cambiar destino',
  de: 'Ziel ändern',
);
const kOperationalRouteDestination = LocalizedText(
  nl: 'Nieuwe bestemming',
  en: 'New destination',
  fr: 'Nouvelle destination',
  es: 'Nuevo destino',
  de: 'Neues Ziel',
);
const kOperationalRouteMinutes = LocalizedText(
  nl: 'Nog nodig voor deze rit (minuten)',
  en: 'Time remaining for this ride (minutes)',
  fr: 'Temps restant pour cette course (minutes)',
  es: 'Tiempo restante para este viaje (minutos)',
  de: 'Verbleibende Zeit für diese Fahrt (Minuten)',
);
const kOperationalRouteExplanation = LocalizedText(
  nl: 'Kies de nieuwe bestemming en schat wanneer deze rit klaar is. De planning van volgende ritten wordt opnieuw bekeken.',
  en: 'Select the new destination and estimate when this ride will finish. Upcoming rides will be reviewed.',
  fr: 'Choisissez la nouvelle destination et estimez la fin de cette course. Les courses suivantes seront réévaluées.',
  es: 'Selecciona el nuevo destino y estima cuándo terminará este viaje. Se revisarán los siguientes viajes.',
  de: 'Wählen Sie das neue Ziel und schätzen Sie das Fahrtende. Die nächsten Fahrten werden neu geprüft.',
);
const kOperationalRouteSave = LocalizedText(
  nl: 'Wijziging doorgeven',
  en: 'Submit change',
  fr: 'Transmettre la modification',
  es: 'Enviar cambio',
  de: 'Änderung senden',
);
const kOperationalRouteRetry = LocalizedText(
  nl: 'Opnieuw proberen',
  en: 'Retry',
  fr: 'Réessayer',
  es: 'Reintentar',
  de: 'Erneut versuchen',
);
const kOperationalRoutePending = LocalizedText(
  nl: 'De bevestiging ontbreekt. Probeer dezelfde wijziging opnieuw.',
  en: 'Confirmation is missing. Retry the same change.',
  fr: 'La confirmation manque. Réessayez la même modification.',
  es: 'Falta la confirmación. Reintenta el mismo cambio.',
  de: 'Die Bestätigung fehlt. Versuchen Sie dieselbe Änderung erneut.',
);
const kOperationalRouteInvalid = LocalizedText(
  nl: 'Selecteer een adres en vul 1 tot 1440 minuten in.',
  en: 'Select an address and enter 1 to 1440 minutes.',
  fr: 'Sélectionnez une adresse et saisissez 1 à 1440 minutes.',
  es: 'Selecciona una dirección e introduce de 1 a 1440 minutos.',
  de: 'Wählen Sie eine Adresse und geben Sie 1 bis 1440 Minuten ein.',
);
const kOperationalRouteChanged = LocalizedText(
  nl: 'Gewijzigde bestemming',
  en: 'Updated destination',
  fr: 'Destination modifiée',
  es: 'Destino actualizado',
  de: 'Geändertes Ziel',
);
const kOperationalRouteEnd = LocalizedText(
  nl: 'Verwacht einde rit',
  en: 'Expected ride end',
  fr: 'Fin prévue de la course',
  es: 'Fin previsto del viaje',
  de: 'Voraussichtliches Fahrtende',
);

const kOperationalStops = LocalizedText(
  nl: 'Resterende tussenstops in volgorde',
  en: 'Remaining stops in order',
  fr: 'Arrêts restants dans l’ordre',
  es: 'Paradas restantes en orden',
  de: 'Verbleibende Stopps in Reihenfolge',
);
const kOperationalAddStop = LocalizedText(
  nl: 'Tussenstop toevoegen',
  en: 'Add stop',
  fr: 'Ajouter un arrêt',
  es: 'Añadir parada',
  de: 'Stopp hinzufügen',
);
const kOperationalStopWait = LocalizedText(
  nl: 'Wachttijd op deze stop (minuten)',
  en: 'Wait at this stop (minutes)',
  fr: 'Attente à cet arrêt (minutes)',
  es: 'Espera en esta parada (minutos)',
  de: 'Wartezeit an diesem Stopp (Minuten)',
);
const kOperationalNotBefore = LocalizedText(
  nl: 'Vertrek niet vóór',
  en: 'Depart no earlier than',
  fr: 'Départ pas avant',
  es: 'Salida no antes de',
  de: 'Abfahrt frühestens',
);
const kOperationalComplete = LocalizedText(
  nl: 'Dit is de volledige resterende route, inclusief terugrit en wachttijden.',
  en: 'This is the complete remaining route, including the return ride and waiting times.',
  fr: 'Ceci est tout le trajet restant, y compris le retour et les temps d’attente.',
  es: 'Esta es toda la ruta restante, incluido el regreso y las esperas.',
  de: 'Dies ist die gesamte verbleibende Route einschließlich Rückfahrt und Wartezeiten.',
);
const kOperationalItineraryInvalid = LocalizedText(
  nl: 'Controleer alle stopadressen, wachttijden en de volledige route. Maximaal 8 tussenstops.',
  en: 'Check every stop address, waiting time and the complete route. Up to 8 stops.',
  fr: 'Vérifiez les adresses, les attentes et le trajet complet. Maximum 8 arrêts.',
  es: 'Revisa las direcciones, esperas y ruta completa. Máximo 8 paradas.',
  de: 'Prüfen Sie Stoppadressen, Wartezeiten und die vollständige Route. Höchstens 8 Stopps.',
);
const kOperationalStopEarlier = LocalizedText(
  nl: 'Eerder in de route',
  en: 'Earlier in route',
  fr: 'Plus tôt dans le trajet',
  es: 'Antes en la ruta',
  de: 'Früher in der Route',
);
const kOperationalRemoveStop = LocalizedText(
  nl: 'Stop verwijderen',
  en: 'Remove stop',
  fr: 'Supprimer l’arrêt',
  es: 'Eliminar parada',
  de: 'Stopp entfernen',
);

String operationalRouteError(String code, AppLanguage language) {
  final label = switch (code) {
    'revision_conflict' || 'operational_update_conflict' => const LocalizedText(
      nl: 'De rit is intussen gewijzigd. Controleer de actuele gegevens en probeer opnieuw.',
      en: 'The ride has changed. Review the current details and retry.',
      fr: 'La course a changé. Vérifiez les données actuelles et réessayez.',
      es: 'El viaje ha cambiado. Revisa los datos actuales y reintenta.',
      de: 'Die Fahrt wurde geändert. Prüfen Sie die aktuellen Angaben und versuchen Sie es erneut.',
    ),
    'operational_route_complex' => const LocalizedText(
      nl: 'Deze rit heeft meerdere stops. Laat de planner de resterende route controleren.',
      en: 'This ride has multiple stops. Ask the planner to review the remaining route.',
      fr: 'Cette course comporte plusieurs arrêts. Demandez au planificateur de vérifier la suite.',
      es: 'Este viaje tiene varias paradas. Pide al planificador que revise la ruta restante.',
      de: 'Diese Fahrt hat mehrere Stopps. Lassen Sie die verbleibende Route prüfen.',
    ),
    'operational_ride_not_running' => const LocalizedText(
      nl: 'Deze rit is niet meer bezig. Vernieuw je ritten.',
      en: 'This ride is no longer in progress. Refresh your rides.',
      fr: 'Cette course n’est plus en cours. Actualisez vos courses.',
      es: 'Este viaje ya no está en curso. Actualiza tus viajes.',
      de: 'Diese Fahrt läuft nicht mehr. Aktualisieren Sie Ihre Fahrten.',
    ),
    'forbidden' => const LocalizedText(
      nl: 'Je chauffeursessie is gewijzigd. Open de rit opnieuw.',
      en: 'Your driver session has changed. Reopen the ride.',
      fr: 'Votre session chauffeur a changé. Rouvrez la course.',
      es: 'Tu sesión de conductor ha cambiado. Vuelve a abrir el viaje.',
      de: 'Ihre Fahrersitzung wurde geändert. Öffnen Sie die Fahrt erneut.',
    ),
    'operational_itinerary_invalid' => kOperationalItineraryInvalid,
    'operational_destination_invalid' ||
    'operational_end_invalid' => kOperationalRouteInvalid,
    _ => const LocalizedText(
      nl: 'De wijziging kon niet worden bevestigd. Probeer opnieuw.',
      en: 'The change could not be confirmed. Retry.',
      fr: 'La modification n’a pas pu être confirmée. Réessayez.',
      es: 'No se pudo confirmar el cambio. Reintenta.',
      de: 'Die Änderung konnte nicht bestätigt werden. Versuchen Sie es erneut.',
    ),
  };
  return label.of(language);
}
