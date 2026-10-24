import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_respond_form.dart';

void main() {
  testWidgets(
    'private offer submits hourly total and frozen time and insurance terms',
    (tester) async {
      appLanguageNotifier.value = AppLanguage.nl;
      LimousineCompanyQuoteDraft? sent;
      await tester.pumpWidget(
        MaterialApp(
          home: LimousineQuoteEditorPage(
            record: const LimousineQuoteRequest(
              quoteRequestId: 'limq_hourly',
              state: 'requested',
              revision: 1,
              serviceType: 'private_chauffeur',
              fulfilment: LimousineQuoteFulfilment(
                requestedDurationMinutes: 150,
              ),
            ),
            clock: () => DateTime(2026, 10, 3),
            onSubmit: (draft) async {
              sent = draft;
            },
          ),
        ),
      );
      expect(find.byKey(kLimousineQuoteTotalFieldKey), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('private_quote_hours')))
            .controller!
            .text,
        '2.5',
      );
      await tester.enterText(
        find.byKey(const Key('private_quote_hourly')),
        '35,00',
      );
      await tester.ensureVisible(find.byKey(kLimousineQuoteVatFieldKey));
      await tester.tap(find.byKey(kLimousineQuoteVatFieldKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BTW inbegrepen').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(kLimousineQuoteSubmitKey));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(kLimousineQuoteSubmitKey))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const Key('private_quote_extra_hours')),
      );
      await tester.enterText(
        find.byKey(const Key('private_quote_extra_hours')),
        '40',
      );
      await tester.ensureVisible(find.byKey(kLimousineQuoteSubmitKey));
      await tester.pump();
      await tester.tap(find.byKey(kLimousineQuoteSubmitKey));
      await tester.pumpAndSettle();
      expect(sent, isNotNull);
      expect(sent!.totalInclVatCents, 8750);
      expect(sent!.overtimeCentsPerHour, 4000);
      expect(sent!.mobilisationDisclosure['nl'], contains('terugkomst op A'));
      expect(sent!.customerObligations['nl'], contains('verzekeraar'));
      expect(sent!.includedServices.toString(), contains('35,00'));
    },
  );
}
