// Generates visual proof PDFs for ordinary receipt logo scale + addresses.
// Run: dart run tool/render_receipt_logo_address_proof.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:fluxidi_tracking/main_parts/receipt_route_address.dart';

Uint8List _syntheticWideLogo() {
  // ~4.5:1 company wordmark stand-in (matches Branding & support aspect).
  final image = img.Image(width: 664, height: 145);
  img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));
  img.fillRect(
    image,
    x1: 24,
    y1: 28,
    x2: 640,
    y2: 117,
    color: img.ColorRgba8(20, 40, 90, 255),
  );
  img.drawString(
    image,
    'COMPANY LOGO',
    font: img.arial24,
    x: 200,
    y: 60,
    color: img.ColorRgba8(255, 255, 255, 255),
  );
  return Uint8List.fromList(img.encodePng(image));
}

Future<Uint8List> _buildReceiptPdf({
  required double logoW,
  required double logoH,
  required String from,
  required String to,
}) async {
  final logo = _syntheticWideLogo();
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Container(
              width: logoW,
              height: logoH,
              color: PdfColors.white,
              child: pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Demo Taxi BV',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text('BTW BE0123.456.789'),
                  pw.Text('Voorbeeldstraat 1'),
                  pw.Text('9000 Gent'),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Text(
          'Betaalbewijs',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),
        pw.Text('Van: $from'),
        pw.SizedBox(height: 4),
        pw.Text('Naar: $to'),
        pw.SizedBox(height: 12),
        pw.Text('Totaal: € 24.50'),
        pw.Text('BTW 6%: € 1.39'),
        pw.Text('Betaalstatus: betaald'),
      ],
    ),
  );
  return doc.save();
}

Future<void> main() async {
  final outDir = Directory('test_reports/document_pdf_logo_scale');
  outDir.createSync(recursive: true);

  final resolved = resolveReceiptRouteAddresses(
    rawSource: {
      'from': '50.772006, 3.669447',
      'to': '50.8500, 3.6100',
      'invoice_from_address': 'Koekamerstraat 48A, 9688 Schorisse',
      'invoice_to_address': 'Stationsplein 1, 9700 Oudenaarde',
    },
    origin: '50.772006, 3.669447',
    destination: '50.8500, 3.6100',
  );

  final before = await _buildReceiptPdf(
    logoW: 82,
    logoH: 82,
    from: '50.772006, 3.669447',
    to: '50.8500, 3.6100',
  );
  final after = await _buildReceiptPdf(
    logoW: kReceiptPdfLogoBoxWidth,
    logoH: kReceiptPdfLogoBoxHeight,
    from: resolved.from ?? 'MISSING',
    to: resolved.to ?? 'MISSING',
  );

  final beforePath = File('${outDir.path}/ordinary_receipt_BEFORE_small_logo.pdf');
  final afterPath = File('${outDir.path}/ordinary_receipt_AFTER_large_logo.pdf');
  beforePath.writeAsBytesSync(before);
  afterPath.writeAsBytesSync(after);

  // Invoice layout unchanged marker (layout constants only — no regeneration).
  File('${outDir.path}/INVOICE_LAYOUT_UNCHANGED.txt').writeAsStringSync(
    'Business invoice logo CSS remains INVOICE_LOGO_CSS_HEIGHT_PX=48.\n'
    'No invoice PDF regeneration in this change.\n'
    'Prior opaque-RGB acceptance (INV-039/040) remains the invoice visual baseline.\n',
  );

  stdout.writeln('Wrote ${beforePath.path}');
  stdout.writeln('Wrote ${afterPath.path}');
  stdout.writeln('from=${resolved.from}');
  stdout.writeln('to=${resolved.to}');
}
