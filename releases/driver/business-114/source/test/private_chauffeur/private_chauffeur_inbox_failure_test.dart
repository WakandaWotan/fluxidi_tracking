import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/private_chauffeur/private_chauffeur_quote_inbox.dart';

class FailingInbox extends MemoryPrivateChauffeurInboxGateway {
  FailingInbox() : super(items: const [PrivateChauffeurInboxItem(id: 'request', from: 'A', to: 'B', state: 'submitted')]);
  bool failLoad = false;
  bool failQuote = false;
  @override
  Future<PrivateChauffeurInboxPage> list({String? tenantId, String? companyId}) async {
    if (failLoad) throw StateError('offline');
    return super.list(tenantId: tenantId, companyId: companyId);
  }
  @override
  Future<void> sendQuote({required String quoteRequestId, required int expectedRevision, required int totalInclVatCents, String? tenantId, String? companyId}) async {
    if (failQuote) throw StateError('rejected');
    return super.sendQuote(quoteRequestId: quoteRequestId, expectedRevision: expectedRevision, totalInclVatCents: totalInclVatCents, tenantId: tenantId, companyId: companyId);
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> open(WidgetTester tester, FailingInbox gateway) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PrivateChauffeurQuoteInboxPanel(gateway: gateway))));
    await tester.tap(find.byKey(const Key('private_chauffeur_inbox_load')));
    await tester.pumpAndSettle();
  }
  testWidgets('no suggested price is sent without explicit company input', (tester) async {
    final gateway = FailingInbox();
    await open(tester, gateway);
    await tester.tap(find.byKey(const Key('private_chauffeur_inbox_quote_request')));
    await tester.pumpAndSettle();
    expect(gateway.quoteCalls, 0);
    expect(find.text('Vul eerst een geldig offertebedrag in.'), findsOneWidget);
  });
  testWidgets('load failure is visible and reload remains possible', (tester) async {
    final gateway = FailingInbox()..failLoad = true;
    await open(tester, gateway);
    expect(find.byKey(const Key('private_chauffeur_inbox_error')), findsOneWidget);
    expect(tester.takeException(), isNull);
    gateway.failLoad = false;
    await tester.tap(find.byKey(const Key('private_chauffeur_inbox_load')));
    await tester.pumpAndSettle();
    expect(find.text('A → B'), findsOneWidget);
    expect(find.byKey(const Key('private_chauffeur_inbox_error')), findsNothing);
  });
  testWidgets('quote rejection preserves input and releases busy state', (tester) async {
    final gateway = FailingInbox()..failQuote = true;
    await open(tester, gateway);
    await tester.enterText(find.byKey(const Key('private_chauffeur_inbox_cents')), '12500');
    await tester.tap(find.byKey(const Key('private_chauffeur_inbox_quote_request')));
    await tester.pumpAndSettle();
    expect(gateway.quoteCalls, 0);
    expect(find.byKey(const Key('private_chauffeur_inbox_error')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('private_chauffeur_inbox_cents'))).controller!.text, '12500');
    expect(tester.widget<FilledButton>(find.byKey(const Key('private_chauffeur_inbox_quote_request'))).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
  for (final response in [http.Response('{"ok":false}', 200), http.Response('{"ok":false}', 403)]) {
    test('HTTP ${response.statusCode} without success cannot confirm an offer', () async {
      final gateway = HttpPrivateChauffeurInboxGateway(bookingBaseUrl: 'https://booking.test', client: MockClient((_) async => response));
      await expectLater(gateway.sendQuote(quoteRequestId: 'request', expectedRevision: 1, totalInclVatCents: 12500, tenantId: 'fixture', companyId: 'fixture'), throwsA(isA<StateError>()));
    });
  }
}
