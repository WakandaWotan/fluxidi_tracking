import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Shared, testable in-app PDF preview page used by ride receipts, business
/// invoice PDFs, credit notes, and refund proofs.
///
/// The page rasterizes every PDF page to a PNG through the `printing`
/// platform channel and renders the results with pinch-to-zoom, double-tap
/// zoom, panning while zoomed, and native vertical scrolling between pages.
/// Share and print actions live in the AppBar and reuse the original PDF
/// bytes (never the raster) so quality and vector selection are preserved.
///
/// Design notes:
///  * No `PageView` wraps the pages. Horizontal swipe gestures from a
///    `PageView` compete with `InteractiveViewer` scale gestures on Android
///    phones, which historically broke pinch-to-zoom in this app. A vertical
///    `ListView` with per-page `InteractiveViewer` avoids that conflict.
///  * Each page owns its own `TransformationController` so zoom state does
///    not bleed between pages.
///  * No `WebView`, no external Android intent — the viewer is a plain
///    Flutter widget so back navigation, share, and print stay in-app.
class FluxidiPdfPreviewPage extends StatefulWidget {
  const FluxidiPdfPreviewPage({
    super.key,
    required this.title,
    required this.bytes,
    this.shareTooltip = 'Share',
    this.printTooltip = 'Print',
    this.generationFailedLabel = 'PDF generation failed',
    this.rasterDpi = 200,
  });

  final String title;
  final Uint8List bytes;
  final String shareTooltip;
  final String printTooltip;
  final String generationFailedLabel;
  final double rasterDpi;

  @override
  State<FluxidiPdfPreviewPage> createState() => _FluxidiPdfPreviewPageState();
}

class _FluxidiPdfPreviewPageState extends State<FluxidiPdfPreviewPage> {
  late final Future<List<Uint8List>> _pagesFuture = _renderPages();

  Future<List<Uint8List>> _renderPages() async {
    final pages = <Uint8List>[];
    await for (final page in Printing.raster(
      widget.bytes,
      dpi: widget.rasterDpi,
    )) {
      pages.add(await page.toPng());
    }
    return pages;
  }

  Future<void> _sharePdf() async {
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}fluxidi-preview.pdf',
    );
    await file.writeAsBytes(widget.bytes, flush: true);
    await Share.shareXFiles(<XFile>[XFile(file.path)], subject: widget.title);
  }

  Future<void> _printPdf() async {
    await Printing.layoutPdf(onLayout: (_) async => widget.bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: widget.shareTooltip,
            onPressed: _sharePdf,
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: widget.printTooltip,
            onPressed: _printPdf,
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
      body: FutureBuilder<List<Uint8List>>(
        future: _pagesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final pages = snapshot.data ?? const <Uint8List>[];
          if (pages.isEmpty) {
            return Center(child: Text(widget.generationFailedLabel));
          }
          return FluxidiPdfPagesView(pages: pages);
        },
      ),
    );
  }
}

/// Presentational widget that renders already-rasterized PDF page PNGs with
/// reliable Android pinch-to-zoom, double-tap-to-zoom, panning while zoomed,
/// and normal vertical scrolling between pages.
///
/// Kept as a public widget so widget tests can drive it with synthetic PNG
/// bytes without invoking the platform PDF rasterizer.
class FluxidiPdfPagesView extends StatefulWidget {
  const FluxidiPdfPagesView({
    super.key,
    required this.pages,
    this.minScale = 0.75,
    this.maxScale = 6.0,
    this.doubleTapScale = 2.5,
    this.backgroundColor = const Color(0xFF101010),
    this.pageColor = Colors.white,
    // Approximate A4 portrait ratio (width / height). Rasterized PDF pages
    // sit inside a slot of this aspect and fit via BoxFit.contain, so the
    // full page is always visible at scale 1×.
    this.pageAspectRatio = 1 / 1.4142,
  });

  final List<Uint8List> pages;
  final double minScale;
  final double maxScale;
  final double doubleTapScale;
  final Color backgroundColor;
  final Color pageColor;
  final double pageAspectRatio;

  @override
  State<FluxidiPdfPagesView> createState() => FluxidiPdfPagesViewState();
}

@visibleForTesting
class FluxidiPdfPagesViewState extends State<FluxidiPdfPagesView> {
  late List<TransformationController> _controllers;
  late List<TapDownDetails?> _lastDoubleTapDown;

  @override
  void initState() {
    super.initState();
    _rebuildControllers(widget.pages.length);
  }

  @override
  void didUpdateWidget(covariant FluxidiPdfPagesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pages.length != widget.pages.length) {
      _disposeControllers();
      _rebuildControllers(widget.pages.length);
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _rebuildControllers(int count) {
    _controllers = List<TransformationController>.generate(
      count,
      (_) => TransformationController(),
      growable: false,
    );
    _lastDoubleTapDown = List<TapDownDetails?>.filled(count, null);
  }

  void _disposeControllers() {
    for (final c in _controllers) {
      c.dispose();
    }
  }

  @visibleForTesting
  TransformationController controllerAt(int index) => _controllers[index];

  @visibleForTesting
  void debugTriggerDoubleTap(int index, Offset localPosition) {
    _lastDoubleTapDown[index] = TapDownDetails(localPosition: localPosition);
    _handleDoubleTap(index);
  }

  void _handleDoubleTap(int index) {
    final controller = _controllers[index];
    final details = _lastDoubleTapDown[index];
    final zoomedIn = controller.value != Matrix4.identity();
    if (zoomedIn || details == null) {
      controller.value = Matrix4.identity();
      return;
    }
    final position = details.localPosition;
    final scale = widget.doubleTapScale;
    controller.value = Matrix4.identity()
      ..translate(-position.dx * (scale - 1), -position.dy * (scale - 1))
      ..scale(scale);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.backgroundColor,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        itemCount: widget.pages.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final page = widget.pages[index];
          final controller = _controllers[index];
          return AspectRatio(
            aspectRatio: widget.pageAspectRatio,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTapDown: (details) =>
                  _lastDoubleTapDown[index] = details,
              onDoubleTap: () => _handleDoubleTap(index),
              child: InteractiveViewer(
                transformationController: controller,
                minScale: widget.minScale,
                maxScale: widget.maxScale,
                boundaryMargin: const EdgeInsets.all(200),
                panEnabled: true,
                scaleEnabled: true,
                child: Container(
                  color: widget.pageColor,
                  padding: const EdgeInsets.all(8),
                  child: Image.memory(
                    page,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
