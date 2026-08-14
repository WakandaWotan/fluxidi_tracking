import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';

const Key kBrandSignatureColorRailKey = Key('brand_signature_color_rail');
const Key kBrandSignatureColorRailThumbKey = Key(
  'brand_signature_color_rail_thumb',
);
const double kBrandSignatureColorRailMinHeight = 56;

/// One continuous lacquer rail. Position is 0.0–1.0, interpolated between
/// the Brand Signature anchors — never a stepped swatch row.
class BrandSignatureColorRail extends StatelessWidget {
  const BrandSignatureColorRail({
    super.key,
    required this.position,
    required this.onChanged,
  });

  final double position;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight < kBrandSignatureColorRailMinHeight
            ? kBrandSignatureColorRailMinHeight
            : constraints.maxHeight;
        final t = position.clamp(0.0, 1.0);
        const thumb = 28.0;
        final travel = (width - thumb).clamp(0.0, width);
        return SizedBox(
          key: kBrandSignatureColorRailKey,
          width: width,
          height: height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _emit(details.localPosition.dx, width),
            onHorizontalDragStart: (details) =>
                _emit(details.localPosition.dx, width),
            onHorizontalDragUpdate: (details) =>
                _emit(details.localPosition.dx, width),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned.fill(
                  child: CustomPaint(painter: _RailPainter()),
                ),
                Positioned(
                  left: travel * t,
                  top: (height - thumb) / 2,
                  child: const _RailThumb(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _emit(double dx, double width) {
    if (width <= 0) return;
    onChanged((dx / width).clamp(0.0, 1.0));
  }
}

class _RailThumb extends StatelessWidget {
  const _RailThumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: kBrandSignatureColorRailThumbKey,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF8F0D8),
        border: Border.all(color: kBrandSignatureGoldAccent, width: 2.4),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x99000000), blurRadius: 8, spreadRadius: 0.4),
        ],
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  const _RailPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(18),
    );
    final shader = LinearGradient(
      colors: kBrandSignatureRailAnchors,
    ).createShader(Offset.zero & size);
    canvas.drawRRect(rect, Paint()..shader = shader);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = kBrandSignatureGoldAccent.withOpacity(0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _RailPainter oldDelegate) => false;
}
