import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/driver_theme_cycle.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';

/// Compact one-tap control that cycles the complete chauffeur/driver theme.
///
/// Applies one full preset per press through [onApply] — the same persistence
/// path the personal theme selector uses — so palette and artwork move together.
class DriverThemeCycleButton extends StatelessWidget {
  const DriverThemeCycleButton({
    super.key,
    required this.themeListenable,
    required this.onApply,
    required this.semanticLabel,
    this.heroOverlay = false,
    this.onCycled,
    this.size = 48,
  });

  /// Active driver theme source (standalone or company chauffeur-view preview).
  final ValueListenable<DriverThemeVariant> themeListenable;

  /// Canonical apply/persist path for the resolved next theme.
  final Future<void> Function(DriverThemeVariant next) onApply;

  /// Localized tooltip / Semantics label (NL/EN/FR/ES from the host).
  final String semanticLabel;

  /// When true (hero header), keep a slightly stronger frosted chip so the
  /// control stays readable on photographic backgrounds.
  final bool heroOverlay;

  /// Optional hook after a successful cycle (toast / tests).
  final ValueChanged<DriverThemeVariant>? onCycled;

  /// Logical size of the tappable surface (minimum 48 for accessibility).
  final double size;

  static const Key buttonKey = Key('driver_theme_cycle_button');

  Future<void> _onTap() async {
    final next = nextDriverThemeVariant(themeListenable.value);
    await onApply(next);
    onCycled?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final double side = size < 48 ? 48 : size;
    return ValueListenableBuilder<DriverThemeVariant>(
      valueListenable: themeListenable,
      builder: (context, variant, _) {
        final palette = paletteForDriverTheme(variant);
        final bg = heroOverlay
            ? palette.surface.withOpacity(palette.isDark ? 0.82 : 0.92)
            : palette.surfaceAlt.withOpacity(palette.isDark ? 0.92 : 1.0);
        final fg = palette.accent;
        final border = palette.accent.withOpacity(palette.isDark ? 0.58 : 0.48);

        return Tooltip(
          message: semanticLabel,
          waitDuration: const Duration(milliseconds: 450),
          child: Semantics(
            button: true,
            label: semanticLabel,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: buttonKey,
                onTap: () => unawaited(_onTap()),
                borderRadius: BorderRadius.circular(12),
                child: Ink(
                  width: side,
                  height: side,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: border),
                  ),
                  child: Icon(
                    Icons.palette_outlined,
                    size: side >= 48 ? 22 : 20,
                    color: fg,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
