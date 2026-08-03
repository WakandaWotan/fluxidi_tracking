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

/// B10e-B: sentinel so `_BillitExportMetadata.copyWith` can distinguish "leave
/// this nullable bool unchanged" from an explicit `null` override.
const Object _unset = Object();

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
  final String environment;
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
  final bool sendPending;
  final bool peppolSendPending;
  final bool reconcilePending;

  const _BillitExportMetadata({
    required this.status,
    required this.environment,
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
    this.sendPending = false,
    this.peppolSendPending = false,
    this.reconcilePending = false,
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
      environment: readAny(const ['environment']),
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
      sendPending: json['send_pending'] == true || json['sendPending'] == true,
      peppolSendPending:
          json['peppol_send_pending'] == true ||
          json['peppolSendPending'] == true,
      reconcilePending:
          json['reconcile_pending'] == true || json['reconcilePending'] == true,
    );
  }

  /// B10e-B: produce an updated copy after a read-only company Billit status
  /// refresh (`GET /company/documents/:documentId/billit-order/status/sandbox`).
  /// Only the safe live-status fields are overridable; link-identity fields the
  /// model does not carry (provider, party_id, idempotency_key, created_at,
  /// updated_at, source) are untouched by definition, and `environment` +
  /// `transportType` + the `*_at` link fields are preserved unless explicitly
  /// provided. Never stores a raw Billit response.
  _BillitExportMetadata copyWith({
    String? status,
    String? orderId,
    String? orderNumber,
    bool? sent,
    bool? peppolSent,
    String? billitStatus,
    Object? billitIsSent = _unset,
    Object? billitPaid = _unset,
    String? statusCheckedAt,
    bool? sendPending,
    bool? peppolSendPending,
    bool? reconcilePending,
  }) {
    return _BillitExportMetadata(
      status: status ?? this.status,
      environment: environment,
      orderId: orderId ?? this.orderId,
      orderNumber: orderNumber ?? this.orderNumber,
      sent: sent ?? this.sent,
      peppolSent: peppolSent ?? this.peppolSent,
      billitStatus: billitStatus ?? this.billitStatus,
      billitIsSent: billitIsSent == _unset
          ? this.billitIsSent
          : billitIsSent as bool?,
      billitPaid: billitPaid == _unset ? this.billitPaid : billitPaid as bool?,
      transportType: transportType,
      sentAt: sentAt,
      peppolSentAt: peppolSentAt,
      statusCheckedAt: statusCheckedAt ?? this.statusCheckedAt,
      sendPending: sendPending ?? this.sendPending,
      peppolSendPending: peppolSendPending ?? this.peppolSendPending,
      reconcilePending: reconcilePending ?? this.reconcilePending,
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
      peppolSent ||
      sendPending ||
      peppolSendPending ||
      reconcilePending;

  /// B12-K: Billit accepted a Peppol send but local reconcile has not finished.
  bool get isPeppolSendPending =>
      sendPending || peppolSendPending || reconcilePending;

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

    var sourceLegId = readAny(const ['source_leg_id', 'sourceLegId']);
    var sourceLegType = readAny(const ['source_leg_type', 'sourceLegType']);
    final rawSource = json['source'];
    if (rawSource is Map) {
      final sourceMap = rawSource.map((k, v) => MapEntry(k.toString(), v));
      String readFromMap(List<String> keys) {
        for (final key in keys) {
          final text = (sourceMap[key] ?? '').toString().trim();
          if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
        }
        return '';
      }

      if (sourceLegId.isEmpty) {
        sourceLegId = readFromMap(const ['leg_id', 'legId', 'source_leg_id']);
      }
      if (sourceLegType.isEmpty) {
        sourceLegType = readFromMap(const [
          'leg_type',
          'legType',
          'source_leg_type',
        ]);
      }
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
      sourceLegId: sourceLegId,
      sourceLegType: sourceLegType,
      billitExport: billitExport,
    );
  }

  /// B10e-B: return a copy with a replaced (updated) Billit export. Every other
  /// field is preserved byte-for-byte; used to apply a read-only status refresh
  /// to the in-memory document without refetching the whole list.
  _BookingDocumentMetadata copyWithBillitExport(_BillitExportMetadata? export) {
    return _BookingDocumentMetadata(
      documentId: documentId,
      documentType: documentType,
      documentNumber: documentNumber,
      proofReference: proofReference,
      lifecycleState: lifecycleState,
      documentStatus: documentStatus,
      issueTimestamp: issueTimestamp,
      currency: currency,
      contentHash: contentHash,
      sourceBookingId: sourceBookingId,
      sourceLegId: sourceLegId,
      sourceLegType: sourceLegType,
      billitExport: export,
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

bool _bookingDocumentMatchesLegFilter(
  _BookingDocumentMetadata doc, {
  String? sourceLegId,
  String? sourceLegType,
}) {
  return bookingDocumentMatchesLegFilter(
    BookingDocumentLegFields(
      sourceLegId: doc.sourceLegId,
      sourceLegType: doc.sourceLegType,
    ),
    sourceLegId: sourceLegId,
    sourceLegType: sourceLegType,
  );
}

/// Builds a display-only Documents row from a just-issued street invoice
/// snapshot so Billit status is visible before the documents GET catches up.
_BookingDocumentMetadata _bookingDocumentFromLocalIssuedSnapshot(
  StreetInvoiceLocalIssuedSnapshot snap,
  String bookingId,
) {
  final hasBillit = snap.hasBillitLink || snap.billitEnvironment.isNotEmpty;
  return _BookingDocumentMetadata(
    documentId: snap.documentId,
    documentType: 'invoice',
    documentNumber: snap.invoiceReference,
    proofReference: '',
    lifecycleState: 'issued',
    documentStatus: 'issued',
    issueTimestamp: '',
    currency: 'EUR',
    contentHash: '',
    sourceBookingId: bookingId,
    sourceLegId: '',
    sourceLegType: '',
    billitExport: hasBillit
        ? _BillitExportMetadata(
            status: snap.billitOrderId.isNotEmpty ? 'created' : '',
            environment: snap.billitEnvironment,
            orderId: snap.billitOrderId,
            orderNumber: '',
            sent: false,
            peppolSent: snap.peppolSent,
            billitStatus: '',
            billitIsSent: null,
            billitPaid: snap.billitPaid,
            transportType: '',
            sentAt: '',
            peppolSentAt: '',
            statusCheckedAt: '',
            reconcilePending:
                snap.billitPaymentSyncStatus.toLowerCase() == 'pending' ||
                snap.billitPaymentSyncStatus.toLowerCase() == 'syncing',
          )
        : null,
  );
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

  /// Optional roundtrip leg filter (outbound/return leg cards only).
  final String? sourceLegId;
  final String? sourceLegType;

  const _BookingDocumentsSection({
    super.key,
    required this.bookingId,
    required this.tokens,
    this.sourceLegId,
    this.sourceLegType,
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
  // B10e-B: per-document Billit-status refresh in-flight set, keyed by
  // document_id (never global) so one refresh never blocks the whole section.
  Set<String> _refreshingDocIds = <String>{};
  // B11-D: per-document Peppol send in-flight set, keyed by document_id so one
  // send never blocks unrelated rows or the status refresh button.
  Set<String> _sendingPeppolDocIds = <String>{};
  // B12-G2: proactive Peppol readiness preview cache, keyed by document_id
  // within the active booking scope. Discarded when the booking identity changes.
  Map<String, BookingPeppolReadinessState> _peppolReadinessByDocId =
      <String, BookingPeppolReadinessState>{};
  Set<String> _fetchingPeppolReadinessDocIds = <String>{};
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

  bool get _hasLegFilter =>
      (widget.sourceLegId ?? '').trim().isNotEmpty ||
      (widget.sourceLegType ?? '').trim().isNotEmpty;

  String get _legFilterScopeKey =>
      '${(widget.sourceLegId ?? '').trim()}::${(widget.sourceLegType ?? '').trim().toLowerCase()}';

  List<_BookingDocumentMetadata> get _filteredDocuments => _documents
      .where((doc) {
        return _bookingDocumentMatchesLegFilter(
          doc,
          sourceLegId: widget.sourceLegId,
          sourceLegType: widget.sourceLegType,
        );
      })
      .toList(growable: false);

  // UI-1B: per-booking locally-issued invoice signal. When the street
  // business-invoice action issues an invoice, its document id is recorded here
  // so the "Documenten" count never shows 0 while the eventually-consistent
  // documents index is still catching up.
  late ValueNotifier<String> _localInvoiceSignal;

  bool get _hasLocalIssuedInvoice => _StreetInvoiceLocalIndex.instance
      .issuedInvoiceDocId(widget.bookingId)
      .isNotEmpty;

  /// Backend-filtered docs plus a synthetic local invoice row when the index
  /// lags (count=1 / empty list field bug). Never mutates [_documents].
  List<_BookingDocumentMetadata> get _documentsForDisplay {
    final base = _filteredDocuments;
    final snap = _StreetInvoiceLocalIndex.instance.snapshotFor(widget.bookingId);
    if (snap == null) return base;
    if (!shouldInjectLocalIssuedInvoiceDocument(
      localDocumentId: snap.documentId,
      visibleBackendDocumentIds: base.map((d) => d.documentId),
    )) {
      return base;
    }
    // Leg-filtered cards hide booking-level invoices without leg meta; do not
    // inject a synthetic row there (keeps count/list semantics aligned).
    if (_hasLegFilter) return base;
    return <_BookingDocumentMetadata>[
      ...base,
      _bookingDocumentFromLocalIssuedSnapshot(snap, widget.bookingId),
    ];
  }

  /// Display-only count that includes a locally-successful invoice until the
  /// backend index exposes it. Never mutates [_documents].
  int _displayedDocumentCount() {
    final localId = _StreetInvoiceLocalIndex.instance.issuedInvoiceDocId(
      widget.bookingId,
    );
    final present =
        localId.isNotEmpty &&
        _filteredDocuments.any((d) => d.documentId == localId);
    // With an active leg filter, a booking-level invoice is not visible in the
    // list — do not inflate the count either (LATE-INVOICE Documents consistency).
    final hasLocalForCount = localId.isNotEmpty && !_hasLegFilter;
    return deriveDisplayedDocumentCount(
      backendVisibleCount: _filteredDocuments.length,
      hasLocalIssuedInvoice: hasLocalForCount,
      localInvoiceInBackend: present,
    );
  }

  void _handleLocalInvoiceChange() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _activeScopeKey = _documentsScopeKey;
    _refreshSignal = _BookingDocumentsRefreshBus.instance.notifierFor(
      widget.bookingId,
    );
    _refreshSignal.addListener(_handleExternalRefresh);
    _localInvoiceSignal = _StreetInvoiceLocalIndex.instance.notifierFor(
      widget.bookingId,
    );
    _localInvoiceSignal.addListener(_handleLocalInvoiceChange);
  }

  @override
  void didUpdateWidget(covariant _BookingDocumentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextScopeKey = _documentsScopeKey;
    final nextLegFilterKey = _legFilterScopeKey;
    final oldLegFilterKey =
        '${(oldWidget.sourceLegId ?? '').trim()}::${(oldWidget.sourceLegType ?? '').trim().toLowerCase()}';
    if (nextScopeKey == _activeScopeKey &&
        nextLegFilterKey == oldLegFilterKey) {
      return;
    }

    if (nextScopeKey == _activeScopeKey) {
      // Same canonical booking, different leg filter (rare without a distinct
      // key). Re-filter the already-fetched documents without a new network call.
      setState(() {});
      return;
    }

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

    _localInvoiceSignal.removeListener(_handleLocalInvoiceChange);
    _localInvoiceSignal = _StreetInvoiceLocalIndex.instance.notifierFor(
      widget.bookingId,
    );
    _localInvoiceSignal.addListener(_handleLocalInvoiceChange);

    final wasExpanded = _expanded;
    setState(() {
      _activeScopeKey = nextScopeKey;
      _documents = const <_BookingDocumentMetadata>[];
      _refreshingDocIds = <String>{};
      _sendingPeppolDocIds = <String>{};
      _peppolReadinessByDocId = <String, BookingPeppolReadinessState>{};
      _fetchingPeppolReadinessDocIds = <String>{};
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
    _localInvoiceSignal.removeListener(_handleLocalInvoiceChange);
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
      _kickPeppolReadinessFetches(parsed, requestScopeKey);
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

  /// B12-G2: mirrors backend/company send eligibility for readiness fetch.
  bool _shouldFetchPeppolReadiness(_BookingDocumentMetadata doc) {
    final export = doc.billitExport;
    if (export == null) return false;
    return shouldFetchBookingPeppolReadiness(
      documentType: doc.documentType,
      documentId: doc.documentId,
      billitEnvironment: export.environment,
      billitOrderId: export.orderId,
      billitSent: export.sent,
      billitPeppolSent: export.peppolSent,
      billitTransportType: export.transportType,
    );
  }

  BookingPeppolReadinessState? _peppolReadinessFor(String docId) {
    return _peppolReadinessByDocId[docId.trim()];
  }

  void _kickPeppolReadinessFetches(
    List<_BookingDocumentMetadata> docs,
    String requestScopeKey,
  ) {
    for (final doc in docs) {
      if (!_shouldFetchPeppolReadiness(doc)) continue;
      final docId = doc.documentId.trim();
      if (docId.isEmpty) continue;
      if (_fetchingPeppolReadinessDocIds.contains(docId)) continue;
      unawaited(_fetchPeppolReadiness(doc, requestScopeKey));
    }
  }

  /// B12-G2: read-only Peppol readiness preview for ONE invoice via
  /// `GET /company/documents/:documentId/billit-payload-preview`. Never sends
  /// Peppol or calls Billit send/status refresh endpoints.
  Future<void> _fetchPeppolReadiness(
    _BookingDocumentMetadata doc,
    String requestScopeKey,
  ) async {
    final docId = doc.documentId.trim();
    if (docId.isEmpty || !_shouldFetchPeppolReadiness(doc)) return;
    if (_fetchingPeppolReadinessDocIds.contains(docId)) return;

    setState(() {
      _fetchingPeppolReadinessDocIds = <String>{
        ..._fetchingPeppolReadinessDocIds,
        docId,
      };
      _peppolReadinessByDocId = <String, BookingPeppolReadinessState>{
        ..._peppolReadinessByDocId,
        docId: BookingPeppolReadinessState.loading,
      };
    });

    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/company/documents/${Uri.encodeComponent(docId)}/billit-payload-preview',
      );
      final auth = await resolveCompanyOwnerAuthHeaders();
      final res = await http
          .get(uri, headers: auth.headers)
          .timeout(const Duration(seconds: 12));
      if (!mounted || requestScopeKey != _activeScopeKey) return;

      BookingPeppolReadinessState next = BookingPeppolReadinessState.unknown;
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          next = parseBookingPeppolReadinessResponse(
            decoded.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      }

      if (!mounted || requestScopeKey != _activeScopeKey) return;
      setState(() {
        _peppolReadinessByDocId = <String, BookingPeppolReadinessState>{
          ..._peppolReadinessByDocId,
          docId: next,
        };
      });
    } catch (_) {
      if (!mounted || requestScopeKey != _activeScopeKey) return;
      setState(() {
        _peppolReadinessByDocId = <String, BookingPeppolReadinessState>{
          ..._peppolReadinessByDocId,
          docId: BookingPeppolReadinessState.unknown,
        };
      });
    } finally {
      if (mounted && requestScopeKey == _activeScopeKey) {
        setState(() {
          _fetchingPeppolReadinessDocIds = <String>{
            ..._fetchingPeppolReadinessDocIds,
          }..remove(docId);
        });
      }
    }
  }

  /// B10e-B: the read-only Billit-status refresh action is offered ONLY for an
  /// invoice document that already has a persisted sandbox Billit export with an
  /// order id. Mirrors the backend eligibility of
  /// `GET /company/documents/:documentId/billit-order/status/sandbox`, so a
  /// hidden button and the backend gate agree. Never shown for credit notes,
  /// refund proofs, invoices without a Billit export, exports without an
  /// order id, or non-sandbox exports.
  bool _shouldShowBillitRefresh(_BookingDocumentMetadata doc) {
    final export = doc.billitExport;
    if (export == null) return false;
    if (doc.documentType.trim().toLowerCase() != 'invoice') return false;
    if (doc.documentId.trim().isEmpty) return false;
    if (export.environment.trim().toLowerCase() != 'sandbox') return false;
    if (export.orderId.trim().isEmpty) return false;
    return true;
  }

  /// B10e-B: read-only refresh of the live Billit status for ONE invoice
  /// document via the company route. Screen-level only: updates the in-memory
  /// document's safe billit_export fields (nothing is persisted server-side).
  /// Uses the same company auth + active-scope pattern as the documents fetch,
  /// keys the in-flight state by document_id, and discards a late response whose
  /// booking scope changed while the request was in flight. Never sends Peppol,
  /// creates/links/reconciles orders, or stores a raw Billit response.
  Future<void> _refreshBillitStatus(_BookingDocumentMetadata doc) async {
    final docId = doc.documentId.trim();
    if (docId.isEmpty) return;
    if (_refreshingDocIds.contains(docId)) return;
    final requestScopeKey = _documentsScopeKey;
    setState(() {
      _refreshingDocIds = <String>{..._refreshingDocIds, docId};
    });
    var success = false;
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/company/documents/${Uri.encodeComponent(docId)}/billit-order/status/sandbox',
      );
      final auth = await resolveCompanyOwnerAuthHeaders();
      final res = await http
          .get(uri, headers: auth.headers)
          .timeout(const Duration(seconds: 12));
      if (!mounted || requestScopeKey != _activeScopeKey) return;
      final decoded = jsonDecode(res.body);
      if (res.statusCode != 200 || decoded is! Map || decoded['ok'] != true) {
        return;
      }
      _applyBillitStatusUpdate(
        docId,
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
      success = true;
      final refreshedDoc = _documents.firstWhere(
        (d) => d.documentId == docId,
        orElse: () => doc,
      );
      if (_shouldFetchPeppolReadiness(refreshedDoc)) {
        unawaited(_fetchPeppolReadiness(refreshedDoc, requestScopeKey));
      }
    } catch (_) {
      // Non-blocking: keep the existing status and fall through to the toast.
    } finally {
      if (mounted && requestScopeKey == _activeScopeKey) {
        setState(() {
          _refreshingDocIds = <String>{..._refreshingDocIds}..remove(docId);
        });
        _showBillitRefreshResult(success);
      }
    }
  }

  /// B10e-B: apply the flattened B10e-A status response onto the matching
  /// in-memory document's billit_export. Only safe live-status fields are
  /// updated; link-identity fields are preserved by [_BillitExportMetadata.copyWith].
  void _applyBillitStatusUpdate(String docId, Map<String, dynamic> decoded) {
    final index = _documents.indexWhere((d) => d.documentId == docId);
    if (index < 0) return;
    final current = _documents[index];
    final export = current.billitExport;
    if (export == null) return;

    String? readString(List<String> keys) {
      for (final key in keys) {
        final raw = decoded[key];
        if (raw == null) continue;
        final text = raw.toString().trim();
        if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
      }
      return null;
    }

    bool? readBool(String key) {
      final value = decoded[key];
      return value is bool ? value : null;
    }

    final updatedExport = export.copyWith(
      status: readString(const ['local_status']),
      orderId: readString(const ['billit_order_id']),
      orderNumber: readString(const ['billit_order_number']),
      sent: readBool('sent'),
      peppolSent: readBool('peppol_sent'),
      billitStatus: readString(const ['billit_status']),
      billitIsSent: readBool('billit_is_sent'),
      billitPaid: readBool('billit_paid'),
      statusCheckedAt: readString(const ['status_checked_at']),
      sendPending: readBool('send_pending'),
      peppolSendPending: readBool('peppol_send_pending'),
      reconcilePending: readBool('reconcile_pending'),
    );

    setState(() {
      _documents = <_BookingDocumentMetadata>[..._documents];
      _documents[index] = current.copyWithBillitExport(updatedExport);
    });
  }

  void _showBillitRefreshResult(bool success) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? _tr(
                  nl: 'Billit-status vernieuwd',
                  en: 'Billit status refreshed',
                  fr: 'Statut Billit actualisé',
                  es: 'Estado de Billit actualizado',
                )
              : _tr(
                  nl: 'Billit-status kon niet vernieuwd worden',
                  en: 'Billit status could not be refreshed',
                  fr: 'Impossible d’actualiser le statut Billit',
                  es: 'No se pudo actualizar el estado de Billit',
                ),
        ),
      ),
    );
  }

  /// B11-D: Peppol send is offered ONLY for an invoice that has a linked sandbox
  /// Billit export with order id and document number, and that has NOT already
  /// been sent / Peppol-sent. Mirrors the backend eligibility of
  /// `POST /company/documents/:documentId/billit-order/send/sandbox`.
  bool _shouldShowBillitPeppolSend(_BookingDocumentMetadata doc) {
    final export = doc.billitExport;
    if (export == null) return false;
    if (doc.documentType.trim().toLowerCase() != 'invoice') return false;
    if (doc.documentId.trim().isEmpty) return false;
    if (doc.documentNumber.trim().isEmpty) return false;
    if (export.environment.trim().toLowerCase() != 'sandbox') return false;
    if (export.orderId.trim().isEmpty) return false;
    if (export.sent) return false;
    if (export.peppolSent) return false;
    if (export.billitIsSent == true) return false;
    if (export.isPeppolSendPending) return false;
    return true;
  }

  /// B11-O: after B11-K decoupled Document Core invoice creation from the
  /// Billit auto-create path, an *issued* invoice can legitimately exist with
  /// NO Billit link (e.g. auto-create setting off, Billit not linked, or the
  /// Billit sandbox order create skipped/failed silently). Before B11-O the
  /// card rendered blank in that state; this helper flags it so the row shows
  /// an explicit, informational "not linked to Billit yet" line matching the
  /// existing document-card styling. Never applies to credit notes / refund
  /// proofs, to non-issued rows, or to rows that already carry a linked Billit
  /// export with an order id — those keep their existing Billit/Peppol UI
  /// byte-for-byte.
  bool _shouldShowBillitNotLinkedYet(_BookingDocumentMetadata doc) {
    if (doc.documentType.trim().toLowerCase() != 'invoice') return false;
    final state =
        (doc.lifecycleState.isNotEmpty
                ? doc.lifecycleState
                : doc.documentStatus)
            .trim()
            .toLowerCase();
    if (state != 'issued') return false;
    final export = doc.billitExport;
    if (export != null && export.orderId.trim().isNotEmpty) return false;
    return true;
  }

  /// B11-D: map audited backend error codes to compact customer-facing text.
  /// Never exposes raw JSON or stack traces in the snackbar.
  String _mapBillitPeppolSendError(String? errorCode) {
    switch ((errorCode ?? '').trim()) {
      case 'confirm_sandbox_send_required':
        return _tr(
          nl: 'Bevestiging ontbreekt voor Peppol-verzending.',
          en: 'Confirmation is required for Peppol sending.',
          fr: 'Confirmation requise pour l’envoi Peppol.',
          es: 'Se requiere confirmación para el envío Peppol.',
        );
      case 'transport_type_not_supported':
        return _tr(
          nl: 'Alleen Peppol-verzending is toegestaan.',
          en: 'Only Peppol sending is allowed.',
          fr: 'Seul l’envoi Peppol est autorisé.',
          es: 'Solo se permite el envío por Peppol.',
        );
      case 'document_type_not_supported_for_peppol_send':
        return _tr(
          nl: 'Alleen facturen kunnen via Peppol worden verzonden.',
          en: 'Only invoices can be sent via Peppol.',
          fr: 'Seules les factures peuvent être envoyées via Peppol.',
          es: 'Solo las facturas pueden enviarse por Peppol.',
        );
      case 'billit_order_not_linked':
        return _tr(
          nl: 'Geen gekoppelde Billit-order voor deze factuur.',
          en: 'No linked Billit order for this invoice.',
          fr: 'Aucune commande Billit liée pour cette facture.',
          es: 'No hay pedido Billit vinculado para esta factura.',
        );
      case 'billit_order_id_mismatch':
        return _tr(
          nl: 'Billit-order komt niet overeen.',
          en: 'Billit order does not match.',
          fr: 'La commande Billit ne correspond pas.',
          es: 'El pedido Billit no coincide.',
        );
      case 'billit_export_not_sandbox':
        return _tr(
          nl: 'Alleen sandbox Billit-export kan via Peppol worden verzonden.',
          en: 'Only sandbox Billit export can be sent via Peppol.',
          fr: 'Seul un export Billit sandbox peut être envoyé via Peppol.',
          es: 'Solo la exportación Billit sandbox puede enviarse por Peppol.',
        );
      case 'billit_order_already_sent':
        return _tr(
          nl: 'Deze factuur is al verzonden.',
          en: 'This invoice has already been sent.',
          fr: 'Cette facture a déjà été envoyée.',
          es: 'Esta factura ya fue enviada.',
        );
      case 'billit_order_already_peppol_sent':
        return _tr(
          nl: 'Deze factuur is al via Peppol verzonden.',
          en: 'This invoice has already been sent via Peppol.',
          fr: 'Cette facture a déjà été envoyée via Peppol.',
          es: 'Esta factura ya fue enviada por Peppol.',
        );
      case 'billit_order_send_pending':
        return _tr(
          nl: 'Peppol-verzending wordt bevestigd. Vernieuw de Billit-status.',
          en: 'Peppol sending is being confirmed. Refresh the Billit status.',
          fr: 'L’envoi Peppol est en cours de confirmation. Actualisez le statut Billit.',
          es: 'El envío Peppol se está confirmando. Actualice el estado de Billit.',
        );
      case 'billit_peppol_not_ready':
        return _tr(
          nl: 'Factuur is nog niet Peppol-klaar.',
          en: 'Invoice is not Peppol-ready yet.',
          fr: 'La facture n’est pas encore prête pour Peppol.',
          es: 'La factura aún no está lista para Peppol.',
        );
      case 'billit_order_not_sendable':
        return _tr(
          nl: 'Billit-order kan nu niet worden verzonden.',
          en: 'Billit order cannot be sent right now.',
          fr: 'La commande Billit ne peut pas être envoyée maintenant.',
          es: 'El pedido Billit no puede enviarse ahora.',
        );
      case 'billit_order_send_failed':
        return _tr(
          nl: 'Peppol-verzending via Billit is mislukt.',
          en: 'Peppol send via Billit failed.',
          fr: 'L’envoi Peppol via Billit a échoué.',
          es: 'El envío Peppol mediante Billit falló.',
        );
      case 'unauthorized':
        return _tr(
          nl: 'Geen toegang.',
          en: 'Not authorized.',
          fr: 'Non autorisé.',
          es: 'No autorizado.',
        );
      case 'forbidden':
        return _tr(
          nl: 'Geen toegang tot dit bedrijf.',
          en: 'No access to this company.',
          fr: 'Pas d’accès à cette entreprise.',
          es: 'Sin acceso a esta empresa.',
        );
      default:
        return _tr(
          nl: 'Peppol-verzending mislukt.',
          en: 'Peppol send failed.',
          fr: 'Échec de l’envoi Peppol.',
          es: 'Error al enviar por Peppol.',
        );
    }
  }

  /// B11-G: map a single Peppol readiness reason code (as emitted by the
  /// backend `billit_peppol_not_ready` response's `reasons[]`) to an
  /// actionable, localized customer-facing sentence. Handles both the current
  /// backend codes (e.g. `missing_currency`, `missing_line_items`,
  /// `missing_vat_rate`) and the prescriptive per-topic aliases used in the
  /// Patch B11-G contract (e.g. `invoice_currency_missing`,
  /// `invoice_lines_missing`, `invoice_vat_breakdown_missing`). Unknown codes
  /// fall back to a labeled "unknown Peppol requirement" line that keeps the
  /// raw code visible for support, but never exposes JSON or stack info.
  String _mapPeppolReadinessReason(String code) {
    switch (code.trim()) {
      case 'customer_identity_missing':
        return _tr(
          nl: 'Klantidentiteit ontbreekt.',
          en: 'Customer identity is missing.',
          fr: 'L’identité du client est manquante.',
          es: 'Falta la identidad del cliente.',
        );
      case 'customer_legal_name_missing':
        return _tr(
          nl: 'Wettelijke klantnaam ontbreekt.',
          en: 'Customer legal name is missing.',
          fr: 'Le nom légal du client est manquant.',
          es: 'Falta el nombre legal del cliente.',
        );
      case 'customer_billing_address_missing':
        return _tr(
          nl: 'Facturatieadres van de klant ontbreekt.',
          en: 'Customer billing address is missing.',
          fr: 'L’adresse de facturation du client est manquante.',
          es: 'Falta la dirección de facturación del cliente.',
        );
      case 'customer_country_missing':
        return _tr(
          nl: 'Land van de klant ontbreekt.',
          en: 'Customer country is missing.',
          fr: 'Le pays du client est manquant.',
          es: 'Falta el país del cliente.',
        );
      case 'customer_vat_or_registration_missing':
        return _tr(
          nl: 'Btw-nummer of ondernemingsnummer van de klant ontbreekt.',
          en: 'Customer VAT number or company registration number is missing.',
          fr: 'Le numéro de TVA ou d’entreprise du client est manquant.',
          es: 'Falta el número de IVA o de registro de la empresa del cliente.',
        );
      case 'customer_peppol_target_missing':
        return _tr(
          nl: 'Peppol-endpoint van de klant ontbreekt.',
          en: 'Customer Peppol endpoint is missing.',
          fr: 'Le point de terminaison Peppol du client est manquant.',
          es: 'Falta el endpoint Peppol del cliente.',
        );
      case 'customer_peppol_scheme_missing':
        return _tr(
          nl: 'Peppol-schema van de klant ontbreekt.',
          en: 'Customer Peppol scheme is missing.',
          fr: 'Le schéma Peppol du client est manquant.',
          es: 'Falta el esquema Peppol del cliente.',
        );
      case 'invoice_currency_missing':
      case 'missing_currency':
        return _tr(
          nl: 'Factuurvaluta ontbreekt.',
          en: 'Invoice currency is missing.',
          fr: 'La devise de la facture est manquante.',
          es: 'Falta la moneda de la factura.',
        );
      case 'invoice_totals_missing':
      case 'missing_totals':
      case 'missing_total':
      case 'missing_subtotal':
      case 'missing_vat_amount':
        return _tr(
          nl: 'Factuurtotalen ontbreken.',
          en: 'Invoice totals are missing.',
          fr: 'Les totaux de la facture sont manquants.',
          es: 'Faltan los totales de la factura.',
        );
      case 'invoice_vat_breakdown_missing':
      case 'missing_vat_rate':
        return _tr(
          nl: 'Btw-uitsplitsing ontbreekt.',
          en: 'VAT breakdown is missing.',
          fr: 'La ventilation de la TVA est manquante.',
          es: 'Falta el desglose del IVA.',
        );
      case 'invoice_lines_missing':
      case 'missing_line_items':
        return _tr(
          nl: 'Factuurlijnen ontbreken.',
          en: 'Invoice line items are missing.',
          fr: 'Les lignes de facture sont manquantes.',
          es: 'Faltan las líneas de la factura.',
        );
      case 'seller_identity_missing':
        return _tr(
          nl: 'Bedrijfsidentiteit ontbreekt.',
          en: 'Seller identity is missing.',
          fr: 'L’identité du vendeur est manquante.',
          es: 'Falta la identidad del vendedor.',
        );
      case 'seller_vat_or_registration_missing':
        return _tr(
          nl: 'Btw-nummer of ondernemingsnummer van je bedrijf ontbreekt.',
          en: 'Seller VAT number or company registration number is missing.',
          fr: 'Le numéro de TVA ou d’entreprise du vendeur est manquant.',
          es: 'Falta el número de IVA o de registro de la empresa del vendedor.',
        );
      case 'seller_country_missing':
        return _tr(
          nl: 'Land van je bedrijf ontbreekt.',
          en: 'Seller country is missing.',
          fr: 'Le pays du vendeur est manquant.',
          es: 'Falta el país del vendedor.',
        );
      default:
        return _tr(
          nl: 'Onbekende Peppol-voorwaarde ontbreekt: $code',
          en: 'Unknown Peppol requirement is missing: $code',
          fr: 'Exigence Peppol inconnue manquante : $code',
          es: 'Falta un requisito Peppol desconocido: $code',
        );
    }
  }

  void _showBillitPeppolSendSnackBar(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// B11-G: safe extraction of a list-of-strings field (e.g. `reasons` or
  /// `warnings`) from the backend send-route response. Ignores non-list values,
  /// null items, and empty/whitespace-only entries. Returns a fresh list; the
  /// caller is free to filter/dedupe further.
  List<String> _extractStringList(Map<String, dynamic>? decoded, String key) {
    if (decoded == null) return const <String>[];
    final raw = decoded[key];
    if (raw is! List) return const <String>[];
    final out = <String>[];
    for (final item in raw) {
      if (item == null) continue;
      final text = item.toString().trim();
      if (text.isEmpty) continue;
      out.add(text);
    }
    return out;
  }

  /// B11-G: show an actionable AlertDialog when the backend returned
  /// `billit_peppol_not_ready`, listing the mapped, deduplicated readiness
  /// reasons instead of a single opaque snackbar. Never exposes raw JSON,
  /// warnings, or stack traces. Read-only UX — does not retry the send.
  Future<void> _showPeppolNotReadyDialog(List<String> reasons) async {
    if (!mounted) return;
    final mapped = <String>[];
    final seen = <String>{};
    for (final code in reasons) {
      final label = _mapPeppolReadinessReason(code);
      if (seen.add(label)) mapped.add(label);
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _tr(
            nl: 'Factuur is nog niet Peppol-klaar',
            en: 'Invoice is not Peppol-ready yet',
            fr: 'La facture n’est pas encore prête pour Peppol',
            es: 'La factura aún no está lista para Peppol',
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _tr(
                  nl: 'Deze factuur kan nog niet via Peppol verzonden worden. Vul eerst de ontbrekende klant- en facturatiegegevens aan.',
                  en: 'This invoice cannot be sent via Peppol yet. First complete the missing customer and billing details.',
                  fr: 'Cette facture ne peut pas encore être envoyée via Peppol. Complétez d’abord les données client et de facturation manquantes.',
                  es: 'Esta factura aún no se puede enviar por Peppol. Primero complete los datos de cliente y facturación que faltan.',
                ),
              ),
              if (mapped.isNotEmpty) const SizedBox(height: 12),
              for (final line in mapped)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(line)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              _tr(nl: 'Sluiten', en: 'Close', fr: 'Fermer', es: 'Cerrar'),
            ),
          ),
        ],
      ),
    );
  }

  /// B11-D: blocking confirmation before the sandbox Peppol send call.
  /// Cancel does nothing; only Send/Verzenden proceeds to the backend route.
  Future<bool> _confirmBillitPeppolSendDialog(
    _BookingDocumentMetadata doc,
  ) async {
    final docNumber = doc.documentNumber.trim();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          _tr(
            nl: 'Factuur via Peppol verzenden?',
            en: 'Send invoice via Peppol?',
            fr: 'Envoyer la facture via Peppol ?',
            es: '¿Enviar factura por Peppol?',
          ),
        ),
        content: Text(
          _tr(
            nl: 'Je staat op het punt factuur $docNumber via Peppol te verzenden in de Billit-sandbox. Controleer eerst klantgegevens, btw-nummer, bedrag en factuurgegevens. Na verzending kan dit niet zomaar ongedaan gemaakt worden.',
            en: 'You are about to send invoice $docNumber via Peppol in the Billit sandbox. First check the customer details, VAT number, amount and invoice data. After sending, this cannot simply be undone.',
            fr: 'Vous êtes sur le point d’envoyer la facture $docNumber via Peppol dans le sandbox Billit. Vérifiez d’abord les données client, le numéro de TVA, le montant et les données de facture. Après l’envoi, cela ne peut pas être annulé facilement.',
            es: 'Está a punto de enviar la factura $docNumber por Peppol en el sandbox de Billit. Compruebe primero los datos del cliente, el número de IVA, el importe y los datos de la factura. Después del envío, esto no se puede deshacer fácilmente.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _tr(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _tr(nl: 'Verzenden', en: 'Send', fr: 'Envoyer', es: 'Enviar'),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// B11-D: apply the safe B11-B send success summary onto the in-memory
  /// document's billit_export so badges/buttons react immediately.
  void _applyBillitPeppolSendSuccess(
    String docId,
    Map<String, dynamic> decoded,
  ) {
    final index = _documents.indexWhere((d) => d.documentId == docId);
    if (index < 0) return;
    final current = _documents[index];
    final export = current.billitExport;
    if (export == null) return;

    String? readString(List<String> keys) {
      for (final key in keys) {
        final raw = decoded[key];
        if (raw == null) continue;
        final text = raw.toString().trim();
        if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
      }
      return null;
    }

    bool? readBool(String key) {
      final value = decoded[key];
      return value is bool ? value : null;
    }

    final updatedExport = export.copyWith(
      status: 'sent',
      sent: readBool('sent') ?? true,
      peppolSent: readBool('peppol_sent') ?? true,
      billitStatus: readString(const ['billit_status']),
      billitIsSent: readBool('billit_is_sent'),
      billitPaid: readBool('billit_paid'),
      statusCheckedAt: readString(const ['status_checked_at']),
      sendPending: false,
      peppolSendPending: false,
      reconcilePending: false,
    );

    setState(() {
      _documents = <_BookingDocumentMetadata>[..._documents];
      _documents[index] = current.copyWithBillitExport(updatedExport);
    });
  }

  /// B12-K: apply defensive pending flags after Billit accepted send but
  /// reconcile has not completed yet (or failed).
  void _applyBillitPeppolSendPending(String docId) {
    final index = _documents.indexWhere((d) => d.documentId == docId);
    if (index < 0) return;
    final current = _documents[index];
    final export = current.billitExport;
    if (export == null) return;

    final updatedExport = export.copyWith(
      sendPending: true,
      peppolSendPending: true,
      reconcilePending: true,
    );

    setState(() {
      _documents = <_BookingDocumentMetadata>[..._documents];
      _documents[index] = current.copyWithBillitExport(updatedExport);
    });
  }

  /// B11-D: sandbox Peppol send for ONE invoice via the company route. Requires
  /// a prior confirmation dialog. Uses the same auth + active-scope pattern as
  /// the B10e-B status refresh. Never calls admin routes, never auto-retries.
  Future<void> _sendBillitPeppolSandbox(_BookingDocumentMetadata doc) async {
    final docId = doc.documentId.trim();
    final docNumber = doc.documentNumber.trim();
    final export = doc.billitExport;
    final orderId = export?.orderId.trim() ?? '';
    if (docId.isEmpty ||
        docNumber.isEmpty ||
        export == null ||
        orderId.isEmpty) {
      return;
    }
    if (_sendingPeppolDocIds.contains(docId)) return;

    final requestScopeKey = _documentsScopeKey;
    setState(() {
      _sendingPeppolDocIds = <String>{..._sendingPeppolDocIds, docId};
    });

    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/company/documents/${Uri.encodeComponent(docId)}/billit-order/send/sandbox',
      );
      final auth = await resolveCompanyOwnerAuthHeaders();
      final payload = <String, dynamic>{
        'confirm_sandbox_send': true,
        'document_number': docNumber,
        'billit_order_id': orderId,
        'transport_type': 'Peppol',
      };
      final res = await http
          .post(
            uri,
            headers: {...auth.headers, 'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted || requestScopeKey != _activeScopeKey) return;

      Map<String, dynamic>? decoded;
      try {
        final raw = jsonDecode(res.body);
        if (raw is Map) {
          decoded = raw.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {
        decoded = null;
      }

      if (decoded != null &&
          decoded['error'] == 'billit_order_reconcile_failed' &&
          decoded['sandbox_send'] == true) {
        _applyBillitPeppolSendPending(docId);
        _showBillitPeppolSendSnackBar(
          _tr(
            nl: 'Peppol-verzending wordt bevestigd. Vernieuw de Billit-status.',
            en: 'Peppol sending is being confirmed. Refresh the Billit status.',
            fr: 'L’envoi Peppol est en cours de confirmation. Actualisez le statut Billit.',
            es: 'El envío Peppol se está confirmando. Actualice el estado de Billit.',
          ),
        );
        _loadDocuments();
        return;
      }

      if (res.statusCode == 200 && decoded != null && decoded['ok'] == true) {
        _applyBillitPeppolSendSuccess(docId, decoded);
        _showBillitPeppolSendSnackBar(
          _tr(
            nl: 'Factuur verzonden via Peppol.',
            en: 'Invoice sent via Peppol.',
            fr: 'Facture envoyée via Peppol.',
            es: 'Factura enviada por Peppol.',
          ),
        );
        _loadDocuments();
        return;
      }

      final errorCode = decoded?['error']?.toString().trim();
      if (errorCode == 'billit_peppol_not_ready') {
        final reasons = _extractStringList(decoded, 'reasons');
        await _showPeppolNotReadyDialog(reasons);
        return;
      }
      _showBillitPeppolSendSnackBar(_mapBillitPeppolSendError(errorCode));
    } catch (_) {
      if (!mounted || requestScopeKey != _activeScopeKey) return;
      _showBillitPeppolSendSnackBar(
        _tr(
          nl: 'Peppol-verzending mislukt.',
          en: 'Peppol send failed.',
          fr: 'Échec de l’envoi Peppol.',
          es: 'Error al enviar por Peppol.',
        ),
      );
    } finally {
      if (mounted && requestScopeKey == _activeScopeKey) {
        setState(() {
          _sendingPeppolDocIds = <String>{..._sendingPeppolDocIds}
            ..remove(docId);
        });
      }
    }
  }

  /// B11-D: show confirmation first; only Send/Verzenden calls the backend.
  Future<void> _promptAndSendBillitPeppolSandbox(
    _BookingDocumentMetadata doc,
  ) async {
    if (_sendingPeppolDocIds.contains(doc.documentId.trim())) return;

    final gate = evaluateBookingPeppolSendGate(
      _peppolReadinessFor(doc.documentId),
    );
    switch (gate) {
      case BookingPeppolSendGate.blockNotReady:
        final reasons =
            _peppolReadinessFor(doc.documentId)?.reasons ?? const <String>[];
        await _showPeppolNotReadyDialog(reasons);
        return;
      case BookingPeppolSendGate.blockLoading:
        _showBillitPeppolSendSnackBar(
          _tr(
            nl: 'Peppol-gereedheid wordt nog gecontroleerd.',
            en: 'Peppol readiness is still being checked.',
            fr: 'La préparation Peppol est encore en cours de vérification.',
            es: 'La preparación Peppol aún se está comprobando.',
          ),
        );
        return;
      case BookingPeppolSendGate.allow:
      case BookingPeppolSendGate.allowWithBackendGuard:
        break;
    }

    final confirmed = await _confirmBillitPeppolSendDialog(doc);
    if (!confirmed || !mounted) return;
    await _sendBillitPeppolSandbox(doc);
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
                if ((_loaded && !_error) || _hasLocalIssuedInvoice) ...[
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
                      '${_displayedDocumentCount()}',
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
    final visible = _documentsForDisplay;
    // Synthetic local invoice (if any) is already merged into [visible], so
    // count=1 can never coexist with the empty-state copy.
    if (shouldShowBookingDocumentsEmptyState(
      visibleDocumentCount: visible.length,
      hasPendingLocalIssuedInvoice: false,
    )) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          _hasLegFilter
              ? _tr(
                  nl: 'Nog geen documenten voor deze rit.',
                  en: 'No documents for this ride yet.',
                  fr: 'Aucun document pour ce trajet.',
                  es: 'Aún no hay documentos para este trayecto.',
                )
              : _tr(
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
      children: [
        for (final doc in visible) _buildDocumentRow(tokens, doc),
      ],
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
            _buildBillitStatusBlock(tokens, doc, doc.billitExport!),
          if (_shouldShowBillitNotLinkedYet(doc))
            _buildBillitNotLinkedYetBlock(tokens),
          if (_shouldShowBillitRefresh(doc))
            _buildBillitRefreshButton(tokens, doc),
          if (_shouldShowBillitPeppolSend(doc))
            _buildBillitPeppolSendButton(tokens, doc),
        ],
      ),
    );
  }

  /// B10e-B: compact, read-only "Refresh Billit status" action. Shown only for
  /// eligible invoice documents (see [_shouldShowBillitRefresh]). This is NOT a
  /// Peppol send / order create button: it only re-reads the live sandbox status
  /// and updates the on-screen badges. Disabled (with a spinner) while that one
  /// document is refreshing; other rows stay interactive.
  Widget _buildBillitRefreshButton(
    _CompanyBookingsThemeTokens tokens,
    _BookingDocumentMetadata doc,
  ) {
    final refreshing = _refreshingDocIds.contains(doc.documentId.trim());
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: TextButton.icon(
        onPressed: refreshing ? null : () => _refreshBillitStatus(doc),
        style: TextButton.styleFrom(
          foregroundColor: tokens.accent,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          alignment: Alignment.centerLeft,
        ),
        icon: refreshing
            ? SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
                ),
              )
            : Icon(Icons.sync, size: 14, color: tokens.accent),
        label: Text(
          _tr(
            nl: 'Billit-status vernieuwen',
            en: 'Refresh Billit status',
            fr: 'Actualiser le statut Billit',
            es: 'Actualizar estado de Billit',
          ),
          style: const TextStyle(fontSize: 11.0, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  /// B11-D: compact Peppol send action for eligible sandbox invoice documents
  /// (see [_shouldShowBillitPeppolSend]). Requires a blocking confirmation
  /// dialog before calling
  /// `POST /company/documents/:documentId/billit-order/send/sandbox`.
  /// Disabled while that document is sending; other rows stay interactive.
  Widget _buildBillitPeppolSendButton(
    _CompanyBookingsThemeTokens tokens,
    _BookingDocumentMetadata doc,
  ) {
    final sending = _sendingPeppolDocIds.contains(doc.documentId.trim());
    final gate = evaluateBookingPeppolSendGate(
      _peppolReadinessFor(doc.documentId),
    );
    final blocked =
        gate == BookingPeppolSendGate.blockNotReady ||
        gate == BookingPeppolSendGate.blockLoading;
    final Color actionColor = gate == BookingPeppolSendGate.blockNotReady
        ? tokens.textSecondary
        : tokens.accent;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: TextButton.icon(
        onPressed: sending
            ? null
            : () => _promptAndSendBillitPeppolSandbox(doc),
        style: TextButton.styleFrom(
          foregroundColor: actionColor,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          alignment: Alignment.centerLeft,
        ),
        icon: sending
            ? SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
                ),
              )
            : Icon(
                blocked ? Icons.info_outline : Icons.send_outlined,
                size: 14,
                color: actionColor,
              ),
        label: Text(
          _tr(
            nl: 'Verstuur via Peppol',
            en: 'Send via Peppol',
            fr: 'Envoyer via Peppol',
            es: 'Enviar por Peppol',
          ),
          style: TextStyle(
            fontSize: 11.0,
            fontWeight: FontWeight.w700,
            color: actionColor,
          ),
        ),
      ),
    );
  }

  /// B11-O: compact, read-only "not linked to Billit yet" line for an issued
  /// invoice whose Document Core record has no Billit export / no Billit order
  /// id yet. Pure display: no onTap, no button, no network call, no confirmation
  /// dialog. Never triggers a Billit create / link / send / reconcile and never
  /// tells the user anything is wrong — it just makes an otherwise blank card
  /// area explicit and consistent with older invoices that DO show a Billit
  /// block. Existing linked-Billit rows never render this and are unaffected.
  Widget _buildBillitNotLinkedYetBlock(_CompanyBookingsThemeTokens tokens) {
    final primary = _tr(
      nl: 'Nog niet gekoppeld aan Billit',
      en: 'Not linked to Billit yet',
      fr: 'Pas encore lié à Billit',
      es: 'Aún no vinculado a Billit',
    );
    final subtext = _tr(
      nl: 'Peppol is beschikbaar zodra deze factuur in Billit klaarstaat.',
      en: 'Peppol becomes available once this invoice is ready in Billit.',
      fr: 'Peppol sera disponible dès que cette facture sera prête dans Billit.',
      es: 'Peppol estará disponible cuando esta factura esté lista en Billit.',
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _billitStatusChip(tokens, primary, primary: false),
          const SizedBox(height: 3),
          Text(
            subtext,
            style: TextStyle(
              color: tokens.textTertiary.withOpacity(0.85),
              fontSize: 9.8,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  /// B10c / B12-G2: read-only Billit/Peppol status block rendered beneath a
  /// document's metadata. Proactive Peppol readiness chip is shown for eligible
  /// unsent sandbox invoices (hidden once sent via Peppol). Pure display except
  /// the not-ready chip, which opens the readiness dialog on tap.
  Widget _buildBillitStatusBlock(
    _CompanyBookingsThemeTokens tokens,
    _BookingDocumentMetadata doc,
    _BillitExportMetadata export,
  ) {
    final billitStatus = export.billitStatus.toLowerCase();
    final status = export.status.toLowerCase();

    String? primaryLabel;
    String? secondaryLabel;

    if (export.isPeppolSendPending) {
      primaryLabel = _tr(
        nl: 'Peppol-verzending wordt bevestigd',
        en: 'Peppol sending is being confirmed',
        fr: 'Envoi Peppol en cours de confirmation',
        es: 'Envío Peppol en confirmación',
      );
      secondaryLabel = _tr(
        nl: 'Vernieuw de Billit-status',
        en: 'Refresh the Billit status',
        fr: 'Actualisez le statut Billit',
        es: 'Actualice el estado de Billit',
      );
    } else if (export.isSentViaPeppol) {
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

    final showReadinessChip =
        shouldShowBookingPeppolReadinessChip(
          fetchEligible: _shouldFetchPeppolReadiness(doc),
          sentViaPeppol: export.isSentViaPeppol,
        ) &&
        !export.isPeppolSendPending;
    final readiness = showReadinessChip
        ? (_peppolReadinessFor(doc.documentId) ??
              BookingPeppolReadinessState.loading)
        : null;

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
              if (readiness != null)
                _buildPeppolReadinessChip(tokens, doc, readiness),
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
          if (readiness != null &&
              readiness.phase == BookingPeppolReadinessPhase.notReady &&
              readiness.reasons.isNotEmpty) ...[
            const SizedBox(height: 3),
            ...readiness.reasons.map((code) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '• ${_mapPeppolReadinessReason(code)}',
                  style: TextStyle(color: tokens.textTertiary, fontSize: 9.8),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  /// B12-G2: proactive Peppol readiness chip inside the Billit status block.
  Widget _buildPeppolReadinessChip(
    _CompanyBookingsThemeTokens tokens,
    _BookingDocumentMetadata doc,
    BookingPeppolReadinessState readiness,
  ) {
    late final String label;
    late final bool primary;
    late final bool warning;
    VoidCallback? onTap;

    switch (readiness.phase) {
      case BookingPeppolReadinessPhase.loading:
        label = _tr(
          nl: 'Peppol-gereedheid controleren…',
          en: 'Checking Peppol readiness…',
          fr: 'Vérification de la préparation Peppol…',
          es: 'Comprobando preparación Peppol…',
        );
        primary = false;
        warning = false;
        break;
      case BookingPeppolReadinessPhase.ready:
        label = _tr(
          nl: 'Klaar voor Peppol',
          en: 'Ready for Peppol',
          fr: 'Prêt pour Peppol',
          es: 'Listo para Peppol',
        );
        primary = true;
        warning = false;
        break;
      case BookingPeppolReadinessPhase.notReady:
        label = _tr(
          nl: 'Peppol-instelling nodig',
          en: 'Peppol setup needed',
          fr: 'Configuration Peppol requise',
          es: 'Configuración Peppol necesaria',
        );
        primary = false;
        warning = true;
        onTap = () => _showPeppolNotReadyDialog(readiness.reasons);
        break;
      case BookingPeppolReadinessPhase.unknown:
        label = _tr(
          nl: 'Peppol-gereedheid niet gecontroleerd',
          en: 'Peppol readiness not checked',
          fr: 'Préparation Peppol non vérifiée',
          es: 'Preparación Peppol no comprobada',
        );
        primary = false;
        warning = false;
        break;
    }

    final chip = _billitStatusChip(
      tokens,
      label,
      primary: primary,
      warning: warning,
    );
    if (onTap == null) return chip;
    return GestureDetector(onTap: onTap, child: chip);
  }

  /// Subtle, read-only status chip. Deliberately styled unlike a button (no
  /// elevation, no ripple, no icon) and distinct from the green lifecycle badge.
  Widget _billitStatusChip(
    _CompanyBookingsThemeTokens tokens,
    String label, {
    required bool primary,
    bool warning = false,
  }) {
    final Color bg = warning
        ? const Color(0xFFFFF3E0)
        : primary
        ? tokens.accent.withOpacity(0.12)
        : tokens.textSecondary.withOpacity(0.10);
    final Color border = warning
        ? const Color(0xFFFFB74D).withOpacity(0.55)
        : primary
        ? tokens.accent.withOpacity(0.4)
        : tokens.textSecondary.withOpacity(0.3);
    final Color fg = warning
        ? const Color(0xFFE65100)
        : primary
        ? tokens.accent
        : tokens.textSecondary;
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
