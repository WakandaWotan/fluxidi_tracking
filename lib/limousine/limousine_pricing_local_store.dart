// Durable overlay for limousine pricing fields the live booking worker
// currently strips, especially per-vehicle public copy. Memory is the
// process cache; disk is the app-restart boundary. Never writes taxi
// notes or VehicleProfile fields.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../app_config.dart';
import 'limousine_vehicle_public_copy.dart';

const String kLimousinePricingLocalDefaultScope = 'default';
const String kLimousinePricingLocalWorkingUpdatedAtKey = 'working_updated_at';
const String kLimousinePricingLocalPublishedUpdatedAtKey =
    'published_updated_at';
const String kLimousinePricingLocalDirName = 'limousine_state';

List<String> limousineDefaultLocalPricingScopeKeys({String? partnerId}) {
  final keys = <String>{kLimousinePricingLocalDefaultScope};
  final alias = (partnerId ?? '').trim();
  if (alias.isNotEmpty) keys.add(alias);
  try {
    final scope = adminTenantCompanyScope();
    final tenant = (scope['tenant_id'] ?? '').toString().trim();
    final company = (scope['company_id'] ?? '').toString().trim();
    if (tenant.isNotEmpty || company.isNotEmpty) {
      keys.add('$tenant:$company');
    }
    if (tenant.isNotEmpty && company.isNotEmpty) {
      keys.add('company:$tenant:$company');
    }
  } catch (_) {}
  return keys.toList(growable: false);
}

abstract class LimousinePricingLocalStore {
  Future<void> warm();

  Map<String, dynamic> peekSection(String scopeKey);

  Map<String, dynamic> peekMerged(Iterable<String> scopeKeys);

  Future<Map<String, dynamic>> readSection(String scopeKey);

  Future<void> writeSection(String scopeKey, Map<String, dynamic> section);

  void writeVehiclePublicCopy({
    required Iterable<String> scopeKeys,
    required Map<String, Map<String, String>> working,
    required Map<String, Map<String, String>> published,
    required bool updatePublished,
    int revision = 0,
  });

  Map<String, Map<String, String>> workingCopyFor(String scopeKey);

  Map<String, Map<String, String>> publishedCopyFor(String scopeKey);

  Map<String, Map<String, String>> publishedCopyForProfile(
    Map<String, dynamic> profile,
  );

  void writeOverlay({
    required Iterable<String> scopeKeys,
    required Map<String, dynamic> fields,
    int revision = 0,
  });
}

class MemoryLimousinePricingLocalStore implements LimousinePricingLocalStore {
  MemoryLimousinePricingLocalStore([
    Map<String, Map<String, dynamic>>? seed,
  ]) : _sections = seed == null
           ? <String, Map<String, dynamic>>{}
           : <String, Map<String, dynamic>>{
               for (final entry in seed.entries)
                 entry.key: Map<String, dynamic>.from(entry.value),
             };

  final Map<String, Map<String, dynamic>> _sections;

  Map<String, Map<String, dynamic>> snapshot() {
    return <String, Map<String, dynamic>>{
      for (final entry in _sections.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
  }

  @override
  Future<void> warm() async {}

  @override
  Map<String, dynamic> peekSection(String scopeKey) {
    return Map<String, dynamic>.from(
      _sections[scopeKey] ?? const <String, dynamic>{},
    );
  }

  @override
  Map<String, dynamic> peekMerged(Iterable<String> scopeKeys) {
    return _peekMerged(this, scopeKeys);
  }

  @override
  Future<Map<String, dynamic>> readSection(String scopeKey) async {
    return peekSection(scopeKey);
  }

  @override
  Future<void> writeSection(String scopeKey, Map<String, dynamic> section) async {
    _sections[scopeKey] = Map<String, dynamic>.from(section);
  }

  @override
  void writeVehiclePublicCopy({
    required Iterable<String> scopeKeys,
    required Map<String, Map<String, String>> working,
    required Map<String, Map<String, String>> published,
    required bool updatePublished,
    int revision = 0,
  }) {
    _writeVehiclePublicCopy(
      this,
      scopeKeys: scopeKeys,
      working: working,
      published: published,
      updatePublished: updatePublished,
      revision: revision,
    );
  }

  @override
  Map<String, Map<String, String>> workingCopyFor(String scopeKey) {
    return limousineVehiclePublicCopyById(
      peekSection(scopeKey)[kLimousineVehiclePublicCopyKey],
    );
  }

  @override
  Map<String, Map<String, String>> publishedCopyFor(String scopeKey) {
    return limousineVehiclePublicCopyById(
      peekSection(scopeKey)[kLimousinePublishedVehiclePublicCopyKey],
    );
  }

  @override
  Map<String, Map<String, String>> publishedCopyForProfile(
    Map<String, dynamic> profile,
  ) {
    return _publishedCopyForProfile(this, profile);
  }

  @override
  void writeOverlay({
    required Iterable<String> scopeKeys,
    required Map<String, dynamic> fields,
    int revision = 0,
  }) {
    _writeOverlay(
      this,
      scopeKeys: scopeKeys,
      fields: fields,
      revision: revision,
    );
  }
}

bool limousinePricingLocalStoreSkipsDisk() {
  return Platform.environment.containsKey('FLUTTER_TEST');
}

class FileLimousinePricingLocalStore implements LimousinePricingLocalStore {
  FileLimousinePricingLocalStore({Directory? root}) : _root = root;

  Directory? _root;
  final Map<String, Map<String, dynamic>> _sections =
      <String, Map<String, dynamic>>{};
  bool _warmed = false;

  @visibleForTesting
  Directory? get debugRoot => _root;

  bool get _diskEnabled => _root != null || !limousinePricingLocalStoreSkipsDisk();

  Future<Directory?> _resolveRoot() async {
    final existing = _root;
    if (existing != null) return existing;
    if (!_diskEnabled) return null;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}$kLimousinePricingLocalDirName',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _root = dir;
    return dir;
  }

  String _safeName(String scopeKey) {
    return scopeKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  }

  File _fileFor(Directory root, String scopeKey) {
    return File(
      '${root.path}${Platform.pathSeparator}pricing_${_safeName(scopeKey)}.json',
    );
  }

  Map<String, dynamic>? _readFileSync(File file) {
    try {
      if (!file.existsSync()) return null;
      final raw = file.readAsStringSync();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  void _writeFileSync(File file, Map<String, dynamic> section) {
    file.writeAsStringSync(jsonEncode(section), flush: true);
  }

  @override
  Future<void> warm() async {
    if (_warmed && (_root != null || !_diskEnabled)) return;
    if (!_diskEnabled) {
      _warmed = true;
      return;
    }
    try {
      final root = await _resolveRoot();
      if (root == null) {
        _warmed = true;
        return;
      }
      if (!await root.exists()) {
        await root.create(recursive: true);
      }
      for (final entity in root.listSync()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final section = _readFileSync(entity);
        if (section == null) continue;
        final name = entity.uri.pathSegments.isEmpty
            ? ''
            : entity.uri.pathSegments.last;
        final fromName = name
            .replaceFirst(RegExp(r'^pricing_'), '')
            .replaceFirst(RegExp(r'\.json$'), '');
        final key = (section['_scope_key'] ?? fromName).toString().trim();
        if (key.isEmpty) continue;
        _sections[key] = section;
      }
      _warmed = true;
    } catch (_) {
      _warmed = true;
    }
  }

  @override
  Map<String, dynamic> peekSection(String scopeKey) {
    final cached = _sections[scopeKey];
    if (cached != null) return Map<String, dynamic>.from(cached);
    final root = _root;
    if (root != null) {
      final section = _readFileSync(_fileFor(root, scopeKey));
      if (section != null) {
        _sections[scopeKey] = section;
        return Map<String, dynamic>.from(section);
      }
    }
    return <String, dynamic>{};
  }

  @override
  Map<String, dynamic> peekMerged(Iterable<String> scopeKeys) {
    return _peekMerged(this, scopeKeys);
  }

  @override
  Future<Map<String, dynamic>> readSection(String scopeKey) async {
    await warm();
    return peekSection(scopeKey);
  }

  @override
  Future<void> writeSection(String scopeKey, Map<String, dynamic> section) async {
    _sections[scopeKey] = Map<String, dynamic>.from(section);
    try {
      final root = await _resolveRoot();
      if (root == null) return;
      _writeFileSync(_fileFor(root, scopeKey), section);
    } catch (_) {}
  }

  @override
  void writeVehiclePublicCopy({
    required Iterable<String> scopeKeys,
    required Map<String, Map<String, String>> working,
    required Map<String, Map<String, String>> published,
    required bool updatePublished,
    int revision = 0,
  }) {
    _writeVehiclePublicCopy(
      this,
      scopeKeys: scopeKeys,
      working: working,
      published: published,
      updatePublished: updatePublished,
      revision: revision,
    );
    final root = _root;
    if (root == null) {
      if (!_diskEnabled) return;
      warm().then((_) {
        final resolved = _root;
        if (resolved == null) return;
        for (final key in scopeKeys) {
          final section = _sections[key];
          if (section == null) continue;
          try {
            _writeFileSync(_fileFor(resolved, key), section);
          } catch (_) {}
        }
      });
      return;
    }
    for (final key in scopeKeys) {
      final section = _sections[key];
      if (section == null) continue;
      try {
        _writeFileSync(_fileFor(root, key), section);
      } catch (_) {}
    }
  }

  @override
  Map<String, Map<String, String>> workingCopyFor(String scopeKey) {
    return limousineVehiclePublicCopyById(
      peekSection(scopeKey)[kLimousineVehiclePublicCopyKey],
    );
  }

  @override
  Map<String, Map<String, String>> publishedCopyFor(String scopeKey) {
    return limousineVehiclePublicCopyById(
      peekSection(scopeKey)[kLimousinePublishedVehiclePublicCopyKey],
    );
  }

  @override
  Map<String, Map<String, String>> publishedCopyForProfile(
    Map<String, dynamic> profile,
  ) {
    return _publishedCopyForProfile(this, profile);
  }

  @override
  void writeOverlay({
    required Iterable<String> scopeKeys,
    required Map<String, dynamic> fields,
    int revision = 0,
  }) {
    _writeOverlay(
      this,
      scopeKeys: scopeKeys,
      fields: fields,
      revision: revision,
    );
    final root = _root;
    if (root == null) {
      if (!_diskEnabled) return;
      warm().then((_) {
        final resolved = _root;
        if (resolved == null) return;
        for (final key in scopeKeys) {
          final section = _sections[key];
          if (section == null) continue;
          try {
            _writeFileSync(_fileFor(resolved, key), section);
          } catch (_) {}
        }
      });
      return;
    }
    for (final key in scopeKeys) {
      final section = _sections[key];
      if (section == null) continue;
      try {
        _writeFileSync(_fileFor(root, key), section);
      } catch (_) {}
    }
  }
}

LimousinePricingLocalStore limousinePricingLocalStore =
    FileLimousinePricingLocalStore();

void _writeVehiclePublicCopy(
  LimousinePricingLocalStore store, {
  required Iterable<String> scopeKeys,
  required Map<String, Map<String, String>> working,
  required Map<String, Map<String, String>> published,
  required bool updatePublished,
  required int revision,
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  final encodedWorking = limousineEncodeVehiclePublicCopy(working);
  final encodedPublished = limousineEncodeVehiclePublicCopy(published);
  for (final key in scopeKeys) {
    if (key.trim().isEmpty) continue;
    final next = Map<String, dynamic>.from(store.peekSection(key));
    next['_scope_key'] = key;
    next[kLimousineVehiclePublicCopyKey] = encodedWorking;
    next[kLimousinePricingLocalWorkingUpdatedAtKey] = now;
    next['source_revision'] = revision;
    if (updatePublished) {
      next[kLimousinePublishedVehiclePublicCopyKey] = encodedPublished;
      next[kLimousinePricingLocalPublishedUpdatedAtKey] = now;
    }
    unawaited(store.writeSection(key, next));
  }
}

void _writeOverlay(
  LimousinePricingLocalStore store, {
  required Iterable<String> scopeKeys,
  required Map<String, dynamic> fields,
  required int revision,
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  for (final key in scopeKeys) {
    if (key.trim().isEmpty) continue;
    final next = Map<String, dynamic>.from(store.peekSection(key));
    next.addAll(fields);
    next['_scope_key'] = key;
    try {
      final scope = adminTenantCompanyScope();
      final tenant = (scope['tenant_id'] ?? '').toString().trim();
      final company = (scope['company_id'] ?? '').toString().trim();
      if (tenant.isNotEmpty &&
          (next['tenant_id'] ?? '').toString().trim().isEmpty) {
        next['tenant_id'] = tenant;
      }
      if (company.isNotEmpty &&
          (next['company_id'] ?? '').toString().trim().isEmpty) {
        next['company_id'] = company;
      }
      if ((next['partner_id'] ?? '').toString().trim().isEmpty &&
          company.isNotEmpty) {
        next['partner_id'] = company;
      }
    } catch (_) {}
    next['source_revision'] = revision;
    next[kLimousinePricingLocalWorkingUpdatedAtKey] = now;
    if (fields.containsKey(kLimousinePublishedVehiclePublicCopyKey) ||
        fields.containsKey('published_public_title') ||
        fields.containsKey('published_limousine_offers')) {
      next[kLimousinePricingLocalPublishedUpdatedAtKey] = now;
    }
    unawaited(store.writeSection(key, next));
  }
}

bool _sectionHasOverlayContent(Map<String, dynamic> section) {
  if (limousineVehiclePublicCopyById(
        section[kLimousineVehiclePublicCopyKey],
      ).isNotEmpty ||
      limousineVehiclePublicCopyById(
        section[kLimousinePublishedVehiclePublicCopyKey],
      ).isNotEmpty) {
    return true;
  }
  bool hasLocalized(Object? raw) {
    if (raw is! Map) return false;
    return raw.values.any((value) => value.toString().trim().isNotEmpty);
  }

  bool hasPhoto(Object? raw) {
    if (raw is Map) {
      final url = (raw['photo_url'] ?? raw['photoUrl'] ?? '').toString();
      return url.startsWith('https://');
    }
    return raw.toString().startsWith('https://');
  }

  return hasLocalized(section['public_title']) ||
      hasLocalized(section['published_public_title']) ||
      hasLocalized(section['public_description']) ||
      hasLocalized(section['published_public_description']) ||
      hasPhoto(section['limousine_profile_cover']) ||
      hasPhoto(section['published_limousine_profile_cover']) ||
      hasPhoto(section['limousine_hero']) ||
      hasPhoto(section['published_limousine_hero']) ||
      hasPhoto(section['limousine_profile_logo']) ||
      hasPhoto(section['published_limousine_profile_logo']) ||
      (section['published_limousine_offers'] is List &&
          (section['published_limousine_offers'] as List).isNotEmpty);
}

String _overlayIdentity(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = (source[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

bool limousinePublishedOverlayMatchesPartner({
  required Map<String, dynamic> overlay,
  required Map<String, dynamic> partner,
  String scopeKey = '',
}) {
  final partnerId = _overlayIdentity(partner, const ['partner_id', 'partnerId']);
  final tenantId = _overlayIdentity(partner, const ['tenant_id', 'tenantId']);
  final companyId = _overlayIdentity(partner, const ['company_id', 'companyId']);
  final overlayPartner = _overlayIdentity(overlay, const [
    'partner_id',
    'partnerId',
  ]);
  final overlayTenant = _overlayIdentity(overlay, const [
    'tenant_id',
    'tenantId',
  ]);
  final overlayCompany = _overlayIdentity(overlay, const [
    'company_id',
    'companyId',
  ]);
  final key = scopeKey.trim().isNotEmpty
      ? scopeKey.trim()
      : (overlay['_scope_key'] ?? '').toString().trim();

  if (overlayPartner.isNotEmpty &&
      partnerId.isNotEmpty &&
      overlayPartner != partnerId) {
    return false;
  }
  if (overlayTenant.isNotEmpty &&
      tenantId.isNotEmpty &&
      overlayTenant != tenantId) {
    return false;
  }
  if (overlayCompany.isNotEmpty &&
      companyId.isNotEmpty &&
      overlayCompany != companyId) {
    return false;
  }

  if (key.isNotEmpty && key != kLimousinePricingLocalDefaultScope) {
    if (key.startsWith('company:')) {
      if (tenantId.isNotEmpty &&
          companyId.isNotEmpty &&
          key != 'company:$tenantId:$companyId') {
        return false;
      }
    } else if (key.contains(':')) {
      if (tenantId.isNotEmpty &&
          companyId.isNotEmpty &&
          key != '$tenantId:$companyId') {
        return false;
      }
    } else if (partnerId.isNotEmpty && key != partnerId) {
      return false;
    }
  }

  if (key == kLimousinePricingLocalDefaultScope &&
      overlayPartner.isEmpty &&
      overlayTenant.isEmpty &&
      overlayCompany.isEmpty) {
    if (tenantId.isEmpty && companyId.isEmpty) return true;
    try {
      final admin = adminTenantCompanyScope();
      final adminTenant = (admin['tenant_id'] ?? '').toString().trim();
      final adminCompany = (admin['company_id'] ?? '').toString().trim();
      if (tenantId.isNotEmpty &&
          companyId.isNotEmpty &&
          adminTenant == tenantId &&
          adminCompany == companyId) {
        return true;
      }
      if (partnerId.isNotEmpty &&
          (partnerId == adminCompany || partnerId == adminTenant)) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  return true;
}

Map<String, dynamic> limousinePeekPublishedOverlayForPartner(
  LimousinePricingLocalStore store,
  Map<String, dynamic> partner,
) {
  final partnerId = _overlayIdentity(partner, const ['partner_id', 'partnerId']);
  final tenantId = _overlayIdentity(partner, const ['tenant_id', 'tenantId']);
  final companyId = _overlayIdentity(partner, const ['company_id', 'companyId']);
  final keys = <String>[
    if (partnerId.isNotEmpty) partnerId,
    if (tenantId.isNotEmpty && companyId.isNotEmpty)
      'company:$tenantId:$companyId',
    if (tenantId.isNotEmpty || companyId.isNotEmpty) '$tenantId:$companyId',
    ...limousineDefaultLocalPricingScopeKeys(partnerId: partnerId),
  ];
  final seen = <String>{};
  for (final key in keys) {
    if (key.trim().isEmpty || !seen.add(key)) continue;
    final section = store.peekSection(key);
    if (!_sectionHasOverlayContent(section)) continue;
    if (!limousinePublishedOverlayMatchesPartner(
      overlay: section,
      partner: partner,
      scopeKey: key,
    )) {
      continue;
    }
    return section;
  }
  return <String, dynamic>{};
}

Map<String, dynamic> _peekMerged(
  LimousinePricingLocalStore store,
  Iterable<String> scopeKeys,
) {
  for (final key in scopeKeys) {
    final section = store.peekSection(key);
    if (_sectionHasOverlayContent(section)) return section;
  }
  return <String, dynamic>{};
}

Map<String, Map<String, String>> _publishedCopyForProfile(
  LimousinePricingLocalStore store,
  Map<String, dynamic> profile,
) {
  final partnerId = limousineCanonicalVehicleId(
    profile['partner_id'] ?? profile['partnerId'],
  );
  for (final key in limousineDefaultLocalPricingScopeKeys(partnerId: partnerId)) {
    final published = store.publishedCopyFor(key);
    if (published.isNotEmpty) return published;
  }
  return <String, Map<String, String>>{};
}
