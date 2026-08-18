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

const Size kLimousineSmX400Portrait = Size(1320, 2112);
const Size kLimousineTabletLandscape = Size(2112, 1320);
const Size kLimousinePhonePortrait = Size(390, 844);

const double kLimousineRequestWizardTabletMaxWidth = 720;
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
  nl: 'Limousineaanbod is nog niet actief in deze testomgeving.',
  en: 'Limousine offers are not active in this test environment yet.',
  fr: 'Les offres limousine ne sont pas encore actives dans cet environnement de test.',
  es: 'Las ofertas de limusina aún no están activas en este entorno de prueba.',
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
}) {
  final gaps = <LimousineRequestStepGap>[];
  switch (step) {
    case LimousineRequestWizardStep.journey:
      if (pickupAddress != null) {
        if (!pickupAddress.isRouteReady) {
          gaps.add(const LimousineRequestStepGap('pickup_required'));
        }
      } else if (draft.from.trim().isEmpty) {
        gaps.add(const LimousineRequestStepGap('pickup_required'));
      }
      if (destinationAddress != null) {
        if (!destinationAddress.isRouteReady) {
          gaps.add(const LimousineRequestStepGap('destination_required'));
        }
      } else if (draft.to.trim().isEmpty) {
        gaps.add(const LimousineRequestStepGap('destination_required'));
      }
      if (stopAddresses.any((stop) => !stop.isEmpty && !stop.isRouteReady)) {
        gaps.add(const LimousineRequestStepGap('stop_address_required'));
      }
      if (DateTime.tryParse(draft.scheduledPickupIso) == null) {
        gaps.add(const LimousineRequestStepGap('pickup_time_required'));
      }
      if (draft.roundtrip && DateTime.tryParse(draft.returnPickupIso) == null) {
        gaps.add(const LimousineRequestStepGap('return_time_required'));
      }
      if (draft.roundtrip &&
          returnPickupAddress != null &&
          !returnPickupAddress.isRouteReady) {
        gaps.add(const LimousineRequestStepGap('return_pickup_required'));
      }
      if (draft.roundtrip &&
          returnDestinationAddress != null &&
          !returnDestinationAddress.isRouteReady) {
        gaps.add(const LimousineRequestStepGap('return_destination_required'));
      }
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
      for (final error in validateLimousineCustomerDraft(draft, offer: offer)) {
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
        );
  }
  if (action == 'create_request' || action == 'submit') {
    return step == LimousineRequestWizardStep.review &&
        limousineRequestWizardCanAdvance(
          step: LimousineRequestWizardStep.review,
          draft: draft,
          offer: offer,
          hasProvider: hasProvider,
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

List<LimousineRequestReviewRow> buildLimousineRequestReviewRows({
  required LimousineQuoteCreateDraft draft,
  required AppLanguage language,
  String providerName = '',
  LimousinePublishedOffer? offer,
  String returnPickupAddress = '',
  String returnDestinationAddress = '',
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
      value: '${draft.from.trim()}  ${draft.to.trim()}'.trim(),
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
      value: draft.scheduledPickupIso.trim().isEmpty
          ? '—'
          : draft.scheduledPickupIso.trim(),
    ),
  );
  if (draft.roundtrip) {
    rows.add(
      LimousineRequestReviewRow(
        id: 'return',
        label: kLimousineReviewReturn.of(language),
        value: draft.returnPickupIso.trim().isEmpty
            ? '—'
            : draft.returnPickupIso.trim(),
      ),
    );
    if (returnPickupAddress.trim().isNotEmpty) {
      rows.add(
        LimousineRequestReviewRow(
          id: 'return_pickup_address',
          label: kLimousineReviewReturnPickup.of(language),
          value: returnPickupAddress.trim(),
        ),
      );
    }
    if (returnDestinationAddress.trim().isNotEmpty) {
      rows.add(
        LimousineRequestReviewRow(
          id: 'return_destination_address',
          label: kLimousineReviewReturnDestination.of(language),
          value: returnDestinationAddress.trim(),
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
  if (draft.selectedExtraIds.isNotEmpty) {
    rows.add(
      LimousineRequestReviewRow(
        id: 'extras',
        label: kLimousineReviewExtras.of(language),
        value: draft.selectedExtraIds.join(', '),
      ),
    );
  }
  final price = _displayedPriceEvidence(offer);
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

String _displayedPriceEvidence(LimousinePublishedOffer? offer) {
  if (offer == null) return '';
  final cents = offer.displayAmountCents;
  if (cents == null) {
    return limousineCustomerPresentationLabel(
      offer.pricePresentation,
      AppLanguage.en,
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
  return kLimousineGatesOffFriendly.of(language);
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
