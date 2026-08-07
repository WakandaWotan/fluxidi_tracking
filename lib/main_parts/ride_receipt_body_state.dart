part of '../main.dart';

/// PAYMENT-AUTH-P0-1: thrown by `_persistInCarPayment` when the booking
/// worker rejects an in-car mark-paid call with HTTP 401 (missing/expired
/// driver or company-owner session). Distinguished from other backend
/// failures so the UI can show a truthful "sign in again" message instead of
/// a generic payment-failed message.
class _InCarPaymentAuthRequiredException implements Exception {
  const _InCarPaymentAuthRequiredException();
}

/// Process-wide sticky memo of POSITIVE receipt eligibility verdicts (keyed by
/// canonical booking id). STREET-BUSINESS-INVOICE-RECEIPT-UX-1C: the volatile
/// `driverRideScopeActiveDriverIdOverride` (the effective/preview driver id) is
/// cleared whenever the driver UI surface deactivates — e.g. while a form modal
/// is pushed or after leaving the receipt — which transiently collapses the
/// auth context in company-admin mode. Sharing one memo lets a confirmed
/// completed street ride keep its Payment slot across form open/cancel and
/// receipt re-entry. The memo logic lives in the pure support library.
final StreetInvoiceEligibilityMemo _streetInvoiceEligibilityMemo =
    StreetInvoiceEligibilityMemo();

class _RideReceiptBodyState extends State<_RideReceiptBody> {
  _ReceiptPaymentStatus _paymentStatus = _ReceiptPaymentStatus.pending;

  /// Set by the embedded street business-invoice action when an invoice is
  /// known for this completed street ride. Used so Payment status does not
  /// fall back to a misleading bare "Unpaid" while the ride is on invoice.
  bool _hasStreetBusinessInvoice = false;
  bool _streetBusinessInvoicePaid = false;

  /// RELEASE-P0-MOLLIE-STREET-CHECKOUT-1: true while the "Online betalen"
  /// start request is in flight. Drives the bounded (~25s) button spinner;
  /// never left `true` indefinitely.
  bool _mollieCheckoutLoading = false;

  /// MOLLIE-OPEN-PAYMENT-RECOVERY-P0: last known open hosted-checkout recovery
  /// info (from 409 conflict or recovery API). While [isPendingOwner], QR /
  /// cash / Tap to Pay / new checkout are blocked.
  MollieOpenPaymentRecoveryInfo? _openMollieRecovery;
  bool _mollieRecoveryBusy = false;

  /// TAP-TO-PAY-DRIVER-UI-1: Mollie POS / Tap to Pay capability + in-flight
  /// guard. Capability is loaded from the driver-safe booking-worker probe;
  /// phone and tablet share the same logical path id.
  bool _tapToPayCapabilityLoaded = false;
  bool _tapToPayAvailable = false;
  bool _tapToPayInFlight = false;
  String? _tapToPayStatusMessageKey;
  final TapToPayStartGuard _tapToPayStartGuard = TapToPayStartGuard();

  /// Raw `/pay/status` payload captured on the poll attempt that first
  /// reported `paid`, used to enrich the authoritative-fields merge when the
  /// live booking GET fallback is unavailable.
  Map<String, dynamic>? _mollieStreetCheckoutPollPaidData;

  /// Cached Booking Worker record used to confirm street-ride identity when
  /// Tracking `/trips/history` omitted `source` (summarizeTrip strips it).
  Map<String, dynamic>? _streetInvoiceLookupBooking;
  bool _streetInvoiceLookupInFlight = false;
  bool _streetInvoiceLookupFailed = false;
  String? _streetInvoiceLookupBookingId;
  String? _streetInvoiceResolvedBookingId;

  /// Resolved chauffeur palette for the current build pass. Set inside the
  /// outer [ValueListenableBuilder] in [build] before any helper widgets that
  /// read it (e.g. [_receiptRow], [_sectionTitle], [_paymentSection],
  /// [_receiptActionsSection]) are constructed. The default initialises to
  /// Night Gold so any (currently non-existent) call path outside [build]
  /// still has a defined palette and we never NPE.
  DriverThemePalette _palette = paletteForDriverTheme(
    DriverThemeVariant.nightGold,
  );

  /// Mirrors the active driver-theme listenable: when the host (Driver
  /// History) supplies one we follow it, otherwise we fall back to the
  /// global standalone notifier so existing callers (e.g. compliance
  /// register) keep working unchanged.
  ValueListenable<DriverThemeVariant> get _receiptThemeListenable =>
      widget.driverThemeListenable ?? driverThemeNotifier;

  _TripHistoryItem get item => widget.item;

  void _setReceiptScopeAssignedAliasesIfEmpty(
    Map<String, dynamic> target, {
    String? driverId,
    String? vehicleId,
  }) {
    void setPairIfEmpty(String snakeKey, String camelKey, String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      final existingSnake = target[snakeKey]?.toString().trim() ?? '';
      final existingCamel = target[camelKey]?.toString().trim() ?? '';
      if (existingSnake.isNotEmpty || existingCamel.isNotEmpty) return;
      target[snakeKey] = trimmed;
      target[camelKey] = trimmed;
    }

    final driver = (driverId ?? '').trim();
    if (driver.isNotEmpty) {
      setPairIfEmpty('assigned_driver_id', 'assignedDriverId', driver);
    }
    final vehicle = (vehicleId ?? '').trim();
    if (vehicle.isNotEmpty) {
      setPairIfEmpty('assigned_vehicle_id', 'assignedVehicleId', vehicle);
    }
  }

  Map<String, dynamic> _driverScopeBookingViewForReceipt() {
    final map = <String, dynamic>{...item.bookingDetails};
    final bookingId = (item.bookingId ?? '').trim();
    if (bookingId.isNotEmpty) {
      map['booking_id'] = bookingId;
      map['bookingId'] = bookingId;
    }
    if (map['booking'] is! Map) {
      map['booking'] = <String, dynamic>{...item.bookingDetails};
    }
    final driverId = item.driverId.trim();
    final vehicleId = (item.vehicleId ?? '').trim();
    if (vehicleId.isNotEmpty) {
      map['vehicle_id'] = vehicleId;
      map['vehicleId'] = vehicleId;
    }
    if (driverId.isNotEmpty) {
      map['driver_id'] = driverId;
      map['driverId'] = driverId;
    }
    _setReceiptScopeAssignedAliasesIfEmpty(
      map,
      driverId: driverId,
      vehicleId: vehicleId,
    );
    final nestedBooking = map['booking'];
    if (nestedBooking is Map) {
      final nested = Map<String, dynamic>.from(nestedBooking);
      _setReceiptScopeAssignedAliasesIfEmpty(
        nested,
        driverId: driverId,
        vehicleId: vehicleId,
      );
      map['booking'] = nested;
    }
    return map;
  }

  bool _guardDriverReceiptOperation({required String action}) {
    final booking = _driverScopeBookingViewForReceipt();
    final allowed = _canActiveDriverOperateBooking(booking);
    if (allowed) return true;
    final bookingId =
        _bookingScopeFirstText(booking, const [
          ['booking_id'],
          ['bookingId'],
          ['id'],
          ['booking', 'booking_id'],
          ['booking', 'bookingId'],
        ]) ??
        'unknown';
    final assignedDriverId = _bookingScopeAssignedDriverId(booking) ?? '';
    final assignedVehicleId = _bookingScopeAssignedVehicleId(booking) ?? '';
    debugPrint(
      '[DRIVER_SCOPE][BLOCK] action=$action booking_id=$bookingId assigned_driver_id=$assignedDriverId assigned_vehicle_id=$assignedVehicleId active_driver_id=${_resolvedActiveDriverIdForScope()} active_vehicle_id=${_activeDriverSessionVehicleIdForScope()} allowed=false',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_driverOwnershipBlockedMessage())));
    }
    return false;
  }

  void _showMissingStrictReceiptPaymentScopeSnackbar(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Backend synchronisatie vereist een actieve bedrijfssessie. Herkoppel of herstel eerst uw bedrijf.',
        ),
      ),
    );
  }

  Map<String, String>? _strictReceiptPaymentScopeForMutation({
    required BuildContext context,
    required String action,
    bool showUx = true,
  }) {
    final strictScope = _strictActiveBookingScopeQuery();
    if (strictScope != null) return strictScope;
    debugPrint(
      '[RECEIPT_PAYMENT_SCOPE][BLOCK] reason=missing_strict_company_scope action=$action',
    );
    if (showUx) _showMissingStrictReceiptPaymentScopeSnackbar(context);
    return null;
  }

  @override
  void initState() {
    super.initState();
    _paymentStatus = _initialPaymentStatus();
    unawaited(_resolveReceiptPaymentStatus());
    unawaited(_ensureStreetBusinessInvoiceEligibilityResolved());
    unawaited(_refreshTapToPayCapability());
    _logStreetInvoiceReentry(phase: 'receipt_open');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final action = widget.initialAction;
      if (action != null) {
        unawaited(_runInitialAction(context, action));
      }
    });
  }

  @override
  void didUpdateWidget(covariant _RideReceiptBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId = (oldWidget.item.bookingId ?? '').trim();
    final newId = (widget.item.bookingId ?? '').trim();
    if (!shouldResetOpenMollieRecoveryForBookingChange(
      previousBookingId: oldId,
      nextBookingId: newId,
    )) {
      return;
    }
    // Different receipt reusing the same State object: drop all stale per-
    // booking lookup/invoice/payment-owner state and re-resolve from scratch.
    // A previous receipt's open-Mollie recovery must never block the new ride.
    _streetInvoiceLookupBooking = null;
    _streetInvoiceLookupBookingId = null;
    _streetInvoiceLookupInFlight = false;
    _streetInvoiceLookupFailed = false;
    _streetInvoiceResolvedBookingId = null;
    _hasStreetBusinessInvoice = false;
    _streetBusinessInvoicePaid = false;
    _tapToPayCapabilityLoaded = false;
    _tapToPayAvailable = false;
    _tapToPayInFlight = false;
    _tapToPayStatusMessageKey = null;
    _openMollieRecovery = null;
    _mollieRecoveryBusy = false;
    _mollieCheckoutLoading = false;
    unawaited(_ensureStreetBusinessInvoiceEligibilityResolved());
    unawaited(_refreshTapToPayCapability());
    _logStreetInvoiceReentry(phase: 'receipt_reentry');
  }

  Future<void> _refreshTapToPayCapability() async {
    // Same logical path on phone and tablet — form factor never gates.
    assert(
      tapToPayLogicalPathId(isTablet: false) ==
          tapToPayLogicalPathId(isTablet: true),
    );
    try {
      final scope = _strictActiveBookingScopeQuery();
      final raw = await fetchDriverMollieTerminalCapability(
        tenantId: scope?['tenant_id'],
        companyId: scope?['company_id'],
      );
      final status = resolveTapToPayCapabilityStatus(raw);
      final available = shouldShowTapToPayAction(status);
      if (!mounted) return;
      setState(() {
        _tapToPayCapabilityLoaded = true;
        _tapToPayAvailable = available;
      });
      debugPrint(
        '[TAP_TO_PAY][CAPABILITY] available=$available '
        'status=${status.name} path=${tapToPayLogicalPathId(isTablet: false)}',
      );
    } catch (e) {
      debugPrint('[TAP_TO_PAY][CAPABILITY][ERROR] $e');
      if (!mounted) return;
      setState(() {
        _tapToPayCapabilityLoaded = true;
        _tapToPayAvailable = false;
      });
    }
  }

  Future<void> _startTapToPay(BuildContext context) async {
    if (_tapToPayInFlight || _tapToPayStartGuard.inFlight) return;
    if (!_tapToPayAvailable) return;
    if (!_guardDriverReceiptOperation(action: 'tap_to_pay')) return;

    // MOLLIE-OPEN-PAYMENT-RECOVERY-P0: never start Tap to Pay while a hosted
    // Mollie checkout may still settle.
    if (_openMollieBlocksFallback) {
      final choice = await _showOpenMollieRecoveryDialog(context);
      if (!context.mounted) return;
      if (choice != null && choice != MollieOpenPaymentRecoveryChoice.dismiss) {
        await _runOpenMollieRecoveryAction(context, choice: choice);
      }
      return;
    }

    final strictScope = _strictReceiptPaymentScopeForMutation(
      context: context,
      action: 'tap_to_pay',
    );
    if (strictScope == null) return;

    final bookingId = (item.bookingId ?? '').trim();
    if (bookingId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_receiptText('bookingIdMissing'))));
      return;
    }

    final maskedRef = _safeRefPreview(bookingId);
    final started = await _tapToPayStartGuard.runOnce(() async {
      if (!mounted) return false;
      setState(() {
        _tapToPayInFlight = true;
        _tapToPayStatusMessageKey = 'tapToPayStarting';
      });

      // Never send amount — server resolves planned fixed price / street fare.
      final start = await startDriverMollieTerminalPayment(
        bookingId: bookingId,
        legId: _operationalLegIdForReceipt(),
        legType: _operationalLegTypeTokenForReceipt(),
        tenantId: strictScope['tenant_id'],
        companyId: strictScope['company_id'],
      );
      final httpCode = (start['http_code'] as num?)?.toInt() ?? 0;
      final ok = start['ok'] == true;
      final paymentId = (start['payment_id'] ?? start['paymentId'] ?? '')
          .toString()
          .trim();
      final status = (start['status'] ?? '').toString();
      final mollieStatus =
          (start['mollie_status'] ?? start['mollieStatus'] ?? '').toString();
      final valid = cardTerminalStartIsValidIntent(
        httpCode: httpCode,
        ok: ok,
        paymentId: paymentId,
        status: status,
        mollieStatus: mollieStatus,
      );
      debugPrint(
        cardTerminalDiagnosticsLine(
          phase: CardTerminalPhase.launch,
          amountCents: 0,
          providerStatus: mollieStatus.isEmpty ? status : mollieStatus,
          paymentWritten: false,
          reason: valid ? 'tap_to_pay_start_ok' : 'tap_to_pay_start_invalid',
        ),
      );
      if (!valid) {
        if (!mounted) return false;
        final recovery = parseMollieOpenPaymentRecovery(
          Map<String, dynamic>.from(start),
          httpCode: httpCode,
        );
        if (recovery != null ||
            manualPaymentBlockedByOpenMollieCheckout(
              httpCode: httpCode,
              decoded: Map<String, dynamic>.from(start),
            )) {
          setState(() {
            _tapToPayInFlight = false;
            _openMollieRecovery = recovery;
            _tapToPayStatusMessageKey = null;
          });
          if (context.mounted) {
            final choice = await _showOpenMollieRecoveryDialog(
              context,
              recovery: recovery,
            );
            if (context.mounted &&
                choice != null &&
                choice != MollieOpenPaymentRecoveryChoice.dismiss) {
              await _runOpenMollieRecoveryAction(context, choice: choice);
            }
          }
          return false;
        }
        setState(() {
          _tapToPayInFlight = false;
          _tapToPayStatusMessageKey = 'cardTerminalRetryOrOther';
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_receiptText('cardTerminalRetryOrOther'))),
          );
        }
        return false;
      }

      if (!mounted) return false;
      setState(() => _tapToPayStatusMessageKey = 'tapToPayWaitingForCard');

      // Bounded poll; only Mollie `paid` (via server reconcile) marks paid.
      const maxAttempts = 40;
      for (var i = 0; i < maxAttempts; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return false;
        if (i > 0 && i % 5 == 0) {
          setState(() => _tapToPayStatusMessageKey = 'tapToPayCheckingStatus');
        }
        final poll = await pollDriverMollieTerminalPaymentStatus(
          bookingId: bookingId,
          paymentId: paymentId,
          legId: _operationalLegIdForReceipt(),
          tenantId: strictScope['tenant_id'],
          companyId: strictScope['company_id'],
        );
        final pollHttp = (poll['http_code'] as num?)?.toInt() ?? 0;
        final providerStatus =
            (poll['mollie_status'] ?? poll['mollieStatus'] ?? '').toString();
        final outcome = classifyCardTerminalProviderStatus(
          providerStatus: providerStatus,
          httpCode: pollHttp >= 400 ? pollHttp : null,
        );
        final serverPaid = poll['paid'] == true;
        final paymentWritten = poll['payment_written'] == true;
        debugPrint(
          cardTerminalDiagnosticsLine(
            phase: CardTerminalPhase.callback,
            amountCents: 0,
            providerStatus: providerStatus,
            paymentWritten: paymentWritten || serverPaid,
            reason: cardTerminalOutcomeReason(outcome),
          ),
        );

        if (serverPaid || cardTerminalShouldWritePaid(outcome)) {
          if (!mounted) return true;
          setState(() {
            _tapToPayStatusMessageKey = 'tapToPaySucceeded';
            _paymentStatus = _ReceiptPaymentStatus.paid;
          });
          final fields = await _fetchAuthoritativePaymentFields(bookingId);
          if (mounted && fields != null && fields.isNotEmpty) {
            _mergePaymentFieldsIntoReceiptDetails(fields);
            setState(() => _paymentStatus = _ReceiptPaymentStatus.paid);
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_receiptText('tapToPaySucceeded'))),
            );
          }
          return true;
        }

        if (cardTerminalIsTerminalOutcome(outcome)) {
          final msgKey =
              cardTerminalUserMessageKey(outcome) ?? 'cardTerminalRetryOrOther';
          if (!mounted) return false;
          setState(() {
            _tapToPayInFlight = false;
            _tapToPayStatusMessageKey = msgKey;
          });
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_receiptText(msgKey))),
            );
          }
          // Explicitly keep unpaid — never invent paid on cancel/fail/return.
          return false;
        }
      }

      if (!mounted) return false;
      setState(() {
        _tapToPayInFlight = false;
        _tapToPayStatusMessageKey = 'tapToPayCheckingStatus';
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('tapToPayCheckingStatus'))),
        );
      }
      debugPrint(
        '[TAP_TO_PAY][POLL_TIMEOUT] booking=$maskedRef unpaid=true '
        '(backend reconcile may still mark paid later)',
      );
      return false;
    });

    if (started == null) {
      // Double-tap ignored.
      return;
    }
    if (mounted) {
      setState(() => _tapToPayInFlight = false);
    }
  }

  /// Bounded re-entry diagnostics (no PII / no tokens). Logged on receipt open
  /// and when the receipt is reused for a different booking id.
  void _logStreetInvoiceReentry({required String phase}) {
    final e = _resolveStreetBusinessInvoiceReceiptEligibility();
    final decision = _resolveStreetInvoiceSlotDecision();
    debugPrint(
      '[STREET_INVOICE_UI] phase=$phase '
      'booking=${_safeRefPreview(e.canonicalBookingId)} '
      'eligibility=${e.reason} '
      'authMode=${decision.authMode.name} '
      'loadState=${decision.kind.name} '
      'hasExistingInvoice=$_hasStreetBusinessInvoice '
      'visible=${decision.kind == StreetInvoiceSlotKind.available} '
      'reason=${decision.reason}',
    );
  }

  Future<void> _runInitialAction(
    BuildContext context,
    _ReceiptQuickAction action,
  ) async {
    try {
      switch (action) {
        case _ReceiptQuickAction.viewPdf:
          await _viewReceiptPdf(context);
          break;
        case _ReceiptQuickAction.sharePdf:
          await _shareReceiptPdf(context);
          break;
        case _ReceiptQuickAction.whatsappPdf:
          await _shareReceiptPdfViaWhatsApp(context);
          break;
        case _ReceiptQuickAction.emailPdf:
          await _shareReceiptPdfViaEmail(context);
          break;
        case _ReceiptQuickAction.printPdf:
          await _printReceiptPdf(context);
          break;
      }
    } finally {
      if (widget.autoPopAfterInitialAction && context.mounted) {
        Navigator.of(context).maybePop();
      }
    }
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(dt.day)}-${two(dt.month)}-${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  String _formatWait(int seconds) {
    if (seconds <= 0) return '0 min';
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    if (min <= 0) return '${sec}s';
    if (sec == 0) return '$min min';
    return '$min min ${sec}s';
  }

  bool get _isPlannedReceipt => item.kind.toLowerCase().trim() == 'planned';

  String? _detailText(String key) {
    final text = item.detail(key);
    return text == null || text == 'null' ? null : text;
  }

  _ReceiptPaymentStatus _initialPaymentStatus() {
    final raw = _firstDetailPathText(const [
      ['payment_status'],
      ['paymentStatus'],
      ['booking', 'payment_status'],
      ['booking', 'paymentStatus'],
      ['record', 'payment_status'],
      ['record', 'paymentStatus'],
      ['record', 'booking', 'payment_status'],
      ['record', 'booking', 'paymentStatus'],
      ['mollie', 'status'],
      ['record', 'mollie', 'status'],
    ])?.toLowerCase().trim();
    if (raw == 'paid' || raw == 'settled' || raw == 'confirmed') {
      return _ReceiptPaymentStatus.paid;
    }
    if (raw == 'open' || raw == 'pending' || raw == 'authorized') {
      return _ReceiptPaymentStatus.sent;
    }
    return _ReceiptPaymentStatus.pending;
  }

  _ReceiptPaymentStatus _paymentStatusFromRaw(String? raw) {
    final normalized = raw?.toLowerCase().trim();
    if (normalized == 'paid' ||
        normalized == 'settled' ||
        normalized == 'confirmed') {
      return _ReceiptPaymentStatus.paid;
    }
    if (normalized == 'open' ||
        normalized == 'pending' ||
        normalized == 'authorized') {
      return _ReceiptPaymentStatus.sent;
    }
    return _ReceiptPaymentStatus.pending;
  }

  /// Returns `true` when [value] (string or bool) signals a confirmed paid
  /// state. Mirrors `isComplianceReceiptPaidStatus` in
  /// `compliance_register_receipt_bridge.dart` so the receipt UI's
  /// "effective paid" detection agrees with the hydration merge guards.
  bool _isPaidStatusValue(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty) return false;
    return text == 'paid' ||
        text == 'settled' ||
        text == 'confirmed' ||
        text == 'completed' ||
        text == 'success';
  }

  /// Comprehensive paid-state detection for the receipt UI. Returns `true`
  /// when ANY of the following carries a paid signal:
  ///   - in-memory `_paymentStatus` is already paid
  ///   - any `payment_status` / `paymentStatus` / `payment_state` alias under
  ///     `booking_details`, `booking`, `record.*`, or root JSON
  ///   - `payment.paid` / `paid` / `is_paid` boolean alias
  ///   - `paid_at` non-empty
  /// Used to hide payment action buttons (`Pay by QR`, `Cash received`,
  /// `Paid by card terminal`) for compliance-paid Local Ride Register rows
  /// and to defend `_resolveReceiptPaymentStatus` against being downgraded
  /// by a still-`pending` booking-worker record.
  bool _isEffectiveReceiptPaid() {
    if (_paymentStatus == _ReceiptPaymentStatus.paid) return true;

    const statusAliasPaths = <List<String>>[
      ['payment_status'],
      ['paymentStatus'],
      ['payment_state'],
      ['paymentState'],
      ['paid'],
      ['is_paid'],
      ['isPaid'],
      ['booking', 'payment_status'],
      ['booking', 'paymentStatus'],
      ['booking', 'payment_state'],
      ['booking', 'paymentState'],
      ['booking', 'paid'],
      ['booking', 'is_paid'],
      ['booking', 'isPaid'],
      ['record', 'payment_status'],
      ['record', 'paymentStatus'],
      ['record', 'payment_state'],
      ['record', 'paymentState'],
      ['record', 'paid'],
      ['record', 'is_paid'],
      ['record', 'isPaid'],
      ['record', 'booking', 'payment_status'],
      ['record', 'booking', 'paymentStatus'],
      ['record', 'booking', 'payment_state'],
      ['record', 'booking', 'paymentState'],
      ['record', 'booking', 'paid'],
      ['record', 'booking', 'is_paid'],
      ['record', 'booking', 'isPaid'],
      ['payment', 'status'],
      ['payment', 'paid'],
      ['booking', 'payment', 'status'],
      ['booking', 'payment', 'paid'],
      ['record', 'payment', 'status'],
      ['record', 'payment', 'paid'],
      ['record', 'booking', 'payment', 'status'],
      ['record', 'booking', 'payment', 'paid'],
      ['mollie', 'status'],
      ['record', 'mollie', 'status'],
    ];
    for (final path in statusAliasPaths) {
      if (_isPaidStatusValue(_detailAt(path))) return true;
    }

    const paidAtPaths = <List<String>>[
      ['paid_at'],
      ['paidAt'],
      ['booking', 'paid_at'],
      ['booking', 'paidAt'],
      ['record', 'paid_at'],
      ['record', 'paidAt'],
      ['record', 'booking', 'paid_at'],
      ['record', 'booking', 'paidAt'],
    ];
    for (final path in paidAtPaths) {
      final text = _cleanContactText(_detailAt(path));
      if (text != null && text.isNotEmpty && text != '—') return true;
    }
    return false;
  }

  String? _mapText(Map<String, dynamic> map, String key) {
    final value = map[key];
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text.toLowerCase() == 'null')
      return null;
    return text;
  }

  String? _historyTopLevelPaymentStatus() {
    return _mapText(item.bookingDetails, 'payment_status') ??
        _mapText(item.bookingDetails, 'paymentStatus');
  }

  String? _historyNestedPaymentStatus() {
    return _firstDetailPathText(const [
      ['booking', 'payment_status'],
      ['booking', 'paymentStatus'],
      ['booking_details', 'payment_status'],
      ['booking_details', 'paymentStatus'],
      ['record', 'payment_status'],
      ['record', 'paymentStatus'],
      ['record', 'booking', 'payment_status'],
      ['record', 'booking', 'paymentStatus'],
      ['mollie', 'status'],
      ['record', 'mollie', 'status'],
    ]);
  }

  void _mergePaymentFieldsIntoReceiptDetails(Map<String, dynamic> fields) {
    for (final entry in fields.entries) {
      final value = entry.value?.toString().trim();
      if (value == null || value.isEmpty || value.toLowerCase() == 'null')
        continue;
      item.bookingDetails[entry.key] = entry.value;
    }
    final bookingMap = item.bookingDetails['booking'];
    if (bookingMap is Map) {
      final mutableBooking = Map<String, dynamic>.from(bookingMap);
      if (fields['payment_status'] != null)
        mutableBooking['payment_status'] = fields['payment_status'];
      if (fields['paymentStatus'] != null)
        mutableBooking['paymentStatus'] = fields['paymentStatus'];
      if (fields['paid_at'] != null)
        mutableBooking['paid_at'] = fields['paid_at'];
      if (fields['paidAt'] != null) mutableBooking['paidAt'] = fields['paidAt'];
      if (fields['payment_provider'] != null)
        mutableBooking['payment_provider'] = fields['payment_provider'];
      if (fields['paymentProvider'] != null)
        mutableBooking['paymentProvider'] = fields['paymentProvider'];
      if (fields['payment_id'] != null)
        mutableBooking['payment_id'] = fields['payment_id'];
      if (fields['paymentId'] != null)
        mutableBooking['paymentId'] = fields['paymentId'];
      if (fields['payment_method'] != null)
        mutableBooking['payment_method'] = fields['payment_method'];
      if (fields['paymentMethod'] != null)
        mutableBooking['paymentMethod'] = fields['paymentMethod'];
      if (fields['payment_source'] != null)
        mutableBooking['payment_source'] = fields['payment_source'];
      if (fields['paymentSource'] != null)
        mutableBooking['paymentSource'] = fields['paymentSource'];
      item.bookingDetails['booking'] = mutableBooking;
    }
  }

  void _appendPaymentUpdateLedgerIfPaid({
    required Map<String, dynamic> fields,
    required String method,
    required String source,
    bool? backendConfirmed,
  }) {
    if (!_isPaidPaymentUpdate(fields)) return;
    final record = _buildCompliancePaymentUpdateLedgerRecord(
      item: item,
      paymentFields: fields,
      method: method,
      source: source,
      eventAt: DateTime.now(),
      backendConfirmed: backendConfirmed,
    );
    unawaited(_writeComplianceLedgerRecord(record: record));
  }

  Map<String, dynamic>? _extractAuthoritativePaymentFields(
    Map<String, dynamic> root,
  ) {
    Map<String, dynamic> asMap(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    String? text(dynamic value) {
      final s = value?.toString().trim();
      if (s == null || s.isEmpty || s.toLowerCase() == 'null') return null;
      return s;
    }

    final data = asMap(root['data']);
    final record = asMap(root['record']);
    final booking = asMap(root['booking']);
    final recordBooking = asMap(record['booking']);
    final dataRecord = asMap(data['record']);
    final dataBooking = asMap(data['booking']);
    final dataRecordBooking = asMap(dataRecord['booking']);

    String? firstHit(String snake, String camel, Map<String, dynamic> map) {
      final hit = text(map[snake] ?? map[camel]);
      return hit;
    }

    final paymentStatus =
        firstHit('payment_status', 'paymentStatus', root) ??
        firstHit('payment_status', 'paymentStatus', record) ??
        firstHit('payment_status', 'paymentStatus', recordBooking) ??
        firstHit('payment_status', 'paymentStatus', booking) ??
        firstHit('payment_status', 'paymentStatus', data) ??
        firstHit('payment_status', 'paymentStatus', dataRecord) ??
        firstHit('payment_status', 'paymentStatus', dataBooking) ??
        firstHit('payment_status', 'paymentStatus', dataRecordBooking);
    final paidAt = text(
      root['paid_at'] ??
          root['paidAt'] ??
          record['paid_at'] ??
          record['paidAt'] ??
          recordBooking['paid_at'] ??
          recordBooking['paidAt'] ??
          booking['paid_at'] ??
          booking['paidAt'] ??
          data['paid_at'] ??
          data['paidAt'] ??
          dataRecord['paid_at'] ??
          dataRecord['paidAt'] ??
          dataBooking['paid_at'] ??
          dataBooking['paidAt'] ??
          dataRecordBooking['paid_at'] ??
          dataRecordBooking['paidAt'],
    );
    final paymentProvider = text(
      root['payment_provider'] ??
          root['paymentProvider'] ??
          record['payment_provider'] ??
          record['paymentProvider'] ??
          booking['payment_provider'] ??
          booking['paymentProvider'] ??
          data['payment_provider'] ??
          data['paymentProvider'] ??
          dataRecord['payment_provider'] ??
          dataRecord['paymentProvider'] ??
          dataBooking['payment_provider'] ??
          dataBooking['paymentProvider'],
    );
    final paymentId = text(
      root['payment_id'] ??
          root['paymentId'] ??
          record['payment_id'] ??
          record['paymentId'] ??
          booking['payment_id'] ??
          booking['paymentId'] ??
          data['payment_id'] ??
          data['paymentId'] ??
          dataRecord['payment_id'] ??
          dataRecord['paymentId'] ??
          dataBooking['payment_id'] ??
          dataBooking['paymentId'],
    );
    final paymentMethod = text(
      root['payment_method'] ??
          root['paymentMethod'] ??
          record['payment_method'] ??
          record['paymentMethod'] ??
          booking['payment_method'] ??
          booking['paymentMethod'] ??
          data['payment_method'] ??
          data['paymentMethod'] ??
          dataRecord['payment_method'] ??
          dataRecord['paymentMethod'] ??
          dataBooking['payment_method'] ??
          dataBooking['paymentMethod'],
    );
    final paymentSource = text(
      root['payment_source'] ??
          root['paymentSource'] ??
          record['payment_source'] ??
          record['paymentSource'] ??
          booking['payment_source'] ??
          booking['paymentSource'] ??
          data['payment_source'] ??
          data['paymentSource'] ??
          dataRecord['payment_source'] ??
          dataRecord['paymentSource'] ??
          dataBooking['payment_source'] ??
          dataBooking['paymentSource'],
    );

    if (paymentStatus == null &&
        paidAt == null &&
        paymentProvider == null &&
        paymentId == null &&
        paymentMethod == null &&
        paymentSource == null) {
      return null;
    }
    return <String, dynamic>{
      if (paymentStatus != null) ...{
        'payment_status': paymentStatus,
        'paymentStatus': paymentStatus,
      },
      if (paidAt != null) ...{'paid_at': paidAt, 'paidAt': paidAt},
      if (paymentProvider != null) ...{
        'payment_provider': paymentProvider,
        'paymentProvider': paymentProvider,
      },
      if (paymentId != null) ...{
        'payment_id': paymentId,
        'paymentId': paymentId,
      },
      if (paymentMethod != null) ...{
        'payment_method': paymentMethod,
        'paymentMethod': paymentMethod,
      },
      if (paymentSource != null) ...{
        'payment_source': paymentSource,
        'paymentSource': paymentSource,
      },
    };
  }

  String? _paymentMethodFromDetails() {
    return _firstDetailPathText(const [
      ['payment_method'],
      ['paymentMethod'],
      ['booking', 'payment_method'],
      ['booking', 'paymentMethod'],
      ['booking_details', 'payment_method'],
      ['booking_details', 'paymentMethod'],
      ['record', 'payment_method'],
      ['record', 'paymentMethod'],
      ['record', 'booking', 'payment_method'],
      ['record', 'booking', 'paymentMethod'],
    ])?.toLowerCase().trim();
  }

  String? _paymentSourceFromDetails() {
    return _firstDetailPathText(const [
      ['payment_source'],
      ['paymentSource'],
      ['booking', 'payment_source'],
      ['booking', 'paymentSource'],
      ['record', 'payment_source'],
      ['record', 'paymentSource'],
      ['record', 'booking', 'payment_source'],
      ['record', 'booking', 'paymentSource'],
    ])?.toLowerCase().trim();
  }

  bool _methodImpliesPaid(String? method) {
    final m = method?.toLowerCase().trim() ?? '';
    return m == 'cash' || m == 'bancontact' || m == 'qr' || m == 'card';
  }

  Future<Map<String, dynamic>?> _fetchAuthoritativePaymentFields(
    String bookingId,
  ) async {
    try {
      // STREET Mollie converge: company-first status auth (same as
      // PaymentReturnCoordinator / street dialog). Cash/QR mark-paid still
      // uses resolveInCarPaymentAuthHeaders (driver-first) elsewhere.
      final authHeaders = await resolveMollieStreetStatusAuthHeaders();
      if (authHeaders.mode == MollieStreetStatusAuthMode.none) {
        debugPrint(
          '[RECEIPT_PAYMENT][AUTHORITATIVE_GET] status=missing_auth '
          'booking=${_safeRefPreview(bookingId)}',
        );
        return null;
      }
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/bookings/${Uri.encodeComponent(bookingId)}',
      );
      final res = await http
          .get(uri, headers: authHeaders.headers)
          .timeout(const Duration(seconds: 12));
      Map<String, dynamic>? parsed;
      dynamic decoded;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        decoded = jsonDecode(res.body);
        if (decoded is Map) {
          final root = Map<String, dynamic>.from(decoded);
          parsed = _extractAuthoritativePaymentFields(root);
        }
      } else {
        debugPrint(
          '[RECEIPT_PAYMENT][AUTHORITATIVE_GET] status=http_${res.statusCode} '
          'booking=${_safeRefPreview(bookingId)}',
        );
      }
      if (parsed != null && parsed.isNotEmpty) return parsed;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _resolveReceiptPaymentStatus() async {
    final bookingId = (item.bookingId ?? '').trim();
    final historyPaymentStatus = _historyTopLevelPaymentStatus();
    final nestedPaymentStatus = _historyNestedPaymentStatus();

    String? authoritativePaymentStatus;
    String? authoritativePaymentMethod;
    if (bookingId.isNotEmpty) {
      final fields = await _fetchAuthoritativePaymentFields(bookingId);
      if (fields != null && fields.isNotEmpty) {
        _mergePaymentFieldsIntoReceiptDetails(fields);
        authoritativePaymentStatus =
            _mapText(fields, 'payment_status') ??
            _mapText(fields, 'paymentStatus');
        authoritativePaymentMethod =
            _mapText(fields, 'payment_method') ??
            _mapText(fields, 'paymentMethod');
      }
    }

    // STREET-CASH-PAYMENT-RELOAD-P0: authoritative BOOKING_KV status wins;
    // History is fallback only. Confirmed Paid is never downgraded by a
    // stale Unpaid History projection when the booking GET failed.
    final resolved = resolveReceiptReloadPaymentStatusRaw(
      authoritativeStatus: authoritativePaymentStatus,
      historyTopLevelStatus: historyPaymentStatus,
      historyNestedStatus: nestedPaymentStatus,
    );

    final methodFromDetails =
        authoritativePaymentMethod ?? _paymentMethodFromDetails();
    final sourceFromDetails = _paymentSourceFromDetails();
    final markAsPaidFromMethod =
        _methodImpliesPaid(methodFromDetails) &&
        (sourceFromDetails == null ||
            sourceFromDetails.isEmpty ||
            sourceFromDetails == 'in_car');
    // Payment authority guard:
    //   If the compliance / local-register hydrated JSON already declares the
    //   ride paid (via any alias surfaced by `_isEffectiveReceiptPaid`), we
    //   MUST NOT downgrade it just because the booking-worker authoritative
    //   record (or the trip-history projection) hasn't caught up to an
    //   in-vehicle cash / Bancontact settlement yet. Upgrades from unpaid to
    //   paid are still honored.
    final basePaidBeforeAsync = _isEffectiveReceiptPaid();
    final alreadyPaidLocally =
        basePaidBeforeAsync || _paymentStatus == _ReceiptPaymentStatus.paid;
    if (!mounted) return;
    setState(() {
      final fromStatus = _paymentStatusFromRaw(resolved);
      if (shouldRetainConfirmedPaidOnReload(
        alreadyConfirmedPaid: alreadyPaidLocally,
        resolvedRawStatus: resolved,
      )) {
        _paymentStatus = _ReceiptPaymentStatus.paid;
        return;
      }
      if (shouldKeepReceiptPaidMonotonic(
        currentlyPaid: alreadyPaidLocally,
        authoritativeSaysPaid: fromStatus == _ReceiptPaymentStatus.paid,
        authoritativeReadSucceeded: authoritativePaymentStatus != null,
      )) {
        _paymentStatus = _ReceiptPaymentStatus.paid;
        return;
      }
      _paymentStatus =
          markAsPaidFromMethod && fromStatus != _ReceiptPaymentStatus.paid
          ? _ReceiptPaymentStatus.paid
          : fromStatus;
    });
  }

  String? _cleanContactText(dynamic value) {
    if (value == null) return null;
    // Defensive guard: never stringify Map/Iterable nodes. When path lookups
    // land on raw compliance/booking sub-trees (e.g. {label: ''}, {}, lists),
    // Dart's default toString() would surface "{}", "{label: }" or "[]" into
    // receipt UI / PDF fields. Treat those as "no scalar value found" so the
    // resolver can fall back to the next path. Route-aware extraction of
    // {label}/{lat,lon} happens upstream (e.g. _TripHistoryItem._placeLabel
    // and _TripHistoryItem._extractRouteLabel) before reaching this helper.
    if (value is Map || value is Iterable) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return null;
    return text;
  }

  dynamic _detailAt(List<String> path) {
    dynamic current = item.bookingDetails;
    for (final key in path) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        current = null;
        break;
      }
    }
    if (current != null) return current;
    return _rawAt(path);
  }

  dynamic _rawAt(List<String> path) {
    dynamic current = item.rawSource;
    for (final key in path) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  String? _firstDetailPathText(List<List<String>> paths) {
    for (final path in paths) {
      final text = _cleanContactText(_detailAt(path));
      if (text != null) return text;
    }
    return null;
  }

  String? _firstDetailText(List<String> keys) {
    for (final key in keys) {
      final text = _detailText(key);
      if (text != null) return text;
    }
    return null;
  }

  double? _detailDouble(String key) {
    final value = item.bookingDetails[key];
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.'));
  }

  bool _isPositiveAmount(double? value) =>
      value != null && value.isFinite && value > 0;

  double? _effectiveOperationalLegAmount() {
    if (!_isPlannedOperationalLegPaymentItem()) return null;
    final candidates = <double?>[
      item.totalEur,
      _detailDouble('segment_price_eur'),
      _detailDouble('leg_price_incl_vat'),
      _detailDouble('legPriceInclVat'),
    ];
    for (final candidate in candidates) {
      if (_isPositiveAmount(candidate)) return candidate;
    }
    return null;
  }

  /// Resolves the amount used for receipt display and outgoing payment
  /// payloads.
  ///
  /// When [wholeBookingScope] is `true` the caller wants the full booking
  /// total (e.g. EPC SEPA QR amount, booking-worker `/bookings/:id/payment`
  /// payload, payment-zone display, legacy `fluxidi://pay` deep link). For
  /// roundtrip/return-enabled bookings the per-leg `item.totalEur` would
  /// silently undercollect (only the outbound leg amount would be charged),
  /// so booking-level payment surfaces must prefer `booking_total_eur`.
  ///
  /// When [wholeBookingScope] is `false` (default) the historical per-leg
  /// behaviour is preserved: planned operational-leg receipts use the leg
  /// amount, falling back to `booking_total_eur` / `item.totalEur` if no
  /// leg-level amount is available. This keeps the PDF receipt / VAT
  /// breakdown / per-trip `/trip/payment` payload leg-focused.
  double? _receiptTotalAmount({bool wholeBookingScope = false}) {
    if (wholeBookingScope) {
      final pkg = _detailDouble('booking_total_eur');
      if (_isPositiveAmount(pkg)) return pkg;
      return item.totalEur;
    }
    if (_isPlannedReceipt) {
      final legAmount = _effectiveOperationalLegAmount();
      if (_isPositiveAmount(legAmount)) return legAmount;
      // Leg-first business rule: prefer `item.totalEur` (the trip-history
      // leg amount, e.g. €200) over the parent `booking_total_eur`
      // (e.g. €400) so the on-screen Total / PDF total never surfaces the
      // parent booking total as a leg ritbon total.
      if (_ReceiptPdfActionRunner._isLegReceiptItem(item) &&
          _isPositiveAmount(item.totalEur)) {
        return item.totalEur;
      }
      return _detailDouble('booking_total_eur') ?? item.totalEur;
    }
    return item.totalEur;
  }

  /// True when this receipt is a planned operational-leg receipt AND a
  /// positive per-leg amount is available. Used to gate every payment
  /// surface (Amount row, EPC SEPA QR, booking-worker / trip-payment
  /// payloads, legacy deep link) so each leg of a roundtrip booking only
  /// collects its own slice and the customer is never asked to pay the
  /// full booking total twice — once on each leg's receipt.
  bool _useLegAmountForPayment() {
    if (_isPlannedOperationalLegPaymentItem()) {
      return _isPositiveAmount(_effectiveOperationalLegAmount());
    }
    // Leg-first business rule: a ritbon proves ONE operational leg. When
    // the planned-operational-leg gate misses (no leg_id/leg_type/row_key
    // on the item, or the trip-history record already flipped past
    // 'planned' kind) but `_isLegReceiptItem` still fires (leg_type token,
    // -R bookingId, or receipt_total < booking_total), keep the
    // payment-zone amount + EPC SEPA QR amount + booking-worker payment
    // payload scoped to the leg amount rather than silently asking the
    // customer for the parent €400 booking total.
    if (_ReceiptPdfActionRunner._isLegReceiptItem(item)) {
      return _isPositiveAmount(item.totalEur);
    }
    return false;
  }

  /// Authoritative amount to request from the customer for the current
  /// receipt:
  ///   * Operational-leg planned receipts (roundtrip outbound / return
  ///     legs, multi-leg planned legs) → the leg amount.
  ///   * Single-leg planned receipts and direct/non-planned receipts →
  ///     the full booking total via `wholeBookingScope: true`.
  /// Use this for every customer-facing payment surface and outbound
  /// payment payload (EPC QR amount, QR dialog caption, payment-zone
  /// Amount row, `/trip/payment` amount, `/bookings/:id/payment` amount,
  /// legacy `fluxidi://pay` deep link). For the PDF body / share text /
  /// VAT breakdown call `_receiptTotalAmount()` directly to keep the
  /// invoice leg-focused on operational-leg receipts.
  double? _selectedPaymentAmount() {
    if (_useLegAmountForPayment()) {
      return _receiptTotalAmount();
    }
    return _receiptTotalAmount(wholeBookingScope: true);
  }

  String _selectedPaymentScopeLabel() =>
      _useLegAmountForPayment() ? 'leg' : 'whole_booking';

  String _moneyText(double? value) {
    if (value == null) return _receiptText('notAvailable');
    return '€ ${value.toStringAsFixed(2)}';
  }

  /// Formats the receipt total for display.
  ///
  /// Defaults to the per-leg amount on planned operational-leg receipts (used
  /// by the PDF body, share text, and the main "Total" row), matching the
  /// invoice the customer keeps. Pass [wholeBookingScope] = `true` for
  /// booking-level payment surfaces (payment-zone Amount row, QR dialog
  /// caption) so the visible amount aligns with the EPC SEPA QR payload and
  /// the booking-worker `/bookings/:id/payment` payload — preventing silent
  /// undercollection of the return leg on roundtrip bookings.
  String _totalText({bool wholeBookingScope = false}) {
    return _moneyText(
      _receiptTotalAmount(wholeBookingScope: wholeBookingScope),
    );
  }

  String _kmText() {
    final km = item.kmTotal;
    if (km == null) return _receiptText('notAvailable');
    return '${km.toStringAsFixed(2)} km';
  }

  bool _isPlaceholderRouteLabel(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return true;
    if (receiptIsNonAddressRoutePlaceholder(text)) return true;
    final lower = text.toLowerCase();
    if (lower == _receiptText('currentLocation').toLowerCase()) return true;
    // Localized fallback labels from `_sanitizeCustomerFacingRouteLabel` are
    // NOT valid route values — they exist only to fill a void when no actual
    // address could be resolved. Treat them as placeholders so the wider
    // path-based picker can still surface the real requested-booking address.
    if (lower == _receiptStartPointFallback().toLowerCase()) return true;
    if (lower == _receiptStartLocationFallback().toLowerCase()) return true;
    return false;
  }

  /// Detects stringified Map / List literals such as `{}`, `{label: }`,
  /// `{label: , lat: 50.8}` or `[]`. These can sneak in when an upstream
  /// resolver calls `value.toString()` on a Map (e.g. legacy
  /// `_extractRouteLabel` fallback) and must never be shown to the user as
  /// an address.
  bool _looksLikeMapLiteralRoute(String? value) {
    if (value == null) return false;
    final trimmed = value.trim();
    if (trimmed.length < 2) return false;
    final start = trimmed[0];
    final end = trimmed[trimmed.length - 1];
    return (start == '{' && end == '}') || (start == '[' && end == ']');
  }

  /// Resolves a clean route-display String from a value that may be a String,
  /// a Map (`{label,address,formatted_address,name,text,value}`) or `null`.
  /// Returns `null` for placeholders / empty Maps / Iterables. Never calls
  /// `toString()` on a Map or Iterable.
  String? _resolveRouteValueText(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final cleaned = _cleanContactText(value);
      if (cleaned == null) return null;
      if (_isPlaceholderRouteLabel(cleaned)) return null;
      return cleaned;
    }
    if (value is Map) {
      for (final key in const <String>[
        'label',
        'address',
        'formatted_address',
        'formattedAddress',
        'name',
        'text',
        'value',
      ]) {
        final inner = value[key];
        if (inner is String) {
          final cleaned = _cleanContactText(inner);
          if (cleaned == null) continue;
          if (_isPlaceholderRouteLabel(cleaned)) continue;
          return cleaned;
        }
      }
      return null;
    }
    if (value is Iterable) return null;
    final cleaned = _cleanContactText(value);
    if (cleaned == null) return null;
    if (_isPlaceholderRouteLabel(cleaned)) return null;
    return cleaned;
  }

  ({String from, String to}) _resolvedRouteForPdf() {
    final resolved = resolveReceiptRouteAddresses(
      rawSource: item.rawSource,
      bookingDetails: item.bookingDetails,
      origin: item.origin,
      destination: item.destination,
    );
    final from = _sanitizeCustomerFacingRouteLabel(
      resolved.from ?? _receiptText('currentLocation'),
      isFromField: true,
    );
    final to = _sanitizeCustomerFacingRouteLabel(
      resolved.to ?? '-',
      isFromField: false,
    );
    debugPrint(
      '[PDF][ROUTE] fromFound=${resolved.from != null} toFound=${resolved.to != null} source=${resolved.source}',
    );
    return (from: from, to: to);
  }

  ({
    String? name,
    String? phoneRaw,
    String? email,
    List<String> keys,
    String source,
  })
  _resolvePdfContact() {
    String? pick(
      List<List<String>> paths,
      List<String> usedKeys, {
      bool email = false,
    }) {
      for (final path in paths) {
        final text = _cleanContactText(_detailAt(path));
        if (text == null || text.isEmpty) continue;
        final normalized = email ? _validEmail(text) : text;
        if (normalized == null || normalized.isEmpty) continue;
        usedKeys.add(path.join('.'));
        return normalized;
      }
      return null;
    }

    final keys = <String>[];
    final normalizedName = _cleanContactText(item.customerName);
    final normalizedPhone = _cleanContactText(item.customerPhone);
    final normalizedEmail = _validEmail(item.customerEmail);
    if (normalizedName != null) keys.add('normalized.customerName');
    if (normalizedPhone != null) keys.add('normalized.customerPhone');
    if (normalizedEmail != null) keys.add('normalized.customerEmail');

    final hasNormalized =
        normalizedName != null ||
        normalizedPhone != null ||
        normalizedEmail != null;
    if (hasNormalized) {
      return (
        name: normalizedName,
        phoneRaw: normalizedPhone,
        email: normalizedEmail,
        keys: keys,
        source: 'normalized',
      );
    }

    final name = pick(const [
      ['customer', 'name'],
      ['customer_name'],
      ['customerName'],
      ['custName'],
      ['name'],
      ['booking', 'customer', 'name'],
      ['booking', 'customer_name'],
      ['booking', 'customerName'],
      ['booking', 'custName'],
      ['booking', 'name'],
      ['record', 'customer_name'],
      ['record', 'booking', 'customer_name'],
      ['record', 'booking', 'customerName'],
      ['payload', 'customer_name'],
      ['payload', 'booking', 'customer_name'],
      ['record', 'payload', 'customer_name'],
      ['record', 'payload', 'customerName'],
      ['record', 'payload', 'custName'],
      ['record', 'payload', 'name'],
      ['record', 'payload', 'booking', 'customer_name'],
      ['record', 'payload', 'booking', 'customerName'],
      ['record', 'payload', 'booking', 'custName'],
      ['record', 'payload', 'booking', 'name'],
    ], keys);

    final phoneRaw = pick(const [
      ['customer', 'phone'],
      ['customer_phone'],
      ['customerPhone'],
      ['custPhone'],
      ['phone'],
      ['tel'],
      ['mobile'],
      ['booking', 'customer', 'phone'],
      ['booking', 'customer_phone'],
      ['booking', 'customerPhone'],
      ['booking', 'custPhone'],
      ['booking', 'phone'],
      ['booking', 'tel'],
      ['booking', 'mobile'],
      ['record', 'customer_phone'],
      ['record', 'booking', 'customer_phone'],
      ['record', 'booking', 'customerPhone'],
      ['record', 'booking', 'custPhone'],
      ['payload', 'customer_phone'],
      ['payload', 'booking', 'customer_phone'],
      ['record', 'payload', 'customer_phone'],
      ['record', 'payload', 'customerPhone'],
      ['record', 'payload', 'custPhone'],
      ['record', 'payload', 'phone'],
      ['record', 'payload', 'tel'],
      ['record', 'payload', 'mobile'],
      ['record', 'payload', 'booking', 'customer_phone'],
      ['record', 'payload', 'booking', 'customerPhone'],
      ['record', 'payload', 'booking', 'custPhone'],
      ['record', 'payload', 'booking', 'phone'],
    ], keys);

    final email = pick(
      const [
        ['customer', 'email'],
        ['customer_email'],
        ['customerEmail'],
        ['custEmail'],
        ['email'],
        ['invoice_email'],
        ['invoiceEmail'],
        ['booking', 'customer', 'email'],
        ['booking', 'customer_email'],
        ['booking', 'customerEmail'],
        ['booking', 'custEmail'],
        ['booking', 'email'],
        ['booking', 'invoice_email'],
        ['booking', 'invoiceEmail'],
        ['record', 'customer_email'],
        ['record', 'booking', 'customer_email'],
        ['record', 'booking', 'customerEmail'],
        ['record', 'booking', 'custEmail'],
        ['payload', 'customer_email'],
        ['payload', 'booking', 'customer_email'],
        ['record', 'payload', 'customer_email'],
        ['record', 'payload', 'customerEmail'],
        ['record', 'payload', 'custEmail'],
        ['record', 'payload', 'email'],
        ['record', 'payload', 'invoice_email'],
        ['record', 'payload', 'invoiceEmail'],
        ['record', 'payload', 'booking', 'customer_email'],
        ['record', 'payload', 'booking', 'customerEmail'],
        ['record', 'payload', 'booking', 'custEmail'],
        ['record', 'payload', 'booking', 'email'],
        ['record', 'payload', 'booking', 'invoice_email'],
        ['record', 'payload', 'booking', 'invoiceEmail'],
      ],
      keys,
      email: true,
    );

    final hasRaw = name != null || phoneRaw != null || email != null;
    return (
      name: name,
      phoneRaw: phoneRaw,
      email: email,
      keys: keys,
      source: hasRaw ? 'raw' : 'none',
    );
  }

  void _logPdfContactResolution() {
    final resolved = _resolvePdfContact();
    final keyList = resolved.keys.join(',');
    debugPrint(
      '[PDF][CONTACT] emailFound=${resolved.email != null} phoneFound=${resolved.phoneRaw != null} source=${resolved.source} keys=$keyList',
    );
  }

  String? get _customerName => _resolvePdfContact().name;

  String? get _customerPhoneRaw => _resolvePdfContact().phoneRaw;

  String? get _customerEmail => _resolvePdfContact().email;

  String? get _customerCountryContext =>
      _firstDetailText([
        'phone_country_code',
        'phoneCountryCode',
        'dial_code',
        'dialCode',
        'customer_country',
        'customerCountry',
        'country',
        'countryCode',
        'country_iso',
        'countryIso',
        'locale',
        'language',
      ]) ??
      _tenantDefaultCountryIso();

  String? _tenantDefaultCountryIso() {
    // Tenant-level fallback only. Future white-label tenants should move this into tenant config.
    if (kTenantId.toLowerCase().trim() == 'fluxidi') return 'BE';
    return null;
  }

  String? get _customerPhoneE164 => _normalizePhoneForWhatsApp(
    _customerPhoneRaw,
    countryContext: _customerCountryContext,
  );

  bool get _hasAnyRawCustomerContact =>
      (_customerName?.trim().isNotEmpty ?? false) ||
      (_customerPhoneRaw?.trim().isNotEmpty ?? false) ||
      (_customerEmail?.trim().isNotEmpty ?? false);

  String _maskEmailForLog(String? value) {
    final email = value?.trim();
    if (email == null || email.isEmpty) return '-';
    final at = email.indexOf('@');
    if (at <= 0) return '***';
    final first = email.substring(0, 1);
    return '$first***${email.substring(at)}';
  }

  String _maskPhoneForLog(String? value) {
    final digits = value?.replaceAll(RegExp(r'\D'), '') ?? '';
    if (digits.isEmpty) return '-';
    final suffix = digits.length <= 2
        ? digits
        : digits.substring(digits.length - 2);
    return '***$suffix';
  }

  void _debugReceiptContactState(String label, {String? emailOverride}) {
    if (!kDebugMode) return;
    debugPrint(
      '[RITBON][CONTACT][$label] '
      'nameFound=${_customerName != null} '
      'emailFound=${(emailOverride ?? _customerEmail) != null} '
      'phoneFound=${_customerPhoneE164 != null} '
      'keys=${item.bookingDetails.keys.where((key) => key.toLowerCase().contains('customer') || key.toLowerCase().contains('phone') || key.toLowerCase().contains('email')).join(',')}',
    );
  }

  String? _validEmail(String? value) {
    final email = value?.trim();
    if (email == null || email.isEmpty) return null;
    final at = email.indexOf('@');
    if (at <= 0 || at >= email.length - 1) return null;
    final dotAfterAt = email.indexOf('.', at + 1);
    if (dotAfterAt <= at + 1 || dotAfterAt >= email.length - 1) return null;
    if (email.contains(RegExp(r'\s'))) return null;
    return email;
  }

  // MVP E.164-like normalizer. Replace/enhance with libphonenumber-style validation later.
  String? _normalizePhoneForWhatsApp(String? raw, {String? countryContext}) {
    final input = raw?.trim();
    if (input == null || input.isEmpty) return null;
    var cleaned = input.replaceAll(RegExp(r'[\s\-\(\)\/\.]'), '');
    if (cleaned.startsWith('00')) cleaned = '+${cleaned.substring(2)}';
    if (cleaned.startsWith('+')) {
      final digits = cleaned.substring(1).replaceAll(RegExp(r'\D'), '');
      if (digits.length < 8 || digits.length > 15) return null;
      return '+$digits';
    }

    final digits = cleaned.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) return null;
    final iso = _countryIsoFromContext(countryContext);
    if (iso == null) return null;
    final dial = _dialCodeForIso(iso);
    if (dial == null) return null;

    String? national;
    switch (iso) {
      case 'BE':
      case 'NL':
      case 'FR':
      case 'DE':
      case 'GB':
      case 'CH':
      case 'AT':
      case 'IE':
        if (!digits.startsWith('0')) return null;
        national = digits.replaceFirst(RegExp(r'^0+'), '');
        break;
      case 'ES':
        if (digits.length != 9 || digits.startsWith('0')) return null;
        national = digits;
        break;
      case 'US':
      case 'CA':
        if (digits.length != 10) return null;
        national = digits;
        break;
      case 'LU':
        if (digits.length < 6 || digits.length > 9) return null;
        national = digits.replaceFirst(RegExp(r'^0+'), '');
        break;
      case 'IT':
      case 'PT':
        if (digits.length < 8 || digits.length > 10) return null;
        national = digits.replaceFirst(RegExp(r'^0+'), '');
        break;
      default:
        return null;
    }
    final normalized = '$dial$national';
    final normalizedDigits = normalized.replaceAll(RegExp(r'\D'), '');
    if (normalizedDigits.length < 8 || normalizedDigits.length > 15)
      return null;
    return normalized;
  }

  String? _countryIsoFromContext(String? context) {
    final raw = context?.trim();
    if (raw == null || raw.isEmpty) return null;
    final lower = raw.toLowerCase();
    if (lower.startsWith('+')) return _isoFromDialCode(lower);
    if (RegExp(r'^\d+$').hasMatch(lower)) return _isoFromDialCode('+$lower');
    final localePart = lower.contains('_') || lower.contains('-')
        ? lower.split(RegExp(r'[_-]')).last
        : lower;
    final c = localePart
        .replaceAll('ë', 'e')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ï', 'i')
        .replaceAll('ä', 'a')
        .replaceAll('ö', 'o')
        .replaceAll('ü', 'u')
        .replaceAll('ç', 'c')
        .trim();
    const aliases = <String, String>{
      'be': 'BE',
      'belgium': 'BE',
      'belgie': 'BE',
      'belgique': 'BE',
      'belgien': 'BE',
      'nl': 'NL',
      'netherlands': 'NL',
      'nederland': 'NL',
      'pays bas': 'NL',
      'fr': 'FR',
      'france': 'FR',
      'frankrijk': 'FR',
      'es': 'ES',
      'spain': 'ES',
      'spanje': 'ES',
      'espagne': 'ES',
      'espana': 'ES',
      'us': 'US',
      'usa': 'US',
      'united states': 'US',
      'america': 'US',
      'ca': 'CA',
      'canada': 'CA',
      'gb': 'GB',
      'uk': 'GB',
      'united kingdom': 'GB',
      'great britain': 'GB',
      'de': 'DE',
      'germany': 'DE',
      'duitsland': 'DE',
      'allemagne': 'DE',
      'deutschland': 'DE',
      'lu': 'LU',
      'luxembourg': 'LU',
      'luxemburg': 'LU',
      'it': 'IT',
      'italy': 'IT',
      'italie': 'IT',
      'italia': 'IT',
      'pt': 'PT',
      'portugal': 'PT',
      'ch': 'CH',
      'switzerland': 'CH',
      'suisse': 'CH',
      'zwitserland': 'CH',
      'at': 'AT',
      'austria': 'AT',
      'oostenrijk': 'AT',
      'autriche': 'AT',
      'ie': 'IE',
      'ireland': 'IE',
    };
    return aliases[c] ?? aliases[lower];
  }

  String? _isoFromDialCode(String dial) {
    const map = <String, String>{
      '+32': 'BE',
      '+31': 'NL',
      '+33': 'FR',
      '+34': 'ES',
      '+1': 'US',
      '+44': 'GB',
      '+49': 'DE',
      '+352': 'LU',
      '+39': 'IT',
      '+351': 'PT',
      '+41': 'CH',
      '+43': 'AT',
      '+353': 'IE',
    };
    return map[dial];
  }

  String? _dialCodeForIso(String iso) {
    const map = <String, String>{
      'BE': '+32',
      'NL': '+31',
      'FR': '+33',
      'ES': '+34',
      'US': '+1',
      'CA': '+1',
      'GB': '+44',
      'DE': '+49',
      'LU': '+352',
      'IT': '+39',
      'PT': '+351',
      'CH': '+41',
      'AT': '+43',
      'IE': '+353',
    };
    return map[iso];
  }

  String? _displayToken(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    final normalized = text.replaceAll('_', ' ').replaceAll('-', ' ');
    return normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) => part.length == 1
              ? part.toUpperCase()
              : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _displayServiceToken(String? value) {
    final raw = value?.trim() ?? '';
    final normalized = raw
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .trim();
    if (normalized == 'passenger' ||
        normalized == 'personenvervoer' ||
        normalized == 'passenger_transport') {
      return _receiptText('passengerTransport');
    }
    if (normalized == 'business' || normalized == 'zakelijk') {
      return _receiptText('businessRide');
    }
    if (normalized == 'airport' ||
        normalized == 'luchthaven' ||
        normalized == 'airport_transfer') {
      return _receiptText('airportTransfer');
    }
    return _displayToken(value) ?? '—';
  }

  String _displayTierToken(String? value) {
    final raw = value?.trim() ?? '';
    final normalized = raw.toLowerCase().replaceAll('-', '_').trim();
    if (normalized == 'comfort') return _receiptText('tierComfort');
    if (normalized == 'private') return _receiptText('tierPrivate');
    if (normalized == 'premium') return _receiptText('tierPremium');
    return _displayToken(value) ?? '—';
  }

  String? _displayExtraValue(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      final token = _displayToken(raw);
      return token == null || token == '—' ? null : token;
    }
    if (raw is List) {
      final values = raw
          .map(_displayExtraValue)
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false);
      if (values.isEmpty) return null;
      return values.join(', ');
    }
    if (raw is Map) {
      final values = <String>[];
      raw.forEach((key, value) {
        final include =
            value == true ||
            value == 1 ||
            value?.toString().toLowerCase().trim() == 'true' ||
            value?.toString().trim() == '1';
        if (!include) return;
        final label = _displayToken(key.toString());
        if (label != null && label != '—') values.add(label);
      });
      if (values.isEmpty) return null;
      return values.join(', ');
    }
    return null;
  }

  String? _plannedExtrasText() {
    const paths = <List<String>>[
      ['extras'],
      ['extra_service'],
      ['extra_service_key'],
      ['selected_options'],
      ['premium_options'],
      ['booking', 'extras'],
      ['booking', 'extra_service'],
      ['booking', 'extra_service_key'],
      ['booking', 'selected_options'],
      ['booking', 'premium_options'],
      ['record', 'payload', 'extras'],
      ['record', 'payload', 'extra_service'],
      ['record', 'payload', 'extra_service_key'],
      ['record', 'payload', 'selected_options'],
      ['record', 'payload', 'premium_options'],
      ['record', 'payload', 'booking', 'extras'],
      ['record', 'payload', 'booking', 'extra_service'],
      ['record', 'payload', 'booking', 'extra_service_key'],
      ['record', 'payload', 'booking', 'selected_options'],
      ['record', 'payload', 'booking', 'premium_options'],
    ];
    for (final path in paths) {
      final text = _displayExtraValue(_detailAt(path));
      if (text != null && text.trim().isNotEmpty) return text;
    }
    return null;
  }

  bool _sameMoney(double? a, double? b) {
    if (a == null || b == null) return false;
    return (a - b).abs() < 0.005;
  }

  bool get _hasReturnPriceSplit {
    final outbound =
        _detailDouble('outbound_price_eur') ??
        _detailDouble('price_incl_vat_main');
    final ret = _detailDouble('return_price_eur');
    return outbound != null &&
        ret != null &&
        ret > 0 &&
        !_sameMoney(outbound, ret);
  }

  bool get _hasReturnBookingInfo =>
      _detailText('return_scheduled_pickup_at') != null ||
      _detailText('return_route') != null ||
      _hasReturnPriceSplit ||
      (item.bookingId ?? '').endsWith('-R');

  List<Widget> _plannedPriceRows() {
    final package = _detailDouble('booking_total_eur');
    final legAmount = _effectiveOperationalLegAmount();
    final segment = _detailDouble('segment_price_eur');
    final outbound = _detailDouble('outbound_price_eur');
    final ret = _detailDouble('return_price_eur');
    final rows = <Widget>[];

    // Leg-first business rule: a ritbon proves ONE operational leg.
    // Render only the active leg's "Vaste prijs" and suppress every
    // roundtrip context row (Totaal boeking €400, Pakketprijs, sibling
    // leg's prijs). Active-leg price priority:
    //   1. _effectiveOperationalLegAmount() — authoritative leg slice
    //   2. outbound_price_eur / return_price_eur — split projection
    //   3. item.totalEur — trip-history leg amount fallback
    final isLegReceipt = _ReceiptPdfActionRunner._isLegReceiptItem(item);
    if (isLegReceipt) {
      final activeLegToken = _ReceiptPdfActionRunner._legReceiptActiveLegToken(
        item,
      );
      double? activePrice;
      if (_isPositiveAmount(legAmount)) {
        activePrice = legAmount;
      } else {
        final splitPrice = activeLegToken == 'return' ? ret : outbound;
        if (_isPositiveAmount(splitPrice)) {
          activePrice = splitPrice;
        } else if (_isPositiveAmount(item.totalEur)) {
          activePrice = item.totalEur;
        }
      }
      if (_isPositiveAmount(activePrice)) {
        rows.add(
          _receiptRow(_receiptText('fixedPrice'), _moneyText(activePrice)),
        );
      }
      return rows;
    }

    if (_isPlannedOperationalLegPaymentItem() && _isPositiveAmount(legAmount)) {
      rows.add(_receiptRow(_receiptText('fixedPrice'), _moneyText(legAmount)));
      if (_isPositiveAmount(package) && !_sameMoney(package, legAmount)) {
        rows.add(
          _receiptRow(
            _tr(
              nl: 'Totaal boeking',
              en: 'Booking total',
              fr: 'Total réservation',
              es: 'Total reserva',
            ),
            _moneyText(package),
          ),
        );
      }
      return rows;
    }

    if (_hasReturnBookingInfo && (outbound != null || ret != null)) {
      if (package != null &&
          !_sameMoney(package, outbound) &&
          !_sameMoney(package, ret)) {
        rows.add(
          _receiptRow(_receiptText('packagePrice'), _moneyText(package)),
        );
      }
      if (outbound != null) {
        rows.add(
          _receiptRow(_receiptText('outboundPrice'), _moneyText(outbound)),
        );
      }
      if (ret != null && !_sameMoney(ret, outbound)) {
        rows.add(_receiptRow(_receiptText('returnPrice'), _moneyText(ret)));
      }
      if (segment != null &&
          !_sameMoney(segment, package) &&
          !_sameMoney(segment, outbound) &&
          !_sameMoney(segment, ret)) {
        rows.add(_receiptRow(_receiptText('ridePrice'), _moneyText(segment)));
      }
      return rows;
    }

    final single = segment ?? outbound ?? package;
    if (single != null) {
      rows.add(_receiptRow(_receiptText('fixedPrice'), _moneyText(single)));
    }
    return rows;
  }

  String _shareText() {
    return _receiptCustomerMessage();
  }

  String get _customerReference {
    return _businessReferenceDisplayForItem(
      item,
      source: 'receipt_body_customer_reference',
    ).value;
  }

  String _localizedPaymentMethodValue(String? raw) {
    final key = paymentMethodDisplayKey(
      paymentMethod: raw,
      paymentProvider: _firstDetailPathText(const [
        ['payment_provider'],
        ['paymentProvider'],
        ['booking', 'payment_provider'],
      ]),
      paymentSource: _paymentSourceFromDetails(),
    );
    switch (key) {
      case 'cash':
        return _tr(nl: 'Contant', en: 'Cash', fr: 'Espèces', es: 'Efectivo');
      case 'bancontactManual':
        return _tr(
          nl: 'Bancontact',
          en: 'Bancontact',
          fr: 'Bancontact',
          es: 'Bancontact',
        );
      case 'tapToPay':
        return _tr(
          nl: 'Tap to Pay',
          en: 'Tap to Pay',
          fr: 'Tap to Pay',
          es: 'Tap to Pay',
        );
      case 'qr':
        return _tr(
          nl: 'QR-code',
          en: 'QR code',
          fr: 'Code QR',
          es: 'Código QR',
        );
      case 'onlineMollie':
        return _tr(
          nl: 'Online betaling',
          en: 'Online payment',
          fr: 'Paiement en ligne',
          es: 'Pago en línea',
        );
      case 'bankTransfer':
        return _tr(
          nl: 'Overschrijving',
          en: 'Bank transfer',
          fr: 'Virement',
          es: 'Transferencia',
        );
      case 'unknown':
        return _receiptText('notAvailable');
      default:
        final value = (raw ?? '').trim();
        if (value.toLowerCase() == 'in_car') {
          return _tr(nl: 'Contant', en: 'Cash', fr: 'Espèces', es: 'Efectivo');
        }
        return _displayToken(value) ?? value.replaceAll('_', ' ');
    }
  }

  String _localizedPaymentSourceValue(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return _receiptText('notAvailable');
    final normalized = value
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    switch (normalized) {
      case 'in_car':
        return _tr(
          nl: 'In de wagen',
          en: 'In vehicle',
          fr: 'Dans le véhicule',
          es: 'En el vehículo',
        );
      case 'payment_link':
        return _tr(
          nl: 'Betaallink',
          en: 'Payment link',
          fr: 'Lien de paiement',
          es: 'Enlace de pago',
        );
      case 'mollie':
        return _tr(nl: 'Mollie', en: 'Mollie', fr: 'Mollie', es: 'Mollie');
      default:
        return _displayToken(value) ?? value.replaceAll('_', ' ');
    }
  }

  String _receiptCustomerMessage() {
    final route = _resolvedRouteForPdf();
    final lines = <String>[
      '${_receiptText('receiptFrom')} $kCompanyName',
      '${_receiptText('type')}: ${item.kindLabel}',
      '${_receiptText('reference')}: $_customerReference',
      '${_receiptText('from')}: ${route.from}',
      '${_receiptText('to')}: ${route.to}',
      if (_detailText('scheduled_pickup_at') != null)
        '${_receiptText('scheduledPickup')}: ${_formatDate(_detailText('scheduled_pickup_at'))}',
      if (item.startedAt?.trim().isNotEmpty ?? false)
        '${_receiptText('startTime')}: ${_formatDate(item.startedAt)}',
      if (item.stoppedAt?.trim().isNotEmpty ?? false)
        '${_receiptText('endTime')}: ${_formatDate(item.stoppedAt)}',
      '${_receiptText('distance')}: ${_kmText()}',
      '${_receiptText('total')}: ${_totalText()}',
      '${_receiptText('paymentStatus')}: ${_paymentStatusText()}',
      '',
      _receiptText('thanksRide'),
    ];
    return lines.join('\n');
  }

  String _paymentStatusText() {
    // Surface "Paid" whenever the hydrated JSON declares it — even if the
    // in-memory enum hasn't been flipped yet (e.g. `_resolveReceiptPaymentStatus`
    // hasn't completed, or the authoritative booking-worker record still says
    // pending while compliance already marked the ride paid).
    if (_isEffectiveReceiptPaid()) return _receiptText('paid');
    final invoiceKey = streetBusinessInvoicePaymentStatusKey(
      hasInvoice: _hasStreetBusinessInvoice,
      invoicePaid: _streetBusinessInvoicePaid,
      receiptPaid: false,
    );
    if (invoiceKey != null) return _receiptText(invoiceKey);
    switch (_paymentStatus) {
      case _ReceiptPaymentStatus.pending:
        return _receiptText('unpaid');
      case _ReceiptPaymentStatus.sent:
        return _receiptText('paymentSent');
      case _ReceiptPaymentStatus.paid:
        return _receiptText('paid');
    }
  }

  StreetBusinessInvoiceBuyerInput _streetBusinessInvoicePrefill() {
    final fields = _resolvedReceiptBusinessFields();
    return streetBusinessInvoicePrefillFromFields(
      companyName: fields.companyName,
      vatNumber: fields.vatNumber,
      invoiceEmail: fields.invoiceEmail,
      invoiceAddress: fields.invoiceAddress,
    );
  }

  void _onStreetBusinessInvoicePresence({
    required bool hasInvoice,
    required bool isPaid,
  }) {
    if (_hasStreetBusinessInvoice == hasInvoice &&
        _streetBusinessInvoicePaid == isPaid) {
      return;
    }
    if (!mounted) {
      _hasStreetBusinessInvoice = hasInvoice;
      _streetBusinessInvoicePaid = isPaid;
      return;
    }
    setState(() {
      _hasStreetBusinessInvoice = hasInvoice;
      _streetBusinessInvoicePaid = isPaid;
    });
  }

  String _paymentLink() {
    final amount = _selectedPaymentAmount() ?? 0.0;
    return Uri(
      scheme: 'fluxidi',
      host: 'pay',
      queryParameters: <String, String>{
        'ref': _customerReference,
        'amount': amount.toStringAsFixed(2),
        'currency': item.currency,
        'memo':
            '$kCompanyName ${_receiptText('receiptTitle')} $_customerReference',
      },
    ).toString();
  }

  /// Resolves the booking/ride owner tenant + company **strictly** from the
  /// booking record (booking details + raw history payload).
  ///
  /// In Fluxidi's tenant model, `tenant_id == company_id` for the booking
  /// owner (see [resolveStrictTenantCompanyScope] / `EffectiveTenantCompanyScope`,
  /// which always sets `tenantId: activeCompanyId, companyId: activeCompanyId`).
  /// The `/trips/history` backend `summarizeTrip()` currently emits only
  /// `tenant_id` at the top level of each trip; legacy records may stamp the
  /// id under `company_id` / `owner_company_id` / nested `record.*` paths
  /// only. To honour that invariant without "inventing" a scope from session
  /// state, we accept the canonical owner id under **either** name and mirror
  /// it into the missing slot. Returns `null` only when neither identifier
  /// can be found anywhere on the record.
  ///
  /// Session/profile values are intentionally **not** used as fallback here.
  /// `presentFields` is populated with the alias paths that produced a value
  /// (for diagnostics only).
  ({
    String tenantId,
    String companyId,
    String tenantSource,
    String companySource,
  })?
  _bookingOwnerScopeForBankPayment({Set<String>? presentFields}) {
    final sources = <(String, Map<dynamic, dynamic>)>[
      ('bookingDetails', item.bookingDetails),
      ('rawSource', item.rawSource),
    ];
    const tenantAliases = <List<String>>[
      ['tenant_id'],
      ['tenantId'],
      ['owner_tenant_id'],
      ['ownerTenantId'],
      ['booking', 'tenant_id'],
      ['booking', 'tenantId'],
      ['booking', 'owner_tenant_id'],
      ['booking', 'ownerTenantId'],
      ['booking_details', 'tenant_id'],
      ['booking_details', 'tenantId'],
      ['record', 'tenant_id'],
      ['record', 'tenantId'],
      ['record', 'booking', 'tenant_id'],
      ['record', 'booking', 'tenantId'],
      ['record', 'booking_details', 'tenant_id'],
      ['record', 'booking_details', 'tenantId'],
      ['record', 'payload', 'tenant_id'],
      ['record', 'payload', 'tenantId'],
      ['payload', 'tenant_id'],
      ['payload', 'tenantId'],
      ['payload', 'booking', 'tenant_id'],
      ['payload', 'booking', 'tenantId'],
    ];
    const companyAliases = <List<String>>[
      ['company_id'],
      ['companyId'],
      ['owner_company_id'],
      ['ownerCompanyId'],
      ['booking', 'company_id'],
      ['booking', 'companyId'],
      ['booking', 'owner_company_id'],
      ['booking', 'ownerCompanyId'],
      ['booking_details', 'company_id'],
      ['booking_details', 'companyId'],
      ['record', 'company_id'],
      ['record', 'companyId'],
      ['record', 'booking', 'company_id'],
      ['record', 'booking', 'companyId'],
      ['record', 'booking_details', 'company_id'],
      ['record', 'booking_details', 'companyId'],
      ['record', 'payload', 'company_id'],
      ['record', 'payload', 'companyId'],
      ['payload', 'company_id'],
      ['payload', 'companyId'],
      ['payload', 'booking', 'company_id'],
      ['payload', 'booking', 'companyId'],
    ];

    ({String value, String source})? findFirst(List<List<String>> aliases) {
      for (final entry in sources) {
        for (final path in aliases) {
          final value = _deepLookupInBookingMap(entry.$2, path);
          if (value == null) continue;
          final text = value.toString().trim();
          if (text.isEmpty) continue;
          final lower = text.toLowerCase();
          if (lower == 'null' || lower == 'undefined') continue;
          final aliasLabel = '${entry.$1}.${path.join('.')}';
          if (presentFields != null) presentFields.add(aliasLabel);
          return (value: text, source: aliasLabel);
        }
      }
      return null;
    }

    final tenantHit = findFirst(tenantAliases);
    final companyHit = findFirst(companyAliases);
    if (tenantHit == null && companyHit == null) return null;

    final tenantId = tenantHit?.value ?? companyHit!.value;
    final companyId = companyHit?.value ?? tenantHit!.value;
    return (
      tenantId: tenantId,
      companyId: companyId,
      tenantSource: tenantHit?.source ?? '${companyHit!.source}|mirrored',
      companySource: companyHit?.source ?? '${tenantHit!.source}|mirrored',
    );
  }

  /// Resolves the currently active company-session tenant + company.
  ///
  /// `localBackendBusinessProfileNotifier` itself carries no `company_id` —
  /// it is loaded as the **active company session's** business profile. The
  /// caller must therefore prove that the active session scope matches the
  /// booking-owner scope before trusting that profile's IBAN as the QR
  /// beneficiary. This helper never falls back to the central
  /// `kTenantId` / demo / default scope.
  ({String tenantId, String companyId, String source})?
  _activeCompanyScopeForBankPayment() {
    final companySession = activeCompanySessionNotifier.value;
    final sessionCompanyId = (companySession?.companyId ?? '').trim();
    if (sessionCompanyId.isNotEmpty) {
      return (
        tenantId: sessionCompanyId,
        companyId: sessionCompanyId,
        source: 'active_company_session',
      );
    }
    final companyProfile = companyProfileNotifier.value;
    final profileCompanyId = (companyProfile?.companyId ?? '').trim();
    if (profileCompanyId.isNotEmpty) {
      return (
        tenantId: profileCompanyId,
        companyId: profileCompanyId,
        source: 'company_profile',
      );
    }
    final driverSession = activeDriverSessionNotifier.value;
    final driverTenantId = (driverSession?.tenantId ?? '').trim();
    final driverCompanyId = (driverSession?.companyId ?? '').trim();
    if ((driverSession?.isVerifiedPairingSession ?? false) &&
        driverTenantId.isNotEmpty &&
        driverCompanyId.isNotEmpty) {
      return (
        tenantId: driverTenantId,
        companyId: driverCompanyId,
        source: 'verified_driver_session',
      );
    }
    return null;
  }

  _BankPaymentDetails _bankPaymentDetails() {
    final profile = localBackendBusinessProfileNotifier.value;
    final beneficiaryRaw = (profile?.legalName.trim().isNotEmpty ?? false)
        ? profile!.legalName.trim()
        : (profile?.companyName.trim().isNotEmpty ?? false)
        ? profile!.companyName.trim()
        : kCompanyName;
    // EPC SCT name field max 70 chars.
    final beneficiary = beneficiaryRaw.length > 70
        ? beneficiaryRaw.substring(0, 70)
        : beneficiaryRaw;
    final ibanNormalized = (profile?.iban ?? '')
        .replaceAll(RegExp(r'\s+'), '')
        .toUpperCase();
    final amount = _selectedPaymentAmount() ?? 0.0;
    final currency = item.currency.trim().isEmpty
        ? 'EUR'
        : item.currency.trim().toUpperCase();
    final memo =
        '$kCompanyName ${_receiptText('receiptTitle')} $_customerReference';
    // EPC unstructured remittance info max 140 chars.
    final reference = memo.length > 140 ? memo.substring(0, 140) : memo;
    return _BankPaymentDetails(
      beneficiary: beneficiary,
      iban: ibanNormalized,
      bic: '',
      amount: amount,
      currency: currency,
      reference: reference,
    );
  }

  /// EPC069-12 SEPA Credit Transfer QR payload (version 002).
  ///
  /// Banking apps that support EPC/SEPA QR codes open a prefilled transfer
  /// screen to the company IBAN. The customer still confirms the transfer
  /// inside their own bank app, so this never marks the booking as paid.
  String _bankPaymentEpcPayload(_BankPaymentDetails details) {
    final amountString =
        '${details.currency}${details.amount.toStringAsFixed(2)}';
    return <String>[
      'BCD',
      '002',
      '1',
      'SCT',
      details.bic,
      details.beneficiary,
      details.iban,
      amountString,
      '',
      '',
      details.reference,
    ].join('\n');
  }

  String _bankPaymentClipboardText(_BankPaymentDetails details) {
    final amountText = _moneyText(details.amount);
    final beneficiaryLabel = _tr(
      nl: 'Begunstigde',
      en: 'Beneficiary',
      fr: 'Bénéficiaire',
      es: 'Beneficiario',
    );
    final memoLabel = _tr(
      nl: 'Mededeling',
      en: 'Reference',
      fr: 'Communication',
      es: 'Concepto',
    );
    return <String>[
      '${_receiptText('amount')}: $amountText',
      '$beneficiaryLabel: ${details.beneficiary}',
      'IBAN: ${details.iban}',
      '$memoLabel: ${details.reference}',
    ].join('\n');
  }

  String _bankPaymentSetupMissingMessage() {
    return _tr(
      nl: 'Bankgegevens ontbreken in de bedrijfsinstellingen.',
      en: 'Bank details are missing in business settings.',
      fr: 'Les coordonnées bancaires manquent dans les paramètres de l’entreprise.',
      es: 'Faltan los datos bancarios en la configuración de la empresa.',
    );
  }

  String _bankPaymentScopeMismatchMessage() {
    return _tr(
      nl: 'Bankgegevens komen niet overeen met dit bedrijf.',
      en: 'Bank details do not match this company.',
      fr: 'Les coordonnées bancaires ne correspondent pas à cette entreprise.',
      es: 'Los datos bancarios no coinciden con esta empresa.',
    );
  }

  String _maskScopeForLog(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '-';
    if (trimmed.length <= 6) return trimmed;
    return '${trimmed.substring(0, 3)}…${trimmed.substring(trimmed.length - 3)}';
  }

  String _bankPaymentCopyButtonLabel() {
    return _tr(
      nl: 'Kopieer betaalgegevens',
      en: 'Copy payment details',
      fr: 'Copier les données de paiement',
      es: 'Copiar datos de pago',
    );
  }

  String _bankPaymentCopySnackText() {
    return _tr(
      nl: 'Betaalgegevens gekopieerd.',
      en: 'Payment details copied.',
      fr: 'Données de paiement copiées.',
      es: 'Datos de pago copiados.',
    );
  }

  String _maskIbanForLog(String iban) {
    final compact = iban.replaceAll(RegExp(r'\s+'), '');
    if (compact.length <= 6) return compact;
    return '${compact.substring(0, 4)}…${compact.substring(compact.length - 2)}';
  }

  void _markPaymentRequestSent() {
    if (_paymentStatus == _ReceiptPaymentStatus.pending) {
      setState(() => _paymentStatus = _ReceiptPaymentStatus.sent);
    }
  }

  Future<void> _copyPaymentLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _paymentLink()));
    _markPaymentRequestSent();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_receiptText('paymentLinkCopied'))));
  }

  Future<void> _openWhatsApp(
    BuildContext context, {
    required String phoneE164,
    required String message,
  }) async {
    final digits = phoneE164.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.https('wa.me', '/$digits', <String, String>{
      'text': message,
    });
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('whatsappOpenFailed'))),
      );
    }
  }

  Future<void> _openEmail(
    BuildContext context, {
    required String email,
    required String subject,
    required String body,
  }) async {
    final recipient = email.trim();
    final encodedSubject = Uri.encodeComponent(subject);
    final encodedBody = Uri.encodeComponent(body);
    final uri = Uri.parse(
      recipient.isNotEmpty
          ? 'mailto:${Uri.encodeComponent(recipient)}?subject=$encodedSubject&body=$encodedBody'
          : 'mailto:?subject=$encodedSubject&body=$encodedBody',
    );
    _debugReceiptContactState(
      'email_open',
      emailOverride: recipient.isNotEmpty ? recipient : null,
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_receiptText('emailOpenFailed'))));
    }
  }

  Future<void> _sendReceiptWhatsApp(BuildContext context) async {
    final phone = _customerPhoneE164;
    final contactSource = _resolvePdfContact().source;
    debugPrint(
      '[PDF][ACTION][WHATSAPP_TEXT] phoneFound=${phone != null} source=$contactSource',
    );
    if (phone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('noValidWhatsappPhone'))),
      );
      return;
    }
    final message = _tr(
      nl: 'Beste klant, uw betaalbewijs/ritbon is klaar. Ik stuur de PDF zo meteen door.',
      en: 'Dear customer, your ride receipt is ready. I will send the PDF shortly.',
      fr: 'Cher client, votre reçu de course est prêt. Je vais envoyer le PDF dans un instant.',
      es: 'Estimado cliente, su comprobante de viaje está listo. Enviaré el PDF en un momento.',
    );
    await _openWhatsApp(context, phoneE164: phone, message: message);
  }

  Future<void> _emailReceiptGeneric(BuildContext context) async {
    await _openEmail(
      context,
      email: _customerEmail ?? '',
      subject: _receiptText('receiptEmailSubject'),
      body: _receiptCustomerMessage(),
    );
  }

  bool _toBoolFlag(String? value) {
    final normalized = value?.toLowerCase().trim() ?? '';
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'ja';
  }

  ({
    bool isBusinessDocument,
    bool invoiceRequested,
    String companyName,
    String vatNumber,
    String invoiceEmail,
    String invoiceAddress,
  })
  _resolvedReceiptBusinessFields() {
    final invoiceRequested = _toBoolFlag(
      _firstDetailPathText(const [
        ['invoice_requested'],
        ['invoiceRequested'],
        ['booking', 'invoice_requested'],
        ['booking', 'invoiceRequested'],
        ['booking_details', 'invoice_requested'],
        ['booking_details', 'invoiceRequested'],
        ['record', 'invoice_requested'],
        ['record', 'invoiceRequested'],
        ['record', 'booking', 'invoice_requested'],
        ['record', 'booking', 'invoiceRequested'],
        ['record', 'booking_details', 'invoice_requested'],
        ['record', 'booking_details', 'invoiceRequested'],
        ['payload', 'invoice_requested'],
        ['payload', 'invoiceRequested'],
        ['payload', 'booking', 'invoice_requested'],
        ['payload', 'booking', 'invoiceRequested'],
      ]),
    );
    final businessFlag = _toBoolFlag(
      _firstDetailPathText(const [
        ['business_customer'],
        ['businessCustomer'],
        ['is_business'],
        ['isBusiness'],
        ['business_detected'],
        ['businessDetected'],
        ['booking', 'business_customer'],
        ['booking', 'businessCustomer'],
        ['booking', 'is_business'],
        ['booking', 'isBusiness'],
        ['booking', 'business_detected'],
        ['booking', 'businessDetected'],
        ['booking_details', 'business_customer'],
        ['booking_details', 'businessCustomer'],
        ['booking_details', 'is_business'],
        ['booking_details', 'isBusiness'],
        ['record', 'business_customer'],
        ['record', 'businessCustomer'],
        ['record', 'is_business'],
        ['record', 'isBusiness'],
        ['record', 'business_detected'],
        ['record', 'businessDetected'],
        ['record', 'booking', 'business_customer'],
        ['record', 'booking', 'businessCustomer'],
        ['record', 'booking', 'is_business'],
        ['record', 'booking', 'isBusiness'],
        ['record', 'booking', 'business_detected'],
        ['record', 'booking', 'businessDetected'],
      ]),
    );
    final customerCompany = _firstDetailPathText(const [
      ['company_name'],
      ['companyName'],
      ['customer_company'],
      ['customerCompany'],
      ['booking', 'company_name'],
      ['booking', 'companyName'],
      ['booking_details', 'company_name'],
      ['booking_details', 'companyName'],
      ['record', 'company_name'],
      ['record', 'companyName'],
      ['record', 'booking', 'company_name'],
      ['record', 'booking', 'companyName'],
      ['record', 'booking_details', 'company_name'],
      ['record', 'booking_details', 'companyName'],
      ['payload', 'company_name'],
      ['payload', 'companyName'],
      ['payload', 'booking', 'company_name'],
      ['payload', 'booking', 'companyName'],
    ]);
    final customerVat = _firstDetailPathText(const [
      ['vat_number'],
      ['vatNumber'],
      ['customer_vat'],
      ['customerVat'],
      ['booking', 'vat_number'],
      ['booking', 'vatNumber'],
      ['booking_details', 'vat_number'],
      ['booking_details', 'vatNumber'],
      ['record', 'vat_number'],
      ['record', 'vatNumber'],
      ['record', 'booking', 'vat_number'],
      ['record', 'booking', 'vatNumber'],
      ['record', 'booking_details', 'vat_number'],
      ['record', 'booking_details', 'vatNumber'],
      ['payload', 'vat_number'],
      ['payload', 'vatNumber'],
      ['payload', 'booking', 'vat_number'],
      ['payload', 'booking', 'vatNumber'],
    ]);
    final invoiceEmail =
        _firstDetailPathText(const [
          ['invoice_email'],
          ['invoiceEmail'],
          ['booking', 'invoice_email'],
          ['booking', 'invoiceEmail'],
          ['booking_details', 'invoice_email'],
          ['booking_details', 'invoiceEmail'],
          ['record', 'invoice_email'],
          ['record', 'invoiceEmail'],
          ['record', 'booking', 'invoice_email'],
          ['record', 'booking', 'invoiceEmail'],
          ['record', 'booking_details', 'invoice_email'],
          ['record', 'booking_details', 'invoiceEmail'],
          ['payload', 'invoice_email'],
          ['payload', 'invoiceEmail'],
          ['payload', 'booking', 'invoice_email'],
          ['payload', 'booking', 'invoiceEmail'],
        ]) ??
        '';
    final invoiceAddress =
        _firstDetailPathText(const [
          ['invoice_address'],
          ['invoiceAddress'],
          ['billing_address'],
          ['billingAddress'],
          ['company_address'],
          ['companyAddress'],
          ['booking', 'invoice_address'],
          ['booking', 'invoiceAddress'],
          ['booking', 'billing_address'],
          ['booking', 'billingAddress'],
          ['booking_details', 'invoice_address'],
          ['booking_details', 'invoiceAddress'],
          ['record', 'invoice_address'],
          ['record', 'invoiceAddress'],
          ['record', 'billing_address'],
          ['record', 'billingAddress'],
          ['record', 'booking', 'invoice_address'],
          ['record', 'booking', 'invoiceAddress'],
          ['record', 'booking_details', 'invoice_address'],
          ['record', 'booking_details', 'invoiceAddress'],
          ['payload', 'invoice_address'],
          ['payload', 'invoiceAddress'],
          ['payload', 'booking', 'invoice_address'],
          ['payload', 'booking', 'invoiceAddress'],
        ]) ??
        '';
    // CONSUMER-SALE-DOCUMENT-PRESENTATION-P0-1: never treat filled company/VAT
    // or Billit Invoice OrderType as business presentation.
    final invoiceIntent = _firstDetailPathText(const [
      ['invoice_intent'],
      ['invoiceIntent'],
      ['booking', 'invoice_intent'],
      ['booking', 'invoiceIntent'],
      ['record', 'invoice_intent'],
      ['record', 'invoiceIntent'],
      ['record', 'booking', 'invoice_intent'],
    ]);
    final saleKind = _firstDetailPathText(const [
      ['fluxidi_sale_kind'],
      ['fluxidiSaleKind'],
      ['sale_kind'],
      ['consumer_sale', 'sale_kind'],
      ['booking', 'fluxidi_sale_kind'],
      ['booking', 'consumer_sale', 'sale_kind'],
      ['record', 'fluxidi_sale_kind'],
      ['record', 'consumer_sale', 'sale_kind'],
    ]);
    final createdByRole = _firstDetailPathText(const [
      ['created_by_role'],
      ['createdByRole'],
      ['record', 'created_by_role'],
    ]);
    final billingCustomerType = _firstDetailPathText(const [
      ['billing_customer_snapshot', 'customer_type'],
      ['billingCustomerSnapshot', 'customer_type'],
      ['booking', 'billing_customer_snapshot', 'customer_type'],
      ['record', 'billing_customer_snapshot', 'customer_type'],
    ]);
    final hasBusiness = isBusinessDocumentForPresentation(
      saleKind: saleKind,
      invoiceIntent: invoiceIntent,
      bookingConsumerSaleKind: saleKind,
      createdByRole: createdByRole,
      billingCustomerType: billingCustomerType,
      businessInvoiceIntent: invoiceRequested || businessFlag,
      companyName: customerCompany,
      vatNumber: customerVat,
    );
    return (
      isBusinessDocument: hasBusiness,
      invoiceRequested: invoiceRequested,
      companyName: (customerCompany ?? '').trim(),
      vatNumber: (customerVat ?? '').trim(),
      invoiceEmail: invoiceEmail.trim(),
      invoiceAddress: invoiceAddress.trim(),
    );
  }

  bool get _isBusinessDocument {
    return _resolvedReceiptBusinessFields().isBusinessDocument;
  }

  double _resolvedVatRate() {
    final settingsVatRate = businessSettingsNotifier.value.pricingVatRate;
    final candidates = <double?>[
      _detailDouble('vat_rate'),
      _detailDouble('vatRate'),
      _detailDouble('booking_vat_rate'),
      _detailDouble('bookingVatRate'),
    ];
    for (final candidate in candidates) {
      if (candidate == null || !candidate.isFinite) continue;
      if (candidate > 1.0) return candidate / 100.0;
      if (candidate >= 0.0) return candidate;
    }
    return settingsVatRate.clamp(0.0, 1.0);
  }

  ({double subtotal, double vatAmount, double total, double vatRate})
  _resolvedReceiptAmounts() {
    final vatRate = _resolvedVatRate();
    final total =
        _receiptTotalAmount() ??
        _detailDouble('total') ??
        _detailDouble('booking_total_eur') ??
        0.0;
    final subtotalCandidate =
        _detailDouble('subtotal_ex_vat') ??
        _detailDouble('subtotalExVat') ??
        _detailDouble('price_ex_vat') ??
        _detailDouble('priceExVat');
    final vatAmountCandidate =
        _detailDouble('vat_amount') ??
        _detailDouble('vatAmount') ??
        _detailDouble('price_vat') ??
        _detailDouble('priceVat');

    final subtotal =
        subtotalCandidate ?? (vatRate > 0 ? (total / (1.0 + vatRate)) : total);
    final vatAmount = vatAmountCandidate ?? (total - subtotal);
    return (
      subtotal: subtotal.isFinite ? subtotal : 0.0,
      vatAmount: vatAmount.isFinite ? vatAmount : 0.0,
      total: total.isFinite ? total : 0.0,
      vatRate: vatRate.isFinite ? vatRate : 0.0,
    );
  }

  String _sanitizeFilePart(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return cleaned.isEmpty ? 'receipt' : cleaned;
  }

  Future<Uint8List?> _loadReceiptLogoBytes(String? preferredPath) async {
    final settings = businessSettingsNotifier.value;
    final profile = localBackendBusinessProfileNotifier.value;
    final loaded = await resolveAndLoadDocumentCompanyLogoBytes(
      localPath: (preferredPath ?? settings.logoAssetPath).trim(),
      companyLogoUrl: (profile?.publicLogoUrl ?? '').trim(),
      configuredFluxidiAsset: kFluxidiLogoAsset,
    );
    return loaded.bytes;
  }

  Future<Map<String, String>> _buildSellerProfile() async {
    final settings = businessSettingsNotifier.value;
    BackendBusinessProfile? backendProfile;
    try {
      backendProfile = await fetchBackendBusinessProfile();
    } catch (_) {
      backendProfile = null;
    }

    final profile =
        backendProfile ??
        localBackendBusinessProfileNotifier.value ??
        BackendBusinessProfile.defaults();
    final postcodeCity = [
      profile.postcode.trim(),
      profile.city.trim(),
    ].where((e) => e.isNotEmpty).join(' ');
    final address = [
      profile.address.trim().isNotEmpty
          ? profile.address.trim()
          : settings.address.trim(),
      if (postcodeCity.isNotEmpty) postcodeCity,
      if (profile.country.trim().isNotEmpty) profile.country.trim(),
    ].where((e) => e.isNotEmpty).join('\n');

    final companyName = profile.companyName.trim().isNotEmpty
        ? profile.companyName.trim()
        : settings.companyName.trim().isNotEmpty
        ? settings.companyName.trim()
        : kCompanyName;
    final legalName = profile.legalName.trim().isNotEmpty
        ? profile.legalName.trim()
        : companyName;
    final profileJson = profile.toJson();
    String localizedFooterFromProfile(AppLanguage lang) {
      final localized = switch (lang) {
        AppLanguage.en =>
          (profileJson['invoiceReceiptFooterTextEn'] ?? '').toString().trim(),
        AppLanguage.fr =>
          (profileJson['invoiceReceiptFooterTextFr'] ?? '').toString().trim(),
        AppLanguage.es =>
          (profileJson['invoiceReceiptFooterTextEs'] ?? '').toString().trim(),
        _ =>
          (profileJson['invoiceReceiptFooterTextNl'] ?? '').toString().trim(),
      };
      return localized;
    }

    final hasAnyLocalizedFooter =
        (profileJson['invoiceReceiptFooterTextNl'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        (profileJson['invoiceReceiptFooterTextEn'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        (profileJson['invoiceReceiptFooterTextFr'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        (profileJson['invoiceReceiptFooterTextEs'] ?? '')
            .toString()
            .trim()
            .isNotEmpty;
    final appLang = appConfig.currentLanguage;
    final localizedFooter = localizedFooterFromProfile(appLang);
    final legacyFooter = profile.invoiceReceiptFooterText.trim();
    final footerText = localizedFooter.isNotEmpty
        ? localizedFooter
        : (legacyFooter.isNotEmpty &&
              (appLang == AppLanguage.nl || !hasAnyLocalizedFooter))
        ? legacyFooter
        : _receiptText('pdfFooterDefault');

    final logoRef = resolveDocumentCompanyLogoRef(
      localPath: settings.logoAssetPath.trim(),
      companyLogoUrl: profile.publicLogoUrl.trim(),
      configuredFluxidiAsset: kFluxidiLogoAsset,
      fileExists: (path) => File(path).existsSync(),
    );
    return <String, String>{
      'companyName': companyName,
      'legalName': legalName,
      'address': address,
      'vatNumber': profile.vatNumber.trim().isNotEmpty
          ? profile.vatNumber.trim()
          : settings.vatCompanyNumber.trim(),
      'phone': profile.phone.trim().isNotEmpty
          ? profile.phone.trim()
          : settings.supportPhone.trim(),
      'email': profile.email.trim().isNotEmpty
          ? profile.email.trim()
          : settings.supportEmail.trim(),
      'website': profile.website.trim(),
      'footer': footerText,
      'logoPath': logoRef.ref,
    };
  }

  pw.Widget _pdfInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 140,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }

  Future<_ReceiptPdfBundle?> _buildReceiptPdfBundle(
    BuildContext context,
  ) async {
    final backendBundle =
        await _ReceiptPdfActionRunner._tryFetchBackendInvoicePdfBundle(
          item: item,
          source: 'receipt_pdf_bundle_stateful_layout',
        );
    if (backendBundle != null) return backendBundle;
    try {
      final smartRef = _businessReferenceDisplayForItem(
        item,
        source: 'receipt_pdf_bundle_stateful_layout',
      );
      _logPdfContactResolution();
      final route = _resolvedRouteForPdf();
      final seller = await _buildSellerProfile();
      final logoBytes = await _loadReceiptLogoBytes(seller['logoPath']);
      final doc = pw.Document();
      final baseFont = await PdfGoogleFonts.notoSansRegular();
      final boldFont = await PdfGoogleFonts.notoSansBold();
      final amounts = _resolvedReceiptAmounts();
      final paymentStatusRaw = _firstDetailPathText(const [
        ['payment_status'],
        ['paymentStatus'],
        ['booking', 'payment_status'],
        ['booking', 'paymentStatus'],
        ['mollie', 'status'],
        ['record', 'mollie', 'status'],
      ]);
      final paymentProviderRaw = _firstDetailPathText(const [
        ['payment_provider'],
        ['paymentProvider'],
        ['booking', 'payment_provider'],
        ['booking', 'paymentProvider'],
      ]);
      final paymentMethod = _localizedPaymentMethodValue(
        _paymentFieldWithMolliePaidFallback(
          value: _paymentMethodFromDetails(),
          paymentStatus: paymentStatusRaw,
          paymentProvider: paymentProviderRaw,
        ),
      );
      final paymentSource = _localizedPaymentSourceValue(
        _paymentFieldWithMolliePaidFallback(
          value: _paymentSourceFromDetails(),
          paymentStatus: paymentStatusRaw,
          paymentProvider: paymentProviderRaw,
        ),
      );
      final rideDateText = _detailText('scheduled_pickup_at') != null
          ? _formatDate(_detailText('scheduled_pickup_at'))
          : _formatDate(item.startedAt);
      final serviceText = _displayServiceToken(_detailText('service_type'));
      final tierText = _displayTierToken(_detailText('tier'));
      final durationText =
          _minutesText('duration_route_min') ??
          _minutesText('route_minutes') ??
          _receiptText('notAvailable');
      final roundtripProjection =
          _ReceiptPdfActionRunner._roundtripProjectionForPdf(item);
      // Leg-first business rule: a ritbon proves ONE operational leg.
      // Suppress the roundtrip PDF section when this is a leg receipt
      // even if the derived projection succeeds. Detection lives in
      // `_isLegReceiptItem`.
      final isLegReceipt = _ReceiptPdfActionRunner._isLegReceiptItem(item);
      final completedRoundtripReceipt =
          !isLegReceipt &&
          _ReceiptPdfActionRunner._isCompletedRoundtripProjection(
            roundtripProjection,
          );
      _ReceiptPdfActionRunner._logReceiptPdfRoute(
        item: item,
        source: 'driver_receipt',
        builder: 'stateful',
        isRoundtrip: completedRoundtripReceipt,
        isLegReceipt: isLegReceipt,
      );
      final businessFields = _resolvedReceiptBusinessFields();
      debugPrint(
        '[RECEIPT][BUSINESS_FIELDS] source=stateful_pdf booking=${_safeRefPreview(item.bookingId ?? item.tripId)} business=${businessFields.isBusinessDocument} invoiceRequested=${businessFields.invoiceRequested} companyFound=${businessFields.companyName.isNotEmpty} vatFound=${businessFields.vatNumber.isNotEmpty} invoiceEmailFound=${businessFields.invoiceEmail.isNotEmpty} invoiceAddressFound=${businessFields.invoiceAddress.isNotEmpty}',
      );
      // #region agent log H5 stateful receipt business projection
      unawaited(
        _agentDebugLog(
          runId: 'initial',
          hypothesisId: 'H5',
          location: 'main.dart:_RideReceiptBodyState._buildReceiptPdfBundle',
          message: '[RECEIPT][BUSINESS_FIELDS]',
          data: <String, dynamic>{
            'source': 'stateful_pdf',
            'booking': _safeRefPreview(item.bookingId ?? item.tripId),
            'business': businessFields.isBusinessDocument,
            'invoiceRequested': businessFields.invoiceRequested,
            'companyFound': businessFields.companyName.isNotEmpty,
            'vatFound': businessFields.vatNumber.isNotEmpty,
            'invoiceEmailFound': businessFields.invoiceEmail.isNotEmpty,
            'invoiceAddressFound': businessFields.invoiceAddress.isNotEmpty,
          },
        ),
      );
      // #endregion
      final documentTitle = businessFields.isBusinessDocument
          ? _receiptText('invoiceLabel')
          : _tr(
              nl: 'Ritbon / Particuliere verkoop',
              en: 'Ride receipt / Private sale',
              fr: 'Reçu de course / Vente particulière',
              es: 'Recibo de viaje / Venta particular',
            );
      final footerText = seller['footer']?.trim().isNotEmpty == true
          ? seller['footer']!.trim()
          : _receiptText('pdfFooterDefault');

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (pw.Context pdfContext) => [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (logoBytes != null)
                  pw.Container(
                    width: kReceiptPdfLogoBoxWidth,
                    height: kReceiptPdfLogoBoxHeight,
                    color: PdfColors.white,
                    child: pw.Image(
                      pw.MemoryImage(logoBytes),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        seller['companyName'] ?? kCompanyName,
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          font: boldFont,
                        ),
                        textAlign: pw.TextAlign.right,
                      ),
                      if ((seller['legalName'] ?? '').trim().isNotEmpty &&
                          seller['legalName'] != seller['companyName'])
                        pw.Text(
                          seller['legalName']!,
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['address'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          seller['address']!,
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['vatNumber'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyVat')}: ${seller['vatNumber']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['phone'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyPhone')}: ${seller['phone']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['email'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyEmail')}: ${seller['email']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['website'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyWebsite')}: ${seller['website']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              documentTitle,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 10),
            _pdfInfoRow(smartRef.label, smartRef.value),
            _pdfInfoRow(_receiptText('date'), rideDateText),
            _pdfInfoRow(_receiptText('type'), item.kindLabel),
            _pdfInfoRow(_receiptText('service'), serviceText),
            _pdfInfoRow(_receiptText('tier'), tierText),
            if (completedRoundtripReceipt)
              ..._ReceiptPdfActionRunner._completedRoundtripPdfRows(
                item,
                boldFont,
              )
            else ...[
              _pdfInfoRow(_receiptText('from'), route.from),
              _pdfInfoRow(_receiptText('to'), route.to),
              _pdfInfoRow(
                _receiptText('distance'),
                isLegReceipt
                    ? _ReceiptPdfActionRunner._legReceiptDistanceText(item)
                    : _kmText(),
              ),
              _pdfInfoRow(
                _receiptText('duration'),
                isLegReceipt
                    ? (_ReceiptPdfActionRunner._legReceiptDurationMinutes(
                            item,
                          ) ??
                          _receiptText('notAvailable'))
                    : durationText,
              ),
              if (isLegReceipt)
                _pdfInfoRow(
                  _receiptText('rideStatus'),
                  _ReceiptPdfActionRunner._legReceiptRideStatusDisplay(item),
                ),
            ],
            pw.SizedBox(height: 12),
            pw.Text(
              _receiptText('customerDetails'),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 6),
            _pdfInfoRow(
              _receiptText('customerName'),
              _customerName ?? _receiptText('notAvailable'),
            ),
            _pdfInfoRow(
              _receiptText('customerEmail'),
              _customerEmail ?? _receiptText('notAvailable'),
            ),
            _pdfInfoRow(
              _receiptText('customerPhone'),
              _customerPhoneRaw ?? _receiptText('notAvailable'),
            ),
            if (businessFields.isBusinessDocument) ...[
              pw.SizedBox(height: 12),
              pw.Text(
                _tr(
                  nl: 'Zakelijk / Factuur',
                  en: 'Business / Invoice',
                  fr: 'Professionnel / Facture',
                  es: 'Empresa / Factura',
                ),
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  font: boldFont,
                ),
              ),
              pw.SizedBox(height: 6),
              _pdfInfoRow(
                _tr(
                  nl: 'Bedrijfsnaam',
                  en: 'Company name',
                  fr: "Nom de l'entreprise",
                  es: 'Empresa',
                ),
                businessFields.companyName.isEmpty
                    ? _receiptText('notAvailable')
                    : businessFields.companyName,
              ),
              _pdfInfoRow(
                _tr(
                  nl: 'BTW-nummer',
                  en: 'VAT number',
                  fr: 'Numero de TVA',
                  es: 'NIF/IVA',
                ),
                businessFields.vatNumber.isEmpty
                    ? _receiptText('notAvailable')
                    : businessFields.vatNumber,
              ),
              _pdfInfoRow(
                _tr(
                  nl: 'Factuur e-mail',
                  en: 'Invoice email',
                  fr: 'E-mail facture',
                  es: 'Email de factura',
                ),
                businessFields.invoiceEmail.isEmpty
                    ? _receiptText('notAvailable')
                    : businessFields.invoiceEmail,
              ),
              _pdfInfoRow(
                _tr(
                  nl: 'Factuuradres',
                  en: 'Invoice address',
                  fr: 'Adresse de facturation',
                  es: 'Direccion de factura',
                ),
                businessFields.invoiceAddress.isEmpty
                    ? _receiptText('notAvailable')
                    : businessFields.invoiceAddress,
              ),
            ],
            pw.SizedBox(height: 12),
            pw.Text(
              _receiptText('paymentActions'),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 6),
            _pdfInfoRow(_receiptText('paymentStatus'), _paymentStatusText()),
            _pdfInfoRow(_receiptText('paymentMethod'), paymentMethod),
            if (businessFields.isBusinessDocument)
              _pdfInfoRow(_receiptText('paymentSource'), paymentSource),
            pw.Divider(color: PdfColors.grey400),
            _pdfInfoRow(
              _receiptText('subtotalExVat'),
              '€ ${amounts.subtotal.toStringAsFixed(2)}',
            ),
            _pdfInfoRow(
              '${_receiptText('vatAmount')} (${(amounts.vatRate * 100).toStringAsFixed(0)}%)',
              '€ ${amounts.vatAmount.toStringAsFixed(2)}',
            ),
            _pdfInfoRow(
              _receiptText('total'),
              '€ ${amounts.total.toStringAsFixed(2)}',
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              footerText,
              style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
            ),
          ],
          theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        ),
      );

      final bytes = await doc.save();
      final tempDir = await getTemporaryDirectory();
      final receiptsDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}fluxidi_receipts',
      );
      if (!await receiptsDir.exists()) {
        await receiptsDir.create(recursive: true);
      }
      final fileName = _sanitizeFilePart(_customerReference);
      final file = File(
        '${receiptsDir.path}${Platform.pathSeparator}$fileName.pdf',
      );
      await file.writeAsBytes(bytes, flush: true);
      return _ReceiptPdfBundle(bytes: bytes, file: file);
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('pdfGenerationFailed'))),
        );
      }
      return null;
    }
  }

  Future<void> _viewReceiptPdf(BuildContext context) async {
    final bundle = await _buildReceiptPdfBundle(context);
    if (bundle == null) {
      if (!mounted) return;
      await _shareReceipt(this.context);
      return;
    }
    if (!widget.showReceiptUi) {
      debugPrint('[PDF][ACTION][CUSTOMER_DIRECT_VIEW] hasPdf=true');
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReceiptPdfPreviewPage(
          title: _receiptText('viewPdf'),
          bytes: bundle.bytes,
        ),
      ),
    );
  }

  Future<void> _shareReceiptPdf(BuildContext context) async {
    final bundle = await _buildReceiptPdfBundle(context);
    if (bundle == null) {
      if (!mounted) return;
      await _shareReceipt(this.context);
      return;
    }
    if (!widget.showReceiptUi) {
      debugPrint('[PDF][ACTION][CUSTOMER_DIRECT_SHARE] hasPdf=true');
    }
    debugPrint('[PDF][ACTION][PDF_SHARE] hasPdf=true');
    await Share.shareXFiles(
      <XFile>[XFile(bundle.file.path)],
      text: _receiptCustomerMessage(),
      subject: _receiptText('receiptEmailSubject'),
    );
  }

  Future<void> _shareReceiptPdfViaWhatsApp(BuildContext context) async {
    final bundle = await _buildReceiptPdfBundle(context);
    if (bundle == null) {
      if (!mounted) return;
      await _sendReceiptWhatsApp(this.context);
      return;
    }
    final phone = _customerPhoneE164;
    final phoneFound = phone != null;
    const packageTarget = 'share_sheet';
    debugPrint(
      '[PDF][ACTION][WHATSAPP_PDF] phoneFound=$phoneFound hasPdf=true packageTarget=$packageTarget',
    );

    if (phoneFound && context.mounted) {
      await Clipboard.setData(ClipboardData(text: phone));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Klantnummer gekopieerd. Kies WhatsApp en selecteer of plak de klant om de PDF te sturen.',
              en: 'Customer number copied. Choose WhatsApp and select or paste the customer to send the PDF.',
              fr: 'Numéro client copié. Choisissez WhatsApp puis sélectionnez ou collez le client pour envoyer le PDF.',
              es: 'Número del cliente copiado. Elija WhatsApp y seleccione o pegue el cliente para enviar el PDF.',
            ),
          ),
        ),
      );
    }

    final message = _tr(
      nl: 'Beste klant, in bijlage vindt u uw betaalbewijs/ritbon (PDF).',
      en: 'Dear customer, your ride receipt PDF is attached.',
      fr: 'Cher client, votre reçu de course PDF est en pièce jointe.',
      es: 'Estimado cliente, su comprobante de viaje en PDF está adjunto.',
    );

    try {
      await Share.shareXFiles(
        <XFile>[XFile(bundle.file.path)],
        text: message,
        subject: _receiptText('whatsappPdf'),
      );
    } catch (_) {
      if (!mounted) return;
      await _sendReceiptWhatsApp(this.context);
    }
  }

  Future<void> _shareReceiptPdfViaEmail(BuildContext context) async {
    await _ReceiptPdfActionRunner.sharePdfViaEmail(
      context: context,
      item: item,
    );
  }

  Future<void> _printReceiptPdf(BuildContext context) async {
    final bundle = await _buildReceiptPdfBundle(context);
    if (bundle == null) {
      if (!mounted) return;
      _printReceiptPlaceholder(this.context);
      return;
    }
    await Printing.layoutPdf(onLayout: (_) async => bundle.bytes);
  }

  void _showPaymentLink(BuildContext context) {
    if (!_guardDriverReceiptOperation(action: 'payment_link')) return;
    _markPaymentRequestSent();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_receiptText('paymentLink')),
        content: SelectableText(_paymentLink()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(_receiptText('close')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _copyPaymentLink(context);
            },
            child: Text(_receiptText('copy')),
          ),
        ],
      ),
    );
  }

  void _showPaymentQr(BuildContext context) {
    if (!_guardDriverReceiptOperation(action: 'payment_qr')) return;

    // MOLLIE-OPEN-PAYMENT-RECOVERY-P0: block EPC QR while Mollie may settle.
    if (_openMollieBlocksFallback) {
      _showOpenMollieRecoveryDialog(context).then((choice) async {
        if (!context.mounted) return;
        if (choice != null &&
            choice != MollieOpenPaymentRecoveryChoice.dismiss) {
          await _runOpenMollieRecoveryAction(context, choice: choice);
        }
      });
      return;
    }

    final rideRefMasked = _safeRefPreview(item.bookingId ?? item.tripId);

    // 1) Booking owner scope must be present on the ride record itself.
    final bookingFieldHits = <String>{};
    final bookingScope = _bookingOwnerScopeForBankPayment(
      presentFields: bookingFieldHits,
    );
    if (bookingScope == null) {
      final bookingDetailKeys = item.bookingDetails.keys
          .map((k) => k.toString())
          .take(10)
          .join(',');
      final rawSourceKeys = item.rawSource.keys
          .map((k) => k.toString())
          .take(10)
          .join(',');
      debugPrint(
        '[QR_PAYMENT][CONFIG] status=missing_booking_scope ref=$rideRefMasked bookingFields=- bookingDetailsKeys=$bookingDetailKeys rawSourceKeys=$rawSourceKeys',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_bankPaymentScopeMismatchMessage())),
      );
      return;
    }

    // 2) Active company scope must be present (no fallback to central/demo).
    final activeScope = _activeCompanyScopeForBankPayment();
    if (activeScope == null) {
      debugPrint(
        '[QR_PAYMENT][CONFIG] status=missing_active_scope ref=$rideRefMasked rideTenant=${_maskScopeForLog(bookingScope.tenantId)} rideCompany=${_maskScopeForLog(bookingScope.companyId)} bookingFields=${bookingFieldHits.join(',')}',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_bankPaymentScopeMismatchMessage())),
      );
      return;
    }

    // 3) Both tenantId AND companyId must match (case-insensitive, trimmed,
    // whitespace-normalized). The cached business profile is implicitly
    // scoped to the active session, so any mismatch here would mean we'd
    // otherwise hand the customer another company's IBAN.
    String normalize(String value) =>
        value.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final tenantMatch =
        normalize(bookingScope.tenantId) == normalize(activeScope.tenantId);
    final companyMatch =
        normalize(bookingScope.companyId) == normalize(activeScope.companyId);
    if (!tenantMatch || !companyMatch) {
      debugPrint(
        '[QR_PAYMENT][CONFIG] status=scope_mismatch ref=$rideRefMasked tenant_match=$tenantMatch company_match=$companyMatch bookingTenant=${_maskScopeForLog(bookingScope.tenantId)} bookingCompany=${_maskScopeForLog(bookingScope.companyId)} activeTenant=${_maskScopeForLog(activeScope.tenantId)} activeCompany=${_maskScopeForLog(activeScope.companyId)} source=${activeScope.source} bookingFields=${bookingFieldHits.join(',')} tenantAliasSource=${bookingScope.tenantSource} companyAliasSource=${bookingScope.companySource}',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_bankPaymentScopeMismatchMessage())),
      );
      return;
    }

    // 4) Now safe to read the cached business profile IBAN/beneficiary.
    final details = _bankPaymentDetails();
    if (!details.isComplete) {
      debugPrint(
        '[QR_PAYMENT][CONFIG] status=missing_bank_details ref=$rideRefMasked tenant=${_maskScopeForLog(activeScope.tenantId)} company=${_maskScopeForLog(activeScope.companyId)} source=${activeScope.source} iban_present=false beneficiary_present=${details.beneficiary.isNotEmpty}',
      );
      debugPrint(
        '[QR_PAYMENT][PAYLOAD] type=epc tenant=${_maskScopeForLog(activeScope.tenantId)} company=${_maskScopeForLog(activeScope.companyId)} amount=${details.amount.toStringAsFixed(2)} ref=${_safeRefPreview(_customerReference)} status=setup_missing',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_bankPaymentSetupMissingMessage())),
      );
      return;
    }

    // PAYMENT-AUTH-P0-1: opening (or copying) the local EPC QR is not a
    // payment confirmation ÔÇö it must never optimistically mark the receipt
    // "sent"/paid. Payment state only changes after the backend confirms an
    // authoritative mark-paid in `_persistInCarPayment`.
    final epcPayload = _bankPaymentEpcPayload(details);
    final clipboardText = _bankPaymentClipboardText(details);
    debugPrint(
      '[QR_PAYMENT][CONFIG] status=ok ref=$rideRefMasked tenant=${_maskScopeForLog(activeScope.tenantId)} company=${_maskScopeForLog(activeScope.companyId)} source=matched_business_profile iban_present=true iban_masked=${_maskIbanForLog(details.iban)} bookingFields=${bookingFieldHits.join(',')}',
    );
    debugPrint(
      '[QR_PAYMENT][PAYLOAD] type=epc tenant=${_maskScopeForLog(activeScope.tenantId)} company=${_maskScopeForLog(activeScope.companyId)} amount=${details.amount.toStringAsFixed(2)} ref=${_safeRefPreview(_customerReference)}',
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_receiptText('qrPayment')),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: QrImageView(
                  data: epcPayload,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  _moneyText(_selectedPaymentAmount()),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                clipboardText,
                textAlign: TextAlign.left,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              Text(
                _receiptText('qrReadyToScan'),
                style: TextStyle(
                  fontSize: 12,
                  color: _palette.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(_receiptText('close')),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _persistInCarPayment(context: context, method: 'qr');
            },
            child: Text(_receiptText('confirmQrPaid')),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: clipboardText));
              // PAYMENT-AUTH-P0-1: copying the transfer details is not a
              // payment confirmation either ÔÇö no payment-status change here.
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(_bankPaymentCopySnackText())),
              );
            },
            child: Text(_bankPaymentCopyButtonLabel()),
          ),
        ],
      ),
    );
  }

  /// RELEASE-P0-MOLLIE-STREET-CHECKOUT-1: user-facing message for a failed
  /// `POST /bookings/:id/street-checkout` start attempt.
  String _mollieStreetCheckoutErrorMessage(MollieStreetCheckoutErrorKind kind) {
    switch (kind) {
      case MollieStreetCheckoutErrorKind.authRequired:
        return _receiptText('paymentAuthRequired');
      case MollieStreetCheckoutErrorKind.rideAlreadyPaid:
        return _receiptText('rideAlreadyPaid');
      case MollieStreetCheckoutErrorKind.mollieNotConnected:
        return _receiptText('mollieNotConnected');
      case MollieStreetCheckoutErrorKind.noOnlineMethods:
        return _receiptText('noOnlineMethods');
      case MollieStreetCheckoutErrorKind.notEligible:
      case MollieStreetCheckoutErrorKind.network:
      case MollieStreetCheckoutErrorKind.unknown:
        return _receiptText('paymentMarkFailed');
    }
  }

  /// RELEASE-P0-MOLLIE-STREET-CHECKOUT-1: starts (or reopens) the Mollie
  /// online checkout for this completed street/direct ride.
  ///
  /// Never sends `amount` as an authority in the request body — the
  /// booking-worker derives the payable amount server-side from the
  /// canonical booking record, matching the same "server decides the money"
  /// rule already enforced for QR/cash/terminal in [_persistInCarPayment].
  Future<void> _startMollieStreetCheckout(BuildContext context) async {
    if (_mollieCheckoutLoading) return;
    if (!_guardDriverReceiptOperation(action: 'street_checkout')) return;

    final strictScope = _strictReceiptPaymentScopeForMutation(
      context: context,
      action: 'street_checkout',
    );
    if (strictScope == null) return;

    final bookingId = (item.bookingId ?? '').trim();
    if (bookingId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_receiptText('bookingIdMissing'))));
      return;
    }

    final authHeaders = await resolveInCarPaymentAuthHeaders();
    if (authHeaders.mode == InCarPaymentAuthMode.none) {
      debugPrint('[MOLLIE_STREET_CHECKOUT][START] status=missing_auth');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('paymentAuthRequired'))),
      );
      return;
    }

    final maskedRef = _safeRefPreview(bookingId);
    setState(() => _mollieCheckoutLoading = true);
    try {
      final uri = Uri.parse(
        '$kBookingBaseUrl/bookings/${Uri.encodeComponent(bookingId)}/street-checkout',
      ).replace(queryParameters: strictScope);
      final payload = <String, dynamic>{
        ...strictScope,
        'return_url': kFluxidiPaymentReturnUrl,
      };
      debugPrint('[MOLLIE_STREET_CHECKOUT][START] booking=$maskedRef');
      final res = await http
          .post(uri, headers: authHeaders.headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 25));
      dynamic decodedRaw;
      try {
        decodedRaw = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        decodedRaw = null;
      }
      final decoded = decodedRaw is Map
          ? Map<String, dynamic>.from(decodedRaw)
          : <String, dynamic>{};
      if (res.statusCode == 401) {
        throw const _InCarPaymentAuthRequiredException();
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final kind = classifyMollieStreetCheckoutStartError(
          httpCode: res.statusCode,
          decoded: decoded,
        );
        debugPrint(
          '[MOLLIE_STREET_CHECKOUT][START][ERROR] booking=$maskedRef '
          'code=${res.statusCode} kind=${kind.name}',
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mollieStreetCheckoutErrorMessage(kind))),
        );
        return;
      }
      final result = parseMollieStreetCheckoutStartResponse(decoded);
      if (!result.ok || !result.hasCheckout) {
        debugPrint(
          '[MOLLIE_STREET_CHECKOUT][START][NO_CHECKOUT] booking=$maskedRef',
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('noOnlineMethods'))),
        );
        return;
      }
      debugPrint(
        '[MOLLIE_STREET_CHECKOUT][START][OK] booking=$maskedRef '
        'reused=${result.reused} hasQr=${(result.qrSrc ?? '').isNotEmpty} '
        'hasCheckoutUrl=${(result.checkoutUrl ?? '').isNotEmpty}',
      );
      final paymentBookingId = (result.paymentBookingId ?? '').trim();
      if (paymentBookingId.isNotEmpty) {
        setFluxidiPendingPayment(
          paymentBookingId: paymentBookingId,
          publicBookingId: bookingId,
        );
      }
      if (!context.mounted) return;
      await _showMollieStreetCheckoutDialog(
        context,
        result: result,
        strictScope: strictScope,
      );
    } catch (err) {
      final isAuthFailure = err is _InCarPaymentAuthRequiredException;
      debugPrint(
        '[MOLLIE_STREET_CHECKOUT][START][EXCEPTION] booking=$maskedRef '
        'auth_failure=$isAuthFailure error=$err',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAuthFailure
                ? _receiptText('paymentAuthRequired')
                : _receiptText('paymentMarkFailed'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _mollieCheckoutLoading = false);
    }
  }

  /// Shows the online-checkout dialog (reusing [PaymentQrPanel] for the QR /
  /// "open payment page" affordance) and starts the bounded `/pay/status`
  /// poll for [result.paymentBookingId]. Resolves once the dialog closes,
  /// either because polling reached a terminal outcome or the driver
  /// dismissed it manually.
  Future<void> _showMollieStreetCheckoutDialog(
    BuildContext context, {
    required MollieStreetCheckoutStartResult result,
    required Map<String, String> strictScope,
  }) async {
    final language = appConfig.currentLanguage;
    final amountText = _moneyText(result.amount ?? _selectedPaymentAmount());
    final safeCheckoutUrl = (result.checkoutUrl ?? '').trim();
    final qrSrc = (result.qrSrc ?? '').trim();
    final paymentBookingId = (result.paymentBookingId ?? '').trim();

    final outcome = await showDialog<MollieStreetCheckoutPollOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(_receiptText('onlinePay')),
        content: SizedBox(
          width: 300,
          child: MollieStreetCheckoutDialogContent(
            language: language,
            qrSrc: qrSrc,
            checkoutUrl: safeCheckoutUrl.isEmpty ? null : safeCheckoutUrl,
            amountText: amountText,
            paymentBookingId: paymentBookingId,
            canonicalBookingId: (item.bookingId ?? '').trim(),
            textMutedColor: _palette.textMuted,
            pendingPaymentListenable: fluxidiPendingPaymentNotifier,
            copy: MollieStreetCheckoutCopy(
              title: _receiptText('onlinePay'),
              instruction: _receiptText('onlinePayInstruction'),
              waitingText: _receiptText('waitingForPayment'),
              processingText: _receiptText('paymentStillProcessing'),
              succeededText: _receiptText('paymentSucceeded'),
              failedText: _receiptText('paymentFailed'),
              cancelledText: _receiptText('paymentCancelled'),
              expiredText: _receiptText('paymentExpired'),
              iHavePaidLabel: _receiptText('iHavePaid'),
              closeLabel: _receiptText('close'),
              statusAuthErrorText: _receiptText('paymentStatusAuthError'),
              statusNotFoundErrorText: _receiptText(
                'paymentStatusNotFoundError',
              ),
              statusServerErrorText: _receiptText('paymentStatusServerError'),
              statusGenericErrorText: _receiptText(
                'paymentStatusGenericError',
              ),
            ),
            pollOnce: () => _pollMollieStreetCheckoutStatusOnce(
              paymentBookingId: paymentBookingId,
              strictScope: strictScope,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(_receiptText('close')),
          ),
        ],
      ),
    );

    if (!context.mounted) return;
    // Always refresh canonical booking after modal close (paid or not).
    await _refreshCanonicalReceiptAfterStreetMollieModal(
      context,
      dialogOutcome: outcome,
    );
  }

  /// Single `GET /pay/status` attempt for a street-checkout in-flight
  /// payment. Uses company-first [resolveMollieStreetStatusAuthHeaders].
  Future<MollieStreetCheckoutPollResult> _pollMollieStreetCheckoutStatusOnce({
    required String paymentBookingId,
    required Map<String, String> strictScope,
  }) async {
    final bookingId = (item.bookingId ?? '').trim();
    if (paymentBookingId.isEmpty) {
      return const MollieStreetCheckoutPollResult(
        outcome: MollieStreetCheckoutPollOutcome.error,
        httpCode: 0,
        sanitizedErrorCode: 'missing_id',
      );
    }
    try {
      final authHeaders = await resolveMollieStreetStatusAuthHeaders(
        json: false,
      );
      if (authHeaders.mode == MollieStreetStatusAuthMode.none) {
        logMollieStreetStatusDiag(
          authMode: authHeaders.mode,
          httpStatus: 0,
          errorCode: 'missing_auth',
          paymentBookingId: paymentBookingId,
          canonicalBookingId: bookingId,
        );
        return const MollieStreetCheckoutPollResult(
          outcome: MollieStreetCheckoutPollOutcome.error,
          httpCode: 0,
          sanitizedErrorCode: 'unauthorized',
        );
      }
      final uri = Uri.parse('$kBookingBaseUrl/pay/status').replace(
        queryParameters: <String, String>{
          'id': paymentBookingId,
          ...strictScope,
        },
      );
      final res = await http
          .get(uri, headers: authHeaders.headers)
          .timeout(const Duration(seconds: 12));
      dynamic decodedRaw;
      try {
        decodedRaw = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        decodedRaw = null;
      }
      final root = decodedRaw is Map
          ? Map<String, dynamic>.from(decodedRaw)
          : <String, dynamic>{};
      final data = root['data'] is Map
          ? Map<String, dynamic>.from(root['data'] as Map)
          : root;
      final result = buildMollieStreetCheckoutPollResult(
        httpCode: res.statusCode,
        root: root,
        data: data,
      );
      logMollieStreetStatusDiag(
        authMode: authHeaders.mode,
        httpStatus: res.statusCode,
        errorCode: result.sanitizedErrorCode ?? result.outcome.name,
        paymentBookingId: paymentBookingId,
        canonicalBookingId: bookingId,
      );
      if (result.outcome == MollieStreetCheckoutPollOutcome.paid) {
        _mollieStreetCheckoutPollPaidData = data;
      }
      return result;
    } catch (e) {
      debugPrint('[MOLLIE_STREET_CHECKOUT][POLL][ERROR] $e');
      logMollieStreetStatusDiag(
        authMode: MollieStreetStatusAuthMode.none,
        httpStatus: 0,
        errorCode: 'network',
        paymentBookingId: paymentBookingId,
        canonicalBookingId: bookingId,
      );
      return MollieStreetCheckoutPollResult.error;
    }
  }

  /// After every street Mollie modal close: apply dialog outcome, then
  /// always run one authoritative canonical booking refresh so a server-paid
  /// ride cannot stay locally unpaid.
  Future<void> _refreshCanonicalReceiptAfterStreetMollieModal(
    BuildContext context, {
    required MollieStreetCheckoutPollOutcome? dialogOutcome,
  }) async {
    await _handleMollieStreetCheckoutDialogOutcome(context, dialogOutcome);

    final beforePaid = _paymentStatus == _ReceiptPaymentStatus.paid;
    final bookingId = (item.bookingId ?? '').trim();
    if (bookingId.isEmpty) return;

    final fields = await _fetchAuthoritativePaymentFields(bookingId);
    if (!mounted) return;

    if (fields == null || fields.isEmpty) {
      if (!beforePaid && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('paymentRefreshFailed'))),
        );
      }
      return;
    }

    _mergePaymentFieldsIntoReceiptDetails(fields);
    final authStatus =
        _mapText(fields, 'payment_status') ?? _mapText(fields, 'paymentStatus');
    final fromStatus = _paymentStatusFromRaw(authStatus);
    final authPaid = fromStatus == _ReceiptPaymentStatus.paid;

    if (!mounted) return;
    setState(() {
      if (shouldKeepReceiptPaidMonotonic(
        currentlyPaid: beforePaid || authPaid,
        authoritativeSaysPaid: authPaid,
        authoritativeReadSucceeded: true,
      )) {
        _paymentStatus = _ReceiptPaymentStatus.paid;
        return;
      }
      if (authPaid) {
        _paymentStatus = _ReceiptPaymentStatus.paid;
      }
    });

    if (authPaid) {
      clearFluxidiPendingPayment();
      if (!beforePaid &&
          dialogOutcome != MollieStreetCheckoutPollOutcome.paid &&
          context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('paymentSucceeded'))),
        );
      }
    }
  }

  Future<void> _handleMollieStreetCheckoutDialogOutcome(
    BuildContext context,
    MollieStreetCheckoutPollOutcome? outcome,
  ) async {
    switch (outcome) {
      case MollieStreetCheckoutPollOutcome.paid:
        await _markMollieStreetCheckoutPaid(context);
        return;
      case MollieStreetCheckoutPollOutcome.failed:
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_receiptText('paymentFailed'))),
          );
        }
        return;
      case MollieStreetCheckoutPollOutcome.cancelled:
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_receiptText('paymentCancelled'))),
          );
        }
        return;
      case MollieStreetCheckoutPollOutcome.expired:
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_receiptText('paymentExpired'))),
          );
        }
        return;
      case MollieStreetCheckoutPollOutcome.pending:
      case MollieStreetCheckoutPollOutcome.error:
      case null:
        // Dismissed without terminal status — canonical refresh runs next.
        return;
    }
  }

  /// Marks the receipt paid after `/pay/status` confirmed `paid`. Prefers
  /// re-fetching the authoritative booking record (same helper used by
  /// [_resolveReceiptPaymentStatus]) so the merged fields (method/provider/
  /// paid_at) come from the booking-worker's canonical record rather than
  /// being guessed from the `/pay/status` shape.
  Future<void> _markMollieStreetCheckoutPaid(BuildContext context) async {
    final bookingId = (item.bookingId ?? '').trim();
    final authoritative = bookingId.isEmpty
        ? null
        : await _fetchAuthoritativePaymentFields(bookingId);
    final pollData = _mollieStreetCheckoutPollPaidData ?? const <String, dynamic>{};
    final paidAtIso =
        (pollData['confirmed_at'] ?? pollData['confirmedAt'] ?? '')
                .toString()
                .trim()
                .isNotEmpty
        ? (pollData['confirmed_at'] ?? pollData['confirmedAt']).toString()
        : DateTime.now().toUtc().toIso8601String();
    final extracted = <String, dynamic>{
      'payment_status': 'paid',
      'paymentStatus': 'paid',
      'payment_method': 'mollie',
      'paymentMethod': 'mollie',
      'payment_source': 'online',
      'paymentSource': 'online',
      'payment_provider': 'mollie',
      'paymentProvider': 'mollie',
      'paid_at': paidAtIso,
      'paidAt': paidAtIso,
      ...?authoritative,
    };
    _mergePaymentFieldsIntoReceiptDetails(extracted);
    if (mounted) {
      setState(() => _paymentStatus = _ReceiptPaymentStatus.paid);
    }
    _appendPaymentUpdateLedgerIfPaid(
      fields: extracted,
      method: 'mollie',
      source: 'online',
      backendConfirmed: true,
    );
    clearFluxidiPendingPayment();
    debugPrint(
      '[MOLLIE_STREET_CHECKOUT][PAID] booking=${_safeRefPreview(bookingId)}',
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_receiptText('paymentSucceeded'))),
    );
  }

  bool get _openMollieBlocksFallback {
    final recovery = _openMollieRecovery;
    if (recovery != null) return recovery.isPendingOwner;
    return receiptDetailsHaveOpenMollieCheckout(
      Map<String, dynamic>.from(item.bookingDetails),
    );
  }

  /// MOLLIE-OPEN-PAYMENT-RECOVERY-P0: recoverable actions when an online
  /// Mollie checkout is still open (refresh / resume / cancel).
  Future<MollieOpenPaymentRecoveryChoice?> _showOpenMollieRecoveryDialog(
    BuildContext context, {
    MollieOpenPaymentRecoveryInfo? recovery,
  }) {
    final info = recovery ?? _openMollieRecovery;
    return showDialog<MollieOpenPaymentRecoveryChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_receiptText('openPaymentExists')),
        content: Text(_receiptText('openPaymentRecoveryBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              MollieOpenPaymentRecoveryChoice.dismiss,
            ),
            child: Text(_receiptText('close')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              MollieOpenPaymentRecoveryChoice.refresh,
            ),
            child: Text(_receiptText('checkPaymentStatus')),
          ),
          if (info?.resumable == true)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                MollieOpenPaymentRecoveryChoice.resume,
              ),
              child: Text(_receiptText('resumeOnlinePayment')),
            ),
          if (info?.cancelAllowed != false)
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                MollieOpenPaymentRecoveryChoice.cancel,
              ),
              child: Text(_receiptText('cancelOnlinePayment')),
            ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _postMollieCheckoutRecovery({
    required String bookingId,
    required String action,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse(
      '$kBookingBaseUrl/bookings/${Uri.encodeComponent(bookingId)}/mollie-checkout-recovery',
    );
    final res = await http
        .post(
          uri,
          headers: {...headers, 'content-type': 'application/json'},
          body: jsonEncode({'action': action}),
        )
        .timeout(const Duration(seconds: 12));
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      decoded = null;
    }
    final root = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    root['_http_code'] = res.statusCode;
    return root;
  }

  Future<void> _runOpenMollieRecoveryAction(
    BuildContext context, {
    required MollieOpenPaymentRecoveryChoice choice,
    String? pendingManualMethod,
  }) async {
    final bookingId = (item.bookingId ?? '').trim();
    if (bookingId.isEmpty) return;
    if (choice == MollieOpenPaymentRecoveryChoice.dismiss) return;

    if (choice == MollieOpenPaymentRecoveryChoice.resume) {
      await _startMollieStreetCheckout(context);
      return;
    }

    final authHeaders = await resolveInCarPaymentAuthHeaders();
    if (authHeaders.mode == InCarPaymentAuthMode.none) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('paymentAuthRequired'))),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _mollieRecoveryBusy = true);
    try {
      final action = choice == MollieOpenPaymentRecoveryChoice.cancel
          ? 'cancel'
          : 'refresh';
      final root = await _postMollieCheckoutRecovery(
        bookingId: bookingId,
        action: action,
        headers: authHeaders.headers,
      );
      if (!mounted || root == null) return;
      final recoveryHttp =
          (root['_http_code'] as num?)?.toInt() ??
          (root['http_code'] as num?)?.toInt();
      final recovery = parseMollieOpenPaymentRecovery(
        root,
        httpCode: recoveryHttp,
      );
      final payStatus = (root['payment_status'] ?? root['paymentStatus'] ?? '')
          .toString()
          .toLowerCase();
      if (payStatus == 'paid' || recovery?.presentationState == 'paid') {
        setState(() {
          _openMollieRecovery = null;
          _paymentStatus = _ReceiptPaymentStatus.paid;
        });
        await _markMollieStreetCheckoutPaid(context);
        return;
      }
      final released =
          recovery?.fallbackAllowed == true ||
          recovery?.presentationState == 'canceled' ||
          recovery?.presentationState == 'expired' ||
          recovery?.presentationState == 'failed';
      setState(() {
        _openMollieRecovery = released ? null : recovery;
      });
      if (!context.mounted) return;
      if (released) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('paymentOwnerReleased'))),
        );
        if (pendingManualMethod != null &&
            choice == MollieOpenPaymentRecoveryChoice.cancel) {
          await _persistInCarPayment(
            context: context,
            method: pendingManualMethod,
            confirmCancelOpenMollie: false,
          );
        }
        return;
      }
      if (root['ok'] != true && root['error'] == 'recovery_refresh_failed') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('paymentRecoveryError'))),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('paymentStillPending'))),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('paymentRecoveryError'))),
      );
    } finally {
      if (mounted) setState(() => _mollieRecoveryBusy = false);
    }
  }

  void _togglePaidDemo(BuildContext context) {
    setState(() {
      _paymentStatus = _paymentStatus == _ReceiptPaymentStatus.paid
          ? _ReceiptPaymentStatus.sent
          : _ReceiptPaymentStatus.paid;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${_receiptText('paymentStatus')}: ${_paymentStatusText()}',
        ),
      ),
    );
  }

  Future<void> _persistInCarPayment({
    required BuildContext context,
    required String method,
    // RELEASE-P0-MOLLIE-STREET-CHECKOUT-1: set on the retry after the driver
    // confirms cancelling an open Mollie checkout (see
    // `manualPaymentBlockedByOpenMollieCheckout` below). Only meaningful for
    // the booking-level payment path; leg/trip payment paths ignore it.
    bool confirmCancelOpenMollie = false,
  }) async {
    if (!_guardDriverReceiptOperation(action: 'persist_payment_$method'))
      return;
    final strictScope = _strictReceiptPaymentScopeForMutation(
      context: context,
      action: 'persist_in_car_payment',
    );
    if (strictScope == null) return;
    // PAYMENT-AUTH-P0-1: resolve the driver/company-owner bearer ONCE for
    // every in-car mark-paid path (QR, cash, manual card terminal). Never
    // fall back to an unauthenticated request ÔÇö the booking-worker payment
    // routes no longer accept the removed client ADMIN_TOKEN.
    final authHeaders = await resolveInCarPaymentAuthHeaders();
    if (authHeaders.mode == InCarPaymentAuthMode.none) {
      debugPrint(
        '[RECEIPT_PAYMENT][AUTH] status=missing_auth method=$method',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('paymentAuthRequired'))),
      );
      return;
    }
    final headers = authHeaders.headers;
    final bookingId = (item.bookingId ?? '').trim();
    final tripId = item.tripId.trim();
    final rawNormalizedMethod = method.toLowerCase().trim();
    // QR ("qr betaling") is conceptually a customer bank transfer for the
    // ENTIRE booking, never for an operational leg. Standardize the wire
    // method name to `qr_code` so it matches PaymentMethodCatalog and the
    // company bookings list / booking-finance aggregate downstream. Other
    // in-vehicle methods (cash, bancontact) keep their existing names.
    final isQrPayment =
        rawNormalizedMethod == 'qr' || rawNormalizedMethod == 'qr_code';
    final normalizedMethod = isQrPayment ? 'qr_code' : rawNormalizedMethod;
    final hasLegId = (_operationalLegIdForReceipt() ?? '').trim().isNotEmpty;
    final hasLegType = (_operationalLegTypeTokenForReceipt() ?? '')
        .trim()
        .isNotEmpty;
    final hasRowKey = (_operationalLegRowKeyForReceipt() ?? '')
        .trim()
        .isNotEmpty;
    final useLegBookingPaymentPath = _isPlannedOperationalLegPaymentItem();
    // Routing rule:
    //   * Operational-leg planned receipts (roundtrip / multi-leg) → booking-
    //     worker `POST /bookings/:parentId/legs/:legId/payment`. Marks only
    //     the current leg paid on the canonical record; parent becomes paid
    //     (and Document Core / Billit lifecycle runs) once all payable legs
    //     are paid.
    //   * Direct trips without a booking id → tracking-worker `/trip/payment`
    //     (local trip KV only; no canonical booking to reconcile).
    //   * Single-leg planned and direct/non-planned receipts → booking-
    //     worker `/bookings/:id/payment`.
    final useTripPaymentPath = bookingId.isEmpty && !useLegBookingPaymentPath;
    final selectedAmount = _selectedPaymentAmount();
    final selectedScope = _selectedPaymentScopeLabel();
    final legAmountForLog = _receiptTotalAmount();
    final bookingTotalForLog = _detailDouble('booking_total_eur');
    debugPrint(
      '[RECEIPT_PAYMENT][LEG_GUARD_DECISION] tripId=$tripId bookingId=$bookingId isPlannedReceipt=$_isPlannedReceipt hasLegId=$hasLegId hasLegType=$hasLegType hasRowKey=$hasRowKey useLegBookingPaymentPath=$useLegBookingPaymentPath method=$normalizedMethod isQr=$isQrPayment routing=${useLegBookingPaymentPath ? "booking_worker_leg_payment" : (useTripPaymentPath ? "tracking_trip_payment" : "booking_worker_payment")}',
    );
    debugPrint(
      '[QR_PAYMENT][AMOUNT_RESOLUTION] booking=${_safeRefPreview(bookingId)} leg_amount=${legAmountForLog ?? "-"} booking_total=${bookingTotalForLog ?? "-"} selected_amount=${selectedAmount ?? "-"} selected_scope=$selectedScope is_planned_operational_leg=${_isPlannedOperationalLegPaymentItem()} method=$normalizedMethod isQr=$isQrPayment routing=${useLegBookingPaymentPath ? "booking_worker_leg_payment" : (useTripPaymentPath ? "tracking_trip_payment" : "booking_worker_payment")}',
    );
    if (isQrPayment && bookingId.isEmpty && !useTripPaymentPath) {
      // QR routed through the booking-worker path requires a bookingId to
      // reconcile to the company booking; without one the booking-finance
      // contribution would never fire. The trip-payment path validates `tripId`
      // in its own branch below.
      debugPrint(
        '[QR_PAYMENT][CONFIRM] status=missing_booking_id tripId=$tripId ref=${_safeRefPreview(tripId)} method=$normalizedMethod amount=${selectedAmount ?? "-"}',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_receiptText('bookingIdMissing'))));
      return;
    }

    if (useLegBookingPaymentPath) {
      final parentBookingId = (_operationalLegParentBookingIdForReceipt() ?? '')
          .trim();
      final legId = (_operationalLegIdForReceipt() ?? '').trim();
      if (parentBookingId.isEmpty || legId.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('bookingIdMissing'))),
        );
        return;
      }
      final amount = selectedAmount;
      final paidAtIso = DateTime.now().toUtc().toIso8601String();
      final payload = <String, dynamic>{
        ...strictScope,
        'payment_status': 'paid',
        'payment_method': normalizedMethod,
        'payment_source': 'in_car',
        'payment_provider': 'manual',
        'currency': item.currency.trim().isEmpty
            ? 'EUR'
            : item.currency.trim().toUpperCase(),
        'paid_by_driver_id': kDriverId,
        'paid_at': paidAtIso,
        ..._driverMutationActorFields(
          actorVehicleId: (item.vehicleId ?? '').trim(),
        ),
        if (amount != null) 'amount': amount,
      };
      try {
        debugPrint(
          '[RECEIPT_PAYMENT][LEG_BOOKING_PAYMENT] parentBookingId=$parentBookingId legId=$legId tripId=$tripId method=$normalizedMethod amount=${amount ?? "-"}',
        );
        final uri = Uri.parse(
          '$kBookingBaseUrl/bookings/${Uri.encodeComponent(parentBookingId)}/legs/${Uri.encodeComponent(legId)}/payment',
        ).replace(queryParameters: strictScope);
        final res = await http
            .post(uri, headers: headers, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 12));
        final resBody = utf8.decode(res.bodyBytes);
        final bodyPreview = resBody.length > 240
            ? '${resBody.substring(0, 240)}...'
            : resBody;
        debugPrint(
          '[RECEIPT_PAYMENT][LEG_BOOKING_PAYMENT][RES] code=${res.statusCode} bodyPreview=$bodyPreview',
        );
        final decoded = jsonDecode(resBody);
        final root = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
        if (res.statusCode == 401) {
          throw const _InCarPaymentAuthRequiredException();
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception(
            (root['error'] ?? 'HTTP ${res.statusCode}').toString(),
          );
        }
        if (root['ok'] != true) {
          throw Exception((root['error'] ?? 'leg_payment_failed').toString());
        }
        final allLegsPaid = _receiptBoolish(
          root['all_legs_paid'] ?? root['allLegsPaid'],
        );
        final lifecycleRan = _receiptBoolish(
          root['lifecycle_ran'] ?? root['lifecycleRan'],
        );
        final legPaymentStatus =
            (root['leg_payment_status'] ?? root['legPaymentStatus'] ?? 'paid')
                .toString();
        final parentPaymentStatus =
            (root['parent_payment_status'] ?? root['parentPaymentStatus'] ?? '')
                .toString();
        final extracted = <String, dynamic>{
          'payment_status': legPaymentStatus,
          'paymentStatus': legPaymentStatus,
          'payment_method': normalizedMethod,
          'paymentMethod': normalizedMethod,
          'payment_source': 'in_car',
          'paymentSource': 'in_car',
          'payment_provider': 'manual',
          'paymentProvider': 'manual',
          'paid_at': paidAtIso,
          'paidAt': paidAtIso,
          'paid_by_driver_id': kDriverId,
          'paidByDriverId': kDriverId,
          if (amount != null) 'payment_amount': amount,
          if (amount != null) 'paymentAmount': amount,
          if (parentPaymentStatus.isNotEmpty)
            'parent_payment_status': parentPaymentStatus,
          if (parentPaymentStatus.isNotEmpty)
            'parentPaymentStatus': parentPaymentStatus,
          'all_legs_paid': allLegsPaid,
          'allLegsPaid': allLegsPaid,
          'lifecycle_ran': lifecycleRan,
          'lifecycleRan': lifecycleRan,
        };
        _mergePaymentFieldsIntoReceiptDetails(extracted);
        _appendPaymentUpdateLedgerIfPaid(
          fields: extracted,
          method: normalizedMethod,
          source: 'in_car',
          backendConfirmed: true,
        );
        if (mounted) {
          setState(() => _paymentStatus = _ReceiptPaymentStatus.paid);
        }
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              allLegsPaid
                  ? _legPaymentFullBookingSuccessMessage()
                  : _legPaymentPartialSuccessMessage(),
            ),
          ),
        );
      } catch (err) {
        final isAuthFailure = err is _InCarPaymentAuthRequiredException;
        debugPrint(
          '[RECEIPT][LEG_BOOKING_PAYMENT_FAILED] parentBookingId=${_safeRefPreview(parentBookingId)} legId=${_safeRefPreview(legId)} method=$method auth_failure=$isAuthFailure',
        );
        if (!context.mounted) return;
        if (isAuthFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_receiptText('paymentAuthRequired'))),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_legPaymentBackendErrorMessage(err.toString())),
          ),
        );
      }
      return;
    }

    if (useTripPaymentPath) {
      if (tripId.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('bookingIdMissing'))),
        );
        return;
      }
      final amount = selectedAmount;
      final paidAtIso = DateTime.now().toUtc().toIso8601String();
      final legId = (_operationalLegIdForReceipt() ?? '').trim();
      final legType = (_operationalLegTypeTokenForReceipt() ?? '').trim();
      final parentBookingId = (_operationalLegParentBookingIdForReceipt() ?? '')
          .trim();
      final rowKey = (_operationalLegRowKeyForReceipt() ?? '').trim();
      final payload = <String, dynamic>{
        'trip_id': tripId,
        if (bookingId.isNotEmpty) 'booking_id': bookingId,
        if (parentBookingId.isNotEmpty) 'parent_booking_id': parentBookingId,
        if (legId.isNotEmpty) 'leg_id': legId,
        if (legType.isNotEmpty) 'leg_type': legType,
        if (rowKey.isNotEmpty) 'row_key': rowKey,
        ...strictScope,
        'payment_status': 'paid',
        'payment_method': normalizedMethod,
        'payment_source': 'in_car',
        'currency': item.currency.trim().isEmpty
            ? 'EUR'
            : item.currency.trim().toUpperCase(),
        'paid_by_driver_id': kDriverId,
        'paid_at': paidAtIso,
        ..._driverMutationActorFields(
          actorVehicleId: (item.vehicleId ?? '').trim(),
        ),
        if (amount != null) 'amount': amount,
      };
      // NOTE (PAYMENT-AUTH-P0-1 scope boundary): this direct-trip fallback
      // path posts to the TRACKING worker's `/trip/payment` route, not the
      // booking-worker payment routes this repair targets. That route still
      // gates on `requireAdmin` server-side; migrating it is out of scope
      // here (tracking-worker changes are explicitly excluded from this
      // repair), so it intentionally keeps its own legacy header shape
      // rather than the resolved driver/company `headers` used above.
      final tripPaymentHeaders = <String, String>{
        'Content-Type': 'application/json',
      };
      if (kAdminToken.trim().isNotEmpty) {
        tripPaymentHeaders['x-admin-token'] = kAdminToken.trim();
      }
      try {
        final uri = Uri.parse(
          '$kWorkerBaseUrl/trip/payment',
        ).replace(queryParameters: strictScope);
        debugPrint(
          '[RECEIPT_PAYMENT][TRIP_PAYMENT] tripId=$tripId bookingId=$bookingId method=$normalizedMethod',
        );
        final res = await http
            .post(uri, headers: tripPaymentHeaders, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 12));
        final resBody = utf8.decode(res.bodyBytes);
        final bodyPreview = resBody.length > 240
            ? '${resBody.substring(0, 240)}...'
            : resBody;
        debugPrint(
          '[RECEIPT_PAYMENT][TRIP_PAYMENT][RES] code=${res.statusCode} bodyPreview=$bodyPreview',
        );
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception('HTTP ${res.statusCode}');
        }
        final decoded = jsonDecode(resBody);
        final root = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
        final payment = root['payment'] is Map
            ? Map<String, dynamic>.from(root['payment'] as Map)
            : <String, dynamic>{};
        final extracted = <String, dynamic>{
          'payment_status': (payment['payment_status'] ?? 'paid').toString(),
          'paymentStatus': (payment['payment_status'] ?? 'paid').toString(),
          'payment_method': (payment['payment_method'] ?? normalizedMethod)
              .toString(),
          'paymentMethod': (payment['payment_method'] ?? normalizedMethod)
              .toString(),
          'payment_source': (payment['payment_source'] ?? 'in_car').toString(),
          'paymentSource': (payment['payment_source'] ?? 'in_car').toString(),
          'paid_at': (payment['paid_at'] ?? paidAtIso).toString(),
          'paidAt': (payment['paid_at'] ?? paidAtIso).toString(),
          if (payment['paid_by_driver_id'] != null)
            'paid_by_driver_id': payment['paid_by_driver_id'].toString(),
          if (payment['paid_by_driver_id'] != null)
            'paidByDriverId': payment['paid_by_driver_id'].toString(),
          if (payment['amount'] != null) 'payment_amount': payment['amount'],
          if (payment['amount'] != null) 'paymentAmount': payment['amount'],
        };
        _mergePaymentFieldsIntoReceiptDetails(extracted);
        _appendPaymentUpdateLedgerIfPaid(
          fields: extracted,
          method: normalizedMethod,
          source: 'in_car',
          backendConfirmed: true,
        );
        if (mounted) {
          setState(() => _paymentStatus = _ReceiptPaymentStatus.paid);
        }
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('paymentMarkedPaid'))),
        );
      } catch (err) {
        debugPrint(
          '[RECEIPT][TRIP_PAYMENT_MARK_FAILED] tripId=$tripId method=$method err=$err',
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('paymentMarkFailed'))),
        );
      }
      return;
    }

    // Booking-level payment (single-leg planned / direct receipts) goes
    // through the booking-worker `/bookings/:id/payment` path. Operational-leg
    // roundtrip receipts take the leg-payment path above.
    final amount = selectedAmount;
    final paidAtIso = DateTime.now().toUtc().toIso8601String();
    final maskedRef = _safeRefPreview(bookingId);
    final maskedTenant = _maskScopeForLog(strictScope['tenant_id'] ?? '');
    final maskedCompany = _maskScopeForLog(strictScope['company_id'] ?? '');
    final payload = <String, dynamic>{
      'booking_id': bookingId,
      'payment_status': 'paid',
      'payment_method': normalizedMethod,
      'payment_source': 'in_car',
      // QR / cash / Bancontact via the driver receipt are always manual
      // confirmations (no Mollie checkout, no PSP id). Tag the provider
      // explicitly so the booking-worker stores it as such and the booking
      // finance aggregate uses the same canonical shape as other manual
      // confirmations.
      if (isQrPayment) 'payment_provider': 'manual',
      ...strictScope,
      'currency': item.currency.trim().isEmpty
          ? 'EUR'
          : item.currency.trim().toUpperCase(),
      'paid_by_driver_id': kDriverId,
      'paid_at': paidAtIso,
      ..._driverMutationActorFields(
        actorVehicleId: (item.vehicleId ?? '').trim(),
      ),
      if (amount != null) 'amount': amount,
      // RELEASE-P0-MOLLIE-STREET-CHECKOUT-1: only present on the driver-
      // confirmed retry after a 409 conflict reported an open Mollie
      // checkout for this booking (see `manualPaymentBlockedByOpenMollieCheckout`).
      if (confirmCancelOpenMollie) 'confirm_cancel_open_mollie': true,
    };

    if (isQrPayment) {
      debugPrint(
        '[QR_PAYMENT][CONFIRM] booking=$maskedRef amount=${amount ?? "-"} tenant=$maskedTenant company=$maskedCompany method=$normalizedMethod provider=manual source=in_car paid_at=$paidAtIso',
      );
    }
    try {
      debugPrint(
        '[RECEIPT_PAYMENT][PARENT_BOOKING_PAYMENT] bookingId=$bookingId method=$normalizedMethod amount=${amount ?? "-"} tenant=$maskedTenant company=$maskedCompany',
      );
      final uri = Uri.parse(
        '$kBookingBaseUrl/bookings/${Uri.encodeComponent(bookingId)}/payment',
      ).replace(queryParameters: strictScope);
      final res = await http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));
      if (isQrPayment) {
        final qrResBody = utf8.decode(res.bodyBytes);
        final qrBodyPreview = qrResBody.length > 240
            ? '${qrResBody.substring(0, 240)}...'
            : qrResBody;
        debugPrint(
          '[BOOKING_PAYMENT_UPDATE][QR] status=${res.statusCode} provider=manual amount=${amount ?? "-"} booking=$maskedRef tenant=$maskedTenant company=$maskedCompany endpoint=booking_worker bodyPreview=$qrBodyPreview',
        );
      }
      if (res.statusCode == 401) {
        throw const _InCarPaymentAuthRequiredException();
      }
      if (res.statusCode == 409) {
        dynamic conflictRaw;
        try {
          conflictRaw = jsonDecode(utf8.decode(res.bodyBytes));
        } catch (_) {
          conflictRaw = null;
        }
        final conflictBody = conflictRaw is Map
            ? Map<String, dynamic>.from(conflictRaw)
            : <String, dynamic>{};
        // RELEASE-P0-MOLLIE-STREET-CHECKOUT-1: a manual confirmation (cash /
        // Bancontact terminal / QR) can race an already-open online Mollie
        // checkout for the same ride. Offer the driver an explicit
        // cancel-and-continue confirmation instead of a bare failure; never
        // retry silently.
        if (manualPaymentBlockedByOpenMollieCheckout(
          httpCode: res.statusCode,
          decoded: conflictBody,
        )) {
          debugPrint(
            '[RECEIPT_PAYMENT][OPEN_MOLLIE_CONFLICT] booking=$maskedRef method=$normalizedMethod confirmCancelOpenMollie=$confirmCancelOpenMollie',
          );
          final recovery = parseMollieOpenPaymentRecovery(
            conflictBody,
            httpCode: res.statusCode,
          );
          if (mounted) {
            setState(() => _openMollieRecovery = recovery);
          }
          if (!confirmCancelOpenMollie) {
            if (!context.mounted) return;
            final choice = await _showOpenMollieRecoveryDialog(
              context,
              recovery: recovery,
            );
            if (!context.mounted) return;
            if (choice == MollieOpenPaymentRecoveryChoice.cancel) {
              // Controlled cancel via recovery API, then retry manual mark-paid
              // only after owner is released (never cancel blindly).
              await _runOpenMollieRecoveryAction(
                context,
                choice: MollieOpenPaymentRecoveryChoice.cancel,
                pendingManualMethod: method,
              );
              return;
            }
            if (choice == MollieOpenPaymentRecoveryChoice.refresh ||
                choice == MollieOpenPaymentRecoveryChoice.resume) {
              await _runOpenMollieRecoveryAction(context, choice: choice!);
              return;
            }
          }
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_receiptText('openPaymentExists'))),
          );
          return;
        }
        throw Exception('HTTP ${res.statusCode}');
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final root = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      final extracted =
          _extractAuthoritativePaymentFields(root) ?? <String, dynamic>{};
      extracted['payment_status'] = 'paid';
      extracted['paymentStatus'] = 'paid';
      extracted['payment_method'] = normalizedMethod;
      extracted['paymentMethod'] = normalizedMethod;
      extracted['payment_source'] = 'in_car';
      extracted['paymentSource'] = 'in_car';
      if (isQrPayment) {
        extracted['payment_provider'] ??= 'manual';
        extracted['paymentProvider'] ??= 'manual';
      }
      extracted['paid_at'] ??= payload['paid_at'];
      extracted['paidAt'] ??= payload['paid_at'];
      _mergePaymentFieldsIntoReceiptDetails(extracted);

      if (mounted) {
        setState(() => _paymentStatus = _ReceiptPaymentStatus.paid);
      }

      final paymentBookingId = _firstDetailPathText(const [
        ['payment_booking_id'],
        ['paymentBookingId'],
        ['booking', 'payment_booking_id'],
        ['booking', 'paymentBookingId'],
        ['record', 'payment_booking_id'],
        ['record', 'paymentBookingId'],
        ['record', 'booking', 'payment_booking_id'],
        ['record', 'booking', 'paymentBookingId'],
      ]);
      await CustomerBookingsStore.instance.markPaid(
        bookingId: bookingId,
        paymentBookingId: paymentBookingId,
      );
      _appendPaymentUpdateLedgerIfPaid(
        fields: extracted,
        method: normalizedMethod,
        source: 'in_car',
        backendConfirmed: true,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('paymentMarkedPaid'))),
      );
    } catch (err) {
      final isAuthFailure = err is _InCarPaymentAuthRequiredException;
      debugPrint(
        '[RECEIPT][PAYMENT_MARK_FAILED] booking=$maskedRef method=$method auth_failure=$isAuthFailure',
      );
      if (isQrPayment) {
        debugPrint(
          '[BOOKING_PAYMENT_UPDATE][QR] status=error booking=$maskedRef tenant=$maskedTenant company=$maskedCompany endpoint=booking_worker auth_failure=$isAuthFailure',
        );
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAuthFailure
                ? _receiptText('paymentAuthRequired')
                : _receiptText('paymentMarkFailed'),
          ),
        ),
      );
    }
  }

  Future<void> _shareReceipt(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _shareText()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_receiptText('receiptCopied'))));
  }

  void _comingSoon(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label ${_receiptText('comingSoon')}')),
    );
  }

  void _printReceiptPlaceholder(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_receiptText('printLater'))));
  }

  Widget _receiptRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: TextStyle(color: _palette.textMuted, fontSize: 13),
              softWrap: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 7,
            child: Text(
              value,
              textAlign: TextAlign.right,
              softWrap: true,
              style: TextStyle(
                color: highlight ? _palette.accent : _palette.textPrimary,
                fontWeight: highlight ? FontWeight.w900 : FontWeight.w700,
                fontSize: highlight ? 18 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionalReceiptRow(String label, String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return _receiptRow(label, text);
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          color: _palette.accent,
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  String? _minutesText(String key) {
    final value = _detailDouble(key);
    if (value == null) return null;
    final rounded = value.round();
    return '$rounded min';
  }

  String? _plannedSubtype() {
    final explicit = _detailText('subtype');
    if (explicit != null) return _localizedRideSubtype(explicit);
    if ((item.bookingId ?? '').endsWith('-R'))
      return _receiptText('returnRide');
    if (_isParentCompletedRoundtripReceipt()) {
      return _tr(
        nl: 'Heen-en-terug',
        en: 'Roundtrip',
        fr: 'Aller-retour',
        es: 'Ida y vuelta',
      );
    }
    if (_detailText('return_scheduled_pickup_at') != null ||
        _detailText('return_route') != null) {
      return _receiptText('outboundRide');
    }
    return null;
  }

  bool _isParentCompletedRoundtripReceipt() {
    // Leg-first business rule: a ritbon proves ONE operational leg, not
    // the parent roundtrip. When `_isLegReceiptItem` fires (explicit
    // leg_type / -R bookingId / receipt_total below booking_total) we
    // never treat the current ritbon as the parent roundtrip — that
    // keeps the on-screen subtype label as "Heenrit" / "Terugrit" and
    // suppresses the "Heen-en-terug" wording on the leg ritbon.
    if (_ReceiptPdfActionRunner._isLegReceiptItem(item)) return false;
    final projection = _detailAt(const ['roundtrip_price_projection']);
    if (projection is Map) {
      final mode = (projection['display_mode'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (mode == 'completed_roundtrip') return true;
    }
    final status = item.status.trim().toUpperCase();
    final completed = status == 'COMPLETED' || status == 'STOPPED';
    final package = _detailDouble('booking_total_eur') ?? item.totalEur;
    final outbound = _detailDouble('outbound_price_eur');
    final ret =
        _detailDouble('return_price_eur') ??
        _detailDouble('price_incl_vat_return');
    final packageMatchesSplit =
        package != null &&
        outbound != null &&
        ret != null &&
        (package - (outbound + ret)).abs() < 0.01;
    return completed &&
        packageMatchesSplit &&
        (_detailText('return_scheduled_pickup_at') != null ||
            _detailText('return_route') != null ||
            _detailText('return_pickup_iso') != null ||
            _detailText('price_incl_vat_return') != null ||
            _detailText('return_price_eur') != null);
  }

  String? _operationalLegTypeTokenForReceipt() {
    final raw = _firstDetailPathText(const [
      ['leg_type'],
      ['legType'],
      ['booking', 'leg_type'],
      ['booking', 'legType'],
      ['booking_details', 'leg_type'],
      ['booking_details', 'legType'],
      ['record', 'leg_type'],
      ['record', 'legType'],
      ['record', 'booking', 'leg_type'],
      ['record', 'booking', 'legType'],
    ])?.toLowerCase().trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.contains('return') || raw.contains('terug')) return 'return';
    if (raw.contains('outbound') || raw.contains('heen')) return 'outbound';
    return raw;
  }

  String? _operationalLegLabelForReceipt() {
    final token = _operationalLegTypeTokenForReceipt();
    if (token == null || token.isEmpty) return null;
    if (_isParentCompletedRoundtripReceipt()) {
      return _tr(
        nl: 'Heen-en-terug',
        en: 'Roundtrip',
        fr: 'Aller-retour',
        es: 'Ida y vuelta',
      );
    }
    if (token == 'return') {
      return _tr(nl: 'Terugrit', en: 'Return', fr: 'Retour', es: 'Vuelta');
    }
    if (token == 'outbound') {
      return _tr(nl: 'Heenrit', en: 'Outbound', fr: 'Aller', es: 'Ida');
    }
    return _plannedSubtype();
  }

  String? _operationalLegIdForReceipt() {
    return _firstDetailPathText(const [
      ['leg_id'],
      ['legId'],
      ['booking', 'leg_id'],
      ['booking', 'legId'],
      ['booking_details', 'leg_id'],
      ['booking_details', 'legId'],
      ['record', 'leg_id'],
      ['record', 'legId'],
      ['record', 'booking', 'leg_id'],
      ['record', 'booking', 'legId'],
    ]);
  }

  String? _operationalLegRowKeyForReceipt() {
    return _firstDetailPathText(const [
      ['row_key'],
      ['rowKey'],
      ['booking', 'row_key'],
      ['booking', 'rowKey'],
      ['booking_details', 'row_key'],
      ['booking_details', 'rowKey'],
      ['record', 'row_key'],
      ['record', 'rowKey'],
      ['record', 'booking', 'row_key'],
      ['record', 'booking', 'rowKey'],
    ]);
  }

  String? _operationalLegParentBookingIdForReceipt() {
    return _firstDetailPathText(const [
          ['parent_booking_id'],
          ['parentBookingId'],
          ['booking', 'parent_booking_id'],
          ['booking', 'parentBookingId'],
          ['booking_details', 'parent_booking_id'],
          ['booking_details', 'parentBookingId'],
          ['record', 'parent_booking_id'],
          ['record', 'parentBookingId'],
          ['record', 'booking', 'parent_booking_id'],
          ['record', 'booking', 'parentBookingId'],
        ]) ??
        (item.bookingId ?? '').trim();
  }

  bool _isPlannedOperationalLegPaymentItem() {
    if (!_isPlannedReceipt) return false;
    final tripId = item.tripId.trim();
    if (tripId.isEmpty || !tripId.toLowerCase().startsWith('planned_')) {
      return false;
    }
    final legId = (_operationalLegIdForReceipt() ?? '').trim();
    final legType = (_operationalLegTypeTokenForReceipt() ?? '').trim();
    final rowKey = (_operationalLegRowKeyForReceipt() ?? '').trim();
    return legId.isNotEmpty || legType.isNotEmpty || rowKey.isNotEmpty;
  }

  bool _receiptBoolish(dynamic value) {
    if (value is bool) return value;
    final raw = (value ?? '').toString().trim().toLowerCase();
    return raw == '1' || raw == 'true' || raw == 'yes' || raw == 'on';
  }

  String _legPaymentPartialSuccessMessage() {
    return _tr(
      nl: 'Deze rit is betaald. De volledige boeking is nog niet volledig betaald.',
      en: 'This leg is paid. The booking is not fully paid yet.',
      fr: 'Cette course est payee. La reservation nest pas encore entierement payee.',
      es: 'Este tramo esta pagado. La reserva aun no esta totalmente pagada.',
    );
  }

  String _legPaymentFullBookingSuccessMessage() {
    return _tr(
      nl: 'Boeking volledig betaald. Documenten worden klaargezet.',
      en: 'Booking fully paid. Documents are being prepared.',
      fr: 'Reservation entierement payee. Les documents sont en preparation.',
      es: 'Reserva totalmente pagada. Los documentos se estan preparando.',
    );
  }

  String _legPaymentBackendErrorMessage(String rawError) {
    final detail = rawError.replaceFirst('Exception: ', '').trim();
    if (detail.isEmpty) return _receiptText('paymentMarkFailed');
    return _tr(
      nl: 'Betaling mislukt: $detail',
      en: 'Payment failed: $detail',
      fr: 'Echec du paiement : $detail',
      es: 'Error de pago: $detail',
    );
  }

  String? _routeSegmentsText() {
    final raw = item.bookingDetails['route_segments'];
    if (raw is! List || raw.isEmpty) return null;
    // Leg-first business rule: a ritbon proves ONE operational leg, so
    // the "Route details" row only renders the active leg's segment.
    // Outbound → route_segments[0], return → route_segments[1].
    final isLegReceipt = _ReceiptPdfActionRunner._isLegReceiptItem(item);
    final activeIndex = isLegReceipt
        ? (_ReceiptPdfActionRunner._legReceiptActiveLegToken(item) == 'return'
              ? 1
              : 0)
        : -1;
    final lines = <String>[];
    for (var i = 0; i < raw.length; i++) {
      if (activeIndex >= 0 && i != activeIndex) continue;
      final segment = raw[i];
      if (segment is! Map) continue;
      final from = segment['from']?.toString().trim();
      final to = segment['to']?.toString().trim();
      final distance = _segmentNumber(segment['distance_km']);
      final duration = _segmentNumber(segment['duration_min']);
      final parts = <String>[
        if (from != null && from.isNotEmpty) from,
        if (to != null && to.isNotEmpty) '→ $to',
      ];
      final meta = <String>[
        if (distance != null) '${distance.toStringAsFixed(1)} km',
        if (duration != null) '${duration.round()} min',
      ].join(', ');
      final route = parts.isEmpty
          ? '${_receiptText('route')} ${i + 1}'
          : parts.join(' ');
      // Leg-first: drop the numeric prefix because there's only one row.
      final prefix = activeIndex >= 0 ? '' : '${i + 1}. ';
      lines.add('$prefix$route${meta.isEmpty ? '' : ': $meta'}');
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  double? _segmentNumber(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.'));
  }

  /// RELEASE-P0-MOLLIE-STREET-CHECKOUT-1: whether the primary "Online
  /// betalen" action may be offered for this receipt. Delegates the actual
  /// decision to the pure [resolveMollieStreetCheckoutEligible] so the rule
  /// (street/direct ride, unpaid, positive amount, not cancelled, has a
  /// booking id) is unit-testable without Flutter.
  bool _mollieStreetCheckoutEligible() {
    final bookingId = (item.bookingId ?? '').trim();
    if (bookingId.isEmpty) return false;
    final statusToken = item.status.trim().toUpperCase().replaceAll(
      RegExp(r'[-\s]+'),
      '_',
    );
    return resolveMollieStreetCheckoutEligible(
      bookingId: bookingId,
      isPaid: _isEffectiveReceiptPaid(),
      isCancelled: statusToken.contains('CANCEL'),
      amount: _selectedPaymentAmount(),
      source: _receiptBookingSourceToken(),
      bookingSource: _receiptBookingSourceToken(),
      rideType: _receiptRideTypeToken(),
    );
  }

  Widget _paymentSection(BuildContext context) {
    final receiptTotal = _selectedPaymentAmount();
    final selectedScope = _selectedPaymentScopeLabel();
    final isPlannedOperationalLeg = _isPlannedOperationalLegPaymentItem();
    final legAmountForLog = _receiptTotalAmount();
    final bookingTotalForLog = _detailDouble('booking_total_eur');
    // Hide payment action buttons whenever ANY paid signal is present in the
    // hydrated JSON, not just when the in-memory `_paymentStatus` enum was
    // already flipped to paid. Prevents `Pay by QR / Cash received / Paid by
    // card terminal` from appearing on Local Ride Register compliance-paid
    // rows whose status got temporarily downgraded by a stale booking-worker
    // record before `_resolveReceiptPaymentStatus` completed.
    // One canonical ride-payment source feeds the Payment/Betaalzone AND the
    // business-invoice controller (1D), so the invoice can never disagree with
    // the receipt about "Betaald".
    final canonicalRide = resolveCanonicalReceiptRidePayment(
      effectiveReceiptPaid: _isEffectiveReceiptPaid(),
    );
    final alreadyPaid = canonicalRide.isPaid;
    logStreetInvoiceRidePayment(
      surface: 'receipt',
      canonical: canonicalRide,
      bookingTag: _safeRefPreview(item.bookingId ?? ''),
    );
    final canRequestPayment =
        !alreadyPaid && receiptTotal != null && receiptTotal > 0;
    debugPrint(
      '[QR_PAYMENT][SECTION_AMOUNT] booking=${_safeRefPreview(item.bookingId ?? "")} is_planned_operational_leg=$isPlannedOperationalLeg leg_amount=${legAmountForLog ?? "-"} booking_total=${bookingTotalForLog ?? "-"} selected_amount=${receiptTotal ?? "-"} selected_scope=$selectedScope qr_enabled=$canRequestPayment',
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _palette.border.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _receiptText('paymentActions'),
            style: TextStyle(
              color: _palette.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          _receiptRow(_receiptText('paymentStatus'), _paymentStatusText()),
          _receiptRow(
            _receiptText('amount'),
            _moneyText(receiptTotal),
            highlight: true,
          ),
          const SizedBox(height: 10),
          if (!alreadyPaid) ...[
            if (_openMollieBlocksFallback) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _receiptText(
                    _mollieRecoveryBusy
                        ? 'checkingPaymentStatus'
                        : 'openPaymentRecoveryBody',
                  ),
                  style: TextStyle(fontSize: 12, color: _palette.textMuted),
                ),
              ),
              FilledButton.icon(
                onPressed: (_mollieRecoveryBusy || !canRequestPayment)
                    ? null
                    : () => _runOpenMollieRecoveryAction(
                          context,
                          choice: MollieOpenPaymentRecoveryChoice.refresh,
                        ),
                icon: const Icon(Icons.refresh),
                label: Text(_receiptText('checkPaymentStatus')),
              ),
              const SizedBox(height: 8),
              if (_openMollieRecovery?.resumable == true ||
                  receiptDetailsHaveOpenMollieCheckout(
                    Map<String, dynamic>.from(item.bookingDetails),
                  )) ...[
                FilledButton.icon(
                  onPressed: (_mollieRecoveryBusy || !canRequestPayment)
                      ? null
                      : () => _runOpenMollieRecoveryAction(
                            context,
                            choice: MollieOpenPaymentRecoveryChoice.resume,
                          ),
                  icon: const Icon(Icons.open_in_browser),
                  label: Text(_receiptText('resumeOnlinePayment')),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: (_mollieRecoveryBusy || !canRequestPayment)
                    ? null
                    : () => _runOpenMollieRecoveryAction(
                          context,
                          choice: MollieOpenPaymentRecoveryChoice.cancel,
                        ),
                icon: const Icon(Icons.cancel_outlined),
                label: Text(_receiptText('cancelOnlinePayment')),
              ),
              const SizedBox(height: 12),
            ],
            if (_mollieStreetCheckoutEligible() && !_openMollieBlocksFallback) ...[
              FilledButton.icon(
                onPressed: (canRequestPayment && !_mollieCheckoutLoading)
                    ? () => _startMollieStreetCheckout(context)
                    : null,
                icon: _mollieCheckoutLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.credit_card_outlined),
                label: Text(_receiptText('onlinePay')),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
                child: Text(
                  _receiptText('onlinePaySubtitle'),
                  style: TextStyle(fontSize: 11, color: _palette.textMuted),
                ),
              ),
              const SizedBox(height: 4),
            ],
            FilledButton.icon(
              onPressed: (canRequestPayment && !_openMollieBlocksFallback)
                  ? () => _showPaymentQr(context)
                  : (_openMollieBlocksFallback
                        ? () => _showPaymentQr(context)
                        : null),
              icon: const Icon(Icons.qr_code_2),
              label: Text(_receiptText('payByQr')),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: (canRequestPayment && !_openMollieBlocksFallback)
                  ? () => _persistInCarPayment(context: context, method: 'cash')
                  : (_openMollieBlocksFallback
                        ? () async {
                            final choice =
                                await _showOpenMollieRecoveryDialog(context);
                            if (!context.mounted) return;
                            if (choice != null &&
                                choice !=
                                    MollieOpenPaymentRecoveryChoice.dismiss) {
                              await _runOpenMollieRecoveryAction(
                                context,
                                choice: choice,
                                pendingManualMethod: 'cash',
                              );
                            }
                          }
                        : null),
              icon: const Icon(Icons.payments_outlined),
              label: Text(_receiptText('cashReceived')),
            ),
            const SizedBox(height: 8),
            if (_tapToPayAvailable) ...[
              FilledButton.icon(
                onPressed: (canRequestPayment &&
                        !_tapToPayInFlight &&
                        !_openMollieBlocksFallback)
                    ? () => _startTapToPay(context)
                    : (_openMollieBlocksFallback && canRequestPayment
                          ? () => _startTapToPay(context)
                          : null),
                icon: _tapToPayInFlight
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.contactless),
                label: Text(
                  _receiptText(
                    _tapToPayInFlight
                        ? (_tapToPayStatusMessageKey ?? 'tapToPayStarting')
                        : 'tapToPay',
                  ),
                ),
              ),
              if ((_tapToPayStatusMessageKey ?? '').isNotEmpty &&
                  !_tapToPayInFlight)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
                  child: Text(
                    _receiptText(_tapToPayStatusMessageKey!),
                    style: TextStyle(fontSize: 11, color: _palette.textMuted),
                  ),
                ),
              const SizedBox(height: 8),
            ] else if (_tapToPayCapabilityLoaded) ...[
              // Capability loaded and no usable terminal: hide Tap to Pay.
              // Manual Bancontact remains available below.
            ],
            FilledButton.icon(
              onPressed: canRequestPayment && !_tapToPayInFlight
                  ? () => _persistInCarPayment(
                      context: context,
                      method: 'bancontact',
                    )
                  : null,
              icon: const Icon(Icons.credit_card),
              label: Text(_receiptText('paidByCardTerminal')),
            ),
          ],
          // Fourth Payment action: business invoice for completed street rides.
          // Remains available while unpaid — invoicing is a valid payment path.
          // Mounts a loading/retry slot while Tracking history omits `source`
          // and we confirm identity via the Booking Worker.
          if (_shouldShowStreetInvoicePaymentSlot()) ...[
            if (!alreadyPaid) const SizedBox(height: 8),
            if (alreadyPaid) const SizedBox(height: 10),
            _streetBusinessInvoicePaymentSlot(alreadyPaid: alreadyPaid),
          ],
        ],
      ),
    );
  }

  /// Single source of truth for the Business-invoice Payment slot. Resolves
  /// live eligibility, then falls back to a sticky positive verdict so a
  /// transiently-cleared driver-scope override never collapses the slot.
  StreetInvoiceSlotDecision _resolveStreetInvoiceSlotDecision() {
    return resolveStreetInvoiceSlotDecision(
      eligibility: _resolveStreetBusinessInvoiceReceiptEligibility(),
      canonicalBookingId: _streetInvoiceActionBookingId(),
      memo: _streetInvoiceEligibilityMemo,
      hasActorContext:
          _receiptHasDriverSessionForInvoice() ||
          _receiptHasCompanyAdminBearerForInvoice(),
      lookupInFlight: _streetInvoiceLookupInFlight,
      lookupFailed: _streetInvoiceLookupFailed,
      kindToken: item.kind,
    );
  }

  bool _shouldShowStreetInvoicePaymentSlot() {
    // The fourth Payment action renders for every state except `unavailable`
    // (a genuine non-street / ineligible ride, where no action should exist).
    return _resolveStreetInvoiceSlotDecision().kind !=
        StreetInvoiceSlotKind.unavailable;
  }

  /// Reads a canonical street `source` / `booking_source` token from the
  /// receipt's booking data (details first, then the raw source payload).
  /// Also accepts Tracking trip fields that summarizeTrip may omit from the
  /// history projection but that still exist on enriched local/compliance rows.
  String _receiptBookingSourceToken() {
    String read(Map<dynamic, dynamic> src) {
      for (final k in const [
        'source',
        'booking_source',
        'bookingSource',
        'trip_source',
        'tripSource',
      ]) {
        final v = (src[k] ?? '').toString().trim();
        if (v.isNotEmpty && v.toLowerCase() != 'null') return v;
      }
      final b = src['booking'];
      if (b is Map) {
        for (final k in const ['source', 'booking_source', 'bookingSource']) {
          final v = (b[k] ?? '').toString().trim();
          if (v.isNotEmpty && v.toLowerCase() != 'null') return v;
        }
      }
      return '';
    }

    final fromDetails = read(item.bookingDetails);
    if (fromDetails.isNotEmpty) return fromDetails;
    final fromRaw = read(item.rawSource);
    if (fromRaw.isNotEmpty) return fromRaw;
    // Looked-up Booking Worker record wins when history omitted source.
    if (_streetInvoiceLookupBooking != null) {
      final signals = extractStreetSignalsFromBookingRecord(
        _streetInvoiceLookupBooking,
      );
      if (signals.source.isNotEmpty) return signals.source;
      if (signals.bookingSource.isNotEmpty) return signals.bookingSource;
    }
    return '';
  }

  /// Reads a `ride_type` token from the receipt's booking data, falling back
  /// to the looked-up Booking Worker record and finally to `item.kind`
  /// (History summaries commonly carry `direct` there for street rides).
  /// Used only as a corroborating signal for the online-checkout eligibility
  /// gate ([_mollieStreetCheckoutEligible]).
  String _receiptRideTypeToken() {
    for (final src in [item.bookingDetails, item.rawSource]) {
      for (final k in const ['ride_type', 'rideType']) {
        final v = (src[k] ?? '').toString().trim();
        if (v.isNotEmpty && v.toLowerCase() != 'null') return v;
      }
    }
    if (_streetInvoiceLookupBooking != null) {
      final signals = extractStreetSignalsFromBookingRecord(
        _streetInvoiceLookupBooking,
      );
      if (signals.rideType.isNotEmpty) return signals.rideType;
    }
    return item.kind;
  }

  String _receiptDirectRideKey() {
    for (final src in [item.bookingDetails, item.rawSource]) {
      for (final k in const ['direct_ride_key', 'directRideKey']) {
        final v = (src[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
    }
    return '';
  }

  String _receiptBookingLinkState() {
    for (final src in [item.bookingDetails, item.rawSource]) {
      for (final k in const ['booking_link_state', 'bookingLinkState']) {
        final v = (src[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
    }
    return '';
  }

  bool _receiptHasDriverSessionForInvoice() {
    final session = activeDriverSessionNotifier.value;
    if (session == null) return false;
    final token = (session.driverSessionToken ?? '').trim();
    if (token.isEmpty) return false;
    if ((session.tenantId ?? '').trim().isEmpty ||
        (session.companyId ?? '').trim().isEmpty) {
      return false;
    }
    return true;
  }

  /// True when a company-admin / business-preview bearer is available (admin
  /// token OR a valid company session). This never fabricates a driver session.
  bool _receiptHasCompanyAdminBearerForInvoice() =>
      hasCompanyOwnerAuthContext();

  /// Best-effort booking tenant/company scope from the receipt row. May be empty
  /// (Tracking history often omits it); the resolver treats empty scope as
  /// "unknown" and the Booking Worker still enforces it hard on create.
  ({String tenantId, String companyId}) _receiptBookingScopeForInvoice() {
    String read(List<String> keys) {
      for (final src in [item.bookingDetails, item.rawSource]) {
        for (final k in keys) {
          final v = (src[k] ?? '').toString().trim();
          if (v.isNotEmpty && v.toLowerCase() != 'null') return v;
        }
      }
      return '';
    }

    return (
      tenantId: read(const ['tenant_id', 'tenantId']),
      companyId: read(const ['company_id', 'companyId']),
    );
  }

  /// Central auth-context resolution for the receipt Business invoice action.
  /// Supports both a standalone driver session and a company-admin / business
  /// preview session — without ever requiring a standalone driver session in
  /// company-admin mode.
  StreetBusinessInvoiceAuthContext _resolveStreetBusinessInvoiceAuthContext() {
    final session = activeDriverSessionNotifier.value;
    final companyScope = _strictActiveBookingScopeQuery();
    final bookingScope = _receiptBookingScopeForInvoice();
    return resolveStreetBusinessInvoiceAuthContext(
      hasDriverSession: _receiptHasDriverSessionForInvoice(),
      driverBearer: (session?.driverSessionToken ?? '').trim(),
      driverTenantId: (session?.tenantId ?? '').trim(),
      driverCompanyId: (session?.companyId ?? '').trim(),
      driverId: (session?.driverId ?? '').trim(),
      hasCompanyAdminBearer: _receiptHasCompanyAdminBearerForInvoice(),
      companyTenantId: (companyScope?['tenant_id'] ?? '').trim(),
      companyCompanyId: (companyScope?['company_id'] ?? '').trim(),
      effectiveDriverId: _resolvedActiveDriverIdForScope().trim(),
      bookingTenantId: bookingScope.tenantId,
      bookingCompanyId: bookingScope.companyId,
      hasOwnership: _receiptOwnedByActiveDriverForInvoice(),
    );
  }

  /// Ownership for the invoice gate. Uses the normal assigned-driver/vehicle
  /// matrix, and also accepts a direct trip whose `driver_id` / `vehicle_id`
  /// matches the active driver session (street rides often lack
  /// `assigned_driver_id` on the history summary).
  bool _receiptOwnedByActiveDriverForInvoice() {
    if (_bookingBelongsToActiveDriver(_driverScopeBookingViewForReceipt())) {
      return true;
    }
    final activeDriverId = _resolvedActiveDriverIdForScope().trim();
    final tripDriver = item.driverId.trim();
    if (activeDriverId.isNotEmpty &&
        tripDriver.isNotEmpty &&
        activeDriverId == tripDriver) {
      return true;
    }
    final tripVehicle = (item.vehicleId ?? '').trim();
    final sessionVehicle = _activeDriverSessionVehicleIdForScope().trim();
    if (tripVehicle.isNotEmpty &&
        sessionVehicle.isNotEmpty &&
        tripVehicle == sessionVehicle) {
      return true;
    }
    if (tripVehicle.isNotEmpty &&
        _activeDriverLinkedVehicleIds().contains(tripVehicle)) {
      return true;
    }
    // Tracking history rows for the driver's own street rides sometimes omit
    // assignee fields entirely. Allow the Payment action to mount when the
    // active driver session is present and the booking is a street_ id or a
    // direct trip opened from this driver's history — the Booking Worker
    // still enforces assigned-driver authorization on create.
    final bookingId = (item.bookingId ?? '').trim().toLowerCase();
    final kind = item.kind.trim().toLowerCase();
    final hasActorContext =
        _receiptHasDriverSessionForInvoice() ||
        _receiptHasCompanyAdminBearerForInvoice();
    if (hasActorContext &&
        activeDriverId.isNotEmpty &&
        (bookingId.startsWith('street_') || kind == 'direct') &&
        tripDriver.isEmpty) {
      return true;
    }
    return false;
  }

  StreetBusinessInvoiceReceiptEligibility
  _resolveStreetBusinessInvoiceReceiptEligibility() {
    final bookingId =
        (_streetInvoiceResolvedBookingId ?? item.bookingId ?? '').trim();
    final st = item.status.trim().toUpperCase().replaceAll(
      RegExp(r'[-\s]+'),
      '_',
    );
    final authContext = _resolveStreetBusinessInvoiceAuthContext();
    return resolveStreetBusinessInvoiceReceiptEligibility(
      bookingId: bookingId,
      tripId: item.tripId.trim(),
      kind: item.kind,
      status: st,
      source: _receiptBookingSourceToken(),
      bookingSource: _receiptBookingSourceToken(),
      rideType: item.kind,
      directRideKey: _receiptDirectRideKey(),
      bookingLinkState: _receiptBookingLinkState(),
      isLocalOnlyFallback: item.isLocalOnlyDirectFallback,
      hasDriverSession: _receiptHasDriverSessionForInvoice(),
      hasOwnership: _receiptOwnedByActiveDriverForInvoice(),
      authContext: authContext,
      isCancelled: st.contains('CANCEL'),
      isRefunded: st.contains('REFUND'),
      isCredited: st.contains('CREDIT'),
      lookedUpBooking: _streetInvoiceLookupBooking,
    );
  }

  void _logStreetInvoiceEligibility(
    StreetBusinessInvoiceReceiptEligibility e, {
    required String phase,
  }) {
    debugPrint(
      '[STREET_INVOICE_UI] phase=$phase '
      'isStreetRide=${e.isStreetRide} '
      'isCompleted=${e.isCompleted} '
      'hasDriverSession=${e.hasDriverSession} '
      'hasOwnership=${e.hasOwnership} '
      'hasBookingId=${e.hasBookingId} '
      'authMode=${e.authMode.name} '
      'needsLookup=${e.needsBookingLookup} '
      'lookupFailed=$_streetInvoiceLookupFailed '
      'visible=${e.visible} '
      'reason=${e.reason} '
      'booking=${_safeRefPreview(e.canonicalBookingId)} '
      'trip=${_safeRefPreview(item.tripId)} '
      'kind=${item.kind}',
    );
  }

  Future<Map<String, dynamic>?> _fetchStreetInvoiceBookingRecord(
    String bookingId,
  ) async {
    final id = bookingId.trim();
    if (id.isEmpty) return null;
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/bookings/${Uri.encodeComponent(id)}',
      );
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      final token =
          (activeDriverSessionNotifier.value?.driverSessionToken ?? '').trim();
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      if (kAdminToken.trim().isNotEmpty) {
        headers['x-admin-token'] = kAdminToken.trim();
      }
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureStreetBusinessInvoiceEligibilityResolved() async {
    final snap = _resolveStreetBusinessInvoiceReceiptEligibility();
    _logStreetInvoiceEligibility(snap, phase: 'eligibility');
    if (!snap.needsBookingLookup) return;
    final lookupId = snap.canonicalBookingId.trim().isNotEmpty
        ? snap.canonicalBookingId.trim()
        : (item.bookingId ?? '').trim();
    if (lookupId.isEmpty) return;
    if (_streetInvoiceLookupInFlight) return;
    if (_streetInvoiceLookupBooking != null &&
        _streetInvoiceLookupBookingId == lookupId) {
      return;
    }
    _streetInvoiceLookupInFlight = true;
    _streetInvoiceLookupFailed = false;
    if (mounted) setState(() {});
    debugPrint(
      '[STREET_INVOICE_UI] phase=lookup_start '
      'booking=${_safeRefPreview(lookupId)}',
    );
    final record = await _fetchStreetInvoiceBookingRecord(lookupId);
    if (!mounted) return;
    _streetInvoiceLookupInFlight = false;
    _streetInvoiceLookupBookingId = lookupId;
    if (record == null) {
      _streetInvoiceLookupFailed = true;
      _logStreetInvoiceEligibility(
        _resolveStreetBusinessInvoiceReceiptEligibility(),
        phase: 'lookup_error',
      );
      setState(() {});
      return;
    }
    final signals = extractStreetSignalsFromBookingRecord(record);
    _streetInvoiceLookupBooking = record;
    _streetInvoiceLookupFailed = false;
    if (signals.bookingId.isNotEmpty) {
      _streetInvoiceResolvedBookingId = signals.bookingId;
    }
    final after = _resolveStreetBusinessInvoiceReceiptEligibility();
    _logStreetInvoiceEligibility(after, phase: 'lookup_done');
    setState(() {});
  }

  /// True when the driver-receipt business-invoice section must be shown.
  bool _driverReceiptInvoiceEligible() {
    final e = _resolveStreetBusinessInvoiceReceiptEligibility();
    return e.visible;
  }

  String _streetInvoiceActionBookingId() {
    final resolved = (_streetInvoiceResolvedBookingId ?? '').trim();
    if (resolved.isNotEmpty) return resolved;
    final fromEligibility =
        _resolveStreetBusinessInvoiceReceiptEligibility().canonicalBookingId;
    if (fromEligibility.trim().isNotEmpty) return fromEligibility.trim();
    return (item.bookingId ?? '').trim();
  }

  Widget _streetBusinessInvoicePaymentSlot({required bool alreadyPaid}) {
    final decision = _resolveStreetInvoiceSlotDecision();
    if (decision.kind == StreetInvoiceSlotKind.available) {
      final canonicalId = decision.canonicalBookingId.isNotEmpty
          ? decision.canonicalBookingId
          : _streetInvoiceActionBookingId();
      return _DriverReceiptBusinessInvoiceAction(
        // Stable key per canonical booking id: preserves the controller (and
        // its loaded/issued state) across rebuilds, and forces a clean fresh
        // controller when the receipt shows a different booking.
        key: ValueKey<String>('street-invoice-$canonicalId'),
        bookingId: canonicalId,
        tripItem: item,
        isPaidBooking: alreadyPaid,
        palette: _palette,
        initialBuyer: _streetBusinessInvoicePrefill(),
        authMode: decision.authMode,
        onInvoicePresenceChanged: _onStreetBusinessInvoicePresence,
      );
    }
    if (decision.kind == StreetInvoiceSlotKind.resolving) {
      // Short non-empty placeholder so the Payment card grows; no silent gap.
      return OutlinedButton.icon(
        onPressed: null,
        icon: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _palette.accent,
          ),
        ),
        label: Text(
          _tr(
            nl: 'Zakelijke factuur…',
            en: 'Business invoice…',
            fr: 'Facture professionnelle…',
            es: 'Factura comercial…',
          ),
        ),
      );
    }
    if (decision.kind == StreetInvoiceSlotKind.retryableError) {
      return OutlinedButton.icon(
        onPressed: () {
          _streetInvoiceLookupBooking = null;
          _streetInvoiceLookupBookingId = null;
          _streetInvoiceLookupFailed = false;
          unawaited(_ensureStreetBusinessInvoiceEligibilityResolved());
        },
        icon: const Icon(Icons.refresh),
        label: Text(
          _tr(
            nl: 'Zakelijke factuur — opnieuw',
            en: 'Business invoice — retry',
            fr: 'Facture professionnelle — réessayer',
            es: 'Factura comercial — reintentar',
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _receiptActionsSection(BuildContext context) {
    final hasEmail = (_customerEmail ?? '').trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _palette.border.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            // Ride receipt ("Bon") actions — distinct from the business invoice.
            _receiptText('receiptActions'),
            style: TextStyle(
              color: _palette.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => _viewReceiptPdf(context),
            icon: const Icon(Icons.visibility_outlined),
            label: Text(_receiptText('viewPdf')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _shareReceiptPdf(context),
            icon: const Icon(Icons.share_outlined),
            label: Text(_receiptText('sharePdf')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _shareReceiptPdfViaWhatsApp(context),
            icon: const Icon(Icons.chat_outlined),
            label: Text(_receiptText('whatsappPdf')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: hasEmail
                ? () => _shareReceiptPdfViaEmail(context)
                : null,
            icon: const Icon(Icons.email_outlined),
            label: Text(_receiptText('emailPdf')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _printReceiptPdf(context),
            icon: const Icon(Icons.print_outlined),
            label: Text(_receiptText('printReceipt')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = _resolvedRouteForPdf();
    final businessFields = _resolvedReceiptBusinessFields();
    final legLabel = _operationalLegLabelForReceipt();
    final subtypeLabel = legLabel ?? _plannedSubtype();
    final receiptRefDisplay = _businessReferenceDisplayForItem(
      item,
      source: 'receipt_screen_row',
    );
    return ValueListenableBuilder<DriverThemeVariant>(
      valueListenable: _receiptThemeListenable,
      builder: (context, themeVariant, _) {
        _palette = paletteForDriverTheme(themeVariant);
        if (!widget.showReceiptUi) {
          return Scaffold(
            backgroundColor: _palette.background,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: _palette.accent),
                  const SizedBox(height: 12),
                  Text(
                    _receiptText('pdfReady'),
                    style: TextStyle(color: _palette.textMuted),
                  ),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          backgroundColor: _palette.background,
          appBar: AppBar(
            backgroundColor: _palette.background,
            elevation: 0,
            iconTheme: IconThemeData(color: _palette.textPrimary),
            titleTextStyle: TextStyle(
              color: _palette.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            title: Text(_receiptText('receiptTitle')),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _palette.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: _palette.border.withOpacity(0.55),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            kFluxidiLogoAsset,
                            width: 46,
                            height: 46,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.local_taxi,
                              color: _palette.accent,
                              size: 38,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Fluxidi',
                                  style: TextStyle(
                                    color: _palette.textPrimary,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  _receiptText('rideReceipt'),
                                  style: TextStyle(color: _palette.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _receiptRow(
                        receiptRefDisplay.label,
                        receiptRefDisplay.value,
                      ),
                      _receiptRow(_receiptText('type'), item.kindLabel),
                      _optionalReceiptRow(
                        _receiptText('subtype'),
                        subtypeLabel,
                      ),
                      _receiptRow(
                        _receiptText('startTime'),
                        _formatDate(item.startedAt),
                      ),
                      _receiptRow(
                        _receiptText('endTime'),
                        _formatDate(item.stoppedAt),
                      ),
                      _receiptRow(_receiptText('from'), route.from),
                      _receiptRow(_receiptText('to'), route.to),
                      _receiptRow(_receiptText('distance'), _kmText()),
                      _receiptRow(
                        _receiptText('actualWaitingTime'),
                        _formatWait(item.waitSecondsTotal),
                      ),
                      _receiptRow(
                        _receiptText('total'),
                        _totalText(),
                        highlight: true,
                      ),
                      if (_hasAnyRawCustomerContact) ...[
                        _sectionTitle(_receiptText('customerDetails')),
                        _optionalReceiptRow(
                          _receiptText('customerName'),
                          _customerName,
                        ),
                        _optionalReceiptRow(
                          _receiptText('customerPhone'),
                          _customerPhoneRaw,
                        ),
                        _optionalReceiptRow(
                          _receiptText('customerEmail'),
                          _customerEmail,
                        ),
                      ],
                      if (businessFields.isBusinessDocument) ...[
                        _sectionTitle(
                          _tr(
                            nl: 'Zakelijk / Factuur',
                            en: 'Business / Invoice',
                            fr: 'Professionnel / Facture',
                            es: 'Empresa / Factura',
                          ),
                        ),
                        _optionalReceiptRow(
                          _tr(
                            nl: 'Bedrijfsnaam',
                            en: 'Company name',
                            fr: "Nom de l'entreprise",
                            es: 'Empresa',
                          ),
                          businessFields.companyName.isEmpty
                              ? null
                              : businessFields.companyName,
                        ),
                        _optionalReceiptRow(
                          _tr(
                            nl: 'BTW-nummer',
                            en: 'VAT number',
                            fr: 'Numero de TVA',
                            es: 'NIF/IVA',
                          ),
                          businessFields.vatNumber.isEmpty
                              ? null
                              : businessFields.vatNumber,
                        ),
                        _optionalReceiptRow(
                          _tr(
                            nl: 'Factuur e-mail',
                            en: 'Invoice email',
                            fr: 'E-mail facture',
                            es: 'Email de factura',
                          ),
                          businessFields.invoiceEmail.isEmpty
                              ? null
                              : businessFields.invoiceEmail,
                        ),
                        _optionalReceiptRow(
                          _tr(
                            nl: 'Factuuradres',
                            en: 'Invoice address',
                            fr: 'Adresse de facturation',
                            es: 'Direccion de factura',
                          ),
                          businessFields.invoiceAddress.isEmpty
                              ? null
                              : businessFields.invoiceAddress,
                        ),
                      ],
                      if (_isPlannedReceipt) ...[
                        _sectionTitle(_receiptText('plannedBookingDetails')),
                        _optionalReceiptRow(
                          _receiptText('scheduledPickup'),
                          _detailText('scheduled_pickup_at') == null
                              ? null
                              : _formatDate(_detailText('scheduled_pickup_at')),
                        ),
                        _optionalReceiptRow(
                          _receiptText('service'),
                          _displayServiceToken(_detailText('service_type')),
                        ),
                        _optionalReceiptRow(
                          _receiptText('tier'),
                          _displayTierToken(_detailText('tier')),
                        ),
                        _optionalReceiptRow(
                          _receiptText('passengers'),
                          _detailText('passengers'),
                        ),
                        _optionalReceiptRow(
                          _receiptText('bags'),
                          _detailText('luggage_count'),
                        ),
                        _optionalReceiptRow(
                          _receiptText('bookedWaitingTime'),
                          _minutesText('booked_wait_minutes'),
                        ),
                        _optionalReceiptRow(
                          _receiptText('extraStops'),
                          _detailText('stops'),
                        ),
                        _receiptRow(
                          _receiptText('extras'),
                          _plannedExtrasText() ??
                              _tr(
                                nl: 'Geen extra opties',
                                en: 'No extra options',
                                fr: 'Aucune option supplementaire',
                                es: 'Sin opciones extra',
                              ),
                        ),
                        _optionalReceiptRow(
                          _receiptText('notes'),
                          _detailText('notes'),
                        ),
                        _sectionTitle(_receiptText('routeAndPrices')),
                        _optionalReceiptRow(
                          _receiptText('routeDetails'),
                          _routeSegmentsText(),
                        ),
                        ..._plannedPriceRows(),
                        // Leg-first: a ritbon proves ONE operational leg, so
                        // the Retour gepland / Retour route rows belong on the
                        // booking-detail page, not on the leg ritbon.
                        if (!_ReceiptPdfActionRunner._isLegReceiptItem(
                          item,
                        )) ...[
                          _optionalReceiptRow(
                            _receiptText('returnPlanned'),
                            _detailText('return_scheduled_pickup_at') == null
                                ? null
                                : _formatDate(
                                    _detailText('return_scheduled_pickup_at'),
                                  ),
                          ),
                          _optionalReceiptRow(
                            _receiptText('returnRoute'),
                            _detailText('return_route'),
                          ),
                        ],
                      ],
                      _sectionTitle(_receiptText('statusPaymentSection')),
                      _receiptRow(
                        _receiptText('rideStatus'),
                        _ReceiptPdfActionRunner._legReceiptRideStatusDisplay(
                          item,
                        ),
                      ),
                      _receiptRow(
                        _receiptText('paymentStatus'),
                        _paymentStatusText(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _paymentSection(context),
                const SizedBox(height: 16),
                _receiptActionsSection(context),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Walks a nested booking map (or any `Map`) along the supplied key path
/// and returns the leaf value (or `null` if any segment is missing or the
/// intermediate value is not a `Map`). Used to look up tenant/company
/// owner ids on bookings whose scope is stamped under nested locations
/// such as `record.tenant_id`, `record.booking.company_id`,
/// `payload.booking.owner_tenant_id`, etc.
dynamic _deepLookupInBookingMap(
  Map<dynamic, dynamic> source,
  List<String> path,
) {
  dynamic current = source;
  for (final key in path) {
    if (current is Map && current.containsKey(key)) {
      current = current[key];
    } else {
      return null;
    }
  }
  return current;
}

/// Resolved company bank-payment details used to render the customer-facing
/// SEPA Credit Transfer QR and the human-readable payment summary.
class _BankPaymentDetails {
  const _BankPaymentDetails({
    required this.beneficiary,
    required this.iban,
    required this.bic,
    required this.amount,
    required this.currency,
    required this.reference,
  });

  final String beneficiary;
  final String iban;
  final String bic;
  final double amount;
  final String currency;
  final String reference;

  bool get isComplete => beneficiary.isNotEmpty && iban.isNotEmpty;
}
