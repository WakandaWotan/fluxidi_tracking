import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/affiliate/company_referral_registration.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'affiliate_fixture.dart';

class IntentMemory implements CompanyReferralIntentStore {
  final values = <String, String>{};
  bool failWrite = false;
  Future<void> Function(String, String)? beforeWrite;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('fixture disk unavailable');
    await beforeWrite?.call(key, value);
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async => values.remove(key);
}

const form = {
  'company_name': 'Referral fixture',
  'email': 'private@example.test',
};
const code = 'FLA-1234567890ABCDEF';
http.Response success() => http.Response(
  jsonEncode({
    'ok': true,
    'tenant_id': 'new_scope',
    'company_id': 'new_scope',
    'company_session_token': 'fixture_company_token',
    'public_company_code': 'FLX-99999',
    'affiliate_referral_state': 'held_owner_review',
  }),
  200,
  headers: affiliatePrivateHeaders,
);
Matcher fails(String code) => throwsA(
  isA<CompanyReferralException>().having((e) => e.code, 'code', code),
);

void main() {
  CustomerSession? current;
  late ValueNotifier<int> revision;
  late IntentMemory memory;
  setUp(() {
    current = affiliateSession('A');
    revision = ValueNotifier(0);
    memory = IntentMemory();
  });
  tearDown(() => revision.dispose());
  CompanyReferralRegistrationClient client(http.Client transport) =>
      CompanyReferralRegistrationClient(
        baseUrl: 'https://booking.example.test',
        transport: transport,
        intents: memory,
        loadSession: () async => current,
        currentSession: () => current,
        revision: revision,
      );

  test(
    'guest cannot borrow company bearer or create referral signup',
    () async {
      current = null;
      var calls = 0;
      final repository = client(
        MockClient((_) async {
          calls++;
          return success();
        }),
      );
      addTearDown(repository.dispose);
      await expectLater(
        repository.register(payload: form, referralCode: code),
        fails('affiliate_personal_login_required'),
      );
      expect(calls, 0);
      expect(memory.values, isEmpty);
    },
  );

  test(
    'exact personal bearer and durable metadata, cleared only after local save',
    () async {
      String? requestId;
      final repository = client(
        MockClient((request) async {
          expect(request.url.path, '/public/company/register');
          expect(request.headers['Authorization'], 'Bearer personal_fixture_A');
          final sent = jsonDecode(request.body);
          expect(sent['referral_code'], code);
          requestId = sent['affiliate_registration_request_id'];
          expect(requestId, matches(RegExp(r'^[a-f0-9]{48}$')));
          expect(memory.values, isNotEmpty);
          return success();
        }),
      );
      addTearDown(repository.dispose);
      final attempt = await repository.register(
        payload: form,
        referralCode: code.toLowerCase(),
      );
      final persisted = memory.values.values.single;
      expect(persisted, contains(requestId));
      for (final private in [
        'personal_fixture_A',
        'fixture_company_token',
        'private@example.test',
        'Referral fixture',
        code,
      ]) {
        expect(persisted, isNot(contains(private)));
      }
      await expectLater(
        repository.ensureNoPendingReferral(),
        fails('affiliate_registration_intent_locked'),
      );
      await repository.complete(attempt);
      await repository.ensureNoPendingReferral();
      expect(jsonDecode(memory.values.values.single), isEmpty);
    },
  );

  test(
    'lost reply and recreated client retry the same ID, never silently clear',
    () async {
      var calls = 0;
      final ids = <String>[];
      final transport = MockClient((request) async {
        calls++;
        ids.add(jsonDecode(request.body)['affiliate_registration_request_id']);
        if (calls == 1) throw http.ClientException('fixture connection lost');
        return success();
      });
      final first = client(transport);
      await expectLater(
        first.register(payload: form, referralCode: code),
        fails('affiliate_registration_retry_same_form'),
      );
      first.dispose();
      final restarted = client(transport);
      addTearDown(restarted.dispose);
      final attempt = await restarted.register(
        payload: {...form},
        referralCode: code,
      );
      expect(ids, hasLength(2));
      expect(ids[0], ids[1]);
      await expectLater(
        restarted.register(
          payload: {...form, 'company_name': 'Different'},
          referralCode: code,
        ),
        fails('affiliate_registration_intent_locked'),
      );
      expect(calls, 2);
      await restarted.complete(attempt);
    },
  );

  test(
    'first exact precommit validation refusal allows correcting the form',
    () async {
      var calls = 0;
      final repository = client(
        MockClient((_) async {
          calls++;
          if (calls == 1)
            return http.Response(
              jsonEncode({'ok': false, 'error': 'invalid_belgian_vat_number'}),
              400,
              headers: affiliatePrivateHeaders,
            );
          return success();
        }),
      );
      addTearDown(repository.dispose);
      await expectLater(
        repository.register(
          payload: {...form, 'vat_number': 'invalid'},
          referralCode: code,
        ),
        fails('invalid_belgian_vat_number'),
      );
      await repository.ensureNoPendingReferral();
      await repository.register(
        payload: {...form, 'vat_number': 'BE0123456789'},
        referralCode: code,
      );
      expect(calls, 2);
    },
  );

  test(
    'precommit-looking refusal after ambiguous delivery cannot discard prior ID',
    () async {
      var calls = 0;
      final repository = client(
        MockClient((_) async {
          calls++;
          if (calls == 1) throw http.ClientException('lost first reply');
          return http.Response(
            jsonEncode({'ok': false, 'error': 'missing_company_name'}),
            400,
            headers: affiliatePrivateHeaders,
          );
        }),
      );
      addTearDown(repository.dispose);
      await expectLater(
        repository.register(payload: form, referralCode: code),
        fails('affiliate_registration_retry_same_form'),
      );
      await expectLater(
        repository.register(payload: form, referralCode: code),
        fails('missing_company_name'),
      );
      await expectLater(
        repository.register(
          payload: {...form, 'company_name': 'changed'},
          referralCode: code,
        ),
        fails('affiliate_registration_intent_locked'),
      );
      current = null;
      revision.value++;
      await expectLater(
        repository.ensureNoPendingReferral(),
        fails('affiliate_registration_intent_locked'),
      );
      expect(calls, 2);
    },
  );

  test('storage failure sends no registration request', () async {
    memory.failWrite = true;
    var calls = 0;
    final repository = client(
      MockClient((_) async {
        calls++;
        return success();
      }),
    );
    addTearDown(repository.dispose);
    await expectLater(
      repository.register(payload: form, referralCode: code),
      fails('affiliate_registration_storage_unavailable'),
    );
    expect(calls, 0);
  });

  test(
    'uncacheable precommit-looking error cannot discard the retry ID',
    () async {
      final repository = client(
        MockClient(
          (_) async => http.Response(
            jsonEncode({'ok': false, 'error': 'missing_company_name'}),
            400,
          ),
        ),
      );
      addTearDown(repository.dispose);
      await expectLater(
        repository.register(payload: form, referralCode: code),
        fails('missing_company_name'),
      );
      await expectLater(
        repository.ensureNoPendingReferral(),
        fails('affiliate_registration_intent_locked'),
      );
      await expectLater(
        repository.register(
          payload: {...form, 'company_name': 'changed'},
          referralCode: code,
        ),
        fails('affiliate_registration_intent_locked'),
      );
    },
  );

  test(
    'company-only switch during POST preserves both newer company and retry intent',
    () async {
      var company = Object();
      final capturedCompany = company;
      final reply = Completer<http.Response>(), started = Completer<void>();
      final repository = client(
        MockClient((_) {
          started.complete();
          return reply.future;
        }),
      );
      addTearDown(repository.dispose);
      final request = repository.register(
        payload: form,
        referralCode: code,
        isCurrentRegistration: () => identical(company, capturedCompany),
      );
      await started.future;
      final newerCompany = Object();
      company = newerCompany;
      reply.complete(success());
      await expectLater(request, fails('affiliate_session_changed'));
      expect(identical(company, newerCompany), isTrue);
      expect(memory.values, isNotEmpty);
    },
  );

  test(
    'logout during intent-clear IO restores the same completed request ID',
    () async {
      final ids = <String>[];
      final repository = client(
        MockClient((request) async {
          ids.add(
            jsonDecode(request.body)['affiliate_registration_request_id'],
          );
          return success();
        }),
      );
      addTearDown(repository.dispose);
      final attempt = await repository.register(
        payload: form,
        referralCode: code,
      );
      final clearing = Completer<void>(), finish = Completer<void>();
      memory.beforeWrite = (_, value) async {
        if (jsonDecode(value).isEmpty && !clearing.isCompleted) {
          clearing.complete();
          await finish.future;
        }
      };
      final completion = repository.complete(attempt);
      await clearing.future;
      current = null;
      revision.value++;
      finish.complete();
      await expectLater(completion, fails('affiliate_session_changed'));
      expect(memory.values.values.single, contains(ids.single));
      current = affiliateSession('A');
      revision.value++;
      await repository.register(payload: form, referralCode: code);
      expect(ids, hasLength(2));
      expect(ids[0], ids[1]);
    },
  );

  test(
    'failed removal and failed restore surface storage failure, not completion',
    () async {
      final repository = client(MockClient((_) async => success()));
      addTearDown(repository.dispose);
      final attempt = await repository.register(
        payload: form,
        referralCode: code,
      );
      memory.failWrite = true;
      await expectLater(
        repository.complete(attempt),
        fails('affiliate_registration_storage_unavailable'),
      );
      expect(
        memory.values.values.single,
        contains(attempt.intentValue.replaceAll('"', r'\"')),
      );
    },
  );

  for (final status in [200, 401]) {
    test('late A $status cannot save A company under current B', () async {
      final reply = Completer<http.Response>(), started = Completer<void>();
      final repository = client(
        MockClient((_) {
          started.complete();
          return reply.future;
        }),
      );
      addTearDown(repository.dispose);
      final request = repository.register(payload: form, referralCode: code);
      await started.future;
      current = affiliateSession('B');
      revision.value++;
      reply.complete(status == 200 ? success() : http.Response('{}', status));
      await expectLater(request, fails('affiliate_session_changed'));
      expect(current!.customerId, 'B');
      expect(memory.values, isNotEmpty);
      await repository
          .ensureNoPendingReferral(); // B has no pending registration.
    });
  }

  test(
    'concurrent same-owner edited forms cannot allocate two identities',
    () async {
      final reply = Completer<http.Response>(), started = Completer<void>();
      var calls = 0;
      final repository = client(
        MockClient((_) {
          calls++;
          started.complete();
          return reply.future;
        }),
      );
      addTearDown(repository.dispose);
      final first = repository.register(payload: form, referralCode: code);
      await started.future;
      final second = repository.register(
        payload: {...form, 'company_name': 'other'},
        referralCode: code,
      );
      reply.complete(success());
      await first;
      await expectLater(second, fails('affiliate_registration_intent_locked'));
      expect(calls, 1);
    },
  );
}
