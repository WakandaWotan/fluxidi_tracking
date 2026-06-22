part of '../main.dart';

/// Read-only customer-safe view extracted from the authoritative booking
/// record returned by `GET /bookings/{id}`. Driver/admin/internal fields
/// (raw tokens, vehicle assignments, internal IDs) are intentionally not
/// surfaced.
class CustomerBookingView {
  CustomerBookingView({
    required this.bookingId,
    required this.lifecycleStatus,
    required this.booking,
    required this.record,
    required this.source,
  });

  final String bookingId;
  final String lifecycleStatus;
  final Map<String, dynamic> booking;
  final Map<String, dynamic> record;
  final Map<String, dynamic> source;

  factory CustomerBookingView.fromResponse(
    String bookingId,
    Map<String, dynamic> response,
  ) {
    final mergedSource = Map<String, dynamic>.from(response);
    final rawRecord = mergedSource['record'];
    final record = (rawRecord is Map)
        ? Map<String, dynamic>.from(rawRecord)
        : <String, dynamic>{};
    final rawBooking = record['booking'];
    final booking = (rawBooking is Map)
        ? Map<String, dynamic>.from(rawBooking)
        : <String, dynamic>{};
    final rawPayload = record['payload'];
    final payload = (rawPayload is Map)
        ? Map<String, dynamic>.from(rawPayload)
        : <String, dynamic>{};
    final lifecycleRaw =
        response['status']?.toString().trim() ??
        response['stage']?.toString().trim() ??
        record['status']?.toString().trim() ??
        record['stage']?.toString().trim() ??
        booking['status']?.toString().trim() ??
        '';
    final lifecycle = _normalizeCustomerLifecycleStatus(lifecycleRaw);
    final businessPayload = _deriveCustomerBusinessInvoicePayload(
      source: <String, dynamic>{
        ...mergedSource,
        ...record,
        ...booking,
        ...payload,
      },
    );
    if (businessPayload.isNotEmpty) {
      booking.addAll(businessPayload);
      payload.addAll(businessPayload);
      record.addAll(businessPayload);
      record['booking'] = booking;
      record['payload'] = payload;
      mergedSource.addAll(businessPayload);
      mergedSource['record'] = record;
      mergedSource['booking'] = booking;
      mergedSource['payload'] = payload;
    }
    // #region agent log H1 hydrate source flags
    unawaited(
      _agentDebugLog(
        runId: 'initial',
        hypothesisId: 'H1',
        location: 'main.dart:CustomerBookingView.fromResponse',
        message: '[CUSTOMER_BOOKING][BUSINESS_PAYLOAD]',
        data: <String, dynamic>{
          'booking': _safeRefPreview(bookingId),
          'rawStatus': lifecycleRaw,
          'normalizedStatus': lifecycle,
          'service': (booking['service'] ?? booking['extra_service'] ?? '')
              .toString(),
          'businessDetected':
              (booking['business_detected'] ??
                      booking['businessDetected'] ??
                      record['business_detected'] ??
                      record['businessDetected'] ??
                      response['business_detected'] ??
                      response['businessDetected'] ??
                      '')
                  .toString(),
          'invoiceRequested':
              (booking['invoice_requested'] ??
                      booking['invoiceRequested'] ??
                      record['invoice_requested'] ??
                      record['invoiceRequested'] ??
                      response['invoice_requested'] ??
                      response['invoiceRequested'] ??
                      '')
                  .toString(),
          'companyName':
              (booking['company_name'] ??
                      booking['companyName'] ??
                      response['company_name'] ??
                      response['companyName'] ??
                      '')
                  .toString(),
          'vatNumber':
              (booking['vat_number'] ??
                      booking['vatNumber'] ??
                      response['vat_number'] ??
                      response['vatNumber'] ??
                      '')
                  .toString(),
          'invoiceEmail':
              (booking['invoice_email'] ??
                      booking['invoiceEmail'] ??
                      response['invoice_email'] ??
                      response['invoiceEmail'] ??
                      '')
                  .toString(),
          'derivedBusiness': (businessPayload['business_detected'] ?? '')
              .toString(),
          'derivedInvoiceRequested':
              (businessPayload['invoice_requested'] ?? '').toString(),
          'derivedCompanyName': (businessPayload['company_name'] ?? '')
              .toString(),
          'derivedVatNumber': (businessPayload['vat_number'] ?? '').toString(),
          'derivedInvoiceEmail': (businessPayload['invoice_email'] ?? '')
              .toString(),
        },
      ),
    );
    // #endregion
    return CustomerBookingView(
      bookingId: bookingId,
      lifecycleStatus: lifecycle,
      booking: booking,
      record: record,
      source: mergedSource,
    );
  }

  factory CustomerBookingView.fromStored(StoredCustomerBooking stored) {
    final booking = <String, dynamic>{
      'tenant_id': stored.tenantId,
      'tenantId': stored.tenantId,
      'company_id': stored.companyId,
      'companyId': stored.companyId,
      'from': stored.from,
      'to': stored.to,
      'pickup_iso': stored.pickupIso,
      'customer_name': stored.customerName,
      'customer_phone': stored.customerPhone,
      'customer_email': stored.customerEmail,
      'price_incl_vat': stored.price,
      'currency': stored.currency,
      'service': stored.service,
      'tier': stored.tier,
      'pax': stored.pax,
      'bags': stored.bags,
      'payment_status': stored.paymentStatus,
      'company_name': stored.companyName,
      'vat_number': stored.vatNumber,
      'invoice_email': stored.invoiceEmail,
      'invoice_address': stored.invoiceAddress,
      'business_customer': stored.businessDetected,
      'invoice_requested': stored.invoiceRequested,
      'quote': stored.quote,
    };
    final businessPayload = _deriveCustomerBusinessInvoicePayload(
      source: <String, dynamic>{
        ...booking,
        'business_detected': stored.businessDetected,
        'businessDetected': stored.businessDetected,
        'invoice_requested': stored.invoiceRequested,
        'invoiceRequested': stored.invoiceRequested,
      },
    );
    booking.addAll(businessPayload);
    final quoteSnapshot = Map<String, dynamic>.from(stored.quote);
    final record = <String, dynamic>{
      'tenant_id': stored.tenantId,
      'tenantId': stored.tenantId,
      'company_id': stored.companyId,
      'companyId': stored.companyId,
      'status': stored.status,
      'payment_status': stored.paymentStatus,
      'booking': booking,
      'payload': <String, dynamic>{
        'tenant_id': stored.tenantId,
        'tenantId': stored.tenantId,
        'company_id': stored.companyId,
        'companyId': stored.companyId,
        'from': stored.from,
        'to': stored.to,
        'pickup_iso': stored.pickupIso,
        'service': stored.service,
        'tier': stored.tier,
        'pax': stored.pax,
        'bags': stored.bags,
        ...businessPayload,
      },
      ...businessPayload,
      if (quoteSnapshot['operational_legs'] is List)
        'operational_legs': quoteSnapshot['operational_legs'],
      if (quoteSnapshot['operationalLegs'] is List)
        'operationalLegs': quoteSnapshot['operationalLegs'],
      if (quoteSnapshot['price_incl_vat_main'] != null)
        'price_incl_vat_main': quoteSnapshot['price_incl_vat_main'],
      if (quoteSnapshot['priceInclVatMain'] != null)
        'priceInclVatMain': quoteSnapshot['priceInclVatMain'],
      if (quoteSnapshot['price_incl_vat_return'] != null)
        'price_incl_vat_return': quoteSnapshot['price_incl_vat_return'],
      if (quoteSnapshot['priceInclVatReturn'] != null)
        'priceInclVatReturn': quoteSnapshot['priceInclVatReturn'],
      if (quoteSnapshot['price_incl_vat'] != null)
        'price_incl_vat': quoteSnapshot['price_incl_vat'],
      if (quoteSnapshot['priceInclVat'] != null)
        'priceInclVat': quoteSnapshot['priceInclVat'],
    };
    for (final key in const <String>[
      'price_incl_vat_main',
      'priceInclVatMain',
      'price_incl_vat_return',
      'priceInclVatReturn',
      'price_incl_vat',
      'priceInclVat',
    ]) {
      final value = quoteSnapshot[key];
      if (value != null) {
        booking[key] = value;
      }
    }
    final source = <String, dynamic>{
      'tenant_id': stored.tenantId,
      'tenantId': stored.tenantId,
      'company_id': stored.companyId,
      'companyId': stored.companyId,
      'record': record,
      'booking': booking,
      'quote': stored.quote,
      'payload': record['payload'],
      ...businessPayload,
    };
    return CustomerBookingView(
      bookingId: stored.canonicalBookingId,
      lifecycleStatus: stored.status.toUpperCase(),
      booking: booking,
      record: record,
      source: source,
    );
  }

  bool _isMeaningful(String value) {
    final s = value.trim().toLowerCase();
    if (s.isEmpty) return false;
    if (s == '-' || s == 'null' || s == 'undefined') return false;
    return true;
  }

  String _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (_isMeaningful(s)) return s;
    }
    return '';
  }

  dynamic _valueAtPath(String path) {
    dynamic current = source;
    for (final segment in path.split('.')) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }

  String _firstPathValue(List<String> paths) {
    for (final path in paths) {
      final raw = _valueAtPath(path);
      final s = raw?.toString().trim() ?? '';
      if (_isMeaningful(s)) return s;
    }
    return '';
  }

  double? _firstPathNum(List<String> paths) {
    for (final path in paths) {
      final raw = _valueAtPath(path);
      if (raw is num) return raw.toDouble();
      final s = raw?.toString().trim() ?? '';
      if (!_isMeaningful(s)) continue;
      final parsed = double.tryParse(s.replaceAll(',', '.'));
      if (parsed != null) return parsed;
    }
    return null;
  }

  double? _sumQuoteLegMetric({
    required List<String> listPaths,
    required List<String> keyCandidates,
  }) {
    for (final path in listPaths) {
      final raw = _valueAtPath(path);
      if (raw is! List || raw.isEmpty) continue;
      var sum = 0.0;
      var found = false;
      for (final item in raw) {
        if (item is! Map) continue;
        for (final key in keyCandidates) {
          final value = item[key];
          if (value is num) {
            sum += value.toDouble();
            found = true;
            break;
          }
          final text = value?.toString().trim() ?? '';
          if (!_isMeaningful(text)) continue;
          final parsed = double.tryParse(text.replaceAll(',', '.'));
          if (parsed != null) {
            sum += parsed;
            found = true;
            break;
          }
        }
      }
      if (found) return sum;
    }
    return null;
  }

  String _quoteLegEndpointLabel({required bool fromField}) {
    final candidates = <dynamic>[
      _valueAtPath('quote.legs'),
      _valueAtPath('record.quote.legs'),
    ];
    for (final raw in candidates) {
      if (raw is! List || raw.isEmpty) continue;
      final edge = fromField ? raw.first : raw.last;
      if (edge is! Map) continue;
      final label = fromField
          ? _firstNonEmpty([
              edge['from'],
              edge['origin'],
              edge['start'],
              edge['start_address'],
              edge['startAddress'],
            ])
          : _firstNonEmpty([
              edge['to'],
              edge['destination'],
              edge['end'],
              edge['end_address'],
              edge['endAddress'],
            ]);
      if (_isMeaningful(label)) return label;
    }
    return '';
  }

  bool _toBool(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes' || text == 'ja';
  }

  bool _firstPathBool(List<String> paths) {
    for (final path in paths) {
      final raw = _valueAtPath(path);
      if (raw == null) continue;
      return _toBool(raw);
    }
    return false;
  }

  bool _looksAirportText(String value) {
    final s = value.trim().toLowerCase();
    if (!_isMeaningful(s)) return false;
    return s.contains('airport') ||
        s.contains('luchthaven') ||
        s.contains('zaventem') ||
        s.contains('charleroi');
  }

  bool _hasAirportFieldHint() {
    final token = _firstPathValue(const <String>[
      'airport_iata',
      'airportIata',
      'airport_name',
      'airportName',
      'booking.airport_iata',
      'booking.airportIata',
      'booking.airport_name',
      'booking.airportName',
      'record.airport_iata',
      'record.airportIata',
      'record.airport_name',
      'record.airportName',
      'record.booking.airport_iata',
      'record.booking.airportIata',
      'record.booking.airport_name',
      'record.booking.airportName',
      'quote.airport_iata',
      'quote.airportIata',
      'quote.airport_name',
      'quote.airportName',
      'payload.airport_iata',
      'payload.airportIata',
      'payload.airport_name',
      'payload.airportName',
    ]);
    return _isMeaningful(token);
  }

  String _serviceFallbackFromAirportHints() {
    if (_hasAirportFieldHint()) return 'airport';
    final routeTexts = <String>[
      fromAddress,
      toAddress,
      returnFrom,
      returnTo,
      _firstPathValue(const <String>[
        'from',
        'to',
        'booking.from',
        'booking.to',
        'record.booking.from',
        'record.booking.to',
        'quote.from',
        'quote.to',
        'payload.from',
        'payload.to',
      ]),
      _firstPathValue(const <String>[
        'quote.service',
        'quote.service_type',
        'quote.booking_type',
        'record.quote.service',
        'record.quote.service_type',
        'record.quote.booking_type',
      ]),
    ];
    if (routeTexts.any(_looksAirportText)) return 'airport';
    return '';
  }

  String _preferNonEmptyText(String authoritative, String localFallback) {
    if (_isMeaningful(authoritative)) return authoritative;
    if (_isMeaningful(localFallback)) return localFallback;
    return '';
  }

  CustomerBookingView mergedWithExisting(CustomerBookingView existing) {
    final mergedBooking = <String, dynamic>{...existing.booking, ...booking};
    final mergedRecord = <String, dynamic>{...existing.record, ...record};
    final mergedSource = <String, dynamic>{...existing.source, ...source};

    final mergedFrom = _preferNonEmptyText(fromAddress, existing.fromAddress);
    final mergedTo = _preferNonEmptyText(toAddress, existing.toAddress);
    final mergedPickupIso = _preferNonEmptyText(pickupIso, existing.pickupIso);
    final mergedName = _preferNonEmptyText(customerName, existing.customerName);
    final mergedPhone = _preferNonEmptyText(
      customerPhone,
      existing.customerPhone,
    );
    final mergedEmail = _preferNonEmptyText(
      customerEmail,
      existing.customerEmail,
    );
    final mergedService = _preferNonEmptyText(service, existing.service);
    final mergedTier = _preferNonEmptyText(tier, existing.tier);
    final mergedPax = _preferNonEmptyText(pax, existing.pax);
    final mergedBags = _preferNonEmptyText(bags, existing.bags);
    final mergedCurrency = _preferNonEmptyText(currency, existing.currency);
    final mergedPaymentStatus = _preferNonEmptyText(
      rawPaymentStatus,
      existing.rawPaymentStatus,
    );
    final mergedLifecycleStatus = _preferNonEmptyText(
      lifecycleStatus,
      existing.lifecycleStatus,
    );
    final mergedPrice = totalAmount ?? existing.totalAmount;

    if (_isMeaningful(mergedFrom)) {
      mergedSource['from'] = mergedFrom;
      mergedBooking['from'] = mergedFrom;
      mergedRecord['from'] = mergedFrom;
    }
    if (_isMeaningful(mergedTo)) {
      mergedSource['to'] = mergedTo;
      mergedBooking['to'] = mergedTo;
      mergedRecord['to'] = mergedTo;
    }
    if (_isMeaningful(mergedPickupIso)) {
      mergedBooking['pickup_iso'] = mergedPickupIso;
      mergedRecord['pickup_iso'] = mergedPickupIso;
    }
    if (_isMeaningful(mergedName)) mergedBooking['customer_name'] = mergedName;
    if (_isMeaningful(mergedPhone))
      mergedBooking['customer_phone'] = mergedPhone;
    if (_isMeaningful(mergedEmail))
      mergedBooking['customer_email'] = mergedEmail;
    if (_isMeaningful(mergedService)) mergedBooking['service'] = mergedService;
    if (_isMeaningful(mergedTier)) mergedBooking['tier'] = mergedTier;
    if (_isMeaningful(mergedPax)) mergedBooking['pax'] = mergedPax;
    if (_isMeaningful(mergedBags)) mergedBooking['bags'] = mergedBags;
    if (_isMeaningful(mergedCurrency))
      mergedBooking['currency'] = mergedCurrency;
    if (_isMeaningful(mergedPaymentStatus)) {
      mergedBooking['payment_status'] = mergedPaymentStatus;
      mergedRecord['payment_status'] = mergedPaymentStatus;
    }
    if (_isMeaningful(mergedLifecycleStatus)) {
      mergedRecord['status'] = mergedLifecycleStatus;
    }
    if (mergedPrice != null) {
      mergedBooking['price_incl_vat'] = mergedPrice;
      mergedRecord['amount'] = mergedPrice;
      mergedSource['price_incl_vat'] = mergedPrice;
    }

    mergedRecord['booking'] = mergedBooking;
    mergedSource['record'] = mergedRecord;
    mergedSource['booking'] = mergedBooking;

    return CustomerBookingView(
      bookingId: _preferNonEmptyText(bookingId, existing.bookingId),
      lifecycleStatus: mergedLifecycleStatus,
      booking: mergedBooking,
      record: mergedRecord,
      source: mergedSource,
    );
  }

  String get fromAddress => _firstNonEmpty([
    _firstPathValue(const <String>[
      'from',
      'pickup',
      'pickup_address',
      'pickupAddress',
      'origin',
      'booking.from',
      'booking.pickup',
      'booking.pickup_address',
      'booking.pickupAddress',
      'record.from',
      'record.booking.from',
      'record.booking.pickup',
      'record.booking.pickup_address',
      'record.booking_details.from',
      'record.booking_details.pickup_address',
      'record.quote.from',
      'data.record.booking.from',
      'data.record.booking_details.from',
      'payload.from',
      'payload.pickup_address',
      'quote.from',
      'quote.inputs.from',
    ]),
    _quoteLegEndpointLabel(fromField: true),
  ]);
  String get toAddress => _firstNonEmpty([
    _firstPathValue(const <String>[
      'to',
      'destination',
      'destination_address',
      'destinationAddress',
      'dropoff',
      'dropoff_address',
      'booking.to',
      'booking.destination',
      'booking.destination_address',
      'record.to',
      'record.booking.to',
      'record.booking.destination',
      'record.booking.destination_address',
      'record.booking_details.to',
      'record.booking_details.destination_address',
      'record.quote.to',
      'data.record.booking.to',
      'data.record.booking_details.to',
      'payload.to',
      'payload.destination_address',
      'quote.to',
      'quote.inputs.to',
    ]),
    _quoteLegEndpointLabel(fromField: false),
  ]);
  String get pickupIso => _firstNonEmpty([
    _firstPathValue(const <String>[
      'pickup_iso',
      'record.pickup_iso',
      'record.booking.pickup_iso',
      'record.booking.pickupStartIso',
      'record.quote.pickup_iso',
      'quote.pickup_iso',
    ]),
    booking['pickupStartIso'],
    booking['pickup_iso'],
    booking['pickup_at'],
    booking['pickupAt'],
    record['pickup_iso'],
  ]);
  String get customerName => _firstNonEmpty([
    booking['customer_name'],
    booking['name'],
    record['customer_name'],
  ]);
  String get customerPhone => _firstNonEmpty([
    booking['customer_phone'],
    booking['phone'],
    booking['customer_phone_e164'],
  ]);
  String get customerEmail => _firstNonEmpty([
    booking['customer_email'],
    booking['email'],
  ]).toLowerCase();
  String get service => _firstNonEmpty([
    _firstPathValue(const <String>[
      'service',
      'serviceType',
      'service_type',
      'bookingType',
      'booking_type',
      'extra_service',
      'extra_service_key',
      'booking.service',
      'booking.serviceType',
      'booking.service_type',
      'booking.bookingType',
      'booking.booking_type',
      'booking.extra_service',
      'record.booking.service',
      'record.booking.serviceType',
      'record.booking.service_type',
      'record.booking.bookingType',
      'record.booking.booking_type',
      'record.booking_details.service',
      'record.booking_details.serviceType',
      'record.booking_details.service_type',
      'record.booking_details.bookingType',
      'record.booking_details.booking_type',
      'record.booking.extra_service',
      'payload.service',
      'payload.serviceType',
      'payload.service_type',
      'payload.bookingType',
      'payload.booking_type',
      'quote.inputs.service',
      'quote.inputs.serviceType',
      'quote.inputs.service_type',
      'quote.inputs.bookingType',
      'quote.inputs.booking_type',
    ]),
    _serviceFallbackFromAirportHints(),
  ]);
  String get tier => _firstNonEmpty([
    _firstPathValue(const <String>[
      'tier',
      'vehicle_tier',
      'vehicleTier',
      'booking.tier',
      'booking.vehicle_tier',
      'booking.vehicleTier',
      'record.booking.tier',
      'record.booking_details.tier',
      'record.booking_details.vehicle_tier',
      'record.booking_details.vehicleTier',
      'payload.tier',
      'payload.vehicle_tier',
      'payload.vehicleTier',
      'quote.inputs.tier',
      'quote.inputs.vehicle_tier',
      'quote.inputs.vehicleTier',
    ]),
  ]);
  String get pax => _firstNonEmpty([
    _firstPathValue(const <String>[
      'pax',
      'passengers',
      'booking.pax',
      'booking.passengers',
      'record.booking.pax',
      'record.booking_details.pax',
      'payload.pax',
      'quote.inputs.pax',
    ]),
  ]);
  String get bags => _firstNonEmpty([
    _firstPathValue(const <String>[
      'bags',
      'booking.bags',
      'record.booking.bags',
      'record.booking_details.bags',
      'payload.bags',
      'quote.inputs.bags',
    ]),
  ]);
  String get currency => _firstNonEmpty([
    _firstPathValue(const <String>[
      'currency',
      'booking.currency',
      'record.currency',
      'record.booking.currency',
      'record.booking_details.currency',
      'quote.currency',
      'payload.currency',
    ]),
    'EUR',
  ]);
  double? get totalAmount {
    return _firstPathNum(const <String>[
      'price',
      'total',
      'amount',
      'final_total',
      'total_price',
      'price_incl_vat',
      'priceInclVat',
      'booking.price',
      'booking.total',
      'booking.amount',
      'booking.final_total',
      'booking.total_price',
      'booking.price_incl_vat',
      'record.price',
      'record.total',
      'record.amount',
      'record.final_total',
      'record.total_price',
      'record.price_incl_vat',
      'record.booking.price',
      'record.booking.total',
      'record.booking.amount',
      'record.booking.final_total',
      'record.booking.total_price',
      'record.booking_details.price',
      'record.booking_details.total',
      'record.booking_details.amount',
      'record.booking_details.final_total',
      'record.booking_details.total_price',
      'record.booking_details.price_incl_vat',
      'record.quote.price',
      'record.quote.total_price',
      'record.quote.total',
      'record.quote.price_incl_vat',
      'record.quote.pricing.price_incl_vat',
      'record.quote.pricing_main.price_incl_vat',
      'record.quote.pricing_main.breakdown.total_incl',
      'quote.price_incl_vat',
      'quote.priceInclVat',
      'quote.total_price',
      'quote.total',
      'quote.pricing.price_incl_vat',
      'quote.pricing_main.price_incl_vat',
      'quote.pricing_main.breakdown.total_incl',
      'payload.price',
      'payload.total',
      'payload.amount',
      'payload.final_total',
      'payload.total_price',
      'payload.price_incl_vat',
      'payload.quote.price_incl_vat',
    ]);
  }

  bool get returnEnabled => _firstPathBool(const <String>[
    'return_enabled',
    'returnEnabled',
    'booking.return_enabled',
    'booking.returnEnabled',
    'record.return_enabled',
    'record.returnEnabled',
    'record.booking.return_enabled',
    'record.booking.returnEnabled',
    'record.quote.return.enabled',
    'quote.return.enabled',
    'payload.return_enabled',
    'payload.returnEnabled',
  ]);

  String get returnFrom => _firstPathValue(const <String>[
    'return_from',
    'returnFrom',
    'booking.return_from',
    'booking.returnFrom',
    'record.return_from',
    'record.returnFrom',
    'record.booking.return_from',
    'record.booking.returnFrom',
    'record.quote.return.from',
    'quote.return.from',
    'payload.return_from',
    'payload.returnFrom',
  ]);

  String get returnTo => _firstPathValue(const <String>[
    'return_to',
    'returnTo',
    'booking.return_to',
    'booking.returnTo',
    'record.return_to',
    'record.returnTo',
    'record.booking.return_to',
    'record.booking.returnTo',
    'record.quote.return.to',
    'quote.return.to',
    'payload.return_to',
    'payload.returnTo',
  ]);

  String get returnPickupIso {
    final pickupIso = _firstPathValue(const <String>[
      'return_pickup_iso',
      'returnPickupIso',
      'booking.return_pickup_iso',
      'booking.returnPickupIso',
      'record.return_pickup_iso',
      'record.returnPickupIso',
      'record.booking.return_pickup_iso',
      'record.booking.returnPickupIso',
      'record.quote.return.pickup_iso',
      'quote.return.pickup_iso',
      'payload.return_pickup_iso',
      'payload.returnPickupIso',
    ]);
    if (_isMeaningful(pickupIso)) return pickupIso;
    final returnDate = _firstPathValue(const <String>[
      'return_date',
      'returnDate',
      'booking.return_date',
      'booking.returnDate',
      'record.return_date',
      'record.returnDate',
      'record.booking.return_date',
      'record.booking.returnDate',
      'payload.return_date',
      'payload.returnDate',
    ]);
    final returnTime = _firstPathValue(const <String>[
      'return_time',
      'returnTime',
      'booking.return_time',
      'booking.returnTime',
      'record.return_time',
      'record.returnTime',
      'record.booking.return_time',
      'record.booking.returnTime',
      'payload.return_time',
      'payload.returnTime',
    ]);
    final fallback = [
      returnDate,
      returnTime,
    ].where((e) => _isMeaningful(e)).join(' ').trim();
    return fallback;
  }

  double? get priceInclVatMain => _firstPathNum(const <String>[
    'price_incl_vat_main',
    'priceInclVatMain',
    'booking.price_incl_vat_main',
    'booking.priceInclVatMain',
    'record.price_incl_vat_main',
    'record.priceInclVatMain',
    'record.booking.price_incl_vat_main',
    'record.booking.priceInclVatMain',
    'record.quote.price_incl_vat_main',
    'record.quote.pricing_main.price_incl_vat',
    'quote.price_incl_vat_main',
    'quote.priceInclVatMain',
    'quote.pricing_main.price_incl_vat',
    'payload.price_incl_vat_main',
    'payload.priceInclVatMain',
  ]);

  double? get priceInclVatReturn => _firstPathNum(const <String>[
    'price_incl_vat_return',
    'priceInclVatReturn',
    'booking.price_incl_vat_return',
    'booking.priceInclVatReturn',
    'record.price_incl_vat_return',
    'record.priceInclVatReturn',
    'record.booking.price_incl_vat_return',
    'record.booking.priceInclVatReturn',
    'record.quote.price_incl_vat_return',
    'record.quote.pricing_return.price_incl_vat',
    'record.quote.return.price_incl_vat',
    'quote.price_incl_vat_return',
    'quote.priceInclVatReturn',
    'quote.pricing_return.price_incl_vat',
    'quote.return.price_incl_vat',
    'payload.price_incl_vat_return',
    'payload.priceInclVatReturn',
  ]);

  double? get priceInclVatTotal => _firstPathNum(const <String>[
    'total_price_incl_vat',
    'totalPriceInclVat',
    'price_incl_vat',
    'priceInclVat',
    'booking.total_price_incl_vat',
    'booking.totalPriceInclVat',
    'booking.price_incl_vat',
    'booking.priceInclVat',
    'record.total_price_incl_vat',
    'record.totalPriceInclVat',
    'record.price_incl_vat',
    'record.priceInclVat',
    'record.booking.total_price_incl_vat',
    'record.booking.totalPriceInclVat',
    'record.booking.price_incl_vat',
    'record.booking.priceInclVat',
    'record.quote.total_price_incl_vat',
    'record.quote.price_incl_vat',
    'record.quote.pricing.price_incl_vat',
    'quote.total_price_incl_vat',
    'quote.price_incl_vat',
    'quote.pricing.price_incl_vat',
    'payload.total_price_incl_vat',
    'payload.totalPriceInclVat',
    'payload.price_incl_vat',
    'payload.priceInclVat',
  ]);

  bool get fixedFareAppliedMain => _firstPathBool(const <String>[
    'fixed_fare_applied_main',
    'fixedFareAppliedMain',
    'booking.fixed_fare_applied_main',
    'booking.fixedFareAppliedMain',
    'record.fixed_fare_applied_main',
    'record.fixedFareAppliedMain',
    'record.booking.fixed_fare_applied_main',
    'record.booking.fixedFareAppliedMain',
    'record.quote.fixed_fare_applied_main',
    'quote.fixed_fare_applied_main',
    'quote.fixedFareAppliedMain',
  ]);

  bool get fixedFareAppliedReturn => _firstPathBool(const <String>[
    'fixed_fare_applied_return',
    'fixedFareAppliedReturn',
    'booking.fixed_fare_applied_return',
    'booking.fixedFareAppliedReturn',
    'record.fixed_fare_applied_return',
    'record.fixedFareAppliedReturn',
    'record.booking.fixed_fare_applied_return',
    'record.booking.fixedFareAppliedReturn',
    'record.quote.fixed_fare_applied_return',
    'quote.fixed_fare_applied_return',
    'quote.fixedFareAppliedReturn',
  ]);

  String get fixedFareRuleIdMain => _firstPathValue(const <String>[
    'fixed_fare_rule_id_main',
    'fixedFareRuleIdMain',
    'booking.fixed_fare_rule_id_main',
    'booking.fixedFareRuleIdMain',
    'record.fixed_fare_rule_id_main',
    'record.fixedFareRuleIdMain',
    'record.booking.fixed_fare_rule_id_main',
    'record.booking.fixedFareRuleIdMain',
    'record.quote.fixed_fare_rule_id_main',
    'quote.fixed_fare_rule_id_main',
    'quote.fixedFareRuleIdMain',
  ]);

  String get fixedFareRuleIdReturn => _firstPathValue(const <String>[
    'fixed_fare_rule_id_return',
    'fixedFareRuleIdReturn',
    'booking.fixed_fare_rule_id_return',
    'booking.fixedFareRuleIdReturn',
    'record.fixed_fare_rule_id_return',
    'record.fixedFareRuleIdReturn',
    'record.booking.fixed_fare_rule_id_return',
    'record.booking.fixedFareRuleIdReturn',
    'record.quote.fixed_fare_rule_id_return',
    'quote.fixed_fare_rule_id_return',
    'quote.fixedFareRuleIdReturn',
  ]);

  String get pricingSourceMain => _firstPathValue(const <String>[
    'pricing_source_main',
    'pricingSourceMain',
    'booking.pricing_source_main',
    'booking.pricingSourceMain',
    'record.pricing_source_main',
    'record.pricingSourceMain',
    'record.booking.pricing_source_main',
    'record.booking.pricingSourceMain',
    'record.quote.pricing_source_main',
    'quote.pricing_source_main',
    'quote.pricingSourceMain',
  ]);

  String get pricingSourceReturn => _firstPathValue(const <String>[
    'pricing_source_return',
    'pricingSourceReturn',
    'booking.pricing_source_return',
    'booking.pricingSourceReturn',
    'record.pricing_source_return',
    'record.pricingSourceReturn',
    'record.booking.pricing_source_return',
    'record.booking.pricingSourceReturn',
    'record.quote.pricing_source_return',
    'quote.pricing_source_return',
    'quote.pricingSourceReturn',
  ]);

  bool get isRoundtrip {
    if (returnEnabled) return true;
    if (_isMeaningful(returnFrom) || _isMeaningful(returnTo)) return true;
    if (_isMeaningful(returnPickupIso)) return true;
    if (priceInclVatReturn != null) return true;
    return false;
  }

  double? get distanceKm {
    return _firstPathNum(const <String>[
          'distance_km',
          'record.distance_km',
          'record.quote.distance_km',
          'quote.distance_km',
        ]) ??
        _sumQuoteLegMetric(
          listPaths: const <String>['quote.legs', 'record.quote.legs'],
          keyCandidates: const <String>['distance_km', 'km', 'distance'],
        );
  }

  double? get durationMin {
    return _firstPathNum(const <String>[
          'duration_min',
          'record.duration_min',
          'record.booking.duration_route_min',
          'record.quote.duration_min',
          'quote.duration_min',
        ]) ??
        _sumQuoteLegMetric(
          listPaths: const <String>['quote.legs', 'record.quote.legs'],
          keyCandidates: const <String>['duration_min', 'minutes', 'duration'],
        );
  }

  double? get waitMin {
    return _firstPathNum(const <String>[
      'wait_min',
      'waitMin',
      'booked_wait_minutes',
      'bookedWaitMinutes',
      'booking.wait_min',
      'booking.waitMin',
      'booking.booked_wait_minutes',
      'booking.bookedWaitMinutes',
      'record.wait_min',
      'record.waitMin',
      'record.booking.wait_min',
      'record.booking.waitMin',
      'record.booking.booked_wait_minutes',
      'record.booking.bookedWaitMinutes',
      'record.payload.wait_min',
      'record.payload.waitMin',
      'record.quote.wait_min',
      'record.quote.waitMin',
      'record.quote.inputs.wait_min',
      'record.quote.inputs.waitMin',
      'quote.wait_min',
      'quote.waitMin',
      'quote.inputs.wait_min',
      'quote.inputs.waitMin',
      'payload.wait_min',
      'payload.waitMin',
    ]);
  }

  String get companyName => _firstNonEmpty([
    _firstPathValue(const <String>[
      'company_name',
      'companyName',
      'customer_company',
      'customerCompany',
      'booking.company_name',
      'booking.companyName',
      'record.company_name',
      'record.companyName',
      'record.booking.company_name',
      'record.booking.companyName',
      'record.booking_details.company_name',
      'record.booking_details.companyName',
      'payload.company_name',
      'payload.companyName',
      'payload.booking.company_name',
      'payload.booking.companyName',
    ]),
    booking['company_name'],
    booking['companyName'],
    booking['company'],
  ]);
  String get vatNumber => _firstNonEmpty([
    _firstPathValue(const <String>[
      'vat_number',
      'vatNumber',
      'customer_vat',
      'customerVat',
      'booking.vat_number',
      'booking.vatNumber',
      'record.vat_number',
      'record.vatNumber',
      'record.booking.vat_number',
      'record.booking.vatNumber',
      'record.booking_details.vat_number',
      'record.booking_details.vatNumber',
      'payload.vat_number',
      'payload.vatNumber',
      'payload.booking.vat_number',
      'payload.booking.vatNumber',
    ]),
    booking['vat_number'],
    booking['vatNumber'],
    booking['vat'],
  ]);
  bool get invoiceRequested => _firstPathBool(const <String>[
    'invoice_requested',
    'invoiceRequested',
    'booking.invoice_requested',
    'booking.invoiceRequested',
    'record.invoice_requested',
    'record.invoiceRequested',
    'record.booking.invoice_requested',
    'record.booking.invoiceRequested',
    'record.booking_details.invoice_requested',
    'record.booking_details.invoiceRequested',
    'payload.invoice_requested',
    'payload.invoiceRequested',
    'payload.booking.invoice_requested',
    'payload.booking.invoiceRequested',
  ]);
  String get invoiceEmail => _firstNonEmpty([
    _firstPathValue(const <String>[
      'invoice_email',
      'invoiceEmail',
      'booking.invoice_email',
      'booking.invoiceEmail',
      'record.invoice_email',
      'record.invoiceEmail',
      'record.booking.invoice_email',
      'record.booking.invoiceEmail',
      'record.booking_details.invoice_email',
      'record.booking_details.invoiceEmail',
    ]),
  ]);
  String get invoiceAddress => _firstNonEmpty([
    _firstPathValue(const <String>[
      'invoice_address',
      'invoiceAddress',
      'billing_address',
      'billingAddress',
      'company_address',
      'companyAddress',
      'booking.invoice_address',
      'booking.invoiceAddress',
      'booking.billing_address',
      'booking.billingAddress',
      'booking.company_address',
      'booking.companyAddress',
      'record.invoice_address',
      'record.invoiceAddress',
      'record.billing_address',
      'record.billingAddress',
      'record.company_address',
      'record.companyAddress',
      'record.booking.invoice_address',
      'record.booking.invoiceAddress',
      'record.booking.billing_address',
      'record.booking.billingAddress',
      'record.booking.company_address',
      'record.booking.companyAddress',
    ]),
  ]);
  String get invoiceUrl => _firstNonEmpty([
    _firstPathValue(const <String>[
      'invoice_url',
      'invoiceUrl',
      'invoice_pdf_url',
      'invoicePdfUrl',
      'invoice_download_url',
      'invoiceDownloadUrl',
      'booking.invoice_url',
      'booking.invoiceUrl',
      'booking.invoice_pdf_url',
      'booking.invoicePdfUrl',
      'booking.invoice_download_url',
      'booking.invoiceDownloadUrl',
      'record.invoice_url',
      'record.invoiceUrl',
      'record.invoice_pdf_url',
      'record.invoicePdfUrl',
      'record.invoice_download_url',
      'record.invoiceDownloadUrl',
      'record.booking.invoice_url',
      'record.booking.invoiceUrl',
      'record.booking.invoice_pdf_url',
      'record.booking.invoicePdfUrl',
      'record.booking.invoice_download_url',
      'record.booking.invoiceDownloadUrl',
    ]),
  ]);
  bool get invoiceEmailAvailable => _firstPathBool(const <String>[
    'invoice_email_available',
    'invoiceEmailAvailable',
    'booking.invoice_email_available',
    'booking.invoiceEmailAvailable',
    'record.invoice_email_available',
    'record.invoiceEmailAvailable',
    'record.booking.invoice_email_available',
    'record.booking.invoiceEmailAvailable',
  ]);
  bool get businessCustomer {
    final hasVat = vatNumber.isNotEmpty;
    if (!hasVat) return false;
    if (invoiceRequested) return true;
    return _firstPathBool(const <String>[
      'business_customer',
      'businessCustomer',
      'is_business',
      'isBusiness',
      'business_detected',
      'businessDetected',
      'booking.business_customer',
      'booking.businessCustomer',
      'booking.is_business',
      'booking.isBusiness',
      'booking.business_detected',
      'booking.businessDetected',
      'record.business_customer',
      'record.businessCustomer',
      'record.is_business',
      'record.isBusiness',
      'record.business_detected',
      'record.businessDetected',
      'record.booking.business_customer',
      'record.booking.businessCustomer',
      'record.booking.is_business',
      'record.booking.isBusiness',
      'record.booking.business_detected',
      'record.booking.businessDetected',
      'record.booking_details.business_customer',
      'record.booking_details.businessCustomer',
      'record.booking_details.is_business',
      'record.booking_details.isBusiness',
      'payload.business_customer',
      'payload.businessCustomer',
      'payload.is_business',
      'payload.isBusiness',
      'payload.business_detected',
      'payload.businessDetected',
    ]);
  }

  String get rawPaymentStatus {
    final candidates = <dynamic>[
      record['payment_status'],
      record['paymentStatus'],
      booking['payment_status'],
      booking['paymentStatus'],
      _firstPathValue(const <String>[
        'payment_status',
        'paymentStatus',
        'record.booking.payment_status',
        'record.booking.paymentStatus',
        'record.booking_details.payment_status',
        'record.booking_details.paymentStatus',
      ]),
    ];
    for (final v in candidates) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s.toLowerCase();
    }
    return '';
  }

  String get paymentMethod {
    return _firstNonEmpty([
      _firstPathValue(const <String>[
        'payment_method',
        'paymentMethod',
        'booking.payment_method',
        'booking.paymentMethod',
        'record.payment_method',
        'record.paymentMethod',
        'record.booking.payment_method',
        'record.booking.paymentMethod',
        'record.booking_details.payment_method',
        'record.booking_details.paymentMethod',
      ]),
    ]).toLowerCase();
  }

  String get paymentSource {
    return _firstNonEmpty([
      _firstPathValue(const <String>[
        'payment_source',
        'paymentSource',
        'booking.payment_source',
        'booking.paymentSource',
        'record.payment_source',
        'record.paymentSource',
        'record.booking.payment_source',
        'record.booking.paymentSource',
        'record.booking_details.payment_source',
        'record.booking_details.paymentSource',
      ]),
    ]).toLowerCase();
  }

  String get paymentProvider {
    return _firstNonEmpty([
      _firstPathValue(const <String>[
        'payment_provider',
        'paymentProvider',
        'booking.payment_provider',
        'booking.paymentProvider',
        'record.payment_provider',
        'record.paymentProvider',
        'record.booking.payment_provider',
        'record.booking.paymentProvider',
        'record.booking_details.payment_provider',
        'record.booking_details.paymentProvider',
      ]),
    ]).toLowerCase();
  }

  String get paymentMode {
    return _firstNonEmpty([
      _firstPathValue(const <String>[
        'payment_mode',
        'paymentMode',
        'booking.payment_mode',
        'booking.paymentMode',
        'record.payment_mode',
        'record.paymentMode',
        'record.booking.payment_mode',
        'record.booking.paymentMode',
        'record.booking_details.payment_mode',
        'record.booking_details.paymentMode',
      ]),
    ]).toLowerCase();
  }

  /// Returns a validated Mollie checkout URL from the authoritative record, or
  /// null when missing or failing HTTPS/Mollie-host checks.
  String? get checkoutUrl {
    final raw = _firstNonEmpty([
      _firstPathValue(const <String>[
        'checkout_url',
        'checkoutUrl',
        'payment_url',
        'paymentUrl',
        'record.checkout_url',
        'record.checkoutUrl',
        'record.payment_url',
        'record.paymentUrl',
        'booking.checkout_url',
        'booking.checkoutUrl',
        'booking.payment_url',
        'booking.paymentUrl',
        'record.booking.checkout_url',
        'record.booking.checkoutUrl',
        'record.booking.payment_url',
        'record.booking.paymentUrl',
        'payload.checkout_url',
        'payload.checkoutUrl',
        'payload.payment_url',
        'payload.paymentUrl',
        'record.mollie.checkout_url',
        'record.mollie.checkoutUrl',
        'record.mollie._links.checkout.href',
        'record.booking.mollie.checkout_url',
        'record.booking.mollie.checkoutUrl',
        'record.booking.mollie._links.checkout.href',
        'mollie.checkout_url',
        'mollie.checkoutUrl',
        'mollie._links.checkout.href',
      ]),
    ]);
    return _sanitizeMollieCheckoutUrl(raw);
  }

  String? _sanitizeMollieCheckoutUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme.toLowerCase() != 'https') return null;
    final host = uri.host.toLowerCase();
    if (host.isEmpty || !host.contains('mollie')) return null;
    return uri.toString();
  }

  String get receiptReference => _firstPathValue(const <String>[
    'receipt_reference',
    'receiptReference',
    'booking.receipt_reference',
    'booking.receiptReference',
    'record.receipt_reference',
    'record.receiptReference',
    'record.booking.receipt_reference',
    'record.booking.receiptReference',
    'record.references.receipt_reference',
    'record.references.receiptReference',
    'payload.receipt_reference',
    'payload.receiptReference',
    'payload.booking.receipt_reference',
    'payload.booking.receiptReference',
    'payload.references.receipt_reference',
    'payload.references.receiptReference',
  ]);

  String get planningReference => _firstPathValue(const <String>[
    'planning_reference',
    'planningReference',
    'booking.planning_reference',
    'booking.planningReference',
    'record.planning_reference',
    'record.planningReference',
    'record.booking.planning_reference',
    'record.booking.planningReference',
    'record.references.planning_reference',
    'record.references.planningReference',
    'payload.planning_reference',
    'payload.planningReference',
    'payload.booking.planning_reference',
    'payload.booking.planningReference',
    'payload.references.planning_reference',
    'payload.references.planningReference',
  ]);

  String get publicBookingReference => _firstPathValue(const <String>[
    'public_booking_reference',
    'publicBookingReference',
    'booking_reference',
    'bookingReference',
    'public_reference',
    'publicReference',
    'booking.public_booking_reference',
    'booking.publicBookingReference',
    'booking.booking_reference',
    'booking.bookingReference',
    'booking.public_reference',
    'booking.publicReference',
    'record.public_booking_reference',
    'record.publicBookingReference',
    'record.booking_reference',
    'record.bookingReference',
    'record.public_reference',
    'record.publicReference',
    'record.booking.public_booking_reference',
    'record.booking.publicBookingReference',
    'record.booking.booking_reference',
    'record.booking.bookingReference',
    'record.booking.public_reference',
    'record.booking.publicReference',
    'record.references.public_booking_reference',
    'record.references.publicBookingReference',
    'record.references.booking_reference',
    'record.references.bookingReference',
    'record.references.public_reference',
    'record.references.publicReference',
    'payload.public_booking_reference',
    'payload.publicBookingReference',
    'payload.booking_reference',
    'payload.bookingReference',
    'payload.public_reference',
    'payload.publicReference',
    'payload.booking.public_booking_reference',
    'payload.booking.publicBookingReference',
    'payload.booking.booking_reference',
    'payload.booking.bookingReference',
    'payload.booking.public_reference',
    'payload.booking.publicReference',
    'payload.references.public_booking_reference',
    'payload.references.publicBookingReference',
    'payload.references.booking_reference',
    'payload.references.bookingReference',
    'payload.references.public_reference',
    'payload.references.publicReference',
  ]);

  String get internalBookingId => _firstNonEmpty([
    bookingId,
    _firstPathValue(const <String>[
      'booking_id',
      'bookingId',
      'id',
      'booking.booking_id',
      'booking.bookingId',
      'record.booking_id',
      'record.bookingId',
      'record.booking.booking_id',
      'record.booking.bookingId',
      'payload.booking_id',
      'payload.bookingId',
      'payload.booking.booking_id',
      'payload.booking.bookingId',
    ]),
  ]);

  bool get _methodImpliesPaid {
    const inCarPaidMethods = <String>{'cash', 'bancontact', 'qr', 'card'};
    return inCarPaidMethods.contains(paymentMethod);
  }

  bool get isPaid {
    final s = rawPaymentStatus;
    return s == 'paid' ||
        s == 'confirmed' ||
        s == 'completed' ||
        s == 'success' ||
        _methodImpliesPaid;
  }

  /// True when the customer paid online (Mollie/online) and must contact the
  /// company instead of cancelling directly from "Mijn boekingen".
  bool blocksCustomerPaidOnlineCancellation({String? classifiedPaymentToken}) {
    final token = _normalizeCustomerPaymentDisplayToken(
      classifiedPaymentToken ?? rawPaymentStatus,
    );
    if (_isPayInCarCustomerPaymentDisplayToken(token)) return false;
    if (_isOnlinePendingCustomerPaymentDisplayToken(token)) return false;
    if (!_isPaidCustomerPaymentDisplayToken(token) &&
        !_isPartialCustomerPaymentDisplayToken(token)) {
      return false;
    }
    if (_methodImpliesPaid) return false;
    if (_isManualCustomerPaymentChannel(
      provider: paymentProvider,
      mode: paymentMode,
    )) {
      return false;
    }
    if (_isMollieCustomerPaymentChannel(
      provider: paymentProvider,
      mode: paymentMode,
    )) {
      return true;
    }
    const onlineTokens = <String>{
      'online',
      'online_payment',
      'online_payments',
      'online-payments',
      'prepaid',
    };
    final providerToken = _normalizeCustomerPaymentDisplayToken(
      paymentProvider,
    );
    final modeToken = _normalizeCustomerPaymentDisplayToken(paymentMode);
    if (onlineTokens.contains(providerToken) ||
        onlineTokens.contains(modeToken)) {
      return true;
    }
    return false;
  }

  String get extraOptions {
    final direct = _firstPathValue(const <String>[
      'extras',
      'extra_service',
      'extra_service_key',
      'premium_options',
      'selected_options',
      'booking.extras',
      'booking.extra_service',
      'booking.extra_service_key',
      'booking.premium_options',
      'booking.selected_options',
      'record.booking.extras',
      'record.booking.extra_service',
      'record.booking.extra_service_key',
      'record.booking.premium_options',
      'record.booking.selected_options',
      'payload.extras',
      'payload.extra_service',
      'payload.extra_service_key',
      'payload.premium_options',
      'payload.selected_options',
      'quote.inputs.extras',
      'quote.inputs.extra_service',
      'quote.inputs.extra_service_key',
    ]);
    if (direct.isNotEmpty) return direct;

    String normalizeList(dynamic raw) {
      if (raw is! List) return '';
      final values = raw
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => _isMeaningful(e))
          .toList(growable: false);
      if (values.isEmpty) return '';
      return values.join(', ');
    }

    final listValue = normalizeList(_valueAtPath('extras'));
    if (listValue.isNotEmpty) return listValue;
    final bookingListValue = normalizeList(_valueAtPath('booking.extras'));
    if (bookingListValue.isNotEmpty) return bookingListValue;
    final payloadListValue = normalizeList(_valueAtPath('payload.extras'));
    if (payloadListValue.isNotEmpty) return payloadListValue;
    return '';
  }

  List<CustomerOperationalLegView> get operationalLegs {
    final byType = <String, CustomerOperationalLegView>{};

    CustomerOperationalLegView? legFromMap(Map<String, dynamic> map) {
      final legId = _firstNonEmpty([
        map['leg_id']?.toString(),
        map['legId']?.toString(),
      ]);
      if (legId.isEmpty) return null;
      final legTypeRaw = (map['leg_type'] ?? map['legType'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final legType = legTypeRaw == 'return' ? 'return' : 'outbound';
      final status =
          (map['status'] ??
                  map['lifecycle_status'] ??
                  map['lifecycleStatus'] ??
                  lifecycleStatus)
              .toString()
              .trim();
      return CustomerOperationalLegView(
        legId: legId,
        legType: legType,
        status: status,
        priceInclVat: _roundtripLegPriceFromMap(map),
      );
    }

    void absorbLeg(CustomerOperationalLegView? leg) {
      if (leg == null || leg.legId.trim().isEmpty) return;
      byType[leg.legType] = leg;
    }

    final rawLists = <dynamic>[
      _valueAtPath('record.operational_legs'),
      _valueAtPath('record.operationalLegs'),
      _valueAtPath('record.booking.operational_legs'),
      _valueAtPath('record.booking.operationalLegs'),
      _valueAtPath('record.payload.operational_legs'),
      _valueAtPath('record.payload.operationalLegs'),
      _valueAtPath('operational_legs'),
      _valueAtPath('operationalLegs'),
      _valueAtPath('booking.operational_legs'),
      _valueAtPath('booking.operationalLegs'),
      _valueAtPath('payload.operational_legs'),
      _valueAtPath('payload.operationalLegs'),
      _valueAtPath('legs'),
      _valueAtPath('record.legs'),
      _valueAtPath('quote.legs'),
      _valueAtPath('record.quote.legs'),
    ];
    for (final raw in rawLists) {
      if (raw is! List) continue;
      for (final entry in raw) {
        if (entry is! Map) continue;
        absorbLeg(legFromMap(Map<String, dynamic>.from(entry)));
      }
    }

    String directLegId(List<String> paths) => _firstPathValue(paths);

    absorbLeg(
      directLegId(const [
            'record.outbound_leg_id',
            'record.outboundLegId',
            'outbound_leg_id',
            'outboundLegId',
            'booking.outbound_leg_id',
            'booking.outboundLegId',
            'record.booking.outbound_leg_id',
            'record.booking.outboundLegId',
            'payload.outbound_leg_id',
            'payload.outboundLegId',
          ]).isEmpty
          ? null
          : CustomerOperationalLegView(
              legId: directLegId(const [
                'record.outbound_leg_id',
                'record.outboundLegId',
                'outbound_leg_id',
                'outboundLegId',
                'booking.outbound_leg_id',
                'booking.outboundLegId',
                'record.booking.outbound_leg_id',
                'record.booking.outboundLegId',
                'payload.outbound_leg_id',
                'payload.outboundLegId',
              ]),
              legType: 'outbound',
              status: lifecycleStatus,
            ),
    );
    absorbLeg(
      directLegId(const [
            'record.return_leg_id',
            'record.returnLegId',
            'return_leg_id',
            'returnLegId',
            'booking.return_leg_id',
            'booking.returnLegId',
            'record.booking.return_leg_id',
            'record.booking.returnLegId',
            'payload.return_leg_id',
            'payload.returnLegId',
          ]).isEmpty
          ? null
          : CustomerOperationalLegView(
              legId: directLegId(const [
                'record.return_leg_id',
                'record.returnLegId',
                'return_leg_id',
                'returnLegId',
                'booking.return_leg_id',
                'booking.returnLegId',
                'record.booking.return_leg_id',
                'record.booking.returnLegId',
                'payload.return_leg_id',
                'payload.returnLegId',
              ]),
              legType: 'return',
              status: lifecycleStatus,
            ),
    );

    final parentId = bookingId.trim();
    if (isRoundtrip && parentId.isNotEmpty) {
      byType.putIfAbsent(
        'outbound',
        () => CustomerOperationalLegView(
          legId: '$parentId:OUTBOUND',
          legType: 'outbound',
          status: lifecycleStatus,
        ),
      );
      byType.putIfAbsent(
        'return',
        () => CustomerOperationalLegView(
          legId: '$parentId:RETURN',
          legType: 'return',
          status: lifecycleStatus,
        ),
      );
    }

    return byType.values.toList(growable: false);
  }

  bool get isCustomerRoundtripBooking {
    if (isRoundtrip) return true;
    final serviceToken = service.trim().toLowerCase();
    if (serviceToken.contains('roundtrip') ||
        serviceToken.contains('round_trip') ||
        serviceToken == 'airport_transfer_roundtrip') {
      return true;
    }
    return operationalLegs.length > 1;
  }

  bool get hasRoundtripOperationalLegs => isCustomerRoundtripBooking;

  CustomerOperationalLegView? get customerOutboundLeg {
    for (final leg in operationalLegs) {
      if (leg.legType == 'outbound') return leg;
    }
    return null;
  }

  CustomerOperationalLegView? get customerReturnLeg {
    for (final leg in operationalLegs) {
      if (leg.legType == 'return') return leg;
    }
    return null;
  }

  bool get isConfirmedPaidForRoundtripProjection {
    final token = rawPaymentStatus.trim().toLowerCase();
    return token == 'paid' ||
        token == 'confirmed' ||
        token == 'completed' ||
        token == 'success' ||
        token == 'partially_paid';
  }

  List<Map<String, dynamic>> get _operationalLegMaps {
    final maps = <Map<String, dynamic>>[];
    final rawLists = <dynamic>[
      _valueAtPath('record.operational_legs'),
      _valueAtPath('record.operationalLegs'),
      _valueAtPath('record.booking.operational_legs'),
      _valueAtPath('record.booking.operationalLegs'),
      _valueAtPath('operational_legs'),
      _valueAtPath('operationalLegs'),
      _valueAtPath('booking.operational_legs'),
      _valueAtPath('booking.operationalLegs'),
      _valueAtPath('payload.operational_legs'),
      _valueAtPath('payload.operationalLegs'),
      _valueAtPath('legs'),
      _valueAtPath('record.legs'),
      _valueAtPath('quote.legs'),
      _valueAtPath('record.quote.legs'),
    ];
    for (final raw in rawLists) {
      if (raw is! List) continue;
      for (final entry in raw) {
        if (entry is! Map) continue;
        maps.add(Map<String, dynamic>.from(entry));
      }
    }
    return maps;
  }

  CustomerRoundtripPriceProjection? get roundtripPriceProjection {
    if (!isCustomerRoundtripBooking) return null;

    final rawLegMaps = _operationalLegMaps;
    double? outboundPrice;
    double? returnPrice;
    var outboundCancelled = false;
    var returnCancelled = false;

    for (final map in rawLegMaps) {
      final legTypeRaw = (map['leg_type'] ?? map['legType'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final legType = legTypeRaw == 'return' ? 'return' : 'outbound';
      final legPrice = _roundtripLegPriceFromMap(map);
      final legStatus =
          (map['status'] ??
                  map['lifecycle_status'] ??
                  map['lifecycleStatus'] ??
                  '')
              .toString();
      final cancelled = _roundtripLegStatusIsCancelled(legStatus);
      if (legType == 'return') {
        returnPrice = legPrice ?? returnPrice;
        returnCancelled = cancelled || returnCancelled;
      } else {
        outboundPrice = legPrice ?? outboundPrice;
        outboundCancelled = cancelled || outboundCancelled;
      }
    }

    if (rawLegMaps.isEmpty) {
      for (final leg in operationalLegs) {
        if (leg.legType == 'return') {
          returnCancelled = leg.isCancelledLeg;
        } else {
          outboundCancelled = leg.isCancelledLeg;
        }
      }
    }

    outboundPrice ??= priceInclVatMain;
    returnPrice ??= priceInclVatReturn;

    final originalTotal = _roundtripResolveOriginalTotal(
      outboundPrice: outboundPrice,
      returnPrice: returnPrice,
    );
    if (originalTotal == null) return null;

    if (outboundPrice == null && returnPrice != null) {
      outboundPrice = (originalTotal - returnPrice).clamp(0, originalTotal);
    } else if (returnPrice == null && outboundPrice != null) {
      returnPrice = (originalTotal - outboundPrice).clamp(0, originalTotal);
    }

    outboundPrice ??= originalTotal / 2;
    returnPrice ??= originalTotal - outboundPrice;

    final resolvedOutboundPrice = outboundPrice;
    final resolvedReturnPrice = returnPrice;

    final outboundAmount = outboundCancelled ? 0.0 : resolvedOutboundPrice;
    final returnAmount = returnCancelled ? 0.0 : resolvedReturnPrice;
    final cancelledOutboundAmount = outboundCancelled
        ? resolvedOutboundPrice
        : 0.0;
    final cancelledReturnAmount = returnCancelled ? resolvedReturnPrice : 0.0;

    final activeTotal = outboundAmount + returnAmount;
    final cancelledTotal = cancelledOutboundAmount + cancelledReturnAmount;
    final hasLegCancellation = cancelledTotal > 0.009;

    if (!hasLegCancellation) return null;

    final paid = isConfirmedPaidForRoundtripProjection;
    final payableTotal = paid ? 0.0 : activeTotal;
    final creditDueTotal = paid ? cancelledTotal : 0.0;

    final projection = CustomerRoundtripPriceProjection(
      originalTotal: originalTotal,
      activeTotal: activeTotal,
      cancelledTotal: cancelledTotal,
      payableTotal: payableTotal,
      creditDueTotal: creditDueTotal,
      paid: paid,
      outbound: CustomerRoundtripLegPriceView(
        legType: 'outbound',
        priceInclVat: resolvedOutboundPrice,
        isCancelled: outboundCancelled,
      ),
      returnLeg: CustomerRoundtripLegPriceView(
        legType: 'return',
        priceInclVat: resolvedReturnPrice,
        isCancelled: returnCancelled,
      ),
    );

    debugPrint(
      '[ROUNDTRIP_PRICE][PROJECT] booking=${_safeRefPreview(bookingId)} original=${projection.originalTotal?.toStringAsFixed(2) ?? "-"} active=${projection.activeTotal?.toStringAsFixed(2) ?? "-"} cancelled=${projection.cancelledTotal?.toStringAsFixed(2) ?? "-"} payable=${projection.payableTotal?.toStringAsFixed(2) ?? "-"} credit=${projection.creditDueTotal?.toStringAsFixed(2) ?? "-"} paid=$paid',
    );
    debugPrint(
      '[ROUNDTRIP_PRICE][LEG] booking=${_safeRefPreview(bookingId)} outbound=${resolvedOutboundPrice.toStringAsFixed(2)} cancelled=$outboundCancelled return=${resolvedReturnPrice.toStringAsFixed(2)} cancelled=$returnCancelled',
    );
    debugPrint(
      '[ROUNDTRIP_PRICE][ACTIVE_TOTAL] booking=${_safeRefPreview(bookingId)} active=${projection.activeTotal?.toStringAsFixed(2) ?? "-"} payable=${projection.payableTotal?.toStringAsFixed(2) ?? "-"}',
    );
    if (paid) {
      debugPrint(
        '[ROUNDTRIP_PRICE][PAID_CREDIT_BREAKDOWN] booking=${_safeRefPreview(bookingId)} original=${projection.originalTotal?.toStringAsFixed(2) ?? "-"} cancelled=${projection.cancelledTotal?.toStringAsFixed(2) ?? "-"} credit=${projection.creditDueTotal?.toStringAsFixed(2) ?? "-"} active=${projection.activeTotal?.toStringAsFixed(2) ?? "-"}',
      );
    } else {
      debugPrint(
        '[ROUNDTRIP_PRICE][UNPAID_SIMPLE] booking=${_safeRefPreview(bookingId)} active=${projection.activeTotal?.toStringAsFixed(2) ?? "-"} payable=${projection.payableTotal?.toStringAsFixed(2) ?? "-"} outboundCancelled=$outboundCancelled returnCancelled=$returnCancelled',
      );
    }
    return projection;
  }

  ({String from, String to, String pickupIso}) roundtripLegRoute(
    String legType,
  ) {
    final normalizedType = legType == 'return' ? 'return' : 'outbound';
    for (final map in _operationalLegMaps) {
      final legTypeRaw = (map['leg_type'] ?? map['legType'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final mapType = legTypeRaw == 'return' ? 'return' : 'outbound';
      if (mapType != normalizedType) continue;
      final from = _firstNonEmpty([
        map['from']?.toString(),
        map['pickup_address']?.toString(),
        map['pickupAddress']?.toString(),
      ]);
      final to = _firstNonEmpty([
        map['to']?.toString(),
        map['destination']?.toString(),
        map['destination_address']?.toString(),
        map['destinationAddress']?.toString(),
      ]);
      final pickup = _firstNonEmpty([
        map['pickup_iso']?.toString(),
        map['pickupIso']?.toString(),
        map['scheduled_pickup_at']?.toString(),
      ]);
      if (from.isNotEmpty || to.isNotEmpty || pickup.isNotEmpty) {
        return (from: from, to: to, pickupIso: pickup);
      }
    }
    if (normalizedType == 'outbound') {
      return (from: fromAddress, to: toAddress, pickupIso: pickupIso);
    }
    return (
      from: _isMeaningful(returnFrom) ? returnFrom : toAddress,
      to: _isMeaningful(returnTo) ? returnTo : fromAddress,
      pickupIso: returnPickupIso,
    );
  }

  double? _customerRoundtripParentCardTotal() {
    final outbound = priceInclVatMain;
    final ret = priceInclVatReturn;
    final legSum = (outbound != null && ret != null && outbound > 0 && ret > 0)
        ? outbound + ret
        : null;

    final parentTotal = priceInclVatTotal ?? totalAmount;

    if (legSum != null) {
      if (parentTotal == null || parentTotal <= 0) return legSum;
      if (parentTotal + 0.009 < legSum) return legSum;
      // Stored parent totals on airport roundtrips sometimes hold outbound-only.
      if (outbound != null &&
          (parentTotal - outbound).abs() < 0.01 &&
          ret != null &&
          ret > 0.009) {
        return legSum;
      }
      return parentTotal;
    }

    final legs = roundtripLegCardViews;
    if (legs.length >= 2) {
      final fromCards = legs
          .map((leg) => leg.priceInclVat)
          .whereType<double>()
          .where((value) => value > 0)
          .fold<double>(0, (sum, value) => sum + value);
      if (fromCards > 0 &&
          (parentTotal == null ||
              parentTotal <= 0 ||
              parentTotal + 0.009 < fromCards)) {
        return fromCards;
      }
    }

    return parentTotal;
  }

  double? get customerDisplayCardAmount {
    if (isCustomerRoundtripBooking) {
      final projection = roundtripPriceProjection;
      if (projection != null) {
        final amount = projection.customerCardAmount;
        debugPrint(
          '[ROUNDTRIP_PRICE][CARD] booking=${_safeRefPreview(bookingId)} amount=${amount?.toStringAsFixed(2) ?? "-"} paid=${projection.paid} mode=projection',
        );
        return amount;
      }
      final amount = _customerRoundtripParentCardTotal();
      debugPrint(
        '[ROUNDTRIP_PRICE][CARD] booking=${_safeRefPreview(bookingId)} amount=${amount?.toStringAsFixed(2) ?? "-"} mode=roundtrip_total',
      );
      return amount;
    }
    return totalAmount ?? priceInclVatTotal;
  }

  double? get customerDisplayPayableAmount {
    final projection = roundtripPriceProjection;
    if (projection == null) {
      return totalAmount ?? priceInclVatTotal;
    }
    return projection.paid ? projection.activeTotal : projection.payableTotal;
  }

  String? get roundtripCancelledLegChipToken {
    final projection = roundtripPriceProjection;
    if (projection == null) return null;
    if (projection.outbound.isCancelled && !projection.returnLeg.isCancelled) {
      return 'outbound';
    }
    if (projection.returnLeg.isCancelled && !projection.outbound.isCancelled) {
      return 'return';
    }
    return null;
  }

  /// Customer-safe refund/credit row for the paid roundtrip Prijs breakdown.
  /// Reads cancelled-leg operational fields first, then parent record layers.
  CustomerRoundtripRefundDisplay? get customerRoundtripRefundDisplay {
    final projection = roundtripPriceProjection;
    if (projection == null || !projection.paid) return null;

    final cancelledLegType = projection.cancelledLegType;
    Map<String, dynamic>? cancelledLegMap;
    for (final map in _operationalLegMaps) {
      final legTypeRaw = (map['leg_type'] ?? map['legType'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final legType = legTypeRaw == 'return' ? 'return' : 'outbound';
      if (legType == cancelledLegType) {
        cancelledLegMap = map;
        break;
      }
    }

    String readRefundText(String snake, String camel) {
      final fromLeg = _customerRefundTextFromMap(cancelledLegMap, snake, camel);
      if (fromLeg.isNotEmpty) return fromLeg;
      return _firstPathValue([
        'record.$snake',
        'record.$camel',
        'record.booking.$snake',
        'record.booking.$camel',
        'record.payload.$snake',
        'record.payload.$camel',
        'booking.$snake',
        'booking.$camel',
        'payload.$snake',
        'payload.$camel',
        snake,
        camel,
      ]);
    }

    int? readRefundCents(String snake, String camel) {
      final fromLeg = _customerRefundCentsFromMap(
        cancelledLegMap,
        snake,
        camel,
      );
      if (fromLeg != null && fromLeg > 0) return fromLeg;
      for (final path in <String>[
        'record.$snake',
        'record.$camel',
        'record.booking.$snake',
        'record.booking.$camel',
        'record.payload.$snake',
        'record.payload.$camel',
        'booking.$snake',
        'booking.$camel',
        'payload.$snake',
        'payload.$camel',
        snake,
        camel,
      ]) {
        final cents = _customerRefundCentsFromDynamic(_valueAtPath(path));
        if (cents != null && cents > 0) return cents;
      }
      return null;
    }

    final refundStatus = readRefundText('refund_status', 'refundStatus');
    final mollieRefundStatus = readRefundText(
      'mollie_refund_status',
      'mollieRefundStatus',
    );
    final mollieRefundId = readRefundText('mollie_refund_id', 'mollieRefundId');
    final refundedAt = readRefundText('refunded_at', 'refundedAt');
    final creditDecision = readRefundText('credit_decision', 'creditDecision');
    final refundedAmountCents = readRefundCents(
      'refunded_amount_cents',
      'refundedAmountCents',
    );
    final creditedAmountCents = readRefundCents(
      'credited_amount_cents',
      'creditedAmountCents',
    );

    final creditDueTotal = projection.creditDueTotal ?? 0;
    final hasCreditDueAmount = creditDueTotal > 0.009;
    final manualHandled = _customerCreditDecisionIsManual(creditDecision);

    final phase = classifyCustomerRefundDisplayPhase(
      refundStatus: refundStatus,
      mollieRefundStatus: mollieRefundStatus,
      mollieRefundId: mollieRefundId,
      refundedAmountCents: refundedAmountCents,
      refundedAt: refundedAt,
      creditDecision: creditDecision,
      hasCreditDueAmount: hasCreditDueAmount,
    );

    double? amountEur;
    if (phase == CustomerRefundDisplayPhase.refunded &&
        refundedAmountCents != null &&
        refundedAmountCents > 0) {
      amountEur = refundedAmountCents / 100;
    } else if (creditedAmountCents != null && creditedAmountCents > 0) {
      amountEur = creditedAmountCents / 100;
    } else if (hasCreditDueAmount) {
      amountEur = creditDueTotal;
    }

    return CustomerRoundtripRefundDisplay(
      phase: phase,
      amountEur: amountEur,
      refundedAt: refundedAt,
      manualHandled: manualHandled,
    );
  }

  List<CustomerRoundtripLegCardView> get roundtripLegCardViews {
    if (!isCustomerRoundtripBooking) {
      return const <CustomerRoundtripLegCardView>[];
    }
    final projection = roundtripPriceProjection;

    CustomerRoundtripLegCardView buildLeg(String legType) {
      final route = roundtripLegRoute(legType);
      final leg = legType == 'return' ? customerReturnLeg : customerOutboundLeg;
      final projectedLeg = legType == 'return'
          ? projection?.returnLeg
          : projection?.outbound;
      final fallbackPrice = legType == 'return'
          ? priceInclVatReturn
          : priceInclVatMain;
      // Roundtrip operational-leg completion scope: the backend leg status is
      // the source of truth. A parent COMPLETED / CANCELLED MUST NOT overwrite
      // a still-open sibling leg (split_no_wait airport roundtrip: outbound
      // completed, return still PENDING/SCHEDULED). The parent lifecycle is
      // only inherited when the leg snapshot carries no status of its own.
      final rawLegStatus = leg?.status.trim() ?? '';
      final String status = rawLegStatus.isNotEmpty
          ? rawLegStatus
          : lifecycleStatus;
      return CustomerRoundtripLegCardView(
        legType: legType,
        legId: leg?.legId ?? '',
        status: status,
        from: route.from,
        to: route.to,
        pickupIso: route.pickupIso,
        priceInclVat:
            projectedLeg?.priceInclVat ?? leg?.priceInclVat ?? fallbackPrice,
        isCancelled:
            projectedLeg?.isCancelled ?? (leg?.isCancelledLeg ?? false),
      );
    }

    final legs = <CustomerRoundtripLegCardView>[
      buildLeg('outbound'),
      buildLeg('return'),
    ];
    debugPrint(
      '[ROUNDTRIP_LEG_UI][CUSTOMER_SPLIT] booking=${_safeRefPreview(bookingId)} legs=${legs.map((leg) => "${leg.legType}:${leg.status}:${leg.isCancelled ? "cancelled" : "active"}").join("|")}',
    );
    return legs;
  }

  Map<String, dynamic>? get completedRoundtripReceiptPayload {
    if (!isCustomerRoundtripBooking) return null;
    final parentCompleted =
        _normalizeCustomerLifecycleStatus(lifecycleStatus) == 'COMPLETED';
    if (!parentCompleted || !isConfirmedPaidForRoundtripProjection) {
      return null;
    }

    final legs = roundtripLegCardViews;
    final outboundLeg = legs
        .where((leg) => leg.legType == 'outbound')
        .cast<CustomerRoundtripLegCardView?>()
        .firstWhere((leg) => leg != null, orElse: () => null);
    final returnLeg = legs
        .where((leg) => leg.legType == 'return')
        .cast<CustomerRoundtripLegCardView?>()
        .firstWhere((leg) => leg != null, orElse: () => null);
    if (outboundLeg == null || returnLeg == null) return null;
    if (outboundLeg.isCancelled || returnLeg.isCancelled) return null;

    final outboundPrice = outboundLeg.priceInclVat ?? priceInclVatMain;
    final returnPrice = returnLeg.priceInclVat ?? priceInclVatReturn;
    final legTotal = (outboundPrice != null && returnPrice != null)
        ? outboundPrice + returnPrice
        : null;
    final total = legTotal ?? priceInclVatTotal ?? totalAmount;
    if (total == null || total <= 0) return null;
    final waitingMinutes = waitMin;

    String statusFor(CustomerRoundtripLegCardView leg) {
      final normalized = _normalizeCustomerLifecycleStatus(leg.status);
      return normalized.isEmpty ? lifecycleStatus : normalized;
    }

    final payload = <String, dynamic>{
      'display_mode': 'completed_roundtrip',
      'original_total_eur': total,
      'active_total_eur': total,
      'payable_total_eur': total,
      'paid': true,
      'active_leg_type': 'outbound',
      'outbound_from': outboundLeg.from,
      'outbound_to': outboundLeg.to,
      'outbound_pickup_iso': outboundLeg.pickupIso,
      'outbound_price_incl_vat': outboundPrice,
      'outbound_status': statusFor(outboundLeg),
      'outbound_distance_km': distanceKm,
      'outbound_duration_min': durationMin,
      'return_from': returnLeg.from,
      'return_to': returnLeg.to,
      'return_pickup_iso': returnLeg.pickupIso,
      'return_price_incl_vat': returnPrice,
      'return_status': statusFor(returnLeg),
      'return_distance_km': null,
      'return_duration_min': null,
      'booked_wait_minutes': waitingMinutes,
      'waiting_package': waitingMinutes != null && waitingMinutes > 0,
      'legs': <Map<String, dynamic>>[
        <String, dynamic>{
          'leg_type': 'outbound',
          'from': outboundLeg.from,
          'to': outboundLeg.to,
          'pickup_iso': outboundLeg.pickupIso,
          'status': statusFor(outboundLeg),
          'price_incl_vat': outboundPrice,
          'distance_km': distanceKm,
          'duration_min': durationMin,
        },
        <String, dynamic>{
          'leg_type': 'return',
          'from': returnLeg.from,
          'to': returnLeg.to,
          'pickup_iso': returnLeg.pickupIso,
          'status': statusFor(returnLeg),
          'price_incl_vat': returnPrice,
        },
      ],
    };
    debugPrint(
      '[ROUNDTRIP_RECEIPT][COMPLETED] booking=${_safeRefPreview(bookingId)} total=${total.toStringAsFixed(2)} wait=${waitingMinutes?.round() ?? 0}',
    );
    return payload;
  }

  StoredCustomerBooking mergeRoundtripSnapshotIntoStored(
    StoredCustomerBooking stored,
  ) {
    final quotePatch = Map<String, dynamic>.from(stored.quote);
    final ops = record['operational_legs'] ?? record['operationalLegs'];
    if (ops is List) {
      quotePatch['operational_legs'] = ops;
    }
    for (final key in const <String>[
      'price_incl_vat_main',
      'priceInclVatMain',
      'price_incl_vat_return',
      'priceInclVatReturn',
      'price_incl_vat',
      'priceInclVat',
    ]) {
      final value = _valueAtPath('record.$key');
      if (value == null) continue;
      quotePatch[key] = value;
      final bookingValue = _valueAtPath('record.booking.$key');
      if (bookingValue != null) {
        quotePatch['booking_$key'] = bookingValue;
      }
    }
    final cardAmount = customerDisplayCardAmount;
    return stored.copyWith(
      price: cardAmount ?? stored.price,
      quote: quotePatch,
    );
  }

  double? _roundtripResolveOriginalTotal({
    required double? outboundPrice,
    required double? returnPrice,
  }) {
    final totalFromFields = priceInclVatTotal ?? totalAmount;
    if (totalFromFields != null && totalFromFields > 0) {
      return totalFromFields;
    }
    if (outboundPrice != null &&
        returnPrice != null &&
        outboundPrice > 0 &&
        returnPrice > 0) {
      return outboundPrice + returnPrice;
    }
    return null;
  }

  double? _roundtripLegPriceFromMap(Map<String, dynamic> map) {
    return _firstPathNumFromMap(map, const <String>[
      'price_incl_vat',
      'priceInclVat',
      'leg_price_incl_vat',
      'legPriceInclVat',
      'amount',
      'total',
    ]);
  }

  double? _firstPathNumFromMap(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final raw = map[key];
      if (raw == null) continue;
      final parsed = double.tryParse(raw.toString().replaceAll(',', '.'));
      if (parsed != null && parsed.isFinite) return parsed;
    }
    return null;
  }

  bool _roundtripLegStatusIsCancelled(String statusRaw) {
    final normalized = statusRaw.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    return normalized.contains('CANCEL') || normalized == 'DELETED';
  }
}

class CustomerRoundtripLegPriceView {
  const CustomerRoundtripLegPriceView({
    required this.legType,
    required this.priceInclVat,
    required this.isCancelled,
  });

  final String legType;
  final double? priceInclVat;
  final bool isCancelled;
}

class CustomerRoundtripLegCardView {
  const CustomerRoundtripLegCardView({
    required this.legType,
    required this.legId,
    required this.status,
    required this.from,
    required this.to,
    required this.pickupIso,
    required this.priceInclVat,
    required this.isCancelled,
  });

  final String legType;
  final String legId;
  final String status;
  final String from;
  final String to;
  final String pickupIso;
  final double? priceInclVat;
  final bool isCancelled;

  bool get isActive => !isCancelled;

  bool get isCompleted {
    if (isCancelled) return false;
    return _normalizeCustomerLifecycleStatus(status) == 'COMPLETED';
  }

  bool get isTerminal {
    if (isCancelled) return true;
    return _isCustomerBookingTerminalStatus(status);
  }
}

class CustomerRoundtripRefundDisplay {
  const CustomerRoundtripRefundDisplay({
    required this.phase,
    required this.amountEur,
    this.refundedAt = '',
    this.manualHandled = false,
  });

  final CustomerRefundDisplayPhase phase;
  final double? amountEur;
  final String refundedAt;
  final bool manualHandled;
}

class CustomerRoundtripPriceProjection {
  const CustomerRoundtripPriceProjection({
    required this.originalTotal,
    required this.activeTotal,
    required this.cancelledTotal,
    required this.payableTotal,
    required this.creditDueTotal,
    required this.paid,
    required this.outbound,
    required this.returnLeg,
  });

  final double? originalTotal;
  final double? activeTotal;
  final double? cancelledTotal;
  final double? payableTotal;
  final double? creditDueTotal;
  final bool paid;
  final CustomerRoundtripLegPriceView outbound;
  final CustomerRoundtripLegPriceView returnLeg;

  bool get showUnpaidSimpleUx => !paid;

  bool get showPaidCreditBreakdown => paid;

  String get activeLegType =>
      outbound.isCancelled && !returnLeg.isCancelled ? 'return' : 'outbound';

  String get cancelledLegType => outbound.isCancelled ? 'outbound' : 'return';

  CustomerRoundtripLegPriceView get activeLeg =>
      activeLegType == 'return' ? returnLeg : outbound;

  CustomerRoundtripLegPriceView get cancelledLeg =>
      cancelledLegType == 'return' ? returnLeg : outbound;

  double? get customerCardAmount => paid ? activeTotal : payableTotal;

  double? get customerReceiptTotal => paid ? activeTotal : payableTotal;

  Map<String, dynamic> toReceiptPayload({required CustomerBookingView view}) {
    final outboundRoute = view.roundtripLegRoute('outbound');
    final returnRoute = view.roundtripLegRoute('return');
    final activeRoute = activeLegType == 'return' ? returnRoute : outboundRoute;
    final displayMode = paid ? 'paid_credit_breakdown' : 'unpaid_simple';

    debugPrint(
      '[ROUNDTRIP_RECEIPT][ACTIVE_LEG] booking=${_safeRefPreview(view.bookingId)} type=$activeLegType from=${activeRoute.from} to=${activeRoute.to} pickup=${activeRoute.pickupIso}',
    );
    debugPrint(
      '[ROUNDTRIP_RECEIPT][CANCELLED_LEG_NOTE] booking=${_safeRefPreview(view.bookingId)} leg=$cancelledLegType mode=$displayMode',
    );

    return <String, dynamic>{
      'display_mode': displayMode,
      'original_total_eur': originalTotal,
      'active_total_eur': activeTotal,
      'cancelled_total_eur': cancelledTotal,
      'payable_total_eur': payableTotal,
      'credit_due_total_eur': creditDueTotal,
      'paid': paid,
      'active_leg_type': activeLegType,
      'cancelled_leg_type': cancelledLegType,
      'active_from': activeRoute.from,
      'active_to': activeRoute.to,
      'active_pickup_iso': activeRoute.pickupIso,
      'outbound_from': outboundRoute.from,
      'outbound_to': outboundRoute.to,
      'outbound_pickup_iso': outboundRoute.pickupIso,
      'return_from': returnRoute.from,
      'return_to': returnRoute.to,
      'return_pickup_iso': returnRoute.pickupIso,
      'outbound_price_incl_vat': outbound.priceInclVat,
      'outbound_cancelled': outbound.isCancelled,
      'return_price_incl_vat': returnLeg.priceInclVat,
      'return_cancelled': returnLeg.isCancelled,
    };
  }
}

class CustomerOperationalLegView {
  const CustomerOperationalLegView({
    required this.legId,
    required this.legType,
    required this.status,
    this.priceInclVat,
  });

  final String legId;
  final String legType;
  final String status;
  final double? priceInclVat;

  bool get isCancelledLeg {
    final normalized = status.trim().toUpperCase();
    return normalized.contains('CANCEL') || normalized == 'DELETED';
  }

  bool get isTerminal {
    final normalized = status.trim().toUpperCase();
    return normalized.contains('CANCEL') ||
        normalized.contains('COMPLETE') ||
        normalized == 'DONE' ||
        normalized == 'FINISHED';
  }
}
