import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/subscription_summary_header.dart';

void main() {
  setUpAll(() async {
    // Use the Android text/icon fonts rather than square Ahem placeholders
    // when measuring visible footer height and capturing real text.
    final fontRoot = '${Platform.environment['FLUTTER_ROOT'] ?? 'C:/dev/flutter'}/bin/cache/artifacts/material_fonts';
    await ui.loadFontFromList(File('$fontRoot/roboto-regular.ttf').readAsBytesSync(), fontFamily: 'Roboto');
    await ui.loadFontFromList(File('$fontRoot/MaterialIcons-Regular.otf').readAsBytesSync(), fontFamily: 'MaterialIcons');
  });

  for (final width in [320.0, 390.0, 800.0]) {
    for (final scale in [1.0, 1.5]) {
      for (final internal in [false, true]) {
        testWidgets(
          'subscription summary fits $width/$scale internal=$internal',
          (tester) async {
            tester.view.physicalSize = Size(width, 1200);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              MaterialApp(
              theme: ThemeData(fontFamily: 'Roboto'),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 1200),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Scaffold(
                    backgroundColor: const Color(0xfffffbf3),
                    body: Align(
                      alignment: Alignment.topCenter,
                      child: RepaintBoundary(
                        key: const Key('summary_shot'),
                        child: Container(
                          color: const Color(0xfffffbf3),
                          padding: const EdgeInsets.all(16),
                          child: SubscriptionSummaryHeader(
                            title: internal
                                ? 'Intern ontwikkelaccount'
                                : 'Fluxidi Pro',
                            subtitle: 'België',
                            badge: const Chip(label: Text('Intern')),
                            amount: internal
                                ? 'Gratis — geen abonnementsincasso'
                                : '€69',
                            period: internal
                                ? 'Onbeperkt voertuigen en chauffeurs'
                                : '/ maand excl. btw',
                            internalAccount: internal,
                            textColor: Colors.black,
                            secondaryTextColor: Colors.black87,
                            accent: const Color(0xff786214),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            expect(tester.takeException(), isNull);
            final summary = find.byType(SubscriptionSummaryHeader);
            expect(
              tester.getSize(summary).height,
              lessThan(350),
              reason:
                  'No stretched account card or zero-width per-letter wrapping',
            );
            expect(tester.getBottomRight(summary).dx, lessThanOrEqualTo(width));
            if (internal && width == 390 && scale == 1.5) {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const Key('summary_shot')),
              );
              final image = await tester.runAsync(
                () => boundary.toImage(pixelRatio: 2),
              );
              final bytes = await tester.runAsync(
                () async => (await image!.toByteData(
                  format: ui.ImageByteFormat.png,
                ))!.buffer.asUint8List(),
              );
              final dir = Directory('.device-check/compact-ui');
              dir.createSync(recursive: true);
              File(
                '${dir.path}/subscription-internal-phone.png',
              ).writeAsBytesSync(bytes!);
            }
          },
        );
      }
    }
  }
}
