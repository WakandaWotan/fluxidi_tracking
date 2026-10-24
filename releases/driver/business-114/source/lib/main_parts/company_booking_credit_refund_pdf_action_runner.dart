part of '../main.dart';

/// 2G-S-B4: resolve the canonical (parent) booking id used by BOTH the
/// credit-note issue request and the Documents section GET. Must always be a
/// `booking:<id>` KV storage key, NEVER a public/display reference.
///
/// Storage-key sources only. The backend list projector emits both `booking_id`
/// and `parent_booking_id` as the parent record's actual KV storage key (e.g.
/// `2026-06-628854` for a PLN roundtrip leg row). The companion
/// `parent_booking_reference`, `linked_order_reference`, `planning_reference`,
/// `public_booking_reference` and `booking_reference` fields (surfaced via
/// `_CompanyBookingOverviewItem.parentReferenceText`) are DISPLAY-ONLY refs
/// allocated by the booking-reference sequence DO (e.g. `2026-06-000079`,
/// `PLN-2026-000293`). They are never `booking:<id>` keys and MUST NOT be
/// used as `canonical_booking_id` — sending them yields a backend 404
/// `source_booking_not_found`.
///
/// 2G-S-B2-hardening regression note: a previous tier preferred
/// `parentReferenceText` whenever it matched `YYYY-MM-NNNNNN`. That
/// surfaced the public sequence id and bypassed the real storage key.
/// Removed in 2G-S-B4.
String _resolveCompanyBookingDocumentsCanonicalId(
  _CompanyBookingOverviewItem item,
) {
  String stripLegSuffix(String value) {
    final colon = value.indexOf(':');
    return colon > 0 ? value.substring(0, colon) : value;
  }

  final ownId = item.bookingId.trim();
  final parentId = item.parentBookingId.trim();
  // 1. Explicit parent_booking_id from the backend, ONLY when genuinely
  //    different from the row's own bookingId (i.e. not the
  //    `_CompanyBookingOverviewItem.fromMap` fallback that copies
  //    `bookingId` into `parentBookingId`). Strip any defensive ":LEG"
  //    suffix in case a parent slot ever carries a leg id directly.
  if (parentId.isNotEmpty && parentId != ownId) {
    return stripLegSuffix(parentId);
  }
  // 2. Fallback: the row's own bookingId stripped of any ":LEG" suffix.
  //    For roundtrip operational-leg rows the backend projector already
  //    puts the parent's storage key into `booking_id`, so this is the
  //    correct parent canonical id (e.g. `2026-06-628854` for the PLN
  //    leg row). For parent/full booking rows the bookingId is itself
  //    the storage key.
  if (ownId.isEmpty) return '';
  return stripLegSuffix(ownId);
}

/// 2G-S-B2 diagnostics: short, PII-free booking-ref mask for `[REQ]`/`[FETCH]`
/// logs. Mirrors the existing `_safeBookingRefForDiag` style.
String _bookingRefMaskForCreditIssueLog(String value) {
  final text = value.trim();
  if (text.isEmpty) return '-';
  if (text.length <= 8) return text;
  return '${text.substring(0, 4)}…${text.substring(text.length - 2)}';
}

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
    final preflight = _creditNotePreflight(item);
    debugPrint(
      '[COMPANY_BOOKINGS][CREDIT_NOTE_PDF][PREFLIGHT] '
      'ref=${_referenceText(item)} ${preflight.diagnostic}',
    );
    if (preflight.isBlocked) {
      _showPreflightBlocked(context);
      return;
    }

    // 2G-S-B2: issue (or idempotently replay) an OFFICIAL Document Core credit
    // note before rendering, so the PDF carries the backend-authoritative FCN-*
    // number and the Documents section can show it. Never blocks the preview:
    // on any failure we fall back to the existing local (unnumbered) PDF.
    final canonicalBookingId = _canonicalBookingId(item);
    final issue = await _issueCompanyCreditNote(
      item: item,
      canonicalBookingId: canonicalBookingId,
    );
    if (!context.mounted) return;
    String? documentNumber;
    String? issueTimestampIso;
    if (issue != null && issue.ok) {
      documentNumber = issue.documentNumber;
      issueTimestampIso = issue.issueTimestamp;
      _BookingDocumentsRefreshBus.instance.requestRefresh(canonicalBookingId);
    } else if (issue != null) {
      _showIssueFallbackNotice(context);
    }

    final bytes = await _buildDocumentBytes(
      item: item,
      kind: _kindCreditNote,
      documentNumber: documentNumber,
      issueTimestampIso: issueTimestampIso,
    );
    if (!context.mounted) return;
    if (bytes == null) {
      _showGenerationFailed(context);
      return;
    }
    debugPrint(
      '[COMPANY_BOOKINGS][CREDIT_NOTE_PDF][PREVIEW] '
      'leg=${_CompanyBookingOverviewItem.isRoundtripOperationalLegRow(item)} '
      'hasPdf=true numbered=${(documentNumber ?? '').isNotEmpty}',
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
    final preflight = _refundProofPreflight(item);
    debugPrint(
      '[COMPANY_BOOKINGS][REFUND_PROOF_PDF][PREFLIGHT] '
      'ref=${_referenceText(item)} ${preflight.diagnostic}',
    );
    if (preflight.isBlocked) {
      _showPreflightBlocked(context);
      return;
    }
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

  /// Non-destructive Document Core preflight for the credit note. Builds a
  /// provider-neutral draft (no writes, no backend, no numbering) and validates
  /// it. Reuses the existing visibility gate as the "credit context valid"
  /// signal so business logic is not duplicated here.
  static DocumentPreflightResult _creditNotePreflight(
    _CompanyBookingOverviewItem item,
  ) {
    final draft = buildCompanyCreditNoteDraftFromOverviewItem(
      item,
      companyProfile: localBackendBusinessProfileNotifier.value,
    );
    return validateCreditNoteDraft(
      draft,
      creditContextValid:
          _CompanyBookingOverviewItem.canShowCreditNotePdfAction(item),
    );
  }

  /// Non-destructive Document Core preflight for the refund proof. Reuses the
  /// existing refund lifecycle helper for the "definitively refunded" signal.
  static DocumentPreflightResult _refundProofPreflight(
    _CompanyBookingOverviewItem item,
  ) {
    final draft = buildCompanyRefundProofDraftFromOverviewItem(
      item,
      companyProfile: localBackendBusinessProfileNotifier.value,
    );
    return validateRefundProofDraft(
      draft,
      refundLifecycleRefunded:
          _CompanyBookingOverviewItem.isRefundLifecycleRefunded(item),
    );
  }

  static void _showPreflightBlocked(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            nl: 'Documentgegevens zijn onvolledig; PDF kan niet veilig worden aangemaakt.',
            en: 'Document data is incomplete; the PDF cannot be generated safely.',
            fr: 'Données du document incomplètes ; le PDF ne peut pas être généré en toute sécurité.',
            es: 'Los datos del documento están incompletos; el PDF no se puede generar de forma segura.',
          ),
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

  static void _showIssueFallbackNotice(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            nl: 'Officiële creditnota kon nu niet worden uitgegeven; er wordt een lokaal voorbeeld getoond.',
            en: 'Official credit note could not be issued right now; showing a local preview.',
            fr: 'La note de crédit officielle n’a pas pu être émise ; aperçu local affiché.',
            es: 'No se pudo emitir la nota de crédito oficial ahora; se muestra una vista previa local.',
          ),
        ),
      ),
    );
  }

  /// Canonical (parent) booking id used for issuing/listing documents.
  /// Delegates to the shared resolver so this file and the booking-overview
  /// page agree on the same canonical id for both issue + Documents list.
  static String _canonicalBookingId(_CompanyBookingOverviewItem item) {
    return _resolveCompanyBookingDocumentsCanonicalId(item);
  }

  /// Deterministic FNV-1a hash (lowercase hex) used for `client_draft_hash`.
  /// Stable across taps on the same device (no randomized seed), contains no
  /// PII (inputs are ids/amounts only).
  static String _stableHashHex(String input) {
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// 2G-S-B2: issue (or idempotently replay) an official company-scoped credit
  /// note via POST /company/documents/credit-note/issue (2G-S-B1). Returns:
  ///   - null            when issuing should not be attempted (skip, no notice)
  ///   - outcome.ok=false on an attempted-but-failed request (caller notices)
  ///   - outcome.ok=true  with the backend-authoritative document_number.
  /// Never throws; never allocates a number client-side.
  static Future<_CreditNoteIssueOutcome?> _issueCompanyCreditNote({
    required _CompanyBookingOverviewItem item,
    required String canonicalBookingId,
  }) async {
    if (canonicalBookingId.isEmpty) return null;
    final creditedCents = item.creditedAmountCents ?? 0;
    if (creditedCents <= 0) return null;
    final currency = item.currency.trim().toUpperCase();
    if (currency.isEmpty) return null;

    final scope = _activeBookingScopeQuery();
    final tenantId = (scope['tenant_id'] ?? scope['tenantId'] ?? '').trim();
    final companyId = (scope['company_id'] ?? scope['companyId'] ?? '').trim();

    final isLeg = _CompanyBookingOverviewItem.isRoundtripOperationalLegRow(
      item,
    );
    final legId = isLeg ? item.legId.trim() : '';
    final legType = isLeg ? item.legType.trim() : '';
    final legOrParent = legId.isNotEmpty ? legId : canonicalBookingId;

    var idempotencyKey =
        'credit-note:v1:$tenantId:$companyId:$canonicalBookingId:$legOrParent:$creditedCents:$currency';
    if (idempotencyKey.length > 200) {
      idempotencyKey = idempotencyKey.substring(0, 200);
    }

    final clientDraftHash = _stableHashHex(
      'cn|v1|$canonicalBookingId|$legOrParent|$creditedCents|$currency|${item.creditDecision.trim()}',
    );

    final body = <String, dynamic>{
      'canonical_booking_id': canonicalBookingId,
      'currency': currency,
      'expected_totals': <String, dynamic>{
        'credited_amount_incl_vat': creditedCents / 100,
      },
      'idempotency_key': idempotencyKey,
      'created_by_role': 'company_owner',
      'client_draft_hash': clientDraftHash,
    };
    if (legId.isNotEmpty) body['source_leg_id'] = legId;
    if (legType.isNotEmpty) body['source_leg_type'] = legType;

    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/company/documents/credit-note/issue',
      );
      final auth = await resolveCompanyOwnerAuthHeaders();
      // 2G-S-B2 fix: explicitly stamp JSON Content-Type/Accept on top of the
      // auth headers so the request is always interpreted as JSON regardless
      // of how resolveCompanyOwnerAuthHeaders defaults change in future.
      final requestHeaders = <String, String>{
        ...auth.headers,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      // 2G-S-B2 hardening: temporary safe diagnostic. Logs only short masks
      // of the booking ids — no tokens, no PII, no body contents.
      debugPrint(
        '[COMPANY_BOOKINGS][CREDIT_NOTE_ISSUE][REQ] '
        'canonical=${_bookingRefMaskForCreditIssueLog(canonicalBookingId)} '
        'leg=${_bookingRefMaskForCreditIssueLog(legId)} '
        'parent=${_bookingRefMaskForCreditIssueLog(item.parentBookingId)} '
        'isLeg=$isLeg',
      );
      final res = await http
          .post(uri, headers: requestHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        final raw = res.body;
        final truncated = raw.length > 300 ? raw.substring(0, 300) : raw;
        debugPrint(
          '[COMPANY_BOOKINGS][CREDIT_NOTE_ISSUE][FAIL] '
          'status=${res.statusCode} body=$truncated',
        );
        return const _CreditNoteIssueOutcome(ok: false);
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['ok'] != true) {
        String reason = '';
        if (decoded is Map) {
          reason =
              (decoded['error'] ??
                      decoded['reason'] ??
                      decoded['message'] ??
                      '')
                  .toString()
                  .trim();
        }
        if (reason.length > 300) reason = reason.substring(0, 300);
        debugPrint(
          '[COMPANY_BOOKINGS][CREDIT_NOTE_ISSUE][FAIL] '
          'body_not_ok reason=${reason.isEmpty ? '-' : reason}',
        );
        return const _CreditNoteIssueOutcome(ok: false);
      }
      final documentNumber = (decoded['document_number'] ?? '')
          .toString()
          .trim();
      final issueTimestamp = (decoded['issue_timestamp'] ?? '')
          .toString()
          .trim();
      final replay = decoded['idempotent_replay'] == true;
      debugPrint(
        '[COMPANY_BOOKINGS][CREDIT_NOTE_ISSUE][OK] '
        'replay=$replay hasNumber=${documentNumber.isNotEmpty}',
      );
      return _CreditNoteIssueOutcome(
        ok: true,
        documentNumber: documentNumber,
        issueTimestamp: issueTimestamp,
        replay: replay,
      );
    } catch (err) {
      debugPrint('[COMPANY_BOOKINGS][CREDIT_NOTE_ISSUE][ERROR] $err');
      return const _CreditNoteIssueOutcome(ok: false);
    }
  }

  static Future<Uint8List?> _buildDocumentBytes({
    required _CompanyBookingOverviewItem item,
    required String kind,
    String? documentNumber,
    String? issueTimestampIso,
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
              documentNumber: documentNumber,
              issueTimestampIso: issueTimestampIso,
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
    String? documentNumber,
    String? issueTimestampIso,
  }) {
    final rows = <pw.Widget>[];
    // 2G-S-B2: stamp the backend-authoritative document number when the
    // official credit note was issued/replayed. Never synthesized client-side.
    if (isCreditNote && (documentNumber ?? '').trim().isNotEmpty) {
      rows.add(
        _pdfInfoRow(
          _tr(
            nl: 'Documentnummer',
            en: 'Document number',
            fr: 'Numéro de document',
            es: 'Número de documento',
          ),
          documentNumber!.trim(),
        ),
      );
    }
    rows.add(
      _pdfInfoRow(
        _tr(
          nl: 'Documentdatum',
          en: 'Document date',
          fr: 'Date du document',
          es: 'Fecha del documento',
        ),
        _formatIsoDateOrNow(issueTimestampIso),
      ),
    );
    rows.add(
      _pdfInfoRow(
        _tr(
          nl: 'Boekingsreferentie',
          en: 'Booking reference',
          fr: 'Référence',
          es: 'Referencia',
        ),
        _referenceText(item),
      ),
    );

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

  /// Format an ISO issue timestamp as a local dd-MM-yyyy document date; falls
  /// back to "now" when absent or unparseable.
  static String _formatIsoDateOrNow(String? iso) {
    final trimmed = (iso ?? '').trim();
    if (trimmed.isNotEmpty) {
      final parsed = DateTime.tryParse(trimmed);
      if (parsed != null) {
        final dt = parsed.toLocal();
        String two(int v) => v.toString().padLeft(2, '0');
        return '${two(dt.day)}-${two(dt.month)}-${dt.year}';
      }
    }
    return _formatNowDate();
  }
}

/// 2G-S-B2: outcome of a company-scoped credit-note issue/replay attempt.
class _CreditNoteIssueOutcome {
  final bool ok;
  final String documentNumber;
  final String issueTimestamp;
  final bool replay;

  const _CreditNoteIssueOutcome({
    required this.ok,
    this.documentNumber = '',
    this.issueTimestamp = '',
    this.replay = false,
  });
}
