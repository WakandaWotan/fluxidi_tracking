import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_presence.dart';

void main() {
  CompanyPlanPresence presence(String code, CompanyPlanPresenceTone tone) {
    return CompanyPlanPresence(
      tone: tone,
      code: code,
      icon: Icons.event_busy_outlined,
    );
  }

  test('planner availability reasons stay distinct', () {
    const lang = AppLanguage.nl;
    final unknown = companyPlanPresenceLabel(
      presence('available', CompanyPlanPresenceTone.unknown),
      lang,
      durationKnown: false,
    );
    final notLive = companyPlanPresenceLabel(
      presence('assignment_driver_not_live', CompanyPlanPresenceTone.blocked),
      lang,
    );
    final outside = companyPlanPresenceLabel(
      presence('assignment_driver_outside_hours', CompanyPlanPresenceTone.blocked),
      lang,
    );
    final busy = companyPlanPresenceLabel(
      presence('assignment_vehicle_busy', CompanyPlanPresenceTone.busy),
      lang,
    );
    expect(unknown, isNot(notLive));
    expect(unknown, isNot(outside));
    expect(unknown, isNot(busy));
    expect(notLive, isNot(outside));
    expect(notLive, isNot(busy));
    expect(outside, isNot(busy));
    expect(unknown.toLowerCase(), contains('niet'));
    expect(notLive.toLowerCase(), contains('live'));
    expect(outside, 'Buiten werkuren');
    expect(busy, 'Voertuig bezet');
  });
}
