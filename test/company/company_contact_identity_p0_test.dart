// COMPANY-CONTACT-IDENTITY-P0 — primary contact mail + pairing + badge.
//
// Run:
//   flutter test test/company/company_contact_identity_p0_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';

CompanyProfile _localProfile({
  String companyId = 'fluxidi_fluxidi_ddmh9g',
  String email = 'cvanrokeghem@outlook.com',
  String companyEmail = 'cvanrokeghem@outlook.com',
  String supportEmail = 'info@fluxidi.com',
  String billingEmail = 'billing@fluxidi.com',
  String bookingEmail = 'fluxidi.booking@gmail.com',
  String notificationEmail = 'notify@fluxidi.com',
  String ownerName = 'Christophe',
  String verificationStatus = CompanyVerificationStatus.pendingVerification,
}) {
  final now = '2026-08-16T08:00:00.000Z';
  return CompanyProfile(
    companyId: companyId,
    companyName: 'Fluxidi',
    ownerName: ownerName,
    email: email,
    phone: '+32000000',
    vatNumber: 'BE0000000000',
    addressLine: 'Kerkstraat 1',
    postalCode: '1000',
    city: 'Brussel',
    countryCode: 'BE',
    companyEmail: companyEmail,
    supportEmail: supportEmail,
    billingEmail: billingEmail,
    bookingEmail: bookingEmail,
    notificationEmail: notificationEmail,
    createdAt: now,
    updatedAt: now,
    isActive: true,
    verificationStatus: verificationStatus,
  );
}

ActiveCompanySession _session({
  String companyId = 'fluxidi_fluxidi_ddmh9g',
  String? token = 'cst_server_confirmed',
}) {
  final now = '2026-08-16T08:00:00.000Z';
  return ActiveCompanySession(
    companyId: companyId,
    role: 'companyAdmin',
    createdAt: now,
    lastUsedAt: now,
    companySessionToken: token,
  );
}

BackendBusinessProfile _backend({
  String email = 'contact@fluxidi.com',
  String companyEmail = 'route@fluxidi.com',
  String supportEmail = 'info@fluxidi.com',
  String invoiceEmail = 'billing@fluxidi.com',
  String bookingEmail = 'fluxidi.booking@gmail.com',
  String notificationEmail = 'notify@fluxidi.com',
  bool mollieConnected = false,
  bool? livePaymentsEnabled,
}) {
  return BackendBusinessProfile(
    companyName: 'Fluxidi',
    legalName: 'Fluxidi BV',
    vatNumber: 'BE0000000000',
    companyRegistrationNumber: '0123',
    address: 'Kerkstraat 1',
    postcode: '1000',
    city: 'Brussel',
    country: 'BE',
    phone: '+32000000',
    email: email,
    companyEmail: companyEmail,
    supportEmail: supportEmail,
    notificationEmail: notificationEmail,
    website: '',
    bookingEmail: bookingEmail,
    invoiceEmail: invoiceEmail,
    iban: '',
    paymentReferencePrefix: 'FLX',
    invoiceReceiptFooterText: '',
    mollieConnected: mollieConnected,
    livePaymentsEnabled: livePaymentsEnabled,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('primary company contact mail', () {
    test('both screens hydrate the same backend email', () {
      final hydrated = hydratePrimaryContactEmails(
        backend: _backend(email: 'contact@fluxidi.com'),
        local: _localProfile(email: 'stale-local@example.com'),
      );
      expect(hydrated.mijnEmail, 'contact@fluxidi.com');
      expect(hydrated.officialEmail, 'contact@fluxidi.com');
      expect(hydrated.mijnEmail, hydrated.officialEmail);
    });

    test(
      'reload/app-restart from cached JSON keeps the same primary email',
      () {
        final saved = _backend(email: 'contact@fluxidi.com');
        final restarted = BackendBusinessProfile.fromJson(saved.toJson());
        final hydrated = hydratePrimaryContactEmails(
          backend: restarted,
          local: _localProfile(email: 'stale-local@example.com'),
        );
        expect(hydrated.mijnEmail, 'contact@fluxidi.com');
        expect(hydrated.officialEmail, 'contact@fluxidi.com');
      },
    );

    test(
      'empty email falls back to companyEmail for backend compatibility',
      () {
        final parsed = BackendBusinessProfile.fromJson(<String, dynamic>{
          'companyName': 'Fluxidi',
          'legalName': 'Fluxidi BV',
          'vatNumber': '',
          'companyRegistrationNumber': '',
          'address': '',
          'postcode': '',
          'city': '',
          'country': 'BE',
          'phone': '',
          'companyEmail': 'alias@fluxidi.com',
          'website': '',
          'bookingEmail': '',
          'invoiceEmail': '',
          'iban': '',
          'paymentReferencePrefix': 'FLX',
          'invoiceReceiptFooterText': '',
        });
        expect(parsed.email, 'alias@fluxidi.com');
        expect(parsed.companyEmail, 'alias@fluxidi.com');
      },
    );

    test(
      'toJson/fromJson keep companyEmail, supportEmail, notificationEmail',
      () {
        final original = _backend();
        final roundTrip = BackendBusinessProfile.fromJson(original.toJson());
        expect(roundTrip.email, original.email);
        expect(roundTrip.companyEmail, original.companyEmail);
        expect(roundTrip.supportEmail, original.supportEmail);
        expect(roundTrip.notificationEmail, original.notificationEmail);
        expect(roundTrip.invoiceEmail, original.invoiceEmail);
        expect(roundTrip.bookingEmail, original.bookingEmail);
      },
    );

    test(
      'primary-contact save reaches /admin/business/profile and only changes email',
      () async {
        final current = _backend();
        BackendBusinessProfile? posted;
        final result = await savePrimaryCompanyContactEmail(
          email: 'new-contact@fluxidi.com',
          fetchCurrent: () async => current,
          persist: (profile) async {
            posted = profile;
            return profile.copyWith(email: profile.email);
          },
        );
        expect(result.ok, isTrue);
        expect(result.persistPath, kAdminBusinessProfilePath);
        expect(posted, isNotNull);
        expect(posted!.email, 'new-contact@fluxidi.com');
        expect(posted!.companyEmail, current.companyEmail);
        expect(posted!.supportEmail, current.supportEmail);
        expect(posted!.invoiceEmail, current.invoiceEmail);
        expect(posted!.bookingEmail, current.bookingEmail);
        expect(posted!.notificationEmail, current.notificationEmail);
      },
    );

    test('backend failure keeps the draft and is not success', () async {
      final result = await savePrimaryCompanyContactEmail(
        email: 'kept@fluxidi.com',
        fetchCurrent: () async => _backend(),
        persist: (_) async => throw Exception('HTTP 503'),
      );
      expect(result.ok, isFalse);
      expect(result.saved, isNull);
      expect(result.draftEmail, 'kept@fluxidi.com');
    });

    test('changing primary contact never overwrites other mail routes', () {
      final current = _backend();
      final next = applyPrimaryCompanyContactEmail(
        current,
        'only-primary@fluxidi.com',
      );
      expect(next.email, 'only-primary@fluxidi.com');
      expect(next.companyEmail, current.companyEmail);
      expect(next.supportEmail, 'info@fluxidi.com');
      expect(next.invoiceEmail, 'billing@fluxidi.com');
      expect(next.bookingEmail, 'fluxidi.booking@gmail.com');
      expect(next.notificationEmail, 'notify@fluxidi.com');

      final local = applyPrimaryCompanyContactEmailToLocal(
        _localProfile(),
        'only-primary@fluxidi.com',
      );
      expect(local.email, 'only-primary@fluxidi.com');
      expect(local.companyEmail, 'cvanrokeghem@outlook.com');
      expect(local.supportEmail, 'info@fluxidi.com');
      expect(local.billingEmail, 'billing@fluxidi.com');
      expect(local.bookingEmail, 'fluxidi.booking@gmail.com');
      expect(local.notificationEmail, 'notify@fluxidi.com');
    });
  });

  group('verified pairing merge', () {
    test('re-pair keeps existing contact person and mail routes', () {
      final existing = _localProfile();
      final incoming = _localProfile(
        ownerName: '',
        email: '',
        companyEmail: '',
        supportEmail: '',
        billingEmail: '',
        bookingEmail: '',
        notificationEmail: '',
      );
      final merged = mergeCompanyProfileForVerifiedPairing(
        incoming: incoming,
        existingLocal: existing,
        existingBackend: _backend(email: 'backend-contact@fluxidi.com'),
      );
      expect(merged.ownerName, 'Christophe');
      expect(merged.email, 'cvanrokeghem@outlook.com');
      expect(merged.companyEmail, 'cvanrokeghem@outlook.com');
      expect(merged.supportEmail, 'info@fluxidi.com');
      expect(merged.billingEmail, 'billing@fluxidi.com');
      expect(merged.bookingEmail, 'fluxidi.booking@gmail.com');
    });

    test(
      're-pair fills empty local primary email from backend, not blanks',
      () {
        final existing = _localProfile(email: '', companyEmail: '');
        final incoming = _localProfile(
          ownerName: '',
          email: '',
          companyEmail: '',
          supportEmail: '',
          billingEmail: '',
          bookingEmail: '',
          notificationEmail: '',
        );
        final merged = mergeCompanyProfileForVerifiedPairing(
          incoming: incoming,
          existingLocal: existing,
          existingBackend: _backend(email: 'backend-contact@fluxidi.com'),
        );
        expect(merged.email, 'backend-contact@fluxidi.com');
        expect(merged.supportEmail, 'info@fluxidi.com');
      },
    );

    test(
      'different company is not overwritten from the previous local profile',
      () {
        final existing = _localProfile(companyId: 'other_company');
        final incoming = _localProfile(
          companyId: 'new_company',
          ownerName: '',
          email: '',
          companyEmail: '',
          supportEmail: '',
          billingEmail: '',
          bookingEmail: '',
          notificationEmail: '',
        );
        final merged = mergeCompanyProfileForVerifiedPairing(
          incoming: incoming,
          existingLocal: existing,
          existingBackend: null,
        );
        expect(merged.ownerName, isEmpty);
        expect(merged.email, isEmpty);
        expect(merged.supportEmail, isEmpty);
      },
    );
  });

  group('company link badge', () {
    test(
      'paired server company shows Gekoppeld, not live-features-later copy',
      () {
        final profile = _localProfile();
        final session = _session();
        expect(
          resolveCompanyLinkDisplayKind(profile: profile, session: session),
          CompanyLinkDisplayKind.paired,
        );
        expect(
          profile.verificationBadgeLabel(AppLanguage.nl, serverPaired: true),
          'Gekoppeld',
        );
        expect(
          profile.showsPendingVerificationNotice(serverPaired: true),
          isFalse,
        );
        expect(
          profile.verificationPendingNotice(AppLanguage.nl),
          contains('live-functies'),
        );
      },
    );

    test('local unpaired company stays fail-closed as Niet geverifieerd', () {
      final profile = _localProfile();
      final localSession = _session(token: null);
      expect(
        resolveCompanyLinkDisplayKind(profile: profile, session: localSession),
        CompanyLinkDisplayKind.localUnverified,
      );
      expect(
        hasServerConfirmedCompanyPairing(
          profile: profile,
          session: localSession,
        ),
        isFalse,
      );
      expect(
        profile.verificationBadgeLabel(AppLanguage.nl, serverPaired: false),
        'Niet geverifieerd',
      );
      expect(profile.showsPendingVerificationNotice(), isTrue);
    });

    test('Mollie/Chiron do not promote the badge to Geverifieerd', () {
      final profile = _localProfile();
      final session = _session();
      expect(
        resolveCompanyLinkDisplayKind(
          profile: profile,
          session: session,
          mollieLive: true,
          chironProductionEnabled: true,
        ),
        CompanyLinkDisplayKind.paired,
      );
      expect(
        profile.verificationBadgeLabel(AppLanguage.nl, serverPaired: true),
        isNot('Geverifieerd'),
      );
      expect(
        resolveCompanyLinkDisplayKind(
          profile: profile,
          session: _session(token: null),
          mollieLive: true,
          chironProductionEnabled: true,
        ),
        CompanyLinkDisplayKind.localUnverified,
      );
    });

    test('explicit verified status is the only Geverifieerd fact', () {
      final profile = _localProfile(
        verificationStatus: CompanyVerificationStatus.verified,
      );
      expect(
        resolveCompanyLinkDisplayKind(
          profile: profile,
          session: _session(token: null),
        ),
        CompanyLinkDisplayKind.verified,
      );
      expect(
        profile.verificationBadgeLabel(AppLanguage.nl, serverPaired: false),
        'Geverifieerd',
      );
    });

    test('old pending_verification JSON remains readable', () {
      final profile = CompanyProfile.fromJson(<String, dynamic>{
        'companyId': 'co_legacy',
        'companyName': 'Legacy Co',
        'ownerName': 'Owner',
        'email': 'legacy@example.com',
        'phone': '',
        'vatNumber': '',
        'addressLine': '',
        'postalCode': '',
        'city': '',
        'countryCode': 'BE',
        'companyEmail': '',
        'supportEmail': '',
        'billingEmail': '',
        'bookingEmail': '',
        'notificationEmail': '',
        'createdAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': '2024-01-01T00:00:00.000Z',
        'isActive': true,
      });
      expect(
        profile.verificationStatus,
        CompanyVerificationStatus.pendingVerification,
      );
      expect(
        profile.verificationBadgeLabel(AppLanguage.nl),
        'Niet geverifieerd',
      );
      expect(profile.showsPendingVerificationNotice(), isTrue);
      expect(
        profile.showsPendingVerificationNotice(serverPaired: true),
        isFalse,
      );
    });
  });
}
