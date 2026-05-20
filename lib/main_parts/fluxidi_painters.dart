part of '../main.dart';

class _BusinessDemandMapOverlayPainter extends CustomPainter {
  const _BusinessDemandMapOverlayPainter({
    required this.totalDemand,
    required this.demandColor,
    required this.centerColor,
  });

  final int totalDemand;
  final Color demandColor;
  final Color centerColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final minSide = math.min(size.width, size.height);
    final demand = totalDemand < 0 ? 0 : totalDemand;
    final hasDemand = demand > 0;

    // Privacy-safe visual haze: decorative signal, not customer GPS.
    final hazePaint = Paint()
      ..color = demandColor.withOpacity(hasDemand ? 0.10 : 0.03)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, minSide * (hasDemand ? 0.30 : 0.22), hazePaint);
    if (hasDemand) {
      canvas.drawCircle(
        center,
        minSide * 0.20,
        hazePaint..color = demandColor.withOpacity(0.07),
      );
    }

    final centerOuter = Paint()
      ..color = centerColor.withOpacity(0.22)
      ..style = PaintingStyle.fill;
    final centerMid = Paint()
      ..color = centerColor.withOpacity(0.46)
      ..style = PaintingStyle.fill;
    final centerCore = Paint()
      ..color = centerColor.withOpacity(0.95)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, minSide * 0.072, centerOuter);
    canvas.drawCircle(center, minSide * 0.038, centerMid);
    canvas.drawCircle(center, minSide * 0.016, centerCore);

    const anchors = <Offset>[
      Offset(-0.34, -0.24),
      Offset(0.30, -0.28),
      Offset(-0.44, 0.12),
      Offset(0.39, 0.18),
      Offset(-0.16, 0.35),
      Offset(0.18, -0.05),
      Offset(0.47, -0.08),
      Offset(-0.28, -0.39),
    ];
    final signalCount = demand == 0
        ? 0
        : demand == 1
        ? 1
        : demand <= 5
        ? 2 + (demand >= 4 ? 1 : 0)
        : 4;
    final spread = minSide * 0.67;

    for (var i = 0; i < signalCount; i++) {
      final factor = demand == 1 ? 1.0 : (1.0 - (i * 0.11)).clamp(0.56, 0.95);
      final anchor = anchors[i];
      final signalCenter =
          center + Offset(anchor.dx * spread, anchor.dy * spread);
      final outer = Paint()
        ..color = demandColor.withOpacity(0.10 * factor)
        ..style = PaintingStyle.fill;
      final mid = Paint()
        ..color = demandColor.withOpacity(0.20 * factor)
        ..style = PaintingStyle.fill;
      final core = Paint()
        ..color = demandColor.withOpacity(0.72 * factor)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(signalCenter, minSide * 0.055, outer);
      canvas.drawCircle(signalCenter, minSide * 0.028, mid);
      canvas.drawCircle(signalCenter, minSide * 0.012, core);
    }
  }

  @override
  bool shouldRepaint(covariant _BusinessDemandMapOverlayPainter oldDelegate) {
    return oldDelegate.totalDemand != totalDemand ||
        oldDelegate.demandColor != demandColor ||
        oldDelegate.centerColor != centerColor;
  }
}

class _RegionRadarPainter extends CustomPainter {
  const _RegionRadarPainter({
    required this.customerColor,
    required this.partnerColor,
    required this.showPartnerOpportunity,
  });

  final Color customerColor;
  final Color partnerColor;
  final bool showPartnerOpportunity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.56);
    final baseRadius = math.min(size.width, size.height) * 0.38;

    final bgGrid = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, baseRadius * (i / 3), bgGrid);
    }

    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              customerColor.withOpacity(0.30),
              customerColor.withOpacity(0.10),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(center: center, radius: baseRadius * 1.02),
          );
    canvas.drawCircle(center, baseRadius, glow);

    final ring = Paint()
      ..color = customerColor.withOpacity(0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, baseRadius * 0.9, ring);

    final pulse = Paint()
      ..color = customerColor.withOpacity(0.26)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    canvas.drawCircle(center, baseRadius * 0.58, pulse);

    const normalizedDots = <Offset>[
      Offset(0.18, 0.27),
      Offset(0.32, 0.34),
      Offset(0.66, 0.24),
      Offset(0.78, 0.38),
      Offset(0.22, 0.52),
      Offset(0.42, 0.58),
      Offset(0.62, 0.56),
      Offset(0.81, 0.63),
      Offset(0.48, 0.73),
      Offset(0.30, 0.71),
      Offset(0.67, 0.78),
    ];
    for (final p in normalizedDots) {
      final dot = Offset(size.width * p.dx, size.height * p.dy);
      final dotPaint = Paint()..color = customerColor.withOpacity(0.96);
      canvas.drawCircle(dot, 2.8, dotPaint);
      final halo = Paint()..color = customerColor.withOpacity(0.28);
      canvas.drawCircle(dot, 6.5, halo);
    }

    if (showPartnerOpportunity) {
      final partnerDot = Offset(size.width * 0.74, size.height * 0.48);
      final partnerPaint = Paint()..color = partnerColor.withOpacity(0.92);
      canvas.drawCircle(partnerDot, 3.3, partnerPaint);
      final partnerHalo = Paint()..color = partnerColor.withOpacity(0.22);
      canvas.drawCircle(partnerDot, 8.0, partnerHalo);
    }

    final mapLabelStyle = TextStyle(
      color: Colors.white.withOpacity(0.56),
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
    );
    final labels = <({String text, Offset pos})>[
      (text: 'Schorisse', pos: const Offset(0.13, 0.20)),
      (text: 'Ronse', pos: const Offset(0.76, 0.19)),
      (text: 'Oudenaarde', pos: const Offset(0.17, 0.82)),
      (text: 'Kluisbergen', pos: const Offset(0.66, 0.73)),
      (text: 'Flobecq', pos: const Offset(0.58, 0.34)),
    ];
    for (final entry in labels) {
      final tp = TextPainter(
        text: TextSpan(text: entry.text, style: mapLabelStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 120);
      tp.paint(
        canvas,
        Offset(size.width * entry.pos.dx, size.height * entry.pos.dy),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RegionRadarPainter oldDelegate) {
    return oldDelegate.customerColor != customerColor ||
        oldDelegate.partnerColor != partnerColor ||
        oldDelegate.showPartnerOpportunity != showPartnerOpportunity;
  }
}
