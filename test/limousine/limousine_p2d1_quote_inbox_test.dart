import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_entry.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_detail_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_respond_form.dart';

Map<String, dynamic> _item({
  String id = 'qr_1',
  String state = 'requested',
  int revision = 3,
  bool transitionsBlocked = false,
  bool withFulfilment = true,
  bool withQuote = false,
  bool withNote = false,
  Map<String, dynamic>? extra,
}) {
  return <String, dynamic>{
    'quote_request_id': id,
    'state': state,
    'revision': revision,
    'offer_id': 'off_exec',
    'service_class_id': 'executive_sedan',
    'journey_type': 'point_to_point',
    'scheduled_pickup_iso': '2026-08-20T09:00:00Z',
    'roundtrip': false,
    'pax': 2,
    'bags': 1,
    'selected_extra_ids': <String>[],
    'created_at': '2026-08-17T10:00:00Z',
    'updated_at': '2026-08-17T11:00:00Z',
    if (withQuote)
      'quote': <String, dynamic>{
        'total_incl_vat_cents': 18500,
        'currency': 'EUR',
        'vat_treatment': 'incl',
        'expires_at': '2026-08-19T10:00:00Z',
        'terms_revision': 2,
      },
    if (withFulfilment)
      'fulfilment': <String, dynamic>{
        'from': 'Brussels',
        'to': 'Antwerp',
        'stops': <String>['Ghent'],
        if (withNote) 'customer_note': 'Please wait at gate 2',
      },
    'inbox': <String, dynamic>{
      'activity_seq': 4,
      'transitions_blocked': transitionsBlocked,
    },
    ...?extra,
  };
}

LimousineQuoteRequest _record({
  String id = 'qr_1',
  String state = 'requested',
  int revision = 3,
  bool transitionsBlocked = false,
  bool withQuote = false,
  bool withNote = false,
}) {
  return LimousineQuoteRequest.fromJson(
    _item(
      id: id,
      state: state,
      revision: revision,
      transitionsBlocked: transitionsBlocked,
      withQuote: withQuote,
      withNote: withNote,
    ),
  );
}

class _FakeGateway implements LimousineQuoteInboxGateway {
  _FakeGateway({
    this.pages,
    this.detailRecords,
    this.listError,
    this.respondError,
    this.respondRecord,
  });

  List<LimousineQuoteInboxPageData>? pages;
  Map<String, LimousineQuoteRequest>? detailRecords;
  LimousineQuoteInboxException? listError;
  LimousineQuoteInboxException? respondError;
  LimousineQuoteRequest? respondRecord;
  final List<Map<String, dynamic>> listCalls = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> respondCalls = <Map<String, dynamic>>[];
  int _pageIndex = 0;

  @override
  Future<LimousineQuoteInboxPageData> list({
    int pageSize = kLimousineQuoteInboxPageDefault,
    String? state,
    String? cursor,
    String? updatedSince,
    String? tenantId,
    String? companyId,
  }) async {
    listCalls.add(<String, dynamic>{
      'page_size': pageSize,
      'state': state,
      'cursor': cursor,
    });
    if (listError != null) throw listError!;
    final configured = pages;
    if (configured == null || configured.isEmpty) {
      return const LimousineQuoteInboxPageData(
        items: <LimousineQuoteRequest>[],
      );
    }
    if (cursor != null && cursor.isNotEmpty) {
      final next = _pageIndex + 1 < configured.length
          ? configured[_pageIndex + 1]
          : configured.last;
      _pageIndex = (_pageIndex + 1).clamp(0, configured.length - 1);
      return next;
    }
    _pageIndex = 0;
    return configured.first;
  }

  @override
  Future<LimousineQuoteRequest> detail(
    String quoteRequestId, {
    String? tenantId,
    String? companyId,
  }) async {
    final records = detailRecords;
    if (records != null && records.containsKey(quoteRequestId)) {
      return records[quoteRequestId]!;
    }
    if (respondRecord != null &&
        respondRecord!.quoteRequestId == quoteRequestId) {
      return respondRecord!;
    }
    return _record(id: quoteRequestId);
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
    respondCalls.add(<String, dynamic>{
      'quote_request_id': quoteRequestId,
      'action': action,
      'expected_revision': expectedRevision,
      if (quote != null) 'quote': quote,
      if (decline != null) 'decline': decline.toWorkerBody(),
    });
    if (respondError != null) throw respondError!;
    final next =
        respondRecord ??
        _record(
          id: quoteRequestId,
          state: action == 'viewed'
              ? 'viewed_by_company'
              : action == 'decline'
              ? 'declined'
              : 'customer_acceptance_required',
          revision: expectedRevision + 1,
          withQuote: action == 'quote',
        );
    return LimousineQuoteRespondResult(record: next);
  }
}

Widget _app(Widget child, {Size size = const Size(390, 844)}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1-2 entry entitlement', () {
    test('entry hidden without entitlement', () {
      expect(limousineQuoteInboxEntryVisible(entitled: null), isFalse);
      expect(limousineQuoteInboxEntryVisible(entitled: false), isFalse);
    });

    testWidgets('entry hidden widget and entitled reaches inbox', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const LimousineQuoteInboxNavEntry(entitled: false)),
      );
      expect(find.byKey(kLimousineQuoteInboxEntryKey), findsNothing);

      var opened = false;
      await tester.pumpWidget(
        _app(
          LimousineQuoteInboxNavEntry(
            entitled: true,
            onOpen: () => opened = true,
          ),
        ),
      );
      expect(find.byKey(kLimousineQuoteInboxEntryKey), findsOneWidget);
      await tester.tap(find.byKey(kLimousineQuoteInboxEntryKey));
      expect(opened, isTrue);

      final gateway = _FakeGateway(
        pages: [
          LimousineQuoteInboxPageData(items: [_record()]),
        ],
      );
      await tester.pumpWidget(
        _app(LimousineQuoteInboxPage(gateway: gateway, entitled: true)),
      );
      await _pumpFrames(tester);
      expect(find.byKey(kLimousineQuoteInboxPageKey), findsOneWidget);
      expect(find.byKey(kLimousineQuoteInboxListKey), findsOneWidget);
    });
  });

  group('3-6 inbox states and filters', () {
    testWidgets('3) loading', (tester) async {
      final gateway = _FakeGateway(pages: const []);
      await tester.pumpWidget(_app(LimousineQuoteInboxPage(gateway: gateway)));
      expect(find.byKey(kLimousineQuoteInboxLoadingKey), findsOneWidget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('4) empty inbox', (tester) async {
      final gateway = _FakeGateway(
        pages: const [LimousineQuoteInboxPageData(items: [])],
      );
      await tester.pumpWidget(_app(LimousineQuoteInboxPage(gateway: gateway)));
      await _pumpFrames(tester);
      expect(find.byKey(kLimousineQuoteInboxEmptyKey), findsOneWidget);
    });

    testWidgets('5) populated inbox', (tester) async {
      final gateway = _FakeGateway(
        pages: [
          LimousineQuoteInboxPageData(
            items: [
              _record(id: 'qr_a'),
              _record(id: 'qr_b', state: 'viewed_by_company'),
            ],
          ),
        ],
      );
      await tester.pumpWidget(_app(LimousineQuoteInboxPage(gateway: gateway)));
      await _pumpFrames(tester);
      expect(
        find.byKey(const ValueKey('limousine_inbox_row_qr_a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('limousine_inbox_row_qr_b')),
        findsOneWidget,
      );
    });

    test('6) state grouping / filter mapping', () {
      expect(
        LimousineQuoteInboxFilter.requested.serverState,
        LimousineQuoteStateId.requested,
      );
      expect(
        LimousineQuoteInboxFilter.viewed.serverState,
        LimousineQuoteStateId.viewedByCompany,
      );
      expect(LimousineQuoteInboxFilter.waitingForCustomer.serverState, isNull);
      expect(
        LimousineQuoteInboxFilter.waitingForCustomer.accepts('quoted'),
        isTrue,
      );
      expect(
        LimousineQuoteInboxFilter.waitingForCustomer.accepts(
          'customer_acceptance_required',
        ),
        isTrue,
      );
      expect(LimousineQuoteInboxFilter.closed.accepts('declined'), isTrue);
      expect(LimousineQuoteInboxFilter.closed.accepts('expired'), isTrue);
      expect(LimousineQuoteInboxFilter.closed.accepts('withdrawn'), isTrue);
      expect(LimousineQuoteInboxFilter.closed.accepts('superseded'), isTrue);
      expect(LimousineQuoteInboxFilter.closed.accepts('cancelled'), isTrue);
      expect(
        LimousineQuoteInboxFilter.completed.serverState,
        'booking_created',
      );
      expect(LimousineQuoteInboxFilter.accepted.serverState, 'accepted');
    });
  });

  group('7-8 opaque cursor pagination', () {
    test('opaque cursor is never decoded', () {
      const cursor = 'YXsd_opaque_not_json';
      expect(opaqueLimousineInboxCursor(cursor), cursor);
      expect(opaqueLimousineInboxCursor(''), isNull);
    });

    test('7-8 merge replay does not duplicate rows', () async {
      final first = LimousineQuoteInboxPageData(
        items: [_record(id: 'qr_1')],
        nextCursor: 'cursor_a',
        hasMore: true,
      );
      final second = LimousineQuoteInboxPageData(
        items: [_record(id: 'qr_2')],
        nextCursor: null,
        hasMore: false,
      );
      final gateway = _FakeGateway(pages: [first, second]);
      final controller = LimousineQuoteInboxController(gateway: gateway);
      await controller.refresh();
      expect(controller.items.map((e) => e.quoteRequestId), ['qr_1']);
      expect(controller.nextCursor, 'cursor_a');
      await controller.loadMore();
      expect(controller.items.map((e) => e.quoteRequestId), ['qr_1', 'qr_2']);
      final replay = mergeLimousineInboxPages(
        existing: controller.items,
        incoming: second.items,
      );
      expect(replay.map((e) => e.quoteRequestId), ['qr_1', 'qr_2']);
      expect(
        gateway.listCalls.every(
          (c) => c['cursor'] == null || c['cursor'] == 'cursor_a',
        ),
        isTrue,
      );
    });
  });

  group('9-10 detail fields', () {
    testWidgets('supplied fields render; missing is not not-allowed', (
      tester,
    ) async {
      final record = _record(withNote: false);
      final gateway = _FakeGateway(
        detailRecords: {record.quoteRequestId: record},
      );
      await tester.pumpWidget(
        _app(
          LimousineQuoteDetailPage(
            quoteRequestId: record.quoteRequestId,
            initial: record,
            gateway: gateway,
          ),
        ),
      );
      await _pumpFrames(tester);
      expect(find.text('Brussels'), findsOneWidget);
      expect(find.text('Antwerp'), findsOneWidget);
      expect(find.textContaining('not allowed'), findsNothing);
      expect(find.textContaining('niet toegestaan'), findsNothing);
      expect(find.text('Please wait at gate 2'), findsNothing);
    });
  });

  group('11-16 respond / quote / decline', () {
    test('11) viewed carries current expected_revision', () async {
      final gateway = _FakeGateway();
      final controller = LimousineQuoteInboxController(gateway: gateway);
      final record = _record(revision: 7);
      await controller.respond(action: 'viewed', record: record);
      expect(gateway.respondCalls.single['expected_revision'], 7);
      expect(gateway.respondCalls.single['action'], 'viewed');
    });

    test('12) quote form validates all required terms', () {
      final empty = validateLimousineCompanyQuoteDraft(
        const LimousineCompanyQuoteDraft(),
      );
      expect(empty.ok, isFalse);
      expect(empty.missing, contains('total_incl_vat_cents'));
      expect(empty.missing, contains('currency'));
      expect(empty.missing, contains('vat_treatment'));
      expect(empty.missing, contains('expires_at'));
      expect(empty.missing, contains('terms_revision'));
      for (final key in kLimousineRequiredTermsKeys) {
        expect(empty.missing, contains(key));
      }
      final ok = validateLimousineCompanyQuoteDraft(
        const LimousineCompanyQuoteDraft(
          totalInclVatCents: 18500,
          currency: 'EUR',
          vatTreatment: 'incl',
          expiresAt: '2026-08-19T10:00:00Z',
          termsRevision: 1,
          cancellationDeadlineHours: 24,
          cancellationPenaltyPercent: 50,
          waitingTimeIncludedMinutes: 15,
          waitingTimeOverageCentsPerMinute: 80,
          noShowPenaltyPercent: 100,
          overtimeCentsPerHour: 9000,
        ),
      );
      expect(ok.ok, isTrue);
    });

    test('13) money uses cents and ISO currency', () {
      expect(limousineMajorUnitsToCents('185.00'), 18500);
      expect(limousineMajorUnitsToCents('185,50'), 18550);
      expect(limousineMajorUnitsToCents('1.2'), 120);
      expect(limousineMajorUnitsToCents('1.234'), isNull);
      expect(formatLimousineMoney(18500, 'eur'), 'EUR 185.00');
      expect(limousineQuoteIsoCurrencyOrEmpty('eur'), 'EUR');
      expect(limousineQuoteIsoCurrencyOrEmpty('EU'), '');
      final payload = validateLimousineCompanyQuotePayload({
        'total_incl_vat_cents': 100,
        'currency': 'EUR',
        'vat_treatment': 'incl',
        'expires_at': '2026-08-19T10:00:00Z',
        'mystery_margin': 12,
        'terms': {
          'terms_revision': 1,
          'cancellation_deadline_hours': 1,
          'cancellation_penalty_percent': 1,
          'waiting_time_included_minutes': 1,
          'waiting_time_overage_cents_per_minute': 1,
          'no_show_penalty_percent': 1,
          'overtime_cents_per_hour': 1,
          'internal_cost': 9,
        },
      });
      expect(payload.ok, isFalse);
      expect(payload.unknownCritical, contains('mystery_margin'));
      expect(payload.unknownCritical, contains('terms.internal_cost'));
    });

    test('14) successful quote replaces local state', () async {
      final quoted = _record(
        state: 'customer_acceptance_required',
        revision: 4,
        withQuote: true,
      );
      final gateway = _FakeGateway(respondRecord: quoted);
      final controller = LimousineQuoteInboxController(gateway: gateway);
      controller.items = [_record(revision: 3)];
      final result = await controller.respond(
        action: 'quote',
        record: _record(revision: 3),
        quote: const LimousineCompanyQuoteDraft(
          totalInclVatCents: 18500,
          currency: 'EUR',
          vatTreatment: 'incl',
          expiresAt: '2026-08-19T10:00:00Z',
          termsRevision: 1,
          cancellationDeadlineHours: 24,
          cancellationPenaltyPercent: 50,
          waitingTimeIncludedMinutes: 15,
          waitingTimeOverageCentsPerMinute: 80,
          noShowPenaltyPercent: 100,
          overtimeCentsPerHour: 9000,
        ).toWorkerQuote(),
      );
      expect(result.record!.state, 'customer_acceptance_required');
      expect(controller.detail!.revision, 4);
      expect(controller.items.single.revision, 4);
      expect(controller.items.single.quote!.totalInclVatCents, 18500);
    });

    test('15) stale revision triggers refresh', () async {
      final fresh = _record(revision: 9, state: 'viewed_by_company');
      final gateway = _FakeGateway(
        respondError: const LimousineQuoteInboxException(
          kind: LimousineQuoteInboxErrorKind.staleRevision,
          code: 'stale_revision',
          currentRevision: 9,
        ),
        detailRecords: {'qr_1': fresh},
      );
      final controller = LimousineQuoteInboxController(gateway: gateway);
      try {
        await controller.respond(
          action: 'viewed',
          record: _record(revision: 3),
        );
        fail('expected stale');
      } on LimousineQuoteInboxException catch (error) {
        expect(error.kind, LimousineQuoteInboxErrorKind.staleRevision);
      }
      expect(controller.detail!.revision, 9);
      expect(controller.detail!.state, 'viewed_by_company');
    });

    testWidgets('16) decline confirmation and safe reason', (tester) async {
      await tester.pumpWidget(_app(const SizedBox()));
      final future = showLimousineDeclineDialog(
        context: tester.element(find.byType(SizedBox)),
        language: AppLanguage.en,
      );
      await _pumpFrames(tester);
      expect(find.byKey(kLimousineQuoteDeclineDialogKey), findsOneWidget);
      expect(
        find.text('The request stays in history. Nothing is deleted.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'No vehicle available');
      await tester.tap(find.byKey(kLimousineQuoteDeclineKey));
      final draft = await future;
      expect(draft!.reasonCode, kLimousineDeclineReasonCompanyDeclined);
      expect(draft.publicText['en'], 'No vehicle available');
    });
  });

  group('17-20 fail-closed actions', () {
    test('17) transitions_blocked is read-only history', () {
      final actions = limousineQuoteActionsFor(
        _record(transitionsBlocked: true, state: 'viewed_by_company'),
      );
      expect(actions.canQuote, isFalse);
      expect(actions.canDecline, isFalse);
      expect(actions.readOnly, isTrue);
    });

    test('18) accepted/terminal have no commercial actions', () {
      for (final state in <String>[
        'accepted',
        'booking_created',
        'declined',
        'expired',
        'withdrawn',
        'superseded',
        'cancelled',
      ]) {
        final actions = limousineQuoteActionsFor(_record(state: state));
        expect(actions.canQuote, isFalse, reason: state);
        expect(actions.canDecline, isFalse, reason: state);
      }
    });

    test('19) unknown state fails closed', () {
      final actions = limousineQuoteActionsFor(_record(state: 'mystery_state'));
      expect(actions.canMarkViewed, isFalse);
      expect(actions.canQuote, isFalse);
      expect(actions.canDecline, isFalse);
      expect(actions.readOnly, isTrue);
    });

    testWidgets('20) auth/gate/network failure does not crash or leak', (
      tester,
    ) async {
      final gateway = _FakeGateway(
        listError: const LimousineQuoteInboxException(
          kind: LimousineQuoteInboxErrorKind.session,
          code: 'unauthorized',
          statusCode: 401,
        ),
      );
      await tester.pumpWidget(_app(LimousineQuoteInboxPage(gateway: gateway)));
      await _pumpFrames(tester);
      expect(find.byKey(kLimousineQuoteInboxRetryKey), findsOneWidget);
      expect(find.textContaining('Bearer'), findsNothing);
      expect(find.textContaining('status_ref'), findsNothing);
      expect(find.textContaining('acceptance_reference'), findsNothing);
      expect(
        limousineQuoteProjectionLeaksForbidden({
          'status_ref': 'limqs1.secret',
          'email': 'a@b.c',
        }),
        isTrue,
      );
      final parsed = LimousineQuoteRequest.fromJson({
        ..._item(),
        'status_ref': 'limqs1.secret',
        'acceptance_reference': 'limacc1.secret',
        'email': 'hidden@example.com',
      });
      expect(parsed.quoteRequestId, 'qr_1');
    });
  });

  group('21-24 labels, layout, taxi/airport, customer gate', () {
    test('21) NL/EN/FR/ES labels', () {
      expect(kLimousineQuoteInboxEntryTitle.nl, 'Limousineoffertes');
      expect(kLimousineQuoteInboxEntryTitle.en, 'Limousine quotes');
      expect(kLimousineQuoteInboxEntryTitle.fr, 'Devis limousine');
      expect(kLimousineQuoteInboxEntryTitle.es, 'Presupuestos de limusina');
      for (final language in AppLanguage.values) {
        if (language == AppLanguage.de) continue;
        expect(kLimousineQuoteInboxEntryTitle.of(language).trim(), isNotEmpty);
        expect(kLimousineQuoteSendQuote.of(language).trim(), isNotEmpty);
        expect(kLimousineQuoteDecline.of(language).trim(), isNotEmpty);
      }
    });

    testWidgets('22) phone and tablet layout smoke', (tester) async {
      final gateway = _FakeGateway(
        pages: [
          LimousineQuoteInboxPageData(items: [_record()]),
        ],
      );
      await tester.pumpWidget(
        _app(
          LimousineQuoteInboxPage(gateway: gateway),
          size: const Size(390, 844),
        ),
      );
      await _pumpFrames(tester);
      expect(find.byKey(kLimousineQuoteInboxPhoneLayoutKey), findsOneWidget);

      await tester.pumpWidget(
        _app(
          LimousineQuoteInboxPage(gateway: gateway),
          size: const Size(1024, 768),
        ),
      );
      await _pumpFrames(tester);
      expect(find.byKey(kLimousineQuoteInboxTabletLayoutKey), findsOneWidget);
    });

    test('23) taxi and airport navigation remain unchanged', () {
      final home = File(
        'lib/main_parts/business_home_page_state.dart',
      ).readAsStringSync();
      expect(home.contains("nl: 'Boekingen'"), isTrue);
      expect(home.contains('_openBusinessBookingsOverview'), isTrue);
      expect(
        File(
          'lib/calculator_page.dart',
        ).readAsStringSync().contains('limousine_quote_inbox'),
        isFalse,
      );
      expect(
        File(
          'lib/main_parts/role_entry_page.dart',
        ).readAsStringSync().contains('LimousineQuoteInboxPage'),
        isFalse,
      );
    });

    test('24) customer marketplace entry remains OFF', () {
      expect(LimousineCustomerEntryContract.isVisible, isFalse);
      final wrangler = File('workers/booking/wrangler.toml').readAsStringSync();
      expect(wrangler.contains('LIMOUSINE_QUOTE_ENABLED'), isFalse);
      expect(wrangler.contains('LIMOUSINE_BOOK_ENABLED'), isFalse);
      expect(wrangler.contains('LIMOUSINE_MANUAL_QUOTE_ENABLED'), isFalse);
    });

    test('subscription profile preserves authoritative limousine flag', () {
      final entitled = BackendSubscriptionProfile.fromJson({
        'tenant_id': 'c1',
        'company_id': 'c1',
        'plan': 'pro',
        'status': 'active',
        'features': {'limousine': true},
      });
      expect(entitled.features['limousine'], isTrue);
      final denied = BackendSubscriptionProfile.fromJson({
        'tenant_id': 'c1',
        'company_id': 'c1',
        'plan': 'pro',
        'status': 'active',
        'features': {'limousine': false},
      });
      expect(denied.features['limousine'], isFalse);
      expect(
        BackendSubscriptionProfile.defaults().features['limousine'],
        isFalse,
      );
    });
  });
}
