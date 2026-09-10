// COMPANY-CUSTOMER-OPS-P0B — XLSX read without executing macros or formulas.

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:fluxidi_tracking/company/company_customer_import_models.dart';

int unpackedCompanyCustomerXlsxSize(Uint8List bytes) {
  late final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: false);
  } catch (_) {
    throw const CompanyCustomerImportException('unreadable');
  }
  var total = 0;
  for (final file in archive) {
    total += file.size;
    if (total > kCompanyCustomerImportMaxXlsxUnpackedBytes) {
      throw const CompanyCustomerImportException('limit_xlsx');
    }
  }
  return total;
}

String companyCustomerXlsxCellText(CellValue? value) {
  if (value == null) return '';
  if (value is FormulaCellValue) {
    throw const CompanyCustomerImportException('formula');
  }
  if (value is TextCellValue) return value.toString();
  if (value is IntCellValue) return '${value.value}';
  if (value is DoubleCellValue) {
    final number = value.value;
    if (number.isNaN || number.isInfinite) {
      throw const CompanyCustomerImportException('unreadable');
    }
    if (number == number.roundToDouble() && number.abs() < 1e15) {
      return '${number.toInt()}';
    }
    throw const CompanyCustomerImportException('unreadable');
  }
  if (value is BoolCellValue) return value.value ? 'true' : 'false';
  if (value is DateCellValue) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
  throw const CompanyCustomerImportException('unreadable');
}

CompanyCustomerImportTable parseCompanyCustomerXlsx({
  required Uint8List bytes,
  required String fileName,
  String? sheetName,
  int headerRowIndex = 0,
}) {
  if (bytes.length > kCompanyCustomerImportMaxFileBytes) {
    throw const CompanyCustomerImportException('limit_file');
  }
  unpackedCompanyCustomerXlsxSize(bytes);
  late final Excel excel;
  try {
    excel = Excel.decodeBytes(bytes);
  } catch (_) {
    throw const CompanyCustomerImportException('unreadable');
  }
  final names = excel.tables.keys.toList();
  if (names.isEmpty) {
    throw const CompanyCustomerImportException('unreadable');
  }
  final selected = (sheetName ?? '').trim().isEmpty ? names.first : sheetName!.trim();
  final sheet = excel.tables[selected];
  if (sheet == null) {
    throw const CompanyCustomerImportException('unreadable');
  }
  if (headerRowIndex < 0 || headerRowIndex >= sheet.maxRows) {
    throw const CompanyCustomerImportException('unreadable');
  }
  if (sheet.maxRows - headerRowIndex - 1 > kCompanyCustomerImportMaxRows) {
    throw const CompanyCustomerImportException('limit_rows');
  }
  final rows = <List<String>>[];
  List<String>? headers;
  for (var r = headerRowIndex; r < sheet.maxRows; r += 1) {
    final row = sheet.rows.length > r ? sheet.rows[r] : const <Data?>[];
    final cells = <String>[
      for (final cell in row) companyCustomerXlsxCellText(cell?.value),
    ];
    if (r == headerRowIndex) {
      headers = cells;
      continue;
    }
    if (cells.every((cell) => cell.trim().isEmpty)) continue;
    rows.add(cells);
  }
  if (headers == null || headers.every((cell) => cell.trim().isEmpty)) {
    throw const CompanyCustomerImportException('unreadable');
  }
  if (rows.length > kCompanyCustomerImportMaxRows) {
    throw const CompanyCustomerImportException('limit_rows');
  }
  return CompanyCustomerImportTable(
    kind: CompanyCustomerImportKind.xlsx,
    fileName: fileName,
    headers: headers,
    rows: rows,
    sheetNames: names,
    selectedSheet: selected,
    headerRowIndex: headerRowIndex,
    sourceLabels: [
      for (var i = 0; i < rows.length; i += 1) headerRowIndex + i + 2,
    ],
  );
}
