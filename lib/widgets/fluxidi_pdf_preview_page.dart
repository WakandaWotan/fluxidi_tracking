import 'dart:io';
import 'dart:math' as math;
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
/// zoom, clamped panning while zoomed, and vertical document scrolling.
/// Share and print actions live in the AppBar and reuse the original PDF
/// bytes (never the raster) so quality and vector selection are preserved.
///
/// Design notes:
///  * No `PageView` — horizontal PageView historically competed with pinch
///    zoom on Android phones.
///  * One `InteractiveViewer` owns the whole document (all pages in a column)
///    so zoom does not detach pages into independent floating canvases.
///  * Fit-width is identity scale (`minScale == 1`). At fit-width, vertical
///    pan scrolls the document; when zoomed, pan moves within clamped bounds.
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
/// page keeps its aspect ratio at fit-width and any leftover height becomes a
/// symmetric surround instead of dead space below a top-anchored page.
@visibleForTesting
({double pageWidth, double pageHeight, double leadingPad, double contentHeight})
fluxidiPdfInitialLayout({
  required Size viewport,
  required int pageCount,
  double pageAspectRatio = 1 / 1.4142,
  double horizontalPadding = 8,
  double pageSpacing = 10,
}) {
  final ratio = pageAspectRatio <= 0 ? 1 / 1.4142 : pageAspectRatio;
  final pageWidth = math.max(1.0, viewport.width - horizontalPadding * 2);
  final pageHeight = pageWidth / ratio;
  final pages = pageCount <= 0 ? 0 : pageCount;
  final stackHeight = pages == 0
      ? 0.0
      : pages * pageHeight + math.max(0, pages - 1) * pageSpacing;
  // Centre a document that is shorter than the viewport; never push a taller
  // document down, which would hide its first page.
  final leadingPad = stackHeight <= 0 || stackHeight >= viewport.height
      ? 0.0
      : (viewport.height - stackHeight) / 2;
  return (
    pageWidth: pageWidth,
    pageHeight: pageHeight,
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
    this.pageSpacing = 10,
    this.horizontalPadding = 8,
  });

  final List<Uint8List> pages;
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

  double _pageHeightForWidth(double width) {
    if (widget.pageAspectRatio <= 0) return width * 1.4142;
    return width / widget.pageAspectRatio;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.backgroundColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          final pageCount = widget.pages.length;
          final layout = fluxidiPdfInitialLayout(
            viewport: viewport,
            pageCount: pageCount,
            pageAspectRatio: widget.pageAspectRatio,
            horizontalPadding: widget.horizontalPadding,
            pageSpacing: widget.pageSpacing,
          );
          final pageWidth = layout.pageWidth;
          final pageHeight = layout.pageHeight;
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
              // Limited margin so zoomed content cannot drift into a huge
              // empty canvas / leave the viewport almost empty.
              boundaryMargin: EdgeInsets.symmetric(
                horizontal: viewport.width * 0.25,
                vertical: viewport.height * 0.25,
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
                              height: pageHeight,
                              child: ColoredBox(
                                color: widget.pageColor,
                                child: Image.memory(
                                  widget.pages[i],
                                  fit: BoxFit.contain,
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
