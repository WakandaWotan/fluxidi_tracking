import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/extra_vehicle_addon_purchase.dart';
import 'package:fluxidi_tracking/company/subscription_fiscal_treatment.dart';

void main() {
  const belgianFiscal = SubscriptionFiscalVerdict(
    taxTreatment: kSubscriptionTaxBelgianVat,
  );

  ExtraVehiclePurchasePreview belgiumAtCapacityPreview() {
    return extraVehiclePurchasePreviewFromAuthoritative(
      usedVehicles: 3,
      capacity: 3,
      catalogExtraVehicleExclCents: 1900,
      profileRecurringAmountCents: 10700,
      baseExclCents: 6900,
      extraDriverUnitExclCents: 900,
      extraVehicleActiveQuantity: 2,
      extraDriverActiveQuantity: 0,
    );
  }

  group('explicit confirmation and preview', () {
    test('shows 3/3, one slot, €19, and new subtotal €126 excl. VAT', () {
      final preview = belgiumAtCapacityPreview();
      expect(preview.usedVehicles, 3);
      expect(preview.capacity, 3);
      expect(preview.additionalSlots, 1);
      expect(preview.unitExclCents, 1900);
      expect(preview.currentSubtotalExclCents, 10700);
      expect(preview.newSubtotalExclCents, 12600);
      expect(
        extraVehicleCapacityLine(languageCode: 'en', preview: preview),
        'Current capacity 3/3',
      );
      expect(
        extraVehicleAdditionalSlotLine(languageCode: 'en', preview: preview),
        '1 additional vehicle slot',
      );
      expect(
        extraVehicleUnitPriceLine(languageCode: 'en', preview: preview),
        '€19/month excl. VAT',
      );
      expect(
        extraVehicleNewSubtotalLine(languageCode: 'en', preview: preview),
        'New subtotal €126/month excl. VAT',
      );
    });

    test('checkout cannot start before explicit confirmation', () {
      final session = ExtraVehiclePurchaseSession(
        startingCapacity: 3,
        fiscal: belgianFiscal,
      );
      expect(session.tryBeginCheckout(), isFalse);
      expect(session.mayOpenVehicleCreateForm, isFalse);
      session.beginConfirmation();
      expect(session.acceptConfirmation(), isTrue);
      expect(session.phase, ExtraVehiclePurchasePhase.checkoutStarting);
    });
  });

  group('cancellation', () {
    test('cancel leaves capacity and form gate unchanged', () {
      final session = ExtraVehiclePurchaseSession(
        startingCapacity: 3,
        fiscal: belgianFiscal,
      );
      session.beginConfirmation();
      session.cancelConfirmation();
      expect(session.phase, ExtraVehiclePurchasePhase.cancelled);
      expect(session.capacity, 3);
      expect(session.subscriptionUnchanged, isTrue);
      expect(session.mayOpenVehicleCreateForm, isFalse);
      expect(session.tryBeginCheckout(), isFalse);
    });
  });

  group('upstream/payment failure', () {
    test('failed checkout does not raise capacity or open the form', () {
      final session = ExtraVehiclePurchaseSession(
        startingCapacity: 3,
        fiscal: belgianFiscal,
      );
      session.beginConfirmation();
      expect(session.acceptConfirmation(), isTrue);
      session.markUpstreamFailure();
      expect(session.phase, ExtraVehiclePurchasePhase.checkoutFailed);
      expect(session.capacity, 3);
      expect(session.subscriptionUnchanged, isTrue);
      expect(session.mayOpenVehicleCreateForm, isFalse);
    });
  });

  group('double-tap / idempotency', () {
    test('second start while checkout is in flight is ignored', () {
      final session = ExtraVehiclePurchaseSession(
        startingCapacity: 3,
        fiscal: belgianFiscal,
      );
      session.beginConfirmation();
      expect(session.acceptConfirmation(), isTrue);
      expect(session.tryBeginCheckout(), isFalse);
      expect(session.acceptConfirmation(), isFalse);
      session.markAwaitingPayment();
      expect(session.tryBeginCheckout(), isFalse);
      expect(session.capacity, 3);
      expect(session.mayOpenVehicleCreateForm, isFalse);
    });
  });

  group('capacity becomes 4 only after confirmed success', () {
    test('form opens only after activation raises capacity', () {
      final session = ExtraVehiclePurchaseSession(
        startingCapacity: 3,
        fiscal: belgianFiscal,
      );
      session.beginConfirmation();
      session.acceptConfirmation();
      session.markAwaitingPayment();
      expect(session.mayOpenVehicleCreateForm, isFalse);
      session.markActivated(newCapacity: 4);
      expect(session.capacity, 4);
      expect(session.phase, ExtraVehiclePurchasePhase.activated);
      expect(session.mayOpenVehicleCreateForm, isTrue);
    });

    test('blocked fiscal never activates a slot', () {
      final session = ExtraVehiclePurchaseSession(
        startingCapacity: 3,
        fiscal: const SubscriptionFiscalVerdict(
          missingFields: [kFiscalFieldVatNumber],
        ),
      );
      expect(
        session.beginConfirmation(),
        ExtraVehiclePurchasePhase.blockedFiscal,
      );
      expect(session.acceptConfirmation(), isFalse);
      session.markActivated(newCapacity: 4);
      expect(session.capacity, 3);
      expect(session.mayOpenVehicleCreateForm, isFalse);
    });
  });
}
