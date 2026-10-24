// COMMERCIAL-ENTITLEMENT-FLUTTER-P0
// Run: flutter test test/company/subscription_entitlement_ux_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/subscription_entitlement_ux.dart';
import 'package:fluxidi_tracking/main_parts/driver_ride_start_auth_guard.dart';

void main() {
  group('classifySubscriptionEntitlementDeny', () {
    test('6: booking 402 → company operational deny', () {
      final d = classifySubscriptionEntitlementDeny(
        httpStatus: 402,
        errorBody: '{"ok":false,"error":"subscription_entitlement_denied"}',
      );
      expect(d.isCompanyOperationalDeny, isTrue);
      expect(
        friendlyEntitlementUserMessage(
          rawError: 'subscription_entitlement_denied',
          languageCode: 'nl',
          isPublicCustomer: false,
          httpStatus: 402,
        ),
        contains('Abonnement vereist'),
      );
      expect(
        friendlyEntitlementUserMessage(
          rawError: 'subscription_entitlement_denied',
          languageCode: 'nl',
          isPublicCustomer: false,
          httpStatus: 402,
        ),
        isNot(contains('subscription_entitlement_denied')),
      );
    });

    test('7: public 503 company_unavailable → neutral', () {
      final msg = friendlyEntitlementUserMessage(
        rawError: 'company_unavailable',
        languageCode: 'nl',
        isPublicCustomer: true,
        httpStatus: 503,
      );
      expect(msg, contains('geen nieuwe boekingen'));
      expect(msg, isNot(contains('company_unavailable')));
      expect(msg!.toLowerCase(), isNot(contains('betaald')));
    });

    test('8: payment_required label', () {
      expect(
        subscriptionStatusLabel(
          statusRaw: 'payment_required',
          languageCode: 'nl',
        ),
        'Abonnement vereist',
      );
    });

    test('9: expired trial blocked message', () {
      final msg = subscriptionBlockedStateMessage(
        statusRaw: 'payment_required',
        languageCode: 'nl',
        cancelAtPeriodEnd: false,
      );
      expect(msg, contains('proefperiode is afgelopen'));
    });

    test('10: grace_period warning only, not hard client block helper', () {
      expect(subscriptionStatusIsWarningOnly('grace_period'), isTrue);
      expect(subscriptionStatusIsOperationallyBlocked('grace_period'), isFalse);
      expect(
        subscriptionStatusLabel(statusRaw: 'grace_period', languageCode: 'nl'),
        'Betalingstermijn',
      );
      expect(
        subscriptionDunningWarningMessage(
          statusRaw: 'grace_period',
          languageCode: 'nl',
        ),
        isNotNull,
      );
    });

    test('11: suspended blocked state', () {
      expect(subscriptionStatusIsOperationallyBlocked('suspended'), isTrue);
      expect(
        subscriptionBlockedStateMessage(
          statusRaw: 'suspended',
          languageCode: 'nl',
          cancelAtPeriodEnd: false,
        ),
        contains('opgeschort'),
      );
    });

    test('12: cancelled-after-period blocked state', () {
      expect(
        subscriptionBlockedStateMessage(
          statusRaw: 'cancelled',
          languageCode: 'nl',
          cancelAtPeriodEnd: true,
        ),
        contains('abonnement is afgelopen'),
      );
    });

    test('13: active cancel_at_period_end before effective = not blocked message', () {
      expect(
        subscriptionBlockedStateMessage(
          statusRaw: 'active',
          languageCode: 'nl',
          cancelAtPeriodEnd: true,
        ),
        isNull,
      );
      expect(subscriptionStatusIsOperationallyBlocked('active'), isFalse);
    });
  });

  group('street/planned hard abort classification', () {
    test('1+2: HTTP 402 on street start is entitlement hard abort', () {
      final c = classifyDirectTripStartError(
        Exception(
          'HTTP 402: {"ok":false,"error":"subscription_entitlement_denied"}',
        ),
      );
      expect(c.isEntitlementFailure, isTrue);
      expect(c.isHardAbort, isTrue);
      expect(c.isTransportOrOther, isFalse);
      expect(c.isAuthFailure, isFalse);
    });

    test('5: planned ride start 402 hard abort helper', () {
      expect(
        isSubscriptionEntitlementHardAbort(
          Exception('HTTP 402: {"error":"subscription_suspended"}'),
        ),
        isTrue,
      );
    });

    test('transport remains non-hard for local-only policy', () {
      final c = classifyDirectTripStartError(
        Exception('TimeoutException after 0:00:06.000000'),
      );
      expect(c.isTransportOrOther, isTrue);
      expect(c.isHardAbort, isFalse);
    });

    test('auth 401 still hard abort', () {
      final c = classifyDirectTripStartError(Exception('HTTP 401: {}'));
      expect(c.isAuthFailure, isTrue);
      expect(c.isHardAbort, isTrue);
    });
  });
}
