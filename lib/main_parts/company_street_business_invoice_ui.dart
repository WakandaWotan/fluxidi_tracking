part of '../main.dart';

/// Company-side wiring for requesting / viewing a business invoice for a
/// completed street ride (Phase STREET-BUSINESS-INVOICE-UI-1 / hardened in
/// UI-1B / driver-symmetric in DRIVER-RECEIPT-1).
///
/// All pure logic (eligibility, payload, parsing, error mapping, lifecycle
/// controller, derived counts) lives in `street_business_invoice_support.dart`;
/// the presentational widget + shared request form + shared detail sheet live
/// in `street_business_invoice_widgets.dart`. Both are unit/widget tested.
///
/// This part ONLY wires the app's existing company/admin networking
/// (`_withActiveBookingScope` + `resolveCompanyOwnerAuthHeaders` + `http`) into
/// that shared controller. The driver receipt reuses the exact same controller
/// + widgets + form via `driver_receipt_business_invoice_ui.dart`, with driver
/// authentication injected instead — there is no second form/controller.
///
/// It never calls a Peppol send route, never mutates payment state, and never
/// creates a second invoice engine — it calls the already-live Booking Worker
/// route `POST /company/bookings/:bookingId/request-business-invoice`.

/// Per-booking record of a locally-issued invoice, shared with the read-only
/// `_BookingDocumentsSection` so the "Documenten" count and list stay honest
/// (and Billit status remains visible) while the documents index catches up.
class _StreetInvoiceLocalIndex {
  _StreetInvoiceLocalIndex._();

  static final _StreetInvoiceLocalIndex instance = _StreetInvoiceLocalIndex._();

  final Map<String, ValueNotifier<String>> _byBooking =
      <String, ValueNotifier<String>>{};
  final Map<String, StreetInvoiceLocalIssuedSnapshot> _snapshots =
      <String, StreetInvoiceLocalIssuedSnapshot>{};

  ValueNotifier<String> notifierFor(String bookingId) =>
      _byBooking.putIfAbsent(bookingId.trim(), () => ValueNotifier<String>(''));

  String issuedInvoiceDocId(String bookingId) =>
      _byBooking[bookingId.trim()]?.value ?? '';

  StreetInvoiceLocalIssuedSnapshot? snapshotFor(String bookingId) =>
      _snapshots[bookingId.trim()];

  void registerIssuedInvoice(
    String bookingId, {
    required String documentId,
    StreetInvoiceLocalIssuedSnapshot? snapshot,
  }) {
    final id = documentId.trim();
    if (id.isEmpty) return;
    final key = bookingId.trim();
    final resolved =
        snapshot ??
        StreetInvoiceLocalIssuedSnapshot(documentId: id);
    _snapshots[key] = resolved.documentId.trim().isEmpty
        ? StreetInvoiceLocalIssuedSnapshot(
            documentId: id,
            invoiceReference: resolved.invoiceReference,
            billitEnvironment: resolved.billitEnvironment,
            billitOrderId: resolved.billitOrderId,
            billitPaymentSyncStatus: resolved.billitPaymentSyncStatus,
            peppolSent: resolved.peppolSent,
            billitPaid: resolved.billitPaid,
          )
        : StreetInvoiceLocalIssuedSnapshot(
            documentId: id,
            invoiceReference: resolved.invoiceReference,
            billitEnvironment: resolved.billitEnvironment,
            billitOrderId: resolved.billitOrderId,
            billitPaymentSyncStatus: resolved.billitPaymentSyncStatus,
            peppolSent: resolved.peppolSent,
            billitPaid: resolved.billitPaid,
          );
    notifierFor(key).value = id;
  }
}

/// Bounded, realistic eventual-consistency window (the live proof showed the
/// documents index can lag >20s after a successful invoice creation).
const Duration kStreetInvoicePollTimeout = Duration(seconds: 60);

/// Builds a [StreetInvoiceActionTheme] from the company-bookings theme tokens.
StreetInvoiceActionTheme _streetInvoiceThemeFromCompanyTokens(
  _CompanyBookingsThemeTokens t,
) {
  return StreetInvoiceActionTheme(
    accent: t.accent,
    textPrimary: t.textPrimary,
    textSecondary: t.textSecondary,
    textTertiary: t.textTertiary,
    danger: t.danger,
    paidText: t.paidText,
    unpaidText: t.unpaidText,
    surface: t.palette.surface,
    surfaceAlt: t.palette.surfaceAlt,
    border: t.palette.border,
  );
}

/// CONSUMER-SALE-LATE-INVOICE-ACTION-PLACEMENT-P1
///
/// Single large “Zakelijke factuur aanvragen” slot above Documenten.
/// Street: mount immediately (canonical street eligibility).
/// Planned/other completed: probe documents; mount only when a convertible
/// consumer sale exists (never guess when Documenten count is 0).
class _CompanyLateBusinessInvoicePlacement extends StatefulWidget {
  const _CompanyLateBusinessInvoicePlacement({
    super.key,
    required this.bookingId,
    required this.isPaidBooking,
    required this.tokens,
    required this.placementKind,
  });

  final String bookingId;
  final bool isPaidBooking;
  final _CompanyBookingsThemeTokens tokens;
  final CompanyLateInvoicePlacementKind placementKind;

  @override
  State<_CompanyLateBusinessInvoicePlacement> createState() =>
      _CompanyLateBusinessInvoicePlacementState();
}

class _CompanyLateBusinessInvoicePlacementState
    extends State<_CompanyLateBusinessInvoicePlacement> {
  bool _probeDone = false;
  bool _showAction = false;
  bool _convertFromConsumerSale = false;

  @override
  void initState() {
    super.initState();
    switch (widget.placementKind) {
      case CompanyLateInvoicePlacementKind.hidden:
        _probeDone = true;
        _showAction = false;
        break;
      case CompanyLateInvoicePlacementKind.streetCanonicalSlot:
        _probeDone = true;
        _showAction = true;
        // Best-effort: detect consumer sale for credit-first form copy.
        unawaited(_probeConsumerSaleFlagOnly());
        break;
      case CompanyLateInvoicePlacementKind.consumerSaleProbeSlot:
        unawaited(_probeForConvertibleConsumerSale());
        break;
    }
  }

  Future<void> _probeConsumerSaleFlagOnly() async {
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/company/bookings/${Uri.encodeComponent(widget.bookingId)}/documents',
      );
      final auth = await resolveCompanyOwnerAuthHeaders();
      final res = await http
          .get(uri, headers: auth.headers)
          .timeout(const Duration(seconds: 12));
      if (!mounted || res.statusCode != 200) return;
      Object? decoded;
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        return;
      }
      final convertible = documentsEnvelopeHasConvertibleConsumerSale(decoded);
      if (!mounted) return;
      setState(() => _convertFromConsumerSale = convertible);
    } catch (_) {
      // Non-fatal: street slot stays visible; form uses non-conversion copy.
    }
  }

  Future<void> _probeForConvertibleConsumerSale() async {
    var show = false;
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/company/bookings/${Uri.encodeComponent(widget.bookingId)}/documents',
      );
      final auth = await resolveCompanyOwnerAuthHeaders();
      final res = await http
          .get(uri, headers: auth.headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        Object? decoded;
        try {
          decoded = jsonDecode(res.body);
        } catch (_) {
          decoded = null;
        }
        show = documentsEnvelopeHasConvertibleConsumerSale(decoded);
      }
    } catch (_) {
      show = false;
    }
    if (!mounted) return;
    setState(() {
      _probeDone = true;
      _showAction = show;
      _convertFromConsumerSale = show;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_probeDone || !_showAction) return const SizedBox.shrink();
    return _StreetBusinessInvoiceAction(
      key: ValueKey('late-invoice-action-${widget.bookingId}'),
      bookingId: widget.bookingId,
      isPaidBooking: widget.isPaidBooking,
      tokens: widget.tokens,
      convertFromConsumerSale: _convertFromConsumerSale,
    );
  }
}

class _StreetBusinessInvoiceAction extends StatefulWidget {
  const _StreetBusinessInvoiceAction({
    super.key,
    required this.bookingId,
    required this.isPaidBooking,
    required this.tokens,
    this.convertFromConsumerSale = false,
  });

  final String bookingId;
  final bool isPaidBooking;
  final _CompanyBookingsThemeTokens tokens;
  final bool convertFromConsumerSale;

  @override
  State<_StreetBusinessInvoiceAction> createState() =>
      _StreetBusinessInvoiceActionState();
}

class _StreetBusinessInvoiceActionState
    extends State<_StreetBusinessInvoiceAction> {
  late final StreetBusinessInvoiceController _controller;
  bool _localIndexNotified = false;
  bool _docsIndicateConvertibleConsumerSale = false;

  @override
  void initState() {
    super.initState();
    _controller = StreetBusinessInvoiceController(
      bookingId: widget.bookingId,
      isPaidBooking: widget.isPaidBooking,
      postInvoice: _postInvoice,
      fetchDocuments: _fetchDocuments,
      pollTimeout: kStreetInvoicePollTimeout,
    );
    _controller.addListener(_onControllerChanged);
    // On (re)open: detect an already-issued invoice and render "view".
    unawaited(_controller.loadExisting());
  }

  @override
  void didUpdateWidget(covariant _StreetBusinessInvoiceAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Controller is preserved across rebuilds; propagate a late paid transition
    // to its monotonic canonical ride-paid so the invoice never stays
    // "outstanding" once the booking is canonically paid (1D).
    if (widget.isPaidBooking != oldWidget.isPaidBooking) {
      _controller.updateCanonicalRidePaymentStatus(widget.isPaidBooking);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    // When an invoice is first known, record it in the shared local index and
    // nudge the existing Documents section (same canonical booking id) to
    // reload. This keeps the Documents count honest and is a GET refresh only.
    if (!_localIndexNotified && _controller.hasIssuedInvoice) {
      _localIndexNotified = true;
      final docId = _controller.displayDocumentId;
      if (docId.isNotEmpty) {
        final issued = _controller.issuedResponse;
        final indexed = _controller.indexedInvoice;
        final snapshot = issued != null
            ? StreetInvoiceLocalIssuedSnapshot.fromIssueResponse(issued)
            : (indexed != null
                  ? StreetInvoiceLocalIssuedSnapshot.fromDocSummary(indexed)
                  : StreetInvoiceLocalIssuedSnapshot(documentId: docId));
        _StreetInvoiceLocalIndex.instance.registerIssuedInvoice(
          widget.bookingId,
          documentId: docId,
          snapshot: snapshot,
        );
      }
      _BookingDocumentsRefreshBus.instance.requestRefresh(widget.bookingId);
    }
  }

  Future<StreetInvoicePostResult> _postInvoice(
    Map<String, dynamic> body,
  ) async {
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/company/bookings/${Uri.encodeComponent(widget.bookingId)}'
        '/request-business-invoice',
      );
      final auth = await resolveCompanyOwnerAuthHeaders();
      final res = await http
          .post(uri, headers: auth.headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
      Object? decoded;
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        decoded = null;
      }
      if (res.statusCode == 200) {
        final parsed = parseStreetBusinessInvoiceResponse(decoded);
        if (parsed != null && parsed.ok) {
          return StreetInvoicePostResult(statusCode: 200, response: parsed);
        }
        return StreetInvoicePostResult(
          statusCode: 200,
          errorToken: decoded is Map ? decoded['error']?.toString() : null,
        );
      }
      return StreetInvoicePostResult(
        statusCode: res.statusCode,
        errorToken: decoded is Map ? decoded['error']?.toString() : null,
      );
    } catch (_) {
      // Timeout / connectivity: treat as network so the UI offers a safe retry.
      return const StreetInvoicePostResult(statusCode: null);
    }
  }

  Future<StreetInvoiceDocsResult> _fetchDocuments() async {
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/company/bookings/${Uri.encodeComponent(widget.bookingId)}/documents',
      );
      final auth = await resolveCompanyOwnerAuthHeaders();
      final res = await http
          .get(uri, headers: auth.headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        return StreetInvoiceDocsResult(statusCode: res.statusCode);
      }
      Object? decoded;
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        decoded = null;
      }
      if (documentsEnvelopeOk(decoded)) {
        _docsIndicateConvertibleConsumerSale =
            documentsEnvelopeHasConvertibleConsumerSale(decoded);
      }
      return StreetInvoiceDocsResult(
        statusCode: 200,
        okEnvelope: documentsEnvelopeOk(decoded),
        invoice: extractInvoiceFromDocuments(
          decoded,
          expectedDocumentId: _controller.issuedResponse?.documentId,
        ),
        invoicePdfReady: extractInvoicePdfReadyFromDocuments(decoded),
      );
    } catch (_) {
      return const StreetInvoiceDocsResult();
    }
  }

  Future<void> _openForm() async {
    final input = await showStreetBusinessInvoiceForm(
      context: context,
      theme: _streetInvoiceThemeFromCompanyTokens(widget.tokens),
      language: appLanguageNotifier.value,
      isPaidBooking: widget.isPaidBooking,
      initial: const StreetBusinessInvoiceBuyerInput(),
      convertFromConsumerSale:
          widget.convertFromConsumerSale ||
          _docsIndicateConvertibleConsumerSale,
    );
    if (input == null || !mounted) return;
    await _controller.submit(input);
  }

  void _openDetail() {
    unawaited(
      showStreetInvoiceDetailSheet(
        context: context,
        theme: _streetInvoiceThemeFromCompanyTokens(widget.tokens),
        language: appLanguageNotifier.value,
        reference: _controller.displayInvoiceReference,
        invoicePaymentStatus: _controller.displayInvoicePaymentStatus,
        peppolSent: _controller.displayPeppolSent,
        hasBillitLink: _controller.hasBillitLink,
        pdfState: _controller.pdfAvailability.state,
        processingStatus:
            _controller.paymentPresentation.invoiceProcessingStatus,
        diagnostics: _controller.paymentDiagnostics,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, language, _) {
        return StreetBusinessInvoiceActionView(
          controller: _controller,
          theme: _streetInvoiceThemeFromCompanyTokens(widget.tokens),
          language: language,
          onRequest: _openForm,
          onView: _openDetail,
          // Compact company card: the detailed Billit/Peppol statuses live in
          // the expanded Documents block below, so do not duplicate them here.
          showBillitAndPeppol: false,
        );
      },
    );
  }
}
