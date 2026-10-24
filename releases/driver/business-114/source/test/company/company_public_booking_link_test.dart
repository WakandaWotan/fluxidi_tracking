import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_public_booking_link.dart';

import 'company_public_booking_link_fixtures.dart';

void main() {
  for (final row in [
    (company: marioCompanyId, slug: 'taxi-mario', name: 'Taxi Mario'),
    (company: fluxidiCompanyId, slug: 'fluxidi-taxi', name: 'Fluxidi'),
  ]) {
    test(
      '${row.name} uses its registered slug without technical query',
      () async {
        final link = await testBookingLink(
          company: row.company,
          slug: row.slug,
          name: row.name,
        );
        expect(link.url, 'https://booking.fluxidi.com/${row.slug}');
        expect(Uri.parse(link.url).query, isEmpty);
        expect(link.companyId, row.company);
        expect(link.companyName, row.name);
      },
    );
  }

  test(
    'uppercase canonical slug becomes the same lowercase host slug',
    () async {
      final link = await resolveCompanyPublicBookingLink(
        expectedCompanyId: marioCompanyId,
        profileLoader: () async => bookingIdentity(),
        contextLoader: (slug) async {
          expect(slug, 'taxi-mario');
          return bookingContext();
        },
      );
      expect(link.slug, 'taxi-mario');
    },
  );

  for (final slug in [
    '',
    'taxi/mario',
    '../taxi-mario',
    'https://evil.test',
    'taxi-mario?company_code=FLX-00001',
    'FLX-00028',
    'api',
    'book',
    'taxi%2fmario',
    'a' * 65,
  ]) {
    test('invalid or missing registered slug is closed: $slug', () async {
      var called = false;
      await expectLater(
        resolveCompanyPublicBookingLink(
          expectedCompanyId: marioCompanyId,
          profileLoader: () async => bookingIdentity(slug: slug),
          contextLoader: (_) async {
            called = true;
            return bookingContext();
          },
        ),
        throwsA(isA<CompanyBookingLinkUnavailable>()),
      );
      expect(called, isFalse);
    });
  }

  test('a name and code never replace a missing registered slug', () async {
    await expectLater(
      resolveCompanyPublicBookingLink(
        expectedCompanyId: marioCompanyId,
        profileLoader: () async => {
          'company_id': marioCompanyId,
          'tenant_id': marioCompanyId,
          'company_name': 'Taxi Mario',
          'company_code': 'FLX-00028',
        },
        contextLoader: (_) async => bookingContext(),
      ),
      throwsA(isA<CompanyBookingLinkUnavailable>()),
    );
  });

  for (final field in ['company_id', 'tenant_id', 'publicCompanySlug']) {
    test('conflicting canonical alias/scope is closed: $field', () async {
      final identity = bookingIdentity();
      (identity['company'] as Map)[field] = field == 'publicCompanySlug'
          ? 'fluxidi-taxi'
          : fluxidiCompanyId;
      await expectLater(
        resolveCompanyPublicBookingLink(
          expectedCompanyId: marioCompanyId,
          profileLoader: () async => identity,
          contextLoader: (_) async => bookingContext(),
        ),
        throwsA(isA<CompanyBookingLinkUnavailable>()),
      );
    });
  }

  test('another tenant cannot supply a company profile', () async {
    await expectLater(
      resolveCompanyPublicBookingLink(
        expectedCompanyId: marioCompanyId,
        profileLoader: () async =>
            bookingIdentity(company: fluxidiCompanyId, slug: 'fluxidi-taxi'),
        contextLoader: (_) async => bookingContext(),
      ),
      throwsA(isA<CompanyBookingLinkUnavailable>()),
    );
  });

  for (final kind in [
    'unknown',
    'wrong slug',
    'other tenant',
    'inactive',
    'blocked',
    'unbookable',
    'disabled',
    'nested tenant',
  ]) {
    test('public host rejects unavailable/wrong company: $kind', () async {
      final context = bookingContext();
      final profile = context['profile'] as Map;
      switch (kind) {
        case 'unknown':
          context['ok'] = false;
        case 'wrong slug':
          context['slug'] = 'fluxidi-taxi';
        case 'other tenant':
          (context['company'] as Map)['company_id'] = fluxidiCompanyId;
        case 'inactive':
          profile['is_active'] = false;
        case 'blocked':
          profile['account_state'] = 'blocked';
        case 'unbookable':
          profile['bookable'] = false;
        case 'disabled':
          profile['profile_enabled'] = false;
        case 'nested tenant':
          profile['vehicles'] = [
            {'tenant_id': fluxidiCompanyId},
          ];
      }
      await expectLater(
        resolveCompanyPublicBookingLink(
          expectedCompanyId: marioCompanyId,
          profileLoader: () async => bookingIdentity(),
          contextLoader: (_) async => context,
        ),
        throwsA(isA<CompanyBookingLinkUnavailable>()),
      );
    });
  }

  for (final stage in ['profile', 'public host']) {
    test(
      'switching company during $stage lookup discards the result',
      () async {
        final pending = Completer<Map<String, dynamic>>();
        var current = true;
        final result = resolveCompanyPublicBookingLink(
          expectedCompanyId: marioCompanyId,
          scopeIsCurrent: () => current,
          profileLoader: () => stage == 'profile'
              ? pending.future
              : Future.value(bookingIdentity()),
          contextLoader: (_) => stage == 'public host'
              ? pending.future
              : Future.value(bookingContext()),
        );
        await Future<void>.delayed(Duration.zero);
        current = false;
        pending.complete(
          stage == 'profile' ? bookingIdentity() : bookingContext(),
        );
        await expectLater(
          result,
          throwsA(isA<CompanyBookingLinkUnavailable>()),
        );
      },
    );
  }
}
