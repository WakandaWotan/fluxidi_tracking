import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/nearby_partners_page.dart';

CustomerBookingCompany? customerBookingCompanyFromNearbySelection(
  Map<String, String>? selected,
) {
  if (selected == null) return null;
  final partnerId = (selected['partner_id'] ?? '').trim();
  if (partnerId.isEmpty) return null;
  return CustomerBookingCompany(
    partnerId: partnerId,
    tenantId: (selected['tenant_id'] ?? '').trim(),
    companyId: (selected['company_id'] ?? '').trim(),
    companyCode: (selected['company_code'] ?? '').trim(),
    companyName: (selected['company_name'] ?? '').trim(),
    logoUrl: (selected['logo_url'] ?? '').trim(),
  );
}

bool customerBookingCompanyIsChosen(CustomerBookingCompany company) {
  return company.routingPartnerId.isNotEmpty;
}

String customerBookingCompanyVisibleName(CustomerBookingCompany company) {
  final name = company.companyName.trim();
  if (name.isNotEmpty) return name;
  return company.companyCode.trim();
}

Future<CustomerBookingCompany?> pickCustomerBookingCompany(
  BuildContext context, {
  bool airportCapableOnly = false,
  WidgetBuilder? customerHomeBuilder,
}) async {
  final selected = await Navigator.of(context).push<Map<String, String>>(
    MaterialPageRoute(
      builder: (_) => NearbyPartnersPage(
        customerHomeBuilder:
            customerHomeBuilder ?? (_) => const SizedBox.shrink(),
        regionRegistrationBuilder:
            customerHomeBuilder ?? (_) => const SizedBox.shrink(),
        syncCustomerProfileFromBackend: ({required String reason}) {
          return CustomerProfileStore.instance.load();
        },
        selectionMode: true,
        airportCapableOnly: airportCapableOnly,
      ),
    ),
  );
  return customerBookingCompanyFromNearbySelection(selected);
}
