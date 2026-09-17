import 'package:flutter/widgets.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/payment/booking_billing_identity.dart';
import 'package:fluxidi_tracking/payment/booking_billing_identity_form.dart';

/// Prefills empty billing controllers from the signed-in customer profile.
void customerBookingPrefillBillingFromProfile(
  BookingBillingIdentityControllers controllers,
  CustomerProfile? profile,
) {
  if (profile == null) return;
  void setIfBlank(TextEditingController controller, String value) {
    if (controller.text.trim().isNotEmpty) return;
    if (value.trim().isEmpty) return;
    controller.text = value.trim();
  }

  setIfBlank(controllers.legalName, profile.companyName);
  setIfBlank(controllers.vatNumber, profile.vatNumber);
  setIfBlank(controllers.registrationNumber, profile.registrationNumber);
  // A Belgian VAT number contains the enterprise number; no other country's
  // format may be reinterpreted this way.
  setIfBlank(
    controllers.registrationNumber,
    belgianEnterpriseNumberFromVat(profile.vatNumber) ?? '',
  );
  setIfBlank(controllers.street, profile.billingStreet);
  setIfBlank(controllers.postalCode, profile.billingPostalCode);
  setIfBlank(controllers.city, profile.billingCity);
  setIfBlank(controllers.country, profile.billingCountry);
  setIfBlank(controllers.contactEmail, profile.invoiceEmail);
  setIfBlank(controllers.peppolEndpointId, profile.peppolEndpointId);
  setIfBlank(controllers.peppolScheme, profile.peppolScheme);
  if (controllers.country.text.trim().isEmpty) {
    controllers.country.text = 'BE';
  }
}

/// What can be done with a typed contact phone.
enum CustomerBookingPhoneState {
  /// Nothing entered.
  empty,

  /// Usable international number.
  international,

  /// A national number with no phone country to complete it. The customer
  /// must say which country the number belongs to; guessing one would send a
  /// wrong number to the driver.
  needsCountry,

  /// Entered as international but not a usable number.
  invalid,
}

class CustomerBookingPhone {
  const CustomerBookingPhone({required this.state, required this.e164});

  final CustomerBookingPhoneState state;

  /// Filled only for [CustomerBookingPhoneState.international].
  final String e164;

  bool get isUsable => state == CustomerBookingPhoneState.international;
}

/// Resolves the booking contact phone for private and business rides alike.
///
/// `+` and `00` follow the existing international contract and are accepted on
/// their own. A national number is only completed from an explicit
/// [phoneCountryCallingCode] or a stored [phoneCountry]; the billing address
/// is never used for this, because where someone is invoiced says nothing
/// about which network their number belongs to.
CustomerBookingPhone resolveCustomerBookingPhone({
  required String phone,
  String phoneCountryCallingCode = '',
  String phoneCountry = '',
}) {
  final raw = phone.trim();
  if (raw.isEmpty) {
    return const CustomerBookingPhone(
      state: CustomerBookingPhoneState.empty,
      e164: '',
    );
  }
  final explicitInternational = raw.startsWith('+') || raw.startsWith('00');
  final callingCode = phoneCountryCallingCode.trim().isNotEmpty
      ? phoneCountryCallingCode.trim()
      : customerBookingCountryCallingCode(phoneCountry);
  final parsed = normalizeCompanyCustomerPhone(raw, callingCode);
  if (parsed.e164.isNotEmpty) {
    return CustomerBookingPhone(
      state: CustomerBookingPhoneState.international,
      e164: parsed.e164,
    );
  }
  return CustomerBookingPhone(
    state: explicitInternational
        ? CustomerBookingPhoneState.invalid
        : CustomerBookingPhoneState.needsCountry,
    e164: '',
  );
}

/// The contact phone to send, or the raw input when it cannot be completed.
///
/// Never invents a country: an ambiguous national number is passed through
/// unchanged and the form asks the customer to clarify.
String customerBookingInternationalPhone({
  required String phone,
  String phoneCountryCallingCode = '',
  String phoneCountry = '',
}) {
  final resolved = resolveCustomerBookingPhone(
    phone: phone,
    phoneCountryCallingCode: phoneCountryCallingCode,
    phoneCountry: phoneCountry,
  );
  return resolved.isUsable ? resolved.e164 : phone.trim();
}

/// Calling code for the ISO country codes the fleet books in. Unknown
/// countries return empty so no wrong prefix is invented.
String customerBookingCountryCallingCode(String country) {
  const codes = <String, String>{
    'BE': '32',
    'NL': '31',
    'FR': '33',
    'LU': '352',
    'DE': '49',
    'GB': '44',
    'UK': '44',
    'ES': '34',
    'IT': '39',
    'PT': '351',
    'AT': '43',
    'CH': '41',
    'DK': '45',
    'SE': '46',
    'NO': '47',
    'PL': '48',
    'IE': '353',
  };
  return codes[country.trim().toUpperCase()] ?? '';
}

/// Canonical `billing_customer` fragment. Off or blank identity sends nothing,
/// so leftover typed business fields never ride along on a private booking.
Map<String, dynamic> customerBookingBillingPayloadFields({
  required bool businessRide,
  required BookingBillingIdentity identity,
  required String defaultEmail,
  required String defaultPhone,
}) {
  return bookingBillingCustomerPayloadFields(
    enabled: businessRide,
    identity: identity,
    defaultEmail: defaultEmail,
    defaultPhone: defaultPhone,
  );
}
