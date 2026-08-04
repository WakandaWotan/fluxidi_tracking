import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// One rasterized PDF page plus its pixel size (for true fit-to-width layout).
@immutable
class FluxidiPdfRasterPage {
  const FluxidiPdfRasterPage({
    required this.bytes,
    required this.widthPx,
    required this.heightPx,
  });

  final Uint8List bytes;
  final int widthPx;
  final int heightPx;

  double get aspectRatio {
    if (widthPx <= 0 || heightPx <= 0) return 1 / 1.4142;
    return widthPx / heightPx;
  }
}

/// Shared, testable in-app PDF preview page used by ride receipts, business
/// invoice PDFs, credit notes, and refund proofs.
///
/// The page rasterizes every PDF page to a PNG through the `printing`
/// platform channel and renders the results with pinch-to-zoom, double-tap
/// zoom, clamped panning while zoomed, and vertical document scrolling.
/// Share and print actions live in the AppBar and reuse the original PDF
/// bytes (never the raster) so quality and vector selection are preserved.
///
/// Design notes:
///  * No `PageView` — horizontal PageView historically competed with pinch
///    zoom on Android phones.
///  * One `InteractiveViewer` owns the whole document (all pages in a column)
///    so zoom does not detach pages into independent floating canvases.
///  * Fit-width is identity scale (`minScale == 1`) with near-zero horizontal
///    padding so the A4 page fills the usable phone width.
///  * Page aspect ratio comes from the raster pixels (not a hard-coded A4
///    guess) so `BoxFit.contain` does not letterbox the page smaller.
///  * Viewer page count equals `Printing.raster` page count (never invents
///    duplicate pages).
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
  late final Future<List<FluxidiPdfRasterPage>> _pagesFuture = _renderPages();

  Future<List<FluxidiPdfRasterPage>> _renderPages() async {
    final pages = <FluxidiPdfRasterPage>[];
    await for (final page in Printing.raster(
      widget.bytes,
      dpi: widget.rasterDpi,
    )) {
      final png = await page.toPng();
      final sized = await decodeFluxidiPdfRasterPage(png);
      pages.add(sized);
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
        toolbarHeight: 48,
        titleSpacing: 8,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
      body: FutureBuilder<List<FluxidiPdfRasterPage>>(
        future: _pagesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final pages = snapshot.data ?? const <FluxidiPdfRasterPage>[];
          if (pages.isEmpty) {
            return Center(child: Text(widget.generationFailedLabel));
          }
          return FluxidiPdfPagesView(pages: pages);
        },
      ),
    );
  }
}

/// Decode PNG raster bytes to a sized page (used by the preview page and tests).
@visibleForTesting
Future<FluxidiPdfRasterPage> decodeFluxidiPdfRasterPage(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final page = FluxidiPdfRasterPage(
    bytes: png,
    widthPx: image.width,
    heightPx: image.height,
  );
  image.dispose();
  return page;
}

/// Pure helpers for zoom / clamp math — unit-tested without a full widget tree.
@visibleForTesting
Matrix4 fluxidiPdfDoubleTapMatrix({
  required Offset focalPoint,
  required double scale,
}) {
  final s = scale;
  return Matrix4.identity()
    ..translate(-focalPoint.dx * (s - 1), -focalPoint.dy * (s - 1))
    ..scale(s);
}

@visibleForTesting
Matrix4 fluxidiPdfClampTransform({
  required Matrix4 current,
  required Size viewport,
  required Size content,
  double edgeKeepFraction = 0.2,
}) {
  final values = current.storage;
  final scale = values[0].abs() < 1e-9 ? 1.0 : values[0].abs();
  var tx = values[12];
  var ty = values[13];

  final scaledW = content.width * scale;
  final scaledH = content.height * scale;
  final keepX = viewport.width * edgeKeepFraction;
  final keepY = viewport.height * edgeKeepFraction;

  // Horizontal: keep at least [keepX] of the page inside the viewport.
  if (scaledW <= viewport.width) {
    tx = (viewport.width - scaledW) / 2;
  } else {
    final minTx = viewport.width - scaledW - keepX;
    final maxTx = keepX;
    tx = tx.clamp(minTx, maxTx);
  }

  // Vertical: allow scrolling the document but never lose the page entirely.
  if (scaledH <= viewport.height) {
    ty = math.min(ty, keepY);
    ty = math.max(ty, viewport.height - scaledH - keepY);
    // Prefer top-aligned for short single-page docs at fit-width.
    if (scale <= 1.01) {
      ty = 0;
    }
  } else {
    final minTy = viewport.height - scaledH - keepY;
    final maxTy = keepY;
    ty = ty.clamp(minTy, maxTy);
  }

  return Matrix4.identity()
    ..translate(tx, ty)
    ..scale(scale);
}

/// Initial, undistorted page geometry for the available viewport.
///
/// A4 cannot fill both axes of a phone without cropping or stretching, so the
/// page keeps its aspect ratio at fit-width. The first page is top-aligned
/// immediately below the toolbar — leftover height is reached by scrolling to
/// the document end (never a large grey band above the page).
@visibleForTesting
({
  double pageWidth,
  List<double> pageHeights,
  double leadingPad,
  double contentHeight,
})
fluxidiPdfInitialLayout({
  required Size viewport,
  required int pageCount,
  double pageAspectRatio = 1 / 1.4142,
  List<double>? pageAspectRatios,
  // Near-zero pad so A4 fills usable phone width (field: page looked too small).
  double horizontalPadding = 0,
  double pageSpacing = 8,
}) {
  final fallbackRatio = pageAspectRatio <= 0 ? 1 / 1.4142 : pageAspectRatio;
  final pageWidth = math.max(1.0, viewport.width - horizontalPadding * 2);
  final pages = pageCount <= 0 ? 0 : pageCount;
  final heights = <double>[];
  for (var i = 0; i < pages; i++) {
    final ratio =
        (pageAspectRatios != null &&
            i < pageAspectRatios.length &&
            pageAspectRatios[i] > 0)
        ? pageAspectRatios[i]
        : fallbackRatio;
    heights.add(pageWidth / ratio);
  }
  final stackHeight = heights.isEmpty
      ? 0.0
      : heights.reduce((a, b) => a + b) +
            math.max(0, heights.length - 1) * pageSpacing;
  // Fit-width + top-aligned: never vertically centre the first page.
  const leadingPad = 0.0;
  return (
    pageWidth: pageWidth,
    pageHeights: heights,
    leadingPad: leadingPad,
    contentHeight: stackHeight,
  );
}

/// Count `/Type /Page` dictionaries in raw PDF bytes (not `/Pages`).
@visibleForTesting
int countPdfPageObjects(Uint8List bytes) {
  final text = String.fromCharCodes(bytes);
  final re = RegExp(r'/Type\s*/Page(?![s\w])');
  return re.allMatches(text).length;
}

/// Presentational widget that renders already-rasterized PDF page PNGs.
///
/// Kept public so widget tests can drive it with synthetic PNG bytes without
/// invoking the platform PDF rasterizer.
class FluxidiPdfPagesView extends StatefulWidget {
  const FluxidiPdfPagesView({
    super.key,
    required this.pages,
    this.minScale = 1.0,
    this.maxScale = 6.0,
    this.doubleTapScale = 2.5,
    // Neutral surround that frames the document instead of a near-black void.
    this.backgroundColor = const Color(0xFF33363B),
    this.pageColor = Colors.white,
    this.pageAspectRatio = 1 / 1.4142,
    this.pageSpacing = 8,
    this.horizontalPadding = 0,
  });

  /// Prefer [FluxidiPdfRasterPage] (pixel-accurate fit-width). Raw [Uint8List]
  /// pages remain accepted for older call sites / tests (A4 aspect fallback).
  final List<Object> pages;
  final double minScale;
  final double maxScale;
  final double doubleTapScale;
  final Color backgroundColor;
  final Color pageColor;
  final double pageAspectRatio;
  final double pageSpacing;
  final double horizontalPadding;

  @override
  State<FluxidiPdfPagesView> createState() => FluxidiPdfPagesViewState();
}

@visibleForTesting
class FluxidiPdfPagesViewState extends State<FluxidiPdfPagesView> {
  final TransformationController _controller = TransformationController();
  TapDownDetails? _lastDoubleTapDown;
  Size _viewport = Size.zero;
  Size _content = Size.zero;
  bool _zoomed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @visibleForTesting
  TransformationController get transformationController => _controller;

  @visibleForTesting
  bool get isZoomed => _zoomed;

  @visibleForTesting
  void debugTriggerDoubleTap(Offset localPosition) {
    _lastDoubleTapDown = TapDownDetails(localPosition: localPosition);
    _handleDoubleTap();
  }

  @visibleForTesting
  void debugSetViewportAndContent({
    required Size viewport,
    required Size content,
  }) {
    _viewport = viewport;
    _content = content;
  }

  void _syncZoomedFlag() {
    final scale = _controller.value.getMaxScaleOnAxis();
    final next = scale > 1.01;
    if (next != _zoomed && mounted) {
      setState(() => _zoomed = next);
    } else {
      _zoomed = next;
    }
  }

  void _clampCurrent() {
    if (_viewport == Size.zero || _content == Size.zero) return;
    final clamped = fluxidiPdfClampTransform(
      current: _controller.value,
      viewport: _viewport,
      content: _content,
    );
    if (clamped != _controller.value) {
      _controller.value = clamped;
    }
    _syncZoomedFlag();
  }

  void _handleDoubleTap() {
    final details = _lastDoubleTapDown;
    final scale = _controller.value.getMaxScaleOnAxis();
    if (scale > 1.01 || details == null) {
      _controller.value = Matrix4.identity();
      _syncZoomedFlag();
      return;
    }
    _controller.value = fluxidiPdfDoubleTapMatrix(
      focalPoint: details.localPosition,
      scale: widget.doubleTapScale,
    );
    _clampCurrent();
  }

  List<FluxidiPdfRasterPage> get _normalizedPages {
    return widget.pages.map((raw) {
      if (raw is FluxidiPdfRasterPage) return raw;
      if (raw is Uint8List) {
        return FluxidiPdfRasterPage(bytes: raw, widthPx: 0, heightPx: 0);
      }
      throw ArgumentError(
        'FluxidiPdfPagesView.pages must be FluxidiPdfRasterPage or Uint8List',
      );
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final normalized = _normalizedPages;
    return ColoredBox(
      color: widget.backgroundColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          final pageCount = normalized.length;
          final ratios = normalized
              .map((p) => p.aspectRatio)
              .toList(growable: false);
          final layout = fluxidiPdfInitialLayout(
            viewport: viewport,
            pageCount: pageCount,
            pageAspectRatio: widget.pageAspectRatio,
            pageAspectRatios: ratios,
            horizontalPadding: widget.horizontalPadding,
            pageSpacing: widget.pageSpacing,
          );
          final pageWidth = layout.pageWidth;
          final contentHeight = layout.contentHeight;
          final content = Size(pageWidth, contentHeight);
          _viewport = viewport;
          _content = content;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTapDown: (details) => _lastDoubleTapDown = details,
            onDoubleTap: _handleDoubleTap,
            child: InteractiveViewer(
              transformationController: _controller,
              minScale: widget.minScale,
              maxScale: widget.maxScale,
              // Tight margin: keep zoom usable without shrinking fit-width.
              boundaryMargin: EdgeInsets.symmetric(
                horizontal: viewport.width * 0.08,
                vertical: viewport.height * 0.12,
              ),
              constrained: false,
              clipBehavior: Clip.hardEdge,
              panEnabled: true,
              scaleEnabled: true,
              alignment: Alignment.topCenter,
              onInteractionEnd: (_) => _clampCurrent(),
              onInteractionUpdate: (_) => _syncZoomedFlag(),
              child: SizedBox(
                width: pageWidth,
                child: pageCount == 0
                    ? const SizedBox.shrink()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (layout.leadingPad > 0)
                            SizedBox(height: layout.leadingPad),
                          for (var i = 0; i < pageCount; i++) ...[
                            if (i > 0)
                              SizedBox(height: widget.pageSpacing),
                            SizedBox(
                              width: pageWidth,
                              height: layout.pageHeights[i],
                              child: ColoredBox(
                                color: widget.pageColor,
                                child: Image.memory(
                                  normalized[i].bytes,
                                  fit: BoxFit.fitWidth,
                                  alignment: Alignment.topCenter,
                                  gaplessPlayback: true,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
