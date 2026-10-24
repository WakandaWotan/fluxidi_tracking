import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver/driver_ride_alert_controller.dart';
import 'package:fluxidi_tracking/driver/driver_ride_frame_border.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer_panel.dart';
import 'package:fluxidi_tracking/main.dart' show FluxidiFrame;
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';

void main() {
  setUpAll(() async {
    for (final file in {
      'Roboto': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      final loader = FontLoader(file.key)
        ..addFont(
          File(
            'C:/dev/flutter/bin/cache/artifacts/material_fonts/${file.value}',
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
  });
  for (final color in [const Color(0xffd7b23c), const Color(0xff2464cc)]) {
    for (final reduce in [false, true]) {
      testWidgets(
        'Outer decoration preserves geometry and touch: $color reduced=$reduce',
        (tester) async {
          final c = DriverRideAlertController(
            play: (_) async {},
            stop: () async {},
            nowMs: () => 0,
          );
          addTearDown(c.dispose);
          final owner = Object();
          var taps = 0;
          final d = BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: color, width: 3),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduce),
                child: DriverRideFrameBorder(
                  controller: c,
                  decoration: d,
                  child: SizedBox.expand(
                    child: TextButton(
                      key: const ValueKey('touch'),
                      onPressed: () => taps++,
                      child: const Text('Aanvaarden'),
                    ),
                  ),
                ),
              ),
            ),
          );
          final rect = tester.getRect(find.byKey(const ValueKey('touch')));
          BoxDecoration current() =>
              tester
                      .widgetList<DecoratedBox>(find.byType(DecoratedBox))
                      .first
                      .decoration
                  as BoxDecoration;
          expect(current(), d);
          c.present(owner: owner, identity: 'offer', deadlineMs: 60000);
          await tester.pump();
          final first = current();
          await tester.pump(const Duration(milliseconds: 800));
          final second = current();
          expect(tester.getRect(find.byKey(const ValueKey('touch'))), rect);
          expect(second.borderRadius, d.borderRadius);
          expect((second.border! as Border).top.width, 3);
          if (reduce) {
            expect(second, first);
          } else {
            expect(second, isNot(first));
          }
          await tester.tap(find.byKey(const ValueKey('touch')));
          expect(taps, 1);
          c.stop(owner: owner);
          await tester.pump();
          expect(current(), d);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final width in [390.0, 900.0]) {
    for (final variant in [
      BusinessThemeVariant.executiveGold,
      BusinessThemeVariant.corporateBlue,
    ]) {
      testWidgets('Actual global frame with compact request: $width $variant', (
        tester,
      ) async {
        final oldBusiness = businessThemeNotifier.value,
            oldActive = businessShellFrameActiveNotifier.value;
        final oldDriver = chauffeurShellFrameThemeNotifier.value;
        businessThemeNotifier.value = variant;
        businessShellFrameActiveNotifier.value = true;
        chauffeurShellFrameThemeNotifier.value = null;
        final owner = Object(), alerts = DriverRideAlertController.instance;
        addTearDown(() {
          alerts.stop(owner: owner);
          businessThemeNotifier.value = oldBusiness;
          businessShellFrameActiveNotifier.value = oldActive;
          chauffeurShellFrameThemeNotifier.value = oldDriver;
          tester.view.reset();
        });
        tester.view.physicalSize = Size(width, width < 500 ? 844 : 1200);
        tester.view.devicePixelRatio = 1;
        final now = DateTime.now().millisecondsSinceEpoch;
        final offer = DriverRideOffer(
          id: 'screen-$width-$variant',
          version: 1,
          vehicleId: 'fixture',
          deadlineMs: now + 60000,
          pickup: 'Koekamerstraat 48 bus A, 9688 Schorisse',
          destination: 'Broeke 98, 9600 Ronse',
          price: 32,
          requirements: const {'passengers': 2},
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: companyOpsMaterialTheme(paletteForBusinessTheme(variant)),
            home: RepaintBoundary(
              key: const ValueKey('capture'),
              child: FluxidiFrame(
                child: Scaffold(
                  body: DriverRideOfferPanel(
                    offer: offer,
                    nowMs: now,
                    onDecision: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        final out = Directory(
          Platform.environment['FLUXIDI_AGENT3_RENDER_DIR'] ?? '${Directory.systemTemp.path}/fluxidi-agent3-alert-renders',
        );
        out.createSync(recursive: true);
        Future<void> capture(String phase) async {
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '${out.path}/${variant.name}-${width.toInt()}-$phase.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('idle');
        alerts.present(
          owner: owner,
          identity: offer.id,
          deadlineMs: offer.deadlineMs,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
        await capture('pulse');
        expect(find.byType(DriverRideFrameBorder), findsOneWidget);
        expect(find.byType(DriverRideOfferPanel), findsOneWidget);
        final frame = find.byType(FluxidiFrame);
        final rect = tester.getRect(frame);
        tester.view.physicalSize = Size(tester.view.physicalSize.height, width);
        await tester.pump();
        expect(tester.getSize(frame).width, greaterThan(0));
        expect(rect.width, width);
        alerts.stop(owner: owner);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
