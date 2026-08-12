import 'package:flutter/material.dart';

import '../../app_strings.dart';
import '../presentation/nav_outlined_map_text.dart';
import '../presentation/navigation_driver_marker_choice.dart';
import '../presentation/phone_cockpit_opacity.dart';

/// NAV-VEHICLE-MODE-CAR-ARROW-1: tablet navigation marker selector with exactly
/// two direct buttons — [ Auto ] [ Pijl ] (localized). It replaces the former
/// experimental 3D vehicle selector (2D / Fluxidi / Classic).
///
/// This selector is independent of the map style: it is shown identically on
/// Light, Dark, 3D-buildings and Satellite styles. Choosing a marker never
/// changes the map style and vice versa.
///
/// Phone Tellers may opt into [phoneFloatingGlass] for the transparent cockpit
/// language. Tablet styling remains the prior opaque capsule.
class NavigationDriverMarkerChoiceSelector extends StatelessWidget {
  const NavigationDriverMarkerChoiceSelector({
    super.key,
    required this.selectedChoice,
    required this.onSelected,
    required this.accentColor,
    required this.textColor,
    required this.surfaceColor,
    this.language = AppLanguage.en,
    this.compactLandscape = false,
    this.phoneFloatingGlass = false,
  });

  final DriverNavigationMarkerChoice selectedChoice;
  final ValueChanged<DriverNavigationMarkerChoice> onSelected;
  final Color accentColor;
  final Color textColor;
  final Color surfaceColor;
  final AppLanguage language;
  final bool compactLandscape;

  /// Phone Tellers only: near-clear outer capsule + outlined glyphs.
  final bool phoneFloatingGlass;

  /// Localized driving-friendly button label.
  static String buttonLabel(
    DriverNavigationMarkerChoice choice,
    AppLanguage language,
  ) {
    return driverNavigationMarkerChoiceLabel(choice, language);
  }

  static IconData iconFor(DriverNavigationMarkerChoice choice) {
    return choice == DriverNavigationMarkerChoice.car
        ? Icons.local_taxi
        : Icons.navigation;
  }

  @override
  Widget build(BuildContext context) {
    // Phone glass: keep ≥48 lp targets even in landscape Tellers.
    final buttonHeight = phoneFloatingGlass
        ? 48.0
        : (compactLandscape ? 42.0 : 48.0);
    final buttonMinWidth = phoneFloatingGlass
        ? 72.0
        : (compactLandscape ? 64.0 : 78.0);
    final fontSize = phoneFloatingGlass
        ? 13.0
        : (compactLandscape ? 12.0 : 13.0);
    const choices = DriverNavigationMarkerChoice.values;
    final gold = PhoneTellersReadability.focusBorder;

    if (phoneFloatingGlass) {
      return Material(
        color: Colors.transparent,
        child: Container(
          key: const ValueKey<String>('nav_marker_selector_phone_glass'),
          decoration: BoxDecoration(
            color: const Color(0xFF000000).withOpacity(PhoneCockpitOpacity.outer),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: gold.withOpacity(0.75), width: 1.1),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < choices.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                _MarkerChoiceButton(
                  choice: choices[i],
                  label: buttonLabel(choices[i], language),
                  selected: choices[i] == selectedChoice,
                  onSelected: onSelected,
                  accentColor: gold,
                  textColor: PhoneTellersReadability.primaryFill,
                  height: buttonHeight,
                  minWidth: buttonMinWidth,
                  fontSize: fontSize,
                  phoneFloatingGlass: true,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Material(
      color: surfaceColor.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor.withValues(alpha: 0.72)),
        ),
        padding: const EdgeInsets.all(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < choices.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              _MarkerChoiceButton(
                choice: choices[i],
                label: buttonLabel(choices[i], language),
                selected: choices[i] == selectedChoice,
                onSelected: onSelected,
                accentColor: accentColor,
                textColor: textColor,
                height: buttonHeight,
                minWidth: buttonMinWidth,
                fontSize: fontSize,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MarkerChoiceButton extends StatelessWidget {
  const _MarkerChoiceButton({
    required this.choice,
    required this.label,
    required this.selected,
    required this.onSelected,
    required this.accentColor,
    required this.textColor,
    required this.height,
    required this.minWidth,
    required this.fontSize,
    this.phoneFloatingGlass = false,
  });

  final DriverNavigationMarkerChoice choice;
  final String label;
  final bool selected;
  final ValueChanged<DriverNavigationMarkerChoice> onSelected;
  final Color accentColor;
  final Color textColor;
  final double height;
  final double minWidth;
  final double fontSize;
  final bool phoneFloatingGlass;

  @override
  Widget build(BuildContext context) {
    final selectedFill = phoneFloatingGlass
        ? accentColor.withOpacity(0.18)
        : accentColor.withValues(alpha: 0.22);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onSelected(choice),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: height,
          constraints: BoxConstraints(
            minWidth: minWidth,
            minHeight: phoneFloatingGlass ? 48 : height,
          ),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(
            horizontal: phoneFloatingGlass ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: selected ? selectedFill : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: phoneFloatingGlass
                  ? (selected
                      ? accentColor.withOpacity(0.95)
                      : accentColor.withOpacity(0.40))
                  : (selected
                      ? accentColor
                      : textColor.withValues(alpha: 0.28)),
              width: selected ? (phoneFloatingGlass ? 1.2 : 2) : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                NavigationDriverMarkerChoiceSelector.iconFor(choice),
                size: fontSize + 5,
                color: selected ? accentColor : textColor,
                shadows: phoneFloatingGlass
                    ? PhoneTellersReadability.softShadow
                    : null,
              ),
              const SizedBox(width: 6),
              if (phoneFloatingGlass)
                NavOutlinedMapText(
                  text: label,
                  fill: selected
                      ? PhoneTellersReadability.focusBorder
                      : PhoneTellersReadability.primaryFill,
                  stroke: PhoneTellersReadability.primaryStroke,
                  strokeWidth: 2.2,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  ),
                )
              else
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? accentColor : textColor,
                    fontSize: fontSize,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
