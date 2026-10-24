/// Characterization tests for the buyer billing identity rules that taxi and
/// airport use today.
///
/// `calculator_page.dart` (L4969/L5029) and
/// `airport_booking_review_page.dart` (L681/L736) each carried their own
/// byte-identical copy of the `billing_customer` mapper and the completeness
/// check, and neither had any test coverage. These tests pin the current
/// behaviour so moving both pages onto the shared
/// [bookingBillingCustomerPayloadFields] seam is provably a no-op for them.
///
/// Every expectation is computed twice: once through the seam, and once by
/// replaying the exact expressions the two pages used inline. If the seam ever
/// drifts from that original logic, these fail.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fluxidi_tracking/payment/booking_billing_identity.dart';

/// Stand-in for the ten `TextEditingController`s each page owned.
class _Draft {
  const _Draft({
    this.legalName = '',
    this.vat = '',
    this.registrationNumber = '',
    this.street = '',
    this.postal = '',
    this.city = '',
    this.country = '',
    this.contactEmail = '',
    this.peppolEndpoint = '',
    this.peppolScheme = '',
  });

  final String legalName;
  final String vat;
  final String registrationNumber;
  final String street;
  final String postal;
  final String city;
  final String country;
  final String contactEmail;
  final String peppolEndpoint;
  final String peppolScheme;

  BookingBillingIdentity get identity => BookingBillingIdentity(
    legalName: legalName,
    vatNumber: vat,
    registrationNumber: registrationNumber,
    street: street,
    postalCode: postal,
    city: city,
    country: country,
    contactEmail: contactEmail,
    peppolEndpointId: peppolEndpoint,
    peppolScheme: peppolScheme,
  );
}

// --------------------------------------------------------------------------
// The original inline logic, copied verbatim from the two pages.
// --------------------------------------------------------------------------

/// Verbatim replay of `_billingAddressComplete` (calculator L4960,
/// airport L675).
bool _legacyAddressComplete(_Draft d) =>
    d.street.trim().isNotEmpty &&
    d.postal.trim().isNotEmpty &&
    d.city.trim().isNotEmpty &&
    d.country.trim().isNotEmpty;

/// Verbatim replay of `_buildBillingCustomerPayloadFields` (calculator L4969,
/// airport L681).
Map<String, dynamic> _legacyBillingCustomerFields(
  _Draft d, {
  required bool billingDetailsEnabled,
  required String defaultEmail,
  required String defaultPhone,
}) {
  if (!billingDetailsEnabled) return const <String, dynamic>{};
  final legalName = d.legalName.trim();
  final vat = d.vat.trim();
  final registrationNumber = d.registrationNumber.trim();
  final street = d.street.trim();
  final postal = d.postal.trim();
  final city = d.city.trim();
  final country = d.country.trim().toUpperCase();
  final contactEmail = d.contactEmail.trim().isNotEmpty
      ? d.contactEmail.trim()
      : defaultEmail.trim();
  final contactPhone = defaultPhone.trim();
  final peppolEndpoint = d.peppolEndpoint.trim();
  final peppolScheme = d.peppolScheme.trim();

  final hasAny =
      legalName.isNotEmpty ||
      vat.isNotEmpty ||
      registrationNumber.isNotEmpty ||
      street.isNotEmpty ||
      postal.isNotEmpty ||
      city.isNotEmpty ||
      country.isNotEmpty ||
      peppolEndpoint.isNotEmpty ||
      peppolScheme.isNotEmpty;
  if (!hasAny) return const <String, dynamic>{};

  final billingCustomer = <String, dynamic>{
    'customer_type': 'business',
    'display_name': legalName.isNotEmpty ? legalName : null,
    'contact_email': contactEmail.isNotEmpty ? contactEmail : null,
    'contact_phone': contactPhone.isNotEmpty ? contactPhone : null,
    'legal_name': legalName.isNotEmpty ? legalName : null,
    'vat_number': vat.isNotEmpty ? vat : null,
    'company_registration_number': registrationNumber.isNotEmpty
        ? registrationNumber
        : null,
    'billing_address': <String, dynamic>{
      'street': street.isNotEmpty ? street : null,
      'postal_code': postal.isNotEmpty ? postal : null,
      'city': city.isNotEmpty ? city : null,
      'country': country.isNotEmpty ? country : null,
    },
    'peppol': <String, dynamic>{
      'endpoint_id': peppolEndpoint.isNotEmpty ? peppolEndpoint : null,
      'scheme': peppolScheme.isNotEmpty ? peppolScheme : null,
    },
  };
  return <String, dynamic>{'billing_customer': billingCustomer};
}

/// Verbatim replay of the `_billingCustomerValidationWarning` decision
/// (calculator L5029, airport L736). True when the page stayed silent.
bool _legacyValidationSilent(_Draft d, {required bool billingDetailsEnabled}) {
  if (!billingDetailsEnabled) return true;
  final hasLegal = d.legalName.trim().isNotEmpty;
  final hasVat = d.vat.trim().isNotEmpty;
  final hasRegistration = d.registrationNumber.trim().isNotEmpty;
  return hasLegal && (hasVat || hasRegistration) && _legacyAddressComplete(d);
}

// --------------------------------------------------------------------------
// The input matrix.
// --------------------------------------------------------------------------

const _Draft _blank = _Draft();

const _Draft _fullBelgianBusiness = _Draft(
  legalName: 'Acme Events BVBA',
  vat: 'BE0123456789',
  street: 'Kerkstraat 12',
  postal: '2000',
  city: 'Antwerpen',
  country: 'be',
  contactEmail: 'facturen@acme.example',
);

const _Draft _registrationInsteadOfVat = _Draft(
  legalName: 'Acme Events BVBA',
  registrationNumber: '0123456789',
  street: 'Kerkstraat 12',
  postal: '2000',
  city: 'Antwerpen',
  country: 'BE',
);

const _Draft _vatOnly = _Draft(vat: 'BE0123456789');
const _Draft _legalNameOnly = _Draft(legalName: 'Acme Events BVBA');
const _Draft _addressOnly = _Draft(
  street: 'Kerkstraat 12',
  postal: '2000',
  city: 'Antwerpen',
  country: 'BE',
);
const _Draft _peppolOnly = _Draft(peppolEndpoint: '0208:0123456789');
const _Draft _nameAndVatNoAddress = _Draft(
  legalName: 'Acme Events BVBA',
  vat: 'BE0123456789',
);
const _Draft _partialAddress = _Draft(
  legalName: 'Acme Events BVBA',
  vat: 'BE0123456789',
  street: 'Kerkstraat 12',
  city: 'Antwerpen',
  country: 'BE',
);
const _Draft _whitespaceOnly = _Draft(
  legalName: '   ',
  vat: '  ',
  street: ' ',
  postal: '  ',
  city: ' ',
  country: '  ',
);
const _Draft _untrimmed = _Draft(
  legalName: '  Acme Events BVBA  ',
  vat: '  BE0123456789 ',
  street: '  Kerkstraat 12 ',
  postal: ' 2000 ',
  city: ' Antwerpen ',
  country: ' be ',
  contactEmail: '  facturen@acme.example  ',
);
const _Draft _peppolPair = _Draft(
  legalName: 'Acme Events BVBA',
  vat: 'BE0123456789',
  street: 'Kerkstraat 12',
  postal: '2000',
  city: 'Antwerpen',
  country: 'BE',
  peppolEndpoint: '0123456789',
  peppolScheme: '0208',
);

const Map<String, _Draft> _matrix = <String, _Draft>{
  'blank': _blank,
  'full Belgian business': _fullBelgianBusiness,
  'registration instead of VAT': _registrationInsteadOfVat,
  'VAT only': _vatOnly,
  'legal name only': _legalNameOnly,
  'address only': _addressOnly,
  'Peppol only': _peppolOnly,
  'name and VAT, no address': _nameAndVatNoAddress,
  'partial address (no postal code)': _partialAddress,
  'whitespace only': _whitespaceOnly,
  'untrimmed input': _untrimmed,
  'complete with Peppol pair': _peppolPair,
};

const List<({String email, String phone})> _contactMatrix =
    <({String email, String phone})>[
      (email: '', phone: ''),
      (email: 'rider@example.com', phone: '+32470112233'),
      (email: '  rider@example.com  ', phone: '  +32470112233  '),
    ];

void main() {
  group('billing_customer mapper matches the taxi and airport originals', () {
    for (final entry in _matrix.entries) {
      for (final enabled in <bool>[false, true]) {
        for (final contact in _contactMatrix) {
          test('${entry.key} / toggle ${enabled ? 'on' : 'off'} / '
              'email "${contact.email}"', () {
            final legacy = _legacyBillingCustomerFields(
              entry.value,
              billingDetailsEnabled: enabled,
              defaultEmail: contact.email,
              defaultPhone: contact.phone,
            );
            final shared = bookingBillingCustomerPayloadFields(
              enabled: enabled,
              identity: entry.value.identity,
              defaultEmail: contact.email,
              defaultPhone: contact.phone,
            );
            expect(shared, legacy);
          });
        }
      }
    }
  });

  group('key order and shape are preserved exactly', () {
    test('top level carries only billing_customer', () {
      final fields = bookingBillingCustomerPayloadFields(
        enabled: true,
        identity: _fullBelgianBusiness.identity,
        defaultEmail: 'rider@example.com',
        defaultPhone: '+32470112233',
      );
      expect(fields.keys.toList(), <String>['billing_customer']);
    });

    test('billing_customer key order is unchanged', () {
      final fields = bookingBillingCustomerPayloadFields(
        enabled: true,
        identity: _fullBelgianBusiness.identity,
        defaultEmail: 'rider@example.com',
        defaultPhone: '+32470112233',
      );
      final billing = fields['billing_customer'] as Map<String, dynamic>;
      expect(billing.keys.toList(), <String>[
        'customer_type',
        'display_name',
        'contact_email',
        'contact_phone',
        'legal_name',
        'vat_number',
        'company_registration_number',
        'billing_address',
        'peppol',
      ]);
      expect(
        (billing['billing_address'] as Map<String, dynamic>).keys.toList(),
        <String>['street', 'postal_code', 'city', 'country'],
      );
      expect(
        (billing['peppol'] as Map<String, dynamic>).keys.toList(),
        <String>['endpoint_id', 'scheme'],
      );
    });

    test('absent fields stay present as explicit nulls', () {
      final fields = bookingBillingCustomerPayloadFields(
        enabled: true,
        identity: _vatOnly.identity,
        defaultEmail: '',
        defaultPhone: '',
      );
      final billing = fields['billing_customer'] as Map<String, dynamic>;
      expect(billing['vat_number'], 'BE0123456789');
      expect(billing['legal_name'], isNull);
      expect(billing['display_name'], isNull);
      expect(billing['contact_email'], isNull);
      expect(billing['contact_phone'], isNull);
      expect(billing['company_registration_number'], isNull);
      final address = billing['billing_address'] as Map<String, dynamic>;
      expect(address.values.every((Object? v) => v == null), isTrue);
    });

    test('customer_type is always the literal business', () {
      for (final entry in _matrix.entries) {
        final fields = bookingBillingCustomerPayloadFields(
          enabled: true,
          identity: entry.value.identity,
          defaultEmail: '',
          defaultPhone: '',
        );
        if (fields.isEmpty) continue;
        final billing = fields['billing_customer'] as Map<String, dynamic>;
        expect(
          billing['customer_type'],
          'business',
          reason: 'case: ${entry.key}',
        );
      }
    });

    test('country is uppercased, other fields are trimmed only', () {
      final fields = bookingBillingCustomerPayloadFields(
        enabled: true,
        identity: _untrimmed.identity,
        defaultEmail: '',
        defaultPhone: '',
      );
      final billing = fields['billing_customer'] as Map<String, dynamic>;
      expect(billing['legal_name'], 'Acme Events BVBA');
      expect(billing['vat_number'], 'BE0123456789');
      expect(billing['contact_email'], 'facturen@acme.example');
      final address = billing['billing_address'] as Map<String, dynamic>;
      expect(address['street'], 'Kerkstraat 12');
      expect(address['postal_code'], '2000');
      expect(address['city'], 'Antwerpen');
      expect(address['country'], 'BE');
    });
  });

  group('emission gates match the originals', () {
    test('toggle off sends nothing for every case', () {
      for (final entry in _matrix.entries) {
        expect(
          bookingBillingCustomerPayloadFields(
            enabled: false,
            identity: entry.value.identity,
            defaultEmail: 'rider@example.com',
            defaultPhone: '+32470112233',
          ),
          isEmpty,
          reason: 'case: ${entry.key}',
        );
      }
    });

    test('toggle on with nothing entered sends nothing', () {
      expect(
        bookingBillingCustomerPayloadFields(
          enabled: true,
          identity: _blank.identity,
          defaultEmail: 'rider@example.com',
          defaultPhone: '+32470112233',
        ),
        isEmpty,
      );
    });

    test('whitespace-only input counts as nothing entered', () {
      expect(
        bookingBillingCustomerPayloadFields(
          enabled: true,
          identity: _whitespaceOnly.identity,
          defaultEmail: 'rider@example.com',
          defaultPhone: '+32470112233',
        ),
        isEmpty,
      );
    });

    test('a contact email alone does not open the fragment', () {
      expect(
        bookingBillingCustomerPayloadFields(
          enabled: true,
          identity: const BookingBillingIdentity(
            contactEmail: 'facturen@acme.example',
          ),
          defaultEmail: '',
          defaultPhone: '',
        ),
        isEmpty,
      );
    });

    test('Peppol data alone does open the fragment', () {
      final fields = bookingBillingCustomerPayloadFields(
        enabled: true,
        identity: _peppolOnly.identity,
        defaultEmail: '',
        defaultPhone: '',
      );
      expect(fields, isNotEmpty);
    });
  });

  group('contact fallback matches the originals', () {
    test('typed invoice email wins over the booking email', () {
      final fields = bookingBillingCustomerPayloadFields(
        enabled: true,
        identity: _fullBelgianBusiness.identity,
        defaultEmail: 'rider@example.com',
        defaultPhone: '+32470112233',
      );
      final billing = fields['billing_customer'] as Map<String, dynamic>;
      expect(billing['contact_email'], 'facturen@acme.example');
    });

    test('booking email fills in when no invoice email was typed', () {
      final fields = bookingBillingCustomerPayloadFields(
        enabled: true,
        identity: _registrationInsteadOfVat.identity,
        defaultEmail: '  rider@example.com  ',
        defaultPhone: '  +32470112233  ',
      );
      final billing = fields['billing_customer'] as Map<String, dynamic>;
      expect(billing['contact_email'], 'rider@example.com');
      expect(billing['contact_phone'], '+32470112233');
    });
  });

  group('completeness rule matches the taxi and airport validators', () {
    for (final entry in _matrix.entries) {
      for (final enabled in <bool>[false, true]) {
        test('${entry.key} / toggle ${enabled ? 'on' : 'off'}', () {
          final legacySilent = _legacyValidationSilent(
            entry.value,
            billingDetailsEnabled: enabled,
          );
          final sharedSilent =
              !enabled || entry.value.identity.isCompleteForBusinessInvoice;
          expect(sharedSilent, legacySilent);
        });
      }
    }

    test('address completeness matches the original getter', () {
      for (final entry in _matrix.entries) {
        expect(
          entry.value.identity.addressComplete,
          _legacyAddressComplete(entry.value),
          reason: 'case: ${entry.key}',
        );
      }
    });

    test('registration number substitutes for VAT', () {
      expect(
        _registrationInsteadOfVat.identity.isCompleteForBusinessInvoice,
        isTrue,
      );
    });

    test('a legal name alone is never complete', () {
      expect(_legalNameOnly.identity.isCompleteForBusinessInvoice, isFalse);
    });

    test('a VAT number alone is never complete', () {
      expect(_vatOnly.identity.isCompleteForBusinessInvoice, isFalse);
    });

    test('a missing postal code blocks completeness', () {
      expect(_partialAddress.identity.isCompleteForBusinessInvoice, isFalse);
    });
  });

  group('first missing required field is reported in form order', () {
    test('blank asks for the legal name first', () {
      expect(
        firstMissingBookingBillingIdentityField(_blank.identity),
        BookingBillingIdentityField.legalName,
      );
    });

    test('name without VAT or registration asks for the number', () {
      expect(
        firstMissingBookingBillingIdentityField(_legalNameOnly.identity),
        BookingBillingIdentityField.legalIdentityNumber,
      );
    });

    test('name and VAT without an address asks for the address', () {
      expect(
        firstMissingBookingBillingIdentityField(_nameAndVatNoAddress.identity),
        BookingBillingIdentityField.address,
      );
    });

    test('a complete identity reports nothing missing', () {
      expect(
        firstMissingBookingBillingIdentityField(_fullBelgianBusiness.identity),
        isNull,
      );
      expect(
        firstMissingBookingBillingIdentityField(
          _registrationInsteadOfVat.identity,
        ),
        isNull,
      );
    });
  });

  group('the buyer identity never carries seller or amount fields', () {
    test('no price, currency, VAT total or seller key is emitted', () {
      final fields = bookingBillingCustomerPayloadFields(
        enabled: true,
        identity: _peppolPair.identity,
        defaultEmail: 'rider@example.com',
        defaultPhone: '+32470112233',
      );
      final billing = fields['billing_customer'] as Map<String, dynamic>;
      const forbidden = <String>[
        'price_incl_vat',
        'price_ex_vat',
        'price_vat',
        'total_incl_vat_cents',
        'currency',
        'vat_rate',
        'vat_treatment',
        'seller',
        'seller_snapshot',
        'seller_vat_number',
        'company_id',
        'tenant_id',
        'partner_id',
        'invoice_intent',
        'business_detected',
        'invoice_requested',
        'billing_customer_snapshot',
      ];
      for (final key in forbidden) {
        expect(billing.containsKey(key), isFalse, reason: 'leaked $key');
        expect(fields.containsKey(key), isFalse, reason: 'leaked $key');
      }
    });
  });
}
