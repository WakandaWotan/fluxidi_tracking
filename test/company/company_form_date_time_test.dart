import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_form_date_time.dart';

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
}
