/// Canonical Pricing-engine setup completeness for company settings badges.
///
/// Aligns with fare calculation / `_toMoney` / worker normalize: configured
/// numeric **zero is valid** when the field is present and finite. Empty or
/// unparseable core fields are incomplete; negatives are invalid.
///
/// Optional Pricing-engine fields (wait, bag, stop, tiers, night/weekend/cap,
/// fuel, return fee) are not required for Compleet. Return rides may use a
/// zero surcharge. VAT is owned by the separate billing/VAT badge.
library;

enum PricingSetupCompletenessKind {
  complete,
  attention,
  incomplete,
}

/// Machine keys for exact user-visible reason mapping.
abstract final class PricingSetupReasonKey {
  static const baseFareMissing = 'base_fare_missing';
  static const baseFareInvalid = 'base_fare_invalid';
  static const perKmMissing = 'per_km_missing';
  static const perKmInvalid = 'per_km_invalid';
  static const perMinuteMissing = 'per_minute_missing';
  static const perMinuteInvalid = 'per_minute_invalid';
  static const minimumFareMissing = 'minimum_fare_missing';
  static const minimumFareInvalid = 'minimum_fare_invalid';
}

class PricingSetupFieldCheck {
  const PricingSetupFieldCheck({
    required this.ok,
    this.missingReasonKey,
    this.invalidReasonKey,
  });

  final bool ok;
  final String? missingReasonKey;
  final String? invalidReasonKey;
}

class PricingSetupCompleteness {
  const PricingSetupCompleteness({
    required this.kind,
    required this.passedCount,
    required this.requiredCount,
    required this.reasonKeys,
  });

  final PricingSetupCompletenessKind kind;
  final int passedCount;
  final int requiredCount;
  final List<String> reasonKeys;

  bool get isComplete => kind == PricingSetupCompletenessKind.complete;
}

/// Parse a money/text field the same way settings persistence does.
double? parsePricingSetupNumber(String raw) {
  final text = raw.replaceAll(',', '.').trim();
  if (text.isEmpty) return null;
  final parsed = double.tryParse(text);
  if (parsed == null || !parsed.isFinite) return null;
  return parsed;
}

/// Core Pricing-engine fields must be present, finite, and **>= 0**.
///
/// Valid `0.00` counts as configured (not missing). Negatives are invalid.
PricingSetupFieldCheck checkPricingCoreNonNegative(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return const PricingSetupFieldCheck(ok: false);
  }
  final parsed = parsePricingSetupNumber(text);
  if (parsed == null) {
    return const PricingSetupFieldCheck(ok: false);
  }
  if (parsed < 0) {
    return const PricingSetupFieldCheck(ok: false);
  }
  return const PricingSetupFieldCheck(ok: true);
}

PricingSetupFieldCheck _checkCore({
  required String raw,
  required String missingKey,
  required String invalidKey,
}) {
  final text = raw.trim();
  if (text.isEmpty) {
    return PricingSetupFieldCheck(ok: false, missingReasonKey: missingKey);
  }
  final parsed = parsePricingSetupNumber(text);
  if (parsed == null || parsed < 0) {
    return PricingSetupFieldCheck(ok: false, invalidReasonKey: invalidKey);
  }
  return const PricingSetupFieldCheck(ok: true);
}

/// Evaluate the four canonical core Pricing-engine fields.
///
/// These are the same fields the settings overview badge historically gated,
/// now aligned with fare-calc allowing zero.
PricingSetupCompleteness evaluatePricingSetupCompleteness({
  required String baseFare,
  required String perKm,
  required String perMinute,
  required String minimumFare,
}) {
  final checks = <PricingSetupFieldCheck>[
    _checkCore(
      raw: baseFare,
      missingKey: PricingSetupReasonKey.baseFareMissing,
      invalidKey: PricingSetupReasonKey.baseFareInvalid,
    ),
    _checkCore(
      raw: perKm,
      missingKey: PricingSetupReasonKey.perKmMissing,
      invalidKey: PricingSetupReasonKey.perKmInvalid,
    ),
    _checkCore(
      raw: perMinute,
      missingKey: PricingSetupReasonKey.perMinuteMissing,
      invalidKey: PricingSetupReasonKey.perMinuteInvalid,
    ),
    _checkCore(
      raw: minimumFare,
      missingKey: PricingSetupReasonKey.minimumFareMissing,
      invalidKey: PricingSetupReasonKey.minimumFareInvalid,
    ),
  ];

  final reasons = <String>[];
  var passed = 0;
  for (final check in checks) {
    if (check.ok) {
      passed++;
      continue;
    }
    if (check.missingReasonKey != null) {
      reasons.add(check.missingReasonKey!);
    } else if (check.invalidReasonKey != null) {
      reasons.add(check.invalidReasonKey!);
    }
  }

  final kind = passed == checks.length
      ? PricingSetupCompletenessKind.complete
      : (passed >= 1
            ? PricingSetupCompletenessKind.attention
            : PricingSetupCompletenessKind.incomplete);

  return PricingSetupCompleteness(
    kind: kind,
    passedCount: passed,
    requiredCount: checks.length,
    reasonKeys: reasons,
  );
}

/// Convenience for persisted [BusinessSettingsState]-shaped numeric values.
PricingSetupCompleteness evaluatePricingSetupCompletenessFromNumbers({
  required double baseFare,
  required double perKm,
  required double perMinute,
  required double minimumFare,
}) {
  String fmt(double v) => v.toStringAsFixed(2);
  return evaluatePricingSetupCompleteness(
    baseFare: fmt(baseFare),
    perKm: fmt(perKm),
    perMinute: fmt(perMinute),
    minimumFare: fmt(minimumFare),
  );
}
