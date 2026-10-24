import 'dart:convert';
import 'dart:io';
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
    expect(prepared[0].write.addresses, hasLength(2));
    expect(prepared[0].write.addresses[0].line1, 'Kerkstraat 1');
    expect(prepared[0].write.addresses[1].line1, 'Office 2');
    expect(prepared[0].write.firstName, 'Anna');
    expect(prepared[0].write.lastName, 'Berg');
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

  test('exact Fluxidi_demo_100_klanten.csv stays valid without phones', () {
    final bytes = File(
      'test/company/fixtures/Fluxidi_demo_100_klanten.csv',
    ).readAsBytesSync();
    final table = parseCompanyCustomerImportBytes(
      bytes: bytes,
      fileName: 'Fluxidi_demo_100_klanten.csv',
    );
    expect(table.rows, hasLength(100));
    expect(table.headers, <String>[
      'display_name',
      'email',
      'phone',
      'company_name',
      'customer_type',
    ]);
    final mappings = suggestCompanyCustomerImportMappings(table.headers);
    expect(mappings, <String>[
      'display_name',
      'email',
      'phone',
      'company_name',
      'skip',
    ]);
    final prepared = prepareCompanyCustomerImportRows(
      table: table,
      mappings: mappings,
    );
    expect(prepared, hasLength(100));
    expect(prepared.every((row) => row.isValid), isTrue);
    expect(prepared.every((row) => row.selected), isTrue);
    expect(prepared.every((row) => row.write.phone.isEmpty), isTrue);
    expect(prepared.every((row) => row.write.email.endsWith('@example.com')), isTrue);
    expect(
      prepared.where((row) => row.write.companyName.isEmpty).length,
      50,
    );
    expect(
      prepared.where((row) => row.write.companyName.isNotEmpty).length,
      50,
    );
    expect(prepared.first.sourceIndex, 2);
    expect(prepared.last.sourceIndex, 101);
  });

  test('full-field synthetic csv maps every supported field and keeps unknown columns', () {
    final bytes = File(
      'test/company/fixtures/Fluxidi_demo_klanten_volledige_velden.csv',
    ).readAsBytesSync();
    final table = parseCompanyCustomerImportBytes(
      bytes: bytes,
      fileName: 'Fluxidi_demo_klanten_volledige_velden.csv',
    );
    expect(table.rows, hasLength(5));
    final mappings = suggestCompanyCustomerImportMappings(table.headers);
    expect(
      companyCustomerImportSkippedHeaders(
        headers: table.headers,
        mappings: mappings,
      ),
      <String>['legacy_crm_id', 'customer_type'],
    );
    expect(mappings.contains('skip'), isTrue);
    expect(mappings.contains('first_name'), isTrue);
    expect(mappings.contains('vat_number'), isTrue);
    expect(mappings.contains('address_house_number'), isTrue);
    expect(mappings.contains('address2_line1'), isTrue);
    expect(mappings.contains('address2_notes'), isTrue);
    final prepared = prepareCompanyCustomerImportRows(
      table: table,
      mappings: mappings,
    );
    expect(prepared, hasLength(5));

    final private = prepared[0];
    expect(private.isValid, isTrue);
    expect(private.write.displayName, 'José Álvarez');
    expect(private.write.firstName, 'José');
    expect(private.write.lastName, 'Álvarez');
    expect(private.write.phone, '+34600111222');
    expect(private.write.countryCallingCode, '34');
    expect(private.write.locale, 'es');
    expect(private.write.companyName, isEmpty);
    expect(private.write.internalNotes, contains('niet op de offerte'));
    expect(private.write.preferences.preferredLocale, 'es');
    expect(private.write.addresses, hasLength(2));
    expect(private.write.addresses[0].line1, 'Calle Mayor 7');
    expect(private.write.addresses[0].line2, 'Ático');
    expect(private.write.addresses[1].type, 'work');

    final business = prepared[1];
    expect(business.isValid, isTrue);
    expect(business.write.companyName, 'DEMO Wolkenhof Logistiek BV');
    expect(business.write.firstName, 'Lina');
    expect(business.write.lastName, 'Mwangi');
    expect(business.write.displayName, 'Lina Mwangi');
    expect(business.write.vatNumber, 'BE0123456749');
    expect(business.write.phone, '0470123456');
    expect(business.write.addresses[0].line2, 'Bus 012');
    expect(business.write.addresses[1].type, 'billing');

    final invalidVat = prepared[2];
    expect(invalidVat.isValid, isFalse);
    expect(invalidVat.fieldErrors['vat_number'], 'invalid');
    expect(invalidVat.selected, isFalse);
    expect(invalidVat.write.vatNumber, 'BE12');

    final displayOnly = prepared[3];
    expect(displayOnly.isValid, isTrue);
    expect(displayOnly.write.displayName, "Dr. Jean-Luc O'Neill");
    expect(displayOnly.write.firstName, isEmpty);
    expect(displayOnly.write.lastName, isEmpty);
    expect(displayOnly.write.phone, '+12025550147');
    expect(displayOnly.write.addresses, hasLength(2));

    final leadingZeros = prepared[4];
    expect(leadingZeros.isValid, isTrue);
    expect(leadingZeros.write.phone, '0470111222');
    expect(leadingZeros.write.addresses[0].postalCode, '04000');
    expect(leadingZeros.write.firstName, 'Marie-Claire');
  });
}
