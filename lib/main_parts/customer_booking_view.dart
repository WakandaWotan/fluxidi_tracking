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
    };
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
      'extra_service',
      'extra_service_key',
      'booking.service',
      'booking.extra_service',
      'record.booking.service',
      'record.booking.extra_service',
      'payload.service',
      'quote.inputs.service',
    ]),
  ]);
  String get tier => _firstNonEmpty([
    _firstPathValue(const <String>[
      'tier',
      'booking.tier',
      'record.booking.tier',
      'record.booking_details.tier',
      'payload.tier',
      'quote.inputs.tier',
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
}
