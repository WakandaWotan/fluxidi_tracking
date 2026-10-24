import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/hotels/hotel_model.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_hotelpage.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_search.dart';

RatehawkViewStaySnapshot _snapshot({
  String token = 'rhctx1.payload.sig',
  int hid = 8473727,
  DateTime? expiresAt,
}) {
  return RatehawkViewStaySnapshot(
    contextToken: token,
    hid: hid,
    checkin: '2026-09-03',
    checkout: '2026-09-04',
    residency: 'be',
    currency: 'EUR',
    guests: const <RatehawkGuestRoom>[RatehawkGuestRoom(adults: 2)],
    expiresAt: expiresAt,
  );
}

HotelStay _ratehawkStay({
  RatehawkViewStaySnapshot? viewStay,
  int hid = 8473727,
}) {
  return HotelStay(
    id: 'ratehawk:$hid',
    name: 'Warwick Brussels',
    type: HotelStayType.hotel,
    city: 'Brussel',
    region: 'Brussels',
    country: 'Belgium',
    address: 'Rue Duquesnoy 5, 1000 Brussels, Belgium',
    description: '',
    imageRef: '',
    lat: 50.845,
    lng: 4.3543,
    source: 'ratehawk',
    provider: 'ratehawk',
    hid: hid,
    isRealApproved: true,
    viewStay: viewStay,
  );
}

Map<String, dynamic> _offerJson({
  String offerRef = 'rh1.aaa.bbb',
  bool bookable = true,
  String paymentType = 'hotel',
  bool includeHash = false,
}) {
  return <String, dynamic>{
    'offer_ref': offerRef,
    'room_name': 'Deluxe Room',
    'room_description': 'City view',
    'occupancy': '2 adults',
    'beds': '1 king',
    'meal_plan': 'breakfast',
    'breakfast_included': true,
    'remaining_availability': '3',
    'customer_total': '180.00',
    'customer_total_label': 'EUR 180.00',
    'currency': 'EUR',
    'included_taxes': <Map<String, dynamic>>[
      <String, dynamic>{'name': 'VAT', 'amount': '20.00'},
    ],
    'excluded_taxes': <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'City tax',
        'amount': '4.50',
        'payable_where': 'property',
      },
    ],
    'vat': <String, dynamic>{'included': true},
    'payment': <String, dynamic>{
      'type': paymentType,
      'recipient': 'hotel',
      'timing': 'at_property',
    },
    'card_data_required': true,
    'cvc_required': false,
    'deposit': <String, dynamic>{
      'disclosed': true,
      'amount': '50.00',
      'currency': 'EUR',
      'refundable': true,
      'payment_recipient': 'hotel',
      'payment_timing': 'at_checkin',
    },
    'cancellation': <String, dynamic>{
      'refundable': true,
      'free_cancellation_before': '2026-09-01T12:00:00Z',
      'penalties': <Map<String, dynamic>>[
        <String, dynamic>{'start_at': '2026-09-01', 'show_amount': '90.00'},
      ],
    },
    'no_show': <String, dynamic>{
      'disclosed': true,
      'amount': '180.00',
      'currency': 'EUR',
      'from_time': '18:00',
      'timezone_context': 'hotel_local_time',
      'included_in_room_total': false,
      'converted': false,
    },
    'bookable': bookable,
    'must_prebook_before_confirmation': true,
    if (includeHash) 'book_hash': 'h-secret',
  };
}

void main() {
  test('missing expired or tampered context fails closed', () {
    final client = RecordingRatehawkHotelpageClient();
    final controller = RatehawkHotelpageController(client: client);
    expect(canRequestRatehawkHotelpage(_ratehawkStay()), isFalse);
    expect(
      canRequestRatehawkHotelpage(
        _ratehawkStay(viewStay: _snapshot(token: 'unsigned.local')),
      ),
      isFalse,
    );
    expect(
      canRequestRatehawkHotelpage(
        _ratehawkStay(viewStay: _snapshot(expiresAt: DateTime.utc(2020, 1, 1))),
      ),
      isFalse,
    );
    controller.loadForStay(_ratehawkStay());
    expect(client.calls, isEmpty);
    expect(controller.state, RatehawkHotelpageLifecycleState.unavailable);
  });

  test('loading lifecycle uses real states and no fake percentage', () async {
    final client = RecordingRatehawkHotelpageClient(
      response: RatehawkHotelpageResponse(
        ok: true,
        offers: <RatehawkHotelpageOffer>[
          parseRatehawkHotelpageOffer(_offerJson())!,
        ],
        retrievedAt: DateTime.utc(2026, 8, 17, 10),
      ),
    );
    final controller = RatehawkHotelpageController(client: client);
    final stay = _ratehawkStay(viewStay: _snapshot());
    expect(controller.state, RatehawkHotelpageLifecycleState.idle);
    await controller.loadForStay(stay);
    expect(client.calls, hasLength(1));
    expect(controller.state, RatehawkHotelpageLifecycleState.ready);
    expect(controller.offers, hasLength(1));
    expect(
      ratehawkHotelpageStateLabel(controller.state, 'nl'),
      isNot(contains('%')),
    );
    expect(
      ratehawkHotelpageStateLabel(controller.state, 'en'),
      isNot(contains('%')),
    );
  });

  test('accepted rooms show room meal beds and availability', () {
    final offer = parseRatehawkHotelpageOffer(_offerJson());
    expect(offer, isNotNull);
    expect(offer!.roomName, 'Deluxe Room');
    expect(offer.mealPlan, 'breakfast');
    expect(offer.beds, '1 king');
    expect(offer.remainingAvailability, '3');
    expect(offer.breakfastIncluded, isTrue);
  });

  test('current customer total and taxes are displayed', () {
    final offer = parseRatehawkHotelpageOffer(_offerJson())!;
    expect(offer.customerTotalLabel, 'EUR 180.00');
    expect(offer.currency, 'EUR');
    expect(offer.includedTaxes.first.amount, '20.00');
    expect(offer.excludedTaxes.first.payableWhere, 'property');
    expect(offer.vatIncluded, isTrue);
  });

  test('payment recipient and timing are displayed', () {
    final offer = parseRatehawkHotelpageOffer(_offerJson())!;
    expect(offer.payment!.type, 'hotel');
    expect(offer.payment!.recipient, 'hotel');
    expect(offer.payment!.timing, 'at_property');
    expect(offer.cardDataRequired, isTrue);
    expect(offer.cvcRequired, isFalse);
  });

  test('hotel deposit is disclosed separately', () {
    final offer = parseRatehawkHotelpageOffer(_offerJson())!;
    expect(offer.deposit.disclosed, isTrue);
    expect(offer.deposit.amount, '50.00');
    expect(offer.deposit.currency, 'EUR');
    expect(offer.deposit.recipient, 'hotel');
    expect(offer.payment!.type, isNot('deposit'));
  });

  test('payment type deposit is rejected', () {
    expect(
      parseRatehawkHotelpageOffer(_offerJson(paymentType: 'deposit')),
      isNull,
    );
  });

  test(
    'cancellation and no-show are displayed without currency conversion',
    () {
      final offer = parseRatehawkHotelpageOffer(_offerJson())!;
      expect(offer.cancellation.refundable, isTrue);
      expect(offer.cancellation.freeCancellationBefore, isNotEmpty);
      expect(offer.cancellation.penalties.first.amount, '90.00');
      expect(offer.noShow.disclosed, isTrue);
      expect(offer.noShow.currency, 'EUR');
      expect(offer.noShow.converted, isFalse);
      expect(offer.noShow.includedInRoomTotal, isFalse);
      expect(offer.noShow.timezoneContext, 'hotel_local_time');
    },
  );

  test('static policies appear only when supplied', () {
    expect(parseRatehawkStaticPolicies(null), isNull);
    final policies = parseRatehawkStaticPolicies(<String, dynamic>{
      'ok': true,
      'pets': <String>['Pets on request'],
      'amenities': <String>[],
    });
    expect(policies, isNotNull);
    expect(policies!.pets, <String>['Pets on request']);
    expect(policies.amenities, isEmpty);
    expect(policies.parking, isEmpty);
  });

  test('missing policy does not become not allowed', () {
    final policies = parseRatehawkStaticPolicies(<String, dynamic>{'ok': true});
    expect(policies!.pets, isEmpty);
    expect(policies.children, isEmpty);
    expect(
      ratehawkUnmappedPolicyLabel('en').toLowerCase(),
      isNot(contains('not allowed')),
    );
  });

  test('expired rate is not bookable and only rh1 is retained', () {
    final expired = parseRatehawkHotelpageOffer(_offerJson(bookable: false))!;
    expect(expired.isSelectable, isFalse);
    final controller = RatehawkHotelpageController(
      client: RecordingRatehawkHotelpageClient(),
    );
    controller.selectOffer(expired);
    expect(controller.selected, isNull);
    final live = parseRatehawkHotelpageOffer(_offerJson())!;
    controller.selectOffer(live);
    expect(controller.selected!.offerRef.startsWith('rh1.'), isTrue);
    expect(controller.selected!.offerRef.contains('book_hash'), isFalse);
  });

  test(
    'hashes credentials reconciliation and commission never reach Flutter',
    () {
      expect(
        parseRatehawkHotelpageOffer(_offerJson(includeHash: true)),
        isNull,
      );
      expect(
        parseRatehawkHotelpagePayload(<String, dynamic>{
          'ok': true,
          'offers': <Map<String, dynamic>>[_offerJson()],
          'commission': 5,
        }).malformed,
        isTrue,
      );
      expect(
        parseRatehawkHotelpageOffer(_offerJson())!.offerRef,
        'rh1.aaa.bbb',
      );
    },
  );

  test('NL EN FR ES hotelpage labels exist', () {
    for (final language in <String>['nl', 'en', 'fr', 'es']) {
      for (final state in RatehawkHotelpageLifecycleState.values) {
        expect(ratehawkHotelpageStateLabel(state, language), isNotEmpty);
        expect(
          ratehawkHotelpageStateLabel(state, language),
          isNot(contains('%')),
        );
      }
      expect(ratehawkExpiredAvailabilityLabel(language), isNotEmpty);
      expect(ratehawkHotelpageSectionTitle(language), isNotEmpty);
      expect(ratehawkPrebookRecheckLabel(language), isNotEmpty);
    }
    expect(
      ratehawkExpiredAvailabilityLabel('nl'),
      'Beschikbaarheid controleren',
    );
    expect(ratehawkExpiredAvailabilityLabel('fr'), 'Vérifier la disponibilité');
    expect(ratehawkExpiredAvailabilityLabel('es'), 'Comprobar disponibilidad');
  });

  test('public hotelpage flutter surface cannot use admin or test binding', () {
    final files = <String>[
      'lib/hotels/ratehawk_hotelpage.dart',
      'lib/hotels/ratehawk_hotelpage_panel.dart',
      'lib/hotels/ratehawk_view_stay.dart',
      'lib/hotels/hotels_page.dart',
    ];
    final source = files
        .map((path) => File(path).readAsStringSync())
        .join('\n');
    expect(source.contains('RATEHAWK_HOTELS_TEST'), isFalse);
    expect(source.contains('/admin/hotels/ratehawk'), isFalse);
    expect(source.contains('x-admin-token'), isFalse);
    expect(source.contains('/public/hotels/ratehawk/prebook'), isFalse);
    expect(source.contains('/public/hotels/ratehawk/book'), isFalse);
    expect(source.contains('/public/hotels/ratehawk/finish'), isFalse);
    expect(source.contains('/public/hotels/ratehawk/cancel'), isFalse);
    expect(source.contains('/public/hotels/ratehawk/voucher'), isFalse);
  });

  test('search envelope attaches rhctx1 only to matching hid', () {
    final stays = attachEnvelopeViewStay(
      stays: <HotelStay>[_ratehawkStay(), _ratehawkStay(hid: 1)],
      payload: <String, dynamic>{
        'view_stay_context': 'rhctx1.payload.sig',
        'stay_context': <String, dynamic>{
          'hid': 8473727,
          'checkin': '2026-09-03',
          'checkout': '2026-09-04',
          'residency': 'be',
          'currency': 'EUR',
          'guests': <Map<String, dynamic>>[
            <String, dynamic>{'adults': 2, 'children': <int>[]},
          ],
        },
      },
    );
    expect(stays.first.viewStay, isNotNull);
    expect(stays.last.viewStay, isNull);
  });
}
