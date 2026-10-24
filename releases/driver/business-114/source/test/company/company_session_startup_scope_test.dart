import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/app_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('company-startup-scope-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    companyProfileNotifier.value = null;
    activeCompanySessionNotifier.value = null;
  });

  tearDown(() async {
    await flushLocalTenantStateWrites();
    companyProfileNotifier.value = null;
    activeCompanySessionNotifier.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> pair(String id, String token) =>
      CompanySessionStore.instance.saveVerifiedCompanyPairingSession(
        tenantId: id,
        companyId: id,
        companyName: id,
        countryCode: 'BE',
        companySessionToken: token,
      );

  test(
    'reopening selects the saved active company and its own bearer',
    () async {
      await pair('company-a', 'token-a');
      await pair('company-b', 'token-b');
      await CompanySessionStore.instance.bootstrap();
      expect(companyProfileNotifier.value?.companyId, 'company-b');
      expect(activeCompanySessionNotifier.value?.companyId, 'company-b');
      expect(
        activeCompanySessionNotifier.value?.companySessionToken,
        'token-b',
      );
    },
  );

  test('an orphan profile does not create a tokenless session', () async {
    await pair('company-a', 'token-a');
    final source = companyProfileNotifier.value!;
    await CompanySessionStore.instance.persistProfile(
      source.copyWith(companyId: 'company-b', companyName: 'company-b'),
    );
    await CompanySessionStore.instance.bootstrap();
    expect(activeCompanySessionNotifier.value?.companyId, 'company-a');
    expect(activeCompanySessionNotifier.value?.companySessionToken, 'token-a');
  });

  test(
    'missing active company session never falls back to another company',
    () async {
      await pair('company-a', 'token-a');
      await pair('company-b', 'token-b');
      final state = Directory('${root.path}/company_session');
      final sessionB = File(
        '${state.path}/tenant_company-b/company_company-b/active_company_session_v1.json',
      );
      expect(await sessionB.exists(), isTrue);
      await sessionB.delete();
      await CompanySessionStore.instance.bootstrap();
      expect(activeCompanySessionNotifier.value, isNull);
      expect(companyProfileNotifier.value, isNull);
    },
  );
  test('local expiry metadata keeps bearer for server validation', () async {
    await CompanySessionStore.instance.saveVerifiedCompanyPairingSession(
      tenantId: 'company-a',
      companyId: 'company-a',
      companyName: 'Company A',
      countryCode: 'BE',
      companySessionToken: 'token-a',
      expiresAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
    );
    await CompanySessionStore.instance.bootstrap();
    expect(activeCompanySessionNotifier.value?.companySessionToken, 'token-a');
    expect(CompanySessionStore.instance.hasValidCompanyContext, isTrue);
    expect(CompanySessionStore.instance.adminSessionRecoveryRequired, isFalse);
  });

  test('another company session requires recovery', () async {
    await pair('company-a', 'token-a');
    final profileA = companyProfileNotifier.value;
    await pair('company-b', 'token-b');
    companyProfileNotifier.value = profileA;
    expect(CompanySessionStore.instance.adminSessionRecoveryRequired, isTrue);
  });
}
