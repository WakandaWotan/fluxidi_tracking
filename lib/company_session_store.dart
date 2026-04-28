import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fluxidi_tracking/app_config.dart';

/// Fallback tenant id when no local company profile exists (aligned with Worker `tenant_id`).
const String kFallbackCompanyId = kTenantId;

final ValueNotifier<ActiveCompanySession?> activeCompanySessionNotifier =
    ValueNotifier<ActiveCompanySession?>(null);

final ValueNotifier<CompanyProfile?> companyProfileNotifier =
    ValueNotifier<CompanyProfile?>(null);

/// Stable company / tenant identifier for linking local MVP data — prefer [CompanyProfile.companyId].
String get resolvedCompanyId {
  final id = companyProfileNotifier.value?.companyId.trim();
  if (id != null && id.isNotEmpty) return id;
  return kFallbackCompanyId;
}

/// Local company profile (sync-ready with future backend tenant endpoints).
class CompanyProfile {
  const CompanyProfile({
    required this.companyId,
    required this.companyName,
    required this.ownerName,
    required this.email,
    required this.phone,
    required this.vatNumber,
    required this.addressLine,
    required this.postalCode,
    required this.city,
    required this.countryCode,
    required this.companyEmail,
    required this.supportEmail,
    required this.billingEmail,
    required this.bookingEmail,
    required this.notificationEmail,
    required this.createdAt,
    required this.updatedAt,
    required this.isActive,
  });

  final String companyId;
  String get tenantId => companyId;

  final String companyName;
  final String ownerName;
  final String email;
  final String phone;
  final String vatNumber;
  final String addressLine;
  final String postalCode;
  final String city;
  final String countryCode;
  final String companyEmail;
  final String supportEmail;
  final String billingEmail;
  final String bookingEmail;
  final String notificationEmail;
  final String createdAt;
  final String updatedAt;
  final bool isActive;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'companyId': companyId,
    'tenantId': companyId,
    'companyName': companyName,
    'ownerName': ownerName,
    'email': email,
    'phone': phone,
    'vatNumber': vatNumber,
    'addressLine': addressLine,
    'postalCode': postalCode,
    'city': city,
    'countryCode': countryCode,
    'companyEmail': companyEmail,
    'supportEmail': supportEmail,
    'billingEmail': billingEmail,
    'bookingEmail': bookingEmail,
    'notificationEmail': notificationEmail,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'isActive': isActive,
  };

  factory CompanyProfile.fromJson(Map<String, dynamic> json) {
    String read(String key) => (json[key] ?? '').toString().trim();
    final id = (read('companyId').isNotEmpty
        ? read('companyId')
        : read('tenantId'));
    return CompanyProfile(
      companyId: id,
      companyName: read('companyName'),
      ownerName: read('ownerName'),
      email: read('email'),
      phone: read('phone'),
      vatNumber: read('vatNumber'),
      addressLine: read('addressLine'),
      postalCode: read('postalCode'),
      city: read('city'),
      countryCode: read('countryCode'),
      companyEmail: read('companyEmail'),
      supportEmail: read('supportEmail'),
      billingEmail: read('billingEmail'),
      bookingEmail: read('bookingEmail'),
      notificationEmail: read('notificationEmail'),
      createdAt: read('createdAt'),
      updatedAt: read('updatedAt'),
      isActive: json['isActive'] is bool
          ? json['isActive'] as bool
          : read('isActive') != 'false',
    );
  }

  CompanyProfile copyWith({
    String? companyId,
    String? companyName,
    String? ownerName,
    String? email,
    String? phone,
    String? vatNumber,
    String? addressLine,
    String? postalCode,
    String? city,
    String? countryCode,
    String? companyEmail,
    String? supportEmail,
    String? billingEmail,
    String? bookingEmail,
    String? notificationEmail,
    String? createdAt,
    String? updatedAt,
    bool? isActive,
  }) {
    return CompanyProfile(
      companyId: companyId ?? this.companyId,
      companyName: companyName ?? this.companyName,
      ownerName: ownerName ?? this.ownerName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      vatNumber: vatNumber ?? this.vatNumber,
      addressLine: addressLine ?? this.addressLine,
      postalCode: postalCode ?? this.postalCode,
      city: city ?? this.city,
      countryCode: countryCode ?? this.countryCode,
      companyEmail: companyEmail ?? this.companyEmail,
      supportEmail: supportEmail ?? this.supportEmail,
      billingEmail: billingEmail ?? this.billingEmail,
      bookingEmail: bookingEmail ?? this.bookingEmail,
      notificationEmail: notificationEmail ?? this.notificationEmail,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }
}

class ActiveCompanySession {
  const ActiveCompanySession({
    required this.companyId,
    required this.role,
    required this.createdAt,
    required this.lastUsedAt,
  });

  final String companyId;

  /// Future sync: `'companyAdmin'` mirrors [AppRole.companyAdmin].
  final String role;
  final String createdAt;
  final String lastUsedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'companyId': companyId,
    'role': role,
    'createdAt': createdAt,
    'lastUsedAt': lastUsedAt,
  };

  factory ActiveCompanySession.fromJson(Map<String, dynamic> json) {
    String read(String key) => (json[key] ?? '').toString().trim();
    return ActiveCompanySession(
      companyId: read('companyId'),
      role: read('role').isNotEmpty ? read('role') : 'companyAdmin',
      createdAt: read('createdAt'),
      lastUsedAt: read('lastUsedAt'),
    );
  }

  ActiveCompanySession copyWith({
    String? companyId,
    String? role,
    String? createdAt,
    String? lastUsedAt,
  }) {
    return ActiveCompanySession(
      companyId: companyId ?? this.companyId,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }
}

/// Persists `[CompanyProfile]` + `[ActiveCompanySession]` as JSON under app documents.
class CompanySessionStore {
  CompanySessionStore._();
  static final CompanySessionStore instance = CompanySessionStore._();

  static const String _profileFileName = 'company_profile_v1.json';
  static const String _sessionFileName = 'active_company_session_v1.json';

  CompanyProfile? _profileMemory;
  ActiveCompanySession? _sessionMemory;

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}company_session');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _profileFile() async {
    final d = await _dir();
    return File('${d.path}${Platform.pathSeparator}$_profileFileName');
  }

  Future<File> _sessionFile() async {
    final d = await _dir();
    return File('${d.path}${Platform.pathSeparator}$_sessionFileName');
  }

  Future<CompanyProfile?> loadProfile() async {
    try {
      if (_profileMemory != null) return _profileMemory;
      final file = await _profileFile();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final p = CompanyProfile.fromJson(Map<String, dynamic>.from(decoded));
      if (p.companyId.isEmpty) return null;
      _profileMemory = p;
      return p;
    } catch (_) {
      return null;
    }
  }

  Future<ActiveCompanySession?> loadSession() async {
    try {
      if (_sessionMemory != null) return _sessionMemory;
      final file = await _sessionFile();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final s = ActiveCompanySession.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (s.companyId.isEmpty) return null;
      _sessionMemory = s;
      return s;
    } catch (_) {
      return null;
    }
  }

  /// Valid when profile exists, active, session matches ids.
  bool get hasValidCompanyContext =>
      companyProfileNotifier.value != null &&
      activeCompanySessionNotifier.value != null &&
      companyProfileNotifier.value!.isActive &&
      companyProfileNotifier.value!.companyId ==
          activeCompanySessionNotifier.value!.companyId;

  /// Call after tenant state load — reconciles disk + sets notifiers; does not overwrite pricing fields.
  Future<void> bootstrap() async {
    _profileMemory = null;
    _sessionMemory = null;
    CompanyProfile? p = await loadProfile();
    ActiveCompanySession? s = await loadSession();

    if (p == null || !p.isActive || p.companyId.isEmpty) {
      await clearLocalCompanyState();
      return;
    }
    companyProfileNotifier.value = p;
    if (s == null || s.companyId != p.companyId) {
      await _writeSessionForProfile(p);
      return;
    }
    activeCompanySessionNotifier.value = s;
    await _touchSessionLastUsed();
  }

  Future<void> _writeSessionForProfile(CompanyProfile p) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final prev = await loadSession();
    final session = ActiveCompanySession(
      companyId: p.companyId,
      role: 'companyAdmin',
      createdAt: prev != null && prev.companyId == p.companyId
          ? prev.createdAt
          : now,
      lastUsedAt: now,
    );
    try {
      final file = await _sessionFile();
      await file.writeAsString(jsonEncode(session.toJson()));
      _sessionMemory = session;
      activeCompanySessionNotifier.value = session;
    } catch (_) {}
  }

  Future<void> _touchSessionLastUsed() async {
    final cur = activeCompanySessionNotifier.value;
    if (cur == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final next = cur.copyWith(lastUsedAt: now);
    try {
      final file = await _sessionFile();
      await file.writeAsString(jsonEncode(next.toJson()));
      _sessionMemory = next;
      activeCompanySessionNotifier.value = next;
    } catch (_) {}
  }

  static String slugifyCompanyName(String raw) {
    var s = raw.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_');
    s = s.replaceAll(RegExp(r'[^a-z0-9_]+'), '');
    s = s.replaceAll(RegExp(r'_+'), '_');
    if (s.startsWith('_')) s = s.substring(1);
    if (s.endsWith('_')) s = s.substring(0, s.length - 1);
    if (s.length > 40) s = s.substring(0, 40);
    if (s.isEmpty) s = 'company';
    return s;
  }

  static String _randomSuffix() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = math.Random();
    final buf = StringBuffer();
    for (var i = 0; i < 6; i++) {
      buf.write(chars[r.nextInt(chars.length)]);
    }
    return buf.toString();
  }

  /// Readable unique id, stable once stored in [CompanyProfile].
  static String generateCompanyId(String companyName) {
    final slug = slugifyCompanyName(companyName);
    return 'fluxidi_${slug}_${_randomSuffix()}';
  }

  /// Persists profile + session; mirrors key fields into [businessSettingsNotifier] for existing UI.
  Future<void> saveNewProfileFromOnboarding({
    required String companyName,
    required String ownerName,
    required String email,
    required String phone,
    String vatNumber = '',
    String city = '',
    String countryCode = 'BE',
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final id = generateCompanyId(companyName);
    final em = email.trim();
    final profile = CompanyProfile(
      companyId: id,
      companyName: companyName.trim(),
      ownerName: ownerName.trim(),
      email: em,
      phone: phone.trim(),
      vatNumber: vatNumber.trim(),
      addressLine: '',
      postalCode: '',
      city: city.trim(),
      countryCode: countryCode.trim().toUpperCase().isEmpty
          ? 'BE'
          : countryCode.trim().toUpperCase(),
      companyEmail: em,
      supportEmail: em,
      billingEmail: em,
      bookingEmail: em,
      notificationEmail: em,
      createdAt: now,
      updatedAt: now,
      isActive: true,
    );
    await persistProfile(profile);
    await _writeSessionForProfile(profile);
    companyProfileNotifier.value = profile;
    applyProfileToBusinessNotifier(profile);
  }

  Future<void> persistProfile(CompanyProfile profile) async {
    try {
      final file = await _profileFile();
      await file.writeAsString(jsonEncode(profile.toJson()));
      _profileMemory = profile;
      companyProfileNotifier.value = profile;
    } catch (_) {}
  }

  /// Merge into [businessSettingsNotifier] (pricing fields preserved).
  void applyProfileToBusinessNotifier(CompanyProfile p) {
    final cur = businessSettingsNotifier.value;
    final addr = <String>[
      if (p.addressLine.trim().isNotEmpty) p.addressLine.trim(),
      if (p.postalCode.trim().isNotEmpty || p.city.trim().isNotEmpty)
        '${p.postalCode.trim()} ${p.city.trim()}'.trim(),
      if (p.countryCode.trim().isNotEmpty) p.countryCode.trim(),
    ].join('\n');
    final support = p.supportEmail.trim().isNotEmpty ? p.supportEmail : p.email;
    final book = p.bookingEmail.trim().isNotEmpty ? p.bookingEmail : p.email;
    final reply = p.notificationEmail.trim().isNotEmpty
        ? p.notificationEmail
        : support;
    updateBusinessSettings(
      cur.copyWith(
        companyName: p.companyName,
        supportEmail: support,
        supportPhone: p.phone,
        vatCompanyNumber: p.vatNumber,
        address: addr,
        bookingSender: book,
        bookingReplyTo: reply,
        whatsappNumber: p.phone,
      ),
    );
  }

  /// Update profile preserving [companyId] and [createdAt].
  Future<void> updateSavedProfile(
    CompanyProfile next, {
    required String preservedCompanyId,
    required String preservedCreatedAt,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final merged = next.copyWith(
      companyId: preservedCompanyId,
      createdAt: preservedCreatedAt,
      updatedAt: now,
      isActive: true,
    );
    await persistProfile(merged);
    await _writeSessionForProfile(merged);
    applyProfileToBusinessNotifier(merged);
  }

  Future<void> clearLocalCompanyState() async {
    try {
      final pf = await _profileFile();
      if (await pf.exists()) await pf.delete();
      final sf = await _sessionFile();
      if (await sf.exists()) await sf.delete();
    } catch (_) {}
    _profileMemory = null;
    _sessionMemory = null;
    companyProfileNotifier.value = null;
    activeCompanySessionNotifier.value = null;
  }
}

/// Prefer company email, then owner/contact email, then support email.
String primaryContactEmailFromCompany(CompanyProfile local) {
  if (local.companyEmail.trim().isNotEmpty) return local.companyEmail.trim();
  if (local.email.trim().isNotEmpty) return local.email.trim();
  return local.supportEmail.trim();
}

/// When [base] still looks like empty/template Worker fields, overlay local onboarding data.
/// Does not replace values that clearly diverge from app defaults (user or API edits).
BackendBusinessProfile mergeLocalIntoBackendPreview(
  BackendBusinessProfile base,
  CompanyProfile? local,
) {
  if (local == null) return base;
  final d = BackendBusinessProfile.defaults();
  String take(String current, String incoming, String def) {
    final c = current.trim();
    final inc = incoming.trim();
    final dt = def.trim();
    if (inc.isEmpty) return current;
    if (c.isEmpty || c == dt) return inc;
    return current;
  }

  final primaryEmail = primaryContactEmailFromCompany(local);

  return BackendBusinessProfile(
    companyName: take(base.companyName, local.companyName, d.companyName),
    legalName: take(base.legalName, local.companyName, d.legalName),
    vatNumber: take(base.vatNumber, local.vatNumber, d.vatNumber),
    companyRegistrationNumber: base.companyRegistrationNumber,
    address: take(base.address, local.addressLine, d.address),
    postcode: take(base.postcode, local.postalCode, d.postcode),
    city: take(base.city, local.city, d.city),
    country: take(base.country, local.countryCode, d.country),
    phone: take(base.phone, local.phone, d.phone),
    email: take(base.email, primaryEmail, d.email),
    website: base.website,
    bookingEmail: take(base.bookingEmail, local.bookingEmail, d.bookingEmail),
    invoiceEmail: take(base.invoiceEmail, local.billingEmail, d.invoiceEmail),
    iban: base.iban,
    paymentReferencePrefix: base.paymentReferencePrefix,
    invoiceReceiptFooterText: base.invoiceReceiptFooterText,
  );
}

// TODO(backlink): Optionally add nullable tenantId/crosswalk on [VehicleProfile]/[DriverProfile]
// and persist alongside fleet JSON when syncing to backend tenant APIs.
