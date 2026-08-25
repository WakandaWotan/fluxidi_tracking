import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/hotels/hotel_places_pagination.dart';
import 'package:fluxidi_tracking/hotels/stay22_search.dart';

void main() {
  test('page 2 stays hidden until a valid has_more cursor exists', () {
    final gate = HotelPlacesPage2Controller();
    expect(gate.snapshot.phase, HotelPlacesPage2Phase.hidden);
    expect(gate.beginRequest(queryGeneration: 1), isFalse);
    gate.applyFirstPage(
      pagination: const HotelPlacesPaginationMeta(
        page: 1,
        hasMore: false,
        maxPages: 2,
      ),
      queryGeneration: 1,
    );
    expect(gate.snapshot.showAction, isFalse);
    gate.applyFirstPage(
      pagination: HotelPlacesPaginationMeta.fromJson(<String, dynamic>{
        'page': 1,
        'has_more': true,
        'next_cursor': 'opaque-cursor-value-1234',
        'max_pages': 2,
        'available_at': DateTime.utc(2026, 8, 25, 12).millisecondsSinceEpoch,
      }),
      queryGeneration: 2,
      now: DateTime.utc(2026, 8, 25, 11, 59, 50),
    );
    expect(gate.snapshot.phase, HotelPlacesPage2Phase.waitingActivation);
    expect(gate.beginRequest(queryGeneration: 2), isFalse);
    expect(gate.activateIfReady(now: DateTime.utc(2026, 8, 25, 12)), isTrue);
    expect(gate.snapshot.canRequest, isTrue);
  });

  test('double tap sends only one request and query change drops the cursor', () {
    final gate = HotelPlacesPage2Controller();
    gate.applyFirstPage(
      pagination: const HotelPlacesPaginationMeta(
        page: 1,
        hasMore: true,
        maxPages: 2,
        nextCursor: 'cursor-1',
      ),
      queryGeneration: 4,
    );
    expect(gate.beginRequest(queryGeneration: 4), isTrue);
    expect(gate.beginRequest(queryGeneration: 4), isFalse);
    expect(gate.snapshot.phase, HotelPlacesPage2Phase.loading);
    gate.reset();
    expect(gate.snapshot.phase, HotelPlacesPage2Phase.hidden);
    expect(gate.beginRequest(queryGeneration: 4), isFalse);
  });

  test('stale page 2 cannot apply to a newer generation', () {
    final gate = HotelPlacesPage2Controller();
    gate.applyFirstPage(
      pagination: const HotelPlacesPaginationMeta(
        page: 1,
        hasMore: true,
        maxPages: 2,
        nextCursor: 'cursor-1',
      ),
      queryGeneration: 1,
    );
    expect(gate.beginRequest(queryGeneration: 1), isTrue);
    expect(gate.shouldApply(queryGeneration: 2), isFalse);
    gate.completeSuccess(queryGeneration: 2);
    expect(gate.snapshot.phase, HotelPlacesPage2Phase.loading);
    gate.completeSuccess(queryGeneration: 1);
    expect(gate.snapshot.phase, HotelPlacesPage2Phase.complete);
    expect(gate.snapshot.showAction, isFalse);
  });

  test('temporary not-ready remains retryable and no third page exists', () {
    final gate = HotelPlacesPage2Controller();
    gate.applyFirstPage(
      pagination: const HotelPlacesPaginationMeta(
        page: 1,
        hasMore: true,
        maxPages: 2,
        nextCursor: 'cursor-1',
      ),
      queryGeneration: 3,
    );
    expect(gate.beginRequest(queryGeneration: 3), isTrue);
    gate.completeRetryable(
      queryGeneration: 3,
      retryAfter: const Duration(seconds: 2),
    );
    expect(gate.snapshot.isRetryable, isTrue);
    expect(gate.beginRequest(queryGeneration: 3), isTrue);
    gate.completeSuccess(queryGeneration: 3);
    expect(gate.beginRequest(queryGeneration: 3), isFalse);
    expect(
      HotelPlacesPaginationMeta.fromJson(<String, dynamic>{
        'page': 2,
        'has_more': true,
        'next_cursor': 'nope',
        'max_pages': 2,
      })?.hasMore,
      isFalse,
    );
  });

  test('duplicate place IDs are removed and actual counts are displayed', () {
    final merged = dedupeHotelStaysByPlaceId(
      <String>['google_places:a', 'google_places:b', 'google_places:a', 'x'],
      idOf: (id) => id,
    );
    expect(merged, <String>['google_places:a', 'google_places:b', 'x']);
    expect(stay22FeaturedCountLabel(20, 'nl'), '20 uitgelichte verblijven');
    expect(stay22FeaturedCountLabel(40, 'nl'), '40 uitgelichte verblijven');
    expect(stay22FeaturedCountLabel(37, 'en'), '37 featured stays');
    expect(stay22MoreFeaturedStaysLabel('nl'), 'Meer uitgelichte verblijven');
    expect(stay22MoreFeaturedStaysLabel('fr'), contains('hébergements'));
    expect(stay22MoreFeaturedStaysLabel('es'), contains('alojamientos'));
  });
}
