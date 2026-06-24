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

/// 2G-Q: read-only typed model for a single issued Document Core record as
/// returned by `GET /admin/bookings/:bookingId/documents` (2G-P backend).
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
  });

  factory _BookingDocumentMetadata.fromJson(Map<String, dynamic> json) {
    String readAny(List<String> keys) {
      for (final key in keys) {
        final text = (json[key] ?? '').toString().trim();
        if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
      }
      return '';
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
  late final ValueNotifier<int> _refreshSignal;

  @override
  void initState() {
    super.initState();
    _refreshSignal = _BookingDocumentsRefreshBus.instance.notifierFor(
      widget.bookingId,
    );
    _refreshSignal.addListener(_handleExternalRefresh);
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
        '/admin/bookings/${Uri.encodeComponent(widget.bookingId)}/documents',
      );
      final auth = await resolveCompanyOwnerAuthHeaders();
      final res = await http
          .get(uri, headers: auth.headers)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
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
      setState(() {
        _documents = parsed;
        _loaded = true;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted) return;
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
          es: 'Comprobante de reembolso',
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

    final legText = doc.sourceLegType.isNotEmpty
        ? doc.sourceLegType
        : (doc.sourceLegId.isNotEmpty ? doc.sourceLegId : '');

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
          if (legText.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '${_tr(nl: 'Rit', en: 'Leg', fr: 'Trajet', es: 'Trayecto')}: $legText',
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
        ],
      ),
    );
  }
}
