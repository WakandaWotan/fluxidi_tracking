import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_agenda_http.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_plan_when.dart';
import 'package:fluxidi_tracking/company/company_timezone.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';

CompanyCustomer _customer() {
  return const CompanyCustomer(
    customerId: 'cus_1',
    tenantId: 't1',
    companyId: 'c1',
    displayName: 'Ada',
    firstName: 'Ada',
    lastName: 'Lovelace',
    phone: '',
    phoneNormalized: '',
    countryCallingCode: '',
    email: '',
    locale: 'nl',
    companyName: '',
    vatNumber: '',
    addresses: <CompanyCustomerAddress>[],
    internalNotes: '',
    preferences: CompanyCustomerPreferences(),
    source: 'manual',
    status: 'active',
    createdAt: '',
    updatedAt: '',
    archivedAt: '',
    revision: 1,
  );
}

void main() {
  tearDown(debugResetCompanyPlanClock);

  test('Nu stamps when_now and never keeps epoch pickup', () {
    debugCompanyPlanClock(() => DateTime.utc(2026, 9, 15, 7, 30));
    final body = <String, dynamic>{
      'pickup_iso': '1970-01-01T00:00:00.000Z',
    };
    companyPlanApplyCreateWhenFields(
      body,
      CompanyRidePlanDraft(
        customer: _customer(),
        pickupLocal: DateTime.utc(1970),
        whenNow: true,
      ),
    );
    expect(body['when'], 'now');
    expect(body['when_now'], isTrue);
    expect(body.containsKey('pickup_iso'), isFalse);
    expect(body.toString(), isNot(contains('1970-01-01')));
  });

  test('Friday 22:00 Brussels wall clock is Friday 20:00Z, not Thursday', () {
    final later = DateTime(2026, 9, 18, 22, 0);
    expect(companyPlanPickupIso(later), '2026-09-18T20:00:00.000Z');
    final reopened = companyTimezoneUtcToLocal(
      DateTime.parse(companyPlanPickupIso(later)),
      kCompanyDefaultTimezone,
    );
    expect(reopened.year, 2026);
    expect(reopened.month, 9);
    expect(reopened.day, 18);
    expect(reopened.hour, 22);
    expect(reopened.minute, 0);
  });

  test('Later keeps the chosen Brussels-local concept as UTC iso', () {
    final later = DateTime(2026, 9, 16, 9, 15);
    final body = <String, dynamic>{};
    companyPlanApplyCreateWhenFields(
      body,
      CompanyRidePlanDraft(
        customer: _customer(),
        pickupLocal: later,
        whenNow: false,
      ),
    );
    expect(body['pickup_iso'], companyPlanPickupIso(later));
    expect(body['when_now'], isNull);
    expect(companyPlanPickupIsEpoch(later), isFalse);
  });

  test('epoch and unix-zero pickups are rejected', () {
    expect(companyPlanPickupIsEpoch(DateTime.utc(1970)), isTrue);
    expect(companyPlanPickupIsEpoch(DateTime.fromMillisecondsSinceEpoch(0)), isTrue);
    expect(companyPlanPickupIsEpoch(DateTime.utc(2026, 9, 15)), isFalse);
    final body = <String, dynamic>{'pickup_iso': 'keep'};
    companyPlanApplyCreateWhenFields(
      body,
      CompanyRidePlanDraft(
        customer: _customer(),
        pickupLocal: DateTime.utc(1970),
        whenNow: false,
      ),
    );
    expect(body.containsKey('pickup_iso'), isFalse);
  });

  test('Later before the injectable clock is invalid', () {
    final now = DateTime(2026, 3, 29, 3, 30);
    debugCompanyPlanClock(() => now);
    expect(
      companyPlanLaterPickupIsValid(DateTime(2026, 3, 29, 2, 0), now: now),
      isFalse,
    );
    expect(
      companyPlanLaterPickupIsValid(DateTime(2026, 3, 29, 4, 0), now: now),
      isTrue,
    );
  });

  test('DST spring-forward keeps a timezone-aware later pickup', () {
    final before = DateTime(2026, 3, 29, 1, 30);
    final after = before.add(const Duration(hours: 2));
    expect(companyPlanPickupIsEpoch(after), isFalse);
    expect(after.isAfter(before), isTrue);
    final fields = companyPlanWhenWireFields(
      whenNow: false,
      laterPickup: after,
    );
    expect(fields['pickup_iso'], companyPlanPickupIso(after));
    expect(fields['pickup_iso'], isNot(contains('1970')));
  });

  test('canonical duration prefers quote then route then typed text', () {
    expect(
      companyPlanCanonicalDurationMin(
        quoteDurationMin: 60,
        durationRouteMin: 45,
        durationText: '15',
      ),
      60,
    );
    expect(
      companyPlanCanonicalDurationMin(
        durationRouteMin: 45,
        durationText: '',
      ),
      45,
    );
    expect(companyPlanCanonicalDurationMin(durationText: '0'), isNull);
  });

  test('create body refuses a leftover 1970 pickup_iso', () async {
    await expectLater(
      createCompanyAgendaRide(
        draft: CompanyRidePlanDraft(
          customer: _customer(),
          pickupLocal: DateTime.utc(1970),
          fromAddress: 'Gent',
          toAddress: 'BRU',
          whenNow: false,
        ),
        idempotencyKey: 'k1',
        headers: () async => const <String, String>{},
        scopeResolver: () => const <String, String>{
          'tenant_id': 't1',
          'company_id': 'c1',
        },
      ),
      throwsA(
        isA<CompanyAgendaException>().having(
          (error) => error.code,
          'code',
          'invalid_pickup_iso',
        ),
      ),
    );
  });

  test('wait minutes are not used as ride duration', () {
    const options = CompanyRideOptions(tier: 'premium', waitMin: 60);
    expect(companyPlanCanonicalDurationMin(durationText: ''), isNull);
    expect(
      formatCompanyRideOptionsSummary(options, language: AppLanguage.nl),
      contains('wacht 60 min'),
    );
    expect(
      formatCompanyRideOptionsSummary(options, language: AppLanguage.nl),
      isNot(equals('Premium · 60 min')),
    );
  });

  test('to-airport pickup after flight departure is flagged', () {
    debugCompanyPlanClock(() => DateTime.utc(2026, 9, 15, 10, 0));
    expect(
      companyPlanFlightDepartsBeforePickup(
        flightAt: '2026-09-15T09:00:00.000Z',
        pickupLocal: DateTime.utc(2026, 9, 15, 10),
        whenNow: false,
      ),
      isTrue,
    );
    expect(
      companyPlanSuggestedToAirportPickup(
        flightAt: '2026-09-15T10:00:00.000Z',
        durationMin: 45,
      ),
      DateTime.parse('2026-09-15T10:00:00.000Z').toLocal().subtract(
        const Duration(minutes: 45),
      ),
    );
  });
}
