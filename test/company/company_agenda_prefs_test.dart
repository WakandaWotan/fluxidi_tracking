import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_agenda_calendar.dart';
import 'package:fluxidi_tracking/company/company_agenda_prefs.dart';

void main() {
  setUp(resetCompanyAgendaPrefsForTest);

  test('hour density prefs round-trip compact and spacious', () {
    expect(parseCompanyAgendaHourDensity(null), CompanyAgendaHourDensity.compact);
    expect(parseCompanyAgendaHourDensity(''), CompanyAgendaHourDensity.compact);
    expect(
      parseCompanyAgendaHourDensity('spacious'),
      CompanyAgendaHourDensity.spacious,
    );
    expect(
      serializeCompanyAgendaHourDensity(CompanyAgendaHourDensity.spacious),
      'spacious',
    );
    expect(
      serializeCompanyAgendaHourDensity(CompanyAgendaHourDensity.compact),
      'compact',
    );
  });
}
