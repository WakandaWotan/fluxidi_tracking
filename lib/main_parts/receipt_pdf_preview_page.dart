part of '../main.dart';

class _ReceiptPdfPreviewPage extends StatefulWidget {
  final String title;
  final Uint8List bytes;

  const _ReceiptPdfPreviewPage({required this.title, required this.bytes});

  @override
  State<_ReceiptPdfPreviewPage> createState() => _ReceiptPdfPreviewPageState();
}

class _ReceiptPdfPreviewPageState extends State<_ReceiptPdfPreviewPage> {
  late final Future<List<Uint8List>> _pagesFuture = _renderPages();

  Future<List<Uint8List>> _renderPages() async {
    final pages = <Uint8List>[];
    await for (final page in Printing.raster(widget.bytes, dpi: 200)) {
      pages.add(await page.toPng());
    }
    return pages;
  }

  Future<void> _sharePdf() async {
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}receipt-preview.pdf',
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
            tooltip: _receiptText('sharePdf'),
            onPressed: _sharePdf,
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: _receiptText('printReceipt'),
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
            return Center(child: Text(_receiptText('pdfGenerationFailed')));
          }
          return PageView.builder(
            itemCount: pages.length,
            itemBuilder: (context, index) {
              final page = pages[index];
              return Container(
                color: const Color(0xFF101010),
                alignment: Alignment.center,
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 6.0,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(8),
                    child: Image.memory(
                      page,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
