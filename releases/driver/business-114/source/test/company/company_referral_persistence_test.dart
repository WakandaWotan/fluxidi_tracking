import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:fluxidi_tracking/fluxidi_runtime_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late bool current;
  bool Function()? ownerCheck;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const previous = ActiveCompanySession(
    companyId: 'company-b',
    role: 'companyAdmin',
    createdAt: '2026-10-04T00:00:00Z',
    lastUsedAt: '2026-10-04T00:00:00Z',
    companySessionToken: 'fixture-b',
  );

  Directory getState() => Directory(
    '${root.path}/${fluxidiRuntimeStateDirName('company_session')}',
  );
  File scoped(String name) =>
      File('${getState().path}/tenant_company-a/company_company-a/$name');
  File pointer() => File('${getState().path}/active_company_id_v1.txt');
  Future<void> register() async {
    if (!current) throw StateError('session_changed');
    await CompanySessionStore.instance.savePublicCompanyRegistrationSession(
      tenantId: 'company-a',
      companyId: 'company-a',
      companyCode: 'FLX-123456',
      companyName: 'Fixture A',
      countryCode: 'BE',
      companySessionToken: 'fixture-a',
      ownerName: 'Fixture owner',
      email: 'owner@example.test',
      isCurrentRegistration: () => current && (ownerCheck?.call() ?? true),
    );
    if (!current) throw StateError('session_changed');
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'company-referral-persistence-',
    );
    current = true;
    ownerCheck = null;
    messenger.setMockMethodCallHandler(channel, (_) async => root.path);
    companyProfileNotifier.value = null;
    activeCompanySessionNotifier.value = previous;
    await getState().create(recursive: true);
    await pointer().writeAsString('company-b');
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    companyProfileNotifier.value = null;
    activeCompanySessionNotifier.value = null;
    expect(
      root.absolute.path.startsWith(Directory.systemTemp.absolute.path),
      true,
    );
    await root.delete(recursive: true);
  });

  test(
    'a personal owner switch during actual directory await preserves B and its disk pointer',
    () async {
      final started = Completer<void>(), release = Completer<String>();
      messenger.setMockMethodCallHandler(channel, (_) {
        if (!started.isCompleted) {
          started.complete();
          return release.future;
        }
        return Future.value(root.path);
      });
      final saving = register();
      final failure = expectLater(saving, throwsA(anything));
      await started.future;
      current = false;
      activeCompanySessionNotifier.value = previous;
      release.complete(root.path);
      await failure;
      expect(activeCompanySessionNotifier.value, same(previous));
      expect(companyProfileNotifier.value, isNull);
      expect(await pointer().readAsString(), 'company-b');
      expect(await scoped('active_company_session_v1.json').exists(), false);
    },
  );

  test(
    'an actual session file failure is reported and cannot activate A',
    () async {
      await Directory(
        scoped('active_company_session_v1.json').path,
      ).create(recursive: true);
      await expectLater(register(), throwsA(anything));
      expect(activeCompanySessionNotifier.value, same(previous));
      expect(companyProfileNotifier.value, isNull);
      expect(await pointer().readAsString(), 'company-b');
    },
  );

  test(
    'reentrant company listener switching to B cannot publish A profile or retain A pointer',
    () async {
      void changed() {
        if (activeCompanySessionNotifier.value?.companyId != 'company-a')
          return;
        current = false;
        activeCompanySessionNotifier.value = previous;
        pointer().writeAsStringSync('company-b');
      }

      activeCompanySessionNotifier.addListener(changed);
      try {
        await expectLater(register(), throwsA(anything));
      } finally {
        activeCompanySessionNotifier.removeListener(changed);
      }
      expect(activeCompanySessionNotifier.value, same(previous));
      expect(companyProfileNotifier.value, isNull);
      expect(await pointer().readAsString(), 'company-b');
    },
  );

  test(
    'current owner success proves scoped profile and bearer before completing',
    () async {
      final settings = businessSettingsNotifier.value;
      final cachedBackendProfile = localBackendBusinessProfileNotifier.value;
      await register();
      expect(activeCompanySessionNotifier.value?.companyId, 'company-a');
      expect(
        activeCompanySessionNotifier.value?.companySessionToken,
        'fixture-a',
      );
      expect(companyProfileNotifier.value?.companyName, 'Fixture A');
      final profile = jsonDecode(
        await scoped('company_profile_v1.json').readAsString(),
      );
      final session = jsonDecode(
        await scoped('active_company_session_v1.json').readAsString(),
      );
      expect(profile['companyId'], 'company-a');
      expect(session['companySessionToken'], 'fixture-a');
      expect(await pointer().readAsString(), 'company-a');
      expect(businessSettingsNotifier.value, same(settings));
      expect(
        localBackendBusinessProfileNotifier.value,
        same(cachedBackendProfile),
      );
      expect(await pointer().readAsString(), 'company-a');
    },
  );

  test(
    'same-person renewed bearer invalidates the pending disk save',
    () async {
      final personal = CustomerSessionStore.instance;
      CustomerSession customer(String bearer) => CustomerSession(
        customerSessionToken: bearer,
        customerId: 'personal-a',
        phoneE164: '+32000000000',
        expiresAt: DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
        createdAt: '2026-10-04T00:00:00Z',
        updatedAt: '2026-10-04T00:00:00Z',
      );
      personal.rememberSession(customer('personal-before'));
      final revision = CustomerSessionStore.sessionRevision.value;
      ownerCheck = () =>
          CustomerSessionStore.sessionRevision.value == revision &&
          personal.peekCachedSession()?.customerSessionToken ==
              'personal-before';
      final started = Completer<void>(), release = Completer<String>();
      messenger.setMockMethodCallHandler(channel, (_) {
        if (!started.isCompleted) {
          started.complete();
          return release.future;
        }
        return Future.value(root.path);
      });
      final failure = expectLater(
        register(),
        throwsA(isA<CompanyRegistrationPersistenceException>()),
      );
      await started.future;
      personal.rememberSession(customer('personal-after'));
      release.complete(root.path);
      await failure;
      expect(
        personal.peekCachedSession()?.customerSessionToken,
        'personal-after',
      );
      expect(activeCompanySessionNotifier.value, same(previous));
      expect(await pointer().readAsString(), 'company-b');
    },
  );

  test(
    'company switching alone invalidates save even when personal callback is still true',
    () async {
      final replacement = previous.copyWith(
        companyId: 'company-c',
        companySessionToken: 'fixture-c',
      );
      final started = Completer<void>(), release = Completer<String>();
      messenger.setMockMethodCallHandler(channel, (_) {
        if (!started.isCompleted) {
          started.complete();
          return release.future;
        }
        return Future.value(root.path);
      });
      final failure = expectLater(
        register(),
        throwsA(isA<CompanyRegistrationPersistenceException>()),
      );
      await started.future;
      activeCompanySessionNotifier.value = replacement;
      await pointer().writeAsString('company-c');
      release.complete(root.path);
      await failure;
      expect(current, true);
      expect(activeCompanySessionNotifier.value, same(replacement));
      expect(await pointer().readAsString(), 'company-c');
    },
  );

  test(
    'switch after actual staged file write leaves no discoverable A credentials',
    () async {
      final zone = Zone.current;
      await IOOverrides.runZoned(
        () async {
          await expectLater(
            register(),
            throwsA(isA<CompanyRegistrationPersistenceException>()),
          );
        },
        createFile: (path) => _ObservedFile(
          zone.run(() => File(path)),
          afterWrite: () {
            if (path.contains('company_profile_v1.json.registration_pending_'))
              current = false;
          },
        ),
      );
      expect(activeCompanySessionNotifier.value, same(previous));
      expect(await pointer().readAsString(), 'company-b');
      expect(await scoped('company_profile_v1.json').exists(), false);
      expect(await scoped('active_company_session_v1.json').exists(), false);
      expect(
        await getState()
            .list(recursive: true)
            .any((file) => file.path.contains('registration_pending_')),
        false,
      );
    },
  );

  test(
    'actual second rename failure restores only our first committed profile',
    () async {
      await scoped('company_profile_v1.json').parent.create(recursive: true);
      final oldBytes = jsonEncode(<String, Object?>{
        'companyId': 'company-a',
        'companyName': 'Previous scoped profile',
        'createdAt': '2026-09-01T00:00:00Z',
        'isActive': true,
      });
      await scoped('company_profile_v1.json').writeAsString(oldBytes);
      final zone = Zone.current;
      await IOOverrides.runZoned(
        () async {
          await expectLater(
            register(),
            throwsA(
              isA<CompanyRegistrationPersistenceException>().having(
                (e) => e.code,
                'code',
                'registration_storage_failed',
              ),
            ),
          );
        },
        createFile: (path) => _ObservedFile(
          zone.run(() => File(path)),
          failRename: path.contains(
            'active_company_session_v1.json.registration_pending_',
          ),
        ),
      );
      expect(await scoped('company_profile_v1.json').readAsString(), oldBytes);
      expect(await scoped('active_company_session_v1.json').exists(), false);
      expect(await pointer().readAsString(), 'company-b');
      expect(activeCompanySessionNotifier.value, same(previous));
      expect(companyProfileNotifier.value, isNull);
    },
  );

  test(
    'profile listener switch rolls back owned session and scoped files without overwriting B',
    () async {
      void changed() {
        if (companyProfileNotifier.value?.companyId != 'company-a') return;
        current = false;
        activeCompanySessionNotifier.value = previous;
        companyProfileNotifier.value = null;
        pointer().writeAsStringSync('company-b');
      }

      companyProfileNotifier.addListener(changed);
      try {
        await expectLater(
          register(),
          throwsA(isA<CompanyRegistrationPersistenceException>()),
        );
      } finally {
        companyProfileNotifier.removeListener(changed);
      }
      expect(activeCompanySessionNotifier.value, same(previous));
      expect(companyProfileNotifier.value, isNull);
      expect(await pointer().readAsString(), 'company-b');
      expect(await scoped('active_company_session_v1.json').exists(), false);
      expect(
        (await CompanySessionStore.instance.loadSession())?.companyId,
        isNot('company-a'),
      );
    },
  );

  test(
    'guarded invalid scope fails closed while unchanged legacy empty response remains a no-op',
    () async {
      await CompanySessionStore.instance.savePublicCompanyRegistrationSession(
        tenantId: '',
        companyId: '',
        companyCode: '',
        companyName: '',
        countryCode: 'BE',
        companySessionToken: '',
      );
      await expectLater(
        CompanySessionStore.instance.savePublicCompanyRegistrationSession(
          tenantId: 'company-b',
          companyId: 'company-a',
          companyCode: '',
          companyName: '',
          countryCode: 'BE',
          companySessionToken: 'fixture-a',
          isCurrentRegistration: () => true,
        ),
        throwsA(
          isA<CompanyRegistrationPersistenceException>().having(
            (e) => e.code,
            'code',
            'invalid_registration_scope',
          ),
        ),
      );
      expect(activeCompanySessionNotifier.value, same(previous));
      expect(await pointer().readAsString(), 'company-b');
      expect(await scoped('active_company_session_v1.json').exists(), false);
    },
  );
}

/// Fault injection wraps real temporary-directory IO, never substitutes data.
class _ObservedFile implements File {
  _ObservedFile(this.file, {this.afterWrite, this.failRename = false});
  final File file;
  final void Function()? afterWrite;
  final bool failRename;
  @override
  String get path => file.path;
  @override
  Future<bool> exists() => file.exists();
  @override
  bool existsSync() => file.existsSync();
  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      file.readAsString(encoding: encoding);
  @override
  String readAsStringSync({Encoding encoding = utf8}) =>
      file.readAsStringSync(encoding: encoding);
  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    await file.writeAsString(
      contents,
      mode: mode,
      encoding: encoding,
      flush: flush,
    );
    afterWrite?.call();
    return this;
  }

  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => file.writeAsStringSync(
    contents,
    mode: mode,
    encoding: encoding,
    flush: flush,
  );
  @override
  File renameSync(String newPath) {
    if (failRename) throw const FileSystemException('fixture rename failure');
    return file.renameSync(newPath);
  }

  @override
  FileSystemEntity deleteSync({bool recursive = false}) {
    file.deleteSync(recursive: recursive);
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused file operation');
}
