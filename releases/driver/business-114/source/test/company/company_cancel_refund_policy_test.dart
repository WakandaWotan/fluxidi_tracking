import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_cancel_refund_policy.dart';

void main() {
  test('double tap does not start a second cancel', () {
    expect(
      companyBookingCancelShouldStart(
        alreadyBusy: false,
        bulkArchiving: false,
      ),
      isTrue,
    );
    expect(
      companyBookingCancelShouldStart(alreadyBusy: true, bulkArchiving: false),
      isFalse,
    );
  });

  test('missing refunds.write blocks another refund until grant is confirmed', () {
    const error = 'mollie_refund_failed (The token does not have the refunds.write permission)';
    expect(companyBookingMollieRefundsWriteMissing(error), isTrue);
    expect(
      companyBookingShouldRetryMollieRefund(
        lastError: error,
        writeGrantConfirmed: false,
      ),
      isFalse,
    );
    expect(
      companyBookingShouldRetryMollieRefund(
        lastError: error,
        writeGrantConfirmed: true,
      ),
      isTrue,
    );
  });

  test('recorded credit is not a Mollie refund', () {
    expect(companyBookingCreditAlreadyRecorded('FULL_CREDIT'), isTrue);
    expect(
      companyBookingIsMollieRefundConfirmed(
        mollieRefundStatus: '',
        refundStatus: '',
        mollieRefundId: '',
      ),
      isFalse,
    );
    expect(
      companyBookingSettledChipToken(
        creditDecision: 'FULL_CREDIT',
        mollieRefundStatus: '',
        refundStatus: '',
        mollieRefundId: '',
      ),
      'CREDITED_NOT_REFUNDED',
    );
    expect(
      companyBookingSettledChipToken(
        creditDecision: 'FULL_CREDIT',
        mollieRefundStatus: 'refunded',
        refundStatus: '',
        mollieRefundId: 're_1',
      ),
      'REFUNDED',
    );
  });

  test('failed refund stays in the failed tab after credit', () {
    expect(
      companyBookingCountsAsFailedRefundTab(
        cancelled: true,
        paid: true,
        mollieRefundStatus: 'failed',
        refundStatus: '',
      ),
      isTrue,
    );
    expect(
      companyBookingCountsAsFailedRefundTab(
        cancelled: true,
        paid: true,
        mollieRefundStatus: '',
        refundStatus: '',
        lastError: kCompanyMollieRefundsWriteMissing,
      ),
      isTrue,
    );
    expect(
      companyBookingCountsAsFailedRefundTab(
        cancelled: true,
        paid: true,
        mollieRefundStatus: '',
        refundStatus: '',
      ),
      isFalse,
    );
  });

  test('accepted refund without provider settlement stays pending on tab and card', () {
    // Observed PLN-2026-000459: FULL_CREDIT + request signal, card said
    // "Niet terugbetaald" while the pending tab counted 1.
    final kind = companyBookingRefundUiKind(
      cancelled: true,
      paid: true,
      mollieRefundStatus: '',
      refundStatus: 'PENDING_CREDIT',
      mollieRefundId: '',
      refundedAmountCents: 570,
      refundedAt: '2026-09-21T22:00:00.000Z',
      complianceEmittedAt: '2026-09-21T22:00:00.000Z',
    );
    expect(kind, CompanyBookingRefundUiKind.pending);
    expect(
      companyBookingRefundApplySnackKind(
        ok: true,
        refundStatus: 'mollie_refund_pending',
        mollieRefundStatus: 'pending',
      ),
      CompanyBookingRefundUiKind.pending,
    );
    expect(
      companyBookingSettledChipToken(
        creditDecision: 'FULL_CREDIT',
        mollieRefundStatus: '',
        refundStatus: 'PENDING_CREDIT',
        mollieRefundId: '',
      ),
      'CREDITED_NOT_REFUNDED',
    );
    expect(
      companyBookingRefundUiKind(
        cancelled: true,
        paid: true,
        mollieRefundStatus: 'refunded',
        refundStatus: 'refunded',
        mollieRefundId: 're_1',
        refundedAmountCents: 570,
      ),
      CompanyBookingRefundUiKind.refunded,
    );
    expect(
      companyBookingRefundApplySnackKind(
        ok: true,
        refundStatus: 'refunded',
        mollieRefundStatus: 'refunded',
      ),
      CompanyBookingRefundUiKind.refunded,
    );
    expect(
      companyBookingRefundUiKind(
        cancelled: true,
        paid: true,
        mollieRefundStatus: 'failed',
        refundStatus: 'mollie_refund_failed',
        lastError: 'mollie_refund_failed',
      ),
      CompanyBookingRefundUiKind.failed,
    );
  });

  test('cancel timing keeps request and reload separate', () {
    const timing = CompanyBookingCancelTiming(requestMs: 180, reloadMs: 2400);
    expect(timing.requestWasTheSlowPart, isFalse);
    expect(timing.reloadMs > timing.requestMs, isTrue);
  });
}
