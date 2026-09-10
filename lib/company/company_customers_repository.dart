// COMPANY-CUSTOMER-OPS-P0A
//
// Company-scoped customer repository. Uses only Worker-issued cursors and
// never stores tokens.

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customers_http.dart';
import 'package:fluxidi_tracking/company_session_store.dart';

typedef CompanyCustomerHeaders = Future<Map<String, String>> Function();
typedef CompanyCustomerListTransport =
    Future<Map<String, dynamic>> Function({
      required String path,
      required Map<String, String> query,
      required CompanyCustomerHeaders headers,
    });
typedef CompanyCustomerSendTransport =
    Future<Map<String, dynamic>> Function({
      required String method,
      required String path,
      required Map<String, String> query,
      required Map<String, dynamic> body,
      required CompanyCustomerHeaders headers,
      String? idempotencyKey,
    });

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

class CompanyCustomersRepository {
  CompanyCustomersRepository({
    CompanyCustomerListTransport? listTransport,
    CompanyCustomerSendTransport? sendTransport,
    CompanyCustomerHeaders? headers,
    Map<String, String>? scopeQuery,
  }) : _listTransport = listTransport ?? companyCustomersHttpGet,
       _sendTransport = sendTransport ?? companyCustomersHttpSend,
       _headers = headers ?? resolveCompanyCustomerHeaders,
       _scopeQuery = scopeQuery;

  final CompanyCustomerListTransport _listTransport;
  final CompanyCustomerSendTransport _sendTransport;
  final CompanyCustomerHeaders _headers;
  final Map<String, String>? _scopeQuery;

  Map<String, String> _scope() {
    final scope = _scopeQuery ?? resolveCompanyCustomerScopeQuery();
    if (scope == null || scope.isEmpty) {
      throw const CompanyCustomerException('missing_tenant_scope');
    }
    return scope;
  }

  Future<CompanyCustomerListPage> list({
    String status = 'active',
    String query = '',
    String cursor = '',
  }) async {
    final decoded = await _listTransport(
      path: kCompanyCustomersPath,
      query: buildCompanyCustomerListQuery(
        scopeQuery: _scope(),
        status: status,
        query: query,
        cursor: cursor,
      ),
      headers: _headers,
    );
    return parseCompanyCustomerListPage(decoded);
  }

  Future<CompanyCustomer> getById(String customerId) async {
    final id = customerId.trim();
    if (id.isEmpty) {
      throw const CompanyCustomerException('not_found');
    }
    final decoded = await _listTransport(
      path: '$kCompanyCustomersPath/${Uri.encodeComponent(id)}',
      query: _scope(),
      headers: _headers,
    );
    return parseCompanyCustomerEnvelope(decoded);
  }

  Future<CompanyCustomerMutationResult> create(
    CompanyCustomerWrite write, {
    String? idempotencyKey,
  }) async {
    final fields = validateCompanyCustomerWrite(write);
    if (fields.isNotEmpty) {
      throw CompanyCustomerException('invalid_customer', fields: fields);
    }
    final decoded = await _sendTransport(
      method: 'POST',
      path: kCompanyCustomersPath,
      query: _scope(),
      body: {...write.toJson(), ..._scope()},
      headers: _headers,
      idempotencyKey: idempotencyKey,
    );
    return parseCompanyCustomerMutation(decoded);
  }

  Future<CompanyCustomer> update(
    String customerId,
    CompanyCustomerWrite write, {
    required int revision,
  }) async {
    final fields = validateCompanyCustomerWrite(write);
    if (fields.isNotEmpty) {
      throw CompanyCustomerException('invalid_customer', fields: fields);
    }
    final id = customerId.trim();
    final decoded = await _sendTransport(
      method: 'PATCH',
      path: '$kCompanyCustomersPath/${Uri.encodeComponent(id)}',
      query: _scope(),
      body: {...write.toJson(revision: revision), ..._scope()},
      headers: _headers,
    );
    return parseCompanyCustomerEnvelope(decoded);
  }

  Future<CompanyCustomer> archive(
    String customerId, {
    String? idempotencyKey,
  }) async {
    return _statusAction(customerId, 'archive', idempotencyKey: idempotencyKey);
  }

  Future<CompanyCustomer> restore(
    String customerId, {
    String? idempotencyKey,
  }) async {
    return _statusAction(customerId, 'restore', idempotencyKey: idempotencyKey);
  }

  Future<CompanyCustomer> _statusAction(
    String customerId,
    String action, {
    String? idempotencyKey,
  }) async {
    final id = customerId.trim();
    final decoded = await _sendTransport(
      method: 'POST',
      path: '$kCompanyCustomersPath/${Uri.encodeComponent(id)}/$action',
      query: _scope(),
      body: _scope(),
      headers: _headers,
      idempotencyKey: idempotencyKey,
    );
    return parseCompanyCustomerEnvelope(decoded);
  }
}
