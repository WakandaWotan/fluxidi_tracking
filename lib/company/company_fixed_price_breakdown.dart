import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_labels.dart';

bool companyQuoteRequiresManualQuote(Map<String, dynamic>? quote) {
  return quote?['request_quote_required'] == true;
}

bool companyQuoteHasFixedPrice(Map<String, dynamic>? quote) {
  if (quote == null) return false;
  if (quote['fixed_fare_applied'] == true) return true;
  final source = quote['pricing_source']?.toString() ?? '';
  if (source == 'airport_fixed_fare' || source == 'company_fixed_price') {
    return true;
  }
  final snapshot = companyFixedPriceSnapshotOf(quote);
  return snapshot != null && snapshot['fixed_fare_rule_id'] != null;
}

Map<String, dynamic>? companyFixedPriceSnapshotOf(Map<String, dynamic>? source) {
  if (source == null) return null;
  final raw = source['fixed_price_snapshot'] ?? source['snapshot'];
  if (raw is Map) return Map<String, dynamic>.from(raw);
  final breakdown = source['breakdown'];
  if (breakdown is Map &&
      (breakdown['fixed_fare_rule_id'] != null ||
          breakdown['kind'] == 'company_fixed_price' ||
          breakdown['kind'] == 'airport_fixed_fare')) {
    return Map<String, dynamic>.from(breakdown);
  }
  return null;
}

Object? companyFixedPriceNeedsMoreDetail(Map<String, dynamic>? source) {
  if (source == null) return null;
  return source['fixed_price_needs_more_detail'] ?? source['needs_more_detail'];
}

/// A postcode rule is not a municipality rule. When the chosen place carries no
/// postcode the fare cannot be judged yet, so name the fare and the postcode it
/// waits for instead of reporting a plain no-match.
List<String> companyFixedPriceClarificationLines(
  Object? needsMoreDetail, {
  required AppLanguage language,
}) {
  if (needsMoreDetail is! List || needsMoreDetail.isEmpty) {
    return const <String>[];
  }
  final lines = <String>[];
  var origin = false;
  var destination = false;
  for (final item in needsMoreDetail) {
    if (item is! Map) continue;
    final name = item['name']?.toString().trim() ?? '';
    final value = item['value']?.toString().trim() ?? '';
    if (name.isEmpty || value.isEmpty) continue;
    final isOrigin = item['role']?.toString() != 'destination';
    if (isOrigin) {
      origin = true;
    } else {
      destination = true;
    }
    final role = isOrigin
        ? kCompanyFixedPricesRoleOrigin.of(language)
        : kCompanyFixedPricesRoleDestination.of(language);
    lines.add(
      '$name ${kCompanyFixedPricesNeedPreciseOrigin.of(language)} $value '
      '($role).',
    );
  }
  if (lines.isEmpty) return const <String>[];
  if (origin) {
    lines.add(kCompanyFixedPricesNeedPreciseOriginHint.of(language));
  }
  if (destination) {
    lines.add(kCompanyFixedPricesNeedPreciseDestinationHint.of(language));
  }
  return lines;
}

List<String> companyFixedPriceBreakdownLines(
  Map<String, dynamic> snapshot, {
  required AppLanguage language,
}) {
  final lines = <String>[
    '${kCompanyFixedPricesApplied.of(language)}: ${snapshot['name'] ?? snapshot['fixed_fare_rule_id'] ?? ''}',
    if ((snapshot['price_covers']?.toString() ?? '') == 'full_assignment')
      language == AppLanguage.nl
          ? 'Geldt voor de volledige heen-/terugopdracht'
          : 'Covers the full outbound/return assignment'
    else
      language == AppLanguage.nl
          ? 'Geldt voor één ritdeel'
          : 'Covers one ride leg',
    'Basis: €${snapshot['base_incl_vat'] ?? snapshot['total_incl_vat']}',
  ];
  final surcharges = snapshot['surcharges'];
  if (surcharges is List) {
    for (final item in surcharges) {
      if (item is! Map) continue;
      final label = item['label']?.toString() ?? 'Toeslag';
      lines.add('$label: €${item['amount_incl_vat']}');
    }
  }
  lines.add(
    language == AppLanguage.nl
        ? 'Totaal incl. btw: €${snapshot['total_incl_vat']} (btw €${snapshot['price_vat'] ?? '—'})'
        : 'Total incl. VAT: €${snapshot['total_incl_vat']} (VAT €${snapshot['price_vat'] ?? '—'})',
  );
  if (snapshot['fixed_fare_rule_id'] != null) {
    lines.add(
      'Regel ${snapshot['fixed_fare_rule_id']} · v${snapshot['rule_version'] ?? 1}',
    );
  }
  return lines.where((line) => line.trim().isNotEmpty).toList();
}

class CompanyFixedPriceBreakdown extends StatelessWidget {
  const CompanyFixedPriceBreakdown({
    super.key,
    required this.language,
    required this.snapshot,
  });

  final AppLanguage language;
  final Map<String, dynamic> snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: kCompanyFixedPriceBreakdownKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in companyFixedPriceBreakdownLines(
          snapshot,
          language: language,
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(line, softWrap: true),
          ),
      ],
    );
  }
}
