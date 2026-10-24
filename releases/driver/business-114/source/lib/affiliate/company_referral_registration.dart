import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../customer_session_store.dart';

class CompanyReferralException implements Exception {
  const CompanyReferralException(this.code);
  final String code;
}

abstract class CompanyReferralIntentStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class SecureCompanyReferralIntentStore implements CompanyReferralIntentStore {
  const SecureCompanyReferralIntentStore();
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> remove(String key) => _storage.delete(key: key);
}

class CompanyReferralAttempt {
  const CompanyReferralAttempt({
    required this.session,
    required this.sessionRevision,
    required this.intentKey,
    required this.intentValue,
    required this.result,
    required this.isCurrentRegistration,
  });
  final CustomerSession session;
  final int sessionRevision;
  final String intentKey, intentValue;
  final Map<String, dynamic> result;
  final bool Function() isCurrentRegistration;
}

/// Optional referral signup. Ordinary signup without a code uses its existing
/// caller. Persistent state contains only a random request ID and form digest.
/// A lost reply reuses the same server registration; it cannot create a second
/// company by silently replacing the intent.
class CompanyReferralRegistrationClient {
  CompanyReferralRegistrationClient({
    http.Client? transport,
    String? baseUrl,
    CompanyReferralIntentStore? intents,
    Future<CustomerSession?> Function()? loadSession,
    CustomerSession? Function()? currentSession,
    ValueListenable<int>? revision,
  }) : _http = transport ?? http.Client(),
       _ownsHttp = transport == null,
       _base = baseUrl ?? kBookingBaseUrl,
       _intents = intents ?? const SecureCompanyReferralIntentStore(),
       _load = loadSession ?? CustomerSessionStore.instance.loadValidSession,
       _current =
           currentSession ?? CustomerSessionStore.instance.peekCachedSession,
       _revision = revision ?? CustomerSessionStore.sessionRevision;

  final http.Client _http;
  final bool _ownsHttp;
  final String _base;
  final CompanyReferralIntentStore _intents;
  final Future<CustomerSession?> Function() _load;
  final CustomerSession? Function() _current;
  final ValueListenable<int> _revision;
  bool _disposed = false;
  static final Map<String, Future<void>> _locks = {};
  static const _storageKey = 'affiliate_company_registration_v1';

  bool _owns(CustomerSession session, int revision) {
    final current = _current(), expiry = DateTime.tryParse(session.expiresAt);
    return !_disposed &&
        current != null &&
        _revision.value == revision &&
        current.customerId == session.customerId &&
        current.customerSessionToken == session.customerSessionToken &&
        session.customerSessionToken.isNotEmpty &&
        expiry != null &&
        DateTime.now().toUtc().isBefore(expiry.toUtc());
  }

  bool owns(CompanyReferralAttempt attempt) =>
      _owns(attempt.session, attempt.sessionRevision) &&
      attempt.isCurrentRegistration();

  void _check(CustomerSession session, int revision) {
    if (!_owns(session, revision)) {
      throw const CompanyReferralException('affiliate_session_changed');
    }
  }

  static dynamic _canonical(dynamic value) {
    if (value is List) return value.map(_canonical).toList();
    if (value is Map<String, dynamic>) {
      final keys = value.keys.toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    return value;
  }

  static String _digest(String value) =>
      sha256.convert(utf8.encode(value)).toString();
  static String _newId() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<Map<String, dynamic>> _index() async {
    try {
      final raw = await _intents.read(_storageKey);
      if (raw == null) return {};
      final index = jsonDecode(raw);
      if (index is! Map<String, dynamic> ||
          index.length > 32 ||
          index.entries.any(
            (e) =>
                !RegExp(r'^[a-f0-9]{64}$').hasMatch(e.key) ||
                e.value is! String,
          )) {
        throw const FormatException();
      }
      return index;
    } catch (_) {
      throw const CompanyReferralException(
        'affiliate_registration_storage_unavailable',
      );
    }
  }

  /// An unfinished referral must not be bypassed by removing the code and
  /// retrying anonymous signup. No other person's stored intent is disclosed.
  Future<void> ensureNoPendingReferral() => _serial(_storageKey, () async {
    final index = await _index();
    if (index.isEmpty) return;
    final session = await _load();
    if (session == null || index.containsKey(_digest(session.customerId))) {
      throw const CompanyReferralException(
        'affiliate_registration_intent_locked',
      );
    }
    _check(session, _revision.value);
  });

  Future<T> _serial<T>(String key, Future<T> Function() action) async {
    final previous = _locks[key];
    final completion = Completer<void>();
    _locks[key] = completion.future;
    try {
      if (previous != null) await previous;
      return await action();
    } finally {
      completion.complete();
      if (identical(_locks[key], completion.future)) _locks.remove(key);
    }
  }

  Future<CompanyReferralAttempt> register({
    required Map<String, dynamic> payload,
    required String referralCode,
    bool Function()? isCurrentRegistration,
  }) async {
    final isCurrent = isCurrentRegistration ?? () => true;
    void checkRegistration() {
      if (_disposed || !isCurrent()) {
        throw const CompanyReferralException('affiliate_session_changed');
      }
    }

    checkRegistration();
    final code = referralCode.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9-]{3,40}$').hasMatch(code)) {
      throw const CompanyReferralException('affiliate_referral_invalid');
    }
    final session = await _load();
    checkRegistration();
    if (session == null) {
      throw const CompanyReferralException('affiliate_personal_login_required');
    }
    final revision = _revision.value;
    void checkOwner() {
      _check(session, revision);
      checkRegistration();
    }

    checkOwner();
    const key = _storageKey;
    final ownerHash = _digest(session.customerId);
    return _serial(key, () async {
      checkOwner();
      final form = Map<String, dynamic>.from(payload)
        ..remove('affiliate_registration_request_id')
        ..['referral_code'] = code;
      final hash = _digest(jsonEncode(_canonical(form)));
      late String intentValue, requestId;
      late int attempts;
      late Map<String, dynamic> index;
      try {
        index = await _index();
        final stored = index[ownerHash] as String?;
        checkOwner();
        if (stored == null) {
          requestId = _newId();
          attempts = 1;
        } else {
          final intent = jsonDecode(stored);
          if (intent is! Map ||
              intent['payload_hash'] != hash ||
              intent['request_id'] is! String ||
              !RegExp(r'^[a-f0-9]{48}$').hasMatch(intent['request_id']) ||
              intent['attempts'] is! int ||
              intent['attempts'] < 1) {
            throw const CompanyReferralException(
              'affiliate_registration_intent_locked',
            );
          }
          requestId = intent['request_id'] as String;
          attempts = (intent['attempts'] as int) + 1;
        }
        if (index.length >= 32 && stored == null) throw const FormatException();
        intentValue = jsonEncode({
          'request_id': requestId,
          'payload_hash': hash,
          'attempts': attempts,
        });
        index[ownerHash] = intentValue;
        final persisted = jsonEncode(index);
        await _intents.write(key, persisted);
        checkOwner();
        if (await _intents.read(key) != persisted) {
          throw const CompanyReferralException(
            'affiliate_registration_storage_unavailable',
          );
        }
        checkOwner();
      } on CompanyReferralException {
        rethrow;
      } catch (_) {
        throw const CompanyReferralException(
          'affiliate_registration_storage_unavailable',
        );
      }
      checkOwner();
      final origin = Uri.parse(_base);
      if (origin.scheme != 'https' ||
          origin.host.isEmpty ||
          origin.userInfo.isNotEmpty ||
          origin.hasQuery ||
          origin.hasFragment) {
        throw const CompanyReferralException(
          'affiliate_registration_unavailable',
        );
      }
      final endpoint = origin.replace(
        path:
            '${origin.path.replaceFirst(RegExp(r'/$'), '')}/public/company/register',
      );
      late http.Response response;
      try {
        response = await _http
            .post(
              endpoint,
              headers: {
                'Authorization': 'Bearer ${session.customerSessionToken}',
                'Content-Type': 'application/json',
                'Cache-Control': 'no-store',
              },
              body: jsonEncode({
                ...form,
                'affiliate_registration_request_id': requestId,
              }),
            )
            .timeout(const Duration(seconds: 12));
      } catch (_) {
        checkOwner();
        throw const CompanyReferralException(
          'affiliate_registration_retry_same_form',
        );
      }
      checkOwner();
      try {
        if (response.bodyBytes.length > 256 * 1024)
          throw const FormatException();
        final result = jsonDecode(utf8.decode(response.bodyBytes));
        if (result is! Map<String, dynamic>) throw const FormatException();
        final cache = response.headers['cache-control']?.toLowerCase() ?? '';
        final privateResponse =
            cache.contains('private') && cache.contains('no-store');
        if (response.statusCode != 200 || result['ok'] != true) {
          final error = result['error'];
          // Only the FIRST observed response can prove no earlier signup was
          // committed. These exact server errors occur before registration
          // side effects. A replay/timeout/unknown error always retains its ID.
          final firstPrecommit =
              attempts == 1 &&
              privateResponse &&
              (response.statusCode == 400 &&
                      [
                        'invalid_belgian_vat_number',
                        'missing_company_name',
                      ].contains(error) ||
                  response.statusCode == 404 &&
                      error == 'affiliate_referral_unavailable' ||
                  response.statusCode == 403 &&
                      error == 'affiliate_self_referral' ||
                  response.statusCode == 503 &&
                      [
                        'affiliate_program_not_enabled',
                        'affiliate_terms_not_configured',
                        'affiliate_not_configured',
                      ].contains(error));
          if (firstPrecommit) {
            checkOwner();
            index.remove(ownerHash);
            await _removeOwnedIntent(
              key: key,
              ownerHash: ownerHash,
              index: index,
              intentValue: intentValue,
              checkOwner: checkOwner,
            );
          }
          throw CompanyReferralException(
            error is String && RegExp(r'^[a-z0-9_]{1,100}$').hasMatch(error)
                ? error
                : 'affiliate_registration_unavailable',
          );
        }
        if (!privateResponse ||
            result['affiliate_referral_state'] != 'held_owner_review' ||
            result['tenant_id'] is! String ||
            (result['tenant_id'] as String).isEmpty ||
            result['company_id'] is! String ||
            (result['company_id'] as String).isEmpty ||
            result['company_session_token'] is! String ||
            (result['company_session_token'] as String).isEmpty)
          throw const FormatException();
        return CompanyReferralAttempt(
          session: session,
          sessionRevision: revision,
          intentKey: key,
          intentValue: intentValue,
          result: result,
          isCurrentRegistration: isCurrent,
        );
      } on CompanyReferralException {
        rethrow;
      } catch (_) {
        throw const CompanyReferralException(
          'affiliate_registration_unavailable',
        );
      }
    });
  }

  /// Call only after the returned company session was successfully saved. A
  /// failed/late attempt retains its durable ID for exact server replay.
  Future<void> complete(CompanyReferralAttempt attempt) =>
      _serial(attempt.intentKey, () async {
        void checkOwner() {
          if (!owns(attempt)) {
            throw const CompanyReferralException('affiliate_session_changed');
          }
        }

        checkOwner();
        final index = await _index(),
            ownerHash = _digest(attempt.session.customerId);
        if (index[ownerHash] != attempt.intentValue) {
          throw const CompanyReferralException(
            'affiliate_registration_intent_locked',
          );
        }
        checkOwner();
        index.remove(ownerHash);
        await _removeOwnedIntent(
          key: attempt.intentKey,
          ownerHash: ownerHash,
          index: index,
          intentValue: attempt.intentValue,
          checkOwner: checkOwner,
        );
      });

  /// A late owner change or failed removal must retain the exact retry ID.
  /// All callers hold the shared intent lock. Restore only our own entry and
  /// verify it; never overwrite an unexpected record belonging to a later run.
  Future<void> _removeOwnedIntent({
    required String key,
    required String ownerHash,
    required Map<String, dynamic> index,
    required String intentValue,
    required void Function() checkOwner,
  }) async {
    try {
      final removed = jsonEncode(index);
      await _intents.write(key, removed);
      checkOwner();
      if (await _intents.read(key) != removed) {
        throw const CompanyReferralException(
          'affiliate_registration_storage_unavailable',
        );
      }
      checkOwner();
    } catch (error) {
      try {
        final latest = await _index();
        if (latest[ownerHash] != null && latest[ownerHash] != intentValue) {
          throw const FormatException();
        }
        latest[ownerHash] = intentValue;
        final restored = jsonEncode(latest);
        await _intents.write(key, restored);
        if (await _intents.read(key) != restored) throw const FormatException();
      } catch (_) {
        throw const CompanyReferralException(
          'affiliate_registration_storage_unavailable',
        );
      }
      if (error is CompanyReferralException) rethrow;
      throw const CompanyReferralException(
        'affiliate_registration_storage_unavailable',
      );
    }
  }

  void dispose() {
    _disposed = true;
    if (_ownsHttp) _http.close();
  }
}
