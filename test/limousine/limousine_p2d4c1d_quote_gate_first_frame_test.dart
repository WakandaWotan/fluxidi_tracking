import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_requests_nav.dart';

class _FakeGateway implements LimousineQuoteInboxGateway {
  _FakeGateway({this.pages});

  List<LimousineQuoteInboxPageData>? pages;
  int listCalls = 0;

  @override
  Future<LimousineQuoteInboxPageData> list({
    int pageSize = 20,
    String? state,
    String? cursor,
    String? updatedSince,
    String? tenantId,
    String? companyId,
  }) async {
    listCalls += 1;
    if (pages == null || pages!.isEmpty) {
      return const LimousineQuoteInboxPageData(items: []);
    }
    return pages!.first;
  }

  @override
  Future<LimousineQuoteRequest> detail(
    String quoteRequestId, {
    String? tenantId,
    String? companyId,
  }) async {
    throw const LimousineQuoteInboxException(
      kind: LimousineQuoteInboxErrorKind.invalid,
      code: 'unused',
    );
  }

  @override
  Future<LimousineQuoteRespondResult> respond({
    required String quoteRequestId,
    required String action,
    required int expectedRevision,
    Map<String, dynamic>? quote,
    LimousineDeclineDraft? decline,
    String? tenantId,
    String? companyId,
  }) async {
    throw const LimousineQuoteInboxException(
      kind: LimousineQuoteInboxErrorKind.invalid,
      code: 'unused',
    );
  }

  @override
  Future<Uint8List> fetchQuotationPdf({
    required String quoteRequestId,
    required int revision,
    String? tenantId,
    String? companyId,
  }) async {
    throw UnimplementedError();
  }
}

Widget _app(Widget child, {Size size = kLimousinePhonePortrait}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(body: child),
    ),
  );
}

void _expectComingSoonOnly() {
  expect(find.byType(LimousineQuoteGateOffPanel), findsOneWidget);
  expect(find.byKey(kLimousineQuoteInboxGateOffKey), findsOneWidget);
  expect(find.text(kLimousineQuoteGateOff.of(AppLanguage.nl)), findsOneWidget);
  expect(find.byType(LimousineQuoteInboxPage), findsNothing);
  expect(find.byKey(kLimousineQuoteInboxPageKey), findsNothing);
  expect(find.byKey(kLimousineQuoteInboxHeroKey), findsNothing);
  expect(find.byKey(kLimousineQuoteInboxLoadingKey), findsNothing);
  expect(find.byKey(kLimousineQuoteInboxEmptyKey), findsNothing);
  expect(find.byKey(kLimousineQuoteInboxListKey), findsNothing);
  expect(find.byKey(kLimousineQuoteInboxSearchKey), findsNothing);
  expect(find.textContaining('@'), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    appLanguageNotifier.value = AppLanguage.nl;
    businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
  });

  test(
    'compile-time quote gates stay off unless an APK dart-define enables them',
    () {
      expect(kLimousineCustomerQuoteGateEnabled, isFalse);
      expect(kLimousineCustomerManualQuoteGateEnabled, isFalse);
      expect(limousineQuoteInboxRuntimeEnabled(), isFalse);
    },
  );

  test(
    'gate off builds the coming-soon panel without constructing the inbox',
    () {
      final gateway = _FakeGateway();
      final body = limousineQuoteRequestsBody(
        runtimeEnabled: false,
        gateway: gateway,
      );
      expect(body, isA<LimousineQuoteGateOffPanel>());
      expect(body, isNot(isA<LimousineQuoteInboxPage>()));
      expect(gateway.listCalls, 0);
    },
  );

  test('gate on is the only path that constructs the tenant-scoped inbox', () {
    final gateway = _FakeGateway();
    final body = limousineQuoteRequestsBody(
      runtimeEnabled: true,
      gateway: gateway,
    );
    expect(body, isA<LimousineQuoteInboxPage>());
    final page = body as LimousineQuoteInboxPage;
    expect(page.embedded, isTrue);
    expect(page.gateway, same(gateway));
    expect(gateway.listCalls, 0);
  });

  testWidgets('1 gate off: first frame is only the coming-soon message', (
    tester,
  ) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      _app(limousineQuoteRequestsBody(runtimeEnabled: false, gateway: gateway)),
    );
    _expectComingSoonOnly();
    expect(gateway.listCalls, 0);
  });

  testWidgets('2-3 gate off: no inbox page and quote client is not called', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      pages: const [LimousineQuoteInboxPageData(items: [])],
    );
    await tester.pumpWidget(
      _app(limousineQuoteRequestsBody(runtimeEnabled: false, gateway: gateway)),
    );
    expect(find.byType(LimousineQuoteInboxPage), findsNothing);
    expect(gateway.listCalls, 0);
  });

  testWidgets('4 gate off: later pumps keep the same stable message', (
    tester,
  ) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      _app(limousineQuoteRequestsBody(runtimeEnabled: false, gateway: gateway)),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      _expectComingSoonOnly();
      expect(gateway.listCalls, 0);
    }
  });

  testWidgets(
    '5 bookings to quote-requests has no interstitial inbox or bookings form',
    (tester) async {
      final gateway = _FakeGateway(
        pages: const [LimousineQuoteInboxPageData(items: [])],
      );
      var section = LimousineBookingsSection.bookings;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              return LimousineBookingsSectionHost(
                quoteRequestsVisible: true,
                section: section,
                onSectionChanged: (next) => setState(() => section = next),
                bookings: const Text('EXISTING_BOOKINGS_LIST'),
                quoteRequests: limousineQuoteRequestsBody(
                  runtimeEnabled: false,
                  gateway: gateway,
                ),
              );
            },
          ),
        ),
      );
      expect(find.text('EXISTING_BOOKINGS_LIST'), findsOneWidget);
      expect(find.byType(LimousineQuoteInboxPage), findsNothing);
      expect(find.byKey(kLimousineQuoteInboxGateOffKey), findsNothing);
      expect(gateway.listCalls, 0);

      await tester.tap(find.byKey(kLimousineQuoteRequestsSectionTabKey));
      await tester.pump();
      _expectComingSoonOnly();
      expect(find.text('EXISTING_BOOKINGS_LIST'), findsNothing);
      expect(gateway.listCalls, 0);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      _expectComingSoonOnly();
      expect(gateway.listCalls, 0);
    },
  );

  testWidgets('6 gate on builds the real inbox only after the flag is on', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      pages: const [LimousineQuoteInboxPageData(items: [])],
    );
    var enabled = false;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            return Column(
              children: [
                TextButton(
                  onPressed: () => setState(() => enabled = true),
                  child: const Text('ENABLE_QUOTE_GATE'),
                ),
                Expanded(
                  child: limousineQuoteRequestsBody(
                    runtimeEnabled: enabled,
                    gateway: gateway,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    _expectComingSoonOnly();
    expect(gateway.listCalls, 0);

    await tester.tap(find.text('ENABLE_QUOTE_GATE'));
    await tester.pump();
    expect(find.byType(LimousineQuoteInboxPage), findsOneWidget);
    expect(find.byKey(kLimousineQuoteInboxPageKey), findsOneWidget);
    expect(find.byType(LimousineQuoteGateOffPanel), findsNothing);
  });

  testWidgets('7 bookings tab does not regress when the quote tab exists', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      pages: const [LimousineQuoteInboxPageData(items: [])],
    );
    var section = LimousineBookingsSection.bookings;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            return LimousineBookingsSectionHost(
              quoteRequestsVisible: true,
              section: section,
              onSectionChanged: (next) => setState(() => section = next),
              bookings: const Text('EXISTING_BOOKINGS_LIST'),
              quoteRequests: limousineQuoteRequestsBody(
                runtimeEnabled: false,
                gateway: gateway,
              ),
            );
          },
        ),
      ),
    );
    expect(find.byKey(kLimousineBookingsQuoteSwitchKey), findsOneWidget);
    expect(find.text('EXISTING_BOOKINGS_LIST'), findsOneWidget);
    expect(find.byType(LimousineQuoteInboxPage), findsNothing);
    expect(gateway.listCalls, 0);

    await tester.tap(find.byKey(kLimousineQuoteRequestsSectionTabKey));
    await tester.pump();
    await tester.tap(find.byKey(kLimousineBookingsSectionTabKey));
    await tester.pump();
    expect(find.text('EXISTING_BOOKINGS_LIST'), findsOneWidget);
    expect(find.byKey(kLimousineQuoteInboxGateOffKey), findsNothing);
    expect(find.byType(LimousineQuoteInboxPage), findsNothing);
    expect(gateway.listCalls, 0);
  });
}
