import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/company/subscription_payment_confirmation.dart';
import 'package:fluxidi_tracking/company/subscription_payment_dialog.dart';
import 'package:fluxidi_tracking/company/subscription_checkout_quote_pipeline.dart';
import 'package:fluxidi_tracking/company/extra_vehicle_addon_purchase.dart';

Map<String, dynamic> checkout({
  String product = 'fluxidi_pro',
  String treatment = 'reviewed_taxable',
  int net = 4900,
  int vat = 1029,
  String currency = 'EUR',
  DateTime? until,
}) => {
  'ok': true,
  'activation_id': 'act_fixture',
  'provider_payment_id': 'tr_fixture',
  'checkout_url': 'https://checkout.mollie.com/payments/tr_fixture',
  'currency': currency,
  'expected_amount_cents': net + vat,
  'amount_excl_vat_cents': net,
  'vat_amount_cents': vat,
  if (product != 'fluxidi_pro') ...{'addon_code': product, 'quantity': 1},
  'tax_totals': {
    'ex_vat_cents': net,
    'vat_cents': vat,
    'gross_cents': net + vat,
    'treatment': treatment,
  },
  'payment_confirmation': {
    'version': 'subscription_payment_confirmation_v1',
    'tenant_id': 'C',
    'company_id': 'C',
    'activation_id': 'act_fixture',
    'provider_payment_id': 'tr_fixture',
    'product_code': product,
    'quantity': 1,
    'currency': currency,
    'ex_vat_cents': net,
    'vat_cents': vat,
    'gross_cents': net + vat,
    'treatment': treatment,
    'recorded_at': '2026-01-01T00:00:00.000Z',
    'valid_until': DateTime.fromMillisecondsSinceEpoch((until ?? DateTime.utc(2050)).millisecondsSinceEpoch, isUtc: true).toIso8601String(),
  },
};
ActiveCompanySession session({
  String company = 'C',
  String token = 'fixture',
  DateTime? expiry,
}) => ActiveCompanySession(
  companyId: company,
  role: 'companyAdmin',
  createdAt: 'fixture',
  lastUsedAt: 'fixture',
  companySessionToken: token,
  companySessionExpiresAtUtc: (expiry ?? DateTime.utc(2050)).toIso8601String(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => activeCompanySessionNotifier.value = null);
  for (final addon in [false, true]) {
    test(
      'actual ${addon ? 'addon' : 'base'} HTTP refuses a stale owner before POST',
      () async {
        int calls = 0;
        await http.runWithClient(
          () async {
            final result = addon
                ? await startCompanySubscriptionAddonCheckout(
                    tenantId: 'C',
                    companyId: 'C',
                    addonCode: 'extra_driver',
                    ownerIsCurrent: () => false,
                  )
                : await startCompanySubscriptionCheckout(
                    tenantId: 'C',
                    companyId: 'C',
                    ownerIsCurrent: () => false,
                  );
            expect(result.ok, isFalse);
            expect(result.error, 'checkout_owner_changed');
          },
          () => MockClient((_) async {
            calls++;
            return http.Response('{}', 500);
          }),
        );
        expect(calls, 0);
      },
    );
    test(
      'actual ${addon ? 'addon' : 'base'} HTTP cannot adopt a delayed response after logout',
      () async {
        activeCompanySessionNotifier.value = session();
        final owner = SubscriptionPaymentOwner('C');
        final reply = Completer<http.Response>(), requested = Completer<void>();
        final product = addon ? 'extra_driver' : 'fluxidi_pro';
        await http.runWithClient(
          () async {
            final pending = addon
                ? startCompanySubscriptionAddonCheckout(
                    tenantId: 'C',
                    companyId: 'C',
                    addonCode: product,
                    ownerIsCurrent: () => owner.isCurrent,
                  )
                : startCompanySubscriptionCheckout(
                    tenantId: 'C',
                    companyId: 'C',
                    ownerIsCurrent: () => owner.isCurrent,
                  );
            await requested.future;
            activeCompanySessionNotifier.value = null;
            activeCompanySessionNotifier.value = session();
            reply.complete(
              http.Response(jsonEncode(checkout(product: product)), 200),
            );
            final result = await pending;
            expect(result.ok, isFalse);
            expect(result.error, 'checkout_owner_changed');
            expect(result.paymentConfirmation, isNull);
          },
          () => MockClient((request) {
            expect(jsonDecode(request.body), isNot(contains('amount_cents')));
            requested.complete();
            return reply.future;
          }),
        );
        owner.dispose();
      },
    );
  }
  for (final product in kSupportedSubscriptionPurchaseCodes) {
    test('$product accepts server cents and rejects another company', () {
      final typed = BackendSubscriptionCheckoutStartResult.fromJson(
        checkout(
          product: product,
          net: product == 'fluxidi_pro' ? 4900 : 950,
          vat: product == 'fluxidi_pro' ? 1029 : 200,
        ),
      );
      expect(typed.paymentConfirmation, isNotNull);
      expect(
        typed.paymentConfirmation!.validFor(
          companyId: 'C',
          productCode: product,
        ),
        isTrue,
      );
      expect(
        typed.paymentConfirmation!.grossCents,
        product == 'fluxidi_pro' ? 5929 : 1150,
      );
      expect(
        typed.paymentConfirmation!.validFor(
          companyId: 'OTHER',
          productCode: product,
        ),
        isFalse,
      );
    });
  }
  for (final treatment in ['eu_b2b_reverse_charge', 'reviewed_zero_rate']) {
    test('$treatment retains its zero VAT meaning and currency', () {
      final c = SubscriptionPaymentConfirmation.fromCheckoutJson(
        checkout(treatment: treatment, vat: 0, currency: 'USD'),
      )!;
      expect(c.currency, 'USD');
      expect(c.vatCents, 0);
      expect(c.treatment, treatment);
    });
  }
  test(
    'taxable one-cent proration may round VAT to zero without becoming a zero-rate treatment',
    () {
      final c = SubscriptionPaymentConfirmation.fromCheckoutJson(
        checkout(net: 1, vat: 0),
      )!;
      expect(c.grossCents, 1);
      expect(c.treatment, 'reviewed_taxable');
    },
  );
  final malformed = <String, void Function(Map<String, dynamic>)>{
    'legacy without proof': (r) => r.remove('payment_confirmation'),
    'negative': (r) => r['payment_confirmation']['ex_vat_cents'] = -1,
    'fractional': (r) => r['payment_confirmation']['gross_cents'] = 5929.5,
    'numeric string': (r) => r['expected_amount_cents'] = '5929',
    'root double': (r) => r['expected_amount_cents'] = 5929.0,
    'redundant double': (r) => r['tax_totals']['gross_cents'] = 5929.0,
    'overflow': (r) =>
        r['payment_confirmation']['ex_vat_cents'] = 9007199254740992,
    'gross mismatch': (r) => r['expected_amount_cents'] = 6900,
    'net mismatch': (r) => r['amount_excl_vat_cents'] = 6900,
    'tax alias mismatch': (r) => r['tax_totals']['vat_cents'] = 0,
    'payment mismatch': (r) => r['provider_payment_id'] = 'tr_other',
    'activation mismatch': (r) => r['activation_id'] = 'act_other',
    'currency mismatch': (r) => r['currency'] = 'USD',
    'guessed treatment': (r) =>
        r['payment_confirmation']['treatment'] = 'belgian_vat',
    'unknown product': (r) =>
        r['payment_confirmation']['product_code'] = 'free_extra',
    'quantity string': (r) => r['payment_confirmation']['quantity'] = '1',
    'wrong addon': (r) {
      r['payment_confirmation']['product_code'] = 'extra_driver';
      r['addon_code'] = 'extra_vehicle';
      r['quantity'] = 1;
    },
    'addon double quantity': (r) {
      r['payment_confirmation']['product_code'] = 'extra_driver';
      r['addon_code'] = 'extra_driver';
      r['quantity'] = 1.0;
    },
    'reverse with VAT': (r) =>
        r['payment_confirmation']['treatment'] = 'eu_b2b_reverse_charge',
    'invalid date': (r) =>
        r['payment_confirmation']['valid_until'] = '2050-02-31T00:00:00.000Z',
    'date absent': (r) => r['payment_confirmation'].remove('recorded_at'),
    'non-HTTPS URL': (r) =>
        r['checkout_url'] = 'http://checkout.mollie.com/payments/tr_fixture',
    'unapproved': (r) => r['ok'] = false,
  };
  for (final entry in malformed.entries) {
    test('${entry.key} blocks final payment confirmation', () {
      final r = checkout();
      entry.value(r);
      expect(
        BackendSubscriptionCheckoutStartResult.fromJson(r).paymentConfirmation,
        isNull,
      );
    });
  }
  test('expiry is exclusive and future recording cannot authorize payment', () {
    final c = SubscriptionPaymentConfirmation.fromCheckoutJson(
      checkout(until: DateTime.utc(2026, 10, 5)),
    )!;
    expect(
      c.validFor(
        companyId: 'C',
        productCode: 'fluxidi_pro',
        now: DateTime.utc(2026, 10, 5),
      ),
      isFalse,
    );
    expect(
      c.validFor(
        companyId: 'C',
        productCode: 'fluxidi_pro',
        now: DateTime.utc(2025),
      ),
      isFalse,
    );
  });
  test('identical company/token cannot revive an owner after logout', () {
    activeCompanySessionNotifier.value = session();
    final owner = SubscriptionPaymentOwner('C');
    expect(owner.isCurrent, isTrue);
    activeCompanySessionNotifier.value = null;
    activeCompanySessionNotifier.value = session();
    expect(owner.isCurrent, isFalse);
    owner.dispose();
  });
  test(
    'intent may request review without inferring reverse charge or changing capacity',
    () {
      final resolution = resolveSubscriptionPurchaseQuote(
        productCode: 'fluxidi_pro',
        quantity: 1,
        fiscalKnown: false,
        fiscalTreatment: 'eu_reverse_charge',
        fiscalMissingFields: ['vat_number'],
        profilePrices: const SubscriptionProfilePriceSlice(
          baseExclCents: 6900,
          extraVehicleExclCents: 1900,
          extraDriverExclCents: 900,
          pdfBundleExclCents: {},
        ),
        live: const SubscriptionQuoteFetchVerdict(
          kind: SubscriptionQuoteFailureKind.routeMissing,
        ),
        intentOnly: true,
      );
      expect(resolution.canConfirm, isTrue);
      expect(resolution.quote!.taxTreatment, isEmpty);
      final fleet = ExtraVehiclePurchaseSession(
        startingCapacity: 1,
        intentOnly: true,
      );
      expect(
        fleet.beginConfirmation(),
        ExtraVehiclePurchasePhase.awaitingConfirmation,
      );
      expect(fleet.acceptConfirmation(), isTrue);
      expect(fleet.mayOpenVehicleCreateForm, isFalse);
    },
  );
  for (final language in ['nl', 'en', 'fr', 'es']) {
    testWidgets('$language shows founder net, VAT and gross before accepting', (
      tester,
    ) async {
      activeCompanySessionNotifier.value = session();
      final owner = SubscriptionPaymentOwner('C');
      addTearDown(owner.dispose);
      bool? accepted;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  accepted = await confirmSubscriptionPayment(
                    context: context,
                    confirmation:
                        BackendSubscriptionCheckoutStartResult.fromJson(
                          checkout(),
                        ).paymentConfirmation,
                    owner: owner,
                    productCode: 'fluxidi_pro',
                    languageCode: language,
                    stillMounted: () => context.mounted,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.text('${subscriptionPaymentText(language, 'net')}: EUR 49.00'),
        findsOneWidget,
      );
      expect(
        find.text('${subscriptionPaymentText(language, 'vat')}: EUR 10.29'),
        findsOneWidget,
      );
      expect(
        find.text('${subscriptionPaymentText(language, 'total')}: EUR 59.29'),
        findsOneWidget,
      );
      expect(accepted, isNull);
      await tester.tap(find.byKey(const Key('payment-accept')));
      await tester.pumpAndSettle();
      expect(accepted, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final change in ['cancel', 'logout', 'switch', 'token', 'expire']) {
    testWidgets('$change cannot authorize payment', (tester) async {
      activeCompanySessionNotifier.value = session();
      final owner = SubscriptionPaymentOwner('C');
      addTearDown(owner.dispose);
      bool? accepted;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  accepted = await confirmSubscriptionPayment(
                    context: context,
                    confirmation:
                        BackendSubscriptionCheckoutStartResult.fromJson(
                          checkout(
                            product: 'extra_vehicle',
                            net: 950,
                            vat: 200,
                          ),
                        ).paymentConfirmation,
                    owner: owner,
                    productCode: 'extra_vehicle',
                    languageCode: 'nl',
                    stillMounted: () => context.mounted,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Te betalen totaal: EUR 11.50'), findsOneWidget);
      if (change == 'cancel') await tester.tap(find.text('Annuleren'));
      if (change == 'logout') {
        activeCompanySessionNotifier.value = null;
        activeCompanySessionNotifier.value = session();
      }
      if (change == 'switch')
        activeCompanySessionNotifier.value = session(company: 'OTHER');
      if (change == 'token')
        activeCompanySessionNotifier.value = session(token: 'other');
      if (change == 'expire')
        activeCompanySessionNotifier.value = session(
          expiry: DateTime.utc(2020),
        );
      await tester.pumpAndSettle();
      expect(accepted, isFalse);
      expect(find.byKey(const Key('payment-accept')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('logout closes only its own confirmation under a newer route', (
    tester,
  ) async {
    activeCompanySessionNotifier.value = session();
    final owner = SubscriptionPaymentOwner('C');
    addTearDown(owner.dispose);
    final navigator = GlobalKey<NavigatorState>();
    bool? accepted;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                accepted = await confirmSubscriptionPayment(
                  context: context,
                  confirmation: BackendSubscriptionCheckoutStartResult.fromJson(
                    checkout(),
                  ).paymentConfirmation,
                  owner: owner,
                  productCode: 'fluxidi_pro',
                  languageCode: 'nl',
                  stillMounted: () => context.mounted,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('New route')),
      ),
    );
    await tester.pumpAndSettle();
    activeCompanySessionNotifier.value = null;
    await tester.pumpAndSettle();
    expect(accepted, isFalse);
    expect(find.text('New route'), findsOneWidget);
    expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('expiry while the dialog is open cancels confirmation', (
    tester,
  ) async {
    activeCompanySessionNotifier.value = session();
    final owner = SubscriptionPaymentOwner('C');
    addTearDown(owner.dispose);
    bool? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                accepted = await confirmSubscriptionPayment(
                  context: context,
                  confirmation: BackendSubscriptionCheckoutStartResult.fromJson(
                    checkout(
                      until: DateTime.now().toUtc().add(
                        const Duration(milliseconds: 500),
                      ),
                    ),
                  ).paymentConfirmation,
                  owner: owner,
                  productCode: 'fluxidi_pro',
                  languageCode: 'nl',
                  stillMounted: () => context.mounted,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(accepted, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('missing proof does not show a payment dialog', (tester) async {
    activeCompanySessionNotifier.value = session();
    final owner = SubscriptionPaymentOwner('C');
    addTearDown(owner.dispose);
    bool? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                accepted = await confirmSubscriptionPayment(
                  context: context,
                  confirmation: null,
                  owner: owner,
                  productCode: 'fluxidi_pro',
                  languageCode: 'nl',
                  stillMounted: () => context.mounted,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(accepted, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'all five purchase paths connect checkout result to strict confirmation',
    () {
      final billing = File(
        'lib/main_parts/company_subscription_billing_state.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      for (final method in [
        '_startCheckout',
        '_startExtraVehicleAddonCheckout',
        '_startExtraDriverAddonCheckout',
        '_startPdfBundleCheckout',
      ]) {
        final start = billing.indexOf('Future<void> $method(');
        final block = billing.substring(
          start,
          billing.indexOf('\n  }\n', start),
        );
        expect(
          block.indexOf('_confirmServerCheckout('),
          greaterThan(
            block.indexOf('final result = await startCompanySubscription'),
          ),
        );
        expect(block, contains('SubscriptionPaymentOwner(scopeId)'));
        expect(block, contains('owner.dispose()'));
      }
      final vehicle = File(
        'lib/vehicle_management_page.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final start = vehicle.indexOf(
        'Future<bool> _purchaseExtraVehicleSlotThenAllowCreate(',
      );
      final block = vehicle.substring(start, vehicle.indexOf('\n  }\n', start));
      expect(
        block.indexOf('confirmSubscriptionPayment('),
        lessThan(block.indexOf('final launched = await launchUrl')),
      );
      expect(block, contains('confirmation: result.paymentConfirmation'));
      expect(block, contains('owner.dispose()'));
    },
  );
}
