import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fluxidi_tracking/active_local_customer_store.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:path_provider/path_provider.dart';

class CustomerProfile {
  const CustomerProfile({
    required this.customerId,
    required this.name,
    required this.phone,
    required this.email,
    required this.preferredPostcode,
    required this.companyName,
    required this.vatNumber,
    this.favoritePartnerIds = const <String>[],
    required this.createdAt,
    required this.updatedAt,
  });

  final String customerId;
  final String name;
  final String phone;
  final String email;
  final String preferredPostcode;
  final String companyName;
  final String vatNumber;
  final List<String> favoritePartnerIds;
  final String createdAt;
  final String updatedAt;

  bool get hasContactDetails =>
      name.trim().isNotEmpty ||
      phone.trim().isNotEmpty ||
      email.trim().isNotEmpty;

  factory CustomerProfile.fromJson(Map<String, dynamic> json) {
    String read(String key) => (json[key] ?? '').toString().trim();
    String readAny(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    List<String> readStringListAny(List<String> keys) {
      for (final key in keys) {
        final raw = json[key];
        if (raw is! List) continue;
        final seen = <String>{};
        final out = <String>[];
        for (final item in raw) {
          final value = item.toString().trim();
          if (value.isEmpty || seen.contains(value)) continue;
          seen.add(value);
          out.add(value);
        }
        return out;
      }
      return const <String>[];
    }

    return CustomerProfile(
      customerId: read('customerId'),
      name: read('name'),
      phone: readAny(const [
        'phone',
        'customerPhone',
        'customer_phone',
        'phoneE164',
        'phone_e164',
      ]),
      email: read('email').toLowerCase(),
      preferredPostcode: readAny(const [
        'preferredPostcode',
        'preferred_postcode',
        'postcode',
        'postalCode',
        'postal_code',
      ]),
      companyName: read('companyName'),
      vatNumber: read('vatNumber'),
      favoritePartnerIds: readStringListAny(const [
        'favorite_partner_ids',
        'favoritePartnerIds',
        'favourite_partner_ids',
        'favouritePartnerIds',
      ]),
      createdAt: read('createdAt'),
      updatedAt: read('updatedAt'),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'customerId': customerId,
      'name': name,
      'phone': phone,
      'email': email,
      'preferredPostcode': preferredPostcode,
      'preferred_postcode': preferredPostcode,
      'companyName': companyName,
      'vatNumber': vatNumber,
      'favorite_partner_ids': favoritePartnerIds,
      'favoritePartnerIds': favoritePartnerIds,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

class CustomerProfileStore {
  CustomerProfileStore._();

  static final CustomerProfileStore instance = CustomerProfileStore._();

  static const String _fileName = 'customer_profile_v1.json';
  static const String _deviceLocalScopeDir = 'device_local';
  static const String _legacyMigrationMarker =
      'legacy_profile_migration_v1.done';

  CustomerProfile? _cache;
  String _cacheScopeKey = '';
  bool _legacyMigrationDone = false;

  String _maskCustomerId(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= 4) return trimmed.isEmpty ? '-' : '...$trimmed';
    return '${trimmed.substring(0, 2)}...${trimmed.substring(trimmed.length - 2)}';
  }

  String _localScopeSegment(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'default';
    final sanitized = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (sanitized.isEmpty) return 'default';
    return sanitized;
  }

  void invalidateCache() {
    _cache = null;
    _cacheScopeKey = '';
  }

  Future<Directory> _stateRootDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}customer_state',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> _activeValidCustomerSessionId() async {
    final cached = CustomerSessionStore.instance.peekCachedSession();
    if (cached != null && CustomerSessionStore.instance.isValid(cached)) {
      final cachedId = cached.customerId.trim();
      if (cachedId.isNotEmpty) return cachedId;
    }
    final loaded = await CustomerSessionStore.instance.loadValidSession();
    return (loaded?.customerId ?? '').trim();
  }

  Future<String> _resolveActiveCustomerId() async {
    final sessionId = await _activeValidCustomerSessionId();
    if (sessionId.isNotEmpty) {
      await ActiveLocalCustomerStore.instance.setActiveCustomerId(sessionId);
      return sessionId;
    }
    return ActiveLocalCustomerStore.instance.getActiveCustomerId();
  }

  Future<File> _customerSessionFile({required String customerId}) async {
    final root = await _stateRootDir();
    final scopedDir = Directory(
      '${root.path}${Platform.pathSeparator}customer_session${Platform.pathSeparator}customer_${_localScopeSegment(customerId)}',
    );
    if (!await scopedDir.exists()) {
      await scopedDir.create(recursive: true);
    }
    final file = File('${scopedDir.path}${Platform.pathSeparator}$_fileName');
    debugPrint(
      '[CUSTOMER_PROFILE][PATH] scope=customer_session customer=${_maskCustomerId(customerId)}',
    );
    return file;
  }

  Future<File> _deviceLocalFile({required String customerId}) async {
    final root = await _stateRootDir();
    final scopedDir = Directory(
      '${root.path}${Platform.pathSeparator}$_deviceLocalScopeDir${Platform.pathSeparator}customer_${_localScopeSegment(customerId)}',
    );
    if (!await scopedDir.exists()) {
      await scopedDir.create(recursive: true);
    }
    final file = File('${scopedDir.path}${Platform.pathSeparator}$_fileName');
    debugPrint(
      '[CUSTOMER_PROFILE][PATH] scope=device_local customer=${_maskCustomerId(customerId)}',
    );
    return file;
  }

  Future<File> _legacyDeviceLocalMonolithFile() async {
    final root = await _stateRootDir();
    final scopedDir = Directory(
      '${root.path}${Platform.pathSeparator}$_deviceLocalScopeDir',
    );
    return File('${scopedDir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<({String scopeKey, String scopeType, String customerId, File file})>
  _resolveStorageTarget() async {
    final customerId = (await _resolveActiveCustomerId()).trim();
    if (customerId.isEmpty) {
      throw StateError('missing_active_customer_id');
    }
    final sessionId = await _activeValidCustomerSessionId();
    if (sessionId.isNotEmpty) {
      final file = await _customerSessionFile(customerId: sessionId);
      return (
        scopeKey: 'customer_session::$sessionId',
        scopeType: 'customer_session',
        customerId: sessionId,
        file: file,
      );
    }
    final file = await _deviceLocalFile(customerId: customerId);
    return (
      scopeKey: 'device_local::$customerId',
      scopeType: 'device_local',
      customerId: customerId,
      file: file,
    );
  }

  Future<CustomerProfile?> _readFromFile(File file) async {
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final profile = CustomerProfile.fromJson(
      Map<String, dynamic>.from(decoded),
    );
    if (profile.customerId.isEmpty) return null;
    return profile;
  }

  String _generateCustomerId() {
    return ActiveLocalCustomerStore.instance.generateCustomerId();
  }

  Future<String> _ensureActiveLocalCustomerId() async {
    final existing =
        (await ActiveLocalCustomerStore.instance.getActiveCustomerId()).trim();
    if (existing.isNotEmpty) return existing;
    return ActiveLocalCustomerStore.instance.createNewLocalCustomerId();
  }

  Future<void> _backupLegacyFile(File file) async {
    if (!await file.exists()) return;
    final backupPath = '${file.path}.migrated_backup';
    if (await File(backupPath).exists()) return;
    await file.rename(backupPath);
    debugPrint('[CUSTOMER_PROFILE][MIGRATE] backup=${file.path}');
  }

  Future<void> _importLegacyProfileToCustomerScope(
    CustomerProfile profile, {
    required String customerId,
  }) async {
    final normalizedId = customerId.trim();
    if (normalizedId.isEmpty) return;
    final target = await _deviceLocalFile(customerId: normalizedId);
    if (await target.exists()) return;
    final payload = profile.copyWithCustomerId(normalizedId);
    await target.writeAsString(jsonEncode(payload.toJson()));
  }

  Future<void> ensureLegacyMigration() async {
    await _migrateLegacyProfileOnceIfNeeded();
  }

  Future<void> _migrateLegacyProfileOnceIfNeeded() async {
    if (_legacyMigrationDone) return;
    _legacyMigrationDone = true;

    final root = await _stateRootDir();
    final marker = File(
      '${root.path}${Platform.pathSeparator}$_legacyMigrationMarker',
    );
    if (await marker.exists()) return;

    try {
      final legacyMonolith = await _legacyDeviceLocalMonolithFile();
      if (await legacyMonolith.exists()) {
        final profile = await _readFromFile(legacyMonolith);
        if (profile != null) {
          var customerId = profile.customerId.trim();
          if (customerId.isEmpty) {
            customerId = _generateCustomerId();
          }
          await ActiveLocalCustomerStore.instance.setActiveCustomerId(
            customerId,
          );
          await _importLegacyProfileToCustomerScope(
            profile,
            customerId: customerId,
          );
        }
        await _backupLegacyFile(legacyMonolith);
      }

      await for (final tenantEntry in root.list(followLinks: false)) {
        if (tenantEntry is! Directory) continue;
        final tenantLeaf = tenantEntry.path.split(Platform.pathSeparator).last;
        if (!tenantLeaf.startsWith('tenant_')) continue;
        await for (final companyEntry in tenantEntry.list(followLinks: false)) {
          if (companyEntry is! Directory) continue;
          final companyLeaf = companyEntry.path
              .split(Platform.pathSeparator)
              .last;
          if (!companyLeaf.startsWith('company_')) continue;
          final legacyFile = File(
            '${companyEntry.path}${Platform.pathSeparator}$_fileName',
          );
          if (!await legacyFile.exists()) continue;
          final profile = await _readFromFile(legacyFile);
          if (profile != null) {
            var customerId = profile.customerId.trim();
            if (customerId.isEmpty) {
              customerId = _generateCustomerId();
            }
            final activeId =
                (await ActiveLocalCustomerStore.instance.getActiveCustomerId())
                    .trim();
            if (activeId.isEmpty) {
              await ActiveLocalCustomerStore.instance.setActiveCustomerId(
                customerId,
              );
            }
            final importId =
                (await ActiveLocalCustomerStore.instance.getActiveCustomerId())
                    .trim();
            if (importId.isNotEmpty) {
              await _importLegacyProfileToCustomerScope(
                profile,
                customerId: importId,
              );
            }
          }
          await _backupLegacyFile(legacyFile);
        }
      }

      await marker.writeAsString('ok', flush: true);
      debugPrint('[CUSTOMER_PROFILE][MIGRATE] ok=true');
    } catch (err) {
      debugPrint('[CUSTOMER_PROFILE][MIGRATE] ok=false error=$err');
    }
  }

  Future<bool> hasResolvableLocalProfile() async {
    final sessionId = await _activeValidCustomerSessionId();
    if (sessionId.isNotEmpty) return true;
    await _migrateLegacyProfileOnceIfNeeded();
    final activeId =
        (await ActiveLocalCustomerStore.instance.getActiveCustomerId()).trim();
    if (activeId.isNotEmpty) {
      final file = await _deviceLocalFile(customerId: activeId);
      if (await file.exists()) return true;
    }
    final legacyMonolith = await _legacyDeviceLocalMonolithFile();
    if (await legacyMonolith.exists()) return true;
    final root = await _stateRootDir();
    final deviceLocalRoot = Directory(
      '${root.path}${Platform.pathSeparator}$_deviceLocalScopeDir',
    );
    if (await deviceLocalRoot.exists()) {
      await for (final entry in deviceLocalRoot.list(followLinks: false)) {
        if (entry is! Directory) continue;
        if (!entry.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('customer_')) {
          continue;
        }
        final file = File('${entry.path}${Platform.pathSeparator}$_fileName');
        if (await file.exists()) return true;
      }
    }
    return false;
  }

  Future<CustomerProfile?> load() async {
    await _migrateLegacyProfileOnceIfNeeded();
    try {
      final target = await _resolveStorageTarget();
      final scopeKey = target.scopeKey;
      if (_cache != null && _cacheScopeKey == scopeKey) return _cache;
      _cache = null;
      _cacheScopeKey = scopeKey;
      final profile = await _readFromFile(target.file);
      _cache = profile;
      return profile;
    } on StateError catch (err) {
      if ('$err'.contains('missing_active_customer_id')) {
        return null;
      }
      debugPrint('[CUSTOMER_PROFILE][LOAD_ERROR] $err');
      return null;
    } catch (err) {
      debugPrint('[CUSTOMER_PROFILE][LOAD_ERROR] $err');
      return null;
    }
  }

  Future<CustomerProfile> save({
    required String name,
    required String phone,
    required String email,
    String preferredPostcode = '',
    String companyName = '',
    String vatNumber = '',
    String? sessionCustomerId,
    Set<String>? favoritePartnerIds,
  }) async {
    await _migrateLegacyProfileOnceIfNeeded();
    final existing = await load();
    final now = DateTime.now().toIso8601String();
    final sessionId = (sessionCustomerId ?? '').trim();
    final activeLocalId = sessionId.isEmpty
        ? (await ActiveLocalCustomerStore.instance.getActiveCustomerId()).trim()
        : '';
    final resolvedFavoritePartnerIds =
        (favoritePartnerIds
                  ?.map((id) => id.trim())
                  .where((id) => id.isNotEmpty)
                  .toSet() ??
              (existing?.favoritePartnerIds.toSet() ?? <String>{}))
          ..removeWhere((id) => id.isEmpty);
    final resolvedCustomerId = sessionId.isNotEmpty
        ? sessionId
        : (activeLocalId.isNotEmpty
              ? activeLocalId
              : await _ensureActiveLocalCustomerId());
    final profile = CustomerProfile(
      customerId: resolvedCustomerId,
      name: name.trim(),
      phone: phone.trim(),
      email: email.trim().toLowerCase(),
      preferredPostcode: preferredPostcode.trim().toUpperCase(),
      companyName: companyName.trim(),
      vatNumber: vatNumber.trim(),
      favoritePartnerIds: resolvedFavoritePartnerIds.toList(growable: false),
      createdAt: (existing?.createdAt.trim().isNotEmpty ?? false)
          ? existing!.createdAt
          : now,
      updatedAt: now,
    );
    try {
      final target = await _resolveStorageTarget();
      await target.file.writeAsString(jsonEncode(profile.toJson()));
      _cache = profile;
      _cacheScopeKey = target.scopeKey;
      switch (target.scopeType) {
        case 'customer_session':
          debugPrint(
            '[CUSTOMER_PROFILE][SAVE] scope=customer_session customer=${_maskCustomerId(target.customerId)}',
          );
        case 'device_local':
          debugPrint(
            '[CUSTOMER_PROFILE][SAVE] scope=device_local customer=${_maskCustomerId(target.customerId)}',
          );
      }
    } catch (err) {
      debugPrint('[CUSTOMER_PROFILE][SAVE_ERROR] $err');
    }
    return profile;
  }

  Future<CustomerProfile> mergeBackendProfileForSession(
    Map<String, dynamic> profile, {
    required String sessionCustomerId,
    String? sessionPhoneE164,
  }) async {
    String readAny(List<String> keys) {
      for (final key in keys) {
        final value = profile[key];
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
      }
      return '';
    }

    String pickPreferBackend(String backend, String local) {
      final b = backend.trim();
      if (b.isNotEmpty) return b;
      return local.trim();
    }

    await ActiveLocalCustomerStore.instance.setActiveCustomerId(
      sessionCustomerId.trim(),
    );
    final existing = await load();
    final nowIso = DateTime.now().toIso8601String();
    final backendCustomerId = readAny(const ['customer_id', 'customerId']);
    final resolvedCustomerId = sessionCustomerId.trim().isNotEmpty
        ? sessionCustomerId.trim()
        : (backendCustomerId.isNotEmpty
              ? backendCustomerId
              : (existing?.customerId.trim().isNotEmpty ?? false)
              ? existing!.customerId.trim()
              : _generateCustomerId());

    final backendName = readAny(const ['name']);
    final backendPhone = readAny(const ['phone']);
    final backendEmail = readAny(const ['email']).toLowerCase();
    final backendPreferredPostcode = readAny(const [
      'preferred_postcode',
      'preferredPostcode',
      'postcode',
      'postalCode',
      'postal_code',
    ]).toUpperCase();
    final backendCompanyName = readAny(const ['company_name', 'companyName']);
    final backendVatNumber = readAny(const ['vat_number', 'vatNumber']);
    List<String> readStringListAny(List<String> keys) {
      for (final key in keys) {
        final value = profile[key];
        if (value is! List) continue;
        final seen = <String>{};
        final out = <String>[];
        for (final item in value) {
          final text = item.toString().trim();
          if (text.isEmpty || seen.contains(text)) continue;
          seen.add(text);
          out.add(text);
        }
        return out;
      }
      return const <String>[];
    }

    const favoritePartnerIdKeys = <String>[
      'favorite_partner_ids',
      'favoritePartnerIds',
      'favourite_partner_ids',
      'favouritePartnerIds',
    ];
    final backendFavoritePartnerIds = readStringListAny(favoritePartnerIdKeys);
    final backendFavoriteKeyPresent = favoritePartnerIdKeys.any(
      profile.containsKey,
    );
    final existingFavoritePartnerIds =
        existing?.favoritePartnerIds ?? const <String>[];
    final resolvedFavoritePartnerIds = backendFavoriteKeyPresent
        ? backendFavoritePartnerIds
        : existingFavoritePartnerIds;
    debugPrint(
      '[CUSTOMER_PROFILE][MERGE_FAVORITES] key_present=$backendFavoriteKeyPresent backend_count=${backendFavoritePartnerIds.length} existing_count=${existingFavoritePartnerIds.length} chosen_source=${backendFavoriteKeyPresent ? "backend" : "existing"}',
    );
    final backendCreatedAt = readAny(const ['created_at', 'createdAt']);
    final backendUpdatedAt = readAny(const ['updated_at', 'updatedAt']);
    final sessionPhone = (sessionPhoneE164 ?? '').trim();
    final localPhone = (existing?.phone ?? '').trim();
    final backendPhoneTrimmed = backendPhone.trim();
    final resolvedPhone = backendPhoneTrimmed.isNotEmpty
        ? backendPhoneTrimmed
        : (localPhone.isNotEmpty ? localPhone : sessionPhone);
    final preservedPhone =
        backendPhoneTrimmed.isEmpty && resolvedPhone.isNotEmpty;
    if (preservedPhone) {
      debugPrint(
        '[CUSTOMER_PROFILE][PRESERVE_PHONE] source=${localPhone.isNotEmpty ? "local" : "session"}',
      );
    }
    if (backendPhoneTrimmed.isEmpty && sessionPhone.isNotEmpty) {
      debugPrint('[CUSTOMER_PROFILE][MERGE_SESSION_PHONE] applied=true');
    }

    final merged = CustomerProfile(
      customerId: resolvedCustomerId,
      name: pickPreferBackend(backendName, existing?.name ?? ''),
      phone: resolvedPhone,
      email: pickPreferBackend(
        backendEmail,
        existing?.email ?? '',
      ).toLowerCase(),
      preferredPostcode: pickPreferBackend(
        backendPreferredPostcode,
        existing?.preferredPostcode ?? '',
      ).toUpperCase(),
      companyName: pickPreferBackend(
        backendCompanyName,
        existing?.companyName ?? '',
      ),
      vatNumber: pickPreferBackend(backendVatNumber, existing?.vatNumber ?? ''),
      favoritePartnerIds: resolvedFavoritePartnerIds,
      createdAt: (existing?.createdAt.trim().isNotEmpty ?? false)
          ? existing!.createdAt
          : (backendCreatedAt.isNotEmpty ? backendCreatedAt : nowIso),
      updatedAt: backendUpdatedAt.isNotEmpty
          ? backendUpdatedAt
          : (existing?.updatedAt.trim().isNotEmpty ?? false)
          ? existing!.updatedAt
          : nowIso,
    );

    try {
      final target = await _resolveStorageTarget();
      await target.file.writeAsString(jsonEncode(merged.toJson()));
      _cache = merged;
      _cacheScopeKey = target.scopeKey;
      debugPrint('[CUSTOMER_PROFILE][MERGE_BACKEND] ok=true');
    } catch (err) {
      debugPrint('[CUSTOMER_PROFILE][MERGE_BACKEND] ok=false error=$err');
    }
    return merged;
  }
}

extension _CustomerProfileCopy on CustomerProfile {
  CustomerProfile copyWithCustomerId(String customerId) {
    return CustomerProfile(
      customerId: customerId,
      name: name,
      phone: phone,
      email: email,
      preferredPostcode: preferredPostcode,
      companyName: companyName,
      vatNumber: vatNumber,
      favoritePartnerIds: favoritePartnerIds,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
