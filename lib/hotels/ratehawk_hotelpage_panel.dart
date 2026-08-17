import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';

import 'hotel_model.dart';
import 'ratehawk_hotelpage.dart';
import 'ratehawk_prebook.dart';
import 'ratehawk_prebook_panel.dart';
import 'ratehawk_search.dart';

class RatehawkHotelpageSection extends StatefulWidget {
  const RatehawkHotelpageSection({
    required this.stay,
    required this.languageCode,
    required this.palette,
    this.client,
    this.prebookClient,
    this.controller,
    this.autoLoad = true,
    super.key,
  });

  final HotelStay stay;
  final String languageCode;
  final CustomerThemePalette palette;
  final RatehawkHotelpageClient? client;
  final RatehawkPrebookClient? prebookClient;
  final RatehawkHotelpageController? controller;
  final bool autoLoad;

  @override
  State<RatehawkHotelpageSection> createState() =>
      _RatehawkHotelpageSectionState();
}

class _RatehawkHotelpageSectionState extends State<RatehawkHotelpageSection> {
  late final RatehawkHotelpageController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        RatehawkHotelpageController(client: widget.client, reduceMotion: false);
    _controller.addListener(_onChanged);
    if (widget.autoLoad && canRequestRatehawkHotelpage(widget.stay)) {
      _controller.loadForStay(widget.stay);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!isRatehawkStay(widget.stay) &&
        _controller.state == RatehawkHotelpageLifecycleState.idle &&
        _controller.requestCount == 0) {
      return const SizedBox.shrink();
    }
    if (!canRequestRatehawkHotelpage(widget.stay) &&
        _controller.requestCount == 0 &&
        _controller.state == RatehawkHotelpageLifecycleState.idle) {
      return const SizedBox.shrink();
    }

    final reduceMotion =
        _controller.reduceMotion || MediaQuery.disableAnimationsOf(context);
    final gold = widget.palette.gold;
    final text = widget.palette.textPrimary;
    final muted = widget.palette.textMuted;
    final language = widget.languageCode;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: widget.palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: gold.withOpacity(widget.palette.isDark ? 0.34 : 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ratehawkHotelpageSectionTitle(language),
            style: TextStyle(
              color: text,
              fontSize: 16.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            ratehawkHotelpageStateLabel(_controller.state, language),
            style: TextStyle(
              color: gold.withOpacity(0.92),
              fontSize: 12.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_controller.retrievedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              _controller.retrievedAt!.toLocal().toString(),
              style: TextStyle(
                color: muted.withOpacity(0.9),
                fontSize: 11.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_isLoading && !reduceMotion) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              minHeight: 2,
              color: gold,
              backgroundColor: gold.withOpacity(0.16),
            ),
          ],
          if (_controller.state == RatehawkHotelpageLifecycleState.retryable ||
              _controller.state ==
                  RatehawkHotelpageLifecycleState.unavailable) ...[
            const SizedBox(height: 10),
            Text(
              ratehawkExpiredAvailabilityLabel(language),
              style: TextStyle(
                color: muted,
                fontSize: 12.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_controller.state ==
                RatehawkHotelpageLifecycleState.retryable) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _controller.retry(widget.stay),
                child: Text(ratehawkRetryLabel(language)),
              ),
            ],
          ],
          if (_controller.offers.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final offer in _controller.offers) ...[
              _OfferCard(
                offer: offer,
                snapshot: widget.stay.viewStay,
                languageCode: language,
                palette: widget.palette,
                selected: _controller.selected?.offerRef == offer.offerRef,
                onSelect: _controller.isOfferSelectable(offer)
                    ? () => _controller.selectOffer(offer)
                    : () {},
                selectable: _controller.isOfferSelectable(offer),
              ),
              const SizedBox(height: 8),
            ],
          ],
          if (_controller.selected != null) ...[
            Text(
              ratehawkPrebookRecheckLabel(language),
              style: TextStyle(
                color: muted,
                fontSize: 11.4,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            RatehawkPrebookSection(
              key: ValueKey<String>(_controller.selected!.offerRef),
              offerRef: _controller.selected!.offerRef,
              languageCode: language,
              palette: widget.palette,
              client: widget.prebookClient,
              onBlocked: _controller.markSelectedStale,
              onRefreshAvailability: () => _controller.retry(widget.stay),
              onOtherRooms: _controller.clearSelected,
            ),
          ],
          if (_controller.policies != null)
            _PoliciesBlock(
              policies: _controller.policies!,
              languageCode: language,
              palette: widget.palette,
            ),
        ],
      ),
    );
  }

  bool get _isLoading {
    return _controller.state == RatehawkHotelpageLifecycleState.checkingRooms ||
        _controller.state ==
            RatehawkHotelpageLifecycleState.verifyingPricesAndTaxes ||
        _controller.state ==
            RatehawkHotelpageLifecycleState.checkingCancellationAndConditions;
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.languageCode,
    required this.palette,
    required this.selected,
    required this.onSelect,
    this.selectable = true,
    this.snapshot,
  });

  final RatehawkHotelpageOffer offer;
  final RatehawkViewStaySnapshot? snapshot;
  final String languageCode;
  final CustomerThemePalette palette;
  final bool selected;
  final VoidCallback onSelect;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final gold = palette.gold;
    final text = palette.textPrimary;
    final muted = palette.textMuted;
    final expired = !selectable;
    final nights = snapshot?.nightCount ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? gold : palette.border.withOpacity(0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (offer.roomName != null)
            Text(
              offer.roomName!,
              style: TextStyle(
                color: text,
                fontSize: 14.4,
                fontWeight: FontWeight.w800,
              ),
            ),
          if (offer.roomDescription != null) ...[
            const SizedBox(height: 4),
            Text(
              offer.roomDescription!,
              style: TextStyle(color: muted, fontSize: 12.2, height: 1.3),
            ),
          ],
          if (offer.occupancy != null || offer.adults != null)
            _line(
              languageCode,
              nl: 'Bezetting',
              en: 'Occupancy',
              fr: 'Occupation',
              es: 'Ocupación',
              value:
                  offer.occupancy ??
                  '${offer.adults ?? ''} ${offer.childAges.isEmpty ? '' : offer.childAges.join(', ')}'
                      .trim(),
              muted: muted,
            ),
          if (offer.beds != null)
            _line(
              languageCode,
              nl: 'Bedden',
              en: 'Beds',
              fr: 'Lits',
              es: 'Camas',
              value: offer.beds!,
              muted: muted,
            ),
          if (offer.mealPlan != null)
            _line(
              languageCode,
              nl: 'Maaltijd',
              en: 'Meal plan',
              fr: 'Repas',
              es: 'Comida',
              value: offer.mealPlan!,
              muted: muted,
            ),
          _line(
            languageCode,
            nl: offer.breakfastIncluded
                ? 'Ontbijt inbegrepen'
                : 'Ontbijt niet inbegrepen',
            en: offer.breakfastIncluded
                ? 'Breakfast included'
                : 'Breakfast excluded',
            fr: offer.breakfastIncluded
                ? 'Petit-déjeuner inclus'
                : 'Petit-déjeuner non inclus',
            es: offer.breakfastIncluded
                ? 'Desayuno incluido'
                : 'Desayuno no incluido',
            value: '',
            muted: muted,
          ),
          if (offer.remainingAvailability != null)
            _line(
              languageCode,
              nl: 'Nog beschikbaar',
              en: 'Remaining',
              fr: 'Restant',
              es: 'Restante',
              value: offer.remainingAvailability!,
              muted: muted,
            ),
          const SizedBox(height: 6),
          Text(
            expired
                ? ratehawkExpiredAvailabilityLabel(languageCode)
                : (offer.customerTotalLabel ??
                      offer.customerTotal ??
                      ratehawkExpiredAvailabilityLabel(languageCode)),
            style: TextStyle(
              color: gold,
              fontSize: 13.4,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (offer.currency != null)
            Text(
              offer.currency!,
              style: TextStyle(color: muted, fontSize: 11.4),
            ),
          if (nights > 0)
            _line(
              languageCode,
              nl: 'Verblijfsduur',
              en: 'Stay duration',
              fr: 'Durée du séjour',
              es: 'Duración de la estancia',
              value: '$nights',
              muted: muted,
            ),
          for (final tax in offer.includedTaxes)
            _line(
              languageCode,
              nl: 'Inbegrepen belasting',
              en: 'Included tax',
              fr: 'Taxe incluse',
              es: 'Impuesto incluido',
              value: [tax.name, tax.amount].whereType<String>().join(' '),
              muted: muted,
            ),
          for (final tax in offer.excludedTaxes)
            _line(
              languageCode,
              nl: tax.payableWhere == 'property'
                  ? 'Te betalen in het hotel'
                  : 'Niet-inbegrepen toeslag',
              en: tax.payableWhere == 'property'
                  ? 'Payable at the property'
                  : 'Excluded fee',
              fr: tax.payableWhere == 'property'
                  ? 'Payable à l’hôtel'
                  : 'Frais exclus',
              es: tax.payableWhere == 'property'
                  ? 'A pagar en el hotel'
                  : 'Tasa excluida',
              value: [tax.name, tax.amount].whereType<String>().join(' '),
              muted: muted,
            ),
          if (offer.vatIncluded != null)
            _line(
              languageCode,
              nl: offer.vatIncluded! ? 'Btw inbegrepen' : 'Btw niet inbegrepen',
              en: offer.vatIncluded! ? 'VAT included' : 'VAT excluded',
              fr: offer.vatIncluded! ? 'TVA incluse' : 'TVA non incluse',
              es: offer.vatIncluded! ? 'IVA incluido' : 'IVA no incluido',
              value: '',
              muted: muted,
            ),
          if (offer.payment != null) ...[
            if (offer.payment!.type != null)
              _line(
                languageCode,
                nl: 'Betaling',
                en: 'Payment',
                fr: 'Paiement',
                es: 'Pago',
                value: offer.payment!.type!,
                muted: muted,
              ),
            if (offer.payment!.recipient != null)
              _line(
                languageCode,
                nl: 'Betalingsontvanger',
                en: 'Payment recipient',
                fr: 'Destinataire du paiement',
                es: 'Destinatario del pago',
                value: offer.payment!.recipient!,
                muted: muted,
              ),
            if (offer.payment!.timing != null)
              _line(
                languageCode,
                nl: 'Betaalmoment',
                en: 'Payment timing',
                fr: 'Moment du paiement',
                es: 'Momento del pago',
                value: offer.payment!.timing!,
                muted: muted,
              ),
          ],
          _line(
            languageCode,
            nl: offer.cardDataRequired
                ? 'Kaartgegevens vereist'
                : 'Geen kaartgegevens vereist',
            en: offer.cardDataRequired
                ? 'Card details required'
                : 'Card details not required',
            fr: offer.cardDataRequired
                ? 'Données de carte requises'
                : 'Données de carte non requises',
            es: offer.cardDataRequired
                ? 'Datos de tarjeta requeridos'
                : 'Datos de tarjeta no requeridos',
            value: '',
            muted: muted,
          ),
          _line(
            languageCode,
            nl: offer.cvcRequired ? 'CVC vereist' : 'CVC niet vereist',
            en: offer.cvcRequired ? 'CVC required' : 'CVC not required',
            fr: offer.cvcRequired ? 'CVC requis' : 'CVC non requis',
            es: offer.cvcRequired ? 'CVC requerido' : 'CVC no requerido',
            value: '',
            muted: muted,
          ),
          if (offer.deposit.disclosed) ...[
            _line(
              languageCode,
              nl: 'Hoteldeposito',
              en: 'Hotel deposit',
              fr: 'Dépôt hôtelier',
              es: 'Depósito del hotel',
              value: [
                offer.deposit.amount,
                offer.deposit.currency,
              ].whereType<String>().join(' '),
              muted: muted,
            ),
            _line(
              languageCode,
              nl: offer.deposit.refundable
                  ? 'Deposito terugbetaalbaar'
                  : 'Deposito niet terugbetaalbaar',
              en: offer.deposit.refundable
                  ? 'Deposit refundable'
                  : 'Deposit non-refundable',
              fr: offer.deposit.refundable
                  ? 'Dépôt remboursable'
                  : 'Dépôt non remboursable',
              es: offer.deposit.refundable
                  ? 'Depósito reembolsable'
                  : 'Depósito no reembolsable',
              value: '',
              muted: muted,
            ),
            if (offer.deposit.recipient != null)
              _line(
                languageCode,
                nl: 'Deposito-ontvanger',
                en: 'Deposit recipient',
                fr: 'Destinataire du dépôt',
                es: 'Destinatario del depósito',
                value: offer.deposit.recipient!,
                muted: muted,
              ),
            if (offer.deposit.timing != null)
              _line(
                languageCode,
                nl: 'Deposito-timing',
                en: 'Deposit timing',
                fr: 'Moment du dépôt',
                es: 'Momento del depósito',
                value: offer.deposit.timing!,
                muted: muted,
              ),
          ],
          _line(
            languageCode,
            nl: offer.cancellation.refundable
                ? 'Annuleerbaar'
                : 'Niet-annuleerbaar',
            en: offer.cancellation.refundable ? 'Refundable' : 'Non-refundable',
            fr: offer.cancellation.refundable
                ? 'Remboursable'
                : 'Non remboursable',
            es: offer.cancellation.refundable
                ? 'Reembolsable'
                : 'No reembolsable',
            value: '',
            muted: muted,
          ),
          if (offer.cancellation.freeCancellationBefore != null)
            _line(
              languageCode,
              nl: 'Gratis annuleren tot',
              en: 'Free cancellation until',
              fr: 'Annulation gratuite jusqu’au',
              es: 'Cancelación gratuita hasta',
              value: offer.cancellation.freeCancellationBefore!,
              muted: muted,
            ),
          for (final penalty in offer.cancellation.penalties)
            _line(
              languageCode,
              nl: 'Annuleringsboete',
              en: 'Cancellation penalty',
              fr: 'Pénalité d’annulation',
              es: 'Penalización de cancelación',
              value: [
                penalty.name,
                penalty.amount,
                penalty.payableWhere,
              ].whereType<String>().join(' '),
              muted: muted,
            ),
          if (offer.noShow.disclosed) ...[
            _line(
              languageCode,
              nl: 'No-show',
              en: 'No-show',
              fr: 'No-show',
              es: 'No-show',
              value: [
                offer.noShow.amount,
                offer.noShow.currency,
              ].whereType<String>().join(' '),
              muted: muted,
            ),
            if (offer.noShow.fromTime != null)
              _line(
                languageCode,
                nl: 'No-show vanaf',
                en: 'No-show from',
                fr: 'No-show à partir de',
                es: 'No-show desde',
                value: [
                  offer.noShow.fromTime,
                  offer.noShow.timezoneContext,
                ].whereType<String>().join(' '),
                muted: muted,
              ),
          ],
          const SizedBox(height: 8),
          if (offer.isSelectable)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onSelect,
                child: Text(ratehawkSelectOfferLabel(languageCode)),
              ),
            )
          else
            Text(
              ratehawkExpiredAvailabilityLabel(languageCode),
              style: TextStyle(
                color: muted,
                fontSize: 12.2,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  Widget _line(
    String languageCode, {
    required String nl,
    required String en,
    required String fr,
    required String es,
    required String value,
    required Color muted,
  }) {
    final label = ratehawkSearchLabel(
      languageCode,
      nl: nl,
      en: en,
      fr: fr,
      es: es,
    );
    final display = value.trim().isEmpty ? label : '$label: $value';
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(
        display,
        style: TextStyle(color: muted, fontSize: 11.6, height: 1.25),
      ),
    );
  }
}

class _PoliciesBlock extends StatelessWidget {
  const _PoliciesBlock({
    required this.policies,
    required this.languageCode,
    required this.palette,
  });

  final RatehawkStaticPolicies policies;
  final String languageCode;
  final CustomerThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final muted = palette.textMuted;
    final sections = <MapEntry<String, List<String>>>[
      MapEntry(
        ratehawkSearchLabel(
          languageCode,
          nl: 'Voorzieningen',
          en: 'Amenities',
          fr: 'Équipements',
          es: 'Servicios',
        ),
        policies.amenities,
      ),
      MapEntry(
        ratehawkSearchLabel(
          languageCode,
          nl: 'Huisdieren',
          en: 'Pets',
          fr: 'Animaux',
          es: 'Mascotas',
        ),
        policies.pets,
      ),
      MapEntry(
        ratehawkSearchLabel(
          languageCode,
          nl: 'Kinderen',
          en: 'Children',
          fr: 'Enfants',
          es: 'Niños',
        ),
        policies.children,
      ),
      MapEntry(
        ratehawkSearchLabel(
          languageCode,
          nl: 'Babybedden',
          en: 'Cots',
          fr: 'Lits bébé',
          es: 'Cunas',
        ),
        policies.cots,
      ),
      MapEntry(
        ratehawkSearchLabel(
          languageCode,
          nl: 'Extra bedden',
          en: 'Extra beds',
          fr: 'Lits supplémentaires',
          es: 'Camas extra',
        ),
        policies.extraBeds,
      ),
      MapEntry(
        ratehawkSearchLabel(
          languageCode,
          nl: 'Toegankelijkheid',
          en: 'Accessibility',
          fr: 'Accessibilité',
          es: 'Accesibilidad',
        ),
        policies.accessibility,
      ),
      MapEntry(
        ratehawkSearchLabel(
          languageCode,
          nl: 'Parkeren',
          en: 'Parking',
          fr: 'Parking',
          es: 'Aparcamiento',
        ),
        policies.parking,
      ),
      MapEntry(
        ratehawkSearchLabel(
          languageCode,
          nl: 'Internet',
          en: 'Internet',
          fr: 'Internet',
          es: 'Internet',
        ),
        policies.internet,
      ),
      MapEntry(
        ratehawkSearchLabel(
          languageCode,
          nl: 'Vroeg/laat inchecken',
          en: 'Early/late check-in',
          fr: 'Arrivée anticipée/tardive',
          es: 'Check-in temprano/tardío',
        ),
        policies.earlyLateCheckIn,
      ),
      MapEntry(
        ratehawkSearchLabel(
          languageCode,
          nl: 'Belangrijke hotelinformatie',
          en: 'Important hotel information',
          fr: 'Informations importantes',
          es: 'Información importante',
        ),
        <String>[
          if (policies.importantInformation != null)
            policies.importantInformation!,
        ],
      ),
      MapEntry(
        ratehawkSearchLabel(
          languageCode,
          nl: 'Beleid',
          en: 'Policies',
          fr: 'Politiques',
          es: 'Políticas',
        ),
        policies.policyStruct,
      ),
    ];
    final visible = sections
        .where((entry) => entry.value.isNotEmpty)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (policies.checkIn != null || policies.checkOut != null) ...[
          const SizedBox(height: 8),
          if (policies.checkIn != null)
            Text(
              '${ratehawkSearchLabel(languageCode, nl: 'Inchecken', en: 'Check-in', fr: 'Arrivée', es: 'Entrada')}: ${policies.checkIn}',
              style: TextStyle(color: muted, fontSize: 11.6),
            ),
          if (policies.checkOut != null)
            Text(
              '${ratehawkSearchLabel(languageCode, nl: 'Uitchecken', en: 'Check-out', fr: 'Départ', es: 'Salida')}: ${policies.checkOut}',
              style: TextStyle(color: muted, fontSize: 11.6),
            ),
        ],
        for (final section in visible) ...[
          const SizedBox(height: 8),
          Text(
            section.key,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 12.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          for (final value in section.value)
            Text(
              value,
              style: TextStyle(color: muted, fontSize: 11.6, height: 1.25),
            ),
        ],
        if (policies.hasUnmappedCritical) ...[
          const SizedBox(height: 8),
          Text(
            ratehawkUnmappedPolicyLabel(languageCode),
            style: TextStyle(
              color: palette.gold,
              fontSize: 11.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          for (final name in policies.unmappedCriticalFieldNames)
            Text(name, style: TextStyle(color: muted, fontSize: 11.2)),
        ],
      ],
    );
  }
}
