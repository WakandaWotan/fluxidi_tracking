import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/company/driver_management_native_page.dart';
import 'driver_management_native_test_support.dart';

void main() {
  setUpAll(() async {
    for (final f in [
      (
        'MaterialIcons',
        'C:/dev/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
      (
        'Roboto',
        'D:/Projecten/_flutter_work/fluxidi_diva_driver_management/features/diva-driver-management/web/partner-assets/roboto-regular.ttf',
      ),
    ]) {
      await (FontLoader(f.$1)..addFont(
            Future.value(ByteData.sublistView(File(f.$2).readAsBytesSync())),
          ))
          .load();
    }
  });
  for (final variant in BusinessThemeVariant.values) {
    for (final size in [(390.0, 844.0), (1280.0, 800.0)]) {
      testWidgets('Production management ${variant.name} ${size.$1}', (
        tester,
      ) async {
        tester.view.physicalSize = Size(size.$1, size.$2);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = NativeDriverFixture(),
            session = ValueNotifier<Object?>(Object()),
            theme = ValueNotifier(variant);
        addTearDown(session.dispose);
        addTearDown(theme.dispose);
        final actions = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: const ValueKey('capture'),
              child: ValueListenableBuilder(
                valueListenable: theme,
                builder: (_, value, __) => DriverManagementNativePage(
                  palette: paletteForBusinessTheme(value),
                  connect: () async => f.repository(),
                  session: session,
                  openLegacy: () => actions.add('legacy'),
                  manageDriver: (id) async => actions.add('manage:$id'),
                  addDriver: () async => actions.add('add'),
                  globalAction: (a) async => actions.add(a),
                  driverAction: (id, a) async => actions.add('$a:$id'),
                  openPartners: () => actions.add('partners'),
                  avatar: (id, size) => SizedBox(
                    key: ValueKey('scoped-photo-$id'),
                    width: size,
                    height: size,
                    child: const Icon(Icons.person),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('ONTWERP'), findsNothing);
        expect(find.text(f.company), findsNothing);
        expect(find.text('driver-1'), findsNothing);
        final vertical = find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first;
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('native-driver-detail-driver-1')),
          250,
          scrollable: vertical,
        );
        await Scrollable.ensureVisible(
          tester.element(
            find.byKey(const ValueKey('native-driver-detail-driver-1')),
          ),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('scoped-photo-driver-1')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('native-driver-detail-driver-1')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('native-driver-detail-title')),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Bewerken'));
        await tester.tap(find.text('Bewerken'));
        await tester.pumpAndSettle();
        expect(actions, contains('edit:driver-1'));
        // Return to list and change theme without a fresh login/repository.
        await tester.tap(find.widgetWithText(ChoiceChip, 'Chauffeurs'));
        await tester.pumpAndSettle();
        theme.value = variant == BusinessThemeVariant.cleanProfessional
            ? BusinessThemeVariant.corporateBlue
            : BusinessThemeVariant.cleanProfessional;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
        final context = tester.element(find.byWidget(scaffold));
        expect(
          Theme.of(context).scaffoldBackgroundColor,
          paletteForBusinessTheme(theme.value).background,
        );
        theme.value = variant;
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          for (final image in tester.widgetList<Image>(find.byType(Image))) {
            await precacheImage(image.image, context);
          }
        });
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1),
              png = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            'D:/Projecten/outputs/business98_final_management_20261013/native-${variant.name}-${size.$1.toInt()}.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}
