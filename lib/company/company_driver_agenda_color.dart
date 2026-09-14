// COMPANY-CUSTOMER-OPS-P0 — agenda color palette and usage helpers.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';

/// The original six colors stay first so existing choices keep working.
const List<String> kCompanyDriverAgendaColorChoices = <String>[
  '#C9A227',
  '#2F6B4F',
  '#3D5A80',
  '#8C2F39',
  '#6B4F2F',
  '#4A4A4A',
  '#1F6F8B',
  '#6B3FA0',
  '#C45C26',
  '#2E7D6F',
  '#7A3B6C',
  '#3F6B2F',
  '#8B4A1B',
  '#2F4A6B',
  '#A13D5C',
  '#4A6B3F',
  '#5C4A8B',
  '#8B5A2B',
  '#2F6B6B',
  '#6B2F3F',
];

String normalizeCompanyAgendaColorHex(String raw) {
  var hex = raw.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 3) {
    hex = hex.split('').map((ch) => '$ch$ch').join();
  }
  if (hex.length == 8) hex = hex.substring(2);
  if (hex.length != 6) return '';
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return '';
  return '#${hex.toUpperCase()}';
}

String companyAgendaColorHexFromColor(Color color) {
  final value = color.value & 0x00FFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

bool companyAgendaColorIsStandard(String raw) {
  final hex = normalizeCompanyAgendaColorHex(raw);
  if (hex.isEmpty) return false;
  return kCompanyDriverAgendaColorChoices.contains(hex);
}

bool companyAgendaColorIsCustom(String raw) {
  final hex = normalizeCompanyAgendaColorHex(raw);
  return hex.isNotEmpty && !companyAgendaColorIsStandard(hex);
}

Color companyAgendaOnColor(Color fill) {
  return fill.computeLuminance() > 0.55 ? Colors.black : Colors.white;
}

String companyAgendaDriverColorHex(Map<String, dynamic> driver) {
  return normalizeCompanyAgendaColorHex(
    (driver['agenda_color'] ?? driver['agendaColor'] ?? '').toString(),
  );
}

/// Other chauffeurs in this company who already use [color]. Reuse stays allowed.
Map<String, List<String>> companyAgendaColorUsageByHex(
  List<Map<String, dynamic>> drivers, {
  String excludeDriverId = '',
}) {
  final used = <String, List<String>>{};
  final skip = excludeDriverId.trim();
  for (final driver in drivers) {
    final id = companyAgendaDriverId(driver);
    if (id.isEmpty || id == skip) continue;
    final hex = companyAgendaDriverColorHex(driver);
    if (hex.isEmpty) continue;
    used
        .putIfAbsent(hex, () => <String>[])
        .add(companyAgendaDriverName(driver));
  }
  return used;
}

List<String> companyAgendaColorUsers(
  Map<String, List<String>> usage,
  String color,
) {
  return List<String>.from(
    usage[normalizeCompanyAgendaColorHex(color)] ?? const <String>[],
  );
}

String companyAgendaColorOccupancyShort(List<String> names) {
  if (names.isEmpty) return '';
  final initials = names
      .map(companyAgendaInitials)
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (initials.isEmpty) return '';
  if (initials.length == 1) return initials.first;
  if (initials.length == 2) return '${initials[0]}, ${initials[1]}';
  return '${initials[0]} +${initials.length - 1}';
}

String companyAgendaColorUsedByText(List<String> names, AppLanguage language) {
  if (names.isEmpty) return '';
  final shown = names.take(3).join(', ');
  final extra = names.length - 3;
  final who = extra > 0 ? '$shown +$extra' : shown;
  return '${kCompanyAgendaColorUsedBy.of(language)} $who';
}
