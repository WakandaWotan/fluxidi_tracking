// CONSUMER-BILLIT-DOCUMENT-UI-1 / CONSUMER-SALE-DOCUMENT-PRESENTATION-P0-1

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/payment/consumer_sale_presentation.dart';

void main() {
  group('consumer sale presentation', () {
    test('1. consumer street ride shows no business invoice label', () {
      expect(
        consumerOrBusinessDocumentLabelKey(
          saleKind: 'consumer_sale',
          documentType: 'invoice',
        ),
        'consumerSale',
      );
      expect(
        documentForbidsInvoiceLabel(
          saleKind: 'consumer_sale',
          documentType: 'invoice',
        ),
        isTrue,
      );
    });

    test('2. consumer planned ride shows no Peppol warning', () {
      final p = resolvePeppolUiPolicy(
        saleKind: 'consumer_sale',
        documentType: 'invoice',
      );
      expect(p.showMissingEndpointWarning, isFalse);
      expect(p.showSettingsRequiredWarning, isFalse);
    });

    test('3. consumer sale shows Peppol not applicable', () {
      final p = resolvePeppolUiPolicy(saleKind: 'consumer_sale');
      expect(p.applicable, isFalse);
      expect(p.showNotApplicable, isTrue);
    });

    test('4. Verstuur via Peppol is absent for consumer', () {
      final p = resolvePeppolUiPolicy(
        saleKind: 'consumer_sale',
        documentType: 'invoice',
        peppolApplicable: false,
      );
      expect(p.showSendAction, isFalse);
    });

    test('5. Zakelijke factuur aanvragen remains available', () {
      expect(
        businessInvoiceActionStillAvailable(
          consumerSalePresent: true,
          businessInvoicePresent: false,
          conversionAllowed: true,
        ),
        isTrue,
      );
    });

    test('6. business invoice still shows Peppol status', () {
      final p = resolvePeppolUiPolicy(
        saleKind: 'business_invoice',
        documentType: 'invoice',
        businessInvoiceIntent: true,
      );
      expect(p.applicable, isTrue);
      expect(p.showSendAction, isTrue);
      expect(
        consumerOrBusinessDocumentLabelKey(
          documentType: 'invoice',
          businessInvoiceIntent: true,
        ),
        'invoice',
      );
    });

    test('7. converted consumer sale shows new business invoice', () {
      expect(
        documentLabelKeyAfterConversion(conversionSucceeded: true),
        'invoice',
      );
      expect(
        resolveDocumentPresentationKind(
          saleKind: 'consumer_sale',
          conversionToBusinessSucceeded: true,
        ),
        FluxidiDocumentPresentationKind.businessInvoice,
      );
    });

    test('8. Billit OrderType Invoice does not force business presentation', () {
      // documentType invoice alone with consumer signals stays consumer.
      expect(
        resolveDocumentPresentationKind(
          documentType: 'invoice',
          saleKind: 'consumer_sale',
          createdByRole: 'system_consumer_sale',
        ),
        FluxidiDocumentPresentationKind.consumerSale,
      );
      expect(
        isBusinessDocumentForPresentation(
          documentType: 'invoice',
          saleKind: 'consumer_sale',
          billitOrderType: 'Invoice',
          documentNumber: 'INV-2026-000099',
        ),
        isFalse,
      );
    });

    test('9. filled company data does not force business presentation', () {
      expect(
        isBusinessDocumentForPresentation(
          saleKind: 'consumer_sale',
          billingCustomerType: 'private',
          companyName: 'Particuliere klant',
          vatNumber: '',
          billitOrderType: 'Invoice',
        ),
        isFalse,
      );
      expect(
        resolveDocumentPresentationKind(
          bookingConsumerSaleKind: 'consumer_sale',
          billingCustomerType: 'private',
          documentType: 'invoice',
        ),
        FluxidiDocumentPresentationKind.consumerSale,
      );
    });

    test('10. PDF title ritbon; payment key never surfaces in_car', () {
      expect(
        consumerOrBusinessPdfTitleKey(saleKind: 'consumer_sale'),
        'ritbon',
      );
      expect(
        paymentMethodDisplayKey(
          paymentMethod: 'cash',
          paymentSource: 'in_car',
        ),
        'cash',
      );
      expect(
        paymentMethodDisplayKey(paymentSource: 'in_car'),
        'cash',
      );
      expect(
        shouldShowPaymentSourceOnDocument(
          presentationKind: FluxidiDocumentPresentationKind.consumerSale,
          paymentSource: 'in_car',
        ),
        isFalse,
      );
      expect(
        consumerSaleShortRideReference('street_1785819368565_6bb22fdh'),
        isNot(contains('street_')),
      );
      expect(
        consumerSaleShortRideReference('street_1785819368565_6bb22fdh').length,
        lessThanOrEqualTo(10),
      );
    });

    test('historical consumer via created_by_role / peppol_applicable', () {
      expect(
        resolveDocumentPresentationKind(
          documentType: 'invoice',
          createdByRole: 'system_consumer_sale',
        ),
        FluxidiDocumentPresentationKind.consumerSale,
      );
      expect(
        resolvePeppolUiPolicy(
          documentType: 'invoice',
          peppolApplicable: false,
        ).showSendAction,
        isFalse,
      );
    });

    test('planned and street share presentation contract', () {
      expect(
        consumerSalePresentationContractId(isStreetRide: false),
        consumerSalePresentationContractId(isStreetRide: true),
      );
    });

    test('Tap to Pay payment method displays correctly', () {
      expect(
        paymentMethodDisplayKey(
          paymentMethod: 'pointofsale',
          paymentProvider: 'mollie',
          paymentSource: 'tap_to_pay',
        ),
        'tapToPay',
      );
    });
  });

  group('CONSUMER-SALE-LATE-BUSINESS-INVOICE-ACTION-P0-3 visibility', () {
    test('1. paid planned consumer sale shows action', () {
      expect(
        shouldShowLateBusinessInvoiceAction(
          saleKind: 'consumer_sale',
          documentType: 'invoice',
        ),
        isTrue,
      );
    });

    test('2. unpaid planned consumer sale shows action', () {
      expect(
        shouldShowLateBusinessInvoiceAction(
          saleKind: 'consumer_sale',
          documentType: 'invoice',
          peppolApplicable: false,
        ),
        isTrue,
      );
    });

    test('3. paid street consumer sale shows action', () {
      expect(
        shouldShowLateBusinessInvoiceAction(
          saleKind: 'consumer_sale',
          documentType: 'invoice',
          createdByRole: 'system_consumer_sale',
        ),
        isTrue,
      );
    });

    test('4. real business invoice hides action', () {
      expect(
        shouldShowLateBusinessInvoiceAction(
          saleKind: 'business_invoice',
          documentType: 'invoice',
        ),
        isFalse,
      );
    });

    test('5. credit note hides action', () {
      expect(
        shouldShowLateBusinessInvoiceAction(
          saleKind: 'credit_note',
          documentType: 'credit_note',
        ),
        isFalse,
      );
    });

    test('6. already converted consumer sale hides action', () {
      expect(
        shouldShowLateBusinessInvoiceAction(
          saleKind: 'consumer_sale',
          documentType: 'invoice',
          superseded: true,
        ),
        isFalse,
      );
      expect(
        shouldShowLateBusinessInvoiceAction(
          saleKind: 'consumer_sale',
          businessInvoicePresent: true,
        ),
        isFalse,
      );
    });

    test('7. conversion in progress hides second active action', () {
      expect(
        shouldShowLateBusinessInvoiceAction(
          saleKind: 'consumer_sale',
          conversionInProgress: true,
        ),
        isFalse,
      );
    });

    test('12. Peppol stays N/A before conversion', () {
      final p = resolvePeppolUiPolicy(saleKind: 'consumer_sale');
      expect(p.showNotApplicable, isTrue);
      expect(p.showSendAction, isFalse);
      expect(p.showMissingEndpointWarning, isFalse);
    });

    test('businessInvoiceActionStillAvailable requires consumer sale', () {
      expect(
        businessInvoiceActionStillAvailable(
          consumerSalePresent: false,
          businessInvoicePresent: false,
          conversionAllowed: true,
        ),
        isFalse,
      );
    });
  });

  group('CONSUMER-SALE-LATE-INVOICE-ACTION-PLACEMENT-P1', () {
    test('1. street consumer sale → streetCanonicalSlot above Documenten', () {
      expect(
        resolveCompanyLateInvoicePlacement(
          completedBucket: true,
          streetRideBusinessInvoiceEligible: true,
        ),
        CompanyLateInvoicePlacementKind.streetCanonicalSlot,
      );
    });

    test('2. planned completed → consumerSaleProbeSlot above Documenten', () {
      expect(
        resolveCompanyLateInvoicePlacement(
          completedBucket: true,
          streetRideBusinessInvoiceEligible: false,
        ),
        CompanyLateInvoicePlacementKind.consumerSaleProbeSlot,
      );
    });

    test('3/4. heen/terug use same placement resolver (per card)', () {
      // Operational leg cards share the same completed/street predicates;
      // each mounts one slot above its own Documenten section.
      expect(
        resolveCompanyLateInvoicePlacement(
          completedBucket: true,
          streetRideBusinessInvoiceEligible: false,
        ),
        CompanyLateInvoicePlacementKind.consumerSaleProbeSlot,
      );
      expect(
        resolveCompanyLateInvoicePlacement(
          completedBucket: true,
          streetRideBusinessInvoiceEligible: true,
        ),
        CompanyLateInvoicePlacementKind.streetCanonicalSlot,
      );
    });

    test('6. non-completed / open bucket hides placement', () {
      expect(
        resolveCompanyLateInvoicePlacement(
          completedBucket: false,
          streetRideBusinessInvoiceEligible: true,
        ),
        CompanyLateInvoicePlacementKind.hidden,
      );
    });

    test('5/7. converted / business invoice hides late request helper', () {
      expect(
        shouldShowLateBusinessInvoiceAction(
          saleKind: 'consumer_sale',
          superseded: true,
        ),
        isFalse,
      );
      expect(
        shouldShowLateBusinessInvoiceAction(
          saleKind: 'business_invoice',
        ),
        isFalse,
      );
    });

    test('8. conversion in progress hides second request', () {
      expect(
        shouldShowLateBusinessInvoiceAction(
          saleKind: 'consumer_sale',
          conversionInProgress: true,
        ),
        isFalse,
      );
    });

    test('10. parent eligibility does not replace per-leg placement mode', () {
      // Planned completed → probe slot; street → canonical. Sibling legs each
      // resolve independently via the same completed/street predicates.
      expect(
        resolveCompanyLateInvoicePlacement(
          completedBucket: true,
          streetRideBusinessInvoiceEligible: false,
        ),
        CompanyLateInvoicePlacementKind.consumerSaleProbeSlot,
      );
    });
  });
}
