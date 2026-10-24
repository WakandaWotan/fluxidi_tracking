import 'package:flutter/material.dart';

/// NAV-TABLET-TRANSPARENT-HEADER-P1: white fill + black stroke glyphs for
/// navigation copy drawn directly over map styles (Light/Dark/Satellite/3D).
///
/// Phone banners never use this helper.
class NavOutlinedMapText extends StatelessWidget {
  const NavOutlinedMapText({
    super.key,
    required this.text,
    required this.style,
    this.maxLines = 1,
    this.softWrap = true,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
    this.fill = Colors.white,
    this.stroke = const Color(0xFF0A0A0A),
    this.strokeWidth = 3.2,
  });

  final String text;
  final TextStyle style;
  final int maxLines;
  final bool softWrap;
  final TextOverflow overflow;
  final TextAlign? textAlign;
  final Color fill;
  final Color stroke;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final base = style.copyWith(
      color: null,
      foreground: null,
      shadows: const <Shadow>[],
    );
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        Text(
          text,
          maxLines: maxLines,
          softWrap: softWrap,
          overflow: overflow,
          textAlign: textAlign,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..strokeJoin = StrokeJoin.round
              ..color = stroke,
          ),
        ),
        Text(
          text,
          maxLines: maxLines,
          softWrap: softWrap,
          overflow: overflow,
          textAlign: textAlign,
          style: base.copyWith(color: fill),
        ),
      ],
    );
  }
}
