import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';

void main() {
  test('chauffeurs screen no longer embeds the loose agenda color panel', () {
    final source = File(
      'lib/main_parts/company_driver_management_page_body.dart',
    ).readAsStringSync();
    expect(source.contains('CompanyDriverAgendaColorsPanel'), isFalse);
    expect(source.contains('CompanyDriverAgendaColorChips'), isFalse);
    expect(source.contains('_driverAgendaColorAction'), isTrue);
    expect(source.contains('CompanyDriverAgendaColorAction'), isTrue);
  });

  test('chauffeurs screen has one page title and compact account counts', () {
    final source = File(
      'lib/main_parts/company_driver_management_page_body.dart',
    ).readAsStringSync();
    expect("en: 'Manage drivers'".allMatches(source).length, 1);
    expect("nl: 'Chauffeurs beheren'".allMatches(source).length, 1);
    expect(
      source.contains('Manage drivers, documents and availability'),
      isFalse,
    );
    expect(source.contains('Currently active'), isFalse);
    expect(source.contains('Momenteel actief'), isFalse);
    expect(source.contains('_compactDriverCounts'), isTrue);
    expect(source.contains('_driverAccountStatusLabel'), isTrue);
    expect(source.contains("en: 'Active'"), isFalse);
    expect(source.contains("nl: 'Actief'"), isFalse);
  });

  test('account status labels do not suggest live availability', () {
    expect(kCompanyDriverAccountOn.of(AppLanguage.nl), 'Account actief');
    expect(kCompanyDriverAccountOn.of(AppLanguage.en), 'Account enabled');
    expect(kCompanyDriverAccountOff.of(AppLanguage.nl), 'Account uit');
    expect(kCompanyDriverAccountOff.of(AppLanguage.en), 'Account disabled');
    expect(
      kCompanyDriverAccountToggleHint.of(AppLanguage.nl),
      contains('geen online-beschikbaarheid'),
    );
    expect(
      kCompanyAgendaColorChange.of(AppLanguage.nl),
      'Agendakleur wijzigen',
    );
    expect(kCompanyAgendaColorSaved.of(AppLanguage.nl), 'Agendakleur bewaard.');
  });
}
