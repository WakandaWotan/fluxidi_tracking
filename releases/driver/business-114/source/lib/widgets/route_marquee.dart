import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Route ticker marquee (single line, seamless loop)
class RouteMarquee extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Duration period;
  final double gap;

  const RouteMarquee({
    super.key,
    required this.text,
    required this.style,
    this.period = const Duration(seconds: 14),
    this.gap = 48,
  });

  @override
  State<RouteMarquee> createState() => _RouteMarqueeState();
}

class _RouteMarqueeState extends State<RouteMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.period)..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double _textWidth() {
    final tp = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final tw = _textWidth();
        final base = math.max(tw, w);
        final travel = base + widget.gap;

        return ClipRect(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final dx = -((_ctrl.value * travel) % travel);
              return Transform.translate(
                offset: Offset(dx, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.text,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      softWrap: false,
                      style: widget.style,
                    ),
                    SizedBox(width: widget.gap),
                    Text(
                      widget.text,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      softWrap: false,
                      style: widget.style,
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
