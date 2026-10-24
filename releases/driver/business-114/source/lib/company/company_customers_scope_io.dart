// COMPANY-CUSTOMER-OPS-P0 — IO-only company session scope.

import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/app_config.dart';

Map<String, String>? resolveCompanyCustomerScopeQuery() {
  final profileId = companyProfileNotifier.value?.companyId.trim() ?? '';
  final sessionId = activeCompanySessionNotifier.value?.companyId.trim() ?? '';
  if (profileId.isEmpty || sessionId.isEmpty || profileId != sessionId) {
    return null;
  }
  return <String, String>{
    'tenant_id': sessionId,
    'company_id': sessionId,
    'tenantId': sessionId,
    'companyId': sessionId,
  };
}

Future<Map<String, String>> resolveCompanyCustomerHeaders() async {
  final auth = await resolveCompanyOwnerAuthHeaders();
  return auth.headers;
}
