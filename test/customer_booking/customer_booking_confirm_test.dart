import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_booking_metrics.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_plan_when.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_checkout.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_confirm.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote_wire.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_book_result.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_submit.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_vehicle_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

void main() {
  const pickup = LimousineAddressValue(
    displayText: 'Koekamerstraat 48A, 9688',
    canonicalLabel: 'Koekamerstraat 48A, 9688 Maarkedal',
    lat: 50.8039,
    lon: 3.6308,
    acceptance: LimousineAddressAcceptance.selected,
  );
  const dropoff = LimousineAddressValue(
    displayText: 'Louise-Marie / East Flanders / Belgium',
    canonicalLabel: 'Louise-Marie / East Flanders / Belgium',
    lat: 50.8012,
    lon: 3.6271,
    acceptance: LimousineAddressAcceptance.selected,
  );
  const quote = CompanyPlanQuoteResult(
    fingerprint: 'q-48a',
    distanceKm: 0.3,
    durationMin: 1,
    priceAvailable: true,
    priceInclVat: 6.30,
    currency: 'EUR',
  );
  final tesla = <String, dynamic>{
    'vehicle_id': 'vh_tesla',
    'name': 'Tesla',
    'vehicle_type': 'sedan',
    'passenger_capacity': 3,
    'assigned_driver_id': 'drv_chris',
  };
  final chris = <String, dynamic>{
    'driver_id': 'drv_chris',
    'first_name': 'Christophe',
  };
  final now = DateTime.utc(2026, 9, 19, 6, 24); // 08:24 Europe/Brussels CEST
  final pickupAt = DateTime(2026, 9, 19, 8, 30);

  List<CustomerBookingVehicleOffer> offers({bool available = true}) {
    return customerBookingVehicleOffers(
      vehicles: <Map<String, dynamic>>[tesla],
      drivers: <Map<String, dynamic>>[chris],
      passengers: 1,
      pickupUtc: companyPlanPickupUtc(pickupAt),
      durationMin: 1,
      availableVehicleIds: available
          ? const <String>{'vh_tesla'}
          : const <String>{},
      unavailableVehicleIds: available
          ? const <String>{}
          : const <String>{'vh_tesla'},
      proposedDriverIds: const <String, String>{'vh_tesla': 'drv_chris'},
      availabilityResolved: true,
    );
  }

  CustomerBookingConfirmDecision deviceRide({
    int? minPrepMinutes,
    LimousineAddressValue? to,
    DateTime? expiresAt,
    String? selectedVehicleId,
    bool bookPosted = false,
    CompanyPlanQuoteResult? quoteOverride,
    int? geometryDurationMin,
    num? geometryDistanceKm,
  }) {
    return customerBookingConfirmDecision(
      hasCompany: true,
      pickup: pickup,
      dropoff: to ?? dropoff,
      pickupNeedsConfirm: false,
      whenNow: false,
      pickupLocal: pickupAt,
      name: 'Christophe',
      phone: '+32469788891',
      quoteLoading: false,
      quote: quoteOverride ?? quote,
      quoteError: null,
      successId: null,
      submitting: false,
      confirmInFlight: false,
      bookPosted: bookPosted,
      bookUncertain: false,
      outboundOffers: offers(),
      selectedVehicleId: selectedVehicleId ?? 'vh_tesla',
      selectedDriverId: 'drv_chris',
      splitReturn: false,
      returnOffers: const <CustomerBookingVehicleOffer>[],
      selectedReturnVehicleId: null,
      availabilityFailed: false,
      passengers: 1,
      minPrepMinutes: minPrepMinutes,
      now: now,
      offerExpiresAt: expiresAt,
      geometryDurationMin: geometryDurationMin,
      geometryDistanceKm: geometryDistanceKm,
      selectedVehicleSeats: 3,
    );
  }

  test(
    'valid taxi input from the 19/09 08:24 device ride makes Confirm active',
    () {
      final decision = deviceRide();
      expect(decision.canConfirm, isTrue, reason: '${decision.firstFailure}');
      expect(decision.condition(kCustomerBookingIssuePickupConfirm).ok, isTrue);
      expect(decision.condition(kCustomerBookingIssueNeedPickup).ok, isTrue);
      expect(
        decision.condition(kCustomerBookingIssuePickupCoords).detail,
        contains('50.8039'),
      );
      expect(decision.condition(kCustomerBookingIssueNeedDropoff).ok, isTrue);
      expect(decision.condition(kCustomerBookingIssueDropoffCoords).ok, isTrue);
      expect(decision.condition(kCustomerBookingIssueNeedVehicle).ok, isTrue);
      expect(decision.selectedVehicleId, 'vh_tesla');
      expect(decision.selectedDriverId, 'drv_chris');
      expect(
        decision.condition(kCustomerBookingIssueNeedWhen).detail,
        contains('08:30'),
      );
      expect(customerBookingMinPrepMinutes(const <String, dynamic>{}), isNull);
    },
  );

  test('six minutes ahead with a company min prep shows the earliest time', () {
    final decision = deviceRide(minPrepMinutes: 15);
    expect(decision.canConfirm, isFalse);
    expect(decision.firstFailure?.id, kCustomerBookingIssueMinPrep);
    expect(decision.suggestedPickup, DateTime(2026, 9, 19, 8, 39));
    expect(
      customerBookingConfirmReasonText(
        decision.firstFailure!,
        AppLanguage.nl,
        suggestedPickup: decision.suggestedPickup,
      ),
      contains('08:39'),
    );
  });

  test('without a configured minimum, six minutes ahead is not blocked', () {
    expect(
      customerBookingMinPrepMinutes(const <String, dynamic>{
        'min_prep_minutes': 0,
      }),
      isNull,
    );
    expect(deviceRide().canConfirm, isTrue);
    expect(deviceRide(minPrepMinutes: 0).canConfirm, isTrue);
  });

  test(
    'incomplete destination reports the missing pin, not a silent grey button',
    () {
      const vague = LimousineAddressValue(
        displayText: 'Louise-Marie / East Flanders / Belgium',
        acceptance: LimousineAddressAcceptance.incomplete,
      );
      final decision = deviceRide(to: vague);
      expect(decision.canConfirm, isFalse);
      expect(decision.firstFailure?.id, kCustomerBookingIssueDropoffCoords);
      expect(
        customerBookingConfirmReasonText(
          decision.firstFailure!,
          AppLanguage.nl,
        ),
        contains('kaartpositie'),
      );
    },
  );

  test('an expired offer is the first blocker and keeps the input', () {
    final decision = deviceRide(expiresAt: DateTime.utc(2026, 9, 19, 6, 20));
    expect(decision.canConfirm, isFalse);
    expect(decision.firstFailure?.id, kCustomerBookingIssueOfferExpired);
    expect(
      customerBookingOfferIsExpired(
        expiresAt: DateTime.utc(2026, 9, 19, 6, 20),
        now: DateTime.utc(2026, 9, 19, 6, 24),
      ),
      isTrue,
    );
  });

  test('selected driver and vehicle ids stay on the confirm snapshot', () {
    final decision = deviceRide();
    expect(decision.selectedVehicleId, 'vh_tesla');
    expect(decision.selectedDriverId, 'drv_chris');
    expect(
      decision.condition(kCustomerBookingIssueNeedVehicle).detail,
      contains('drv_chris'),
    );
  });

  test('one in-flight confirm blocks a second book attempt', () {
    expect(
      customerBookingAllowsAnotherBookAttempt(
        submitting: false,
        confirmInFlight: true,
        successId: null,
        bookPosted: false,
        bookUncertain: false,
      ),
      isFalse,
    );
    expect(
      customerBookingAllowsAnotherBookAttempt(
        submitting: false,
        confirmInFlight: false,
        successId: null,
        bookPosted: false,
        bookUncertain: false,
      ),
      isTrue,
    );
  });

  test('a posted or uncertain /book cannot start a second /book', () {
    expect(
      customerBookingAllowsAnotherBookAttempt(
        submitting: false,
        confirmInFlight: false,
        successId: null,
        bookPosted: true,
        bookUncertain: false,
      ),
      isFalse,
    );
    expect(
      customerBookingAllowsAnotherBookAttempt(
        submitting: false,
        confirmInFlight: false,
        successId: null,
        bookPosted: false,
        bookUncertain: true,
      ),
      isFalse,
    );
    final posted = deviceRide(bookPosted: true);
    expect(posted.canConfirm, isFalse);
    expect(posted.firstFailure?.id, kCustomerBookingIssueConfirmBusy);
  });

  test('timeout is uncertain; connection refused may retry once', () {
    expect(
      customerBookingBookExceptionFromCaught(
        Exception('TimeoutException after 0:00:20'),
      ).uncertain,
      isTrue,
    );
    expect(
      customerBookingBookExceptionFromCaught(
        Exception('SocketException: Connection refused'),
      ).uncertain,
      isFalse,
    );
  });

  test('completed without a settlement stays unpaid', () {
    expect(
      customerBookingStoredPaymentStatus(
        isMollieCheckout: true,
        response: const <String, dynamic>{
          'payment_status': 'completed',
          'status': 'completed',
        },
      ),
      'pending',
    );
  });

  test('Bancontact without settlement stays unpaid', () {
    expect(
      customerBookingStoredPaymentStatus(
        isMollieCheckout: true,
        response: const <String, dynamic>{
          'payment_method': 'bancontact',
          'status': 'completed',
        },
      ),
      'pending',
    );
  });

  test(
    'sub-minute quote duration still supports confirm with visible price',
    () {
      expect(parseCompanyBookingDurationMin(0.4), 1);
      const shortQuote = CompanyPlanQuoteResult(
        fingerprint: 'short',
        distanceKm: 0.3,
        durationMin: null,
        priceAvailable: true,
        priceInclVat: 6.30,
      );
      expect(shortQuote.hasRoute, isFalse);
      expect(
        customerBookingQuoteSupportsConfirm(
          quote: shortQuote,
          geometryDurationMin: 1,
          geometryDistanceKm: 0.3,
        ),
        isTrue,
      );
      final decision = deviceRide(
        quoteOverride: shortQuote,
        geometryDurationMin: 1,
        geometryDistanceKm: 0.3,
      );
      expect(decision.canConfirm, isTrue, reason: '${decision.firstFailure}');
    },
  );
}
