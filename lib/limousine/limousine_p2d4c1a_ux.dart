// LIMOUSINE-MARKETPLACE-P2D4C1A — tablet/customer UX contracts.
// Presentation only. Booking/create payloads stay in limousine_customer_quote.dart.

import 'package:flutter/material.dart';

import '../app_strings.dart';
import '../business_theme/brand_signature_palette.dart';
import '../business_theme_palette.dart';
import '../customer_theme_palette.dart';
import 'limousine_address_lookup.dart';
import 'limousine_customer_quote.dart';
import 'limousine_customer_quote_labels.dart';
import 'limousine_offers.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_transfer_endpoint.dart';
import 'limousine_unified_intent.dart';

const Size kLimousineSmX400Portrait = Size(1320, 2112);
const Size kLimousineTabletLandscape = Size(2112, 1320);
const Size kLimousinePhonePortrait = Size(390, 844);

const double kLimousineRequestWizardTabletMaxWidth = 960;
const double kLimousineOfferEditorMaxWidth = 560;
const double kLimousineOfferEditorMenuMaxHeight = 240;

const Key kLimousineRequestWizardKey = ValueKey<String>(
  'limousine_request_wizard',
);
const Key kLimousineRequestWizardStepperKey = ValueKey<String>(
  'limousine_request_wizard_stepper',
);
const Key kLimousineRequestWizardColumnKey = ValueKey<String>(
  'limousine_request_wizard_column',
);
const Key kLimousineRequestWizardFooterKey = ValueKey<String>(
  'limousine_request_wizard_footer',
);
const Key kLimousineRequestWizardNextKey = ValueKey<String>(
  'limousine_request_wizard_next',
);
const Key kLimousineRequestWizardBackKey = ValueKey<String>(
  'limousine_request_wizard_back',
);
const Key kLimousineRequestWizardHintKey = ValueKey<String>(
  'limousine_request_wizard_hint',
);
const Key kLimousineRequestReviewSummaryKey = ValueKey<String>(
  'limousine_request_review_summary',
);
const Key kLimousineRequestAddStopKey = ValueKey<String>(
  'limousine_request_add_stop',
);
const Key kLimousineRequestWizardScrollKey = ValueKey<String>(
  'limousine_request_wizard_scroll',
);
const Key kLimousineOfferEditorDialogKey = ValueKey<String>(
  'limousine_offer_editor_dialog',
);
const Key kLimousineOfferEditorScrollKey = ValueKey<String>(
  'limousine_offer_editor_scroll',
);
const Key kLimousineOfferEditorActionsKey = ValueKey<String>(
  'limousine_offer_editor_actions',
);
const Key kLimousineOfferEditorLanguageTabsKey = ValueKey<String>(
  'limousine_offer_editor_language_tabs',
);
const Key kLimousineCompanyOffersStatusKey = ValueKey<String>(
  'limousine_company_offers_status',
);

Key limousineRequestWizardStepKey(LimousineRequestWizardStep step) =>
    ValueKey<String>('limousine_request_wizard_step_${step.name}');

Key limousineOfferEditorLanguageTabKey(String lang) =>
    ValueKey<String>('limousine_offer_editor_lang_$lang');

const LocalizedText kLimousineGatesOffFriendly = LocalizedText(
  nl: 'Offerteaanvragen en boekingen zijn nog niet actief in deze testomgeving.',
  en: 'Quote requests and bookings are not active in this test environment yet.',
  fr: 'Les demandes de devis et les réservations ne sont pas encore actives dans cet environnement de test.',
  es: 'Las solicitudes de presupuesto y las reservas aún no están activas en este entorno de prueba.',
);

const LocalizedText kLimousinePricingStaleConflict = LocalizedText(
  nl: 'Een nieuwere versie staat al op de server. Vernieuw en probeer opnieuw.',
  en: 'A newer version is already on the server. Refresh and try again.',
  fr: 'Une version plus récente est déjà sur le serveur. Actualisez et réessayez.',
  es: 'Ya hay una versión más reciente en el servidor. Actualice e inténtelo de nuevo.',
);

const LocalizedText kLimousinePricingSaveFailed = LocalizedText(
  nl: 'Opslaan is niet gelukt. Controleer de verbinding en probeer opnieuw.',
  en: 'Save failed. Check the connection and try again.',
  fr: 'L’enregistrement a échoué. Vérifiez la connexion et réessayez.',
  es: 'No se pudo guardar. Compruebe la conexión e inténtelo de nuevo.',
);

const LocalizedText kLimousineBusinessSetupTransactionsOff =
    kLimousineGatesOffFriendly;

const LocalizedText kLimousineBusinessSetupTestNotReadyMessage = LocalizedText(
  nl: 'Testomgeving: nog niet zichtbaar. Maak voertuig, aanbod, tekst en foto compleet.',
  en: 'Test environment: not visible yet. Complete vehicle, offer, text and photo.',
  fr: 'Environnement de test : pas encore visible. Complétez véhicule, offre, texte et photo.',
  es: 'Entorno de prueba: aún no visible. Complete vehículo, oferta, texto y foto.',
);

const LocalizedText kLimousineRequestIncompleteHint = LocalizedText(
  nl: 'Vul de verplichte velden in om verder te gaan.',
  en: 'Complete the required fields to continue.',
  fr: 'Complétez les champs obligatoires pour continuer.',
  es: 'Complete los campos obligatorios para continuar.',
);

const LocalizedText kLimousineReviewProvider = LocalizedText(
  nl: 'Aanbieder',
  en: 'Provider',
  fr: 'Prestataire',
  es: 'Proveedor',
);

const LocalizedText kLimousineReviewOffer = LocalizedText(
  nl: 'Aanbod / klasse',
  en: 'Offer / class',
  fr: 'Offre / classe',
  es: 'Oferta / clase',
);

const LocalizedText kLimousineReviewRoute = LocalizedText(
  nl: 'Traject',
  en: 'Route',
  fr: 'Itinéraire',
  es: 'Ruta',
);

const LocalizedText kLimousineReviewStops = LocalizedText(
  nl: 'Stops',
  en: 'Stops',
  fr: 'Arrêts',
  es: 'Paradas',
);

const LocalizedText kLimousineReviewPickup = LocalizedText(
  nl: 'Ophaalmoment',
  en: 'Pickup',
  fr: 'Prise en charge',
  es: 'Recogida',
);

const LocalizedText kLimousineReviewReturn = LocalizedText(
  nl: 'Terugrit',
  en: 'Return',
  fr: 'Retour',
  es: 'Regreso',
);

const LocalizedText kLimousineReviewReturnPickup = LocalizedText(
  nl: 'Terugrit ophaal',
  en: 'Return pickup',
  fr: 'Retour — prise en charge',
  es: 'Regreso — recogida',
);

const LocalizedText kLimousineReviewReturnDestination = LocalizedText(
  nl: 'Terugrit bestemming',
  en: 'Return destination',
  fr: 'Retour — destination',
  es: 'Regreso — destino',
);

const LocalizedText kLimousineReviewPassengers = LocalizedText(
  nl: 'Passagiers',
  en: 'Passengers',
  fr: 'Passagers',
  es: 'Pasajeros',
);

const LocalizedText kLimousineReviewBags = LocalizedText(
  nl: 'Bagage',
  en: 'Baggage',
  fr: 'Bagages',
  es: 'Equipaje',
);

const LocalizedText kLimousineReviewExtras = LocalizedText(
  nl: 'Extra’s',
  en: 'Extras',
  fr: 'Options',
  es: 'Extras',
);

const LocalizedText kLimousineReviewOccasion = LocalizedText(
  nl: 'Gelegenheid',
  en: 'Occasion',
  fr: 'Occasion',
  es: 'Ocasión',
);

const LocalizedText kLimousineReviewDuration = LocalizedText(
  nl: 'Duur',
  en: 'Duration',
  fr: 'Durée',
  es: 'Duración',
);

const LocalizedText kLimousineReviewPriceStatusQuote = LocalizedText(
  nl: 'Prijs op aanvraag — nog geen boeking of betaling',
  en: 'Price on request — no booking or payment yet',
  fr: 'Prix sur demande — pas encore de réservation ni de paiement',
  es: 'Precio bajo petición — aún no hay reserva ni pago',
);

const LocalizedText kLimousineReviewPriceStatusFrom = LocalizedText(
  nl: 'Vanafprijs ter informatie — het bedrijf bevestigt de eindprijs',
  en: 'From-price is informational — the company confirms the final price',
  fr: 'Prix à partir de est indicatif — l’entreprise confirme le prix final',
  es: 'El precio desde es informativo — la empresa confirma el precio final',
);

const LocalizedText kLimousineReviewPriceStatusBook = LocalizedText(
  nl: 'Vastgelegde prijs na bevestiging door het bedrijf',
  en: 'Price is frozen after the company confirms',
  fr: 'Prix figé après confirmation de l’entreprise',
  es: 'Precio fijado tras la confirmación de la empresa',
);

const LocalizedText kLimousineReviewPriceEvidence = LocalizedText(
  nl: 'Getoonde prijs (geen boekingsbedrag)',
  en: 'Displayed price (not a booking total)',
  fr: 'Prix affiché (pas un total de réservation)',
  es: 'Precio mostrado (no es un total de reserva)',
);

const LocalizedText kLimousineReviewVat = LocalizedText(
  nl: 'BTW / voorwaarden',
  en: 'VAT / terms',
  fr: 'TVA / conditions',
  es: 'IVA / condiciones',
);

enum LimousineRequestWizardStep { journey, provider, details, review }

enum LimousineReturnTripKind { unset, wait, later }

const List<LimousineRequestWizardStep> kLimousineRequestWizardSteps =
    <LimousineRequestWizardStep>[
      LimousineRequestWizardStep.journey,
      LimousineRequestWizardStep.provider,
      LimousineRequestWizardStep.details,
      LimousineRequestWizardStep.review,
    ];

LimousineRequestWizardStep limousineRequestWizardStepOf(
  LimousineCustomerQuoteStep step,
) {
  switch (step) {
    case LimousineCustomerQuoteStep.journey:
      return LimousineRequestWizardStep.journey;
    case LimousineCustomerQuoteStep.providerOffer:
      return LimousineRequestWizardStep.provider;
    case LimousineCustomerQuoteStep.detailsExtras:
      return LimousineRequestWizardStep.details;
    case LimousineCustomerQuoteStep.reviewRequest:
    case LimousineCustomerQuoteStep.waitingCompany:
    case LimousineCustomerQuoteStep.reviewQuote:
    case LimousineCustomerQuoteStep.acceptOffer:
      return LimousineRequestWizardStep.review;
  }
}

LimousineCustomerQuoteStep limousineCustomerQuoteStepOf(
  LimousineRequestWizardStep step,
) {
  switch (step) {
    case LimousineRequestWizardStep.journey:
      return LimousineCustomerQuoteStep.journey;
    case LimousineRequestWizardStep.provider:
      return LimousineCustomerQuoteStep.providerOffer;
    case LimousineRequestWizardStep.details:
      return LimousineCustomerQuoteStep.detailsExtras;
    case LimousineRequestWizardStep.review:
      return LimousineCustomerQuoteStep.reviewRequest;
  }
}

LocalizedText limousineRequestWizardStepLabel(LimousineRequestWizardStep step) {
  switch (step) {
    case LimousineRequestWizardStep.journey:
      return kLimousineCustomerStepJourney;
    case LimousineRequestWizardStep.provider:
      return kLimousineCustomerStepProvider;
    case LimousineRequestWizardStep.details:
      return kLimousineCustomerStepDetails;
    case LimousineRequestWizardStep.review:
      return kLimousineCustomerStepReview;
  }
}

class LimousineRequestStepGap {
  const LimousineRequestStepGap(this.code);

  final String code;
}

List<LimousineRequestStepGap> limousineReturnTripGaps({
  required LimousineQuoteCreateDraft draft,
  LimousineReturnTripKind returnKind = LimousineReturnTripKind.unset,
  LimousineAddressValue? returnPickupAddress,
  LimousineAddressValue? returnDestinationAddress,
  bool waitDurationSupported = false,
  int? waitMinutes,
}) {
  if (!draft.roundtrip) return const <LimousineRequestStepGap>[];
  final gaps = <LimousineRequestStepGap>[];
  if (returnPickupAddress != null && !returnPickupAddress.isRouteReady) {
    gaps.add(const LimousineRequestStepGap('return_pickup_required'));
  }
  if (returnDestinationAddress != null &&
      !returnDestinationAddress.isRouteReady) {
    gaps.add(const LimousineRequestStepGap('return_destination_required'));
  }
  switch (returnKind) {
    case LimousineReturnTripKind.unset:
      gaps.add(const LimousineRequestStepGap('return_mode_required'));
      return gaps;
    case LimousineReturnTripKind.wait:
      if (!waitDurationSupported) {
        gaps.add(const LimousineRequestStepGap('return_wait_unavailable'));
      } else if (waitMinutes == null || waitMinutes < 15 || waitMinutes > 240) {
        gaps.add(const LimousineRequestStepGap('return_wait_required'));
      }
      return gaps;
    case LimousineReturnTripKind.later:
      final outbound = DateTime.tryParse(draft.scheduledPickupIso);
      final ret = DateTime.tryParse(draft.returnPickupIso);
      if (ret == null) {
        gaps.add(const LimousineRequestStepGap('return_time_required'));
      } else if (outbound != null && !ret.isAfter(outbound)) {
        gaps.add(const LimousineRequestStepGap('return_time_order'));
      }
      return gaps;
  }
}

List<LimousineRequestStepGap> limousineRequestWizardGaps({
  required LimousineRequestWizardStep step,
  required LimousineQuoteCreateDraft draft,
  LimousinePublishedOffer? offer,
  bool hasProvider = false,
  LimousineAddressValue? pickupAddress,
  LimousineAddressValue? destinationAddress,
  List<LimousineAddressValue> stopAddresses = const <LimousineAddressValue>[],
  LimousineAddressValue? returnPickupAddress,
  LimousineAddressValue? returnDestinationAddress,
  LimousineReturnTripKind returnKind = LimousineReturnTripKind.unset,
  bool waitDurationSupported = false,
  int? waitMinutes,
}) {
  final gaps = <LimousineRequestStepGap>[];
  switch (step) {
    case LimousineRequestWizardStep.journey:
      final typedPickupReady =
          draft.fromEndpoint != null && draft.fromEndpoint!.routeText.isNotEmpty;
      final typedDestinationReady =
          draft.toEndpoint != null && draft.toEndpoint!.routeText.isNotEmpty;
      if (!typedPickupReady) {
        if (pickupAddress != null) {
          if (!pickupAddress.isRouteReady) {
            gaps.add(const LimousineRequestStepGap('pickup_required'));
          }
        } else if (draft.from.trim().isEmpty) {
          gaps.add(const LimousineRequestStepGap('pickup_required'));
        }
      }
      if (!typedDestinationReady) {
        if (destinationAddress != null) {
          if (!destinationAddress.isRouteReady) {
            gaps.add(const LimousineRequestStepGap('destination_required'));
          }
        } else if (draft.to.trim().isEmpty) {
          gaps.add(const LimousineRequestStepGap('destination_required'));
        }
      }
      if (stopAddresses.any((stop) => !stop.isRouteReady)) {
        gaps.add(const LimousineRequestStepGap('stop_address_required'));
      }
      if (DateTime.tryParse(draft.scheduledPickupIso) == null) {
        gaps.add(const LimousineRequestStepGap('pickup_time_required'));
      }
      gaps.addAll(
        limousineReturnTripGaps(
          draft: draft,
          returnKind: returnKind,
          returnPickupAddress: returnPickupAddress,
          returnDestinationAddress: returnDestinationAddress,
          waitDurationSupported: waitDurationSupported,
          waitMinutes: waitMinutes,
        ),
      );
      if (limousineOfferToken(draft.journeyType) == 'hourly_package' &&
          (draft.requestedDurationMinutes == null ||
              draft.requestedDurationMinutes! <= 0)) {
        gaps.add(const LimousineRequestStepGap('duration_required'));
      }
      break;
    case LimousineRequestWizardStep.provider:
      if (!hasProvider ||
          draft.publicPartnerId.trim().isEmpty ||
          draft.offerId.trim().isEmpty) {
        gaps.add(const LimousineRequestStepGap('provider_required'));
      }
      break;
    case LimousineRequestWizardStep.details:
      final draftErrors = validateLimousineCustomerDraft(draft, offer: offer);
      if (draftErrors.contains(LimousineCustomerDraftError.capacityExceeded)) {
        gaps.add(const LimousineRequestStepGap('capacity_exceeded'));
      }
      if (draftErrors.contains(LimousineCustomerDraftError.invalidExtra)) {
        gaps.add(const LimousineRequestStepGap('invalid_extra'));
      }
      break;
    case LimousineRequestWizardStep.review:
      gaps.addAll(
        limousineReturnTripGaps(
          draft: draft,
          returnKind: returnKind,
          returnPickupAddress: returnPickupAddress,
          returnDestinationAddress: returnDestinationAddress,
          waitDurationSupported: waitDurationSupported,
          waitMinutes: waitMinutes,
        ),
      );
      for (final error in validateLimousineCustomerDraft(draft, offer: offer)) {
        if (error == LimousineCustomerDraftError.invalidSchedule &&
            draft.roundtrip) {
          continue;
        }
        gaps.add(LimousineRequestStepGap(error.name));
      }
      break;
  }
  return gaps;
}

bool limousineRequestWizardCanAdvance({
  required LimousineRequestWizardStep step,
  required LimousineQuoteCreateDraft draft,
  LimousinePublishedOffer? offer,
  bool hasProvider = false,
  LimousineAddressValue? pickupAddress,
  LimousineAddressValue? destinationAddress,
  List<LimousineAddressValue> stopAddresses = const <LimousineAddressValue>[],
  LimousineAddressValue? returnPickupAddress,
  LimousineAddressValue? returnDestinationAddress,
  LimousineReturnTripKind returnKind = LimousineReturnTripKind.unset,
  bool waitDurationSupported = false,
  int? waitMinutes,
}) {
  return limousineRequestWizardGaps(
    step: step,
    draft: draft,
    offer: offer,
    hasProvider: hasProvider,
    pickupAddress: pickupAddress,
    destinationAddress: destinationAddress,
    stopAddresses: stopAddresses,
    returnPickupAddress: returnPickupAddress,
    returnDestinationAddress: returnDestinationAddress,
    returnKind: returnKind,
    waitDurationSupported: waitDurationSupported,
    waitMinutes: waitMinutes,
  ).isEmpty;
}

bool limousineRequestWizardAllowsHttp({
  required LimousineRequestWizardStep step,
  required LimousineQuoteCreateDraft draft,
  LimousinePublishedOffer? offer,
  bool hasProvider = false,
  required String action,
  LimousineAddressValue? pickupAddress,
  LimousineAddressValue? destinationAddress,
  List<LimousineAddressValue> stopAddresses = const <LimousineAddressValue>[],
  LimousineAddressValue? returnPickupAddress,
  LimousineAddressValue? returnDestinationAddress,
  LimousineReturnTripKind returnKind = LimousineReturnTripKind.unset,
  bool waitDurationSupported = false,
  int? waitMinutes,
}) {
  if (action == 'discover') {
    return step == LimousineRequestWizardStep.provider &&
        limousineRequestWizardCanAdvance(
          step: LimousineRequestWizardStep.journey,
          draft: draft,
          offer: offer,
          hasProvider: hasProvider,
          pickupAddress: pickupAddress,
          destinationAddress: destinationAddress,
          stopAddresses: stopAddresses,
          returnPickupAddress: returnPickupAddress,
          returnDestinationAddress: returnDestinationAddress,
          returnKind: returnKind,
          waitDurationSupported: waitDurationSupported,
          waitMinutes: waitMinutes,
        );
  }
  if (action == 'create_request' || action == 'submit') {
    return step == LimousineRequestWizardStep.review &&
        limousineRequestWizardCanAdvance(
          step: LimousineRequestWizardStep.review,
          draft: draft,
          offer: offer,
          hasProvider: hasProvider,
          returnPickupAddress: returnPickupAddress,
          returnDestinationAddress: returnDestinationAddress,
          returnKind: returnKind,
          waitDurationSupported: waitDurationSupported,
          waitMinutes: waitMinutes,
        );
  }
  return false;
}

class LimousineRequestReviewRow {
  const LimousineRequestReviewRow({
    required this.id,
    required this.label,
    required this.value,
  });

  final String id;
  final String label;
  final String value;
}

String limousineReviewEndpointLabel(LimousineTransferEndpoint? endpoint, String fallback) {
  if (endpoint == null || endpoint.isEmpty) return fallback.trim();
  if (endpoint.kind == LimousineTransferEndpointKind.airport) {
    final iata = (endpoint.iataCode ?? '').trim();
    final name = (endpoint.airportName ?? endpoint.displayName).trim();
    if (iata.isNotEmpty && name.isNotEmpty) return '$name ($iata)';
    return endpoint.displayName.trim().isEmpty ? fallback : endpoint.displayName.trim();
  }
  if (endpoint.kind == LimousineTransferEndpointKind.hotel) {
    final name = (endpoint.hotelName ?? endpoint.displayName).trim();
    final address = endpoint.formattedAddress.trim();
    if (name.isNotEmpty && address.isNotEmpty && name != address) {
      return '$name — $address';
    }
    return name.isEmpty ? address : name;
  }
  return endpoint.routeText.isEmpty ? fallback.trim() : endpoint.routeText;
}

String limousineReviewRouteLabel(LimousineQuoteCreateDraft draft) {
  final from = limousineReviewEndpointLabel(draft.fromEndpoint, draft.from);
  final to = limousineReviewEndpointLabel(draft.toEndpoint, draft.to);
  return '$from  $to'.trim();
}

List<LimousineRequestReviewRow> buildLimousineRequestReviewRows({
  required LimousineQuoteCreateDraft draft,
  required AppLanguage language,
  String providerName = '',
  LimousinePublishedOffer? offer,
  String returnPickupAddress = '',
  String returnDestinationAddress = '',
  LimousineReturnTripKind returnKind = LimousineReturnTripKind.unset,
}) {
  final rows = <LimousineRequestReviewRow>[
    LimousineRequestReviewRow(
      id: 'provider',
      label: kLimousineReviewProvider.of(language),
      value: providerName.trim().isEmpty ? '—' : providerName.trim(),
    ),
    LimousineRequestReviewRow(
      id: 'offer',
      label: kLimousineReviewOffer.of(language),
      value: _offerSummary(offer, language, draft),
    ),
    LimousineRequestReviewRow(
      id: 'route',
      label: kLimousineReviewRoute.of(language),
      value: limousineReviewRouteLabel(draft),
    ),
  ];
  if (draft.stops.isNotEmpty) {
    rows.add(
      LimousineRequestReviewRow(
        id: 'stops',
        label: kLimousineReviewStops.of(language),
        value: draft.stops.join(', '),
      ),
    );
  }
  rows.add(
    LimousineRequestReviewRow(
      id: 'pickup',
      label: kLimousineReviewPickup.of(language),
      value: limousineCustomerReviewScheduleLabel(
        draft.scheduledPickupIso,
        language,
      ),
    ),
  );
  if (draft.roundtrip) {
    rows.add(
      LimousineRequestReviewRow(
        id: 'return',
        label: kLimousineReviewReturn.of(language),
        value: returnKind == LimousineReturnTripKind.later
            ? limousineCustomerReviewScheduleLabel(
                draft.returnPickupIso,
                language,
              )
            : '—',
      ),
    );
    final returnPickupLabel = limousineReviewEndpointLabel(
      draft.returnPickupEndpoint,
      returnPickupAddress,
    );
    final returnDestinationLabel = limousineReviewEndpointLabel(
      draft.returnDestinationEndpoint,
      returnDestinationAddress,
    );
    if (returnPickupLabel.isNotEmpty) {
      rows.add(
        LimousineRequestReviewRow(
          id: 'return_pickup_address',
          label: kLimousineReviewReturnPickup.of(language),
          value: returnPickupLabel,
        ),
      );
    }
    if (returnDestinationLabel.isNotEmpty) {
      rows.add(
        LimousineRequestReviewRow(
          id: 'return_destination_address',
          label: kLimousineReviewReturnDestination.of(language),
          value: returnDestinationLabel,
        ),
      );
    }
  }
  rows.add(
    LimousineRequestReviewRow(
      id: 'pax',
      label: kLimousineReviewPassengers.of(language),
      value: '${draft.pax ?? 1}',
    ),
  );
  rows.add(
    LimousineRequestReviewRow(
      id: 'bags',
      label: kLimousineReviewBags.of(language),
      value: '${draft.bags ?? 0}',
    ),
  );
  if (draft.requestedDurationMinutes != null &&
      draft.requestedDurationMinutes! > 0) {
    rows.add(
      LimousineRequestReviewRow(
        id: 'duration',
        label: kLimousineReviewDuration.of(language),
        value: '${draft.requestedDurationMinutes} min',
      ),
    );
  }
  if (draft.occasion.trim().isNotEmpty) {
    rows.add(
      LimousineRequestReviewRow(
        id: 'occasion',
        label: kLimousineReviewOccasion.of(language),
        value: draft.occasion.trim(),
      ),
    );
  }
  if (draft.selectedExtraIds.isNotEmpty) {
    rows.add(
      LimousineRequestReviewRow(
        id: 'extras',
        label: kLimousineReviewExtras.of(language),
        value: draft.selectedExtraIds.join(', '),
      ),
    );
  }
  final mode = offer == null
      ? LimousinePublishedPricingMode.quoteRequired
      : limousinePublishedPricingModeOf(offer);
  rows.add(
    LimousineRequestReviewRow(
      id: 'price_status',
      label: kLimousineReviewPriceEvidence.of(language),
      value: switch (mode) {
        LimousinePublishedPricingMode.fromPrice =>
          kLimousineReviewPriceStatusFrom.of(language),
        LimousinePublishedPricingMode.exactFixed ||
        LimousinePublishedPricingMode.hourly ||
        LimousinePublishedPricingMode.package =>
          kLimousineReviewPriceStatusBook.of(language),
        LimousinePublishedPricingMode.quoteRequired =>
          kLimousineReviewPriceStatusQuote.of(language),
      },
    ),
  );
  final price = _displayedPriceEvidence(offer, language);
  if (price.isNotEmpty) {
    rows.add(
      LimousineRequestReviewRow(
        id: 'price_evidence',
        label: kLimousineReviewPriceEvidence.of(language),
        value: price,
      ),
    );
  }
  final vat = _vatOrTerms(offer, language);
  if (vat.isNotEmpty) {
    rows.add(
      LimousineRequestReviewRow(
        id: 'vat_terms',
        label: kLimousineReviewVat.of(language),
        value: vat,
      ),
    );
  }
  return rows;
}

String _offerSummary(
  LimousinePublishedOffer? offer,
  AppLanguage language,
  LimousineQuoteCreateDraft draft,
) {
  if (offer == null) return draft.offerId.trim();
  final title = localizedLimousineText(
    offer.title,
    languageCode: language.name,
  ).trim();
  final classId = offer.serviceClassId.trim();
  if (title.isNotEmpty && classId.isNotEmpty) return '$title · $classId';
  if (title.isNotEmpty) return title;
  if (classId.isNotEmpty) return classId;
  return offer.offerId;
}

String limousineCustomerReviewScheduleLabel(String iso, AppLanguage language) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return '—';
  final local = parsed.toLocal();
  final months = switch (language) {
    AppLanguage.fr => const [
      'janv.',
      'févr.',
      'mars',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sept.',
      'oct.',
      'nov.',
      'déc.',
    ],
    AppLanguage.es => const [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sept',
      'oct',
      'nov',
      'dic',
    ],
    AppLanguage.en => const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ],
    _ => const [
      'jan',
      'feb',
      'mrt',
      'apr',
      'mei',
      'jun',
      'jul',
      'aug',
      'sep',
      'okt',
      'nov',
      'dec',
    ],
  };
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]} ${local.year} · $hh:$mm';
}

String _displayedPriceEvidence(
  LimousinePublishedOffer? offer,
  AppLanguage language,
) {
  if (offer == null) return '';
  final cents = offer.displayAmountCents;
  if (cents == null) {
    return limousineCustomerPresentationLabel(
      offer.pricePresentation,
      language,
    );
  }
  final amount = (cents / 100).toStringAsFixed(2);
  return '$amount ${offer.currency}'.trim();
}

String _vatOrTerms(LimousinePublishedOffer? offer, AppLanguage language) {
  if (offer == null) return '';
  final parts = <String>[];
  final presentation = limousineCustomerPresentationLabel(
    offer.pricePresentation,
    language,
  ).trim();
  if (presentation.isNotEmpty) parts.add(presentation);
  final info = localizedLimousineText(
    offer.description,
    languageCode: language.name,
  ).trim();
  if (info.isNotEmpty) parts.add(info);
  return parts.join(' · ');
}

bool limousineReviewContainsOrphanArrow(String text) =>
    text.contains('→') || text.contains('->');

bool limousineLooksLikeRawException(String text) {
  final lower = text.toLowerCase();
  return lower.contains('exception:') ||
      lower.contains('not_found') ||
      lower.contains('stack') ||
      lower.contains('limousine_quote_enabled') ||
      lower.contains('limousine_book_enabled') ||
      lower.contains('limousine_manual_quote') ||
      lower.contains('limousine_test_company') ||
      lower.contains('limousine_acceptance_secret');
}

String limousineFriendlyCompanyError(
  Object error, {
  AppLanguage language = AppLanguage.nl,
}) {
  final text = error.toString().toLowerCase();
  if (text.contains('stale_source_revision') ||
      (text.contains('409') && text.contains('stale'))) {
    return kLimousinePricingStaleConflict.of(language);
  }
  return kLimousinePricingSaveFailed.of(language);
}

class LimousineOffersEditorSnapshot {
  const LimousineOffersEditorSnapshot({
    required this.enabled,
    required this.offers,
  });

  final bool enabled;
  final List<Map<String, dynamic>> offers;

  LimousineOffersEditorSnapshot copy() {
    return LimousineOffersEditorSnapshot(
      enabled: enabled,
      offers: offers
          .map((offer) => Map<String, dynamic>.from(offer))
          .toList(growable: false),
    );
  }
}

LimousineOffersEditorSnapshot limousineRollbackFailedPersistence({
  required LimousineOffersEditorSnapshot confirmed,
}) {
  return confirmed.copy();
}

bool limousineCompanySaveAllowed({
  required bool dirty,
  required bool saving,
  required Iterable<List<String>> offerErrors,
}) {
  if (!dirty || saving) return false;
  return offerErrors.every((errors) => errors.isEmpty);
}

double limousineRelativeLuminance(Color color) {
  double channel(double srgb) {
    return srgb <= 0.03928
        ? srgb / 12.92
        : ((srgb + 0.055) / 1.055) * ((srgb + 0.055) / 1.055);
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double limousineContrastRatio(Color a, Color b) {
  final l1 = limousineRelativeLuminance(a);
  final l2 = limousineRelativeLuminance(b);
  final light = l1 > l2 ? l1 : l2;
  final dark = l1 > l2 ? l2 : l1;
  return (light + 0.05) / (dark + 0.05);
}

bool limousineHasReadableContrast(Color foreground, Color background) {
  return limousineContrastRatio(foreground, background) >= 4.5;
}

class LimousineUxTokens {
  const LimousineUxTokens({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.onSurface,
    required this.muted,
    required this.border,
    required this.gold,
    required this.danger,
    required this.fieldFill,
    required this.onHero,
    required this.heroScrim,
    required this.isDark,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color onSurface;
  final Color muted;
  final Color border;
  final Color gold;
  final Color danger;
  final Color fieldFill;
  final Color onHero;
  final Color heroScrim;
  final bool isDark;

  factory LimousineUxTokens.fromCustomer(CustomerThemePalette palette) {
    return LimousineUxTokens(
      background: palette.background,
      surface: palette.surface,
      surfaceAlt: palette.surfaceAlt,
      onSurface: palette.textPrimary,
      muted: palette.textMuted,
      border: palette.border,
      gold: palette.gold,
      danger: palette.danger,
      fieldFill: palette.surface,
      onHero: palette.textPrimary,
      heroScrim: palette.background.withOpacity(palette.isDark ? 0.55 : 0.42),
      isDark: palette.isDark,
    );
  }

  factory LimousineUxTokens.fromSurface({
    required Color background,
    Color gold = const Color(0xFFC49A45),
  }) {
    final isDark = limousineRelativeLuminance(background) < 0.45;
    final onSurface = isDark
        ? const Color(0xFFF6F1E8)
        : const Color(0xFF182028);
    final surface = isDark
        ? Color.lerp(background, const Color(0xFFFFFFFF), 0.10)!
        : const Color(0xFFFFFFFF);
    return LimousineUxTokens(
      background: background,
      surface: surface,
      surfaceAlt: isDark
          ? Color.lerp(background, gold, 0.08)!
          : const Color(0xFFFFF5E8),
      onSurface: onSurface,
      muted: isDark ? const Color(0xB3F6F1E8) : const Color(0xFF5F6670),
      border: isDark ? const Color(0xFF3B2C14) : const Color(0xFFE7DECF),
      gold: gold,
      danger: const Color(0xFFCD5C6C),
      fieldFill: surface,
      onHero: onSurface,
      heroScrim: background.withOpacity(isDark ? 0.55 : 0.42),
      isDark: isDark,
    );
  }

  factory LimousineUxTokens.fromBrandSignature(BrandSignaturePalette palette) {
    return LimousineUxTokens.fromSurface(
      background: palette.page,
      gold: palette.accent,
    );
  }

  factory LimousineUxTokens.fromBusiness(BusinessThemePalette palette) {
    return LimousineUxTokens(
      background: palette.background,
      surface: palette.surface,
      surfaceAlt: palette.surfaceAlt,
      onSurface: palette.textPrimary,
      muted: palette.textMuted,
      border: palette.border,
      gold: palette.accent,
      danger: palette.danger,
      fieldFill: palette.surface,
      onHero: palette.textPrimary,
      heroScrim: palette.background.withOpacity(palette.isDark ? 0.55 : 0.38),
      isDark: palette.isDark,
    );
  }
}

ThemeData limousineUxThemeData(LimousineUxTokens tokens) {
  final brightness = tokens.isDark ? Brightness.dark : Brightness.light;
  final onPrimary = tokens.isDark
      ? const Color(0xFF14110C)
      : const Color(0xFF1A1408);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: tokens.gold,
    onPrimary: onPrimary,
    secondary: tokens.gold,
    onSecondary: onPrimary,
    error: tokens.danger,
    onError: const Color(0xFFFFFFFF),
    surface: tokens.surface,
    onSurface: tokens.onSurface,
  );
  final base = ThemeData(useMaterial3: true, brightness: brightness);
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.background,
    canvasColor: tokens.surface,
    dialogBackgroundColor: tokens.surface,
    dividerColor: tokens.border,
    textTheme: base.textTheme.apply(
      bodyColor: tokens.onSurface,
      displayColor: tokens.onSurface,
    ),
    iconTheme: IconThemeData(color: tokens.onSurface),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.fieldFill,
      hintStyle: TextStyle(color: tokens.muted),
      labelStyle: TextStyle(color: tokens.muted),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: tokens.gold),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: TextStyle(color: tokens.onSurface),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(tokens.surface),
        maximumSize: const WidgetStatePropertyAll<Size>(
          Size(double.infinity, kLimousineOfferEditorMenuMaxHeight),
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: tokens.surfaceAlt,
      selectedColor: tokens.gold.withOpacity(0.22),
      labelStyle: TextStyle(color: tokens.onSurface),
      secondaryLabelStyle: TextStyle(color: tokens.onSurface),
      disabledColor: tokens.surfaceAlt.withOpacity(0.6),
    ),
  );
}

double limousineRequestWizardContentWidth(double viewportWidth) {
  if (viewportWidth >= 700) {
    return viewportWidth < kLimousineRequestWizardTabletMaxWidth
        ? viewportWidth
        : kLimousineRequestWizardTabletMaxWidth;
  }
  return viewportWidth;
}

List<CustomerThemeVariant> get kLimousineUxContrastVariants =>
    const <CustomerThemeVariant>[
      CustomerThemeVariant.premiumLight,
      CustomerThemeVariant.nightGold,
      CustomerThemeVariant.royalBlueGold,
    ];
