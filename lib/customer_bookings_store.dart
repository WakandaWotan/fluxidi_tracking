import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:fluxidi_tracking/effective_tenant_company_scope.dart';
import 'package:path_provider/path_provider.dart';

String _localScopeSegment(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'default';
  final sanitized = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (sanitized.isEmpty) return 'default';
  return sanitized;
}

String _maskScopeId(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 6) return trimmed;
  return '${trimmed.substring(0, 3)}...${trimmed.substring(trimmed.length - 3)}';
}

({String tenantId, String companyId})? _activeLocalScope() {
  final scope = resolveStrictTenantCompanyScope(allowDriverFallback: true);
  if (scope != null) {
    return (tenantId: scope.tenantId, companyId: scope.companyId);
  }
  final session = CustomerSessionStore.instance.peekCachedSession();
  final defaultTenant = (session?.defaultTenantId ?? '').trim();
  final defaultCompany = (session?.defaultCompanyId ?? '').trim();
  if (defaultTenant.isEmpty || defaultCompany.isEmpty) return null;
  final tenantLower = defaultTenant.toLowerCase();
  final companyLower = defaultCompany.toLowerCase();
  if (tenantLower == 'global' || companyLower == 'global') return null;
  if (tenantLower == 'fluxidi' || companyLower == 'fluxidi') return null;
  debugPrint(
    '[CUSTOMER_BOOKINGS][SCOPE_FALLBACK] source=customer_session_default',
  );
  return (tenantId: defaultTenant, companyId: defaultCompany);
}

bool _isSafeBusinessScopeValue(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  final normalized = trimmed.toLowerCase();
  return normalized != 'global' && normalized != 'fluxidi';
}

class StoredCustomerBooking {
  const StoredCustomerBooking({
    required this.bookingId,
    this.tenantId = '',
    this.companyId = '',
    this.publicBookingId = '',
    this.planningReference = '',
    this.bookingReference = '',
    this.publicReference = '',
    this.receiptReference = '',
    this.paymentBookingId = '',
    this.customerName = '',
    this.customerPhone = '',
    this.customerEmail = '',
    this.from = '',
    this.to = '',
    this.pickupIso = '',
    this.price,
    this.currency = '',
    this.service = '',
    this.tier = '',
    this.pax = '',
    this.bags = '',
    this.paymentStatus = '',
    this.status = '',
    this.createdAt = '',
    this.businessDetected = false,
    this.invoiceRequested = false,
    this.companyName = '',
    this.vatNumber = '',
    this.invoiceEmail = '',
    this.invoiceAddress = '',
    this.quote = const <String, dynamic>{},
    this.updatedAt = '',
  });

  final String bookingId;
  final String tenantId;
  final String companyId;
  final String publicBookingId;
  final String planningReference;
  final String bookingReference;
  final String publicReference;
  final String receiptReference;
  final String paymentBookingId;
  final String customerName;
  final String customerPhone;
  final String customerEmail;
  final String from;
  final String to;
  final String pickupIso;
  final double? price;
  final String currency;
  final String service;
  final String tier;
  final String pax;
  final String bags;
  final String paymentStatus;
  final String status;
  final String createdAt;
  final bool businessDetected;
  final bool invoiceRequested;
  final String companyName;
  final String vatNumber;
  final String invoiceEmail;
  final String invoiceAddress;
  final Map<String, dynamic> quote;
  final String updatedAt;

  String get canonicalBookingId {
    final primary = bookingId.trim();
    if (primary.isNotEmpty) return primary;
    return publicBookingId.trim();
  }

  String get publicBookingReference {
    return publicBookingId.trim();
  }

  StoredCustomerBooking copyWith({
    String? bookingId,
    String? tenantId,
    String? companyId,
    String? publicBookingId,
    String? planningReference,
    String? bookingReference,
    String? publicReference,
    String? receiptReference,
    String? paymentBookingId,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? from,
    String? to,
    String? pickupIso,
    double? price,
    bool clearPrice = false,
    String? currency,
    String? service,
    String? tier,
    String? pax,
    String? bags,
    String? paymentStatus,
    String? status,
    String? createdAt,
    bool? businessDetected,
    bool? invoiceRequested,
    String? companyName,
    String? vatNumber,
    String? invoiceEmail,
    String? invoiceAddress,
    Map<String, dynamic>? quote,
    String? updatedAt,
  }) {
    return StoredCustomerBooking(
      bookingId: bookingId ?? this.bookingId,
      tenantId: tenantId ?? this.tenantId,
      companyId: companyId ?? this.companyId,
      publicBookingId: publicBookingId ?? this.publicBookingId,
      planningReference: planningReference ?? this.planningReference,
      bookingReference: bookingReference ?? this.bookingReference,
      publicReference: publicReference ?? this.publicReference,
      receiptReference: receiptReference ?? this.receiptReference,
      paymentBookingId: paymentBookingId ?? this.paymentBookingId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerEmail: customerEmail ?? this.customerEmail,
      from: from ?? this.from,
      to: to ?? this.to,
      pickupIso: pickupIso ?? this.pickupIso,
      price: clearPrice ? null : (price ?? this.price),
      currency: currency ?? this.currency,
      service: service ?? this.service,
      tier: tier ?? this.tier,
      pax: pax ?? this.pax,
      bags: bags ?? this.bags,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      businessDetected: businessDetected ?? this.businessDetected,
      invoiceRequested: invoiceRequested ?? this.invoiceRequested,
      companyName: companyName ?? this.companyName,
      vatNumber: vatNumber ?? this.vatNumber,
      invoiceEmail: invoiceEmail ?? this.invoiceEmail,
      invoiceAddress: invoiceAddress ?? this.invoiceAddress,
      quote: quote ?? this.quote,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String _string(dynamic value) => value?.toString().trim() ?? '';

  static bool _isMeaningfulString(String s) {
    final normalized = s.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (normalized == '-' ||
        normalized == 'null' ||
        normalized == 'undefined') {
      return false;
    }
    return true;
  }

  static bool _bool(dynamic value) {
    if (value is bool) return value;
    final s = _string(value).toLowerCase();
    return s == '1' || s == 'true' || s == 'yes' || s == 'ja';
  }

  static double? _double(dynamic value) {
    if (value is num) return value.toDouble();
    final s = _string(value);
    if (s.isEmpty) return null;
    return double.tryParse(s.replaceAll(',', '.'));
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  static dynamic _valueAtPath(Map<String, dynamic> source, String path) {
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

  static String _firstPathValue(
    Map<String, dynamic> source,
    List<String> paths, {
    String fallback = '',
  }) {
    for (final path in paths) {
      final value = _valueAtPath(source, path);
      final s = _string(value);
      if (_isMeaningfulString(s)) return s;
    }
    return fallback;
  }

  static double? _firstPathDouble(
    Map<String, dynamic> source,
    List<String> paths, {
    double? fallback,
  }) {
    for (final path in paths) {
      final value = _valueAtPath(source, path);
      final n = _double(value);
      if (n != null) return n;
    }
    return fallback;
  }

  static String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final s = _string(value);
      if (_isMeaningfulString(s)) return s;
    }
    return '';
  }

  static String _preferNonEmpty(String authoritative, String localFallback) {
    if (_isMeaningfulString(authoritative)) return authoritative;
    if (_isMeaningfulString(localFallback)) return localFallback;
    return '';
  }

  static StoredCustomerBooking fromBookSuccess({
    required Map<String, dynamic> response,
    required Map<String, dynamic> requestPayload,
    required String customerName,
    required String customerPhone,
    required String customerEmail,
  }) {
    final bookingMap = _map(response['booking']);
    final payloadMap = _map(requestPayload);
    final quoteMap = _map(payloadMap['quote']);
    final data = <String, dynamic>{
      ...response,
      'booking': bookingMap,
      'payload': payloadMap,
      'quote': quoteMap,
    };
    final bookingId = _firstNonEmpty([
      response['booking_id'],
      response['bookingId'],
      response['public_booking_id'],
      response['publicBookingId'],
      response['id'],
      bookingMap['booking_id'],
      bookingMap['bookingId'],
      bookingMap['public_booking_id'],
      bookingMap['publicBookingId'],
      bookingMap['id'],
      response['public_reference'],
      response['publicReference'],
    ]);
    final publicBookingReference = _firstNonEmpty([
      response['public_booking_reference'],
      response['publicBookingReference'],
      response['booking_reference'],
      response['bookingReference'],
      response['public_reference'],
      response['publicReference'],
      bookingMap['public_booking_reference'],
      bookingMap['publicBookingReference'],
      bookingMap['booking_reference'],
      bookingMap['bookingReference'],
      bookingMap['public_reference'],
      bookingMap['publicReference'],
    ]);
    final planningReference = _firstNonEmpty([
      response['planning_reference'],
      response['planningReference'],
      bookingMap['planning_reference'],
      bookingMap['planningReference'],
    ]);
    final receiptReference = _firstNonEmpty([
      response['receipt_reference'],
      response['receiptReference'],
      bookingMap['receipt_reference'],
      bookingMap['receiptReference'],
    ]);
    final paymentBookingId = _firstNonEmpty([
      response['payment_booking_id'],
      response['paymentBookingId'],
      bookingMap['payment_booking_id'],
      bookingMap['paymentBookingId'],
    ]);
    final paymentStatus = _firstNonEmpty([
      response['payment_status'],
      response['paymentStatus'],
      bookingMap['payment_status'],
      bookingMap['paymentStatus'],
      response['requiresPayment'] == true ? 'pending' : 'unpaid',
    ]);
    final lifecycleStatus = _firstNonEmpty([
      response['status'],
      bookingMap['status'],
      'PENDING',
    ]).toUpperCase();
    final activeScope = _activeLocalScope();
    final tenantId = _firstNonEmpty([
      response['tenant_id'],
      response['tenantId'],
      bookingMap['tenant_id'],
      bookingMap['tenantId'],
      payloadMap['tenant_id'],
      payloadMap['tenantId'],
      activeScope?.tenantId,
    ]);
    final companyId = _firstNonEmpty([
      response['company_id'],
      response['companyId'],
      bookingMap['company_id'],
      bookingMap['companyId'],
      payloadMap['company_id'],
      payloadMap['companyId'],
      activeScope?.companyId,
    ]);
    final businessDetected = _bool(
      _firstNonEmpty([
        response['business_detected'],
        bookingMap['business_detected'],
        requestPayload['vat_number'],
        requestPayload['company_name'],
      ]),
    );
    final invoiceRequested = _bool(
      _firstNonEmpty([
        response['invoice_requested'],
        bookingMap['invoice_requested'],
        requestPayload['invoice_requested'],
        businessDetected ? 'true' : 'false',
      ]),
    );
    return StoredCustomerBooking(
      bookingId: bookingId,
      tenantId: tenantId,
      companyId: companyId,
      publicBookingId: _firstNonEmpty([publicBookingReference, bookingId]),
      planningReference: planningReference,
      bookingReference: _firstNonEmpty([
        response['booking_reference'],
        response['bookingReference'],
        bookingMap['booking_reference'],
        bookingMap['bookingReference'],
        publicBookingReference,
      ]),
      publicReference: _firstNonEmpty([
        response['public_reference'],
        response['publicReference'],
        bookingMap['public_reference'],
        bookingMap['publicReference'],
        publicBookingReference,
      ]),
      receiptReference: receiptReference,
      paymentBookingId: paymentBookingId,
      customerName: customerName.trim(),
      customerPhone: customerPhone.trim(),
      customerEmail: customerEmail.trim().toLowerCase(),
      from: _firstPathValue(data, const <String>[
        'from',
        'pickup',
        'pickup_address',
        'pickupAddress',
        'origin',
        'booking.from',
        'booking.pickup',
        'booking.pickup_address',
        'booking.pickupAddress',
        'payload.from',
        'payload.pickup_address',
        'quote.inputs.from',
      ]),
      to: _firstPathValue(data, const <String>[
        'to',
        'destination',
        'destination_address',
        'destinationAddress',
        'dropoff',
        'dropoff_address',
        'booking.to',
        'booking.destination',
        'booking.destination_address',
        'payload.to',
        'payload.destination_address',
        'quote.inputs.to',
      ]),
      pickupIso: _firstNonEmpty([
        requestPayload['pickup_iso'],
        bookingMap['pickup_iso'],
        bookingMap['pickupStartIso'],
        payloadMap['pickup_iso'],
      ]),
      price: _firstPathDouble(data, const <String>[
        'price',
        'total',
        'amount',
        'price_incl_vat',
        'priceInclVat',
        'booking.price',
        'booking.total',
        'booking.amount',
        'quote.price_incl_vat',
        'quote.priceInclVat',
        'payload.price',
        'payload.total',
        'payload.amount',
        'payload.quote.price_incl_vat',
      ]),
      currency: _firstNonEmpty([
        response['currency'],
        bookingMap['currency'],
        payloadMap['currency'],
        quoteMap['currency'],
        'EUR',
      ]),
      service: _firstPathValue(data, const <String>[
        'service',
        'extra_service',
        'extra_service_key',
        'booking.service',
        'booking.extra_service',
        'payload.service',
        'quote.inputs.service',
      ]),
      tier: _firstNonEmpty([
        payloadMap['tier'],
        bookingMap['tier'],
        quoteMap['tier'],
      ]),
      pax: _firstNonEmpty([
        payloadMap['pax'],
        bookingMap['pax'],
        bookingMap['passengers'],
        quoteMap['pax'],
      ]),
      bags: _firstNonEmpty([
        payloadMap['bags'],
        bookingMap['bags'],
        quoteMap['bags'],
      ]),
      paymentStatus: paymentStatus.toLowerCase(),
      status: lifecycleStatus,
      createdAt: DateTime.now().toIso8601String(),
      businessDetected: businessDetected,
      invoiceRequested: invoiceRequested,
      companyName: _firstNonEmpty([
        requestPayload['company_name'],
        requestPayload['companyName'],
        bookingMap['company_name'],
      ]),
      vatNumber: _firstNonEmpty([
        requestPayload['vat_number'],
        requestPayload['vatNumber'],
        bookingMap['vat_number'],
      ]),
      invoiceEmail: _firstNonEmpty([
        requestPayload['invoice_email'],
        bookingMap['invoice_email'],
      ]),
      invoiceAddress: _firstNonEmpty([
        requestPayload['invoice_address'],
        bookingMap['invoice_address'],
      ]),
      quote: quoteMap,
      updatedAt: DateTime.now().toIso8601String(),
    );
  }

  static StoredCustomerBooking fromAuthoritativeResponse({
    required String bookingId,
    required Map<String, dynamic> response,
    StoredCustomerBooking? fallback,
  }) {
    final root = _map(response);
    final data = _map(root['data']);
    final rootRecord = _map(root['record']);
    final rec = rootRecord.isNotEmpty ? rootRecord : _map(data['record']);
    final booking = _map(rec['booking']);
    final bookingDetails = _map(rec['booking_details']);
    final payload = _map(rec['payload']);
    final quote = _map(rec['quote']);
    final merged = <String, dynamic>{
      ...root,
      'record': rec,
      'booking': booking,
      'payload': payload,
      'quote': quote,
      'booking_details': bookingDetails,
      'data': data,
    };
    final activeScope = _activeLocalScope();
    final authoritativeInternalBookingId = _firstNonEmpty([
      response['booking_id'],
      response['bookingId'],
      rec['booking_id'],
      rec['bookingId'],
      booking['booking_id'],
      booking['bookingId'],
    ]);
    final authoritativePublicBookingId = _firstNonEmpty([
      response['public_booking_reference'],
      response['publicBookingReference'],
      response['booking_reference'],
      response['bookingReference'],
      response['public_reference'],
      response['publicReference'],
      response['public_booking_id'],
      response['publicBookingId'],
      rec['public_booking_reference'],
      rec['publicBookingReference'],
      rec['booking_reference'],
      rec['bookingReference'],
      rec['public_reference'],
      rec['publicReference'],
      booking['public_booking_reference'],
      booking['publicBookingReference'],
      booking['booking_reference'],
      booking['bookingReference'],
      booking['public_reference'],
      booking['publicReference'],
      booking['public_booking_id'],
      booking['publicBookingId'],
    ]);
    final resolvedBookingId = _firstNonEmpty([
      authoritativeInternalBookingId,
      bookingId,
      fallback?.bookingId,
    ]);
    if (authoritativeInternalBookingId.isNotEmpty &&
        authoritativePublicBookingId.isNotEmpty) {
      debugPrint(
        '[CUSTOMER_BOOKINGS][ID_RESOLVE] input=$bookingId internal=$authoritativeInternalBookingId public=$authoritativePublicBookingId final=$resolvedBookingId',
      );
    }
    return StoredCustomerBooking(
      bookingId: resolvedBookingId,
      tenantId: _firstNonEmpty([
        response['tenant_id'],
        response['tenantId'],
        rec['tenant_id'],
        rec['tenantId'],
        booking['tenant_id'],
        booking['tenantId'],
        data['tenant_id'],
        data['tenantId'],
        fallback?.tenantId,
        activeScope?.tenantId,
      ]),
      companyId: _firstNonEmpty([
        response['company_id'],
        response['companyId'],
        rec['company_id'],
        rec['companyId'],
        booking['company_id'],
        booking['companyId'],
        data['company_id'],
        data['companyId'],
        fallback?.companyId,
        activeScope?.companyId,
      ]),
      publicBookingId: _firstNonEmpty([
        response['public_booking_reference'],
        response['publicBookingReference'],
        response['booking_reference'],
        response['bookingReference'],
        response['public_reference'],
        response['publicReference'],
        rec['public_booking_reference'],
        rec['publicBookingReference'],
        rec['booking_reference'],
        rec['bookingReference'],
        rec['public_reference'],
        rec['publicReference'],
        booking['public_booking_reference'],
        booking['publicBookingReference'],
        booking['booking_reference'],
        booking['bookingReference'],
        booking['public_reference'],
        booking['publicReference'],
        response['booking_id'],
        response['public_booking_id'],
        resolvedBookingId,
      ]),
      planningReference: _firstNonEmpty([
        response['planning_reference'],
        response['planningReference'],
        rec['planning_reference'],
        rec['planningReference'],
        booking['planning_reference'],
        booking['planningReference'],
        fallback?.planningReference,
      ]),
      bookingReference: _firstNonEmpty([
        response['booking_reference'],
        response['bookingReference'],
        rec['booking_reference'],
        rec['bookingReference'],
        booking['booking_reference'],
        booking['bookingReference'],
        fallback?.bookingReference,
      ]),
      publicReference: _firstNonEmpty([
        response['public_reference'],
        response['publicReference'],
        rec['public_reference'],
        rec['publicReference'],
        booking['public_reference'],
        booking['publicReference'],
        fallback?.publicReference,
      ]),
      receiptReference: _firstNonEmpty([
        response['receipt_reference'],
        response['receiptReference'],
        rec['receipt_reference'],
        rec['receiptReference'],
        booking['receipt_reference'],
        booking['receiptReference'],
        fallback?.receiptReference,
      ]),
      paymentBookingId: _firstNonEmpty([
        rec['payment_booking_id'],
        rec['paymentBookingId'],
        booking['payment_booking_id'],
        booking['paymentBookingId'],
        fallback?.paymentBookingId,
      ]),
      customerName: _firstNonEmpty([
        booking['customer_name'],
        booking['name'],
        fallback?.customerName,
      ]),
      customerPhone: _firstNonEmpty([
        booking['customer_phone'],
        booking['phone'],
        fallback?.customerPhone,
      ]),
      customerEmail: _firstNonEmpty([
        booking['customer_email'],
        booking['email'],
        fallback?.customerEmail,
      ]).toLowerCase(),
      from: _preferNonEmpty(
        _firstPathValue(merged, const <String>[
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
          'record.booking.pickup_address',
          'record.booking_details.from',
          'record.booking_details.pickup_address',
          'data.record.booking.from',
          'data.record.booking_details.from',
          'payload.from',
          'payload.pickup_address',
          'quote.inputs.from',
        ]),
        fallback?.from ?? '',
      ),
      to: _preferNonEmpty(
        _firstPathValue(merged, const <String>[
          'to',
          'destination',
          'destination_address',
          'destinationAddress',
          'dropoff',
          'dropoff_address',
          'booking.to',
          'booking.destination',
          'booking.destination_address',
          'record.booking.to',
          'record.booking.destination_address',
          'record.booking_details.to',
          'record.booking_details.destination_address',
          'data.record.booking.to',
          'data.record.booking_details.to',
          'payload.to',
          'payload.destination_address',
          'quote.inputs.to',
        ]),
        fallback?.to ?? '',
      ),
      pickupIso: _firstNonEmpty([
        _firstPathValue(merged, const <String>[
          'pickup_iso',
          'pickupStartIso',
          'record.pickup_iso',
          'record.booking.pickup_iso',
          'record.booking.pickupStartIso',
          'record.booking_details.pickup_iso',
          'payload.pickup_iso',
        ]),
        booking['pickupStartIso'],
        booking['pickup_iso'],
        booking['pickupAt'],
        fallback?.pickupIso,
      ]),
      price: _firstPathDouble(merged, const <String>[
        'price',
        'total',
        'amount',
        'price_incl_vat',
        'priceInclVat',
        'booking.price',
        'booking.total',
        'booking.amount',
        'record.price',
        'record.total',
        'record.booking.price',
        'record.booking.total',
        'record.booking_details.price',
        'record.booking_details.total',
        'quote.price_incl_vat',
        'quote.priceInclVat',
        'payload.price',
        'payload.total',
        'payload.amount',
        'payload.quote.price_incl_vat',
      ], fallback: fallback?.price),
      currency: _firstNonEmpty([
        _firstPathValue(merged, const <String>[
          'currency',
          'record.currency',
          'booking.currency',
          'record.booking.currency',
          'record.booking_details.currency',
          'quote.currency',
          'payload.currency',
        ]),
        booking['currency'],
        rec['currency'],
        fallback?.currency,
        'EUR',
      ]),
      service: _preferNonEmpty(
        _firstPathValue(merged, const <String>[
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
        fallback?.service ?? '',
      ),
      tier: _preferNonEmpty(
        _firstPathValue(merged, const <String>[
          'tier',
          'booking.tier',
          'record.booking.tier',
          'record.booking_details.tier',
          'payload.tier',
          'quote.inputs.tier',
        ]),
        fallback?.tier ?? '',
      ),
      pax: _preferNonEmpty(
        _firstPathValue(merged, const <String>[
          'pax',
          'passengers',
          'booking.pax',
          'booking.passengers',
          'record.booking.pax',
          'record.booking_details.pax',
          'payload.pax',
          'quote.inputs.pax',
        ]),
        fallback?.pax ?? '',
      ),
      bags: _preferNonEmpty(
        _firstPathValue(merged, const <String>[
          'bags',
          'booking.bags',
          'record.booking.bags',
          'record.booking_details.bags',
          'payload.bags',
          'quote.inputs.bags',
        ]),
        fallback?.bags ?? '',
      ),
      paymentStatus: _firstNonEmpty([
        rec['payment_status'],
        rec['paymentStatus'],
        booking['payment_status'],
        booking['paymentStatus'],
        fallback?.paymentStatus,
      ]).toLowerCase(),
      status: _firstNonEmpty([
        response['status'],
        rec['status'],
        rec['stage'],
        booking['status'],
        fallback?.status,
      ]).toUpperCase(),
      createdAt: _firstNonEmpty([
        rec['createdAt'],
        rec['created_at'],
        booking['created_at'],
        fallback?.createdAt,
        DateTime.now().toIso8601String(),
      ]),
      businessDetected: _bool(
        _firstNonEmpty([
          booking['business_detected'],
          booking['business_customer'],
          booking['is_business'],
          fallback?.businessDetected,
        ]),
      ),
      invoiceRequested: _bool(
        _firstNonEmpty([
          booking['invoice_requested'],
          fallback?.invoiceRequested,
        ]),
      ),
      companyName: _firstNonEmpty([
        booking['company_name'],
        fallback?.companyName,
      ]),
      vatNumber: _firstNonEmpty([booking['vat_number'], fallback?.vatNumber]),
      invoiceEmail: _firstNonEmpty([
        booking['invoice_email'],
        fallback?.invoiceEmail,
      ]),
      invoiceAddress: _firstNonEmpty([
        booking['invoice_address'],
        booking['billing_address'],
        fallback?.invoiceAddress,
      ]),
      quote: quote.isNotEmpty
          ? quote
          : (fallback?.quote ?? const <String, dynamic>{}),
      updatedAt: DateTime.now().toIso8601String(),
    );
  }

  factory StoredCustomerBooking.fromJson(Map<String, dynamic> json) {
    return StoredCustomerBooking(
      bookingId: _string(json['booking_id']),
      tenantId: _firstNonEmpty([json['tenant_id'], json['tenantId']]),
      companyId: _firstNonEmpty([json['company_id'], json['companyId']]),
      publicBookingId: _firstNonEmpty([
        json['public_booking_id'],
        json['public_booking_reference'],
        json['publicBookingReference'],
        json['booking_reference'],
        json['bookingReference'],
        json['public_reference'],
        json['publicReference'],
      ]),
      planningReference: _string(json['planning_reference']),
      bookingReference: _string(json['booking_reference']),
      publicReference: _string(json['public_reference']),
      receiptReference: _string(json['receipt_reference']),
      paymentBookingId: _string(json['payment_booking_id']),
      customerName: _string(json['customer_name']),
      customerPhone: _string(json['customer_phone']),
      customerEmail: _string(json['customer_email']).toLowerCase(),
      from: _string(json['from']),
      to: _string(json['to']),
      pickupIso: _string(json['pickup_iso']),
      price: _double(json['price']),
      currency: _firstNonEmpty([json['currency'], 'EUR']),
      service: _string(json['service']),
      tier: _string(json['tier']),
      pax: _string(json['pax']),
      bags: _string(json['bags']),
      paymentStatus: _string(json['payment_status']).toLowerCase(),
      status: _string(json['status']).toUpperCase(),
      createdAt: _string(json['created_at']),
      businessDetected: _bool(json['business_detected']),
      invoiceRequested: _bool(json['invoice_requested']),
      companyName: _string(json['company_name']),
      vatNumber: _string(json['vat_number']),
      invoiceEmail: _string(json['invoice_email']),
      invoiceAddress: _string(json['invoice_address']),
      quote: _map(json['quote']),
      updatedAt: _string(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'booking_id': bookingId,
      'tenant_id': tenantId,
      'tenantId': tenantId,
      'company_id': companyId,
      'companyId': companyId,
      'public_booking_id': publicBookingId,
      'public_booking_reference': publicBookingId,
      'publicBookingReference': publicBookingId,
      'planning_reference': planningReference,
      'planningReference': planningReference,
      'booking_reference': bookingReference,
      'bookingReference': bookingReference,
      'public_reference': publicReference,
      'publicReference': publicReference,
      'receipt_reference': receiptReference,
      'receiptReference': receiptReference,
      'payment_booking_id': paymentBookingId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_email': customerEmail,
      'from': from,
      'to': to,
      'pickup_iso': pickupIso,
      'price': price,
      'currency': currency,
      'service': service,
      'tier': tier,
      'pax': pax,
      'bags': bags,
      'payment_status': paymentStatus,
      'status': status,
      'created_at': createdAt,
      'business_detected': businessDetected,
      'invoice_requested': invoiceRequested,
      'company_name': companyName,
      'vat_number': vatNumber,
      'invoice_email': invoiceEmail,
      'invoice_address': invoiceAddress,
      'quote': quote,
      'updated_at': updatedAt,
    };
  }
}

class CustomerBookingsStore {
  CustomerBookingsStore._();

  static final CustomerBookingsStore instance = CustomerBookingsStore._();

  static const String _fileName = 'customer_bookings_v1.json';
  static const String _hiddenAliasesFileName =
      'customer_bookings_hidden_aliases_v1.json';
  static const String _stateDirName = 'customer_state';

  List<StoredCustomerBooking>? _cache;
  String _cacheScopeKey = '';
  Future<void> _writeQueue = Future<void>.value();

  Future<Directory> _stateRootDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}$_stateDirName',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _legacyFile() async {
    final dir = await _stateRootDir();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<File> _scopedFile({
    required String tenantId,
    required String companyId,
  }) async {
    final root = await _stateRootDir();
    final tenantSegment = _localScopeSegment(tenantId);
    final companySegment = _localScopeSegment(companyId);
    final scopedDir = Directory(
      '${root.path}${Platform.pathSeparator}tenant_$tenantSegment${Platform.pathSeparator}company_$companySegment',
    );
    if (!await scopedDir.exists()) {
      await scopedDir.create(recursive: true);
    }
    final file = File('${scopedDir.path}${Platform.pathSeparator}$_fileName');
    debugPrint(
      '[LOCAL_SCOPE][CUSTOMER_BOOKINGS_PATH] tenant=${_maskScopeId(tenantId)} company=${_maskScopeId(companyId)} path=${file.path}',
    );
    return file;
  }

  Future<String> _activeValidCustomerSessionId() async {
    final cached = CustomerSessionStore.instance.peekCachedSession();
    if (cached != null && CustomerSessionStore.instance.isValid(cached)) {
      final cachedId = cached.customerId.trim();
      if (cachedId.isNotEmpty) return cachedId;
    }
    final loaded = await CustomerSessionStore.instance.loadValidSession();
    return (loaded?.customerId ?? '').trim();
  }

  Future<File> _customerSessionScopedFile({required String customerId}) async {
    final root = await _stateRootDir();
    final scopedDir = Directory(
      '${root.path}${Platform.pathSeparator}customer_session${Platform.pathSeparator}customer_${_localScopeSegment(customerId)}',
    );
    if (!await scopedDir.exists()) {
      await scopedDir.create(recursive: true);
    }
    final file = File('${scopedDir.path}${Platform.pathSeparator}$_fileName');
    debugPrint(
      '[LOCAL_SCOPE][CUSTOMER_BOOKINGS_PATH] scope=customer_session path=${file.path}',
    );
    return file;
  }

  Future<File> _scopedHiddenAliasesFile({
    required String tenantId,
    required String companyId,
  }) async {
    final scopedFile = await _scopedFile(
      tenantId: tenantId,
      companyId: companyId,
    );
    return File(
      '${scopedFile.parent.path}${Platform.pathSeparator}$_hiddenAliasesFileName',
    );
  }

  Future<File> _customerSessionHiddenAliasesFile({
    required String customerId,
  }) async {
    final scopedFile = await _customerSessionScopedFile(customerId: customerId);
    return File(
      '${scopedFile.parent.path}${Platform.pathSeparator}$_hiddenAliasesFileName',
    );
  }

  Future<File?> _file() async {
    final scope = _activeLocalScope();
    if (scope == null) return null;
    return _scopedFile(tenantId: scope.tenantId, companyId: scope.companyId);
  }

  bool _belongsToScope(
    StoredCustomerBooking item, {
    required String tenantId,
    required String companyId,
    required bool allowLegacyWithoutScope,
  }) {
    final itemTenant = item.tenantId.trim();
    final itemCompany = item.companyId.trim();
    final activeTenant = tenantId.trim();
    final activeCompany = companyId.trim();
    if (itemTenant.isEmpty && itemCompany.isEmpty) {
      return allowLegacyWithoutScope;
    }
    if (itemTenant.isNotEmpty && itemTenant != activeTenant) return false;
    if (itemCompany.isNotEmpty && itemCompany != activeCompany) return false;
    return true;
  }

  List<StoredCustomerBooking> _filterForScope(
    List<StoredCustomerBooking> items, {
    required String tenantId,
    required String companyId,
    required bool allowLegacyWithoutScope,
  }) {
    return items
        .where(
          (item) => _belongsToScope(
            item,
            tenantId: tenantId,
            companyId: companyId,
            allowLegacyWithoutScope: allowLegacyWithoutScope,
          ),
        )
        .toList(growable: false);
  }

  bool _allowLegacyWithoutScopeForScope({
    required String tenantId,
    required String companyId,
  }) => false;

  StoredCustomerBooking _coerceScope(
    StoredCustomerBooking item, {
    required String tenantId,
    required String companyId,
  }) {
    return item.copyWith(
      tenantId: item.tenantId.trim().isNotEmpty ? item.tenantId : tenantId,
      companyId: item.companyId.trim().isNotEmpty ? item.companyId : companyId,
    );
  }

  Future<List<StoredCustomerBooking>> _readFileItems(File file) async {
    if (!await file.exists()) return const <StoredCustomerBooking>[];
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return const <StoredCustomerBooking>[];
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (err) {
      await _backupCorruptFile(file, reason: 'decode_error');
      debugPrint('[CUSTOMER_BOOKINGS][LOAD_ERROR] decode_error=$err');
      return const <StoredCustomerBooking>[];
    }
    if (decoded is! List) {
      await _backupCorruptFile(file, reason: 'non_list_root');
      debugPrint(
        '[CUSTOMER_BOOKINGS][LOAD_ERROR] non_list_root type=${decoded.runtimeType}',
      );
      return const <StoredCustomerBooking>[];
    }
    return decoded
        .whereType<Map>()
        .map(
          (m) => StoredCustomerBooking.fromJson(Map<String, dynamic>.from(m)),
        )
        .toList(growable: false);
  }

  Future<void> _removeVisibleLegacyItemsForScope({
    required String tenantId,
    required String companyId,
  }) async {
    final legacyFile = await _legacyFile();
    if (!await legacyFile.exists()) return;
    final legacyItems = await _readFileItems(legacyFile);
    if (legacyItems.isEmpty) return;
    final retained = legacyItems
        .where((item) {
          return !_belongsToScope(
            item,
            tenantId: tenantId,
            companyId: companyId,
            allowLegacyWithoutScope: true,
          );
        })
        .toList(growable: false);
    if (retained.length == legacyItems.length) return;
    await _atomicWriteJsonArray(
      file: legacyFile,
      payload: retained.map((e) => e.toJson()).toList(growable: false),
    );
  }

  Future<List<StoredCustomerBooking>> loadAll() async {
    final scope = _activeLocalScope();
    if (scope != null) {
      return _loadAllForScope(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
    }
    final customerId = await _activeValidCustomerSessionId();
    if (customerId.isNotEmpty) {
      debugPrint('[CUSTOMER_BOOKINGS][SCOPE_FALLBACK] source=customer_session');
      return _loadAllForCustomerSessionScope(customerId);
    }
    _cache = <StoredCustomerBooking>[];
    _cacheScopeKey = '';
    debugPrint(
      '[CUSTOMER_BOOKINGS][SKIP_SCOPE] reason=missing_tenant_company_scope',
    );
    return <StoredCustomerBooking>[];
  }

  Future<List<StoredCustomerBooking>> _loadAllForCustomerSessionScope(
    String customerId,
  ) async {
    final normalizedCustomerId = customerId.trim();
    if (normalizedCustomerId.isEmpty) return <StoredCustomerBooking>[];
    final scopeKey = 'customer_session::$normalizedCustomerId';
    if (_cache != null) {
      if (_cacheScopeKey == scopeKey) {
        return List<StoredCustomerBooking>.from(_cache!);
      }
      _cache = <StoredCustomerBooking>[];
      _cacheScopeKey = '';
    }
    try {
      _cacheScopeKey = scopeKey;
      final file = await _customerSessionScopedFile(
        customerId: normalizedCustomerId,
      );
      final items = await _readFileItems(file);
      _cache = List<StoredCustomerBooking>.from(items);
      return List<StoredCustomerBooking>.from(items);
    } catch (err) {
      debugPrint('[CUSTOMER_BOOKINGS][LOAD_ERROR] $err');
      _cache = <StoredCustomerBooking>[];
      return <StoredCustomerBooking>[];
    }
  }

  Future<List<StoredCustomerBooking>> _loadAllForScope({
    required String tenantId,
    required String companyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedCompanyId = companyId.trim();
    final scopeKey = '$normalizedTenantId::$normalizedCompanyId';
    if (_cache != null) {
      if (_cacheScopeKey == scopeKey) {
        return List<StoredCustomerBooking>.from(_cache!);
      }
      _cache = null;
    }
    try {
      final allowLegacyWithoutScope = _allowLegacyWithoutScopeForScope(
        tenantId: normalizedTenantId,
        companyId: normalizedCompanyId,
      );
      _cacheScopeKey = scopeKey;
      final scopedFile = await _scopedFile(
        tenantId: normalizedTenantId,
        companyId: normalizedCompanyId,
      );
      final scopedItems = await _readFileItems(scopedFile);
      if (scopedItems.isNotEmpty) {
        final filtered =
            _filterForScope(
                  scopedItems,
                  tenantId: normalizedTenantId,
                  companyId: normalizedCompanyId,
                  allowLegacyWithoutScope: allowLegacyWithoutScope,
                )
                .map(
                  (item) => _coerceScope(
                    item,
                    tenantId: normalizedTenantId,
                    companyId: normalizedCompanyId,
                  ),
                )
                .toList(growable: false);
        _cache = filtered;
        return List<StoredCustomerBooking>.from(filtered);
      }
      _cache = <StoredCustomerBooking>[];
      return <StoredCustomerBooking>[];
    } catch (err) {
      debugPrint('[CUSTOMER_BOOKINGS][LOAD_ERROR] $err');
      _cache = <StoredCustomerBooking>[];
      return <StoredCustomerBooking>[];
    }
  }

  Future<void> _saveAll(List<StoredCustomerBooking> items) async {
    final scope = _activeLocalScope();
    if (scope != null) {
      await _saveAllForScope(
        items,
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      return;
    }
    final key = _cacheScopeKey;
    if (key.startsWith('customer_session::')) {
      final customerId = key.substring('customer_session::'.length).trim();
      if (customerId.isNotEmpty) {
        await _saveAllForCustomerSessionScope(items, customerId: customerId);
        return;
      }
    }
    final customerId = await _activeValidCustomerSessionId();
    if (customerId.isNotEmpty) {
      await _saveAllForCustomerSessionScope(items, customerId: customerId);
      return;
    }
    debugPrint(
      '[CUSTOMER_BOOKINGS][SKIP_SCOPE] reason=missing_tenant_company_scope',
    );
  }

  Future<void> _saveAllForScope(
    List<StoredCustomerBooking> items, {
    required String tenantId,
    required String companyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedCompanyId = companyId.trim();
    final scopeKey = '$normalizedTenantId::$normalizedCompanyId';
    final normalized = items
        .map(
          (item) => _coerceScope(
            item,
            tenantId: normalizedTenantId,
            companyId: normalizedCompanyId,
          ),
        )
        .toList(growable: false);
    _cacheScopeKey = scopeKey;
    _cache = List<StoredCustomerBooking>.from(normalized);
    await _enqueueWrite(() async {
      try {
        final file = await _scopedFile(
          tenantId: normalizedTenantId,
          companyId: normalizedCompanyId,
        );
        final payload = normalized
            .map((e) => e.toJson())
            .toList(growable: false);
        await _atomicWriteJsonArray(file: file, payload: payload);
      } catch (err) {
        debugPrint('[CUSTOMER_BOOKINGS][SAVE_ERROR] $err');
      }
    });
  }

  Future<void> _saveAllForCustomerSessionScope(
    List<StoredCustomerBooking> items, {
    required String customerId,
  }) async {
    final normalizedCustomerId = customerId.trim();
    if (normalizedCustomerId.isEmpty) return;
    final scopeKey = 'customer_session::$normalizedCustomerId';
    _cacheScopeKey = scopeKey;
    _cache = List<StoredCustomerBooking>.from(items);
    await _enqueueWrite(() async {
      try {
        final file = await _customerSessionScopedFile(
          customerId: normalizedCustomerId,
        );
        final payload = items.map((e) => e.toJson()).toList(growable: false);
        await _atomicWriteJsonArray(file: file, payload: payload);
      } catch (err) {
        debugPrint('[CUSTOMER_BOOKINGS][SAVE_ERROR] $err');
      }
    });
  }

  Future<void> _enqueueWrite(Future<void> Function() writeOp) {
    _writeQueue = _writeQueue.then((_) => writeOp(), onError: (_) => writeOp());
    return _writeQueue;
  }

  String _safeTimestampToken() {
    final iso = DateTime.now().toUtc().toIso8601String();
    return iso.replaceAll(RegExp(r'[^0-9A-Za-z]'), '_');
  }

  Future<void> _backupCorruptFile(File file, {required String reason}) async {
    try {
      if (!await file.exists()) return;
      final dirPath = file.parent.path;
      final backupName =
          'customer_bookings_v1.corrupt.${_safeTimestampToken()}.json';
      final backup = File('$dirPath${Platform.pathSeparator}$backupName');
      await file.copy(backup.path);
      debugPrint(
        '[CUSTOMER_BOOKINGS][RECOVERY] reason=$reason backup=${backup.path}',
      );
    } catch (err) {
      debugPrint(
        '[CUSTOMER_BOOKINGS][RECOVERY_ERROR] reason=$reason error=$err',
      );
    }
  }

  Future<void> _atomicWriteJsonArray({
    required File file,
    required List<Map<String, dynamic>> payload,
  }) async {
    final encoded = jsonEncode(payload);
    final dirPath = file.parent.path;
    final tempPath = '${file.path}.tmp';
    final swapPath = '$dirPath${Platform.pathSeparator}$_fileName.swap';
    final tempFile = File(tempPath);
    final swapFile = File(swapPath);

    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    await tempFile.writeAsString(encoded, flush: true);

    try {
      if (await swapFile.exists()) {
        await swapFile.delete();
      }
      if (await file.exists()) {
        await file.rename(swapFile.path);
      }
      await tempFile.rename(file.path);
      if (await swapFile.exists()) {
        await swapFile.delete();
      }
    } catch (_) {
      if (await tempFile.exists()) {
        await file.writeAsString(encoded, flush: true);
        await tempFile.delete();
      }
      if (!await file.exists() && await swapFile.exists()) {
        await swapFile.rename(file.path);
      } else if (await swapFile.exists()) {
        await swapFile.delete();
      }
    }
  }

  Future<Set<String>> _readHiddenAliasesFromFile(File file) async {
    if (!await file.exists()) return <String>{};
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      final aliases = <String>{};
      for (final entry in decoded) {
        if (entry is String) {
          final normalized = _normalizedReference(entry);
          if (normalized.isNotEmpty) aliases.add(normalized);
          continue;
        }
        if (entry is Map) {
          final alias = _normalizedReference((entry['alias'] ?? '').toString());
          if (alias.isNotEmpty) aliases.add(alias);
        }
      }
      return aliases;
    } catch (err) {
      debugPrint('[CUSTOMER_BOOKINGS][HIDDEN_LOAD_ERROR] $err');
      return <String>{};
    }
  }

  Future<void> _writeHiddenAliasesToFile(File file, Set<String> aliases) async {
    final normalized = aliases.toList(growable: false)..sort();
    final payload = normalized
        .map((alias) => <String, dynamic>{'alias': alias})
        .toList(growable: false);
    await _enqueueWrite(() async {
      try {
        await _atomicWriteJsonArray(file: file, payload: payload);
      } catch (err) {
        debugPrint('[CUSTOMER_BOOKINGS][HIDDEN_SAVE_ERROR] $err');
      }
    });
  }

  Future<List<File>> _hiddenAliasesTargets({
    String? tenantIdHint,
    String? companyIdHint,
    String? customerSessionIdHint,
    required bool includeActiveScope,
    required bool includeCacheScope,
    required bool includeValidSessionFallback,
  }) async {
    final filesByPath = <String, File>{};
    Future<void> addScoped(String tenantId, String companyId) async {
      final tenant = tenantId.trim();
      final company = companyId.trim();
      if (tenant.isEmpty || company.isEmpty) return;
      final file = await _scopedHiddenAliasesFile(
        tenantId: tenant,
        companyId: company,
      );
      filesByPath[file.path] = file;
    }

    Future<void> addSession(String customerId) async {
      final normalized = customerId.trim();
      if (normalized.isEmpty) return;
      final file = await _customerSessionHiddenAliasesFile(
        customerId: normalized,
      );
      filesByPath[file.path] = file;
    }

    await addScoped(tenantIdHint ?? '', companyIdHint ?? '');
    await addSession(customerSessionIdHint ?? '');

    if (includeActiveScope) {
      final activeScope = _activeLocalScope();
      if (activeScope != null) {
        await addScoped(activeScope.tenantId, activeScope.companyId);
      }
    }

    if (includeCacheScope) {
      final key = _cacheScopeKey.trim();
      if (key.startsWith('customer_session::')) {
        final customerId = key.substring('customer_session::'.length).trim();
        await addSession(customerId);
      } else if (key.contains('::')) {
        final parts = key.split('::');
        if (parts.length == 2) {
          await addScoped(parts[0], parts[1]);
        }
      }
    }

    if (includeValidSessionFallback) {
      final customerId = await _activeValidCustomerSessionId();
      await addSession(customerId);
    }

    return filesByPath.values.toList(growable: false);
  }

  Future<bool> markHiddenByAnyReferenceAliases(Set<String> aliases) async {
    final normalizedAliases = _normalizedReferenceSet(aliases);
    if (normalizedAliases.isEmpty) return false;
    final targets = await _hiddenAliasesTargets(
      includeActiveScope: true,
      includeCacheScope: true,
      includeValidSessionFallback: true,
    );
    if (targets.isEmpty) {
      debugPrint(
        '[CUSTOMER_BOOKINGS][HIDDEN_MARK][SKIP] reason=missing_tenant_company_scope',
      );
      return false;
    }
    var wroteAny = false;
    for (final file in targets) {
      final current = await _readHiddenAliasesFromFile(file);
      final merged = <String>{...current, ...normalizedAliases};
      if (merged.length == current.length) continue;
      await _writeHiddenAliasesToFile(file, merged);
      wroteAny = true;
    }
    return wroteAny || targets.isNotEmpty;
  }

  Future<bool> isAnyReferenceAliasHidden(
    Set<String> aliases, {
    String? tenantIdHint,
    String? companyIdHint,
    String? customerSessionIdHint,
  }) async {
    final normalizedAliases = _normalizedReferenceSet(aliases);
    if (normalizedAliases.isEmpty) return false;
    final targets = await _hiddenAliasesTargets(
      tenantIdHint: tenantIdHint,
      companyIdHint: companyIdHint,
      customerSessionIdHint: customerSessionIdHint,
      includeActiveScope: true,
      includeCacheScope: true,
      includeValidSessionFallback: true,
    );
    for (final file in targets) {
      final current = await _readHiddenAliasesFromFile(file);
      if (current.isEmpty) continue;
      if (current.any(normalizedAliases.contains)) {
        return true;
      }
    }
    return false;
  }

  int _findIndex(
    List<StoredCustomerBooking> items,
    StoredCustomerBooking incoming,
  ) {
    final bookingId = incoming.bookingId.trim();
    final publicId = incoming.publicBookingId.trim();
    final paymentBookingId = incoming.paymentBookingId.trim();
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (bookingId.isNotEmpty && item.bookingId.trim() == bookingId) return i;
      if (publicId.isNotEmpty && item.publicBookingId.trim() == publicId)
        return i;
      if (paymentBookingId.isNotEmpty &&
          item.paymentBookingId.trim().isNotEmpty &&
          item.paymentBookingId.trim() == paymentBookingId) {
        return i;
      }
    }
    return -1;
  }

  Future<void> upsert(StoredCustomerBooking booking) async {
    final now = DateTime.now().toIso8601String();
    final bookingTenantId = booking.tenantId.trim();
    final bookingCompanyId = booking.companyId.trim();
    final hasBookingBusinessScope =
        _isSafeBusinessScopeValue(bookingTenantId) &&
        _isSafeBusinessScopeValue(bookingCompanyId);
    final activeScope = _activeLocalScope();

    bool useCustomerSessionStorage = false;
    String targetTenantId = '';
    String targetCompanyId = '';
    String customerSessionId = '';

    if (hasBookingBusinessScope) {
      targetTenantId = bookingTenantId;
      targetCompanyId = bookingCompanyId;
    } else if (activeScope != null) {
      targetTenantId = activeScope.tenantId;
      targetCompanyId = activeScope.companyId;
    } else {
      customerSessionId = await _activeValidCustomerSessionId();
      if (customerSessionId.isEmpty) {
        debugPrint(
          '[CUSTOMER_BOOKINGS][SKIP_SCOPE] reason=missing_tenant_company_scope op=upsert',
        );
        return;
      }
      useCustomerSessionStorage = true;
    }

    final list = List<StoredCustomerBooking>.from(
      useCustomerSessionStorage
          ? await _loadAllForCustomerSessionScope(customerSessionId)
          : await _loadAllForScope(
              tenantId: targetTenantId,
              companyId: targetCompanyId,
            ),
    );
    final index = _findIndex(list, booking);
    final incoming = useCustomerSessionStorage
        ? booking.copyWith(
            updatedAt: now,
            createdAt: booking.createdAt.trim().isEmpty
                ? now
                : booking.createdAt,
          )
        : booking.copyWith(
            tenantId: booking.tenantId.trim().isNotEmpty
                ? booking.tenantId
                : targetTenantId,
            companyId: booking.companyId.trim().isNotEmpty
                ? booking.companyId
                : targetCompanyId,
            updatedAt: now,
            createdAt: booking.createdAt.trim().isEmpty
                ? now
                : booking.createdAt,
          );
    if (index >= 0) {
      final existing = list[index];
      list[index] = existing.copyWith(
        bookingId: incoming.bookingId.isNotEmpty
            ? incoming.bookingId
            : existing.bookingId,
        tenantId: incoming.tenantId.isNotEmpty
            ? incoming.tenantId
            : existing.tenantId,
        companyId: incoming.companyId.isNotEmpty
            ? incoming.companyId
            : existing.companyId,
        publicBookingId: incoming.publicBookingId.isNotEmpty
            ? incoming.publicBookingId
            : existing.publicBookingId,
        planningReference: incoming.planningReference.isNotEmpty
            ? incoming.planningReference
            : existing.planningReference,
        bookingReference: incoming.bookingReference.isNotEmpty
            ? incoming.bookingReference
            : existing.bookingReference,
        publicReference: incoming.publicReference.isNotEmpty
            ? incoming.publicReference
            : existing.publicReference,
        receiptReference: incoming.receiptReference.isNotEmpty
            ? incoming.receiptReference
            : existing.receiptReference,
        paymentBookingId: incoming.paymentBookingId.isNotEmpty
            ? incoming.paymentBookingId
            : existing.paymentBookingId,
        customerName: incoming.customerName.isNotEmpty
            ? incoming.customerName
            : existing.customerName,
        customerPhone: incoming.customerPhone.isNotEmpty
            ? incoming.customerPhone
            : existing.customerPhone,
        customerEmail: incoming.customerEmail.isNotEmpty
            ? incoming.customerEmail
            : existing.customerEmail,
        from: incoming.from.isNotEmpty ? incoming.from : existing.from,
        to: incoming.to.isNotEmpty ? incoming.to : existing.to,
        pickupIso: incoming.pickupIso.isNotEmpty
            ? incoming.pickupIso
            : existing.pickupIso,
        price: incoming.price ?? existing.price,
        currency: incoming.currency.isNotEmpty
            ? incoming.currency
            : existing.currency,
        service: incoming.service.isNotEmpty
            ? incoming.service
            : existing.service,
        tier: incoming.tier.isNotEmpty ? incoming.tier : existing.tier,
        pax: incoming.pax.isNotEmpty ? incoming.pax : existing.pax,
        bags: incoming.bags.isNotEmpty ? incoming.bags : existing.bags,
        paymentStatus: incoming.paymentStatus.isNotEmpty
            ? incoming.paymentStatus
            : existing.paymentStatus,
        status: incoming.status.isNotEmpty ? incoming.status : existing.status,
        createdAt: existing.createdAt.isNotEmpty
            ? existing.createdAt
            : incoming.createdAt,
        businessDetected:
            incoming.businessDetected || existing.businessDetected,
        invoiceRequested:
            incoming.invoiceRequested || existing.invoiceRequested,
        companyName: incoming.companyName.isNotEmpty
            ? incoming.companyName
            : existing.companyName,
        vatNumber: incoming.vatNumber.isNotEmpty
            ? incoming.vatNumber
            : existing.vatNumber,
        invoiceEmail: incoming.invoiceEmail.isNotEmpty
            ? incoming.invoiceEmail
            : existing.invoiceEmail,
        invoiceAddress: incoming.invoiceAddress.isNotEmpty
            ? incoming.invoiceAddress
            : existing.invoiceAddress,
        quote: incoming.quote.isNotEmpty ? incoming.quote : existing.quote,
        updatedAt: now,
      );
    } else {
      list.add(incoming);
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (useCustomerSessionStorage) {
      await _saveAllForCustomerSessionScope(
        list,
        customerId: customerSessionId,
      );
      return;
    }
    await _saveAllForScope(
      list,
      tenantId: targetTenantId,
      companyId: targetCompanyId,
    );
  }

  Future<void> markPaid({
    required String bookingId,
    String? paymentBookingId,
    String? bookingStatus,
  }) async {
    final list = await loadAll();
    final bId = bookingId.trim();
    final pId = (paymentBookingId ?? '').trim();
    bool changed = false;
    final now = DateTime.now().toIso8601String();
    for (int i = 0; i < list.length; i++) {
      final item = list[i];
      if ((bId.isNotEmpty && item.bookingId.trim() == bId) ||
          (pId.isNotEmpty && item.paymentBookingId.trim() == pId)) {
        list[i] = item.copyWith(
          paymentStatus: 'paid',
          status: (bookingStatus ?? '').trim().isNotEmpty
              ? bookingStatus!.trim()
              : (item.status.isNotEmpty ? item.status : 'CONFIRMED'),
          updatedAt: now,
        );
        changed = true;
      }
    }
    if (changed) {
      await _saveAll(list);
    }
  }

  Future<void> remove(String bookingId) async {
    final id = bookingId.trim();
    if (id.isEmpty) return;
    await removeByAnyReferenceAliases(<String>{id});
  }

  Future<void> clear() async {
    final scope = _activeLocalScope();
    if (scope == null) {
      _cache = <StoredCustomerBooking>[];
      _cacheScopeKey = '';
      debugPrint(
        '[CUSTOMER_BOOKINGS][SKIP_SCOPE] reason=missing_tenant_company_scope op=clear',
      );
      return;
    }
    _cacheScopeKey = '${scope.tenantId.trim()}::${scope.companyId.trim()}';
    await _saveAll(const <StoredCustomerBooking>[]);
  }

  String _normalizedReference(String value) {
    return value.trim().toLowerCase();
  }

  Set<String> _normalizedReferenceSet(Iterable<String> values) {
    final out = <String>{};
    for (final value in values) {
      final text = _normalizedReference(value);
      if (text.isEmpty) continue;
      out.add(text);
    }
    return out;
  }

  Set<String> _bookingAliases(StoredCustomerBooking item) {
    return _normalizedReferenceSet(<String>[
      item.bookingId,
      item.canonicalBookingId,
      item.publicBookingId,
      item.publicBookingReference,
      item.planningReference,
      item.bookingReference,
      item.publicReference,
      item.receiptReference,
      item.paymentBookingId,
    ]);
  }

  String _leafDirName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    for (int i = parts.length - 1; i >= 0; i--) {
      final part = parts[i].trim();
      if (part.isNotEmpty) return part;
    }
    return '';
  }

  int _safeIsoTimestampMs(String iso) {
    final text = iso.trim();
    if (text.isEmpty) return 0;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return 0;
    return parsed.toUtc().millisecondsSinceEpoch;
  }

  int _bookingSortTimestampMs(StoredCustomerBooking item) {
    final updatedMs = _safeIsoTimestampMs(item.updatedAt);
    final createdMs = _safeIsoTimestampMs(item.createdAt);
    final pickupMs = _safeIsoTimestampMs(item.pickupIso);
    return <int>[
      updatedMs,
      createdMs,
      pickupMs,
    ].reduce((a, b) => a > b ? a : b);
  }

  Future<List<StoredCustomerBooking>>
  loadAllAcrossKnownCustomerScopesForDisplayOnly({
    bool allowDiagnosticFallback = false,
  }) async {
    if (!allowDiagnosticFallback) {
      debugPrint(
        '[CUSTOMER_BOOKINGS][FALLBACK_SCAN][SKIP] reason=diagnostic_flag_disabled',
      );
      return const <StoredCustomerBooking>[];
    }
    try {
      final root = await _stateRootDir();
      if (!await root.exists()) {
        debugPrint(
          '[CUSTOMER_BOOKINGS][FALLBACK_SCAN] files=0 loaded=0 result=0',
        );
        return const <StoredCustomerBooking>[];
      }
      final matchedFiles = <File>[];
      await for (final tenantEntry in root.list(followLinks: false)) {
        if (tenantEntry is! Directory) continue;
        final tenantLeaf = _leafDirName(tenantEntry.path);
        if (!tenantLeaf.startsWith('tenant_')) continue;
        await for (final companyEntry in tenantEntry.list(followLinks: false)) {
          if (companyEntry is! Directory) continue;
          final companyLeaf = _leafDirName(companyEntry.path);
          if (!companyLeaf.startsWith('company_')) continue;
          final file = File(
            '${companyEntry.path}${Platform.pathSeparator}$_fileName',
          );
          if (await file.exists()) {
            matchedFiles.add(file);
          }
        }
      }
      if (matchedFiles.isEmpty) {
        debugPrint(
          '[CUSTOMER_BOOKINGS][FALLBACK_SCAN] files=0 loaded=0 result=0',
        );
        return const <StoredCustomerBooking>[];
      }
      final dedupedByKey = <String, StoredCustomerBooking>{};
      final aliasToKey = <String, String>{};
      var loadedCount = 0;
      var generatedKeyCounter = 0;
      for (final file in matchedFiles) {
        final fileItems = await _readFileItems(file);
        if (fileItems.isEmpty) continue;
        loadedCount += fileItems.length;
        for (final item in fileItems) {
          final aliases = _bookingAliases(item);
          String? existingKey;
          for (final alias in aliases) {
            existingKey = aliasToKey[alias];
            if (existingKey != null && existingKey.isNotEmpty) break;
          }
          final targetKey =
              existingKey ??
              (aliases.isNotEmpty
                  ? aliases.first
                  : 'fallback_key_${generatedKeyCounter++}');
          final existing = dedupedByKey[targetKey];
          if (existing == null) {
            dedupedByKey[targetKey] = item;
          } else {
            final existingTs = _bookingSortTimestampMs(existing);
            final incomingTs = _bookingSortTimestampMs(item);
            if (incomingTs > existingTs) {
              dedupedByKey[targetKey] = item;
            }
          }
          final active = dedupedByKey[targetKey]!;
          for (final alias in _bookingAliases(active)) {
            aliasToKey[alias] = targetKey;
          }
        }
      }
      final result = dedupedByKey.values.toList(growable: false)
        ..sort(
          (a, b) =>
              _bookingSortTimestampMs(b).compareTo(_bookingSortTimestampMs(a)),
        );
      debugPrint(
        '[CUSTOMER_BOOKINGS][FALLBACK_SCAN] files=${matchedFiles.length} loaded=$loadedCount result=${result.length}',
      );
      return result;
    } catch (_) {
      debugPrint(
        '[CUSTOMER_BOOKINGS][FALLBACK_SCAN] files=0 loaded=0 result=0',
      );
      return const <StoredCustomerBooking>[];
    }
  }

  Future<({bool removed, int removedCount, int remaining})>
  removeByAnyReferenceAliases(Set<String> aliases) async {
    final normalizedAliases = _normalizedReferenceSet(aliases);
    if (normalizedAliases.isEmpty) {
      final current = await loadAll();
      return (removed: false, removedCount: 0, remaining: current.length);
    }
    final list = await loadAll();
    var removedCount = 0;
    list.removeWhere((item) {
      final itemAliases = _bookingAliases(item);
      final matches = itemAliases.any(normalizedAliases.contains);
      if (matches) removedCount += 1;
      return matches;
    });
    if (removedCount > 0) {
      await _saveAll(list);
    }
    return (
      removed: removedCount > 0,
      removedCount: removedCount,
      remaining: list.length,
    );
  }

  Future<({bool removed, int removedCount, int remaining})>
  removeByAnyReferenceAliasesAcrossKnownCustomerScopesForDisplayOnly(
    Set<String> aliases,
  ) async {
    final normalizedAliases = _normalizedReferenceSet(aliases);
    if (normalizedAliases.isEmpty) {
      return (removed: false, removedCount: 0, remaining: 0);
    }
    try {
      final root = await _stateRootDir();
      if (!await root.exists()) {
        return (removed: false, removedCount: 0, remaining: 0);
      }
      final matchedFiles = <File>[];
      await for (final tenantEntry in root.list(followLinks: false)) {
        if (tenantEntry is! Directory) continue;
        final tenantLeaf = _leafDirName(tenantEntry.path);
        if (!tenantLeaf.startsWith('tenant_')) continue;
        await for (final companyEntry in tenantEntry.list(followLinks: false)) {
          if (companyEntry is! Directory) continue;
          final companyLeaf = _leafDirName(companyEntry.path);
          if (!companyLeaf.startsWith('company_')) continue;
          final file = File(
            '${companyEntry.path}${Platform.pathSeparator}$_fileName',
          );
          if (await file.exists()) {
            matchedFiles.add(file);
          }
        }
      }
      var removedCount = 0;
      var remaining = 0;
      for (final file in matchedFiles) {
        final items = await _readFileItems(file);
        if (items.isEmpty) continue;
        final retained = <StoredCustomerBooking>[];
        for (final item in items) {
          final itemAliases = _bookingAliases(item);
          final matches = itemAliases.any(normalizedAliases.contains);
          if (matches) {
            removedCount += 1;
          } else {
            retained.add(item);
          }
        }
        remaining += retained.length;
        if (retained.length != items.length) {
          await _atomicWriteJsonArray(
            file: file,
            payload: retained.map((e) => e.toJson()).toList(growable: false),
          );
        }
      }
      if (removedCount > 0) {
        _cache = null;
        _cacheScopeKey = '';
      }
      return (
        removed: removedCount > 0,
        removedCount: removedCount,
        remaining: remaining,
      );
    } catch (_) {
      return (removed: false, removedCount: 0, remaining: 0);
    }
  }

  Future<void> clearLocalTestData() async {
    final scope = _activeLocalScope();
    if (scope == null) {
      _cacheScopeKey = '';
      _cache = <StoredCustomerBooking>[];
      debugPrint(
        '[CUSTOMER_BOOKINGS][SKIP_SCOPE] reason=missing_tenant_company_scope op=clearLocalTestData',
      );
      return;
    }
    _cacheScopeKey = '${scope.tenantId.trim()}::${scope.companyId.trim()}';
    _cache = <StoredCustomerBooking>[];
    await _enqueueWrite(() async {
      try {
        final tenantId = scope.tenantId.trim();
        final companyId = scope.companyId.trim();
        final file = await _file();
        if (file == null) return;
        final tempFile = File('${file.path}.tmp');
        final swapFile = File(
          '${file.parent.path}${Platform.pathSeparator}$_fileName.swap',
        );
        if (!await file.exists()) {
          await file.create(recursive: true);
        }
        await file.writeAsString('[]', flush: true);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        if (await swapFile.exists()) {
          await swapFile.delete();
        }
        await _removeVisibleLegacyItemsForScope(
          tenantId: tenantId,
          companyId: companyId,
        );
        debugPrint(
          '[LOCAL_SCOPE][CLEANUP] target=customer_bookings tenant=${_maskScopeId(tenantId)} company=${_maskScopeId(companyId)}',
        );
      } catch (err) {
        debugPrint('[CUSTOMER_BOOKINGS][CLEAR_LOCAL_TEST_DATA_ERROR] $err');
      }
    });
  }
}
