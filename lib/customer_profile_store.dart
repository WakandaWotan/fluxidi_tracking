import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:fluxidi_tracking/effective_tenant_company_scope.dart';
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

  CustomerProfile? _cache;
  String _cacheScopeKey = '';

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

  ({String tenantId, String companyId})? _activeLocalScope() {
    final strict = resolveStrictTenantCompanyScope(allowDriverFallback: true);
    if (strict != null) {
      return (tenantId: strict.tenantId, companyId: strict.companyId);
    }
    final session = CustomerSessionStore.instance.peekCachedSession();
    final defaultTenant = (session?.defaultTenantId ?? '').trim();
    final defaultCompany = (session?.defaultCompanyId ?? '').trim();
    if (defaultTenant.isEmpty || defaultCompany.isEmpty) return null;
    final tenantLower = defaultTenant.toLowerCase();
    final companyLower = defaultCompany.toLowerCase();
    if (tenantLower == 'global' || companyLower == 'global') return null;
    if (tenantLower == 'fluxidi' || companyLower == 'fluxidi') return null;
    debugPrint(
      '[CUSTOMER_PROFILE][SCOPE_FALLBACK] source=customer_session_default',
    );
    return (tenantId: defaultTenant, companyId: defaultCompany);
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

  Future<File> _scopedFile({
    required String tenantId,
    required String companyId,
  }) async {
    final root = await _stateRootDir();
    final scopedDir = Directory(
      '${root.path}${Platform.pathSeparator}tenant_${_localScopeSegment(tenantId)}${Platform.pathSeparator}company_${_localScopeSegment(companyId)}',
    );
    if (!await scopedDir.exists()) {
      await scopedDir.create(recursive: true);
    }
    final file = File('${scopedDir.path}${Platform.pathSeparator}$_fileName');
    debugPrint(
      '[CUSTOMER_PROFILE][PATH] tenant=$tenantId company=$companyId path=${file.path}',
    );
    return file;
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

  Future<File> _customerSessionFile({required String customerId}) async {
    final root = await _stateRootDir();
    final scopedDir = Directory(
      '${root.path}${Platform.pathSeparator}customer_session${Platform.pathSeparator}customer_${_localScopeSegment(customerId)}',
    );
    if (!await scopedDir.exists()) {
      await scopedDir.create(recursive: true);
    }
    final file = File('${scopedDir.path}${Platform.pathSeparator}$_fileName');
    debugPrint('[CUSTOMER_PROFILE][PATH] scope=customer_session');
    return file;
  }

  Future<File> _deviceLocalFile() async {
    final root = await _stateRootDir();
    final scopedDir = Directory(
      '${root.path}${Platform.pathSeparator}$_deviceLocalScopeDir',
    );
    if (!await scopedDir.exists()) {
      await scopedDir.create(recursive: true);
    }
    return File('${scopedDir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<CustomerProfile?> _readDeviceLocalProfileFallback() async {
    try {
      return await _readFromFile(await _deviceLocalFile());
    } catch (_) {
      return null;
    }
  }

  Future<({String scopeKey, String scopeType, String customerId, File file})>
  _resolveStorageTarget() async {
    final scope = _activeLocalScope();
    if (scope != null) {
      final file = await _scopedFile(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      return (
        scopeKey: '${scope.tenantId.trim()}::${scope.companyId.trim()}',
        scopeType: 'tenant_company',
        customerId: '',
        file: file,
      );
    }
    final customerId = await _activeValidCustomerSessionId();
    if (customerId.isNotEmpty) {
      debugPrint('[CUSTOMER_PROFILE][SCOPE_FALLBACK] source=customer_session');
      final file = await _customerSessionFile(customerId: customerId);
      return (
        scopeKey: 'customer_session::$customerId',
        scopeType: 'customer_session',
        customerId: customerId,
        file: file,
      );
    }
    debugPrint('[CUSTOMER_PROFILE][SCOPE_FALLBACK] source=device_local');
    final file = await _deviceLocalFile();
    return (
      scopeKey: 'device_local',
      scopeType: 'device_local',
      customerId: '',
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
    final random = math.Random.secure();
    final partA = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final partB = random.nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
    return 'cust_${partA}_$partB';
  }

  Future<CustomerProfile?> load() async {
    final target = await _resolveStorageTarget();
    final scopeKey = target.scopeKey;
    if (_cache != null && _cacheScopeKey == scopeKey) return _cache;
    _cache = null;
    _cacheScopeKey = scopeKey;
    try {
      var profile = await _readFromFile(target.file);
      if (profile == null && target.scopeType != 'device_local') {
        profile = await _readDeviceLocalProfileFallback();
        if (profile != null) {
          debugPrint('[CUSTOMER_PROFILE][LOAD] scope=fallback_device_local');
        }
      }
      _cache = profile;
      return profile;
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
    final existing = await load();
    final now = DateTime.now().toIso8601String();
    final sessionId = (sessionCustomerId ?? '').trim();
    final existingId = existing?.customerId.trim() ?? '';
    final resolvedFavoritePartnerIds =
        (favoritePartnerIds
                  ?.map((id) => id.trim())
                  .where((id) => id.isNotEmpty)
                  .toSet() ??
              (existing?.favoritePartnerIds.toSet() ?? <String>{}))
          ..removeWhere((id) => id.isEmpty);
    final profile = CustomerProfile(
      customerId: sessionId.isNotEmpty
          ? sessionId
          : (existingId.isNotEmpty ? existingId : _generateCustomerId()),
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
          debugPrint('[CUSTOMER_PROFILE][SAVE] scope=device_local');
        case 'tenant_company':
          debugPrint('[CUSTOMER_PROFILE][SAVE] scope=tenant_company');
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
