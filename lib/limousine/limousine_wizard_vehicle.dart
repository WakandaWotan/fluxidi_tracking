// Locked public-offer entry: skip or choose a published vehicle.
// Marketplace discovery without a preselected provider stays a separate path.

import 'package:flutter/foundation.dart';

import '../app_config.dart';
import '../app_strings.dart';
import 'limousine_customer_quote.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_p2d4c1c_journey.dart';
import 'limousine_provider_showroom.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_vehicle_public_copy.dart';

enum LimousineWizardVehicleMode { discover, skip, choose, locked }

const Key kLimousineWizardVehicleListKey = ValueKey<String>(
  'limousine_wizard_vehicle_list',
);
const Key kLimousineQuoteSubmitTraceKey = ValueKey<String>(
  'limousine_quote_submit_trace',
);
const Key kLimousineQuoteSubmitErrorKey = ValueKey<String>(
  'limousine_quote_submit_error',
);
const Key kLimousineQuoteSubmitConfirmationKey = ValueKey<String>(
  'limousine_quote_submit_confirmation',
);
const Key kLimousineQuoteSubmitReferenceKey = ValueKey<String>(
  'limousine_quote_submit_reference',
);
const Key kLimousineQuoteSubmittedHomeKey = ValueKey<String>(
  'limousine_quote_submitted_home',
);
const Key kLimousineQuoteSubmitLoadingKey = ValueKey<String>(
  'limousine_quote_submit_loading',
);
const Key kLimousineReviewLockedVehicleKey = ValueKey<String>(
  'limousine_review_locked_vehicle',
);

Key limousineWizardVehicleCardKey(String vehicleId) =>
    ValueKey<String>('limousine_wizard_vehicle_card_$vehicleId');

const LocalizedText kLimousineCustomerStepLimousine = LocalizedText(
  nl: 'Limousine',
  en: 'Limousine',
  fr: 'Limousine',
  es: 'Limusina',
);

const LocalizedText kLimousineWizardPassengers = LocalizedText(
  nl: 'Passagiers',
  en: 'Passengers',
  fr: 'Passagers',
  es: 'Pasajeros',
);

const LocalizedText kLimousineWizardLuggage = LocalizedText(
  nl: 'Bagage',
  en: 'Luggage',
  fr: 'Bagages',
  es: 'Equipaje',
);

const LocalizedText kLimousineReviewSubmitting = LocalizedText(
  nl: 'Offerte wordt verzonden…',
  en: 'Sending quote request…',
  fr: 'Envoi de la demande…',
  es: 'Enviando la solicitud…',
);

const LocalizedText kLimousineJourneyContinueExtras = LocalizedText(
  nl: 'Verder naar extra’s',
  en: 'Continue to extras',
  fr: 'Continuer vers les extras',
  es: 'Continuar a extras',
);

const LocalizedText kLimousineJourneyContinueLimousine = LocalizedText(
  nl: 'Verder',
  en: 'Continue',
  fr: 'Continuer',
  es: 'Continuar',
);

const LocalizedText kLimousineReviewLockedVehicle = LocalizedText(
  nl: 'Gekozen limousine',
  en: 'Chosen limousine',
  fr: 'Limousine choisie',
  es: 'Limusina elegida',
);

const LocalizedText kLimousineQuoteSubmittedTitle = LocalizedText(
  nl: 'Aanvraag verzonden',
  en: 'Request sent',
  fr: 'Demande envoyée',
  es: 'Solicitud enviada',
);

const LocalizedText kLimousineQuoteSubmittedBody = LocalizedText(
  nl: 'Het limousinebedrijf heeft uw aanvraag ontvangen.',
  en: 'The limousine company has received your request.',
  fr: 'L’entreprise de limousine a reçu votre demande.',
  es: 'La empresa de limusinas ha recibido su solicitud.',
);

const LocalizedText kLimousineQuoteSubmittedHome = LocalizedText(
  nl: 'Terug naar start',
  en: 'Back to start',
  fr: 'Retour à l’accueil',
  es: 'Volver al inicio',
);

const LocalizedText kLimousineBookingSubmittedTitle = LocalizedText(
  nl: 'Uw boekingsaanvraag is goed verzonden.',
  en: 'Your booking request was sent successfully.',
  fr: 'Votre demande de réservation a bien été envoyée.',
  es: 'Su solicitud de reserva se envió correctamente.',
);

const LocalizedText kLimousineBookingSubmittedBody = LocalizedText(
  nl: 'De aanbieder bevestigt eerst de beschikbaarheid. Dit is nog geen bevestigde rit.',
  en: 'The provider first confirms availability. This is not a confirmed trip yet.',
  fr: 'Le prestataire confirme d’abord la disponibilité. Ce n’est pas encore un trajet confirmé.',
  es: 'El proveedor confirma primero la disponibilidad. Aún no es un viaje confirmado.',
);

const LocalizedText kLimousineQuoteSubmittedReference = LocalizedText(
  nl: 'Aanvraagreferentie',
  en: 'Request reference',
  fr: 'Référence de la demande',
  es: 'Referencia de la solicitud',
);

const LocalizedText kLimousineSubmitNetworkError = LocalizedText(
  nl: 'Verzenden is niet gelukt. Controleer de verbinding en probeer opnieuw. Uw gegevens blijven bewaard.',
  en: 'Sending failed. Check the connection and try again. Your details are kept.',
  fr: 'L’envoi a échoué. Vérifiez la connexion et réessayez. Vos données sont conservées.',
  es: 'No se pudo enviar. Compruebe la conexión e inténtelo de nuevo. Sus datos se conservan.',
);

const LocalizedText kLimousineSubmitInvalidError = LocalizedText(
  nl: 'Controleer het traject, de limousine en de gekozen locaties. Daarna kunt u opnieuw verzenden.',
  en: 'Check the journey, limousine and selected locations, then send again.',
  fr: 'Vérifiez le trajet, la limousine et les lieux choisis, puis renvoyez.',
  es: 'Revise el trayecto, la limusina y las ubicaciones y vuelva a enviar.',
);

const LocalizedText kLimousineSubmitNotEligibleError = LocalizedText(
  nl: 'Dit bedrijf kan deze offerteaanvraag nu niet ontvangen.',
  en: 'This company cannot receive this quote request right now.',
  fr: 'Cette entreprise ne peut pas recevoir cette demande pour le moment.',
  es: 'Esta empresa no puede recibir esta solicitud ahora.',
);

const LocalizedText kLimousineSubmitOfferGoneError = LocalizedText(
  nl: 'Dit aanbod is niet meer beschikbaar. Kies een ander gepubliceerd aanbod.',
  en: 'This offer is no longer available. Choose another published offer.',
  fr: 'Cette offre n’est plus disponible. Choisissez une autre offre publiée.',
  es: 'Esta oferta ya no está disponible. Elija otra oferta publicada.',
);

const LocalizedText kLimousineSubmitNotQuotableError = LocalizedText(
  nl: 'Dit aanbod vraagt een boeking, geen offerteaanvraag.',
  en: 'This offer requires a booking, not a quote request.',
  fr: 'Cette offre nécessite une réservation, pas une demande de devis.',
  es: 'Esta oferta requiere una reserva, no una solicitud de presupuesto.',
);

const LocalizedText kLimousineSubmitVehicleError = LocalizedText(
  nl: 'Deze limousine hoort niet bij het gekozen aanbod.',
  en: 'This limousine does not belong to the selected offer.',
  fr: 'Cette limousine n’appartient pas à l’offre choisie.',
  es: 'Esta limusina no pertenece a la oferta seleccionada.',
);

const LocalizedText kLimousineSubmitGenericError = LocalizedText(
  nl: 'De aanvraag is niet verzonden. Probeer opnieuw. Uw gegevens blijven bewaard.',
  en: 'The request was not sent. Try again. Your details are kept.',
  fr: 'La demande n’a pas été envoyée. Réessayez. Vos données sont conservées.',
  es: 'La solicitud no se envió. Inténtelo de nuevo. Sus datos se conservan.',
);

const LocalizedText kLimousineSubmitServerError = LocalizedText(
  nl: 'De server kon de aanvraag niet verwerken. Probeer opnieuw. Uw gegevens blijven bewaard.',
  en: 'The server could not process the request. Try again. Your details are kept.',
  fr: 'Le serveur n’a pas pu traiter la demande. Réessayez. Vos données sont conservées.',
  es: 'El servidor no pudo procesar la solicitud. Inténtelo de nuevo. Sus datos se conservan.',
);

const LocalizedText kLimousineSubmitConflictError = LocalizedText(
  nl: 'Deze aanvraag is gewijzigd of is niet meer geldig. Controleer de gegevens en probeer opnieuw.',
  en: 'This request changed or is no longer valid. Check the details and try again.',
  fr: 'Cette demande a changé ou n’est plus valable. Vérifiez les données et réessayez.',
  es: 'Esta solicitud cambió o ya no es válida. Revise los datos e inténtelo de nuevo.',
);

const LocalizedText kLimousineSubmitTechnicalRef = LocalizedText(
  nl: 'Technische referentie',
  en: 'Technical reference',
  fr: 'Référence technique',
  es: 'Referencia técnica',
);

class LimousineWizardVehicleOption {
  const LimousineWizardVehicleOption({
    required this.vehicleId,
    required this.name,
    this.serviceClassId = '',
    this.photoUrl = '',
    this.passengerCapacity,
    this.luggageCapacity,
    this.publicDescription = const <String, String>{},
    this.pricePresentation = '',
  });

  final String vehicleId;
  final String name;
  final String serviceClassId;
  final String photoUrl;
  final int? passengerCapacity;
  final int? luggageCapacity;
  final Map<String, String> publicDescription;
  final String pricePresentation;

  String classLabel(AppLanguage language) {
    return limousineServiceClassLabel(serviceClassId, language);
  }

  factory LimousineWizardVehicleOption.fromShowroomVehicle(
    LimousineShowroomVehicle vehicle, {
    String pricePresentation = '',
  }) {
    return LimousineWizardVehicleOption(
      vehicleId: vehicle.vehicleId.trim(),
      name: vehicle.displayName,
      serviceClassId: vehicle.serviceClassId,
      photoUrl: vehicle.primaryPhotoUrl,
      passengerCapacity: vehicle.passengerCapacity,
      luggageCapacity: vehicle.luggageCapacity,
      publicDescription: vehicle.publicDescription,
      pricePresentation: pricePresentation,
    );
  }

  Map<String, dynamic> toPublicSnapshot() {
    return <String, dynamic>{
      'vehicle_id': vehicleId,
      if (name.trim().isNotEmpty) 'public_name': name.trim(),
      if (serviceClassId.trim().isNotEmpty)
        'service_class_id': serviceClassId.trim(),
      if (photoUrl.startsWith('https://')) 'photo_url': photoUrl,
      if (passengerCapacity != null) 'passenger_capacity': passengerCapacity,
      if (luggageCapacity != null) 'luggage_capacity': luggageCapacity,
    };
  }

  static LimousineWizardVehicleOption? fromPublicSnapshot(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    final id = limousineCanonicalVehicleId(
      map['vehicle_id'] ?? map['vehicleId'],
    );
    if (id.isEmpty) return null;
    return LimousineWizardVehicleOption(
      vehicleId: id,
      name: (map['public_name'] ?? map['name'] ?? map['display_name'] ?? '')
          .toString()
          .trim(),
      serviceClassId: (map['service_class_id'] ?? map['serviceClassId'] ?? '')
          .toString()
          .trim(),
      photoUrl: (map['photo_url'] ?? map['photoUrl'] ?? '').toString().trim(),
      passengerCapacity: int.tryParse(
        '${map['passenger_capacity'] ?? map['pax'] ?? ''}',
      ),
      luggageCapacity: int.tryParse(
        '${map['luggage_capacity'] ?? map['bags'] ?? ''}',
      ),
    );
  }
}

List<LimousineWizardVehicleOption> limousineWizardVehicleOptions(
  LimousinePublishedOffer offer, {
  List<LimousineShowroomVehicle> catalog = const <LimousineShowroomVehicle>[],
}) {
  final seen = <String>{};
  final out = <LimousineWizardVehicleOption>[];
  final byId = <String, LimousineShowroomVehicle>{
    for (final vehicle in catalog)
      if (vehicle.vehicleId.trim().isNotEmpty)
        limousineCanonicalVehicleId(vehicle.vehicleId): vehicle,
  };

  void add(LimousineWizardVehicleOption option) {
    final id = option.vehicleId.trim();
    if (id.isEmpty || seen.contains(id)) return;
    seen.add(id);
    final catalogHit = byId[limousineCanonicalVehicleId(id)];
    if (catalogHit != null &&
        (option.name.trim().isEmpty ||
            option.name == _offerDisplayName(offer) ||
            option.photoUrl.isEmpty)) {
      out.add(
        LimousineWizardVehicleOption.fromShowroomVehicle(
          catalogHit,
          pricePresentation: offer.pricePresentation,
        ),
      );
      return;
    }
    out.add(option);
  }

  final rawVehicles = offer.raw['vehicles'];
  if (rawVehicles is List) {
    for (final item in rawVehicles) {
      if (item is! Map) continue;
      final parsed = _vehicleFromMap(
        item.map((key, value) => MapEntry(key.toString(), value)),
        offer,
      );
      if (parsed != null) add(parsed);
    }
  }

  if (out.length > 1) return List<LimousineWizardVehicleOption>.unmodifiable(out);

  final ids = offer.raw['vehicle_ids'] ?? offer.raw['vehicleIds'];
  if (ids is List) {
    for (final rawId in ids) {
      final id = limousineCanonicalVehicleId(rawId);
      if (id.isEmpty) continue;
      final catalogHit = byId[id];
      add(
        catalogHit == null
            ? LimousineWizardVehicleOption(
                vehicleId: id,
                name: _offerDisplayName(offer),
                serviceClassId: offer.serviceClassId,
                photoUrl: offer.photoUrl,
                passengerCapacity: offer.passengerCapacity,
                luggageCapacity: offer.luggageCapacity,
                publicDescription: offer.description,
                pricePresentation: offer.pricePresentation,
              )
            : LimousineWizardVehicleOption.fromShowroomVehicle(
                catalogHit,
                pricePresentation: offer.pricePresentation,
              ),
      );
    }
  }

  if (out.length > 1) return List<LimousineWizardVehicleOption>.unmodifiable(out);

  if (out.isEmpty) {
    final fallback = LimousineWizardVehicleOption(
      vehicleId: offer.vehicleId.trim(),
      name: _offerDisplayName(offer),
      serviceClassId: offer.serviceClassId,
      photoUrl: offer.photoUrl,
      passengerCapacity: offer.passengerCapacity,
      luggageCapacity: offer.luggageCapacity,
      publicDescription: offer.description,
      pricePresentation: offer.pricePresentation,
    );
    if (fallback.vehicleId.isNotEmpty) {
      add(fallback);
    } else {
      return List<LimousineWizardVehicleOption>.unmodifiable(<LimousineWizardVehicleOption>[
        fallback,
      ]);
    }
  }
  return List<LimousineWizardVehicleOption>.unmodifiable(out);
}

LimousineWizardVehicleMode limousineWizardVehicleMode({
  required bool providerOfferLocked,
  LimousinePublishedOffer? offer,
  String lockedVehicleId = '',
}) {
  if (!providerOfferLocked || offer == null) {
    return LimousineWizardVehicleMode.discover;
  }
  if (lockedVehicleId.trim().isNotEmpty) {
    return LimousineWizardVehicleMode.locked;
  }
  return limousineWizardVehicleOptions(offer).length > 1
      ? LimousineWizardVehicleMode.choose
      : LimousineWizardVehicleMode.skip;
}

bool limousineWizardSkipsVehicleStep(LimousineWizardVehicleMode mode) {
  return mode == LimousineWizardVehicleMode.skip ||
      mode == LimousineWizardVehicleMode.locked;
}

List<LimousineRequestWizardStep> limousineVisibleWizardSteps(
  LimousineWizardVehicleMode mode,
) {
  if (limousineWizardSkipsVehicleStep(mode)) {
    return const <LimousineRequestWizardStep>[
      LimousineRequestWizardStep.journey,
      LimousineRequestWizardStep.details,
      LimousineRequestWizardStep.review,
    ];
  }
  return kLimousineRequestWizardSteps;
}

LocalizedText limousineWizardPrimaryAction(
  LimousineRequestWizardStep step,
  LimousineWizardVehicleMode mode,
) {
  if (step == LimousineRequestWizardStep.journey) {
    if (limousineWizardSkipsVehicleStep(mode)) {
      return kLimousineJourneyContinueExtras;
    }
    if (mode == LimousineWizardVehicleMode.choose) {
      return kLimousineJourneyContinueLimousine;
    }
  }
  return limousineRequestWizardPrimaryAction(step);
}

LocalizedText limousineVisibleWizardStepLabel(
  LimousineRequestWizardStep step,
  LimousineWizardVehicleMode mode,
) {
  if (step == LimousineRequestWizardStep.provider &&
      mode != LimousineWizardVehicleMode.discover) {
    return kLimousineCustomerStepLimousine;
  }
  return limousineRequestWizardStepLabel(step);
}

String limousineAutoSelectVehicleId(LimousinePublishedOffer offer) {
  final options = limousineWizardVehicleOptions(offer);
  if (options.length == 1) return options.first.vehicleId.trim();
  return '';
}

LocalizedText limousineSubmitErrorLabel(String code) {
  switch (code) {
    case 'unavailable':
    case 'gate_off':
    case 'manual_quote_gate_off':
    case 'not_found':
      return kLimousineGatesOffFriendly;
    case 'network':
      return kLimousineSubmitNetworkError;
    case 'invalid_request':
    case 'missingAddresses':
    case 'missingProviderOffer':
    case 'invalidSchedule':
    case 'invalidDuration':
    case 'capacityExceeded':
    case 'invalidExtra':
    case 'unsupportedJourney':
    case 'vehicle_required':
      return kLimousineSubmitInvalidError;
    case 'not_eligible':
      return kLimousineSubmitNotEligibleError;
    case 'unknown_offer':
    case 'offer_unpublished':
      return kLimousineSubmitOfferGoneError;
    case 'offer_not_manual_quotable':
      return kLimousineSubmitNotQuotableError;
    case 'vehicle_scope_mismatch':
    case 'vehicle_not_published':
      return kLimousineSubmitVehicleError;
    case 'journey_type_not_allowed':
    case 'offer_scope_changed':
      return kLimousineOfferScopeChanged;
    case 'conflict':
    case 'stale_revision':
      return kLimousineSubmitConflictError;
    case 'invalid_response':
    case 'internal_error':
    case 'BOOKING_KV binding is missing':
      return kLimousineSubmitServerError;
    default:
      return kLimousineSubmitGenericError;
  }
}

String _offerDisplayName(LimousinePublishedOffer offer) {
  final title = localizedLimousineText(offer.title, languageCode: 'nl');
  if (title.trim().isNotEmpty &&
      title.trim() != offer.offerId &&
      !title.contains('_')) {
    return title.trim();
  }
  final en = localizedLimousineText(offer.title, languageCode: 'en');
  if (en.trim().isNotEmpty && en.trim() != offer.offerId && !en.contains('_')) {
    return en.trim();
  }
  return 'Limousine';
}

LimousineWizardVehicleOption? _vehicleFromMap(
  Map<String, dynamic> map,
  LimousinePublishedOffer offer,
) {
  final id = limousineCanonicalVehicleId(
    map['vehicle_id'] ?? map['vehicleId'] ?? map['id'],
  );
  if (id.isEmpty) return null;
  final name = (map['name'] ?? map['display_name'] ?? map['brand_model'] ?? '')
      .toString()
      .trim();
  final photos = <String>[];
  final photo = (map['photo_url'] ?? map['photoUrl'] ?? '').toString().trim();
  if (photo.startsWith('https://')) photos.add(photo);
  final gallery = map['photo_urls'] ?? map['photoUrls'];
  if (gallery is List) {
    for (final item in gallery) {
      final url = item.toString().trim();
      if (url.startsWith('https://')) photos.add(url);
    }
  }
  return LimousineWizardVehicleOption(
    vehicleId: id,
    name: name.isEmpty ? _offerDisplayName(offer) : name,
    serviceClassId: (map['service_class_id'] ??
            map['serviceClassId'] ??
            map['service_class'] ??
            offer.serviceClassId)
        .toString()
        .trim(),
    photoUrl: photos.isNotEmpty ? photos.first : offer.photoUrl,
    passengerCapacity:
        offer.passengerCapacity ??
        int.tryParse('${map['passenger_capacity'] ?? map['pax'] ?? ''}'),
    luggageCapacity:
        offer.luggageCapacity ??
        int.tryParse('${map['luggage_capacity'] ?? map['luggage'] ?? ''}'),
    publicDescription: limousinePublicCopyLocalizedOf(
      map['public_description'] ?? map['description'],
    ),
    pricePresentation: offer.pricePresentation,
  );
}
