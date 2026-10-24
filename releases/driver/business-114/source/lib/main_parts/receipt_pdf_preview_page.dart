part of '../main.dart';

/// Ride-receipt / business-invoice PDF preview route.
///
/// Thin adapter around the shared, testable [FluxidiPdfPreviewPage] widget in
/// `lib/widgets/fluxidi_pdf_preview_page.dart`. The shared widget owns the
/// rasterization, pinch-to-zoom, double-tap zoom, share, and print behavior;
/// this adapter only supplies the localized AppBar and tooltip strings from
/// the app's existing `_receiptText` locale helper.
class _ReceiptPdfPreviewPage extends StatelessWidget {
  final String title;
  final Uint8List bytes;

  const _ReceiptPdfPreviewPage({required this.title, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return FluxidiPdfPreviewPage(
      title: title,
      bytes: bytes,
      shareTooltip: _receiptText('sharePdf'),
      printTooltip: _receiptText('printReceipt'),
      generationFailedLabel: _receiptText('pdfGenerationFailed'),
    );
  }
}
