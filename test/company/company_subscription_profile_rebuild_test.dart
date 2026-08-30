import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('business settings does not create a remote Future on every build', () {
    final source = File('lib/business_settings_page.dart').readAsStringSync();
    expect(source.contains('_limousineReadinessProfileFuture'), isTrue);
    expect(
      source.contains(
        'if (_limousineReadinessScopeId != scopeId ||\n'
        '        _limousineReadinessProfileFuture == null)',
      ),
      isTrue,
    );
    expect(
      source.contains(
        'future: fetchCompanySubscriptionProfile(\n'
        '        tenantId: scopeId,\n'
        '        companyId: scopeId,\n'
        '      ),',
      ),
      isFalse,
    );
  });
}
