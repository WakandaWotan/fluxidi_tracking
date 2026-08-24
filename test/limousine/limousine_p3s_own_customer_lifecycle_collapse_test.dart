import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_external_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_presentation.dart';

const Size kPhone360 = Size(360, 800);
const Size kPhone390 = Size(390, 844);
const Size kPhone430 = Size(430, 932);
const Size kTabletPortrait = Size(768, 1024);

Map<String, dynamic> _item({
  required String id,
  required String state,
  required int revision,
  String bookingReference = '',
}) {
  return <String, dynamic>{
    'quote_request_id': id,
    'state': state,
    'revision': revision,
    'offer_id': 'off_exec',
    'service_class_id': 'executive_sedan',
    'journey_type': 'point_to_point',
    'scheduled_pickup_iso': '2026-10-01T16:00:00Z',
    'pax': 2,
    'bags': 1,
    'origin_channel': kLimousineExternalOriginChannel,
    'contact_display_name': 'Ada Lovelace',
    'vehicle_snapshot': <String, dynamic>{'public_name': 'Party Limo'},
    'created_at': '2026-08-17T10:00:00Z',
    'updated_at': '2026-08-17T1$revision:00:00Z',
    if (bookingReference.isNotEmpty) 'booking_reference': bookingReference,
    'quote': <String, dynamic>{
      'total_incl_vat_cents': 18500,
      'currency': 'EUR',
      'expires_at': '2026-08-19T10:00:00Z',
      'terms_revision': 2,
    },
    'fulfilment': <String, dynamic>{
      'from': 'Korenmarkt 1, Gent',
      'to': 'Graslei, Gent',
    },
    'external_delivery': <String, dynamic>{
      'invitation_state': state == 'booking_created'
          ? 'booking_created'
          : state == 'accepted'
          ? 'accepted'
          : 'link_created',
    },
    'inbox': <String, dynamic>{
      'activity_seq': revision,
      'transitions_blocked': false,
    },
  };
}

LimousineQuoteRequest _record({
  required String id,
  required String state,
  required int revision,
  String bookingReference = '',
}) {
  return LimousineQuoteRequest.fromJson(
    _item(
      id: id,
      state: state,
      revision: revision,
      bookingReference: bookingReference,
    ),
  );
}

class _FakeGateway implements LimousineQuoteInboxGateway {
  _FakeGateway(this.items);

  final List<LimousineQuoteRequest> items;

  @override
  Future<LimousineQuoteInboxPageData> list({
    int pageSize = 20,
    String? state,
    String? cursor,
    String? updatedSince,
    String? tenantId,
    String? companyId,
  }) async {
    return LimousineQuoteInboxPageData(items: items);
  }

  @override
  Future<LimousineQuoteRequest> detail(
    String quoteRequestId, {
    String? tenantId,
    String? companyId,
  }) async {
    return items.firstWhere((item) => item.quoteRequestId == quoteRequestId);
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

Widget _app(Widget child, {required Size size}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(body: child),
    ),
  );
}

void _bindView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpInbox(
  WidgetTester tester,
  List<LimousineQuoteRequest> items, {
  Size size = kPhone360,
}) async {
  _bindView(tester, size);
  await tester.pumpWidget(
    _app(
      LimousineQuoteInboxPage(embedded: true, gateway: _FakeGateway(items)),
      size: size,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Finder _row(String id) =>
    find.byKey(ValueKey<String>('limousine_inbox_row_$id'));

List<LimousineQuoteRequest> _sameQuoteLifecycle() {
  return <LimousineQuoteRequest>[
    _record(id: 'limq_own', state: 'customer_acceptance_required', revision: 3),
    _record(id: 'limq_own', state: 'accepted', revision: 4),
    _record(
      id: 'limq_own',
      state: 'booking_created',
      revision: 5,
      bookingReference: 'LIMO-2026-001',
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousTheme = businessThemeNotifier.value;
  final previousLang = appLanguageNotifier.value;

  setUp(() {
    appLanguageNotifier.value = AppLanguage.nl;
    businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
  });

  tearDown(() {
    businessThemeNotifier.value = previousTheme;
    appLanguageNotifier.value = previousLang;
  });

  test('controller merge keeps one latest record per quote_request_id', () {
    final merged = mergeLimousineInboxPages(
      existing: const <LimousineQuoteRequest>[],
      incoming: _sameQuoteLifecycle(),
    );
    expect(merged, hasLength(1));
    expect(merged.single.quoteRequestId, 'limq_own');
    expect(merged.single.state, 'booking_created');
    expect(merged.single.bookingReference, 'LIMO-2026-001');
  });

  testWidgets('same quote with sent + accepted + booked renders one card', (
    tester,
  ) async {
    await _pumpInbox(tester, _sameQuoteLifecycle());
    expect(_row('limq_own'), findsOneWidget);
    expect(find.byKey(kLimousineQuoteInboxListKey), findsOneWidget);
    expect(
      find.text(
        kLimousineQuoteInboxStatusLabels[LimousineQuoteStateId.bookingCreated]!
            .of(AppLanguage.nl),
      ),
      findsWidgets,
    );
    expect(find.textContaining('limq_'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accepted-only quote renders one accepted card', (tester) async {
    await _pumpInbox(tester, [
      _record(id: 'limq_acc', state: 'accepted', revision: 4),
    ]);
    expect(_row('limq_acc'), findsOneWidget);
    expect(
      find.text(
        kLimousineQuoteInboxStatusLabels[LimousineQuoteStateId.accepted]!.of(
          AppLanguage.nl,
        ),
      ),
      findsWidgets,
    );
  });

  testWidgets('waiting-only quote renders one waiting card', (tester) async {
    await _pumpInbox(tester, [
      _record(
        id: 'limq_wait',
        state: 'customer_acceptance_required',
        revision: 3,
      ),
    ]);
    expect(_row('limq_wait'), findsOneWidget);
    expect(
      find.text(
        kLimousineQuoteInboxStatusLabels[LimousineQuoteStateId
                .customerAcceptanceRequired]!
            .of(AppLanguage.nl),
      ),
      findsWidgets,
    );
  });

  testWidgets('unrelated quotes remain separate cards', (tester) async {
    await _pumpInbox(tester, [
      _record(id: 'limq_a', state: 'accepted', revision: 2),
      _record(id: 'limq_b', state: 'customer_acceptance_required', revision: 1),
    ]);
    expect(_row('limq_a'), findsOneWidget);
    expect(_row('limq_b'), findsOneWidget);
  });

  testWidgets('phone and tablet portraits do not overflow', (tester) async {
    for (final size in const [
      kPhone360,
      kPhone390,
      kPhone430,
      kLimousinePhonePortrait,
      kTabletPortrait,
    ]) {
      await _pumpInbox(tester, _sameQuoteLifecycle(), size: size);
      expect(_row('limq_own'), findsOneWidget, reason: '$size');
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });
}
