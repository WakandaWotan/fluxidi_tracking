// BOOKINGS-LIST-PAGINATION-CLIENT-P0C
//
// Localized chrome for bounded booking-list pagination. Uses the existing
// LocalizedText contract (NL/FR/EN/ES). Do not hardcode Dutch in shared UI.

import 'package:fluxidi_tracking/app_strings.dart';

const LocalizedText kBookingPageLoadMoreLabel = LocalizedText(
  nl: 'Meer laden',
  en: 'Load more',
  fr: 'Charger plus',
  es: 'Cargar más',
);

const LocalizedText kBookingPageLoadMoreSemantics = LocalizedText(
  nl: 'Volgende pagina boekingen laden',
  en: 'Load the next page of bookings',
  fr: 'Charger la page suivante des réservations',
  es: 'Cargar la página siguiente de reservas',
);

const LocalizedText kBookingPageRetryPageLabel = LocalizedText(
  nl: 'Opnieuw proberen',
  en: 'Try again',
  fr: 'Réessayer',
  es: 'Intentar de nuevo',
);

const LocalizedText kBookingPageRetryPageSemantics = LocalizedText(
  nl: 'Mislukte pagina opnieuw laden',
  en: 'Retry the failed booking page',
  fr: 'Réessayer la page de réservations échouée',
  es: 'Reintentar la página de reservas fallida',
);

const LocalizedText kBookingPageNextPageFailedLabel = LocalizedText(
  nl: 'Volgende pagina laden is mislukt. Eerder geladen ritten blijven zichtbaar.',
  en: 'Could not load the next page. Previously loaded rides stay visible.',
  fr: 'Impossible de charger la page suivante. Les courses déjà chargées restent visibles.',
  es: 'No se pudo cargar la página siguiente. Los viajes ya cargados siguen visibles.',
);
