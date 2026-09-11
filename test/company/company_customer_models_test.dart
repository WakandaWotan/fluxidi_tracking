import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';

void main() {
  group('company customer model parsing', () {
    test('list page is fail-closed and never invents a cursor', () {
      expect(
        () => parseCompanyCustomerListPage(<String, dynamic>{'ok': false}),
        throwsA(isA<CompanyCustomerException>()),
      );
      expect(
        () => parseCompanyCustomerListPage(<String, dynamic>{
          'ok': true,
          'items': 'nope',
        }),
        throwsA(isA<CompanyCustomerException>()),
      );
      expect(
        () => parseCompanyCustomerListPage(<String, dynamic>{
          'ok': true,
          'items': <dynamic>[
            <String, dynamic>{'display_name': 'Ada'},
          ],
        }),
        throwsA(isA<CompanyCustomerException>()),
      );
      final page = parseCompanyCustomerListPage(<String, dynamic>{
        'ok': true,
        'items': <dynamic>[
          <String, dynamic>{
            'customer_id': 'cus_1',
            'display_name': 'Ada',
            'status': 'active',
            'email_masked': '*@ex.test',
            'phone_masked': '***50',
          },
        ],
        'has_more': true,
        'next_cursor': '',
        'total_count': 1,
      });
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
      expect(page.items.single.customerId, 'cus_1');
    });

    test('has_more requires the Worker cursor', () {
      final page = parseCompanyCustomerListPage(<String, dynamic>{
        'ok': true,
        'items': <dynamic>[
          <String, dynamic>{
            'customer_id': 'cus_1',
            'display_name': 'Ada',
            'status': 'active',
          },
        ],
        'has_more': true,
        'next_cursor': 'opaque-from-worker',
      });
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, 'opaque-from-worker');
    });

    test('detail parse is fail-closed on missing revision or status', () {
      expect(
        () => parseCompanyCustomerEnvelope(<String, dynamic>{
          'ok': true,
          'customer': <String, dynamic>{
            'customer_id': 'cus_1',
            'display_name': 'Ada',
            'status': 'mystery',
            'revision': 1,
          },
        }),
        throwsA(isA<CompanyCustomerException>()),
      );
      expect(
        () => parseCompanyCustomerEnvelope(<String, dynamic>{
          'ok': true,
          'customer': <String, dynamic>{
            'customer_id': 'cus_1',
            'display_name': 'Ada',
            'status': 'active',
          },
        }),
        throwsA(isA<CompanyCustomerException>()),
      );
    });

    test('display name suggestion does not overwrite a manual edit', () {
      expect(
        suggestedCompanyCustomerDisplayName(
          firstName: 'Ada',
          lastName: 'Lovelace',
        ),
        'Ada Lovelace',
      );
      expect(
        shouldReplaceSuggestedCompanyCustomerDisplayName(
          currentDisplayName: '',
          previousSuggestion: '',
        ),
        isTrue,
      );
      expect(
        shouldReplaceSuggestedCompanyCustomerDisplayName(
          currentDisplayName: 'Ada Lovelace',
          previousSuggestion: 'Ada Lovelace',
        ),
        isTrue,
      );
      expect(
        shouldReplaceSuggestedCompanyCustomerDisplayName(
          currentDisplayName: 'Ada L.',
          previousSuggestion: 'Ada Lovelace',
        ),
        isFalse,
      );
    });

    test('write validation requires a name and one contact method', () {
      expect(
        validateCompanyCustomerWrite(const CompanyCustomerWrite()),
        containsPair('display_name', 'required'),
      );
      expect(
        validateCompanyCustomerWrite(
          const CompanyCustomerWrite(displayName: 'Ada'),
        ),
        containsPair('contact', 'required'),
      );
      expect(
        validateCompanyCustomerWrite(
          const CompanyCustomerWrite(
            displayName: 'Ada',
            email: 'not-an-email',
          ),
        ),
        containsPair('email', 'invalid'),
      );
      expect(
        validateCompanyCustomerWrite(
          const CompanyCustomerWrite(
            displayName: 'Ada',
            email: 'ada@example.test',
          ),
        ),
        isEmpty,
      );
    });

    test('phone normalize stays country-aware without a default country', () {
      final local = normalizeCompanyCustomerPhone('0470123456', '');
      expect(local.normalized, '0470123456');
      expect(local.e164, isEmpty);
      final withCode = normalizeCompanyCustomerPhone('0470123456', '32');
      expect(withCode.e164, '+320470123456');
      final e164 = normalizeCompanyCustomerPhone('+442071838750', '');
      expect(e164.e164, '+442071838750');
    });
  });
}
