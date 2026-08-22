/// Canonical buyer billing identity shared by the taxi, airport and limousine
/// booking surfaces.
///
/// This is the BUYER only. The seller is resolved server-side from the
/// company/business profile bound to the booking scope, so nothing here may
/// ever describe the selling company.
///
/// `POST /book` reads the `billing_customer` fragment produced here through
/// `normalizeBillingCustomerIdentityInput` and derives
/// `billing_customer_snapshot`, `business_detected` and `invoice_intent`
/// itself. Clients therefore send identity only and never claim intent.
library;

/// Buyer-entered billing fields, held raw so a surface can bind its text
/// controllers directly. Every read trims, matching the controller-based
/// behaviour the taxi and airport pages have always had.
class BookingBillingIdentity {
  const BookingBillingIdentity({
    this.legalName = '',
    this.vatNumber = '',
    this.registrationNumber = '',
    this.street = '',
    this.postalCode = '',
    this.city = '',
    this.country = '',
    this.contactEmail = '',
    this.peppolEndpointId = '',
    this.peppolScheme = '',
  });

  final String legalName;
  final String vatNumber;
  final String registrationNumber;
  final String street;
  final String postalCode;
  final String city;
  final String country;
  final String contactEmail;
  final String peppolEndpointId;
  final String peppolScheme;

  static const BookingBillingIdentity empty = BookingBillingIdentity();

  String get trimmedLegalName => legalName.trim();
  String get trimmedVatNumber => vatNumber.trim();
  String get trimmedRegistrationNumber => registrationNumber.trim();
  String get trimmedStreet => street.trim();
  String get trimmedPostalCode => postalCode.trim();
  String get trimmedCity => city.trim();

  /// Uppercased to match the canonical two-letter ISO country the Worker
  /// normalizer expects.
  String get trimmedCountry => country.trim().toUpperCase();
  String get trimmedContactEmail => contactEmail.trim();
  String get trimmedPeppolEndpointId => peppolEndpointId.trim();
  String get trimmedPeppolScheme => peppolScheme.trim();

  bool get addressComplete =>
      trimmedStreet.isNotEmpty &&
      trimmedPostalCode.isNotEmpty &&
      trimmedCity.isNotEmpty &&
      trimmedCountry.isNotEmpty;

  /// A legal person needs a name plus either a VAT number or a company
  /// registration (KBO/enterprise) number. Either satisfies the same
  /// legal-identity slot for Peppol readiness.
  bool get hasLegalIdentity =>
      trimmedLegalName.isNotEmpty &&
      (trimmedVatNumber.isNotEmpty || trimmedRegistrationNumber.isNotEmpty);

  /// The canonical completeness rule taxi and airport already apply.
  bool get isCompleteForBusinessInvoice => hasLegalIdentity && addressComplete;

  /// Whether anything meaningful was entered. Mirrors the Worker's own
  /// meaningful-field gate, so an all-blank business toggle sends nothing.
  bool get hasAnyField =>
      trimmedLegalName.isNotEmpty ||
      trimmedVatNumber.isNotEmpty ||
      trimmedRegistrationNumber.isNotEmpty ||
      trimmedStreet.isNotEmpty ||
      trimmedPostalCode.isNotEmpty ||
      trimmedCity.isNotEmpty ||
      trimmedCountry.isNotEmpty ||
      trimmedPeppolEndpointId.isNotEmpty ||
      trimmedPeppolScheme.isNotEmpty;

  BookingBillingIdentity copyWith({
    String? legalName,
    String? vatNumber,
    String? registrationNumber,
    String? street,
    String? postalCode,
    String? city,
    String? country,
    String? contactEmail,
    String? peppolEndpointId,
    String? peppolScheme,
  }) {
    return BookingBillingIdentity(
      legalName: legalName ?? this.legalName,
      vatNumber: vatNumber ?? this.vatNumber,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      street: street ?? this.street,
      postalCode: postalCode ?? this.postalCode,
      city: city ?? this.city,
      country: country ?? this.country,
      contactEmail: contactEmail ?? this.contactEmail,
      peppolEndpointId: peppolEndpointId ?? this.peppolEndpointId,
      peppolScheme: peppolScheme ?? this.peppolScheme,
    );
  }
}

/// The first required field that is still missing for a business invoice, or
/// null when the identity is complete. Order matches the form field order so a
/// surface can point the customer at the next thing to fix.
BookingBillingIdentityField? firstMissingBookingBillingIdentityField(
  BookingBillingIdentity identity,
) {
  if (identity.trimmedLegalName.isEmpty) {
    return BookingBillingIdentityField.legalName;
  }
  if (identity.trimmedVatNumber.isEmpty &&
      identity.trimmedRegistrationNumber.isEmpty) {
    return BookingBillingIdentityField.legalIdentityNumber;
  }
  if (!identity.addressComplete) {
    return BookingBillingIdentityField.address;
  }
  return null;
}

/// Required-field groups a surface can report on.
enum BookingBillingIdentityField { legalName, legalIdentityNumber, address }

/// Builds the canonical optional `billing_customer` payload fragment.
///
/// Returns an empty map when the business-invoice choice is off or nothing
/// meaningful was entered, so a private booking's payload stays byte-identical
/// to what it has always been.
///
/// [defaultEmail] and [defaultPhone] supply the buyer's contact channel when no
/// dedicated invoice email was typed; they are the booking's own contact
/// fields, never another customer's and never the seller's.
Map<String, dynamic> bookingBillingCustomerPayloadFields({
  required bool enabled,
  required BookingBillingIdentity identity,
  required String defaultEmail,
  required String defaultPhone,
}) {
  if (!enabled) return const <String, dynamic>{};
  final legalName = identity.trimmedLegalName;
  final vat = identity.trimmedVatNumber;
  final registrationNumber = identity.trimmedRegistrationNumber;
  final street = identity.trimmedStreet;
  final postal = identity.trimmedPostalCode;
  final city = identity.trimmedCity;
  final country = identity.trimmedCountry;
  final contactEmail = identity.trimmedContactEmail.isNotEmpty
      ? identity.trimmedContactEmail
      : defaultEmail.trim();
  final contactPhone = defaultPhone.trim();
  final peppolEndpoint = identity.trimmedPeppolEndpointId;
  final peppolScheme = identity.trimmedPeppolScheme;

  if (!identity.hasAnyField) return const <String, dynamic>{};

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
