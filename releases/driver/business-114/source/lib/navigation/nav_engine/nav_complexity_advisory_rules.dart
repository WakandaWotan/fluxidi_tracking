import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'nav_complexity_learning_uploader.dart';

/// NAV-AI-5A: off by default — fetch advisory rules only for manual staging:
/// `--dart-define=NAV_COMPLEXITY_FETCH_ADVISORY_RULES=true`
const bool kNavComplexityFetchAdvisoryRules = bool.fromEnvironment(
  'NAV_COMPLEXITY_FETCH_ADVISORY_RULES',
  defaultValue: false,
);

const Duration kNavComplexityAdvisoryRulesTimeout = Duration(milliseconds: 1500);

const String _diagTag = 'NAV_AI_5_RULES';
const String _rulesPath = '/admin/nav-complexity-rules/advisory';

const Set<String> _forbiddenRuleKeys = {
  'latitude',
  'longitude',
  'lat',
  'lng',
  'lon',
  'address',
  'bookingid',
  'booking_id',
  'customerid',
  'customer_id',
  'driverid',
  'driver_id',
  'phone',
  'email',
  'name',
  'sessionhash',
  'session_hash',
};

String _safeReason(String value, {int maxLen = 48}) {
  final text = value.trim();
  if (text.isEmpty) return 'na';
  return text.length > maxLen ? text.substring(0, maxLen) : text;
}

void _logRules({
  required String result,
  required String reason,
  int count = 0,
}) {
  assert(() {
    debugPrint(
      '[$_diagTag] result=${_safeReason(result, maxLen: 16)} '
      'count=$count reason=${_safeReason(reason)}',
    );
    return true;
  }());
}

Uri _rulesUri(String baseUrl) {
  final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  return Uri.parse(trimmed).replace(path: _rulesPath);
}

bool _containsForbiddenKeys(Map<String, dynamic> payload) {
  for (final key in payload.keys) {
    final normalized = key.toLowerCase();
    for (final forbidden in _forbiddenRuleKeys) {
      if (normalized == forbidden ||
          normalized.endsWith('_$forbidden') ||
          normalized.startsWith('${forbidden}_') ||
          normalized.contains('_${forbidden}_')) {
        return true;
      }
    }
  }
  return false;
}

/// Anonymous advisory navigation complexity rule from Learning Worker.
class NavComplexityAdvisoryRule {
  final String id;
  final String scope;
  final String reasonCode;
  final String recommendation;
  final double confidence;
  final int minSamples;
  final int sampleCount;
  final bool enabledForRuntime;
  final String? speedBucket;
  final String? snapDistBucket;
  final String? confidenceBucket;
  final String? maneuverType;

  const NavComplexityAdvisoryRule({
    required this.id,
    required this.scope,
    required this.reasonCode,
    required this.recommendation,
    required this.confidence,
    required this.minSamples,
    required this.sampleCount,
    required this.enabledForRuntime,
    this.speedBucket,
    this.snapDistBucket,
    this.confidenceBucket,
    this.maneuverType,
  });

  factory NavComplexityAdvisoryRule.fromJson(Map<String, dynamic> json) {
    return NavComplexityAdvisoryRule(
      id: json['id']?.toString() ?? '',
      scope: json['scope']?.toString() ?? 'global',
      reasonCode: json['reasonCode']?.toString() ?? '',
      recommendation: json['recommendation']?.toString() ?? '',
      confidence: (json['confidence'] is num)
          ? (json['confidence'] as num).toDouble()
          : 0,
      minSamples: json['minSamples'] is int
          ? json['minSamples'] as int
          : int.tryParse('${json['minSamples']}') ?? 0,
      sampleCount: json['sampleCount'] is int
          ? json['sampleCount'] as int
          : int.tryParse('${json['sampleCount']}') ?? 0,
      enabledForRuntime: json['enabledForRuntime'] == true,
      speedBucket: json['speedBucket']?.toString(),
      snapDistBucket: json['snapDistBucket']?.toString(),
      confidenceBucket: json['confidenceBucket']?.toString(),
      maneuverType: json['maneuverType']?.toString(),
    );
  }

  Map<String, dynamic> toDiagnosticsJson() => <String, dynamic>{
    'id': id,
    'scope': scope,
    'reasonCode': reasonCode,
    'recommendation': recommendation,
    'confidence': confidence,
    'minSamples': minSamples,
    'sampleCount': sampleCount,
    'enabledForRuntime': enabledForRuntime,
    if (speedBucket != null) 'speedBucket': speedBucket,
    if (snapDistBucket != null) 'snapDistBucket': snapDistBucket,
    if (confidenceBucket != null) 'confidenceBucket': confidenceBucket,
    if (maneuverType != null) 'maneuverType': maneuverType,
  };
}

/// Parsed advisory rules response.
class NavComplexityAdvisoryRulesResponse {
  final bool ok;
  final bool advisoryOnly;
  final int version;
  final String? generatedAt;
  final String? reason;
  final List<NavComplexityAdvisoryRule> rules;

  const NavComplexityAdvisoryRulesResponse({
    required this.ok,
    required this.advisoryOnly,
    required this.version,
    required this.rules,
    this.generatedAt,
    this.reason,
  });

  factory NavComplexityAdvisoryRulesResponse.fromJson(Map<String, dynamic> json) {
    final rawRules = json['rules'];
    final parsedRules = <NavComplexityAdvisoryRule>[];
    if (rawRules is List) {
      for (final item in rawRules) {
        if (item is Map<String, dynamic>) {
          parsedRules.add(NavComplexityAdvisoryRule.fromJson(item));
        }
      }
    }
    return NavComplexityAdvisoryRulesResponse(
      ok: json['ok'] == true,
      advisoryOnly: json['advisoryOnly'] == true,
      version: json['version'] is int
          ? json['version'] as int
          : int.tryParse('${json['version']}') ?? 1,
      generatedAt: json['generatedAt']?.toString(),
      reason: json['reason']?.toString(),
      rules: parsedRules,
    );
  }
}

/// In-memory store for latest advisory rules (diagnostics only).
class NavComplexityAdvisoryRulesStore {
  NavComplexityAdvisoryRulesStore._();

  static final NavComplexityAdvisoryRulesStore instance =
      NavComplexityAdvisoryRulesStore._();

  NavComplexityAdvisoryRulesResponse? _latest;

  NavComplexityAdvisoryRulesResponse? get latest => _latest;

  void setLatest(NavComplexityAdvisoryRulesResponse response) {
    _latest = response;
  }

  void clear() {
    _latest = null;
  }
}

/// Best-effort client for advisory learned rules. Never throws; never applied
/// to NavComplexityGuard or navigation runtime in NAV-AI-5A.
class NavComplexityAdvisoryRulesClient {
  NavComplexityAdvisoryRulesClient({
    http.Client? client,
    String? baseUrlOverride,
    String? serviceTokenOverride,
    NavComplexityAdvisoryRulesStore? store,
  }) : _client = client,
       _baseUrlOverride = baseUrlOverride,
       _serviceTokenOverride = serviceTokenOverride,
       _store = store ?? NavComplexityAdvisoryRulesStore.instance;

  final http.Client? _client;
  final String? _baseUrlOverride;
  final String? _serviceTokenOverride;
  final NavComplexityAdvisoryRulesStore _store;

  static final NavComplexityAdvisoryRulesClient instance =
      NavComplexityAdvisoryRulesClient();

  NavComplexityAdvisoryRulesResponse? get cached => _store.latest;

  /// Fetches advisory rules when [kNavComplexityFetchAdvisoryRules] is enabled.
  Future<NavComplexityAdvisoryRulesResponse?> fetchIfEnabled({
    Future<void> Function(Map<String, dynamic> summary)? recordDiagnostics,
  }) async {
    if (!kNavComplexityFetchAdvisoryRules) {
      _logRules(result: 'skipped', reason: 'flag_off');
      return null;
    }
    return fetch(recordDiagnostics: recordDiagnostics);
  }

  /// Fetches advisory rules regardless of flag (for tests/manual calls).
  Future<NavComplexityAdvisoryRulesResponse?> fetch({
    Future<void> Function(Map<String, dynamic> summary)? recordDiagnostics,
  }) async {
    try {
      final baseUrl = (_baseUrlOverride ?? kLearningBaseUrl).trim();
      final token = (_serviceTokenOverride ?? kLearningServiceToken).trim();
      if (baseUrl.isEmpty || token.isEmpty) {
        _logRules(result: 'skipped', reason: 'missing_config');
        return null;
      }

      final ownsClient = _client == null;
      final client = _client ?? http.Client();
      try {
        final response = await client
            .get(
              _rulesUri(baseUrl),
              headers: <String, String>{
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
              },
            )
            .timeout(kNavComplexityAdvisoryRulesTimeout);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          _logRules(result: 'failed', reason: 'http_${response.statusCode}');
          return null;
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          _logRules(result: 'failed', reason: 'invalid_json');
          return null;
        }
        if (_containsForbiddenKeys(decoded)) {
          _logRules(result: 'failed', reason: 'forbidden_keys');
          return null;
        }

        final parsed = NavComplexityAdvisoryRulesResponse.fromJson(decoded);
        if (!parsed.ok || !parsed.advisoryOnly) {
          _logRules(result: 'failed', reason: 'not_advisory');
          return null;
        }
        for (final rule in parsed.rules) {
          if (rule.enabledForRuntime) {
            _logRules(result: 'failed', reason: 'runtime_rule_rejected');
            return null;
          }
        }

        _store.setLatest(parsed);
        _logRules(
          result: 'fetched',
          reason: parsed.reason ?? 'ok',
          count: parsed.rules.length,
        );

        if (recordDiagnostics != null) {
          await recordDiagnostics(<String, dynamic>{
            'advisoryOnly': true,
            'version': parsed.version,
            'generatedAt': parsed.generatedAt,
            'reason': parsed.reason,
            'ruleCount': parsed.rules.length,
            'rules': parsed.rules.map((r) => r.toDiagnosticsJson()).toList(),
          });
        }

        return parsed;
      } on Exception {
        _logRules(result: 'failed', reason: 'request_failed');
        return null;
      } finally {
        if (ownsClient) {
          client.close();
        }
      }
    } on Exception {
      _logRules(result: 'failed', reason: 'unexpected');
      return null;
    }
  }
}

/// Startup helper — best-effort fetch when flag enabled; never blocks caller.
Future<void> fetchNavComplexityAdvisoryRulesIfEnabled({
  Future<void> Function(Map<String, dynamic> summary)? recordDiagnostics,
}) {
  return NavComplexityAdvisoryRulesClient.instance.fetchIfEnabled(
    recordDiagnostics: recordDiagnostics,
  );
}

/// @visibleForTesting
Uri navComplexityAdvisoryRulesUri(String baseUrl) => _rulesUri(baseUrl);

/// @visibleForTesting
bool navComplexityAdvisoryRulesPayloadContainsForbiddenKeys(
  Map<String, dynamic> payload,
) {
  return _containsForbiddenKeys(payload);
}
