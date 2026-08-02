// FLUXIDI-PDF-VIEWER-PINCH-ZOOM-1
//
// Widget tests for the shared in-app PDF preview widget used by ride
// receipts and business invoice PDFs. Locks the following contract:
//
//   * No `PageView` wraps the pages — a horizontal PageView historically
//     stole pinch-to-zoom gestures on Android phones.
//   * Each page is rendered inside its own `InteractiveViewer` with
//     `scaleEnabled: true`, `panEnabled: true`, and a sane min/max scale.
//   * Double-tap-to-zoom toggles between identity and the configured
//     double-tap scale, centred on the tapped point.
//   * Zoom state is per-page and does not bleed across pages.
//   * A single page renders without any PageView regression.
//
// The widget is exercised through `FluxidiPdfPagesView`, which accepts
// already-rasterized PNG bytes, so these tests do not depend on the
// `printing` platform channel.

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

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  group('FluxidiPdfPagesView', () {
    testWidgets('renders one InteractiveViewer per page (single page)', (
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
    });

    testWidgets(
      'multi-page: one controller per page and never a PageView',
      (tester) async {
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

        final state = tester.state<FluxidiPdfPagesViewState>(
          find.byType(FluxidiPdfPagesView),
        );
        // Per-page transformation controllers must match the page count so
        // each page keeps its own zoom state.
        expect(state.controllerAt(0), isA<TransformationController>());
        expect(state.controllerAt(2), isA<TransformationController>());
        // Every built page uses InteractiveViewer (ListView is lazy so we
        // only assert at least one is present, plus the PageView regression
        // guard which is what actually matters).
        expect(find.byType(InteractiveViewer), findsWidgets);
        expect(find.byType(PageView), findsNothing);
      },
    );

    testWidgets('InteractiveViewer has scale enabled and sane bounds', (
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
      expect(iv.minScale, lessThan(1.0));
      expect(iv.maxScale, greaterThan(2.0));
      expect(iv.transformationController, isNotNull);
    });

    testWidgets('double-tap on a page zooms in, second double-tap resets', (
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

      expect(state.controllerAt(0).value, Matrix4.identity());

      state.debugTriggerDoubleTap(0, const Offset(100, 200));
      await tester.pump();
      expect(state.controllerAt(0).value, isNot(Matrix4.identity()));
      // Second page must not be zoomed — zoom state is per-page.
      expect(state.controllerAt(1).value, Matrix4.identity());

      state.debugTriggerDoubleTap(0, const Offset(100, 200));
      await tester.pump();
      expect(state.controllerAt(0).value, Matrix4.identity());
    });

    testWidgets('zoom on one page does not affect the sibling page', (
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

      state.debugTriggerDoubleTap(1, const Offset(50, 50));
      await tester.pump();

      expect(state.controllerAt(0).value, Matrix4.identity());
      expect(state.controllerAt(1).value, isNot(Matrix4.identity()));
    });

    testWidgets('background scroll host is a ListView, not a PageView', (
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

      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(PageView), findsNothing);
    });
  });
}
