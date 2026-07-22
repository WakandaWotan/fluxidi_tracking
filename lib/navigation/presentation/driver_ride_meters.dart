// NAV-PRESENTATION-COMPACT-BANNER-LANES-TELLERS-1 / Commit 3
//
// Driver-facing "Tellers" presentation. Read-only view over live ride meters.
// Does not own GPS, fare, waiting, route progress, or the Mapbox map.

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';

/// Presentation mode for the driver navigation surface.
enum DriverNavPresentationMode {
  /// Live map + maneuver banner (default).
  navigation,

  /// Opaque Tellers overlay; navigation subtree stays mounted underneath.
  tellers,
}

/// Pure toggle owner — idempotent, no side effects on engines.
class DriverNavPresentationModeController {
  DriverNavPresentationMode _mode = DriverNavPresentationMode.navigation;

  DriverNavPresentationMode get mode => _mode;

  bool get isTellers => _mode == DriverNavPresentationMode.tellers;

  /// Returns true when the mode actually changed.
  bool showTellers() {
    if (_mode == DriverNavPresentationMode.tellers) return false;
    _mode = DriverNavPresentationMode.tellers;
    return true;
  }

  bool showNavigation() {
    if (_mode == DriverNavPresentationMode.navigation) return false;
    _mode = DriverNavPresentationMode.navigation;
    return true;
  }

  void reset() {
    _mode = DriverNavPresentationMode.navigation;
  }
}

/// Snapshot of authoritative live values for the Tellers screen.
///
/// Money is already formatted by the existing display policy; this model does
/// not introduce a second rounding rule or finalize fare.
class DriverRideMetersSnapshot {
  const DriverRideMetersSnapshot({
    required this.fareText,
    required this.distanceTravelledText,
    required this.rideDurationText,
    required this.waitingTimeText,
    required this.statusText,
    this.etaText = '',
    this.remainingDistanceText = '',
    this.tariffName = '',
    this.companyName = '',
  });

  final String fareText;
  final String distanceTravelledText;
  final String rideDurationText;
  final String waitingTimeText;
  final String statusText;
  final String etaText;
  final String remainingDistanceText;
  final String tariffName;
  final String companyName;
}

/// Large, theme-aware Tellers overlay. Opaque — does not show satellite/map
/// behind the meters. Map style selection is unrelated to this UI theme.
class DriverRideMetersView extends StatelessWidget {
  const DriverRideMetersView({
    super.key,
    required this.snapshot,
    required this.onBackToNavigation,
    this.onStop,
    this.onToggleWait,
    this.isWaiting = false,
    this.themeListenable,
    this.compact = false,
    this.isTablet = false,
    this.isLandscape = false,
  });

  final DriverRideMetersSnapshot snapshot;
  final VoidCallback onBackToNavigation;
  final VoidCallback? onStop;
  final VoidCallback? onToggleWait;
  final bool isWaiting;
  final ValueListenable<DriverThemeVariant>? themeListenable;
  final bool compact;
  final bool isTablet;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DriverThemeVariant>(
      valueListenable: themeListenable ?? driverThemeNotifier,
      builder: (context, variant, _) {
        final palette = paletteForDriverTheme(variant);
        return Material(
          key: const ValueKey<String>('driver_tellers_view'),
          color: palette.background,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 28 : 16,
                vertical: isLandscape ? 10 : 14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(palette),
                  SizedBox(height: isLandscape ? 10 : 16),
                  Expanded(child: _buildMetersGrid(palette)),
                  if (_hasSecondary(snapshot)) ...[
                    SizedBox(height: isLandscape ? 8 : 12),
                    _buildSecondaryRow(palette),
                  ],
                  SizedBox(height: isLandscape ? 8 : 12),
                  _buildFooterActions(palette),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _hasSecondary(DriverRideMetersSnapshot s) {
    return s.etaText.trim().isNotEmpty ||
        s.remainingDistanceText.trim().isNotEmpty ||
        s.tariffName.trim().isNotEmpty ||
        s.companyName.trim().isNotEmpty;
  }

  Widget _buildHeader(DriverThemePalette palette) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Tellers',
            style: TextStyle(
              fontSize: isTablet ? 28 : 22,
              fontWeight: FontWeight.w900,
              color: palette.textPrimary,
            ),
          ),
        ),
        Semantics(
          button: true,
          label: 'Navigatie',
          child: FilledButton.icon(
            key: const ValueKey<String>('driver_tellers_back_nav'),
            onPressed: onBackToNavigation,
            icon: const Icon(Icons.map_outlined, size: 20),
            label: const Text('Navigatie'),
            style: FilledButton.styleFrom(
              backgroundColor: palette.accent,
              foregroundColor: palette.isDark ? Colors.black : Colors.white,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetersGrid(DriverThemePalette palette) {
    final tiles = <Widget>[
      _MeterTile(
        key: const ValueKey('teller_fare'),
        label: 'Tarief',
        value: snapshot.fareText,
        semanticLabel: 'Tarief ${snapshot.fareText}',
        palette: palette,
        emphasize: true,
        isTablet: isTablet,
        isLandscape: isLandscape,
      ),
      _MeterTile(
        key: const ValueKey('teller_distance'),
        label: 'Afstand',
        value: snapshot.distanceTravelledText,
        semanticLabel: 'Afstand gereden ${snapshot.distanceTravelledText}',
        palette: palette,
        isTablet: isTablet,
        isLandscape: isLandscape,
      ),
      _MeterTile(
        key: const ValueKey('teller_duration'),
        label: 'Ritduur',
        value: snapshot.rideDurationText,
        semanticLabel: 'Ritduur ${snapshot.rideDurationText}',
        palette: palette,
        isTablet: isTablet,
        isLandscape: isLandscape,
      ),
      _MeterTile(
        key: const ValueKey('teller_waiting'),
        label: 'Wachttijd',
        value: snapshot.waitingTimeText,
        semanticLabel: 'Wachttijd ${snapshot.waitingTimeText}',
        palette: palette,
        isTablet: isTablet,
        isLandscape: isLandscape,
      ),
      _MeterTile(
        key: const ValueKey('teller_status'),
        label: 'Status',
        value: snapshot.statusText,
        semanticLabel: 'Status ${snapshot.statusText}',
        palette: palette,
        isTablet: isTablet,
        isLandscape: isLandscape,
      ),
    ];

    if (isLandscape && !isTablet) {
      return Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: tiles[i]),
          ],
        ],
      );
    }

    if (isTablet) {
      return GridView.count(
        crossAxisCount: isLandscape ? 3 : 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: isLandscape ? 1.55 : 1.35,
        physics: const NeverScrollableScrollPhysics(),
        children: tiles,
      );
    }

    // Phone portrait: 2-column grid for the five essentials (last spans).
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: tiles[0]),
              const SizedBox(width: 10),
              Expanded(child: tiles[1]),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Row(
            children: [
              Expanded(child: tiles[2]),
              const SizedBox(width: 10),
              Expanded(child: tiles[3]),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(child: tiles[4]),
      ],
    );
  }

  Widget _buildSecondaryRow(DriverThemePalette palette) {
    final bits = <String>[];
    if (snapshot.etaText.trim().isNotEmpty) {
      bits.add('ETA ${snapshot.etaText.trim()}');
    }
    if (snapshot.remainingDistanceText.trim().isNotEmpty) {
      bits.add('Rest ${snapshot.remainingDistanceText.trim()}');
    }
    if (snapshot.tariffName.trim().isNotEmpty) {
      bits.add(snapshot.tariffName.trim());
    }
    if (snapshot.companyName.trim().isNotEmpty) {
      bits.add(snapshot.companyName.trim());
    }
    return Text(
      bits.join('  ·  '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: isTablet ? 14 : 12,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary.withOpacity(0.72),
      ),
    );
  }

  Widget _buildFooterActions(DriverThemePalette palette) {
    final actions = <Widget>[];
    if (onToggleWait != null) {
      actions.add(
        Expanded(
          child: OutlinedButton(
            key: const ValueKey('driver_tellers_wait'),
            onPressed: onToggleWait,
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.textPrimary,
              side: BorderSide(color: palette.border),
              minimumSize: const Size(48, 48),
            ),
            child: Text(isWaiting ? 'Hervatten' : 'Pauze'),
          ),
        ),
      );
    }
    if (onStop != null) {
      if (actions.isNotEmpty) actions.add(const SizedBox(width: 10));
      actions.add(
        Expanded(
          child: OutlinedButton(
            key: const ValueKey('driver_tellers_stop'),
            onPressed: onStop,
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.textPrimary,
              side: BorderSide(color: palette.accent.withOpacity(0.8)),
              minimumSize: const Size(48, 48),
            ),
            child: const Text('Stop'),
          ),
        ),
      );
    }
    if (actions.isEmpty) return const SizedBox.shrink();
    return Row(children: actions);
  }
}

class _MeterTile extends StatelessWidget {
  const _MeterTile({
    super.key,
    required this.label,
    required this.value,
    required this.semanticLabel,
    required this.palette,
    required this.isTablet,
    required this.isLandscape,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final String semanticLabel;
  final DriverThemePalette palette;
  final bool isTablet;
  final bool isLandscape;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final valueSize = isTablet
        ? (isLandscape ? 36.0 : 40.0)
        : (isLandscape ? 18.0 : 28.0);
    return Semantics(
      label: semanticLabel,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 18 : 12,
          vertical: isTablet ? 16 : 10,
        ),
        decoration: BoxDecoration(
          color: palette.surface.withOpacity(palette.isDark ? 0.94 : 0.98),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: emphasize
                ? palette.accent.withOpacity(0.85)
                : palette.border.withOpacity(0.7),
            width: emphasize ? 1.8 : 1.1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isTablet ? 14 : 12,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary.withOpacity(0.72),
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: valueSize,
                  fontWeight: FontWeight.w900,
                  color: palette.textPrimary,
                  height: 1.05,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
