import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company/business_profile_publication.dart';

void main() {
  for (final company in ['mario', 'another-company']) {
    for (final enabled in [true, false]) {
      test('publish/reload preserves company settings: $company/$enabled', () {
        final profile = BackendBusinessProfile.defaults().copyWith(
          companyId: company,
          companyName: company,
          businessAppUseCompanyHeader: enabled,
          driverAppUseCompanyHeader: !enabled,
          customerAppHeaderMode: 'header_and_logo',
          customerAppHeaderLogoPosition: 'top_right',
          customerAppHeaderMediaRevision: 'revision-12',
          airportFixedFareMinLeadDeclared: true,
          airportFixedFareMinLeadHours: 48,
          airportAutoCalcOutsideFixedFares: false,
          paymentOwnerMode: 'company',
          mollieConnected: true,
        );
        final published = businessProfileAfterPublication(
          profile,
          publishedAt: '2026-10-02T08:00:00Z',
        );
        final expected = {
          ...profile.toJson(),
          'publicPartnerProfilePublishedAt': '2026-10-02T08:00:00Z',
          'public_partner_profile_published_at': '2026-10-02T08:00:00Z',
          'publicPartnerProfilePublishStatus': 'published',
          'public_partner_profile_publish_status': 'published',
        };
        expect(published.toJson(), expected);
        final reloaded = BackendBusinessProfile.fromJson(published.toJson());
        expect(reloaded.businessAppUseCompanyHeader, enabled);
        expect(reloaded.driverAppUseCompanyHeader, !enabled);
        expect(reloaded.airportFixedFareMinLeadHours, 48);
        expect(reloaded.mollieConnected, isTrue);
      });
    }
  }
}


