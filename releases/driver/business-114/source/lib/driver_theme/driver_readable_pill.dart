import 'package:flutter/material.dart';
import '../driver_theme_palette.dart';

/// A ride badge whose text and icon are paired with its own opaque surface.
class DriverReadablePill extends StatelessWidget {
  const DriverReadablePill({
    super.key,
    required this.text,
    required this.surface,
    required this.foreground,
    required this.border,
    this.icon,
    this.compact = false,
  });

  final String text;
  final Color surface, foreground, border;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final readable = driverReadableTextOn(surface, foreground);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 14 : 16, color: readable),
            SizedBox(width: compact ? 4 : 6),
          ],
          Text(
            text,
            style: TextStyle(color: readable, fontSize: compact ? 12.2 : null),
          ),
        ],
      ),
    );
  }
}
