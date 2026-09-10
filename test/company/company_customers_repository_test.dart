import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';

void main() {
  late List<Map<String, dynamic>> listCalls;
  late List<Map<String, dynamic>> sendCalls;

  CompanyCustomersRepository repo({
    Map<String, dynamic>? listBody,
    Map<String, dynamic>? sendBody,
    Object? listError,
    Object? sendError,
  }) {
    listCalls = <Map<String, dynamic>>[];
    sendCalls = <Map<String, dynamic>>[];
    return CompanyCustomersRepository(
      scopeQuery: const <String, String>{
        'tenant_id': 'TA',
        'company_id': 'CA',
      },
      headers: () async => const <String, String>{'Authorization': 'Bearer x'},
      listTransport: ({
        required path,
        required query,
        required headers,
      }) async {
        listCalls.add(<String, dynamic>{'path': path, 'query': query});
        if (listError != null) throw listError;
        return listBody ??
            <String, dynamic>{
              'ok': true,
              'items': <dynamic>[],
              'has_more': false,
              'next_cursor': null,
            };
      },
      sendTransport: ({
        required method,
        required path,
        required query,
        required body,
        required headers,
        idempotencyKey,
      }) async {
        sendCalls.add(<String, dynamic>{
          'method': method,
          'path': path,
          'query': query,
          'body': body,
          'idempotencyKey': idempotencyKey,
        });
        if (sendError != null) throw sendError;
        return sendBody ??
            <String, dynamic>{
              'ok': true,
              'customer': <String, dynamic>{
                'customer_id': 'cus_1',
                'display_name': 'Ada',
                'status': 'active',
                'revision': 1,
                'email': 'ada@example.test',
              },
            };
      },
    );
  }

  test('list uses only the supplied server cursor', () async {
    final customers = repo(
      listBody: <String, dynamic>{
        'ok': true,
        'items': <dynamic>[
          <String, dynamic>{
            'customer_id': 'cus_1',
            'display_name': 'Ada',
            'status': 'active',
          },
        ],
        'has_more': true,
        'next_cursor': 'server-cursor-2',
      },
    );
    final page = await customers.list(query: 'ada', cursor: 'server-cursor-1');
    expect(page.hasMore, isTrue);
    expect(page.nextCursor, 'server-cursor-2');
    expect(listCalls.single['query']['cursor'], 'server-cursor-1');
    expect(listCalls.single['query']['q'], 'ada');
    expect(listCalls.single['query']['status'], 'active');
  });

  test('create update archive restore hit the Worker contract', () async {
    final customers = repo(
      sendBody: <String, dynamic>{
        'ok': true,
        'customer': <String, dynamic>{
          'customer_id': 'cus_9',
          'display_name': 'Ada',
          'status': 'active',
          'revision': 2,
          'email': 'ada@example.test',
        },
      },
    );
    final created = await customers.create(
      const CompanyCustomerWrite(
        displayName: 'Ada',
        email: 'ada@example.test',
      ),
      idempotencyKey: 'create-1',
    );
    expect(created.customer.customerId, 'cus_9');
    expect(sendCalls.first['method'], 'POST');
    expect(sendCalls.first['path'], '/company/customers');
    expect(sendCalls.first['idempotencyKey'], 'create-1');

    await customers.update(
      'cus_9',
      const CompanyCustomerWrite(
        displayName: 'Ada L',
        email: 'ada@example.test',
      ),
      revision: 2,
    );
    expect(sendCalls[1]['method'], 'PATCH');
    expect(sendCalls[1]['body']['revision'], 2);

    await customers.archive('cus_9', idempotencyKey: 'arch-1');
    expect(sendCalls[2]['path'], '/company/customers/cus_9/archive');
    await customers.restore('cus_9');
    expect(sendCalls[3]['path'], '/company/customers/cus_9/restore');
  });

  test('create does not send when local validation fails', () async {
    final customers = repo();
    expect(
      () => customers.create(const CompanyCustomerWrite(displayName: 'Ada')),
      throwsA(isA<CompanyCustomerException>()),
    );
    expect(sendCalls, isEmpty);
  });

  test('missing scope fails closed before transport', () async {
    final customers = CompanyCustomersRepository(
      scopeQuery: const <String, String>{},
      headers: () async => const <String, String>{},
      listTransport: ({
        required path,
        required query,
        required headers,
      }) async {
        throw StateError('transport must not run');
      },
    );
    expect(
      () => customers.list(),
      throwsA(
        isA<CompanyCustomerException>().having(
          (error) => error.code,
          'code',
          'missing_tenant_scope',
        ),
      ),
    );
  });
}
