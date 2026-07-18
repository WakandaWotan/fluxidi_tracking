import 'package:flutter/material.dart';

/// NAV-VEHICLE-MODE-CAR-ARROW-1 (Phase 6): professional lightweight 2D
/// navigation arrow marker.
///
/// Pure vector [CustomPainter] — no GLB, no ModelLayer, no network asset. Like
/// the 2D car HUD it is screen-fixed and points straight up (forward); the map
/// rotates underneath it, so it always indicates the travel course. It stays
/// readable on light and dark map backgrounds via a contrasting outline plus a
/// subtle drop shadow.
class NavigationDriverArrowMarker extends StatelessWidget {
  const NavigationDriverArrowMarker({
    super.key,
    this.size = 56.0,
    this.fillColor = const Color(0xFFFFD21F),
    this.outlineColor = const Color(0xFF0B1326),
  });

  final double size;
  final Color fillColor;
  final Color outlineColor;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Semantics(
        label: 'Driver navigation arrow',
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _NavigationArrowPainter(
              fillColor: fillColor,
              outlineColor: outlineColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationArrowPainter extends CustomPainter {
  const _NavigationArrowPainter({
    required this.fillColor,
    required this.outlineColor,
  });

  final Color fillColor;
  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // A forward-pointing chevron/arrowhead with a notched tail, centered.
    final path = Path()
      ..moveTo(w * 0.5, h * 0.06) // nose (top)
      ..lineTo(w * 0.90, h * 0.90) // bottom-right
      ..lineTo(w * 0.5, h * 0.68) // tail notch (center)
      ..lineTo(w * 0.10, h * 0.90) // bottom-left
      ..close();

    // Subtle drop shadow for separation from the map.
    canvas.drawShadow(
      path.shift(const Offset(0, 1.5)),
      Colors.black.withValues(alpha: 0.55),
      4.0,
      true,
    );

    // Filled body.
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = fillColor;
    canvas.drawPath(path, fill);

    // Contrasting outline so it reads on light and dark backgrounds.
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = (w * 0.055).clamp(1.6, 4.0)
      ..color = outlineColor;
    canvas.drawPath(path, outline);

    // Bright inner rim for extra contrast on dark map styles.
    final innerRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = (w * 0.018).clamp(0.6, 1.6)
      ..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawPath(path, innerRim);
  }

  @override
  bool shouldRepaint(covariant _NavigationArrowPainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.outlineColor != outlineColor;
  }
}
