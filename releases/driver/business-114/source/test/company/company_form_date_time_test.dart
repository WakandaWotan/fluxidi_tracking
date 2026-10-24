import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_form_date_time.dart';
import 'package:fluxidi_tracking/company/company_plan_when.dart';
import 'package:fluxidi_tracking/company/company_timezone.dart';

void main() {
  test('form date and time never render an ISO timestamp', () {
    final local = DateTime(2026, 9, 8, 14, 0);
    expect(formatCompanyFormDate(local, AppLanguage.nl), '8 september 2026');
    expect(formatCompanyFormTime(local), '14:00');
    expect(formatCompanyFormDateTime(local, AppLanguage.nl).contains('T'), isFalse);
    expect(companyFormLooksLikeIsoTimestamp('2026-09-08T12:00:00.000Z'), isTrue);
  });

  test('typed local date and time parse without keeping ISO in the field', () {
    final date = parseCompanyFormDate('8/9/2026', AppLanguage.nl);
    expect(date, DateTime(2026, 9, 8));
    expect(parseCompanyFormTime('14:00'), const TimeOfDay(hour: 14, minute: 0));
    final fromIso = parseCompanyFormDate('2026-09-08T12:00:00.000Z', AppLanguage.nl);
    expect(fromIso?.year, 2026);
    expect(fromIso?.month, 9);
  });

  testWidgets('cancelling a picker keeps the previous value', (tester) async {
    var value = DateTime(2026, 9, 8, 14, 0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyDateTimeFields(
            fieldId: 'quote_start',
            language: AppLanguage.nl,
            value: value,
            onChanged: (next) => value = next ?? value,
          ),
        ),
      ),
    );
    expect(find.text('8 september 2026'), findsOneWidget);
    expect(find.text('14:00'), findsOneWidget);
    await tester.tap(find.byKey(companyFormDateIconKey('quote_start')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(value, DateTime(2026, 9, 8, 14, 0));
    expect(find.text('8 september 2026'), findsOneWidget);
    await tester.tap(find.byKey(companyFormDateFieldKey('quote_start')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(value, DateTime(2026, 9, 8, 14, 0));
    await tester.tap(find.byKey(companyFormTimeFieldKey('quote_start')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(value, DateTime(2026, 9, 8, 14, 0));
    expect(find.text('14:00'), findsOneWidget);
  });

  testWidgets('changing the date via the form sends, stores and reopens the same day', (
    tester,
  ) async {
    var value = DateTime(2026, 9, 17, 22, 0);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('nl'),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return CompanyDateTimeFields(
                fieldId: 'agenda_pickup',
                language: AppLanguage.nl,
                value: value,
                firstDate: DateTime(2026, 9, 17),
                onChanged: (next) => setState(() => value = next ?? value),
              );
            },
          ),
        ),
      ),
    );
    expect(find.text('17 september 2026'), findsOneWidget);
    await tester.tap(find.byKey(companyFormDateIconKey('agenda_pickup')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('18'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(value.year, 2026);
    expect(value.month, 9);
    expect(value.day, 18);
    expect(value.hour, 22);
    expect(companyPlanPickupIso(value), '2026-09-18T20:00:00.000Z');
    final reopened = companyTimezoneUtcToLocal(
      DateTime.parse(companyPlanPickupIso(value)),
      kCompanyDefaultTimezone,
    );
    expect(reopened.day, 18);
    expect(reopened.hour, 22);
    expect(find.text('18 september 2026'), findsOneWidget);
  });

  testWidgets('Nu to Later keeps a valid later wall clock that can cross midnight', (
    tester,
  ) async {
    debugCompanyPlanClock(() => DateTime(2026, 9, 17, 21, 30));
    addTearDown(debugResetCompanyPlanClock);
    var whenNow = true;
    DateTime? later;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        whenNow = false;
                        later = DateTime(2026, 9, 17, 23, 30);
                      });
                    },
                    child: const Text('Later'),
                  ),
                  if (!whenNow)
                    CompanyDateTimeFields(
                      fieldId: 'later_midnight',
                      language: AppLanguage.nl,
                      value: later,
                      onChanged: (next) => setState(() => later = next),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(companyFormTimeFieldKey('later_midnight')),
      '00:15',
    );
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(later, isNotNull);
    expect(later!.year, 2026);
    expect(later!.month, 9);
    expect(later!.day, 17);
    expect(later!.hour, 0);
    expect(later!.minute, 15);
    expect(companyPlanPickupIso(later!), '2026-09-16T22:15:00.000Z');
    final overnight = DateTime(2026, 9, 17, 23, 30);
    expect(companyPlanPickupIso(overnight), '2026-09-17T21:30:00.000Z');
    expect(
      DateTime.parse(companyPlanPickupIso(overnight)).add(
        const Duration(minutes: 90),
      ).toIso8601String(),
      '2026-09-17T23:00:00.000Z',
    );
  });
}
