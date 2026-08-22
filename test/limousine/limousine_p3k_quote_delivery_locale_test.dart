import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_request_history.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_requests_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_status_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_detail_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_respond_form.dart';

const String _statusRef = 'limqs1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM';
const String _acceptRef = 'limacc1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM';

final Uint8List _pdfBytes = Uint8List.fromList(
  '%PDF-1.1\n1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n%%EOF'.codeUnits,
);

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
  String quotationSentAt = '',
  String quotationExpiresAt = '',
  int? quotationTotalInclVatCents,
  bool acceptanceAllowed = false,
  bool withQuote = false,
  String locale = 'nl',
}) {
  return <String, dynamic>{
    'quote_request_id': id,
    'state': state,
    'revision': revision,
    'locale': locale,
    'offer_id': 'off_1',
    'service_class_id': 'executive_sedan',
    'journey_type': 'point_to_point',
    'scheduled_pickup_iso': '2026-09-01T10:00:00Z',
    'pax': 2,
    'bags': 1,
    'acceptance_allowed': acceptanceAllowed,
    'company_viewed': companyViewed,
    if (companyViewedAt.isNotEmpty) 'company_viewed_at': companyViewedAt,
    if (quotationSentAt.isNotEmpty) 'quotation_sent_at': quotationSentAt,
    if (quotationExpiresAt.isNotEmpty)
      'quotation_expires_at': quotationExpiresAt,
    if (quotationTotalInclVatCents != null)
      'quotation_total_incl_vat_cents': quotationTotalInclVatCents,
    'quotation_currency': 'EUR',
    'quotation_available': quotationAvailable,
    if (quotationRevision != null) 'quotation_revision': quotationRevision,
    if (withQuote)
      'quote': <String, dynamic>{
        'total_incl_vat_cents': quotationTotalInclVatCents ?? 18500,
        'currency': 'EUR',
        'vat_treatment': 'incl',
        'quoted_at': quotationSentAt.isEmpty
            ? '2026-08-22T10:00:00Z'
            : quotationSentAt,
        'expires_at': quotationExpiresAt.isEmpty
            ? '2099-01-01T00:00:00Z'
            : quotationExpiresAt,
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
  String locale = 'nl',
}) {
  return LimousineQuoteRequest.fromJson(
    _quoteJson(
      state: state,
      revision: revision,
      quotationAvailable: quotationAvailable,
      quotationRevision: quotationRevision,
      companyViewed: companyViewed,
      companyViewedAt: companyViewedAt,
      quotationSentAt: quotationAvailable ? '2026-08-22T10:00:00Z' : '',
      quotationExpiresAt: quotationAvailable ? '2099-01-01T00:00:00Z' : '',
      quotationTotalInclVatCents: total ?? (quotationAvailable ? 18500 : null),
      acceptanceAllowed: acceptanceAllowed,
      withQuote: withQuote || quotationAvailable || acceptanceAllowed,
      locale: locale,
    ),
  );
}

class _StatusGateway with LimousineCustomerQuoteGateway {
  _StatusGateway({this.live, this.pdfBytes, this.pollError, this.pollDelay});

  LimousineQuoteRequest? live;
  Uint8List? pdfBytes;
  Object? pollError;
  Completer<void>? pollDelay;
  int pollCalls = 0;
  int overlapping = 0;
  int maxOverlapping = 0;
  Map<String, String>? lastPdf;
  Map<String, dynamic>? lastAccept;

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
    overlapping += 1;
    if (overlapping > maxOverlapping) maxOverlapping = overlapping;
    final waiter = pollDelay;
    if (waiter != null) await waiter.future;
    overlapping -= 1;
    final error = pollError;
    if (error != null) {
      throw error is LimousineCustomerQuoteException
          ? error
          : const LimousineCustomerQuoteException(code: 'network');
    }
    return live ?? _request();
  }

  @override
  Future<LimousineQuoteAcceptResult> accept({
    required String quoteRequestId,
    required int expectedRevision,
    required int termsRevision,
  }) async {
    lastAccept = <String, dynamic>{
      'quote_request_id': quoteRequestId,
      'expected_revision': expectedRevision,
      'terms_revision': termsRevision,
    };
    return LimousineQuoteAcceptResult(
      request: _request(
        state: 'accepted',
        revision: expectedRevision,
        quotationAvailable: true,
        quotationRevision: 3,
        withQuote: true,
        total: 18500,
      ),
      acceptanceReference: _acceptRef,
    );
  }

  @override
  Future<Uint8List> fetchQuotationPdf({
    required String quoteRequestId,
    required int revision,
    required String statusRef,
  }) async {
    lastPdf = <String, String>{
      'quote_request_id': quoteRequestId,
      'revision': '$revision',
      'status_ref': statusRef,
    };
    return pdfBytes ?? _pdfBytes;
  }
}

class _InboxGateway implements LimousineQuoteInboxGateway {
  _InboxGateway(
    this.record, {
    LimousineQuoteRequest? listRecord,
    this.staleQuoteBelow,
  }) : listRecord = listRecord ?? record;

  LimousineQuoteRequest record;
  LimousineQuoteRequest listRecord;
  int? staleQuoteBelow;
  final List<String> actions = <String>[];
  final List<int> quoteRevisions = <int>[];

  @override
  Future<LimousineQuoteInboxPageData> list({
    int pageSize = kLimousineQuoteInboxPageDefault,
    String? state,
    String? cursor,
    String? updatedSince,
    String? tenantId,
    String? companyId,
  }) async {
    return LimousineQuoteInboxPageData(
      items: <LimousineQuoteRequest>[listRecord],
    );
  }

  @override
  Future<LimousineQuoteRequest> detail(
    String quoteRequestId, {
    String? tenantId,
    String? companyId,
  }) async {
    return record;
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
    actions.add(action);
    if (action == 'viewed') {
      record = LimousineQuoteRequest.fromJson(
        _quoteJson(
          id: quoteRequestId,
          state: 'viewed_by_company',
          revision: expectedRevision + 1,
          companyViewed: true,
          companyViewedAt: '2026-08-22T10:05:00Z',
        ),
      );
      listRecord = record;
    }
    if (action == 'quote') {
      quoteRevisions.add(expectedRevision);
      final staleBelow = staleQuoteBelow;
      if (staleBelow != null && expectedRevision < staleBelow) {
        throw LimousineQuoteInboxException(
          kind: LimousineQuoteInboxErrorKind.staleRevision,
          code: 'stale_revision',
          currentRevision: record.revision,
        );
      }
      record = _request(
        state: 'customer_acceptance_required',
        revision: expectedRevision + 2,
        quotationAvailable: true,
        quotationRevision: expectedRevision + 2,
        companyViewed: true,
        companyViewedAt: '2026-08-22T10:05:00Z',
        acceptanceAllowed: true,
        withQuote: true,
      );
      listRecord = record;
    }
    return LimousineQuoteRespondResult(record: record);
  }

  @override
  Future<Uint8List> fetchQuotationPdf({
    required String quoteRequestId,
    required int revision,
    String? tenantId,
    String? companyId,
  }) async => _pdfBytes;
}

class _PdfClient extends http.BaseClient {
  Uri? uri;
  Map<String, String> headers = const <String, String>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    uri = request.url;
    headers = Map<String, String>.from(request.headers);
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[_pdfBytes]),
      200,
      headers: const {'content-type': 'application/pdf'},
    );
  }
}

Widget _statusApp(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Widget _liveStatus(
  LimousineCustomerQuoteController controller, {
  AppLanguage language = AppLanguage.nl,
}) {
  return _statusApp(
    ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return LimousineCustomerStatusView(
          controller: controller,
          language: language,
          palette: _palette,
        );
      },
    ),
  );
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _largeSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _fillAndSubmitCompanyQuote(WidgetTester tester) async {
  await tester.enterText(find.byKey(kLimousineQuoteTotalFieldKey), '185,00');
  await tester.pump();
  await tester.ensureVisible(find.byKey(kLimousineQuoteVatFieldKey));
  await tester.tap(find.byKey(kLimousineQuoteVatFieldKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text('BTW inbegrepen').last);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(kLimousineQuoteSubmitKey));
  await tester.tap(find.byKey(kLimousineQuoteSubmitKey));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    appLanguageNotifier.value = AppLanguage.nl;
  });

  test('25-28) customer lifecycle labels', () {
    expect(
      limousineCustomerStateLabel('requested', AppLanguage.nl),
      'Aanvraag verzonden',
    );
    expect(
      limousineCustomerStateLabel('requested', AppLanguage.en),
      'Request sent',
    );
    expect(
      limousineCustomerStateLabel('requested', AppLanguage.fr),
      'Demande envoyée',
    );
    expect(
      limousineCustomerStateLabel('requested', AppLanguage.es),
      'Solicitud enviada',
    );
    expect(
      limousineCustomerStateLabel('viewed_by_company', AppLanguage.nl),
      'Het bedrijf heeft uw aanvraag bekeken',
    );
    expect(
      limousineCustomerStateLabel(
        'customer_acceptance_required',
        AppLanguage.nl,
      ),
      'Offerte ontvangen',
    );
    expect(
      limousineCustomerStateLabel('accepted', AppLanguage.nl),
      'Offerte geaccepteerd',
    );
    expect(
      limousineCustomerStateLabel('booking_created', AppLanguage.nl),
      'Boeking aangemaakt',
    );
    expect(kLimousineQuoteSendSuccessTitle.nl, 'Offerte verstuurd');
  });

  testWidgets('1-9) requested, viewed, quotation received and CTAs', (
    tester,
  ) async {
    final gateway = _StatusGateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    controller.request = _request();
    await tester.pumpWidget(_liveStatus(controller));
    await _pump(tester);
    expect(find.text('Aanvraag verzonden'), findsWidgets);
    expect(find.textContaining('bekijkt uw aanvraag'), findsOneWidget);
    expect(find.byKey(kLimousineCustomerViewQuotationKey), findsNothing);

    controller.request = _request(
      state: 'viewed_by_company',
      revision: 2,
      companyViewed: true,
      companyViewedAt: '2026-08-22T10:05:00Z',
    );
    controller.notifyListeners();
    await _pump(tester);
    expect(find.text('Het bedrijf heeft uw aanvraag bekeken'), findsWidgets);
    expect(find.byKey(kLimousineCustomerViewedAtKey), findsOneWidget);

    controller.request = _request(
      state: 'customer_acceptance_required',
      revision: 4,
      quotationAvailable: true,
      quotationRevision: 4,
      companyViewed: true,
      companyViewedAt: '2026-08-22T10:05:00Z',
      acceptanceAllowed: true,
      withQuote: true,
    );
    controller.notifyListeners();
    await _pump(tester);
    expect(find.text('Offerte ontvangen'), findsWidgets);
    expect(find.byKey(kLimousineCustomerQuoteSentAtKey), findsOneWidget);
    expect(find.byKey(kLimousineCustomerQuoteExpiresAtKey), findsOneWidget);
    expect(find.byKey(kLimousineCustomerQuoteTotalKey), findsOneWidget);
    expect(find.byKey(kLimousineCustomerViewQuotationKey), findsOneWidget);
    expect(find.byKey(kLimousineCustomerAcceptKey), findsOneWidget);
    controller.dispose();
  });

  test('10-15) PDF and accept use revision, status ref, and limacc1', () async {
    final gateway = _StatusGateway(
      pdfBytes: _pdfBytes,
      live: _request(
        state: 'customer_acceptance_required',
        revision: 4,
        quotationAvailable: true,
        quotationRevision: 4,
        acceptanceAllowed: true,
        withQuote: true,
      ),
    );
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    controller.restorePersistedRequest(
      LimousineCustomerRequestRecord(
        quoteRequestId: 'limq_1',
        statusRef: _statusRef,
        state: 'customer_acceptance_required',
        request: gateway.live,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final bytes = await controller.loadQuotationPdf();
    expect(bytes, isNotEmpty);
    expect(gateway.lastPdf!['revision'], '4');
    expect(gateway.lastPdf!['status_ref'], _statusRef);
    controller.termsAcknowledged = true;
    final accepted = await controller.acceptCurrentQuote();
    expect(accepted, isTrue);
    expect(gateway.lastAccept!['expected_revision'], 4);
    expect(controller.handoff?.acceptanceReference, _acceptRef);
    expect(controller.request!.quotationAvailable, isTrue);
    controller.dispose();
  });

  testWidgets('10-15) view and accept CTAs remain tappable', (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _StatusGateway(
      pdfBytes: _pdfBytes,
      live: _request(
        state: 'customer_acceptance_required',
        revision: 4,
        quotationAvailable: true,
        quotationRevision: 4,
        acceptanceAllowed: true,
        withQuote: true,
      ),
    );
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    controller.restorePersistedRequest(
      LimousineCustomerRequestRecord(
        quoteRequestId: 'limq_1',
        statusRef: _statusRef,
        state: 'customer_acceptance_required',
        request: gateway.live,
      ),
    );
    await tester.pumpWidget(_liveStatus(controller));
    await _pump(tester);
    final viewButton = find.byKey(kLimousineCustomerViewQuotationKey);
    await tester.ensureVisible(viewButton);
    await tester.tap(viewButton);
    await tester.pump();
    await tester.pump();
    expect(gateway.lastPdf!['revision'], '4');
    expect(gateway.lastPdf!['status_ref'], _statusRef);
    await tester.pageBack();
    await tester.pump();
    await tester.pump();

    controller.termsAcknowledged = true;
    controller.notifyListeners();
    await _pump(tester);
    final acceptButton = find.byKey(kLimousineCustomerAcceptKey);
    await tester.ensureVisible(acceptButton);
    await tester.tap(acceptButton);
    await tester.pump();
    await tester.pump();
    expect(gateway.lastAccept!['expected_revision'], 4);
    expect(controller.handoff?.acceptanceReference, _acceptRef);
    controller.dispose();
  });

  test('11-12) HTTP PDF keeps status_ref in header not query', () async {
    final client = _PdfClient();
    final gateway = HttpLimousineCustomerQuoteGateway(
      client: client,
      bookingBaseUrl: 'https://booking.test',
      authHeaders: () async => <String, String>{},
    );
    await gateway.fetchQuotationPdf(
      quoteRequestId: 'limq_1',
      revision: 4,
      statusRef: _statusRef,
    );
    expect(client.uri!.queryParameters['revision'], '4');
    expect(client.uri!.queryParameters.containsKey('status_ref'), isFalse);
    expect(client.headers['X-Fluxidi-Status-Ref'], _statusRef);
  });

  testWidgets('16) list card uses current lifecycle after reload', (
    tester,
  ) async {
    final vault = MemoryLimousineCustomerRequestHistoryVault();
    final history = LimousineCustomerRequestHistoryRepository(vault: vault);
    await history.upsert(
      LimousineCustomerRequestRecord(
        quoteRequestId: 'limq_1',
        statusRef: _statusRef,
        state: 'requested',
        companyName: 'Coachline',
        request: _request(),
      ),
    );
    final gateway = _StatusGateway(
      live: _request(
        state: 'customer_acceptance_required',
        revision: 4,
        quotationAvailable: true,
        quotationRevision: 4,
        withQuote: true,
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Offerte ontvangen'), findsWidgets);
  });

  test('17-24) refresh cadence, overlap, dispose, network preserve', () async {
    expect(kLimousineStatusAutoPollInterval, const Duration(seconds: 15));
    expect(limousineCustomerShouldPoll('requested'), isTrue);
    expect(limousineCustomerShouldPoll('viewed_by_company'), isTrue);
    expect(limousineCustomerShouldPoll('quoted'), isTrue);
    expect(limousineCustomerShouldPoll('customer_acceptance_required'), isTrue);
    expect(limousineCustomerShouldPoll('accepted'), isFalse);
    expect(limousineCustomerShouldPoll('booking_created'), isFalse);
    expect(limousineCustomerShouldPoll('expired'), isFalse);
    expect(limousineCustomerShouldPoll('declined'), isFalse);

    final delay = Completer<void>();
    final gateway = _StatusGateway(live: _request(), pollDelay: delay);
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    controller.restorePersistedRequest(
      LimousineCustomerRequestRecord(
        quoteRequestId: 'limq_1',
        statusRef: _statusRef,
        state: 'requested',
        request: _request(),
      ),
    );
    final first = controller.refreshStatus();
    final second = controller.refreshStatus();
    delay.complete();
    await first;
    await second;
    expect(gateway.maxOverlapping, 1);
    expect(controller.statusRefreshInFlight, isFalse);

    final failing = _StatusGateway(
      live: _request(
        state: 'viewed_by_company',
        revision: 2,
        companyViewed: true,
      ),
      pollError: const LimousineCustomerQuoteException(code: 'network'),
    );
    final held = LimousineCustomerQuoteController(gateway: failing);
    held.restorePersistedRequest(
      LimousineCustomerRequestRecord(
        quoteRequestId: 'limq_1',
        statusRef: _statusRef,
        state: 'viewed_by_company',
        request: _request(state: 'viewed_by_company', revision: 2),
      ),
    );
    await held.refreshStatus();
    expect(held.request!.state, 'viewed_by_company');
    expect(held.phase, isNot(LimousineCustomerQuotePhase.unavailable));
    held.dispose();
    expect(held.pollingEnabled, isFalse);
    controller.dispose();
  });

  testWidgets('29-30) company viewed is idempotent and send confirms', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _InboxGateway(_request());
    await tester.pumpWidget(
      MaterialApp(
        home: LimousineQuoteDetailPage(
          quoteRequestId: 'limq_1',
          initial: gateway.record,
          gateway: gateway,
        ),
      ),
    );
    await _pump(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(gateway.actions.where((action) => action == 'viewed').length, 1);
    expect(find.byKey(kLimousineQuoteViewedConfirmationKey), findsOneWidget);
    expect(find.textContaining('Aanvraag bekeken'), findsWidgets);
  });

  testWidgets('quotation language is visible on the company form', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LimousineQuoteEditorPage(
          record: _request(state: 'viewed_by_company'),
        ),
      ),
    );
    await _pump(tester);
    expect(find.byKey(kLimousineQuoteLanguageKey), findsOneWidget);
    expect(find.textContaining('Taal offerte'), findsOneWidget);
  });

  test('31-36) no local PDF bytes in limqs1 metadata', () {
    expect(looksLikeLimousineAcceptanceRef(_acceptRef), isTrue);
    final snapshot = LimousineCustomerRequestRecord(
      quoteRequestId: 'limq_1',
      statusRef: _statusRef,
      state: 'customer_acceptance_required',
      request: _request(
        quotationAvailable: true,
        quotationRevision: 4,
        withQuote: true,
      ),
    ).toJson();
    expect(snapshot.containsKey('pdf'), isFalse);
    expect(jsonEncode(snapshot).contains('%PDF'), isFalse);
  });

  test('A1) viewed then quote uses the latest live revision', () async {
    final viewed = _request(
      state: 'viewed_by_company',
      revision: 2,
      companyViewed: true,
      companyViewedAt: '2026-08-22T10:05:00Z',
    );
    final gateway = _InboxGateway(
      viewed,
      listRecord: _request(),
      staleQuoteBelow: 2,
    );
    final controller = LimousineQuoteInboxController(gateway: gateway);
    controller.items = <LimousineQuoteRequest>[_request()];
    final live = await controller.liveRecordForRespond(_request());
    expect(live.revision, 2);
    final result = await controller.respond(
      action: 'quote',
      record: live,
      quote: const LimousineCompanyQuoteDraft(
        totalInclVatCents: 18500,
        currency: 'EUR',
        vatTreatment: 'incl',
        expiresAt: '2099-01-01T00:00:00Z',
        termsRevision: 1,
      ).toWorkerQuote(),
    );
    expect(gateway.quoteRevisions, <int>[2]);
    expect(result.record!.quotationAvailable, isTrue);
    expect(result.record!.state, 'customer_acceptance_required');
    expect(controller.items.single.quotationAvailable, isTrue);
  });

  test('A2) stale expected_revision is surfaced and not swallowed', () async {
    final viewed = _request(
      state: 'viewed_by_company',
      revision: 2,
      companyViewed: true,
    );
    final gateway = _InboxGateway(viewed, staleQuoteBelow: 2);
    final controller = LimousineQuoteInboxController(gateway: gateway);
    try {
      await controller.respond(
        action: 'quote',
        record: _request(),
        quote: const LimousineCompanyQuoteDraft(
          totalInclVatCents: 18500,
          currency: 'EUR',
          vatTreatment: 'incl',
          expiresAt: '2099-01-01T00:00:00Z',
          termsRevision: 1,
        ).toWorkerQuote(),
      );
      fail('expected stale_revision');
    } on LimousineQuoteInboxException catch (error) {
      expect(error.kind, LimousineQuoteInboxErrorKind.staleRevision);
      expect(error.code, 'stale_revision');
    }
    expect(gateway.record.state, 'viewed_by_company');
    expect(gateway.record.quotationAvailable, isFalse);
  });

  testWidgets('A2/A10) failed send stays on the filled form', (tester) async {
    await _largeSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: LimousineQuoteEditorPage(
          record: _request(state: 'viewed_by_company', revision: 1),
          onSubmit: (_) async {
            throw const LimousineQuoteInboxException(
              kind: LimousineQuoteInboxErrorKind.staleRevision,
              code: 'stale_revision',
              currentRevision: 2,
            );
          },
        ),
      ),
    );
    await tester.pump();
    await _fillAndSubmitCompanyQuote(tester);
    expect(find.byKey(kLimousineQuoteEditorPageKey), findsOneWidget);
    expect(find.byKey(kLimousineQuoteEditorSubmitErrorKey), findsOneWidget);
    expect(find.text(kLimousineQuoteStaleRevision.nl), findsOneWidget);
    expect(find.byKey(kLimousineQuoteSendSuccessKey), findsNothing);
  });

  testWidgets('A1/A3-A9) detail send after viewed reloads committed quote', (
    tester,
  ) async {
    await _largeSurface(tester);
    final gateway = _InboxGateway(_request(), staleQuoteBelow: 2);
    await tester.pumpWidget(
      MaterialApp(
        home: LimousineQuoteDetailPage(
          quoteRequestId: 'limq_1',
          initial: gateway.record,
          gateway: gateway,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(gateway.actions.where((action) => action == 'viewed').length, 1);
    expect(gateway.record.revision, 2);
    await tester.ensureVisible(find.byKey(kLimousineQuoteSubmitKey));
    await tester.tap(find.byKey(kLimousineQuoteSubmitKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineQuoteEditorPageKey), findsOneWidget);
    await _fillAndSubmitCompanyQuote(tester);
    expect(gateway.quoteRevisions, <int>[2]);
    expect(find.byKey(kLimousineQuoteEditorPageKey), findsNothing);
    expect(find.byKey(kLimousineQuoteSendSuccessKey), findsOneWidget);
    expect(find.textContaining('€'), findsWidgets);
    expect(gateway.record.quotationAvailable, isTrue);
    expect(gateway.record.state, 'customer_acceptance_required');
  });

  testWidgets('A1) inbox send uses refreshed revision after viewed', (
    tester,
  ) async {
    await _largeSurface(tester);
    final viewed = _request(
      state: 'viewed_by_company',
      revision: 2,
      companyViewed: true,
      companyViewedAt: '2026-08-22T10:05:00Z',
    );
    final gateway = _InboxGateway(
      viewed,
      listRecord: _request(),
      staleQuoteBelow: 2,
    );
    await tester.pumpWidget(
      MaterialApp(home: LimousineQuoteInboxPage(gateway: gateway)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final send = find.byKey(
      limousineQuoteInboxActionKey('limq_1', 'createQuote'),
    );
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    await _fillAndSubmitCompanyQuote(tester);
    expect(gateway.quoteRevisions, <int>[2]);
    expect(find.byKey(kLimousineQuoteEditorPageKey), findsNothing);
    expect(gateway.record.quotationAvailable, isTrue);
    expect(find.text('Offerte verstuurd'), findsWidgets);
  });

  test('B11-B17) create body keeps request locale and aliases', () {
    LimousineQuoteCreateDraft draft(String locale) {
      return LimousineQuoteCreateDraft(
        publicPartnerId: 'company:fluxidi:fluxidi',
        offerId: 'off_1',
        journeyType: 'point_to_point',
        from: 'Gent',
        to: 'Brussel',
        scheduledPickupIso: '2026-09-01T10:00:00Z',
        locale: locale,
      );
    }

    expect(normalizeLimousineQuoteLocale('nl-BE'), 'nl');
    expect(normalizeLimousineQuoteLocale('en-GB'), 'en');
    expect(normalizeLimousineQuoteLocale('en_US'), 'en');
    expect(normalizeLimousineQuoteLocale('fr-BE'), 'fr');
    expect(normalizeLimousineQuoteLocale('es-ES'), 'es');
    expect(limousineCustomerCreateBody(draft('nl'))['locale'], 'nl');
    expect(limousineCustomerCreateBody(draft('en'))['locale'], 'en');
    expect(limousineCustomerCreateBody(draft('fr'))['locale'], 'fr');
    expect(limousineCustomerCreateBody(draft('es'))['locale'], 'es');
    expect(limousineCustomerCreateBody(draft('en-GB'))['locale'], 'en');
    expect(limousineCustomerCreateBody(draft('fr-FR'))['locale'], 'fr');
    expect(
      limousineQuoteDocumentLanguageLabel('en_gb', AppLanguage.nl),
      kLimousineQuoteLanguageEn.nl,
    );
  });
}
