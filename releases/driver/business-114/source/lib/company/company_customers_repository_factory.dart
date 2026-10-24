// COMPANY-CUSTOMER-OPS-P0 — default native repository binding.

import 'package:fluxidi_tracking/company/company_customer_import_session.dart';
import 'package:fluxidi_tracking/company/company_customers_http.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';
import 'package:fluxidi_tracking/company/company_customers_scope_io.dart';

CompanyCustomersRepository createCompanyCustomersRepository() {
  return CompanyCustomersRepository(
    listTransport: companyCustomersHttpGet,
    sendTransport: companyCustomersHttpSend,
    headers: resolveCompanyCustomerHeaders,
    scopeResolver: resolveCompanyCustomerScopeQuery,
  );
}

CompanyCustomerImportSessionStore createCompanyCustomerImportSessionStore() {
  return DirectoryCompanyCustomerImportSessionStore();
}
