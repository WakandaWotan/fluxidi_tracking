// RELEASE-P0 — Clean Professional contrast + local ride register lifecycle
// through the actual ChironComplianceDashboardPage route.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/chiron_company_connection_config.dart';
import 'package:fluxidi_tracking/chiron_compliance_dashboard_page.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/compliance_ledger_reader.dart';
import 'package:fluxidi_tracking/widgets/chiron_friendly_diagnose_sheet.dart';

double _wcagChannel(double c) {
  if (c <= 0.03928) return c / 12.92;
  return math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(Color color) {
  final r = _wcagChannel(color.red / 255.0);
  final g = _wcagChannel(color.green / 255.0);
  final b = _wcagChannel(color.blue / 255.0);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final light = math.max(la, lb);
  final dark = math.min(la, lb);
  return (light + 0.05) / (dark + 0.05);
}

Finder _pageScrollable() => find.byType(Scrollable).first;

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: _pageScrollable(),
  );
  await tester.ensureVisible(finder);
  await tester.pump();
}

class _FakeLedgerReader extends ComplianceLedgerReader {
  _FakeLedgerReader({
    this.local,
    this.backendError,
    this.delay = Duration.zero,
    this.throwOnLocal,
    this.hangForever = false,
  });

  final ComplianceLedgerReadResult? local;
  final String? backendError;
  final Duration delay;
  final Object? throwOnLocal;
  final bool hangForever;
  int loadCount = 0;

  @override
  Future<ComplianceLedgerReadResult> loadRegisterGrouped({
    required int groupLimit,
    bool allowLegacyWithoutScope = false,
    void Function(ComplianceLedgerReadResult localSnapshot)? onLocalLoaded,
  }) async {
    loadCount += 1;
    if (hangForever) {
      return Completer<ComplianceLedgerReadResult>().future;
    }
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (throwOnLocal != null) {
      final empty = ComplianceLedgerReadResult(
        entries: const <ComplianceLedgerEntry>[],
        fileExists: false,
        skippedMalformedLines: 0,
        isSyncingBackend: false,
        backendFetchOk: false,
        backendError: complianceLedgerLooksLikeLockError(throwOnLocal!)
            ? 'local_file_lock'
            : 'local_read_failed',
      );
      onLocalLoaded?.call(empty);
      throw throwOnLocal!;
    }
    final snapshot =
        local ??
        const ComplianceLedgerReadResult(
          entries: <ComplianceLedgerEntry>[],
          fileExists: false,
          skippedMalformedLines: 0,
          isSyncingBackend: true,
        );
    onLocalLoaded?.call(snapshot);
    if (backendError != null) {
      return snapshot.copyWith(
        backendFetchOk: false,
        backendError: backendError,
        isSyncingBackend: false,
      );
    }
    return snapshot.copyWith(
      backendFetchOk: true,
      isSyncingBackend: false,
      mergedCount: snapshot.entries.length,
    );
  }
}

void _seedSession() {
  final now = DateTime.now().toUtc().toIso8601String();
  activeCompanySessionNotifier.value = ActiveCompanySession(
    companyId: 'co_contrast_test',
    role: 'companyAdmin',
    createdAt: now,
    lastUsedAt: now,
    companySessionToken: 'cst_contrast_test',
    companySessionExpiresAtUtc: DateTime.now()
        .toUtc()
        .add(const Duration(hours: 2))
        .toIso8601String(),
  );
  companyProfileNotifier.value = CompanyProfile(
    companyId: 'co_contrast_test',
    companyName: 'Contrast Co',
    ownerName: 'Owner',
    email: 'owner@example.test',
    phone: '+3200',
    vatNumber: '',
    addressLine: '',
    postalCode: '',
    city: '',
    countryCode: 'BE',
    companyEmail: '',
    supportEmail: '',
    billingEmail: '',
    bookingEmail: '',
    notificationEmail: '',
    createdAt: now,
    updatedAt: now,
    isActive: true,
  );
  backendChironConnectionStatusNotifier.value =
      const BackendChironConnectionStatus(
        ok: true,
        enabled: true,
        testCredentialsStored: true,
        lastConnectionStatus: 'test_passed',
        testflowStatus: 'in_progress',
        accTestSubmitActive: true,
        productionSubmitActive: false,
        effectiveChironEnvironment: ChironConnectionEnvironment.test,
      );
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  Size size = const Size(1280, 2400),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      // Reproduce production shell: dark theme + white outlined buttons.
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFD400),
          onPrimary: Colors.black,
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
        ),
      ),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        );
      },
      home: const ChironComplianceDashboardPage(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    appLanguageNotifier.value = AppLanguage.nl;
    businessThemeNotifier.value = BusinessThemeVariant.cleanProfessional;
    _seedSession();
  });

  tearDown(() {
    ComplianceLedgerReader.debugFactory = null;
    backendChironConnectionStatusNotifier.value = null;
    activeCompanySessionNotifier.value = null;
    companyProfileNotifier.value = null;
  });

  group('Clean Professional contrast on routed page', () {
    testWidgets('outlined / filled controls readable on light surfaces', (
      tester,
    ) async {
      await _pumpDashboard(tester);
      await _reveal(tester, find.byKey(const ValueKey('chiron_test_setup_card')));

      // Read the INNER Chiron Theme from a control on a light card.
      final themed = find.descendant(
        of: find.byKey(const ValueKey('chiron_test_setup_card')),
        matching: find.byType(OutlinedButton),
      );
      expect(themed, findsWidgets);
      final theme = Theme.of(tester.element(themed.first));
      final palette = paletteForBusinessTheme(
        BusinessThemeVariant.cleanProfessional,
      );
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.onSurface, palette.textPrimary);

      final outlinedFg =
          theme.outlinedButtonTheme.style?.foregroundColor?.resolve({}) ??
          theme.colorScheme.onSurface;
      expect(contrastRatio(outlinedFg, palette.surface), greaterThanOrEqualTo(4.5));
      // Must not inherit shell white-on-light.
      expect(outlinedFg, isNot(Colors.white));

      final filledFg =
          theme.filledButtonTheme.style?.foregroundColor?.resolve({}) ??
          theme.colorScheme.onPrimary;
      final filledBg =
          theme.filledButtonTheme.style?.backgroundColor?.resolve({}) ??
          theme.colorScheme.primary;
      expect(contrastRatio(filledFg, filledBg), greaterThanOrEqualTo(4.5));

      // Disabled production portal must remain readable (theme disabled fg).
      await _reveal(
        tester,
        find.byKey(const ValueKey('chiron_production_block_locked')),
      );
      expect(find.text('Open Chiron-productieportaal'), findsWidgets);
      final disabledFg =
          theme.outlinedButtonTheme.style?.foregroundColor?.resolve({
            WidgetState.disabled,
          }) ??
          theme.disabledColor;
      expect(disabledFg, isNot(Colors.white));
      expect(
        contrastRatio(disabledFg, palette.surface),
        greaterThanOrEqualTo(3.0),
      );
    });

    testWidgets('reset dialog readable under Clean Professional', (
      tester,
    ) async {
      await _pumpDashboard(tester);
      final reset = find.byKey(const ValueKey('chiron_reset_testflow_button'));
      await _reveal(tester, reset);
      final button = tester.widget<OutlinedButton>(reset);
      final future = Future<void>.sync(button.onPressed!);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(Dialog), findsOneWidget);
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      final surface = dialog.backgroundColor!;
      final palette = paletteForBusinessTheme(
        BusinessThemeVariant.cleanProfessional,
      );
      expect(contrastRatio(palette.textPrimary, surface), greaterThanOrEqualTo(4.5));
      expect(
        contrastRatio(palette.textSecondary, surface),
        greaterThanOrEqualTo(4.5),
      );

      await tester.tap(find.text('Annuleren'));
      await tester.pump();
      await future;
    });

    for (final variant in <BusinessThemeVariant>[
      BusinessThemeVariant.cleanProfessional,
      BusinessThemeVariant.corporateBlue,
      BusinessThemeVariant.executiveGold,
    ]) {
      testWidgets('${variant.name} phone/tablet/large-text no overflow', (
        tester,
      ) async {
        businessThemeNotifier.value = variant;
        for (final size in <Size>[
          const Size(390, 844),
          const Size(1280, 2400),
        ]) {
          for (final scale in <double>[1.0, 1.3, 1.5]) {
            await _pumpDashboard(tester, size: size, textScale: scale);
            expect(tester.takeException(), isNull);
            await _reveal(tester, find.text('Diagnose'));
            expect(tester.takeException(), isNull);
          }
        }
      });
    }
  });

  group('Local ride register lifecycle', () {
    Future<void> openRegister(WidgetTester tester) async {
      await _pumpDashboard(tester);
      await _reveal(tester, find.text('Lokaal rittenregister').first);
      await tester.tap(find.text('Lokaal rittenregister').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Local ledger page app bar confirms navigation completed.
      expect(find.byType(AppBar), findsWidgets);
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('cache success → data; spinner disappears', (tester) async {
      final fake = _FakeLedgerReader(
        local: ComplianceLedgerReadResult(
          entries: [
            ComplianceLedgerEntry.fromRaw({
              'booking_id': '2026-08-001',
              'tenant_id': 'co_contrast_test',
              'company_id': 'co_contrast_test',
              'event_type': 'ride_completed',
              'created_at': DateTime.now().toUtc().toIso8601String(),
            }, sourceLineIndex: 0),
          ],
          fileExists: true,
          skippedMalformedLines: 0,
          localCount: 1,
          mergedCount: 1,
        ),
      );
      ComplianceLedgerReader.debugFactory = () => fake;

      await openRegister(tester);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('chiron_local_register_loading')), findsNothing);
      expect(find.textContaining('2026-08-001'), findsWidgets);
      expect(fake.loadCount, 1);
    });

    testWidgets('no cache → empty state', (tester) async {
      final fake = _FakeLedgerReader(
        local: const ComplianceLedgerReadResult(
          entries: <ComplianceLedgerEntry>[],
          fileExists: false,
          skippedMalformedLines: 0,
        ),
      );
      ComplianceLedgerReader.debugFactory = () => fake;
      await openRegister(tester);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('chiron_local_register_empty')), findsOneWidget);
      expect(find.text('Nog geen lokale ritten gevonden'), findsOneWidget);
      expect(find.byKey(const ValueKey('chiron_local_register_loading')), findsNothing);
    });

    testWidgets('backend timeout → error when empty', (tester) async {
      final fake = _FakeLedgerReader(backendError: 'backend_timeout');
      ComplianceLedgerReader.debugFactory = () => fake;
      await openRegister(tester);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('chiron_local_register_error')), findsOneWidget);
      expect(find.byKey(const ValueKey('chiron_local_register_loading')), findsNothing);
    });

    testWidgets('auth timeout → error when empty', (tester) async {
      final fake = _FakeLedgerReader(backendError: 'auth_timeout');
      ComplianceLedgerReader.debugFactory = () => fake;
      await openRegister(tester);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('chiron_local_register_error')), findsOneWidget);
    });

    testWidgets('malformed response → error when empty', (tester) async {
      final fake = _FakeLedgerReader(backendError: 'malformed_response');
      ComplianceLedgerReader.debugFactory = () => fake;
      await openRegister(tester);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('chiron_local_register_error')), findsOneWidget);
    });

    testWidgets('local open timeout → error', (tester) async {
      final fake = _FakeLedgerReader(backendError: 'local_read_timeout');
      ComplianceLedgerReader.debugFactory = () => fake;
      await openRegister(tester);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('chiron_local_register_error')), findsOneWidget);
    });

    testWidgets('local file lock → error with retry', (tester) async {
      final fake = _FakeLedgerReader(
        throwOnLocal: Exception('Sharing violation - file locked'),
      );
      ComplianceLedgerReader.debugFactory = () => fake;
      await openRegister(tester);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('chiron_local_register_error')), findsOneWidget);
      expect(find.byKey(const ValueKey('chiron_local_register_retry')), findsOneWidget);
      expect(find.textContaining('vergrendeld'), findsOneWidget);
    });

    testWidgets('rebuild does not restart request', (tester) async {
      final fake = _FakeLedgerReader(
        delay: const Duration(milliseconds: 200),
        local: const ComplianceLedgerReadResult(
          entries: <ComplianceLedgerEntry>[],
          fileExists: false,
          skippedMalformedLines: 0,
        ),
      );
      ComplianceLedgerReader.debugFactory = () => fake;
      await openRegister(tester);
      expect(fake.loadCount, 1);
      await tester.pump(); // rebuild
      businessThemeNotifier.value = BusinessThemeVariant.corporateBlue;
      await tester.pump();
      businessThemeNotifier.value = BusinessThemeVariant.cleanProfessional;
      await tester.pump();
      expect(fake.loadCount, 1);
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('refresh double tap → one request', (tester) async {
      final fake = _FakeLedgerReader(
        delay: const Duration(milliseconds: 200),
        local: const ComplianceLedgerReadResult(
          entries: <ComplianceLedgerEntry>[],
          fileExists: false,
          skippedMalformedLines: 0,
        ),
      );
      ComplianceLedgerReader.debugFactory = () => fake;
      await openRegister(tester);
      await tester.pump(const Duration(milliseconds: 250));
      final baseline = fake.loadCount;
      final refresh = find.byKey(const ValueKey('chiron_local_register_refresh'));
      await tester.tap(refresh);
      // Second tap while first refresh is still in flight must coalesce.
      await tester.tap(refresh);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(fake.loadCount, baseline + 1);
    });

    testWidgets('hang forever hits hard deadline; spinner disappears', (
      tester,
    ) async {
      final fake = _FakeLedgerReader(hangForever: true);
      ComplianceLedgerReader.debugFactory = () => fake;
      await openRegister(tester);
      expect(
        find.byKey(const ValueKey('chiron_local_register_loading')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 12));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('chiron_local_register_loading')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('chiron_local_register_error')),
        findsOneWidget,
      );
    });

    testWidgets('cached rows stay visible when refresh fails', (tester) async {
      final fake = _StickyCacheThenFailReader();
      ComplianceLedgerReader.debugFactory = () => fake;
      await openRegister(tester);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('2026-08-010'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('chiron_local_register_refresh')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('2026-08-010'), findsWidgets);
      expect(find.byKey(const ValueKey('chiron_local_register_loading')), findsNothing);
    });
  });

  group('Diagnose loading ownership', () {
    testWidgets('opens first tap; one loading owner inside sheet', (
      tester,
    ) async {
      await _pumpDashboard(tester);
      final diagnose = find.byKey(const ValueKey('chiron_diagnose_button'));
      await _reveal(tester, diagnose);
      await tester.tap(diagnose);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(ChironFriendlyDiagnoseSheet), findsOneWidget);
      // Hub button must not switch to a second busy label behind the sheet.
      final hubButton = tester.widget<FilledButton>(diagnose);
      final hubLabel = find.descendant(
        of: diagnose,
        matching: find.text('Diagnose'),
      );
      expect(hubLabel, findsOneWidget);
      expect(hubButton.onPressed, isNotNull);
      // Loading copy is allowed only inside the sheet.
      final sheetLoading = find.descendant(
        of: find.byType(ChironFriendlyDiagnoseSheet),
        matching: find.text('Diagnose wordt uitgevoerd…'),
      );
      expect(sheetLoading, findsOneWidget);
    });
  });
}

class _StickyCacheThenFailReader extends ComplianceLedgerReader {
  int loads = 0;

  @override
  Future<ComplianceLedgerReadResult> loadRegisterGrouped({
    required int groupLimit,
    bool allowLegacyWithoutScope = false,
    void Function(ComplianceLedgerReadResult localSnapshot)? onLocalLoaded,
  }) async {
    loads += 1;
    final cached = ComplianceLedgerReadResult(
      entries: [
        ComplianceLedgerEntry.fromRaw({
          'booking_id': '2026-08-010',
          'tenant_id': 'co_contrast_test',
          'company_id': 'co_contrast_test',
          'event_type': 'ride_completed',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }, sourceLineIndex: 0),
      ],
      fileExists: true,
      skippedMalformedLines: 0,
      localCount: 1,
      mergedCount: 1,
      isSyncingBackend: loads == 1,
    );
    onLocalLoaded?.call(cached);
    if (loads == 1) {
      return cached.copyWith(backendFetchOk: true, isSyncingBackend: false);
    }
    return cached.copyWith(
      backendFetchOk: false,
      backendError: 'backend_timeout',
      isSyncingBackend: false,
      entries: const <ComplianceLedgerEntry>[],
      mergedCount: 0,
    );
  }
}
