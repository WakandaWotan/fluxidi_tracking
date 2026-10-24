import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver/driver_ride_alert_controller.dart';
import 'package:fluxidi_tracking/driver/driver_ride_frame_border.dart';

void main() {
  for (final reduce in [false, true]) {
    testWidgets('pending ride has conspicuous red frame; reduced motion=$reduce', (tester) async {
      final alerts = DriverRideAlertController(play: (_) async {}, stop: () async {}, nowMs: () => 0);
      final owner = Object();
      const idle = BoxDecoration(border: Border.fromBorderSide(BorderSide(color: Color(0xffd7b23c), width: 3)));
      await tester.pumpWidget(MaterialApp(home: MediaQuery(data: MediaQueryData(disableAnimations: reduce),
        child: DriverRideFrameBorder(controller: alerts, decoration: idle, child: const SizedBox.expand()))));
      BoxDecoration frame() => tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration as BoxDecoration;
      alerts.present(owner: owner, identity: 'pending', deadlineMs: 60000);
      await tester.pump(); await tester.pump(const Duration(milliseconds: 800));
      final color = (frame().border as Border).top.color;
      expect(color.r, greaterThan(color.g * 1.8));
      expect(color.r, greaterThan(color.b * 1.8));
      expect(color.a, 1);
      alerts.stop(owner: owner); await tester.pump();
      expect(frame(), idle);
      await tester.pumpWidget(const SizedBox()); alerts.dispose();
    });
  }
}
