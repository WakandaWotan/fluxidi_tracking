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

/// NAV-PARKING-2 Commit 4: latest-wins owner for the temporary Tellers camera
/// viewport/padding. Pure and side-effect free — it only tracks a monotonic
/// generation so a stale Tellers camera callback (from a viewport that has
/// since been closed or superseded) can be rejected, and closing can never
/// resurrect an old viewport. It does NOT create a camera/GPS owner.
class DriverTellersViewportController {
  int _generation = 0;
  bool _active = false;

  bool get active => _active;
  int get generation => _generation;

  /// Activate (or re-activate latest-wins) the Tellers viewport. Returns the
  /// token the caller must present when a deferred camera callback fires.
  int open() {
    _generation += 1;
    _active = true;
    return _generation;
  }

  /// Restore normal follow presentation. Bumps the generation so any pending
  /// Tellers viewport callback becomes stale and cannot resurrect the viewport.
  void close() {
    if (!_active && _generation == 0) return;
    _generation += 1;
    _active = false;
  }

  /// True only when [token] belongs to the current active viewport.
  bool isCallbackValid(int token) => _active && token == _generation;

  void reset() {
    _generation += 1;
    _active = false;
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
    this.showLiveWindow = true,
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

  /// NAV-PARKING-2 Commit 4: when true the layout reserves a transparent
  /// cut-out region over the retained MapWidget so the single mounted map is
  /// the live navigation window. No second MapWidget is ever created here.
  final bool showLiveWindow;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DriverThemeVariant>(
      valueListenable: themeListenable ?? driverThemeNotifier,
      builder: (context, variant, _) {
        final palette = paletteForDriverTheme(variant);
        // NAV-PHONE-DRIVER-VIEW-FLICKER-1: NO full-screen transparent Material
        // over the retained Android HC MapWidget. A full-screen transparent
        // compositing layer that repaints every fare/timer tick caused HC
        // overlay-surface churn (phone flicker). Instead the root only lays out
        // (SafeArea/Padding do not paint); opaque meter panels cover their own
        // regions and the live-navigation window is a genuinely uncovered
        // region so the map shows through without a repainting overlay.
        return KeyedSubtree(
          key: const ValueKey<String>('driver_tellers_view'),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 20 : 12,
                vertical: isLandscape ? 8 : 12,
              ),
              child: (isLandscape && showLiveWindow)
                  ? _buildLandscapeSplit(palette)
                  : _buildPortraitStack(palette),
            ),
          ),
        );
      },
    );
  }

  /// Tablet/phone landscape: meters panel + status + controls on the left, a
  /// substantial live navigation window on the right.
  Widget _buildLandscapeSplit(DriverThemePalette palette) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: isTablet ? 5 : 6,
          child: _buildMetersPanel(palette, withControls: true),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: isTablet ? 6 : 5,
          child: _buildLiveWindow(palette),
        ),
      ],
    );
  }

  /// Portrait (and no-live-window): meters panel on top, live window below,
  /// compact status + controls.
  Widget _buildPortraitStack(DriverThemePalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMetersPanel(palette, withControls: !showLiveWindow),
        if (showLiveWindow) ...[
          SizedBox(height: isLandscape ? 8 : 12),
          Expanded(child: _buildLiveWindow(palette)),
          SizedBox(height: isLandscape ? 8 : 12),
          // NAV-PHONE-DRIVER-VIEW-FLICKER-1: controls sit in their own opaque,
          // repaint-isolated panel — no transparent controls repainting over
          // the HC map region.
          RepaintBoundary(
            child: Container(
              padding: EdgeInsets.all(isTablet ? 12 : 8),
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: palette.border.withOpacity(0.5)),
              ),
              child: _buildFooterActions(palette),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMetersPanel(
    DriverThemePalette palette, {
    required bool withControls,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(palette),
        SizedBox(height: isLandscape ? 8 : 12),
        _buildMetersGrid(palette),
        SizedBox(height: isLandscape ? 6 : 10),
        _buildStatusChip(palette),
        if (withControls) ...[
          SizedBox(height: isLandscape ? 8 : 12),
          _buildFooterActions(palette),
        ],
      ],
    );
    // NAV-PHONE-DRIVER-VIEW-FLICKER-1: fully OPAQUE panel (no per-frame alpha
    // blending over the HC platform view) isolated in its own RepaintBoundary,
    // so fare/timer/location ticks repaint only this panel and never the map.
    return RepaintBoundary(
      child: Container(
        key: const ValueKey<String>('driver_tellers_meters_panel'),
        padding: EdgeInsets.all(isTablet ? 14 : 10),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border.withOpacity(0.5)),
        ),
        child: content,
      ),
    );
  }

  /// NAV-PARKING-2 Commit 4: transparent, bordered live navigation window. The
  /// single mounted MapWidget behind the Tellers overlay shows through here —
  /// current marker, selected route, next maneuver and distance remain visible.
  Widget _buildLiveWindow(DriverThemePalette palette) {
    // NAV-PHONE-DRIVER-VIEW-FLICKER-1: the interior is genuinely uncovered (no
    // fill, only a thin static frame) so the retained HC map shows straight
    // through. Wrapped in a RepaintBoundary and independent of the live
    // snapshot, so meter/timer ticks never repaint this map-overlapping region.
    return RepaintBoundary(
      child: Container(
        key: const ValueKey<String>('driver_tellers_live_window'),
        constraints: const BoxConstraints(minHeight: 120),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: palette.accent.withOpacity(0.7),
            width: 2,
          ),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Live navigatie',
                style: TextStyle(
                  fontSize: isTablet ? 12 : 11,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary.withOpacity(0.85),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(DriverThemePalette palette) {
    // NAV-PARKING-2 Commit 4: status is a small secondary element, never a
    // fifth equal meter tile.
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const ValueKey<String>('driver_tellers_status'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: palette.border.withOpacity(0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isWaiting ? const Color(0xFFFFB020) : palette.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              snapshot.statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isTablet ? 13 : 12,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary.withOpacity(0.85),
              ),
            ),
          ],
        ),
      ),
    );
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

  /// NAV-PARKING-2 Commit 4: exactly FOUR principal meter tiles in a balanced
  /// 2x2 area (Tarief, Afstand, Ritduur, Wachttijd). Status is rendered
  /// separately as a smaller element — never a fifth equal tile.
  Widget _buildMetersGrid(DriverThemePalette palette) {
    final fare = _MeterTile(
      key: const ValueKey('teller_fare'),
      label: 'Tarief',
      value: snapshot.fareText,
      semanticLabel: 'Tarief ${snapshot.fareText}',
      palette: palette,
      emphasize: true,
      isTablet: isTablet,
      isLandscape: isLandscape,
    );
    final distance = _MeterTile(
      key: const ValueKey('teller_distance'),
      label: 'Afstand',
      value: snapshot.distanceTravelledText,
      semanticLabel: 'Afstand gereden ${snapshot.distanceTravelledText}',
      palette: palette,
      isTablet: isTablet,
      isLandscape: isLandscape,
    );
    final duration = _MeterTile(
      key: const ValueKey('teller_duration'),
      label: 'Ritduur',
      value: snapshot.rideDurationText,
      semanticLabel: 'Ritduur ${snapshot.rideDurationText}',
      palette: palette,
      isTablet: isTablet,
      isLandscape: isLandscape,
    );
    final waiting = _MeterTile(
      key: const ValueKey('teller_waiting'),
      label: 'Wachttijd',
      value: snapshot.waitingTimeText,
      semanticLabel: 'Wachttijd ${snapshot.waitingTimeText}',
      palette: palette,
      isTablet: isTablet,
      isLandscape: isLandscape,
    );

    Widget row(Widget a, Widget b) => Row(
          children: [
            Expanded(child: a),
            const SizedBox(width: 10),
            Expanded(child: b),
          ],
        );

    // Balanced 2x2 in all layouts.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row(fare, distance),
        const SizedBox(height: 10),
        row(duration, waiting),
      ],
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
          mainAxisSize: MainAxisSize.min,
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
