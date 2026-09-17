// Local-test-only customer entry. Issues a real Worker session for an
// already-existing local customer. Never starts OTP and never invents a token.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:fluxidi_tracking/active_local_customer_store.dart';
import 'package:fluxidi_tracking/company/local_synthetic_company_session.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:fluxidi_tracking/fluxidi_runtime_env.dart';
import 'package:fluxidi_tracking/nearby/stap3_flow_keys.dart';
import 'package:http/http.dart' as http;

const String kLocalQaCustomerSessionPath = '/local/customer/qa-session';

/// Header carrying the loopback-only QA token.
///
/// Deliberately not the platform admin header: a customer-facing surface must
/// never be able to construct that one, even behind compile-time guards, so
/// the security contract in `test/security/no_client_admin_token_test.dart`
/// stays absolute rather than gaining an exemption.
const String kLocalQaCustomerSessionHeader = 'x-fluxidi-local-qa-token';

typedef LocalQaCustomerHttpPost =
    Future<http.Response> Function(
      Uri url, {
      Map<String, String>? headers,
      Object? body,
    });

bool canUseLocalQaCustomerSession({
  String runtimeEnv = kFluxidiRuntimeEnvDefine,
  String bookingBaseUrl = kFluxidiRuntimeBookingBaseUrlOverride,
  bool qaEnabled = kFluxidiLocalQaCustomerSessionDefine,
  Uri? deepLink,
  Map<String, String>? queryParameters,
}) {
  if (!qaEnabled) return false;
  final env = runtimeEnv.trim().toLowerCase();
  if (env != 'local_test' && env != 'local') return false;
  if (!isLoopbackBookingBaseUrl(bookingBaseUrl)) return false;
  if (isProductionBookingHost(bookingBaseUrl)) return false;
  final query = <String, String>{
    ...?queryParameters,
    ...?deepLink?.queryParameters,
  };
  // Query / deep-link flags must not grant access, even on loopback.
  if (query.isNotEmpty && !qaEnabled) return false;
  return true;
}

/// Existing local demo taxi company. Never invents a second partner.
CustomerBookingCompany? localQaDemoTaxiCompany({
  String runtimeEnv = kFluxidiRuntimeEnvDefine,
  String bookingBaseUrl = kFluxidiRuntimeBookingBaseUrlOverride,
  bool qaEnabled = kFluxidiLocalQaCustomerSessionDefine,
}) {
  if (!canUseLocalQaCustomerSession(
    runtimeEnv: runtimeEnv,
    bookingBaseUrl: bookingBaseUrl,
    qaEnabled: qaEnabled,
  )) {
    return null;
  }
  const companyId = 'demo_company_p0';
  return CustomerBookingCompany(
    partnerId: kStap3LocalPartnerId,
    tenantId: companyId,
    companyId: companyId,
    companyCode: kLocalSyntheticCompanyCodes[companyId] ?? 'FLX-DEMO1',
    companyName: kLocalSyntheticCompanyNames[companyId] ?? 'Fluxidi Demo Cars',
  );
}

String maskLocalQaCustomerId(String customerId) {
  final trimmed = customerId.trim();
  if (trimmed.length <= 4) return trimmed.isEmpty ? '-' : '...$trimmed';
  return '${trimmed.substring(0, 2)}...${trimmed.substring(trimmed.length - 2)}';
}

class LocalQaCustomerSessionAccess {
  const LocalQaCustomerSessionAccess({
    required this.enabled,
    required this.ensureExistingSession,
  });

  final bool enabled;
  final Future<CustomerSession> Function({String? preferredCustomerId})
  ensureExistingSession;

  factory LocalQaCustomerSessionAccess.compiled({
    LocalQaCustomerHttpPost? httpPost,
  }) {
    return LocalQaCustomerSessionAccess(
      enabled: canUseLocalQaCustomerSession(),
      ensureExistingSession: ({String? preferredCustomerId}) async {
        final fromArg = (preferredCustomerId ?? '').trim();
        final preferred = fromArg.isNotEmpty
            ? fromArg
            : ActiveLocalCustomerStore.instance.peekCachedCustomerId();
        return ensureLocalQaCustomerSession(
          preferredCustomerId: preferred.isEmpty ? null : preferred,
          httpPost: httpPost,
        );
      },
    );
  }
}

Future<CustomerSession> ensureLocalQaCustomerSession({
  String? preferredCustomerId,
  LocalQaCustomerHttpPost? httpPost,
  String bookingBaseUrl = kFluxidiRuntimeBookingBaseUrlOverride,
  bool qaEnabled = kFluxidiLocalQaCustomerSessionDefine,
  String runtimeEnv = kFluxidiRuntimeEnvDefine,
  String adminToken = kFluxidiLocalQaAdminTokenDefine,
}) async {
  // Loopback-only by construction; see [canUseLocalQaCustomerSession].
  if (!canUseLocalQaCustomerSession(
    runtimeEnv: runtimeEnv,
    bookingBaseUrl: bookingBaseUrl,
    qaEnabled: qaEnabled,
  )) {
    throw StateError('local_qa_customer_session_refused');
  }
  final memory = CustomerSessionStore.instance.peekCachedSession();
  if (memory != null && CustomerSessionStore.instance.isValid(memory)) {
    final existingId = memory.customerId.trim();
    if (existingId.isNotEmpty) {
      ActiveLocalCustomerStore.instance.rememberActiveCustomerId(existingId);
    }
    return memory;
  }
  // OneDrive-backed Documents I/O can exceed a UI budget. Probe briefly, then
  // issue a Worker session instead of blocking customer home.
  CustomerSession? disk;
  try {
    disk = await CustomerSessionStore.instance.loadValidSession().timeout(
      const Duration(milliseconds: 400),
    );
  } catch (_) {
    disk = null;
  }
  if (disk != null) {
    final existingId = disk.customerId.trim();
    if (existingId.isNotEmpty) {
      ActiveLocalCustomerStore.instance.rememberActiveCustomerId(existingId);
    }
    return disk;
  }
  final token = adminToken.trim();
  if (token.isEmpty) {
    throw StateError('local_qa_customer_session_not_configured');
  }
  final preferred = localQaPreferredCustomerId(preferredCustomerId);
  final endpoint = Uri.parse(
    '${bookingBaseUrl.trim()}$kLocalQaCustomerSessionPath',
  );
  final post = httpPost ?? http.post;
  final res = await post(
    endpoint,
    headers: <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      kLocalQaCustomerSessionHeader: token,
    },
    body: jsonEncode(<String, dynamic>{
      if (preferred.isNotEmpty) 'customer_id': preferred,
      if (preferred.isNotEmpty) 'customerId': preferred,
    }),
  ).timeout(const Duration(seconds: 4));
  final decoded = jsonDecode(utf8.decode(res.bodyBytes));
  if (decoded is! Map) {
    throw StateError('local_qa_customer_session_invalid_response');
  }
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode < 200 || res.statusCode >= 300 || map['ok'] != true) {
    final error = (map['error'] ?? 'local_qa_customer_session_failed')
        .toString()
        .trim();
    throw StateError(error);
  }
  final sessionToken =
      (map['customer_session_token'] ?? map['customerSessionToken'] ?? '')
          .toString()
          .trim();
  final customerId = (map['customer_id'] ?? map['customerId'] ?? '')
      .toString()
      .trim();
  final expiresInSeconds =
      int.tryParse(
        (map['expires_in_seconds'] ?? map['expiresInSeconds'] ?? '').toString(),
      ) ??
      (30 * 24 * 60 * 60);
  if (sessionToken.isEmpty || customerId.isEmpty) {
    throw StateError('local_qa_customer_session_missing');
  }
  final now = DateTime.now().toUtc();
  final session = CustomerSession(
    customerSessionToken: sessionToken,
    expiresAt: now.add(Duration(seconds: expiresInSeconds)).toIso8601String(),
    customerId: customerId,
    phoneE164: '',
    defaultTenantId: null,
    defaultCompanyId: null,
    createdAt: now.toIso8601String(),
    updatedAt: now.toIso8601String(),
  );
  CustomerSessionStore.instance.rememberSession(session);
  ActiveLocalCustomerStore.instance.rememberActiveCustomerId(customerId);
  unawaited(_persistLocalQaCustomerSession(session, customerId));
  debugPrint(
    '[CUSTOMER_SESSION][LOCAL_QA] ok=true customer=${maskLocalQaCustomerId(customerId)}',
  );
  return session;
}

/// Device-local `createNewLocalCustomerId` stubs are not Worker identities.
String localQaPreferredCustomerId(String? raw) {
  final preferred = (raw ?? '').trim();
  if (preferred.isEmpty) return '';
  if (RegExp(r'^cust_[0-9a-f]+_[0-9a-f]{8}$').hasMatch(preferred)) {
    return '';
  }
  return preferred;
}

Future<void> _persistLocalQaCustomerSession(
  CustomerSession session,
  String customerId,
) async {
  try {
    await CustomerSessionStore.instance.save(session);
    await ActiveLocalCustomerStore.instance.setActiveCustomerId(customerId);
  } catch (err) {
    debugPrint('[CUSTOMER_SESSION][LOCAL_QA] persist_best_effort error=$err');
  }
}
