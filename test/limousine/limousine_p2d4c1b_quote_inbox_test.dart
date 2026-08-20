import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_detail_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_presentation.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_tile.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_respond_form.dart';

Map<String, dynamic> _item({
  String id = 'qr_1',
  String state = 'requested',
  String from = 'Brussels',
  String to = 'Antwerp',
  bool withQuote = false,
  String? note,
}) {
  return <String, dynamic>{
    'quote_request_id': id,
    'state': state,
    'revision': 3,
    'offer_id': 'off_exec',
    'service_class_id': 'executive_sedan',
    'journey_type': 'point_to_point',
    'scheduled_pickup_iso': '2026-08-20T09:00:00Z',
    'pax': 2,
    'bags': 1,
    'created_at': '2026-08-17T10:00:00Z',
    'updated_at': '2026-08-17T11:00:00Z',
    if (withQuote)
      'quote': <String, dynamic>{
        'total_incl_vat_cents': 18500,
        'currency': 'EUR',
        'expires_at': '2026-08-19T10:00:00Z',
        'terms_revision': 2,
      },
    'fulfilment': <String, dynamic>{
      'from': from,
      'to': to,
      if (note != null) 'customer_note': note,
    },
    'inbox': <String, dynamic>{'activity_seq': 1, 'transitions_blocked': false},
  };
}

LimousineQuoteRequest _record({
  String id = 'qr_1',
  String state = 'requested',
  bool withQuote = false,
  String from = 'Brussels',
  String to = 'Antwerp',
}) {
  return LimousineQuoteRequest.fromJson(
    _item(id: id, state: state, withQuote: withQuote, from: from, to: to),
  );
}

class _FakeGateway implements LimousineQuoteInboxGateway {
  _FakeGateway({this.pages, this.listError, this.detailRecords, this.delay});

  List<LimousineQuoteInboxPageData>? pages;
  LimousineQuoteInboxException? listError;
  Map<String, LimousineQuoteRequest>? detailRecords;
  Future<void>? delay;
  final listCalls = <Map<String, dynamic>>[];

  @override
  Future<LimousineQuoteInboxPageData> list({
    int pageSize = 20,
    String? state,
    String? cursor,
    String? updatedSince,
    String? tenantId,
    String? companyId,
  }) async {
    listCalls.add(<String, dynamic>{
      'state': state,
      'cursor': cursor,
      'tenantId': tenantId,
      'companyId': companyId,
    });
    if (delay != null) await delay;
    if (listError != null) throw listError!;
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
    return detailRecords?[quoteRequestId] ?? _record(id: quoteRequestId);
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
}

Widget _app(Widget child, {Size size = kLimousinePhonePortrait}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

void _bindView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _pumpInbox(
  WidgetTester tester,
  Widget child, {
  Size size = kLimousinePhonePortrait,
}) async {
  _bindView(tester, size);
  await tester.pumpWidget(_app(child, size: size));
  await _pumpFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousTheme = businessThemeNotifier.value;
  final previousLang = appLanguageNotifier.value;

  setUp(() {
    appLanguageNotifier.value = AppLanguage.nl;
  });

  tearDown(() {
    businessThemeNotifier.value = previousTheme;
    appLanguageNotifier.value = previousLang;
  });

  test('four languages localize interface labels', () {
    for (final language in const [
      AppLanguage.nl,
      AppLanguage.en,
      AppLanguage.fr,
      AppLanguage.es,
    ]) {
      expect(kLimousineQuoteInboxTitle.of(language), isNotEmpty);
      expect(kLimousineQuoteInboxHeroBody.of(language), isNotEmpty);
      expect(kLimousineQuoteInboxKpiNew.of(language), isNotEmpty);
      expect(kLimousineQuoteInboxSearchHint.of(language), isNotEmpty);
      expect(kLimousineQuoteInboxCreateQuote.of(language), isNotEmpty);
      expect(kLimousineQuoteInboxOpenHandoff.of(language), isNotEmpty);
      expect(kLimousineQuoteGateOff.of(language), isNotEmpty);
      expect(
        limousineQuoteInboxStatusLabel(_record(), language),
        isNot(contains('requested')),
      );
    }
    expect(
      kLimousineQuoteGateOff.nl,
      'Limousineoffertes zijn nog niet actief in deze testomgeving.',
    );
  });

  test('raw backend statuses never become labels', () {
    for (final state in LimousineQuoteStateId.known) {
      expect(
        limousineQuoteInboxStatusLabel(_record(state: state), AppLanguage.nl),
        isNot(state),
      );
    }
    expect(limousineQuoteInboxLooksRawBackend('requested'), isTrue);
    expect(limousineQuoteInboxLooksRawBackend('Exception: 404'), isTrue);
    expect(
      limousineQuoteInboxLooksRawBackend(kLimousineQuoteGateOff.nl),
      isFalse,
    );
  });

  test('KPI counts come from loaded records', () {
    final kpis = limousineQuoteInboxKpis(<LimousineQuoteRequest>[
      _record(id: 'a', state: 'requested'),
      _record(id: 'b', state: 'requested'),
      _record(id: 'c', state: 'viewed_by_company'),
      _record(id: 'd', state: 'quoted', withQuote: true),
      _record(id: 'e', state: 'accepted', withQuote: true),
    ]);
    expect(kpis.neu, 2);
    expect(kpis.toAnswer, 3);
    expect(kpis.waitingCustomer, 1);
    expect(kpis.accepted, 1);
  });

  test('search matches place and public reference only', () {
    final records = <LimousineQuoteRequest>[
      _record(id: 'qr_ghent', from: 'Ghent', to: 'Bruges'),
      _record(id: 'qr_antwerp', from: 'Brussels', to: 'Antwerp'),
    ];
    expect(
      limousineQuoteInboxSearch(records, 'Ghent').single.quoteRequestId,
      'qr_ghent',
    );
    expect(
      limousineQuoteInboxSearch(records, 'qr_antwerp').single.quoteRequestId,
      'qr_antwerp',
    );
    expect(limousineQuoteInboxSearch(records, 'hidden@example.com'), isEmpty);
  });

  test('lifecycle actions stay possible-only', () {
    expect(
      limousineQuoteInboxCardActions(_record()),
      containsAll(<LimousineQuoteInboxCardAction>[
        LimousineQuoteInboxCardAction.createQuote,
        LimousineQuoteInboxCardAction.view,
      ]),
    );
    expect(
      limousineQuoteInboxCardActions(_record(state: 'quoted', withQuote: true)),
      contains(LimousineQuoteInboxCardAction.viewQuote),
    );
    expect(
      limousineQuoteInboxCardActions(
        _record(state: 'accepted', withQuote: true),
      ),
      contains(LimousineQuoteInboxCardAction.openAcceptedHandoff),
    );
    expect(
      limousineQuoteInboxCardActions(_record(state: 'booking_created')),
      contains(LimousineQuoteInboxCardAction.viewBooking),
    );
    expect(
      limousineQuoteInboxCardActions(
        _record(state: 'accepted', withQuote: true),
      ),
      isNot(contains(LimousineQuoteInboxCardAction.createQuote)),
    );
  });

  test('every committed theme has readable palette contrast', () {
    for (final variant in BusinessThemeVariant.values) {
      if (variant == BusinessThemeVariant.brandSignatureGold) {
        continue;
      }
      final palette = paletteForBusinessTheme(variant);
      expect(
        limousineHasReadableContrast(palette.textPrimary, palette.background),
        isTrue,
        reason: variant.name,
      );
      expect(
        limousineHasReadableContrast(palette.textPrimary, palette.surface),
        isTrue,
        reason: variant.name,
      );
    }
    final gold = paletteForBusinessTheme(
      BusinessThemeVariant.brandSignatureGold,
    );
    expect(
      limousineHasReadableContrast(gold.textPrimary, gold.background),
      isTrue,
    );
  });

  test('inbox page source stays on business palette tokens', () {
    final page = File(
      'lib/limousine/limousine_quote_inbox_page.dart',
    ).readAsStringSync();
    expect(limousineQuoteInboxUsesPaletteTokens(page), isTrue);
    expect(page.contains('VerticalDivider'), isFalse);
    expect(page.contains('/book'), isFalse);
    expect(page.contains('taxi'), isFalse);
  });

  testWidgets('tile is localized, populated and entitlement-gated', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const SizedBox(
          width: 220,
          height: 140,
          child: LimousineQuoteInboxDashboardTile(entitled: false),
        ),
      ),
    );
    expect(find.byKey(kLimousineQuoteInboxEntryKey), findsNothing);

    await tester.pumpWidget(
      _app(
        const SizedBox(
          width: 220,
          height: 140,
          child: LimousineQuoteInboxDashboardTile(
            entitled: true,
            unreadCount: 3,
            language: AppLanguage.nl,
          ),
        ),
      ),
    );
    expect(find.byKey(kLimousineQuoteInboxEntryKey), findsOneWidget);
    expect(find.byKey(kLimousineQuoteInboxTileVisualKey), findsOneWidget);
    expect(find.text('Limousineoffertes'), findsOneWidget);
    expect(find.byKey(kLimousineQuoteInboxTileBadgeKey), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('Gold Blue Clean Professional and dark stay themed', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      pages: [
        LimousineQuoteInboxPageData(items: [_record()]),
      ],
    );
    for (final variant in const [
      BusinessThemeVariant.brandSignatureGold,
      BusinessThemeVariant.corporateBlue,
      BusinessThemeVariant.cleanProfessional,
      BusinessThemeVariant.executiveGold,
      BusinessThemeVariant.fluxidiNeonRush,
    ]) {
      businessThemeNotifier.value = variant;
      await _pumpInbox(tester, LimousineQuoteInboxPage(gateway: gateway));
      final scaffold = tester.widget<Scaffold>(
        find.byKey(kLimousineQuoteInboxPageKey),
      );
      expect(
        scaffold.backgroundColor,
        paletteForBusinessTheme(variant).background,
      );
      expect(find.byKey(kLimousineQuoteInboxPhoneLayoutKey), findsOneWidget);
    }
  });

  testWidgets('active populated inbox and KPI cards', (tester) async {
    final gateway = _FakeGateway(
      pages: [
        LimousineQuoteInboxPageData(
          items: [
            _record(id: 'qr_new'),
            _record(id: 'qr_wait', state: 'quoted', withQuote: true),
            _record(id: 'qr_acc', state: 'accepted', withQuote: true),
          ],
        ),
      ],
    );
    await _pumpInbox(tester, LimousineQuoteInboxPage(gateway: gateway));
    expect(find.byKey(kLimousineQuoteInboxListKey), findsOneWidget);
    expect(find.byKey(kLimousineQuoteInboxKpiRowKey), findsOneWidget);
    expect(find.byKey(limousineQuoteInboxKpiKey('neu')), findsOneWidget);
    expect(find.text('requested'), findsNothing);
    expect(find.textContaining('404'), findsNothing);
    expect(find.byType(VerticalDivider), findsNothing);
  });

  testWidgets('active empty inbox', (tester) async {
    await _pumpInbox(
      tester,
      LimousineQuoteInboxPage(
        gateway: _FakeGateway(
          pages: const [LimousineQuoteInboxPageData(items: [])],
        ),
      ),
    );
    expect(find.byKey(kLimousineQuoteInboxEmptyKey), findsOneWidget);
    expect(
      find.text(kLimousineQuoteInboxEmpty.of(appLanguageNotifier.value)),
      findsOneWidget,
    );
    expect(
      find.text(kLimousineQuoteInboxEmptyHint.of(appLanguageNotifier.value)),
      findsOneWidget,
    );
    expect(find.byKey(kLimousineQuoteInboxGateOffKey), findsNothing);
    expect(find.byKey(kLimousineQuoteInboxRetryKey), findsNothing);
  });

  testWidgets('gate unavailable has no retry', (tester) async {
    await _pumpInbox(tester, const LimousineQuoteInboxPage(entitled: false));
    expect(find.byKey(kLimousineQuoteInboxGateOffKey), findsOneWidget);
    expect(
      find.text(kLimousineQuoteGateOff.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(find.byKey(kLimousineQuoteInboxRetryKey), findsNothing);
    expect(find.byKey(kLimousineQuoteInboxEmptyKey), findsNothing);

    await _pumpInbox(
      tester,
      LimousineQuoteInboxPage(
        key: const ValueKey<String>('limousine_inbox_gate_api'),
        gateway: _FakeGateway(
          listError: const LimousineQuoteInboxException(
            kind: LimousineQuoteInboxErrorKind.gateOff,
            code: 'manual_quote_gate_off',
            statusCode: 404,
          ),
        ),
      ),
    );
    expect(find.byKey(kLimousineQuoteInboxGateOffKey), findsOneWidget);
    expect(find.byKey(kLimousineQuoteInboxRetryKey), findsNothing);
    expect(find.textContaining('not_found'), findsNothing);
    expect(find.textContaining('404'), findsNothing);
  });

  testWidgets('temporary failure shows retry', (tester) async {
    await _pumpInbox(
      tester,
      LimousineQuoteInboxPage(
        gateway: _FakeGateway(
          listError: const LimousineQuoteInboxException(
            kind: LimousineQuoteInboxErrorKind.network,
            code: 'network',
          ),
        ),
      ),
    );
    expect(find.byKey(kLimousineQuoteInboxErrorKey), findsOneWidget);
    expect(find.byKey(kLimousineQuoteInboxRetryKey), findsOneWidget);
    expect(find.byKey(kLimousineQuoteInboxGateOffKey), findsNothing);
  });

  testWidgets('loading uses a contained skeleton', (tester) async {
    final hold = Completer<void>();
    await tester.pumpWidget(
      _app(
        LimousineQuoteInboxPage(
          gateway: _FakeGateway(
            pages: const [LimousineQuoteInboxPageData(items: [])],
            delay: hold.future,
          ),
        ),
      ),
    );
    expect(find.byKey(kLimousineQuoteInboxLoadingKey), findsOneWidget);
    hold.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('search and status filtering hide unmatched cards', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      pages: [
        LimousineQuoteInboxPageData(
          items: [
            _record(id: 'qr_ghent', from: 'Ghent', to: 'Bruges'),
            _record(
              id: 'qr_quoted',
              from: 'Brussels',
              to: 'Antwerp',
              state: 'quoted',
              withQuote: true,
            ),
          ],
        ),
      ],
    );
    await _pumpInbox(tester, LimousineQuoteInboxPage(gateway: gateway));
    await tester.enterText(find.byKey(kLimousineQuoteInboxSearchKey), 'Ghent');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('limousine_inbox_row_qr_ghent')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('limousine_inbox_row_qr_quoted')),
      findsNothing,
    );
    await tester.enterText(find.byKey(kLimousineQuoteInboxSearchKey), '');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('limousine_inbox_filter_requested')),
    );
    await _pumpFrames(tester);
    expect(
      find.byKey(const ValueKey('limousine_inbox_row_qr_ghent')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('limousine_inbox_row_qr_quoted')),
      findsNothing,
    );
  });

  testWidgets('phone and tablet layouts have no split divider', (tester) async {
    final gateway = _FakeGateway(
      pages: [
        LimousineQuoteInboxPageData(items: [_record()]),
      ],
    );
    await _pumpInbox(tester, LimousineQuoteInboxPage(gateway: gateway));
    expect(find.byKey(kLimousineQuoteInboxPhoneLayoutKey), findsOneWidget);

    await _pumpInbox(
      tester,
      LimousineQuoteInboxPage(gateway: gateway),
      size: const Size(1024, 768),
    );
    expect(find.byKey(kLimousineQuoteInboxTabletLayoutKey), findsOneWidget);
    expect(find.byType(VerticalDivider), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('accepted request opens existing detail handoff, not /book', (
    tester,
  ) async {
    final accepted = _record(id: 'qr_acc', state: 'accepted', withQuote: true);
    final gateway = _FakeGateway(
      pages: [
        LimousineQuoteInboxPageData(items: [accepted]),
      ],
      detailRecords: {'qr_acc': accepted},
    );
    await _pumpInbox(
      tester,
      LimousineQuoteInboxPage(gateway: gateway),
      size: const Size(390, 1200),
    );
    final handoff = find.byKey(
      limousineQuoteInboxActionKey('qr_acc', 'openAcceptedHandoff'),
    );
    await tester.ensureVisible(handoff);
    await tester.pump();
    await tester.tap(handoff);
    await tester.pumpAndSettle();
    expect(find.byType(LimousineQuoteDetailPage), findsOneWidget);
    expect(find.byType(LimousineQuoteEditorPage), findsNothing);
  });

  test('tenant isolation stays on scoped admin URIs', () {
    final left = adminTenantCompanyScopedUri(
      Uri.parse('https://example.test/admin/limousine/quote-requests'),
      tenantId: 'tenant_a',
      companyId: 'tenant_a',
    );
    final right = adminTenantCompanyScopedUri(
      Uri.parse('https://example.test/admin/limousine/quote-requests'),
      tenantId: 'tenant_b',
      companyId: 'tenant_b',
    );
    expect(left.queryParameters['tenant_id'], 'tenant_a');
    expect(left.queryParameters['company_id'], 'tenant_a');
    expect(right.queryParameters['tenant_id'], 'tenant_b');
    expect(left.toString(), isNot(right.toString()));
    expect(
      () => adminTenantCompanyScopedUri(
        Uri.parse('https://example.test/admin/limousine/quote-requests'),
        tenantId: 'tenant_a',
        companyId: 'tenant_b',
      ),
      throwsStateError,
    );
    final api = File(
      'lib/limousine/limousine_quote_inbox_api.dart',
    ).readAsStringSync();
    expect(api.contains('adminTenantCompanyScopedUri'), isTrue);
    expect(api.contains('tenantId: tenantId'), isTrue);
    expect(api.contains('companyId: companyId'), isTrue);
  });

  test('authoritative amount uses the quote snapshot only', () {
    final quoted = _record(state: 'quoted', withQuote: true);
    expect(
      limousineQuoteInboxAuthoritativeAmount(quoted, AppLanguage.nl),
      'EUR 185.00 aangeboden',
    );
    expect(
      limousineQuoteInboxAuthoritativeAmount(
        _record(state: 'accepted', withQuote: true),
        AppLanguage.nl,
      ),
      'EUR 185.00 geaccepteerd',
    );
    expect(
      limousineQuoteInboxAuthoritativeAmount(_record(), AppLanguage.nl),
      isNull,
    );
    expect(
      File(
        'lib/limousine/limousine_quote_inbox_page.dart',
      ).readAsStringSync().contains('clientTotal'),
      isFalse,
    );
  });

  test('opening and refresh stay off /book and taxi fallback', () {
    final api = File(
      'lib/limousine/limousine_quote_inbox_api.dart',
    ).readAsStringSync();
    final page = File(
      'lib/limousine/limousine_quote_inbox_page.dart',
    ).readAsStringSync();
    expect(api.contains('/book'), isFalse);
    expect(page.contains('/book'), isFalse);
    expect(page.contains('admin/limousine/quote-requests'), isFalse);
    expect(api.contains('adminTenantCompanyScopedUri'), isTrue);
    expect(page.contains('formatLimousineMoney'), isFalse);
    expect(
      File(
        'lib/limousine/limousine_quote_inbox_presentation.dart',
      ).readAsStringSync().contains('formatLimousineMoney'),
      isTrue,
    );
  });
}
