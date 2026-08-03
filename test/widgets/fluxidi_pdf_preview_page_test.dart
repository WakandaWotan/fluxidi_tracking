// FLUXIDI-PDF-VIEWER-PINCH-ZOOM-1
// FLUXIDI-INVOICE-PDF-PAGINATION-LOGO-ADDRESS-AND-ZOOM-P0-1
//
// Widget tests for the shared in-app PDF preview widget used by ride
// receipts and business invoice PDFs.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluxidi_tracking/widgets/fluxidi_pdf_preview_page.dart';

/// Minimal 1×1 transparent PNG. Enough for `Image.memory` to lay out.
final Uint8List _fakePngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

/// Minimal one-page PDF bytes (valid enough for `/Type /Page` counting).
final Uint8List _onePagePdf = Uint8List.fromList(
  '''%PDF-1.1
1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj
2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj
3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>endobj
trailer<< /Root 1 0 R >>
%%EOF'''.codeUnits,
);

/// Minimal two-page PDF bytes.
final Uint8List _twoPagePdf = Uint8List.fromList(
  '''%PDF-1.1
1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj
2 0 obj<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>endobj
3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>endobj
4 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>endobj
trailer<< /Root 1 0 R >>
%%EOF'''.codeUnits,
);

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  group('PDF page-count proof (bytes, not viewer duplication)', () {
    test('one-page PDF bytes report exactly one /Type /Page', () {
      expect(countPdfPageObjects(_onePagePdf), 1);
    });

    test('two-page PDF bytes report exactly two /Type /Page', () {
      expect(countPdfPageObjects(_twoPagePdf), 2);
    });
  });

  group('zoom / clamp helpers', () {
    test('double-tap matrix zooms around focal point', () {
      final m = fluxidiPdfDoubleTapMatrix(
        focalPoint: const Offset(100, 200),
        scale: 2.5,
      );
      expect(m.getMaxScaleOnAxis(), closeTo(2.5, 1e-9));
      expect(m.storage[12], closeTo(-100 * 1.5, 1e-6));
      expect(m.storage[13], closeTo(-200 * 1.5, 1e-6));
    });

    test('clamp keeps content from vanishing outside viewport', () {
      final extreme = Matrix4.identity()
        ..translate(-5000.0, -5000.0)
        ..scale(3.0);
      final clamped = fluxidiPdfClampTransform(
        current: extreme,
        viewport: const Size(400, 800),
        content: const Size(400, 566),
      );
      final tx = clamped.storage[12];
      final ty = clamped.storage[13];
      // At least 20% of the viewport should still overlap content.
      expect(tx, greaterThan(-400 * 3.0));
      expect(ty, greaterThan(-566 * 3.0));
      expect(tx, lessThan(400.0));
      expect(ty, lessThan(800.0));
    });

    test('fit-width short document recentres vertically to top', () {
      final drifted = Matrix4.identity()..translate(0.0, 120.0);
      final clamped = fluxidiPdfClampTransform(
        current: drifted,
        viewport: const Size(400, 800),
        content: const Size(384, 543),
      );
      expect(clamped.storage[13], 0);
      expect(clamped.getMaxScaleOnAxis(), closeTo(1.0, 1e-9));
    });
  });

  group('FluxidiPdfPagesView', () {
    testWidgets('one-page document: single InteractiveViewer, no PageView', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          FluxidiPdfPagesView(pages: <Uint8List>[_fakePngBytes]),
        ),
      );
      await tester.pump();

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(PageView), findsNothing);
      expect(find.byType(ListView), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('viewer page widgets equal supplied raster page count', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          FluxidiPdfPagesView(
            pages: <Uint8List>[
              _fakePngBytes,
              _fakePngBytes,
              _fakePngBytes,
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsNWidgets(3));
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(PageView), findsNothing);
    });

    testWidgets('one-page PDF is not duplicated by the viewer', (tester) async {
      await tester.pumpWidget(
        _wrap(
          FluxidiPdfPagesView(pages: <Uint8List>[_fakePngBytes]),
        ),
      );
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('InteractiveViewer has scale enabled and fit-width minScale', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          FluxidiPdfPagesView(pages: <Uint8List>[_fakePngBytes]),
        ),
      );
      await tester.pump();

      final iv = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(iv.scaleEnabled, isTrue);
      expect(iv.panEnabled, isTrue);
      expect(iv.minScale, 1.0);
      expect(iv.maxScale, greaterThan(2.0));
      expect(iv.constrained, isFalse);
      expect(iv.transformationController, isNotNull);
    });

    testWidgets('initial transform is identity (fit-width, centred)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          FluxidiPdfPagesView(pages: <Uint8List>[_fakePngBytes]),
        ),
      );
      await tester.pump();

      final state = tester.state<FluxidiPdfPagesViewState>(
        find.byType(FluxidiPdfPagesView),
      );
      expect(state.transformationController.value, Matrix4.identity());
      expect(state.isZoomed, isFalse);
    });

    testWidgets('double-tap zooms around tap; second tap returns to fit-width', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          FluxidiPdfPagesView(
            pages: <Uint8List>[_fakePngBytes, _fakePngBytes],
          ),
        ),
      );
      await tester.pump();

      final state = tester.state<FluxidiPdfPagesViewState>(
        find.byType(FluxidiPdfPagesView),
      );

      expect(state.transformationController.value, Matrix4.identity());

      state.debugTriggerDoubleTap(const Offset(100, 200));
      await tester.pump();
      expect(
        state.transformationController.value,
        isNot(Matrix4.identity()),
      );
      expect(
        state.transformationController.value.getMaxScaleOnAxis(),
        closeTo(2.5, 0.05),
      );

      state.debugTriggerDoubleTap(const Offset(100, 200));
      await tester.pump();
      expect(state.transformationController.value, Matrix4.identity());
    });

    testWidgets('share and print actions remain on FluxidiPdfPreviewPage', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FluxidiPdfPreviewPage(
            title: 'Factuur',
            bytes: _onePagePdf,
            shareTooltip: 'Share PDF',
            printTooltip: 'Print PDF',
          ),
        ),
      );
      // FutureBuilder waiting on Printing.raster — assert AppBar actions exist
      // without waiting for platform rasterization.
      expect(find.byTooltip('Share PDF'), findsOneWidget);
      expect(find.byTooltip('Print PDF'), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
      expect(find.byIcon(Icons.print_outlined), findsOneWidget);
    });

    testWidgets('multi-page column remains a single zoom surface', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          FluxidiPdfPagesView(
            pages: <Uint8List>[
              _fakePngBytes,
              _fakePngBytes,
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(Column), findsWidgets);
      expect(find.byType(Image), findsNWidgets(2));
    });
  });
}
