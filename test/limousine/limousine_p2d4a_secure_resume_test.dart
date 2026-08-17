import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_resume.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_resume_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_resume_ui.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_vault.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_entry.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';

const String _acceptRef = 'limacc1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM';

DateTime _now = DateTime.utc(2026, 8, 17, 12);

DateTime _clock() => _now;

LimousineAcceptedQuoteHandoff _handoff({
  String reference = _acceptRef,
  String partnerId = 'p1',
  int totalInclVatCents = 45000,
}) {
  return LimousineAcceptedQuoteHandoff(
    acceptanceReference: reference,
    quoteRequestId: 'limq_1',
    quoteRevision: 3,
    termsRevision: 3,
    totalInclVatCents: totalInclVatCents,
    currency: 'EUR',
    offerId: 'off_1',
    publicPartnerId: partnerId,
    from: 'Gent',
    to: 'Brussel',
    scheduledPickupIso: '2026-09-01T10:00:00Z',
  );
}

LimousineQuoteCreateDraft _draft({String partnerId = 'p1'}) {
  return LimousineQuoteCreateDraft(
    publicPartnerId: partnerId,
    offerId: 'off_1',
    journeyType: 'point_to_point',
    from: 'Gent',
    to: 'Brussel',
    stops: const ['Antwerpen'],
    scheduledPickupIso: '2026-09-01T10:00:00Z',
    pax: 2,
    bags: 1,
  );
}

LimousineAcceptedBookingReview _review({int totalInclVatCents = 45000}) {
  return LimousineAcceptedBookingReview(
    providerName: 'Coachline',
    offerTitle: 'Executive',
    serviceClassId: 'executive_sedan',
    serviceClassLabel: 'Executive sedan',
    vehicleSupplied: true,
    journeyType: 'point_to_point',
    from: 'Gent',
    to: 'Brussel',
    stops: const ['Antwerpen'],
    scheduledPickupIso: '2026-09-01T10:00:00Z',
    roundtrip: false,
    returnPickupIso: '',
    pax: 2,
    bags: 1,
    acceptedExtras: const [
      {
        'extra_id': 'wait',
        'label': {'en': 'Wait'},
      },
    ],
    includedServices: const [
      {
        'item_id': 'water',
        'label': {'en': 'Water'},
      },
    ],
    mobilisationDisclosure: const {'en': 'Included', 'nl': 'Inbegrepen'},
    totalInclVatCents: totalInclVatCents,
    currency: 'EUR',
    vatTreatment: 'incl',
    termsRevision: 3,
    terms: const {'terms_revision': 3, 'cancellation_deadline_hours': 24},
  );
}

LimousineQuoteRequest _request({String state = 'quoted'}) {
  return LimousineQuoteRequest.fromJson(<String, dynamic>{
    'quote_request_id': 'limq_1',
    'state': state,
    'revision': 3,
    'offer_id': 'off_1',
    'service_class_id': 'executive_sedan',
    'journey_type': 'point_to_point',
    'scheduled_pickup_iso': '2026-09-01T10:00:00Z',
    'acceptance_allowed': true,
    'quote': <String, dynamic>{
      'total_incl_vat_cents': 45000,
      'currency': 'EUR',
      'vat_treatment': 'incl',
      'terms_revision': 3,
      'expires_at': _now.add(const Duration(minutes: 60)).toIso8601String(),
      'terms': {
        'cancellation_deadline_hours': 24,
        'cancellation_penalty_percent': 10,
        'waiting_time_included_minutes': 15,
        'waiting_time_overage_cents_per_minute': 50,
        'no_show_penalty_percent': 20,
        'overtime_cents_per_hour': 8000,
      },
    },
  });
}

LimousineAcceptedBookingCustomer get _customer =>
    const LimousineAcceptedBookingCustomer(
      sessionToken: 'sess_1',
      customerId: 'cust_1',
      name: 'Ada',
      phone: '+32470000000',
      email: 'ada@example.com',
    );

LimousineAcceptedBookingResumeScope _scope({
  String customerId = 'cust_1',
  String? publicPartnerId,
  String? tenantId,
  String? companyId,
}) {
  return LimousineAcceptedBookingResumeScope(
    customerId: customerId,
    publicPartnerId: publicPartnerId,
    tenantId: tenantId,
    companyId: companyId,
  );
}

class _BookGateway implements LimousineAcceptedBookingGateway {
  int calls = 0;
  Map<String, dynamic>? lastPayload;
  Object? error;
  Duration delay = Duration.zero;

  @override
  Future<LimousineAcceptedBookResult> book(Map<String, dynamic> payload) async {
    calls += 1;
    lastPayload = payload;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final thrown = error;
    if (thrown != null) {
      if (thrown is Exception) throw thrown;
      throw Exception('$thrown');
    }
    return const LimousineAcceptedBookResult(
      bookingId: 'B-100',
      publicReference: 'FLX-100',
      raw: <String, dynamic>{
        'ok': true,
        'booking_id': 'B-100',
        'public_reference': 'FLX-100',
      },
    );
  }
}

class _QuoteGateway implements LimousineCustomerQuoteGateway {
  LimousineQuoteAcceptResult? acceptResult;
  LimousineCustomerQuoteException? acceptError;

  @override
  Future<List<LimousineDiscoveredProvider>> discoverNearby({
    String? postcode,
    double? lat,
    double? lng,
    int radiusKm = 20,
  }) async => const [];

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
    throw const LimousineCustomerQuoteException(code: 'unused');
  }

  @override
  Future<LimousineQuoteAcceptResult> accept({
    required String quoteRequestId,
    required int expectedRevision,
    required int termsRevision,
  }) async {
    final error = acceptError;
    if (error != null) throw error;
    return acceptResult ??
        LimousineQuoteAcceptResult(
          request: _request(state: 'accepted'),
          acceptanceReference: _acceptRef,
          expiresAt: _now.add(const Duration(minutes: 60)).toIso8601String(),
        );
  }
}

Future<bool> _persist(
  LimousineAcceptedBookingResumeRepository repo, {
  LimousineAcceptedQuoteHandoff? handoff,
  String customerId = 'cust_1',
  DateTime? expiresAt,
  LimousineAcceptedBookingReview? review,
}) {
  return repo.persistAccepted(
    handoff: handoff ?? _handoff(),
    draft: _draft(),
    review: review ?? _review(),
    customerId: customerId,
    expiresAt: expiresAt ?? _now.add(const Duration(minutes: 60)),
    providerName: 'Coachline',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _now = DateTime.utc(2026, 8, 17, 12);
  });

  test('1) secure envelope round-trips through the vault', () async {
    final vault = MemoryLimousineAcceptedBookingVault();
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: vault,
      clock: _clock,
    );
    expect(await _persist(repo), isTrue);
    final restored = await repo.restore(scope: _scope());
    expect(restored, isNotNull);
    expect(restored!.handoff.acceptanceReference, _acceptRef);
    expect(restored.customerId, 'cust_1');
    expect(restored.publicPartnerId, 'p1');
    expect(restored.tenantId, 'p1');
    expect(restored.companyId, 'p1');
    expect(restored.review.totalInclVatCents, 45000);
    expect(restored.draft.stops, ['Antwerpen']);
    expect(jsonEncode(restored.toJson()), isNot(contains('sess_1')));
    expect(jsonEncode(restored.toJson()), isNot(contains('Bearer')));
  });

  test('2) same-customer same-scope restoration succeeds', () async {
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: MemoryLimousineAcceptedBookingVault(),
      clock: _clock,
    );
    await _persist(repo);
    final restored = await repo.restore(
      scope: _scope(publicPartnerId: 'p1', tenantId: 'p1', companyId: 'p1'),
    );
    expect(restored?.handoff.from, 'Gent');
    expect(restored?.review.offerTitle, 'Executive');
  });

  test('3) cross-customer isolation clears the envelope', () async {
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: MemoryLimousineAcceptedBookingVault(),
      clock: _clock,
    );
    await _persist(repo);
    expect(await repo.restore(scope: _scope(customerId: 'cust_2')), isNull);
    expect(await repo.restore(scope: _scope()), isNull);
  });

  test('4) cross-tenant isolation clears the envelope', () async {
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: MemoryLimousineAcceptedBookingVault(),
      clock: _clock,
    );
    await _persist(repo);
    expect(await repo.restore(scope: _scope(tenantId: 'other_tenant')), isNull);
    expect(await repo.restore(scope: _scope()), isNull);
  });

  test('5) company and public-partner mismatch clears the envelope', () async {
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: MemoryLimousineAcceptedBookingVault(),
      clock: _clock,
    );
    await _persist(repo);
    expect(await repo.restore(scope: _scope(companyId: 'other_co')), isNull);
    await _persist(repo);
    expect(
      await repo.restore(scope: _scope(publicPartnerId: 'other_partner')),
      isNull,
    );
    expect(await repo.restore(scope: _scope()), isNull);
  });

  test('6) expiry cleanup uses the fake clock', () async {
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: MemoryLimousineAcceptedBookingVault(),
      clock: _clock,
    );
    await _persist(repo, expiresAt: _now.add(const Duration(minutes: 60)));
    expect(await repo.restore(scope: _scope()), isNotNull);
    _now = _now.add(const Duration(hours: 2));
    expect(await repo.restore(scope: _scope()), isNull);
    expect(await repo.restore(scope: _scope()), isNull);
  });

  test('7) malformed and incompatible schema cleanup', () async {
    final vault = MemoryLimousineAcceptedBookingVault();
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: vault,
      clock: _clock,
    );
    await vault.write('{"schema_version":2,"customer_id":"cust_1"}');
    expect(await repo.restore(scope: _scope()), isNull);
    await vault.write('not-json');
    expect(await repo.restore(scope: _scope()), isNull);
    await vault.write(
      jsonEncode(<String, dynamic>{
        'schema_version': 1,
        'acceptance_reference': 'limacc1.onlytwo',
        'customer_id': 'cust_1',
        'public_partner_id': 'p1',
        'tenant_id': 'p1',
        'company_id': 'p1',
        'from': 'Gent',
        'to': 'Brussel',
        'scheduled_pickup_iso': '2026-09-01T10:00:00Z',
        'created_at': _now.toIso8601String(),
        'expires_at': _now.add(const Duration(minutes: 60)).toIso8601String(),
      }),
    );
    expect(await repo.restore(scope: _scope()), isNull);
  });

  test('8) logout cleanup clears the vault', () async {
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: MemoryLimousineAcceptedBookingVault(),
      clock: _clock,
    );
    final quote = LimousineCustomerQuoteController(
      gateway: _QuoteGateway(),
      resumeRepository: repo,
      customerIdLoader: () async => 'cust_1',
      clock: _clock,
    );
    await _persist(repo);
    quote.handoff = _handoff();
    quote.handleSessionClearedForTests();
    await Future<void>.delayed(Duration.zero);
    expect(quote.handoff, isNull);
    expect(await repo.restore(scope: _scope()), isNull);
    quote.dispose();
  });

  test('9) explicit discard cleanup', () async {
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: MemoryLimousineAcceptedBookingVault(),
      clock: _clock,
    );
    final quote = LimousineCustomerQuoteController(
      gateway: _QuoteGateway(),
      resumeRepository: repo,
      customerIdLoader: () async => 'cust_1',
      clock: _clock,
    );
    await _persist(repo);
    quote.applySecureResumeEnvelope((await repo.restore(scope: _scope()))!);
    await quote.discardSecureResume();
    expect(quote.handoff, isNull);
    expect(quote.restoredFromSecureResume, isFalse);
    expect(await repo.restore(scope: _scope()), isNull);
    quote.dispose();
  });

  test('10) confirmed success cleanup', () async {
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: MemoryLimousineAcceptedBookingVault(),
      clock: _clock,
    );
    await _persist(repo);
    final quote = LimousineCustomerQuoteController(
      gateway: _QuoteGateway(),
      resumeRepository: repo,
      customerIdLoader: () async => 'cust_1',
      clock: _clock,
    )..applySecureResumeEnvelope((await repo.restore(scope: _scope()))!);
    final booking = LimousineAcceptedBookingController(
      handoff: quote.handoff!,
      draft: quote.draft,
      reviewSnapshot: quote.secureResumeReview,
      entryEnabled: true,
      quoteController: quote,
      resumeRepository: repo,
      gateway: _BookGateway(),
      customerOverride: _customer,
      customerLoader: () async => _customer,
      persister:
          ({
            required response,
            required requestPayload,
            required customer,
          }) async {},
    )..setConfirmationAcknowledged(true);
    expect(await booking.confirmBooking(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(quote.handoff, isNull);
    expect(await repo.restore(scope: _scope()), isNull);
    booking.dispose();
    quote.dispose();
  });

  test('11) retryable and ambiguous failure retain the envelope', () async {
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: MemoryLimousineAcceptedBookingVault(),
      clock: _clock,
    );
    await _persist(repo);
    final quote = LimousineCustomerQuoteController(
      gateway: _QuoteGateway(),
      resumeRepository: repo,
      customerIdLoader: () async => 'cust_1',
      clock: _clock,
    )..applySecureResumeEnvelope((await repo.restore(scope: _scope()))!);
    final retryable = LimousineAcceptedBookingController(
      handoff: quote.handoff!,
      draft: quote.draft,
      entryEnabled: true,
      quoteController: quote,
      resumeRepository: repo,
      gateway: _BookGateway()
        ..error = const LimousineAcceptedBookException(code: 'network'),
      customerOverride: _customer,
      customerLoader: () async => _customer,
      persister:
          ({
            required response,
            required requestPayload,
            required customer,
          }) async {},
    )..setConfirmationAcknowledged(true);
    expect(await retryable.confirmBooking(), isFalse);
    expect(quote.handoff, isNotNull);
    expect(await repo.restore(scope: _scope()), isNotNull);
    retryable.dispose();

    final ambiguous = LimousineAcceptedBookingController(
      handoff: quote.handoff!,
      draft: quote.draft,
      entryEnabled: true,
      quoteController: quote,
      resumeRepository: repo,
      gateway: _BookGateway()
        ..error = const LimousineAcceptedBookException(
          code: 'ambiguous_timeout',
          ambiguous: true,
        ),
      customerOverride: _customer,
      customerLoader: () async => _customer,
      persister:
          ({
            required response,
            required requestPayload,
            required customer,
          }) async {},
    )..setConfirmationAcknowledged(true);
    expect(await ambiguous.confirmBooking(), isFalse);
    expect(ambiguous.phase, LimousineAcceptedBookingPhase.ambiguous);
    expect(quote.handoff, isNotNull);
    expect(await repo.restore(scope: _scope()), isNotNull);
    ambiguous.dispose();
    quote.dispose();
  });

  testWidgets('12) restoration makes zero /book calls', (tester) async {
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: MemoryLimousineAcceptedBookingVault(),
      clock: _clock,
    );
    await _persist(repo);
    final quote = LimousineCustomerQuoteController(
      gateway: _QuoteGateway(),
      resumeRepository: repo,
      customerIdLoader: () async => 'cust_1',
      clock: _clock,
    );
    final envelope = await quote.restoreAcceptedResume(scope: _scope());
    expect(envelope, isNotNull);
    final gateway = _BookGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: LimousineCustomerQuotePage(
          controller: quote,
          entryEnabled: true,
          resumeRepository: repo,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineAcceptedBookingContinueKey), findsOneWidget);
    expect(find.textContaining('limacc1'), findsNothing);
    expect(find.textContaining('sess_1'), findsNothing);
    expect(gateway.calls, 0);
    quote.dispose();
  });

  testWidgets('13) continue booking restores the accepted review only', (
    tester,
  ) async {
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: MemoryLimousineAcceptedBookingVault(),
      clock: _clock,
    );
    await _persist(repo);
    final quote = LimousineCustomerQuoteController(
      gateway: _QuoteGateway(),
      resumeRepository: repo,
      customerIdLoader: () async => 'cust_1',
      clock: _clock,
    )..applySecureResumeEnvelope((await repo.restore(scope: _scope()))!);
    final gateway = _BookGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: LimousineAcceptedBookingContinueAction(
                language: AppLanguage.en,
                onContinue: () => openLimousineAcceptedBookingReview(
                  context,
                  quoteController: quote,
                  gateway: gateway,
                  entryEnabled: true,
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.byKey(kLimousineAcceptedBookingContinueKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineAcceptedBookingReviewKey), findsOneWidget);
    expect(find.text('Coachline'), findsOneWidget);
    expect(find.text('Executive'), findsWidgets);
    expect(gateway.calls, 0);
    expect(find.textContaining('limacc1'), findsNothing);
    quote.dispose();
  });

  test('14) exactly one /book after explicit confirmation', () async {
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: MemoryLimousineAcceptedBookingVault(),
      clock: _clock,
    );
    await _persist(repo);
    final quote = LimousineCustomerQuoteController(
      gateway: _QuoteGateway(),
      resumeRepository: repo,
      customerIdLoader: () async => 'cust_1',
      clock: _clock,
    )..applySecureResumeEnvelope((await repo.restore(scope: _scope()))!);
    final gateway = _BookGateway();
    final booking = LimousineAcceptedBookingController(
      handoff: quote.handoff!,
      draft: quote.draft,
      reviewSnapshot: quote.secureResumeReview,
      entryEnabled: true,
      quoteController: quote,
      gateway: gateway,
      customerOverride: _customer,
      customerLoader: () async => _customer,
      persister:
          ({
            required response,
            required requestPayload,
            required customer,
          }) async {},
    );
    expect(await booking.confirmBooking(), isFalse);
    expect(gateway.calls, 0);
    booking.setConfirmationAcknowledged(true);
    expect(await booking.confirmBooking(), isTrue);
    expect(gateway.calls, 1);
    booking.dispose();
    quote.dispose();
  });

  test(
    '15) double-tap and stale-generation stay protected after resume',
    () async {
      final repo = LimousineAcceptedBookingResumeRepository(
        vault: MemoryLimousineAcceptedBookingVault(),
        clock: _clock,
      );
      await _persist(repo);
      final quote = LimousineCustomerQuoteController(
        gateway: _QuoteGateway(),
        resumeRepository: repo,
        customerIdLoader: () async => 'cust_1',
        clock: _clock,
      )..applySecureResumeEnvelope((await repo.restore(scope: _scope()))!);
      final gateway = _BookGateway()..delay = const Duration(milliseconds: 40);
      final booking = LimousineAcceptedBookingController(
        handoff: quote.handoff!,
        draft: quote.draft,
        entryEnabled: true,
        quoteController: quote,
        gateway: gateway,
        customerOverride: _customer,
        customerLoader: () async => _customer,
        persister:
            ({
              required response,
              required requestPayload,
              required customer,
            }) async {},
      )..setConfirmationAcknowledged(true);
      final first = booking.confirmBooking();
      final second = booking.confirmBooking();
      expect(await first, isTrue);
      expect(await second, isFalse);
      expect(gateway.calls, 1);
      expect(booking.bookCalls, 1);
      booking.dispose();
      quote.dispose();
    },
  );

  test('16) accepted snapshot stays immutable after restart', () async {
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: MemoryLimousineAcceptedBookingVault(),
      clock: _clock,
    );
    await _persist(repo, review: _review(totalInclVatCents: 45000));
    final restored = await repo.restore(scope: _scope());
    expect(restored!.review.totalInclVatCents, 45000);
    expect(restored.review.from, 'Gent');
    expect(restored.review.offerTitle, 'Executive');
    final mutated = LimousineCustomerQuoteController(
      gateway: _QuoteGateway(),
      resumeRepository: repo,
      customerIdLoader: () async => 'cust_1',
      clock: _clock,
    )..applySecureResumeEnvelope(restored);
    mutated.updateDraft(
      mutated.draft.copyWith(from: 'Antwerpen', to: 'Leuven'),
    );
    expect(mutated.secureResumeReview!.from, 'Gent');
    expect(mutated.secureResumeReview!.totalInclVatCents, 45000);
    mutated.dispose();
  });

  test('17) persisted totals never become /book authority', () async {
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: MemoryLimousineAcceptedBookingVault(),
      clock: _clock,
    );
    await _persist(repo, review: _review(totalInclVatCents: 999999));
    final quote = LimousineCustomerQuoteController(
      gateway: _QuoteGateway(),
      resumeRepository: repo,
      customerIdLoader: () async => 'cust_1',
      clock: _clock,
    )..applySecureResumeEnvelope((await repo.restore(scope: _scope()))!);
    final gateway = _BookGateway();
    final booking = LimousineAcceptedBookingController(
      handoff: quote.handoff!,
      draft: quote.draft,
      reviewSnapshot: quote.secureResumeReview,
      entryEnabled: true,
      quoteController: quote,
      gateway: gateway,
      customerOverride: _customer,
      customerLoader: () async => _customer,
      persister:
          ({
            required response,
            required requestPayload,
            required customer,
          }) async {},
    )..setConfirmationAcknowledged(true);
    expect(quote.secureResumeReview!.totalInclVatCents, 999999);
    expect(await booking.confirmBooking(), isTrue);
    expect(gateway.lastPayload!.containsKey('total_incl_vat_cents'), isFalse);
    expect(gateway.lastPayload!.containsKey('price_incl_vat'), isFalse);
    expect(gateway.lastPayload!['limousine_acceptance_reference'], _acceptRef);
    expect(booking.reviewSnapshot!.totalInclVatCents, 999999);
    booking.dispose();
    quote.dispose();
  });

  testWidgets('18) token never appears in UI or logs', (tester) async {
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: MemoryLimousineAcceptedBookingVault(),
      clock: _clock,
    );
    await _persist(repo);
    final quote = LimousineCustomerQuoteController(
      gateway: _QuoteGateway(),
      resumeRepository: repo,
      customerIdLoader: () async => 'cust_1',
      clock: _clock,
    )..applySecureResumeEnvelope((await repo.restore(scope: _scope()))!);
    final booking = LimousineAcceptedBookingController(
      handoff: quote.handoff!,
      draft: quote.draft,
      reviewSnapshot: quote.secureResumeReview,
      entryEnabled: true,
      quoteController: quote,
      gateway: _BookGateway(),
      customerOverride: _customer,
      customerLoader: () async => _customer,
      persister:
          ({
            required response,
            required requestPayload,
            required customer,
          }) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LimousineAcceptedBookingPage(
          controller: booking,
          entryEnabled: true,
        ),
      ),
    );
    expect(find.textContaining('limacc1'), findsNothing);
    expect(find.textContaining('sess_1'), findsNothing);
    booking.setConfirmationAcknowledged(true);
    await booking.confirmBooking();
    expect(booking.logSinkForTests.join(), isNot(contains('limacc1')));
    expect(quote.logSinkForTests.join(), isNot(contains('limacc1')));
    booking.dispose();
    quote.dispose();
  });

  test('19) failed storage operations fail closed', () async {
    final vault = MemoryLimousineAcceptedBookingVault()..failWrites = true;
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: vault,
      clock: _clock,
    );
    expect(await _persist(repo), isFalse);
    expect(repo.failedClosedForTests, isTrue);
    expect(await repo.restore(scope: _scope()), isNull);

    final readVault = MemoryLimousineAcceptedBookingVault()..failReads = true;
    final readRepo = LimousineAcceptedBookingResumeRepository(
      vault: readVault,
      clock: _clock,
    );
    expect(await readRepo.restore(scope: _scope()), isNull);
    expect(readRepo.failedClosedForTests, isTrue);
  });

  test('20) stale persist cannot resurrect a cleared envelope', () async {
    final vault = MemoryLimousineAcceptedBookingVault();
    final repo = LimousineAcceptedBookingResumeRepository(
      vault: vault,
      clock: _clock,
    );
    late final Future<bool> pending;
    vault.failWrites = false;
    pending = _persist(repo);
    await repo.discard();
    await pending;
    expect(await repo.restore(scope: _scope()), isNull);
  });

  test(
    '21) accept persists only with authoritative expiry and customer id',
    () async {
      final repo = LimousineAcceptedBookingResumeRepository(
        vault: MemoryLimousineAcceptedBookingVault(),
        clock: _clock,
      );
      final missingExpiry = LimousineCustomerQuoteController(
        gateway: _QuoteGateway()
          ..acceptResult = LimousineQuoteAcceptResult(
            request: _request(state: 'accepted'),
            acceptanceReference: _acceptRef,
          ),
        resumeRepository: repo,
        customerIdLoader: () async => 'cust_1',
        clock: _clock,
      );
      missingExpiry
        ..updateDraft(_draft())
        ..request = _request()
        ..setTermsAcknowledged(true);
      expect(await missingExpiry.acceptCurrentQuote(), isTrue);
      expect(await repo.restore(scope: _scope()), isNull);
      missingExpiry.dispose();

      final gateway = _QuoteGateway();
      final quote = LimousineCustomerQuoteController(
        gateway: gateway,
        resumeRepository: repo,
        customerIdLoader: () async => 'cust_1',
        clock: _clock,
      );
      quote
        ..updateDraft(_draft())
        ..request = _request()
        ..setTermsAcknowledged(true);
      expect(await quote.acceptCurrentQuote(), isTrue);
      expect(await repo.restore(scope: _scope()), isNotNull);
      quote.dispose();
    },
  );

  test('22) marketplace and worker gates stay OFF', () {
    expect(kLimousineMarketplaceCustomerEntryEnabled, isFalse);
    expect(LimousineCustomerEntryContract.isVisible, isFalse);
  });

  test('23) continue-booking labels exist in NL/EN/FR/ES', () {
    for (final language in AppLanguage.values) {
      if (language == AppLanguage.de) continue;
      expect(kLimousineAcceptedBookingContinue.of(language).trim(), isNotEmpty);
      expect(kLimousineAcceptedBookingDiscard.of(language).trim(), isNotEmpty);
      expect(
        kLimousineAcceptedBookingResumeHint.of(language).trim(),
        isNotEmpty,
      );
    }
  });
}
