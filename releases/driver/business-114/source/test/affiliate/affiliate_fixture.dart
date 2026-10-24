import 'package:flutter/foundation.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_repository.dart';
import 'package:http/http.dart' as http;

CustomerSession affiliateSession(String id, {DateTime? expiry}) =>
    CustomerSession(
      customerSessionToken: 'personal_fixture_$id',
      customerId: id,
      phoneE164: '+32000000000',
      expiresAt:
          (expiry ?? DateTime.now().toUtc().add(const Duration(hours: 1)))
              .toIso8601String(),
      createdAt: '2026-10-04T00:00:00Z',
      updatedAt: '2026-10-04T00:00:00Z',
    );

Map<String, dynamic> affiliateOverview({
  String id = 'A',
  String status = 'not_enrolled',
}) => {
  'ok': true,
  'affiliate_id': id,
  'status': status,
  'revision': 1,
  'program_enabled': true,
  'may_apply': true,
  'terms_version': 'approved_fixture_v1',
  'terms_text': 'Fixturevoorwaarden van de server.',
  'commission_rate_bps': 500,
  'revenue_basis': 'verified_paid_ex_vat_subscriptions_and_addons',
  'automatic_bank_transfers': false,
  'bank_verified': false,
  'balances': [],
  if (status == 'active') 'referral_code': 'FIXTURE_ACTIVE_CODE',
};

const affiliatePrivateHeaders = {'cache-control': 'private, no-store'};

class AffiliateFixture {
  AffiliateFixture({
    required http.Client http,
    CustomerSession? session,
    bool guest = false,
  }) {
    current = guest ? null : session ?? affiliateSession('A');
    repository = AffiliateRepository(
      transport: http,
      baseUrl: 'https://booking.example.test',
      loadSession: () async => current,
      currentSession: () => current,
      revision: revision,
    );
  }
  CustomerSession? current;
  final revision = ValueNotifier<int>(0);
  late final AffiliateRepository repository;
  void replace(CustomerSession? session) {
    current = session;
    revision.value++;
  }

  void dispose() {
    repository.dispose();
    revision.dispose();
  }
}
