// COMPANY-CUSTOMER-OPS-P0A
//
// Company-scoped customer repository. Uses only Worker-issued cursors and
// never stores tokens.

import 'package:fluxidi_tracking/company/company_customer_import_models.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_models.dart';

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

class CompanyCustomersRepository {
  Map<String, String> get monthlyInvoiceScope => Map.unmodifiable(_scope());

  Future<Map<String, dynamic>> monthlyInvoice(
    String customerId,
    String action, {
    required String month,
    Map<String, dynamic> body = const {},
    Map<String, String>? expectedScope,
  }) async {
    final scope = Map<String, String>.from(_scope());
    if (expectedScope != null &&
        (scope['tenant_id'] != expectedScope['tenant_id'] ||
            scope['company_id'] != expectedScope['company_id'])) {
      throw const CompanyCustomerException('invoice_scope_changed');
    }
    final mutate = ['issue', 'prepare', 'send'].contains(action);
    final path =
        '$kCompanyCustomersPath/${Uri.encodeComponent(customerId)}/monthly-invoices/${action == 'prepare' ? 'pdf' : action}';
    final result = mutate
        ? await _sendTransport(
            method: 'POST',
            path: path,
            query: scope,
            body: {...body, 'month': month, ...scope},
            headers: _headers,
          )
        : await _listTransport(
            path: path,
            query: {
              ...scope,
              'month': month,
              if (action == 'list') 'cursor': body['cursor']?.toString() ?? '',
            },
            headers: _headers,
          );
    final after = _scope();
    if (after['tenant_id'] != scope['tenant_id'] ||
        after['company_id'] != scope['company_id']) {
      throw const CompanyCustomerException('invoice_scope_changed');
    }
    if (result['ok'] != true)
      throw CompanyCustomerException(
        result['error']?.toString() ?? 'invalid_payload',
      );
    final document = result['document'];
    final snapshot = document is Map ? document['immutable_snapshot'] : null;
    final invoice =
        result['invoice'] ??
        (snapshot is Map ? snapshot['monthly_invoice'] : null);
    if (invoice != null &&
        (invoice is! Map ||
            invoice['tenant_id'] != scope['tenant_id'] ||
            invoice['company_id'] != scope['company_id'] ||
            invoice['customer_id'] != customerId ||
            invoice['month'] != month)) {
      throw const CompanyCustomerException('invoice_scope_mismatch');
    }
    if (invoice is Map) {
      final totals = invoice['totals'];
      final lines = invoice['lines'];
      if (totals is! Map ||
          totals['gross_cents'] is! int ||
          (totals['gross_cents'] as int) < 0 ||
          invoice['currency'] is! String ||
          !RegExp(r'^[A-Z]{3}$').hasMatch(invoice['currency'] as String) ||
          lines is! List ||
          lines.length > 1000 ||
          lines.any(
            (line) =>
                line is! Map ||
                line['gross_cents'] is! int ||
                (line['gross_cents'] as int) < 0 ||
                line['completed_at'] is! String ||
                line['booking_id'] is! String ||
                line['currency'] != invoice['currency'],
          )) {
        throw const CompanyCustomerException('invalid_payload');
      }
    }
    if (action == 'list') {
      final items = result['items'];
      final cursor = result['next_cursor'];
      final monthPattern = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');
      if (items is! List ||
          items.length > 20 ||
          (cursor != null &&
              (cursor is! String || !monthPattern.hasMatch(cursor))) ||
          items.any(
            (item) =>
                item is! Map ||
                item['month'] is! String ||
                !monthPattern.hasMatch(item['month'] as String) ||
                !['preparing', 'issued'].contains(item['state']) ||
                (item['state'] == 'issued' &&
                    (item['gross_cents'] is! int ||
                        item['currency'] is! String ||
                        item['document_number'] is! String)),
          )) {
        throw const CompanyCustomerException('invalid_payload');
      }
    }
    return result;
  }

  CompanyCustomersRepository({
    required CompanyCustomerListTransport listTransport,
    required CompanyCustomerSendTransport sendTransport,
    CompanyCustomerHeaders? headers,
    Map<String, String>? scopeQuery,
    Map<String, String>? Function()? scopeResolver,
  }) : _listTransport = listTransport,
       _sendTransport = sendTransport,
       _headers = headers ?? _emptyHeaders,
       _scopeQuery = scopeQuery,
       _scopeResolver = scopeResolver;

  final CompanyCustomerListTransport _listTransport;
  final CompanyCustomerSendTransport _sendTransport;
  final CompanyCustomerHeaders _headers;
  final Map<String, String>? _scopeQuery;
  final Map<String, String>? Function()? _scopeResolver;

  static Future<Map<String, String>> _emptyHeaders() async =>
      const <String, String>{};

  Map<String, String> _scope() {
    final scope = _scopeQuery ?? _scopeResolver?.call();
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

  String companyScopeId() => _scope()['company_id'] ?? '';

  Future<List<CompanyCustomerImportCompanyMatch>> lookupImportContacts({
    required String importId,
    required List<Map<String, String>> contacts,
  }) async {
    final decoded = await _sendTransport(
      method: 'POST',
      path:
          '$kCompanyCustomerImportPathPrefix/${Uri.encodeComponent(importId)}/lookups',
      query: _scope(),
      body: <String, dynamic>{
        ..._scope(),
        'contacts': contacts,
      },
      headers: _headers,
    );
    return parseCompanyCustomerImportMatches(decoded);
  }

  Future<CompanyCustomerImportBatchResult> importBatch({
    required String importId,
    required List<Map<String, dynamic>> rows,
  }) async {
    final decoded = await _sendTransport(
      method: 'POST',
      path:
          '$kCompanyCustomerImportPathPrefix/${Uri.encodeComponent(importId)}/batches',
      query: _scope(),
      body: <String, dynamic>{
        ..._scope(),
        'rows': rows,
      },
      headers: _headers,
    );
    return parseCompanyCustomerImportBatch(decoded);
  }

  Future<List<CompanyCustomerQuote>> listQuotes(String customerId) async {
    final decoded = await _listTransport(
      path:
          '$kCompanyCustomersPath/${Uri.encodeComponent(customerId.trim())}$kCompanyCustomerQuotesPathSuffix',
      query: _scope(),
      headers: _headers,
    );
    return parseCompanyCustomerQuotes(decoded);
  }

  Future<CompanyCustomerQuote> createQuote(
    String customerId,
    CompanyCustomerQuoteWrite write, {
    String? idempotencyKey,
  }) async {
    final decoded = await _sendTransport(
      method: 'POST',
      path:
          '$kCompanyCustomersPath/${Uri.encodeComponent(customerId.trim())}$kCompanyCustomerQuotesPathSuffix',
      query: _scope(),
      body: <String, dynamic>{...write.toJson(), ..._scope()},
      headers: _headers,
      idempotencyKey: idempotencyKey,
    );
    if (decoded['ok'] != true) {
      throw CompanyCustomerException(
        decoded['error']?.toString().trim().isNotEmpty == true
            ? decoded['error'].toString()
            : 'quote_not_ok',
      );
    }
    return parseCompanyCustomerQuote(decoded);
  }

  Future<CompanyCustomerQuote> getQuote(String quoteId) async {
    final decoded = await _listTransport(
      path: '$kCompanyCustomerQuotesPath/${Uri.encodeComponent(quoteId.trim())}',
      query: _scope(),
      headers: _headers,
    );
    if (decoded['ok'] != true) {
      throw CompanyCustomerException(
        decoded['error']?.toString().trim().isNotEmpty == true
            ? decoded['error'].toString()
            : 'quote_not_ok',
      );
    }
    return parseCompanyCustomerQuote(decoded);
  }

  Future<CompanyCustomerQuote> updateQuote(
    String quoteId,
    CompanyCustomerQuoteWrite write, {
    required int revision,
  }) async {
    final decoded = await _sendTransport(
      method: 'PATCH',
      path: '$kCompanyCustomerQuotesPath/${Uri.encodeComponent(quoteId.trim())}',
      query: _scope(),
      body: <String, dynamic>{...write.toJson(revision: revision), ..._scope()},
      headers: _headers,
    );
    if (decoded['ok'] != true) {
      throw CompanyCustomerException(
        decoded['error']?.toString().trim().isNotEmpty == true
            ? decoded['error'].toString()
            : 'quote_not_ok',
      );
    }
    return parseCompanyCustomerQuote(decoded);
  }

  Future<CompanyCustomerQuote> sendQuote(String quoteId) async {
    final decoded = await _sendTransport(
      method: 'POST',
      path:
          '$kCompanyCustomerQuotesPath/${Uri.encodeComponent(quoteId.trim())}/send',
      query: _scope(),
      body: _scope(),
      headers: _headers,
    );
    if (decoded['ok'] != true) {
      throw CompanyCustomerException(
        decoded['error']?.toString().trim().isNotEmpty == true
            ? decoded['error'].toString()
            : 'quote_not_ok',
      );
    }
    return parseCompanyCustomerQuote(decoded);
  }

  Future<CompanyCustomerImportStatus> getImport(String importId) async {
    final decoded = await _listTransport(
      path: '$kCompanyCustomerImportPathPrefix/${Uri.encodeComponent(importId)}',
      query: _scope(),
      headers: _headers,
    );
    return parseCompanyCustomerImportStatus(decoded);
  }
}
