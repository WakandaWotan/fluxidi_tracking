part of '../main.dart';

class _RideReceiptBodyState extends State<_RideReceiptBody> {
  _ReceiptPaymentStatus _paymentStatus = _ReceiptPaymentStatus.pending;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final action = widget.initialAction;
      if (action != null) {
        unawaited(_runInitialAction(context, action));
      }
    });
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
    Map<String, dynamic> asMap(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/bookings/${Uri.encodeComponent(bookingId)}',
      );
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (kAdminToken.trim().isNotEmpty) {
        headers['x-admin-token'] = kAdminToken.trim();
      }
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));
      Map<String, dynamic>? parsed;
      dynamic decoded;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        decoded = jsonDecode(res.body);
        if (decoded is Map) {
          final root = Map<String, dynamic>.from(decoded);
          parsed = _extractAuthoritativePaymentFields(root);
        }
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

    String? resolved = authoritativePaymentStatus;
    if (resolved != null && resolved.isNotEmpty) {
    } else if (historyPaymentStatus != null &&
        historyPaymentStatus.isNotEmpty) {
      resolved = historyPaymentStatus;
    } else if (nestedPaymentStatus != null && nestedPaymentStatus.isNotEmpty) {
      resolved = nestedPaymentStatus;
    }

    final methodFromDetails =
        authoritativePaymentMethod ?? _paymentMethodFromDetails();
    final sourceFromDetails = _paymentSourceFromDetails();
    final markAsPaidFromMethod =
        _methodImpliesPaid(methodFromDetails) &&
        (sourceFromDetails == null ||
            sourceFromDetails.isEmpty ||
            sourceFromDetails == 'in_car');
    if (!mounted) return;
    setState(() {
      final fromStatus = _paymentStatusFromRaw(resolved);
      _paymentStatus =
          markAsPaidFromMethod && fromStatus != _ReceiptPaymentStatus.paid
          ? _ReceiptPaymentStatus.paid
          : fromStatus;
    });
  }

  String? _cleanContactText(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
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

  double? _receiptTotalAmount() {
    if (_isPlannedReceipt) {
      final legAmount = _effectiveOperationalLegAmount();
      if (_isPositiveAmount(legAmount)) return legAmount;
      return _detailDouble('booking_total_eur') ?? item.totalEur;
    }
    return item.totalEur;
  }

  String _moneyText(double? value) {
    if (value == null) return _receiptText('notAvailable');
    return '€ ${value.toStringAsFixed(2)}';
  }

  String _totalText() {
    return _moneyText(_receiptTotalAmount());
  }

  String _kmText() {
    final km = item.kmTotal;
    if (km == null) return _receiptText('notAvailable');
    return '${km.toStringAsFixed(2)} km';
  }

  bool _isPlaceholderRouteLabel(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return true;
    if (text == '-' || text == '—') return true;
    return text.toLowerCase() == _receiptText('currentLocation').toLowerCase();
  }

  ({String from, String to}) _resolvedRouteForPdf() {
    final normalizedFrom = _isPlaceholderRouteLabel(item.origin)
        ? null
        : item.origin.trim();
    final normalizedTo = _isPlaceholderRouteLabel(item.destination)
        ? null
        : item.destination.trim();

    String? pickLabel(List<List<String>> paths) {
      for (final path in paths) {
        final text = _cleanContactText(_detailAt(path));
        if (!_isPlaceholderRouteLabel(text)) return text;
      }
      return null;
    }

    final rawFrom = pickLabel(const [
      ['from'],
      ['pickup'],
      ['pickup_address'],
      ['pickupAddress'],
      ['pickupLocation'],
      ['pickup_location'],
      ['origin'],
      ['start_address'],
      ['startAddress'],
      ['booking', 'from'],
      ['booking', 'pickup'],
      ['booking', 'pickup_address'],
      ['booking', 'pickupAddress'],
      ['record', 'from'],
      ['record', 'booking', 'from'],
      ['record', 'booking', 'pickup'],
      ['payload', 'from'],
      ['payload', 'booking', 'from'],
      ['quote', 'inputs', 'from'],
    ]);
    final rawTo = pickLabel(const [
      ['to'],
      ['destination'],
      ['destination_address'],
      ['destinationAddress'],
      ['dropoff'],
      ['dropoff_address'],
      ['dropoffAddress'],
      ['end_address'],
      ['endAddress'],
      ['booking', 'to'],
      ['booking', 'destination'],
      ['booking', 'destination_address'],
      ['booking', 'destinationAddress'],
      ['record', 'to'],
      ['record', 'booking', 'to'],
      ['record', 'booking', 'destination'],
      ['payload', 'to'],
      ['payload', 'booking', 'to'],
      ['quote', 'inputs', 'to'],
    ]);

    final from = _sanitizeCustomerFacingRouteLabel(
      normalizedFrom ?? rawFrom ?? _receiptText('currentLocation'),
      isFromField: true,
    );
    final to = _sanitizeCustomerFacingRouteLabel(
      normalizedTo ?? rawTo ?? '-',
      isFromField: false,
    );
    final source = (normalizedFrom != null || normalizedTo != null)
        ? 'normalized'
        : ((rawFrom != null || rawTo != null) ? 'raw' : 'fallback');
    debugPrint(
      '[PDF][ROUTE] fromFound=${from != _receiptText('currentLocation')} toFound=${to != '-'} source=$source',
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
    final outbound = _detailDouble('outbound_price_eur');
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
    final value = (raw ?? '').trim();
    if (value.isEmpty) return _receiptText('notAvailable');
    final normalized = value
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    switch (normalized) {
      case 'cash':
        return _tr(nl: 'Contant', en: 'Cash', fr: 'Espèces', es: 'Efectivo');
      case 'bancontact':
        return _tr(
          nl: 'Bancontact',
          en: 'Bancontact',
          fr: 'Bancontact',
          es: 'Bancontact',
        );
      case 'card':
        return _tr(nl: 'Kaart', en: 'Card', fr: 'Carte', es: 'Tarjeta');
      case 'qr':
      case 'qr_code':
        return _tr(
          nl: 'QR-code',
          en: 'QR code',
          fr: 'Code QR',
          es: 'Código QR',
        );
      case 'mollie':
        return _tr(
          nl: 'Online betaling',
          en: 'Online payment',
          fr: 'Paiement en ligne',
          es: 'Pago en línea',
        );
      default:
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
    switch (_paymentStatus) {
      case _ReceiptPaymentStatus.pending:
        return _receiptText('unpaid');
      case _ReceiptPaymentStatus.sent:
        return _receiptText('paymentSent');
      case _ReceiptPaymentStatus.paid:
        return _receiptText('paid');
    }
  }

  String _paymentLink() {
    final amount = _receiptTotalAmount() ?? 0.0;
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
    final hasBusiness =
        invoiceRequested ||
        businessFlag ||
        (customerCompany != null && customerCompany.trim().isNotEmpty) ||
        (customerVat != null && customerVat.trim().isNotEmpty);
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
    final candidates = <String>[
      if (preferredPath != null && preferredPath.trim().isNotEmpty)
        preferredPath.trim(),
      kFluxidiLogoAsset,
    ];
    for (final candidate in candidates) {
      try {
        if (candidate.startsWith('assets/')) {
          final data = await rootBundle.load(candidate);
          return data.buffer.asUint8List();
        }
        final f = File(candidate);
        if (await f.exists()) {
          return await f.readAsBytes();
        }
      } catch (_) {
        // Ignore and try next candidate.
      }
    }
    return null;
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
      'logoPath': settings.logoAssetPath.trim(),
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
          : _receiptText('paymentReceiptLabel');
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
                    width: 82,
                    height: 82,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
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
            _pdfInfoRow(_receiptText('from'), route.from),
            _pdfInfoRow(_receiptText('to'), route.to),
            _pdfInfoRow(_receiptText('distance'), _kmText()),
            _pdfInfoRow(_receiptText('duration'), durationText),
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
    _markPaymentRequestSent();
    final link = _paymentLink();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_receiptText('qrPayment')),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: link,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 12),
              Text(
                _totalText(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                link,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
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
            onPressed: () {
              Navigator.of(ctx).pop();
              _copyPaymentLink(context);
            },
            child: Text(_receiptText('copyLink')),
          ),
        ],
      ),
    );
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
  }) async {
    if (!_guardDriverReceiptOperation(action: 'persist_payment_$method'))
      return;
    final strictScope = _strictReceiptPaymentScopeForMutation(
      context: context,
      action: 'persist_in_car_payment',
    );
    if (strictScope == null) return;
    final bookingId = (item.bookingId ?? '').trim();
    final tripId = item.tripId.trim();
    final normalizedMethod = method.toLowerCase().trim();
    final hasLegId = (_operationalLegIdForReceipt() ?? '').trim().isNotEmpty;
    final hasLegType = (_operationalLegTypeTokenForReceipt() ?? '')
        .trim()
        .isNotEmpty;
    final hasRowKey = (_operationalLegRowKeyForReceipt() ?? '')
        .trim()
        .isNotEmpty;
    final useLegTripPaymentPath = _isPlannedOperationalLegPaymentItem();
    final useTripPaymentPath = bookingId.isEmpty || useLegTripPaymentPath;
    debugPrint(
      '[RECEIPT_PAYMENT][LEG_GUARD_DECISION] tripId=$tripId bookingId=$bookingId isPlannedReceipt=$_isPlannedReceipt hasLegId=$hasLegId hasLegType=$hasLegType hasRowKey=$hasRowKey useLegTripPaymentPath=$useLegTripPaymentPath',
    );
    if (useTripPaymentPath) {
      if (tripId.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('bookingIdMissing'))),
        );
        return;
      }
      final amount = _receiptTotalAmount();
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
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (kAdminToken.trim().isNotEmpty) {
        headers['x-admin-token'] = kAdminToken.trim();
      }
      try {
        final uri = Uri.parse(
          '$kWorkerBaseUrl/trip/payment',
        ).replace(queryParameters: strictScope);
        if (useLegTripPaymentPath) {
          debugPrint(
            '[RECEIPT_PAYMENT][LEG_TRIP_PAYMENT] tripId=$tripId bookingId=$bookingId legId=$legId legType=$legType parentBookingId=$parentBookingId method=$normalizedMethod',
          );
        }
        final res = await http
            .post(uri, headers: headers, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 12));
        final resBody = utf8.decode(res.bodyBytes);
        final bodyPreview = resBody.length > 240
            ? '${resBody.substring(0, 240)}...'
            : resBody;
        debugPrint(
          '[RECEIPT_PAYMENT][LEG_TRIP_PAYMENT][RES] code=${res.statusCode} bodyPreview=$bodyPreview',
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

    final amount = _receiptTotalAmount();
    final payload = <String, dynamic>{
      'booking_id': bookingId,
      'payment_status': 'paid',
      'payment_method': normalizedMethod,
      'payment_source': 'in_car',
      ...strictScope,
      'currency': item.currency.trim().isEmpty
          ? 'EUR'
          : item.currency.trim().toUpperCase(),
      'paid_by_driver_id': kDriverId,
      'paid_at': DateTime.now().toUtc().toIso8601String(),
      ..._driverMutationActorFields(
        actorVehicleId: (item.vehicleId ?? '').trim(),
      ),
      if (amount != null) 'amount': amount,
    };
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (kAdminToken.trim().isNotEmpty) {
      headers['x-admin-token'] = kAdminToken.trim();
    }

    try {
      debugPrint(
        '[RECEIPT_PAYMENT][PARENT_BOOKING_PAYMENT] bookingId=$bookingId method=$normalizedMethod',
      );
      final uri = Uri.parse(
        '$kBookingBaseUrl/bookings/${Uri.encodeComponent(bookingId)}/payment',
      ).replace(queryParameters: strictScope);
      final res = await http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));
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
      debugPrint(
        '[RECEIPT][PAYMENT_MARK_FAILED] bookingId=$bookingId method=$method err=$err',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('paymentMarkFailed'))),
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
    if (_detailText('return_scheduled_pickup_at') != null ||
        _detailText('return_route') != null) {
      return _receiptText('outboundRide');
    }
    return null;
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

  String? _routeSegmentsText() {
    final raw = item.bookingDetails['route_segments'];
    if (raw is! List || raw.isEmpty) return null;
    final lines = <String>[];
    for (var i = 0; i < raw.length; i++) {
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
      lines.add('${i + 1}. $route${meta.isEmpty ? '' : ': $meta'}');
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  double? _segmentNumber(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.'));
  }

  Widget _paymentSection(BuildContext context) {
    final receiptTotal = _receiptTotalAmount();
    final alreadyPaid = _paymentStatus == _ReceiptPaymentStatus.paid;
    final canRequestPayment =
        !alreadyPaid && receiptTotal != null && receiptTotal > 0;
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
          _receiptRow(_receiptText('amount'), _totalText(), highlight: true),
          const SizedBox(height: 10),
          if (!alreadyPaid) ...[
            FilledButton.icon(
              onPressed: canRequestPayment
                  ? () => _showPaymentQr(context)
                  : null,
              icon: const Icon(Icons.qr_code_2),
              label: Text(_receiptText('payByQr')),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: canRequestPayment
                  ? () => _persistInCarPayment(context: context, method: 'cash')
                  : null,
              icon: const Icon(Icons.payments_outlined),
              label: Text(_receiptText('cashReceived')),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: canRequestPayment
                  ? () => _persistInCarPayment(
                      context: context,
                      method: 'bancontact',
                    )
                  : null,
              icon: const Icon(Icons.credit_card),
              label: Text(_receiptText('paidByCardTerminal')),
            ),
          ],
        ],
      ),
    );
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
                      _sectionTitle(_receiptText('statusPaymentSection')),
                      _receiptRow(
                        _receiptText('rideStatus'),
                        _localizedRideStatus(item.status),
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
