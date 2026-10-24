// Proves the Uurrooster entry points exist in Chauffeursbeheer for both the
// portrait card and the compact landscape row, and that opening one carries the
// right company/driver identity and rights.
//
// The screen itself is covered by company_schedule_timezone_guard_test.dart;
// this suite is about reaching it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule_page.dart';

void main() {
  final source = File(
    'lib/main_parts/company_driver_management_page_body.dart',
  ).readAsStringSync();

  group('Chauffeursbeheer reaches the roster', () {
    test('both driver layouts mount the Uurrooster action', () {
      // Portrait card and compact landscape row each get their own button.
      expect(
        RegExp(r'companyDriverScheduleActionKey\(').allMatches(source).length,
        2,
        reason: 'expected the action in both driver layouts',
      );
      expect(
        RegExp(r'_openDriverSchedule\(context,').allMatches(source).length,
        greaterThanOrEqualTo(4),
        reason: 'card, landscape row, compact menu and edit dialog',
      );
      expect(source.contains('Icons.schedule_outlined'), isTrue);
      expect(source.contains('kCompanyDriverScheduleTitle.of('), isTrue);
      expect(source.contains('_openPortraitDriverManageSheet('), isTrue);
      expect(
        source.contains('unawaited(_openDriverSchedule(context, existing))'),
        isTrue,
      );
    });

    test('the action carries driver id, company scope and rights', () {
      expect(source.contains('final driverId = companyDriverRecordId(driver)'),
          isTrue);
      expect(source.contains('if (driverId.isEmpty) return;'), isTrue);
      // Company scope comes from the session, never from the row.
      expect(source.contains('final scope = companyOpsScope();'), isTrue);
      expect(source.contains('companyDriverScheduleCallerCanEdit('), isTrue);
      expect(source.contains('openCompanyDriverSchedulePage('), isTrue);
      expect(source.contains('fetchCompanyOpsDriverSchedule('), isTrue);
      expect(source.contains('persistenceAvailable: loaded.canPersist && canEdit'), isTrue);
    });

    test('the action key is unique per driver', () {
      expect(
        companyDriverScheduleActionKey('drv_a'),
        isNot(companyDriverScheduleActionKey('drv_b')),
      );
      expect(
        companyDriverScheduleActionKey(' drv_a '),
        companyDriverScheduleActionKey('drv_a'),
      );
    });

    test('the label is the agreed one in every language', () {
      expect(kCompanyDriverScheduleTitle.of(AppLanguage.nl), 'Uurrooster');
      expect(kCompanyDriverScheduleTitle.of(AppLanguage.en), 'Working hours');
      expect(kCompanyDriverScheduleTitle.of(AppLanguage.fr), 'Horaire');
      expect(kCompanyDriverScheduleTitle.of(AppLanguage.es), 'Horario');
    });
  });

  group('existing rights are respected', () {
    test('a company administrator manages every driver', () {
      expect(
        companyDriverScheduleCallerCanEdit(
          isCompanyAdmin: true,
          callerDriverId: '',
          targetDriverId: 'drv_other',
        ),
        isTrue,
      );
      expect(
        companyDriverScheduleCallerCanView(
          isCompanyAdmin: true,
          callerDriverId: '',
          targetDriverId: 'drv_other',
        ),
        isTrue,
      );
    });

    test('a driver may view only their own roster and never edit', () {
      expect(
        companyDriverScheduleCallerCanView(
          isCompanyAdmin: false,
          callerDriverId: 'drv_self',
          targetDriverId: 'drv_self',
        ),
        isTrue,
      );
      expect(
        companyDriverScheduleCallerCanEdit(
          isCompanyAdmin: false,
          callerDriverId: 'drv_self',
          targetDriverId: 'drv_self',
        ),
        isFalse,
      );
      expect(
        companyDriverScheduleCallerCanView(
          isCompanyAdmin: false,
          callerDriverId: 'drv_self',
          targetDriverId: 'drv_other',
        ),
        isFalse,
      );
    });

    test('an unidentified caller reaches nothing', () {
      expect(
        companyDriverScheduleCallerCanView(
          isCompanyAdmin: false,
          callerDriverId: '',
          targetDriverId: 'drv_self',
        ),
        isFalse,
      );
    });
  });
}
