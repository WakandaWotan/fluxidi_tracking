import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_request_history.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_presentation.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_presentation.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_respond_form.dart';

LimousineQuoteRequest _request({
  String id = 'qr_live_1',
  String state = 'requested',
  int revision = 1,
  bool withQuote = false,
  String vehicleId = 'vh_1787076028764',
  String offerId = 'limo_test_preview_por_1',
  String serviceClassId = 'stretch_limousine',
  String vehicleName = 'Hummer stretch',
  String pickupIso = '2026-08-29T10:00:00.000Z',
}) {
  return LimousineQuoteRequest.fromJson(<String, dynamic>{
    'quote_request_id': id,
    'state': state,
    'revision': revision,
    'offer_id': offerId,
    'service_class_id': serviceClassId,
    'vehicle_id': vehicleId,
    'journey_type': 'airport_transfer',
    'scheduled_pickup_iso': pickupIso,
    'pax': 6,
    'created_at': '2026-08-21T10:00:00Z',
    'updated_at': '2026-08-21T10:00:00Z',
    'vehicle_snapshot': <String, dynamic>{'public_name': vehicleName},
    'fulfilment': <String, dynamic>{'from': 'Brussel-Zuid', 'to': 'Oudenaarde'},
    if (withQuote)
      'quote': <String, dynamic>{
        'total_incl_vat_cents': 25000,
        'currency': 'EUR',
        'vat_treatment': 'incl',
        'expires_at': '2026-08-28T21:59:59.000Z',
        'terms_revision': 1,
        'terms': <String, dynamic>{
          'terms_revision': 1,
          'cancellation_deadline_hours': 0,
          'cancellation_penalty_percent': 0,
          'waiting_time_included_minutes': 0,
          'waiting_time_overage_cents_per_minute': 0,
          'no_show_penalty_percent': 0,
          'overtime_cents_per_hour': 0,
        },
      },
  });
}

class _StatusGateway implements LimousineCustomerQuoteGateway {
  _StatusGateway(this.live);

  LimousineQuoteRequest live;
  int polls = 0;

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
    polls += 1;
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
  }) async {
    throw UnimplementedError();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    appLanguageNotifier.value = AppLanguage.nl;
  });

  group('form UX', () {
    test('euro to cents stays integer-safe', () {
      expect(limousineMajorUnitsToCents('250,00'), 25000);
      expect(limousineMajorUnitsToCents('1,00'), 100);
      expect(limousineMajorUnitsToCents('1.2'), 120);
      expect(limousineMajorUnitsToCents('1.234'), isNull);
    });

    test('currency display is EUR without ISO wording', () {
      expect(kLimousineDefaultQuoteCurrency, 'EUR');
      expect(kLimousineQuoteCurrency.nl.contains('ISO'), isFalse);
      expect(kLimousineQuoteExpires.nl.contains('ISO'), isFalse);
      expect(kLimousineQuoteWaitingOverage.nl.contains('centen'), isFalse);
      expect(kLimousineQuoteOvertime.nl.contains('centen'), isFalse);
    });

    test('date picker maps to ISO internally', () {
      final clock = DateTime(2026, 8, 21, 9);
      final date = limousineDefaultQuoteValidUntilDate(clock);
      expect(date, DateTime(2026, 8, 28));
      final iso = limousineQuoteExpiresAtIsoFromDate(date);
      expect(DateTime.tryParse(iso), isNotNull);
      expect(formatLimousineUserDate(iso, AppLanguage.nl), '28 augustus 2026');
      expect(limousineLooksLikeRawIsoTimestamp(iso), isTrue);
    });

    test('empty optional terms do not block a completed simple quote', () {
      final completed = completeLimousineCompanyQuoteDraft(
        const LimousineCompanyQuoteDraft(
          totalInclVatCents: 25000,
          vatTreatment: kLimousineQuoteVatIncl,
        ),
        now: DateTime(2026, 8, 21),
      );
      final validation = validateLimousineCompanyQuoteDraft(completed);
      expect(validation.ok, isTrue);
      expect(completed.currency, 'EUR');
      expect(completed.termsRevision, 1);
      expect(completed.cancellationDeadlineHours, 0);
      expect(completed.waitingTimeOverageCentsPerMinute, 0);
      expect(completed.overtimeCentsPerHour, 0);
      expect(completed.toWorkerQuote()['terms']['terms_revision'], 1);
    });

    test('required validation stays on amount, VAT and expiry', () {
      final empty = validateLimousineCompanyQuoteDraft(
        const LimousineCompanyQuoteDraft(),
      );
      expect(empty.missing, contains('total_incl_vat_cents'));
      expect(empty.missing, contains('vat_treatment'));
      expect(empty.missing, contains('expires_at'));
      expect(
        limousineQuoteFieldErrorLabel('total_incl_vat_cents', AppLanguage.nl),
        'Vul een geldig offertebedrag in.',
      );
      expect(
        limousineQuoteFieldErrorLabel('expires_at', AppLanguage.nl),
        'Kies tot wanneer de offerte geldig is.',
      );
    });

    testWidgets('editor hides developer labels and enables a simple submit', (
      tester,
    ) async {
      LimousineCompanyQuoteDraft? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: LimousineQuoteEditorPage(
            record: _request(),
            clock: () => DateTime(2026, 8, 21, 9),
            onSubmit: (draft) async => submitted = draft,
          ),
        ),
      );
      expect(find.textContaining('ISO'), findsNothing);
      expect(find.textContaining('centen'), findsNothing);
      expect(find.text('Voorwaardenrevisie'), findsNothing);
      expect(find.text('EUR'), findsWidgets);
      expect(find.text('Bedrag'), findsOneWidget);
      expect(find.textContaining('incl'), findsNothing);
      await tester.ensureVisible(find.byKey(kLimousineQuoteSubmitKey));
      await tester.pump();

      final submit = tester.widget<FilledButton>(
        find.byKey(kLimousineQuoteSubmitKey),
      );
      expect(submit.onPressed, isNull);
      expect(find.text('Vul een geldig offertebedrag in.'), findsWidgets);

      await tester.enterText(
        find.byKey(kLimousineQuoteTotalFieldKey),
        '250,00',
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(kLimousineQuoteVatFieldKey));
      await tester.tap(find.byKey(kLimousineQuoteVatFieldKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BTW inbegrepen').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(kLimousineQuoteSubmitKey));
      await tester.pump();

      final enabled = tester.widget<FilledButton>(
        find.byKey(kLimousineQuoteSubmitKey),
      );
      expect(enabled.onPressed, isNotNull);
      await tester.tap(find.byKey(kLimousineQuoteSubmitKey));
      await tester.pumpAndSettle();
      expect(submitted, isNotNull);
      expect(submitted!.totalInclVatCents, 25000);
      expect(submitted!.vatTreatment, kLimousineQuoteVatIncl);
      expect(submitted!.termsRevision, 1);
      expect(submitted!.cancellationDeadlineHours, 0);
      expect(DateTime.tryParse(submitted!.expiresAt), isNotNull);
    });
  });

  group('status lifecycle', () {
    test('canonical labels cover requested → viewed → quote received', () {
      expect(
        limousineCustomerStateLabel('requested', AppLanguage.nl),
        'Aanvraag verzonden',
      );
      expect(
        limousineCustomerStateLabel(
          'viewed_by_company',
          AppLanguage.nl,
          companyName: 'Hummer Party',
        ),
        'Het bedrijf heeft uw aanvraag bekeken',
      );
      expect(
        limousineCustomerStateLabel('quoted', AppLanguage.nl),
        'Offerte ontvangen',
      );
      expect(
        limousineQuoteInboxStatusLabel(
          _request(state: 'viewed_by_company'),
          AppLanguage.nl,
        ),
        'Aanvraag bekeken',
      );
      expect(
        limousineQuoteInboxStatusLabel(
          _request(state: 'quoted', withQuote: true),
          AppLanguage.nl,
        ),
        'Wacht op klant',
      );
    });

    test('history survives a new repository on the same vault', () async {
      const statusRef = 'limqs1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM';
      final vault = MemoryLimousineCustomerRequestHistoryVault();
      final first = LimousineCustomerRequestHistoryRepository(vault: vault);
      await first.upsert(
        LimousineCustomerRequestRecord(
          quoteRequestId: 'qr_live_1',
          statusRef: statusRef,
          state: 'requested',
          companyName: 'Hummer Party',
          vehicleDisplayName: 'Hummer stretch',
          from: 'Brussel-Zuid',
          to: 'Oudenaarde',
          scheduledPickupIso: '2026-08-29T10:00:00.000Z',
          request: _request(),
        ),
      );
      final second = LimousineCustomerRequestHistoryRepository(vault: vault);
      final items = await second.list();
      expect(items, hasLength(1));
      expect(items.single.quoteRequestId, 'qr_live_1');
      expect(items.single.state, 'requested');
      expect(items.single.companyName, 'Hummer Party');

      await second.updateFromPoll(
        _request(state: 'viewed_by_company', revision: 2),
      );
      final afterView = await second.list();
      expect(afterView.single.state, 'viewed_by_company');

      await second.updateFromPoll(
        _request(state: 'quoted', revision: 3, withQuote: true),
      );
      final afterQuote = await second.list();
      expect(afterQuote.single.state, 'quoted');
      expect(afterQuote.single.request!.quote!.totalInclVatCents, 25000);
    });

    test(
      'controller restore keeps the live request after a new instance',
      () async {
        const statusRef = 'limqs1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM';
        final vault = MemoryLimousineCustomerRequestHistoryVault();
        final history = LimousineCustomerRequestHistoryRepository(vault: vault);
        await history.upsert(
          LimousineCustomerRequestRecord(
            quoteRequestId: 'qr_live_1',
            statusRef: statusRef,
            state: 'quoted',
            companyName: 'Hummer Party',
            request: _request(state: 'quoted', withQuote: true),
          ),
        );
        final stored = (await history.list()).single;
        final gateway = _StatusGateway(
          _request(state: 'quoted', revision: 4, withQuote: true),
        );
        final controller = LimousineCustomerQuoteController(
          gateway: gateway,
          historyRepository: history,
        );
        controller.restorePersistedRequest(stored);
        expect(controller.request!.quoteRequestId, 'qr_live_1');
        expect(controller.providerDisplayName, 'Hummer Party');
        expect(
          limousineCustomerStateLabel(
            controller.request!.state,
            AppLanguage.nl,
          ),
          'Offerte ontvangen',
        );
        await Future<void>.delayed(Duration.zero);
        expect(gateway.polls, 1);
        expect(controller.request!.revision, 4);
        await controller.refreshStatus(manual: true);
        expect(gateway.polls, 2);
        final reloaded = await history.list();
        expect(reloaded.single.state, 'quoted');
        controller.dispose();
      },
    );
  });

  group('presentation', () {
    test('raw class, vehicle, offer and ISO stay off the user surface', () {
      final record = _request();
      expect(
        limousineQuoteServiceClassDisplay('stretch_limousine', AppLanguage.nl),
        'Stretchlimousine',
      );
      expect(
        limousineQuoteVehicleDisplay(record, AppLanguage.nl),
        'Hummer stretch',
      );
      expect(
        limousineQuoteVehicleDisplay(record, AppLanguage.nl),
        isNot('vh_1787076028764'),
      );
      expect(
        limousineQuoteOfferDisplay(record, AppLanguage.nl),
        isNot(record.offerId),
      );
      expect(limousineLooksLikeRawVehicleOrOfferId(record.vehicleId), isTrue);
      expect(limousineLooksLikeRawServiceClassId('stretch_limousine'), isTrue);
      final formatted = formatLimousineUserDateTime(
        record.scheduledPickupIso,
        AppLanguage.nl,
      );
      expect(formatted.contains('augustus'), isTrue);
      expect(limousineLooksLikeRawIsoTimestamp(formatted), isFalse);
      expect(
        limousineVatTreatmentLabel('incl', AppLanguage.nl),
        'BTW inbegrepen',
      );
      expect(formatLimousineEuroAmount(25000), '€ 250,00');
    });
  });
}
