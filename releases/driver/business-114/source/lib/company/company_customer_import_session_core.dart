// COMPANY-CUSTOMER-OPS-P0B — session store without dart:io.

import 'package:fluxidi_tracking/company/company_customer_import_models.dart';

abstract class CompanyCustomerImportSessionStore {
  Future<CompanyCustomerImportSession?> load(String companyId);
  Future<void> save(CompanyCustomerImportSession session);
  Future<void> clear(String companyId);
}

class MemoryCompanyCustomerImportSessionStore
    implements CompanyCustomerImportSessionStore {
  CompanyCustomerImportSession? _session;

  @override
  Future<CompanyCustomerImportSession?> load(String companyId) async {
    final session = _session;
    if (session == null || session.companyId != companyId) return null;
    if (session.isExpired) {
      _session = null;
      return null;
    }
    return session;
  }

  @override
  Future<void> save(CompanyCustomerImportSession session) async {
    if (session.isExpired) {
      _session = null;
      return;
    }
    _session = session;
  }

  @override
  Future<void> clear(String companyId) async {
    if (_session?.companyId == companyId) _session = null;
  }
}
