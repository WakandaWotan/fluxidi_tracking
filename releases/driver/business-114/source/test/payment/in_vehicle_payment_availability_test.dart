import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/payment/in_vehicle_payment_availability.dart';
import 'package:fluxidi_tracking/payment/mollie_street_checkout.dart';

void main() {
  test('10. planned booking payment options match street-ride availability', () {
    final street = resolveInVehiclePaymentMethodAvailability(
      alreadyPaid: false,
      qrConfigured: true,
      onlineCheckoutEligible: resolveInVehicleOnlineCheckoutEligible(
        bookingId: 'street_1',
        isPaid: false,
        isCancelled: false,
        amount: 9.4,
        rideType: 'direct',
      ),
    );
    final planned = resolveInVehiclePaymentMethodAvailability(
      alreadyPaid: false,
      qrConfigured: true,
      onlineCheckoutEligible: resolveInVehicleOnlineCheckoutEligible(
        bookingId: 'bk_planned',
        isPaid: false,
        isCancelled: false,
        amount: 9.4,
        kind: 'planned',
        rideType: 'planned',
      ),
    );
    expect(street.visibleMethodIds, ['online', 'qr', 'cash']);
    expect(planned.visibleMethodIds, street.visibleMethodIds);
    expect(
      hasPlannedRideMarker(bookingId: 'PLN-2026-000407', kind: 'planned'),
      isTrue,
    );
    expect(
      hasPlannedRideMarker(
        bookingId: '2026-08-199',
        rideType: 'business',
        source: 'flutter_app',
        planningReference: 'PLN-2026-000499',
      ),
      isTrue,
    );
    expect(
      resolveMollieStreetCheckoutEligible(
        bookingId: 'bk_planned',
        isPaid: false,
        isCancelled: false,
        amount: 9.4,
        kind: 'planned',
      ),
      isTrue,
    );
  });

  test('11. hosted-payment return does not invent a second charge locally', () {
    final paid = resolveInVehiclePaymentMethodAvailability(
      alreadyPaid: true,
      qrConfigured: true,
      onlineCheckoutEligible: true,
    );
    expect(paid.visibleMethodIds, isEmpty);
    expect(
      resolveInVehicleOnlineCheckoutEligible(
        bookingId: 'bk_planned',
        isPaid: true,
        isCancelled: false,
        amount: 9.4,
        kind: 'planned',
      ),
      isFalse,
    );
  });

  test('unavailable online provider fails closed with localized copy', () {
    final blocked = resolveInVehiclePaymentMethodAvailability(
      alreadyPaid: false,
      qrConfigured: true,
      onlineCheckoutEligible: false,
      onlineBlockedMessage: inVehicleOnlineUnavailableMessage(languageCode: 'nl'),
    );
    expect(blocked.online, isFalse);
    expect(blocked.qr, isTrue);
    expect(blocked.cash, isTrue);
    expect(blocked.onlineBlockedMessage, contains('niet beschikbaar'));
    expect(inVehicleOnlineUnavailableMessage(languageCode: 'fr'), isNotEmpty);
    expect(inVehicleOnlineUnavailableMessage(languageCode: 'en'), isNotEmpty);
    expect(inVehicleOnlineUnavailableMessage(languageCode: 'es'), isNotEmpty);
  });
}
