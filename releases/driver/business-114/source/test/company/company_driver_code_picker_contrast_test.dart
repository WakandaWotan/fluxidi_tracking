import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/company/company_driver_code_picker_sheet.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
}
void main() {
  test('picker ink stays readable when custom text and surface disagree', () {
    for (final surface in [Colors.white, const Color(0xFFF1EFEA), Colors.black, Colors.grey]) {
      for (final ink in [Colors.white, Colors.black, Colors.grey, Colors.yellow]) {
        expect(contrast(driverCodePickerInk(ink, surface), surface), greaterThanOrEqualTo(4.5));
      }
    }
  });
  setUpAll(() async { final font=FontLoader('ProofText')..addFont(File('C:/Windows/Fonts/segoeui.ttf').readAsBytes().then((b)=>ByteData.sublistView(b))); await font.load(); });
  final palettes={for(final v in BusinessThemeVariant.values)v.name:paletteForBusinessTheme(v),'customLight':brandSignatureBusinessPalette(BrandSignaturePalette.fromColor(Colors.white))};
  for (final variant in palettes.keys) {
    testWidgets('driver code picker readable and selectable in ${variant}', (tester) async {
      final palette = palettes[variant]!;
      var selected = false;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark().copyWith(textTheme:ThemeData.dark().textTheme.apply(fontFamily:'ProofText')), // Reproduce the hostile inherited white text.
        home: Scaffold(body: RepaintBoundary(key: const ValueKey('proof'),
          child: ColoredBox(color: palette.surface, child: CompanyDriverCodePickerSheet(
            palette: palette, title: 'Kies chauffeur voor code',
            entries: [CompanyDriverCodePickerEntry(
              name: 'Test chauffeur', status: 'Code ingesteld', onSelected: () => selected = true,
            )],
          )),
        )),
      ));
      await tester.pump();
      for (final label in ['Kies chauffeur voor code', 'Test chauffeur', 'Code ingesteld']) {
        final ink = tester.widget<Text>(find.text(label)).style!.color!;
        expect(contrast(ink, palette.surface), greaterThanOrEqualTo(4.5), reason: label);
      }
      await tester.tap(find.text('Test chauffeur')); expect(selected, isTrue);
      expect(tester.takeException(), isNull);
      if (variant == 'customLight') {
        await tester.runAsync(() async {
        final image = await tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('proof'))).toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = Directory('test_reports/driver_codes_contrast_20261006')..createSync(recursive: true);
        await File('${output.path}/custom_light.png').writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
        });
      }
    });
  }
}
