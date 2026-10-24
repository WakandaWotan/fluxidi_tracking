import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_vehicles.dart';
import 'package:fluxidi_tracking/payment/booking_payment_options.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';

/// Shape the public partner profile actually returns today.
Map<String, dynamic> _publicPartnerProfile() {
  return <String, dynamic>{
    'partner_id': 'partner_anon',
    'company_name': 'Anon Taxi',
    'country': 'BE',
    'payment_methods': <String>['bancontact', 'qr_code', 'in_vehicle_card'],
    'booking_capabilities': <String, dynamic>{'online_payments': true},
  };
}

/// Shape a worker that publishes the capability projection returns.
Map<String, dynamic> _profileWithCapability() {
  return <String, dynamic>{
    'partner_id': 'partner_anon',
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
}

void main() {
  group('payment capability mapping', () {
    test('a profile without a capability projection is reported as such', () {
      final capability = BookingPaymentCapability.fromPublicJson(
        _publicPartnerProfile(),
      );
      expect(capability.capabilityProjectionPresent, isFalse);
      // Online must stay blocked: nothing confirms the company can take it.
      expect(capability.paymentOwnerMode, isEmpty);
      expect(capability.mollieConnected, isFalse);
      expect(capability.qrTransferAvailable, isFalse);
    });

    test('published payment_methods are no longer silently dropped', () {
      final capability = BookingPaymentCapability.fromPublicJson(
        _publicPartnerProfile(),
      );
      expect(capability.publicPaymentOptions, contains('bancontact'));
      expect(capability.enabledPaymentOptionIds, isNotEmpty);
      expect(capability.countryCode, 'BE');
    });

    test('a nested capability projection is read in full', () {
      final capability = BookingPaymentCapability.fromPublicJson(
        _profileWithCapability(),
      );
      expect(capability.capabilityProjectionPresent, isTrue);
      expect(capability.paymentOwnerMode, 'company_mollie');
      expect(capability.mollieConnected, isTrue);
      expect(capability.qrTransferAvailable, isTrue);
      expect(capability.qrPaymentConfigured, isTrue);
    });

    test('camelCase keys are accepted alongside snake_case', () {
      final capability = BookingPaymentCapability.fromPublicJson(
        <String, dynamic>{
          'paymentOwnerMode': 'company_mollie',
          'mollieConnected': true,
          'qrTransferAvailable': true,
          'publicPaymentOptions': <String>['bancontact'],
        },
      );
      expect(capability.paymentOwnerMode, 'company_mollie');
      expect(capability.mollieConnected, isTrue);
      expect(capability.qrTransferAvailable, isTrue);
      expect(capability.publicPaymentOptions, <String>['bancontact']);
    });

    test('a load failure is distinct from a company without settings', () {
      const failed = BookingPaymentCapability.unavailable();
      expect(failed.capabilityProjectionPresent, isFalse);
      expect(failed.paymentOwnerMode, isEmpty);

      final published = BookingPaymentCapability.fromPublicJson(
        _profileWithCapability(),
      );
      expect(published.capabilityProjectionPresent, isTrue);
    });

    test('QR stays display-only until the company reports bank details', () {
      final withoutBank = BookingPaymentOptions(
        capability: BookingPaymentCapability.fromPublicJson(
          _publicPartnerProfile(),
        ),
        countryCode: 'BE',
        languageCode: 'nl',
        isApplePlatform: false,
      );
      if (withoutBank.visibleMethodIds.contains(PaymentMethodIds.qrCode)) {
        expect(withoutBank.isDisplayOnly(PaymentMethodIds.qrCode), isTrue);
        // No capability was reported, so this is "not known", not "no IBAN".
        expect(withoutBank.qrPaymentDetailsUnknown, isTrue);
        expect(withoutBank.qrPaymentMissingBankDetails, isFalse);
      }
      expect(
        withoutBank.isDisplayOnly(PaymentMethodIds.inVehicleCard),
        isFalse,
      );

      final withBank = BookingPaymentOptions(
        capability: BookingPaymentCapability.fromPublicJson(
          _profileWithCapability(),
        ),
        countryCode: 'BE',
        languageCode: 'nl',
        isApplePlatform: false,
      );
      expect(withBank.qrPaymentConfigured, isTrue);
      expect(withBank.qrPaymentMissingBankDetails, isFalse);
    });

    test('status distinguishes load failure, missing and not offered', () {
      final failed = BookingPaymentCapability.fromPublicJson(
        <String, dynamic>{'payment_capability_status': 'load_failed'},
      );
      expect(failed.projectionStatus, BookingPaymentCapabilityStatus.loadFailed);
      expect(failed.capabilityProjectionPresent, isFalse);

      final missing = BookingPaymentCapability.fromPublicJson(
        <String, dynamic>{'payment_capability_status': 'missing'},
      );
      expect(missing.projectionStatus, BookingPaymentCapabilityStatus.missing);
      expect(missing.capabilityProjectionPresent, isFalse);

      final notOffered = BookingPaymentCapability.fromPublicJson(
        <String, dynamic>{
          'payment_capability_status': 'not_offered',
          'payment_capability': <String, dynamic>{
            'payment_owner_mode': 'manual_only',
            'mollie_connected': false,
            'qr_transfer_available': false,
          },
        },
      );
      expect(
        notOffered.projectionStatus,
        BookingPaymentCapabilityStatus.notOffered,
      );
      expect(notOffered.capabilityProjectionPresent, isTrue);
      expect(notOffered.paymentOwnerMode, 'manual_only');
    });

    test('the company snapshot carries the mapped capability', () {
      final snapshot = customerBookingCompanySnapshotFromProfile(
        _profileWithCapability(),
      );
      expect(snapshot.payment.paymentOwnerMode, 'company_mollie');
      expect(snapshot.payment.capabilityProjectionPresent, isTrue);
    });
  });
}
