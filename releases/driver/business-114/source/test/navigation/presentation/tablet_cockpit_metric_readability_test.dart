import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/widgets/cockpit_widget.dart';

void main() {
  for (final size in [const Size(350, 700), const Size(640, 380), const Size(1280, 800)]) {
    testWidgets('tablet metrics readable at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: CockpitWidget(
        hostIsTablet: true, etaText: '48 min', kmText: '55.4', priceText: '88.90',
        tripStarted: false, isWaiting: false, navActive: true,
        onNav: () {}, onStart: () {}, onStop: () {}, onWait: () {}, onGo: () {},
      ))));
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (final value in ['48 min', '55.4', '88.90']) {
        final text = tester.widget<Text>(find.text(value));
        expect(text.style!.fontSize, greaterThanOrEqualTo(18));
      }
    });
  }
}
