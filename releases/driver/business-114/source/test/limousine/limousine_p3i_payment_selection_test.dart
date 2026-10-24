// P3I Phase 3d — the accepted limousine quote pays through the canonical
// booking payment seam: the partner's own capability, the shared resolver, the
// shared picker, an explicit BookingPaymentSelection and the existing /book
// checkout lifecycle. No limousine payment engine, no cash default.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/payment/booking_checkout_response.dart';
import 'package:fluxidi_tracking/payment/booking_payment_options.dart';
import 'package:fluxidi_tracking/payment/payment_booking_selection.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';
import 'package:fluxidi_tracking/payment_return.dart';

const String _acceptRef = 'limacc1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM';

const Map<String, dynamic> _mollieCheckoutRaw = <String, dynamic>{
  'ok': true,
  'booking_id': 'B-100',
  'public_reference': 'FLX-100',
  'payment_booking_id': 'PB-100',
  'checkout_url': 'https://www.mollie.com/checkout/select-method/abc',
};

/// A partner that only collects in the car.
const BookingPaymentCapability _manualOnly = BookingPaymentCapability(
  paymentOwnerMode: 'manual_only',
  paymentDemoMode: false,
  mollieConnected: false,
  publicPaymentOptions: <String>[PaymentMethodIds.inVehicleCard],
  countryCode: 'BE',
);

/// A partner with a linked Mollie account that published Bancontact.
const BookingPaymentCapability _onlineBancontact = BookingPaymentCapability(
  paymentOwnerMode: 'company_mollie',
  paymentDemoMode: false,
  mollieConnected: true,
  livePaymentsEnabled: true,
  publicPaymentOptions: <String>[
    PaymentMethodIds.bancontact,
    PaymentMethodIds.inVehicleCard,
  ],
  countryCode: 'BE',
);

LimousineAcceptedQuoteHandoff _handoff() {
  return const LimousineAcceptedQuoteHandoff(
    acceptanceReference: _acceptRef,
    quoteRequestId: 'limq_1',
    quoteRevision: 3,
    termsRevision: 3,
    totalInclVatCents: 45000,
    currency: 'EUR',
    offerId: 'off_1',
    publicPartnerId: 'p1',
    from: 'Gent',
    to: 'Brussel',
    scheduledPickupIso: '2026-09-01T10:00:00Z',
  );
}

LimousineQuoteCreateDraft _draft() {
  return const LimousineQuoteCreateDraft(
    publicPartnerId: 'p1',
    offerId: 'off_1',
    journeyType: 'point_to_point',
    from: 'Gent',
    to: 'Brussel',
    scheduledPickupIso: '2026-09-01T10:00:00Z',
    pax: 2,
    bags: 1,
  );
}

LimousineQuoteRequest _request() {
  return LimousineQuoteRequest.fromJson(<String, dynamic>{
    'quote_request_id': 'limq_1',
    'state': 'accepted',
    'revision': 3,
    'offer_id': 'off_1',
    'vehicle_id': 'veh_1',
    'journey_type': 'point_to_point',
    'scheduled_pickup_iso': '2026-09-01T10:00:00Z',
    'pax': 2,
    'bags': 1,
    'quote': <String, dynamic>{
      'total_incl_vat_cents': 45000,
      'currency': 'EUR',
      'terms_revision': 3,
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
  _BookGateway({Map<String, dynamic>? raw})
    : raw =
          raw ??
          const <String, dynamic>{
            'ok': true,
            'booking_id': 'B-100',
            'public_reference': 'FLX-100',
          };

  int calls = 0;
  Map<String, dynamic>? lastPayload;
  Object? error;
  Map<String, dynamic> raw;

  @override
  Future<LimousineAcceptedBookResult> book(Map<String, dynamic> payload) async {
    calls += 1;
    lastPayload = payload;
    final thrown = error;
    if (thrown != null) {
      if (thrown is Exception) throw thrown;
      throw Exception('$thrown');
    }
    return LimousineAcceptedBookResult(
      bookingId: (raw['booking_id'] ?? '').toString(),
      publicReference: (raw['public_reference'] ?? '').toString(),
      raw: raw,
    );
  }
}

class _Persisted {
  Map<String, dynamic>? response;
  Map<String, dynamic>? requestPayload;
  int calls = 0;
}

LimousineAcceptedBookingController _controller({
  required _BookGateway gateway,
  BookingPaymentCapability? capability = _manualOnly,
  LimousineAcceptedPaymentCapabilityLoader? loader,
  LimousineAcceptedCheckoutOpener? checkoutOpener,
  _Persisted? persisted,
}) {
  return LimousineAcceptedBookingController(
    handoff: _handoff(),
    draft: _draft(),
    request: _request(),
    entryEnabled: true,
    gateway: gateway,
    customerOverride: _customer,
    customerLoader: () async => _customer,
    initialPaymentCapability: capability,
    paymentCapabilityLoader: loader,
    checkoutOpener: checkoutOpener ?? (url) async => true,
    isApplePaymentPlatform: false,
    persister:
        ({
          required response,
          required requestPayload,
          required customer,
        }) async {
          if (persisted == null) return;
          persisted.calls += 1;
          persisted.response = response;
          persisted.requestPayload = requestPayload;
        },
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  LimousineAcceptedBookingController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LimousineAcceptedBookingPage(
        controller: controller,
        entryEnabled: true,
      ),
    ),
  );
  await tester.pump();
}

String _readSource(String path) => File(path).readAsStringSync();

/// Source with comments removed, so a doc comment naming a canonical endpoint
/// does not read as a second implementation of it.
String _readCode(String path) => _readSource(path)
    .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '')
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(clearFluxidiPendingPayment);

  group('A) capability decides the visible options', () {
    test('A1) a manual-only partner offers only the manual option', () {
      final controller = _controller(gateway: _BookGateway());
      expect(controller.visiblePaymentMethodIds, <String>[
        PaymentMethodIds.inVehicleCard,
      ]);
      expect(controller.selectablePaymentMethodIds, <String>[
        PaymentMethodIds.inVehicleCard,
      ]);
      expect(
        controller.selectedPaymentMethodId,
        PaymentMethodIds.inVehicleCard,
        reason: 'a single accepted method preselects, as taxi/airport do',
      );
      controller.dispose();
    });

    test('A2) a connected partner offers its published online methods', () {
      final controller = _controller(
        gateway: _BookGateway(),
        capability: _onlineBancontact,
      );
      expect(
        controller.visiblePaymentMethodIds,
        contains(PaymentMethodIds.bancontact),
      );
      expect(
        controller.visiblePaymentMethodIds,
        contains(PaymentMethodIds.inVehicleCard),
      );
      expect(
        controller.selectablePaymentMethodIds,
        contains(PaymentMethodIds.bancontact),
      );
      controller.dispose();
    });

    test('A3) an online method the partner did not publish stays hidden', () {
      final controller = _controller(
        gateway: _BookGateway(),
        capability: _onlineBancontact,
      );
      expect(
        controller.visiblePaymentMethodIds,
        isNot(contains(PaymentMethodIds.ideal)),
      );
      expect(
        controller.visiblePaymentMethodIds,
        isNot(contains(PaymentMethodIds.paypal)),
      );
      controller.dispose();
    });

    test(
      'A4) an unreadable capability guesses nothing and blocks the CTA',
      () async {
        final gateway = _BookGateway();
        final controller = _controller(
          gateway: gateway,
          capability: null,
          loader: () async => null,
        );
        await controller.loadPaymentCapability();
        expect(controller.paymentCapability, isNull);
        expect(controller.visiblePaymentMethodIds, isEmpty);
        expect(controller.selectedPaymentMethodId, isNull);
        expect(controller.canConfirmBooking, isFalse);
        expect(
          controller.error,
          LimousineAcceptedBookingError.paymentCapabilityUnavailable,
        );
        controller.setConfirmationAcknowledged(true);
        expect(await controller.confirmBooking(), isFalse);
        expect(gateway.calls, 0);
        controller.dispose();
      },
    );

    testWidgets('A4b) the page shows a retry instead of every method', (
      tester,
    ) async {
      final controller = _controller(
        gateway: _BookGateway(),
        capability: null,
        loader: () async => null,
      );
      await _pumpPage(tester, controller);
      expect(
        find.byKey(kLimousineAcceptedBookingPaymentSectionKey),
        findsOneWidget,
      );
      expect(
        find.byKey(kLimousineAcceptedBookingPaymentRetryKey),
        findsOneWidget,
      );
      expect(
        find.byKey(
          limousineAcceptedBookingPaymentMethodKey(
            PaymentMethodIds.inVehicleCard,
          ),
        ),
        findsNothing,
      );
      controller.dispose();
    });

    test(
      'A5) the capability comes from the quote read, not from this device',
      () {
        final api = _readSource(
          'lib/limousine/limousine_accepted_booking_api.dart',
        );
        final page = _readSource(
          'lib/limousine/limousine_accepted_booking_page.dart',
        );
        for (final source in <String>[api, page]) {
          expect(
            source.contains('localBackendBusinessProfileNotifier'),
            isFalse,
            reason: 'the device-local company is not the marketplace partner',
          );
        }
        expect(
          api.contains('/limousine/quote-requests/status'),
          isTrue,
          reason: 'capability is reread from the authoritative quote status',
        );
        expect(api.contains('BookingPaymentCapability.fromPublicJson'), isTrue);
      },
    );

    test('A6) capability survives process death by being reread', () async {
      var attempt = 0;
      final controller = _controller(
        gateway: _BookGateway(),
        capability: null,
        loader: () async {
          attempt += 1;
          return attempt == 1 ? null : _manualOnly;
        },
      );
      await controller.loadPaymentCapability();
      expect(controller.visiblePaymentMethodIds, isEmpty);
      expect(controller.canConfirmBooking, isFalse);

      await controller.loadPaymentCapability();
      expect(controller.capabilityLoads, 2);
      expect(controller.visiblePaymentMethodIds, <String>[
        PaymentMethodIds.inVehicleCard,
      ]);
      controller.setConfirmationAcknowledged(true);
      expect(controller.canConfirmBooking, isTrue);
      controller.dispose();
    });
  });

  group('B) the choice is explicit', () {
    test('B1) without a usable choice nothing is submitted', () async {
      final gateway = _BookGateway();
      final controller = _controller(
        gateway: gateway,
        capability: _onlineBancontact,
      );
      controller.selectedPaymentMethodId = null;
      controller.setConfirmationAcknowledged(true);
      expect(controller.hasPaymentSelection, isFalse);
      expect(controller.canConfirmBooking, isFalse);
      expect(await controller.confirmBooking(), isFalse);
      expect(gateway.calls, 0);
      expect(
        controller.error,
        LimousineAcceptedBookingError.paymentMethodRequired,
      );
      controller.dispose();
    });

    test('B1b) a method the partner does not accept is not a selection', () {
      final controller = _controller(gateway: _BookGateway());
      controller.selectPaymentMethod(PaymentMethodIds.bancontact);
      expect(
        controller.selectedPaymentMethodId,
        PaymentMethodIds.inVehicleCard,
        reason: 'an unaccepted tap leaves the previous choice alone',
      );
      controller.dispose();
    });

    test(
      'B2) an explicit manual choice maps to the canonical manual fields',
      () async {
        final gateway = _BookGateway();
        final controller = _controller(gateway: gateway);
        controller.selectPaymentMethod(PaymentMethodIds.inVehicleCard);
        controller.setConfirmationAcknowledged(true);
        expect(await controller.confirmBooking(), isTrue);
        final payload = gateway.lastPayload!;
        expect(payload['payment_mode'], 'manual');
        expect(payload['payment_provider'], 'manual');
        expect(payload['payment_method'], PaymentMethodIds.inVehicleCard);
        expect(payload.containsKey('mollie_method'), isFalse);
        expect(payload.containsKey('qr_preferred'), isFalse);
        expect(
          payload['payment_mode'],
          BookingPaymentSelection.fromMethodId(
            PaymentMethodIds.inVehicleCard,
          ).toPayloadFields()['payment_mode'],
          reason: 'same mapper as taxi and airport',
        );
        controller.dispose();
      },
    );

    test(
      'B3) an explicit online choice maps to the canonical Mollie fields',
      () async {
        final gateway = _BookGateway(raw: _mollieCheckoutRaw);
        final controller = _controller(
          gateway: gateway,
          capability: _onlineBancontact,
        );
        controller.selectPaymentMethod(PaymentMethodIds.bancontact);
        controller.setConfirmationAcknowledged(true);
        expect(await controller.confirmBooking(), isTrue);
        final payload = gateway.lastPayload!;
        expect(payload['payment_mode'], 'mollie');
        expect(payload['payment_provider'], 'mollie');
        expect(payload['payment_method'], PaymentMethodIds.bancontact);
        expect(payload['mollie_method'], 'bancontact');
        expect(
          payload['mollie_method'],
          BookingPaymentSelection.fromMethodId(
            PaymentMethodIds.bancontact,
          ).toPayloadFields()['mollie_method'],
        );
        controller.dispose();
      },
    );

    test('B4) the payload carries the latest choice', () async {
      final gateway = _BookGateway();
      final controller = _controller(
        gateway: gateway,
        capability: _onlineBancontact,
      );
      controller.selectPaymentMethod(PaymentMethodIds.bancontact);
      controller.selectPaymentMethod(PaymentMethodIds.inVehicleCard);
      controller.setConfirmationAcknowledged(true);
      expect(await controller.confirmBooking(), isTrue);
      expect(
        gateway.lastPayload!['payment_method'],
        PaymentMethodIds.inVehicleCard,
      );
      expect(gateway.lastPayload!['payment_mode'], 'manual');
      controller.dispose();
    });

    test('B5) no cash default is left in the payload chain', () {
      final payloadSource = _readSource(
        'lib/limousine/limousine_accepted_booking.dart',
      );
      final apiSource = _readSource(
        'lib/limousine/limousine_accepted_booking_api.dart',
      );
      expect(
        payloadSource.contains('required BookingPaymentSelection payment'),
        isTrue,
        reason: 'the caller must state the method',
      );
      for (final source in <String>[payloadSource, apiSource]) {
        expect(
          RegExp(
            r"BookingPaymentSelection\.fromMethodId\(\s*PaymentMethodIds\.(cash|inVehicleCard)",
          ).hasMatch(source),
          isFalse,
          reason: 'no built-in manual method',
        );
        expect(source.contains('PaymentMethodIds.cash'), isFalse);
        expect(
          source.contains('BookingPaymentSelection.defaultManualMethodId'),
          isFalse,
        );
      }
    });
  });

  group('C) the existing surfaces keep their own behaviour', () {
    test('C1/C2) taxi and airport resolve options through the shared seam', () {
      final calculator = _readSource('lib/calculator_page.dart');
      final airport = _readSource(
        'lib/airport/airport_booking_review_page.dart',
      );
      for (final source in <String>[calculator, airport]) {
        expect(source.contains('BookingPaymentOptions('), isTrue);
        expect(source.contains('BookingPaymentMethodTile('), isTrue);
      }
      expect(
        File(
          'test/payment/booking_payment_options_characterization_test.dart',
        ).existsSync(),
        isTrue,
        reason: 'the landed characterization suite still guards them',
      );
    });

    test('C3/C4/C5) limousine asks the same resolver the same questions', () {
      final resolved = BookingPaymentOptions(
        capability: _onlineBancontact,
        countryCode: paymentMarketCountryCode(_onlineBancontact.countryCode),
        languageCode: 'nl',
        isApplePlatform: false,
      );
      final controller = _controller(
        gateway: _BookGateway(),
        capability: _onlineBancontact,
      );
      expect(
        controller.visiblePaymentMethodIds,
        resolved.visibleMethodIds,
        reason: 'same ordering and same set as any other surface',
      );
      for (final id in resolved.visibleMethodIds) {
        expect(
          controller.selectablePaymentMethodIds.contains(id),
          !resolved.isDisplayOnly(id),
        );
      }
      controller.dispose();
    });
  });

  group('D) the booking lifecycle stays canonical', () {
    test(
      'D1) the accepted price is never sent, whichever method is chosen',
      () async {
        for (final entry in <(BookingPaymentCapability, String)>[
          (_manualOnly, PaymentMethodIds.inVehicleCard),
          (_onlineBancontact, PaymentMethodIds.bancontact),
        ]) {
          final gateway = _BookGateway(
            raw: entry.$2 == PaymentMethodIds.bancontact
                ? _mollieCheckoutRaw
                : null,
          );
          final controller = _controller(
            gateway: gateway,
            capability: entry.$1,
          );
          controller.selectPaymentMethod(entry.$2);
          controller.setConfirmationAcknowledged(true);
          expect(await controller.confirmBooking(), isTrue);
          final payload = gateway.lastPayload!;
          expect(payload.containsKey('total_incl_vat_cents'), isFalse);
          expect(payload.containsKey('price_incl_vat'), isFalse);
          expect(payload.containsKey('amount'), isFalse);
          expect(payload['limousine_acceptance_reference'], _acceptRef);
          expect(limousineAcceptedBookPayloadIsSafe(payload), isTrue);
          controller.dispose();
        }
      },
    );

    test('D2) a manual choice creates the booking through /book', () async {
      final gateway = _BookGateway();
      final controller = _controller(gateway: gateway);
      controller.setConfirmationAcknowledged(true);
      expect(await controller.confirmBooking(), isTrue);
      expect(gateway.calls, 1);
      expect(controller.result!.publicReference, 'FLX-100');
      expect(controller.checkoutStartFailed, isFalse);
      expect(
        fluxidiPendingPaymentNotifier.value,
        isNull,
        reason: 'a manual booking owes nothing to the payment coordinator',
      );
      controller.dispose();
    });

    test(
      'D3) an online choice uses the checkout the /book response carried',
      () async {
        final opened = <String>[];
        final gateway = _BookGateway(
          raw: const <String, dynamic>{
            'ok': true,
            'booking_id': 'B-300',
            'public_reference': 'FLX-300',
            'payment_booking_id': 'PB-300',
            'checkout_url': 'https://www.mollie.com/checkout/select-method/abc',
          },
        );
        final controller = _controller(
          gateway: gateway,
          capability: _onlineBancontact,
          checkoutOpener: (url) async {
            opened.add(url);
            return true;
          },
        );
        controller.selectPaymentMethod(PaymentMethodIds.bancontact);
        controller.setConfirmationAcknowledged(true);
        expect(await controller.confirmBooking(), isTrue);
        expect(opened, <String>[
          'https://www.mollie.com/checkout/select-method/abc',
        ]);
        expect(controller.checkoutStartFailed, isFalse);
        final pending = fluxidiPendingPaymentNotifier.value;
        expect(pending, isNotNull);
        expect(pending!.paymentBookingId, 'PB-300');
        expect(pending.publicBookingId, 'FLX-300');
        expect(
          pending.isChecking,
          isTrue,
          reason: 'the existing coordinator owns /pay/status from here',
        );
        expect(bookingCheckoutUrl(gateway.raw), opened.single);
        expect(bookingPaymentBookingId(gateway.raw), 'PB-300');
        controller.dispose();
      },
    );

    test(
      'D3b) a missing checkout link reports instead of switching method',
      () async {
        final gateway = _BookGateway(
          raw: const <String, dynamic>{
            'ok': true,
            'booking_id': 'B-301',
            'public_reference': 'FLX-301',
            'payment_booking_id': 'PB-301',
          },
        );
        final controller = _controller(
          gateway: gateway,
          capability: _onlineBancontact,
        );
        controller.selectPaymentMethod(PaymentMethodIds.bancontact);
        controller.setConfirmationAcknowledged(true);
        expect(await controller.confirmBooking(), isFalse);
        expect(controller.checkoutStartFailed, isTrue);
        expect(controller.succeeded, isFalse);
        expect(controller.checkoutPending, isTrue);
        expect(controller.canResumeCheckout, isTrue);
        expect(gateway.lastPayload!['payment_mode'], 'mollie');
        controller.dispose();
      },
    );

    test('D4) a retry after success creates no second booking', () async {
      final gateway = _BookGateway();
      final controller = _controller(gateway: gateway);
      controller.setConfirmationAcknowledged(true);
      expect(await controller.confirmBooking(), isTrue);
      expect(await controller.confirmBooking(), isFalse);
      expect(gateway.calls, 1);
      expect(controller.bookCalls, 1);
      controller.dispose();
    });

    test('D4b) a stale capability asks again without booking twice', () async {
      var loads = 0;
      final gateway = _BookGateway()
        ..error = const LimousineAcceptedBookException(
          code: 'payment_method_disabled_for_company',
        );
      final controller = _controller(
        gateway: gateway,
        capability: _onlineBancontact,
        loader: () async {
          loads += 1;
          return _manualOnly;
        },
      );
      controller.selectPaymentMethod(PaymentMethodIds.bancontact);
      controller.setConfirmationAcknowledged(true);
      expect(await controller.confirmBooking(), isFalse);
      expect(gateway.calls, 1);
      expect(loads, 1, reason: 'the authoritative capability is reread');
      expect(controller.visiblePaymentMethodIds, <String>[
        PaymentMethodIds.inVehicleCard,
      ]);
      expect(
        controller.selectedPaymentMethodId,
        PaymentMethodIds.inVehicleCard,
        reason: 'the customer confirms a method the partner still accepts',
      );
      expect(controller.succeeded, isFalse);
      controller.dispose();
    });

    test(
      'D5) a confirmed booking still reaches the bookings history',
      () async {
        final persisted = _Persisted();
        final gateway = _BookGateway();
        final controller = _controller(gateway: gateway, persisted: persisted);
        controller.setConfirmationAcknowledged(true);
        expect(await controller.confirmBooking(), isTrue);
        expect(persisted.calls, 1);
        expect(persisted.response!['public_reference'], 'FLX-100');
        expect(persisted.requestPayload!['payment_mode'], 'manual');
        expect(
          _readSource(
            'lib/limousine/limousine_accepted_booking_api.dart',
          ).contains('CustomerBookingsStore.instance.upsert'),
          isTrue,
        );
        controller.dispose();
      },
    );

    test('D6) no limousine payment engine, route or checkout screen', () {
      final api = _readCode(
        'lib/limousine/limousine_accepted_booking_api.dart',
      );
      final page = _readCode(
        'lib/limousine/limousine_accepted_booking_page.dart',
      );
      final payload = _readCode(
        'lib/limousine/limousine_accepted_booking.dart',
      );
      for (final source in <String>[api, page, payload]) {
        expect(source.contains('/pay/status'), isFalse);
        expect(source.contains('checkout-resume'), isFalse);
        expect(source.contains('mollie.com'), isFalse);
        expect(source.contains('WebView'), isFalse);
        expect(source.contains('api_key'), isFalse);
      }
      expect(
        api.contains("import '../payment_return.dart'"),
        isTrue,
        reason: 'the app-wide coordinator owns the payment lifecycle',
      );
      expect(
        api.contains("import '../payment/payment_booking_selection.dart'"),
        isTrue,
        reason: 'the canonical mapper, not a second one',
      );
      final worker = _readSource('workers/booking/fluxidi_booking_worker.js');
      expect(worker.contains('/limousine/checkout'), isFalse);
      expect(worker.contains('/limousine/pay'), isFalse);
    });
  });
}
