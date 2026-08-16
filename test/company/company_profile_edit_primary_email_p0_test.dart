// COMPANY-PROFILE-EDIT-PRIMARY-EMAIL-P0
//
// Run:
//   flutter test test/company/company_profile_edit_primary_email_p0_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_onboarding_page.dart';
import 'package:fluxidi_tracking/company_session_store.dart';

CompanyProfile _profile() {
  const now = '2026-08-16T08:00:00.000Z';
  return const CompanyProfile(
    companyId: 'fluxidi_fluxidi_ddmh9g',
    companyName: 'Fluxidi',
    ownerName: 'Christophe',
    email: 'stale-local@example.com',
    phone: '+32000000',
    vatNumber: 'BE0000000000',
    addressLine: 'Kerkstraat 1',
    postalCode: '1000',
    city: 'Brussel',
    countryCode: 'BE',
    companyEmail: 'cvanrokeghem@outlook.com',
    supportEmail: 'info@fluxidi.com',
    billingEmail: 'billing@fluxidi.com',
    bookingEmail: 'fluxidi.booking@gmail.com',
    notificationEmail: 'notify@fluxidi.com',
    createdAt: now,
    updatedAt: now,
    isActive: true,
    verificationStatus: CompanyVerificationStatus.pendingVerification,
  );
}

BackendBusinessProfile _backend({String email = 'contact@fluxidi.com'}) {
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
    companyEmail: 'route@fluxidi.com',
    supportEmail: 'info@fluxidi.com',
    notificationEmail: 'notify@fluxidi.com',
    website: '',
    bookingEmail: 'fluxidi.booking@gmail.com',
    invoiceEmail: 'billing@fluxidi.com',
    iban: '',
    paymentReferencePrefix: 'FLX',
    invoiceReceiptFooterText: '',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    appLanguageNotifier.value = AppLanguage.nl;
    companyProfileNotifier.value = _profile();
    localBackendBusinessProfileNotifier.value = _backend();
  });

  tearDown(() {
    companyProfileNotifier.value = null;
    localBackendBusinessProfileNotifier.value = null;
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    required Future<BackendBusinessProfile> Function() fetch,
    required Future<BackendBusinessProfile> Function(BackendBusinessProfile)
    save,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyProfileEditPage(
          fetchBusinessProfile: fetch,
          saveBusinessProfile: save,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('Mijn bedrijfsgegevens loads the backend primary email', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      fetch: () async => _backend(email: 'contact@fluxidi.com'),
      save: (profile) async => profile,
    );
    expect(find.text('Mijn bedrijfsgegevens'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'contact@fluxidi.com'),
      findsOneWidget,
    );
    expect(find.text('stale-local@example.com'), findsNothing);
  });

  testWidgets('save posts only the primary email to the business profile API', (
    tester,
  ) async {
    BackendBusinessProfile? posted;
    await pumpEditor(
      tester,
      fetch: () async => _backend(),
      save: (profile) async {
        posted = profile;
        return profile;
      },
    );
    final emailField = find.widgetWithText(
      TextFormField,
      'contact@fluxidi.com',
    );
    await tester.enterText(emailField, 'new-contact@fluxidi.com');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Opslaan'));
    await tester.tap(find.widgetWithText(FilledButton, 'Opslaan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(posted, isNotNull);
    expect(posted!.email, 'new-contact@fluxidi.com');
    expect(posted!.supportEmail, 'info@fluxidi.com');
    expect(posted!.invoiceEmail, 'billing@fluxidi.com');
    expect(posted!.bookingEmail, 'fluxidi.booking@gmail.com');
    expect(posted!.companyEmail, 'route@fluxidi.com');
  });

  testWidgets(
    'backend error shows no false success and keeps the draft email',
    (tester) async {
      var persistCalls = 0;
      await pumpEditor(
        tester,
        fetch: () async => _backend(),
        save: (profile) async {
          persistCalls += 1;
          expect(profile.email, 'kept@fluxidi.com');
          throw Exception('HTTP 503');
        },
      );
      final emailField = find.widgetWithText(
        TextFormField,
        'contact@fluxidi.com',
      );
      await tester.enterText(emailField, 'kept@fluxidi.com');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Opslaan'));
      await tester.tap(find.widgetWithText(FilledButton, 'Opslaan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(persistCalls, 1);
      expect(find.text('Opgeslagen.'), findsNothing);
      expect(
        find.textContaining('Opslaan/synchroniseren niet gelukt'),
        findsWidgets,
      );
      expect(
        find.widgetWithText(TextFormField, 'kept@fluxidi.com'),
        findsOneWidget,
      );
      expect(find.text('Mijn bedrijfsgegevens'), findsOneWidget);
    },
  );
}
