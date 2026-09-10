// COMPANY-CUSTOMER-OPS-P0B

import 'dart:math';

import 'package:fluxidi_tracking/company/company_customer_models.dart';

const int kCompanyCustomerImportMaxFileBytes = 2 * 1024 * 1024;
const int kCompanyCustomerImportMaxRows = 2000;
const int kCompanyCustomerImportMaxXlsxUnpackedBytes = 8 * 1024 * 1024;
const int kCompanyCustomerImportBatchSize = 2;
const Duration kCompanyCustomerImportSessionTtl = Duration(hours: 72);
const String kCompanyCustomerImportPathPrefix = '/company/customers/import';

class CompanyCustomerImportException implements Exception {
  const CompanyCustomerImportException(this.code, {this.detail = ''});

  final String code;
  final String detail;

  @override
  String toString() => 'CompanyCustomerImportException($code)';
}

enum CompanyCustomerImportKind { csv, xlsx, vcard }

enum CompanyCustomerImportDecision { create, skip }

class CompanyCustomerImportPickedFile {
  const CompanyCustomerImportPickedFile({
    required this.name,
    required this.bytes,
  });

  final String name;
  final List<int> bytes;
}

class CompanyCustomerImportTable {
  const CompanyCustomerImportTable({
    required this.kind,
    required this.fileName,
    required this.headers,
    required this.rows,
    this.sheetNames = const <String>[],
    this.selectedSheet = '',
    this.headerRowIndex = 0,
    this.sourceLabels = const <int>[],
  });

  final CompanyCustomerImportKind kind;
  final String fileName;
  final List<String> headers;
  final List<List<String>> rows;
  final List<String> sheetNames;
  final String selectedSheet;
  final int headerRowIndex;
  final List<int> sourceLabels;

  int sourceIndexFor(int rowOffset) {
    if (rowOffset >= 0 && rowOffset < sourceLabels.length) {
      return sourceLabels[rowOffset];
    }
    return rowOffset + 1;
  }
}

class CompanyCustomerImportCompanyMatch {
  const CompanyCustomerImportCompanyMatch({
    required this.rowKey,
    required this.customerId,
    required this.field,
    required this.displayName,
    required this.emailMasked,
    required this.phoneMasked,
    required this.status,
  });

  final String rowKey;
  final String customerId;
  final String field;
  final String displayName;
  final String emailMasked;
  final String phoneMasked;
  final String status;
}

class CompanyCustomerImportPreparedRow {
  CompanyCustomerImportPreparedRow({
    required this.rowKey,
    required this.sourceIndex,
    required this.write,
    required this.fieldErrors,
    required this.inFileDupSources,
    required this.companyMatches,
    required this.selected,
    required this.decision,
  });

  final String rowKey;
  final int sourceIndex;
  final CompanyCustomerWrite write;
  final Map<String, String> fieldErrors;
  final List<int> inFileDupSources;
  final List<CompanyCustomerImportCompanyMatch> companyMatches;
  bool selected;
  CompanyCustomerImportDecision decision;

  bool get isValid => fieldErrors.isEmpty;
}

class CompanyCustomerImportRowOutcome {
  const CompanyCustomerImportRowOutcome({
    required this.rowKey,
    required this.outcome,
    this.customerId = '',
    this.error = '',
    this.fields = const <String, String>{},
    this.idempotent = false,
    this.replayed = false,
  });

  final String rowKey;
  final String outcome;
  final String customerId;
  final String error;
  final Map<String, String> fields;
  final bool idempotent;
  final bool replayed;
}

class CompanyCustomerImportBatchResult {
  const CompanyCustomerImportBatchResult({
    required this.importId,
    required this.added,
    required this.skipped,
    required this.failed,
    required this.processed,
    required this.rows,
  });

  final String importId;
  final int added;
  final int skipped;
  final int failed;
  final int processed;
  final List<CompanyCustomerImportRowOutcome> rows;
}

class CompanyCustomerImportStatus {
  const CompanyCustomerImportStatus({
    required this.importId,
    required this.added,
    required this.skipped,
    required this.failed,
    required this.processed,
    required this.rows,
  });

  final String importId;
  final int added;
  final int skipped;
  final int failed;
  final int processed;
  final Map<String, CompanyCustomerImportRowOutcome> rows;
}

class CompanyCustomerImportFileFingerprint {
  const CompanyCustomerImportFileFingerprint({
    required this.fileName,
    required this.byteLength,
    required this.headerSignature,
    required this.mappingSignature,
  });

  final String fileName;
  final int byteLength;
  final String headerSignature;
  final String mappingSignature;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'file_name': fileName,
      'byte_length': byteLength,
      'header_signature': headerSignature,
      'mapping_signature': mappingSignature,
    };
  }
}

CompanyCustomerImportFileFingerprint? parseCompanyCustomerImportFileFingerprint(
  Object? raw,
) {
  if (raw == null) return null;
  if (raw is! Map) return null;
  final map = Map<dynamic, dynamic>.from(raw);
  final name = map['file_name']?.toString().trim() ?? '';
  final length = parseExactCount(map['byte_length']) ?? 0;
  if (name.isEmpty || length < 1) return null;
  return CompanyCustomerImportFileFingerprint(
    fileName: name,
    byteLength: length,
    headerSignature: map['header_signature']?.toString() ?? '',
    mappingSignature: map['mapping_signature']?.toString() ?? '',
  );
}

String companyCustomerImportHeaderSignature(List<String> headers) {
  return headers.join('\u001f');
}

String companyCustomerImportMappingSignature(List<String> mappings) {
  return mappings.join(',');
}

CompanyCustomerImportFileFingerprint buildCompanyCustomerImportFingerprint({
  required CompanyCustomerImportPickedFile file,
  required CompanyCustomerImportTable table,
  required List<String> mappings,
}) {
  return CompanyCustomerImportFileFingerprint(
    fileName: file.name.trim(),
    byteLength: file.bytes.length,
    headerSignature: companyCustomerImportHeaderSignature(table.headers),
    mappingSignature: companyCustomerImportMappingSignature(mappings),
  );
}

class CompanyCustomerImportSession {
  CompanyCustomerImportSession({
    required this.importId,
    required this.companyId,
    required this.expiresAt,
    required this.rows,
    required this.outcomes,
    required this.defaultCallingCode,
    this.confirmedPartial = false,
    this.fingerprint,
    this.mappings = const <String>[],
  });

  final String importId;
  final String companyId;
  final DateTime expiresAt;
  final List<CompanyCustomerImportPreparedRow> rows;
  final Map<String, CompanyCustomerImportRowOutcome> outcomes;
  final String defaultCallingCode;
  bool confirmedPartial;
  final CompanyCustomerImportFileFingerprint? fingerprint;
  final List<String> mappings;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool get needsFileRepick => rows.isEmpty && importId.trim().isNotEmpty;

  List<CompanyCustomerImportPreparedRow> get pending {
    return [
      for (final row in rows)
        if (row.selected &&
            row.isValid &&
            !outcomes.containsKey(row.rowKey))
          row,
    ];
  }

  CompanyCustomerImportSession copyWith({
    List<CompanyCustomerImportPreparedRow>? rows,
    Map<String, CompanyCustomerImportRowOutcome>? outcomes,
    bool? confirmedPartial,
    CompanyCustomerImportFileFingerprint? fingerprint,
    List<String>? mappings,
    String? defaultCallingCode,
  }) {
    return CompanyCustomerImportSession(
      importId: importId,
      companyId: companyId,
      expiresAt: expiresAt,
      rows: rows ?? this.rows,
      outcomes: outcomes ?? this.outcomes,
      defaultCallingCode: defaultCallingCode ?? this.defaultCallingCode,
      confirmedPartial: confirmedPartial ?? this.confirmedPartial,
      fingerprint: fingerprint ?? this.fingerprint,
      mappings: mappings ?? this.mappings,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'import_id': importId,
      'company_id': companyId,
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'default_calling_code': defaultCallingCode,
      'confirmed_partial': confirmedPartial,
      if (fingerprint != null) 'fingerprint': fingerprint!.toJson(),
      'mappings': mappings,
      'outcomes': <String, dynamic>{
        for (final entry in outcomes.entries)
          entry.key: <String, dynamic>{
            'row_key': entry.value.rowKey,
            'outcome': entry.value.outcome,
            if (entry.value.customerId.isNotEmpty)
              'customer_id': entry.value.customerId,
            if (entry.value.error.isNotEmpty) 'error': entry.value.error,
            if (entry.value.idempotent) 'idempotent': true,
            if (entry.value.replayed) 'replayed': true,
          },
      },
      'rows': [
        for (final row in rows)
          <String, dynamic>{
            'row_key': row.rowKey,
            'source_index': row.sourceIndex,
            'selected': row.selected,
            'decision': row.decision == CompanyCustomerImportDecision.skip
                ? 'skip'
                : 'create',
            'field_errors': row.fieldErrors,
            'customer': row.write.toJson(),
          },
      ],
    };
  }
}

const List<String> kCompanyCustomerImportTargetFields = <String>[
  'skip',
  'display_name',
  'first_name',
  'last_name',
  'email',
  'phone',
  'country_calling_code',
  'company_name',
  'vat_number',
  'locale',
  'internal_notes',
  'address_line1',
  'address_line2',
  'address_city',
  'address_postal_code',
  'address_country',
  'address_type',
];

String? suggestCompanyCustomerImportMapping(String header) {
  final key = header.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), ' ');
  const names = <String, String>{
    'name': 'display_name',
    'naam': 'display_name',
    'full name': 'display_name',
    'volledige naam': 'display_name',
    'display name': 'display_name',
    'fn': 'display_name',
    'first name': 'first_name',
    'voornaam': 'first_name',
    'prenom': 'first_name',
    'prénom': 'first_name',
    'given name': 'first_name',
    'last name': 'last_name',
    'achternaam': 'last_name',
    'familienaam': 'last_name',
    'surname': 'last_name',
    'nom': 'last_name',
    'email': 'email',
    'e mail': 'email',
    'e-mail': 'email',
    'mail': 'email',
    'phone': 'phone',
    'telephone': 'phone',
    'téléphone': 'phone',
    'telefoon': 'phone',
    'gsm': 'phone',
    'mobile': 'phone',
    'tel': 'phone',
    'country code': 'country_calling_code',
    'landnummer': 'country_calling_code',
    'calling code': 'country_calling_code',
    'company': 'company_name',
    'company name': 'company_name',
    'bedrijf': 'company_name',
    'bedrijfsnaam': 'company_name',
    'organisation': 'company_name',
    'organization': 'company_name',
    'org': 'company_name',
    'vat': 'vat_number',
    'btw': 'vat_number',
    'vat number': 'vat_number',
    'locale': 'locale',
    'taal': 'locale',
    'language': 'locale',
    'notes': 'internal_notes',
    'notities': 'internal_notes',
    'note': 'internal_notes',
    'address': 'address_line1',
    'adres': 'address_line1',
    'street': 'address_line1',
    'straat': 'address_line1',
    'line1': 'address_line1',
    'line2': 'address_line2',
    'city': 'address_city',
    'plaats': 'address_city',
    'stad': 'address_city',
    'ville': 'address_city',
    'postal code': 'address_postal_code',
    'postcode': 'address_postal_code',
    'zip': 'address_postal_code',
    'country': 'address_country',
    'land': 'address_country',
    'address type': 'address_type',
  };
  return names[key];
}

List<String> suggestCompanyCustomerImportMappings(List<String> headers) {
  return [
    for (final header in headers)
      suggestCompanyCustomerImportMapping(header) ?? 'skip',
  ];
}

CompanyCustomerWrite writeFromImportValues(
  Map<String, String> values, {
  String defaultCallingCode = '',
}) {
  final addresses = <CompanyCustomerAddress>[];
  final line1 = values['address_line1']?.trim() ?? '';
  final line2 = values['address_line2']?.trim() ?? '';
  final city = values['address_city']?.trim() ?? '';
  final postal = values['address_postal_code']?.trim() ?? '';
  final country = values['address_country']?.trim() ?? '';
  final type = (values['address_type']?.trim().toLowerCase() ?? '').isEmpty
      ? 'other'
      : values['address_type']!.trim().toLowerCase();
  if (line1.isNotEmpty ||
      line2.isNotEmpty ||
      city.isNotEmpty ||
      postal.isNotEmpty ||
      country.isNotEmpty) {
    addresses.add(
      CompanyCustomerAddress(
        type: type,
        line1: line1,
        line2: line2,
        city: city,
        postalCode: postal,
        countryCode: country,
      ),
    );
  }
  return CompanyCustomerWrite(
    displayName: values['display_name'] ?? '',
    firstName: values['first_name'] ?? '',
    lastName: values['last_name'] ?? '',
    email: values['email'] ?? '',
    phone: values['phone'] ?? '',
    countryCallingCode: (values['country_calling_code'] ?? '').trim().isEmpty
        ? defaultCallingCode
        : values['country_calling_code']!.trim(),
    companyName: values['company_name'] ?? '',
    vatNumber: values['vat_number'] ?? '',
    locale: values['locale'] ?? '',
    internalNotes: values['internal_notes'] ?? '',
    addresses: addresses,
  );
}

Map<String, String> valuesFromMappedRow({
  required List<String> headers,
  required List<String> row,
  required List<String> mappings,
}) {
  final values = <String, String>{};
  for (var i = 0; i < mappings.length; i += 1) {
    final field = mappings[i];
    if (field == 'skip' || !kCompanyCustomerImportTargetFields.contains(field)) {
      continue;
    }
    final value = i < row.length ? row[i] : '';
    if (value.trim().isEmpty) continue;
    final existing = values[field];
    if (existing == null || existing.trim().isEmpty) {
      values[field] = value;
    }
  }
  return values;
}

List<CompanyCustomerImportPreparedRow> prepareCompanyCustomerImportRows({
  required CompanyCustomerImportTable table,
  required List<String> mappings,
  String defaultCallingCode = '',
}) {
  if (table.rows.length > kCompanyCustomerImportMaxRows) {
    throw const CompanyCustomerImportException('limit_rows');
  }
  final prepared = <CompanyCustomerImportPreparedRow>[];
  final emailOwners = <String, List<int>>{};
  final phoneOwners = <String, List<int>>{};
  for (var i = 0; i < table.rows.length; i += 1) {
    final sourceIndex = table.sourceIndexFor(i);
    final values = valuesFromMappedRow(
      headers: table.headers,
      row: table.rows[i],
      mappings: mappings,
    );
    final write = writeFromImportValues(
      values,
      defaultCallingCode: defaultCallingCode,
    );
    final errors = validateCompanyCustomerWrite(write);
    final email = normalizeCompanyCustomerEmail(write.email);
    final phone = normalizeCompanyCustomerPhone(
      write.phone,
      write.countryCallingCode,
    );
    if (email.isNotEmpty) {
      emailOwners.putIfAbsent(email, () => <int>[]).add(sourceIndex);
    }
    if (phone.normalized.isNotEmpty) {
      phoneOwners.putIfAbsent(phone.normalized, () => <int>[]).add(sourceIndex);
    }
    prepared.add(
      CompanyCustomerImportPreparedRow(
        rowKey: 'r$sourceIndex',
        sourceIndex: sourceIndex,
        write: write,
        fieldErrors: errors,
        inFileDupSources: <int>[],
        companyMatches: <CompanyCustomerImportCompanyMatch>[],
        selected: errors.isEmpty,
        decision: CompanyCustomerImportDecision.create,
      ),
    );
  }
  for (final row in prepared) {
    final email = normalizeCompanyCustomerEmail(row.write.email);
    final phone = normalizeCompanyCustomerPhone(
      row.write.phone,
      row.write.countryCallingCode,
    );
    final dups = <int>{};
    if (email.isNotEmpty) {
      dups.addAll(emailOwners[email] ?? const <int>[]);
    }
    if (phone.normalized.isNotEmpty) {
      dups.addAll(phoneOwners[phone.normalized] ?? const <int>[]);
    }
    dups.remove(row.sourceIndex);
    row.inFileDupSources.addAll(dups.toList()..sort());
  }
  return prepared;
}

int? parseExactCount(Object? raw) {
  if (raw == null || raw is bool) return null;
  if (raw is int) return raw < 0 ? null : raw;
  if (raw is num) {
    final parsed = raw.toInt();
    if (raw != parsed || parsed < 0) return null;
    return parsed;
  }
  if (raw is String) {
    return int.tryParse(raw.trim());
  }
  return null;
}

CompanyCustomerImportRowOutcome parseCompanyCustomerImportRowOutcome(
  Map<dynamic, dynamic> raw,
) {
  final rowKey = raw['row_key']?.toString().trim() ?? '';
  final outcome = raw['outcome']?.toString().trim() ?? '';
  if (rowKey.isEmpty || outcome.isEmpty) {
    throw const CompanyCustomerException('invalid_payload');
  }
  final fields = <String, String>{};
  final rawFields = raw['fields'];
  if (rawFields is Map) {
    rawFields.forEach((key, value) {
      final name = key.toString().trim();
      final code = value?.toString().trim() ?? '';
      if (name.isNotEmpty && code.isNotEmpty) fields[name] = code;
    });
  }
  return CompanyCustomerImportRowOutcome(
    rowKey: rowKey,
    outcome: outcome,
    customerId: raw['customer_id']?.toString().trim() ?? '',
    error: raw['error']?.toString().trim() ?? '',
    fields: fields,
    idempotent: raw['idempotent'] == true,
    replayed: raw['replayed'] == true,
  );
}

CompanyCustomerImportBatchResult parseCompanyCustomerImportBatch(
  Map<dynamic, dynamic> raw,
) {
  if (raw['ok'] != true) {
    throw CompanyCustomerException(
      raw['error']?.toString().trim().isNotEmpty == true
          ? raw['error'].toString()
          : 'import_not_ok',
    );
  }
  final rowsRaw = raw['rows'];
  if (rowsRaw is! List) {
    throw const CompanyCustomerException('invalid_payload');
  }
  return CompanyCustomerImportBatchResult(
    importId: raw['import_id']?.toString().trim() ?? '',
    added: parseExactCount(raw['added']) ?? 0,
    skipped: parseExactCount(raw['skipped']) ?? 0,
    failed: parseExactCount(raw['failed']) ?? 0,
    processed: parseExactCount(raw['processed']) ?? 0,
    rows: [
      for (final item in rowsRaw)
        if (item is Map) parseCompanyCustomerImportRowOutcome(item),
    ],
  );
}

CompanyCustomerImportStatus parseCompanyCustomerImportStatus(
  Map<dynamic, dynamic> raw,
) {
  if (raw['ok'] != true) {
    throw CompanyCustomerException(
      raw['error']?.toString().trim().isNotEmpty == true
          ? raw['error'].toString()
          : 'import_not_ok',
    );
  }
  final importRaw = raw['import'];
  if (importRaw is! Map) {
    throw const CompanyCustomerException('invalid_payload');
  }
  final rows = <String, CompanyCustomerImportRowOutcome>{};
  final rowsRaw = importRaw['rows'];
  if (rowsRaw is Map) {
    rowsRaw.forEach((key, value) {
      if (value is! Map) return;
      final mapped = Map<dynamic, dynamic>.from(value);
      mapped['row_key'] = key.toString();
      if ((mapped['outcome']?.toString() ?? '').isEmpty) return;
      final parsed = parseCompanyCustomerImportRowOutcome(mapped);
      rows[parsed.rowKey] = parsed;
    });
  }
  return CompanyCustomerImportStatus(
    importId: importRaw['import_id']?.toString().trim() ?? '',
    added: parseExactCount(importRaw['added']) ?? 0,
    skipped: parseExactCount(importRaw['skipped']) ?? 0,
    failed: parseExactCount(importRaw['failed']) ?? 0,
    processed: parseExactCount(importRaw['processed']) ?? 0,
    rows: rows,
  );
}

List<CompanyCustomerImportCompanyMatch> parseCompanyCustomerImportMatches(
  Map<dynamic, dynamic> raw,
) {
  if (raw['ok'] != true) {
    throw CompanyCustomerException(
      raw['error']?.toString().trim().isNotEmpty == true
          ? raw['error'].toString()
          : 'import_not_ok',
    );
  }
  final list = raw['matches'];
  if (list is! List) {
    throw const CompanyCustomerException('invalid_payload');
  }
  return [
    for (final item in list)
      if (item is Map)
        CompanyCustomerImportCompanyMatch(
          rowKey: item['row_key']?.toString().trim() ?? '',
          customerId: item['customer_id']?.toString().trim() ?? '',
          field: item['field']?.toString().trim() ?? '',
          displayName: item['display_name']?.toString().trim() ?? '',
          emailMasked: item['email_masked']?.toString().trim() ?? '',
          phoneMasked: item['phone_masked']?.toString().trim() ?? '',
          status: item['status']?.toString().trim() ?? 'active',
        ),
  ].where((item) => item.customerId.isNotEmpty && item.field.isNotEmpty).toList();
}

String newCompanyCustomerImportId([List<int>? bytes]) {
  final random = Random.secure();
  final raw = bytes ?? List<int>.generate(16, (_) => random.nextInt(256));
  final hex = raw.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return 'imp_$hex';
}

CompanyCustomerWrite companyCustomerWriteFromImportJson(Map<dynamic, dynamic> raw) {
  final addresses = <CompanyCustomerAddress>[];
  final rawAddresses = raw['addresses'];
  if (rawAddresses is List) {
    for (final item in rawAddresses) {
      if (item is Map) {
        addresses.add(parseCompanyCustomerAddress(item));
      }
    }
  }
  return CompanyCustomerWrite(
    displayName: raw['display_name']?.toString() ?? '',
    firstName: raw['first_name']?.toString() ?? '',
    lastName: raw['last_name']?.toString() ?? '',
    email: raw['email']?.toString() ?? '',
    phone: raw['phone']?.toString() ?? '',
    countryCallingCode: raw['country_calling_code']?.toString() ?? '',
    locale: raw['locale']?.toString() ?? '',
    companyName: raw['company_name']?.toString() ?? '',
    vatNumber: raw['vat_number']?.toString() ?? '',
    internalNotes: raw['internal_notes']?.toString() ?? '',
    addresses: addresses,
  );
}

CompanyCustomerImportSession? parseCompanyCustomerImportSession(
  Map<dynamic, dynamic> raw,
) {
  final importId = raw['import_id']?.toString().trim() ?? '';
  final companyId = raw['company_id']?.toString().trim() ?? '';
  final expiresAt = DateTime.tryParse(raw['expires_at']?.toString() ?? '');
  if (importId.isEmpty || companyId.isEmpty || expiresAt == null) return null;
  final outcomes = <String, CompanyCustomerImportRowOutcome>{};
  final outcomesRaw = raw['outcomes'];
  if (outcomesRaw is Map) {
    outcomesRaw.forEach((key, value) {
      if (value is! Map) return;
      final mapped = Map<dynamic, dynamic>.from(value);
      mapped['row_key'] = mapped['row_key']?.toString().trim().isNotEmpty == true
          ? mapped['row_key']
          : key.toString();
      if ((mapped['outcome']?.toString() ?? '').isEmpty) return;
      final parsed = parseCompanyCustomerImportRowOutcome(mapped);
      outcomes[parsed.rowKey] = parsed;
    });
  }
  final rows = <CompanyCustomerImportPreparedRow>[];
  final rowsRaw = raw['rows'];
  if (rowsRaw is List) {
    for (final item in rowsRaw) {
      if (item is! Map) continue;
      final map = Map<dynamic, dynamic>.from(item);
      final rowKey = map['row_key']?.toString().trim() ?? '';
      if (rowKey.isEmpty) continue;
      final customerRaw = map['customer'];
      rows.add(
        CompanyCustomerImportPreparedRow(
          rowKey: rowKey,
          sourceIndex: parseExactCount(map['source_index']) ?? 0,
          write: customerRaw is Map
              ? companyCustomerWriteFromImportJson(customerRaw)
              : const CompanyCustomerWrite(),
          fieldErrors: <String, String>{
            if (map['field_errors'] is Map)
              for (final entry in Map<dynamic, dynamic>.from(map['field_errors']).entries)
                if (entry.key.toString().trim().isNotEmpty)
                  entry.key.toString(): entry.value.toString(),
          },
          inFileDupSources: const <int>[],
          companyMatches: const <CompanyCustomerImportCompanyMatch>[],
          selected: map['selected'] != false,
          decision: map['decision']?.toString() == 'skip'
              ? CompanyCustomerImportDecision.skip
              : CompanyCustomerImportDecision.create,
        ),
      );
    }
  }
  return CompanyCustomerImportSession(
    importId: importId,
    companyId: companyId,
    expiresAt: expiresAt.toUtc(),
    rows: rows,
    outcomes: outcomes,
    defaultCallingCode: raw['default_calling_code']?.toString() ?? '',
    confirmedPartial: raw['confirmed_partial'] == true,
    fingerprint: parseCompanyCustomerImportFileFingerprint(raw['fingerprint']),
    mappings: [
      if (raw['mappings'] is List)
        for (final item in raw['mappings'] as List) item.toString(),
    ],
  );
}

enum CompanyCustomerImportFileMatch { ok, fileMismatch, mappingMismatch }

CompanyCustomerImportFileMatch matchCompanyCustomerImportFile({
  required CompanyCustomerImportFileFingerprint fingerprint,
  required CompanyCustomerImportPickedFile file,
  required CompanyCustomerImportTable table,
  required List<String> mappings,
}) {
  if (fingerprint.fileName != file.name.trim() ||
      fingerprint.byteLength != file.bytes.length ||
      fingerprint.headerSignature !=
          companyCustomerImportHeaderSignature(table.headers)) {
    return CompanyCustomerImportFileMatch.fileMismatch;
  }
  if (fingerprint.mappingSignature !=
      companyCustomerImportMappingSignature(mappings)) {
    return CompanyCustomerImportFileMatch.mappingMismatch;
  }
  return CompanyCustomerImportFileMatch.ok;
}
