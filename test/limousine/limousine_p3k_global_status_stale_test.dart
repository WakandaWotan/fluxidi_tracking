import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_request_history.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_requests_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_status_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';

const String _statusRef = 'limqs1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM';

CustomerThemePalette get _palette =>
    paletteForCustomerTheme(CustomerThemeVariant.premiumLight);

Map<String, dynamic> _quoteJson({
  String id = 'limq_1',
  String state = 'requested',
  int revision = 1,
  bool quotationAvailable = false,
  int? quotationRevision,
  bool companyViewed = false,
  String companyViewedAt = '',
  bool acceptanceAllowed = false,
  bool withQuote = false,
  int? total,
}) {
  return <String, dynamic>{
    'quote_request_id': id,
    'state': state,
    'revision': revision,
    'locale': 'nl',
    'offer_id': 'off_1',
    'service_class_id': 'executive_sedan',
    'journey_type': 'point_to_point',
    'scheduled_pickup_iso': '2026-09-01T10:00:00Z',
    'pax': 2,
    'bags': 1,
    'acceptance_allowed': acceptanceAllowed,
    'company_viewed': companyViewed,
    if (companyViewedAt.isNotEmpty) 'company_viewed_at': companyViewedAt,
    if (quotationAvailable) 'quotation_sent_at': '2026-08-22T10:00:00Z',
    if (quotationAvailable) 'quotation_expires_at': '2099-01-01T00:00:00Z',
    if (total != null || quotationAvailable)
      'quotation_total_incl_vat_cents': total ?? 60000,
    'quotation_currency': 'EUR',
    'quotation_available': quotationAvailable,
    if (quotationRevision != null) 'quotation_revision': quotationRevision,
    if (withQuote || quotationAvailable || acceptanceAllowed)
      'quote': <String, dynamic>{
        'total_incl_vat_cents': total ?? 60000,
        'currency': 'EUR',
        'vat_treatment': 'incl',
        'quoted_at': '2026-08-22T10:00:00Z',
        'expires_at': '2099-01-01T00:00:00Z',
        'terms_revision': 3,
        'terms': <String, dynamic>{
          'terms_revision': 3,
          'cancellation_deadline_hours': 24,
          'cancellation_penalty_percent': 20,
          'waiting_time_included_minutes': 60,
          'waiting_time_overage_cents_per_minute': 150,
          'no_show_penalty_percent': 100,
          'overtime_cents_per_hour': 10000,
        },
      },
  };
}

LimousineQuoteRequest _request({
  String state = 'requested',
  int revision = 1,
  bool quotationAvailable = false,
  int? quotationRevision,
  bool companyViewed = false,
  String companyViewedAt = '',
  bool acceptanceAllowed = false,
  bool withQuote = false,
  int? total,
}) {
  return LimousineQuoteRequest.fromJson(
    _quoteJson(
      state: state,
      revision: revision,
      quotationAvailable: quotationAvailable,
      quotationRevision: quotationRevision,
      companyViewed: companyViewed,
      companyViewedAt: companyViewedAt,
      acceptanceAllowed: acceptanceAllowed,
      withQuote: withQuote,
      total: total,
    ),
  );
}

class _StatusGateway with LimousineCustomerQuoteGateway {
  _StatusGateway({this.live, this.pollError});

  LimousineQuoteRequest? live;
  Object? pollError;
  int pollCalls = 0;

  @override
  Future<List<LimousineDiscoveredProvider>> discoverNearby({
    String? postcode,
    double? lat,
    double? lng,
    int radiusKm = 20,
  }) async => const <LimousineDiscoveredProvider>[];

  @override
  Future<LimousineProviderDetail> loadProvider(String partnerId) async {
    throw const LimousineCustomerQuoteException(code: 'unused');
  }

  @override
  Future<LimousineQuoteCreateResult> createRequest(
    LimousineQuoteCreateDraft draft,
  ) async {
    throw const LimousineCustomerQuoteException(code: 'unused');
  }

  @override
  Future<LimousineQuoteRequest> pollStatus(String statusRef) async {
    pollCalls += 1;
    final error = pollError;
    if (error != null) {
      throw error is LimousineCustomerQuoteException
          ? error
          : const LimousineCustomerQuoteException(
              code: 'invalid_status_ref',
              unavailable: true,
              statusCode: 404,
            );
    }
    return live ?? _request();
  }

  @override
  Future<LimousineQuoteAcceptResult> accept({
    required String quoteRequestId,
    required int expectedRevision,
    required int termsRevision,
  }) async {
    throw const LimousineCustomerQuoteException(code: 'unused');
  }

  @override
  Future<Uint8List> fetchQuotationPdf({
    required String quoteRequestId,
    required int revision,
    required String statusRef,
  }) async => Uint8List(0);
}

LimousineCustomerRequestRecord _persistedRequested() {
  return LimousineCustomerRequestRecord(
    quoteRequestId: 'limq_1',
    statusRef: _statusRef,
    state: 'requested',
    companyName: 'Coachline',
    request: _request(),
  );
}

Widget _statusApp(LimousineCustomerQuoteController controller) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            return LimousineCustomerStatusView(
              controller: controller,
              language: appLanguageNotifier.value,
              palette: _palette,
            );
          },
        ),
      ),
    ),
  );
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    appLanguageNotifier.value = AppLanguage.nl;
  });

  test('status refresh failed copy is localized', () {
    expect(
      kLimousineCustomerStatusRefreshFailed.nl,
      'Status kon niet worden bijgewerkt. Probeer opnieuw.',
    );
    expect(
      kLimousineCustomerStatusRefreshFailed.en,
      'Status could not be updated. Try again.',
    );
    expect(
      kLimousineCustomerStatusRefreshFailed.fr,
      'Le statut n’a pas pu être mis à jour. Réessayez.',
    );
    expect(
      kLimousineCustomerStatusRefreshFailed.es,
      'No se pudo actualizar el estado. Inténtelo de nuevo.',
    );
  });

  testWidgets('1-3) persisted requested + live quoted shows CTAs', (
    tester,
  ) async {
    final gateway = _StatusGateway(
      live: _request(
        state: 'customer_acceptance_required',
        revision: 3,
        quotationAvailable: true,
        quotationRevision: 3,
        acceptanceAllowed: true,
        withQuote: true,
        total: 60000,
      ),
    );
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    controller.restorePersistedRequest(_persistedRequested());
    await tester.pumpWidget(_statusApp(controller));
    await _pump(tester);
    expect(find.text('Offerte ontvangen'), findsWidgets);
    expect(find.byKey(kLimousineCustomerViewQuotationKey), findsOneWidget);
    expect(find.byKey(kLimousineCustomerAcceptKey), findsOneWidget);
    expect(find.text('Aanvraag verzonden'), findsNothing);
    expect(find.textContaining('limqs1'), findsNothing);
    expect(controller.logSinkForTests.join(), isNot(contains('limqs1')));
    controller.dispose();
  });

  testWidgets('4) company-viewed-only shows viewed copy', (tester) async {
    final gateway = _StatusGateway(
      live: _request(
        state: 'viewed_by_company',
        revision: 2,
        companyViewed: true,
        companyViewedAt: '2026-08-22T16:47:40.608Z',
      ),
    );
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    controller.restorePersistedRequest(_persistedRequested());
    await tester.pumpWidget(_statusApp(controller));
    await _pump(tester);
    expect(find.text('Het bedrijf heeft uw aanvraag bekeken'), findsWidgets);
    expect(find.text('Aanvraag verzonden'), findsNothing);
    controller.dispose();
  });

  testWidgets('5) detail 404 is explicit retry, not requested', (tester) async {
    final gateway = _StatusGateway(
      pollError: const LimousineCustomerQuoteException(
        code: 'invalid_status_ref',
        unavailable: true,
        statusCode: 404,
      ),
    );
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    controller.restorePersistedRequest(_persistedRequested());
    await tester.pumpWidget(_statusApp(controller));
    await _pump(tester);
    expect(
      find.byKey(kLimousineCustomerStatusRefreshFailedKey),
      findsOneWidget,
    );
    expect(
      find.text('Status kon niet worden bijgewerkt. Probeer opnieuw.'),
      findsOneWidget,
    );
    expect(find.text('Aanvraag verzonden'), findsNothing);
    expect(find.textContaining('bekijkt uw aanvraag'), findsNothing);
    expect(controller.request!.state, 'requested');
    expect(controller.statusRefForTests, _statusRef);
    expect(controller.phase, LimousineCustomerQuotePhase.unavailable);
    expect(find.textContaining('limqs1'), findsNothing);
    controller.dispose();
  });

  testWidgets('6) list 404 is stale, not confirmed requested', (tester) async {
    final vault = MemoryLimousineCustomerRequestHistoryVault();
    final history = LimousineCustomerRequestHistoryRepository(vault: vault);
    await history.upsert(_persistedRequested());
    final gateway = _StatusGateway(
      pollError: const LimousineCustomerQuoteException(
        code: 'invalid_status_ref',
        unavailable: true,
        statusCode: 404,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LimousineCustomerRequestsSection(
            history: history,
            gateway: gateway,
            quoteEnabled: true,
          ),
        ),
      ),
    );
    await _pump(tester);
    expect(find.byKey(kLimousineCustomerRequestStaleKey), findsOneWidget);
    expect(find.text('Aanvraag verzonden'), findsNothing);
    expect(
      find.text('Status kon niet worden bijgewerkt. Probeer opnieuw.'),
      findsOneWidget,
    );
    expect(
      find.byKey(limousineCustomerRequestRetryKey('limq_1')),
      findsOneWidget,
    );
    expect(find.textContaining('limqs1'), findsNothing);
    final stored = await history.list();
    expect(stored.single.state, 'requested');
    expect(stored.single.statusRef, _statusRef);
    expect(jsonEncode(stored.single.toJson()).contains('%PDF'), isFalse);
  });

  testWidgets('7) retry after 404 then 200 updates quotation received', (
    tester,
  ) async {
    final gateway = _StatusGateway(
      pollError: const LimousineCustomerQuoteException(
        code: 'invalid_status_ref',
        unavailable: true,
        statusCode: 404,
      ),
    );
    DateTime now = DateTime.utc(2026, 8, 23, 6);
    final controller = LimousineCustomerQuoteController(
      gateway: gateway,
      clock: () => now,
    );
    controller.restorePersistedRequest(_persistedRequested());
    await tester.pumpWidget(_statusApp(controller));
    await _pump(tester);
    expect(
      find.byKey(kLimousineCustomerStatusRefreshFailedKey),
      findsOneWidget,
    );

    gateway
      ..pollError = null
      ..live = _request(
        state: 'customer_acceptance_required',
        revision: 3,
        quotationAvailable: true,
        quotationRevision: 3,
        acceptanceAllowed: true,
        withQuote: true,
      );
    now = now.add(const Duration(seconds: 9));
    final retry = find.text('Vernieuwen').first;
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await _pump(tester);
    expect(find.text('Offerte ontvangen'), findsWidgets);
    expect(find.byKey(kLimousineCustomerStatusRefreshFailedKey), findsNothing);
    expect(controller.statusRefreshFailed, isFalse);
    controller.dispose();
  });

  testWidgets('8-9) resume and manual refresh recover after 404', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final vault = MemoryLimousineCustomerRequestHistoryVault();
    final history = LimousineCustomerRequestHistoryRepository(vault: vault);
    await history.upsert(_persistedRequested());
    final gateway = _StatusGateway(
      pollError: const LimousineCustomerQuoteException(
        code: 'invalid_status_ref',
        unavailable: true,
        statusCode: 404,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LimousineCustomerRequestDetailPage(
          record: _persistedRequested(),
          gateway: gateway,
          history: history,
        ),
      ),
    );
    await _pump(tester);
    expect(
      find.byKey(kLimousineCustomerStatusRefreshFailedKey),
      findsOneWidget,
    );

    gateway
      ..pollError = null
      ..live = _request(
        state: 'customer_acceptance_required',
        revision: 3,
        quotationAvailable: true,
        quotationRevision: 3,
        acceptanceAllowed: true,
        withQuote: true,
      );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pump(tester);
    expect(find.text('Offerte ontvangen'), findsWidgets);
    expect(find.byKey(kLimousineCustomerViewQuotationKey), findsOneWidget);
    expect(find.byKey(kLimousineCustomerAcceptKey), findsOneWidget);

    gateway.live = _request(
      state: 'customer_acceptance_required',
      revision: 3,
      quotationAvailable: true,
      quotationRevision: 3,
      acceptanceAllowed: true,
      withQuote: true,
      total: 60000,
    );
    final refresh = find.text('Vernieuwen').last;
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await _pump(tester);
    expect(find.text('Offerte ontvangen'), findsWidgets);
    expect(find.textContaining('limqs1'), findsNothing);
  });

  testWidgets('6/7) list retry after failure becomes live quoted', (
    tester,
  ) async {
    final vault = MemoryLimousineCustomerRequestHistoryVault();
    final history = LimousineCustomerRequestHistoryRepository(vault: vault);
    await history.upsert(_persistedRequested());
    final gateway = _StatusGateway(
      pollError: const LimousineCustomerQuoteException(
        code: 'invalid_status_ref',
        unavailable: true,
        statusCode: 404,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LimousineCustomerRequestsSection(
            history: history,
            gateway: gateway,
            quoteEnabled: true,
          ),
        ),
      ),
    );
    await _pump(tester);
    expect(find.text('Aanvraag verzonden'), findsNothing);
    gateway
      ..pollError = null
      ..live = _request(
        state: 'customer_acceptance_required',
        revision: 3,
        quotationAvailable: true,
        quotationRevision: 3,
        withQuote: true,
      );
    await tester.tap(find.byKey(limousineCustomerRequestRetryKey('limq_1')));
    await _pump(tester);
    expect(find.text('Offerte ontvangen'), findsWidgets);
    expect(find.byKey(kLimousineCustomerRequestStaleKey), findsNothing);
    final stored = await history.list();
    expect(stored.single.state, 'customer_acceptance_required');
    expect(jsonEncode(stored.single.toJson()).contains('%PDF'), isFalse);
    expect(jsonEncode(stored.single.toJson()).contains('limqs1'), isTrue);
    expect(find.textContaining('limqs1'), findsNothing);
  });

  test('10-11) history snapshot never stores PDF bytes or logs the ref', () {
    final snapshot = _persistedRequested().toJson();
    expect(snapshot.containsKey('pdf'), isFalse);
    expect(jsonEncode(snapshot).contains('%PDF'), isFalse);
    expect(limousineTextLooksLikeSecret(_statusRef), isTrue);
    expect(limousineTextLooksLikeSecret('status_network'), isFalse);
  });
}
