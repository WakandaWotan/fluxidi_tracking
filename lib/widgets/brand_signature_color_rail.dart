import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';

const Key kBrandSignatureColorRailKey = Key('brand_signature_color_rail');
const Key kBrandSignatureColorRailThumbKey = Key(
  'brand_signature_color_rail_thumb',
);
const Key kBrandSignatureSvFieldKey = Key('brand_signature_sv_field');
const Key kBrandSignatureSvThumbKey = Key('brand_signature_sv_thumb');
const double kBrandSignatureColorRailMinHeight = 48;
const double kBrandSignatureSvFieldMinHeight = 132;

/// Full 0–360° hue rail. [hue] is degrees.
class BrandSignatureColorRail extends StatelessWidget {
  const BrandSignatureColorRail({
    super.key,
    required this.hue,
    required this.onHueChanged,
  });

  final double hue;
  final ValueChanged<double> onHueChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight < kBrandSignatureColorRailMinHeight
            ? kBrandSignatureColorRailMinHeight
            : constraints.maxHeight;
        final t = (hue % 360) / 360.0;
        const thumb = 26.0;
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
                const Positioned.fill(child: CustomPaint(painter: _HuePainter())),
                Positioned(
                  left: travel * t,
                  top: (height - thumb) / 2,
                  child: const _StudioThumb(key: kBrandSignatureColorRailThumbKey),
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
    onHueChanged(((dx / width).clamp(0.0, 1.0) * 360) % 360);
  }
}

/// Saturation/value field for the current hue.
class BrandSignatureSvField extends StatelessWidget {
  const BrandSignatureSvField({
    super.key,
    required this.hsv,
    required this.onChanged,
  });

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight < kBrandSignatureSvFieldMinHeight
            ? kBrandSignatureSvFieldMinHeight
            : constraints.maxHeight;
        const thumb = 22.0;
        final left = (hsv.saturation.clamp(0.0, 1.0) * (width - thumb)).clamp(
          0.0,
          width,
        );
        final top = ((1 - hsv.value.clamp(0.0, 1.0)) * (height - thumb)).clamp(
          0.0,
          height,
        );
        return SizedBox(
          key: kBrandSignatureSvFieldKey,
          width: width,
          height: height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _emit(details.localPosition, width, height),
            onPanStart: (details) => _emit(details.localPosition, width, height),
            onPanUpdate: (details) =>
                _emit(details.localPosition, width, height),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _SvPainter(hue: hsv.hue)),
                ),
                Positioned(
                  left: left,
                  top: top,
                  child: const _StudioThumb(key: kBrandSignatureSvThumbKey),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _emit(Offset local, double width, double height) {
    if (width <= 0 || height <= 0) return;
    final saturation = (local.dx / width).clamp(0.0, 1.0);
    final value = (1 - local.dy / height).clamp(0.0, 1.0);
    onChanged(HSVColor.fromAHSV(1, hsv.hue, saturation, value));
  }
}

class _StudioThumb extends StatelessWidget {
  const _StudioThumb({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.transparent,
        border: Border.all(color: Colors.white, width: 2.2),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0xCC000000), blurRadius: 4, spreadRadius: 0.6),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.all(1.4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF111111), width: 1.2),
        ),
      ),
    );
  }
}

class _HuePainter extends CustomPainter {
  const _HuePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(16),
    );
    canvas.save();
    canvas.clipRRect(rect);
    canvas.drawRRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: kBrandSignatureHueSpectrum,
        ).createShader(Offset.zero & size),
    );
    canvas.restore();
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = kBrandSignatureGoldAccent.withOpacity(0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _HuePainter oldDelegate) => false;
}

class _SvPainter extends CustomPainter {
  const _SvPainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(16),
    );
    canvas.save();
    canvas.clipRRect(rect);
    canvas.drawRRect(
      rect,
      Paint()..color = HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x00000000), Color(0xFF000000)],
        ).createShader(Offset.zero & size),
    );
    canvas.restore();
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = kBrandSignatureGoldAccent.withOpacity(0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _SvPainter oldDelegate) => oldDelegate.hue != hue;
}
