import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_request_history.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_status_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_detail_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_labels.dart';
import 'package:fluxidi_tracking/widgets/fluxidi_pdf_preview_page.dart';

const String _statusRef = 'limqs1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM';
const String _acceptRef = 'limacc1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM';

final Uint8List _pdfBytes = Uint8List.fromList(
  '%PDF-1.1\n1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n%%EOF'.codeUnits,
);

CustomerThemePalette get _palette =>
    paletteForCustomerTheme(CustomerThemeVariant.premiumLight);

Map<String, dynamic> _quoteJson({
  String id = 'limq_1',
  String state = 'customer_acceptance_required',
  bool quotationAvailable = false,
  int? quotationRevision,
  bool acceptanceAllowed = true,
}) {
  return <String, dynamic>{
    'quote_request_id': id,
    'state': state,
    'revision': 3,
    'offer_id': 'off_1',
    'service_class_id': 'executive_sedan',
    'journey_type': 'point_to_point',
    'scheduled_pickup_iso': '2026-09-01T10:00:00Z',
    'pax': 2,
    'bags': 1,
    'acceptance_allowed': acceptanceAllowed,
    'quote': <String, dynamic>{
      'total_incl_vat_cents': 45000,
      'currency': 'EUR',
      'vat_treatment': 'incl',
      'terms_revision': 3,
      'expires_at': '2099-01-01T00:00:00Z',
      'terms': <String, dynamic>{
        'terms_revision': 3,
        'cancellation_deadline_hours': 24,
        'cancellation_penalty_percent': 50,
        'waiting_time_included_minutes': 15,
        'waiting_time_overage_cents_per_minute': 100,
        'no_show_penalty_percent': 100,
        'overtime_cents_per_hour': 9000,
      },
    },
    'quotation_available': quotationAvailable,
    if (quotationRevision != null) 'quotation_revision': quotationRevision,
  };
}

LimousineQuoteRequest _request({
  String id = 'limq_1',
  String state = 'customer_acceptance_required',
  bool quotationAvailable = false,
  int? quotationRevision,
  bool acceptanceAllowed = true,
}) {
  return LimousineQuoteRequest.fromJson(
    _quoteJson(
      id: id,
      state: state,
      quotationAvailable: quotationAvailable,
      quotationRevision: quotationRevision,
      acceptanceAllowed: acceptanceAllowed,
    ),
  );
}

class _PartnerGateway implements LimousineQuoteInboxGateway {
  _PartnerGateway({
    required this.record,
    this.pdfBytes,
    this.pdfError,
    this.delay,
  });

  LimousineQuoteRequest record;
  Uint8List? pdfBytes;
  Object? pdfError;
  Completer<void>? delay;
  final List<Map<String, dynamic>> pdfCalls = <Map<String, dynamic>>[];

  @override
  Future<LimousineQuoteInboxPageData> list({
    int pageSize = kLimousineQuoteInboxPageDefault,
    String? state,
    String? cursor,
    String? updatedSince,
    String? tenantId,
    String? companyId,
  }) async {
    return LimousineQuoteInboxPageData(items: <LimousineQuoteRequest>[record]);
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
    throw UnimplementedError();
  }

  @override
  Future<Uint8List> fetchQuotationPdf({
    required String quoteRequestId,
    required int revision,
    String? tenantId,
    String? companyId,
  }) async {
    pdfCalls.add(<String, dynamic>{
      'quote_request_id': quoteRequestId,
      'revision': revision,
      'tenant_id': tenantId,
      'company_id': companyId,
    });
    final waiter = delay;
    if (waiter != null) await waiter.future;
    final error = pdfError;
    if (error != null) {
      throw error is Exception ? error : Exception(error.toString());
    }
    return pdfBytes ?? _pdfBytes;
  }
}

class _CustomerGateway implements LimousineCustomerQuoteGateway {
  _CustomerGateway({this.pdfBytes});

  Uint8List? pdfBytes;
  Object? pdfError;
  final List<Map<String, String>> pdfCalls = <Map<String, String>>[];

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
  Future<LimousineBookingRequestResult> createBookingRequest(
    LimousineQuoteCreateDraft draft,
  ) async {
    throw const LimousineCustomerQuoteException(code: 'unused');
  }

  @override
  Future<LimousineQuoteRequest> pollStatus(String statusRef) async {
    throw const LimousineCustomerQuoteException(code: 'unused');
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
  }) async {
    pdfCalls.add(<String, String>{
      'quote_request_id': quoteRequestId,
      'revision': '$revision',
      'status_ref': statusRef,
    });
    final error = pdfError;
    if (error != null) {
      throw error is Exception ? error : Exception(error.toString());
    }
    return pdfBytes ?? _pdfBytes;
  }
}

class _PdfCaptureClient extends http.BaseClient {
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

Widget _detailApp(Widget child) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(390, 2400)),
      child: child,
    ),
  );
}

Widget _statusApp(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Finder _quotationButton([Key key = kLimousineQuoteViewQuotationKey]) {
  return find.byKey(key, skipOffstage: false);
}

Future<void> _largeSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    appLanguageNotifier.value = AppLanguage.nl;
  });

  testWidgets('1) partner detail hides quotation action for a legacy quote', (
    tester,
  ) async {
    await _largeSurface(tester);
    final record = _request();
    final gateway = _PartnerGateway(record: record);
    await tester.pumpWidget(
      _detailApp(
        LimousineQuoteDetailPage(
          quoteRequestId: record.quoteRequestId,
          initial: record,
          gateway: gateway,
        ),
      ),
    );
    await _pump(tester);
    expect(
      find.byKey(kLimousineQuoteViewQuotationKey, skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets(
    '2-4) partner action calls dedicated endpoint and opens preview',
    (tester) async {
      await _largeSurface(tester);
      final record = _request(quotationAvailable: true, quotationRevision: 3);
      final delay = Completer<void>();
      final gateway = _PartnerGateway(
        record: record,
        delay: delay,
        pdfBytes: _pdfBytes,
      );
      await tester.pumpWidget(
        _detailApp(
          LimousineQuoteDetailPage(
            quoteRequestId: record.quoteRequestId,
            initial: record,
            gateway: gateway,
          ),
        ),
      );
      await _pump(tester);
      expect(_quotationButton(), findsOneWidget);
      expect(
        find.text('Offerte bekijken', skipOffstage: false),
        findsOneWidget,
      );
      await tester.ensureVisible(_quotationButton());
      await tester.tap(_quotationButton());
      await tester.pump();
      expect(
        find.byKey(kLimousineQuoteViewQuotationLoadingKey),
        findsOneWidget,
      );
      delay.complete();
      await tester.pump();
      await tester.pump();
      expect(gateway.pdfCalls, isNotEmpty);
      expect(gateway.pdfCalls.single['quote_request_id'], 'limq_1');
      expect(gateway.pdfCalls.single['revision'], 3);
      expect(find.byType(FluxidiPdfPreviewPage), findsOneWidget);
      expect(find.text('Offerte'), findsWidgets);
    },
  );

  testWidgets('5-14) customer status shows historical quotation action', (
    tester,
  ) async {
    Future<void> pumpState(String state) async {
      final gateway = _CustomerGateway();
      final controller = LimousineCustomerQuoteController(gateway: gateway);
      controller.restorePersistedRequest(
        LimousineCustomerRequestRecord(
          quoteRequestId: 'limq_1',
          statusRef: _statusRef,
          state: state,
          request: _request(
            state: state,
            quotationAvailable: true,
            quotationRevision: 3,
            acceptanceAllowed: state == 'customer_acceptance_required',
          ),
        ),
      );
      await tester.pumpWidget(
        _statusApp(
          LimousineCustomerStatusView(
            controller: controller,
            language: AppLanguage.nl,
            palette: _palette,
          ),
        ),
      );
      await _pump(tester);
      expect(find.byKey(kLimousineCustomerViewQuotationKey), findsOneWidget);
      controller.dispose();
    }

    await pumpState('customer_acceptance_required');
    await pumpState('accepted');
    await pumpState('expired');
    await pumpState('declined');
    await pumpState('withdrawn');
  });

  testWidgets('5) customer status hides action for a legacy quote', (
    tester,
  ) async {
    final gateway = _CustomerGateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway)
      ..request = _request();
    await tester.pumpWidget(
      _statusApp(
        LimousineCustomerStatusView(
          controller: controller,
          language: AppLanguage.en,
          palette: _palette,
        ),
      ),
    );
    await _pump(tester);
    expect(find.byKey(kLimousineCustomerViewQuotationKey), findsNothing);
    controller.dispose();
  });

  testWidgets(
    '7-10) customer tap sends status_ref header path and opens bytes',
    (tester) async {
      final gateway = _CustomerGateway(pdfBytes: _pdfBytes);
      final controller = LimousineCustomerQuoteController(gateway: gateway);
      controller.restorePersistedRequest(
        LimousineCustomerRequestRecord(
          quoteRequestId: 'limq_1',
          statusRef: _statusRef,
          state: 'customer_acceptance_required',
          request: _request(quotationAvailable: true, quotationRevision: 3),
        ),
      );
      await tester.pumpWidget(
        _statusApp(
          LimousineCustomerStatusView(
            controller: controller,
            language: AppLanguage.en,
            palette: _palette,
          ),
        ),
      );
      await _pump(tester);
      await tester.tap(find.byKey(kLimousineCustomerViewQuotationKey));
      await tester.pump();
      await tester.pump();
      expect(gateway.pdfCalls.single['quote_request_id'], 'limq_1');
      expect(gateway.pdfCalls.single['revision'], '3');
      expect(gateway.pdfCalls.single['status_ref'], _statusRef);
      expect(find.byType(FluxidiPdfPreviewPage), findsOneWidget);
      expect(find.text('Quotation'), findsWidgets);
      controller.dispose();
    },
  );

  testWidgets('15) no customer reject action is added', (tester) async {
    final gateway = _CustomerGateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway)
      ..request = _request(quotationAvailable: true, quotationRevision: 3);
    await tester.pumpWidget(
      _statusApp(
        LimousineCustomerStatusView(
          controller: controller,
          language: AppLanguage.en,
          palette: _palette,
        ),
      ),
    );
    await _pump(tester);
    expect(find.text(kLimousineCustomerDeclineAction.en), findsNothing);
    expect(find.text(kLimousineCustomerDeclineAction.nl), findsNothing);
    expect(find.text(kLimousineCustomerDeclineAction.fr), findsNothing);
    expect(find.text(kLimousineCustomerDeclineAction.es), findsNothing);
    expect(find.byKey(kLimousineCustomerAcceptKey), findsOneWidget);
    controller.dispose();
  });

  testWidgets('19-20) loading and retryable error states', (tester) async {
    await _largeSurface(tester);
    final delay = Completer<void>();
    final gateway = _PartnerGateway(
      record: _request(quotationAvailable: true, quotationRevision: 3),
      delay: delay,
      pdfError: const LimousineQuoteInboxException(
        kind: LimousineQuoteInboxErrorKind.network,
        code: 'network',
      ),
    );
    await tester.pumpWidget(
      _detailApp(
        LimousineQuoteDetailPage(
          quoteRequestId: 'limq_1',
          initial: gateway.record,
          gateway: gateway,
        ),
      ),
    );
    await _pump(tester);
    await tester.ensureVisible(_quotationButton());
    await tester.tap(_quotationButton());
    await tester.pump();
    expect(find.byKey(kLimousineQuoteViewQuotationLoadingKey), findsOneWidget);
    delay.complete();
    await tester.pump();
    expect(find.byKey(kLimousineQuoteViewQuotationErrorKey), findsOneWidget);
    expect(find.byType(FluxidiPdfPreviewPage), findsNothing);
    gateway.pdfError = null;
    await tester.ensureVisible(_quotationButton());
    await tester.tap(_quotationButton());
    await tester.pump();
    await tester.pump();
    expect(find.byType(FluxidiPdfPreviewPage), findsOneWidget);
  });

  test('21-24) quotation labels are localized', () {
    expect(kLimousineQuoteViewQuotation.nl, 'Offerte bekijken');
    expect(kLimousineQuoteViewQuotation.en, 'View quotation');
    expect(kLimousineQuoteViewQuotation.fr, 'Voir le devis');
    expect(kLimousineQuoteViewQuotation.es, 'Ver presupuesto');
  });

  testWidgets('21-24) NL/EN/FR/ES CTA labels render', (tester) async {
    await _largeSurface(tester);
    final record = _request(quotationAvailable: true, quotationRevision: 3);
    for (final lang in AppLanguage.values) {
      if (lang != AppLanguage.nl &&
          lang != AppLanguage.en &&
          lang != AppLanguage.fr &&
          lang != AppLanguage.es) {
        continue;
      }
      appLanguageNotifier.value = lang;
      final gateway = _PartnerGateway(record: record);
      await tester.pumpWidget(
        _detailApp(
          LimousineQuoteDetailPage(
            quoteRequestId: record.quoteRequestId,
            initial: record,
            gateway: gateway,
          ),
        ),
      );
      await _pump(tester);
      await tester.ensureVisible(_quotationButton());
      expect(
        find.text(kLimousineQuoteViewQuotation.of(lang), skipOffstage: false),
        findsOneWidget,
      );
    }
  });

  testWidgets('25) payment and booking CTAs remain unchanged', (tester) async {
    final gateway = _CustomerGateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway)
      ..request = _request(quotationAvailable: true, quotationRevision: 3)
      ..handoff = const LimousineAcceptedQuoteHandoff(
        acceptanceReference: _acceptRef,
        quoteRequestId: 'limq_1',
        quoteRevision: 3,
        termsRevision: 3,
        totalInclVatCents: 45000,
        currency: 'EUR',
        offerId: 'off_1',
        publicPartnerId: 'p1',
        from: 'Gent',
        to: 'Brussel',
        scheduledPickupIso: '2026-09-01T10:00:00Z',
      );
    await tester.pumpWidget(
      _statusApp(
        LimousineCustomerStatusView(
          controller: controller,
          language: AppLanguage.en,
          palette: _palette,
          onOpenBookingReview: () {},
        ),
      ),
    );
    await _pump(tester);
    expect(find.byKey(kLimousineCustomerAcceptKey), findsOneWidget);
    expect(find.byKey(kLimousineAcceptedBookingOpenReviewKey), findsOneWidget);
    expect(find.byKey(kLimousineCustomerViewQuotationKey), findsOneWidget);
    controller.dispose();
  });

  test(
    '7-9) customer HTTP uses quote id, revision, and status_ref header only',
    () async {
      final client = _PdfCaptureClient();
      final gateway = HttpLimousineCustomerQuoteGateway(
        client: client,
        bookingBaseUrl: 'https://booking.example',
        authHeaders: () async => const <String, String>{
          'Accept': 'application/json',
        },
      );
      final bytes = await gateway.fetchQuotationPdf(
        quoteRequestId: 'limq_1',
        revision: 3,
        statusRef: _statusRef,
      );
      expect(bytes, isNotEmpty);
      expect(
        client.uri!.path,
        '/limousine/quote-requests/limq_1/quotation.pdf',
      );
      expect(client.uri!.queryParameters['revision'], '3');
      expect(client.uri!.queryParameters.containsKey('status_ref'), isFalse);
      expect(client.uri!.queryParameters.containsKey('statusRef'), isFalse);
      expect(
        client.headers['x-fluxidi-status-ref'] ??
            client.headers['X-Fluxidi-Status-Ref'],
        _statusRef,
      );
    },
  );

  test(
    '3) partner HTTP uses dedicated quotation.pdf path without status_ref',
    () {
      final src = File(
        'lib/limousine/limousine_quote_inbox_api.dart',
      ).readAsStringSync();
      expect(
        src.contains('/admin/limousine/quote-requests/\$id/quotation.pdf'),
        isTrue,
      );
      expect(src.contains("'revision': '\$revision'"), isTrue);
      expect(src.contains('status_ref_not_allowed'), isTrue);
      expect(src.contains('X-Fluxidi-Status-Ref'), isFalse);
    },
  );

  test(
    '16-18) no Flutter PDF generation and no limqs1/limacc1 byte persistence',
    () {
      final action = File(
        'lib/limousine/limousine_quotation_pdf_action.dart',
      ).readAsStringSync();
      final customerApi = File(
        'lib/limousine/limousine_customer_quote_api.dart',
      ).readAsStringSync();
      final partnerApi = File(
        'lib/limousine/limousine_quote_inbox_api.dart',
      ).readAsStringSync();
      final status = File(
        'lib/limousine/limousine_customer_status_page.dart',
      ).readAsStringSync();
      for (final src in <String>[action, customerApi, partnerApi, status]) {
        expect(src.contains('pw.Document'), isFalse);
        expect(src.contains('package:pdf/'), isFalse);
        expect(src.contains('SharedPreferences'), isFalse);
        expect(src.contains('FlutterSecureStorage'), isFalse);
      }
      expect(action.contains('FluxidiPdfPreviewPage'), isTrue);
      expect(customerApi.contains('X-Fluxidi-Status-Ref'), isTrue);
      expect(customerApi.contains('limqs1'), isTrue);
      expect(customerApi.contains('quotation.pdf'), isTrue);
      expect(
        File(
          'lib/limousine/limousine_customer_request_history.dart',
        ).readAsStringSync().contains('pdf'),
        isFalse,
      );
      expect(status.contains('kLimousineCustomerDeclineAction'), isFalse);
    },
  );

  test('controller loadQuotationPdf does not write vault keys', () async {
    final store = LimousineInMemoryStatusReferenceStore();
    final gateway = _CustomerGateway();
    final controller = LimousineCustomerQuoteController(
      gateway: gateway,
      statusStore: store,
    );
    controller.restorePersistedRequest(
      LimousineCustomerRequestRecord(
        quoteRequestId: 'limq_1',
        statusRef: _statusRef,
        state: 'customer_acceptance_required',
        request: _request(quotationAvailable: true, quotationRevision: 3),
      ),
    );
    final bytes = await controller.loadQuotationPdf();
    expect(bytes, _pdfBytes);
    expect(utf8.decode(bytes).contains('limqs1'), isFalse);
    expect(store.persistsAcrossRestarts, isFalse);
    controller.dispose();
  });
}
