// Business invoice layout visual baseline (48px logo — unchanged by this work).
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<void> main() async {
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
  final logo = Uint8List.fromList(img.encodePng(image));
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Image(
                pw.MemoryImage(logo),
                height: 48,
                fit: pw.BoxFit.contain,
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Demo Taxi BV',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text('BTW BE0123.456.789'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Factuur',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Invoice logo CSS height remains 48px (unchanged).'),
        ],
      ),
    ),
  );
  final out = File(
    'test_reports/document_pdf_logo_scale/business_invoice_layout_UNCHANGED.pdf',
  );
  out.writeAsBytesSync(await doc.save());
  stdout.writeln('wrote ${out.path}');
}
