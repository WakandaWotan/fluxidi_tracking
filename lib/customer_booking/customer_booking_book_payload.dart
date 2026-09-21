// Fields the working calculator and website send on POST /book.
// Customer taxi and airport must use the same payment contract.

import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/payment/payment_booking_selection.dart';
import 'package:fluxidi_tracking/payment_return.dart';

const String kCustomerBookingBookSource = 'customer_booking';
const String kCustomerBookingBookChannel = 'flutter_customer';

/// Mollie return + payment fields for the shared taxi/airport /book body.
Map<String, dynamic> customerBookingBookContractFields({
  required BookingPaymentSelection selection,
  required CustomerBookingKind kind,
  CompanyPlanQuoteResult? quote,
}) {
  return <String, dynamic>{
    ...selection.toPayloadFields(),
    'return_url': kFluxidiPaymentReturnUrl,
    'returnUrl': kFluxidiPaymentReturnUrl,
    'booking_source': kCustomerBookingBookSource,
    'entry_channel': kCustomerBookingBookChannel,
    'entry_kind': kind.name,
    ...customerBookingQuoteBookFields(quote),
  };
}

Map<String, dynamic> customerBookingQuoteBookFields(
  CompanyPlanQuoteResult? quote,
) {
  if (quote == null) return const <String, dynamic>{};
  return <String, dynamic>{
    'quote': <String, dynamic>{
      'ok': true,
      'price_available': quote.priceAvailable,
      if (quote.priceInclVat != null) 'price_incl_vat': quote.priceInclVat,
      if (quote.displayTotalPrice != null)
        'total_price_incl_vat': quote.displayTotalPrice,
      if (quote.outboundPriceInclVat != null)
        'outbound_price_incl_vat': quote.outboundPriceInclVat,
      if (quote.returnPriceInclVat != null)
        'return_price_incl_vat': quote.returnPriceInclVat,
      if (quote.distanceKm != null) 'distance_km': quote.distanceKm,
      if (quote.durationMin != null) 'duration_min': quote.durationMin,
      'currency': quote.currency,
      if (quote.pricingSource.isNotEmpty) 'pricing_source': quote.pricingSource,
      if (quote.fixedPriceSnapshot != null)
        'fixed_price_snapshot': quote.fixedPriceSnapshot,
    },
  };
}
