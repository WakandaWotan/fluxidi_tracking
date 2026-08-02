import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/street_business_invoice_support.dart';

void main() {
  group('eligibility', () {
    test('completed street ride by id prefix is eligible (case 1/3)', () {
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'street_123_abc',
          status: 'COMPLETED',
        ),
        isTrue,
      );
    });

    test('completed street ride by source/booking_source is eligible', () {
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'bk_1',
          source: 'street_ride',
          status: 'COMPLETED',
        ),
        isTrue,
      );
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'bk_1',
          bookingSource: 'street_ride',
          status: 'completed',
        ),
        isTrue,
      );
    });

    test('ride_type==direct is NEVER sufficient on its own (UI-1B)', () {
      // completed planned booking with ride_type=direct
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'planned_booking_1',
          rideType: 'direct',
          status: 'COMPLETED',
        ),
        isFalse,
      );
      // completed customer booking with ride_type=direct
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'bk_customer_9',
          source: 'customer',
          rideType: 'direct',
          status: 'COMPLETED',
        ),
        isFalse,
      );
      // arbitrary completed non-street booking with ride_type=direct
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'xyz_123',
          rideType: 'direct',
          status: 'COMPLETED',
        ),
        isFalse,
      );
    });

    test('canonical street ride excludes cancelled/refunded/credited', () {
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'street_1',
          status: 'COMPLETED',
          isCancelled: true,
        ),
        isFalse,
      );
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'street_1',
          status: 'COMPLETED',
          isRefunded: true,
        ),
        isFalse,
      );
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'street_1',
          status: 'COMPLETED',
          isCredited: true,
        ),
        isFalse,
      );
      expect(hasCanonicalStreetIdentity(bookingId: 'bk_1'), isFalse);
      expect(hasCanonicalStreetIdentity(bookingId: 'street_abc'), isTrue);
    });

    test('paid and unpaid completed street rides are both eligible (case 3)', () {
      // Eligibility does not depend on payment; both flow through the same gate.
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'street_paid',
          status: 'COMPLETED',
        ),
        isTrue,
      );
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'street_unpaid',
          status: 'COMPLETED',
        ),
        isTrue,
      );
    });

    test('non-street or incomplete booking is not eligible (case 2)', () {
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'bk_customer_1',
          status: 'COMPLETED',
        ),
        isFalse,
      );
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'street_123',
          status: 'IN_PROGRESS',
        ),
        isFalse,
      );
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'street_123',
          status: 'CANCELLED',
        ),
        isFalse,
      );
    });
  });

  group('responsive layout (cases 4/5)', () {
    test('narrow phone width stacks full-width (case 4)', () {
      expect(streetInvoiceActionIsNarrowLayout(360), isTrue);
      expect(streetInvoiceActionIsNarrowLayout(599.9), isTrue);
    });

    test('wide/tablet width renders side-by-side (case 5)', () {
      expect(streetInvoiceActionIsNarrowLayout(600), isFalse);
      expect(streetInvoiceActionIsNarrowLayout(1024), isFalse);
    });
  });

  group('payload building (case 6)', () {
    test('builds exact billing_customer payload and omits empties', () {
      const input = StreetBusinessInvoiceBuyerInput(
        legalName: 'Fluxidi Sandbox Test Buyer',
        street: 'Teststraat 1',
        postalCode: '1000',
        city: 'Brussel',
        country: 'be',
        contactEmail: 'sandbox-buyer@fluxidi.test',
        buyerReference: 'SANDBOX-PROOF-A1',
      );
      final body = input.toRequestBody();
      expect(body.keys, ['billing_customer']);
      final billing = body['billing_customer'] as Map<String, dynamic>;
      expect(billing['customer_type'], 'business');
      expect(billing['legal_name'], 'Fluxidi Sandbox Test Buyer');
      expect(billing['contact_email'], 'sandbox-buyer@fluxidi.test');
      expect(billing['buyer_reference'], 'SANDBOX-PROOF-A1');
      // Omitted optionals are absent, never empty strings.
      expect(billing.containsKey('vat_number'), isFalse);
      expect(billing.containsKey('company_registration_number'), isFalse);
      final addr = billing['billing_address'] as Map<String, dynamic>;
      expect(addr['street'], 'Teststraat 1');
      expect(addr['postal_code'], '1000');
      expect(addr['city'], 'Brussel');
      expect(addr['country'], 'BE'); // upper-cased
    });
  });

  group('form validation', () {
    test('requires legal name and full address', () {
      const empty = StreetBusinessInvoiceBuyerInput(country: 'BE');
      final v = validateStreetBusinessInvoiceForm(empty);
      expect(v.isValid, isFalse);
      expect(v.legalNameMissing, isTrue);
      expect(v.streetMissing, isTrue);
      expect(v.countryMissing, isFalse);
    });

    test('valid when required fields present', () {
      const input = StreetBusinessInvoiceBuyerInput(
        legalName: 'ACME BV',
        street: 'Straat 1',
        postalCode: '1000',
        city: 'Brussel',
        country: 'BE',
      );
      expect(validateStreetBusinessInvoiceForm(input).isValid, isTrue);
    });
  });

  group('response parsing (cases 12/14)', () {
    test('parses reused response and peppol_sent false', () {
      final resp = parseStreetBusinessInvoiceResponse({
        'ok': true,
        'booking_id': 'street_1',
        'document_id': 'doc-1',
        'invoice_reference': 'INV-2026-000030',
        'reused': true,
        'payment_status': 'paid',
        'billit_environment': 'sandbox',
        'billit_order_id': '2954728',
        'peppol_sent': false,
        'warnings': <String>[],
      });
      expect(resp, isNotNull);
      expect(resp!.reused, isTrue);
      expect(resp.isPaid, isTrue);
      expect(resp.peppolSent, isFalse);
      expect(resp.invoiceReference, 'INV-2026-000030');
      expect(resp.billitOrderId, '2954728');
    });

    test('unpaid response reports unpaid', () {
      final resp = parseStreetBusinessInvoiceResponse({
        'ok': true,
        'document_id': 'doc-2',
        'invoice_reference': 'INV-2026-000031',
        'payment_status': 'unpaid',
        'peppol_sent': false,
      });
      expect(resp!.isPaid, isFalse);
      expect(resp.peppolSent, isFalse);
    });
  });

  group('error classification (case 13)', () {
    test('maps status codes and tokens', () {
      expect(
        classifyStreetBusinessInvoiceError(statusCode: 409),
        StreetBusinessInvoiceErrorKind.identityConflict,
      );
      expect(
        classifyStreetBusinessInvoiceError(
          errorToken: 'billing_identity_conflict',
        ),
        StreetBusinessInvoiceErrorKind.identityConflict,
      );
      expect(
        classifyStreetBusinessInvoiceError(statusCode: 403),
        StreetBusinessInvoiceErrorKind.accessDenied,
      );
      expect(
        classifyStreetBusinessInvoiceError(errorToken: 'not_in_scope'),
        StreetBusinessInvoiceErrorKind.accessDenied,
      );
      expect(
        classifyStreetBusinessInvoiceError(statusCode: 422),
        StreetBusinessInvoiceErrorKind.readiness,
      );
      expect(
        classifyStreetBusinessInvoiceError(statusCode: null),
        StreetBusinessInvoiceErrorKind.network,
      );
    });

    test('driver-auth tokens map before generic status codes', () {
      // driver_not_assigned is a 403, but must NOT read as generic accessDenied.
      expect(
        classifyStreetBusinessInvoiceError(
          statusCode: 403,
          errorToken: 'driver_not_assigned',
        ),
        StreetBusinessInvoiceErrorKind.driverNotAuthorized,
      );
      expect(
        classifyStreetBusinessInvoiceError(
          errorToken: 'driver_session_required',
        ),
        StreetBusinessInvoiceErrorKind.driverNotAuthorized,
      );
      // not_a_street_booking is a 422, but must NOT read as billing readiness.
      expect(
        classifyStreetBusinessInvoiceError(
          statusCode: 422,
          errorToken: 'not_a_street_booking',
        ),
        StreetBusinessInvoiceErrorKind.notCompletedStreet,
      );
      expect(
        classifyStreetBusinessInvoiceError(errorToken: 'booking_not_completed'),
        StreetBusinessInvoiceErrorKind.notCompletedStreet,
      );
      expect(
        classifyStreetBusinessInvoiceError(errorToken: 'forbidden'),
        StreetBusinessInvoiceErrorKind.accessDenied,
      );
    });
  });

  group('driver eligibility (both paid and unpaid street rides qualify)', () {
    test('canonical street via source qualifies when completed', () {
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'abc',
          source: 'street_ride',
          bookingSource: 'street_ride',
          rideType: 'direct',
          status: 'COMPLETED',
        ),
        isTrue,
      );
    });

    test('street_ id prefix qualifies (paid or unpaid) when completed', () {
      for (final _ in const [true, false]) {
        expect(
          isStreetRideBusinessInvoiceEligible(
            bookingId: 'street_1720000000000_abcd',
            status: 'COMPLETED',
          ),
          isTrue,
        );
      }
    });

    test('direct ride_type alone never qualifies', () {
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'planned_1',
          rideType: 'direct',
          status: 'COMPLETED',
        ),
        isFalse,
      );
    });

    test('incomplete / reversed street rides never qualify', () {
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'street_1',
          status: 'IN_PROGRESS',
        ),
        isFalse,
      );
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'street_1',
          status: 'COMPLETED',
          isCancelled: true,
        ),
        isFalse,
      );
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'street_1',
          status: 'COMPLETED',
          isRefunded: true,
        ),
        isFalse,
      );
    });
  });

  group('documents parsing (cases 8/9/11)', () {
    Map<String, dynamic> docsEnvelope(List<Map<String, dynamic>> docs) => {
      'ok': true,
      'source_booking_id': 'street_1',
      'documents': docs,
      'count': docs.length,
    };

    test(
      'extracts invoice, honours expected id, counts case-insensitively',
      () {
        final decoded = docsEnvelope([
          {
            'document_id': 'doc-a',
            'document_type': 'Invoice',
            'document_number': 'INV-1',
            'lifecycle_state': 'issued',
            'billit_export': {
              'environment': 'sandbox',
              'order_id': '111',
              'peppol_sent': false,
              'billit_paid': true,
            },
          },
        ]);
        expect(countInvoiceDocuments(decoded), 1);
        final inv = extractInvoiceFromDocuments(
          decoded,
          expectedDocumentId: 'doc-a',
        );
        expect(inv, isNotNull);
        expect(inv!.documentNumber, 'INV-1');
        expect(inv.billitOrderId, '111');
        expect(inv.peppolSent, isFalse);
        expect(inv.billitPaid, isTrue);
      },
    );

    test('failed/empty envelope yields null invoice, not a false zero', () {
      expect(extractInvoiceFromDocuments({'ok': false}), isNull);
      expect(documentsEnvelopeOk({'ok': false}), isFalse);
      expect(extractInvoiceFromDocuments(docsEnvelope(const [])), isNull);
    });
  });

  group('derived document count (section 2)', () {
    test('indexed count 0 + successful POST invoice => displayed >= 1', () {
      expect(
        deriveDisplayedDocumentCount(
          backendVisibleCount: 0,
          hasLocalIssuedInvoice: true,
          localInvoiceInBackend: false,
        ),
        1,
      );
    });

    test('subsequent GET count 0 must not revert displayed count to 0', () {
      // Same inputs on a later poll still yield >= 1.
      expect(
        deriveDisplayedDocumentCount(
          backendVisibleCount: 0,
          hasLocalIssuedInvoice: true,
          localInvoiceInBackend: false,
        ),
        1,
      );
    });

    test('subsequent GET finds same invoice => still exactly one, not two', () {
      expect(
        deriveDisplayedDocumentCount(
          backendVisibleCount: 1,
          hasLocalIssuedInvoice: true,
          localInvoiceInBackend: true,
        ),
        1,
      );
    });

    test('reopening with indexed invoice => exactly one', () {
      expect(
        deriveDisplayedDocumentCount(
          backendVisibleCount: 1,
          hasLocalIssuedInvoice: false,
          localInvoiceInBackend: false,
        ),
        1,
      );
    });
  });

  group('honest billit status (section 3)', () {
    test('billit_order_id present => hasBillitLink true', () async {
      final c = StreetBusinessInvoiceController(
        bookingId: 'street_1',
        isPaidBooking: true,
        delay: (_) async {},
        pollInterval: const Duration(milliseconds: 1),
        pollTimeout: const Duration(milliseconds: 1),
        postInvoice: (_) async => StreetInvoicePostResult(
          statusCode: 200,
          response: const StreetBusinessInvoiceResponse(
            ok: true,
            bookingId: 'street_1',
            documentId: 'doc-1',
            invoiceReference: 'INV-1',
            reused: false,
            paymentStatus: 'paid',
            billitEnvironment: 'sandbox',
            billitOrderId: '2954728',
            billitOrderReused: false,
            billitPaymentSyncStatus: 'synced',
            peppolSent: false,
            warnings: <String>[],
            paymentReconciliation: '',
          ),
        ),
        fetchDocuments: () async =>
            const StreetInvoiceDocsResult(statusCode: 200, okEnvelope: true),
      );
      await c.submit(
        const StreetBusinessInvoiceBuyerInput(
          legalName: 'ACME',
          street: 'S 1',
          postalCode: '1000',
          city: 'Brussel',
          country: 'BE',
        ),
      );
      expect(c.hasBillitLink, isTrue);
      expect(c.displayBillitOrderId, '2954728');
      await c.pollingFuture;
      c.dispose();
    });

    test('empty billit_order_id => hasBillitLink false', () async {
      final c = StreetBusinessInvoiceController(
        bookingId: 'street_1',
        isPaidBooking: false,
        delay: (_) async {},
        pollInterval: const Duration(milliseconds: 1),
        pollTimeout: const Duration(milliseconds: 1),
        postInvoice: (_) async => StreetInvoicePostResult(
          statusCode: 200,
          response: const StreetBusinessInvoiceResponse(
            ok: true,
            bookingId: 'street_1',
            documentId: 'doc-1',
            invoiceReference: 'INV-1',
            reused: false,
            paymentStatus: 'unpaid',
            billitEnvironment: 'sandbox',
            billitOrderId: '',
            billitOrderReused: false,
            billitPaymentSyncStatus: '',
            peppolSent: false,
            warnings: <String>[],
            paymentReconciliation: 'pending_external_payment',
          ),
        ),
        fetchDocuments: () async =>
            const StreetInvoiceDocsResult(statusCode: 200, okEnvelope: true),
      );
      await c.submit(
        const StreetBusinessInvoiceBuyerInput(
          legalName: 'ACME',
          street: 'S 1',
          postalCode: '1000',
          city: 'Brussel',
          country: 'BE',
        ),
      );
      expect(c.hasBillitLink, isFalse);
      expect(c.displayBillitOrderId, isEmpty);
      await c.pollingFuture;
      c.dispose();
    });
  });

  group('controller lifecycle', () {
    StreetInvoicePostResult okPost({bool reused = false, bool paid = true}) =>
        StreetInvoicePostResult(
          statusCode: 200,
          response: StreetBusinessInvoiceResponse(
            ok: true,
            bookingId: 'street_1',
            documentId: 'doc-1',
            invoiceReference: 'INV-2026-000030',
            reused: reused,
            paymentStatus: paid ? 'paid' : 'unpaid',
            billitEnvironment: 'sandbox',
            billitOrderId: '2954728',
            billitOrderReused: false,
            billitPaymentSyncStatus: paid ? 'synced' : '',
            peppolSent: false,
            warnings: const [],
            paymentReconciliation: paid ? '' : 'pending_external_payment',
          ),
        );

    StreetInvoiceDocSummary invoiceSummary() => const StreetInvoiceDocSummary(
      documentId: 'doc-1',
      documentNumber: 'INV-2026-000030',
      lifecycleState: 'issued',
      billitEnvironment: 'sandbox',
      billitOrderId: '2954728',
      peppolSent: false,
      billitPaid: true,
    );

    test('double tap produces exactly one POST (case 7)', () async {
      var postCount = 0;
      final c = StreetBusinessInvoiceController(
        bookingId: 'street_1',
        isPaidBooking: true,
        delay: (_) async {},
        pollInterval: const Duration(milliseconds: 1),
        pollTimeout: const Duration(milliseconds: 1),
        postInvoice: (_) async {
          postCount++;
          return okPost();
        },
        fetchDocuments: () async =>
            const StreetInvoiceDocsResult(statusCode: 200, okEnvelope: true),
      );
      const input = StreetBusinessInvoiceBuyerInput(
        legalName: 'ACME',
        street: 'S 1',
        postalCode: '1000',
        city: 'Brussel',
        country: 'BE',
      );
      final f1 = c.submit(input);
      final f2 = c.submit(input); // second tap while first in-flight
      await Future.wait([f1, f2]);
      await c.pollingFuture;
      expect(postCount, 1);
      c.dispose();
    });

    test(
      'POST success while documents GET returns zero keeps invoice, no revert '
      '(case 8)',
      () async {
        final c = StreetBusinessInvoiceController(
          bookingId: 'street_1',
          isPaidBooking: true,
          delay: (_) async {},
          pollInterval: const Duration(milliseconds: 1),
          pollTimeout: const Duration(milliseconds: 2), // 2 attempts, all empty
          postInvoice: (_) async => okPost(),
          fetchDocuments: () async =>
              const StreetInvoiceDocsResult(statusCode: 200, okEnvelope: true),
        );
        await c.submit(
          const StreetBusinessInvoiceBuyerInput(
            legalName: 'ACME',
            street: 'S 1',
            postalCode: '1000',
            city: 'Brussel',
            country: 'BE',
          ),
        );
        // Immediately after POST: trusted-from-response, invoice retained.
        expect(c.state, StreetBusinessInvoiceUiState.issuedFromResponse);
        expect(c.hasIssuedInvoice, isTrue);
        expect(c.displayInvoiceReference, 'INV-2026-000030');
        await c.pollingFuture;
        // Index never exposed it -> visibilityDelayed, still retaining success.
        expect(c.state, StreetBusinessInvoiceUiState.visibilityDelayed);
        expect(c.hasIssuedInvoice, isTrue);
        c.dispose();
      },
    );

    test('poll eventually finds invoice -> issuedIndexed (case 9)', () async {
      var calls = 0;
      final c = StreetBusinessInvoiceController(
        bookingId: 'street_1',
        isPaidBooking: true,
        delay: (_) async {},
        pollInterval: const Duration(milliseconds: 1),
        pollTimeout: const Duration(milliseconds: 20),
        postInvoice: (_) async => okPost(),
        fetchDocuments: () async {
          calls++;
          if (calls >= 2) {
            return StreetInvoiceDocsResult(
              statusCode: 200,
              okEnvelope: true,
              invoice: invoiceSummary(),
            );
          }
          return const StreetInvoiceDocsResult(
            statusCode: 200,
            okEnvelope: true,
          );
        },
      );
      await c.submit(
        const StreetBusinessInvoiceBuyerInput(
          legalName: 'ACME',
          street: 'S 1',
          postalCode: '1000',
          city: 'Brussel',
          country: 'BE',
        ),
      );
      await c.pollingFuture;
      expect(c.state, StreetBusinessInvoiceUiState.issuedIndexed);
      expect(c.indexedInvoice, isNotNull);
      c.dispose();
    });

    test('existing invoice on load -> issuedIndexed (case 11)', () async {
      final c = StreetBusinessInvoiceController(
        bookingId: 'street_1',
        isPaidBooking: true,
        delay: (_) async {},
        postInvoice: (_) async => okPost(),
        fetchDocuments: () async => StreetInvoiceDocsResult(
          statusCode: 200,
          okEnvelope: true,
          invoice: invoiceSummary(),
        ),
      );
      await c.loadExisting();
      expect(c.state, StreetBusinessInvoiceUiState.issuedIndexed);
      expect(c.displayInvoiceReference, 'INV-2026-000030');
      c.dispose();
    });

    test('reused=true response displays the same invoice (case 12)', () async {
      final c = StreetBusinessInvoiceController(
        bookingId: 'street_1',
        isPaidBooking: true,
        delay: (_) async {},
        pollInterval: const Duration(milliseconds: 1),
        pollTimeout: const Duration(milliseconds: 1),
        postInvoice: (_) async => okPost(reused: true),
        fetchDocuments: () async =>
            const StreetInvoiceDocsResult(statusCode: 200, okEnvelope: true),
      );
      await c.submit(
        const StreetBusinessInvoiceBuyerInput(
          legalName: 'ACME',
          street: 'S 1',
          postalCode: '1000',
          city: 'Brussel',
          country: 'BE',
        ),
      );
      expect(c.issuedResponse!.reused, isTrue);
      expect(c.displayDocumentId, 'doc-1');
      await c.pollingFuture;
      c.dispose();
    });

    test('409 conflict -> error identityConflict (case 13)', () async {
      final c = StreetBusinessInvoiceController(
        bookingId: 'street_1',
        isPaidBooking: true,
        delay: (_) async {},
        postInvoice: (_) async => const StreetInvoicePostResult(
          statusCode: 409,
          errorToken: 'billing_identity_conflict',
        ),
        fetchDocuments: () async =>
            const StreetInvoiceDocsResult(statusCode: 200, okEnvelope: true),
      );
      await c.submit(
        const StreetBusinessInvoiceBuyerInput(
          legalName: 'ACME',
          street: 'S 1',
          postalCode: '1000',
          city: 'Brussel',
          country: 'BE',
        ),
      );
      expect(c.state, StreetBusinessInvoiceUiState.error);
      expect(c.errorKind, StreetBusinessInvoiceErrorKind.identityConflict);
      c.dispose();
    });

    test(
      'visibility polling issues only GET, never a second POST (case 15)',
      () async {
        var postCount = 0;
        var getCount = 0;
        final c = StreetBusinessInvoiceController(
          bookingId: 'street_1',
          isPaidBooking: false,
          delay: (_) async {},
          pollInterval: const Duration(milliseconds: 1),
          pollTimeout: const Duration(milliseconds: 5),
          postInvoice: (_) async {
            postCount++;
            return okPost(paid: false);
          },
          fetchDocuments: () async {
            getCount++;
            return const StreetInvoiceDocsResult(
              statusCode: 200,
              okEnvelope: true,
            );
          },
        );
        await c.submit(
          const StreetBusinessInvoiceBuyerInput(
            legalName: 'ACME',
            street: 'S 1',
            postalCode: '1000',
            city: 'Brussel',
            country: 'BE',
          ),
        );
        await c.pollingFuture;
        expect(postCount, 1);
        expect(getCount, greaterThan(0));
        expect(c.displayIsPaid, isFalse);
        expect(c.displayPeppolSent, isFalse); // Peppol false surfaced (case 14)
        c.dispose();
      },
    );

    test(
      'network error then retry re-checks documents before second create',
      () async {
        var postCount = 0;
        var getCount = 0;
        final c = StreetBusinessInvoiceController(
          bookingId: 'street_1',
          isPaidBooking: false,
          delay: (_) async {},
          pollInterval: const Duration(milliseconds: 1),
          pollTimeout: const Duration(milliseconds: 1),
          postInvoice: (_) async {
            postCount++;
            if (postCount == 1) {
              return const StreetInvoicePostResult(statusCode: null);
            }
            return okPost(paid: false);
          },
          fetchDocuments: () async {
            getCount++;
            // After the ambiguous network failure, the invoice is already on
            // the server — retry must surface it without a second POST.
            if (postCount >= 1 && getCount >= 2) {
              return StreetInvoiceDocsResult(
                statusCode: 200,
                okEnvelope: true,
                invoice: invoiceSummary(),
              );
            }
            return const StreetInvoiceDocsResult(
              statusCode: 200,
              okEnvelope: true,
            );
          },
        );
        const input = StreetBusinessInvoiceBuyerInput(
          legalName: 'ACME',
          street: 'S 1',
          postalCode: '1000',
          city: 'Brussel',
          country: 'BE',
        );
        await c.submit(input);
        expect(c.state, StreetBusinessInvoiceUiState.error);
        expect(c.errorKind, StreetBusinessInvoiceErrorKind.network);
        expect(postCount, 1);
        await c.submit(input); // retry
        expect(postCount, 1); // no second create
        expect(c.hasIssuedInvoice, isTrue);
        expect(c.state, StreetBusinessInvoiceUiState.issuedIndexed);
        c.dispose();
      },
    );
  });

  group('receipt UX-1A runtime gate resolver', () {
    test(
      'history row without source/street_ prefix but kind=direct needs lookup',
      () {
        final e = resolveStreetBusinessInvoiceReceiptEligibility(
          bookingId: 'bk_linked_1',
          tripId: 'trip_1',
          kind: 'direct',
          status: 'stopped',
          source: '',
          bookingSource: '',
          hasDriverSession: true,
          hasOwnership: true,
        );
        expect(e.isStreetRide, isTrue);
        expect(e.isCompleted, isTrue);
        expect(e.needsBookingLookup, isTrue);
        expect(e.eligible, isFalse);
        expect(e.reason, 'needs_booking_lookup');
      },
    );

    test(
      'lookup confirming street_ride makes Business invoice eligible',
      () {
        final e = resolveStreetBusinessInvoiceReceiptEligibility(
          bookingId: 'bk_linked_1',
          tripId: 'trip_1',
          kind: 'direct',
          status: 'stopped',
          source: '',
          bookingSource: '',
          hasDriverSession: true,
          hasOwnership: true,
          lookedUpBooking: {
            'ok': true,
            'booking_id': 'bk_linked_1',
            'source': 'street_ride',
            'booking_source': 'street_ride',
            'ride_type': 'direct',
            'status': 'COMPLETED',
          },
        );
        expect(e.eligible, isTrue);
        expect(e.needsBookingLookup, isFalse);
        expect(e.canonicalBookingId, 'bk_linked_1');
        expect(e.reason, 'eligible_driver');
        expect(e.authMode, StreetBusinessInvoiceAuthMode.driver);
      },
    );

    test('direct local street_ booking id is eligible without source', () {
      final e = resolveStreetBusinessInvoiceReceiptEligibility(
        bookingId: 'street_1720000000000_abcd',
        kind: 'direct',
        status: 'STOPPED',
        source: '',
        bookingSource: '',
        hasDriverSession: true,
        hasOwnership: true,
      );
      expect(e.eligible, isTrue);
      expect(e.needsBookingLookup, isFalse);
    });

    test('planned non-street ride stays hidden', () {
      final e = resolveStreetBusinessInvoiceReceiptEligibility(
        bookingId: 'planned_1',
        kind: 'planned',
        status: 'COMPLETED',
        source: 'customer',
        hasDriverSession: true,
        hasOwnership: true,
      );
      expect(e.eligible, isFalse);
      expect(e.visible, isFalse);
    });

    test('unpaid completed street ride remains eligible', () {
      final e = resolveStreetBusinessInvoiceReceiptEligibility(
        bookingId: 'street_unpaid_1',
        kind: 'direct',
        status: 'completed',
        source: 'street_ride',
        hasDriverSession: true,
        hasOwnership: true,
      );
      expect(e.eligible, isTrue);
    });

    test('no authorized actor hides action', () {
      final e = resolveStreetBusinessInvoiceReceiptEligibility(
        bookingId: 'street_1',
        kind: 'direct',
        status: 'COMPLETED',
        hasDriverSession: false,
        hasCompanyAdminContext: false,
        hasOwnership: true,
      );
      expect(e.eligible, isFalse);
      expect(e.reason, 'no_authorized_actor');
      expect(e.authMode, StreetBusinessInvoiceAuthMode.none);
    });

    test(
      'company admin context makes completed street ride eligible (UX-1B)',
      () {
        final e = resolveStreetBusinessInvoiceReceiptEligibility(
          bookingId: 'street_1',
          kind: 'direct',
          status: 'COMPLETED',
          source: 'street_ride',
          hasDriverSession: false,
          hasCompanyAdminContext: true,
          hasOwnership: true,
        );
        expect(e.eligible, isTrue);
        expect(e.visible, isTrue);
        expect(e.reason, 'eligible_company_admin');
        expect(e.authMode, StreetBusinessInvoiceAuthMode.companyAdmin);
        expect(e.hasAuthorizedCompanyAdminContext, isTrue);
      },
    );

    test(
      'exact runtime case: no driver session + company admin => visible=true',
      () {
        // isStreetRide=true, isCompleted=true, hasOwnership=true,
        // hasBookingId=true, hasDriverSession=false, companyAdminContext=true.
        final auth = resolveStreetBusinessInvoiceAuthContext(
          hasDriverSession: false,
          hasCompanyAdminBearer: true,
          companyTenantId: 'tenant_a',
          companyCompanyId: 'company_a',
          effectiveDriverId: 'driver_9',
          bookingTenantId: 'tenant_a',
          bookingCompanyId: 'company_a',
          hasOwnership: true,
        );
        final e = resolveStreetBusinessInvoiceReceiptEligibility(
          bookingId: 'street_1720000000000_abcd',
          kind: 'direct',
          status: 'STOPPED',
          source: 'street_ride',
          hasOwnership: true,
          authContext: auth,
        );
        expect(e.isStreetRide, isTrue);
        expect(e.isCompleted, isTrue);
        expect(e.hasOwnership, isTrue);
        expect(e.hasBookingId, isTrue);
        expect(e.hasDriverSession, isFalse);
        expect(e.authMode, StreetBusinessInvoiceAuthMode.companyAdmin);
        expect(e.visible, isTrue);
        expect(e.reason, 'eligible_company_admin');
      },
    );
  });

  group('receipt UX-1B auth-context resolver', () {
    test('standalone driver session => driver mode + driver bearer', () {
      final auth = resolveStreetBusinessInvoiceAuthContext(
        hasDriverSession: true,
        driverBearer: 'driver-token',
        driverTenantId: 'tenant_a',
        driverCompanyId: 'company_a',
        driverId: 'driver_1',
        hasCompanyAdminBearer: true,
        companyTenantId: 'tenant_a',
        companyCompanyId: 'company_a',
        effectiveDriverId: 'driver_1',
        bookingTenantId: 'tenant_a',
        bookingCompanyId: 'company_a',
        hasOwnership: true,
      );
      expect(auth.authorized, isTrue);
      expect(auth.mode, StreetBusinessInvoiceAuthMode.driver);
      expect(auth.reason, 'driver_session_valid');
      expect(auth.tenantId, 'tenant_a');
      expect(auth.effectiveDriverId, 'driver_1');
    });

    test('no driver session + company admin bearer => companyAdmin mode', () {
      final auth = resolveStreetBusinessInvoiceAuthContext(
        hasDriverSession: false,
        hasCompanyAdminBearer: true,
        companyTenantId: 'tenant_a',
        companyCompanyId: 'company_a',
        effectiveDriverId: 'driver_9',
        bookingTenantId: 'tenant_a',
        bookingCompanyId: 'company_a',
        hasOwnership: true,
      );
      expect(auth.authorized, isTrue);
      expect(auth.mode, StreetBusinessInvoiceAuthMode.companyAdmin);
      expect(auth.reason, 'company_admin_context_valid');
      expect(auth.effectiveDriverId, 'driver_9');
    });

    test('no driver session + no company admin bearer => none', () {
      final auth = resolveStreetBusinessInvoiceAuthContext(
        hasDriverSession: false,
        hasCompanyAdminBearer: false,
      );
      expect(auth.authorized, isFalse);
      expect(auth.mode, StreetBusinessInvoiceAuthMode.none);
      expect(auth.reason, 'no_authorized_actor');
    });

    test('company scope mismatch is rejected', () {
      final auth = resolveStreetBusinessInvoiceAuthContext(
        hasDriverSession: false,
        hasCompanyAdminBearer: true,
        companyTenantId: 'tenant_a',
        companyCompanyId: 'company_a',
        effectiveDriverId: 'driver_9',
        bookingTenantId: 'tenant_a',
        bookingCompanyId: 'company_other',
        hasOwnership: true,
      );
      expect(auth.authorized, isFalse);
      expect(auth.reason, 'company_scope_mismatch');
    });

    test('ownership mismatch is rejected', () {
      final auth = resolveStreetBusinessInvoiceAuthContext(
        hasDriverSession: false,
        hasCompanyAdminBearer: true,
        companyTenantId: 'tenant_a',
        companyCompanyId: 'company_a',
        effectiveDriverId: 'driver_9',
        bookingTenantId: 'tenant_a',
        bookingCompanyId: 'company_a',
        hasOwnership: false,
      );
      expect(auth.authorized, isFalse);
      expect(auth.reason, 'ownership_failed');
    });

    test('company admin bearer without effective driver => none', () {
      final auth = resolveStreetBusinessInvoiceAuthContext(
        hasDriverSession: false,
        hasCompanyAdminBearer: true,
        companyTenantId: 'tenant_a',
        companyCompanyId: 'company_a',
        effectiveDriverId: '',
        hasOwnership: true,
      );
      expect(auth.authorized, isFalse);
      expect(auth.mode, StreetBusinessInvoiceAuthMode.none);
    });
  });

  group('receipt UX-1C slot lifecycle', () {
    StreetBusinessInvoiceReceiptEligibility companyAdminEligible() =>
        resolveStreetBusinessInvoiceReceiptEligibility(
          bookingId: 'street_1',
          kind: 'direct',
          status: 'COMPLETED',
          source: 'street_ride',
          hasDriverSession: false,
          hasCompanyAdminContext: true,
          hasOwnership: true,
        );

    StreetBusinessInvoiceReceiptEligibility authCollapsed() =>
        resolveStreetBusinessInvoiceReceiptEligibility(
          bookingId: 'street_1',
          kind: 'direct',
          status: 'COMPLETED',
          source: 'street_ride',
          hasDriverSession: false,
          hasCompanyAdminContext: false,
          hasOwnership: true,
        );

    test('live-eligible slot is available and is remembered', () {
      final memo = StreetInvoiceEligibilityMemo();
      final d = resolveStreetInvoiceSlotDecision(
        eligibility: companyAdminEligible(),
        canonicalBookingId: 'street_1',
        memo: memo,
        hasActorContext: true,
        lookupInFlight: false,
        lookupFailed: false,
        kindToken: 'direct',
      );
      expect(d.kind, StreetInvoiceSlotKind.available);
      expect(d.authMode, StreetBusinessInvoiceAuthMode.companyAdmin);
      expect(memo.recall('street_1'), StreetBusinessInvoiceAuthMode.companyAdmin);
    });

    test('sticky recovery keeps slot available after auth-context collapse', () {
      final memo = StreetInvoiceEligibilityMemo();
      // First render confirms eligibility (company admin) and memoizes it.
      resolveStreetInvoiceSlotDecision(
        eligibility: companyAdminEligible(),
        canonicalBookingId: 'street_1',
        memo: memo,
        hasActorContext: true,
        lookupInFlight: false,
        lookupFailed: false,
        kindToken: 'direct',
      );
      // Override cleared → live resolves to no_authorized_actor, but a company
      // admin bearer still exists → slot stays available (sticky).
      final collapsed = authCollapsed();
      expect(collapsed.reason, 'no_authorized_actor');
      final d = resolveStreetInvoiceSlotDecision(
        eligibility: collapsed,
        canonicalBookingId: 'street_1',
        memo: memo,
        hasActorContext: true,
        lookupInFlight: false,
        lookupFailed: false,
        kindToken: 'direct',
      );
      expect(d.kind, StreetInvoiceSlotKind.available);
      expect(d.reason, 'eligible_sticky');
      expect(d.authMode, StreetBusinessInvoiceAuthMode.companyAdmin);
    });

    test('sticky recovery is denied when no actor context remains', () {
      final memo = StreetInvoiceEligibilityMemo();
      memo.remember('street_1', StreetBusinessInvoiceAuthMode.companyAdmin);
      final d = resolveStreetInvoiceSlotDecision(
        eligibility: authCollapsed(),
        canonicalBookingId: 'street_1',
        memo: memo,
        hasActorContext: false,
        lookupInFlight: false,
        lookupFailed: false,
        kindToken: 'direct',
      );
      expect(d.kind, StreetInvoiceSlotKind.unavailable);
    });

    test('sticky never overrides a hard-negative verdict (cancelled)', () {
      final memo = StreetInvoiceEligibilityMemo();
      memo.remember('street_1', StreetBusinessInvoiceAuthMode.companyAdmin);
      final cancelled = resolveStreetBusinessInvoiceReceiptEligibility(
        bookingId: 'street_1',
        kind: 'direct',
        status: 'CANCELLED',
        source: 'street_ride',
        hasDriverSession: false,
        hasCompanyAdminContext: true,
        hasOwnership: true,
        isCancelled: true,
      );
      final d = resolveStreetInvoiceSlotDecision(
        eligibility: cancelled,
        canonicalBookingId: 'street_1',
        memo: memo,
        hasActorContext: true,
        lookupInFlight: false,
        lookupFailed: false,
        kindToken: 'direct',
      );
      expect(d.kind, StreetInvoiceSlotKind.unavailable);
    });

    test('needs-lookup maps to resolving, lookup failure to retryableError', () {
      final memo = StreetInvoiceEligibilityMemo();
      final needsLookup = resolveStreetBusinessInvoiceReceiptEligibility(
        bookingId: 'bk_linked_1',
        tripId: 'trip_1',
        kind: 'direct',
        status: 'stopped',
        source: '',
        hasDriverSession: true,
        hasOwnership: true,
      );
      expect(needsLookup.needsBookingLookup, isTrue);
      final resolving = resolveStreetInvoiceSlotDecision(
        eligibility: needsLookup,
        canonicalBookingId: 'bk_linked_1',
        memo: memo,
        hasActorContext: true,
        lookupInFlight: true,
        lookupFailed: false,
        kindToken: 'direct',
      );
      expect(resolving.kind, StreetInvoiceSlotKind.resolving);

      final retry = resolveStreetInvoiceSlotDecision(
        eligibility: needsLookup,
        canonicalBookingId: 'bk_linked_1',
        memo: memo,
        hasActorContext: true,
        lookupInFlight: false,
        lookupFailed: true,
        kindToken: 'direct',
      );
      expect(retry.kind, StreetInvoiceSlotKind.retryableError);
    });

    test('a different booking id never reuses another booking verdict', () {
      final memo = StreetInvoiceEligibilityMemo();
      memo.remember('street_1', StreetBusinessInvoiceAuthMode.companyAdmin);
      expect(memo.recall('street_2'), isNull);
      final d = resolveStreetInvoiceSlotDecision(
        eligibility: resolveStreetBusinessInvoiceReceiptEligibility(
          bookingId: 'street_2',
          kind: 'direct',
          status: 'COMPLETED',
          source: 'street_ride',
          hasDriverSession: false,
          hasCompanyAdminContext: false,
          hasOwnership: true,
        ),
        canonicalBookingId: 'street_2',
        memo: memo,
        hasActorContext: true,
        lookupInFlight: false,
        lookupFailed: false,
        kindToken: 'direct',
      );
      expect(d.kind, StreetInvoiceSlotKind.unavailable);
    });

    test('non-street ride resolves to unavailable (no fourth action)', () {
      final memo = StreetInvoiceEligibilityMemo();
      final planned = resolveStreetBusinessInvoiceReceiptEligibility(
        bookingId: 'planned_1',
        kind: 'planned',
        status: 'COMPLETED',
        source: 'customer',
        hasDriverSession: true,
        hasOwnership: true,
      );
      final d = resolveStreetInvoiceSlotDecision(
        eligibility: planned,
        canonicalBookingId: 'planned_1',
        memo: memo,
        hasActorContext: true,
        lookupInFlight: false,
        lookupFailed: false,
        kindToken: 'planned',
      );
      expect(d.kind, StreetInvoiceSlotKind.unavailable);
    });

    StreetInvoicePostResult okPost() => const StreetInvoicePostResult(
      statusCode: 200,
      response: StreetBusinessInvoiceResponse(
        ok: true,
        bookingId: 'street_1',
        documentId: 'doc-1',
        invoiceReference: 'INV-2026-000030',
        reused: false,
        paymentStatus: 'unpaid',
        billitEnvironment: 'sandbox',
        billitOrderId: '2954728',
        billitOrderReused: false,
        billitPaymentSyncStatus: '',
        peppolSent: false,
        warnings: <String>[],
        paymentReconciliation: 'pending_external_payment',
      ),
    );

    test('opening the form without submit performs no POST (stays available)',
        () async {
      var postCount = 0;
      final c = StreetBusinessInvoiceController(
        bookingId: 'street_1',
        isPaidBooking: false,
        delay: (_) async {},
        postInvoice: (_) async {
          postCount++;
          return okPost();
        },
        fetchDocuments: () async =>
            const StreetInvoiceDocsResult(statusCode: 200, okEnvelope: true),
      );
      // Simulates "open form → Cancel": loadExisting runs, submit never does.
      await c.loadExisting();
      expect(postCount, 0);
      expect(c.hasIssuedInvoice, isFalse);
      expect(c.state, StreetBusinessInvoiceUiState.eligibleNoInvoice);
      c.dispose();
    });

    test('loadExisting: 200 + existing invoice => issuedIndexed', () async {
      final c = StreetBusinessInvoiceController(
        bookingId: 'street_1',
        isPaidBooking: true,
        delay: (_) async {},
        postInvoice: (_) async => okPost(),
        fetchDocuments: () async => const StreetInvoiceDocsResult(
          statusCode: 200,
          okEnvelope: true,
          invoice: StreetInvoiceDocSummary(
            documentId: 'doc-1',
            documentNumber: 'INV-2026-000030',
            lifecycleState: 'issued',
            billitEnvironment: 'sandbox',
            billitOrderId: '2954728',
            peppolSent: false,
            billitPaid: true,
          ),
        ),
      );
      await c.loadExisting();
      expect(c.hasIssuedInvoice, isTrue);
      expect(c.state, StreetBusinessInvoiceUiState.issuedIndexed);
      c.dispose();
    });

    test('loadExisting: network failure stays available (button visible)',
        () async {
      final c = StreetBusinessInvoiceController(
        bookingId: 'street_1',
        isPaidBooking: false,
        delay: (_) async {},
        postInvoice: (_) async => okPost(),
        fetchDocuments: () async => throw Exception('network'),
      );
      await c.loadExisting();
      expect(c.hasIssuedInvoice, isFalse);
      expect(c.state, StreetBusinessInvoiceUiState.eligibleNoInvoice);
      c.dispose();
    });

    test('successful submit yields an existing-invoice state', () async {
      final c = StreetBusinessInvoiceController(
        bookingId: 'street_1',
        isPaidBooking: false,
        delay: (_) async {},
        pollInterval: const Duration(milliseconds: 1),
        pollTimeout: const Duration(milliseconds: 1),
        postInvoice: (_) async => okPost(),
        fetchDocuments: () async =>
            const StreetInvoiceDocsResult(statusCode: 200, okEnvelope: true),
      );
      await c.submit(
        const StreetBusinessInvoiceBuyerInput(
          legalName: 'ACME',
          street: 'S 1',
          postalCode: '1000',
          city: 'Brussel',
          country: 'BE',
        ),
      );
      expect(c.hasIssuedInvoice, isTrue);
      await c.pollingFuture;
      c.dispose();
    });
  });

  group('receipt PDF + payment sync (PDF-PAYMENT-SYNC-1)', () {
    test('invoice without PDF artifact => preparing, View/Share not available',
        () {
      final pdf = resolveStreetInvoicePdfAvailability(
        hasIssuedInvoice: true,
        pdfArtifactReady: false,
        pdfProbeStatusCode: 404,
      );
      expect(pdf.state, StreetInvoicePdfAvailabilityState.preparing);
      expect(pdf.canViewOrShare, isFalse);
    });

    test('PDF artifact ready => available', () {
      final pdf = resolveStreetInvoicePdfAvailability(
        hasIssuedInvoice: true,
        pdfArtifactReady: true,
      );
      expect(pdf.state, StreetInvoicePdfAvailabilityState.available);
      expect(pdf.canViewOrShare, isTrue);
    });

    test('PDF probe 404 while Billit updating stays preparing (not error toast)',
        () {
      final pdf = resolveStreetInvoicePdfAvailability(
        hasIssuedInvoice: true,
        pdfProbeStatusCode: 404,
      );
      expect(pdf.state, StreetInvoicePdfAvailabilityState.preparing);
      expect(pdf.isRetryable, isFalse);
    });

    test('PDF network failure => retryableError', () {
      final pdf = resolveStreetInvoicePdfAvailability(
        hasIssuedInvoice: true,
        pdfProbeFailed: true,
      );
      expect(pdf.state, StreetInvoicePdfAvailabilityState.retryableError);
    });

    test('paid ride + unpaid Billit => syncInProgress, not outstanding', () {
      final p = resolveStreetInvoicePaymentPresentation(
        hasIssuedInvoice: true,
        ridePaid: true,
        billitPaid: false,
        hasBillitLink: true,
      );
      expect(
        p.invoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.syncInProgress,
      );
      expect(p.ridePaymentStatus, StreetInvoiceRidePaymentStatus.paid);
      expect(p.isConsistent, isTrue);
    });

    test('Billit paid => invoice paid', () {
      final p = resolveStreetInvoicePaymentPresentation(
        hasIssuedInvoice: true,
        ridePaid: true,
        billitPaid: true,
        billitPaymentSyncStatus: 'synced',
        hasBillitLink: true,
      );
      expect(p.invoicePaymentStatus, StreetInvoiceInvoicePaymentStatus.paid);
    });

    test('unpaid ride + unpaid invoice => outstanding', () {
      final p = resolveStreetInvoicePaymentPresentation(
        hasIssuedInvoice: true,
        ridePaid: false,
        billitPaid: false,
      );
      expect(
        p.invoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.outstanding,
      );
    });

    test('receipt payment key: sync in progress still shows paid', () {
      expect(
        streetBusinessInvoicePaymentStatusKey(
          hasInvoice: true,
          invoicePaid: false,
          receiptPaid: true,
          paymentSyncInProgress: true,
        ),
        'paid',
      );
    });

    // RELEASE-P0: unlinked vs syncing must stay separated.
    test(
      'P0: ridePaid + no Billit link => notLinkedToBillit (not syncInProgress)',
      () {
        final p = resolveStreetInvoicePaymentPresentation(
          hasIssuedInvoice: true,
          ridePaid: true,
          billitPaid: null,
          billitUpdating: true,
          syncPending: true,
          billitPaymentSyncStatus: '',
          hasBillitLink: false,
        );
        expect(
          p.invoicePaymentStatus,
          StreetInvoiceInvoicePaymentStatus.notLinkedToBillit,
        );
        expect(p.reason, 'not_linked_to_billit');
        expect(
          p.invoicePaymentStatus,
          isNot(StreetInvoiceInvoicePaymentStatus.syncInProgress),
        );
      },
    );

    test(
      '1B: ridePaid + billitPaid false + linked + updating => syncInProgress',
      () {
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
        expect(p.reason, 'payment_sync_in_progress');
        expect(
          p.invoicePaymentStatus,
          isNot(StreetInvoiceInvoicePaymentStatus.outstanding),
        );
      },
    );

    test('1B: only truly unpaid ride/invoice => outstanding', () {
      final unpaid = resolveStreetInvoicePaymentPresentation(
        hasIssuedInvoice: true,
        ridePaid: false,
        billitPaid: false,
      );
      expect(
        unpaid.invoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.outstanding,
      );
      final paidRideUnlinked = resolveStreetInvoicePaymentPresentation(
        hasIssuedInvoice: true,
        ridePaid: true,
        billitPaid: false,
        hasBillitLink: false,
      );
      expect(
        paidRideUnlinked.invoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.notLinkedToBillit,
      );
      final paidRideLinked = resolveStreetInvoicePaymentPresentation(
        hasIssuedInvoice: true,
        ridePaid: true,
        billitPaid: false,
        hasBillitLink: true,
      );
      expect(
        paidRideLinked.invoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.syncInProgress,
      );
    });

    test('1B: Billit paid/synced => invoicePaid', () {
      expect(
        resolveStreetInvoicePaymentPresentation(
          hasIssuedInvoice: true,
          ridePaid: true,
          billitPaid: true,
          hasBillitLink: true,
        ).invoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.paid,
      );
      expect(
        resolveStreetInvoicePaymentPresentation(
          hasIssuedInvoice: true,
          ridePaid: true,
          billitPaid: false,
          billitPaymentSyncStatus: 'synced',
          hasBillitLink: true,
        ).invoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.paid,
      );
    });

    test('1B: sync failure is syncFailed, never outstanding', () {
      final p = resolveStreetInvoicePaymentPresentation(
        hasIssuedInvoice: true,
        ridePaid: true,
        billitPaid: false,
        billitPaymentSyncStatus: 'failed',
        hasBillitLink: true,
      );
      expect(
        p.invoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.syncFailed,
      );
      expect(p.reason, 'payment_sync_failed_retryable');
      expect(
        p.invoicePaymentStatus,
        isNot(StreetInvoiceInvoicePaymentStatus.outstanding),
      );
    });

    test('P0: empty sync token without link is not pending forever', () {
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
        streetInvoicePaymentStatusKey(p.invoicePaymentStatus),
        'notLinkedToBillit',
      );
    });

    test('controller: no PDF artifact keeps View gated; refresh bounded',
        () async {
      var probeCount = 0;
      final c = StreetBusinessInvoiceController(
        bookingId: 'street_1',
        isPaidBooking: true,
        delay: (_) async {},
        statusRefreshDelays: const [
          Duration.zero,
          Duration(milliseconds: 1),
        ],
        postInvoice: (_) async => const StreetInvoicePostResult(statusCode: 500),
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
          ),
        ),
        probePdf: () async {
          probeCount++;
          return const StreetInvoicePdfProbeResult(statusCode: 404);
        },
      );
      await c.loadExisting();
      await c.statusRefreshFuture;
      expect(c.hasIssuedInvoice, isTrue);
      expect(c.pdfAvailability.canViewOrShare, isFalse);
      expect(
        c.pdfAvailability.state,
        StreetInvoicePdfAvailabilityState.preparing,
      );
      expect(
        c.paymentPresentation.invoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.notLinkedToBillit,
      );
      expect(probeCount, greaterThan(0));
      c.dispose();
      // Dispose stops further refresh; probe count must stay finite.
      final afterDispose = probeCount;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(probeCount, afterDispose);
    });

    test('controller: PDF ready enables View/Share', () async {
      final c = StreetBusinessInvoiceController(
        bookingId: 'street_1',
        isPaidBooking: true,
        delay: (_) async {},
        statusRefreshDelays: const [Duration.zero],
        postInvoice: (_) async => const StreetInvoicePostResult(statusCode: 500),
        fetchDocuments: () async => const StreetInvoiceDocsResult(
          statusCode: 200,
          okEnvelope: true,
          invoicePdfReady: true,
          invoice: StreetInvoiceDocSummary(
            documentId: 'doc-1',
            documentNumber: 'INV-2026-000032',
            lifecycleState: 'issued',
            billitEnvironment: 'sandbox',
            billitOrderId: 'ord_1',
            peppolSent: false,
            billitPaid: true,
            billitPaymentSyncStatus: 'synced',
          ),
        ),
        probePdf: () async => const StreetInvoicePdfProbeResult(statusCode: 200),
      );
      await c.loadExisting();
      await c.statusRefreshFuture;
      expect(c.pdfAvailability.canViewOrShare, isTrue);
      expect(c.displayIsPaid, isTrue);
      c.dispose();
    });

    test('extractInvoicePdfReadyFromDocuments reads invoice_pdf.ready', () {
      expect(
        extractInvoicePdfReadyFromDocuments({
          'ok': true,
          'documents': <dynamic>[],
          'invoice_pdf': {'ready': true, 'exists': true},
        }),
        isTrue,
      );
      expect(
        extractInvoicePdfReadyFromDocuments({
          'ok': true,
          'documents': <dynamic>[],
          'invoice_pdf': {'ready': false},
        }),
        isFalse,
      );
      expect(extractInvoicePdfReadyFromDocuments({'ok': true}), isNull);
    });
  });

  group('receipt UX-1 helpers', () {
    test('payment status key distinguishes invoice pending from unpaid', () {
      expect(
        streetBusinessInvoicePaymentStatusKey(
          hasInvoice: false,
          invoicePaid: false,
          receiptPaid: false,
        ),
        isNull,
      );
      expect(
        streetBusinessInvoicePaymentStatusKey(
          hasInvoice: true,
          invoicePaid: false,
          receiptPaid: false,
        ),
        'invoicePending',
      );
      expect(
        streetBusinessInvoicePaymentStatusKey(
          hasInvoice: true,
          invoicePaid: true,
          receiptPaid: false,
        ),
        'paid',
      );
    });

    test('prefill parses company + address fields', () {
      final input = streetBusinessInvoicePrefillFromFields(
        companyName: ' ACMe BV ',
        vatNumber: 'BE0123456789',
        invoiceEmail: 'billing@acme.test',
        invoiceAddress: 'Teststraat 1, 1000 Brussel, BE',
      );
      expect(input.legalName, 'ACMe BV');
      expect(input.vatNumber, 'BE0123456789');
      expect(input.contactEmail, 'billing@acme.test');
      expect(input.postalCode, '1000');
      expect(input.city.toLowerCase(), contains('brussel'));
      expect(input.country, 'BE');
      expect(input.street, isNotEmpty);
    });

    test('VAT validation accepts BE numbers and rejects garbage', () {
      expect(isPlausibleVatOrCompanyNumber(''), isTrue);
      expect(isPlausibleVatOrCompanyNumber('BE0123456789'), isTrue);
      expect(isPlausibleVatOrCompanyNumber('0123456789'), isTrue);
      expect(isPlausibleVatOrCompanyNumber('??'), isFalse);
      final bad = validateStreetBusinessInvoiceForm(
        const StreetBusinessInvoiceBuyerInput(
          legalName: 'ACME',
          street: 'S 1',
          postalCode: '1000',
          city: 'Brussel',
          country: 'BE',
          vatNumber: '??',
        ),
      );
      expect(bad.isValid, isFalse);
      expect(bad.vatInvalid, isTrue);
    });

    test('non-street bookings stay ineligible (receipt gate)', () {
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'planned_roundtrip_1',
          source: 'customer',
          rideType: 'planned',
          status: 'COMPLETED',
        ),
        isFalse,
      );
    });

    test('unpaid completed street ride stays eligible', () {
      expect(
        isStreetRideBusinessInvoiceEligible(
          bookingId: 'street_unpaid_1',
          source: 'street_ride',
          status: 'COMPLETED',
        ),
        isTrue,
      );
    });
  });

  group('PDF-PAYMENT-SYNC-1D canonical ride-paid wiring', () {
    StreetInvoiceDocSummary lagInvoice() => const StreetInvoiceDocSummary(
      documentId: 'doc-1',
      documentNumber: 'INV-2026-000032',
      lifecycleState: 'issued',
      billitEnvironment: 'sandbox',
      billitOrderId: '',
      peppolSent: false,
      billitPaid: false,
      billitPaymentSyncStatus: '',
    );

    StreetBusinessInvoiceController lagController({required bool isPaidBooking}) {
      return StreetBusinessInvoiceController(
        bookingId: 'street_1',
        isPaidBooking: isPaidBooking,
        delay: (_) async {},
        pollInterval: const Duration(days: 1),
        pollTimeout: const Duration(days: 1),
        postInvoice: (_) async => const StreetInvoicePostResult(statusCode: 500),
        fetchDocuments: () async => StreetInvoiceDocsResult(
          statusCode: 200,
          okEnvelope: true,
          invoicePdfReady: false,
          invoice: lagInvoice(),
        ),
      );
    }

    // (case 1) receipt resolver says paid → canonical isPaid true.
    test('effectiveReceiptPaid → canonical paid (receipt_effective_paid)', () {
      final r = resolveCanonicalReceiptRidePayment(effectiveReceiptPaid: true);
      expect(r.isPaid, isTrue);
      expect(r.normalizedStatus, 'paid');
      expect(r.source, 'receipt_effective_paid');
    });

    test('explicit payment_status=paid → canonical paid (explicit_status)', () {
      final r = resolveCanonicalReceiptRidePayment(
        explicitPaymentStatus: 'PAID',
      );
      expect(r.isPaid, isTrue);
      expect(r.source, 'explicit_status');
    });

    // (case 2) documents-response missing payment_status → UNKNOWN, not false.
    test('missing document payment field is unknown, never unpaid', () {
      final r = resolveCanonicalReceiptRidePayment(documentRidePaid: null);
      expect(r.isPaid, isFalse);
      expect(r.normalizedStatus, 'unknown');
    });

    test('prior canonical paid is retained despite missing document', () {
      final r = resolveCanonicalReceiptRidePayment(
        priorCanonicalPaid: true,
        documentRidePaid: null,
      );
      expect(r.isPaid, isTrue);
      expect(r.reason, 'monotonic_retained');
    });

    // (case 3) documents billitPaid=false + no order link → notLinkedToBillit.
    test('paid ride + no Billit link → controller resolves notLinkedToBillit', () async {
      final c = lagController(isPaidBooking: true);
      await c.loadExisting();
      expect(c.rideConfirmedPaid, isTrue);
      expect(
        c.displayInvoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.notLinkedToBillit,
      );
      c.dispose();
    });

    // (case 4) late canonical paid transition flips outstanding → notLinked
    // without recreating the controller (still no Billit order id).
    test('late updateCanonicalRidePaymentStatus(true) flips to notLinkedToBillit', () async {
      final c = lagController(isPaidBooking: false);
      await c.loadExisting();
      expect(
        c.displayInvoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.outstanding,
      );
      c.updateCanonicalRidePaymentStatus(true);
      expect(c.rideConfirmedPaid, isTrue);
      expect(
        c.displayInvoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.notLinkedToBillit,
      );
      c.dispose();
    });

    // (case 5) loadExisting after paid: an envelope without a ride payment field
    // must not reset ride-paid.
    test('loadExisting after paid keeps ride paid (no downgrade)', () async {
      final c = lagController(isPaidBooking: true);
      c.updateCanonicalRidePaymentStatus(true);
      await c.loadExisting();
      expect(c.rideConfirmedPaid, isTrue);
      expect(
        c.displayInvoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.notLinkedToBillit,
      );
      c.dispose();
    });

    // (case 6) monotonic: a false/unknown signal never downgrades a paid ride.
    test('monotonic: false update does not downgrade a paid ride', () {
      final c = lagController(isPaidBooking: true);
      expect(c.rideConfirmedPaid, isTrue);
      c.updateCanonicalRidePaymentStatus(false);
      expect(c.rideConfirmedPaid, isTrue);
      c.dispose();
    });

    // (case 10) explicit reversal/refund may change paid per contract.
    test('explicit reversal downgrades a paid ride', () {
      final c = lagController(isPaidBooking: true);
      c.updateCanonicalRidePaymentStatus(false, reversal: true);
      expect(c.rideConfirmedPaid, isFalse);
      c.dispose();
    });

    test('resolver reversal → unpaid (source=reversal)', () {
      final r = resolveCanonicalReceiptRidePayment(
        priorCanonicalPaid: true,
        reversal: true,
      );
      expect(r.isPaid, isFalse);
      expect(r.source, 'reversal');
    });

    // (case 9) a genuinely unpaid ride stays outstanding.
    test('genuinely unpaid ride stays outstanding', () async {
      final c = lagController(isPaidBooking: false);
      await c.loadExisting();
      expect(c.rideConfirmedPaid, isFalse);
      expect(
        c.displayInvoicePaymentStatus,
        StreetInvoiceInvoicePaymentStatus.outstanding,
      );
      c.dispose();
    });
  });
}
