// COMPANY-CUSTOMER-OPS-P0B — local resume metadata only. No raw files.

import 'dart:convert';
import 'dart:io';

import 'package:fluxidi_tracking/company/company_customer_import_models.dart';
import 'package:path_provider/path_provider.dart';

export 'package:fluxidi_tracking/company/company_customer_import_session_core.dart';

import 'package:fluxidi_tracking/company/company_customer_import_session_core.dart';

class DirectoryCompanyCustomerImportSessionStore
    implements CompanyCustomerImportSessionStore {
  DirectoryCompanyCustomerImportSessionStore({
    Future<Directory> Function()? directory,
  }) : _directory = directory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _fileFor(String companyId) async {
    final safe = companyId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final dir = await _directory();
    return File('${dir.path}/company_customer_import_$safe.json');
  }

  @override
  Future<CompanyCustomerImportSession?> load(String companyId) async {
    try {
      final file = await _fileFor(companyId);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final session = parseCompanyCustomerImportSession(decoded);
      if (session == null || session.companyId != companyId || session.isExpired) {
        await clear(companyId);
        return null;
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(CompanyCustomerImportSession session) async {
    if (session.isExpired) {
      await clear(session.companyId);
      return;
    }
    final file = await _fileFor(session.companyId);
    await file.writeAsString(jsonEncode(session.toJson()));
  }

  @override
  Future<void> clear(String companyId) async {
    try {
      final file = await _fileFor(companyId);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
