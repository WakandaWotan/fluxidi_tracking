import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/fluxidi_runtime_env.dart';
import 'package:path_provider/path_provider.dart';

/// Languages the customer can pick. These are the languages the existing
/// customer screens are actually translated into, so the picker never offers a
/// language the bridged flows cannot render.
const List<AppLanguage> kCustomerLanguages = <AppLanguage>[
  AppLanguage.nl,
  AppLanguage.fr,
  AppLanguage.en,
  AppLanguage.de,
  AppLanguage.es,
];

const Map<AppLanguage, String> kCustomerLanguageLabels = <AppLanguage, String>{
  AppLanguage.nl: 'Nederlands',
  AppLanguage.fr: 'Français',
  AppLanguage.en: 'English',
  AppLanguage.de: 'Deutsch',
  AppLanguage.es: 'Español',
};

const Map<AppLanguage, String> kCustomerLanguageShortLabels =
    <AppLanguage, String>{
  AppLanguage.nl: 'NL',
  AppLanguage.fr: 'FR',
  AppLanguage.en: 'EN',
  AppLanguage.de: 'DE',
  AppLanguage.es: 'ES',
};

const AppLanguage _kDefaultCustomerLanguage = AppLanguage.nl;

const String _stateDirName = 'customer_state';
const String _fileName = 'customer_language_v1.json';

Future<File> _languageFile() async {
  final base = await getApplicationDocumentsDirectory();
  final root = Directory(
    '${base.path}${Platform.pathSeparator}'
    '${fluxidiRuntimeStateDirName(_stateDirName)}',
  );
  if (!await root.exists()) {
    await root.create(recursive: true);
  }
  return File('${root.path}${Platform.pathSeparator}$_fileName');
}

AppLanguage _fromStorage(String raw) {
  final normalized = raw.trim();
  for (final language in kCustomerLanguages) {
    if (language.name == normalized) return language;
  }
  return _kDefaultCustomerLanguage;
}

/// Restores the chosen language at boot.
///
/// The combined app keeps a customer's language choice in memory only, because
/// a business session supplies one on login. This app has no business session,
/// so a choice that does not survive a restart would simply be lost.
Future<void> loadCustomerLanguagePreference() async {
  var language = _kDefaultCustomerLanguage;
  try {
    final file = await _languageFile();
    if (await file.exists()) {
      final raw = await file.readAsString();
      if (raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          language = _fromStorage((decoded['language'] ?? '').toString());
        }
      }
    }
  } catch (_) {
    language = _kDefaultCustomerLanguage;
  }
  setAppLanguage(language);
}

Future<void> saveCustomerLanguagePreference(AppLanguage language) async {
  setAppLanguage(language);
  try {
    final file = await _languageFile();
    await file.writeAsString(
      jsonEncode(<String, dynamic>{
        'language': language.name,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  } catch (error) {
    debugPrint('[CUSTOMER_LANGUAGE][SAVE_ERROR] $error');
  }
}
