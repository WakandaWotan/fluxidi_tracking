// COMPANY-DISPATCH-P0 — assignment choices, presence labels, heartbeat.

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_http.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_agenda_scope_io.dart'
    if (dart.library.html) 'package:fluxidi_tracking/company/company_agenda_scope_web.dart';
import 'package:fluxidi_tracking/company/company_assignment_choice_field.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';

const String kCompanyAgendaAssignmentChoicesPath =
    '/company/agenda/assignment-choices';
const String kPublicDriverHeartbeatPath = '/public/driver/heartbeat';
const Duration kCompanyDriverLiveAfter = Duration(minutes: 3);

const Key kCompanyAgendaCurrentDriverKey = Key('company_agenda_current_driver');
const Key kCompanyAgendaNoOtherDriverKey = Key('company_agenda_no_other_driver');

class CompanyAssignmentChoices {
  const CompanyAssignmentChoices({
    required this.drivers,
    this.soon = false,
    this.currentDriverId = '',
    this.currentDriverName = '',
  });

  final List<Map<String, dynamic>> drivers;
  final bool soon;
  final String currentDriverId;
  final String currentDriverName;

  bool get hasAlternatives => drivers.isNotEmpty;
}

Future<CompanyAssignmentChoices> fetchCompanyAssignmentChoices({
  required String pickupIso,
  int? durationMin,
  String excludeBookingId = '',
  String currentDriverId = '',
  Future<Map<String, String>> Function()? headers,
  Map<String, String>? Function()? scopeResolver,
}) async {
  final scope = (scopeResolver ?? resolveCompanyAgendaScopeQuery)();
  if (scope == null) {
    throw const CompanyAgendaException('missing_company_scope');
  }
  try {
    final query = <String, String>{
      ...scope,
      if (pickupIso.trim().isNotEmpty) 'pickup_iso': pickupIso.trim(),
      if (durationMin != null && durationMin > 0) 'duration_min': '$durationMin',
      if (excludeBookingId.trim().isNotEmpty)
        'exclude_booking_id': excludeBookingId.trim(),
      if (currentDriverId.trim().isNotEmpty)
        'current_driver_id': currentDriverId.trim(),
    };
    final res = await http
        .get(
          Uri.parse(
            '$kBookingBaseUrl$kCompanyAgendaAssignmentChoicesPath',
          ).replace(queryParameters: query),
          headers: await (headers ?? resolveCompanyAgendaHeaders)(),
        )
        .timeout(const Duration(seconds: 12));
    final decoded = tryDecodeCompanyAgendaJson(res.bodyBytes);
    if (decoded == null || decoded['ok'] != true) {
      throw CompanyAgendaException(
        decoded?['error']?.toString() ?? 'http_${res.statusCode}',
      );
    }
    final current = decoded['current_driver'];
    final rows = <Map<String, dynamic>>[];
    final raw = decoded['drivers'];
    if (raw is List) {
      for (final row in raw.whereType<Map>()) {
        rows.add(Map<String, dynamic>.from(row));
      }
    }
    return CompanyAssignmentChoices(
      drivers: rows,
      soon: decoded['soon'] == true,
      currentDriverId: current is Map
          ? (current['driver_id']?.toString() ?? '')
          : currentDriverId,
      currentDriverName: current is Map
          ? (current['display_name']?.toString() ?? '')
          : '',
    );
  } catch (error) {
    throwCompanyAgendaHttpError(error);
  }
}

List<Map<String, dynamic>> companyDispatchAlternativeDrivers({
  required List<Map<String, dynamic>> drivers,
  String currentDriverId = '',
}) {
  final current = currentDriverId.trim();
  return [
    for (final driver in drivers)
      if (companyAgendaDriverId(driver).isNotEmpty &&
          companyAgendaDriverId(driver) != current &&
          companyAgendaDriverIsActive(driver))
        driver,
  ];
}

String companyDispatchPresenceLabelText(
  String raw,
  AppLanguage language,
) {
  switch (raw.trim()) {
    case 'available':
      return kCompanyDriverPresenceAvailable.of(language);
    case 'on_trip':
      return kCompanyDriverPresenceOnTrip.of(language);
    case 'scheduled_no_live':
      return kCompanyDriverPresenceScheduledNoLive.of(language);
    case 'paused':
      return kCompanyDriverPresencePaused.of(language);
    case 'offline_work':
      return kCompanyDriverPresenceOfflineWork.of(language);
    case 'connection_lost':
      return kCompanyDriverPresenceLost.of(language);
    default:
      return '';
  }
}

bool companyDispatchIsLive({
  required DateTime? lastSeenUtc,
  required DateTime nowUtc,
  Duration ttl = kCompanyDriverLiveAfter,
}) {
  final seen = lastSeenUtc;
  if (seen == null) return false;
  return nowUtc.difference(seen) <= ttl;
}

Future<bool> syncPublicDriverHeartbeat({
  required String driverSessionToken,
}) async {
  final token = driverSessionToken.trim();
  if (token.isEmpty) return false;
  try {
    final response = await http
        .post(
          Uri.parse('${appConfig.bookingBaseUrl}$kPublicDriverHeartbeatPath'),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: '{}',
        )
        .timeout(const Duration(seconds: 8));
    return response.statusCode >= 200 && response.statusCode < 300;
  } catch (_) {
    return false;
  }
}

String companyDispatchAssignmentWarningText(
  String code,
  AppLanguage language,
) {
  if (code.trim().isEmpty) return '';
  return companyAgendaAssignmentExceptionText(
    CompanyAgendaException(code.trim()),
    language,
  );
}
