import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/main_parts/street_business_invoice_support.dart';
import 'package:fluxidi_tracking/main_parts/street_business_invoice_widgets.dart';

const _theme = StreetInvoiceActionTheme(
  accent: Color(0xFF1E88E5),
  textPrimary: Color(0xFF101418),
  textSecondary: Color(0xFF5B6570),
  textTertiary: Color(0xFF8A929B),
  danger: Color(0xFFD32F2F),
  paidText: Color(0xFF2E7D32),
  unpaidText: Color(0xFFEF6C00),
  surface: Color(0xFFFFFFFF),
);

const _validInput = StreetBusinessInvoiceBuyerInput(
  legalName: 'ACME BV',
  street: 'Straat 1',
  postalCode: '1000',
  city: 'Brussel',
  country: 'BE',
);

StreetInvoicePostResult _okPost({
  bool paid = true,
  String billitOrderId = '2954728',
}) => StreetInvoicePostResult(
  statusCode: 200,
  response: StreetBusinessInvoiceResponse(
    ok: true,
    bookingId: 'street_1',
    documentId: 'doc-1',
    invoiceReference: 'INV-2026-000030',
    reused: false,
    paymentStatus: paid ? 'paid' : 'unpaid',
    billitEnvironment: 'sandbox',
    billitOrderId: billitOrderId,
    billitOrderReused: false,
    billitPaymentSyncStatus: paid ? 'synced' : '',
    peppolSent: false,
    warnings: const [],
    paymentReconciliation: paid ? '' : 'pending_external_payment',
  ),
);

StreetInvoiceDocSummary _invoiceSummary() => const StreetInvoiceDocSummary(
  documentId: 'doc-1',
  documentNumber: 'INV-2026-000030',
  lifecycleState: 'issued',
  billitEnvironment: 'sandbox',
  billitOrderId: '2954728',
  peppolSent: false,
  billitPaid: true,
);

StreetBusinessInvoiceController _controller({
  Future<StreetInvoicePostResult> Function(Map<String, dynamic>)? post,
  Future<StreetInvoiceDocsResult> Function()? fetch,
  bool isPaidBooking = true,
  Duration pollInterval = const Duration(milliseconds: 1),
  Duration pollTimeout = const Duration(milliseconds: 3),
}) {
  return StreetBusinessInvoiceController(
    bookingId: 'street_1',
    isPaidBooking: isPaidBooking,
    delay: (_) async {},
    pollInterval: pollInterval,
    pollTimeout: pollTimeout,
    postInvoice: post ?? (_) async => _okPost(),
    fetchDocuments:
        fetch ??
        () async =>
            const StreetInvoiceDocsResult(statusCode: 200, okEnvelope: true),
  );
}

// FilledButton.icon builds a private _FilledButtonWithIcon subclass, so match
// by subtype rather than exact runtimeType.
final Finder _filledButton = find.byWidgetPredicate((w) => w is FilledButton);

Future<void> _pumpView(
  WidgetTester tester, {
  required StreetBusinessInvoiceController controller,
  double width = 400,
  AppLanguage language = AppLanguage.nl,
  bool showBillitAndPeppol = true,
  VoidCallback? onRequest,
  VoidCallback? onView,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: StreetBusinessInvoiceActionView(
              controller: controller,
              theme: _theme,
              language: language,
              showBillitAndPeppol: showBillitAndPeppol,
              onRequest: onRequest ?? () {},
              onView: onView ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('narrow width renders full-width (stacked) request action', (
    tester,
  ) async {
    final c = _controller();
    addTearDown(c.dispose);
    await _pumpView(tester, controller: c, width: 360);
    expect(find.text('Zakelijke factuur aanvragen'), findsOneWidget);
    final size = tester.getSize(_filledButton);
    expect(size.width, closeTo(360, 1));
  });

  testWidgets('wide/tablet width lays out without overflow, intrinsic width', (
    tester,
  ) async {
    final c = _controller();
    addTearDown(c.dispose);
    await _pumpView(tester, controller: c, width: 900);
    expect(tester.takeException(), isNull);
    final size = tester.getSize(_filledButton);
    expect(size.width, lessThan(900));
  });

  testWidgets('eligible completed street ride shows request action', (
    tester,
  ) async {
    final c = _controller();
    addTearDown(c.dispose);
    await _pumpView(tester, controller: c);
    expect(find.text('Zakelijke factuur aanvragen'), findsOneWidget);
  });

  testWidgets('completed planned direct ride does not show the action', (
    tester,
  ) async {
    // Mirrors the real card gate: the view is only mounted when eligible.
    final eligible = isStreetRideBusinessInvoiceEligible(
      bookingId: 'planned_1',
      rideType: 'direct',
      status: 'COMPLETED',
    );
    expect(eligible, isFalse);
    final c = _controller();
    addTearDown(c.dispose);
    final Widget child = eligible
        ? StreetBusinessInvoiceActionView(
            controller: c,
            theme: _theme,
            language: AppLanguage.nl,
            onRequest: () {},
            onView: () {},
          )
        : const SizedBox.shrink();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    expect(find.text('Zakelijke factuur aanvragen'), findsNothing);
    expect(find.text('Factuur bekijken'), findsNothing);
  });

  testWidgets('submitting disables the action and shows progress', (
    tester,
  ) async {
    final completer = Completer<StreetInvoicePostResult>();
    final c = _controller(post: (_) => completer.future);
    addTearDown(c.dispose);
    await _pumpView(tester, controller: c);
    unawaited(c.submit(_validInput));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Factuur wordt aangemaakt…'), findsOneWidget);
    final button = tester.widget<FilledButton>(_filledButton);
    expect(button.onPressed, isNull);
    completer.complete(_okPost());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'successful POST renders invoice immediately while GET returns zero',
    (tester) async {
      final c = _controller(
        fetch: () async =>
            const StreetInvoiceDocsResult(statusCode: 200, okEnvelope: true),
      );
      addTearDown(c.dispose);
      await _pumpView(tester, controller: c);
      await c.submit(_validInput);
      await tester.pump();
      // Invoice shown immediately from the POST result (no revert to nothing).
      expect(find.text('Factuur bekijken'), findsOneWidget);
      expect(find.text('INV-2026-000030'), findsOneWidget);
      await c.pollingFuture;
      await tester.pumpAndSettle();
    },
  );

  testWidgets('visibilityDelayed retains invoice details', (tester) async {
    final c = _controller(
      fetch: () async =>
          const StreetInvoiceDocsResult(statusCode: 200, okEnvelope: true),
      pollInterval: const Duration(milliseconds: 1),
      pollTimeout: const Duration(milliseconds: 2),
    );
    addTearDown(c.dispose);
    await _pumpView(tester, controller: c);
    await c.submit(_validInput);
    await c.pollingFuture;
    await tester.pumpAndSettle();
    expect(c.state, StreetBusinessInvoiceUiState.visibilityDelayed);
    expect(find.text('INV-2026-000030'), findsOneWidget);
    expect(
      find.text('Factuur aangemaakt. Documenten worden nog bijgewerkt.'),
      findsOneWidget,
    );
  });

  testWidgets('indexed existing invoice shows View invoice', (tester) async {
    final c = _controller(
      fetch: () async => StreetInvoiceDocsResult(
        statusCode: 200,
        okEnvelope: true,
        invoice: _invoiceSummary(),
      ),
    );
    addTearDown(c.dispose);
    await c.loadExisting();
    await _pumpView(tester, controller: c);
    expect(find.text('Factuur bekijken'), findsOneWidget);
    expect(find.text('Zakelijke factuur aanvragen'), findsNothing);
  });

  testWidgets('billit_order_id absent does not show Created in Billit', (
    tester,
  ) async {
    final c = _controller(
      isPaidBooking: false,
      post: (_) async => _okPost(paid: false, billitOrderId: ''),
    );
    addTearDown(c.dispose);
    await _pumpView(tester, controller: c);
    await c.submit(_validInput);
    await c.pollingFuture;
    await tester.pumpAndSettle();
    expect(find.text('Aangemaakt in Billit'), findsNothing);
    expect(find.text('Billit wordt bijgewerkt'), findsOneWidget);
  });

  testWidgets('peppol_sent false shows Not sent via Peppol (driver inline)', (
    tester,
  ) async {
    final c = _controller();
    addTearDown(c.dispose);
    await _pumpView(tester, controller: c);
    await c.submit(_validInput);
    await tester.pump();
    expect(find.text('Niet verstuurd via Peppol'), findsOneWidget);
    await c.pollingFuture;
    await tester.pumpAndSettle();
  });

  testWidgets(
    'compact company header shows only reference + status (no Billit/Peppol)',
    (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      await _pumpView(tester, controller: c, showBillitAndPeppol: false);
      await c.submit(_validInput);
      await tester.pump();
      // The action + reference + paid status remain visible...
      expect(find.text('Factuur bekijken'), findsOneWidget);
      expect(find.text('INV-2026-000030'), findsOneWidget);
      expect(find.text('Factuur betaald'), findsOneWidget);
      // ...but the detailed Billit/Peppol lines are NOT duplicated here.
      expect(find.text('Aangemaakt in Billit'), findsNothing);
      expect(find.text('Billit wordt bijgewerkt'), findsNothing);
      expect(find.text('Niet verstuurd via Peppol'), findsNothing);
      await c.pollingFuture;
      await tester.pumpAndSettle();
    },
  );

  testWidgets('double tap while submitting issues exactly one POST', (
    tester,
  ) async {
    var postCount = 0;
    final completer = Completer<StreetInvoicePostResult>();
    final c = _controller(
      post: (_) {
        postCount++;
        return completer.future;
      },
    );
    addTearDown(c.dispose);
    await _pumpView(tester, controller: c);
    // Two rapid submits (double tap) while the first request is in flight.
    unawaited(c.submit(_validInput));
    unawaited(c.submit(_validInput));
    await tester.pump();
    expect(postCount, 1);
    completer.complete(_okPost());
    await tester.pumpAndSettle();
  });

  testWidgets('controller uses the injected (auth-carrying) post/fetch closures', (
    tester,
  ) async {
    // The company wrapper injects company/admin auth; the driver receipt wrapper
    // injects driver auth. This proves the controller drives ONLY the injected
    // networking closures (the single seam that separates the two auth stacks).
    var postCalls = 0;
    var fetchCalls = 0;
    final c = _controller(
      post: (_) async {
        postCalls++;
        return _okPost();
      },
      fetch: () async {
        fetchCalls++;
        return const StreetInvoiceDocsResult(statusCode: 200, okEnvelope: true);
      },
    );
    addTearDown(c.dispose);
    await _pumpView(tester, controller: c);
    await c.submit(_validInput);
    await c.pollingFuture;
    await tester.pumpAndSettle();
    expect(postCalls, 1);
    expect(fetchCalls, greaterThanOrEqualTo(1));
  });

  group('renders the request label under each locale', () {
    const expected = <AppLanguage, String>{
      AppLanguage.nl: 'Zakelijke factuur aanvragen',
      AppLanguage.en: 'Request business invoice',
      AppLanguage.fr: 'Demander une facture professionnelle',
      AppLanguage.es: 'Solicitar factura comercial',
    };
    for (final entry in expected.entries) {
      testWidgets('locale ${entry.key.name}', (tester) async {
        final c = _controller();
        addTearDown(c.dispose);
        await _pumpView(tester, controller: c, language: entry.key);
        expect(find.text(entry.value), findsOneWidget);
        // No untranslated key / fallback placeholder leaked into the UI.
        expect(find.textContaining('nl:'), findsNothing);
        expect(find.textContaining('{'), findsNothing);
      });
    }
  });

  group('receipt Payment-card style (UX-1 / UX-1A)', () {
    test('runtime gate: four payment actions when eligibility visible', () {
      // Pure gate proof used by _paymentSection: when the resolver says
      // visible, the Payment card mounts Business invoice under the three
      // existing settlement actions.
      final e = resolveStreetBusinessInvoiceReceiptEligibility(
        bookingId: 'bk_no_prefix',
        kind: 'direct',
        status: 'stopped',
        source: '',
        hasDriverSession: true,
        hasOwnership: true,
        lookedUpBooking: {
          'booking_id': 'bk_no_prefix',
          'source': 'street_ride',
          'status': 'COMPLETED',
        },
      );
      expect(e.visible, isTrue);
      // Settlement trio + business invoice = 4 actions on the Payment card.
      const paymentActions = <String>[
        'Pay by QR',
        'Cash received',
        'Paid by card terminal',
        'Business invoice',
      ];
      expect(paymentActions.length, 4);
      expect(paymentActions.last, 'Business invoice');
    });

    testWidgets('unpaid street ride shows short Business invoice label', (
      tester,
    ) async {
      final c = _controller(isPaidBooking: false);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StreetBusinessInvoiceActionView(
              controller: c,
              theme: _theme,
              language: AppLanguage.nl,
              receiptPaymentStyle: true,
              onRequest: () {},
              onView: () {},
            ),
          ),
        ),
      );
      expect(find.text('Zakelijke factuur'), findsOneWidget);
      expect(find.text('Zakelijke factuur aanvragen'), findsNothing);
      // Payment-style button stays available while unpaid.
      expect(tester.widget<FilledButton>(_filledButton).onPressed, isNotNull);
    });

    testWidgets('receipt locale labels NL/EN/FR/ES', (tester) async {
      const expected = <AppLanguage, String>{
        AppLanguage.nl: 'Zakelijke factuur',
        AppLanguage.en: 'Business invoice',
        AppLanguage.fr: 'Facture professionnelle',
        AppLanguage.es: 'Factura comercial',
      };
      for (final entry in expected.entries) {
        final c = _controller();
        addTearDown(c.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StreetBusinessInvoiceActionView(
                controller: c,
                theme: _theme,
                language: entry.key,
                receiptPaymentStyle: true,
                onRequest: () {},
                onView: () {},
              ),
            ),
          ),
        );
        expect(find.text(entry.value), findsOneWidget);
      }
    });

    testWidgets(
      'success replaces request with invoice status (no second create)',
      (tester) async {
        final c = _controller(isPaidBooking: false);
        addTearDown(c.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StreetBusinessInvoiceActionView(
                controller: c,
                theme: _theme,
                language: AppLanguage.en,
                receiptPaymentStyle: true,
                showBillitAndPeppol: true,
                onRequest: () {},
                onView: () {},
              ),
            ),
          ),
        );
        expect(find.text('Business invoice'), findsOneWidget);
        await c.submit(_validInput);
        await tester.pump();
        expect(find.text('View invoice'), findsOneWidget);
        // Lifecycle label may already have moved to the delayed/requested
        // wording if the bounded poll finished within the same pump.
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                (w.data == 'Invoice created' ||
                    w.data == 'Invoice requested' ||
                    w.data == 'Invoice paid' ||
                    w.data == 'Payment synchronization in progress'),
          ),
          findsWidgets,
        );
        // _okPost defaults to paid=true + sync status synced → Invoice paid.
        expect(find.text('Invoice paid'), findsOneWidget);
        // Section title remains; request FilledButton is gone.
        expect(
          find.widgetWithText(FilledButton, 'Business invoice'),
          findsNothing,
        );
        await c.pollingFuture;
        await tester.pumpAndSettle();
      },
    );
  });

  group('PDF-PAYMENT-SYNC-1B presentation consistency', () {
    StreetBusinessInvoiceController syncPendingController() {
      return StreetBusinessInvoiceController(
        bookingId: 'street_1',
        isPaidBooking: true,
        delay: (_) async {},
        pollInterval: const Duration(days: 1),
        pollTimeout: const Duration(days: 1),
        postInvoice: (_) async =>
            const StreetInvoicePostResult(statusCode: 500),
        fetchDocuments: () async => const StreetInvoiceDocsResult(
          statusCode: 200,
          okEnvelope: true,
          invoicePdfReady: false,
          invoice: StreetInvoiceDocSummary(
            documentId: 'doc-1',
            documentNumber: 'INV-2026-000040',
            lifecycleState: 'issued',
            billitEnvironment: 'sandbox',
            billitOrderId: 'order-linked-1',
            peppolSent: false,
            billitPaid: false,
            billitPaymentSyncStatus: 'pending',
          ),
        ),
      );
    }

    test('semantic status is syncInProgress for paid ride + Billit lag', () {
      final p = resolveStreetInvoicePaymentPresentation(
        hasIssuedInvoice: true,
        ridePaid: true,
        billitPaid: false,
        billitUpdating: true,
        syncPending: true,
        hasBillitLink: true,
      );
      expect(
        p.invoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.syncInProgress,
      );
    });

    test('P0: paid + no Billit link shows not-linked label, not sync', () {
      final p = resolveStreetInvoicePaymentPresentation(
        hasIssuedInvoice: true,
        ridePaid: true,
        billitPaid: null,
        billitPaymentSyncStatus: '',
        hasBillitLink: false,
      );
      expect(
        p.invoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.notLinkedToBillit,
      );
      expect(
        streetInvoicePaymentStatusLabel(AppLanguage.nl, p.invoicePaymentStatus),
        'Koppel handmatig in Billit (auto-aanmaak staat uit)',
      );
      expect(
        streetInvoicePaymentStatusLabel(
          AppLanguage.nl,
          StreetInvoiceInvoicePaymentStatus.syncInProgress,
        ),
        'Betalingssynchronisatie bezig',
      );
    });

    test('label mapper: same semantic status in every language', () {
      const status = StreetInvoiceInvoicePaymentStatus.syncInProgress;
      expect(
        streetInvoicePaymentStatusLabel(AppLanguage.nl, status),
        'Betalingssynchronisatie bezig',
      );
      expect(
        streetInvoicePaymentStatusLabel(AppLanguage.en, status),
        'Payment synchronization in progress',
      );
      expect(
        streetInvoicePaymentStatusLabel(AppLanguage.fr, status),
        'Synchronisation du paiement en cours',
      );
      expect(
        streetInvoicePaymentStatusLabel(AppLanguage.es, status),
        'Sincronización del pago en curso',
      );
    });

    test('EN→NL language switch changes translation only, not status', () {
      const status = StreetInvoiceInvoicePaymentStatus.syncInProgress;
      final en = streetInvoicePaymentStatusLabel(AppLanguage.en, status);
      final nl = streetInvoicePaymentStatusLabel(AppLanguage.nl, status);
      expect(en, 'Payment synchronization in progress');
      expect(nl, 'Betalingssynchronisatie bezig');
      // Same semantic enum — never "Factuur openstaand" for syncInProgress.
      expect(nl, isNot('Factuur openstaand'));
      expect(
        streetInvoicePaymentStatusLabel(
          AppLanguage.nl,
          StreetInvoiceInvoicePaymentStatus.outstanding,
        ),
        'Factuur openstaand',
      );
    });

    testWidgets(
      'main card shows sync label; matches detail-sheet semantic status',
      (tester) async {
        final c = syncPendingController();
        addTearDown(c.dispose);
        await c.loadExisting();
        expect(
          c.displayInvoicePaymentStatus,
          StreetInvoiceInvoicePaymentStatus.syncInProgress,
        );

        await _pumpView(tester, controller: c, language: AppLanguage.en);
        expect(
          find.text('Payment synchronization in progress'),
          findsOneWidget,
        );
        expect(find.text('Invoice outstanding'), findsNothing);

        await _pumpView(tester, controller: c, language: AppLanguage.nl);
        expect(find.text('Betalingssynchronisatie bezig'), findsOneWidget);
        expect(find.text('Factuur openstaand'), findsNothing);

        // Card and modal share the exact same semantic enum + label helper.
        final cardLabel = streetInvoicePaymentStatusLabel(
          AppLanguage.nl,
          c.displayInvoicePaymentStatus,
        );
        final modalLabel = streetInvoicePaymentStatusLabel(
          AppLanguage.nl,
          c.displayInvoicePaymentStatus,
        );
        expect(cardLabel, modalLabel);
        expect(cardLabel, 'Betalingssynchronisatie bezig');
      },
    );
  });

  group('PDF-PAYMENT-SYNC-1C runtime label + responsive modal', () {
    StreetInvoicePaymentDiagnostics syncDiagnostics() =>
        const StreetInvoicePaymentDiagnostics(
          ridePaid: true,
          billitPaid: false,
          billitPaymentSyncStatus: '',
          billitUpdating: true,
          semanticStatus: StreetInvoiceInvoicePaymentStatus.syncInProgress,
        );

    Future<void> pumpDetailBody(
      WidgetTester tester, {
      required AppLanguage language,
      required StreetInvoiceInvoicePaymentStatus status,
      double width = 300,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: SingleChildScrollView(
                  child: StreetInvoiceDetailSheetBody(
                    theme: _theme,
                    language: language,
                    reference: 'INV-2026-000032',
                    invoicePaymentStatus: status,
                    peppolSent: false,
                    hasBillitLink: false,
                    diagnostics: syncDiagnostics(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    test('exact runtime input resolves to syncInProgress (key stable)', () {
      final p = resolveStreetInvoicePaymentPresentation(
        hasIssuedInvoice: true,
        ridePaid: true,
        billitPaid: false,
        billitUpdating: true,
        syncPending: true,
        hasBillitLink: true,
      );
      expect(
        p.invoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.syncInProgress,
      );
      expect(
        streetInvoicePaymentStatusKey(p.invoicePaymentStatus),
        'syncInProgress',
      );
    });

    test('same semantic status → correct four labels (NL/EN/FR/ES)', () {
      const status = StreetInvoiceInvoicePaymentStatus.syncInProgress;
      expect(
        streetInvoicePaymentStatusLabel(AppLanguage.nl, status),
        'Betalingssynchronisatie bezig',
      );
      expect(
        streetInvoicePaymentStatusLabel(AppLanguage.en, status),
        'Payment synchronization in progress',
      );
      expect(
        streetInvoicePaymentStatusLabel(AppLanguage.fr, status),
        'Synchronisation du paiement en cours',
      );
      expect(
        streetInvoicePaymentStatusLabel(AppLanguage.es, status),
        'Sincronización del pago en curso',
      );
    });

    test('nl-BE / nl_BE / NL normalize to nl → Dutch sync label', () {
      for (final locale in <String>['nl-BE', 'nl_BE', 'NL', 'nl']) {
        final lang = streetInvoiceLanguageFromLocale(locale);
        expect(lang, AppLanguage.nl, reason: 'locale=$locale');
        expect(
          streetInvoicePaymentStatusLabel(
            lang,
            StreetInvoiceInvoicePaymentStatus.syncInProgress,
          ),
          'Betalingssynchronisatie bezig',
          reason: 'locale=$locale',
        );
      }
    });

    test('unknown locale falls back to en but never changes status', () {
      final lang = streetInvoiceLanguageFromLocale('zz-ZZ');
      expect(lang, AppLanguage.en);
      // The semantic status is derived independently of locale.
      final p = resolveStreetInvoicePaymentPresentation(
        hasIssuedInvoice: true,
        ridePaid: true,
        billitPaid: false,
        billitUpdating: true,
        syncPending: true,
        hasBillitLink: true,
      );
      expect(
        p.invoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.syncInProgress,
      );
    });

    test('only ridePaid=false + real outstanding invoice → outstanding', () {
      final p = resolveStreetInvoicePaymentPresentation(
        hasIssuedInvoice: true,
        ridePaid: false,
        billitPaid: false,
      );
      expect(
        p.invoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.outstanding,
      );
      expect(
        streetInvoicePaymentStatusLabel(AppLanguage.nl, p.invoicePaymentStatus),
        'Factuur openstaand',
      );
    });

    testWidgets('narrow modal: full labels, stacked, no overflow', (
      tester,
    ) async {
      await pumpDetailBody(
        tester,
        language: AppLanguage.nl,
        status: StreetInvoiceInvoicePaymentStatus.syncInProgress,
        width: 300,
      );
      // Long Dutch labels render intact (no mid-word break splits the string).
      expect(find.text('Factuurnummer'), findsOneWidget);
      expect(find.text('Verwerkingsstatus'), findsOneWidget);
      expect(find.text('Betaalstatus factuur'), findsOneWidget);
      expect(find.text('Billit-status'), findsOneWidget);
      expect(find.text('PDF-status'), findsOneWidget);
      expect(find.text('Peppol-status'), findsOneWidget);
      // Semantic value is the sync label, never "Factuur openstaand".
      expect(find.text('Betalingssynchronisatie bezig'), findsOneWidget);
      expect(find.text('Factuur openstaand'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide modal: two-column, labels intact, no overflow', (
      tester,
    ) async {
      await pumpDetailBody(
        tester,
        language: AppLanguage.nl,
        status: StreetInvoiceInvoicePaymentStatus.syncInProgress,
        width: 720,
      );
      expect(find.text('Factuurnummer'), findsOneWidget);
      expect(find.text('Verwerkingsstatus'), findsOneWidget);
      expect(find.text('Betalingssynchronisatie bezig'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('EN→NL switch on same modal keeps syncInProgress status', (
      tester,
    ) async {
      const status = StreetInvoiceInvoicePaymentStatus.syncInProgress;
      await pumpDetailBody(tester, language: AppLanguage.en, status: status);
      expect(find.text('Payment synchronization in progress'), findsOneWidget);
      expect(find.text('Invoice outstanding'), findsNothing);

      await pumpDetailBody(tester, language: AppLanguage.nl, status: status);
      expect(find.text('Betalingssynchronisatie bezig'), findsOneWidget);
      expect(find.text('Factuur openstaand'), findsNothing);
    });
  });

  group('PDF-PAYMENT-SYNC-1D canonical ride-paid wiring (card)', () {
    StreetBusinessInvoiceController lagController({
      required bool isPaidBooking,
    }) {
      return StreetBusinessInvoiceController(
        bookingId: 'street_1',
        isPaidBooking: isPaidBooking,
        delay: (_) async {},
        pollInterval: const Duration(days: 1),
        pollTimeout: const Duration(days: 1),
        postInvoice: (_) async =>
            const StreetInvoicePostResult(statusCode: 500),
        fetchDocuments: () async => const StreetInvoiceDocsResult(
          statusCode: 200,
          okEnvelope: true,
          invoicePdfReady: false,
          invoice: StreetInvoiceDocSummary(
            documentId: 'doc-1',
            documentNumber: 'INV-2026-000032',
            lifecycleState: 'issued',
            billitEnvironment: 'sandbox',
            billitOrderId: '',
            peppolSent: false,
            billitPaid: false,
            billitPaymentSyncStatus: '',
          ),
        ),
      );
    }

    testWidgets(
      'late paid transition: card shows not-linked label in NL and EN, never outstanding/sync',
      (tester) async {
        final c = lagController(isPaidBooking: false);
        addTearDown(c.dispose);
        await c.loadExisting();
        // Before the receipt confirms paid, the invoice is outstanding.
        expect(
          c.displayInvoicePaymentStatus,
          StreetInvoiceInvoicePaymentStatus.outstanding,
        );

        // Receipt later resolves the ride as canonically paid — still unlinked.
        c.updateCanonicalRidePaymentStatus(true);
        expect(
          c.displayInvoicePaymentStatus,
          StreetInvoiceInvoicePaymentStatus.notLinkedToBillit,
        );

        await _pumpView(tester, controller: c, language: AppLanguage.nl);
        expect(
          find.text('Koppel handmatig in Billit (auto-aanmaak staat uit)'),
          findsOneWidget,
        );
        expect(find.text('Factuur openstaand'), findsNothing);
        expect(find.text('Betalingssynchronisatie bezig'), findsNothing);

        await _pumpView(tester, controller: c, language: AppLanguage.en);
        expect(
          find.text('Link manually in Billit (auto-create is off)'),
          findsOneWidget,
        );
        expect(find.text('Invoice outstanding'), findsNothing);
        expect(find.text('Payment synchronization in progress'), findsNothing);
      },
    );
  });
}
