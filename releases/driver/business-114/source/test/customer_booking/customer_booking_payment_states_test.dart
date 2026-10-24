import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_vehicles.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_payment_page.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/payment/booking_payment_options.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';

/// Public partner profile as the live API returns it today: no capability.
Map<String, dynamic> _profileWithoutCapability() => <String, dynamic>{
  'partner_id': 'company:tenant_anon:company_anon',
  'company_name': 'Anon Taxi',
  'payment_methods': <String>['bancontact', 'qr_code', 'in_vehicle_card'],
  'booking_capabilities': <String, dynamic>{'online_payments': true},
};

/// Profile once the prepared worker change is active for this company.
Map<String, dynamic> _profileFullyConfigured() => <String, dynamic>{
  'partner_id': 'company:tenant_anon:company_anon',
  'company_name': 'Anon Taxi',
  'payment_capability': <String, dynamic>{
    'payment_owner_mode': 'company_mollie',
    'payment_demo_mode': false,
    'mollie_connected': true,
    'public_payment_options': <String>['bancontact', 'qr_code'],
    'qr_transfer_available': true,
    'country': 'BE',
  },
};

/// A company that deliberately switched online payment off.
Map<String, dynamic> _profileMethodsDisabled() => <String, dynamic>{
  'partner_id': 'company:tenant_anon:company_anon',
  'payment_capability': <String, dynamic>{
    'payment_owner_mode': 'manual_only',
    'mollie_connected': false,
    'public_payment_options': <String>['in_vehicle_card'],
    'qr_transfer_available': false,
    'country': 'BE',
  },
};

Future<void> _pumpPage(
  WidgetTester tester, {
  required BookingPaymentCapability capability,
  bool loadFailed = false,
  Size size = const Size(390, 844),
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey('pay_${size.width}x${size.height}_$loadFailed'),
      home: CustomerBookingPaymentOptionsPage(
        language: AppLanguage.nl,
        palette: paletteForCustomerTheme(CustomerThemeVariant.nightGold),
        capability: capability,
        loadFailed: loadFailed,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('payment screen states', () {
    testWidgets('a failed profile request says so', (tester) async {
      await _pumpPage(
        tester,
        capability: const BookingPaymentCapability.unavailable(),
        loadFailed: true,
      );
      final message = tester.widget<Text>(
        find.byKey(kCustomerBookingPaymentUnavailableKey),
      );
      expect(message.data, contains('konden niet worden geladen'));
      // The only confirmable option remains in-vehicle, but with a reason.
      expect(
        find.byKey(customerBookingPaymentMethodKey(
          PaymentMethodIds.inVehicleCard,
        )),
        findsOneWidget,
      );
    });

    testWidgets('missing payment info is never "bankgegevens ontbreken', (
      tester,
    ) async {
      final capability = BookingPaymentCapability.fromPublicJson(
        _profileWithoutCapability(),
      );
      await _pumpPage(tester, capability: capability);
      final message = tester.widget<Text>(
        find.byKey(kCustomerBookingPaymentUnavailableKey),
      );
      expect(message.data, contains('niet beschikbaar'));
      expect(message.data, isNot(contains('heeft nog geen')));
      expect(find.textContaining('Bankgegevens ontbreken'), findsNothing);
      expect(
        find.textContaining('betaalgegevens van dit bedrijf zijn hier niet'),
        findsWidgets,
      );
    });

    testWidgets('disabled methods leave only what the company allows', (
      tester,
    ) async {
      final capability = BookingPaymentCapability.fromPublicJson(
        _profileMethodsDisabled(),
      );
      await _pumpPage(tester, capability: capability);
      final options = BookingPaymentOptions(
        capability: capability,
        countryCode: 'BE',
        languageCode: 'nl',
        isApplePlatform: false,
      );
      expect(options.isDisplayOnly(PaymentMethodIds.inVehicleCard), isFalse);
      // manual_only means online methods are not offered at all.
      expect(
        options.visibleMethodIds,
        isNot(contains(PaymentMethodIds.bancontact)),
      );
      // The company said manual only, so this is a real setting, not a gap.
      expect(capability.capabilityProjectionPresent, isTrue);
      expect(options.onlinePaymentsBlockedMessage, isNotNull);
    });

    testWidgets('a fully configured company can confirm online', (
      tester,
    ) async {
      final capability = BookingPaymentCapability.fromPublicJson(
        _profileFullyConfigured(),
      );
      await _pumpPage(tester, capability: capability);
      final options = BookingPaymentOptions(
        capability: capability,
        countryCode: 'BE',
        languageCode: 'nl',
        isApplePlatform: false,
      );
      expect(options.visibleMethodIds, contains(PaymentMethodIds.bancontact));
      expect(options.isDisplayOnly(PaymentMethodIds.bancontact), isFalse);
      expect(options.qrPaymentConfigured, isTrue);
      expect(options.qrPaymentMissingBankDetails, isFalse);
      expect(options.qrPaymentDetailsUnknown, isFalse);
      expect(find.byKey(kCustomerBookingPaymentUnavailableKey), findsNothing);
      expect(find.byKey(kCustomerBookingPaymentConfirmKey), findsOneWidget);
    });

    testWidgets('the real flow never starts from the demo account', (
      tester,
    ) async {
      const snapshot = CustomerBookingCompanySnapshot();
      expect(snapshot.payment.paymentOwnerMode, isEmpty);
      expect(snapshot.payment.capabilityProjectionPresent, isFalse);
      final options = BookingPaymentOptions(
        capability: snapshot.payment,
        countryCode: 'BE',
        languageCode: 'nl',
        isApplePlatform: false,
      );
      // Demo mode would have made Mollie methods confirmable here.
      for (final id in options.visibleMethodIds) {
        if (id == PaymentMethodIds.inVehicleCard) continue;
        expect(
          options.isDisplayOnly(id),
          isTrue,
          reason: '$id must not be confirmable without a known capability',
        );
      }
    });

    testWidgets('readable on phone, tablet and desktop widths', (tester) async {
      final capability = BookingPaymentCapability.fromPublicJson(
        _profileFullyConfigured(),
      );
      for (final size in const <Size>[
        Size(390, 844),
        Size(844, 390),
        Size(800, 1280),
        Size(1280, 800),
        Size(1600, 900),
      ]) {
        await _pumpPage(tester, capability: capability, size: size);
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow at ${size.width}x${size.height}',
        );
        expect(
          find.byKey(kCustomerBookingPaymentConfirmKey),
          findsOneWidget,
          reason: 'confirm missing at ${size.width}x${size.height}',
        );
      }
    });
  });
}
