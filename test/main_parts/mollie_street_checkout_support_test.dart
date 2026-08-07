// RELEASE-P0-MOLLIE-STREET-CHECKOUT-1
//
// Pure-logic tests for lib/payment/mollie_street_checkout.dart: eligibility
// for the receipt "Online betalen" action, response/error parsing, the
// manual-payment-vs-open-Mollie conflict gate, and `/pay/status` poll
// classification.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/payment/mollie_street_checkout.dart';

void main() {
  group('resolveMollieStreetCheckoutEligible', () {
    test('street booking id prefix, unpaid, positive amount -> eligible', () {
      expect(
        resolveMollieStreetCheckoutEligible(
          bookingId: 'street_123_abc',
          isPaid: false,
          isCancelled: false,
          amount: 24.5,
        ),
        isTrue,
      );
    });

    test('source/booking_source street_ride marker -> eligible', () {
      expect(
        resolveMollieStreetCheckoutEligible(
          bookingId: 'bk_1',
          isPaid: false,
          isCancelled: false,
          amount: 10,
          source: 'street_ride',
        ),
        isTrue,
      );
      expect(
        resolveMollieStreetCheckoutEligible(
          bookingId: 'bk_1',
          isPaid: false,
          isCancelled: false,
          amount: 10,
          bookingSource: 'street_ride',
        ),
        isTrue,
      );
    });

    test('ride_type == direct alone is sufficient (unlike business invoice)', () {
      expect(
        resolveMollieStreetCheckoutEligible(
          bookingId: 'bk_1',
          isPaid: false,
          isCancelled: false,
          amount: 10,
          rideType: 'direct',
        ),
        isTrue,
      );
    });

    test('no street/direct marker at all -> not eligible', () {
      expect(
        resolveMollieStreetCheckoutEligible(
          bookingId: 'bk_planned_1',
          isPaid: false,
          isCancelled: false,
          amount: 10,
          source: 'customer',
          rideType: 'planned',
        ),
        isFalse,
      );
    });

    test('already paid -> not eligible', () {
      expect(
        resolveMollieStreetCheckoutEligible(
          bookingId: 'street_1',
          isPaid: true,
          isCancelled: false,
          amount: 10,
        ),
        isFalse,
      );
    });

    test('cancelled -> not eligible', () {
      expect(
        resolveMollieStreetCheckoutEligible(
          bookingId: 'street_1',
          isPaid: false,
          isCancelled: true,
          amount: 10,
        ),
        isFalse,
      );
    });

    test('missing / zero / negative amount -> not eligible', () {
      for (final amount in [null, 0.0, -5.0]) {
        expect(
          resolveMollieStreetCheckoutEligible(
            bookingId: 'street_1',
            isPaid: false,
            isCancelled: false,
            amount: amount,
          ),
          isFalse,
          reason: 'amount=$amount',
        );
      }
    });

    test('missing/blank booking id -> not eligible even with markers', () {
      expect(
        resolveMollieStreetCheckoutEligible(
          bookingId: '  ',
          isPaid: false,
          isCancelled: false,
          amount: 10,
          source: 'street_ride',
        ),
        isFalse,
      );
    });
  });

  group('parseMollieStreetCheckoutStartResponse', () {
    test('top-level checkout_url + qr_code.src + payment_booking_id', () {
      final result = parseMollieStreetCheckoutStartResponse(<String, dynamic>{
        'ok': true,
        'checkout_url': 'https://mollie.example/checkout/abc',
        'qr_code': {'src': 'data:image/png;base64,AAA'},
        'payment_booking_id': 'pay_123',
        'amount': 24.5,
        'reused': false,
      });
      expect(result.ok, isTrue);
      expect(result.checkoutUrl, 'https://mollie.example/checkout/abc');
      expect(result.qrSrc, 'data:image/png;base64,AAA');
      expect(result.paymentBookingId, 'pay_123');
      expect(result.amount, 24.5);
      expect(result.reused, isFalse);
      expect(result.hasCheckout, isTrue);
    });

    test('camelCase + nested under booking/payment also parse', () {
      final result = parseMollieStreetCheckoutStartResponse(<String, dynamic>{
        'booking': {'checkoutUrl': 'https://mollie.example/c2'},
        'payment': {'paymentBookingId': 'pay_456', 'amount': 12},
        'existing_open': true,
      });
      expect(result.checkoutUrl, 'https://mollie.example/c2');
      expect(result.paymentBookingId, 'pay_456');
      expect(result.amount, 12.0);
      expect(result.reused, isTrue);
      expect(result.hasCheckout, isTrue);
    });

    test('status == existing_open marks reused (reopen an open checkout)', () {
      final result = parseMollieStreetCheckoutStartResponse(<String, dynamic>{
        'checkout_url': 'https://mollie.example/c3',
        'status': 'existing_open',
      });
      expect(result.reused, isTrue);
    });

    test('no checkout url and no qr -> not ok / no checkout', () {
      final result = parseMollieStreetCheckoutStartResponse(<String, dynamic>{
        'ok': true,
      });
      expect(result.hasCheckout, isFalse);
    });
  });

  group('classifyMollieStreetCheckoutStartError', () {
    test('401 -> authRequired regardless of body', () {
      expect(
        classifyMollieStreetCheckoutStartError(httpCode: 401, decoded: null),
        MollieStreetCheckoutErrorKind.authRequired,
      );
    });

    test('already-paid tokens -> rideAlreadyPaid', () {
      for (final token in ['already_paid', 'ride_paid', 'booking_paid']) {
        expect(
          classifyMollieStreetCheckoutStartError(
            httpCode: 422,
            decoded: {'error': token},
          ),
          MollieStreetCheckoutErrorKind.rideAlreadyPaid,
          reason: token,
        );
      }
    });

    test('not-connected tokens -> mollieNotConnected', () {
      expect(
        classifyMollieStreetCheckoutStartError(
          httpCode: 422,
          decoded: {'error': 'mollie_not_connected'},
        ),
        MollieStreetCheckoutErrorKind.mollieNotConnected,
      );
    });

    test('no-online-method tokens -> noOnlineMethods', () {
      expect(
        classifyMollieStreetCheckoutStartError(
          httpCode: 422,
          decoded: {'error': 'no_online_method_active'},
        ),
        MollieStreetCheckoutErrorKind.noOnlineMethods,
      );
    });

    test('not-a-street-booking tokens -> notEligible', () {
      expect(
        classifyMollieStreetCheckoutStartError(
          httpCode: 422,
          decoded: {'error': 'not_a_street_booking'},
        ),
        MollieStreetCheckoutErrorKind.notEligible,
      );
    });

    test('unrecognised error -> unknown', () {
      expect(
        classifyMollieStreetCheckoutStartError(
          httpCode: 500,
          decoded: {'error': 'boom'},
        ),
        MollieStreetCheckoutErrorKind.unknown,
      );
    });
  });

  group('manualPaymentBlockedByOpenMollieCheckout', () {
    test('non-409 is never a Mollie conflict', () {
      expect(
        manualPaymentBlockedByOpenMollieCheckout(
          httpCode: 422,
          decoded: {'requires_confirm_cancel_mollie': true},
        ),
        isFalse,
      );
    });

    test('409 with explicit confirm flag -> blocked', () {
      expect(
        manualPaymentBlockedByOpenMollieCheckout(
          httpCode: 409,
          decoded: {'requires_confirm_cancel_mollie': true},
        ),
        isTrue,
      );
      expect(
        manualPaymentBlockedByOpenMollieCheckout(
          httpCode: 409,
          decoded: {'requires_confirm_cancel_open_mollie': true},
        ),
        isTrue,
      );
    });

    test('open checkout recovery payload parses actions', () {
      final info = parseMollieOpenPaymentRecovery({
        'error': 'open_mollie_checkout_exists',
        'requires_confirm_cancel_open_mollie': true,
        'open_checkout': {
          'checkout_url': 'https://www.mollie.com/checkout/x',
          'mollie_payment_id': 'tr_1',
          'mollie_status': 'open',
        },
        'recovery': {
          'presentation_state': 'pending',
          'resumable': true,
          'cancel_allowed': true,
          'fallback_allowed': false,
          'actions': [
            'refresh_status',
            'resume_checkout',
            'cancel_open_checkout',
          ],
        },
      });
      expect(info, isNotNull);
      expect(info!.isPendingOwner, isTrue);
      expect(info.resumable, isTrue);
      expect(info.cancelAllowed, isTrue);
      expect(info.fallbackAllowed, isFalse);
      expect(info.actions, contains('refresh_status'));
    });

    test('receipt details detect open Mollie owner', () {
      expect(
        receiptDetailsHaveOpenMollieCheckout({
          'payment_status': 'pending',
          'payment_provider': 'mollie',
          'checkout_url': 'https://www.mollie.com/checkout/x',
          'mollie': {'status': 'open'},
        }),
        isTrue,
      );
      expect(
        receiptDetailsHaveOpenMollieCheckout({
          'payment_status': 'paid',
          'payment_provider': 'mollie',
          'checkout_url': 'https://www.mollie.com/checkout/x',
        }),
        isFalse,
      );
    });

    test('409 with mollie/open_payment error token -> blocked', () {
      expect(
        manualPaymentBlockedByOpenMollieCheckout(
          httpCode: 409,
          decoded: {'error': 'open_payment_exists'},
        ),
        isTrue,
      );
      expect(
        manualPaymentBlockedByOpenMollieCheckout(
          httpCode: 409,
          decoded: {'error': 'open_mollie_checkout'},
        ),
        isTrue,
      );
    });

    test('409 with an unrelated conflict reason -> not a Mollie conflict', () {
      expect(
        manualPaymentBlockedByOpenMollieCheckout(
          httpCode: 409,
          decoded: {'error': 'duplicate_request'},
        ),
        isFalse,
      );
    });

    test('409 with no decodable body -> conservatively blocked', () {
      expect(
        manualPaymentBlockedByOpenMollieCheckout(httpCode: 409, decoded: null),
        isTrue,
      );
    });
  });

  group('classifyMollieStreetCheckoutPollStatus / molliePollOutcomeIsTerminal', () {
    test('mollie.status == paid -> paid (terminal)', () {
      final outcome = classifyMollieStreetCheckoutPollStatus(
        httpCode: 200,
        data: {
          'mollie': {'status': 'paid'},
        },
      );
      expect(outcome, MollieStreetCheckoutPollOutcome.paid);
      expect(molliePollOutcomeIsTerminal(outcome), isTrue);
    });

    test('non-empty confirmed_at -> paid even without an explicit status', () {
      final outcome = classifyMollieStreetCheckoutPollStatus(
        httpCode: 200,
        data: {'confirmed_at': '2026-01-01T00:00:00Z'},
      );
      expect(outcome, MollieStreetCheckoutPollOutcome.paid);
    });

    test('failed / expired / cancelled map to their own terminal outcomes', () {
      expect(
        classifyMollieStreetCheckoutPollStatus(
          httpCode: 200,
          data: {
            'mollie': {'status': 'failed'},
          },
        ),
        MollieStreetCheckoutPollOutcome.failed,
      );
      expect(
        classifyMollieStreetCheckoutPollStatus(
          httpCode: 200,
          data: {
            'mollie': {'status': 'expired'},
          },
        ),
        MollieStreetCheckoutPollOutcome.expired,
      );
      for (final s in ['canceled', 'cancelled']) {
        expect(
          classifyMollieStreetCheckoutPollStatus(
            httpCode: 200,
            data: {
              'mollie': {'status': s},
            },
          ),
          MollieStreetCheckoutPollOutcome.cancelled,
          reason: s,
        );
      }
    });

    test('open/pending -> pending (not terminal, keep polling)', () {
      final outcome = classifyMollieStreetCheckoutPollStatus(
        httpCode: 200,
        data: {
          'mollie': {'status': 'open'},
        },
      );
      expect(outcome, MollieStreetCheckoutPollOutcome.pending);
      expect(molliePollOutcomeIsTerminal(outcome), isFalse);
    });

    test('non-2xx HTTP -> error (not terminal, never paid)', () {
      final outcome = classifyMollieStreetCheckoutPollStatus(
        httpCode: 500,
        data: {
          'mollie': {'status': 'paid'},
        },
      );
      expect(outcome, MollieStreetCheckoutPollOutcome.error);
      expect(molliePollOutcomeIsTerminal(outcome), isFalse);
    });

    test('missing data -> error', () {
      expect(
        classifyMollieStreetCheckoutPollStatus(httpCode: 200, data: null),
        MollieStreetCheckoutPollOutcome.error,
      );
    });
  });
}
