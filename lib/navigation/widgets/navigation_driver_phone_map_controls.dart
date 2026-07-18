import 'package:flutter/material.dart';

import '../../app_strings.dart';
import '../presentation/navigation_driver_marker_choice.dart';
import 'navigation_driver_vehicle_choice_selector.dart';

/// NAV-MOBILE-ENTERPRISE-COCKPIT-COMPACT-CONTROLS-1: phone-only compact map
/// controls.
///
/// Enterprise cockpit priority: the taxi-meter (ETA / KM / fare) and primary
/// ride actions own the bottom strip; these secondary map controls stay
/// compact, never permanent-text, and never overlap the ride controls:
/// - one compact marker icon button (popup carries Auto / Pijl),
/// - two independent zoom buttons [+] and [−] with no panel, no "View X/13"
///   and no Z/P/A debug values.
/// Tablet keeps its existing direct selector and View panel untouched.

/// Practical driving touch target (44–48 logical px requirement).
const double kDriverPhoneMapControlButtonSize = 48.0;

/// Clear spacing between the independent + and − buttons.
const double kDriverPhoneZoomButtonsGap = 10.0;

/// Edge margin against safe-area bounds.
const double kDriverPhoneMapControlsEdgeMargin = 14.0;

/// Total footprint of the phone zoom stack (two buttons + gap, no panel).
Size driverPhoneZoomControlsSize({
  double buttonSize = kDriverPhoneMapControlButtonSize,
  double gap = kDriverPhoneZoomButtonsGap,
}) {
  return Size(buttonSize, buttonSize * 2 + gap);
}

/// Resolved placement for the compact phone vehicle icon button.
class DriverPhoneVehicleButtonPlacement {
  const DriverPhoneVehicleButtonPlacement({
    required this.left,
    required this.bottom,
    required this.clamped,
    required this.reason,
  });

  final double left;
  final double bottom;
  final bool clamped;
  final String reason;
}

/// Places the compact vehicle icon on the left side of the map-control zone.
///
/// Portrait: mirrors the zoom zone on the left (same bottom offset, never
/// stacked above the zoom controls). Landscape: mid-left vertical placement,
/// clamped below the route banner reserve and above the bottom ride strip.
DriverPhoneVehicleButtonPlacement resolveDriverPhoneVehicleButtonPlacement({
  required double screenHeight,
  required double safeTop,
  required double safeBottom,
  required double safeLeft,
  required bool isLandscape,
  required double zoomControlsBottom,
  double buttonSize = kDriverPhoneMapControlButtonSize,
  double navBannerReserve = 0.0,
  double bottomStripReserve = 0.0,
  double margin = kDriverPhoneMapControlsEdgeMargin,
}) {
  final left = safeLeft + margin;
  final minBottom = safeBottom + bottomStripReserve + margin;
  final maxBottom =
      screenHeight - (safeTop + margin + navBannerReserve) - buttonSize;
  var clamped = false;
  double bottom;
  String reason;
  if (isLandscape) {
    bottom = (screenHeight - buttonSize) / 2.0;
    reason = 'landscape_mid_left';
  } else {
    bottom = zoomControlsBottom;
    reason = 'portrait_left_of_map_zone';
  }
  if (bottom < minBottom) {
    bottom = minBottom;
    clamped = true;
    reason = '${reason}_clamped_bottom';
  } else if (bottom > maxBottom) {
    bottom = maxBottom;
    clamped = true;
    reason = '${reason}_clamped_top';
  }
  return DriverPhoneVehicleButtonPlacement(
    left: left,
    bottom: bottom,
    clamped: clamped,
    reason: reason,
  );
}

/// PHONE ONLY: two independent compact zoom buttons.
///
/// No enclosing panel, no "View X/13" label, no Z/P/A debug values. The +/−
/// callbacks are the existing cockpit view-level callbacks, unchanged.
class NavigationDriverPhoneZoomControls extends StatelessWidget {
  const NavigationDriverPhoneZoomControls({
    super.key,
    required this.onPlus,
    required this.onMinus,
    required this.accentColor,
    required this.textColor,
    required this.surfaceColor,
    this.buttonSize = kDriverPhoneMapControlButtonSize,
  });

  final VoidCallback onPlus;
  final VoidCallback onMinus;
  final Color accentColor;
  final Color textColor;
  final Color surfaceColor;
  final double buttonSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PhoneMapControlButton(
          size: buttonSize,
          accentColor: accentColor,
          textColor: textColor,
          surfaceColor: surfaceColor,
          semanticLabel: 'Closer driver perspective',
          onTap: onPlus,
          child: Icon(Icons.add, size: 22, color: textColor),
        ),
        const SizedBox(height: kDriverPhoneZoomButtonsGap),
        _PhoneMapControlButton(
          size: buttonSize,
          accentColor: accentColor,
          textColor: textColor,
          surfaceColor: surfaceColor,
          semanticLabel: 'Wider driver perspective',
          onTap: onMinus,
          child: Icon(Icons.remove, size: 22, color: textColor),
        ),
      ],
    );
  }
}

/// PHONE ONLY: compact marker icon button opening the two-way choice
/// popup (Auto / Pijl).
///
/// Same state model and callback as the tablet selector — no duplicate
/// selector system. The popup opens upward over the map so it never covers
/// the taxi-meter or the bottom ride actions.
class NavigationDriverMarkerCompactButton extends StatefulWidget {
  const NavigationDriverMarkerCompactButton({
    super.key,
    required this.selectedChoice,
    required this.onSelected,
    required this.accentColor,
    required this.textColor,
    required this.surfaceColor,
    this.language = AppLanguage.en,
    this.buttonSize = kDriverPhoneMapControlButtonSize,
  });

  final DriverNavigationMarkerChoice selectedChoice;
  final ValueChanged<DriverNavigationMarkerChoice> onSelected;
  final Color accentColor;
  final Color textColor;
  final Color surfaceColor;
  final AppLanguage language;
  final double buttonSize;

  /// Short popup labels shared with the tablet selector buttons.
  static String menuLabel(
    DriverNavigationMarkerChoice choice,
    AppLanguage language,
  ) {
    return NavigationDriverMarkerChoiceSelector.buttonLabel(choice, language);
  }

  @override
  State<NavigationDriverMarkerCompactButton> createState() =>
      _NavigationDriverMarkerCompactButtonState();
}

class _NavigationDriverMarkerCompactButtonState
    extends State<NavigationDriverMarkerCompactButton> {
  bool _menuOpen = false;

  void _setMenuOpen(bool open) {
    if (_menuOpen == open || !mounted) return;
    setState(() => _menuOpen = open);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;
    const choices = DriverNavigationMarkerChoice.values;
    // Estimated popup height (2 items × 48 + chrome): open upward over the
    // map, away from the bottom taxi-meter / ride action strip.
    const menuLift = 124.0;
    return PopupMenuButton<DriverNavigationMarkerChoice>(
      tooltip: driverNavigationMarkerChoiceLabel(
        widget.selectedChoice,
        widget.language,
      ),
      position: PopupMenuPosition.over,
      offset: const Offset(0, -menuLift),
      color: widget.surfaceColor,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: accent.withValues(alpha: 0.72)),
      ),
      constraints: const BoxConstraints(minWidth: 136),
      onOpened: () => _setMenuOpen(true),
      onCanceled: () => _setMenuOpen(false),
      onSelected: (choice) {
        _setMenuOpen(false);
        widget.onSelected(choice);
      },
      itemBuilder: (context) {
        return [
          for (final choice in choices)
            PopupMenuItem<DriverNavigationMarkerChoice>(
              value: choice,
              height: 48,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    choice == widget.selectedChoice
                        ? Icons.check_circle
                        : NavigationDriverMarkerChoiceSelector.iconFor(choice),
                    size: 18,
                    color: choice == widget.selectedChoice
                        ? accent
                        : widget.textColor.withValues(alpha: 0.65),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    NavigationDriverMarkerCompactButton.menuLabel(
                      choice,
                      widget.language,
                    ),
                    style: TextStyle(
                      color: choice == widget.selectedChoice
                          ? accent
                          : widget.textColor,
                      fontSize: 14,
                      fontWeight: choice == widget.selectedChoice
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ];
      },
      child: Semantics(
        button: true,
        label: driverNavigationMarkerChoiceLabel(
          widget.selectedChoice,
          widget.language,
        ),
        child: Container(
          width: widget.buttonSize,
          height: widget.buttonSize,
          decoration: BoxDecoration(
            color: _menuOpen
                ? Color.alphaBlend(
                    accent.withValues(alpha: 0.22),
                    widget.surfaceColor.withValues(alpha: 0.94),
                  )
                : widget.surfaceColor.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _menuOpen ? accent : accent.withValues(alpha: 0.72),
              width: _menuOpen ? 2 : 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 6,
              ),
            ],
          ),
          child: Icon(
            NavigationDriverMarkerChoiceSelector.iconFor(widget.selectedChoice),
            size: 24,
            color: _menuOpen ? accent : widget.textColor,
          ),
        ),
      ),
    );
  }
}

class _PhoneMapControlButton extends StatelessWidget {
  const _PhoneMapControlButton({
    required this.size,
    required this.accentColor,
    required this.textColor,
    required this.surfaceColor,
    required this.semanticLabel,
    required this.onTap,
    required this.child,
  });

  final double size;
  final Color accentColor;
  final Color textColor;
  final Color surfaceColor;
  final String semanticLabel;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: surfaceColor.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.72),
                width: 1.1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
