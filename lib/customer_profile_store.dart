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
    this.invoiceEmail = '',
    this.billingStreet = '',
    this.billingPostalCode = '',
    this.billingCity = '',
    this.billingCountry = '',
    this.peppolEndpointId = '',
    this.peppolScheme = '',
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
  // Optional business billing identity (provider-neutral). All default to ''
  // and never affect existing behavior when blank.
  final String invoiceEmail;
  final String billingStreet;
  final String billingPostalCode;
  final String billingCity;
  final String billingCountry;
  final String peppolEndpointId;
  final String peppolScheme;
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

    final billingAddress = json['billing_address'] is Map
        ? Map<String, dynamic>.from(json['billing_address'] as Map)
        : const <String, dynamic>{};
    String readNestedBilling(String key) {
      final value = billingAddress[key];
      if (value == null) return '';
      final text = value.toString().trim();
      return text.toLowerCase() == 'null' ? '' : text;
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
      invoiceEmail: readAny(const [
        'invoiceEmail',
        'invoice_email',
      ]).toLowerCase(),
      billingStreet:
          readAny(const ['billingStreet', 'billing_street']).isNotEmpty
          ? readAny(const ['billingStreet', 'billing_street'])
          : readNestedBilling('street'),
      billingPostalCode:
          readAny(const ['billingPostalCode', 'billing_postal_code']).isNotEmpty
          ? readAny(const ['billingPostalCode', 'billing_postal_code'])
          : readNestedBilling('postal_code'),
      billingCity: readAny(const ['billingCity', 'billing_city']).isNotEmpty
          ? readAny(const ['billingCity', 'billing_city'])
          : readNestedBilling('city'),
      billingCountry:
          readAny(const ['billingCountry', 'billing_country']).isNotEmpty
          ? readAny(const ['billingCountry', 'billing_country'])
          : readNestedBilling('country'),
      peppolEndpointId: readAny(const [
        'peppolEndpointId',
        'peppol_endpoint_id',
      ]).isNotEmpty
          ? readAny(const ['peppolEndpointId', 'peppol_endpoint_id'])
          : (() {
              final peppol = json['peppol'] is Map
                  ? Map<String, dynamic>.from(json['peppol'] as Map)
                  : const <String, dynamic>{};
              for (final key in const [
                'endpoint_id',
                'endpointId',
                'participant_id',
                'participantId',
              ]) {
                final value = peppol[key];
                if (value == null) continue;
                final text = value.toString().trim();
                if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
              }
              return '';
            })(),
      peppolScheme: readAny(const ['peppolScheme', 'peppol_scheme']).isNotEmpty
          ? readAny(const ['peppolScheme', 'peppol_scheme'])
          : (() {
              final peppol = json['peppol'] is Map
                  ? Map<String, dynamic>.from(json['peppol'] as Map)
                  : const <String, dynamic>{};
              final value = peppol['scheme'];
              if (value == null) return '';
              final text = value.toString().trim();
              return text.toLowerCase() == 'null' ? '' : text;
            })(),
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
      'invoiceEmail': invoiceEmail,
      'invoice_email': invoiceEmail,
      'billingStreet': billingStreet,
      'billing_street': billingStreet,
      'billingPostalCode': billingPostalCode,
      'billing_postal_code': billingPostalCode,
      'billingCity': billingCity,
      'billing_city': billingCity,
      'billingCountry': billingCountry,
      'billing_country': billingCountry,
      'peppolEndpointId': peppolEndpointId,
      'peppol_endpoint_id': peppolEndpointId,
      'peppolScheme': peppolScheme,
      'peppol_scheme': peppolScheme,
      'billing_address': <String, dynamic>{
        'street': billingStreet,
        'postal_code': billingPostalCode,
        'city': billingCity,
        'country': billingCountry,
      },
      'favorite_partner_ids': favoritePartnerIds,
      'favoritePartnerIds': favoritePartnerIds,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

/// How a customer profile POST should treat empty values.
///
/// Backend semantics (unchanged):
/// - omitted key → preserve server value
/// - present empty string → intentional clear
/// - present normalized value → replace
///
/// Never infer “clear” from an empty local default on bootstrap.
enum CustomerProfileSyncIntent {
  /// Best-effort / onboarding / background: only non-empty confirmed fields.
  /// Never includes empty billing/Peppol keys (cannot wipe server billing).
  bootstrapMerge,

  /// User tapped save on “Mijn gegevens”: full supported schema.
  /// Empty string clears the corresponding server field.
  explicitProfileSave,

  /// Favorites (or similarly narrow) update: never sends billing/Peppol keys.
  favoritesOnly,
}

/// Builds the profile API POST body for [intent].
///
/// Pass the result through [sanitizePublicCustomerProfilePayload] before send.
Map<String, dynamic> buildPublicCustomerProfilePayload({
  required CustomerProfile profile,
  required CustomerProfileSyncIntent intent,
}) {
  void putIfNonEmpty(Map<String, dynamic> out, String key, String value) {
    final text = value.trim();
    if (text.isEmpty) return;
    out[key] = text;
  }

  switch (intent) {
    case CustomerProfileSyncIntent.favoritesOnly:
      final out = <String, dynamic>{
        'favorite_partner_ids': profile.favoritePartnerIds,
        'favoritePartnerIds': profile.favoritePartnerIds,
      };
      // Core contact may be sent when non-empty so the worker merge still has
      // identity context; billing/Peppol keys are never included.
      putIfNonEmpty(out, 'name', profile.name);
      putIfNonEmpty(out, 'phone', profile.phone);
      putIfNonEmpty(out, 'email', profile.email);
      putIfNonEmpty(out, 'preferred_postcode', profile.preferredPostcode);
      putIfNonEmpty(out, 'company_name', profile.companyName);
      putIfNonEmpty(out, 'vat_number', profile.vatNumber);
      return out;

    case CustomerProfileSyncIntent.bootstrapMerge:
      final out = <String, dynamic>{};
      putIfNonEmpty(out, 'name', profile.name);
      putIfNonEmpty(out, 'phone', profile.phone);
      putIfNonEmpty(out, 'email', profile.email);
      putIfNonEmpty(out, 'preferred_postcode', profile.preferredPostcode);
      putIfNonEmpty(out, 'company_name', profile.companyName);
      putIfNonEmpty(out, 'vat_number', profile.vatNumber);
      putIfNonEmpty(out, 'invoice_email', profile.invoiceEmail);
      putIfNonEmpty(out, 'billing_street', profile.billingStreet);
      putIfNonEmpty(out, 'billing_postal_code', profile.billingPostalCode);
      putIfNonEmpty(out, 'billing_city', profile.billingCity);
      putIfNonEmpty(out, 'billing_country', profile.billingCountry);
      putIfNonEmpty(out, 'peppol_endpoint_id', profile.peppolEndpointId);
      putIfNonEmpty(out, 'peppol_scheme', profile.peppolScheme);
      if (profile.favoritePartnerIds.isNotEmpty) {
        out['favorite_partner_ids'] = profile.favoritePartnerIds;
        out['favoritePartnerIds'] = profile.favoritePartnerIds;
      }
      final hasBilling = profile.billingStreet.trim().isNotEmpty ||
          profile.billingPostalCode.trim().isNotEmpty ||
          profile.billingCity.trim().isNotEmpty ||
          profile.billingCountry.trim().isNotEmpty;
      if (hasBilling) {
        out['billing_address'] = <String, dynamic>{
          if (profile.billingStreet.trim().isNotEmpty)
            'street': profile.billingStreet.trim(),
          if (profile.billingPostalCode.trim().isNotEmpty)
            'postal_code': profile.billingPostalCode.trim(),
          if (profile.billingCity.trim().isNotEmpty)
            'city': profile.billingCity.trim(),
          if (profile.billingCountry.trim().isNotEmpty)
            'country': profile.billingCountry.trim(),
        };
      }
      final hasPeppol = profile.peppolEndpointId.trim().isNotEmpty ||
          profile.peppolScheme.trim().isNotEmpty;
      if (hasPeppol) {
        out['peppol'] = <String, dynamic>{
          if (profile.peppolEndpointId.trim().isNotEmpty)
            'endpoint_id': profile.peppolEndpointId.trim(),
          if (profile.peppolScheme.trim().isNotEmpty)
            'scheme': profile.peppolScheme.trim(),
        };
      }
      return out;

    case CustomerProfileSyncIntent.explicitProfileSave:
      // Full schema: empty string means intentional clear on the worker.
      return <String, dynamic>{
        'name': profile.name.trim(),
        'phone': profile.phone.trim(),
        'email': profile.email.trim().toLowerCase(),
        'preferred_postcode': profile.preferredPostcode.trim(),
        'company_name': profile.companyName.trim(),
        'vat_number': profile.vatNumber.trim(),
        'invoice_email': profile.invoiceEmail.trim().toLowerCase(),
        'billing_street': profile.billingStreet.trim(),
        'billing_postal_code': profile.billingPostalCode.trim(),
        'billing_city': profile.billingCity.trim(),
        'billing_country': profile.billingCountry.trim(),
        'billing_address': <String, dynamic>{
          'street': profile.billingStreet.trim(),
          'postal_code': profile.billingPostalCode.trim(),
          'city': profile.billingCity.trim(),
          'country': profile.billingCountry.trim(),
        },
        'peppol_endpoint_id': profile.peppolEndpointId.trim(),
        'peppol_scheme': profile.peppolScheme.trim(),
        'peppol': <String, dynamic>{
          'endpoint_id': profile.peppolEndpointId.trim(),
          'scheme': profile.peppolScheme.trim(),
        },
        'favorite_partner_ids': profile.favoritePartnerIds,
        'favoritePartnerIds': profile.favoritePartnerIds,
      };
  }
}

/// Booking-facing billing fields hydrated from a synchronized [CustomerProfile].
/// Mirrors calculator/airport `billing_customer` + top-level invoice email keys
/// without triggering Billit/Peppol submission.
Map<String, dynamic> bookingBillingFieldsFromCustomerProfile(
  CustomerProfile profile,
) {
  final invoiceEmail = profile.invoiceEmail.trim().toLowerCase();
  final legalName = profile.companyName.trim();
  final vat = profile.vatNumber.trim();
  final street = profile.billingStreet.trim();
  final postal = profile.billingPostalCode.trim();
  final city = profile.billingCity.trim();
  final country = profile.billingCountry.trim().toUpperCase();
  final peppolEndpoint = profile.peppolEndpointId.trim();
  final peppolScheme = profile.peppolScheme.trim();
  final hasBillingCustomer = legalName.isNotEmpty ||
      vat.isNotEmpty ||
      street.isNotEmpty ||
      postal.isNotEmpty ||
      city.isNotEmpty ||
      country.isNotEmpty ||
      peppolEndpoint.isNotEmpty ||
      peppolScheme.isNotEmpty;
  return <String, dynamic>{
    if (invoiceEmail.isNotEmpty) 'invoice_email': invoiceEmail,
    if (invoiceEmail.isNotEmpty) 'invoiceEmail': invoiceEmail,
    if (hasBillingCustomer)
      'billing_customer': <String, dynamic>{
        'customer_type': 'business',
        if (legalName.isNotEmpty) 'legal_name': legalName,
        if (legalName.isNotEmpty) 'display_name': legalName,
        if (vat.isNotEmpty) 'vat_number': vat,
        'billing_address': <String, dynamic>{
          if (street.isNotEmpty) 'street': street,
          if (postal.isNotEmpty) 'postal_code': postal,
          if (city.isNotEmpty) 'city': city,
          if (country.isNotEmpty) 'country': country,
        },
        'peppol': <String, dynamic>{
          if (peppolEndpoint.isNotEmpty) 'endpoint_id': peppolEndpoint,
          if (peppolScheme.isNotEmpty) 'scheme': peppolScheme,
        },
      },
  };
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
    String? invoiceEmail,
    String? billingStreet,
    String? billingPostalCode,
    String? billingCity,
    String? billingCountry,
    String? peppolEndpointId,
    String? peppolScheme,
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
    // When a new optional billing field is not provided by the caller, keep the
    // existing stored value instead of blanking it.
    String resolveOptional(String? incoming, String existingValue) =>
        incoming == null ? existingValue : incoming.trim();
    final profile = CustomerProfile(
      customerId: resolvedCustomerId,
      name: name.trim(),
      phone: phone.trim(),
      email: email.trim().toLowerCase(),
      preferredPostcode: preferredPostcode.trim().toUpperCase(),
      companyName: companyName.trim(),
      vatNumber: vatNumber.trim(),
      invoiceEmail: resolveOptional(
        invoiceEmail,
        existing?.invoiceEmail ?? '',
      ).toLowerCase(),
      billingStreet: resolveOptional(
        billingStreet,
        existing?.billingStreet ?? '',
      ),
      billingPostalCode: resolveOptional(
        billingPostalCode,
        existing?.billingPostalCode ?? '',
      ),
      billingCity: resolveOptional(billingCity, existing?.billingCity ?? ''),
      billingCountry: resolveOptional(
        billingCountry,
        existing?.billingCountry ?? '',
      ).toUpperCase(),
      peppolEndpointId: resolveOptional(
        peppolEndpointId,
        existing?.peppolEndpointId ?? '',
      ),
      peppolScheme: resolveOptional(peppolScheme, existing?.peppolScheme ?? ''),
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

    final backendUpdatedAtEarly = readAny(const ['updated_at', 'updatedAt']);
    // Prefer a non-empty local draft when it is strictly newer than the server
    // stamp (unsaved edits after a prior pull). Empty backend never wipes local.
    String pickPreferBackend(String backend, String local) {
      final b = backend.trim();
      final l = local.trim();
      if (b.isEmpty) return l;
      if (l.isEmpty) return b;
      final localTs = DateTime.tryParse(existing?.updatedAt ?? '');
      final backendTs = DateTime.tryParse(backendUpdatedAtEarly);
      if (localTs != null &&
          backendTs != null &&
          localTs.isAfter(backendTs)) {
        return l;
      }
      return b;
    }

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
    final backendBillingAddress = profile['billing_address'] is Map
        ? Map<String, dynamic>.from(profile['billing_address'] as Map)
        : const <String, dynamic>{};
    String readNestedBackendBilling(String key) {
      final value = backendBillingAddress[key];
      if (value == null) return '';
      final text = value.toString().trim();
      return text.toLowerCase() == 'null' ? '' : text;
    }

    final backendInvoiceEmail = readAny(const [
      'invoice_email',
      'invoiceEmail',
    ]).toLowerCase();
    final backendBillingStreet =
        readAny(const ['billing_street', 'billingStreet']).isNotEmpty
        ? readAny(const ['billing_street', 'billingStreet'])
        : readNestedBackendBilling('street');
    final backendBillingPostalCode =
        readAny(const ['billing_postal_code', 'billingPostalCode']).isNotEmpty
        ? readAny(const ['billing_postal_code', 'billingPostalCode'])
        : readNestedBackendBilling('postal_code');
    final backendBillingCity =
        readAny(const ['billing_city', 'billingCity']).isNotEmpty
        ? readAny(const ['billing_city', 'billingCity'])
        : readNestedBackendBilling('city');
    final backendBillingCountry =
        readAny(const ['billing_country', 'billingCountry']).isNotEmpty
        ? readAny(const ['billing_country', 'billingCountry'])
        : readNestedBackendBilling('country');
    final backendPeppolEndpointId = readAny(const [
      'peppol_endpoint_id',
      'peppolEndpointId',
    ]).isNotEmpty
        ? readAny(const ['peppol_endpoint_id', 'peppolEndpointId'])
        : (() {
            final peppol = profile['peppol'] is Map
                ? Map<String, dynamic>.from(profile['peppol'] as Map)
                : const <String, dynamic>{};
            for (final key in const [
              'endpoint_id',
              'endpointId',
              'participant_id',
              'participantId',
            ]) {
              final value = peppol[key];
              if (value == null) continue;
              final text = value.toString().trim();
              if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
            }
            return '';
          })();
    final backendPeppolScheme = readAny(const [
      'peppol_scheme',
      'peppolScheme',
    ]).isNotEmpty
        ? readAny(const ['peppol_scheme', 'peppolScheme'])
        : (() {
            final peppol = profile['peppol'] is Map
                ? Map<String, dynamic>.from(profile['peppol'] as Map)
                : const <String, dynamic>{};
            final value = peppol['scheme'];
            if (value == null) return '';
            final text = value.toString().trim();
            return text.toLowerCase() == 'null' ? '' : text;
          })();
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
      invoiceEmail: pickPreferBackend(
        backendInvoiceEmail,
        existing?.invoiceEmail ?? '',
      ).toLowerCase(),
      billingStreet: pickPreferBackend(
        backendBillingStreet,
        existing?.billingStreet ?? '',
      ),
      billingPostalCode: pickPreferBackend(
        backendBillingPostalCode,
        existing?.billingPostalCode ?? '',
      ),
      billingCity: pickPreferBackend(
        backendBillingCity,
        existing?.billingCity ?? '',
      ),
      billingCountry: pickPreferBackend(
        backendBillingCountry,
        existing?.billingCountry ?? '',
      ).toUpperCase(),
      peppolEndpointId: pickPreferBackend(
        backendPeppolEndpointId,
        existing?.peppolEndpointId ?? '',
      ),
      peppolScheme: pickPreferBackend(
        backendPeppolScheme,
        existing?.peppolScheme ?? '',
      ),
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
      invoiceEmail: invoiceEmail,
      billingStreet: billingStreet,
      billingPostalCode: billingPostalCode,
      billingCity: billingCity,
      billingCountry: billingCountry,
      peppolEndpointId: peppolEndpointId,
      peppolScheme: peppolScheme,
      favoritePartnerIds: favoritePartnerIds,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
