import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../widgets/fluxidi_pdf_preview_page.dart';
import 'limousine_quote_inbox.dart';

class LimousineQuotationPdfAction extends StatefulWidget {
  const LimousineQuotationPdfAction({
    super.key,
    required this.label,
    required this.previewTitle,
    required this.errorLabel,
    required this.loadBytes,
    this.buttonKey = kLimousineQuoteViewQuotationKey,
  });

  final String label;
  final String previewTitle;
  final String errorLabel;
  final Future<Uint8List> Function() loadBytes;
  final Key buttonKey;

  @override
  State<LimousineQuotationPdfAction> createState() =>
      _LimousineQuotationPdfActionState();
}

class _LimousineQuotationPdfActionState
    extends State<LimousineQuotationPdfAction> {
  bool _loading = false;
  bool _error = false;

  Future<void> _open() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final bytes = await widget.loadBytes();
      if (!mounted) return;
      if (bytes.isEmpty) {
        setState(() {
          _loading = false;
          _error = true;
        });
        return;
      }
      setState(() => _loading = false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              FluxidiPdfPreviewPage(title: widget.previewTitle, bytes: bytes),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          key: widget.buttonKey,
          onPressed: _loading ? null : _open,
          child: _loading
              ? const SizedBox(
                  key: kLimousineQuoteViewQuotationLoadingKey,
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.label),
        ),
        if (_error)
          Padding(
            key: kLimousineQuoteViewQuotationErrorKey,
            padding: const EdgeInsets.only(top: 8),
            child: Text(widget.errorLabel),
          ),
      ],
    );
  }
}
