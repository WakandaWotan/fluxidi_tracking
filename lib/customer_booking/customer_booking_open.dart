import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_checkout.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_flow.dart';
import 'package:fluxidi_tracking/payment/pending_payment.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool> customerBookingOpenHostedCheckout(
  CustomerBookingCheckoutPlan plan,
) async {
  if (!plan.canOpen) return false;
  if (plan.paymentBookingId.isNotEmpty) {
    setFluxidiPendingPayment(
      paymentBookingId: plan.paymentBookingId,
      publicBookingId: plan.publicReference.isEmpty ? null : plan.publicReference,
    );
    markFluxidiPendingPaymentChecking(paymentBookingId: plan.paymentBookingId);
  }
  final uri = Uri.tryParse(plan.checkoutUrl);
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<T?> openCustomerBookingFlow<T>(
  BuildContext context, {
  required CustomerBookingEntryContext entry,
  String? bookingBaseUrl,
  AppLanguage? language,
  WidgetBuilder? onGoToStartPage,
}) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      builder: (_) => CustomerBookingFlow(
        entry: entry,
        bookingBaseUrl: bookingBaseUrl ?? kBookingBaseUrl,
        language: language ?? appConfig.currentLanguage,
        onGoToStartPage: onGoToStartPage,
        hostedCheckout: customerBookingOpenHostedCheckout,
      ),
    ),
  );
}
