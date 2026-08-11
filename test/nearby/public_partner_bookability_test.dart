import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/nearby/public_partner_bookability.dart';

void main() {
  group('public partner bookability', () {
    test('1) active partner => active + bookable', () {
      final partner = <String, dynamic>{
        'is_active': true,
        'bookable': true,
        'availability_status': 'active',
        'company_name': 'Fluxidi Taxi',
      };
      expect(isPublicPartnerBookable(partner), isTrue);
      expect(publicPartnerDisplayName(partner), 'Fluxidi Taxi');
    });

    test('2) CAPE active-until-period-end => active + bookable', () {
      // Server maps CAPE (still entitled) to bookable=true / active.
      final partner = <String, dynamic>{
        'is_active': true,
        'bookable': true,
        'availability_status': 'active',
        'company_name': 'Prometheus',
      };
      expect(isPublicPartnerBookable(partner), isTrue);
    });

    test('3) expired/cancelled => inactive + booking blocked', () {
      final partner = <String, dynamic>{
        'is_active': false,
        'bookable': false,
        'availability_status': 'inactive',
        'company_name': 'Entitlement Mollie SaaS TEST',
        'partner_id':
            'company:cmp_entitlement_test_mollie_saas_20260811:cmp_entitlement_test_mollie_saas_20260811',
      };
      expect(isPublicPartnerBookable(partner), isFalse);
      expect(
        publicPartnerInactiveBookingMessage(languageCode: 'nl'),
        contains('niet actief'),
      );
      expect(
        publicPartnerInactiveBookingMessage(languageCode: 'nl'),
        contains('geen nieuwe boekingen'),
      );
    });

    test('4) no internal tenant IDs in public partner presentation', () {
      expect(
        looksLikeInternalPartnerIdentifier(
          'company:cmp_entitlement_test_mollie_saas_20260811:cmp_entitlement_test_mollie_saas_20260811',
        ),
        isTrue,
      );
      expect(
        looksLikeInternalPartnerIdentifier(
          'cmp_entitlement_test_mollie_saas_20260811',
        ),
        isTrue,
      );
      expect(looksLikeInternalPartnerIdentifier('FLX-00021'), isFalse);
      expect(looksLikeInternalPartnerIdentifier('Fluxidi Taxi'), isFalse);

      final display = publicPartnerDisplayName(<String, dynamic>{
        'partner_id':
            'company:cmp_entitlement_test_mollie_saas_20260811:cmp_entitlement_test_mollie_saas_20260811',
        'company_name': 'cmp_entitlement_test_mollie_saas_20260811',
      }, fallback: 'company:cmp_x:cmp_x');
      expect(display, isEmpty);
      expect(looksLikeInternalPartnerIdentifier(display), isFalse);
    });
  });
}
