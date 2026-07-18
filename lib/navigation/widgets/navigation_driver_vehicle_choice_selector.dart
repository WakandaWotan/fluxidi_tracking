import 'package:flutter/material.dart';

import '../../app_strings.dart';
import '../presentation/navigation_driver_marker_choice.dart';

/// NAV-VEHICLE-MODE-CAR-ARROW-1: tablet navigation marker selector with exactly
/// two direct buttons — [ Auto ] [ Pijl ] (localized). It replaces the former
/// experimental 3D vehicle selector (2D / Fluxidi / Classic).
///
/// This selector is independent of the map style: it is shown identically on
/// Light, Dark, 3D-buildings and Satellite styles. Choosing a marker never
/// changes the map style and vice versa.
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
  });

  final DriverNavigationMarkerChoice selectedChoice;
  final ValueChanged<DriverNavigationMarkerChoice> onSelected;
  final Color accentColor;
  final Color textColor;
  final Color surfaceColor;
  final AppLanguage language;
  final bool compactLandscape;

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
    final buttonHeight = compactLandscape ? 42.0 : 48.0;
    final buttonMinWidth = compactLandscape ? 64.0 : 78.0;
    final fontSize = compactLandscape ? 12.0 : 13.0;
    const choices = DriverNavigationMarkerChoice.values;
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

  @override
  Widget build(BuildContext context) {
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
          constraints: BoxConstraints(minWidth: minWidth),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? accentColor
                  : textColor.withValues(alpha: 0.28),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                NavigationDriverMarkerChoiceSelector.iconFor(choice),
                size: fontSize + 5,
                color: selected ? accentColor : textColor,
              ),
              const SizedBox(width: 6),
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
