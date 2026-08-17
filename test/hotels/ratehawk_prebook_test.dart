import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/hotels/hotel_model.dart';
import 'package:fluxidi_tracking/hotels/hotels_page.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_hotelpage.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_prebook.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_prebook_panel.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_search.dart';

HotelStay _ratehawkStay() {
  return HotelStay(
    id: 'ratehawk:8473727',
    name: 'Warwick Brussels',
    type: HotelStayType.hotel,
    city: 'Brussel',
    region: 'Brussels',
    country: 'Belgium',
    address: 'Rue Duquesnoy 5, 1000 Brussels, Belgium',
    description: 'RateHawk stay',
    imageRef: '',
    lat: 50.845,
    lng: 4.3543,
    imageUrl: 'https://example.com/warwick.jpg',
    provider: 'ratehawk',
    source: 'ratehawk',
    hid: 8473727,
    isRealApproved: true,
    viewStay: const RatehawkViewStaySnapshot(
      contextToken: 'rhctx1.payload.sig',
      hid: 8473727,
      checkin: '2026-09-03',
      checkout: '2026-09-04',
      residency: 'be',
      currency: 'EUR',
      guests: <RatehawkGuestRoom>[RatehawkGuestRoom(adults: 2)],
    ),
  );
}

RatehawkHotelpageOffer _offer() {
  return const RatehawkHotelpageOffer(
    offerRef: 'rh1.aaa.bbb',
    roomName: 'Deluxe Room',
    customerTotal: '180.00',
    customerTotalLabel: 'EUR 180.00',
    currency: 'EUR',
    bookable: true,
  );
}

class _GatedPrebookClient implements RatehawkPrebookClient {
  _GatedPrebookClient({required this.gate, required this.checkResponse});

  final Completer<void> gate;
  final RatehawkPrebookResponse checkResponse;

  @override
  Future<RatehawkPrebookResponse> check({
    required String offerRef,
    required String locale,
  }) async {
    await gate.future;
    return checkResponse;
  }

  @override
  Future<RatehawkPrebookResponse> accept({
    required String prebookRef,
    required String locale,
    String? termsRevision,
  }) async {
    return const RatehawkPrebookResponse(reason: 'unused');
  }
}

RatehawkPrebookResponse _ready({
  bool changed = false,
  bool blocked = false,
  List<RatehawkPrebookChange> changes = const <RatehawkPrebookChange>[],
}) {
  return RatehawkPrebookResponse(
    ok: true,
    invoked: true,
    progressBlocked: blocked,
    acceptanceAllowed: !blocked,
    changed: changed,
    changes: changes,
    currentTerms: _offer(),
    prebookRef: blocked ? null : 'rhp1.ccc.ddd',
    termsRevision: 'rev-1',
    existingActions: const <String>[
      'saved',
      'taxi_to_this_stay',
      'airport_transfer',
      'stay22_fallback_availability',
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NL EN FR ES prebook labels exist without fake percentages', () {
    for (final language in <String>['nl', 'en', 'fr', 'es']) {
      for (final state in RatehawkPrebookLifecycleState.values) {
        final label = ratehawkPrebookStateLabel(state, language);
        expect(label, isNotEmpty);
        expect(label, isNot(contains('%')));
      }
      expect(ratehawkPrebookCheckLabel(language), isNotEmpty);
      expect(ratehawkPrebookConfirmLabel(language), isNotEmpty);
      expect(ratehawkPrebookAcceptChangesLabel(language), isNotEmpty);
    }
    expect(ratehawkPrebookCheckLabel('nl'), 'Prijs en voorwaarden controleren');
    expect(ratehawkPrebookCheckLabel('en'), 'Check price and conditions');
    expect(
      ratehawkPrebookCheckLabel('fr'),
      'Vérifier le prix et les conditions',
    );
    expect(ratehawkPrebookCheckLabel('es'), 'Comprobar precio y condiciones');
  });

  test('parse rejects hashes reconciliation and credentials', () {
    final parsed = parseRatehawkPrebookPayload(<String, dynamic>{
      'ok': true,
      'book_hash': 'secret',
      'prebook_ref': 'rhp1.aaa.bbb',
    });
    expect(parsed.malformed, isTrue);
    expect(parsed.reason, 'forbidden_provider_fields');
    expect(parsed.prebookRef, isNull);
  });

  test('parse keeps opaque rhp1 and rha1 only', () {
    final parsed = parseRatehawkPrebookPayload(<String, dynamic>{
      'ok': true,
      'invoked': true,
      'progress_blocked': false,
      'acceptance_allowed': true,
      'changed': false,
      'prebook_ref': 'rhp1.aaa.bbb',
      'accepted_ref': 'rha1.ccc.ddd',
      'terms_revision': 'rev-1',
      'current_terms': <String, dynamic>{
        'offer_ref': 'rh1.aaa.bbb',
        'room_name': 'Deluxe Room',
        'customer_total_label': 'EUR 180.00',
        'bookable': true,
      },
      'dispute_snapshot': <String, dynamic>{
        'ok': true,
        'hid': 8473727,
        'room_name': 'Deluxe Room',
        'customer_total': <String, dynamic>{
          'label': 'EUR 180.00',
          'currency': 'EUR',
        },
        'omitted': <String>['book_hash', 'commission'],
      },
      'existing_actions': <String>['saved', 'taxi_to_this_stay'],
    });
    expect(parsed.prebookRef, 'rhp1.aaa.bbb');
    expect(parsed.acceptedRef, 'rha1.ccc.ddd');
    expect(parsed.currentTerms?.roomName, 'Deluxe Room');
    expect(parsed.disputeSnapshot?.ok, isTrue);
    expect(parsed.disputeSnapshot?.omitted, contains('book_hash'));
  });

  test('controller does not apply a stale newer-selection overwrite', () async {
    final gate = Completer<void>();
    final client = _GatedPrebookClient(
      gate: gate,
      checkResponse: _ready(changed: true),
    );
    final controller = RatehawkPrebookController(client: client);
    final pending = controller.check(offerRef: 'rh1.aaa.bbb', locale: 'nl');
    expect(controller.state, RatehawkPrebookLifecycleState.checking);
    controller.cancel();
    expect(controller.state, RatehawkPrebookLifecycleState.idle);
    gate.complete();
    await pending;
    expect(controller.state, RatehawkPrebookLifecycleState.idle);
    expect(controller.response, isNull);
  });

  test('blocked response drops bookable acceptance token', () async {
    final parsed = parseRatehawkPrebookPayload(<String, dynamic>{
      'ok': true,
      'progress_blocked': true,
      'acceptance_allowed': false,
      'reason': 'currency_changed',
    });
    final controller = RatehawkPrebookController(
      client: RecordingRatehawkPrebookClient(checkResponse: parsed),
    );
    expect(parsed.prebookRef, isNull);
    await controller.check(offerRef: 'rh1.aaa.bbb', locale: 'nl');
    expect(controller.state, RatehawkPrebookLifecycleState.blocked);
    expect(controller.response?.prebookRef, isNull);
  });

  test('explicit accept is bound to the current terms revision', () async {
    final client = RecordingRatehawkPrebookClient(
      checkResponse: _ready(),
      acceptResponse: const RatehawkPrebookResponse(
        ok: true,
        accepted: true,
        acceptedRef: 'rha1.eee.fff',
        termsRevision: 'rev-1',
        progressBlocked: false,
        disputeSnapshot: RatehawkPrebookDisputeSnapshot(
          ok: true,
          hid: 8473727,
          termsRevision: 'rev-1',
          omitted: <String>['book_hash', 'commission'],
        ),
      ),
    );
    final controller = RatehawkPrebookController(client: client);
    await controller.check(offerRef: 'rh1.aaa.bbb', locale: 'nl');
    await controller.accept(locale: 'nl');
    expect(controller.state, RatehawkPrebookLifecycleState.accepted);
    expect(client.acceptCalls.single['terms_revision'], 'rev-1');
    expect(client.acceptCalls.single['prebook_ref'], 'rhp1.ccc.ddd');
  });

  testWidgets('check CTA and Stay22 taxi airport remain usable', (
    tester,
  ) async {
    final hotelpage = RecordingRatehawkHotelpageClient(
      response: RatehawkHotelpageResponse(
        ok: true,
        offers: <RatehawkHotelpageOffer>[_offer()],
        retrievedAt: DateTime.utc(2026, 8, 17, 10),
      ),
    );
    final prebook = RecordingRatehawkPrebookClient(checkResponse: _ready());
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final previous = appLanguageNotifier.value;
    appLanguageNotifier.value = AppLanguage.nl;
    addTearDown(() => appLanguageNotifier.value = previous);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1200, 1800)),
          child: HotelsPage(
            stays: <HotelStay>[_ratehawkStay()],
            ratehawkSearchClient: RecordingRatehawkHotelSearchClient(),
            ratehawkHotelpageClient: hotelpage,
            ratehawkPrebookClient: prebook,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Bekijk verblijf').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Deze kamer kiezen'));
    await tester.pump();
    expect(find.text('Prijs en voorwaarden controleren'), findsWidgets);
    expect(find.text('Taxi naar dit verblijf'), findsWidgets);
    expect(find.text('Luchthaven transfer'), findsWidgets);
    expect(find.text('Bekijk beschikbaarheid'), findsWidgets);
    await tester.tap(find.text('Prijs en voorwaarden controleren').last);
    await tester.pump();
    expect(prebook.checkCalls, hasLength(1));
    expect(prebook.checkCalls.single['offer_ref'], 'rh1.aaa.bbb');
    expect(find.text('Voorwaarden bevestigen'), findsWidgets);
    expect(find.text('Taxi naar dit verblijf'), findsWidgets);
  });

  testWidgets('changed terms require explicit renewed acceptance', (
    tester,
  ) async {
    final controller = RatehawkPrebookController(
      client: RecordingRatehawkPrebookClient(
        checkResponse: _ready(
          changed: true,
          changes: const <RatehawkPrebookChange>[
            RatehawkPrebookChange(
              code: 'price_changed',
              label: 'Prijs',
              before: 'EUR 180.00',
              after: 'EUR 195.00',
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RatehawkPrebookSection(
            offerRef: 'rh1.aaa.bbb',
            languageCode: 'nl',
            palette: paletteForCustomerTheme(CustomerThemeVariant.nightGold),
            controller: controller,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Prijs en voorwaarden controleren').last);
    await tester.pump();
    expect(find.text('Gewijzigde voorwaarden accepteren'), findsWidgets);
    expect(find.textContaining('EUR 180.00'), findsWidgets);
    expect(find.textContaining('EUR 195.00'), findsWidgets);
  });

  test(
    'public prebook URL stays out of hotelpage files and booking paths absent',
    () {
      final hotelpageFiles = <String>[
        'lib/hotels/ratehawk_hotelpage.dart',
        'lib/hotels/ratehawk_hotelpage_panel.dart',
        'lib/hotels/ratehawk_view_stay.dart',
        'lib/hotels/hotels_page.dart',
      ];
      final hotelpageSource = hotelpageFiles
          .map((path) => File(path).readAsStringSync())
          .join('\n');
      expect(
        hotelpageSource.contains('/public/hotels/ratehawk/prebook'),
        isFalse,
      );
      expect(hotelpageSource.contains('/public/hotels/ratehawk/book'), isFalse);
      expect(
        hotelpageSource.contains('/public/hotels/ratehawk/finish'),
        isFalse,
      );
      expect(
        hotelpageSource.contains('/public/hotels/ratehawk/cancel'),
        isFalse,
      );
      expect(
        hotelpageSource.contains('/public/hotels/ratehawk/voucher'),
        isFalse,
      );

      final prebook = File(
        'lib/hotels/ratehawk_prebook.dart',
      ).readAsStringSync();
      final appConfig = File('lib/app_config.dart').readAsStringSync();
      expect(prebook.contains('/public/hotels/ratehawk/prebook'), isFalse);
      expect(appConfig.contains('/public/hotels/ratehawk/prebook'), isTrue);
      expect(
        appConfig.contains('/public/hotels/ratehawk/prebook/accept'),
        isTrue,
      );
      expect(prebook.contains('/public/hotels/ratehawk/book'), isFalse);
      expect(prebook.contains('RATEHAWK_HOTELS_TEST'), isFalse);
    },
  );
}
