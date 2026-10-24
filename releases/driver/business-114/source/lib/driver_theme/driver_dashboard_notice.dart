import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';

/// Identity text sits on the page on phones, and on the hero scrim on tablets.
class DriverDashboardText extends StatelessWidget {
  const DriverDashboardText({
    super.key,
    required this.text,
    required this.surface,
    required this.foreground,
    required this.style,
    this.maxLines,
  });

  final String text;
  final Color surface;
  final Color foreground;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
    style: style.copyWith(color: driverReadableTextOn(surface, foreground)),
  );
}

/// Explicit colours prevent the company button theme from supplying black
/// foreground to a transparent button on a dark chauffeur dashboard.
class DriverDevicePairingNotice extends StatelessWidget {
  const DriverDevicePairingNotice({
    super.key,
    required this.palette,
    required this.surface,
    required this.message,
    required this.actionLabel,
    required this.paired,
    required this.onPressed,
    this.errorMessage,
  });

  final DriverThemePalette palette;
  final Color surface;
  final String message;
  final String actionLabel;
  final bool paired;
  final VoidCallback? onPressed;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final foreground = driverReadableTextOn(surface, palette.textPrimary);
    return ColoredBox(
      color: surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DriverDashboardText(
            text: message,
            surface: surface,
            foreground: palette.textMuted,
            style: const TextStyle(),
          ),
          if (errorMessage != null)
            DriverDashboardText(
              text: errorMessage!,
              surface: surface,
              foreground: palette.danger,
              style: const TextStyle(),
            ),
          OutlinedButton.icon(
            onPressed: onPressed,
            style: ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(surface),
              foregroundColor: WidgetStatePropertyAll(foreground),
              iconColor: WidgetStatePropertyAll(foreground),
              side: WidgetStatePropertyAll(BorderSide(color: palette.accent)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            icon: Icon(paired ? Icons.drive_eta : Icons.phonelink_lock),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
