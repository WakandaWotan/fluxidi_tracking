part of '../main.dart';

/// Driver-receipt wiring for requesting / viewing a business invoice for the
/// driver's OWN completed street ride (Phase STREET-BUSINESS-INVOICE-DRIVER-
/// RECEIPT-1 / UX-1).
///
/// This reuses the EXACT same shared controller, presentational widget, request
/// form and detail sheet as the company flow (see
/// `street_business_invoice_support.dart` /
/// `street_business_invoice_widgets.dart` /
/// `company_street_business_invoice_ui.dart`). The only difference is the
/// injected networking: the driver flow authenticates with the driver session
/// bearer + strict driver scope instead of company/admin auth.
///
/// It never creates a second invoice engine, never sends Peppol and never
/// mutates payment state — it calls the same live Booking Worker route
/// `POST /company/bookings/:bookingId/request-business-invoice`, which now also
/// authorizes an assigned driver for their own completed street ride.

/// Builds a [StreetInvoiceActionTheme] from the driver receipt palette.
StreetInvoiceActionTheme streetInvoiceThemeFromDriverPalette(
  DriverThemePalette p,
) {
  return StreetInvoiceActionTheme(
    accent: p.accent,
    textPrimary: p.textPrimary,
    textSecondary: p.textMuted,
    textTertiary: p.textMuted,
    danger: p.danger,
    paidText: p.success,
    unpaidText: p.accent,
    surface: p.surface,
    surfaceAlt: p.surfaceAlt,
    border: p.border,
  );
}

/// Embedded inside the receipt Payment card as the fourth payment action.
class _DriverReceiptBusinessInvoiceAction extends StatefulWidget {
  const _DriverReceiptBusinessInvoiceAction({
    super.key,
    required this.bookingId,
    required this.tripItem,
    required this.isPaidBooking,
    required this.palette,
    required this.initialBuyer,
    required this.authMode,
    this.onInvoicePresenceChanged,
  });

  final String bookingId;
  final _TripHistoryItem tripItem;
  final bool isPaidBooking;
  final DriverThemePalette palette;
  final StreetBusinessInvoiceBuyerInput initialBuyer;

  /// Which authenticated actor issues the GET documents / POST request calls.
  /// driver → driver session bearer; companyAdmin → company/admin bearer.
  final StreetBusinessInvoiceAuthMode authMode;
  final void Function({required bool hasInvoice, required bool isPaid})?
  onInvoicePresenceChanged;

  @override
  State<_DriverReceiptBusinessInvoiceAction> createState() =>
      _DriverReceiptBusinessInvoiceActionState();
}

class _DriverReceiptBusinessInvoiceActionState
    extends State<_DriverReceiptBusinessInvoiceAction> {
  late final StreetBusinessInvoiceController _controller;

  @override
  void initState() {
    super.initState();
    _controller = StreetBusinessInvoiceController(
      bookingId: widget.bookingId,
      isPaidBooking: widget.isPaidBooking,
      postInvoice: _postInvoice,
      fetchDocuments: _fetchDocuments,
      probePdf: _probePdf,
      pollTimeout: kStreetInvoicePollTimeout,
    );
    _controller.addListener(_onControllerChanged);
    unawaited(_controller.loadExisting());
  }

  @override
  void didUpdateWidget(covariant _DriverReceiptBusinessInvoiceAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The controller is preserved across rebuilds (stable ValueKey), so a late
    // receipt-paid transition must be propagated to its monotonic canonical
    // ride-paid — otherwise the resolver keeps the construction-time value and
    // shows "Factuur openstaand" for an already-paid ride (1D).
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

  void _notifyPresence() {
    // Receipt Payment row treats sync-in-progress / sync-failed as ride-paid;
    // the invoice block shows the semantic sync label separately.
    widget.onInvoicePresenceChanged?.call(
      hasInvoice: _controller.hasIssuedInvoice,
      isPaid:
          _controller.displayIsPaid ||
          _controller.displayPaymentSyncInProgress ||
          _controller.displayPaymentSyncFailed,
    );
  }

  void _onControllerChanged() {
    _notifyPresence();
    if (mounted) setState(() {});
  }

  /// Auth-context aware request builder. In driver mode it uses the strict
  /// driver scope query + driver session bearer. In company-admin mode it uses
  /// the active company/business-preview scope + company/admin bearer resolved
  /// by [resolveCompanyOwnerAuthHeaders]. It never mixes tokens across modes
  /// and never falls back to an arbitrary "first available" token. Returns null
  /// (with a message the caller maps to an error) when the selected actor's
  /// scope or token is not available.
  Future<({Uri uri, Map<String, String> headers})?> _authedRequest(
    String path,
  ) async {
    if (widget.authMode == StreetBusinessInvoiceAuthMode.companyAdmin) {
      final scope = _strictActiveBookingScopeQuery();
      if (scope == null) return null;
      final auth = await resolveCompanyOwnerAuthHeaders();
      if (auth.mode == CompanyOwnerAuthMode.none) return null;
      final uri = Uri.parse('$kBookingBaseUrl$path').replace(
        queryParameters: <String, String>{
          'tenant_id': scope['tenant_id']!,
          'company_id': scope['company_id']!,
        },
      );
      return (
        uri: uri,
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          ...auth.headers,
        },
      );
    }
    // Driver mode: strict driver scope + driver session bearer.
    final scope = _strictActiveBookingScopeQuery();
    final token = (activeDriverSessionNotifier.value?.driverSessionToken ?? '')
        .trim();
    if (scope == null || token.isEmpty) return null;
    final uri = Uri.parse('$kBookingBaseUrl$path').replace(
      queryParameters: <String, String>{
        'tenant_id': scope['tenant_id']!,
        'company_id': scope['company_id']!,
      },
    );
    return (
      uri: uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
  }

  Future<StreetInvoicePostResult> _postInvoice(
    Map<String, dynamic> body,
  ) async {
    try {
      final req = await _authedRequest(
        '/company/bookings/${Uri.encodeComponent(widget.bookingId)}'
        '/request-business-invoice',
      );
      if (req == null) {
        return StreetInvoicePostResult(
          statusCode: 401,
          errorToken:
              widget.authMode == StreetBusinessInvoiceAuthMode.companyAdmin
              ? 'company_session_required'
              : 'driver_session_required',
        );
      }
      final res = await http
          .post(req.uri, headers: req.headers, body: jsonEncode(body))
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
      return const StreetInvoicePostResult(statusCode: null);
    }
  }

  Future<StreetInvoiceDocsResult> _fetchDocuments() async {
    try {
      final req = await _authedRequest(
        '/company/bookings/${Uri.encodeComponent(widget.bookingId)}/documents',
      );
      if (req == null) return const StreetInvoiceDocsResult();
      final res = await http
          .get(req.uri, headers: req.headers)
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

  /// Lightweight PDF endpoint probe — status only, never treats a 404 as a
  /// hard error (that means "still preparing").
  Future<StreetInvoicePdfProbeResult> _probePdf() async {
    try {
      final scope = _strictActiveBookingScopeQuery();
      if (scope == null) {
        return const StreetInvoicePdfProbeResult(statusCode: 401, failed: false);
      }
      Map<String, String> headers;
      if (widget.authMode == StreetBusinessInvoiceAuthMode.companyAdmin) {
        final auth = await resolveCompanyOwnerAuthHeaders(json: false);
        if (auth.mode == CompanyOwnerAuthMode.none) {
          return const StreetInvoicePdfProbeResult(
            statusCode: 401,
            failed: false,
          );
        }
        headers = <String, String>{
          'Accept': 'application/pdf',
          ...auth.headers,
        };
      } else {
        final token =
            (activeDriverSessionNotifier.value?.driverSessionToken ?? '')
                .trim();
        if (token.isEmpty) {
          return const StreetInvoicePdfProbeResult(
            statusCode: 401,
            failed: false,
          );
        }
        headers = <String, String>{
          'Accept': 'application/pdf',
          'Authorization': 'Bearer $token',
        };
      }
      final uri = Uri.parse(
        '$kBookingBaseUrl/bookings/${Uri.encodeComponent(widget.bookingId)}/invoice/pdf',
      ).replace(
        queryParameters: <String, String>{
          'tenant_id': scope['tenant_id']!,
          'company_id': scope['company_id']!,
        },
      );
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));
      return StreetInvoicePdfProbeResult(statusCode: res.statusCode);
    } catch (_) {
      return const StreetInvoicePdfProbeResult(failed: true);
    }
  }

  /// Short, non-reversible mask of a booking id for diagnostics (no full id).
  static String _maskInvoiceBookingRef(String bookingId) {
    final id = bookingId.trim();
    if (id.isEmpty) return '-';
    if (id.length <= 6) return '${id.substring(0, 1)}***';
    return '${id.substring(0, 4)}***${id.substring(id.length - 2)}';
  }

  void _logInvoiceUiPhase(String phase) {
    // Bounded diagnostics only — never logs buyer PII or tokens.
    debugPrint(
      '[STREET_INVOICE_UI] phase=$phase '
      'booking=${_maskInvoiceBookingRef(widget.bookingId)} '
      'authMode=${widget.authMode.name} '
      'hasExistingInvoice=${_controller.hasIssuedInvoice} '
      'actionVisible=true',
    );
  }

  Future<void> _openForm() async {
    // Opening the form is a pure UI action: it mutates NO invoice state, sets
    // no in-flight/submit flag and performs no server create. The action stays
    // logically available underneath the modal.
    _logInvoiceUiPhase('form_open');
    final input = await showStreetBusinessInvoiceForm(
      context: context,
      theme: streetInvoiceThemeFromDriverPalette(widget.palette),
      language: appLanguageNotifier.value,
      isPaidBooking: widget.isPaidBooking,
      initial: widget.initialBuyer,
    );
    if (input == null || !mounted) {
      // Cancel / dismiss: no submit, no state mutation — the request action
      // remains exactly as it was (available or existingInvoice).
      if (mounted) _logInvoiceUiPhase('form_cancel');
      return;
    }
    await _controller.submit(input);
  }

  void _openDetail() {
    unawaited(
      showStreetInvoiceDetailSheet(
        context: context,
        theme: streetInvoiceThemeFromDriverPalette(widget.palette),
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

  Future<void> _viewInvoicePdf() async {
    if (!_controller.pdfAvailability.canViewOrShare) {
      await _controller.refreshStatus();
      if (!mounted || !_controller.pdfAvailability.canViewOrShare) return;
    }
    await _ReceiptPdfActionRunner.previewInvoicePdf(
      context: context,
      item: widget.tripItem,
    );
  }

  Future<void> _shareInvoicePdf() async {
    if (!_controller.pdfAvailability.canViewOrShare) {
      await _controller.refreshStatus();
      if (!mounted || !_controller.pdfAvailability.canViewOrShare) return;
    }
    await _ReceiptPdfActionRunner.shareInvoicePdf(
      context: context,
      item: widget.tripItem,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, language, _) {
        // Embedded in the Payment card — no second surface/card wrapper.
        return StreetBusinessInvoiceActionView(
          controller: _controller,
          theme: streetInvoiceThemeFromDriverPalette(widget.palette),
          language: language,
          onRequest: _openForm,
          onView: _openDetail,
          showBillitAndPeppol: true,
          receiptPaymentStyle: true,
          onViewPdf: _controller.hasIssuedInvoice
              ? () => unawaited(_viewInvoicePdf())
              : null,
          onSharePdf: _controller.hasIssuedInvoice
              ? () => unawaited(_shareInvoicePdf())
              : null,
        );
      },
    );
  }
}
