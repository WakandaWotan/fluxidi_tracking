part of '../main.dart';

String? _normalizedCustomerProofPhone(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  if (text.toLowerCase() == 'null') return null;
  return text;
}

String? _normalizedCustomerProofEmail(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  if (text.toLowerCase() == 'null') return null;
  return text.toLowerCase();
}

Future<CustomerProfile?> _loadCachedCustomerProfileIfNeeded() async {
  if (_cachedCustomerProfile != null) return _cachedCustomerProfile;
  final loaded = await CustomerProfileStore.instance.load();
  if (loaded != null) {
    _setCachedCustomerProfile(loaded);
  }
  return loaded;
}

void _invalidateCustomerProfileCaches() {
  _clearCachedCustomerProfile();
  CustomerProfileStore.instance.invalidateCache();
  CustomerBookingsStore.instance.invalidateCache();
}

Future<Map<String, String>> _customerOwnershipProof({
  required String bookingId,
  Set<String>? aliases,
  String? fallbackEmail,
  String? fallbackPhone,
  Map<String, dynamic>? source,
}) async {
  final normalizedAliases = <String>{};
  void addAlias(String? value) {
    final cleaned = _cleanBusinessReferenceText(value);
    if (cleaned == null) return;
    normalizedAliases.add(cleaned.toLowerCase());
  }

  addAlias(bookingId);
  for (final alias in aliases ?? const <String>{}) {
    addAlias(alias);
  }
  if (source != null && source.isNotEmpty) {
    normalizedAliases.addAll(_customerBookingAliasesFromSource(source));
  }

  String? storedEmail;
  String? storedPhone;
  if (normalizedAliases.isNotEmpty) {
    try {
      final all = await CustomerBookingsStore.instance.loadAll();
      for (final item in all) {
        final itemAliases = _customerBookingAliasesFromStored(item);
        final matches =
            item.canonicalBookingId.trim() == bookingId.trim() ||
            _customerAliasesIntersect(itemAliases, normalizedAliases);
        if (!matches) continue;
        storedEmail = _normalizedCustomerProofEmail(item.customerEmail);
        storedPhone = _normalizedCustomerProofPhone(item.customerPhone);
        if (storedEmail != null || storedPhone != null) break;
      }
    } catch (_) {
      // Proof lookup is best-effort; continue with profile/view fallbacks.
    }
  }

  final profile = await _loadCachedCustomerProfileIfNeeded();
  final email =
      storedEmail ??
      _normalizedCustomerProofEmail(profile?.email) ??
      _normalizedCustomerProofEmail(fallbackEmail);
  final phone =
      storedPhone ??
      _normalizedCustomerProofPhone(profile?.phone) ??
      _normalizedCustomerProofPhone(fallbackPhone);

  return <String, String>{
    if (email != null) 'customer_email': email,
    if (phone != null) 'customer_phone': phone,
  };
}

dynamic _customerBootstrapValueAtPath(
  Map<String, dynamic> source,
  String path,
) {
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

String _customerBootstrapText(Map<String, dynamic> source, List<String> paths) {
  for (final path in paths) {
    final value = _customerBootstrapValueAtPath(source, path);
    final text = (value ?? '').toString().trim();
    if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
  }
  return '';
}

double? _customerBootstrapDouble(
  Map<String, dynamic> source,
  List<String> paths,
) {
  for (final path in paths) {
    final value = _customerBootstrapValueAtPath(source, path);
    if (value is num) return value.toDouble();
    final text = (value ?? '').toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') continue;
    final parsed = double.tryParse(text.replaceAll(',', '.'));
    if (parsed != null) return parsed;
  }
  return null;
}

StoredCustomerBooking? _storedBookingFromCustomerBootstrap(
  Map<String, dynamic> item,
  CustomerSession session,
) {
  final bookingId = _customerBootstrapText(item, const [
    'booking_id',
    'bookingId',
    'id',
    'public_booking_id',
    'publicBookingId',
  ]);
  if (bookingId.isEmpty) return null;
  final nowIso = DateTime.now().toIso8601String();
  final tenantId = _customerBootstrapText(item, const [
    'tenant_id',
    'tenantId',
  ]);
  final companyId = _customerBootstrapText(item, const [
    'company_id',
    'companyId',
  ]);
  return StoredCustomerBooking(
    bookingId: bookingId,
    tenantId: tenantId.isNotEmpty
        ? tenantId
        : (session.defaultTenantId ?? '').trim(),
    companyId: companyId.isNotEmpty
        ? companyId
        : (session.defaultCompanyId ?? '').trim(),
    publicBookingId: _customerBootstrapText(item, const [
      'public_booking_reference',
      'publicBookingReference',
      'booking_reference',
      'bookingReference',
      'public_reference',
      'publicReference',
      'public_booking_id',
      'publicBookingId',
    ]),
    planningReference: _customerBootstrapText(item, const [
      'planning_reference',
      'planningReference',
    ]),
    bookingReference: _customerBootstrapText(item, const [
      'booking_reference',
      'bookingReference',
    ]),
    publicReference: _customerBootstrapText(item, const [
      'public_reference',
      'publicReference',
    ]),
    receiptReference: _customerBootstrapText(item, const [
      'receipt_reference',
      'receiptReference',
    ]),
    paymentBookingId: _customerBootstrapText(item, const [
      'payment_booking_id',
      'paymentBookingId',
    ]),
    customerName: _customerBootstrapText(item, const [
      'customer_name',
      'customerName',
    ]),
    customerPhone: _customerBootstrapText(item, const [
      'customer_phone',
      'customerPhone',
    ]),
    customerEmail: _customerBootstrapText(item, const [
      'customer_email',
      'customerEmail',
    ]),
    from: _customerBootstrapText(item, const [
      'from',
      'pickup_address',
      'pickupAddress',
    ]),
    to: _customerBootstrapText(item, const [
      'to',
      'dropoff_address',
      'dropoffAddress',
    ]),
    pickupIso: _customerBootstrapText(item, const ['pickup_iso', 'pickupIso']),
    price: _customerBootstrapDouble(item, const [
      'price',
      'quoted_price',
      'quotedPrice',
    ]),
    currency: _customerBootstrapText(item, const [
      'currency',
      'quote.currency',
    ]),
    paymentStatus: _customerBootstrapText(item, const [
      'payment_status',
      'paymentStatus',
    ]),
    status: _customerBootstrapText(item, const [
      'status',
      'stage',
      'booking_status',
      'bookingStatus',
    ]),
    service: _customerBootstrapText(item, const [
      'service_type',
      'serviceType',
      'service',
    ]),
    tier: _customerBootstrapText(item, const [
      'tier',
      'vehicle_tier',
      'vehicleTier',
    ]),
    pax: _customerBootstrapText(item, const [
      'passenger_count',
      'passengerCount',
      'pax',
    ]),
    bags: _customerBootstrapText(item, const [
      'luggage_count',
      'luggageCount',
      'bags',
    ]),
    createdAt:
        _customerBootstrapText(item, const [
          'created_at',
          'createdAt',
        ]).isNotEmpty
        ? _customerBootstrapText(item, const ['created_at', 'createdAt'])
        : nowIso,
    updatedAt:
        _customerBootstrapText(item, const [
          'updated_at',
          'updatedAt',
        ]).isNotEmpty
        ? _customerBootstrapText(item, const ['updated_at', 'updatedAt'])
        : nowIso,
    companyName: _customerBootstrapText(item, const [
      'company_name',
      'companyName',
    ]),
    vatNumber: _customerBootstrapText(item, const ['vat_number', 'vatNumber']),
    invoiceEmail: _customerBootstrapText(item, const [
      'invoice_email',
      'invoiceEmail',
    ]),
    invoiceAddress: _customerBootstrapText(item, const [
      'invoice_address',
      'invoiceAddress',
    ]),
    quote: _customerBootstrapValueAtPath(item, 'quote') is Map
        ? Map<String, dynamic>.from(
            _customerBootstrapValueAtPath(item, 'quote') as Map,
          )
        : const <String, dynamic>{},
  );
}

bool _isSafeRecoveredCustomerScopeValue(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  final normalized = trimmed.toLowerCase();
  if (normalized == 'global' || normalized == 'fluxidi') return false;
  return true;
}

({String tenantId, String companyId})?
_defaultCustomerScopeFromBootstrapResponse({
  required Map<String, dynamic> response,
  required List<dynamic> bookings,
}) {
  final customerNode = response['customer'] is Map
      ? Map<String, dynamic>.from(response['customer'] as Map)
      : const <String, dynamic>{};
  final customerTenant =
      (customerNode['tenant_id'] ?? customerNode['tenantId'] ?? '')
          .toString()
          .trim();
  final customerCompany =
      (customerNode['company_id'] ?? customerNode['companyId'] ?? '')
          .toString()
          .trim();
  if (_isSafeRecoveredCustomerScopeValue(customerTenant) &&
      _isSafeRecoveredCustomerScopeValue(customerCompany)) {
    return (tenantId: customerTenant, companyId: customerCompany);
  }
  for (final entry in bookings) {
    if (entry is! Map) continue;
    final item = Map<String, dynamic>.from(entry);
    final tenant = (item['tenant_id'] ?? item['tenantId'] ?? '')
        .toString()
        .trim();
    final company = (item['company_id'] ?? item['companyId'] ?? '')
        .toString()
        .trim();
    if (_isSafeRecoveredCustomerScopeValue(tenant) &&
        _isSafeRecoveredCustomerScopeValue(company)) {
      return (tenantId: tenant, companyId: company);
    }
  }
  return null;
}

Future<void> _persistCustomerSessionDefaultScopeIfNeeded({
  required CustomerSession session,
  required Map<String, dynamic> response,
  required List<dynamic> bookings,
}) async {
  final inferred = _defaultCustomerScopeFromBootstrapResponse(
    response: response,
    bookings: bookings,
  );
  if (inferred == null) return;
  final currentTenant = (session.defaultTenantId ?? '').trim();
  final currentCompany = (session.defaultCompanyId ?? '').trim();
  if (currentTenant == inferred.tenantId &&
      currentCompany == inferred.companyId) {
    return;
  }
  final nextSession = CustomerSession(
    customerSessionToken: session.customerSessionToken,
    expiresAt: session.expiresAt,
    customerId: session.customerId,
    phoneE164: session.phoneE164,
    defaultTenantId: inferred.tenantId,
    defaultCompanyId: inferred.companyId,
    createdAt: session.createdAt,
    updatedAt: session.updatedAt,
  );
  await CustomerSessionStore.instance.save(nextSession);
  debugPrint(
    '[CUSTOMER_BOOTSTRAP][SESSION_SCOPE] tenant=${inferred.tenantId} company=${inferred.companyId}',
  );
}

Future<int> _bootstrapCustomerSessionAndMergeBookings({
  required String reason,
}) async {
  try {
    final session = await CustomerSessionStore.instance.loadValidSession();
    if (session == null) return 0;
    debugPrint('[CUSTOMER_BOOTSTRAP][REQ] reason=$reason');
    final response = await fetchPublicCustomerSessionBootstrap(
      customerSessionToken: session.customerSessionToken,
    );
    if (response == null) {
      final status = lastCustomerBootstrapHttpStatusCode;
      if (status == 401 || status == 403) {
        await CustomerSessionStore.instance.clear();
        debugPrint('[CUSTOMER_BOOTSTRAP][SESSION_EXPIRED]');
      } else {
        debugPrint(
          '[CUSTOMER_BOOTSTRAP][FAIL] reason=$reason status=${status ?? 0}',
        );
      }
      return 0;
    }
    final dynamic bookingsRaw =
        response['bookings'] ??
        _customerBootstrapValueAtPath(response, 'data.bookings') ??
        const <dynamic>[];
    final bookings = bookingsRaw is List ? bookingsRaw : const <dynamic>[];
    await _persistCustomerSessionDefaultScopeIfNeeded(
      session: session,
      response: response,
      bookings: bookings,
    );
    debugPrint('[CUSTOMER_BOOTSTRAP][OK] count=${bookings.length}');
    var merged = 0;
    for (final entry in bookings) {
      if (entry is! Map) continue;
      final stored = _storedBookingFromCustomerBootstrap(
        Map<String, dynamic>.from(entry),
        session,
      );
      if (stored == null) continue;
      final aliases = _customerBookingAliasesFromStored(stored);
      final hidden = await CustomerBookingsStore.instance
          .isAnyReferenceAliasHidden(
            aliases,
            tenantIdHint: stored.tenantId,
            companyIdHint: stored.companyId,
            customerSessionIdHint: session.customerId,
          );
      if (hidden) {
        debugPrint(
          '[CUSTOMER_BOOTSTRAP][SKIP_HIDDEN] booking=${_safeRefPreview(stored.canonicalBookingId)}',
        );
        continue;
      }
      await CustomerBookingsStore.instance.upsert(stored);
      merged += 1;
    }
    debugPrint('[CUSTOMER_BOOTSTRAP][MERGE] count=$merged');
    return merged;
  } catch (err) {
    debugPrint('[CUSTOMER_BOOTSTRAP][FAIL] reason=$reason error=$err');
    return 0;
  }
}

Future<CustomerProfile?> _syncCustomerProfileFromBackendBestEffort({
  required String reason,
}) async {
  try {
    final session = await CustomerSessionStore.instance.loadValidSession();
    if (session == null) {
      debugPrint(
        '[CUSTOMER_PROFILE_SYNC][PULL] ok=false reason=$reason stage=no_valid_session',
      );
      return null;
    }
    await ActiveLocalCustomerStore.instance.setActiveCustomerId(
      session.customerId,
    );
    _invalidateCustomerProfileCaches();
    final remote = await fetchPublicCustomerProfile(
      customerSessionToken: session.customerSessionToken,
    );
    if (remote == null) {
      final status = lastCustomerProfileHttpStatusCode ?? 0;
      if (status == 401 || status == 403) {
        await CustomerSessionStore.instance.clear();
      }
      debugPrint(
        '[CUSTOMER_PROFILE_SYNC][PULL] ok=false reason=$reason stage=fetch_failed status=$status',
      );
      return null;
    }
    final merged = await CustomerProfileStore.instance
        .mergeBackendProfileForSession(
          remote,
          sessionCustomerId: session.customerId,
          sessionPhoneE164: session.phoneE164,
        );
    _setCachedCustomerProfile(merged);
    debugPrint('[CUSTOMER_PROFILE_SYNC][PULL] ok=true reason=$reason');
    return merged;
  } catch (err) {
    debugPrint(
      '[CUSTOMER_PROFILE_SYNC][PULL] ok=false reason=$reason stage=error error=$err',
    );
    return null;
  }
}

Future<CustomerProfile?> _syncCustomerProfileToBackendBestEffort({
  required String reason,
  required CustomerProfile localProfile,
}) async {
  try {
    final session = await CustomerSessionStore.instance.loadValidSession();
    if (session == null) {
      debugPrint(
        '[CUSTOMER_PROFILE_SYNC][PUSH] ok=false reason=$reason stage=no_valid_session',
      );
      return null;
    }
    await ActiveLocalCustomerStore.instance.setActiveCustomerId(
      session.customerId,
    );
    _invalidateCustomerProfileCaches();
    final remote = await upsertPublicCustomerProfile(
      customerSessionToken: session.customerSessionToken,
      payload: <String, dynamic>{
        'name': localProfile.name,
        'phone': localProfile.phone,
        'email': localProfile.email,
        'preferred_postcode': localProfile.preferredPostcode,
        'company_name': localProfile.companyName,
        'vat_number': localProfile.vatNumber,
      },
    );
    if (remote == null) {
      final status = lastCustomerProfileHttpStatusCode ?? 0;
      if (status == 401 || status == 403) {
        await CustomerSessionStore.instance.clear();
      }
      debugPrint(
        '[CUSTOMER_PROFILE_SYNC][PUSH] ok=false reason=$reason stage=post_failed status=$status',
      );
      return null;
    }
    final merged = await CustomerProfileStore.instance
        .mergeBackendProfileForSession(
          remote,
          sessionCustomerId: session.customerId,
          sessionPhoneE164: session.phoneE164,
        );
    _setCachedCustomerProfile(merged);
    debugPrint('[CUSTOMER_PROFILE_SYNC][PUSH] ok=true reason=$reason');
    return merged;
  } catch (err) {
    debugPrint(
      '[CUSTOMER_PROFILE_SYNC][PUSH] ok=false reason=$reason stage=error error=$err',
    );
    return null;
  }
}

/// Admin token (optional) for driver actions like complete/cancel/delete.
/// Set at run/build time:
/// flutter run --dart-define=ADMIN_TOKEN=yourSecret
