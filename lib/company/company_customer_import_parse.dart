// COMPANY-CUSTOMER-OPS-P0B — CSV and vCard readers. No silent truncation.

import 'dart:convert';
import 'dart:typed_data';

import 'package:fluxidi_tracking/company/company_customer_import_models.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';

void assertCompanyCustomerImportFileSize(List<int> bytes) {
  if (bytes.length > kCompanyCustomerImportMaxFileBytes) {
    throw const CompanyCustomerImportException('limit_file');
  }
}

String decodeCompanyCustomerImportText(List<int> bytes) {
  assertCompanyCustomerImportFileSize(bytes);
  try {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3));
    }
    return utf8.decode(bytes);
  } catch (_) {
    throw const CompanyCustomerImportException('unreadable');
  }
}

String detectCsvDelimiter(String text) {
  final sample = _firstCsvProbeLine(text);
  var commas = 0;
  var semicolons = 0;
  var tabs = 0;
  var inQuotes = false;
  for (var i = 0; i < sample.length; i += 1) {
    final char = sample[i];
    if (char == '"') {
      if (inQuotes && i + 1 < sample.length && sample[i + 1] == '"') {
        i += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }
    if (inQuotes) continue;
    if (char == ',') commas += 1;
    if (char == ';') semicolons += 1;
    if (char == '\t') tabs += 1;
  }
  if (tabs >= commas && tabs >= semicolons && tabs > 0) return '\t';
  if (semicolons > commas) return ';';
  return ',';
}

String _firstCsvProbeLine(String text) {
  var inQuotes = false;
  final out = StringBuffer();
  for (var i = 0; i < text.length; i += 1) {
    final char = text[i];
    if (char == '"') {
      if (inQuotes && i + 1 < text.length && text[i + 1] == '"') {
        out.write('"');
        i += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }
    if (!inQuotes && (char == '\n' || char == '\r')) break;
    out.write(char);
  }
  return out.toString();
}

List<List<String>> parseCsvRecords(String text, {required String delimiter}) {
  final rows = <List<String>>[];
  var field = StringBuffer();
  var row = <String>[];
  var inQuotes = false;
  for (var i = 0; i < text.length; i += 1) {
    final char = text[i];
    if (inQuotes) {
      if (char == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(char);
      }
      continue;
    }
    if (char == '"') {
      inQuotes = true;
      continue;
    }
    if (char == delimiter) {
      row.add(field.toString());
      field = StringBuffer();
      continue;
    }
    if (char == '\r') {
      continue;
    }
    if (char == '\n') {
      row.add(field.toString());
      field = StringBuffer();
      if (row.any((part) => part.trim().isNotEmpty) || rows.isNotEmpty) {
        rows.add(row);
      }
      row = <String>[];
      continue;
    }
    field.write(char);
  }
  if (inQuotes) {
    throw const CompanyCustomerImportException('unreadable');
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    if (row.any((part) => part.trim().isNotEmpty)) rows.add(row);
  }
  return rows;
}

CompanyCustomerImportTable parseCompanyCustomerCsv({
  required List<int> bytes,
  required String fileName,
}) {
  final text = decodeCompanyCustomerImportText(bytes);
  final delimiter = detectCsvDelimiter(text);
  final records = parseCsvRecords(text, delimiter: delimiter);
  if (records.isEmpty) {
    throw const CompanyCustomerImportException('unreadable');
  }
  if (records.length - 1 > kCompanyCustomerImportMaxRows) {
    throw const CompanyCustomerImportException('limit_rows');
  }
  final headers = records.first;
  final rows = records.skip(1).toList();
  return CompanyCustomerImportTable(
    kind: CompanyCustomerImportKind.csv,
    fileName: fileName,
    headers: headers,
    rows: rows,
    sourceLabels: [for (var i = 0; i < rows.length; i += 1) i + 2],
  );
}

String _unfoldVcard(String text) {
  return text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'\n[ \t]'), '');
}

class _VcardLine {
  const _VcardLine(this.name, this.params, this.value);
  final String name;
  final Map<String, String> params;
  final String value;
}

_VcardLine? _parseVcardLine(String raw) {
  final colon = raw.indexOf(':');
  if (colon <= 0) return null;
  final left = raw.substring(0, colon);
  final value = raw.substring(colon + 1);
  final parts = left.split(';');
  final name = parts.first.trim().toUpperCase();
  if (name.contains('.')) {
    final group = name.split('.');
    return _VcardLine(group.last, _vcardParams(parts.skip(1)), value);
  }
  return _VcardLine(name, _vcardParams(parts.skip(1)), value);
}

Map<String, String> _vcardParams(Iterable<String> parts) {
  final params = <String, String>{};
  for (final part in parts) {
    final eq = part.indexOf('=');
    if (eq <= 0) {
      params[part.trim().toUpperCase()] = '';
      continue;
    }
    params[part.substring(0, eq).trim().toUpperCase()] =
        part.substring(eq + 1).trim();
  }
  return params;
}

String _unescapeVcard(String value) {
  return value
      .replaceAll(r'\,', ',')
      .replaceAll(r'\;', ';')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\N', '\n');
}

String _stripTelUri(String value) {
  final trimmed = value.trim();
  if (trimmed.toLowerCase().startsWith('tel:')) {
    return trimmed.substring(4);
  }
  return trimmed;
}

CompanyCustomerImportTable parseCompanyCustomerVcard({
  required List<int> bytes,
  required String fileName,
}) {
  final text = _unfoldVcard(decodeCompanyCustomerImportText(bytes));
  final cards = <List<_VcardLine>>[];
  var current = <_VcardLine>[];
  var inCard = false;
  var version = '';
  for (final raw in text.split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) continue;
    final upper = line.trim().toUpperCase();
    if (upper == 'BEGIN:VCARD') {
      inCard = true;
      current = <_VcardLine>[];
      version = '';
      continue;
    }
    if (upper == 'END:VCARD') {
      if (inCard) cards.add(current);
      inCard = false;
      continue;
    }
    if (!inCard) continue;
    final parsed = _parseVcardLine(line);
    if (parsed == null) continue;
    if (parsed.name == 'VERSION') {
      version = parsed.value.trim();
      if (version.isNotEmpty && version != '3.0' && version != '4.0') {
        throw const CompanyCustomerImportException('unsupported');
      }
    }
    current.add(parsed);
  }
  if (inCard) {
    throw const CompanyCustomerImportException('unreadable');
  }
  if (cards.length > kCompanyCustomerImportMaxRows) {
    throw const CompanyCustomerImportException('limit_rows');
  }
  if (cards.isEmpty) {
    throw const CompanyCustomerImportException('unreadable');
  }
  const headers = <String>[
    'FN',
    'First name',
    'Last name',
    'Email',
    'Phone',
    'Company',
    'Notes',
    'Address',
    'City',
    'Postal code',
    'Country',
    'Address 2',
    'City 2',
    'Country 2',
    'Postal code 2',
    'Address type',
    'Address type 2',
  ];
  final rows = <List<String>>[];
  final labels = <int>[];
  for (var i = 0; i < cards.length; i += 1) {
    final card = cards[i];
    String fn = '';
    String first = '';
    String last = '';
    String email = '';
    String phone = '';
    String org = '';
    String note = '';
    final addresses = <CompanyCustomerAddress>[];
    for (final line in card) {
      final value = _unescapeVcard(line.value);
      switch (line.name) {
        case 'FN':
          if (fn.isEmpty) fn = value.trim();
        case 'N':
          final parts = value.split(';');
          if (last.isEmpty && parts.isNotEmpty) last = parts[0].trim();
          if (first.isEmpty && parts.length > 1) first = parts[1].trim();
        case 'EMAIL':
          if (email.isEmpty) email = value.trim();
        case 'TEL':
          if (phone.isEmpty) phone = _stripTelUri(value);
        case 'ORG':
          if (org.isEmpty) org = value.split(';').first.trim();
        case 'NOTE':
          if (note.isEmpty) note = value.trim();
        case 'ADR':
          final parts = value.split(';');
          addresses.add(
            CompanyCustomerAddress(
              type: (line.params['TYPE'] ?? 'other').split(',').first.toLowerCase(),
              line1: parts.length > 2 ? parts[2].trim() : '',
              city: parts.length > 3 ? parts[3].trim() : '',
              postalCode: parts.length > 5 ? parts[5].trim() : '',
              countryCode: parts.length > 6 ? parts[6].trim() : '',
            ),
          );
      }
    }
    final firstAddress = addresses.isNotEmpty
        ? addresses.first
        : const CompanyCustomerAddress();
    final secondAddress = addresses.length > 1
        ? addresses[1]
        : const CompanyCustomerAddress();
    rows.add(<String>[
      fn,
      first,
      last,
      email,
      phone,
      org,
      note,
      firstAddress.line1,
      firstAddress.city,
      firstAddress.postalCode,
      firstAddress.countryCode,
      secondAddress.line1,
      secondAddress.city,
      secondAddress.countryCode,
      secondAddress.postalCode,
      firstAddress.type,
      secondAddress.type,
    ]);
    labels.add(i + 1);
  }
  return CompanyCustomerImportTable(
    kind: CompanyCustomerImportKind.vcard,
    fileName: fileName,
    headers: headers,
    rows: rows,
    sourceLabels: labels,
  );
}

CompanyCustomerImportKind companyCustomerImportKindForName(String name) {
  final lower = name.trim().toLowerCase();
  if (lower.endsWith('.csv') || lower.endsWith('.txt')) {
    return CompanyCustomerImportKind.csv;
  }
  if (lower.endsWith('.xlsx')) {
    return CompanyCustomerImportKind.xlsx;
  }
  if (lower.endsWith('.vcf') || lower.endsWith('.vcard')) {
    return CompanyCustomerImportKind.vcard;
  }
  throw const CompanyCustomerImportException('unsupported');
}

CompanyCustomerImportTable parseCompanyCustomerImportBytes({
  required List<int> bytes,
  required String fileName,
  String? sheetName,
  int headerRowIndex = 0,
  CompanyCustomerImportTable Function({
    required Uint8List bytes,
    required String fileName,
    String? sheetName,
    int headerRowIndex,
  })? xlsxParser,
}) {
  final kind = companyCustomerImportKindForName(fileName);
  switch (kind) {
    case CompanyCustomerImportKind.csv:
      return parseCompanyCustomerCsv(bytes: bytes, fileName: fileName);
    case CompanyCustomerImportKind.vcard:
      return parseCompanyCustomerVcard(bytes: bytes, fileName: fileName);
    case CompanyCustomerImportKind.xlsx:
      if (xlsxParser == null) {
        throw const CompanyCustomerImportException('unsupported');
      }
      return xlsxParser(
        bytes: Uint8List.fromList(bytes),
        fileName: fileName,
        sheetName: sheetName,
        headerRowIndex: headerRowIndex,
      );
  }
}
