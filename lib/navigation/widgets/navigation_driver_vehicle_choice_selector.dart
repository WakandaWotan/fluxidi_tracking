import 'package:flutter/material.dart';

import '../presentation/navigation_driver_vehicle_model_layer.dart';

/// NAV-3D-VEHICLE-CHOICE-3WAY-1: tablet three-way vehicle presentation
/// selector with direct buttons: [ 2D ] [ Fluxidi ] [ Classic ].
///
/// First-class selector (not a fallback control): visible only while the 3D
/// map style is active, large enough for driving use, styled with the
/// Fluxidi visual language (dark panel, gold border/accent, clear active
/// state).
class NavigationDriverVehicleChoiceSelector extends StatelessWidget {
  const NavigationDriverVehicleChoiceSelector({
    super.key,
    required this.selectedChoice,
    required this.onSelected,
    required this.accentColor,
    required this.textColor,
    required this.surfaceColor,
    this.compactLandscape = false,
  });

  final DriverVehiclePresentationChoice selectedChoice;
  final ValueChanged<DriverVehiclePresentationChoice> onSelected;
  final Color accentColor;
  final Color textColor;
  final Color surfaceColor;
  final bool compactLandscape;

  /// Short driving-friendly button labels.
  static String buttonLabel(DriverVehiclePresentationChoice choice) {
    switch (choice) {
      case DriverVehiclePresentationChoice.taxi2d:
        return '2D';
      case DriverVehiclePresentationChoice.fluxidi3d:
        return 'Fluxidi';
      case DriverVehiclePresentationChoice.classic3d:
        return 'Classic';
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttonHeight = compactLandscape ? 42.0 : 48.0;
    final buttonMinWidth = compactLandscape ? 64.0 : 78.0;
    final fontSize = compactLandscape ? 12.0 : 13.0;
    final choices = DriverVehiclePresentationChoice.values;
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
              _VehicleChoiceButton(
                choice: choices[i],
                label: buttonLabel(choices[i]),
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

class _VehicleChoiceButton extends StatelessWidget {
  const _VehicleChoiceButton({
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

  final DriverVehiclePresentationChoice choice;
  final String label;
  final bool selected;
  final ValueChanged<DriverVehiclePresentationChoice> onSelected;
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
          child: Text(
            label,
            style: TextStyle(
              color: selected ? accentColor : textColor,
              fontSize: fontSize,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
