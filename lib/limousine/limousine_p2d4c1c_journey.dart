// LIMOUSINE-MARKETPLACE-P2D4C1C — customer journey chrome contracts.
// Presentation and validation only. Create/submit stay on the existing
// quote controller. Waiting-duration is not a live Worker field.

import 'package:flutter/foundation.dart';

import '../app_strings.dart';
import 'limousine_p2d4c1a_ux.dart';

/// Limousine quote-create has `roundtrip` + `return_pickup_iso` only.
/// Taxi/booking `wait_minutes` is a different engine and must not be reused.
const bool kLimousineReturnWaitDurationSupported = false;

const List<int> kLimousineReturnWaitPresetMinutes = <int>[15, 30, 45, 60, 90];

enum LimousineOfferBrowseFilter { all, exactVehicle, serviceClass }

const LocalizedText kLimousineJourneyHeroTitle = LocalizedText(
  nl: 'Waar mogen we u ophalen?',
  en: 'Where may we pick you up?',
  fr: 'Où pouvons-nous venir vous chercher ?',
  es: '¿Dónde podemos recogerle?',
);

const LocalizedText kLimousineJourneyHeroBody = LocalizedText(
  nl: 'Vertel ons uw reis, wij regelen de rest.',
  en: 'Tell us your journey; we arrange the rest.',
  fr: 'Parlez-nous de votre trajet, nous nous occupons du reste.',
  es: 'Cuéntenos su viaje; nosotros nos ocupamos del resto.',
);

const LocalizedText kLimousineJourneyRouteCardTitle = LocalizedText(
  nl: 'Uw traject',
  en: 'Your journey',
  fr: 'Votre trajet',
  es: 'Su trayecto',
);

const LocalizedText kLimousineJourneyTypeCardTitle = LocalizedText(
  nl: 'Soort traject',
  en: 'Journey type',
  fr: 'Type de trajet',
  es: 'Tipo de trayecto',
);

const LocalizedText kLimousineJourneySecureNote = LocalizedText(
  nl: 'Traject wordt veilig gecontroleerd',
  en: 'Your journey is checked securely',
  fr: 'L’itinéraire est vérifié en toute sécurité',
  es: 'El trayecto se comprueba de forma segura',
);

const LocalizedText kLimousineJourneyChooseProvider = LocalizedText(
  nl: 'Kies een aanbieder',
  en: 'Choose a provider',
  fr: 'Choisir un prestataire',
  es: 'Elegir un proveedor',
);

const LocalizedText kLimousineProviderHeroTitle = LocalizedText(
  nl: 'Kies uw limousine',
  en: 'Choose your limousine',
  fr: 'Choisissez votre limousine',
  es: 'Elija su limusina',
);

const LocalizedText kLimousineProviderHeroBody = LocalizedText(
  nl: 'Vergelijk betrouwbare opties. Prijzen blijven van de aanbieder.',
  en: 'Compare trusted options. Prices stay provider-authoritative.',
  fr: 'Comparez des options de confiance. Les prix restent ceux du prestataire.',
  es: 'Compare opciones de confianza. Los precios los confirma el proveedor.',
);

const LocalizedText kLimousineProviderExactVehicle = LocalizedText(
  nl: 'Exact voertuig',
  en: 'Exact vehicle',
  fr: 'Véhicule exact',
  es: 'Vehículo exacto',
);

const LocalizedText kLimousineProviderServiceClass = LocalizedText(
  nl: 'Serviceklasse',
  en: 'Service class',
  fr: 'Classe de service',
  es: 'Clase de servicio',
);

const LocalizedText kLimousineProviderContinue = LocalizedText(
  nl: 'Verder met deze limousine',
  en: 'Continue with this limousine',
  fr: 'Continuer avec cette limousine',
  es: 'Continuar con esta limusina',
);

const LocalizedText kLimousineProviderViewProfile = LocalizedText(
  nl: 'Bekijk profiel',
  en: 'View profile',
  fr: 'Voir le profil',
  es: 'Ver perfil',
);

const LocalizedText kLimousineProviderNoneNearby = LocalizedText(
  nl: 'Geen limousineaanbieder gevonden voor dit traject.',
  en: 'No limousine provider was found for this journey.',
  fr: 'Aucun prestataire limousine trouvé pour ce trajet.',
  es: 'No se encontró ningún proveedor de limusina para este trayecto.',
);

const LocalizedText kLimousineProviderNoOffer = LocalizedText(
  nl: 'Deze aanbieder heeft geen gepubliceerd aanbod.',
  en: 'This provider has no published offer.',
  fr: 'Ce prestataire n’a pas d’offre publiée.',
  es: 'Este proveedor no tiene una oferta publicada.',
);

const LocalizedText kLimousineProviderRetry = LocalizedText(
  nl: 'Opnieuw proberen',
  en: 'Try again',
  fr: 'Réessayer',
  es: 'Reintentar',
);

const LocalizedText kLimousineProviderEditRoute = LocalizedText(
  nl: 'Traject bewerken',
  en: 'Edit journey',
  fr: 'Modifier le trajet',
  es: 'Editar el trayecto',
);

const LocalizedText kLimousineExtrasHeroTitle = LocalizedText(
  nl: 'Maak uw reis persoonlijk',
  en: 'Make your journey personal',
  fr: 'Personnalisez votre voyage',
  es: 'Personalice su viaje',
);

const LocalizedText kLimousineExtrasHeroBody = LocalizedText(
  nl: 'Kies alleen extras die deze aanbieder echt aanbiedt.',
  en: 'Choose only extras this provider actually offers.',
  fr: 'Choisissez uniquement les extras réellement proposés.',
  es: 'Elija solo los extras que este proveedor ofrece realmente.',
);

const LocalizedText kLimousineExtrasEmpty = LocalizedText(
  nl: 'Deze rit heeft geen extra opties. U kunt passagiers, bagage en een opmerking toevoegen.',
  en: 'This journey has no extra options. You can still set passengers, luggage and a note.',
  fr: 'Ce trajet n’a pas d’options supplémentaires. Vous pouvez indiquer passagers, bagages et une note.',
  es: 'Este viaje no tiene extras. Aún puede indicar pasajeros, equipaje y una nota.',
);

const LocalizedText kLimousineExtrasPriceAuthority = LocalizedText(
  nl: 'De definitieve prijs wordt door de aanbieder bevestigd.',
  en: 'The provider confirms the final price.',
  fr: 'Le prestataire confirme le prix définitif.',
  es: 'El proveedor confirma el precio definitivo.',
);

const LocalizedText kLimousineExtrasContinue = LocalizedText(
  nl: 'Controleer uw aanvraag',
  en: 'Review your request',
  fr: 'Vérifier votre demande',
  es: 'Revisar su solicitud',
);

const LocalizedText kLimousineExtrasChangeSelection = LocalizedText(
  nl: 'Wijzigen',
  en: 'Change',
  fr: 'Modifier',
  es: 'Cambiar',
);

const LocalizedText kLimousineReviewHeroTitle = LocalizedText(
  nl: 'Alles naar wens?',
  en: 'Does everything look right?',
  fr: 'Tout est en ordre ?',
  es: '¿Todo está en orden?',
);

const LocalizedText kLimousineReviewHeroBody = LocalizedText(
  nl: 'Controleer uw aanvraag en ontvang een offerte op maat.',
  en: 'Review your request and receive a tailored quote.',
  fr: 'Vérifiez votre demande et recevez un devis sur mesure.',
  es: 'Revise su solicitud y reciba un presupuesto a medida.',
);

const LocalizedText kLimousineReviewEdit = LocalizedText(
  nl: 'Bewerken',
  en: 'Edit',
  fr: 'Modifier',
  es: 'Editar',
);

const LocalizedText kLimousineReviewQuoteOnRequest = LocalizedText(
  nl: 'Offerte op aanvraag',
  en: 'Quote on request',
  fr: 'Devis sur demande',
  es: 'Presupuesto bajo petición',
);

const LocalizedText kLimousineReviewNoPayment = LocalizedText(
  nl: 'Nog geen betaling',
  en: 'No payment yet',
  fr: 'Aucun paiement pour le moment',
  es: 'Aún no hay pago',
);

const LocalizedText kLimousineReviewDecideLater = LocalizedText(
  nl: 'U beslist na ontvangst van de offerte',
  en: 'You decide after receiving the quote',
  fr: 'Vous décidez après réception du devis',
  es: 'Usted decide tras recibir el presupuesto',
);

const LocalizedText kLimousineReviewSubmit = LocalizedText(
  nl: 'Offerte aanvragen',
  en: 'Request quote',
  fr: 'Demander un devis',
  es: 'Solicitar presupuesto',
);

const LocalizedText kLimousineReturnWhen = LocalizedText(
  nl: 'Wanneer wilt u terug?',
  en: 'When would you like to return?',
  fr: 'Quand souhaitez-vous rentrer ?',
  es: '¿Cuándo desea regresar?',
);

const LocalizedText kLimousineReturnWaitTitle = LocalizedText(
  nl: 'Chauffeur wacht',
  en: 'Chauffeur waits',
  fr: 'Le chauffeur attend',
  es: 'El chófer espera',
);

const LocalizedText kLimousineReturnWaitBody = LocalizedText(
  nl: 'De chauffeur blijft gekoppeld terwijl u op bestemming bent.',
  en: 'The chauffeur stays assigned while you remain at the destination.',
  fr: 'Le chauffeur reste associé pendant votre séjour à destination.',
  es: 'El chófer permanece asignado mientras usted está en el destino.',
);

const LocalizedText kLimousineReturnWaitUnavailable = LocalizedText(
  nl: 'Wachttijd is in deze testomgeving nog niet beschikbaar.',
  en: 'Waiting duration is not available in this test environment yet.',
  fr: 'La durée d’attente n’est pas encore disponible dans cet environnement de test.',
  es: 'La espera aún no está disponible en este entorno de prueba.',
);

const LocalizedText kLimousineReturnLaterTitle = LocalizedText(
  nl: 'Later ophalen',
  en: 'Pick up later',
  fr: 'Reprise plus tard',
  es: 'Recoger más tarde',
);

const LocalizedText kLimousineReturnLaterBody = LocalizedText(
  nl: 'Kies een concrete datum en tijd voor de terugrit.',
  en: 'Choose a concrete date and time for the return pickup.',
  fr: 'Choisissez une date et une heure précises pour le retour.',
  es: 'Elija una fecha y hora concretas para el regreso.',
);

const LocalizedText kLimousineReturnPriceNote = LocalizedText(
  nl: 'De aanbieder bevestigt de prijs van de terugrit.',
  en: 'The provider confirms the return-journey price.',
  fr: 'Le prestataire confirme le prix du retour.',
  es: 'El proveedor confirma el precio del regreso.',
);

const LocalizedText kLimousineGapPickup = LocalizedText(
  nl: 'Vul een ophaaladres in.',
  en: 'Enter a pickup address.',
  fr: 'Indiquez une adresse de prise en charge.',
  es: 'Indique una dirección de recogida.',
);

const LocalizedText kLimousineGapDestination = LocalizedText(
  nl: 'Vul een bestemming in.',
  en: 'Enter a destination.',
  fr: 'Indiquez une destination.',
  es: 'Indique un destino.',
);

const LocalizedText kLimousineGapPickupTime = LocalizedText(
  nl: 'Kies de ophaaldatum en -tijd.',
  en: 'Choose the pickup date and time.',
  fr: 'Choisissez la date et l’heure de prise en charge.',
  es: 'Elija la fecha y hora de recogida.',
);

const LocalizedText kLimousineGapReturnMode = LocalizedText(
  nl: 'Kies hoe u wilt terugkeren.',
  en: 'Choose how you want to return.',
  fr: 'Choisissez comment vous souhaitez rentrer.',
  es: 'Elija cómo desea regresar.',
);

const LocalizedText kLimousineGapReturnWait = LocalizedText(
  nl: 'Kies de wachttijd van de chauffeur.',
  en: 'Choose the chauffeur waiting duration.',
  fr: 'Choisissez le temps d’attente du chauffeur.',
  es: 'Elija el tiempo de espera del chófer.',
);

const LocalizedText kLimousineGapReturnTime = LocalizedText(
  nl: 'Kies de datum en tijd van de terugrit.',
  en: 'Choose the return pickup date and time.',
  fr: 'Choisissez la date et l’heure du retour.',
  es: 'Elija la fecha y hora del regreso.',
);

const LocalizedText kLimousineGapReturnPickup = LocalizedText(
  nl: 'Vul het ophaaladres van de terugrit in.',
  en: 'Enter the return pickup address.',
  fr: 'Indiquez l’adresse de prise en charge du retour.',
  es: 'Indique la dirección de recogida del regreso.',
);

const LocalizedText kLimousineGapReturnDestination = LocalizedText(
  nl: 'Vul de bestemming van de terugrit in.',
  en: 'Enter the return destination.',
  fr: 'Indiquez la destination du retour.',
  es: 'Indique el destino del regreso.',
);

const LocalizedText kLimousineGapDuration = LocalizedText(
  nl: 'Kies de gevraagde duur.',
  en: 'Choose the requested duration.',
  fr: 'Choisissez la durée demandée.',
  es: 'Elija la duración solicitada.',
);

const LocalizedText kLimousineGapReturnOrder = LocalizedText(
  nl: 'De terugrit moet later zijn dan de heenrit.',
  en: 'The return pickup must be later than the outbound pickup.',
  fr: 'Le retour doit être postérieur à l’aller.',
  es: 'El regreso debe ser posterior a la ida.',
);

const LocalizedText kLimousineGapStop = LocalizedText(
  nl: 'Vul de tussenstop in of verwijder hem.',
  en: 'Fill in the stop or remove it.',
  fr: 'Complétez l’arrêt ou supprimez-le.',
  es: 'Complete la parada o elimínela.',
);

const LocalizedText kLimousineGapProvider = LocalizedText(
  nl: 'Kies een limousineaanbieder en een aanbod.',
  en: 'Choose a limousine provider and an offer.',
  fr: 'Choisissez un prestataire limousine et une offre.',
  es: 'Elija un proveedor de limusina y una oferta.',
);

const LocalizedText kLimousineGapCapacity = LocalizedText(
  nl: 'Passagiers of bagage overschrijden de capaciteit.',
  en: 'Passengers or luggage exceed the capacity.',
  fr: 'Les passagers ou bagages dépassent la capacité.',
  es: 'Los pasajeros o el equipaje superan la capacidad.',
);

const LocalizedText kLimousineRemoveStop = LocalizedText(
  nl: 'Stop verwijderen',
  en: 'Remove stop',
  fr: 'Supprimer l’arrêt',
  es: 'Quitar parada',
);

const LocalizedText kLimousineChooseDateTime = LocalizedText(
  nl: 'Kies datum en tijd',
  en: 'Choose date and time',
  fr: 'Choisir la date et l’heure',
  es: 'Elegir fecha y hora',
);

const Key kLimousineOutboundPickupTimeKey = ValueKey<String>(
  'limousine_outbound_pickup_time',
);
const Key kLimousineReturnPickupTimeKey = ValueKey<String>(
  'limousine_return_pickup_time',
);
const Key kLimousineReturnCardKey = ValueKey<String>('limousine_return_card');
const Key kLimousineReturnWaitModeKey = ValueKey<String>(
  'limousine_return_mode_wait',
);
const Key kLimousineReturnLaterModeKey = ValueKey<String>(
  'limousine_return_mode_later',
);
const Key kLimousineJourneyHeroTitleKey = ValueKey<String>(
  'limousine_journey_hero_title',
);
const Key kLimousineProviderExactFilterKey = ValueKey<String>(
  'limousine_provider_filter_exact',
);
const Key kLimousineProviderClassFilterKey = ValueKey<String>(
  'limousine_provider_filter_class',
);
const Key kLimousineExtrasEmptyKey = ValueKey<String>('limousine_extras_empty');
const Key kLimousineReviewQuoteStateKey = ValueKey<String>(
  'limousine_review_quote_state',
);

Key limousineRequestRemoveStopKey(int index) =>
    ValueKey<String>('limousine_request_remove_stop_$index');

LocalizedText limousineRequestWizardPrimaryAction(
  LimousineRequestWizardStep step,
) {
  switch (step) {
    case LimousineRequestWizardStep.journey:
      return kLimousineJourneyChooseProvider;
    case LimousineRequestWizardStep.provider:
      return kLimousineProviderContinue;
    case LimousineRequestWizardStep.details:
      return kLimousineExtrasContinue;
    case LimousineRequestWizardStep.review:
      return kLimousineReviewSubmit;
  }
}

LocalizedText limousineRequestWizardHeroTitle(LimousineRequestWizardStep step) {
  switch (step) {
    case LimousineRequestWizardStep.journey:
      return kLimousineJourneyHeroTitle;
    case LimousineRequestWizardStep.provider:
      return kLimousineProviderHeroTitle;
    case LimousineRequestWizardStep.details:
      return kLimousineExtrasHeroTitle;
    case LimousineRequestWizardStep.review:
      return kLimousineReviewHeroTitle;
  }
}

LocalizedText limousineRequestWizardHeroBody(LimousineRequestWizardStep step) {
  switch (step) {
    case LimousineRequestWizardStep.journey:
      return kLimousineJourneyHeroBody;
    case LimousineRequestWizardStep.provider:
      return kLimousineProviderHeroBody;
    case LimousineRequestWizardStep.details:
      return kLimousineExtrasHeroBody;
    case LimousineRequestWizardStep.review:
      return kLimousineReviewHeroBody;
  }
}

LocalizedText limousineRequestGapLabel(String code) {
  switch (code) {
    case 'pickup_required':
      return kLimousineGapPickup;
    case 'destination_required':
      return kLimousineGapDestination;
    case 'pickup_time_required':
      return kLimousineGapPickupTime;
    case 'return_mode_required':
      return kLimousineGapReturnMode;
    case 'return_wait_required':
      return kLimousineGapReturnWait;
    case 'return_wait_unavailable':
      return kLimousineReturnWaitUnavailable;
    case 'return_time_required':
      return kLimousineGapReturnTime;
    case 'return_time_order':
      return kLimousineGapReturnOrder;
    case 'return_pickup_required':
      return kLimousineGapReturnPickup;
    case 'return_destination_required':
      return kLimousineGapReturnDestination;
    case 'duration_required':
      return kLimousineGapDuration;
    case 'stop_address_required':
      return kLimousineGapStop;
    case 'provider_required':
      return kLimousineGapProvider;
    case 'capacity_exceeded':
      return kLimousineGapCapacity;
    default:
      return kLimousineGapPickupTime;
  }
}

List<String> limousineReturnWaitDurationGaps({
  required bool supported,
  int? minutes,
}) {
  if (!supported) return const <String>['return_wait_unavailable'];
  if (minutes == null || minutes < 15 || minutes > 240) {
    return const <String>['return_wait_required'];
  }
  return const <String>[];
}

String limousineCustomerFormatDateTime(String iso, AppLanguage language) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return '';
  return limousineCustomerReviewScheduleLabel(iso, language);
}

bool limousineCustomerLooksLikeRawIso(String text) {
  return RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}').hasMatch(text);
}

bool limousineP2d4c1cLabelsComplete() {
  const labels = <LocalizedText>[
    kLimousineJourneyHeroTitle,
    kLimousineJourneyHeroBody,
    kLimousineJourneyChooseProvider,
    kLimousineProviderHeroTitle,
    kLimousineProviderContinue,
    kLimousineExtrasHeroTitle,
    kLimousineExtrasContinue,
    kLimousineReviewHeroTitle,
    kLimousineReviewSubmit,
    kLimousineReturnWhen,
    kLimousineReturnWaitTitle,
    kLimousineReturnLaterTitle,
    kLimousineGapPickupTime,
    kLimousineGapReturnMode,
    kLimousineGapReturnWait,
    kLimousineGapReturnTime,
    kLimousineGapStop,
    kLimousineReviewQuoteOnRequest,
    kLimousineReviewNoPayment,
    kLimousineReviewDecideLater,
  ];
  for (final label in labels) {
    for (final language in const [
      AppLanguage.nl,
      AppLanguage.en,
      AppLanguage.fr,
      AppLanguage.es,
    ]) {
      if (label.of(language).trim().isEmpty) return false;
    }
    if (label.nl == 'Complete the required fields to continue.') return false;
    if (label.fr == label.en && label.es == label.en && label.nl == label.en) {
      // Shared brand words are allowed; long English sentences are not.
      if (label.en.contains('Complete the required')) return false;
    }
  }
  return true;
}
