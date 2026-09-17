import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/active_local_customer_store.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer/local_qa_customer_session.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:fluxidi_tracking/fluxidi_runtime_env.dart';
import 'package:fluxidi_tracking/main.dart';
import 'package:fluxidi_tracking/nearby/stap3_flow_keys.dart';
import 'package:http/http.dart' as http;

const String _kExistingCustomerId = 'cust_oP9lF7XzUfyaiN5cz_ncV14PV4qnr5XF';
const String _kLoopback = 'http://127.0.0.1:8788';
const String _kProductionHost =
    'https://fluxidi-booking-api.fluxidi.workers.dev';

CustomerSession _session({
  required String customerId,
  DateTime? expiresAt,
}) {
  final now = DateTime.now().toUtc();
  return CustomerSession(
    customerSessionToken: 'cus_test_local_qa',
    expiresAt: (expiresAt ?? now.add(const Duration(days: 1))).toIso8601String(),
    customerId: customerId,
    phoneE164: '',
    createdAt: now.toIso8601String(),
    updatedAt: now.toIso8601String(),
  );
}

void _installPathProviderMock() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in <String>[
    'plugins.flutter.io/shared_preferences',
    'plugins.flutter.io/flutter_secure_storage',
    'flutter.baseflow.com/geolocator',
    'dev.fluttercommunity.plus/connectivity',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      if (call.method == 'getAll') return <String, Object>{};
      if (call.method == 'readAll') return <String, String>{};
      return null;
    });
  }
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => Directory.systemTemp.path,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _installPathProviderMock();
    appLanguageNotifier.value = AppLanguage.en;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await CustomerSessionStore.instance.clear();
    await ActiveLocalCustomerStore.instance.clearActiveCustomerId();
  });

  test('local_test binds the existing Fluxidi Demo Cars partner', () {
    final company = localQaDemoTaxiCompany(
      runtimeEnv: 'local_test',
      bookingBaseUrl: _kLoopback,
      qaEnabled: true,
    );
    expect(company, isNotNull);
    expect(company!.companyId, 'demo_company_p0');
    expect(company.partnerId, kStap3LocalPartnerId);
    expect(company.companyName, 'Fluxidi Demo Cars');
    expect(
      localQaDemoTaxiCompany(
        runtimeEnv: 'production',
        bookingBaseUrl: _kProductionHost,
        qaEnabled: true,
      ),
      isNull,
    );
  });

  test('1 local_test + loopback may use the existing customer profile', () {
    expect(
      canUseLocalQaCustomerSession(
        runtimeEnv: 'local_test',
        bookingBaseUrl: _kLoopback,
        qaEnabled: true,
      ),
      isTrue,
    );
  });

  test('2+3 QA bootstrap never starts OTP or sends mail', () async {
    final urls = <String>[];
    final session = await ensureLocalQaCustomerSession(
      preferredCustomerId: _kExistingCustomerId,
      runtimeEnv: 'local_test',
      bookingBaseUrl: _kLoopback,
      qaEnabled: true,
      adminToken: 'local-demo-admin',
      httpPost: (url, {headers, body}) async {
        urls.add(url.path);
        expect(url.path, kLocalQaCustomerSessionPath);
        expect(url.path.contains('/auth/phone/'), isFalse);
        expect(url.path.contains('/auth/email/'), isFalse);
        expect(url.path.contains('sms'), isFalse);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'customer_session_token': 'cus_worker_issued',
            'customer_id': _kExistingCustomerId,
            'expires_in_seconds': 3600,
          }),
          200,
        );
      },
    );
    expect(urls, [kLocalQaCustomerSessionPath]);
    expect(session.customerId, _kExistingCustomerId);
  });

  test('4+5 existing customer id is reused, no second profile', () async {
    await ActiveLocalCustomerStore.instance.setActiveCustomerId(
      _kExistingCustomerId,
    );
    final session = await ensureLocalQaCustomerSession(
      preferredCustomerId: _kExistingCustomerId,
      runtimeEnv: 'local_test',
      bookingBaseUrl: _kLoopback,
      qaEnabled: true,
      adminToken: 'local-demo-admin',
      httpPost: (url, {headers, body}) async {
        final payload = jsonDecode(body as String) as Map;
        expect(payload['customer_id'], _kExistingCustomerId);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'customer_session_token': 'cus_worker_issued',
            'customer_id': _kExistingCustomerId,
            'created': false,
          }),
          200,
        );
      },
    );
    expect(session.customerId, _kExistingCustomerId);
    expect(
      await ActiveLocalCustomerStore.instance.getActiveCustomerId(),
      _kExistingCustomerId,
    );
    expect(maskLocalQaCustomerId(_kExistingCustomerId), isNot(contains('oP9l')));
  });

  test('6 expired session uses only the local QA bootstrap', () async {
    await CustomerSessionStore.instance.save(
      _session(
        customerId: _kExistingCustomerId,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      ),
    );
    final urls = <String>[];
    final session = await ensureLocalQaCustomerSession(
      preferredCustomerId: _kExistingCustomerId,
      runtimeEnv: 'local_test',
      bookingBaseUrl: _kLoopback,
      qaEnabled: true,
      adminToken: 'local-demo-admin',
      httpPost: (url, {headers, body}) async {
        urls.add(url.path);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'customer_session_token': 'cus_worker_reissued',
            'customer_id': _kExistingCustomerId,
          }),
          200,
        );
      },
    );
    expect(urls, [kLocalQaCustomerSessionPath]);
    expect(session.customerSessionToken, 'cus_worker_reissued');
    expect(session.customerId, _kExistingCustomerId);
  });

  test('7 local_test with a remote host refuses the bypass', () {
    expect(
      canUseLocalQaCustomerSession(
        runtimeEnv: 'local_test',
        bookingBaseUrl: _kProductionHost,
        qaEnabled: true,
      ),
      isFalse,
    );
  });

  test('8 production and staging keep normal authentication', () {
    expect(
      canUseLocalQaCustomerSession(
        runtimeEnv: 'production',
        bookingBaseUrl: _kProductionHost,
        qaEnabled: true,
      ),
      isFalse,
    );
    expect(
      canUseLocalQaCustomerSession(
        runtimeEnv: 'staging',
        bookingBaseUrl: _kLoopback,
        qaEnabled: true,
      ),
      isFalse,
    );
    final source = File(
      '${Directory.current.path}/lib/main_parts/role_entry_page.dart',
    ).readAsStringSync();
    expect(source.contains('_promptCustomerEntryIntent'), isTrue);
    expect(source.contains('CustomerPhoneRecoveryPage'), isTrue);
    expect(
      File(
        '${Directory.current.path}/lib/app_config.dart',
      ).readAsStringSync().contains('startPublicCustomerPhoneAuth'),
      isTrue,
    );
  });

  test('local device stub is not sent; Worker keeps the existing id', () async {
    expect(localQaPreferredCustomerId('cust_65b6ac234254e_07343ecc'), isEmpty);
    expect(localQaPreferredCustomerId(_kExistingCustomerId), _kExistingCustomerId);
    final session = await ensureLocalQaCustomerSession(
      preferredCustomerId: 'cust_65b6ac234254e_07343ecc',
      runtimeEnv: 'local_test',
      bookingBaseUrl: _kLoopback,
      qaEnabled: true,
      adminToken: 'local-demo-admin',
      httpPost: (url, {headers, body}) async {
        final payload = jsonDecode(body as String) as Map;
        expect(payload.containsKey('customer_id'), isFalse);
        expect(payload.containsKey('customerId'), isFalse);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'customer_session_token': 'cus_worker_issued',
            'customer_id': _kExistingCustomerId,
            'created': false,
          }),
          200,
        );
      },
    );
    expect(session.customerId, _kExistingCustomerId);
  });

  test('compiled QA access does not read a disk customer id first', () {
    final source = File(
      '${Directory.current.path}/lib/customer/local_qa_customer_session.dart',
    ).readAsStringSync();
    expect(source.contains('peekCachedCustomerId'), isTrue);
    expect(
      File(
        '${Directory.current.path}/lib/customer/local_qa_customer_session.dart',
      ).readAsStringSync().contains('localQaDemoTaxiCompany'),
      isTrue,
    );
    expect(source.contains('getActiveCustomerId'), isFalse);
    expect(source.contains('mergeBackendProfileForSession'), isFalse);
    final roleEntry = File(
      '${Directory.current.path}/lib/main_parts/role_entry_page.dart',
    ).readAsStringSync();
    expect(
      roleEntry.contains('ensureExistingSession()\n            .timeout'),
      isFalse,
    );
  });

  test('9 query or deep link cannot enable local access in production', () {
    expect(
      canUseLocalQaCustomerSession(
        runtimeEnv: 'production',
        bookingBaseUrl: _kProductionHost,
        qaEnabled: false,
        queryParameters: const <String, String>{
          'local_qa': '1',
          'FLUXIDI_LOCAL_QA_CUSTOMER_SESSION': 'true',
        },
        deepLink: Uri.parse(
          'fluxidi://customer?FLUXIDI_LOCAL_QA_CUSTOMER_SESSION=true',
        ),
      ),
      isFalse,
    );
    expect(kFluxidiLocalQaCustomerSessionDefine, isFalse);
  });

  testWidgets(
    '10 Customer opens immediately and does not wait for two HTTP timeouts',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      var ensureCalls = 0;
      await tester.pumpWidget(
        buildFluxidiRootMaterialApp(
          theme: ThemeData.dark(),
          home: RoleEntryPage(
            autoAdvanceCarousel: false,
            localQaCustomerSession: LocalQaCustomerSessionAccess(
              enabled: true,
              ensureExistingSession: ({preferredCustomerId}) async {
                ensureCalls += 1;
                return _session(customerId: _kExistingCustomerId);
              },
            ),
          ),
        ),
      );
      await tester.pump();
      final sw = Stopwatch()..start();
      await tester.tap(find.byKey(kRoleEntryCustomerKey));
      for (var i = 0; i < 20; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.byType(CustomerHomePage).evaluate().isNotEmpty) break;
      }
      expect(ensureCalls, 1);
      expect(find.text('Start as customer'), findsNothing);
      expect(find.text('Login with phone'), findsNothing);
      expect(find.text('New customer'), findsNothing);
      expect(find.byType(CustomerHomePage), findsOneWidget);
      expect(sw.elapsed < const Duration(seconds: 2), isTrue);
    },
  );

  testWidgets('production RoleEntry still shows the normal customer dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      buildFluxidiRootMaterialApp(
        theme: ThemeData.dark(),
        home: const RoleEntryPage(autoAdvanceCarousel: false),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(kRoleEntryCustomerKey));
    for (var i = 0; i < 20; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.textContaining('Start as customer').evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.textContaining('Start as customer'), findsOneWidget);
    expect(find.text('Login with phone'), findsOneWidget);
  });
}
