// Ordered Confirm gate. First failing condition is the visible reason.

import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_plan_when.dart';
import 'package:fluxidi_tracking/company/company_timezone.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_labels.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote_wire.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_submit.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_vehicle_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

const String kCustomerBookingIssueNeedVehicle = 'need_vehicle';
const String kCustomerBookingIssueNeedReturnVehicle = 'need_return_vehicle';
const String kCustomerBookingIssuePickupCoords = 'pickup_coords';
const String kCustomerBookingIssueDropoffCoords = 'dropoff_coords';
const String kCustomerBookingIssueDropoffLocality = 'dropoff_locality';
const String kCustomerBookingIssueMinPrep = 'min_prep';
const String kCustomerBookingIssueOfferExpired = 'offer_expired';
const String kCustomerBookingIssueBookPosted = 'book_posted';
const String kCustomerBookingIssueConfirmBusy = 'confirm_busy';
const String kCustomerBookingIssuePickupConfirm = 'pickup_confirm';
const String kCustomerBookingIssueAvailabilityFailed = 'availability_failed';
const String kCustomerBookingIssueCapacity = 'capacity';

class CustomerBookingConfirmCondition {
  const CustomerBookingConfirmCondition({
    required this.id,
    required this.ok,
    required this.detail,
    this.focusKey = '',
  });

  final String id;
  final bool ok;
  final String detail;
  final String focusKey;
}

class CustomerBookingConfirmDecision {
  const CustomerBookingConfirmDecision({
    required this.conditions,
    this.suggestedPickup,
    this.selectedVehicleId = '',
    this.selectedDriverId = '',
    this.offerId = '',
    this.offerExpiresAt,
  });

  final List<CustomerBookingConfirmCondition> conditions;
  final DateTime? suggestedPickup;
  final String selectedVehicleId;
  final String selectedDriverId;
  final String offerId;
  final DateTime? offerExpiresAt;

  bool get canConfirm => firstFailure == null;

  CustomerBookingConfirmCondition? get firstFailure {
    for (final condition in conditions) {
      if (!condition.ok) return condition;
    }
    return null;
  }

  CustomerBookingConfirmCondition condition(String id) {
    return conditions.firstWhere(
      (condition) => condition.id == id,
      orElse: () =>
          CustomerBookingConfirmCondition(id: id, ok: false, detail: 'missing'),
    );
  }
}

class CustomerBookingAddressGap {
  const CustomerBookingAddressGap({required this.code, required this.detail});

  final String code;
  final String detail;
}

int? customerBookingMinPrepMinutes(Map<String, dynamic>? profile) {
  if (profile == null) return null;
  for (final key in const <String>[
    'min_prep_minutes',
    'minimum_notice_minutes',
    'booking_lead_minutes',
    'min_lead_minutes',
    'minPrepMinutes',
    'minimumNoticeMinutes',
  ]) {
    final raw = profile[key];
    if (raw == null) continue;
    if (raw is bool) continue;
    final value = raw is num
        ? raw.toInt()
        : int.tryParse(raw.toString().trim());
    if (value != null && value > 0) return value;
  }
  return null;
}

CustomerBookingAddressGap? customerBookingAddressGap(
  LimousineAddressValue value,
) {
  final text = value.displayText.trim().isEmpty
      ? value.canonicalLabel.trim()
      : value.displayText.trim();
  if (customerBookingAddressReady(value) && value.hasCoordinates) {
    return null;
  }
  if (text.isEmpty && !value.isRouteReady) {
    return const CustomerBookingAddressGap(
      code: 'empty',
      detail: 'missing_text',
    );
  }
  if (!value.hasCoordinates) {
    return const CustomerBookingAddressGap(
      code: 'no_coords',
      detail: 'missing_coordinates',
    );
  }
  if (!value.isRouteReady || !customerBookingAddressReady(value)) {
    if (limousineAddressLooksLikeLocalityOnly(text) ||
        !limousineAddressHasStreetNumber(text)) {
      return const CustomerBookingAddressGap(
        code: 'locality',
        detail: 'missing_street_or_pin',
      );
    }
    return const CustomerBookingAddressGap(
      code: 'not_ready',
      detail: 'not_selected',
    );
  }
  return null;
}

bool customerBookingOfferIsExpired({DateTime? expiresAt, DateTime? now}) {
  if (expiresAt == null) return false;
  final clock = (now ?? DateTime.now()).toUtc();
  return !clock.isBefore(expiresAt.toUtc());
}

bool customerBookingAllowsAnotherBookAttempt({
  required bool submitting,
  required bool confirmInFlight,
  required String? successId,
  required bool bookPosted,
  required bool bookUncertain,
}) {
  if (submitting || confirmInFlight) return false;
  if ((successId ?? '').trim().isNotEmpty) return false;
  if (bookPosted || bookUncertain) return false;
  return true;
}

bool customerBookingHasBookableVehicle({
  required List<CustomerBookingVehicleOffer> offers,
  required String? vehicleId,
}) {
  final id = (vehicleId ?? '').trim();
  if (id.isEmpty) return false;
  for (final offer in offers) {
    if (offer.vehicleId == id && offer.available) return true;
  }
  return false;
}

String customerBookingConfirmReasonText(
  CustomerBookingConfirmCondition failure,
  AppLanguage language, {
  DateTime? suggestedPickup,
}) {
  final suggested = suggestedPickup == null
      ? ''
      : companyPlanFormatClock(suggestedPickup);
  switch (failure.id) {
    case kCustomerBookingIssueConfirmBusy:
    case kCustomerBookingIssueAlreadyBooked:
    case kCustomerBookingIssueBookPosted:
      return kCustomerBookingBookAlreadySent.of(language);
    case kCustomerBookingIssuePickupConfirm:
      return kCustomerBookingAddressNeedsConfirm.of(language);
    case kCustomerBookingIssueNeedPickup:
      return kCustomerBookingNeedPickupField.of(language);
    case kCustomerBookingIssuePickupCoords:
      return kCustomerBookingPickupNeedsPin.of(language);
    case kCustomerBookingIssueNeedDropoff:
      return kCustomerBookingNeedDropoffField.of(language);
    case kCustomerBookingIssueDropoffCoords:
      return kCustomerBookingDropoffNeedsPin.of(language);
    case kCustomerBookingIssueDropoffLocality:
      return kCustomerBookingDropoffNeedsStreet.of(language);
    case kCustomerBookingIssueNeedCompany:
      return kCustomerBookingNeedCompany.of(language);
    case kCustomerBookingIssueNeedWhen:
      return kCustomerBookingNeedWhen.of(language);
    case kCustomerBookingIssueLaterInvalid:
      return kCustomerBookingLaterInvalid.of(language);
    case kCustomerBookingIssueMinPrep:
      return kCustomerBookingMinPrep
          .of(language)
          .replaceAll('{time}', suggested);
    case kCustomerBookingIssueNeedName:
      return kCustomerBookingNeedNameField.of(language);
    case kCustomerBookingIssueNeedPhone:
      return kCustomerBookingNeedPhoneField.of(language);
    case kCustomerBookingIssueNeedQuote:
      return kCustomerBookingNeedQuote.of(language);
    case kCustomerBookingIssuePriceFailed:
      return kCustomerBookingPriceFailed.of(language);
    case kCustomerBookingIssueNeedVehicle:
    case kCustomerBookingIssueNeedReturnVehicle:
    case kCustomerBookingIssueUnavailable:
      return kCustomerBookingNoVehicleAtTime.of(language);
    case kCustomerBookingIssueOfferExpired:
      return kCustomerBookingOfferExpired.of(language);
    case kCustomerBookingIssueAvailabilityFailed:
      return kCustomerBookingVehiclesLoadFailed.of(language);
    case kCustomerBookingIssueCapacity:
      return kCustomerBookingSuggestLarger.of(language);
    default:
      if (failure.detail.isNotEmpty && failure.detail != failure.id) {
        return customerBookingSubmitIssueText(failure.detail, language);
      }
      return customerBookingSubmitIssueText(failure.id, language);
  }
}

CustomerBookingConfirmDecision customerBookingConfirmDecision({
  required bool hasCompany,
  required LimousineAddressValue pickup,
  required LimousineAddressValue dropoff,
  required bool pickupNeedsConfirm,
  required bool whenNow,
  required DateTime? pickupLocal,
  required String name,
  required String phone,
  required bool quoteLoading,
  required CompanyPlanQuoteResult? quote,
  required String? quoteError,
  required String? successId,
  required bool submitting,
  required bool confirmInFlight,
  required bool bookPosted,
  required bool bookUncertain,
  required List<CustomerBookingVehicleOffer> outboundOffers,
  required String? selectedVehicleId,
  required String selectedDriverId,
  required bool splitReturn,
  required List<CustomerBookingVehicleOffer> returnOffers,
  required String? selectedReturnVehicleId,
  required bool availabilityFailed,
  required int passengers,
  int? minPrepMinutes,
  DateTime? now,
  DateTime? offerExpiresAt,
  String offerId = '',
  int? geometryDurationMin,
  num? geometryDistanceKm,
  int? selectedVehicleSeats,
}) {
  final conditions = <CustomerBookingConfirmCondition>[];
  void add({
    required String id,
    required bool ok,
    required String detail,
    String focusKey = '',
  }) {
    conditions.add(
      CustomerBookingConfirmCondition(
        id: id,
        ok: ok,
        detail: detail,
        focusKey: focusKey,
      ),
    );
  }

  final canAttempt = customerBookingAllowsAnotherBookAttempt(
    submitting: submitting,
    confirmInFlight: confirmInFlight,
    successId: successId,
    bookPosted: bookPosted,
    bookUncertain: bookUncertain,
  );
  add(
    id: kCustomerBookingIssueConfirmBusy,
    ok: canAttempt,
    detail: submitting || confirmInFlight
        ? 'busy'
        : ((successId ?? '').trim().isNotEmpty
              ? 'success'
              : (bookPosted || bookUncertain ? 'posted' : 'open')),
    focusKey: 'confirm',
  );

  add(
    id: kCustomerBookingIssueNeedCompany,
    ok: hasCompany,
    detail: hasCompany ? 'partner' : 'missing',
    focusKey: 'company',
  );

  add(
    id: kCustomerBookingIssuePickupConfirm,
    ok: !pickupNeedsConfirm,
    detail: pickupNeedsConfirm ? 'needs_map_confirm' : 'confirmed',
    focusKey: 'pickup',
  );

  final pickupGap = customerBookingAddressGap(pickup);
  add(
    id: kCustomerBookingIssueNeedPickup,
    ok: pickupGap == null || pickupGap.code != 'empty',
    detail: pickup.displayText,
    focusKey: 'pickup',
  );
  add(
    id: kCustomerBookingIssuePickupCoords,
    ok: pickupGap == null || pickupGap.code != 'no_coords',
    detail: pickup.hasCoordinates
        ? '${pickup.lat},${pickup.lon}'
        : 'missing_coordinates',
    focusKey: 'pickup',
  );

  final dropoffGap = customerBookingAddressGap(dropoff);
  add(
    id: kCustomerBookingIssueNeedDropoff,
    ok: dropoffGap == null || dropoffGap.code != 'empty',
    detail: dropoff.displayText,
    focusKey: 'dropoff',
  );
  add(
    id: kCustomerBookingIssueDropoffCoords,
    ok: dropoffGap == null || dropoffGap.code != 'no_coords',
    detail: dropoff.hasCoordinates
        ? '${dropoff.lat},${dropoff.lon}'
        : (dropoffGap?.detail ?? 'ok'),
    focusKey: 'dropoff',
  );
  add(
    id: kCustomerBookingIssueDropoffLocality,
    ok: dropoffGap == null || dropoffGap.code != 'locality',
    detail: dropoffGap?.detail ?? 'street_or_pin_ready',
    focusKey: 'dropoff',
  );

  DateTime? suggested;
  var whenOk = true;
  var whenCode = kCustomerBookingIssueNeedWhen;
  var whenDetail = whenNow
      ? 'now'
      : (pickupLocal?.toIso8601String() ?? 'missing');
  if (!whenNow && pickupLocal == null) {
    whenOk = false;
    whenDetail = 'missing_datetime';
  } else if (!whenNow && pickupLocal != null) {
    if (!companyPlanLaterPickupIsValid(pickupLocal, now: now)) {
      whenOk = false;
      whenCode = kCustomerBookingIssueLaterInvalid;
      whenDetail = 'past';
      suggested = companyPlanEarliestBookablePickup(
        now: now,
        minPrepMinutes: minPrepMinutes,
      );
    } else if (companyPlanLaterPickupBlockedByMinPrep(
      pickupLocal,
      now: now,
      minPrepMinutes: minPrepMinutes,
    )) {
      whenOk = false;
      whenCode = kCustomerBookingIssueMinPrep;
      whenDetail = 'min_prep_$minPrepMinutes';
      suggested = companyPlanEarliestBookablePickup(
        now: now,
        minPrepMinutes: minPrepMinutes,
      );
    } else {
      whenDetail =
          'later ${companyPlanFormatClock(pickupLocal)} tz=$kCompanyDefaultTimezone prep=${minPrepMinutes ?? 0}';
    }
  }
  add(id: whenCode, ok: whenOk, detail: whenDetail, focusKey: 'when');

  add(
    id: kCustomerBookingIssueNeedName,
    ok: name.trim().isNotEmpty,
    detail: name.trim().isEmpty ? 'missing' : 'present',
    focusKey: 'name',
  );
  add(
    id: kCustomerBookingIssueNeedPhone,
    ok: phone.trim().isNotEmpty,
    detail: phone.trim().isEmpty ? 'missing' : 'present',
    focusKey: 'phone',
  );

  add(
    id: kCustomerBookingIssueNeedQuote,
    ok:
        !quoteLoading &&
        (quoteError ?? '').trim().isEmpty &&
        customerBookingQuoteSupportsConfirm(
          quote: quote,
          geometryDurationMin: geometryDurationMin,
          geometryDistanceKm: geometryDistanceKm,
        ),
    detail: quoteLoading
        ? 'loading'
        : ((quoteError ?? '').trim().isNotEmpty
              ? quoteError!.trim()
              : (quote == null
                    ? 'missing'
                    : 'price=${quote.displayTotalPrice} km=${quote.distanceKm} min=${quote.durationMin}')),
    focusKey: 'quote',
  );
  add(
    id: kCustomerBookingIssuePriceFailed,
    ok: quote == null || !customerBookingQuotePriceFailed(quote),
    detail: quote == null ? 'none' : 'price_ok',
    focusKey: 'quote',
  );

  final expired = customerBookingOfferIsExpired(
    expiresAt: offerExpiresAt,
    now: now,
  );
  add(
    id: kCustomerBookingIssueOfferExpired,
    ok: !expired,
    detail: offerExpiresAt == null
        ? 'no_expiry'
        : (expired ? 'expired' : 'valid'),
    focusKey: 'quote',
  );
  add(
    id: kCustomerBookingIssueAvailabilityFailed,
    ok: !availabilityFailed,
    detail: availabilityFailed ? 'load_failed' : 'ok',
    focusKey: 'vehicle',
  );

  final vehicleOk = customerBookingHasBookableVehicle(
    offers: outboundOffers,
    vehicleId: selectedVehicleId,
  );
  add(
    id: kCustomerBookingIssueNeedVehicle,
    ok: vehicleOk,
    detail: vehicleOk
        ? 'vehicle=${selectedVehicleId!.trim()} driver=$selectedDriverId'
        : 'missing_or_unavailable:${selectedVehicleId ?? ''}',
    focusKey: 'vehicle',
  );
  if (splitReturn) {
    add(
      id: kCustomerBookingIssueNeedReturnVehicle,
      ok: customerBookingHasBookableVehicle(
        offers: returnOffers,
        vehicleId: selectedReturnVehicleId,
      ),
      detail: selectedReturnVehicleId ?? '',
      focusKey: 'vehicle',
    );
  }
  add(
    id: kCustomerBookingIssueCapacity,
    ok:
        selectedVehicleSeats == null ||
        selectedVehicleSeats <= 0 ||
        passengers <= selectedVehicleSeats,
    detail: 'pax=$passengers seats=${selectedVehicleSeats ?? 'unknown'}',
    focusKey: 'pax',
  );

  return CustomerBookingConfirmDecision(
    conditions: conditions,
    suggestedPickup: suggested,
    selectedVehicleId: (selectedVehicleId ?? '').trim(),
    selectedDriverId: selectedDriverId.trim(),
    offerId: offerId,
    offerExpiresAt: offerExpiresAt,
  );
}
