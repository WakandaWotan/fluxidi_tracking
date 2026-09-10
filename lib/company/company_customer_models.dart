// COMPANY-CUSTOMER-OPS-P0A
//
// Fail-closed parsing of the Worker company-customer contract. Never invents
// cursors and never treats a failed write as a local success.

const int kCompanyCustomerHttpListLimit = 50;
const String kCompanyCustomersPath = '/company/customers';

class CompanyCustomerException implements Exception {
  const CompanyCustomerException(
    this.code, {
    this.fields = const <String, String>{},
    this.revision,
    this.offline = false,
  });

  final String code;
  final Map<String, String> fields;
  final int? revision;
  final bool offline;

  @override
  String toString() => 'CompanyCustomerException($code)';
}

class CompanyCustomerAddress {
  const CompanyCustomerAddress({
    this.addressId = '',
    this.type = 'other',
    this.label = '',
    this.line1 = '',
    this.line2 = '',
    this.city = '',
    this.postalCode = '',
    this.countryCode = '',
    this.notes = '',
  });

  final String addressId;
  final String type;
  final String label;
  final String line1;
  final String line2;
  final String city;
  final String postalCode;
  final String countryCode;
  final String notes;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (addressId.trim().isNotEmpty) 'address_id': addressId.trim(),
      'type': type.trim().isEmpty ? 'other' : type.trim(),
      if (label.trim().isNotEmpty) 'label': label.trim(),
      if (line1.trim().isNotEmpty) 'line1': line1.trim(),
      if (line2.trim().isNotEmpty) 'line2': line2.trim(),
      if (city.trim().isNotEmpty) 'city': city.trim(),
      if (postalCode.trim().isNotEmpty) 'postal_code': postalCode.trim(),
      if (countryCode.trim().isNotEmpty) 'country_code': countryCode.trim(),
      if (notes.trim().isNotEmpty) 'notes': notes.trim(),
    };
  }
}

class CompanyCustomerPreferences {
  const CompanyCustomerPreferences({
    this.version = 1,
    this.preferredLocale = '',
  });

  final int version;
  final String preferredLocale;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': version,
      if (preferredLocale.trim().isNotEmpty)
        'preferred_locale': preferredLocale.trim(),
    };
  }
}

class CompanyCustomerListItem {
  const CompanyCustomerListItem({
    required this.customerId,
    required this.displayName,
    required this.companyName,
    required this.phoneMasked,
    required this.emailMasked,
    required this.status,
    required this.updatedAt,
  });

  final String customerId;
  final String displayName;
  final String companyName;
  final String phoneMasked;
  final String emailMasked;
  final String status;
  final String updatedAt;

  bool get isArchived => status == 'archived';
}

class CompanyCustomer {
  const CompanyCustomer({
    required this.customerId,
    required this.tenantId,
    required this.companyId,
    required this.displayName,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.phoneNormalized,
    required this.countryCallingCode,
    required this.email,
    required this.locale,
    required this.companyName,
    required this.vatNumber,
    required this.addresses,
    required this.internalNotes,
    required this.preferences,
    required this.source,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.archivedAt,
    required this.revision,
  });

  final String customerId;
  final String tenantId;
  final String companyId;
  final String displayName;
  final String firstName;
  final String lastName;
  final String phone;
  final String phoneNormalized;
  final String countryCallingCode;
  final String email;
  final String locale;
  final String companyName;
  final String vatNumber;
  final List<CompanyCustomerAddress> addresses;
  final String internalNotes;
  final CompanyCustomerPreferences preferences;
  final String source;
  final String status;
  final String createdAt;
  final String updatedAt;
  final String? archivedAt;
  final int revision;

  bool get isArchived => status == 'archived';
}

class CompanyCustomerDuplicateMatch {
  const CompanyCustomerDuplicateMatch({
    required this.customerId,
    required this.field,
  });

  final String customerId;
  final String field;
}

class CompanyCustomerMutationResult {
  const CompanyCustomerMutationResult({
    required this.customer,
    this.duplicateMatches = const <CompanyCustomerDuplicateMatch>[],
    this.idempotent = false,
  });

  final CompanyCustomer customer;
  final List<CompanyCustomerDuplicateMatch> duplicateMatches;
  final bool idempotent;
}

class CompanyCustomerListPage {
  const CompanyCustomerListPage({
    required this.items,
    required this.hasMore,
    required this.nextCursor,
    required this.totalCount,
  });

  final List<CompanyCustomerListItem> items;
  final bool hasMore;
  final String? nextCursor;
  final int? totalCount;
}

class CompanyCustomerWrite {
  const CompanyCustomerWrite({
    this.displayName = '',
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.countryCallingCode = '',
    this.email = '',
    this.locale = '',
    this.companyName = '',
    this.vatNumber = '',
    this.addresses = const <CompanyCustomerAddress>[],
    this.internalNotes = '',
    this.preferences = const CompanyCustomerPreferences(),
  });

  final String displayName;
  final String firstName;
  final String lastName;
  final String phone;
  final String countryCallingCode;
  final String email;
  final String locale;
  final String companyName;
  final String vatNumber;
  final List<CompanyCustomerAddress> addresses;
  final String internalNotes;
  final CompanyCustomerPreferences preferences;

  Map<String, dynamic> toJson({int? revision}) {
    return <String, dynamic>{
      if (displayName.trim().isNotEmpty) 'display_name': displayName.trim(),
      if (firstName.trim().isNotEmpty) 'first_name': firstName.trim(),
      if (lastName.trim().isNotEmpty) 'last_name': lastName.trim(),
      if (phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (countryCallingCode.trim().isNotEmpty)
        'country_calling_code': countryCallingCode.trim(),
      if (email.trim().isNotEmpty) 'email': email.trim(),
      if (locale.trim().isNotEmpty) 'locale': locale.trim(),
      if (companyName.trim().isNotEmpty) 'company_name': companyName.trim(),
      if (vatNumber.trim().isNotEmpty) 'vat_number': vatNumber.trim(),
      'addresses': [
        for (final address in addresses) address.toJson(),
      ],
      if (internalNotes.trim().isNotEmpty)
        'internal_notes': internalNotes.trim(),
      'preferences': preferences.toJson(),
      if (revision != null) 'revision': revision,
    };
  }
}

final _emailAt = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String composeCompanyCustomerDisplayName({
  required String displayName,
  required String firstName,
  required String lastName,
}) {
  final display = displayName.trim();
  if (display.isNotEmpty) return display;
  return '$firstName $lastName'.trim();
}

String normalizeCompanyCustomerEmail(String raw) => raw.trim().toLowerCase();

({String normalized, String e164, String countryCallingCode})
normalizeCompanyCustomerPhone(String raw, String countryCallingCode) {
  final text = raw.trim();
  final cc = countryCallingCode.replaceAll(RegExp(r'[^0-9]'), '');
  if (text.isEmpty) {
    return (normalized: '', e164: '', countryCallingCode: cc);
  }
  final keepPlus = text.startsWith('+');
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    return (normalized: '', e164: '', countryCallingCode: cc);
  }
  var e164 = '';
  if (keepPlus && digits.length >= 8 && digits.length <= 15) {
    e164 = '+$digits';
  } else if (cc.isNotEmpty && digits.length >= 4 && digits.length <= 15) {
    final national = digits.startsWith(cc) ? digits.substring(cc.length) : digits;
    final combined = '$cc$national';
    if (combined.length >= 8 && combined.length <= 15) {
      e164 = '+$combined';
    }
  }
  final normalized = e164.isNotEmpty ? e164 : (keepPlus ? '+$digits' : digits);
  return (normalized: normalized, e164: e164, countryCallingCode: cc);
}

bool isUsableCompanyCustomerEmail(String raw) {
  final email = normalizeCompanyCustomerEmail(raw);
  if (email.isEmpty || email.length > 320) return false;
  if (email.startsWith('.') || email.endsWith('.')) return false;
  return _emailAt.hasMatch(email);
}

bool isUsableCompanyCustomerPhone(String normalized) {
  final digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length >= 8 && digits.length <= 15;
}

Map<String, String> validateCompanyCustomerWrite(CompanyCustomerWrite write) {
  final fields = <String, String>{};
  final name = composeCompanyCustomerDisplayName(
    displayName: write.displayName,
    firstName: write.firstName,
    lastName: write.lastName,
  );
  if (name.isEmpty) fields['display_name'] = 'required';
  final emailOk =
      write.email.trim().isEmpty || isUsableCompanyCustomerEmail(write.email);
  if (write.email.trim().isNotEmpty && !emailOk) {
    fields['email'] = 'invalid';
  }
  final phone = normalizeCompanyCustomerPhone(
    write.phone,
    write.countryCallingCode,
  );
  if (write.phone.trim().isNotEmpty &&
      !isUsableCompanyCustomerPhone(phone.normalized)) {
    fields['phone'] = 'invalid';
  }
  final hasContact =
      isUsableCompanyCustomerEmail(write.email) ||
      isUsableCompanyCustomerPhone(phone.normalized);
  if (!hasContact) fields['contact'] = 'required';
  return fields;
}

int? _parseExactCount(Object? raw) {
  if (raw == null || raw is bool) return null;
  if (raw is int) return raw < 0 ? null : raw;
  if (raw is num) {
    final parsed = raw.toInt();
    if (raw != parsed || parsed < 0) return null;
    return parsed;
  }
  if (raw is String) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }
  return null;
}

String _requireText(Map<dynamic, dynamic> map, String key) {
  final value = map[key]?.toString().trim() ?? '';
  if (value.isEmpty) {
    throw const CompanyCustomerException('invalid_payload');
  }
  return value;
}

String _optionalText(Map<dynamic, dynamic> map, String key) {
  return map[key]?.toString().trim() ?? '';
}

CompanyCustomerAddress parseCompanyCustomerAddress(Map<dynamic, dynamic> raw) {
  final type = _optionalText(raw, 'type').toLowerCase();
  const allowed = <String>{'home', 'work', 'pickup', 'billing', 'other'};
  return CompanyCustomerAddress(
    addressId: _optionalText(raw, 'address_id'),
    type: allowed.contains(type) ? type : 'other',
    label: _optionalText(raw, 'label'),
    line1: _optionalText(raw, 'line1'),
    line2: _optionalText(raw, 'line2'),
    city: _optionalText(raw, 'city'),
    postalCode: _optionalText(raw, 'postal_code'),
    countryCode: _optionalText(raw, 'country_code'),
    notes: _optionalText(raw, 'notes'),
  );
}

CompanyCustomerPreferences parseCompanyCustomerPreferences(Object? raw) {
  if (raw == null) return const CompanyCustomerPreferences();
  if (raw is! Map) {
    throw const CompanyCustomerException('invalid_payload');
  }
  final map = Map<dynamic, dynamic>.from(raw);
  final version = _parseExactCount(map['version']) ?? 1;
  if (version < 1) {
    throw const CompanyCustomerException('invalid_payload');
  }
  return CompanyCustomerPreferences(
    version: version,
    preferredLocale: _optionalText(map, 'preferred_locale'),
  );
}

CompanyCustomerListItem parseCompanyCustomerListItem(Map<dynamic, dynamic> raw) {
  final status = _requireText(raw, 'status');
  if (status != 'active' && status != 'archived') {
    throw const CompanyCustomerException('invalid_payload');
  }
  return CompanyCustomerListItem(
    customerId: _requireText(raw, 'customer_id'),
    displayName: _optionalText(raw, 'display_name'),
    companyName: _optionalText(raw, 'company_name'),
    phoneMasked: _optionalText(raw, 'phone_masked'),
    emailMasked: _optionalText(raw, 'email_masked'),
    status: status,
    updatedAt: _optionalText(raw, 'updated_at'),
  );
}

CompanyCustomer parseCompanyCustomer(Map<dynamic, dynamic> raw) {
  final status = _requireText(raw, 'status');
  if (status != 'active' && status != 'archived') {
    throw const CompanyCustomerException('invalid_payload');
  }
  final revision = _parseExactCount(raw['revision']);
  if (revision == null || revision < 1) {
    throw const CompanyCustomerException('invalid_payload');
  }
  final addressesRaw = raw['addresses'];
  if (addressesRaw != null && addressesRaw is! List) {
    throw const CompanyCustomerException('invalid_payload');
  }
  final addresses = <CompanyCustomerAddress>[
    for (final item in (addressesRaw as List<dynamic>? ?? const <dynamic>[]))
      if (item is Map) parseCompanyCustomerAddress(item),
  ];
  final archivedAt = _optionalText(raw, 'archived_at');
  return CompanyCustomer(
    customerId: _requireText(raw, 'customer_id'),
    tenantId: _optionalText(raw, 'tenant_id'),
    companyId: _optionalText(raw, 'company_id'),
    displayName: _requireText(raw, 'display_name'),
    firstName: _optionalText(raw, 'first_name'),
    lastName: _optionalText(raw, 'last_name'),
    phone: _optionalText(raw, 'phone'),
    phoneNormalized: _optionalText(raw, 'phone_normalized'),
    countryCallingCode: _optionalText(raw, 'country_calling_code'),
    email: _optionalText(raw, 'email'),
    locale: _optionalText(raw, 'locale'),
    companyName: _optionalText(raw, 'company_name'),
    vatNumber: _optionalText(raw, 'vat_number'),
    addresses: addresses,
    internalNotes: _optionalText(raw, 'internal_notes'),
    preferences: parseCompanyCustomerPreferences(raw['preferences']),
    source: _optionalText(raw, 'source').isEmpty
        ? 'manual'
        : _optionalText(raw, 'source'),
    status: status,
    createdAt: _optionalText(raw, 'created_at'),
    updatedAt: _optionalText(raw, 'updated_at'),
    archivedAt: archivedAt.isEmpty ? null : archivedAt,
    revision: revision,
  );
}

CompanyCustomerListPage parseCompanyCustomerListPage(Map<dynamic, dynamic> raw) {
  if (raw['ok'] != true) {
    final error = raw['error']?.toString().trim();
    throw CompanyCustomerException(
      (error == null || error.isEmpty) ? 'customers_not_ok' : error,
    );
  }
  final itemsRaw = raw['items'];
  if (itemsRaw is! List) {
    throw const CompanyCustomerException('invalid_payload');
  }
  final items = <CompanyCustomerListItem>[
    for (final item in itemsRaw)
      if (item is Map) parseCompanyCustomerListItem(item),
  ];
  if (items.length != itemsRaw.whereType<Map>().length &&
      itemsRaw.any((item) => item is! Map)) {
    throw const CompanyCustomerException('invalid_payload');
  }
  final hasMoreFlag = raw['has_more'] == true;
  final cursor = raw['next_cursor']?.toString().trim() ?? '';
  final hasMore = hasMoreFlag && cursor.isNotEmpty;
  return CompanyCustomerListPage(
    items: items,
    hasMore: hasMore,
    nextCursor: hasMore ? cursor : null,
    totalCount: _parseExactCount(raw['total_count']),
  );
}

CompanyCustomer parseCompanyCustomerEnvelope(Map<dynamic, dynamic> raw) {
  if (raw['ok'] != true) {
    final error = raw['error']?.toString().trim();
    throw CompanyCustomerException(
      (error == null || error.isEmpty) ? 'customers_not_ok' : error,
      fields: _parseFields(raw['fields']),
      revision: _parseExactCount(raw['revision']),
    );
  }
  final customerRaw = raw['customer'];
  if (customerRaw is! Map) {
    throw const CompanyCustomerException('invalid_payload');
  }
  return parseCompanyCustomer(customerRaw);
}

CompanyCustomerMutationResult parseCompanyCustomerMutation(
  Map<dynamic, dynamic> raw,
) {
  final customer = parseCompanyCustomerEnvelope(raw);
  final warning = raw['duplicate_warning'];
  final matches = <CompanyCustomerDuplicateMatch>[];
  if (warning is Map) {
    final list = warning['matches'];
    if (list is List) {
      for (final item in list) {
        if (item is! Map) continue;
        final id = item['customer_id']?.toString().trim() ?? '';
        final field = item['field']?.toString().trim() ?? '';
        if (id.isEmpty || field.isEmpty) {
          throw const CompanyCustomerException('invalid_payload');
        }
        matches.add(CompanyCustomerDuplicateMatch(customerId: id, field: field));
      }
    }
  }
  return CompanyCustomerMutationResult(
    customer: customer,
    duplicateMatches: matches,
    idempotent: raw['idempotent'] == true,
  );
}

Map<String, String> _parseFields(Object? raw) {
  if (raw is! Map) return const <String, String>{};
  final fields = <String, String>{};
  raw.forEach((key, value) {
    final name = key.toString().trim();
    final code = value?.toString().trim() ?? '';
    if (name.isNotEmpty && code.isNotEmpty) fields[name] = code;
  });
  return fields;
}

Map<String, String> buildCompanyCustomerListQuery({
  required Map<String, String> scopeQuery,
  required String status,
  required String query,
  required String cursor,
  int limit = kCompanyCustomerHttpListLimit,
}) {
  final params = <String, String>{
    ...scopeQuery,
    'status': status,
    'limit': '$limit',
  };
  final q = query.trim();
  if (q.isNotEmpty) params['q'] = q;
  final next = cursor.trim();
  if (next.isNotEmpty) params['cursor'] = next;
  return params;
}
