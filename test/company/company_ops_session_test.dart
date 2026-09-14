import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';
import 'package:fluxidi_tracking/company/company_ops_session.dart';

void main() {
  test('synthetic dart-defines are unused outside the local-test bind', () {
    final session = resolveCompanyOpsSession(
      allowSynthetic: false,
      syntheticCompanyId: 'demo_company_p0',
      syntheticToken: 'cst_local_demo_synthetic',
    );
    expect(session.companyId, isEmpty);
    expect(session.sessionToken, isEmpty);
    expect(companyOpsSessionIsReady(session), isFalse);
  });

  test('active paired company wins over leftover synthetic defines', () {
    final session = resolveCompanyOpsSession(
      activeCompanyId: 'fluxidi_fluxidi_ddmh9g',
      activeSessionToken: 'cst_prod_example',
      activeLinkMethod: 'company_pairing_code',
      allowSynthetic: false,
      syntheticCompanyId: 'demo_company_p0',
      syntheticToken: 'cst_local_demo_synthetic',
    );
    expect(session.companyId, 'fluxidi_fluxidi_ddmh9g');
    expect(session.sessionToken, 'cst_prod_example');
  });

  test('local ops notifier is ignored when it is a blocked synthetic session', () {
    final session = resolveCompanyOpsSession(
      localOps: const CompanyOpsLocalSession(
        companyId: 'demo_company_p0',
        sessionToken: 'cst_local_demo_synthetic',
      ),
      allowSynthetic: false,
    );
    expect(session.companyId, isEmpty);
    expect(companyOpsSessionIsReady(session), isFalse);
  });

  test('local-test bind may use the synthetic company', () {
    final session = resolveCompanyOpsSession(
      allowSynthetic: true,
      syntheticCompanyId: 'demo_company_p0',
      syntheticToken: 'cst_local_demo_synthetic',
    );
    expect(session.companyId, 'demo_company_p0');
    expect(session.sessionToken, 'cst_local_demo_synthetic');
    expect(companyOpsSessionIsReady(session), isTrue);
  });
}
