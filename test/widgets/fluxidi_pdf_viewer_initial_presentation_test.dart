// FLUXIDI-CANONICAL-COMPANY-LOGO-AND-INVOICE-PRESENTATION-P0-1
//
// Field failure: the one-page invoice opened with the page pinned to the top of
// a tall phone screen, leaving a large dead background area below it. A4 cannot
// fill both axes of a phone without cropping or stretching, so the page keeps
// fit-width and the leftover height becomes a symmetric neutral surround.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/widgets/fluxidi_pdf_preview_page.dart';

const double _a4Ratio = 1 / 1.4142;

/// 1x1 transparent PNG, enough for Image.memory in a widget test.
final Uint8List _pixel = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  group('initial geometry is undistorted and centered', () {
    const layouts = <String, Size>{
      'phone portrait': Size(390, 844),
      'phone landscape': Size(844, 390),
      'tall phone': Size(412, 1000),
      'tablet portrait': Size(834, 1194),
      'tablet landscape': Size(1194, 834),
    };

    layouts.forEach((name, viewport) {
      test('$name: a single page keeps the A4 ratio exactly', () {
        final layout = fluxidiPdfInitialLayout(
          viewport: viewport,
          pageCount: 1,
          pageAspectRatio: _a4Ratio,
        );
        expect(
          layout.pageWidth / layout.pageHeight,
          closeTo(_a4Ratio, 0.0001),
          reason: '$name must not stretch or crop the page',
        );
        expect(layout.pageWidth, closeTo(viewport.width - 16, 0.001));
        expect(layout.pageWidth, greaterThan(0));
        expect(layout.pageHeight, greaterThan(0));
      });
    });

    test('a short document is centered, not pinned to the top', () {
      // 390x844 phone: an A4 page at 374 wide is ~529 tall, leaving ~315 spare.
      final layout = fluxidiPdfInitialLayout(
        viewport: const Size(390, 844),
        pageCount: 1,
        pageAspectRatio: _a4Ratio,
      );
      expect(layout.contentHeight, lessThan(844));
      expect(layout.leadingPad, greaterThan(0));
      expect(
        layout.leadingPad,
        closeTo((844 - layout.contentHeight) / 2, 0.001),
        reason: 'the surround must be symmetric above and below',
      );
    });

    test('no phone geometry leaves a majority dead area below the page', () {
      for (final viewport in layouts.values) {
        final layout = fluxidiPdfInitialLayout(
          viewport: viewport,
          pageCount: 1,
          pageAspectRatio: _a4Ratio,
        );
        final occupied = layout.contentHeight / viewport.height;
        final belowFraction = layout.leadingPad / viewport.height;
        // Whatever is left over is split evenly, so the gap under the page can
        // never exceed half the leftover - the old top-anchored dead band.
        expect(
          belowFraction,
          lessThan(0.5),
          reason: '$viewport leaves too much space on one side',
        );
        expect(occupied, greaterThan(0.0));
      }
    });

    test('a document taller than the viewport is never pushed down', () {
      final layout = fluxidiPdfInitialLayout(
        viewport: const Size(390, 844),
        pageCount: 3,
        pageAspectRatio: _a4Ratio,
      );
      expect(layout.contentHeight, greaterThan(844));
      expect(
        layout.leadingPad,
        0,
        reason: 'padding would hide the first page of a multipage document',
      );
    });

    test('multipage height accounts for every page and the spacing', () {
      final one = fluxidiPdfInitialLayout(
        viewport: const Size(390, 844),
        pageCount: 1,
        pageAspectRatio: _a4Ratio,
        pageSpacing: 10,
      );
      final three = fluxidiPdfInitialLayout(
        viewport: const Size(390, 844),
        pageCount: 3,
        pageAspectRatio: _a4Ratio,
        pageSpacing: 10,
      );
      expect(three.contentHeight, closeTo(one.contentHeight * 3 + 20, 0.001));
      expect(three.pageWidth, one.pageWidth);
      expect(three.pageHeight, one.pageHeight);
    });

    test('an empty document has no content and no padding', () {
      final layout = fluxidiPdfInitialLayout(
        viewport: const Size(390, 844),
        pageCount: 0,
      );
      expect(layout.contentHeight, 0);
      expect(layout.leadingPad, 0);
    });
  });

  group('gestures survive the new initial presentation', () {
    Future<void> pumpViewer(WidgetTester tester, Size size, int pages) async {
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
    }

    testWidgets('opens at fit-width identity with one zoom surface', (
      tester,
    ) async {
      await pumpViewer(tester, const Size(390, 844), 1);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.scaleEnabled, isTrue);
      expect(viewer.panEnabled, isTrue);
      expect(viewer.minScale, 1.0);
      expect(viewer.maxScale, greaterThan(1.0));
      expect(
        viewer.transformationController!.value,
        Matrix4.identity(),
        reason: 'initial open must be undistorted fit-width',
      );
    });

    testWidgets('double tap zooms around the tap then returns to fitted', (
      tester,
    ) async {
      await pumpViewer(tester, const Size(390, 844), 1);
      final controller = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;

      await tester.tapAt(const Offset(180, 300));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(const Offset(180, 300));
      await tester.pumpAndSettle();
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.01));

      await tester.tapAt(const Offset(180, 300));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(const Offset(180, 300));
      await tester.pumpAndSettle();
      expect(controller.value, Matrix4.identity());
    });

    testWidgets('panning stays clamped within useful bounds', (tester) async {
      await pumpViewer(tester, const Size(390, 844), 1);
      final controller = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;

      controller.value = fluxidiPdfDoubleTapMatrix(
        focalPoint: const Offset(180, 300),
        scale: 2.5,
      );
      await tester.pump();
      await tester.drag(find.byType(InteractiveViewer), const Offset(-4000, 0));
      await tester.pumpAndSettle();

      final clamped = fluxidiPdfClampTransform(
        current: controller.value,
        viewport: const Size(390, 844),
        content: const Size(374, 529),
      );
      expect(clamped.storage[12], closeTo(controller.value.storage[12], 400));
    });

    testWidgets('a neutral surround frames the document', (tester) async {
      await pumpViewer(tester, const Size(390, 844), 1);
      final view = tester.widget<FluxidiPdfPagesView>(
        find.byType(FluxidiPdfPagesView),
      );
      final bg = view.backgroundColor;
      // Not a near-black void, and clearly distinct from the white page so the
      // document reads as framed rather than lost.
      expect(bg, isNot(Colors.black));
      expect(bg.computeLuminance(), greaterThan(0.01));
      expect(bg.computeLuminance(), lessThan(0.5));
      expect(view.pageColor, Colors.white);
    });
  });
}
