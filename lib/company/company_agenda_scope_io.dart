import 'package:fluxidi_tracking/company/company_customers_scope_io.dart';

Map<String, String>? resolveCompanyAgendaScopeQuery() {
  return resolveCompanyCustomerScopeQuery();
}

Future<Map<String, String>> resolveCompanyAgendaHeaders() {
  return resolveCompanyCustomerHeaders();
}
