/// Characterization tests for the payment picker rules that taxi and airport
/// use today.
///
/// `calculator_page.dart` and `airport_booking_review_page.dart` each carried
/// their own copy of these decisions, and neither had test coverage. These
/// tests pin the current behaviour so moving both pages onto the shared
/// [BookingPaymentOptions] seam is provably a no-op for them.
///
/// Every expectation is computed twice: once through the seam, and once by
/// replaying the exact expressions the two pages used inline. If the seam ever
/// drifts from that original logic, these fail.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fluxidi_tracking/payment/booking_payment_options.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';
import 'package:fluxidi_tracking/payment/payment_method_resolver.dart';

/// Stand-in for the profile fields the two pages read off
/// `localBackendBusinessProfileNotifier`.
class _Profile {
  const _Profile({
    this.paymentOwnerMode = 'fluxidi_central_demo',
    this.paymentDemoMode = true,
    this.mollieConnected = false,
    this.livePaymentsEnabled,
    this.mollieForcedTestMode,
    this.publicPaymentOptions = const <String>[],
    this.iban = '',
  });

  final String paymentOwnerMode;
  final bool paymentDemoMode;
  final bool mollieConnected;
  final bool? livePaymentsEnabled;
  final bool? mollieForcedTestMode;
  final List<String> publicPaymentOptions;
  final String iban;
}

// --------------------------------------------------------------------------
// The original inline logic, copied verbatim from the two pages.
// --------------------------------------------------------------------------

PaymentOwnershipGate _legacyGate(_Profile? profile) {
  if (profile == null) return const PaymentOwnershipGate();
  return PaymentOwnershipGate(
    paymentOwnerMode: profile.paymentOwnerMode,
    paymentDemoMode: profile.paymentDemoMode,
    mollieConnected: profile.mollieConnected,
  );
}

PaymentMethodClientContext _legacyClientContext(
  _Profile? profile, {
  required bool isApplePlatform,
}) {
  final forcedTestMode = PaymentMethodResolver.inferMollieForcedTestMode(
    gate: _legacyGate(profile),
    livePaymentsEnabled: profile?.livePaymentsEnabled,
    mollieForcedTestMode: profile?.mollieForcedTestMode,
  );
  return PaymentMethodClientContext.forPlatform(
    isApplePlatform: isApplePlatform,
    supportsGooglePayCheckout: !forcedTestMode,
  );
}

bool _legacyBlocksGooglePay(_Profile? profile) =>
    PaymentMethodResolver.blocksGooglePayBookSubmit(
      gate: _legacyGate(profile),
      livePaymentsEnabled: profile?.livePaymentsEnabled,
      mollieForcedTestMode: profile?.mollieForcedTestMode,
    );

List<String> _legacyEnabledIds(_Profile? profile) => profile == null
    ? const <String>[]
    : filterPublicPartnerPaymentOptionIds(profile.publicPaymentOptions);

ResolvedPaymentMethods _legacyResolved(
  _Profile? profile, {
  required String countryCode,
  required String languageCode,
  required bool isApplePlatform,
}) => PaymentMethodResolver.resolve(
  countryCode: countryCode,
  enabledPublicPaymentOptionIds: _legacyEnabledIds(profile),
  ownershipGate: _legacyGate(profile),
  clientContext: _legacyClientContext(
    profile,
    isApplePlatform: isApplePlatform,
  ),
  languageCode: languageCode,
);

bool _legacyQrConfigured(_Profile? profile) =>
    (profile?.iban.trim().isNotEmpty ?? false);

bool _legacyIsDisplayOnly(_Profile? profile, String methodId) {
  final id = normalizePaymentMethodId(methodId);
  final def = PaymentMethodCatalog.definitionFor(id);
  if (def == null) return true;
  if (id == PaymentMethodIds.inVehicleCard) return false;
  if (id == PaymentMethodIds.qrCode) return !_legacyQrConfigured(profile);
  if (PaymentMethodResolver.isGooglePayMethodId(id) &&
      _legacyBlocksGooglePay(profile)) {
    return true;
  }
  return !def.isSupportedMollieCheckout;
}

bool _legacyIsDirectCheckout(_Profile? profile, String methodId) {
  if (_legacyIsDisplayOnly(profile, methodId)) return false;
  return PaymentMethodCatalog.definitionFor(
        methodId,
      )?.isSupportedMollieCheckout ??
      false;
}

bool _legacyIsSelectableExternal(_Profile? profile, String methodId) {
  final id = normalizePaymentMethodId(methodId);
  final def = PaymentMethodCatalog.definitionFor(id);
  if (def == null) return false;
  if (def.isSupportedMollieCheckout) return false;
  if (id == PaymentMethodIds.inVehicleCard) return true;
  if (id == PaymentMethodIds.qrCode) return _legacyQrConfigured(profile);
  return false;
}

// --------------------------------------------------------------------------

BookingPaymentOptions _seam(
  _Profile? profile, {
  required String countryCode,
  required String languageCode,
  required bool isApplePlatform,
}) => BookingPaymentOptions(
  capability: profile == null
      ? const BookingPaymentCapability.unknown()
      : BookingPaymentCapability(
          paymentOwnerMode: profile.paymentOwnerMode,
          paymentDemoMode: profile.paymentDemoMode,
          mollieConnected: profile.mollieConnected,
          livePaymentsEnabled: profile.livePaymentsEnabled,
          mollieForcedTestMode: profile.mollieForcedTestMode,
          publicPaymentOptions: profile.publicPaymentOptions,
          qrTransferAvailable: profile.iban.trim().isNotEmpty,
        ),
  countryCode: countryCode,
  languageCode: languageCode,
  isApplePlatform: isApplePlatform,
);

/// The company/profile shapes the two pages can realistically encounter.
const Map<String, _Profile?> _profiles = <String, _Profile?>{
  'no profile loaded': null,
  'central demo': _Profile(),
  'manual only': _Profile(paymentOwnerMode: 'manual_only'),
  'company mollie, not linked': _Profile(paymentOwnerMode: 'company_mollie'),
  'company mollie, linked, live': _Profile(
    paymentOwnerMode: 'company_mollie',
    mollieConnected: true,
    livePaymentsEnabled: true,
  ),
  'company mollie, linked, test mode': _Profile(
    paymentOwnerMode: 'company_mollie',
    mollieConnected: true,
    livePaymentsEnabled: false,
  ),
  'company mollie, linked, forced test mode': _Profile(
    paymentOwnerMode: 'company_mollie',
    mollieConnected: true,
    mollieForcedTestMode: true,
  ),
  'unrecognised owner mode': _Profile(paymentOwnerMode: 'something_new'),
  'published subset': _Profile(
    mollieConnected: true,
    livePaymentsEnabled: true,
    publicPaymentOptions: <String>[
      PaymentMethodIds.bancontact,
      PaymentMethodIds.cardPayment,
    ],
  ),
  'published subset with unknown id': _Profile(
    mollieConnected: true,
    livePaymentsEnabled: true,
    publicPaymentOptions: <String>['not_a_method', PaymentMethodIds.bancontact],
  ),
  'iban filled in': _Profile(iban: 'BE68539007547034'),
  'iban blank': _Profile(iban: '   '),
};

const List<String> _countries = <String>[
  PaymentCountryCodes.belgium,
  PaymentCountryCodes.netherlands,
  PaymentCountryCodes.france,
  PaymentCountryCodes.spain,
  '',
];

void main() {
  group('the shared seam reproduces the inline taxi/airport rules', () {
    for (final entry in _profiles.entries) {
      for (final country in _countries) {
        for (final isApplePlatform in const <bool>[false, true]) {
          final label =
              '${entry.key} / country "$country" / apple=$isApplePlatform';
          test(label, () {
            final profile = entry.value;
            const languageCode = 'nl';
            final options = _seam(
              profile,
              countryCode: country,
              languageCode: languageCode,
              isApplePlatform: isApplePlatform,
            );
            final legacy = _legacyResolved(
              profile,
              countryCode: country,
              languageCode: languageCode,
              isApplePlatform: isApplePlatform,
            );

            expect(options.visibleMethodIds, legacy.ids);
            expect(options.resolved.countryCode, legacy.countryCode);
            expect(options.resolved.enabledFilterApplied, legacy.enabledFilterApplied);
            expect(
              options.resolved.onlinePaymentsAvailable,
              legacy.onlinePaymentsAvailable,
            );
            expect(
              options.onlinePaymentsBlockedMessage,
              legacy.onlinePaymentsBlockedMessage,
            );
            expect(options.blocksGooglePayBookSubmit, _legacyBlocksGooglePay(profile));
            expect(options.qrPaymentConfigured, _legacyQrConfigured(profile));

            // Per-method classification, over the union of every known method
            // so a method that is currently hidden is still characterized.
            for (final id in PaymentMethodCatalog.knownIds) {
              expect(
                options.isDisplayOnly(id),
                _legacyIsDisplayOnly(profile, id),
                reason: 'isDisplayOnly($id) for $label',
              );
              expect(
                options.isDirectCheckout(id),
                _legacyIsDirectCheckout(profile, id),
                reason: 'isDirectCheckout($id) for $label',
              );
              expect(
                options.isSelectableExternal(id),
                _legacyIsSelectableExternal(profile, id),
                reason: 'isSelectableExternal($id) for $label',
              );
            }
          });
        }
      }
    }
  });

  group('the blocked-online message keeps its per-language wording', () {
    for (final languageCode in const <String>['nl', 'en', 'fr', 'es']) {
      test('language $languageCode', () {
        const profile = _Profile(paymentOwnerMode: 'manual_only');
        final options = _seam(
          profile,
          countryCode: PaymentCountryCodes.belgium,
          languageCode: languageCode,
          isApplePlatform: false,
        );
        expect(
          options.onlinePaymentsBlockedMessage,
          _legacyResolved(
            profile,
            countryCode: PaymentCountryCodes.belgium,
            languageCode: languageCode,
            isApplePlatform: false,
          ).onlinePaymentsBlockedMessage,
        );
        expect(options.onlinePaymentsBlockedMessage, isNotNull);
        expect(
          options.googlePayBlockedMessage(),
          PaymentMethodResolver.googlePayTestModeUnavailableMessage(
            languageCode: languageCode,
          ),
        );
      });
    }
  });

  group('the observable picker guarantees', () {
    test('a manual option is always offered, even when online is blocked', () {
      final options = _seam(
        const _Profile(paymentOwnerMode: 'manual_only'),
        countryCode: PaymentCountryCodes.belgium,
        languageCode: 'nl',
        isApplePlatform: false,
      );
      expect(
        options.visibleMethodIds.any(
          PaymentMethodCatalog.alwaysVisibleManualMethodIds.contains,
        ),
        isTrue,
      );
      expect(options.onlinePaymentsBlockedMessage, isNotNull);
    });

    test('a company without online payments offers no hosted checkout', () {
      final options = _seam(
        const _Profile(paymentOwnerMode: 'manual_only'),
        countryCode: PaymentCountryCodes.belgium,
        languageCode: 'nl',
        isApplePlatform: false,
      );
      expect(options.resolved.onlinePaymentsAvailable, isFalse);
      expect(options.visibleMethodIds.where(options.isDirectCheckout), isEmpty);
    });

    test('a linked live company does offer hosted checkout', () {
      final options = _seam(
        const _Profile(
          paymentOwnerMode: 'company_mollie',
          mollieConnected: true,
          livePaymentsEnabled: true,
        ),
        countryCode: PaymentCountryCodes.belgium,
        languageCode: 'nl',
        isApplePlatform: false,
      );
      expect(options.resolved.onlinePaymentsAvailable, isTrue);
      expect(options.onlinePaymentsBlockedMessage, isNull);
      expect(
        options.visibleMethodIds.where(options.isDirectCheckout),
        isNotEmpty,
      );
    });

    test('Google Pay cannot be confirmed in forced test mode', () {
      final options = _seam(
        const _Profile(
          paymentOwnerMode: 'company_mollie',
          mollieConnected: true,
          livePaymentsEnabled: false,
        ),
        countryCode: PaymentCountryCodes.belgium,
        languageCode: 'nl',
        isApplePlatform: false,
      );
      expect(options.mollieForcedTestMode, isTrue);
      expect(options.blocksGooglePayBookSubmit, isTrue);
      expect(options.isGooglePaySubmitBlocked(PaymentMethodIds.googlePay), isTrue);
      expect(options.isDisplayOnly(PaymentMethodIds.googlePay), isTrue);
      expect(options.isDirectCheckout(PaymentMethodIds.googlePay), isFalse);
    });

    test('Apple Pay only appears on Apple platforms', () {
      const profile = _Profile(
        paymentOwnerMode: 'company_mollie',
        mollieConnected: true,
        livePaymentsEnabled: true,
      );
      final android = _seam(
        profile,
        countryCode: PaymentCountryCodes.belgium,
        languageCode: 'nl',
        isApplePlatform: false,
      );
      expect(android.visibleMethodIds, isNot(contains(PaymentMethodIds.applePay)));
    });

    test('QR transfer is display-only until an IBAN exists', () {
      final without = _seam(
        const _Profile(),
        countryCode: PaymentCountryCodes.belgium,
        languageCode: 'nl',
        isApplePlatform: false,
      );
      expect(without.qrPaymentConfigured, isFalse);
      expect(without.isDisplayOnly(PaymentMethodIds.qrCode), isTrue);
      expect(without.isSelectableExternal(PaymentMethodIds.qrCode), isFalse);

      final with_ = _seam(
        const _Profile(iban: 'BE68539007547034'),
        countryCode: PaymentCountryCodes.belgium,
        languageCode: 'nl',
        isApplePlatform: false,
      );
      expect(with_.qrPaymentConfigured, isTrue);
      expect(with_.isDisplayOnly(PaymentMethodIds.qrCode), isFalse);
      expect(with_.isSelectableExternal(PaymentMethodIds.qrCode), isTrue);
    });

    test('an unknown published option id is ignored, not shown', () {
      final options = _seam(
        const _Profile(
          mollieConnected: true,
          livePaymentsEnabled: true,
          publicPaymentOptions: <String>[
            'not_a_method',
            PaymentMethodIds.bancontact,
          ],
        ),
        countryCode: PaymentCountryCodes.belgium,
        languageCode: 'nl',
        isApplePlatform: false,
      );
      expect(options.capability.enabledPaymentOptionIds, <String>[
        PaymentMethodIds.bancontact,
      ]);
      expect(options.visibleMethodIds, isNot(contains('not_a_method')));
    });

    test('no known profile behaves as the historical default gate', () {
      final options = _seam(
        null,
        countryCode: PaymentCountryCodes.belgium,
        languageCode: 'nl',
        isApplePlatform: false,
      );
      expect(
        options.capability.ownershipGate.onlinePaymentsAvailable,
        const PaymentOwnershipGate().onlinePaymentsAvailable,
      );
      expect(options.capability.enabledPaymentOptionIds, isEmpty);
    });
  });
}
