import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';

/// Phone landscape compact strip height (Navigatie anchor reserve only).
const double kDirectRideEstimatePanelPhoneLandscapeCompactReserve = 52.0;

class _DirectRideEstimateTheme {
  const _DirectRideEstimateTheme({
    required this.panelGradient,
    required this.panelBorder,
    required this.accent,
    required this.valueAccent,
    required this.primaryText,
    required this.mutedText,
  });

  final Gradient panelGradient;
  final Color panelBorder;
  final Color accent;
  final Color valueAccent;
  final Color primaryText;
  final Color mutedText;
}

_DirectRideEstimateTheme _themeForDriverVariant(DriverThemeVariant variant) {
  if (variant == DriverThemeVariant.customHuisstijl) {
    final palette = paletteForDriverTheme(variant);
    return _DirectRideEstimateTheme(
      panelGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [palette.surface, palette.surfaceAlt],
      ),
      panelBorder: palette.border.withOpacity(0.62),
      accent: palette.accent,
      valueAccent: palette.accent,
      primaryText: palette.textPrimary,
      mutedText: palette.textMuted,
    );
  }
  if (variant == DriverThemeVariant.midnightBlue) {
    return const _DirectRideEstimateTheme(
      panelGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0E1D33), Color(0xFF0A1426)],
      ),
      panelBorder: Color(0x66599CDA),
      accent: Color(0xFF4DA3FF),
      valueAccent: Color(0xFF8FD0FF),
      primaryText: Color(0xFFEAF6FF),
      mutedText: Color(0xFFAFCBEA),
    );
  }
  if (variant == DriverThemeVariant.highContrast) {
    return const _DirectRideEstimateTheme(
      panelGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3A2A17), Color(0xFF21160B)],
      ),
      panelBorder: Color(0x99E8C57E),
      accent: Color(0xFFE8C57E),
      valueAccent: Color(0xFFFFDFA3),
      primaryText: Color(0xFFFFF0D0),
      mutedText: Color(0xFFE1CCA0),
    );
  }
  if (variant == DriverThemeVariant.lightEmerald) {
    return const _DirectRideEstimateTheme(
      panelGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFE4F1EB)],
      ),
      panelBorder: Color(0x99B7CEC4),
      accent: Color(0xFF1F8A65),
      valueAccent: Color(0xFF3AA87E),
      primaryText: Color(0xFF143028),
      mutedText: Color(0xFF4A665C),
    );
  }
  return const _DirectRideEstimateTheme(
    panelGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF111111), Color(0xFF090909)],
    ),
    panelBorder: Color(0x55E5B641),
    accent: Color(0xFFE5B641),
    valueAccent: Color(0xFFFFD36A),
    primaryText: Colors.white,
    mutedText: Color(0xFFB2B2B2),
  );
}

class DirectRideEstimatePanel extends StatelessWidget {
  final bool visible;
  final double? estimatedFare;
  final bool isLoading;
  final String? error;
  final String currency;
  final String label;
  final String note;
  final String loadingText;
  final String unavailableText;
  final String Function(double amount, String currency) formatAmount;
  final ValueListenable<DriverThemeVariant>? themeListenable;

  /// Phone landscape: single horizontal row, tighter vertical padding.
  final bool compactHorizontal;

  const DirectRideEstimatePanel({
    super.key,
    required this.visible,
    required this.estimatedFare,
    required this.isLoading,
    required this.error,
    required this.currency,
    required this.label,
    required this.note,
    required this.loadingText,
    required this.unavailableText,
    required this.formatAmount,
    this.themeListenable,
    this.compactHorizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final estimateValue = estimatedFare != null
        ? formatAmount(estimatedFare!, currency)
        : null;
    final statusText = isLoading
        ? loadingText
        : (estimateValue ?? unavailableText);
    final valueIsEstimate = !isLoading && estimateValue != null;

    return ValueListenableBuilder<DriverThemeVariant>(
      valueListenable: themeListenable ?? driverThemeNotifier,
      builder: (context, variant, _) {
        final theme = _themeForDriverVariant(variant);
        if (compactHorizontal) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: theme.panelGradient,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.panelBorder),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.local_taxi_outlined,
                  size: 13,
                  color: theme.accent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 4,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: valueIsEstimate
                          ? theme.valueAccent
                          : theme.primaryText,
                      fontSize: valueIsEstimate ? 13.5 : 10.5,
                      fontWeight: valueIsEstimate
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                ),
                if (valueIsEstimate) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: theme.mutedText,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            gradient: theme.panelGradient,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.panelBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.local_taxi_outlined,
                    size: 14,
                    color: theme.accent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                statusText,
                maxLines: valueIsEstimate ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: valueIsEstimate
                      ? theme.valueAccent
                      : theme.primaryText,
                  fontSize: valueIsEstimate ? 15 : 11.5,
                  fontWeight: valueIsEstimate
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.mutedText,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
