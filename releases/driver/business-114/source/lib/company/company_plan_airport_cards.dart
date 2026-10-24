// COMPANY-AGENDA-P0 — Belgian airport destination cards. Catalog stays canonical.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_plan_ride_mode.dart';

const String kCompanyPlanAirportCardDir = 'assets/booking/airports/v1';
const double kCompanyPlanAirportCardAspect = 16 / 9;
const BoxFit kCompanyPlanAirportCardFit = BoxFit.cover;

const List<String> kCompanyPlanFeaturedAirportIata = <String>[
  'BRU',
  'CRL',
  'ANR',
  'OST',
  'LGG',
  'KJK',
];

const String kCompanyPlanAirportCardOtherId = 'other';

const String kCompanyPlanAirportCardBru =
    '$kCompanyPlanAirportCardDir/fluxidi_airport_bru_brussels_zaventem_v1.webp';
const String kCompanyPlanAirportCardCrl =
    '$kCompanyPlanAirportCardDir/fluxidi_airport_crl_charleroi_v1.webp';
const String kCompanyPlanAirportCardAnr =
    '$kCompanyPlanAirportCardDir/fluxidi_airport_anr_antwerp_v1.webp';
const String kCompanyPlanAirportCardOst =
    '$kCompanyPlanAirportCardDir/fluxidi_airport_ost_ostend_bruges_v1.webp';
const String kCompanyPlanAirportCardLgg =
    '$kCompanyPlanAirportCardDir/fluxidi_airport_lgg_liege_v1.webp';
const String kCompanyPlanAirportCardKjk =
    '$kCompanyPlanAirportCardDir/fluxidi_airport_kjk_kortrijk_wevelgem_v1.webp';

Key companyPlanAirportCardKey(String id) {
  return Key('company_plan_airport_card_${id.trim().toLowerCase()}');
}

String? companyPlanAirportCardAssetForIata(String? iata) {
  return switch (iata?.trim().toUpperCase() ?? '') {
    'BRU' => kCompanyPlanAirportCardBru,
    'CRL' => kCompanyPlanAirportCardCrl,
    'ANR' => kCompanyPlanAirportCardAnr,
    'OST' => kCompanyPlanAirportCardOst,
    'LGG' => kCompanyPlanAirportCardLgg,
    'KJK' => kCompanyPlanAirportCardKjk,
    _ => null,
  };
}

String companyPlanAirportCardAsset(String? iata) {
  return companyPlanAirportCardAssetForIata(iata) ??
      kCompanyPlanAirportModeAsset;
}

String companyPlanAirportCardCompactTitle(String iata) {
  final catalog = airportByIata(iata);
  if (catalog != null) {
    final city = catalog.city.trim();
    final code = catalog.iata.trim().toUpperCase();
    if (city.isNotEmpty && code.isNotEmpty) return '$city · $code';
    if (code.isNotEmpty) return code;
  }
  return companyPlanAirportCardTitle(iata);
}

String companyPlanAirportCardTitle(String iata) {
  final catalog = airportByIata(iata);
  if (catalog != null && catalog.name.trim().isNotEmpty) {
    return catalog.name.trim();
  }
  return switch (iata.trim().toUpperCase()) {
    'BRU' => 'Brussels Airport',
    'CRL' => 'Brussels South Charleroi Airport',
    'ANR' => 'Antwerp Airport',
    'OST' => 'Ostend-Bruges Airport',
    'LGG' => 'Liège Airport',
    'KJK' => 'Kortrijk-Wevelgem Airport',
    _ => iata.trim().toUpperCase(),
  };
}

AirportCatalogAirport? companyPlanAirportCatalogRecord(String iata) {
  return airportByIata(iata);
}

bool companyPlanFeaturedAirportIataContains(String? iata) {
  final code = iata?.trim().toUpperCase() ?? '';
  return kCompanyPlanFeaturedAirportIata.contains(code);
}

const Key kCompanyPlanAirportPrevKey = Key('company_plan_airport_prev');
const Key kCompanyPlanAirportNextKey = Key('company_plan_airport_next');

const List<int> kCompanyPlanAirportWaitPresets = <int>[15, 30, 45, 60, 90];

int companyPlanAirportCarouselIndex(String? iata) {
  final code = iata?.trim().toUpperCase() ?? '';
  final index = kCompanyPlanFeaturedAirportIata.indexOf(code);
  return index >= 0 ? index : kCompanyPlanFeaturedAirportIata.length;
}

class CompanyPlanAirportDestinationCards extends StatefulWidget {
  const CompanyPlanAirportDestinationCards({
    super.key,
    required this.language,
    required this.selectedIata,
    required this.onSelectedIata,
    required this.onSelectedOther,
    this.cardKeyOf,
    this.compact = false,
  });

  final AppLanguage language;
  final String selectedIata;
  final ValueChanged<String> onSelectedIata;
  final VoidCallback onSelectedOther;
  final Key Function(String id)? cardKeyOf;
  final bool compact;

  @override
  State<CompanyPlanAirportDestinationCards> createState() =>
      _CompanyPlanAirportDestinationCardsState();
}

class _CompanyPlanAirportDestinationCardsState
    extends State<CompanyPlanAirportDestinationCards> {
  final ScrollController _scroll = ScrollController();
  bool _canBack = false;
  bool _canForward = true;
  bool _programmaticScroll = false;
  double _lastCardWidth = 240;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelected(animate: false);
      _syncArrows();
    });
  }

  @override
  void didUpdateWidget(covariant CompanyPlanAirportDestinationCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIata != widget.selectedIata) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToSelected(animate: true),
      );
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_syncArrows);
    _scroll.dispose();
    super.dispose();
  }

  void _syncArrows() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final back = position.pixels > 8;
    final forward = position.pixels < position.maxScrollExtent - 8;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  double _itemExtent(double cardWidth) => cardWidth + 8;

  void _scrollToSelected({required bool animate}) {
    if (!_scroll.hasClients) return;
    if (!animate && widget.selectedIata.trim().isEmpty) return;
    final width = _lastCardWidth;
    final index = companyPlanAirportCarouselIndex(widget.selectedIata);
    final target = (index * _itemExtent(width)).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _moveTo(target, animate: animate);
  }

  Future<void> _moveTo(double target, {required bool animate}) async {
    if (!_scroll.hasClients) return;
    final clamped = target.clamp(0.0, _scroll.position.maxScrollExtent);
    if ((clamped - _scroll.offset).abs() < 1) return;
    _programmaticScroll = true;
    try {
      if (animate) {
        await _scroll.animateTo(
          clamped,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scroll.jumpTo(clamped);
      }
    } finally {
      _programmaticScroll = false;
      _syncArrows();
    }
  }

  void _step(int direction) {
    if (!_scroll.hasClients) return;
    final width = _lastCardWidth;
    final extent = _itemExtent(width);
    final current = (_scroll.offset / extent).round();
    final next = (current + direction).clamp(
      0,
      kCompanyPlanFeaturedAirportIata.length,
    );
    unawaited(
      _moveTo(
        (next * extent).clamp(0.0, _scroll.position.maxScrollExtent),
        animate: true,
      ),
    );
  }

  void _snap() {
    if (_programmaticScroll || !_scroll.hasClients) return;
    final width = _lastCardWidth;
    final extent = _itemExtent(width);
    final index = (_scroll.offset / extent).round().clamp(
      0,
      kCompanyPlanFeaturedAirportIata.length,
    );
    unawaited(
      _moveTo(
        (index * extent).clamp(0.0, _scroll.position.maxScrollExtent),
        animate: true,
      ),
    );
  }

  double _cardWidth(double maxWidth) {
    if (widget.compact) {
      return 148;
    }
    final finite = maxWidth.isFinite ? maxWidth : 390.0;
    final usable = (finite - 72).clamp(200.0, finite);
    if (usable < 520) return (usable * 0.86).clamp(200.0, 280.0);
    if (usable < 900) return (usable - 8) / 2.15;
    return (usable - 16) / 3.15;
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedIata.trim().toUpperCase();
    final otherSelected =
        selected.isEmpty || !companyPlanFeaturedAirportIataContains(selected);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final cardWidth = _cardWidth(constraints.maxWidth);
        _lastCardWidth = cardWidth;
        final ids = <String>[
          ...kCompanyPlanFeaturedAirportIata,
          kCompanyPlanAirportCardOtherId,
        ];
        final list = SizedBox(
              height: widget.compact
                  ? 92
                  : cardWidth / kCompanyPlanAirportCardAspect + 4,
              child: Row(
                children: [
                  if (!widget.compact)
                    _ArrowButton(
                      key: kCompanyPlanAirportPrevKey,
                      icon: Icons.chevron_left,
                      enabled: _canBack,
                      onPressed: () => _step(-1),
                    ),
                  Expanded(
                    child: Listener(
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent && _scroll.hasClients) {
                          final delta = event.scrollDelta.dx.abs() >
                                  event.scrollDelta.dy.abs()
                              ? event.scrollDelta.dx
                              : event.scrollDelta.dy;
                          _scroll.jumpTo(
                            (_scroll.offset + delta)
                                .clamp(0.0, _scroll.position.maxScrollExtent),
                          );
                        }
                      },
                      child: NotificationListener<ScrollEndNotification>(
                        onNotification: (notification) {
                          if (!_programmaticScroll) _snap();
                          return false;
                        },
                        child: SingleChildScrollView(
                          controller: _scroll,
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: [
                              for (var index = 0; index < ids.length; index++) ...[
                                if (index > 0) const SizedBox(width: gap),
                                SizedBox(
                                  width: cardWidth,
                                  child: _AirportCard(
                                    cardKey: (widget.cardKeyOf ??
                                            companyPlanAirportCardKey)(
                                          ids[index],
                                        ),
                                    iata: ids[index] == kCompanyPlanAirportCardOtherId
                                        ? ''
                                        : ids[index],
                                    title: ids[index] == kCompanyPlanAirportCardOtherId
                                        ? kCompanyAgendaOtherAirport.of(
                                            widget.language,
                                          )
                                        : widget.compact
                                            ? companyPlanAirportCardCompactTitle(
                                                ids[index],
                                              )
                                            : companyPlanAirportCardTitle(ids[index]),
                                    assetPath: ids[index] ==
                                            kCompanyPlanAirportCardOtherId
                                        ? kCompanyPlanAirportModeAsset
                                        : companyPlanAirportCardAsset(ids[index]),
                                    selected: ids[index] ==
                                            kCompanyPlanAirportCardOtherId
                                        ? otherSelected
                                        : selected == ids[index],
                                    compact: widget.compact,
                                    onTap: ids[index] ==
                                            kCompanyPlanAirportCardOtherId
                                        ? widget.onSelectedOther
                                        : () => widget.onSelectedIata(ids[index]),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!widget.compact)
                    _ArrowButton(
                      key: kCompanyPlanAirportNextKey,
                      icon: Icons.chevron_right,
                      enabled: _canForward,
                      onPressed: () => _step(1),
                    ),
                ],
              ),
            );
        return list;
      },
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    super.key,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _AirportCard extends StatelessWidget {
  const _AirportCard({
    required this.cardKey,
    required this.iata,
    required this.title,
    required this.assetPath,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final Key cardKey;
  final String iata;
  final String title;
  final String assetPath;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = iata.isEmpty ? title : '$title, $iata';
    return Material(
      key: cardKey,
      color: selected ? scheme.primaryContainer : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outline.withValues(alpha: 0.35),
          width: selected ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          button: true,
          selected: selected,
          label: semantic,
          child: AspectRatio(
            aspectRatio: kCompanyPlanAirportCardAspect,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  assetPath,
                  fit: kCompanyPlanAirportCardFit,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.medium,
                  cacheWidth: 480,
                  errorBuilder: (_, __, ___) => Image.asset(
                    kCompanyPlanAirportModeAsset,
                    fit: kCompanyPlanAirportCardFit,
                    alignment: Alignment.center,
                    errorBuilder: (_, __, ___) => Icon(
                      kCompanyPlanAirportModeIcon,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Color(0x00000000),
                        Color(0x99000000),
                      ],
                    ),
                  ),
                ),
                if (selected)
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.check_circle,
                        color: scheme.primary,
                        size: 22,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        title,
                        maxLines: compact ? 1 : 2,
                        softWrap: !compact,
                        overflow: TextOverflow.ellipsis,
                        style: (compact
                                ? theme.textTheme.labelLarge
                                : theme.textTheme.titleSmall)
                            ?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!compact && iata.isNotEmpty)
                        Text(
                          iata,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
