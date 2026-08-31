// BOOKINGS-LIST-PAGINATION-CLIENT-P0C
//
// Explicit load-more / retry chrome. Never auto-drains pages.

import 'package:flutter/material.dart';

class BookingListLoadMoreBar extends StatelessWidget {
  const BookingListLoadMoreBar({
    super.key,
    required this.visible,
    required this.loading,
    required this.enabled,
    required this.label,
    required this.semanticsLabel,
    required this.onPressed,
    this.errorText,
    this.retryLabel,
    this.retrySemanticsLabel,
    this.onRetry,
    this.accent,
    this.foreground,
  });

  final bool visible;
  final bool loading;
  final bool enabled;
  final String label;
  final String semanticsLabel;
  final VoidCallback? onPressed;
  final String? errorText;
  final String? retryLabel;
  final String? retrySemanticsLabel;
  final VoidCallback? onRetry;
  final Color? accent;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    if (!visible && (errorText == null || errorText!.trim().isEmpty)) {
      return const SizedBox.shrink();
    }
    final color = accent ?? Theme.of(context).colorScheme.primary;
    final textColor = foreground ?? color;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if ((errorText ?? '').trim().isNotEmpty) ...[
            Text(
              errorText!.trim(),
              textAlign: TextAlign.center,
              style: TextStyle(color: textColor, height: 1.35),
            ),
            const SizedBox(height: 8),
            if (onRetry != null)
              Semantics(
                button: true,
                label: retrySemanticsLabel ?? retryLabel,
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: loading ? null : onRetry,
                    child: Text(retryLabel ?? label),
                  ),
                ),
              ),
          ] else if (visible)
            Semantics(
              button: true,
              enabled: enabled && !loading,
              label: semanticsLabel,
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: enabled && !loading ? onPressed : null,
                  style: OutlinedButton.styleFrom(foregroundColor: color),
                  child: loading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: color,
                          ),
                        )
                      : Text(label),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
