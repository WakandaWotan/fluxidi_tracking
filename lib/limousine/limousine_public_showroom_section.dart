import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../customer_theme_palette.dart';
import 'limousine_customer_quote.dart';
import 'limousine_customer_quote_page.dart';
import 'limousine_offers.dart';
import 'limousine_provider_showroom.dart';
import 'limousine_public_showroom.dart';
import 'limousine_public_showroom_labels.dart';
import 'limousine_quote_inbox.dart';

class LimousinePublicShowroomSection extends StatefulWidget {
  const LimousinePublicShowroomSection({
    super.key,
    required this.profile,
    required this.partnerId,
    required this.companyName,
    required this.language,
    required this.palette,
    this.entryEnabled = true,
    this.onOpenQuote,
  });

  final Map<String, dynamic> profile;
  final String partnerId;
  final String companyName;
  final AppLanguage language;
  final CustomerThemePalette palette;
  final bool entryEnabled;
  final void Function(LimousinePublishedOffer offer)? onOpenQuote;

  @override
  State<LimousinePublicShowroomSection> createState() =>
      _LimousinePublicShowroomSectionState();
}

class _LimousinePublicShowroomSectionState
    extends State<LimousinePublicShowroomSection> {
  final Set<String> _expanded = <String>{};

  String _t(LocalizedText text) => text.of(widget.language);

  @override
  Widget build(BuildContext context) {
    if (!limousinePublicShowroomShouldRender(
      entryEnabled: widget.entryEnabled,
      profile: widget.profile,
    )) {
      return const SizedBox.shrink();
    }
    final offers = collectLimousineShowroomOffers(widget.profile);
    final palette = widget.palette;
    return Container(
      key: kLimousinePublicShowroomSectionKey,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: palette.isDark
              ? palette.gold.withOpacity(0.24)
              : palette.border,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withOpacity(palette.isDark ? 0.14 : 0.07),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(kLimousineShowroomTitle),
            style: TextStyle(
              color: palette.isDark
                  ? palette.gold.withOpacity(0.95)
                  : palette.bronze,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          for (final offer in offers) _card(offer),
        ],
      ),
    );
  }

  Widget _card(LimousinePublishedOffer offer) {
    final palette = widget.palette;
    final expanded = _expanded.contains(offer.offerId);
    final cta = limousineShowroomCtaFor(offer);
    final title = localizedLimousineText(
      offer.title,
      languageCode: widget.language.name,
    );
    final description = localizedLimousineText(
      offer.description,
      languageCode: widget.language.name,
    );
    final classLabel = limousineServiceClassLabel(
      offer.serviceClassId,
      widget.language,
    );
    return Container(
      key: limousineShowroomCardKey(offer.offerId),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: palette.isDark
              ? palette.gold.withOpacity(0.2)
              : palette.border,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (offer.isVehicleTargeted)
            _vehiclePhoto(offer)
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _t(kLimousineShowroomClassDisclosure),
                style: TextStyle(color: palette.textMuted, fontSize: 12.5),
              ),
            ),
          Text(
            title.isEmpty ? offer.offerId : title,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                description,
                style: TextStyle(color: palette.textMuted, height: 1.35),
              ),
            ),
          if (classLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                classLabel,
                style: TextStyle(
                  color: palette.bronze,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (offer.passengerCapacity != null)
                Text(
                  '${_t(kLimousineShowroomPassengers)}: ${offer.passengerCapacity}',
                ),
              if (offer.luggageCapacity != null)
                Text(
                  '${_t(kLimousineShowroomLuggage)}: ${offer.luggageCapacity}',
                ),
              if (offer.isVehicleTargeted && offer.color.isNotEmpty)
                Text('${_t(kLimousineShowroomColour)}: ${offer.color}'),
            ],
          ),
          if (expanded) ...[
            const SizedBox(height: 8),
            if (offer.journeyTypes.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final journey in offer.journeyTypes)
                    Chip(
                      label: Text(
                        limousineJourneyTypeLabel(journey, widget.language),
                      ),
                    ),
                ],
              ),
            if (offer.includedServices.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _t(kLimousineShowroomIncluded),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final item in offer.includedServices)
                Text(
                  localizedLimousineText(
                    item['label'] is Map
                        ? Map<String, String>.from(
                            (item['label'] as Map).map(
                              (key, value) =>
                                  MapEntry(key.toString(), '$value'),
                            ),
                          )
                        : const <String, String>{},
                    languageCode: widget.language.name,
                  ),
                ),
            ],
            if (offer.paidExtras.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _t(kLimousineShowroomExtras),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final extra in offer.paidExtras)
                Text(
                  localizedLimousineText(
                    extra['label'] is Map
                        ? Map<String, String>.from(
                            (extra['label'] as Map).map(
                              (key, value) =>
                                  MapEntry(key.toString(), '$value'),
                            ),
                          )
                        : const <String, String>{},
                    languageCode: widget.language.name,
                  ),
                ),
            ],
            if (localizedLimousineText(
              offer.mobilisationDisclosure,
              languageCode: widget.language.name,
            ).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  localizedLimousineText(
                    offer.mobilisationDisclosure,
                    languageCode: widget.language.name,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 8),
          Text(
            limousineShowroomPriceLabel(offer, widget.language),
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: limousineShowroomViewKey(offer.offerId),
                onPressed: () {
                  setState(() {
                    if (expanded) {
                      _expanded.remove(offer.offerId);
                    } else {
                      _expanded.add(offer.offerId);
                    }
                  });
                },
                child: Text(
                  expanded
                      ? _t(kLimousineShowroomHideDetails)
                      : _t(kLimousineShowroomView),
                ),
              ),
              if (cta == LimousineShowroomCta.requestQuote)
                FilledButton(
                  key: limousineShowroomQuoteCtaKey(offer.offerId),
                  onPressed: limousineCustomerQuoteCtaEnabled()
                      ? () => _openQuote(offer)
                      : null,
                  child: Text(
                    limousineCustomerQuoteCtaEnabled()
                        ? _t(kLimousineShowroomRequestQuote)
                        : _t(kLimousineShowroomQuoteComingSoon),
                  ),
                ),
              if (cta == LimousineShowroomCta.book)
                FilledButton(
                  key: limousineShowroomBookCtaKey(offer.offerId),
                  onPressed: limousineCustomerBookCtaEnabled()
                      ? () => _openQuote(offer)
                      : null,
                  child: Text(
                    limousineCustomerBookCtaEnabled()
                        ? _t(kLimousineShowroomBook)
                        : _t(kLimousineShowroomBookComingSoon),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _vehiclePhoto(LimousinePublishedOffer offer) {
    final palette = widget.palette;
    final placeholder = Container(
      height: 168,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          colors: [palette.surfaceAlt, palette.gold.withOpacity(0.16)],
        ),
      ),
      child: Icon(
        Icons.directions_car_filled_outlined,
        color: palette.gold,
        size: 36,
      ),
    );
    if (offer.photoUrl.isEmpty) return placeholder;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          offer.photoUrl,
          height: 168,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder,
        ),
      ),
    );
  }

  void _openQuote(LimousinePublishedOffer offer) {
    final bookCta = limousineShowroomCtaFor(offer) == LimousineShowroomCta.book;
    final allowed = bookCta
        ? limousineCustomerBookCtaEnabled()
        : limousineCustomerQuoteCtaEnabled();
    if (!allowed) return;
    final onOpen = widget.onOpenQuote;
    if (onOpen != null) {
      onOpen(offer);
      return;
    }
    openLimousineCustomerQuoteFlow(
      context,
      publicPartnerId: widget.partnerId,
      offer: offer,
      companyName: widget.companyName,
      entryEnabled: limousineCustomerQuoteCtaEnabled(),
    );
  }
}
