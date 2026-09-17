// Shared customer-address and customer-list helpers for plan + quote.

import 'package:fluxidi_tracking/company/company_address_field.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/company/company_trip_route.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

enum CompanyCustomerGroundSlot { pickup, dropoff }

CompanyCustomer companyCustomerUnspecified() {
  return const CompanyCustomer(
    customerId: '',
    tenantId: '',
    companyId: '',
    displayName: '',
    firstName: '',
    lastName: '',
    phone: '',
    phoneNormalized: '',
    countryCallingCode: '',
    email: '',
    locale: '',
    companyName: '',
    vatNumber: '',
    addresses: <CompanyCustomerAddress>[],
    internalNotes: '',
    preferences: CompanyCustomerPreferences(),
    source: 'manual',
    status: 'active',
    createdAt: '',
    updatedAt: '',
    archivedAt: null,
    revision: 1,
  );
}

bool companyCustomerIsSpecified(CompanyCustomer customer) {
  return customer.customerId.trim().isNotEmpty && !customer.isArchived;
}

String companyCustomerListItemLabel(CompanyCustomerListItem item) {
  final name = item.displayName.trim();
  if (name.isNotEmpty) return name;
  final company = item.companyName.trim();
  if (company.isNotEmpty) return company;
  return item.customerId.trim();
}

bool companyCustomerListItemMatches(
  CompanyCustomerListItem item,
  String rawNeedle,
) {
  if (item.isArchived) return false;
  final needle = rawNeedle.trim().toLowerCase();
  if (needle.isEmpty) return true;
  final haystack = <String>[
    item.displayName,
    item.companyName,
    item.phoneMasked,
    item.emailMasked,
    item.customerId,
  ].join(' ').toLowerCase();
  return haystack.contains(needle);
}

CompanyCustomerAddress? companyCustomerPreferredAddress(
  CompanyCustomer customer,
) {
  final usable = [
    for (final address in customer.addresses)
      if (companyCustomerAddressLine(address).trim().isNotEmpty) address,
  ];
  if (usable.isEmpty) return null;
  // Within one type, an address that names a street beats a bare locality:
  // picking the latter is what turned a full pickup into "9688 Maarkedal, BE".
  CompanyCustomerAddress? bestOf(Iterable<CompanyCustomerAddress> candidates) {
    CompanyCustomerAddress? fallback;
    for (final address in candidates) {
      if (address.line1.trim().isNotEmpty) return address;
      fallback ??= address;
    }
    return fallback;
  }

  for (final type in const ['home', 'pickup', 'work', 'billing']) {
    final ofType = usable.where(
      (address) => address.type.trim().toLowerCase() == type,
    );
    final chosen = bestOf(ofType);
    if (chosen != null) return chosen;
  }
  return bestOf(usable) ?? usable.first;
}

CompanyCustomerGroundSlot companyCustomerGroundSlotForOptions(
  CompanyRideOptions options,
) {
  return companyTripRouteKindOf(options) == CompanyTripRouteKind.fromAirport
      ? CompanyCustomerGroundSlot.dropoff
      : CompanyCustomerGroundSlot.pickup;
}

void companyApplySavedAddress(
  LimousineAddressFieldController field,
  CompanyCustomerAddress address,
) {
  field.acceptCopy(companyAddressValueFromSaved(address));
}

void companyApplyCustomerGroundAddress({
  required CompanyCustomer customer,
  required CompanyRideOptions options,
  required LimousineAddressFieldController pickup,
  required LimousineAddressFieldController dropoff,
  CompanyCustomerAddress? address,
  bool overwritePickup = true,
  bool overwriteDropoff = true,
}) {
  final chosen = address ?? companyCustomerPreferredAddress(customer);
  if (chosen == null) return;
  final slot = companyCustomerGroundSlotForOptions(options);
  if (slot == CompanyCustomerGroundSlot.dropoff) {
    if (overwriteDropoff) companyApplySavedAddress(dropoff, chosen);
    return;
  }
  if (overwritePickup) companyApplySavedAddress(pickup, chosen);
}
