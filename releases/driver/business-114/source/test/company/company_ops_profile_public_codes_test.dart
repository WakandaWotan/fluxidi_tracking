import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_customers_repository_factory_web.dart';

void main() {
  test(
    'profile GET preserves registered slug and canonical scoped-key identity',
    () {
      final merged = mergeCompanyOpsProfilePublicCodes({
        'ok': true,
        'key': 'tenant:mario-company:company:mario-company:business_profile:v1',
        'public_company_slug': 'TAXI-MARIO',
        'business_profile': {'companyName': 'Taxi Mario'},
      });
      expect(merged['public_company_slug'], 'TAXI-MARIO');
      expect(merged['tenant_id'], 'mario-company');
      expect(merged['company_id'], 'mario-company');
    },
  );

  test(
    'profile GET keeps Worker public codes that sit beside business_profile',
    () {
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
    },
  );
}
