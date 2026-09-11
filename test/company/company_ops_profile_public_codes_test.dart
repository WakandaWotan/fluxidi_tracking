import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_customers_repository_factory_web.dart';

void main() {
  test('profile GET keeps Worker public codes that sit beside business_profile', () {
    final merged = mergeCompanyOpsProfilePublicCodes(<String, dynamic>{
      'ok': true,
      'public_company_code': 'FLX-00001',
      'company_code': 'FLX-00001',
      'business_profile': <String, dynamic>{
        'companyName': 'Fluxidi Demo Cars',
        'country': 'BE',
      },
    });
    expect(merged['companyName'], 'Fluxidi Demo Cars');
    expect(merged['public_company_code'], 'FLX-00001');
    expect(merged['company_code'], 'FLX-00001');
  });
}
