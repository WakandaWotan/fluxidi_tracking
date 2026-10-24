import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_address_field.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_form_date_time.dart';
import 'package:fluxidi_tracking/company/company_roundtrip.dart';
import 'package:fluxidi_tracking/company/company_roundtrip_fields.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

void main() {
  testWidgets('waiting return hides return date/time and shows wait presets', (
    tester,
  ) async {
    final lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async {
        return const LimousinePlaceLookupResult(
          suggestions: <LimousinePlaceSuggestion>[],
        );
      },
    );
    final to = LimousineAddressFieldController(lookup: lookup, fieldId: 'rt');
    addTearDown(to.dispose);
    var wait = 45;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return CompanyRoundtripFields(
                language: AppLanguage.nl,
                choice: CompanyRoundtripChoice.continuousWait,
                onChoiceChanged: (_) {},
                returnPickup: DateTime(2026, 9, 16, 18),
                onReturnPickupChanged: (_) {},
                returnTo: to,
                waitMin: wait,
                onWaitMinChanged: (next) => setState(() => wait = next),
              );
            },
          ),
        ),
      ),
    );
    expect(find.byKey(companyFormDateFieldKey('roundtrip_return')), findsNothing);
    expect(find.byKey(companyFormTimeFieldKey('roundtrip_return')), findsNothing);
    expect(find.byKey(kCompanyRoundtripWaitKey), findsOneWidget);
    expect(find.text('Chauffeur wacht ongeveer 45 minuten'), findsOneWidget);
    await tester.tap(find.byKey(companyRoundtripWaitPresetKey(30)));
    await tester.pumpAndSettle();
    expect(wait, 30);
    expect(find.text('Chauffeur wacht ongeveer 30 minuten'), findsOneWidget);
    expect(find.byKey(kCompanyRoundtripReturnToKey), findsOneWidget);
    expect(find.text(kCompanySavedAddresses.of(AppLanguage.nl)), findsNothing);
  });

  testWidgets('split return still shows its own date and time', (tester) async {
    final lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async {
        return const LimousinePlaceLookupResult(
          suggestions: <LimousinePlaceSuggestion>[],
        );
      },
    );
    final to = LimousineAddressFieldController(lookup: lookup, fieldId: 'rt');
    addTearDown(to.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyRoundtripFields(
            language: AppLanguage.nl,
            choice: CompanyRoundtripChoice.splitNoWait,
            onChoiceChanged: (_) {},
            returnPickup: DateTime(2026, 9, 16, 18),
            onReturnPickupChanged: (_) {},
            returnTo: to,
          ),
        ),
      ),
    );
    expect(find.byKey(companyFormDateFieldKey('roundtrip_return')), findsOneWidget);
    expect(find.byKey(companyFormTimeFieldKey('roundtrip_return')), findsOneWidget);
    expect(find.byKey(kCompanyRoundtripWaitKey), findsNothing);
    expect(find.text(kCompanyAgendaWaitTime.of(AppLanguage.nl)), findsNothing);
  });

  test('waiting return reuses outbound duration instead of an empty return field', () {
    expect(
      companyPlanReturnDurationMin(
        choice: CompanyRoundtripChoice.continuousWait,
        outboundDurationMin: 72,
        returnDurationText: '',
      ),
      72,
    );
    expect(
      companyPlanReturnDurationMin(
        choice: CompanyRoundtripChoice.splitNoWait,
        outboundDurationMin: 72,
        returnDurationText: '40',
      ),
      40,
    );
    expect(
      companyPlanReturnDurationMin(
        choice: CompanyRoundtripChoice.splitNoWait,
        outboundDurationMin: 72,
        quotedReturnDurationMin: 41,
        returnDurationText: '',
      ),
      41,
    );
    expect(
      companyPlanReturnDurationMin(
        choice: CompanyRoundtripChoice.splitNoWait,
        outboundDurationMin: 72,
        returnDurationText: '',
      ),
      72,
    );
  });
}
