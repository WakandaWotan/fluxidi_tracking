import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_entry.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_requests_nav.dart';

VehicleProfile _vehicle({
  String id = 'v1',
  String name = 'Coach',
  String category = '',
  bool active = true,
}) {
  return VehicleProfile(
    id: id,
    vehicleName: name,
    brandModel: name,
    licensePlate: '1-ABC-123',
    color: 'black',
    passengerCapacity: 4,
    luggageCapacity: 2,
    tierId: 'comfort',
    isActive: active,
    driverId: null,
    primaryPhotoRef: '',
    galleryPhotoRefs: const <String>[],
    serviceCategory: category,
  );
}

Map<String, dynamic> _quoteOffer({bool enabled = true}) {
  return <String, dynamic>{
    'offer_id': 'off_quote',
    'enabled': enabled,
    'published': false,
    'price_presentation': LimousinePricePresentation.quoteRequired,
    'currency': 'EUR',
    'target_type': LimousineOfferTarget.serviceClass,
    'service_class_id': 'executive_sedan',
  };
}

Map<String, dynamic> _fromPriceOffer() {
  return <String, dynamic>{
    'offer_id': 'off_from',
    'enabled': true,
    'published': true,
    'price_presentation': LimousinePricePresentation.fromPrice,
    'display_amount_cents': 25000,
    'currency': 'EUR',
    'target_type': LimousineOfferTarget.serviceClass,
    'service_class_id': 'executive_sedan',
  };
}

class _FakeGateway implements LimousineQuoteInboxGateway {
  _FakeGateway({this.pages, this.listError});

  List<LimousineQuoteInboxPageData>? pages;
  LimousineQuoteInboxException? listError;
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
}

Widget _app(Widget child, {Size size = kLimousinePhonePortrait}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(body: child),
    ),
  );
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetLimousineQuoteRequestsConfirmedOffers();
    appLanguageNotifier.value = AppLanguage.nl;
    businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
  });

  tearDown(resetLimousineQuoteRequestsConfirmedOffers);

  test('no active limousine vehicle hides the quote tab', () {
    expect(
      limousineQuoteRequestsTabVisible(
        serverConfirmedVehicles: [
          _vehicle(category: ''),
          _vehicle(id: 'v2', category: 'limousine', active: false),
        ],
        serverConfirmedOffers: [_quoteOffer()],
      ),
      isFalse,
    );
  });

  test('unsaved local limousine checkbox does not reveal the tab', () {
    final saved = [_vehicle(name: 'S-Class', category: '')];
    final draft = [_vehicle(name: 'S-Class', category: 'limousine')];
    expect(
      limousineQuoteRequestsTabVisible(
        serverConfirmedVehicles: saved,
        serverConfirmedOffers: [_quoteOffer()],
      ),
      isFalse,
    );
    expect(
      limousineQuoteRequestsTabVisible(
        serverConfirmedVehicles: draft,
        serverConfirmedOffers: [_quoteOffer()],
      ),
      isTrue,
    );
  });

  test('vehicle name or marketplace flag is not authority', () {
    expect(
      limousineQuoteRequestsTabVisible(
        serverConfirmedVehicles: [_vehicle(name: 'Limousine')],
        serverConfirmedOffers: [_quoteOffer()],
      ),
      isFalse,
    );
    expect(kLimousineMarketplaceCustomerEntryEnabled, isFalse);
  });

  test('saved limousine without prijs op aanvraag hides the tab', () {
    expect(
      limousineQuoteRequestsTabVisible(
        serverConfirmedVehicles: [_vehicle(category: 'limousine')],
        serverConfirmedOffers: [_fromPriceOffer(), _quoteOffer(enabled: false)],
      ),
      isFalse,
    );
  });

  test('both server-confirmed conditions show the tab', () {
    expect(
      limousineQuoteRequestsTabVisible(
        serverConfirmedVehicles: [_vehicle(category: 'limousine')],
        serverConfirmedOffers: [_quoteOffer()],
      ),
      isTrue,
    );
  });

  test('dashboard no longer contains the Limousineoffertes tile', () {
    final home = File(
      'lib/main_parts/business_home_page_state.dart',
    ).readAsStringSync();
    expect(home.contains('LimousineQuoteInboxDashboardTile'), isFalse);
    expect(home.contains('_openLimousineQuoteInbox'), isFalse);
    expect(home.contains('_refreshLimousineQuoteInboxCount'), isFalse);
    expect(home.contains("nl: 'Boekingen'"), isTrue);
    expect(home.contains('_openBusinessBookingsOverview'), isTrue);
  });

  testWidgets('bookings section is the default and reuses the inbox', (
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
              quoteRequests: LimousineQuoteInboxPage(
                embedded: true,
                gateway: gateway,
              ),
            );
          },
        ),
      ),
    );
    await _pumpFrames(tester);
    expect(find.byKey(kLimousineBookingsQuoteSwitchKey), findsOneWidget);
    expect(find.text('EXISTING_BOOKINGS_LIST'), findsOneWidget);
    expect(find.byKey(kLimousineQuoteInboxPageKey), findsNothing);
    expect(gateway.listCalls, 0);

    await tester.tap(find.byKey(kLimousineQuoteRequestsSectionTabKey));
    await _pumpFrames(tester);
    expect(find.byKey(kLimousineQuoteInboxPageKey), findsOneWidget);
    expect(find.text('EXISTING_BOOKINGS_LIST'), findsNothing);
    expect(gateway.listCalls, 1);

    await tester.tap(find.byKey(kLimousineBookingsSectionTabKey));
    await _pumpFrames(tester);
    expect(find.text('EXISTING_BOOKINGS_LIST'), findsOneWidget);
    expect(find.byKey(kLimousineQuoteInboxPageKey), findsNothing);
  });

  testWidgets('hidden tab leaves the bookings page unchanged', (tester) async {
    await tester.pumpWidget(
      _app(
        const LimousineBookingsSectionHost(
          quoteRequestsVisible: false,
          section: LimousineBookingsSection.bookings,
          onSectionChanged: _ignoreSection,
          bookings: Text('EXISTING_BOOKINGS_LIST'),
          quoteRequests: Text('QUOTE_INBOX_SHOULD_STAY_HIDDEN'),
        ),
      ),
    );
    expect(find.byKey(kLimousineBookingsQuoteSwitchKey), findsNothing);
    expect(find.text('EXISTING_BOOKINGS_LIST'), findsOneWidget);
    expect(find.text('QUOTE_INBOX_SHOULD_STAY_HIDDEN'), findsNothing);
  });

  testWidgets('gates-off shows a compact test message and keeps bookings', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      listError: const LimousineQuoteInboxException(
        kind: LimousineQuoteInboxErrorKind.gateOff,
        code: 'not_found',
        statusCode: 404,
      ),
    );
    var section = LimousineBookingsSection.quoteRequests;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            return LimousineBookingsSectionHost(
              quoteRequestsVisible: true,
              section: section,
              onSectionChanged: (next) => setState(() => section = next),
              bookings: const Text('EXISTING_BOOKINGS_LIST'),
              quoteRequests: LimousineQuoteInboxPage(
                embedded: true,
                gateway: gateway,
              ),
            );
          },
        ),
      ),
    );
    await _pumpFrames(tester);
    expect(find.byKey(kLimousineQuoteInboxGateOffKey), findsOneWidget);
    expect(
      find.text('Limousineoffertes zijn nog niet actief in deze testomgeving.'),
      findsOneWidget,
    );
    expect(find.textContaining('not_found'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.byKey(kLimousineQuoteInboxRetryKey), findsNothing);
    await tester.tap(find.byKey(kLimousineBookingsSectionTabKey));
    await _pumpFrames(tester);
    expect(find.text('EXISTING_BOOKINGS_LIST'), findsOneWidget);
  });

  testWidgets('NL EN FR ES chrome stays translated', (tester) async {
    for (final language in const [
      AppLanguage.nl,
      AppLanguage.en,
      AppLanguage.fr,
      AppLanguage.es,
    ]) {
      appLanguageNotifier.value = language;
      await tester.pumpWidget(
        _app(
          LimousineBookingsSectionHost(
            quoteRequestsVisible: true,
            section: LimousineBookingsSection.bookings,
            onSectionChanged: _ignoreSection,
            language: language,
            bookings: const SizedBox.shrink(),
            quoteRequests: const SizedBox.shrink(),
          ),
        ),
      );
      expect(
        find.text(kLimousineBookingsSectionLabel.of(language)),
        findsWidgets,
      );
      expect(
        find.text(kLimousineQuoteRequestsSectionLabel.of(language)),
        findsOneWidget,
      );
    }
  });

  testWidgets('light dark blue gold and phone tablet stay themed', (
    tester,
  ) async {
    for (final variant in const [
      BusinessThemeVariant.cleanProfessional,
      BusinessThemeVariant.executiveGold,
      BusinessThemeVariant.corporateBlue,
      BusinessThemeVariant.brandSignatureGold,
    ]) {
      businessThemeNotifier.value = variant;
      final palette = paletteForBusinessTheme(variant);
      for (final size in const [kLimousinePhonePortrait, Size(1024, 768)]) {
        await tester.pumpWidget(
          _app(
            LimousineBookingsQuoteRequestsSwitch(
              section: LimousineBookingsSection.bookings,
              onChanged: _ignoreSection,
              unreadCount: 2,
            ),
            size: size,
          ),
        );
        final material = tester.widget<Material>(
          find.byKey(kLimousineBookingsQuoteSwitchKey),
        );
        expect(material.color, palette.surface, reason: variant.name);
        expect(find.byKey(kLimousineQuoteRequestsTabBadgeKey), findsOneWidget);
      }
    }
  });

  test('accepted quote without /book is not a booking', () {
    final accepted = LimousineQuoteRequest.fromJson(<String, dynamic>{
      'quote_request_id': 'qr_accepted',
      'state': 'accepted',
      'revision': 4,
      'offer_id': 'off_exec',
      'quote': <String, dynamic>{
        'total_incl_vat_cents': 18500,
        'currency': 'EUR',
        'expires_at': '2026-08-19T10:00:00Z',
        'terms_revision': 2,
      },
    });
    expect(accepted.quoteRequestId, 'qr_accepted');
    expect(accepted.bookingReference, isEmpty);
    expect(accepted.state, 'accepted');

    final bookings = File(
      'lib/main_parts/company_bookings_overview_page.dart',
    ).readAsStringSync();
    expect(bookings.contains('quote_request_id'), isFalse);
    expect(bookings.contains("kListBookingsPath"), isTrue);
    expect(bookings.contains('LimousineQuoteInboxPage'), isTrue);
    expect(bookings.contains('_all.addAll(_controller.items)'), isFalse);
  });

  test('no extra polling, cron, KV list or new network route', () {
    final nav = File(
      'lib/limousine/limousine_quote_requests_nav.dart',
    ).readAsStringSync();
    final bookings = File(
      'lib/main_parts/company_bookings_overview_page.dart',
    ).readAsStringSync();
    final home = File(
      'lib/main_parts/business_home_page_state.dart',
    ).readAsStringSync();
    expect(nav.contains('Timer.periodic'), isFalse);
    expect(nav.contains('/admin/pricing/limousine'), isFalse);
    expect(nav.contains('KV'), isFalse);
    expect(bookings.contains('Timer.periodic'), isFalse);
    expect(bookings.contains('fetchAdminLimousinePricing'), isTrue);
    expect(
      bookings.contains('HttpLimousineQuoteInboxGateway().list()'),
      isFalse,
    );
    expect(home.contains('HttpLimousineQuoteInboxGateway().list()'), isFalse);
    expect(
      File(
        'lib/limousine/limousine_quote_inbox_page.dart',
      ).readAsStringSync().contains('/book'),
      isFalse,
    );
  });
}

void _ignoreSection(LimousineBookingsSection _) {}
