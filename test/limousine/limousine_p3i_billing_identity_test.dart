// P3I Phase 4 — the accepted limousine quote reuses the canonical buyer
// billing identity. Private is the default. A company invoice is an explicit
// customer choice that sends `billing_customer` and never a price, seller,
// invoice_intent or billing_customer_snapshot.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/payment/booking_billing_identity.dart';
import 'package:fluxidi_tracking/payment/booking_billing_identity_form.dart';
import 'package:fluxidi_tracking/payment/booking_payment_options.dart';
import 'package:fluxidi_tracking/payment/payment_booking_selection.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';

const String _acceptRef = 'limacc1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM';

const BookingPaymentCapability _manualOnly = BookingPaymentCapability(
  paymentOwnerMode: 'manual_only',
  paymentDemoMode: false,
  mollieConnected: false,
  publicPaymentOptions: <String>[PaymentMethodIds.inVehicleCard],
  countryCode: 'BE',
);

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

const BookingBillingIdentity _buyer = BookingBillingIdentity(
  legalName: 'Acme Events BVBA',
  vatNumber: 'BE0123456789',
  street: 'Kerkstraat 12',
  postalCode: '2000',
  city: 'Antwerpen',
  country: 'be',
  contactEmail: 'facturen@acme.example',
);

const List<String> _forbiddenAuthority = <String>[
  'invoice_intent',
  'invoiceIntent',
  'business_detected',
  'businessDetected',
  'invoice_requested',
  'invoiceRequested',
  'billing_customer_snapshot',
  'billingCustomerSnapshot',
  'seller',
  'seller_snapshot',
  'sellerSnapshot',
  'total_incl_vat_cents',
  'price_incl_vat',
  'price_ex_vat',
  'price_vat',
  'vat_treatment',
  'vat_rate',
];

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
      'vat_treatment': 'incl',
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
  _BookGateway();

  int calls = 0;
  Map<String, dynamic>? lastPayload;

  @override
  Future<LimousineAcceptedBookResult> book(Map<String, dynamic> payload) async {
    calls += 1;
    lastPayload = payload;
    return const LimousineAcceptedBookResult(
      bookingId: 'B-100',
      publicReference: 'FLX-100',
      raw: <String, dynamic>{
        'ok': true,
        'booking_id': 'B-100',
        'public_reference': 'FLX-100',
      },
    );
  }
}

LimousineAcceptedBookingController _controller({
  required _BookGateway gateway,
  BookingPaymentCapability capability = _manualOnly,
}) {
  return LimousineAcceptedBookingController(
    handoff: _handoff(),
    draft: _draft(),
    request: _request(),
    providerName: 'Coachline Limousines',
    entryEnabled: true,
    gateway: gateway,
    customerOverride: _customer,
    customerLoader: () async => _customer,
    initialPaymentCapability: capability,
    isApplePaymentPlatform: false,
    persister:
        ({
          required response,
          required requestPayload,
          required customer,
        }) async {},
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  LimousineAcceptedBookingController controller,
) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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

Future<void> _acknowledge(WidgetTester tester) async {
  final finder = find.byKey(kLimousineAcceptedBookingConfirmKey);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _enableBusinessInvoice(WidgetTester tester) async {
  final finder = find.byKey(kBookingBillingToggleKey);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _enterField(
  WidgetTester tester,
  BookingBillingFormField field,
  String value,
) async {
  final finder = find.byKey(bookingBillingFieldKey(field));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.enterText(finder, value);
  await tester.pump();
}

Future<void> _fillCompleteBuyer(WidgetTester tester) async {
  await _enterField(
    tester,
    BookingBillingFormField.legalName,
    'Acme Events BVBA',
  );
  await _enterField(tester, BookingBillingFormField.vatNumber, 'BE0123456789');
  await _enterField(tester, BookingBillingFormField.street, 'Kerkstraat 12');
  await _enterField(tester, BookingBillingFormField.postalCode, '2000');
  await _enterField(tester, BookingBillingFormField.city, 'Antwerpen');
  await _enterField(tester, BookingBillingFormField.country, 'be');
}

FilledButton _submitButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.byKey(kLimousineAcceptedBookingSubmitKey),
  );
}

void _expectNoAuthorityKeys(Map<String, dynamic> payload) {
  for (final key in _forbiddenAuthority) {
    expect(payload.containsKey(key), isFalse, reason: 'leaked $key');
  }
  expect(limousineAcceptedBookPayloadIsSafe(payload), isTrue);
}

String _readSource(String path) => File(path).readAsStringSync();

String _readCode(String path) => _readSource(path)
    .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '')
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    appLanguageNotifier.value = AppLanguage.en;
  });

  group('A) private default and business choice on the page', () {
    testWidgets('A1) private/default shows the toggle and hides buyer fields', (
      tester,
    ) async {
      final controller = _controller(gateway: _BookGateway());
      await _pumpPage(tester, controller);
      expect(
        find.byKey(kLimousineAcceptedBookingBillingSectionKey),
        findsOneWidget,
      );
      expect(find.byKey(kBookingBillingToggleKey), findsOneWidget);
      expect(
        find.byKey(bookingBillingFieldKey(BookingBillingFormField.legalName)),
        findsNothing,
      );
      expect(controller.billingEnabled, isFalse);
      expect(
        find.text('This does not change the accepted total.'),
        findsOneWidget,
      );
      controller.dispose();
    });

    testWidgets('A2) enabling business invoice reveals the buyer fields', (
      tester,
    ) async {
      final controller = _controller(gateway: _BookGateway());
      await _pumpPage(tester, controller);
      await _enableBusinessInvoice(tester);
      expect(controller.billingEnabled, isTrue);
      expect(
        find.byKey(bookingBillingFieldKey(BookingBillingFormField.legalName)),
        findsOneWidget,
      );
      expect(
        find.byKey(bookingBillingFieldKey(BookingBillingFormField.vatNumber)),
        findsOneWidget,
      );
      expect(
        find.byKey(bookingBillingFieldKey(BookingBillingFormField.street)),
        findsOneWidget,
      );
      controller.dispose();
    });

    testWidgets('A3) incomplete business identity disables the CTA', (
      tester,
    ) async {
      final controller = _controller(gateway: _BookGateway());
      await _pumpPage(tester, controller);
      await _acknowledge(tester);
      await tester.ensureVisible(
        find.byKey(kLimousineAcceptedBookingSubmitKey),
      );
      await tester.pump();
      expect(_submitButton(tester).onPressed, isNotNull);

      await _enableBusinessInvoice(tester);
      await tester.ensureVisible(
        find.byKey(kLimousineAcceptedBookingSubmitKey),
      );
      await tester.pump();
      expect(controller.canConfirmBooking, isFalse);
      expect(_submitButton(tester).onPressed, isNull);
      expect(find.byKey(kBookingBillingWarningKey), findsOneWidget);
      expect(
        find.text('Enter the company name for the invoice.'),
        findsOneWidget,
      );
      controller.dispose();
    });

    testWidgets('A4) completing required fields enables the CTA', (
      tester,
    ) async {
      final controller = _controller(gateway: _BookGateway());
      await _pumpPage(tester, controller);
      await _enableBusinessInvoice(tester);
      await _fillCompleteBuyer(tester);
      await _acknowledge(tester);
      await tester.ensureVisible(
        find.byKey(kLimousineAcceptedBookingSubmitKey),
      );
      await tester.pump();
      expect(controller.billingIdentity.isCompleteForBusinessInvoice, isTrue);
      expect(controller.canConfirmBooking, isTrue);
      expect(_submitButton(tester).onPressed, isNotNull);
      expect(find.byKey(kBookingBillingWarningKey), findsNothing);
      controller.dispose();
    });

    testWidgets('A5) turning business mode off removes the fragment', (
      tester,
    ) async {
      final gateway = _BookGateway();
      final controller = _controller(gateway: gateway);
      await _pumpPage(tester, controller);
      await _enableBusinessInvoice(tester);
      await _fillCompleteBuyer(tester);
      await tester.tap(find.byKey(kBookingBillingToggleKey));
      await tester.pump();
      expect(controller.billingEnabled, isFalse);
      expect(
        find.byKey(bookingBillingFieldKey(BookingBillingFormField.legalName)),
        findsNothing,
      );
      await _acknowledge(tester);
      await tester.ensureVisible(
        find.byKey(kLimousineAcceptedBookingSubmitKey),
      );
      await tester.pump();
      await tester.tap(find.byKey(kLimousineAcceptedBookingSubmitKey));
      await tester.pump();
      expect(gateway.calls, 1);
      expect(gateway.lastPayload!.containsKey('billing_customer'), isFalse);
      expect(gateway.lastPayload!.containsKey('invoice_email'), isFalse);
      controller.dispose();
    });

    testWidgets('A6) validation copy follows the page language', (
      tester,
    ) async {
      appLanguageNotifier.value = AppLanguage.fr;
      final controller = _controller(gateway: _BookGateway());
      await _pumpPage(tester, controller);
      await _enableBusinessInvoice(tester);
      expect(
        find.text('Indiquez le nom de l’entreprise pour la facture.'),
        findsOneWidget,
      );
      controller.dispose();
    });

    testWidgets('A7) the payment picker remains usable beside billing', (
      tester,
    ) async {
      final controller = _controller(
        gateway: _BookGateway(),
        capability: _onlineBancontact,
      );
      await _pumpPage(tester, controller);
      expect(
        find.byKey(
          limousineAcceptedBookingPaymentMethodKey(PaymentMethodIds.bancontact),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(
          limousineAcceptedBookingPaymentMethodKey(PaymentMethodIds.bancontact),
        ),
      );
      await tester.pump();
      await _enableBusinessInvoice(tester);
      expect(controller.selectedPaymentMethodId, PaymentMethodIds.bancontact);
      expect(controller.billingEnabled, isTrue);
      controller.dispose();
    });

    testWidgets('A8) unmounting disposes billing controllers', (tester) async {
      final controller = _controller(gateway: _BookGateway());
      await _pumpPage(tester, controller);
      await _enableBusinessInvoice(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
      controller.dispose();
    });
  });

  group('B) canonical payload', () {
    test('B1) private + manual sends no billing fragment', () async {
      final gateway = _BookGateway();
      final controller = _controller(gateway: gateway);
      controller.setConfirmationAcknowledged(true);
      expect(await controller.confirmBooking(), isTrue);
      final payload = gateway.lastPayload!;
      expect(payload.containsKey('billing_customer'), isFalse);
      expect(payload.containsKey('invoice_email'), isFalse);
      expect(payload['payment_mode'], 'manual');
      expect(payload['limousine_acceptance_reference'], _acceptRef);
      _expectNoAuthorityKeys(payload);
      controller.dispose();
    });

    test('B2) private + online sends no billing fragment', () async {
      final gateway = _BookGateway();
      final controller = _controller(
        gateway: gateway,
        capability: _onlineBancontact,
      );
      controller.selectPaymentMethod(PaymentMethodIds.bancontact);
      controller.setConfirmationAcknowledged(true);
      expect(await controller.confirmBooking(), isTrue);
      final payload = gateway.lastPayload!;
      expect(payload.containsKey('billing_customer'), isFalse);
      expect(payload['payment_mode'], 'mollie');
      _expectNoAuthorityKeys(payload);
      controller.dispose();
    });

    test('B3) business + manual uses the canonical buyer fragment', () async {
      final gateway = _BookGateway();
      final controller = _controller(gateway: gateway);
      controller.setBillingEnabled(true);
      controller.updateBillingIdentity(_buyer);
      controller.setConfirmationAcknowledged(true);
      expect(await controller.confirmBooking(), isTrue);
      final payload = gateway.lastPayload!;
      expect(payload['payment_mode'], 'manual');
      expect(payload['invoice_email'], 'facturen@acme.example');
      final billing = payload['billing_customer'] as Map<String, dynamic>;
      expect(billing['customer_type'], 'business');
      expect(billing['legal_name'], 'Acme Events BVBA');
      expect(billing['vat_number'], 'BE0123456789');
      expect(billing['display_name'], 'Acme Events BVBA');
      expect(billing['contact_email'], 'facturen@acme.example');
      expect(billing['contact_phone'], '+32470000000');
      final address = billing['billing_address'] as Map<String, dynamic>;
      expect(address['street'], 'Kerkstraat 12');
      expect(address['postal_code'], '2000');
      expect(address['city'], 'Antwerpen');
      expect(address['country'], 'BE');
      _expectNoAuthorityKeys(payload);
      expect(
        payload['billing_customer'],
        bookingBillingCustomerPayloadFields(
          enabled: true,
          identity: _buyer,
          defaultEmail: _customer.email,
          defaultPhone: _customer.phone,
        )['billing_customer'],
      );
      controller.dispose();
    });

    test('B4) business + online keeps payment and billing together', () async {
      final gateway = _BookGateway();
      final controller = _controller(
        gateway: gateway,
        capability: _onlineBancontact,
      );
      controller.selectPaymentMethod(PaymentMethodIds.bancontact);
      controller.setBillingEnabled(true);
      controller.updateBillingIdentity(_buyer);
      controller.setConfirmationAcknowledged(true);
      expect(await controller.confirmBooking(), isTrue);
      final payload = gateway.lastPayload!;
      expect(payload['payment_mode'], 'mollie');
      expect(payload['mollie_method'], 'bancontact');
      expect(
        (payload['billing_customer'] as Map)['legal_name'],
        'Acme Events BVBA',
      );
      _expectNoAuthorityKeys(payload);
      controller.dispose();
    });

    test('B5) incomplete business identity never calls /book', () async {
      final gateway = _BookGateway();
      final controller = _controller(gateway: gateway);
      controller.setBillingEnabled(true);
      controller.updateBillingIdentity(
        const BookingBillingIdentity(legalName: 'Acme Events BVBA'),
      );
      controller.setConfirmationAcknowledged(true);
      expect(controller.canConfirmBooking, isFalse);
      expect(await controller.confirmBooking(), isFalse);
      expect(gateway.calls, 0);
      expect(
        controller.error,
        LimousineAcceptedBookingError.billingIdentityIncomplete,
      );
      expect(controller.billingEnabled, isTrue);
      controller.dispose();
    });

    test('B6) buyer and marketplace partner stay different identities', () {
      final payload = limousineAcceptedBookPayload(
        handoff: _handoff(),
        draft: _draft(),
        customer: _customer,
        payment: BookingPaymentSelection.fromMethodId(
          PaymentMethodIds.inVehicleCard,
        ),
        billingEnabled: true,
        billing: _buyer,
      );
      final billing = payload['billing_customer'] as Map<String, dynamic>;
      expect(billing['legal_name'], 'Acme Events BVBA');
      expect(payload['public_partner_id'], 'p1');
      expect(payload['customer']['name'], 'Ada');
      expect(billing['legal_name'], isNot(payload['public_partner_id']));
      expect(billing['legal_name'], isNot(payload['customer']['name']));
      expect(billing.containsKey('seller'), isFalse);
      expect(billing.containsKey('company_id'), isFalse);
      expect(billing.containsKey('tenant_id'), isFalse);
    });

    test('B7) a typed invoice email is optional and wins when present', () {
      final withEmail =
          bookingBillingCustomerPayloadFields(
                enabled: true,
                identity: _buyer,
                defaultEmail: 'ada@example.com',
                defaultPhone: '+32470000000',
              )['billing_customer']
              as Map<String, dynamic>;
      expect(withEmail['contact_email'], 'facturen@acme.example');
      final without =
          bookingBillingCustomerPayloadFields(
                enabled: true,
                identity: const BookingBillingIdentity(
                  legalName: 'Acme Events BVBA',
                  vatNumber: 'BE0123456789',
                  street: 'Kerkstraat 12',
                  postalCode: '2000',
                  city: 'Antwerpen',
                  country: 'BE',
                ),
                defaultEmail: 'ada@example.com',
                defaultPhone: '+32470000000',
              )['billing_customer']
              as Map<String, dynamic>;
      expect(without['contact_email'], 'ada@example.com');
    });

    test(
      'B8) passenger name is never synthesized into a business identity',
      () {
        final payload = limousineAcceptedBookPayload(
          handoff: _handoff(),
          draft: _draft(),
          customer: _customer,
          payment: BookingPaymentSelection.fromMethodId(
            PaymentMethodIds.inVehicleCard,
          ),
        );
        expect(payload.containsKey('billing_customer'), isFalse);
        expect(payload['customer']['name'], 'Ada');
      },
    );
  });

  group('C) accepted price stays on the quote', () {
    test('C1) private and business payloads omit every amount key', () {
      for (final enabled in <bool>[false, true]) {
        final payload = limousineAcceptedBookPayload(
          handoff: _handoff(),
          draft: _draft(),
          customer: _customer,
          payment: BookingPaymentSelection.fromMethodId(
            PaymentMethodIds.inVehicleCard,
          ),
          billingEnabled: enabled,
          billing: enabled ? _buyer : BookingBillingIdentity.empty,
        );
        _expectNoAuthorityKeys(payload);
        expect(payload.containsKey('quote'), isFalse);
        expect(payload.containsKey('quote.pricing'), isFalse);
      }
    });

    test('C2) billing identity does not reread vehicle or package pricing', () {
      final payload = limousineAcceptedBookPayload(
        handoff: _handoff(),
        draft: _draft(),
        customer: _customer,
        payment: BookingPaymentSelection.fromMethodId(
          PaymentMethodIds.inVehicleCard,
        ),
        billingEnabled: true,
        billing: _buyer,
      );
      expect(_handoff().totalInclVatCents, 45000);
      expect(payload.containsKey('vehicle_price'), isFalse);
      final page = _readCode(
        'lib/limousine/limousine_accepted_booking_page.dart',
      );
      expect(page.contains('published_price'), isFalse);
      expect(page.contains('offer.pricing'), isFalse);
    });

    test('C3) labels tell the customer the accepted total is unchanged', () {
      expect(
        kLimousineAcceptedBookingBillingPriceUnchanged.of(AppLanguage.en),
        'This does not change the accepted total.',
      );
    });
  });

  group('D) process death and PII', () {
    test('D1) a new controller after resume is private until re-entry', () {
      final first = _controller(gateway: _BookGateway());
      first.setBillingEnabled(true);
      first.updateBillingIdentity(_buyer);
      expect(first.billingEnabled, isTrue);
      first.dispose();

      final resumed = _controller(gateway: _BookGateway());
      expect(resumed.billingEnabled, isFalse);
      expect(resumed.billingIdentity, BookingBillingIdentity.empty);
      expect(resumed.handoff.acceptanceReference, _acceptRef);
      resumed.dispose();
    });

    test(
      'D2) an active session never silently falls back to private',
      () async {
        final gateway = _BookGateway();
        final controller = _controller(gateway: gateway);
        controller.setBillingEnabled(true);
        controller.updateBillingIdentity(
          const BookingBillingIdentity(legalName: 'Acme Events BVBA'),
        );
        controller.setConfirmationAcknowledged(true);
        expect(await controller.confirmBooking(), isFalse);
        expect(controller.billingEnabled, isTrue);
        expect(gateway.calls, 0);
        controller.dispose();
      },
    );

    test('D3) billing PII is not written into tokens, logs or resume', () {
      final api = _readCode(
        'lib/limousine/limousine_accepted_booking_api.dart',
      );
      final resume = _readCode(
        'lib/limousine/limousine_accepted_booking_resume.dart',
      );
      expect(resume.contains('BookingBillingIdentity'), isFalse);
      expect(resume.contains('billing_customer'), isFalse);
      expect(api.contains("limousineAcceptedBookingTextLeaksToken"), isTrue);
      expect(api.contains("_safeLog('book_blocked')"), isTrue);
    });
  });

  group('E) taxi/airport keep their own UI and the shared mapper', () {
    test('E1) taxi and airport still render their inline billing forms', () {
      final taxi = _readCode('lib/calculator_page.dart');
      final airport = _readCode('lib/airport/airport_booking_review_page.dart');
      for (final source in <String>[taxi, airport]) {
        expect(source.contains('bookingBillingCustomerPayloadFields('), isTrue);
        expect(source.contains('BookingBillingIdentity('), isTrue);
        expect(source.contains('BookingBillingIdentityForm('), isFalse);
      }
    });

    test('E2) taxi keeps its distinct toggle copy', () {
      expect(
        _readSource(
          'lib/calculator_page.dart',
        ).contains('Ik wil een factuur op bedrijf'),
        isTrue,
      );
      expect(
        _readSource(
          'lib/airport/airport_booking_review_page.dart',
        ).contains('Ik heb een bedrijfsfactuur nodig'),
        isTrue,
      );
    });
  });

  group('F) no second engine, no device-local seller', () {
    test(
      'F1) accepted-booking files never read the device company profile',
      () {
        for (final path in <String>[
          'lib/limousine/limousine_accepted_booking.dart',
          'lib/limousine/limousine_accepted_booking_api.dart',
          'lib/limousine/limousine_accepted_booking_page.dart',
          'lib/payment/booking_billing_identity.dart',
          'lib/payment/booking_billing_identity_form.dart',
        ]) {
          expect(
            _readCode(path).contains('localBackendBusinessProfileNotifier'),
            isFalse,
            reason: path,
          );
        }
      },
    );

    test('F2) no limousine invoice, Billit or Peppol engine', () {
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
        expect(source.contains('/limousine/invoice'), isFalse);
        expect(source.contains('/limousine/billit'), isFalse);
        expect(source.contains('/limousine/peppol'), isFalse);
        expect(source.contains('ensureBillitOrder'), isFalse);
        expect(source.contains('_issueInvoiceCore'), isFalse);
      }
      final worker = _readSource('workers/booking/fluxidi_booking_worker.js');
      expect(worker.contains('/limousine/invoice'), isFalse);
      expect(worker.contains('/limousine/billit'), isFalse);
      expect(worker.contains('/limousine/peppol'), isFalse);
      expect(worker.contains('normalizeBillingCustomerIdentityInput'), isTrue);
      expect(
        worker.contains('ensureDocumentCoreInvoiceForPaidBusinessBooking'),
        isTrue,
      );
      expect(
        worker.contains('ensureBillitOrderForPaidBusinessBooking'),
        isTrue,
      );
    });

    testWidgets('F3) a submitted business booking still goes through /book', (
      tester,
    ) async {
      final gateway = _BookGateway();
      final controller = _controller(gateway: gateway);
      await _pumpPage(tester, controller);
      await _enableBusinessInvoice(tester);
      await _fillCompleteBuyer(tester);
      await _acknowledge(tester);
      await tester.ensureVisible(
        find.byKey(kLimousineAcceptedBookingSubmitKey),
      );
      await tester.pump();
      await tester.tap(find.byKey(kLimousineAcceptedBookingSubmitKey));
      await tester.pump();
      expect(gateway.calls, 1);
      expect(
        gateway.lastPayload!['limousine_acceptance_reference'],
        _acceptRef,
      );
      expect(gateway.lastPayload!['billing_customer'], isA<Map>());
      controller.dispose();
    });
  });
}
