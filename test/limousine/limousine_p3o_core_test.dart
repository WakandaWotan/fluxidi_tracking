// P3O — accepted limousine checkout handoff, pax authority, frozen cancellation.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_cancellation_terms.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/payment/booking_payment_options.dart';
import 'package:fluxidi_tracking/payment/payment_booking_selection.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';

const String _acceptRef = 'limacc1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM';

const Map<String, dynamic> _mollieRaw = <String, dynamic>{
  'ok': true,
  'booking_id': 'B-800',
  'public_reference': 'FLX-800',
  'payment_booking_id': 'PB-800',
  'checkout_url': 'https://www.mollie.com/checkout/select-method/p3o',
};

const BookingPaymentCapability _online = BookingPaymentCapability(
  paymentOwnerMode: 'company_mollie',
  paymentDemoMode: false,
  mollieConnected: true,
  livePaymentsEnabled: true,
  publicPaymentOptions: <String>[
    PaymentMethodIds.bancontact,
    PaymentMethodIds.kbcCbc,
    PaymentMethodIds.belfius,
    PaymentMethodIds.cardPayment,
    PaymentMethodIds.paypal,
    PaymentMethodIds.googlePay,
    PaymentMethodIds.qrCode,
    PaymentMethodIds.inVehicleCard,
  ],
  countryCode: 'BE',
);

LimousineAcceptedQuoteHandoff _handoff() {
  return const LimousineAcceptedQuoteHandoff(
    acceptanceReference: _acceptRef,
    quoteRequestId: 'limq_p3o',
    quoteRevision: 6,
    termsRevision: 4,
    totalInclVatCents: 106000,
    currency: 'EUR',
    offerId: 'off_1',
    publicPartnerId: 'p1',
    from: 'Gent',
    to: 'Brussel',
    scheduledPickupIso: '2026-09-01T10:00:00Z',
  );
}

LimousineQuoteCreateDraft _draft({int pax = 8, int bags = 2}) {
  return LimousineQuoteCreateDraft(
    publicPartnerId: 'p1',
    offerId: 'off_1',
    journeyType: 'point_to_point',
    from: 'Gent',
    to: 'Brussel',
    scheduledPickupIso: '2026-09-01T10:00:00Z',
    pax: pax,
    bags: bags,
  );
}

LimousineQuoteRequest _request({int pax = 8, int bags = 2}) {
  return LimousineQuoteRequest.fromJson(<String, dynamic>{
    'quote_request_id': 'limq_p3o',
    'state': 'accepted',
    'revision': 6,
    'offer_id': 'off_1',
    'vehicle_id': 'veh_1',
    'journey_type': 'point_to_point',
    'scheduled_pickup_iso': '2026-09-01T10:00:00Z',
    'pax': pax,
    'bags': bags,
    'quote': <String, dynamic>{
      'total_incl_vat_cents': 106000,
      'currency': 'EUR',
      'terms_revision': 4,
    },
  });
}

const LimousineAcceptedBookingCustomer _customer =
    LimousineAcceptedBookingCustomer(
      sessionToken: 'sess_1',
      customerId: 'cust_1',
      name: 'Ada',
      phone: '+32470000000',
      email: 'ada@example.com',
    );

class _BookGateway implements LimousineAcceptedBookingGateway {
  _BookGateway({this.raw = _mollieRaw, this.throwCode});

  int calls = 0;
  Map<String, dynamic>? lastPayload;
  Map<String, dynamic> raw;
  String? throwCode;

  @override
  Future<LimousineAcceptedBookResult> book(Map<String, dynamic> payload) async {
    calls += 1;
    lastPayload = payload;
    final code = throwCode;
    if (code != null) {
      throw LimousineAcceptedBookException(code: code, statusCode: 502);
    }
    return LimousineAcceptedBookResult(
      bookingId: (raw['booking_id'] ?? '').toString(),
      publicReference: (raw['public_reference'] ?? '').toString(),
      raw: raw,
    );
  }
}

LimousineAcceptedBookingController _controller({
  required _BookGateway gateway,
  BookingPaymentCapability capability = _online,
  LimousineAcceptedCheckoutOpener? checkoutOpener,
  int pax = 8,
  int bags = 2,
}) {
  return LimousineAcceptedBookingController(
    handoff: _handoff(),
    draft: _draft(pax: pax, bags: bags),
    request: _request(pax: pax, bags: bags),
    entryEnabled: true,
    gateway: gateway,
    customerOverride: _customer,
    customerLoader: () async => _customer,
    initialPaymentCapability: capability,
    checkoutOpener: checkoutOpener ?? (url) async => true,
    isApplePaymentPlatform: false,
    persister:
        ({
          required response,
          required requestPayload,
          required customer,
        }) async {},
  );
}

Map<String, dynamic> _frozenBooking({
  int hours = 24,
  int penalty = 25,
  int noShow = 100,
  int gross = 106000,
}) {
  return <String, dynamic>{
    'service_type': 'limousine',
    'payment_status': 'unpaid',
    'pickup_iso': '2026-09-01T10:00:00Z',
    'cancellation_deadline_hours': hours,
    'cancellation_penalty_percent': penalty,
    'no_show_penalty_percent': noShow,
    'cancellation_canonical_gross_cents': gross,
    'cancellation_terms_source': kLimousineFrozenCancellationSource,
    'terms_revision': 4,
    'quote': <String, dynamic>{
      'limousine_accepted_price': <String, dynamic>{
        'service_category': 'limousine',
        'total_incl_vat_cents': gross,
        'price_incl_vat': gross / 100,
        'cancellation_deadline_hours': hours,
        'cancellation_penalty_percent': penalty,
        'no_show_penalty_percent': noShow,
        'cancellation_canonical_gross_cents': gross,
        'cancellation_terms_source': kLimousineFrozenCancellationSource,
        'terms_revision': 4,
      },
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('online checkout handoff', () {
    test('selected Bancontact stays mollie + bancontact until submit', () async {
      final gateway = _BookGateway();
      final controller = _controller(gateway: gateway);
      expect(controller.selectedPaymentMethodId, isNull);
      controller.selectPaymentMethod(PaymentMethodIds.bancontact);
      controller.setConfirmationAcknowledged(true);
      expect(await controller.confirmBooking(), isTrue);
      expect(gateway.lastPayload!['payment_mode'], 'mollie');
      expect(gateway.lastPayload!['payment_provider'], 'mollie');
      expect(gateway.lastPayload!['mollie_method'], 'bancontact');
      expect(controller.succeeded, isTrue);
      controller.dispose();
    });

    for (final entry in <(String, String)>[
      (PaymentMethodIds.kbcCbc, 'kbc'),
      (PaymentMethodIds.belfius, 'belfius'),
      (PaymentMethodIds.cardPayment, 'creditcard'),
      (PaymentMethodIds.paypal, 'paypal'),
      (PaymentMethodIds.googlePay, 'googlepay'),
    ]) {
      test('${entry.$1} maps to mollie + ${entry.$2}', () {
        final fields = BookingPaymentSelection.fromMethodId(
          entry.$1,
        ).toPayloadFields();
        expect(fields['payment_mode'], 'mollie');
        expect(fields['payment_provider'], 'mollie');
        expect(fields['mollie_method'], entry.$2);
      });
    }

    test('manual QR and pay-in-car stay manual', () {
      final qr = BookingPaymentSelection.fromMethodId(PaymentMethodIds.qrCode);
      expect(qr.paymentMode, 'manual');
      expect(qr.isManualCollection, isTrue);
      final car = BookingPaymentSelection.fromMethodId(
        PaymentMethodIds.inVehicleCard,
      );
      expect(car.paymentMode, 'manual');
      expect(car.isMollieCheckout, isFalse);
    });

    test('missing checkout URL blocks success and keeps the booking', () async {
      final gateway = _BookGateway(
        raw: const <String, dynamic>{
          'ok': true,
          'booking_id': 'B-801',
          'public_reference': 'FLX-801',
        },
      );
      final controller = _controller(gateway: gateway);
      controller.selectPaymentMethod(PaymentMethodIds.bancontact);
      controller.setConfirmationAcknowledged(true);
      expect(await controller.confirmBooking(), isFalse);
      expect(controller.succeeded, isFalse);
      expect(controller.checkoutPending, isTrue);
      expect(controller.result!.bookingId, 'B-801');
      expect(controller.canResumeCheckout, isTrue);
      controller.dispose();
    });

    testWidgets('launchUrl false shows resume, retry does not book twice', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final gateway = _BookGateway();
      var launches = 0;
      final controller = _controller(
        gateway: gateway,
        checkoutOpener: (url) async {
          launches += 1;
          return false;
        },
      );
      controller.selectPaymentMethod(PaymentMethodIds.bancontact);
      controller.setConfirmationAcknowledged(true);
      expect(await controller.confirmBooking(), isFalse);
      await tester.pumpWidget(
        MaterialApp(
          home: LimousineAcceptedBookingPage(
            controller: controller,
            entryEnabled: true,
          ),
        ),
      );
      expect(find.byKey(kLimousineAcceptedBookingSuccessKey), findsNothing);
      expect(find.byKey(kLimousineAcceptedBookingCheckoutPendingKey), findsOneWidget);
      expect(find.byKey(kLimousineAcceptedBookingResumeCheckoutKey), findsOneWidget);
      expect(
        find.text(kLimousineAcceptedBookingResumeCheckout.of(AppLanguage.en)),
        findsOneWidget,
      );
      await tester.tap(find.byKey(kLimousineAcceptedBookingResumeCheckoutKey));
      await tester.pump();
      expect(gateway.calls, 1);
      expect(launches, 2);
      expect(controller.checkoutPending, isTrue);
      controller.dispose();
    });

    test('checkout create failure keeps Bancontact and shows a retry error', () async {
      final gateway = _BookGateway(throwCode: 'payment_checkout_unavailable');
      final controller = _controller(gateway: gateway);
      controller.selectPaymentMethod(PaymentMethodIds.bancontact);
      controller.setConfirmationAcknowledged(true);
      expect(await controller.confirmBooking(), isFalse);
      expect(controller.succeeded, isFalse);
      expect(controller.checkoutPending, isFalse);
      expect(
        controller.error,
        LimousineAcceptedBookingError.checkoutCreateFailed,
      );
      expect(controller.selectedPaymentMethodId, PaymentMethodIds.bancontact);
      expect(gateway.calls, 1);
      expect(
        limousineAcceptedBookErrorFromCode('payment_checkout_unavailable'),
        LimousineAcceptedBookingError.checkoutCreateFailed,
      );
      controller.dispose();
    });

    test('manual booking still succeeds without a checkout URL', () async {
      final gateway = _BookGateway(
        raw: const <String, dynamic>{
          'ok': true,
          'booking_id': 'B-802',
          'public_reference': 'FLX-802',
        },
      );
      final controller = _controller(
        gateway: gateway,
        capability: const BookingPaymentCapability(
          paymentOwnerMode: 'manual_only',
          paymentDemoMode: false,
          mollieConnected: false,
          publicPaymentOptions: <String>[
            PaymentMethodIds.qrCode,
            PaymentMethodIds.inVehicleCard,
          ],
          countryCode: 'BE',
        ),
      );
      controller.selectPaymentMethod(PaymentMethodIds.qrCode);
      controller.setConfirmationAcknowledged(true);
      expect(await controller.confirmBooking(), isTrue);
      expect(controller.succeeded, isTrue);
      expect(gateway.lastPayload!['payment_mode'], 'manual');
      controller.dispose();
    });
  });

  group('pax authority on the accepted booking UI', () {
    testWidgets('accepted review shows pax 8 and bags 2', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final controller = _controller(gateway: _BookGateway());
      await tester.pumpWidget(
        MaterialApp(
          home: LimousineAcceptedBookingPage(
            controller: controller,
            entryEnabled: true,
          ),
        ),
      );
      expect(controller.reviewFor(AppLanguage.nl).pax, 8);
      expect(controller.reviewFor(AppLanguage.nl).bags, 2);
      expect(find.textContaining('8'), findsWidgets);
      controller.dispose();
    });
  });

  group('frozen cancellation preview', () {
    test('before deadline is 0% and €0', () {
      final preview = limousineCancellationPreviewFromDetails(
        _frozenBooking(),
        pickupIso: DateTime.utc(2026, 9, 2, 10).toIso8601String(),
        now: DateTime.utc(2026, 9, 1, 8),
      )!;
      expect(preview.beforeFreeDeadline, isTrue);
      expect(preview.applicablePenaltyPercent, 0);
      expect(preview.penaltyCents, 0);
      expect(preview.outstandingCents, 0);
      expect(preview.terms.deadlineHours, 24);
    });

    test('after deadline is 25% of €1,060 = €265', () {
      final preview = limousineCancellationPreviewFromDetails(
        _frozenBooking(),
        pickupIso: DateTime.utc(2026, 9, 1, 10).toIso8601String(),
        now: DateTime.utc(2026, 9, 1, 9),
      )!;
      expect(preview.beforeFreeDeadline, isFalse);
      expect(preview.applicablePenaltyPercent, 25);
      expect(preview.penaltyCents, 26500);
      expect(preview.outstandingCents, 26500);
      final body = limousineCancellationPreviewBody(preview);
      expect(body.nl, contains('24'));
      expect(body.nl, contains('25%'));
      expect(body.nl, contains('265'));
      expect(body.nl, contains('1060'));
    });

    test('paid cancellation shows refund = paid - penalty', () {
      final details = _frozenBooking();
      details['payment_status'] = 'paid';
      final preview = limousineCancellationPreviewFromDetails(
        details,
        pickupIso: DateTime.utc(2026, 9, 1, 10).toIso8601String(),
        paymentStatus: 'paid',
        paidAmountCents: 106000,
        now: DateTime.utc(2026, 9, 1, 9),
      )!;
      expect(preview.refundCents, 79500);
      expect(limousineCancellationPreviewBody(preview).nl, contains('795'));
    });

    test('no-show uses 100%', () {
      final preview = limousineCancellationPreviewFromDetails(
        _frozenBooking(),
        pickupIso: DateTime.utc(2026, 8, 1, 10).toIso8601String(),
        now: DateTime.utc(2026, 8, 23, 12),
      )!;
      expect(preview.isNoShow, isTrue);
      expect(preview.applicablePenaltyPercent, 100);
      expect(preview.penaltyCents, 106000);
    });

    test('taxi-like details without frozen terms stay null', () {
      expect(
        limousineFrozenCancellationTermsFromDetails(<String, dynamic>{
          'service_type': 'taxi',
          'pax': 2,
        }),
        isNull,
      );
    });
  });
}
