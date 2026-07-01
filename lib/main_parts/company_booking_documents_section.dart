part of '../main.dart';

/// 2G-S-B2: lightweight per-booking refresh signal bus.
///
/// The credit-note issue action (`_CompanyBookingCreditRefundPdfActionRunner`)
/// calls [requestRefresh] after a successful issue/replay so an already-built
/// [_BookingDocumentsSection] for that booking reloads and shows the new
/// official document — without rebuilding the whole bookings list. Sections key
/// on the same canonical booking id used by the 2G-P lookup, so leg rows and
/// their parent share one signal.
class _BookingDocumentsRefreshBus {
  _BookingDocumentsRefreshBus._();

  static final _BookingDocumentsRefreshBus instance =
      _BookingDocumentsRefreshBus._();

  final Map<String, ValueNotifier<int>> _signals =
      <String, ValueNotifier<int>>{};

  /// Get-or-create the shared signal for [bookingId]. Sections call this in
  /// initState so the signal exists before any [requestRefresh].
  ValueNotifier<int> notifierFor(String bookingId) =>
      _signals.putIfAbsent(bookingId.trim(), () => ValueNotifier<int>(0));

  /// Bump the signal for [bookingId] if a section is listening. No-op when no
  /// section for that booking is currently built.
  void requestRefresh(String bookingId) {
    final signal = _signals[bookingId.trim()];
    if (signal != null) signal.value = signal.value + 1;
  }
}

/// B10c: read-only, envelope-only projection of the `billit_export` object that
/// the booking documents backend (`GET /company/bookings/:bookingId/documents`)
/// already returns per issued document.
///
/// Surfaces ONLY safe lifecycle/link fields for display. It never parses or
/// exposes the raw Billit response, customer data, addresses, order lines, VAT
/// details, files, tokens or secrets. This model carries no actions and triggers
/// no network calls — it is purely a display projection of already-fetched data.
class _BillitExportMetadata {
  final String status;
  final String orderId;
  final String orderNumber;
  final bool sent;
  final bool peppolSent;
  final String billitStatus;
  final bool? billitIsSent;
  final bool? billitPaid;
  final String transportType;
  final String sentAt;
  final String peppolSentAt;
  final String statusCheckedAt;

  const _BillitExportMetadata({
    required this.status,
    required this.orderId,
    required this.orderNumber,
    required this.sent,
    required this.peppolSent,
    required this.billitStatus,
    required this.billitIsSent,
    required this.billitPaid,
    required this.transportType,
    required this.sentAt,
    required this.peppolSentAt,
    required this.statusCheckedAt,
  });

  factory _BillitExportMetadata.fromJson(Map<String, dynamic> json) {
    String readAny(List<String> keys) {
      for (final key in keys) {
        final text = (json[key] ?? '').toString().trim();
        if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
      }
      return '';
    }

    bool? readBoolOrNull(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value is bool) return value;
      }
      return null;
    }

    return _BillitExportMetadata(
      status: readAny(const ['status']),
      orderId: readAny(const ['order_id', 'orderId']),
      orderNumber: readAny(const ['order_number', 'orderNumber']),
      sent: json['sent'] == true,
      peppolSent: json['peppol_sent'] == true || json['peppolSent'] == true,
      billitStatus: readAny(const ['billit_status', 'billitStatus']),
      billitIsSent: readBoolOrNull(const ['billit_is_sent', 'billitIsSent']),
      billitPaid: readBoolOrNull(const ['billit_paid', 'billitPaid']),
      transportType: readAny(const ['transport_type', 'transportType']),
      sentAt: readAny(const ['sent_at', 'sentAt']),
      peppolSentAt: readAny(const ['peppol_sent_at', 'peppolSentAt']),
      statusCheckedAt: readAny(const ['status_checked_at', 'statusCheckedAt']),
    );
  }

  /// True when there is at least one displayable link/status field. Documents
  /// without a meaningful Billit export report false so they render exactly as
  /// before this patch.
  bool get hasDisplayableStatus =>
      orderId.isNotEmpty ||
      orderNumber.isNotEmpty ||
      status.isNotEmpty ||
      billitStatus.isNotEmpty ||
      sent ||
      peppolSent;

  /// The invoice has been handed to Peppol. Used to pick the "Verzonden via
  /// Peppol" primary badge and to hide the "sending is manual" hint.
  bool get isSentViaPeppol =>
      peppolSent || (transportType.toLowerCase() == 'peppol' && sent);
}

/// 2G-Q: read-only typed model for a single issued Document Core record as
/// returned by `GET /company/bookings/:bookingId/documents` (B10d-A route,
/// mirroring the 2G-P admin documents shape).
///
/// Tolerant of snake_case and camelCase keys, mirroring the existing
/// `DriverDocument.fromJson` convention. Contains only the safe metadata the
/// backend exposes — never buyer/seller PII.
class _BookingDocumentMetadata {
  final String documentId;
  final String documentType;
  final String documentNumber;
  final String proofReference;
  final String lifecycleState;
  final String documentStatus;
  final String issueTimestamp;
  final String currency;
  final String contentHash;
  final String sourceBookingId;
  final String sourceLegId;
  final String sourceLegType;
  // B10c: safe read-only Billit export projection (null when the document has no
  // meaningful Billit export). Existing documents without it render unchanged.
  final _BillitExportMetadata? billitExport;

  const _BookingDocumentMetadata({
    required this.documentId,
    required this.documentType,
    required this.documentNumber,
    required this.proofReference,
    required this.lifecycleState,
    required this.documentStatus,
    required this.issueTimestamp,
    required this.currency,
    required this.contentHash,
    required this.sourceBookingId,
    required this.sourceLegId,
    required this.sourceLegType,
    this.billitExport,
  });

  factory _BookingDocumentMetadata.fromJson(Map<String, dynamic> json) {
    String readAny(List<String> keys) {
      for (final key in keys) {
        final text = (json[key] ?? '').toString().trim();
        if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
      }
      return '';
    }

    // B10c: parse the already-returned billit_export envelope if present. Only
    // kept when it carries at least one displayable link/status field, so
    // documents without a Billit export behave exactly as before.
    _BillitExportMetadata? billitExport;
    final rawExport = json['billit_export'] ?? json['billitExport'];
    if (rawExport is Map) {
      final parsedExport = _BillitExportMetadata.fromJson(
        rawExport.map((k, v) => MapEntry(k.toString(), v)),
      );
      if (parsedExport.hasDisplayableStatus) billitExport = parsedExport;
    }

    return _BookingDocumentMetadata(
      documentId: readAny(const ['document_id', 'documentId']),
      documentType: readAny(const ['document_type', 'documentType']),
      documentNumber: readAny(const ['document_number', 'documentNumber']),
      proofReference: readAny(const ['proof_reference', 'proofReference']),
      lifecycleState: readAny(const ['lifecycle_state', 'lifecycleState']),
      documentStatus: readAny(const ['document_status', 'documentStatus']),
      issueTimestamp: readAny(const ['issue_timestamp', 'issueTimestamp']),
      currency: readAny(const ['currency']),
      contentHash: readAny(const ['content_hash', 'contentHash']),
      sourceBookingId: readAny(const ['source_booking_id', 'sourceBookingId']),
      sourceLegId: readAny(const ['source_leg_id', 'sourceLegId']),
      sourceLegType: readAny(const ['source_leg_type', 'sourceLegType']),
      billitExport: billitExport,
    );
  }

  /// Best human-facing reference for the row title (credit notes carry a
  /// document number, refund proofs a proof reference).
  String get displayReference {
    if (documentNumber.isNotEmpty) return documentNumber;
    if (proofReference.isNotEmpty) return proofReference;
    if (documentId.isNotEmpty) {
      return documentId.length > 8 ? documentId.substring(0, 8) : documentId;
    }
    return '—';
  }
}

/// Compact, read-only "Documenten" section shown on a company/admin booking
/// card. Lazily fetches issued documents for the booking the first time the
/// section is expanded so a long bookings list never fires a request per row.
///
/// Visibility only (2G-Q): no download/open/send actions. Failures are
/// non-blocking and never break the booking detail card.
class _BookingDocumentsSection extends StatefulWidget {
  final String bookingId;
  final _CompanyBookingsThemeTokens tokens;

  const _BookingDocumentsSection({
    super.key,
    required this.bookingId,
    required this.tokens,
  });

  @override
  State<_BookingDocumentsSection> createState() =>
      _BookingDocumentsSectionState();
}

class _BookingDocumentsSectionState extends State<_BookingDocumentsSection> {
  bool _expanded = false;
  bool _loading = false;
  bool _loaded = false;
  bool _error = false;
  List<_BookingDocumentMetadata> _documents =
      const <_BookingDocumentMetadata>[];
  late ValueNotifier<int> _refreshSignal;
  // Stable identity of the booking whose documents are currently held in state.
  // Used to (a) reset state when a reused State element is handed a different
  // booking (tab/list-item reuse) and (b) discard late async responses whose
  // scope no longer matches. Equal to the canonical booking id used by the
  // documents fetch route (tenant/company come from the global active scope).
  late String _activeScopeKey;

  /// Stable scope key for the booking this section currently renders. The
  /// fetch route is `/company/bookings/<bookingId>/documents` scoped by the
  /// active tenant/company session, so the per-widget identity is the
  /// canonical booking id.
  String get _documentsScopeKey => widget.bookingId.trim();

  @override
  void initState() {
    super.initState();
    _activeScopeKey = _documentsScopeKey;
    _refreshSignal = _BookingDocumentsRefreshBus.instance.notifierFor(
      widget.bookingId,
    );
    _refreshSignal.addListener(_handleExternalRefresh);
  }

  @override
  void didUpdateWidget(covariant _BookingDocumentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextScopeKey = _documentsScopeKey;
    if (nextScopeKey == _activeScopeKey) return;

    // The booking identity changed under a reused State element (switching
    // tabs/filters recycles this widget position). Re-wire the per-booking
    // refresh signal to the new booking and drop the previous booking's
    // documents so nothing leaks across the swap. Any in-flight request keyed
    // to the old scope is discarded on return by the scope-key guard.
    _refreshSignal.removeListener(_handleExternalRefresh);
    _refreshSignal = _BookingDocumentsRefreshBus.instance.notifierFor(
      widget.bookingId,
    );
    _refreshSignal.addListener(_handleExternalRefresh);

    final wasExpanded = _expanded;
    setState(() {
      _activeScopeKey = nextScopeKey;
      _documents = const <_BookingDocumentMetadata>[];
      _loaded = false;
      _loading = false;
      _error = false;
      _expanded = wasExpanded;
    });
    if (wasExpanded) {
      _loadDocuments();
    }
  }

  @override
  void dispose() {
    _refreshSignal.removeListener(_handleExternalRefresh);
    super.dispose();
  }

  /// 2G-S-B2: an external producer (credit-note issue) asked us to reload.
  /// Expand and force a fresh fetch so the newly issued document appears.
  void _handleExternalRefresh() {
    if (!mounted) return;
    setState(() {
      _expanded = true;
      _loaded = false;
      _error = false;
    });
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    if (_loading) return;
    // Capture the scope this request belongs to. If the section is handed a
    // different booking before the response returns, the guards below discard
    // the stale response instead of showing another booking's documents.
    final requestScopeKey = _documentsScopeKey;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      // 2G-S-B2 hardening: temporary safe diagnostic. Masked booking id only;
      // no tokens, no PII, no response body contents.
      debugPrint(
        '[COMPANY_BOOKINGS][DOCUMENTS][FETCH] '
        'booking=${_bookingRefMaskForCreditIssueLog(widget.bookingId)}',
      );
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/company/bookings/${Uri.encodeComponent(widget.bookingId)}/documents',
      );
      final auth = await resolveCompanyOwnerAuthHeaders();
      final res = await http
          .get(uri, headers: auth.headers)
          .timeout(const Duration(seconds: 12));
      if (!mounted || requestScopeKey != _activeScopeKey) return;
      if (res.statusCode != 200) {
        setState(() {
          _error = true;
          _loading = false;
          _loaded = true;
        });
        return;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['ok'] != true) {
        setState(() {
          _error = true;
          _loading = false;
          _loaded = true;
        });
        return;
      }
      final rawDocs = decoded['documents'];
      final parsed = <_BookingDocumentMetadata>[];
      if (rawDocs is List) {
        for (final entry in rawDocs) {
          if (entry is Map) {
            parsed.add(
              _BookingDocumentMetadata.fromJson(
                entry.map((k, v) => MapEntry(k.toString(), v)),
              ),
            );
          }
        }
      }
      if (!mounted || requestScopeKey != _activeScopeKey) return;
      setState(() {
        _documents = parsed;
        _loaded = true;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted || requestScopeKey != _activeScopeKey) return;
      setState(() {
        _error = true;
        _loading = false;
        _loaded = true;
      });
    }
  }

  void _toggle() {
    final next = !_expanded;
    setState(() => _expanded = next);
    if (next && !_loaded && !_loading) {
      _loadDocuments();
    }
  }

  String _localizedDocumentType(String type) {
    switch (type.toLowerCase()) {
      case 'invoice':
        return _tr(nl: 'Factuur', en: 'Invoice', fr: 'Facture', es: 'Factura');
      case 'credit_note':
        return _tr(
          nl: 'Creditnota',
          en: 'Credit note',
          fr: 'Note de crédit',
          es: 'Nota de crédito',
        );
      case 'refund_proof':
        return _tr(
          nl: 'Terugbetalingsbewijs',
          en: 'Refund proof',
          fr: 'Preuve de remboursement',
          es: 'Justificante de reembolso',
        );
      default:
        return type.isEmpty
            ? _tr(
                nl: 'Document',
                en: 'Document',
                fr: 'Document',
                es: 'Documento',
              )
            : type;
    }
  }

  /// Customer-facing leg label. Maps the technical `outbound`/`return` leg type
  /// to human wording, falls back to a neutral "Ride" word for any other/unknown
  /// leg, and never surfaces the raw technical leg id. Returns '' when there is
  /// no leg information at all (leg line is then hidden).
  String _localizedLegLabel(_BookingDocumentMetadata doc) {
    final type = doc.sourceLegType.trim().toLowerCase();
    if (type == 'outbound') {
      return _tr(
        nl: 'Rit: heenrit',
        en: 'Ride: outbound',
        fr: 'Trajet : aller',
        es: 'Trayecto: ida',
      );
    }
    if (type == 'return') {
      return _tr(
        nl: 'Rit: terugrit',
        en: 'Ride: return',
        fr: 'Trajet : retour',
        es: 'Trayecto: vuelta',
      );
    }
    if (doc.sourceLegType.trim().isNotEmpty ||
        doc.sourceLegId.trim().isNotEmpty) {
      return _tr(nl: 'Rit', en: 'Ride', fr: 'Trajet', es: 'Trayecto');
    }
    return '';
  }

  String _localizedLifecycle(_BookingDocumentMetadata doc) {
    final state =
        (doc.lifecycleState.isNotEmpty
                ? doc.lifecycleState
                : doc.documentStatus)
            .toLowerCase();
    switch (state) {
      case 'issued':
        return _tr(nl: 'Uitgegeven', en: 'Issued', fr: 'Émis', es: 'Emitido');
      case 'draft':
      case 'draft_preview':
        return _tr(nl: 'Concept', en: 'Draft', fr: 'Brouillon', es: 'Borrador');
      case 'voided':
      case 'cancelled':
      case 'canceled':
        return _tr(
          nl: 'Geannuleerd',
          en: 'Voided',
          fr: 'Annulé',
          es: 'Anulado',
        );
      default:
        return state.isEmpty ? '—' : state;
    }
  }

  String _formatIssueDate(String iso) {
    if (iso.isEmpty) return '';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  String _shortHash(String hash) {
    if (hash.isEmpty) return '';
    return hash.length > 8 ? hash.substring(0, 8) : hash;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.folder_open_outlined,
                  size: 16,
                  color: tokens.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  _tr(
                    nl: 'Documenten',
                    en: 'Documents',
                    fr: 'Documents',
                    es: 'Documentos',
                  ),
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 12.1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_loaded && !_error) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: tokens.accent.withOpacity(0.4)),
                    ),
                    child: Text(
                      '${_documents.length}',
                      style: TextStyle(
                        color: tokens.accent,
                        fontSize: 10.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: tokens.textTertiary,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) _buildExpandedBody(tokens),
      ],
    );
  }

  Widget _buildExpandedBody(_CompanyBookingsThemeTokens tokens) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _tr(
                nl: 'Documenten laden…',
                en: 'Loading documents…',
                fr: 'Chargement des documents…',
                es: 'Cargando documentos…',
              ),
              style: TextStyle(color: tokens.textTertiary, fontSize: 11.4),
            ),
          ],
        ),
      );
    }
    if (_error) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _tr(
                  nl: 'Documenten konden niet worden geladen.',
                  en: 'Documents could not be loaded.',
                  fr: 'Impossible de charger les documents.',
                  es: 'No se pudieron cargar los documentos.',
                ),
                style: TextStyle(color: tokens.textTertiary, fontSize: 11.4),
              ),
            ),
            TextButton(
              onPressed: _loading ? null : _loadDocuments,
              style: TextButton.styleFrom(
                foregroundColor: tokens.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _tr(
                  nl: 'Opnieuw',
                  en: 'Retry',
                  fr: 'Réessayer',
                  es: 'Reintentar',
                ),
                style: const TextStyle(
                  fontSize: 11.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_documents.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          _tr(
            nl: 'Nog geen documenten voor deze boeking.',
            en: 'No documents for this booking yet.',
            fr: 'Aucun document pour cette réservation.',
            es: 'Aún no hay documentos para esta reserva.',
          ),
          style: TextStyle(color: tokens.textTertiary, fontSize: 11.4),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final doc in _documents) _buildDocumentRow(tokens, doc)],
    );
  }

  Widget _buildDocumentRow(
    _CompanyBookingsThemeTokens tokens,
    _BookingDocumentMetadata doc,
  ) {
    final typeLabel = _localizedDocumentType(doc.documentType);
    final lifecycleLabel = _localizedLifecycle(doc);
    final issueDate = _formatIssueDate(doc.issueTimestamp);
    final shortHash = _shortHash(doc.contentHash);

    final metaParts = <String>[
      typeLabel,
      if (doc.currency.isNotEmpty) doc.currency.toUpperCase(),
      if (issueDate.isNotEmpty) issueDate,
    ];

    final legLabel = _localizedLegLabel(doc);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.chipUnselectedBg.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  doc.displayReference,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 12.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.paidBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tokens.paidBorder),
                ),
                child: Text(
                  lifecycleLabel,
                  style: TextStyle(
                    color: tokens.paidText,
                    fontSize: 10.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            metaParts.join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: tokens.textSecondary, fontSize: 11.0),
          ),
          if (legLabel.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              legLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.textTertiary, fontSize: 10.6),
            ),
          ],
          if (shortHash.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '#$shortHash',
              style: TextStyle(
                color: tokens.textTertiary.withOpacity(0.8),
                fontSize: 9.8,
              ),
            ),
          ],
          if (doc.billitExport != null)
            _buildBillitStatusBlock(tokens, doc.billitExport!),
        ],
      ),
    );
  }

  /// B10c: read-only Billit/Peppol status block rendered beneath a document's
  /// metadata. Pure display: no onTap, no button, no network call, no send.
  /// Everything is derived from the already-fetched `billit_export` envelope.
  Widget _buildBillitStatusBlock(
    _CompanyBookingsThemeTokens tokens,
    _BillitExportMetadata export,
  ) {
    final billitStatus = export.billitStatus.toLowerCase();
    final status = export.status.toLowerCase();

    String? primaryLabel;
    String? secondaryLabel;

    if (export.isSentViaPeppol) {
      primaryLabel = _tr(
        nl: 'Verzonden via Peppol',
        en: 'Sent via Peppol',
        fr: 'Envoyé via Peppol',
        es: 'Enviado por Peppol',
      );
      if (billitStatus == 'topay') {
        secondaryLabel = _tr(
          nl: 'Te betalen',
          en: 'To be paid',
          fr: 'À payer',
          es: 'Por pagar',
        );
      }
    } else if (billitStatus == 'tosend' || status == 'created') {
      primaryLabel = _tr(
        nl: 'Klaargezet in Billit',
        en: 'Prepared in Billit',
        fr: 'Préparé dans Billit',
        es: 'Preparado en Billit',
      );
      secondaryLabel = _tr(
        nl: 'Nog niet via Peppol verzonden',
        en: 'Not sent via Peppol yet',
        fr: 'Pas encore envoyé via Peppol',
        es: 'Aún no enviado por Peppol',
      );
    } else if (billitStatus == 'topay') {
      primaryLabel = _tr(
        nl: 'Billit-order aangemaakt',
        en: 'Billit order created',
        fr: 'Commande Billit créée',
        es: 'Pedido Billit creado',
      );
      secondaryLabel = _tr(
        nl: 'Te betalen',
        en: 'To be paid',
        fr: 'À payer',
        es: 'Por pagar',
      );
    } else if (export.orderId.isNotEmpty || export.orderNumber.isNotEmpty) {
      primaryLabel = _tr(
        nl: 'Billit-order aangemaakt',
        en: 'Billit order created',
        fr: 'Commande Billit créée',
        es: 'Pedido Billit creado',
      );
    }

    if (primaryLabel == null) return const SizedBox.shrink();

    String detailLine = '';
    if (export.orderNumber.isNotEmpty) {
      detailLine = 'Billit: ${export.orderNumber}';
    } else if (export.orderId.isNotEmpty) {
      detailLine = _tr(
        nl: 'Billit-order aangemaakt',
        en: 'Billit order created',
        fr: 'Commande Billit créée',
        es: 'Pedido Billit creado',
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _billitStatusChip(tokens, primaryLabel, primary: true),
              if (secondaryLabel != null)
                _billitStatusChip(tokens, secondaryLabel, primary: false),
            ],
          ),
          if (detailLine.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              detailLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.textTertiary, fontSize: 10.4),
            ),
          ],
          if (!export.peppolSent) ...[
            const SizedBox(height: 2),
            Text(
              _tr(
                nl: 'Peppol-verzending blijft handmatig',
                en: 'Peppol sending remains manual',
                fr: 'L’envoi Peppol reste manuel',
                es: 'El envío por Peppol sigue siendo manual',
              ),
              style: TextStyle(
                color: tokens.textTertiary.withOpacity(0.8),
                fontSize: 9.8,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Subtle, read-only status chip. Deliberately styled unlike a button (no
  /// elevation, no ripple, no icon) and distinct from the green lifecycle badge.
  Widget _billitStatusChip(
    _CompanyBookingsThemeTokens tokens,
    String label, {
    required bool primary,
  }) {
    final Color bg = primary
        ? tokens.accent.withOpacity(0.12)
        : tokens.textSecondary.withOpacity(0.10);
    final Color border = primary
        ? tokens.accent.withOpacity(0.4)
        : tokens.textSecondary.withOpacity(0.3);
    final Color fg = primary ? tokens.accent : tokens.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
