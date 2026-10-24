import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/local_synthetic_company_session.dart';

void main() {
  test('local synthetic session binds only to loopback + cst_local token', () {
    expect(
      shouldBindLocalSyntheticCompanySession(
        releaseMode: false,
        bookingBaseUrl: 'http://127.0.0.1:8788',
        sessionToken: 'cst_local_demo_synthetic',
        companyId: 'demo_company_p0',
      ),
      isTrue,
    );
    expect(
      shouldBindLocalSyntheticCompanySession(
        releaseMode: true,
        bookingBaseUrl: 'http://127.0.0.1:8788',
        sessionToken: 'cst_local_demo_synthetic',
        companyId: 'demo_company_p0',
      ),
      isFalse,
    );
    expect(
      shouldBindLocalSyntheticCompanySession(
        releaseMode: false,
        bookingBaseUrl: 'https://fluxidi-booking-api.fluxidi.workers.dev',
        sessionToken: 'cst_local_demo_synthetic',
        companyId: 'demo_company_p0',
      ),
      isFalse,
    );
    expect(
      shouldBindLocalSyntheticCompanySession(
        releaseMode: false,
        bookingBaseUrl: 'http://127.0.0.1:8788',
        sessionToken: 'prod_session_token',
        companyId: 'demo_company_p0',
      ),
      isFalse,
    );
  });

  test('local synthetic session is discarded on a production booking host', () {
    expect(
      shouldDiscardLocalSyntheticSessionForHost(
        bookingBaseUrl: 'https://fluxidi-booking-api.fluxidi.workers.dev',
        companyId: 'demo_company_p0',
        sessionToken: 'cst_local_demo_synthetic',
        linkMethod: 'local_synthetic_demo',
      ),
      isTrue,
    );
    expect(
      shouldDiscardLocalSyntheticSessionForHost(
        bookingBaseUrl: 'http://127.0.0.1:8788',
        companyId: 'demo_company_p0',
        sessionToken: 'cst_local_demo_synthetic',
        linkMethod: 'local_synthetic_demo',
      ),
      isFalse,
    );
    expect(
      shouldDiscardLocalSyntheticSessionForHost(
        bookingBaseUrl: 'https://fluxidi-booking-api.fluxidi.workers.dev',
        companyId: 'fluxidi_fluxidi_ddmh9g',
        sessionToken: 'cst_prod_example',
        linkMethod: 'company_pairing_code',
      ),
      isFalse,
    );
    expect(
      isProductionBookingHost(
        'https://fluxidi-booking-api.fluxidi.workers.dev',
      ),
      isTrue,
    );
  });

  test('local loopback dart-defines replace a foreign or empty session', () {
    expect(
      shouldReplaceSessionForLocalSyntheticBind(
        existingCompanyId: 'demo_company_p0',
        configuredCompanyId: 'demo_company_p0',
      ),
      isFalse,
    );
    expect(
      shouldReplaceSessionForLocalSyntheticBind(
        existingCompanyId: '',
        configuredCompanyId: 'demo_company_p0',
      ),
      isTrue,
    );
    expect(
      shouldReplaceSessionForLocalSyntheticBind(
        existingCompanyId: 'fluxidi_fluxidi_ddmh9g',
        configuredCompanyId: 'demo_company_p0',
      ),
      isTrue,
    );
  });
}
