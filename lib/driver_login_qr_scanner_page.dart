import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class DriverLoginQrScannerPage extends StatefulWidget {
  const DriverLoginQrScannerPage({super.key});

  @override
  State<DriverLoginQrScannerPage> createState() =>
      _DriverLoginQrScannerPageState();
}

class _DriverLoginQrScannerPageState extends State<DriverLoginQrScannerPage> {
  bool _handled = false;

  void _handleDetect(BarcodeCapture capture) {
    if (_handled) return;
    final barcode = capture.barcodes.isNotEmpty ? capture.barcodes.first : null;
    final raw = barcode?.rawValue?.trim() ?? '';
    if (raw.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07080C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF07080C),
        foregroundColor: Colors.white,
        title: const Text('Scan bedrijfs QR'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Text(
            'Richt de camera op de QR-code van de bedrijfsleider.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.86),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(onDetect: _handleDetect),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFFE5B641).withOpacity(0.7),
                          width: 1.4,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
