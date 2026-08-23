import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_entry.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_request_history.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_requests_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_marketplace_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_presentation.dart';
import 'package:fluxidi_tracking/main_parts/street_business_invoice_support.dart';
import 'package:fluxidi_tracking/main_parts/street_business_invoice_widgets.dart';

const String _statusRef = 'limqs1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM';

Map<String, dynamic> _quoteJson({
  required String id,
  required String state,
  bool quotationAvailable = false,
  bool companyViewed = false,
  bool withQuote = false,
  int total = 60000,
}) {
  return <String, dynamic>{
    'quote_request_id': id,
    'state': state,
    'revision': 1,
    'locale': 'nl',
    'offer_id': 'off_1',
    'service_class_id': 'executive_sedan',
    'journey_type': 'point_to_point',
    'scheduled_pickup_iso': '2026-09-01T10:00:00Z',
    'pax': 2,
    'bags': 1,
    'company_viewed': companyViewed,
    'quotation_available': quotationAvailable,
    if (quotationAvailable) 'quotation_sent_at': '2026-08-22T10:00:00Z',
    if (quotationAvailable || withQuote)
      'quotation_total_incl_vat_cents': total,
    'quotation_currency': 'EUR',
    'vehicle_snapshot': <String, dynamic>{'public_name': 'Mercedes S-Class'},
    'fulfilment': <String, dynamic>{
      'from': 'Antwerpen Centraal',
      'to': 'Brussel Zuid',
    },
    if (withQuote || quotationAvailable)
      'quote': <String, dynamic>{
        'total_incl_vat_cents': total,
        'currency': 'EUR',
        'vat_treatment': 'incl',
        'quoted_at': '2026-08-22T10:00:00Z',
        'expires_at': '2099-01-01T00:00:00Z',
        'terms_revision': 1,
      },
  };
}

LimousineQuoteRequest _request({
  required String id,
  required String state,
  bool quotationAvailable = false,
  bool companyViewed = false,
  bool withQuote = false,
}) {
  return LimousineQuoteRequest.fromJson(
    _quoteJson(
      id: id,
      state: state,
      quotationAvailable: quotationAvailable,
      companyViewed: companyViewed,
      withQuote: withQuote,
    ),
  );
}

LimousineCustomerRequestRecord _record({
  required String id,
  required String state,
  bool quotationAvailable = false,
  bool companyViewed = false,
  bool withQuote = false,
}) {
  return LimousineCustomerRequestRecord(
    quoteRequestId: id,
    statusRef: _statusRef,
    state: state,
    companyName: 'Coachline',
    vehicleDisplayName: 'Mercedes S-Class',
    from: 'Antwerpen Centraal',
    to: 'Brussel Zuid',
    scheduledPickupIso: '2026-09-01T10:00:00Z',
    request: _request(
      id: id,
      state: state,
      quotationAvailable: quotationAvailable,
      companyViewed: companyViewed,
      withQuote: withQuote,
    ),
  );
}

class _StatusGateway with LimousineCustomerQuoteGateway {
  _StatusGateway(this.live);

  LimousineQuoteRequest live;
  int pollCalls = 0;
  int deleteCalls = 0;

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
    return live;
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

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required LimousineCustomerRequestRecord record,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final vault = MemoryLimousineCustomerRequestHistoryVault();
  final history = LimousineCustomerRequestHistoryRepository(vault: vault);
  await history.upsert(record);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LimousineCustomerRequestsSection(
          history: history,
          gateway: _StatusGateway(record.request!),
          quoteEnabled: true,
        ),
      ),
    ),
  );
  await _pump(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    appLanguageNotifier.value = AppLanguage.nl;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  group('customer limousine request cards', () {
    testWidgets('requested card is full-width with company route and hide', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        record: _record(id: 'limq_req', state: 'requested'),
      );
      final card = find.byKey(limousineCustomerRequestCardKey('limq_req'));
      expect(card, findsOneWidget);
      expect(
        tester.getSize(card).width,
        tester.getSize(find.byType(Scaffold)).width,
      );
      expect(find.text('Aanvraag verzonden'), findsOneWidget);
      expect(find.text('Coachline'), findsOneWidget);
      expect(find.text('Mercedes S-Class'), findsOneWidget);
      expect(find.text('Antwerpen Centraal'), findsOneWidget);
      expect(find.text('Brussel Zuid'), findsOneWidget);
      expect(find.text('limq_req'), findsOneWidget);
      expect(
        find.text(
          limousineQuoteDisplayOrEmpty('2026-09-01T10:00:00Z', AppLanguage.nl),
        ),
        findsOneWidget,
      );
      expect(find.text(kLimousineCustomerHideFromOverview.nl), findsOneWidget);
    });

    testWidgets('viewed card uses Bekeken door bedrijf', (tester) async {
      await _pumpCard(
        tester,
        record: _record(
          id: 'limq_view',
          state: 'viewed_by_company',
          companyViewed: true,
        ),
      );
      expect(find.text('Bekeken door bedrijf'), findsOneWidget);
      expect(find.text(kLimousineCustomerHideFromOverview.nl), findsOneWidget);
    });

    testWidgets('quoted card shows amount and Offerte ontvangen', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        record: _record(
          id: 'limq_quoted',
          state: 'quoted',
          quotationAvailable: true,
          withQuote: true,
        ),
      );
      expect(find.text('Offerte ontvangen'), findsOneWidget);
      expect(find.text(formatLimousineEuroAmount(60000)), findsOneWidget);
      expect(find.text('Coachline'), findsOneWidget);
      expect(find.text('Antwerpen Centraal'), findsOneWidget);
    });

    testWidgets('accepted card uses Verbergen', (tester) async {
      await _pumpCard(
        tester,
        record: _record(
          id: 'limq_acc',
          state: 'accepted',
          quotationAvailable: true,
          withQuote: true,
        ),
      );
      expect(find.text('Offerte geaccepteerd'), findsOneWidget);
      expect(find.text(kLimousineCustomerHideAfterBooking.nl), findsOneWidget);
    });

    testWidgets('booking-created card keeps booking chrome', (tester) async {
      await _pumpCard(
        tester,
        record: _record(
          id: 'limq_book',
          state: 'booking_created',
          quotationAvailable: true,
          withQuote: true,
        ),
      );
      expect(find.text('Boeking aangemaakt'), findsOneWidget);
      expect(find.text(formatLimousineEuroAmount(60000)), findsOneWidget);
      expect(find.text(kLimousineCustomerHideAfterBooking.nl), findsOneWidget);
    });

    testWidgets('hide removes local history only', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final vault = MemoryLimousineCustomerRequestHistoryVault();
      final history = LimousineCustomerRequestHistoryRepository(vault: vault);
      final record = _record(
        id: 'limq_hide',
        state: 'booking_created',
        quotationAvailable: true,
        withQuote: true,
      );
      await history.upsert(record);
      final canonical = <String, dynamic>{
        'quote_request_id': 'limq_hide',
        'booking_id': '2026-08-176',
        'invoice_id': 'INV-2026-000071',
      };
      final gateway = _StatusGateway(record.request!);
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
      await tester.tap(
        find.byKey(limousineCustomerRequestHideKey('limq_hide')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          kLimousineCustomerHideAfterBooking.nl,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(limousineCustomerRequestCardKey('limq_hide')),
        findsNothing,
      );
      expect(await history.list(), isEmpty);
      expect(gateway.deleteCalls, 0);
      expect(canonical['invoice_id'], 'INV-2026-000071');
      expect(canonical['booking_id'], '2026-08-176');
    });

    test('hide helper never deletes Worker quote or booking', () {
      final source = File(
        'lib/limousine/limousine_customer_requests_page.dart',
      ).readAsStringSync();
      expect(source.contains('removeByQuoteRequestId'), isTrue);
      expect(source.contains('kLimousineCustomerHideConfirmBody'), isTrue);
      expect(source.contains('/quotes/'), isFalse);
      expect(source.contains('deleteQuote'), isFalse);
      expect(source.contains('cancelBooking'), isFalse);
    });
  });

  group('limousine nav and labels', () {
    test('label is Limousine and never Boek nu / Boek een', () {
      expect(kLimousineBookLabel.nl, 'Limousine');
      expect(kLimousineBookLabel.en, 'Limousine');
      expect(kLimousineBookLabel.fr, 'Limousine');
      expect(kLimousineBookLabel.es, 'Limusina');
      expect(LimousineCustomerEntryContract.bookLabel.nl, 'Limousine');
      final labels = File(
        'lib/limousine/limousine_marketplace_labels.dart',
      ).readAsStringSync();
      expect(labels.contains('Boek nu limousine'), isFalse);
      expect(labels.contains('Boek een limousine'), isFalse);
    });

    test('home card visibility is only the dart-define gate', () {
      expect(
        LimousineCustomerEntryContract.isVisible,
        kLimousineMarketplaceCustomerEntryEnabled,
      );
      expect(kLimousineMarketplaceCustomerEntryEnabled, isFalse);
      final home = File(
        'lib/main_parts/customer_home_page.dart',
      ).readAsStringSync();
      final start = home.indexOf('Widget? _limousineCustomerCard(');
      expect(start, greaterThan(0));
      final body = home.substring(start, start + 900);
      expect(
        body.contains(
          'if (!LimousineCustomerEntryContract.isVisible) return null;',
        ),
        isTrue,
      );
      expect(body.contains('appLanguageNotifier'), isFalse);
      expect(body.contains('customerThemeNotifier'), isFalse);
      expect(
        body.contains('limousineBookLabelFor(appConfig.currentLanguage)'),
        isTrue,
      );
      expect(
        home.contains(
          "key: const ValueKey<String>('limousine_customer_entry_card')",
        ),
        isTrue,
      );
      expect(
        File(
          'lib/limousine/limousine_customer_entry.dart',
        ).readAsStringSync().contains('defaultValue: false'),
        isTrue,
      );
    });

    test('gate is not wrapped by theme language resume or refresh', () {
      final home = File(
        'lib/main_parts/customer_home_page.dart',
      ).readAsStringSync();
      expect(home.contains('if (_limousineCustomerCard('), isTrue);
      expect(home.contains('LimousineCustomerEntryContract.isVisible'), isTrue);
      expect(
        home.contains('kLimousineMarketplaceCustomerEntryEnabled'),
        isFalse,
      );
    });
  });

  group('light and dark contrast', () {
    test('customer bottom nav uses full muted text on light ivory', () {
      final light = paletteForCustomerTheme(CustomerThemeVariant.premiumLight);
      final ivory = paletteForCustomerTheme(CustomerThemeVariant.ivoryGold);
      final dark = paletteForCustomerTheme(CustomerThemeVariant.nightGold);
      expect(
        brandSignatureContrastRatio(light.textMuted, light.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        brandSignatureContrastRatio(ivory.textMuted, ivory.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        brandSignatureContrastRatio(dark.textMuted, dark.background),
        greaterThanOrEqualTo(3.0),
      );
      final home = File(
        'lib/main_parts/customer_home_page.dart',
      ).readAsStringSync();
      expect(home.contains('_isNightGold'), isTrue);
      expect(home.contains('_themePalette.textMuted'), isTrue);
      expect(
        home.contains('unselectedItemColor: _premiumMuted.withOpacity(0.82)'),
        isFalse,
      );
    });

    test('limousine cards pair light surface with dark text', () {
      for (final variant in <CustomerThemeVariant>[
        CustomerThemeVariant.premiumLight,
        CustomerThemeVariant.nightGold,
      ]) {
        final palette = paletteForCustomerTheme(variant);
        expect(
          brandSignatureContrastRatio(palette.textPrimary, palette.surface),
          greaterThanOrEqualTo(4.5),
        );
      }
      final source = File(
        'lib/limousine/limousine_customer_requests_page.dart',
      ).readAsStringSync();
      expect(source.contains('palette.isDark'), isTrue);
      expect(source.contains('width: double.infinity'), isTrue);
    });

    test('driver My Rides light emerald pills are no longer gold-on-ivory', () {
      final pairing = driverRideCardColors(DriverThemeVariant.lightEmerald);
      expect(
        brandSignatureContrastRatio(pairing.foreground, pairing.surface),
        greaterThanOrEqualTo(4.5),
      );
      final source = File(
        'lib/main_parts/driver_home_page_state.dart',
      ).readAsStringSync();
      expect(source.contains('_rideCardSchedulePillColors'), isTrue);
      expect(source.contains('_lightEmeraldGhostButtonStyle()'), isTrue);
      expect(
        source.contains(
          'isLightEmerald\n        ? _lightEmeraldGhostButtonStyle()',
        ),
        isTrue,
      );
    });
  });

  group('Billit manual mode copy', () {
    test('unlinked paid invoice tells the user to link manually', () {
      expect(
        streetInvoicePaymentStatusLabel(
          AppLanguage.nl,
          StreetInvoiceInvoicePaymentStatus.notLinkedToBillit,
        ),
        'Koppel handmatig in Billit (auto-aanmaak staat uit)',
      );
      expect(
        streetInvoicePaymentStatusLabel(
          AppLanguage.en,
          StreetInvoiceInvoicePaymentStatus.notLinkedToBillit,
        ),
        'Link manually in Billit (auto-create is off)',
      );
      final worker = File(
        'workers/booking/modules/street_business_invoice.js',
      ).readAsStringSync();
      expect(
        worker.contains('existing_invoice_no_order_auto_create_off'),
        isTrue,
      );
      expect(worker.contains('if (autoCreateEnabled !== true)'), isTrue);
      expect(worker.contains('reason: "setting_off"'), isTrue);
    });
  });
}
