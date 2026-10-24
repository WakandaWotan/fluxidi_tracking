import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_crew_combo.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule.dart';
import 'package:fluxidi_tracking/company/company_plan_presence.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/company/company_plan_when.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/company/company_timezone.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

DateTime _brussels(int year, int month, int day, int hour, int minute) {
  return companyTimezoneLocalToUtc(
    DateTime(year, month, day, hour, minute),
    kCompanyDefaultTimezone,
  );
}

Map<String, dynamic> _wotan() {
  return <String, dynamic>{
    'driver_id': 'drv_wotan',
    'first_name': 'Wotan',
    'display_name': 'Wotan',
    'is_active': true,
    'preferred_vehicle_id': 'vh_cadillac',
    'linked_vehicle_ids': <String>['vh_cadillac'],
    'last_seen_at': DateTime.utc(2026, 9, 25, 12, 0).toIso8601String(),
    'availability_status': 'offline',
    'weekly_roster': <String, dynamic>{
      'explicitly_set': true,
      'timezone': kCompanyDefaultTimezone,
      'days': <String, dynamic>{
        'fri': <Map<String, dynamic>>[
          <String, dynamic>{'start': '18:00', 'end': '06:00'},
        ],
      },
    },
  };
}

Map<String, dynamic> _cadillac() {
  return <String, dynamic>{
    'vehicle_id': 'vh_cadillac',
    'name': 'Cadillac',
    'vehicle_type': 'sedan',
    'passenger_capacity': 4,
    'assigned_driver_id': 'drv_wotan',
    'is_active': true,
  };
}

CompanyDriverSchedule _fridayNight() {
  return companyDriverSchedulesFromRecords(<Map<String, dynamic>>[_wotan()])
      .values
      .single;
}

void main() {
  test('25/9 22:00 flight, 94 min and 15 min margin pick up at 20:11', () {
    final pickup = companyPlanSuggestedToAirportPickup(
      flightAt: '2026-09-25T22:00:00',
      durationMin: 94,
      arrivalMarginMin: 15,
    );
    expect(pickup, DateTime(2026, 9, 25, 20, 11));
    final start = _brussels(2026, 9, 25, 20, 11);
    final end = start.add(const Duration(minutes: 94));
    expect(
      companyDriverScheduleConflictFor(
        schedule: _fridayNight(),
        rideStartUtc: start,
        rideEndUtc: end,
      ),
      CompanyDriverScheduleConflict.none,
    );
    final combos = companyPlanCrewCombos(
      drivers: <Map<String, dynamic>>[_wotan()],
      vehicles: <Map<String, dynamic>>[_cadillac()],
      type: CompanyPlanVehicleType.sedan,
      passengers: 1,
      whenNow: false,
      rideStartUtc: start,
      rideEndUtc: end,
      schedules: companyDriverSchedulesFromRecords(
        <Map<String, dynamic>>[_wotan()],
      ),
      durationKnown: true,
    );
    expect(combos.single.suitable, isTrue);
    expect(combos.single.driverId, 'drv_wotan');
  });

  test('night shift starts at 18:00, not 17:59', () {
    final schedule = _fridayNight();
    expect(
      companyDriverScheduleConflictFor(
        schedule: schedule,
        rideStartUtc: _brussels(2026, 9, 25, 17, 59),
        rideEndUtc: _brussels(2026, 9, 25, 18, 59),
      ),
      CompanyDriverScheduleConflict.outsideWorkingHours,
    );
    expect(
      companyDriverScheduleConflictFor(
        schedule: schedule,
        rideStartUtc: _brussels(2026, 9, 25, 18, 0),
        rideEndUtc: _brussels(2026, 9, 25, 19, 0),
      ),
      CompanyDriverScheduleConflict.none,
    );
    expect(
      companyDriverScheduleConflictFor(
        schedule: schedule,
        rideStartUtc: _brussels(2026, 9, 25, 18, 1),
        rideEndUtc: _brussels(2026, 9, 25, 19, 1),
      ),
      CompanyDriverScheduleConflict.none,
    );
  });

  test('Saturday 01:00-02:00 stays inside Friday 18:00-06:00', () {
    expect(
      companyDriverScheduleConflictFor(
        schedule: _fridayNight(),
        rideStartUtc: _brussels(2026, 9, 26, 1, 0),
        rideEndUtc: _brussels(2026, 9, 26, 2, 0),
      ),
      CompanyDriverScheduleConflict.none,
    );
  });

  test('deployment ending at 06:00 fits and 06:01 does not', () {
    final schedule = _fridayNight();
    expect(
      companyDriverScheduleConflictFor(
        schedule: schedule,
        rideStartUtc: _brussels(2026, 9, 26, 5, 0),
        rideEndUtc: _brussels(2026, 9, 26, 6, 0),
      ),
      CompanyDriverScheduleConflict.none,
    );
    expect(
      companyDriverScheduleConflictFor(
        schedule: schedule,
        rideStartUtc: _brussels(2026, 9, 26, 5, 0),
        rideEndUtc: _brussels(2026, 9, 26, 6, 1),
      ),
      CompanyDriverScheduleConflict.rideEndsAfterWorkingHours,
    );
  });

  test('stale connection is not outside working hours for a later airport ride', () {
    final start = _brussels(2026, 9, 25, 20, 11);
    final end = start.add(const Duration(minutes: 94));
    final later = resolveCompanyPlanPresence(
      driver: _wotan(),
      whenNow: false,
      vehicles: <Map<String, dynamic>>[_cadillac()],
      lastSeenUtc: DateTime.utc(2026, 9, 25, 12, 0),
      nowUtc: DateTime.utc(2026, 9, 25, 14, 26),
      schedule: _fridayNight(),
      rideStartUtc: start,
      rideEndUtc: end,
      durationKnown: true,
    );
    expect(later.code, isNot('assignment_driver_outside_hours'));
    expect(later.suitable, isTrue);
    expect(
      companyPlanPresenceLabel(later, AppLanguage.nl),
      isNot('Buiten werkuren'),
    );

    final nowRide = resolveCompanyPlanPresence(
      driver: _wotan(),
      whenNow: true,
      vehicles: <Map<String, dynamic>>[_cadillac()],
      lastSeenUtc: DateTime.utc(2026, 9, 25, 12, 0),
      nowUtc: DateTime.utc(2026, 9, 25, 14, 26),
      schedule: _fridayNight(),
      rideStartUtc: start,
      rideEndUtc: end,
      durationKnown: true,
    );
    expect(nowRide.code, isNot('assignment_driver_outside_hours'));
    expect(
      companyPlanPresenceLabel(nowRide, AppLanguage.nl).toLowerCase(),
      contains('live'),
    );
  });

  test('missing duration stays unknown instead of outside hours', () {
    final presence = resolveCompanyPlanPresence(
      driver: _wotan(),
      whenNow: false,
      vehicles: <Map<String, dynamic>>[_cadillac()],
      schedule: _fridayNight(),
      rideStartUtc: _brussels(2026, 9, 25, 20, 11),
      durationKnown: false,
    );
    expect(presence.code, 'assignment_availability_unknown');
    expect(presence.tone, CompanyPlanPresenceTone.unknown);
    expect(
      companyPlanPresenceLabel(presence, AppLanguage.nl, durationKnown: false),
      isNot('Buiten werkuren'),
    );
  });

  test('map geometry 94 min is the duration used when quote and typed are empty', () {
    expect(
      companyPlanCanonicalDurationMin(geometryDurationMin: 94),
      94,
    );
  });

  test('stale quote response does not replace a newer fingerprint', () async {
    final slow = Completer<CompanyPlanQuoteResult>();
    var calls = 0;
    final coordinator = CompanyPlanQuoteCoordinator(
      transport: (request) {
        calls += 1;
        if (request.fingerprint.contains('old')) {
          return slow.future;
        }
        return Future<CompanyPlanQuoteResult>.value(
          CompanyPlanQuoteResult(
            fingerprint: request.fingerprint,
            durationMin: 94,
            priceInclVat: 200,
          ),
        );
      },
    );
    final from = LimousineAddressValue(
      displayText: 'Koekamerstraat 48A',
      canonicalLabel: 'Koekamerstraat 48A',
      lat: 50.82,
      lon: 3.64,
      placeId: 'from',
      acceptance: LimousineAddressAcceptance.selected,
    );
    final to = LimousineAddressValue(
      displayText: 'OST',
      canonicalLabel: 'OST',
      lat: 51.20,
      lon: 2.86,
      placeId: 'to',
      acceptance: LimousineAddressAcceptance.selected,
    );
    final oldRequest = companyPlanQuoteRequestFromAddresses(
      from: from,
      to: to,
      pickupLocal: DateTime(2026, 9, 24, 20, 11),
      options: const CompanyRideOptions(service: 'airport'),
      passengers: 1,
    )!;
    final newRequest = companyPlanQuoteRequestFromAddresses(
      from: from,
      to: to,
      pickupLocal: DateTime(2026, 9, 25, 20, 11),
      options: const CompanyRideOptions(service: 'airport'),
      passengers: 1,
    )!;
    expect(oldRequest.fingerprint, isNot(newRequest.fingerprint));
    final oldFuture = coordinator.quote(
      CompanyPlanQuoteRequest(
        fingerprint: 'old|${oldRequest.fingerprint}',
        body: oldRequest.body,
      ),
    );
    final latest = await coordinator.quote(
      CompanyPlanQuoteRequest(
        fingerprint: 'new|${newRequest.fingerprint}',
        body: newRequest.body,
      ),
    );
    expect(latest.durationMin, 94);
    slow.complete(
      const CompanyPlanQuoteResult(
        fingerprint: 'old',
        durationMin: 12,
        priceInclVat: 1,
      ),
    );
    await oldFuture;
    expect(coordinator.cached?.durationMin, 94);
    expect(calls, 2);
  });
}
