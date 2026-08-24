import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';

/// Catalog of the four outlined Ride-receipt ("Bon") PDF actions.
///
/// Order is the product contract: Share, WhatsApp, Email, Print. The filled
/// "Bekijk PDF" action stays a separate filled button above this list.
const List<ReceiptOutlinedActionSpec> kReceiptOutlinedPdfActions =
    <ReceiptOutlinedActionSpec>[
      ReceiptOutlinedActionSpec(
        id: 'sharePdf',
        icon: Icons.share_outlined,
        labelKey: 'sharePdf',
      ),
      ReceiptOutlinedActionSpec(
        id: 'whatsappPdf',
        icon: Icons.chat_outlined,
        labelKey: 'whatsappPdf',
      ),
      ReceiptOutlinedActionSpec(
        id: 'emailPdf',
        icon: Icons.email_outlined,
        labelKey: 'emailPdf',
      ),
      ReceiptOutlinedActionSpec(
        id: 'printReceipt',
        icon: Icons.print_outlined,
        labelKey: 'printReceipt',
      ),
    ];

@immutable
class ReceiptOutlinedActionSpec {
  const ReceiptOutlinedActionSpec({
    required this.id,
    required this.icon,
    required this.labelKey,
  });

  final String id;
  final IconData icon;
  final String labelKey;
}

/// Explicit outlined-action colors for the receipt "Bon" card.
///
/// Values are computed from the active chauffeur/business palette tokens.
/// They never read [ThemeData.outlinedButtonTheme], [ColorScheme.onSurface]
/// or any other inherited button foreground that can resolve to white on a
/// light card.
@immutable
class ReceiptOutlinedActionColors {
  const ReceiptOutlinedActionColors({
    required this.surface,
    required this.foreground,
    required this.disabledForeground,
    required this.outline,
    required this.disabledOutline,
    required this.pressedOverlay,
  });

  final Color surface;
  final Color foreground;
  final Color disabledForeground;
  final Color outline;
  final Color disabledOutline;
  final Color pressedOverlay;

  factory ReceiptOutlinedActionColors.fromTokens({
    required Color surface,
    required Color textPrimary,
    required Color textMuted,
    required Color accent,
  }) {
    final foreground = receiptOutlinedActionForeground(
      surface: surface,
      preferred: textPrimary,
    );
    return ReceiptOutlinedActionColors(
      surface: surface,
      foreground: foreground,
      disabledForeground: receiptOutlinedActionDisabledForeground(
        surface: surface,
        enabled: foreground,
        muted: textMuted,
      ),
      outline: accent,
      disabledOutline: accent.withOpacity(0.42),
      pressedOverlay: foreground.withOpacity(0.12),
    );
  }

  factory ReceiptOutlinedActionColors.fromDriverTheme(
    DriverThemePalette palette,
  ) {
    return ReceiptOutlinedActionColors.fromTokens(
      surface: palette.surface,
      textPrimary: palette.textPrimary,
      textMuted: palette.textMuted,
      accent: palette.accent,
    );
  }

  factory ReceiptOutlinedActionColors.fromBusinessTheme(
    BusinessThemePalette palette,
  ) {
    return ReceiptOutlinedActionColors.fromTokens(
      surface: palette.surface,
      textPrimary: palette.textPrimary,
      textMuted: palette.textMuted,
      accent: palette.accent,
    );
  }

  Color resolveForeground({required bool disabled, required bool busy}) {
    if (busy) return foreground;
    if (disabled) return disabledForeground;
    return foreground;
  }
}

/// Dark ink on a light card, light ink on a dark card. Never near-white on
/// a light surface, even when [preferred] is white.
Color receiptOutlinedActionForeground({
  required Color surface,
  required Color preferred,
}) {
  if (_isNearWhiteOnLightSurface(preferred, surface)) {
    return brandSignatureReadableTextOn(surface);
  }
  if (brandSignatureContrastRatio(preferred, surface) >= 4.5) {
    return preferred;
  }
  return brandSignatureReadableTextOn(surface);
}

Color receiptOutlinedActionDisabledForeground({
  required Color surface,
  required Color enabled,
  required Color muted,
}) {
  if (!_isNearWhiteOnLightSurface(muted, surface) &&
      brandSignatureContrastRatio(muted, surface) >= 3.0) {
    return muted;
  }
  for (final blend in const <double>[0.28, 0.18, 0.10, 0.0]) {
    final candidate = Color.lerp(enabled, surface, blend)!;
    if (brandSignatureContrastRatio(candidate, surface) >= 3.0) {
      return candidate;
    }
  }
  return enabled;
}

bool _isNearWhiteOnLightSurface(Color foreground, Color surface) {
  final surfaceLum = brandSignatureRelativeLuminance(surface);
  final foregroundLum = brandSignatureRelativeLuminance(foreground);
  return surfaceLum >= 0.70 && foregroundLum >= 0.85;
}

ButtonStyle receiptOutlinedActionButtonStyle(
  ReceiptOutlinedActionColors colors,
) {
  return OutlinedButton.styleFrom(
    foregroundColor: colors.foreground,
    backgroundColor: Colors.transparent,
    disabledForegroundColor: colors.disabledForeground,
    disabledBackgroundColor: Colors.transparent,
    iconColor: colors.foreground,
    disabledIconColor: colors.disabledForeground,
    side: BorderSide(color: colors.outline, width: 1.2),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    textStyle: const TextStyle(fontWeight: FontWeight.w800),
  ).copyWith(
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colors.disabledForeground;
      }
      return colors.foreground;
    }),
    iconColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colors.disabledForeground;
      }
      return colors.foreground;
    }),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed) ||
          states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return colors.pressedOverlay;
      }
      return colors.outline.withOpacity(0.10);
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return BorderSide(color: colors.disabledOutline, width: 1.2);
      }
      return BorderSide(color: colors.outline, width: 1.2);
    }),
  );
}

/// Outlined receipt action with an explicit label + icon color.
///
/// Use this instead of a bare [OutlinedButton.icon] on the receipt "Bon"
/// card so a dark app [outlinedButtonTheme] (white foreground) cannot hide
/// the action on a light surface.
class ReceiptOutlinedActionButton extends StatelessWidget {
  const ReceiptOutlinedActionButton({
    super.key,
    required this.colors,
    required this.icon,
    required this.label,
    this.onPressed,
    this.busy = false,
  });

  final ReceiptOutlinedActionColors colors;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null && !busy;
    final foreground = colors.resolveForeground(
      disabled: disabled,
      busy: busy,
    );
    final effectiveOnPressed = busy ? () {} : onPressed;
    return AbsorbPointer(
      absorbing: busy,
      child: OutlinedButton.icon(
        onPressed: effectiveOnPressed,
        style: receiptOutlinedActionButtonStyle(colors),
        icon: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            : Icon(icon, color: foreground),
        label: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
