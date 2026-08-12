import 'dart:ui';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_streetlevel_marker_anchor.dart';

class _CockpitThemeTokens {
  const _CockpitThemeTokens({
    required this.panelBackground,
    required this.panelBorder,
    required this.panelGlow,
    required this.tileBackground,
    required this.tileBorder,
    required this.primaryText,
    required this.mutedText,
    required this.accent,
    required this.hotBackground,
  });

  final Color panelBackground;
  final Color panelBorder;
  final Color panelGlow;
  final Color tileBackground;
  final Color tileBorder;
  final Color primaryText;
  final Color mutedText;
  final Color accent;
  final Color hotBackground;
}

/// Fluxidi Driver — Cockpit (compact premium)
class CockpitWidget extends StatefulWidget {
  final String etaText;
  final String kmText;
  final String priceText;

  /// Metric tile label above [priceText]. Planned rides use `Vaste prijs`;
  /// street/direct keep the existing `€` meter label.
  final String priceLabel;

  final bool tripStarted;
  final bool isWaiting;
  final bool navActive;
  final bool embedded;

  /// NAV-RELEASE-FINAL-FLOW-1: when false, the NAV-to-pickup control is
  /// omitted (direct street draft: driver is already at pickup A).
  final bool showNavToPickupAction;

  final VoidCallback onNav;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onWait;
  final VoidCallback onGo;
  final ValueListenable<DriverThemeVariant>? themeListenable;

  /// NAV-UI-R6F: compact icon-only map actions (recenter, satellite, offline,
  /// diagnostics, more…) integrated into the cockpit bar during route/nav.
  final List<Widget> secondaryActions;

  /// NAV-PRES-TABLET-CONTROLS-ZOOM-1: tablet-enlarged secondary row spacing.
  final double secondaryActionGap;

  /// NAV-PRES-TABLET-CONTROLS-ZOOM-1: secondary row height (touch targets).
  final double secondaryActionRowHeight;

  /// NAV-PRES-TABLET-PORTRAIT-POLISH-1: vertical gap metric row → primary row.
  final double metricsToPrimaryGap;

  /// NAV-PRES-TABLET-PORTRAIT-POLISH-1: vertical gap primary row → icon row.
  final double primaryToSecondaryGap;

  /// NAV-PRES-TABLET-PORTRAIT-POLISH-1: horizontal inset for icon row edges.
  final double secondaryRowHorizontalInset;

  /// NAV-PRES-TABLET-PORTRAIT-POLISH-1: even distribution across width.
  final bool distributeSecondaryRowEvenly;

  /// NAV-MOBILE-LANDSCAPE-KPI-PRIORITY-AND-FIRST-3D-CHOICE-FIX-1: phone
  /// landscape collapse state. It gives ETA/KM/fare more width and retains
  /// only stop/end + pause in the direct ride-control zone.
  final bool landscapeKpiPriority;

  /// Phone landscape Navigatie: tighter strip padding inside fixed panel height.
  final bool flatterPhoneLandscape;

  const CockpitWidget({
    super.key,
    required this.etaText,
    required this.kmText,
    required this.priceText,
    this.priceLabel = '€',
    required this.tripStarted,
    required this.isWaiting,
    required this.navActive,
    required this.onNav,
    required this.onStart,
    required this.onStop,
    required this.onWait,
    required this.onGo,
    this.embedded = false,
    this.showNavToPickupAction = true,
    this.themeListenable,
    this.secondaryActions = const <Widget>[],
    this.secondaryActionGap = 6,
    this.secondaryActionRowHeight = 44,
    this.metricsToPrimaryGap = 4,
    this.primaryToSecondaryGap = 4,
    this.secondaryRowHorizontalInset = 0,
    this.distributeSecondaryRowEvenly = false,
    this.landscapeKpiPriority = false,
    this.flatterPhoneLandscape = false,
  });

  @override
  State<CockpitWidget> createState() => _CockpitWidgetState();
}

class _CockpitWidgetState extends State<CockpitWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  _CockpitThemeTokens _activeTheme = _themeForVariant(
    DriverThemeVariant.nightGold,
  );

  static const double _minTapSize = 44.0;

  static _CockpitThemeTokens _themeForVariant(DriverThemeVariant variant) {
    if (variant == DriverThemeVariant.midnightBlue) {
      return const _CockpitThemeTokens(
        panelBackground: Color(0xFF0A162B),
        panelBorder: Color(0x805AA7E8),
        panelGlow: Color(0x334DA3FF),
        tileBackground: Color(0xFF0E1E37),
        tileBorder: Color(0x665A9DD9),
        primaryText: Color(0xFFEAF6FF),
        mutedText: Color(0xFFAFCBEA),
        accent: Color(0xFF4DA3FF),
        hotBackground: Color(0xFF112F54),
      );
    }
    if (variant == DriverThemeVariant.highContrast) {
      return const _CockpitThemeTokens(
        panelBackground: Color(0xFF20160B),
        panelBorder: Color(0x99E8C57E),
        panelGlow: Color(0x33E8C57E),
        tileBackground: Color(0xFF2A1D0F),
        tileBorder: Color(0x88D8B56F),
        primaryText: Color(0xFFFFF0D0),
        mutedText: Color(0xFFE1CCA0),
        accent: Color(0xFFE8C57E),
        hotBackground: Color(0xFF3A2A15),
      );
    }
    return const _CockpitThemeTokens(
      panelBackground: Color(0xFF08142D),
      panelBorder: Color(0x80FFD54F),
      panelGlow: Color(0x33F5C400),
      tileBackground: Color(0xFF101E3A),
      tileBorder: Color(0x26FFFFFF),
      primaryText: Colors.white,
      mutedText: Color(0xCCFFFFFF),
      accent: Color(0xFFFFD54F),
      hotBackground: Color(0xFF2B260D),
    );
  }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.tripStarted) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant CockpitWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.tripStarted && widget.tripStarted) {
      _pulse.repeat(reverse: true);
    } else if (oldWidget.tripStarted && !widget.tripStarted) {
      _pulse.stop();
      _pulse.value = 0.0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DriverThemeVariant>(
      valueListenable: widget.themeListenable ?? driverThemeNotifier,
      builder: (context, variant, _) {
        _activeTheme = _themeForVariant(variant);
        final eta = (widget.etaText.trim().isEmpty) ? '—' : widget.etaText;
        final km = (widget.kmText.trim().isEmpty) ? '—' : widget.kmText;
        final price = (widget.priceText.trim().isEmpty)
            ? '—'
            : widget.priceText;
        final priceLabel = widget.priceLabel.trim().isEmpty
            ? '€'
            : widget.priceLabel.trim();
        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        final panel = AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final t = widget.tripStarted ? _pulse.value : 0.0;
            final borderOpacity = widget.tripStarted ? (0.74 + 0.08 * t) : 0.34;

            return ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: Container(
                  decoration: BoxDecoration(
                    color: _activeTheme.panelBackground.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _activeTheme.panelBorder.withOpacity(
                        borderOpacity * 0.72,
                      ),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.28),
                        blurRadius: 6,
                        spreadRadius: 0.2,
                      ),
                      BoxShadow(
                        color: _activeTheme.panelGlow.withOpacity(0.35),
                        blurRadius: 12,
                        spreadRadius: 0.1,
                      ),
                    ],
                  ),
                  child: isLandscape
                      ? _buildLandscapeStrip(
                          eta: eta,
                          km: km,
                          price: price,
                          priceLabel: priceLabel,
                        )
                      : _buildPortraitPanel(
                          eta: eta,
                          km: km,
                          price: price,
                          priceLabel: priceLabel,
                        ),
                ),
              ),
            );
          },
        );

        if (widget.embedded) {
          return panel;
        }

        return SafeArea(
          bottom: true,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              child: panel,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPortraitPanel({
    required String eta,
    required String km,
    required String price,
    required String priceLabel,
  }) {
    const metricTileGap = 4.0;
    final metricsPrimaryGap = widget.metricsToPrimaryGap;
    final primarySecondaryGap = widget.primaryToSecondaryGap;
    final hasSecondary = widget.secondaryActions.isNotEmpty;
    final secondaryBlockHeight = hasSecondary
        ? widget.secondaryActionRowHeight + primarySecondaryGap
        : 0.0;
    return SizedBox(
      // NAV-VEHICLE-MODE-CAR-ARROW-1: shared with the Street Level marker
      // anchor so the marker sits just above this panel. The outer decoration
      // border adds kCockpitPanelBorderTotal, so the rendered panel matches
      // kCockpitPortraitBasePanelHeight (the value the anchor uses).
      height: kCockpitPortraitBaseContentHeight + secondaryBlockHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
        child: Column(
          children: [
            Expanded(
              flex: 6,
              child: Row(
                children: [
                  _metricTile('ETA', eta),
                  const SizedBox(width: metricTileGap),
                  _metricTile('KM', km),
                  const SizedBox(width: metricTileGap),
                  _metricTile(priceLabel, price),
                ],
              ),
            ),
            SizedBox(height: metricsPrimaryGap),
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  if (widget.showNavToPickupAction) ...[
                    _iconBtn(
                      keyId: 'nav',
                      label: widget.navActive ? 'Navigation on' : 'Navigation',
                      icon: widget.navActive
                          ? Icons.navigation
                          : Icons.navigation_outlined,
                      onTap: widget.onNav,
                      hot: widget.navActive,
                    ),
                    const SizedBox(width: metricTileGap),
                  ],
                  _iconBtn(
                    keyId: 'primary',
                    label: widget.tripStarted ? 'Stop trip' : 'Start trip',
                    icon: widget.tripStarted
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outline,
                    onTap: widget.tripStarted ? widget.onStop : widget.onStart,
                    hot: widget.tripStarted,
                  ),
                  const SizedBox(width: metricTileGap),
                  _iconBtn(
                    keyId: 'wait',
                    label: widget.isWaiting ? 'Resume driving' : 'Pause / wait',
                    icon: widget.isWaiting ? Icons.play_arrow : Icons.pause,
                    onTap: widget.isWaiting ? widget.onGo : widget.onWait,
                    hot: widget.isWaiting,
                  ),
                ],
              ),
            ),
            if (hasSecondary) ...[
              SizedBox(height: primarySecondaryGap),
              SizedBox(
                height: widget.secondaryActionRowHeight,
                child: _secondaryActionsRow(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _secondaryActionsRow() {
    if (widget.distributeSecondaryRowEvenly) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: widget.secondaryRowHorizontalInset,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: widget.secondaryActions,
        ),
      );
    }
    final children = <Widget>[];
    final actionGap = widget.secondaryActionGap;
    for (final action in widget.secondaryActions) {
      if (children.isNotEmpty) children.add(SizedBox(width: actionGap));
      children.add(action);
    }
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.secondaryRowHorizontalInset,
      ),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }

  Widget _buildLandscapeStrip({
    required String eta,
    required String km,
    required String price,
    required String priceLabel,
  }) {
    return SizedBox(
      // NAV-VEHICLE-MODE-CAR-ARROW-1: shared with the Street Level marker
      // anchor so the marker sits just above this panel. The outer decoration
      // border adds kCockpitPanelBorderTotal, so the rendered strip matches
      // kCockpitLandscapePanelHeight (the value the anchor uses).
      height: kCockpitLandscapeContentHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 6,
          vertical: widget.flatterPhoneLandscape ? 1 : 2,
        ),
        child: Row(
          children: [
            Expanded(
              flex: widget.landscapeKpiPriority ? 8 : 6,
              child: Row(
                children: [
                  _metricTile(
                    'ETA',
                    eta,
                    compact: !widget.landscapeKpiPriority,
                    dense: widget.flatterPhoneLandscape,
                  ),
                  const SizedBox(width: 4),
                  _metricTile(
                    'KM',
                    km,
                    compact: !widget.landscapeKpiPriority,
                    dense: widget.flatterPhoneLandscape,
                  ),
                  const SizedBox(width: 4),
                  _metricTile(
                    priceLabel,
                    price,
                    compact: !widget.landscapeKpiPriority,
                    dense: widget.flatterPhoneLandscape,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              flex: widget.landscapeKpiPriority ? 4 : 5,
              child: Row(
                children: [
                  if (!widget.landscapeKpiPriority &&
                      widget.showNavToPickupAction) ...[
                    _iconBtn(
                      keyId: 'nav',
                      label: widget.navActive
                          ? 'Navigation on'
                          : 'Navigation',
                      icon: widget.navActive
                          ? Icons.navigation
                          : Icons.navigation_outlined,
                      onTap: widget.onNav,
                      hot: widget.navActive,
                    ),
                    const SizedBox(width: 4),
                  ],
                  _iconBtn(
                    keyId: 'primary',
                    label: widget.tripStarted ? 'Stop trip' : 'Start trip',
                    icon: widget.tripStarted
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outline,
                    onTap: widget.tripStarted ? widget.onStop : widget.onStart,
                    hot: widget.tripStarted,
                  ),
                  const SizedBox(width: 4),
                  _iconBtn(
                    keyId: 'wait',
                    label: widget.isWaiting ? 'Resume driving' : 'Pause / wait',
                    icon: widget.isWaiting ? Icons.play_arrow : Icons.pause,
                    onTap: widget.isWaiting ? widget.onGo : widget.onWait,
                    hot: widget.isWaiting,
                  ),
                ],
              ),
            ),
            if (widget.secondaryActions.isNotEmpty) ...[
              SizedBox(width: widget.secondaryActionGap),
              _secondaryActionsRow(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metricTile(String label, String value, {bool compact = false, bool dense = false}) {
    final valueFontSize = dense ? 11.5 : (compact ? 12.0 : 13.0);
    final labelFontSize = dense ? 7.5 : (compact ? 8.0 : 8.5);

    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Container(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
                maxHeight: constraints.maxHeight,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: 2,
                vertical: dense ? 1 : 2,
              ),
              decoration: BoxDecoration(
                color: _activeTheme.tileBackground.withOpacity(0.94),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: _activeTheme.tileBorder.withOpacity(0.88),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      color: _activeTheme.mutedText.withOpacity(0.86),
                      fontSize: labelFontSize,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          value,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            color: _activeTheme.primaryText,
                            fontSize: valueFontSize,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _iconBtn({
    required String keyId,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required bool hot,
  }) {
    final isStop = keyId == 'primary' && widget.tripStarted;
    final isNavActive = keyId == 'nav' && hot;
    final isWait = keyId == 'wait';
    final accent = isStop ? const Color(0xFFFF6B5F) : _activeTheme.accent;
    final background = isStop
        ? const Color(0xFF3A1821)
        : (isNavActive
              ? _activeTheme.hotBackground
              : _activeTheme.tileBackground);
    final bgOpacity = isStop ? 0.96 : (hot && !isWait ? 0.92 : 0.86);
    final borderOpacity = isStop
        ? 0.78
        : (isNavActive ? 0.62 : (isWait ? 0.18 : 0.28));
    final contentColor = hot && !isWait
        ? accent
        : _activeTheme.primaryText.withOpacity(isWait ? 0.76 : 0.88);

    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: Tooltip(
          message: label,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: _minTapSize),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: background.withOpacity(bgOpacity),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: accent.withOpacity(borderOpacity),
                      width: isStop ? 1.4 : 1.0,
                    ),
                    boxShadow: hot
                        ? [
                            BoxShadow(
                              color: accent.withOpacity(isStop ? 0.22 : 0.12),
                              blurRadius: isStop ? 8 : 5,
                              spreadRadius: 0.1,
                            ),
                          ]
                        : [],
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      key: ValueKey<String>('${keyId}_$label'),
                      size: 20,
                      color: contentColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
