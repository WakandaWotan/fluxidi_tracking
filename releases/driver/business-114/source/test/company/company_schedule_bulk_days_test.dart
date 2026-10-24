import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule_page.dart';

void main() {
  testWidgets('bulk day presets select seven, five or two independent days', (tester) async {
    await tester.pumpWidget(MaterialApp(home: CompanyDriverSchedulePage(
      language: AppLanguage.nl,
      schedule: CompanyDriverSchedule.fromJson({'driver_id': 'test', 'timezone': 'Europe/Brussels', 'weekdays': {}})!,
      driverName: 'Test', persistenceAvailable: true,
    )));
    await tester.tap(find.text('Werkblok voor meerdere dagen'));
    await tester.pumpAndSettle();
    int selected() => tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile)).where((w) => w.value == true).length;
    expect(selected(), 5);
    await tester.tap(find.text('Hele week'));
    await tester.pumpAndSettle();
    expect(selected(), 7);
    await tester.tap(find.text('Weekend'));
    await tester.pumpAndSettle();
    expect(selected(), 2);
    await tester.tap(find.text('Weekdagen'));
    await tester.pumpAndSettle();
    expect(selected(), 5);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Maandag'));
    await tester.pumpAndSettle();
    expect(selected(), 4);
    expect(tester.takeException(), isNull);
  });
}
