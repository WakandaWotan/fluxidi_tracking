import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_external_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_external_quote_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_presentation.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_requests_nav.dart';

const Size kPhone360 = Size(360, 800);
const Size kPhone390 = Size(390, 844);
const Size kPhone430 = Size(430, 932);
const Size kTabletPortrait = Size(768, 1024);

const String _pickup = 'Korenmarkt 1, 9000 Gent, België';
const String _destination = 'Grand-Place 1, 1000 Bruxelles, Belgique';

Map<String, dynamic> _item({
  String id = 'limq_phone',
  String state = 'requested',
  int? durationMinutes = 0,
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
    'origin_channel': kLimousineExternalOriginChannel,
    'contact_display_name': 'Ada Lovelace',
    'vehicle_snapshot': <String, dynamic>{'public_name': 'Mercedes S-Class'},
    'created_at': '2026-08-17T10:00:00Z',
    'updated_at': '2026-08-17T11:00:00Z',
    'quote': <String, dynamic>{
      'total_incl_vat_cents': 18500,
      'currency': 'EUR',
      'expires_at': '2026-08-19T10:00:00Z',
      'terms_revision': 2,
    },
    'fulfilment': <String, dynamic>{
      'from': _pickup,
      'to': _destination,
      'requested_duration_minutes': durationMinutes,
    },
    'inbox': <String, dynamic>{'activity_seq': 1, 'transitions_blocked': false},
  };
}

LimousineQuoteRequest _record({
  String id = 'limq_phone',
  int? durationMinutes = 0,
}) {
  return LimousineQuoteRequest.fromJson(
    _item(id: id, durationMinutes: durationMinutes),
  );
}

class _FakeGateway implements LimousineQuoteInboxGateway {
  _FakeGateway({this.pages});

  List<LimousineQuoteInboxPageData>? pages;

  @override
  Future<LimousineQuoteInboxPageData> list({
    int pageSize = 20,
    String? state,
    String? cursor,
    String? updatedSince,
    String? tenantId,
    String? companyId,
  }) async {
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

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

_FakeGateway _gateway() {
  return _FakeGateway(
    pages: [
      LimousineQuoteInboxPageData(items: [_record()]),
    ],
  );
}

Future<void> _pumpInboxHost(
  WidgetTester tester, {
  required Size size,
  AppLanguage language = AppLanguage.nl,
  int? unreadCount = 2,
}) async {
  _bindView(tester, size);
  appLanguageNotifier.value = language;
  await tester.pumpWidget(
    _app(
      LimousineBookingsSectionHost(
        quoteRequestsVisible: true,
        section: LimousineBookingsSection.quoteRequests,
        onSectionChanged: (_) {},
        unreadCount: unreadCount,
        language: language,
        bookings: const SizedBox.shrink(),
        quoteRequests: LimousineQuoteInboxPage(
          embedded: true,
          gateway: _gateway(),
        ),
      ),
      size: size,
    ),
  );
  await _pumpFrames(tester);
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

  test('summary cards hide internal ids and zero duration', () {
    final record = _record();
    expect(limousineQuoteInboxLooksInternalId('limq_phone'), isTrue);
    expect(limousineQuoteInboxLooksInternalId('qr_1'), isTrue);
    expect(limousineQuoteInboxLooksInternalId('REF-2026-1'), isFalse);
    expect(limousineQuoteInboxPublicReference(record), 'limq_phone');
    expect(limousineQuoteInboxCardReference(record), isEmpty);
    expect(limousineQuoteInboxShowsRequestedDuration(0), isFalse);
    expect(limousineQuoteInboxShowsRequestedDuration(45), isTrue);
    expect(limousineQuoteInboxPickupText(record), _pickup);
    expect(limousineQuoteInboxDestinationText(record), _destination);
    expect(
      limousineQuoteInboxCardHeading(record, AppLanguage.nl),
      'Ada Lovelace',
    );
  });

  testWidgets('phone and tablet portraits do not overflow', (tester) async {
    for (final size in const [
      kPhone360,
      kPhone390,
      kPhone430,
      kLimousinePhonePortrait,
      kTabletPortrait,
    ]) {
      await _pumpInboxHost(tester, size: size);
      expect(tester.takeException(), isNull, reason: '$size');
      expect(find.byKey(kLimousineQuoteInboxTestBadgeKey), findsOneWidget);
      expect(find.text('Testomgeving'), findsOneWidget);
    }
  });

  testWidgets('main tabs keep full NL EN FR ES labels on phone', (
    tester,
  ) async {
    for (final language in const [
      AppLanguage.nl,
      AppLanguage.en,
      AppLanguage.fr,
      AppLanguage.es,
    ]) {
      final label = kLimousineQuoteRequestsSectionLabel.of(language);
      await _pumpInboxHost(tester, size: kPhone360, language: language);
      expect(find.text(label), findsWidgets, reason: language.name);
      expect(find.textContaining('Offerteaanvrag...'), findsNothing);
      final tabLabel = tester.widget<Text>(
        find.descendant(
          of: find.byKey(kLimousineQuoteRequestsSectionTabKey),
          matching: find.text(label),
        ),
      );
      expect(tabLabel.maxLines, 2, reason: language.name);
      expect(tabLabel.overflow, isNot(TextOverflow.ellipsis));
      expect(tabLabel.softWrap, isTrue);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byKey(kLimousineQuoteRequestsSectionTabKey),
          matching: find.text(label),
        ),
      );
      expect(paragraph.didExceedMaxLines, isFalse, reason: language.name);
      expect(find.byKey(kLimousineQuoteRequestsTabBadgeKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('KPI Te beantwoorden wraps in two lines on phone', (
    tester,
  ) async {
    await _pumpInboxHost(tester, size: kPhone360);
    final title = tester.widget<Text>(
      find.descendant(
        of: find.byKey(limousineQuoteInboxKpiKey('toAnswer')),
        matching: find.text(kLimousineQuoteInboxKpiToAnswer.of(AppLanguage.nl)),
      ),
    );
    expect(title.maxLines, 2);
    expect(title.softWrap, isTrue);
    expect(title.overflow, isNot(TextOverflow.ellipsis));
    expect(
      find.text(kLimousineQuoteInboxKpiToAnswerHint.of(AppLanguage.nl)),
      findsNothing,
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byKey(limousineQuoteInboxKpiKey('toAnswer')),
        matching: find.text(kLimousineQuoteInboxKpiToAnswer.of(AppLanguage.nl)),
      ),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
  });

  testWidgets('phone card uses structured route and hides limq_ and 0m', (
    tester,
  ) async {
    await _pumpInboxHost(tester, size: kPhone360);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('limousine_inbox_row_limq_phone')),
    );
    expect(find.byKey(kLimousineQuoteInboxPhoneLayoutKey), findsOneWidget);
    expect(
      find.byKey(limousineQuoteInboxCardPickupKey('limq_phone')),
      findsOneWidget,
    );
    expect(
      find.byKey(limousineQuoteInboxCardDestinationKey('limq_phone')),
      findsOneWidget,
    );
    expect(find.text(_pickup), findsOneWidget);
    expect(find.text(_destination), findsOneWidget);
    expect(find.text('$_pickup · $_destination'), findsNothing);
    expect(find.textContaining('limq_'), findsNothing);
    expect(find.text('0m'), findsNothing);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Mercedes S-Class'), findsOneWidget);
    expect(
      find.text(kLimousineOwnCustomerOrigin.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(
      find.byKey(limousineQuoteInboxCardAmountKey('limq_phone')),
      findsOneWidget,
    );
    final firstAction = find.byKey(
      limousineQuoteInboxActionKey('limq_phone', 'editQuote'),
    );
    expect(firstAction, findsOneWidget);
    expect(tester.widget(firstAction), isA<FilledButton>());
    expect(tester.getSize(firstAction).height, greaterThanOrEqualTo(44));
  });

  testWidgets('tablet layout key stays tablet', (tester) async {
    await _pumpInboxHost(tester, size: kTabletPortrait);
    expect(find.byKey(kLimousineQuoteInboxTabletLayoutKey), findsOneWidget);
    expect(find.byKey(kLimousineQuoteInboxPhoneLayoutKey), findsNothing);
    final tabLabel = tester.widget<Text>(
      find.descendant(
        of: find.byKey(kLimousineQuoteRequestsSectionTabKey),
        matching: find.text(
          kLimousineQuoteRequestsSectionLabel.of(AppLanguage.nl),
        ),
      ),
    );
    expect(tabLabel.maxLines, 1);
    expect(tester.takeException(), isNull);
  });
}
