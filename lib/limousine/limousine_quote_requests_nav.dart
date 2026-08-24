// LIMOUSINE-P2D4C1D — Bookings-page quote-request tab visibility and chrome.
// Quotes stay on the existing inbox controller/API. Bookings stay on the
// existing company bookings list. Visibility uses only server-confirmed
// company state: saved active limousine vehicles and a saved "Prijs op
// aanvraag" offer.

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../business_theme_palette.dart';
import '../business_theme_store.dart';
import 'limousine_business_setup.dart';
import 'limousine_offers.dart';
import 'limousine_provider_showroom.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_quote_inbox_api.dart';
import 'limousine_quote_inbox_labels.dart';
import 'limousine_quote_inbox_page.dart';

bool limousineQuoteInboxRuntimeEnabled({
  bool quoteGate = kLimousineCustomerQuoteGateEnabled,
  bool manualQuoteGate = kLimousineCustomerManualQuoteGateEnabled,
}) {
  return limousineCustomerQuoteCtaEnabled(
    quoteGate: quoteGate,
    manualQuoteGate: manualQuoteGate,
  );
}

Widget limousineQuoteRequestsBody({
  required bool runtimeEnabled,
  LimousineQuoteInboxGateway? gateway,
  ValueChanged<int?>? onUnreadCount,
}) {
  // Compile-time gates are synchronous. Never construct the inbox (or its
  // HTTP client / controller) when quotes are off — that first frame is the
  // flash: hero, skeleton, empty list, then a post-frame gate-off redirect.
  debugPrint(
    '[LIMOUSINE_QUOTE_TAB] frame=build runtimeEnabled=$runtimeEnabled '
    'child=${runtimeEnabled ? 'LimousineQuoteInboxPage' : 'LimousineQuoteGateOffPanel'}',
  );
  if (!runtimeEnabled) {
    return const LimousineQuoteGateOffPanel(embedded: true);
  }
  return LimousineQuoteInboxPage(
    embedded: true,
    gateway: gateway,
    onUnreadCount: onUnreadCount,
  );
}

enum LimousineBookingsSection { bookings, quoteRequests }

final ValueNotifier<List<Map<String, dynamic>>>
limousineQuoteRequestsConfirmedOffers =
    ValueNotifier<List<Map<String, dynamic>>>(const <Map<String, dynamic>>[]);

bool limousineQuoteRequestsConfirmedOffersKnown = false;

void rememberLimousineQuoteRequestsConfirmedOffers(
  Iterable<Map<String, dynamic>> offers,
) {
  limousineQuoteRequestsConfirmedOffersKnown = true;
  limousineQuoteRequestsConfirmedOffers.value = offers
      .map(Map<String, dynamic>.from)
      .toList(growable: false);
}

void resetLimousineQuoteRequestsConfirmedOffers() {
  limousineQuoteRequestsConfirmedOffersKnown = false;
  limousineQuoteRequestsConfirmedOffers.value = const <Map<String, dynamic>>[];
}

List<Map<String, dynamic>> limousineOffersFromPricingPayload(
  Map<String, dynamic> data,
) {
  final section = (data['limousine'] is Map)
      ? Map<String, dynamic>.from(data['limousine'] as Map)
      : <String, dynamic>{};
  final raw = section['offers'];
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

bool limousineHasActiveSavedLimousineVehicle(
  Iterable<VehicleProfile> vehicles,
) {
  return vehicles.any(
    (vehicle) =>
        vehicle.isActive && limousineVehicleAppearsInLimousinePreview(vehicle),
  );
}

bool limousineQuoteOnRequestIsEnabled(Map<String, dynamic> offer) {
  if (limousineOfferToken(offer['price_presentation']) !=
      LimousinePricePresentation.quoteRequired) {
    return false;
  }
  return offer['enabled'] != false;
}

bool limousineHasEnabledQuoteOnRequest(Iterable<Map<String, dynamic>> offers) {
  return offers.any(limousineQuoteOnRequestIsEnabled);
}

/// Authoritative tab visibility. Callers must pass the last server-confirmed
/// fleet and offer snapshots. Draft checkbox state, vehicle names and
/// Flutter marketplace entry flags are never read here.
bool limousineQuoteRequestsTabVisible({
  required Iterable<VehicleProfile> serverConfirmedVehicles,
  required Iterable<Map<String, dynamic>> serverConfirmedOffers,
}) {
  return limousineHasActiveSavedLimousineVehicle(serverConfirmedVehicles) &&
      limousineHasEnabledQuoteOnRequest(serverConfirmedOffers);
}

class LimousineBookingsQuoteRequestsSwitch extends StatelessWidget {
  const LimousineBookingsQuoteRequestsSwitch({
    super.key,
    required this.section,
    required this.onChanged,
    this.unreadCount,
    this.language,
  });

  final LimousineBookingsSection section;
  final ValueChanged<LimousineBookingsSection> onChanged;
  final int? unreadCount;
  final AppLanguage? language;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, appLanguage, _) {
        final lang = language ?? appLanguage;
        return ValueListenableBuilder<BusinessThemeVariant>(
          valueListenable: businessThemeNotifier,
          builder: (context, variant, _) {
            final palette = paletteForBusinessTheme(variant);
            final badge = unreadCount != null && unreadCount! > 0
                ? unreadCount
                : null;
            final width = MediaQuery.sizeOf(context).width;
            final phone = width < 700;
            return Material(
              key: kLimousineBookingsQuoteSwitchKey,
              color: palette.surface,
              borderRadius: BorderRadius.circular(12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 10,
                        child: _tab(
                          key: kLimousineBookingsSectionTabKey,
                          label: kLimousineBookingsSectionLabel.of(lang),
                          selected:
                              section == LimousineBookingsSection.bookings,
                          palette: palette,
                          phone: phone,
                          onTap: () =>
                              onChanged(LimousineBookingsSection.bookings),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        flex: phone ? 14 : 10,
                        child: _tab(
                          key: kLimousineQuoteRequestsSectionTabKey,
                          label: kLimousineQuoteRequestsSectionLabel.of(lang),
                          selected:
                              section == LimousineBookingsSection.quoteRequests,
                          palette: palette,
                          phone: phone,
                          badge: badge,
                          onTap: () =>
                              onChanged(LimousineBookingsSection.quoteRequests),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _tab({
    required Key key,
    required String label,
    required bool selected,
    required BusinessThemePalette palette,
    required VoidCallback onTap,
    required bool phone,
    int? badge,
  }) {
    return Material(
      key: key,
      color: selected ? palette.accent.withOpacity(0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: phone ? 4 : 8,
            vertical: phone ? 6 : 8,
          ),
          child: phone
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.clip,
                      softWrap: true,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected
                            ? palette.accent
                            : palette.textSecondary,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                        height: 1.15,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(height: 4),
                      _unreadBadge(palette, badge),
                    ],
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected
                              ? palette.accent
                              : palette.textSecondary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      _unreadBadge(palette, badge),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _unreadBadge(BusinessThemePalette palette, int badge) {
    return Container(
      key: kLimousineQuoteRequestsTabBadgeKey,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: palette.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$badge',
        style: TextStyle(
          color: palette.textOnAccent,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }
}

class LimousineBookingsSectionHost extends StatelessWidget {
  const LimousineBookingsSectionHost({
    super.key,
    required this.quoteRequestsVisible,
    required this.section,
    required this.onSectionChanged,
    required this.bookings,
    required this.quoteRequests,
    this.unreadCount,
    this.language,
  });

  final bool quoteRequestsVisible;
  final LimousineBookingsSection section;
  final ValueChanged<LimousineBookingsSection> onSectionChanged;
  final Widget bookings;
  final Widget quoteRequests;
  final int? unreadCount;
  final AppLanguage? language;

  @override
  Widget build(BuildContext context) {
    final showQuotes =
        quoteRequestsVisible &&
        section == LimousineBookingsSection.quoteRequests;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (quoteRequestsVisible) ...[
          LimousineBookingsQuoteRequestsSwitch(
            section: section,
            onChanged: onSectionChanged,
            unreadCount: unreadCount,
            language: language,
          ),
          const SizedBox(height: 10),
        ],
        Expanded(child: showQuotes ? quoteRequests : bookings),
      ],
    );
  }
}
