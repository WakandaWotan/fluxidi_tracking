import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_customer_import_models.dart';
import 'package:fluxidi_tracking/company/company_customer_import_parse.dart';
import 'package:fluxidi_tracking/company/company_customer_import_xlsx.dart';

void main() {
  test('csv keeps accents phones quotes and embedded newlines', () {
    const csv = '\uFEFFNaam;E-mail;Telefoon;Adres\n'
        '"José Álvarez";"jose@example.test";"+34600111222";"Calle 1\nMadrid"\n'
        'Marie;"marie@example.test";"0470111222";""\n';
    final table = parseCompanyCustomerCsv(
      bytes: utf8.encode(csv),
      fileName: 'contacts.csv',
    );
    expect(table.rows, hasLength(2));
    expect(table.headers.first, 'Naam');
    expect(table.rows[0][0], 'José Álvarez');
    expect(table.rows[0][2], '+34600111222');
    expect(table.rows[0][3], contains('Madrid'));
    expect(table.rows[1][2], '0470111222');
    final mappings = suggestCompanyCustomerImportMappings(table.headers);
    expect(mappings, containsAll(<String>['display_name', 'email', 'phone']));
    final prepared = prepareCompanyCustomerImportRows(
      table: table,
      mappings: mappings,
    );
    expect(prepared[0].isValid, isTrue);
    expect(prepared[1].write.phone, '0470111222');
  });

  test('tab csv and empty required fields stay visible', () {
    const csv = 'Name\tEmail\nAda\t\n\tada@example.test\n';
    final table = parseCompanyCustomerCsv(
      bytes: utf8.encode(csv),
      fileName: 'x.csv',
    );
    final prepared = prepareCompanyCustomerImportRows(
      table: table,
      mappings: suggestCompanyCustomerImportMappings(table.headers),
    );
    expect(prepared[0].fieldErrors.containsKey('contact'), isTrue);
    expect(prepared[1].fieldErrors.containsKey('display_name'), isTrue);
    expect(prepared.where((row) => row.selected).length, 0);
  });

  test('in-file duplicate emails are flagged without merging', () {
    const csv = 'Name,Email\nOne,same@example.test\nTwo,same@example.test\n';
    final table = parseCompanyCustomerCsv(
      bytes: utf8.encode(csv),
      fileName: 'dups.csv',
    );
    final prepared = prepareCompanyCustomerImportRows(
      table: table,
      mappings: suggestCompanyCustomerImportMappings(table.headers),
    );
    expect(prepared[0].inFileDupSources, <int>[3]);
    expect(prepared[1].inFileDupSources, <int>[2]);
  });

  test('vcard 3.0 and 4.0 keep folded lines and extra addresses', () {
    const vcf = 'BEGIN:VCARD\n'
        'VERSION:3.0\n'
        'FN:Anna \n Berg\n'
        'N:Berg;Anna;;;\n'
        'EMAIL:anna@example.test\n'
        'TEL;TYPE=CELL:+32470000011\n'
        'ADR;TYPE=HOME:;;Kerkstraat 1;Gent;;9000;BE\n'
        'ADR;TYPE=WORK:;;Office 2;Antwerp;;2000;BE\n'
        'END:VCARD\n'
        'BEGIN:VCARD\n'
        'VERSION:4.0\n'
        'FN:Luis\n'
        'TEL:tel:+34600999888\n'
        'EMAIL:luis@example.test\n'
        'END:VCARD\n';
    final table = parseCompanyCustomerVcard(
      bytes: utf8.encode(vcf),
      fileName: 'people.vcf',
    );
    expect(table.rows, hasLength(2));
    expect(table.rows[0][0], 'Anna Berg');
    expect(table.rows[0][4], '+32470000011');
    expect(table.rows[0][7], 'Kerkstraat 1');
    expect(table.rows[0][11], 'Office 2');
    expect(table.rows[1][4], '+34600999888');
    final prepared = prepareCompanyCustomerImportRows(
      table: table,
      mappings: suggestCompanyCustomerImportMappings(table.headers),
    );
    expect(prepared.every((row) => row.isValid), isTrue);
    expect(prepared[0].write.addresses, hasLength(1));
  });

  test('unsupported vcard version is rejected', () {
    expect(
      () => parseCompanyCustomerVcard(
        bytes: utf8.encode('BEGIN:VCARD\nVERSION:2.1\nFN:Old\nEND:VCARD\n'),
        fileName: 'old.vcf',
      ),
      throwsA(
        isA<CompanyCustomerImportException>().having(
          (error) => error.code,
          'code',
          'unsupported',
        ),
      ),
    );
  });

  test('xlsx reads a chosen sheet and rejects formulas', () {
    final excel = Excel.createExcel();
    final sheet = excel['Contacts'];
    sheet.appendRow([
      TextCellValue('Name'),
      TextCellValue('Email'),
    ]);
    sheet.appendRow([
      TextCellValue('José'),
      TextCellValue('jose@example.test'),
    ]);
    final bytes = Uint8List.fromList(excel.encode()!);
    final table = parseCompanyCustomerXlsx(
      bytes: bytes,
      fileName: 'contacts.xlsx',
      sheetName: 'Contacts',
    );
    expect(table.rows.single[0], 'José');
    expect(table.sheetNames, contains('Contacts'));

    final bad = Excel.createExcel();
    final formulas = bad['Sheet1'];
    formulas.appendRow([TextCellValue('Name'), TextCellValue('Email')]);
    formulas
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
        .value = FormulaCellValue('=A1');
    formulas
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1))
        .value = TextCellValue('x@example.test');
    expect(
      () => parseCompanyCustomerXlsx(
        bytes: Uint8List.fromList(bad.encode()!),
        fileName: 'bad.xlsx',
      ),
      throwsA(
        isA<CompanyCustomerImportException>().having(
          (error) => error.code,
          'code',
          'formula',
        ),
      ),
    );
  });

  test('file and row limits fail before import', () {
    expect(
      () => parseCompanyCustomerCsv(
        bytes: List<int>.filled(kCompanyCustomerImportMaxFileBytes + 1, 65),
        fileName: 'huge.csv',
      ),
      throwsA(
        isA<CompanyCustomerImportException>().having(
          (error) => error.code,
          'code',
          'limit_file',
        ),
      ),
    );
    final rows = StringBuffer('Name,Email\n');
    for (var i = 0; i < kCompanyCustomerImportMaxRows + 1; i += 1) {
      rows.writeln('P$i,p$i@example.test');
    }
    expect(
      () => parseCompanyCustomerCsv(
        bytes: utf8.encode(rows.toString()),
        fileName: 'many.csv',
      ),
      throwsA(
        isA<CompanyCustomerImportException>().having(
          (error) => error.code,
          'code',
          'limit_rows',
        ),
      ),
    );
  });

  test('401 synthetic csv rows stay complete and unique', () {
    final buffer = StringBuffer('Name,Email\n');
    for (var i = 1; i <= 401; i += 1) {
      buffer.writeln('Person $i,p$i@p0b.test');
    }
    final table = parseCompanyCustomerCsv(
      bytes: utf8.encode(buffer.toString()),
      fileName: 'four.csv',
    );
    final prepared = prepareCompanyCustomerImportRows(
      table: table,
      mappings: suggestCompanyCustomerImportMappings(table.headers),
    );
    expect(prepared, hasLength(401));
    expect({for (final row in prepared) row.rowKey}, hasLength(401));
    expect(prepared.every((row) => row.isValid), isTrue);
  });

  test('session json roundtrip keeps pending rows without the raw file', () {
    final table = parseCompanyCustomerCsv(
      bytes: utf8.encode('Name,Email\nAda,ada@example.test\n'),
      fileName: 'one.csv',
    );
    final mappings = suggestCompanyCustomerImportMappings(table.headers);
    final rows = prepareCompanyCustomerImportRows(
      table: table,
      mappings: mappings,
    );
    final session = CompanyCustomerImportSession(
      importId: 'imp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      companyId: 'CA',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
      rows: rows,
      outcomes: <String, CompanyCustomerImportRowOutcome>{},
      defaultCallingCode: '',
      mappings: mappings,
      fingerprint: buildCompanyCustomerImportFingerprint(
        file: CompanyCustomerImportPickedFile(
          name: 'one.csv',
          bytes: utf8.encode('Name,Email\nAda,ada@example.test\n'),
        ),
        table: table,
        mappings: mappings,
      ),
    );
    final parsed = parseCompanyCustomerImportSession(session.toJson());
    expect(parsed, isNotNull);
    expect(parsed!.pending, hasLength(1));
    expect(parsed.needsFileRepick, isFalse);
    expect(parsed.rows.first.write.email, 'ada@example.test');
    expect(parsed.fingerprint?.contentSha256, isNotEmpty);
  });

  test('metadata-only session requires the same file and mapping', () {
    final bytes = utf8.encode('Name,Email\nAda,ada@example.test\n');
    final table = parseCompanyCustomerCsv(bytes: bytes, fileName: 'one.csv');
    final mappings = suggestCompanyCustomerImportMappings(table.headers);
    final fingerprint = buildCompanyCustomerImportFingerprint(
      file: CompanyCustomerImportPickedFile(name: 'one.csv', bytes: bytes),
      table: table,
      mappings: mappings,
    );
    final session = CompanyCustomerImportSession(
      importId: 'imp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      companyId: 'CA',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
      rows: const <CompanyCustomerImportPreparedRow>[],
      outcomes: const <String, CompanyCustomerImportRowOutcome>{
        'r1': CompanyCustomerImportRowOutcome(
          rowKey: 'r1',
          outcome: 'created',
          customerId: 'cus_1',
        ),
      },
      defaultCallingCode: '',
      mappings: mappings,
      fingerprint: fingerprint,
    );
    expect(session.needsFileRepick, isTrue);
    expect(
      matchCompanyCustomerImportFile(
        fingerprint: fingerprint,
        file: CompanyCustomerImportPickedFile(name: 'one.csv', bytes: bytes),
        table: table,
        mappings: mappings,
      ),
      CompanyCustomerImportFileMatch.ok,
    );
    expect(
      matchCompanyCustomerImportFile(
        fingerprint: fingerprint,
        file: CompanyCustomerImportPickedFile(name: 'other.csv', bytes: bytes),
        table: table,
        mappings: mappings,
      ),
      CompanyCustomerImportFileMatch.fileMismatch,
    );
    expect(
      matchCompanyCustomerImportFile(
        fingerprint: fingerprint,
        file: CompanyCustomerImportPickedFile(name: 'one.csv', bytes: bytes),
        table: table,
        mappings: <String>['skip', 'email'],
      ),
      CompanyCustomerImportFileMatch.mappingMismatch,
    );
  });

  test('same name size and columns with different content refuse resume', () {
    final original = utf8.encode('Name,Email\nAda,ada@example.test\n');
    final changed = utf8.encode('Name,Email\nAda,ada@examplf.test\n');
    expect(changed.length, original.length);
    final table = parseCompanyCustomerCsv(bytes: original, fileName: 'one.csv');
    final changedTable = parseCompanyCustomerCsv(
      bytes: changed,
      fileName: 'one.csv',
    );
    final mappings = suggestCompanyCustomerImportMappings(table.headers);
    final fingerprint = buildCompanyCustomerImportFingerprint(
      file: CompanyCustomerImportPickedFile(name: 'one.csv', bytes: original),
      table: table,
      mappings: mappings,
    );
    expect(fingerprint.contentSha256, isNotEmpty);
    expect(
      matchCompanyCustomerImportFile(
        fingerprint: fingerprint,
        file: CompanyCustomerImportPickedFile(name: 'one.csv', bytes: changed),
        table: changedTable,
        mappings: mappings,
      ),
      CompanyCustomerImportFileMatch.fileMismatch,
    );
    expect(
      matchCompanyCustomerImportFile(
        fingerprint: CompanyCustomerImportFileFingerprint(
          fileName: 'one.csv',
          byteLength: original.length,
          headerSignature: companyCustomerImportHeaderSignature(table.headers),
          mappingSignature: companyCustomerImportMappingSignature(mappings),
          contentSha256: '',
        ),
        file: CompanyCustomerImportPickedFile(name: 'one.csv', bytes: original),
        table: table,
        mappings: mappings,
      ),
      CompanyCustomerImportFileMatch.fileMismatch,
    );
  });
}
