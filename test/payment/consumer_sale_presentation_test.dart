// CONSUMER-BILLIT-DOCUMENT-UI-1

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/payment/consumer_sale_presentation.dart';

void main() {
  group('consumer sale presentation', () {
    test('1. private ride shows Particuliere verkoop / Ontvangstbewijs key', () {
      expect(
        consumerOrBusinessDocumentLabelKey(saleKind: 'consumer_sale'),
        'consumerSale',
      );
    });

    test('2. private ride does not use Factuur label', () {
      expect(
        documentForbidsInvoiceLabel(saleKind: 'consumer_sale'),
        isTrue,
      );
      expect(
        consumerOrBusinessDocumentLabelKey(saleKind: 'consumer_sale'),
        isNot('invoice'),
      );
    });

    test('3. status registered in Billit', () {
      expect(
        consumerSaleStatusLabelKey(
          saleKind: 'consumer_sale',
          registeredInBillit: true,
          billitOrderId: 'ord_1',
        ),
        'registeredInBillit',
      );
    });

    test('4+5. Peppol not applicable; no missing-endpoint warning', () {
      final p = resolvePeppolUiPolicy(saleKind: 'consumer_sale');
      expect(p.applicable, isFalse);
      expect(p.showNotApplicable, isTrue);
      expect(p.showMissingEndpointWarning, isFalse);
      expect(p.showSettingsRequiredWarning, isFalse);
      expect(p.showSendAction, isFalse);
    });

    test('6. business ride still shows Factuur', () {
      expect(
        consumerOrBusinessDocumentLabelKey(
          documentType: 'invoice',
          businessInvoiceIntent: true,
        ),
        'invoice',
      );
      expect(
        documentForbidsInvoiceLabel(businessInvoiceIntent: true),
        isFalse,
      );
    });

    test('7. business invoice action remains available for consumer sale', () {
      expect(
        businessInvoiceActionStillAvailable(
          consumerSalePresent: true,
          businessInvoicePresent: false,
          conversionAllowed: true,
        ),
        isTrue,
      );
    });

    test('8. conversion refreshes document type to invoice', () {
      expect(
        documentLabelKeyAfterConversion(conversionSucceeded: true),
        'invoice',
      );
      expect(
        documentLabelKeyAfterConversion(conversionSucceeded: false),
        'consumerSale',
      );
    });

    test('9. planned and street share presentation contract', () {
      expect(
        consumerSalePresentationContractId(isStreetRide: false),
        consumerSalePresentationContractId(isStreetRide: true),
      );
    });

    test('10. Tap to Pay payment method displays correctly', () {
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
}
