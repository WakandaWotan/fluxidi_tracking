import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_booking_created_sort.dart';

CompanyBookingCreatedSortFields _f({
  required String id,
  String created = '',
  String leg = '',
}) {
  return CompanyBookingCreatedSortFields(
    bookingId: id,
    createdAtIso: created,
    legId: leg,
  );
}

enum _Bucket { open, completed }

class _Row {
  _Row({
    required this.id,
    required this.bucket,
    this.created = '',
    this.updated = '',
    this.leg = '',
  });

  final String id;
  final _Bucket bucket;
  final String created;
  final String updated;
  final String leg;
}

List<_Row> _sortRows(List<_Row> rows) {
  return sortCompanyBookingsNewestCreatedFirst(
    rows,
    (r) => CompanyBookingCreatedSortFields(
      bookingId: r.id,
      createdAtIso: r.created,
      legId: r.leg,
    ),
  );
}

List<_Row> _filterBucket(List<_Row> sorted, _Bucket bucket) {
  return sorted.where((r) => r.bucket == bucket).toList(growable: false);
}

void main() {
  group('company booking newest-created-first', () {
    test('1) three bookings: newest created first, oldest last', () {
      final sorted = sortCompanyBookingsNewestCreatedFirst(
        <CompanyBookingCreatedSortFields>[
          _f(id: 'A', created: '2026-01-01T10:00:00.000Z'),
          _f(id: 'B', created: '2026-06-15T12:00:00.000Z'),
          _f(id: 'C', created: '2026-03-01T08:00:00.000Z'),
        ],
        (x) => x,
      );
      expect(sorted.map((e) => e.bookingId).toList(), <String>['B', 'C', 'A']);
    });

    test('2) older booking with newer updated_at stays below later-created', () {
      // updated_at is intentionally NOT passed into the sort fields.
      final olderCreated = _Row(
        id: 'OLD',
        bucket: _Bucket.open,
        created: '2026-01-01T00:00:00.000Z',
        updated: '2026-07-30T23:59:59.000Z',
      );
      final newerCreated = _Row(
        id: 'NEW',
        bucket: _Bucket.open,
        created: '2026-07-01T00:00:00.000Z',
        updated: '2026-07-01T00:00:01.000Z',
      );
      final sorted = _sortRows(<_Row>[olderCreated, newerCreated]);
      expect(sorted.map((e) => e.id).toList(), <String>['NEW', 'OLD']);
      expect(
        compareCompanyBookingsNewestCreatedFirst(
          CompanyBookingCreatedSortFields(
            bookingId: olderCreated.id,
            createdAtIso: olderCreated.created,
          ),
          CompanyBookingCreatedSortFields(
            bookingId: newerCreated.id,
            createdAtIso: newerCreated.created,
          ),
        ),
        greaterThan(0),
      );
    });

    test('3) equal created_at uses booking-id descending', () {
      const ts = '2026-05-01T12:00:00.000Z';
      final sorted = sortCompanyBookingsNewestCreatedFirst(
        <CompanyBookingCreatedSortFields>[
          _f(id: 'bk_aaa', created: ts),
          _f(id: 'bk_zzz', created: ts),
          _f(id: 'bk_mmm', created: ts),
        ],
        (x) => x,
      );
      expect(
        sorted.map((e) => e.bookingId).toList(),
        <String>['bk_zzz', 'bk_mmm', 'bk_aaa'],
      );
    });

    test('4) missing creation timestamp: no crash, stable fallback order', () {
      final sorted = sortCompanyBookingsNewestCreatedFirst(
        <CompanyBookingCreatedSortFields>[
          _f(id: '2026-03-10-100', created: ''),
          _f(id: '2026-01-01-050', created: ''),
          _f(id: 'no-date-zzz', created: ''),
          _f(id: 'no-date-aaa', created: ''),
          _f(id: 'with-ts', created: '2026-07-01T00:00:00.000Z'),
        ],
        (x) => x,
      );
      expect(sorted.first.bookingId, 'with-ts');
      // Date-prefixed ids fall back to date order (newest date first).
      expect(sorted[1].bookingId, '2026-03-10-100');
      expect(sorted[2].bookingId, '2026-01-01-050');
      // Missing date prefix → ms=0; tie-break booking id DESC.
      expect(sorted[3].bookingId, 'no-date-zzz');
      expect(sorted[4].bookingId, 'no-date-aaa');

      final again = sortCompanyBookingsNewestCreatedFirst(sorted, (x) => x);
      expect(
        again.map((e) => e.bookingId).toList(),
        sorted.map((e) => e.bookingId).toList(),
      );
    });

    test('5) open/planned tab preserves newest-created order', () {
      final sorted = _sortRows(<_Row>[
        _Row(
          id: 'o1',
          bucket: _Bucket.open,
          created: '2026-01-01T00:00:00.000Z',
        ),
        _Row(
          id: 'c1',
          bucket: _Bucket.completed,
          created: '2026-07-01T00:00:00.000Z',
        ),
        _Row(
          id: 'o2',
          bucket: _Bucket.open,
          created: '2026-06-01T00:00:00.000Z',
        ),
        _Row(
          id: 'o3',
          bucket: _Bucket.open,
          created: '2026-03-01T00:00:00.000Z',
        ),
      ]);
      final open = _filterBucket(sorted, _Bucket.open);
      expect(open.map((e) => e.id).toList(), <String>['o2', 'o3', 'o1']);
    });

    test('6) completed/voltooid tab preserves newest-created order', () {
      final sorted = _sortRows(<_Row>[
        _Row(
          id: 'c1',
          bucket: _Bucket.completed,
          created: '2026-01-01T00:00:00.000Z',
        ),
        _Row(
          id: 'o1',
          bucket: _Bucket.open,
          created: '2026-07-01T00:00:00.000Z',
        ),
        _Row(
          id: 'c2',
          bucket: _Bucket.completed,
          created: '2026-06-01T00:00:00.000Z',
        ),
        _Row(
          id: 'c3',
          bucket: _Bucket.completed,
          created: '2026-03-01T00:00:00.000Z',
        ),
      ]);
      final completed = _filterBucket(sorted, _Bucket.completed);
      expect(completed.map((e) => e.id).toList(), <String>['c2', 'c3', 'c1']);
    });

    test('7) refresh / re-entry keeps the same order', () {
      final input = <CompanyBookingCreatedSortFields>[
        _f(id: 'x', created: '2026-02-01T00:00:00.000Z'),
        _f(id: 'y', created: '2026-05-01T00:00:00.000Z'),
        _f(id: 'z', created: '2026-03-01T00:00:00.000Z'),
      ];
      final first = sortCompanyBookingsNewestCreatedFirst(input, (e) => e);
      final second = sortCompanyBookingsNewestCreatedFirst(
        first.reversed,
        (e) => e,
      );
      expect(
        second.map((e) => e.bookingId).toList(),
        first.map((e) => e.bookingId).toList(),
      );
      expect(
        second.map((e) => e.bookingId).toList(),
        <String>['y', 'z', 'x'],
      );
    });

    test('8) newly created booking appears on top', () {
      final existing = _sortRows(<_Row>[
        _Row(
          id: 'old',
          bucket: _Bucket.open,
          created: '2026-01-01T00:00:00.000Z',
        ),
        _Row(
          id: 'mid',
          bucket: _Bucket.open,
          created: '2026-04-01T00:00:00.000Z',
        ),
      ]);
      final withNew = _sortRows(<_Row>[
        ...existing,
        _Row(
          id: 'brand_new',
          bucket: _Bucket.open,
          created: '2026-07-31T15:00:00.000Z',
        ),
      ]);
      expect(withNew.first.id, 'brand_new');
      expect(withNew.map((e) => e.id).toList(), <String>[
        'brand_new',
        'mid',
        'old',
      ]);
    });

    test('extractCompanyBookingCreatedAtIso reads canonical aliases', () {
      expect(
        extractCompanyBookingCreatedAtIso(const <String, dynamic>{
          'created_at': '2026-07-01T00:00:00.000Z',
          'updated_at': '2026-07-31T00:00:00.000Z',
          'pickup_iso': '2026-08-01T00:00:00.000Z',
        }),
        '2026-07-01T00:00:00.000Z',
      );
      expect(
        extractCompanyBookingCreatedAtIso(const <String, dynamic>{
          'booking': <String, dynamic>{
            'createdAt': '2026-06-01T00:00:00.000Z',
          },
        }),
        '2026-06-01T00:00:00.000Z',
      );
      expect(
        extractCompanyBookingCreatedAtIso(const <String, dynamic>{
          'inserted_at': '2026-05-01T00:00:00.000Z',
        }),
        '2026-05-01T00:00:00.000Z',
      );
      expect(
        extractCompanyBookingCreatedAtIso(const <String, dynamic>{
          'updated_at': '2026-07-31T00:00:00.000Z',
          'pickup_iso': '2026-08-01T00:00:00.000Z',
        }),
        isEmpty,
      );
    });
  });
}
