import 'package:fluxidi_tracking/company/company_customers_repository_factory_web.dart';

Map<String, String>? resolveCompanyAgendaScopeQuery() {
  final id = resolveCompanyOpsLocalSession().companyId.trim();
  if (id.isEmpty) return null;
  return <String, String>{
    'tenant_id': id,
    'company_id': id,
    'tenantId': id,
    'companyId': id,
  };
}

Future<Map<String, String>> resolveCompanyAgendaHeaders() async {
  final session = resolveCompanyOpsLocalSession();
  return <String, String>{
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${session.sessionToken}',
  };
}
