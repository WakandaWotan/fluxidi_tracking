import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

String normalizeCustomerSessionPhoneE164(String raw) {
  final input = raw.trim();
  if (input.isEmpty) return '';
  var compact = input.replaceAll(RegExp(r'[\s\-\(\)]'), '');
  if (compact.startsWith('00') && compact.length > 2) {
    compact = '+${compact.substring(2)}';
  }
  if (compact.startsWith('04') && RegExp(r'^04\d{8}$').hasMatch(compact)) {
    return '+32${compact.substring(1)}';
  }
  if (compact.startsWith('+3204') &&
      RegExp(r'^\+3204\d{8}$').hasMatch(compact)) {
    return '+32${compact.substring(4)}';
  }
  if (compact.startsWith('+')) {
    final digits = compact.substring(1).replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? '' : '+$digits';
  }
  return compact;
}

class CustomerSession {
  const CustomerSession({
    required this.customerSessionToken,
    required this.expiresAt,
    required this.customerId,
    required this.phoneE164,
    this.defaultTenantId,
    this.defaultCompanyId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String customerSessionToken;
  final String expiresAt;
  final String customerId;
  final String phoneE164;
  final String? defaultTenantId;
  final String? defaultCompanyId;
  final String createdAt;
  final String updatedAt;

  factory CustomerSession.fromJson(Map<String, dynamic> json) {
    String read(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        final text = (value ?? '').toString().trim();
        if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
      }
      return '';
    }

    final defaultTenant = read(const ['defaultTenantId', 'default_tenant_id']);
    final defaultCompany = read(const [
      'defaultCompanyId',
      'default_company_id',
    ]);

    final rawPhone = read(const ['phoneE164', 'phone_e164']);
    final normalizedPhone = normalizeCustomerSessionPhoneE164(rawPhone);
    return CustomerSession(
      customerSessionToken: read(const [
        'customerSessionToken',
        'customer_session_token',
      ]),
      expiresAt: read(const ['expiresAt', 'expires_at']),
      customerId: read(const ['customerId', 'customer_id']),
      phoneE164: normalizedPhone,
      defaultTenantId: defaultTenant.isEmpty ? null : defaultTenant,
      defaultCompanyId: defaultCompany.isEmpty ? null : defaultCompany,
      createdAt: read(const ['createdAt', 'created_at']),
      updatedAt: read(const ['updatedAt', 'updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'customerSessionToken': customerSessionToken,
      'customer_session_token': customerSessionToken,
      'expiresAt': expiresAt,
      'expires_at': expiresAt,
      'customerId': customerId,
      'customer_id': customerId,
      'phoneE164': phoneE164,
      'phone_e164': phoneE164,
      if ((defaultTenantId ?? '').trim().isNotEmpty)
        'defaultTenantId': defaultTenantId,
      if ((defaultTenantId ?? '').trim().isNotEmpty)
        'default_tenant_id': defaultTenantId,
      if ((defaultCompanyId ?? '').trim().isNotEmpty)
        'defaultCompanyId': defaultCompanyId,
      if ((defaultCompanyId ?? '').trim().isNotEmpty)
        'default_company_id': defaultCompanyId,
      'createdAt': createdAt,
      'created_at': createdAt,
      'updatedAt': updatedAt,
      'updated_at': updatedAt,
    };
  }
}

class CustomerSessionStore {
  CustomerSessionStore._();

  static final CustomerSessionStore instance = CustomerSessionStore._();

  static const String _stateDirName = 'customer_state';
  static const String _fileName = 'global_customer_session_v1.json';

  CustomerSession? _cache;

  Future<File> _file() async {
    final base = await getApplicationDocumentsDirectory();
    final root = Directory(
      '${base.path}${Platform.pathSeparator}$_stateDirName',
    );
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return File('${root.path}${Platform.pathSeparator}$_fileName');
  }

  Future<CustomerSession?> load() async {
    if (_cache != null) return _cache;
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final session = CustomerSession.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (session.customerSessionToken.trim().isEmpty) return null;
      final rawPhone = ((decoded['phoneE164'] ?? decoded['phone_e164']) ?? '')
          .toString()
          .trim();
      final normalizedPhone = normalizeCustomerSessionPhoneE164(rawPhone);
      final phoneChanged = rawPhone != normalizedPhone;
      debugPrint('[CUSTOMER_SESSION][PHONE_NORMALIZED] changed=$phoneChanged');
      if (phoneChanged) {
        final healed = CustomerSession(
          customerSessionToken: session.customerSessionToken,
          expiresAt: session.expiresAt,
          customerId: session.customerId,
          phoneE164: normalizedPhone,
          defaultTenantId: session.defaultTenantId,
          defaultCompanyId: session.defaultCompanyId,
          createdAt: session.createdAt,
          updatedAt: session.updatedAt,
        );
        await file.writeAsString(jsonEncode(healed.toJson()), flush: true);
        _cache = healed;
        return healed;
      }
      _cache = session;
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(CustomerSession session) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final normalizedPhone = normalizeCustomerSessionPhoneE164(
      session.phoneE164,
    );
    final phoneChanged = session.phoneE164.trim() != normalizedPhone;
    debugPrint('[CUSTOMER_SESSION][PHONE_NORMALIZED] changed=$phoneChanged');
    final normalized = CustomerSession(
      customerSessionToken: session.customerSessionToken.trim(),
      expiresAt: session.expiresAt.trim(),
      customerId: session.customerId.trim(),
      phoneE164: normalizedPhone,
      defaultTenantId: (session.defaultTenantId ?? '').trim().isEmpty
          ? null
          : session.defaultTenantId!.trim(),
      defaultCompanyId: (session.defaultCompanyId ?? '').trim().isEmpty
          ? null
          : session.defaultCompanyId!.trim(),
      createdAt: session.createdAt.trim().isEmpty ? nowIso : session.createdAt,
      updatedAt: nowIso,
    );
    final file = await _file();
    await file.writeAsString(jsonEncode(normalized.toJson()), flush: true);
    _cache = normalized;
  }

  Future<void> clear() async {
    _cache = null;
    try {
      final file = await _file();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  bool isValid(CustomerSession session) {
    if (session.customerSessionToken.trim().isEmpty) return false;
    if (session.customerId.trim().isEmpty) return false;
    final expiresAt = DateTime.tryParse(session.expiresAt.trim());
    if (expiresAt == null) return false;
    return DateTime.now().toUtc().isBefore(expiresAt.toUtc());
  }

  Future<CustomerSession?> loadValidSession() async {
    final loaded = await load();
    final valid = loaded != null && isValid(loaded);
    debugPrint('[CUSTOMER_SESSION][LOAD_VALID] valid=$valid');
    return valid ? loaded : null;
  }
}
