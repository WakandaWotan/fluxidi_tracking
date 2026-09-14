import 'dart:io';

import 'package:fluxidi_tracking/company/company_agenda_calendar.dart';
import 'package:fluxidi_tracking/fluxidi_runtime_env.dart';
import 'package:path_provider/path_provider.dart';

const String kCompanyAgendaPrefsFileName = 'company_agenda_hour_density.txt';

CompanyAgendaHourDensity? companyAgendaHourDensityOverrideForTest;
CompanyAgendaHourDensity? _memoryDensity;

void resetCompanyAgendaPrefsForTest() {
  companyAgendaHourDensityOverrideForTest = null;
  _memoryDensity = null;
}

CompanyAgendaHourDensity parseCompanyAgendaHourDensity(String? raw) {
  return (raw ?? '').trim() == 'spacious'
      ? CompanyAgendaHourDensity.spacious
      : CompanyAgendaHourDensity.compact;
}

String serializeCompanyAgendaHourDensity(CompanyAgendaHourDensity density) {
  return density == CompanyAgendaHourDensity.spacious ? 'spacious' : 'compact';
}

Future<File?> _prefsFile() async {
  try {
    final base = await getApplicationDocumentsDirectory();
    final root = Directory(
      '${base.path}${Platform.pathSeparator}${fluxidiRuntimeStateDirName('company_ops_state')}',
    );
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return File(
      '${root.path}${Platform.pathSeparator}$kCompanyAgendaPrefsFileName',
    );
  } catch (_) {
    return null;
  }
}

Future<CompanyAgendaHourDensity> loadCompanyAgendaHourDensity() async {
  final override = companyAgendaHourDensityOverrideForTest;
  if (override != null) return override;
  final memory = _memoryDensity;
  if (memory != null) return memory;
  try {
    final file = await _prefsFile();
    if (file == null || !await file.exists()) {
      return CompanyAgendaHourDensity.compact;
    }
    final parsed = parseCompanyAgendaHourDensity(await file.readAsString());
    _memoryDensity = parsed;
    return parsed;
  } catch (_) {
    return CompanyAgendaHourDensity.compact;
  }
}

Future<void> saveCompanyAgendaHourDensity(
  CompanyAgendaHourDensity density,
) async {
  _memoryDensity = density;
  try {
    final file = await _prefsFile();
    if (file == null) return;
    await file.writeAsString(
      serializeCompanyAgendaHourDensity(density),
      flush: true,
    );
  } catch (_) {
    // Keep the in-memory value when persistence temporarily fails.
  }
}
