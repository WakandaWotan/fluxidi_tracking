// CUSTOMER BILLING PROFILE P0 — Flutter sanitizer / parser / merge contracts.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';

void main() {
  group('sanitizePublicCustomerProfilePayload', () {
    test('1. serializer includes all supported billing fields when present', () {
      final out = sanitizePublicCustomerProfilePayload(<String, dynamic>{
        'name': 'Alice',
        'phone': '+32470000001',
        'email': 'alice@example.com',
        'preferred_postcode': '1000',
        'company_name': 'Alice BV',
        'vat_number': 'NL123456789B01',
        'invoice_email': 'invoice@example.com',
        'billing_street': 'Main 1',
        'billing_postal_code': '1000',
        'billing_city': 'Brussels',
        'billing_country': 'be',
        'peppol_endpoint_id': '0208:0123456789',
        'peppol_scheme': '0208',
        'favorite_partner_ids': <String>['p1'],
      });
      expect(out['invoice_email'], 'invoice@example.com');
      expect(out['billing_street'], 'Main 1');
      expect(out['billing_postal_code'], '1000');
      expect(out['billing_city'], 'Brussels');
      expect(out['billing_country'], 'BE');
      expect(out['peppol_endpoint_id'], '0208:0123456789');
      expect(out['peppol_scheme'], '0208');
      expect(out['peppol'], isA<Map>());
      expect((out['peppol'] as Map)['endpoint_id'], '0208:0123456789');
      expect(out['favorite_partner_ids'], <String>['p1']);
    });

    test('2. sanitizer no longer drops billing/Peppol fields', () {
      final out = sanitizePublicCustomerProfilePayload(<String, dynamic>{
        'invoice_email': 'a@b.co',
        'billing_address': <String, dynamic>{
          'street': 'S',
          'postal_code': '1',
          'city': 'C',
          'country': 'NL',
        },
        'peppol': <String, dynamic>{
          'endpoint_id': '0208:1',
          'scheme': '0208',
        },
      });
      expect(out.containsKey('invoice_email'), isTrue);
      expect(out.containsKey('billing_street'), isTrue);
      expect(out.containsKey('peppol_endpoint_id'), isTrue);
      expect(out.containsKey('unknown_x'), isFalse);
    });

    test('8. device-local / favorites partial upsert omits billing keys', () {
      final out = sanitizePublicCustomerProfilePayload(<String, dynamic>{
        'name': 'Alice',
        'email': 'alice@example.com',
        'favorite_partner_ids': <String>['p1'],
      });
      expect(out.containsKey('invoice_email'), isFalse);
      expect(out.containsKey('billing_street'), isFalse);
      expect(out.containsKey('peppol_endpoint_id'), isFalse);
      expect(out['favorite_partner_ids'], <String>['p1']);
    });
  });

  group('CustomerProfile parser', () {
    test('3. parser restores billing/Peppol from profile API shape', () {
      final profile = CustomerProfile.fromJson(<String, dynamic>{
        'customerId': 'cust_1',
        'name': 'Alice',
        'phone': '+32470000001',
        'email': 'alice@example.com',
        'preferred_postcode': '1000',
        'companyName': 'Alice BV',
        'vatNumber': 'BE0123',
        'invoice_email': 'invoice@example.com',
        'billing_address': <String, dynamic>{
          'street': 'Main 1',
          'postal_code': '1000',
          'city': 'Brussels',
          'country': 'BE',
        },
        'peppol': <String, dynamic>{
          'endpoint_id': '0208:1',
          'scheme': '0208',
        },
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-02T00:00:00.000Z',
      });
      expect(profile.invoiceEmail, 'invoice@example.com');
      expect(profile.billingStreet, 'Main 1');
      expect(profile.billingPostalCode, '1000');
      expect(profile.billingCity, 'Brussels');
      expect(profile.billingCountry, 'BE');
      expect(profile.peppolEndpointId, '0208:1');
      expect(profile.peppolScheme, '0208');
    });

    test('10. existing name/phone/email/company/VAT still serialize', () {
      final profile = CustomerProfile(
        customerId: 'cust_1',
        name: 'Alice',
        phone: '+32470000001',
        email: 'alice@example.com',
        preferredPostcode: '1000',
        companyName: 'Alice BV',
        vatNumber: 'BE0123',
        invoiceEmail: 'inv@example.com',
        billingStreet: 'S',
        billingPostalCode: '1',
        billingCity: 'C',
        billingCountry: 'BE',
        peppolEndpointId: '0208:1',
        peppolScheme: '0208',
        createdAt: 'a',
        updatedAt: 'b',
      );
      final json = profile.toJson();
      expect(json['name'], 'Alice');
      expect(json['vatNumber'], 'BE0123');
      expect(json['invoice_email'], 'inv@example.com');
      expect(json['peppol_endpoint_id'], '0208:1');
      final roundTrip = CustomerProfile.fromJson(json);
      expect(roundTrip.invoiceEmail, 'inv@example.com');
      expect(roundTrip.peppolScheme, '0208');
    });
  });

  group('source contracts', () {
    String read(String path) => File(path).readAsStringSync();

    test('4-6. bootstrap push includes billing; pull uses merge; save UX distinguishes sync', () {
      final bootstrap = read('lib/main_parts/customer_session_bootstrap.dart');
      expect(bootstrap, contains("'invoice_email': localProfile.invoiceEmail"));
      expect(bootstrap, contains("'billing_street': localProfile.billingStreet"));
      expect(bootstrap, contains("'peppol_endpoint_id': localProfile.peppolEndpointId"));
      expect(bootstrap, contains('mergeBackendProfileForSession'));
      expect(bootstrap, contains('_syncCustomerProfileFromBackendBestEffort'));

      final edit = read('lib/main_parts/customer_profile_edit_page_state.dart');
      expect(edit, contains('Gegevens opgeslagen en gesynchroniseerd.'));
      expect(edit, contains('Synchronisatie met de server is mislukt'));
      expect(edit, isNot(contains("nl: 'Gegevens opgeslagen.',")));
    });

    test('5. merge prefers non-empty backend over empty local (second device)', () {
      final store = read('lib/customer_profile_store.dart');
      expect(store, contains('pickPreferBackend'));
      expect(store, contains('backendInvoiceEmail'));
      expect(store, contains('backendPeppolEndpointId'));
    });

    test('9. booking calculator still prefills billing_customer from profile', () {
      final calc = read('lib/calculator_page.dart');
      expect(calc, contains('profile.billingStreet'));
      expect(calc, contains('profile.invoiceEmail'));
      expect(calc, contains('profile.peppolEndpointId'));
      expect(calc, contains("'billing_customer': billingCustomer"));
      expect(calc, contains("'peppol': <String, dynamic>"));
    });
  });
}
