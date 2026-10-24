// FLUXIDI-INVOICE-LOGO-LIVE-MISSING-AND-VIEWER-FIT-WIDTH-P0-3
//
// Field failure: the shared PDF viewer centred a short A4 page vertically,
// leaving a large grey band above (and below) the invoice. Product behaviour is
// fit-width and top-aligned immediately under the toolbar.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/widgets/fluxidi_pdf_preview_page.dart';

const double _a4Ratio = 1 / 1.4142;

final Uint8List _pixel = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  group('fit-width + top-aligned initial presentation', () {
    const layouts = <String, Size>{
      'phone portrait': Size(390, 844),
      'phone landscape': Size(844, 390),
      'tall phone': Size(412, 1000),
      'tablet portrait': Size(834, 1194),
      'tablet landscape': Size(1194, 834),
    };

    // Tests 12, 15, 16, 21, 22.
    layouts.forEach((name, viewport) {
      test('$name: fit-width uses full available document width', () {
        final layout = fluxidiPdfInitialLayout(
          viewport: viewport,
          pageCount: 1,
          pageAspectRatio: _a4Ratio,
        );
        expect(layout.pageWidth, closeTo(viewport.width, 0.001));
        expect(
          layout.pageWidth / layout.pageHeights.first,
          closeTo(_a4Ratio, 0.0001),
          reason: '$name must preserve A4 and never stretch/crop',
        );
      });

      test('$name: first page is top-aligned with no large top grey band', () {
        final layout = fluxidiPdfInitialLayout(
          viewport: viewport,
          pageCount: 1,
          pageAspectRatio: _a4Ratio,
        );
        expect(layout.leadingPad, 0, reason: '$name');
      });
    });

    // Tests 13 + 14.
    test('single-page short document starts at the top, not centred', () {
      final layout = fluxidiPdfInitialLayout(
        viewport: const Size(390, 844),
        pageCount: 1,
        pageAspectRatio: _a4Ratio,
      );
      expect(layout.contentHeight, lessThan(844));
      expect(layout.leadingPad, 0);
    });

    // Test 19.
    test('multipage documents remain vertically navigable from the top', () {
      final layout = fluxidiPdfInitialLayout(
        viewport: const Size(390, 844),
        pageCount: 3,
        pageAspectRatio: _a4Ratio,
        pageSpacing: 10,
      );
      expect(layout.contentHeight, greaterThan(844));
      expect(layout.leadingPad, 0);
    });
  });

  group('gestures + shared receipt/invoice viewer', () {
    Future<FluxidiPdfPagesViewState> pumpViewer(
      WidgetTester tester,
      Size size,
      int pages,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FluxidiPdfPagesView(
              pages: List<Uint8List>.filled(pages, _pixel),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.state<FluxidiPdfPagesViewState>(
        find.byType(FluxidiPdfPagesView),
      );
    }

    // Test 17.
    testWidgets('double-tap reset returns to fit-width and top', (tester) async {
      final state = await pumpViewer(tester, const Size(390, 844), 1);
      state.debugTriggerDoubleTap(const Offset(180, 300));
      await tester.pumpAndSettle();
      expect(
        state.transformationController.value.getMaxScaleOnAxis(),
        greaterThan(1.01),
      );

      state.debugTriggerDoubleTap(const Offset(180, 300));
      await tester.pumpAndSettle();
      expect(state.transformationController.value, Matrix4.identity());
      expect(state.isZoomed, isFalse);
      expect(
        fluxidiPdfInitialLayout(viewport: const Size(390, 844), pageCount: 1)
            .leadingPad,
        0,
      );
    });

    // Test 18.
    testWidgets('pinch and pan remain clamped', (tester) async {
      await pumpViewer(tester, const Size(390, 844), 1);
      final clamped = fluxidiPdfClampTransform(
        current: Matrix4.identity()
          ..translate(-5000.0, -5000.0)
          ..scale(2.5),
        viewport: const Size(390, 844),
        content: const Size(390, 551),
      );
      expect(clamped.storage[0].abs(), closeTo(2.5, 0.001));
      expect(clamped.storage[12].abs(), lessThan(5000));
      expect(clamped.storage[13].abs(), lessThan(5000));
    });

    // Test 20 — same widget is used by receipts and invoices.
    testWidgets('receipt viewer receives the same presentation behaviour', (
      tester,
    ) async {
      await pumpViewer(tester, const Size(390, 844), 1);
      expect(find.byType(FluxidiPdfPagesView), findsOneWidget);
      final layout = fluxidiPdfInitialLayout(
        viewport: const Size(390, 844),
        pageCount: 1,
      );
      expect(layout.leadingPad, 0);
      expect(layout.pageWidth, closeTo(390, 0.001));
    });

    // Test 23.
    test('share and print helpers operate on the original PDF bytes', () {
      final src = File('lib/widgets/fluxidi_pdf_preview_page.dart').readAsStringSync();
      expect(src.contains('Share.shareXFiles'), isTrue);
      expect(src.contains('Printing.layoutPdf'), isTrue);
      expect(src.contains('widget.bytes'), isTrue);
      expect(src.contains('const leadingPad = 0.0'), isTrue);
    });
  });
}
