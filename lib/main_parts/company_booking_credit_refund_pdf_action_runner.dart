part of '../main.dart';

/// Patch-1 local document runner for company-bookings credit / refund PDFs.
///
/// This runner is intentionally provider-neutral and fully local:
///   * No backend calls (no `/bookings/:id/invoice/pdf`, no `/receipt/email`).
///   * No refund/payment endpoint calls.
///   * No Chiron, Billit, Peppol, OAuth or UBL generation.
///
/// It reuses the existing local PDF infrastructure from
/// [_ReceiptPdfActionRunner] (seller profile, logo bytes, info-row widget,
/// Google fonts) and the existing [_ReceiptPdfPreviewPage] for preview /
/// share / print. The ritbon (receipt) pipeline is NOT modified: a creditnota
/// and a terugbetalingsbewijs are separate document types.
class _CompanyBookingCreditRefundPdfActionRunner {
  /// Document kind, used only to localise the title + note.
  static const String _kindCreditNote = 'credit_note';
  static const String _kindRefundProof = 'refund_proof';

  /// Builds + previews the "Creditnota" document for a cancelled / credited
  /// booking or operational leg row.
  static Future<void> previewCreditNotePdf({
    required BuildContext context,
    required _CompanyBookingOverviewItem item,
  }) async {
    final bytes = await _buildDocumentBytes(item: item, kind: _kindCreditNote);
    if (!context.mounted) return;
    if (bytes == null) {
      _showGenerationFailed(context);
      return;
    }
    debugPrint(
      '[COMPANY_BOOKINGS][CREDIT_NOTE_PDF][PREVIEW] '
      'leg=${_CompanyBookingOverviewItem.isRoundtripOperationalLegRow(item)} hasPdf=true',
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReceiptPdfPreviewPage(
          title: _tr(
            nl: 'Creditnota',
            en: 'Credit note',
            fr: 'Note de crédit',
            es: 'Nota de crédito',
          ),
          bytes: bytes,
        ),
      ),
    );
  }

  /// Builds + previews the "Terugbetalingsbewijs" document for a row that has
  /// reached a final refunded lifecycle state.
  static Future<void> previewRefundProofPdf({
    required BuildContext context,
    required _CompanyBookingOverviewItem item,
  }) async {
    final bytes = await _buildDocumentBytes(item: item, kind: _kindRefundProof);
    if (!context.mounted) return;
    if (bytes == null) {
      _showGenerationFailed(context);
      return;
    }
    debugPrint(
      '[COMPANY_BOOKINGS][REFUND_PROOF_PDF][PREVIEW] '
      'leg=${_CompanyBookingOverviewItem.isRoundtripOperationalLegRow(item)} hasPdf=true',
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReceiptPdfPreviewPage(
          title: _tr(
            nl: 'Terugbetalingsbewijs',
            en: 'Refund proof',
            fr: 'Preuve de remboursement',
            es: 'Comprobante de reembolso',
          ),
          bytes: bytes,
        ),
      ),
    );
  }

  static void _showGenerationFailed(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            nl: 'PDF-document kon niet worden aangemaakt.',
            en: 'Could not generate the PDF document.',
            fr: 'Impossible de générer le document PDF.',
            es: 'No se pudo generar el documento PDF.',
          ),
        ),
      ),
    );
  }

  static Future<Uint8List?> _buildDocumentBytes({
    required _CompanyBookingOverviewItem item,
    required String kind,
  }) async {
    try {
      final seller = await _ReceiptPdfActionRunner._buildSellerProfile();
      final logoBytes = await _ReceiptPdfActionRunner._loadReceiptLogoBytes(
        seller['logoPath'],
      );
      final doc = pw.Document();
      final baseFont = await PdfGoogleFonts.notoSansRegular();
      final boldFont = await PdfGoogleFonts.notoSansBold();

      final isCreditNote = kind == _kindCreditNote;
      final isLegRow = _CompanyBookingOverviewItem.isRoundtripOperationalLegRow(
        item,
      );

      final title = isCreditNote
          ? _tr(
              nl: 'Creditnota',
              en: 'Credit note',
              fr: 'Note de crédit',
              es: 'Nota de crédito',
            )
          : _tr(
              nl: 'Terugbetalingsbewijs',
              en: 'Refund proof',
              fr: 'Preuve de remboursement',
              es: 'Comprobante de reembolso',
            );

      final footerText = _localizedFooterText();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
          build: (pw.Context pdfContext) => <pw.Widget>[
            _headerBlock(
              seller: seller,
              logoBytes: logoBytes,
              boldFont: boldFont,
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 12),
            ..._documentInfoRows(
              item: item,
              isCreditNote: isCreditNote,
              isLegRow: isLegRow,
            ),
            pw.SizedBox(height: 18),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                _documentNote(isCreditNote: isCreditNote, isLegRow: isLegRow),
                style: const pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.grey800,
                ),
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              footerText,
              style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
            ),
          ],
        ),
      );

      return await doc.save();
    } catch (err) {
      debugPrint('[COMPANY_BOOKINGS][CREDIT_REFUND_PDF][ERROR] $err');
      return null;
    }
  }

  static pw.Widget _headerBlock({
    required Map<String, String> seller,
    required Uint8List? logoBytes,
    required pw.Font boldFont,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: <pw.Widget>[
        if (logoBytes != null)
          pw.Container(
            width: 82,
            height: 82,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
          ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Text(
                (seller['companyName'] ?? '').trim().isNotEmpty
                    ? seller['companyName']!.trim()
                    : kCompanyName,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  font: boldFont,
                ),
                textAlign: pw.TextAlign.right,
              ),
              if ((seller['legalName'] ?? '').trim().isNotEmpty &&
                  seller['legalName'] != seller['companyName'])
                pw.Text(seller['legalName']!, textAlign: pw.TextAlign.right),
              if ((seller['address'] ?? '').trim().isNotEmpty)
                pw.Text(seller['address']!, textAlign: pw.TextAlign.right),
              if ((seller['vatNumber'] ?? '').trim().isNotEmpty)
                pw.Text(
                  '${_tr(nl: 'BTW', en: 'VAT', fr: 'TVA', es: 'IVA')}: ${seller['vatNumber']!}',
                  textAlign: pw.TextAlign.right,
                ),
              if ((seller['phone'] ?? '').trim().isNotEmpty)
                pw.Text(seller['phone']!, textAlign: pw.TextAlign.right),
              if ((seller['email'] ?? '').trim().isNotEmpty)
                pw.Text(seller['email']!, textAlign: pw.TextAlign.right),
            ],
          ),
        ),
      ],
    );
  }

  static List<pw.Widget> _documentInfoRows({
    required _CompanyBookingOverviewItem item,
    required bool isCreditNote,
    required bool isLegRow,
  }) {
    final rows = <pw.Widget>[
      _pdfInfoRow(
        _tr(
          nl: 'Documentdatum',
          en: 'Document date',
          fr: 'Date du document',
          es: 'Fecha del documento',
        ),
        _formatNowDate(),
      ),
      _pdfInfoRow(
        _tr(
          nl: 'Boekingsreferentie',
          en: 'Booking reference',
          fr: 'Référence',
          es: 'Referencia',
        ),
        _referenceText(item),
      ),
    ];

    if (isLegRow) {
      rows.add(
        _pdfInfoRow(
          _tr(nl: 'Rit-deel', en: 'Ride leg', fr: 'Segment', es: 'Tramo'),
          _legLabel(item.legType),
        ),
      );
      final parentRef = item.parentReferenceText.trim().isNotEmpty
          ? item.parentReferenceText.trim()
          : item.parentBookingId.trim();
      if (parentRef.isNotEmpty) {
        rows.add(
          _pdfInfoRow(
            _tr(
              nl: 'Bovenliggende boeking',
              en: 'Parent booking',
              fr: 'Réservation parente',
              es: 'Reserva principal',
            ),
            parentRef,
          ),
        );
      }
    }

    if (item.customerName.trim().isNotEmpty &&
        item.customerName.trim() != '—') {
      rows.add(
        _pdfInfoRow(
          _tr(nl: 'Klant', en: 'Customer', fr: 'Client', es: 'Cliente'),
          item.customerName.trim(),
        ),
      );
    }

    // Leg-first amount: a roundtrip leg row uses its own [amount]; only a
    // true parent/full booking row may fall back to [parentAmount].
    final originalAmount = isLegRow
        ? item.amount
        : (item.parentAmount ?? item.amount);

    if (isCreditNote) {
      rows.add(
        _pdfInfoRow(
          _tr(
            nl: 'Oorspronkelijk bedrag',
            en: 'Original amount',
            fr: 'Montant initial',
            es: 'Importe original',
          ),
          _money(originalAmount, item.currency),
        ),
      );
      if (item.creditedAmountCents != null && item.creditedAmountCents! > 0) {
        rows.add(
          _pdfInfoRow(
            _tr(
              nl: 'Gecrediteerd bedrag',
              en: 'Credited amount',
              fr: 'Montant crédité',
              es: 'Importe acreditado',
            ),
            _money(item.creditedAmountCents! / 100, item.currency),
          ),
        );
      }
      if (item.creditDecision.trim().isNotEmpty) {
        rows.add(
          _pdfInfoRow(
            _tr(
              nl: 'Creditbeslissing',
              en: 'Credit decision',
              fr: 'Décision de crédit',
              es: 'Decisión de crédito',
            ),
            _creditDecisionLabel(item.creditDecision),
          ),
        );
      }
    } else {
      // Refund proof: prefer the explicit refunded amount; fall back to the
      // leg-first original amount when the cents field is absent.
      final refundedAmount =
          (item.refundedAmountCents != null && item.refundedAmountCents! > 0)
          ? item.refundedAmountCents! / 100
          : originalAmount;
      rows.add(
        _pdfInfoRow(
          _tr(
            nl: 'Terugbetaald bedrag',
            en: 'Refunded amount',
            fr: 'Montant remboursé',
            es: 'Importe reembolsado',
          ),
          _money(refundedAmount, item.currency),
        ),
      );
      rows.add(
        _pdfInfoRow(
          _tr(
            nl: 'Terugbetalingsstatus',
            en: 'Refund status',
            fr: 'Statut du remboursement',
            es: 'Estado del reembolso',
          ),
          _tr(
            nl: 'Terugbetaald',
            en: 'Refunded',
            fr: 'Remboursé',
            es: 'Reembolsado',
          ),
        ),
      );
      if (item.refundedAt.trim().isNotEmpty) {
        rows.add(
          _pdfInfoRow(
            _tr(
              nl: 'Terugbetaald op',
              en: 'Refunded on',
              fr: 'Remboursé le',
              es: 'Reembolsado el',
            ),
            _ReceiptPdfActionRunner._formatDate(item.refundedAt),
          ),
        );
      }
      if (item.refundProvider.trim().isNotEmpty) {
        rows.add(
          _pdfInfoRow(
            _tr(
              nl: 'Terugbetaalmethode',
              en: 'Refund provider',
              fr: 'Prestataire',
              es: 'Proveedor',
            ),
            item.refundProvider.trim(),
          ),
        );
      }
      if (item.mollieRefundId.trim().isNotEmpty) {
        rows.add(
          _pdfInfoRow(
            _tr(
              nl: 'Terugbetaal-ID',
              en: 'Refund id',
              fr: 'ID remboursement',
              es: 'ID reembolso',
            ),
            item.mollieRefundId.trim(),
          ),
        );
      }
    }

    return rows;
  }

  static pw.Widget _pdfInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Container(
            width: 178,
            padding: const pw.EdgeInsets.only(right: 16),
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
              softWrap: true,
            ),
          ),
          pw.Expanded(
            child: pw.Text(value, textAlign: pw.TextAlign.left, softWrap: true),
          ),
        ],
      ),
    );
  }

  static String _documentNote({
    required bool isCreditNote,
    required bool isLegRow,
  }) {
    if (isCreditNote) {
      return isLegRow
          ? _tr(
              nl: 'Dit document corrigeert het betreffende rit-deel na annulatie of creditbeslissing. Het is geen ritbon en bewijst geen uitgevoerde rit.',
              en: 'This document corrects the relevant ride leg after cancellation or a credit decision. It is not a ride receipt and does not prove an executed ride.',
              fr: 'Ce document corrige le segment concerné après annulation ou décision de crédit. Ce n’est pas un reçu de course.',
              es: 'Este documento corrige el tramo correspondiente tras la cancelación o decisión de crédito. No es un recibo de viaje.',
            )
          : _tr(
              nl: 'Dit document corrigeert de boeking na annulatie of creditbeslissing. Het is geen ritbon en bewijst geen uitgevoerde rit.',
              en: 'This document corrects the booking after cancellation or a credit decision. It is not a ride receipt and does not prove an executed ride.',
              fr: 'Ce document corrige la réservation après annulation ou décision de crédit. Ce n’est pas un reçu de course.',
              es: 'Este documento corrige la reserva tras la cancelación o decisión de crédito. No es un recibo de viaje.',
            );
    }
    return _tr(
      nl: 'Dit document bewijst de registratie van de terugbetaling binnen Fluxidi. Het is geen ritbon en bewijst geen uitgevoerde rit.',
      en: 'This document proves the registration of the refund within Fluxidi. It is not a ride receipt and does not prove an executed ride.',
      fr: 'Ce document atteste l’enregistrement du remboursement dans Fluxidi. Ce n’est pas un reçu de course.',
      es: 'Este documento acredita el registro del reembolso dentro de Fluxidi. No es un recibo de viaje.',
    );
  }

  static String _localizedFooterText() {
    return _tr(
      nl: 'Bedankt voor uw vertrouwen in Fluxidi.',
      en: 'Thank you for your trust in Fluxidi.',
      fr: 'Merci pour votre confiance en Fluxidi.',
      es: 'Gracias por confiar en Fluxidi.',
    );
  }

  static String _referenceText(_CompanyBookingOverviewItem item) {
    final ref = item.referenceText.trim();
    if (ref.isNotEmpty) return ref;
    final bookingId = item.bookingId.trim();
    return bookingId.isEmpty ? '—' : bookingId;
  }

  static String _legLabel(String legType) {
    final t = legType.trim().toLowerCase();
    if (t == 'return') {
      return _tr(
        nl: 'Terugrit',
        en: 'Return leg',
        fr: 'Trajet retour',
        es: 'Tramo de vuelta',
      );
    }
    if (t == 'outbound') {
      return _tr(
        nl: 'Heenrit',
        en: 'Outbound leg',
        fr: 'Trajet aller',
        es: 'Tramo de ida',
      );
    }
    return _tr(nl: 'Rit', en: 'Ride leg', fr: 'Trajet', es: 'Tramo');
  }

  static String _creditDecisionLabel(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'FULL_CREDIT':
        return _tr(
          nl: 'Volledige credit',
          en: 'Full credit',
          fr: 'Crédit complet',
          es: 'Crédito total',
        );
      case 'PARTIAL_CREDIT':
        return _tr(
          nl: 'Gedeeltelijke credit',
          en: 'Partial credit',
          fr: 'Crédit partiel',
          es: 'Crédito parcial',
        );
      case 'NO_REFUND':
        return _tr(
          nl: 'Geen terugbetaling',
          en: 'No refund',
          fr: 'Pas de remboursement',
          es: 'Sin reembolso',
        );
      case 'HANDLED_MANUALLY':
        return _tr(
          nl: 'Handmatig afgehandeld',
          en: 'Handled manually',
          fr: 'Traité manuellement',
          es: 'Gestionado manualmente',
        );
      default:
        return raw.trim().isEmpty ? '—' : raw.replaceAll('_', ' ');
    }
  }

  static String _money(num? amount, String rawCurrency) {
    if (amount == null) return '—';
    final currency = rawCurrency.trim().toUpperCase();
    final symbol = currency.isEmpty || currency == 'EUR' ? '€' : '$currency ';
    final value = amount.toStringAsFixed(2).replaceAll('.', ',');
    return '$symbol$value';
  }

  static String _formatNowDate() {
    final dt = DateTime.now().toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}-${two(dt.month)}-${dt.year}';
  }
}
