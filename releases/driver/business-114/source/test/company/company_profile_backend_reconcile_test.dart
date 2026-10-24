import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company_session_store.dart';

CompanyProfile localProfile(String id) => CompanyProfile(
  companyId: id,
  companyName: 'Old local name',
  ownerName: 'Owner',
  email: 'registration@example.com',
  phone: '000',
  vatNumber: 'old VAT',
  addressLine: 'Old street',
  postalCode: '0000',
  city: 'Old city',
  countryCode: 'BE',
  companyEmail: 'registration@example.com',
  supportEmail: 'custom-support@example.com',
  billingEmail: 'registration@example.com',
  bookingEmail: 'custom-bookings@example.com',
  notificationEmail: 'registration@example.com',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  isActive: true,
);

BackendBusinessProfile backendProfile(String id) =>
    BackendBusinessProfile.defaults().copyWith(
      companyId: id,
      companyName: 'Taxi Mario',
      vatNumber: 'BE0821692938',
      address: 'Raapstraat 56',
      postcode: '9100',
      city: 'Sint-Niklaas',
      email: 'primary@example.com',
      companyEmail: 'company@example.com',
      supportEmail: '',
      invoiceEmail: 'invoice@example.com',
      bookingEmail: 'booking@example.com',
      notificationEmail: 'notify@example.com',
    );

void main() {
  test('backend shared fields win while distinct routes remain separate', () {
    final merged = reconcileCompanyProfileWithBackend(
      local: localProfile('cmp_taxi-mario_4b6d297325'),
      backend: backendProfile('cmp_taxi-mario_4b6d297325'),
    );
    expect(merged.vatNumber, 'BE0821692938');
    expect(merged.addressLine, 'Raapstraat 56');
    expect(merged.email, 'primary@example.com');
    expect(merged.companyEmail, 'company@example.com');
    expect(merged.supportEmail, 'custom-support@example.com');
    expect(merged.billingEmail, 'invoice@example.com');
    expect(merged.bookingEmail, 'booking@example.com');
    expect(merged.notificationEmail, 'notify@example.com');
  });

  test('old registration mail is not reused for unconfigured routes', () {
    final merged = reconcileCompanyProfileWithBackend(
      local: localProfile('cmp_taxi-mario_4b6d297325'),
      backend: backendProfile('cmp_taxi-mario_4b6d297325').copyWith(
        companyEmail: '',
        invoiceEmail: '',
        notificationEmail: '',
      ),
    );
    expect(merged.companyEmail, isEmpty);
    expect(merged.billingEmail, isEmpty);
    expect(merged.notificationEmail, isEmpty);
    expect(merged.supportEmail, 'custom-support@example.com');
  });

  test('FLX00001 profile cannot be merged into Taxi Mario', () {
    expect(
      () => reconcileCompanyProfileWithBackend(
        local: localProfile('cmp_taxi-mario_4b6d297325'),
        backend: backendProfile('fluxidi_fluxidi_ddmh9g'),
      ),
      throwsStateError,
    );
  });

  test('parser does not copy primary email into company mail', () {
    final parsed = BackendBusinessProfile.fromJson({'email': 'primary@example.com'});
    expect(parsed.companyEmail, isEmpty);
  });
}
