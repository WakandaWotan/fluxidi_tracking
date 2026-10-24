import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
const customerRideRouteGold=Color(0xFFE0B63F);
Future<Uint8List> customerRideTargetMarker({required bool destination}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(2);
  final outline = ui.Path()
    ..moveTo(22, 54)
    ..cubicTo(18, 45, 3, 31, 3, 22)
    ..arcToPoint(
      const ui.Offset(41, 22),
      radius: const ui.Radius.circular(19),
      clockwise: true,
    )
    ..cubicTo(41, 31, 26, 45, 22, 54)
    ..close();
  canvas.drawPath(
    outline,
    ui.Paint()
      ..color = const Color(0xFF302C23)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3,
  );
  canvas.drawPath(
    outline,
    ui.Paint()
      ..color = destination ? const Color(0xFFB73D39) : customerRideRouteGold,
  );
  canvas.drawCircle(
    const ui.Offset(22, 22),
    8,
    ui.Paint()..color = Colors.white,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(88, 112);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

