import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:fluxidi_tracking/fluxidi_runtime_env.dart';
import 'affiliate_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'personal load/save/remember/clear notify and late disk load cannot replace B or company login',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'affiliate-person-boundaries-',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final started = Completer<void>(), release = Completer<String>();
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) {
          if (!started.isCompleted) {
            started.complete();
            return release.future;
          }
          return Future.value(root.path);
        },
      );
      addTearDown(() async {
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
        final target = root.absolute.path;
        expect(target.startsWith(Directory.systemTemp.absolute.path), true);
        if (await root.exists()) await root.delete(recursive: true);
      });
      final stateDir = Directory(
        '${root.path}/${fluxidiRuntimeStateDirName('customer_state')}',
      );
      await stateDir.create(recursive: true);
      await File(
        '${stateDir.path}/global_customer_session_v1.json',
      ).writeAsString(jsonEncode(affiliateSession('A').toJson()));
      final store = CustomerSessionStore.instance;
      final firstRevision = CustomerSessionStore.sessionRevision.value;
      final pending = store.load();
      await started.future;
      store.rememberSession(affiliateSession('B'));
      expect(CustomerSessionStore.sessionRevision.value, firstRevision + 1);
      release.complete(root.path);
      expect((await pending)?.customerId, 'B');
      expect(store.peekCachedSession()?.customerId, 'B');
      activeCompanySessionNotifier.value = const ActiveCompanySession(
        companyId: 'company_fixture', role: 'companyAdmin',
        createdAt: '2026-10-04T00:00:00Z', lastUsedAt: '2026-10-04T00:00:00Z',
        companySessionToken: 'company_fixture_bearer');
      addTearDown(() => activeCompanySessionNotifier.value = null);
      final company = activeCompanySessionNotifier.value;
      expect(company?.companySessionToken, 'company_fixture_bearer');
      var changes = 0;
      void changed() {
        changes++;
      }

      CustomerSessionStore.sessionRevision.addListener(changed);
      await store.save(affiliateSession('C'));
      store.rememberSession(affiliateSession('D'));
      final clearing = store.clear();
      expect(store.peekCachedSession(), isNull);
      expect(changes, 3);
      expect(await store.load(), isNull);
      await clearing;
      CustomerSessionStore.sessionRevision.removeListener(changed);
      expect(activeCompanySessionNotifier.value, same(company));
      expect(
        activeCompanySessionNotifier.value?.companySessionToken,
        'company_fixture_bearer',
      );
    },
  );
}
