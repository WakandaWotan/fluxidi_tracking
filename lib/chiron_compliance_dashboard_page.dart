import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_settings_page.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/chiron_company_connection_config.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/compliance_ledger_reader.dart';
import 'package:fluxidi_tracking/compliance_register_receipt_bridge.dart';
import 'package:fluxidi_tracking/local_ride_assignment_cache.dart';
import 'package:fluxidi_tracking/main_parts/chiron_context_hydration_retry.dart';
import 'package:fluxidi_tracking/main_parts/chiron_dossier_grouping.dart';
import 'package:fluxidi_tracking/main_parts/chiron_last_good_events_cache.dart';
import 'package:fluxidi_tracking/main_parts/chiron_sync_status_presentation.dart';
import 'package:fluxidi_tracking/company_driver_management_page.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/customer_bookings_store.dart';
import 'package:fluxidi_tracking/driver_documents_store.dart';
import 'package:fluxidi_tracking/vehicle_management_page.dart';
import 'package:fluxidi_tracking/widgets/chiron_acceptance_step_card.dart';
import 'package:fluxidi_tracking/widgets/chiron_environment_status_labels.dart';
import 'package:fluxidi_tracking/widgets/chiron_friendly_diagnose_sheet.dart';
import 'package:fluxidi_tracking/widgets/chiron_production_setup_card.dart';
import 'package:fluxidi_tracking/widgets/chiron_self_service_wizard.dart';
import 'package:fluxidi_tracking/widgets/chiron_test_setup_card.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

@immutable
class _ChironThemeTokens {
  const _ChironThemeTokens({
    required this.variant,
    required this.palette,
    required this.background,
    required this.card,
    required this.panel,
    required this.border,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textFaint,
    required this.chipText,
    required this.progressTrack,
    required this.success,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.statusSuspendedBg,
    required this.statusVerifiedBg,
    required this.statusPendingBg,
  });

  final BusinessThemeVariant variant;
  final BusinessThemePalette palette;
  final Color background;
  final Color card;
  final Color panel;
  final Color border;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textFaint;
  final Color chipText;
  final Color progressTrack;
  final Color success;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color statusSuspendedBg;
  final Color statusVerifiedBg;
  final Color statusPendingBg;
}

_ChironThemeTokens _chironTokensForVariant(BusinessThemeVariant variant) {
  final palette = paletteForBusinessTheme(variant);
  final isClean = variant == BusinessThemeVariant.cleanProfessional;
  return _ChironThemeTokens(
    variant: variant,
    palette: palette,
    background: palette.background,
    card: palette.surface,
    panel: palette.surfaceAlt,
    border: palette.border.withOpacity(isClean ? 0.92 : 0.62),
    accent: palette.accent,
    textPrimary: palette.textPrimary,
    textSecondary: palette.textSecondary,
    textMuted: palette.textMuted.withOpacity(isClean ? 0.98 : 0.9),
    textFaint: palette.textMuted.withOpacity(isClean ? 0.9 : 0.78),
    chipText: variant == BusinessThemeVariant.executiveGold
        ? const Color(0xFFEAD9A3)
        : palette.accent.withOpacity(isClean ? 0.94 : 0.96),
    progressTrack: isClean
        ? palette.border.withOpacity(0.55)
        : palette.textPrimary.withOpacity(0.12),
    success: palette.success,
    warning: isClean ? const Color(0xFFB97600) : const Color(0xFFF6B94D),
    warningSoft: isClean ? const Color(0x1AC98200) : const Color(0x1AFFB74D),
    danger: palette.danger,
    dangerSoft: isClean ? const Color(0x1AC95D6D) : const Color(0x33FF5A5A),
    statusSuspendedBg: isClean
        ? const Color(0x1AC95D6D)
        : const Color(0xFF3A1010),
    statusVerifiedBg: isClean
        ? const Color(0x1A2FAE7B)
        : const Color(0xFF12331F),
    statusPendingBg: isClean
        ? const Color(0x1AC98200)
        : const Color(0xFF2A2410),
  );
}

_ChironThemeTokens _chironTokens() =>
    _chironTokensForVariant(businessThemeNotifier.value);

/// Material theme derived from the active Chiron surface colors.
///
/// The app shell is dark (`ColorScheme.dark` + white outlined buttons). Clean
/// Professional paints light cards; without this override, outlined/filled
/// controls inherit white foreground on light surfaces (unreadable).
ThemeData _chironMaterialTheme(_ChironThemeTokens tokens) {
  final isDark = tokens.palette.isDark;
  final base = (isDark ? ThemeData.dark : ThemeData.light)(useMaterial3: true);
  final typography =
      (isDark ? Typography.whiteMountainView : Typography.blackMountainView)
          .apply(
            bodyColor: tokens.textPrimary,
            displayColor: tokens.textPrimary,
          );
  final disabledFg = Color.lerp(
    tokens.textMuted,
    tokens.textPrimary,
    isDark ? 0.18 : 0.28,
  )!;
  final disabledBg = tokens.border.withOpacity(isDark ? 0.28 : 0.45);
  return base.copyWith(
    brightness: isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: tokens.background,
    disabledColor: disabledFg,
    colorScheme: ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: tokens.accent,
      onPrimary: tokens.palette.textOnAccent,
      secondary: tokens.accent,
      onSecondary: tokens.palette.textOnAccent,
      error: tokens.danger,
      onError: tokens.palette.textOnAccent,
      surface: tokens.card,
      onSurface: tokens.textPrimary,
    ),
    textTheme: typography,
    primaryTextTheme: typography,
    iconTheme: IconThemeData(color: tokens.textSecondary),
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.background,
      foregroundColor: tokens.textPrimary,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.card,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: tokens.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
      contentTextStyle: TextStyle(
        color: tokens.textSecondary,
        fontSize: 14,
        height: 1.35,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: tokens.accent),
    inputDecorationTheme: InputDecorationTheme(
      labelStyle: TextStyle(color: tokens.textSecondary),
      hintStyle: TextStyle(color: tokens.textMuted),
      helperStyle: TextStyle(color: tokens.textMuted, fontSize: 11.5),
      filled: true,
      fillColor: tokens.panel,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: tokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: tokens.accent, width: 1.2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: tokens.border.withOpacity(0.7)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return disabledFg;
          return tokens.textPrimary;
        }),
        iconColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return disabledFg;
          return tokens.textPrimary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return disabledBg;
          return Colors.transparent;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return BorderSide(color: tokens.border.withOpacity(0.95));
          }
          return BorderSide(color: tokens.accent.withOpacity(0.85));
        }),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return disabledBg;
          return tokens.accent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return disabledFg;
          return tokens.palette.textOnAccent;
        }),
        iconColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return disabledFg;
          return tokens.palette.textOnAccent;
        }),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return disabledFg;
          return tokens.textPrimary;
        }),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: tokens.panel,
      disabledColor: disabledBg,
      selectedColor: tokens.accent.withOpacity(0.16),
      labelStyle: TextStyle(color: tokens.textSecondary, fontSize: 12),
      secondaryLabelStyle: TextStyle(color: tokens.textPrimary, fontSize: 12),
      side: BorderSide(color: tokens.border),
    ),
  );
}

Color get _chironBg => _chironTokens().background;
Color get _chironCard => _chironTokens().card;
Color get _chironPanel => _chironTokens().panel;
Color get _chironGold => _chironTokens().accent;
Color get _chironBorder => _chironTokens().border;
Color get _chironTextPrimary => _chironTokens().textPrimary;
Color get _chironTextSecondary => _chironTokens().textSecondary;
Color get _chironTextMuted => _chironTokens().textMuted;
Color get _chironTextFaint => _chironTokens().textFaint;
Color get _chironChipText => _chironTokens().chipText;
Color get _chironWarning => _chironTokens().warning;
Color get _chironWarningSoft => _chironTokens().warningSoft;
Color get _chironDanger => _chironTokens().danger;
Color get _chironDangerSoft => _chironTokens().dangerSoft;
Color get _chironSuccess => _chironTokens().success;
Color get _chironProgressTrack => _chironTokens().progressTrack;

ButtonStyle _chironTestAccessSecondaryButtonStyle() {
  final tokens = _chironTokens();
  final isClean = tokens.variant == BusinessThemeVariant.cleanProfessional;
  final disabledForeground = tokens.textMuted;
  final disabledBackground = tokens.border.withOpacity(isClean ? 0.24 : 0.14);
  final disabledBorder = tokens.border.withOpacity(isClean ? 0.92 : 0.58);

  return ButtonStyle(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return disabledForeground;
      return tokens.accent;
    }),
    iconColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return disabledForeground;
      return tokens.accent;
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return disabledBackground;
      return Colors.transparent;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return BorderSide(color: disabledBorder);
      }
      return BorderSide(color: tokens.border);
    }),
    textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
  );
}

ButtonStyle _chironTestAccessDangerButtonStyle() {
  final tokens = _chironTokens();
  final isClean = tokens.variant == BusinessThemeVariant.cleanProfessional;
  final disabledForeground = Color.lerp(
    tokens.danger,
    tokens.textMuted,
    isClean ? 0.28 : 0.38,
  )!;
  final disabledBackground = tokens.dangerSoft.withOpacity(
    isClean ? 0.55 : 0.35,
  );
  final disabledBorder = tokens.danger.withOpacity(isClean ? 0.42 : 0.32);

  return ButtonStyle(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return disabledForeground;
      return tokens.danger;
    }),
    iconColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return disabledForeground;
      return tokens.danger;
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return disabledBackground;
      return Colors.transparent;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return BorderSide(color: disabledBorder);
      }
      return BorderSide(color: tokens.danger.withOpacity(0.55));
    }),
    textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
  );
}

({String tenantId, String companyId})? _chironDashboardTenantCompanyScope() {
  final activeCompanyId = companyProfileNotifier.value?.companyId.trim() ?? '';
  if (activeCompanyId.isNotEmpty) {
    return (tenantId: activeCompanyId, companyId: activeCompanyId);
  }
  final sessionCompanyId =
      activeCompanySessionNotifier.value?.companyId.trim() ?? '';
  if (sessionCompanyId.isNotEmpty) {
    return (tenantId: sessionCompanyId, companyId: sessionCompanyId);
  }
  return null;
}

class ChironComplianceDashboardPage extends StatelessWidget {
  const ChironComplianceDashboardPage({super.key});

  AppLanguage get _lang => appConfig.currentLanguage;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (_lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return en;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      builder: (context, variant, _) {
        final tokens = _chironTokensForVariant(variant);
        return Theme(
          data: _chironMaterialTheme(tokens),
          child: Scaffold(
            backgroundColor: tokens.background,
            appBar: AppBar(
              backgroundColor: tokens.background,
              foregroundColor: tokens.textPrimary,
              title: Text(
                _t(
                  nl: 'Chiron-compliance',
                  en: 'Chiron Compliance',
                  fr: 'Conformité Chiron',
                  es: 'Cumplimiento Chiron',
                ),
              ),
            ),
            body: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _ChironComplianceOverview(lang: _lang),
                // RELEASE-P0-CHIRON-STATE-MACHINE-2026-07-31: explicit split
                // status labels replace the previously ambiguous "official
                // submission: off" line. Backed entirely by the new server
                // fields (`acc_test_submit_active`, `production_submit_active`,
                // `effective_chiron_environment`) so the client never
                // second-guesses the state-machine derivation.
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ValueListenableBuilder<BackendChironConnectionStatus?>(
                    valueListenable: backendChironConnectionStatusNotifier,
                    builder: (context, backendStatus, _) {
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: tokens.panel,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t(
                                nl: 'Chiron-omgevingstatus',
                                en: 'Chiron environment status',
                                fr: 'État de l\'environnement Chiron',
                                es: 'Estado del entorno Chiron',
                              ),
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ChironEnvironmentStatusLabels(
                              status: backendStatus,
                              language: _lang,
                              textColor: tokens.textPrimary,
                              mutedColor: tokens.textSecondary,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                _HubActionCard(
                title: _t(
                  nl: 'Checklist & voorbereiding',
                  en: 'Checklist & readiness',
                  fr: 'Checklist et préparation',
                  es: 'Checklist y preparación',
                ),
                subtitle: _t(
                  nl: 'Controleer bedrijfsprofiel, chauffeurs en voertuigen voor dagelijks gebruik.',
                  en: 'Check company profile, drivers and vehicles for day-to-day use.',
                  fr: 'Vérifiez le profil entreprise, les chauffeurs et les véhicules pour un usage quotidien.',
                  es: 'Revisa perfil de empresa, conductores y vehículos para el uso diario.',
                ),
                trailingIcon: Icons.fact_check_outlined,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const _ChironReadinessChecklistPage(),
                    ),
                  );
                },
              ),
              _HubActionCard(
                title: _t(
                  nl: 'Backendmeldingen',
                  en: 'Backend messages',
                  fr: 'Messages système',
                  es: 'Mensajes del sistema',
                ),
                subtitle: _t(
                  nl: 'Bekijk recente alleen-lezen meldingen uit de compliancemodule.',
                  en: 'View recent read-only messages from the compliance module.',
                  fr: 'Consultez les messages récents en lecture seule du module de conformité.',
                  es: 'Consulta los mensajes recientes de solo lectura del módulo de cumplimiento.',
                ),
                note: _t(
                  nl: 'Alleen lezen · handmatig verversen',
                  en: 'Read-only · manual refresh',
                  fr: 'Lecture seule · rafraîchissement manuel',
                  es: 'Solo lectura · actualización manual',
                ),
                trailingIcon: Icons.cloud_done_outlined,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const _ChironRemoteCompliancePage(),
                    ),
                  );
                },
              ),
              _HubActionCard(
                title: _t(
                  nl: 'Lokaal rittenregister',
                  en: 'Local ride register',
                  fr: 'Registre local des trajets',
                  es: 'Registro local de viajes',
                ),
                subtitle: _t(
                  nl: 'Bekijk lokale ritregistraties van afgeronde ritten.',
                  en: 'View local compliance records of completed rides.',
                  fr: 'Consultez les enregistrements locaux de conformité des courses terminées.',
                  es: 'Consulta registros locales de cumplimiento de viajes completados.',
                ),
                note: _t(
                  nl: 'Alleen lezen',
                  en: 'Read-only',
                  fr: 'Lecture seule',
                  es: 'Solo lectura',
                ),
                trailingIcon: Icons.receipt_long_outlined,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const _ChironLocalLedgerPage(),
                    ),
                  );
                },
              ),
              ],
            ),
          ),
        );
      },
    );
  }
}

({String tenantId, String companyId})? _chironScopedCompanyIds() {
  final activeCompanyId = companyProfileNotifier.value?.companyId.trim() ?? '';
  if (activeCompanyId.isNotEmpty) {
    return (tenantId: activeCompanyId, companyId: activeCompanyId);
  }
  final sessionCompanyId =
      activeCompanySessionNotifier.value?.companyId.trim() ?? '';
  if (sessionCompanyId.isNotEmpty) {
    return (tenantId: sessionCompanyId, companyId: sessionCompanyId);
  }
  return null;
}

Future<_ChironReadinessResponse> _fetchChironReadinessResponse(
  AppLanguage lang,
) async {
  String tr({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return en;
    }
  }

  final effective = _chironScopedCompanyIds();
  if (effective == null) {
    return _ChironReadinessResponse.missingScope(
      errorMessage: tr(
        nl: 'Geen bedrijfscontext beschikbaar.',
        en: 'No company context available.',
        fr: 'Aucun contexte entreprise disponible.',
        es: 'No hay contexto de empresa disponible.',
      ),
    );
  }

  /* CHIRON-P0-2A: readiness now goes through the booking worker's
   * company-owner authenticated proxy at bookingBaseUrl. The direct
   * compliance admin bearer is no longer used or shipped in the client. */
  if (!hasCompanyOwnerAuthContext()) {
    return _ChironReadinessResponse.error(
      errorMessage: tr(
        nl: 'Niet gemachtigd om het technisch rapport te laden.',
        en: 'Not authorized to load the technical report.',
        fr: 'Non autorisé à charger le rapport technique.',
        es: 'No autorizado para cargar el informe técnico.',
      ),
      unauthorized: true,
    );
  }

  final uri = _chironBookingReadonlyEndpoint(
    '/admin/chiron/readiness',
    tenantId: effective.tenantId,
    companyId: effective.companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  try {
    final res = await http
        .post(
          uri,
          headers: auth.headers,
          body: jsonEncode(<String, dynamic>{
            'tenant_id': effective.tenantId,
            'company_id': effective.companyId,
            'limit': 20,
            'event_type': 'ride_stop',
          }),
        )
        .timeout(const Duration(seconds: 15));
    final contentType = (res.headers['content-type'] ?? '').toLowerCase();
    Map<String, dynamic> payload = const <String, dynamic>{};
    if (contentType.contains('application/json') && res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          payload = Map<String, dynamic>.from(decoded);
        }
      } catch (err) {
        debugPrint(
          '[$_chironBookingWorkerProxyLogTag][READINESS_TOP] json_parse_failed status=${res.statusCode} err=$err',
        );
      }
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      debugPrint(
        '[$_chironBookingWorkerProxyLogTag][READINESS_TOP] auth_failed status=${res.statusCode}',
      );
      return _ChironReadinessResponse.error(
        errorMessage: tr(
          nl: 'Niet gemachtigd om het technisch rapport te laden.',
          en: 'Not authorized to load the technical report.',
          fr: 'Non autorisé à charger le rapport technique.',
          es: 'No autorizado para cargar el informe técnico.',
        ),
        unauthorized: true,
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      debugPrint(
        '[$_chironBookingWorkerProxyLogTag][READINESS_TOP] non_success status=${res.statusCode}',
      );
      return _ChironReadinessResponse.error(
        errorMessage: tr(
          nl: 'Technisch rapport kon niet geladen worden.',
          en: 'Technical report could not be loaded.',
          fr: 'Le rapport technique n’a pas pu être chargé.',
          es: 'No se pudo cargar el informe técnico.',
        ),
      );
    }
    return _ChironReadinessResponse.fromJson(payload);
  } catch (err) {
    debugPrint(
      '[$_chironBookingWorkerProxyLogTag][READINESS_TOP] request_failed err=$err',
    );
    return _ChironReadinessResponse.error(
      errorMessage: tr(
        nl: 'Technisch rapport kon niet geladen worden.',
        en: 'Technical report could not be loaded.',
        fr: 'Le rapport technique n’a pas pu être chargé.',
        es: 'No se pudo cargar el informe técnico.',
      ),
    );
  }
}

Future<void> _openChironTechnicalReport(
  BuildContext context,
  AppLanguage lang,
) async {
  String tr({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return en;
    }
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        Center(child: CircularProgressIndicator(color: _chironGold)),
  );

  final response = await _fetchChironReadinessResponse(lang);
  if (!context.mounted) return;
  Navigator.of(context).pop();

  if (response.missingScope || !response.ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(response.errorMessage),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  if (response.processedCount == 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            nl: 'Nog geen ritdata gevonden voor een technische controle.',
            en: 'No ride data found yet for a technical check.',
            fr: 'Aucune donnée de course trouvée pour un contrôle technique.',
            es: 'Aún no hay datos de viaje para una comprobación técnica.',
          ),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          _ChironReadinessReportPage(lang: lang, response: response),
    ),
  );
}

class _ChironComplianceOverview extends StatefulWidget {
  const _ChironComplianceOverview({required this.lang});

  final AppLanguage lang;

  @override
  State<_ChironComplianceOverview> createState() =>
      _ChironComplianceOverviewState();
}

class _ChironComplianceOverviewState extends State<_ChironComplianceOverview> {
  final GlobalKey _testAccessSectionKey = GlobalKey();

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (widget.lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return en;
    }
  }

  void _scrollToTestAccess() {
    final target = _testAccessSectionKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _baseCard(
      title: _t(nl: 'Overzicht', en: 'Overview', fr: 'Aperçu', es: 'Resumen'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              nl: 'Stel uw Chiron-koppeling in en test de verbinding.',
              en: 'Set up your Chiron connection and test it.',
              fr: 'Configurez votre connexion Chiron et testez-la.',
              es: 'Configure su conexión Chiron y pruébela.',
            ),
            style: TextStyle(color: _chironTextSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<BackendChironConnectionStatus?>(
            valueListenable: backendChironConnectionStatusNotifier,
            builder: (context, backendStatus, _) {
              Future<void> refreshStatus() async {
                final scope = _chironDashboardTenantCompanyScope();
                if (scope == null) return;
                final status = await fetchBackendChironConnectionStatus(
                  tenantId: scope.tenantId,
                  companyId: scope.companyId,
                );
                backendChironConnectionStatusNotifier.value = status;
              }

              return Column(
                key: const ValueKey('chiron_compliance_overview_wizard'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KeyedSubtree(
                    key: _testAccessSectionKey,
                    child: ChironSelfServiceWizard(
                      status: backendStatus,
                      language: widget.lang,
                      textPrimary: _chironTextPrimary,
                      textSecondary: _chironTextSecondary,
                      panelColor: _chironPanel,
                      borderColor: _chironBorder,
                      accentColor: _chironGold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ChironTestSetupCard(
                    status: backendStatus,
                    language: widget.lang,
                    backgroundColor: _chironPanel,
                    textColor: _chironTextPrimary,
                    mutedColor: _chironTextSecondary,
                    onSave: (clientId, clientSecret) async {
                      final scope = _chironDashboardTenantCompanyScope();
                      if (scope == null) {
                        throw Exception('missing_scope');
                      }
                      if (clientId.trim().isEmpty ||
                          clientSecret.trim().isEmpty) {
                        throw Exception('missing_test_credentials');
                      }
                      await _saveChironOAuthClientCredentialsViaBooking(
                        tenantId: scope.tenantId,
                        companyId: scope.companyId,
                        clientId: clientId.trim(),
                        clientSecret: clientSecret,
                      );
                      await refreshStatus();
                    },
                    onTestConnection: () async {
                      final scope = _chironDashboardTenantCompanyScope();
                      if (scope == null) {
                        throw Exception('missing_scope');
                      }
                      final result =
                          await _runChironMockConnectionTestViaBooking(
                        tenantId: scope.tenantId,
                        companyId: scope.companyId,
                        environment: ChironConnectionEnvironment.test,
                      );
                      await refreshStatus();
                      if (!result.ok) {
                        throw Exception(
                          (result.sanitizedError ?? result.errorCode ??
                                  'connection_failed')
                              .toString(),
                        );
                      }
                    },
                    onClear: () async {
                      final scope = _chironDashboardTenantCompanyScope();
                      if (scope == null) {
                        throw Exception('missing_scope');
                      }
                      await _clearChironTestCredentialsViaBooking(
                        tenantId: scope.tenantId,
                        companyId: scope.companyId,
                      );
                      await refreshStatus();
                    },
                  ),
                  const SizedBox(height: 12),
                  ChironAcceptanceStepCard(
                    status: backendStatus,
                    language: widget.lang,
                    backgroundColor: _chironPanel,
                    textColor: _chironTextPrimary,
                    mutedColor: _chironTextSecondary,
                    onReset: () async {
                      final scope = _chironDashboardTenantCompanyScope();
                      if (scope == null) return;
                      final progress = await showChironTestflowResetDialog(
                        context: context,
                        lang: widget.lang,
                        productionActive:
                            backendStatus?.productionEnabled ?? false,
                        onReset: () => _resetChironTestflowViaBooking(
                          tenantId: scope.tenantId,
                          companyId: scope.companyId,
                        ),
                      );
                      // Only refresh after a confirmed successful reset —
                      // cancel must not start a hanging status fetch.
                      if (progress != null) {
                        await refreshStatus();
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  ChironProductionSetupCard(
                    status: backendStatus,
                    language: widget.lang,
                    backgroundColor: _chironPanel,
                    textColor: _chironTextPrimary,
                    mutedColor: _chironTextSecondary,
                    onSave: (clientId, clientSecret) async {
                      final scope = _chironDashboardTenantCompanyScope();
                      if (scope == null) {
                        throw Exception('missing_scope');
                      }
                      if (clientId.trim().isEmpty ||
                          clientSecret.trim().isEmpty) {
                        throw Exception('missing_production_credentials');
                      }
                      await _saveChironProductionOAuthCredentialsViaBooking(
                        tenantId: scope.tenantId,
                        companyId: scope.companyId,
                        clientId: clientId.trim(),
                        clientSecret: clientSecret,
                      );
                      await refreshStatus();
                    },
                    onTestConnection: () async {
                      final scope = _chironDashboardTenantCompanyScope();
                      if (scope == null) {
                        throw Exception('missing_scope');
                      }
                      final result =
                          await _runChironMockConnectionTestViaBooking(
                        tenantId: scope.tenantId,
                        companyId: scope.companyId,
                        environment: ChironConnectionEnvironment.production,
                      );
                      await refreshStatus();
                      if (!result.ok) {
                        throw Exception(
                          (result.sanitizedError ??
                                  result.errorCode ??
                                  'connection_failed')
                              .toString(),
                        );
                      }
                    },
                    onActivate: () async {
                      final scope = _chironDashboardTenantCompanyScope();
                      if (scope == null) {
                        throw Exception('missing_scope');
                      }
                      final current =
                          backendChironConnectionStatusNotifier.value;
                      final updated =
                          await saveBackendChironConnectionStatus(
                        tenantId: scope.tenantId,
                        companyId: scope.companyId,
                        enabled: current?.enabled ?? true,
                        environment:
                            ChironConnectionEnvironment.production,
                        region: current?.region.isNotEmpty == true
                            ? current!.region
                            : ChironRegionScope.flanders,
                        productionEnabled: true,
                      );
                      backendChironConnectionStatusNotifier.value = updated;
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _ChironHubStatusCard(
            lang: widget.lang,
            onConfigureConnection: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const BusinessSettingsPage(),
                ),
              );
            },
            onTestConnection: _scrollToTestAccess,
          ),
          const SizedBox(height: 12),
          _ChironHubAdvancedDiagnosticsSection(
            lang: widget.lang,
            onOpenReport: () =>
                _openChironTechnicalReport(context, widget.lang),
          ),
          // Obsolete duplicate credential / testflow editor
          // (_ChironTestAccessCard) intentionally not routed here — the
          // three-step wizard cards above are the only self-service UI.
        ],
      ),
    );
  }
}

// RELEASE-P0: obsolete 8-step onboarding ExpansionTile and helper tiles were removed from the active Chiron route.

class _ChironHubStatusCard extends StatefulWidget {
  const _ChironHubStatusCard({
    required this.lang,
    required this.onConfigureConnection,
    required this.onTestConnection,
  });

  final AppLanguage lang;
  final VoidCallback onConfigureConnection;
  final VoidCallback onTestConnection;

  @override
  State<_ChironHubStatusCard> createState() => _ChironHubStatusCardState();
}

class _ChironHubStatusCardState extends State<_ChironHubStatusCard> {
  late final ChironContextLoadCoordinator _loadCoordinator;

  @override
  void initState() {
    super.initState();
    _loadCoordinator = ChironContextLoadCoordinator(
      listenables: <Listenable>[
        activeCompanySessionNotifier,
        companyProfileNotifier,
      ],
      hasCompanySession: () => hasCompanyOwnerAuthContext(),
      companyId: () {
        final profile = companyProfileNotifier.value?.companyId.trim() ?? '';
        if (profile.isNotEmpty) return profile;
        return activeCompanySessionNotifier.value?.companyId.trim() ?? '';
      },
      runLoad: _refreshBackendChironStatus,
      onDiag: (stage) => debugPrint('[CHIRON_LOAD][DIAG] stage=$stage'),
    )..attach();
  }

  @override
  void dispose() {
    _loadCoordinator.dispose();
    super.dispose();
  }

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (widget.lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return en;
    }
  }

  Future<void> _refreshBackendChironStatus(int gen) async {
    final scope = _chironScopedCompanyIds();
    if (scope == null) return;
    try {
      final fetched = await _fetchChironTestAccessBackendStatus(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!_loadCoordinator.shouldApplyGeneration(gen)) return;
      _publishChironDashboardStatusFetch(
        status: fetched.status,
        internalTest: fetched.internalTest,
      );
    } catch (e) {
      if (_loadCoordinator.shouldApplyGeneration(gen)) {
        debugPrint('[CHIRON_CONNECTION][DASHBOARD_LOAD] error=$e');
      }
    }
  }

  ({String label, Color color, Color background, Color border})
  _hubStatusVisual({
    required bool enabled,
    required bool testCredentialsStored,
    required bool internalTestPassed,
    required String lastConnectionStatus,
    required bool productionEnabled,
    required bool backendConfirmed,
  }) {
    final status = lastConnectionStatus.trim().toLowerCase();
    if (productionEnabled && backendConfirmed) {
      return (
        label: _t(
          nl: 'Productie actief',
          en: 'Production active',
          fr: 'Production active',
          es: 'Producción activa',
        ),
        color: _chironSuccess,
        background: _chironSuccess.withOpacity(0.16),
        border: _chironSuccess.withOpacity(0.55),
      );
    }
    if (status == ChironConnectionStatus.testFailed) {
      return (
        label: _t(
          nl: 'Actie nodig',
          en: 'Action needed',
          fr: 'Action requise',
          es: 'Acción necesaria',
        ),
        color: _chironWarning,
        background: _chironWarningSoft,
        border: _chironWarning.withOpacity(0.55),
      );
    }
    if (internalTestPassed) {
      return (
        label: _t(
          nl: 'Interne test geslaagd',
          en: 'Internal test passed',
          fr: 'Test interne réussi',
          es: 'Prueba interna superada',
        ),
        color: _chironSuccess,
        background: _chironSuccess.withOpacity(0.16),
        border: _chironSuccess.withOpacity(0.55),
      );
    }
    if (testCredentialsStored) {
      return (
        label: _t(
          nl: 'Testgegevens opgeslagen',
          en: 'Test credentials stored',
          fr: 'Identifiants de test enregistrés',
          es: 'Credenciales de prueba guardadas',
        ),
        color: _chironGold,
        background: _chironGold.withOpacity(0.12),
        border: _chironGold.withOpacity(0.45),
      );
    }
    if (!enabled) {
      return (
        label: _t(
          nl: 'Niet ingesteld',
          en: 'Not configured',
          fr: 'Non configuré',
          es: 'No configurado',
        ),
        color: _chironTextSecondary,
        background: _chironPanel,
        border: _chironBorder,
      );
    }
    return (
      label: _t(
        nl: 'Actie nodig',
        en: 'Action needed',
        fr: 'Action requise',
        es: 'Acción necesaria',
      ),
      color: _chironWarning,
      background: _chironWarningSoft,
      border: _chironWarning.withOpacity(0.55),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BackendChironConnectionStatus?>(
      valueListenable: backendChironConnectionStatusNotifier,
      builder: (context, backendStatus, _) {
        return ValueListenableBuilder<_ChironPersistedInternalTestStatus?>(
          valueListenable: _chironPersistedInternalTestNotifier,
          builder: (context, persistedInternalTest, __) {
            return ValueListenableBuilder<BusinessSettingsState>(
              valueListenable: businessSettingsNotifier,
              builder: (context, settings, ___) {
                final enabled =
                    backendStatus?.enabled ?? settings.chironEnabled;
                final testCredentialsStored =
                    backendStatus?.testCredentialsStored ?? false;
                final productionEnabled =
                    backendStatus?.productionEnabled ??
                    settings.chironProductionEnabled;
                final backendConfirmed = backendStatus != null;
                final lastConnectionStatus =
                    backendStatus?.lastConnectionStatus ??
                    (settings.chironConnectionStatus ==
                            ChironConnectionStatus.testPassed
                        ? ChironConnectionStatus.testPassed
                        : settings.chironConnectionStatus ==
                              ChironConnectionStatus.testFailed
                        ? ChironConnectionStatus.testFailed
                        : settings.chironConnectionStatus ==
                              ChironConnectionStatus.testPending
                        ? ChironConnectionStatus.testPending
                        : ChironBackendLastConnectionStatus.neverTested);
                final internalTestPassed =
                    testCredentialsStored &&
                    (persistedInternalTest?.isPassed ?? false);
                final statusVisual = _hubStatusVisual(
                  enabled: enabled,
                  testCredentialsStored: testCredentialsStored,
                  internalTestPassed: internalTestPassed,
                  lastConnectionStatus: lastConnectionStatus,
                  productionEnabled: productionEnabled,
                  backendConfirmed: backendConfirmed,
                );

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _chironPanel,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _chironBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_loadCoordinator.prerequisitesReady)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _t(
                              nl: 'Bedrijfscontext wordt geladen…',
                              en: 'Loading company context…',
                              fr: 'Chargement du contexte entreprise…',
                              es: 'Cargando contexto de empresa…',
                            ),
                            style: TextStyle(
                              color: _chironTextMuted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            _t(
                              nl: 'Chiron-instellingen',
                              en: 'Chiron settings',
                              fr: 'Paramètres Chiron',
                              es: 'Configuración Chiron',
                            ),
                            style: TextStyle(
                              color: _chironGold,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: statusVisual.background,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: statusVisual.border),
                            ),
                            child: Text(
                              statusVisual.label,
                              style: TextStyle(
                                color: statusVisual.color,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ChironEnvironmentStatusLabels(
                        status: backendStatus,
                        language: widget.lang,
                        textColor: _chironTextPrimary,
                        mutedColor: _chironTextSecondary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        chironHonestNextStepLabel(
                          status: backendStatus,
                          language: widget.lang,
                          enabled: enabled,
                        ),
                        style: TextStyle(
                          color: _chironTextSecondary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: widget.onConfigureConnection,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _chironGold,
                              side: BorderSide(color: _chironBorder),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: Text(
                              _t(
                                nl: 'Open instellingen',
                                en: 'Open settings',
                                fr: 'Ouvrir les paramètres',
                                es: 'Abrir configuración',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: widget.onTestConnection,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _chironGold,
                              side: BorderSide(color: _chironBorder),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: Text(
                              _t(
                                nl: 'Test verbinding',
                                en: 'Test connection',
                                fr: 'Tester la connexion',
                                es: 'Probar conexión',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ChironHubAdvancedDiagnosticsSection extends StatefulWidget {
  const _ChironHubAdvancedDiagnosticsSection({
    required this.lang,
    required this.onOpenReport,
  });

  final AppLanguage lang;
  final VoidCallback onOpenReport;

  @override
  State<_ChironHubAdvancedDiagnosticsSection> createState() =>
      _ChironHubAdvancedDiagnosticsSectionState();
}

class _ChironHubAdvancedDiagnosticsSectionState
    extends State<_ChironHubAdvancedDiagnosticsSection> {
  /// Silent re-entry guard only — never drives a "Running diagnostics…" label
  /// behind the open sheet. Loading ownership lives inside the sheet.
  bool _sheetOpen = false;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
    String? de,
  }) {
    switch (widget.lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return de ?? en;
    }
  }

  /// One tap opens the sheet immediately. Spinner/error stay in the sheet.
  Future<void> _openDiagnoseOnce() async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    final status = backendChironConnectionStatusNotifier.value;
    try {
      await showChironFriendlyDiagnoseSheet(
        context: context,
        language: widget.lang,
        status: status,
        panelColor: _chironPanel,
        cardColor: _chironCard,
        borderColor: _chironBorder,
        textPrimary: _chironTextPrimary,
        textSecondary: _chironTextSecondary,
        onOpenAdvanced: widget.onOpenReport,
      );
    } finally {
      _sheetOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _chironPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _chironBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              nl: 'Probleemoplossing',
              en: 'Troubleshooting',
              fr: 'Dépannage',
              es: 'Solución de problemas',
              de: 'Fehlerbehebung',
            ),
            style: TextStyle(
              color: _chironTextPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _t(
              nl: 'Open Diagnose voor een duidelijke status van test, acceptatie en productie.',
              en: 'Open Diagnose for a clear status of test, acceptance and production.',
              fr: 'Ouvrez Diagnostic pour un état clair du test, de l’acceptation et de la production.',
              es: 'Abra Diagnóstico para un estado claro de prueba, aceptación y producción.',
              de: 'Öffnen Sie Diagnose für einen klaren Status von Test, Akzeptanz und Produktion.',
            ),
            style: TextStyle(
              color: _chironTextMuted,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              key: const ValueKey('chiron_diagnose_button'),
              onPressed: _openDiagnoseOnce,
              icon: const Icon(Icons.troubleshoot_outlined, size: 20),
              label: Text(
                _t(
                  nl: 'Diagnose',
                  en: 'Diagnose',
                  fr: 'Diagnostic',
                  es: 'Diagnóstico',
                  de: 'Diagnose',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


Uri _chironBookingScopedEndpoint(
  String path, {
  required String tenantId,
  required String companyId,
}) {
  return Uri.parse('${appConfig.bookingBaseUrl}$path').replace(
    queryParameters: <String, String>{
      'tenant_id': tenantId,
      'company_id': companyId,
      'tenantId': tenantId,
      'companyId': companyId,
    },
  );
}

String _chironSafeApiErrorCode(Map<String, dynamic> decoded) {
  final error = decoded['error'];
  if (error == null) return 'unknown_error';
  final text = error.toString().trim();
  return text.isEmpty ? 'unknown_error' : text;
}

Future<String> _saveChironTestCredentialsViaBooking({
  required String tenantId,
  required String companyId,
  required String apiToken,
}) async {
  final endpoint = _chironBookingScopedEndpoint(
    '/admin/chiron/config/test-credentials',
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .post(
        endpoint,
        headers: auth.headers,
        body: jsonEncode(<String, dynamic>{
          'tenant_id': tenantId,
          'company_id': companyId,
          'auth_scheme': ChironCredentialAuthScheme.authSchemeApiToken,
          'credential_fields': <String, dynamic>{'api_token': apiToken},
        }),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) {
    throw BackendChironConnectionApiException(
      error: 'invalid_response',
      statusCode: res.statusCode,
    );
  }
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode < 200 || res.statusCode >= 300 || map['ok'] == false) {
    throw BackendChironConnectionApiException(
      error: _chironSafeApiErrorCode(map),
      statusCode: res.statusCode,
    );
  }
  final masked = map['masked_identifier'] ?? map['maskedIdentifier'];
  return masked == null ? '' : masked.toString().trim();
}

/// Chiron Connect 4A: store per-company OAuth2 client credentials (test/ACC).
/// Only client_id + client_secret are sent; the secret never returns from the
/// backend (response is masked-only).
Future<String> _saveChironOAuthClientCredentialsViaBooking({
  required String tenantId,
  required String companyId,
  required String clientId,
  required String clientSecret,
}) async {
  final endpoint = _chironBookingScopedEndpoint(
    '/admin/chiron/config/test-credentials',
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .post(
        endpoint,
        headers: auth.headers,
        body: jsonEncode(<String, dynamic>{
          'tenant_id': tenantId,
          'company_id': companyId,
          'auth_scheme':
              ChironCredentialAuthScheme.authSchemeOAuthClientCredentials,
          'credential_fields': <String, dynamic>{
            'client_id': clientId,
            'client_secret': clientSecret,
          },
        }),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) {
    throw BackendChironConnectionApiException(
      error: 'invalid_response',
      statusCode: res.statusCode,
    );
  }
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode < 200 || res.statusCode >= 300 || map['ok'] == false) {
    throw BackendChironConnectionApiException(
      error: _chironSafeApiErrorCode(map),
      statusCode: res.statusCode,
    );
  }
  final masked = map['masked_identifier'] ?? map['maskedIdentifier'];
  return masked == null ? '' : masked.toString().trim();
}

/// RELEASE-P0-CHIRON-SELF-SERVICE-2026-07-31: store production OAuth credentials.
Future<String> _saveChironProductionOAuthCredentialsViaBooking({
  required String tenantId,
  required String companyId,
  required String clientId,
  required String clientSecret,
}) async {
  final endpoint = _chironBookingScopedEndpoint(
    '/admin/chiron/config/production-credentials',
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .post(
        endpoint,
        headers: auth.headers,
        body: jsonEncode(<String, dynamic>{
          'tenant_id': tenantId,
          'company_id': companyId,
          'auth_scheme':
              ChironCredentialAuthScheme.authSchemeOAuthClientCredentials,
          'credential_fields': <String, dynamic>{
            'client_id': clientId,
            'client_secret': clientSecret,
          },
        }),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) {
    throw BackendChironConnectionApiException(
      error: 'invalid_response',
      statusCode: res.statusCode,
    );
  }
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode < 200 || res.statusCode >= 300 || map['ok'] == false) {
    throw BackendChironConnectionApiException(
      error: _chironSafeApiErrorCode(map),
      statusCode: res.statusCode,
    );
  }
  final masked = map['masked_identifier'] ?? map['maskedIdentifier'];
  return masked == null ? '' : masked.toString().trim();
}

Future<void> _clearChironTestCredentialsViaBooking({
  required String tenantId,
  required String companyId,
}) async {
  final endpoint = _chironBookingScopedEndpoint(
    '/admin/chiron/config/test-credentials/clear',
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .post(
        endpoint,
        headers: auth.headers,
        body: jsonEncode(<String, dynamic>{
          'tenant_id': tenantId,
          'company_id': companyId,
        }),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) {
    throw BackendChironConnectionApiException(
      error: 'invalid_response',
      statusCode: res.statusCode,
    );
  }
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode < 200 || res.statusCode >= 300 || map['ok'] == false) {
    throw BackendChironConnectionApiException(
      error: _chironSafeApiErrorCode(map),
      statusCode: res.statusCode,
    );
  }
}

class _ChironMockConnectionTestResult {
  const _ChironMockConnectionTestResult({
    required this.ok,
    this.mockOnly = false,
    this.externalCallPerformed = false,
    this.credentialDecryptOk = false,
    this.credentialPayloadValid = false,
    this.maskedIdentifier = '',
    this.lastConnectionStatus = '',
    this.productionEnabled = false,
    this.officialSubmitEnabled = false,
    this.updatedAt,
    this.errorCode,
    // Chiron Connect 4B: OAuth2 client credentials live test fields. The UI
    // shows confirmation only; the access token itself is never sent back.
    this.authScheme = '',
    this.accessTokenObtained = false,
    this.tokenType = '',
    this.expiresInSeconds,
    this.sanitizedError,
  });

  final bool ok;
  final bool mockOnly;
  final bool externalCallPerformed;
  final bool credentialDecryptOk;
  final bool credentialPayloadValid;
  final String maskedIdentifier;
  final String lastConnectionStatus;
  final bool productionEnabled;
  final bool officialSubmitEnabled;
  final String? updatedAt;
  final String? errorCode;
  final String authScheme;
  final bool accessTokenObtained;
  final String tokenType;
  final int? expiresInSeconds;
  final String? sanitizedError;

  bool get isOAuthScheme =>
      authScheme.toLowerCase() ==
      ChironCredentialAuthScheme.authSchemeOAuthClientCredentials;

  factory _ChironMockConnectionTestResult.fromJson(Map<String, dynamic> json) {
    bool boolField(List<String> keys, {bool fallback = false}) {
      for (final key in keys) {
        final value = json[key];
        if (value is bool) return value;
        if (value is String) {
          final token = value.trim().toLowerCase();
          if (token == 'true') return true;
          if (token == 'false') return false;
        }
      }
      return fallback;
    }

    String textField(List<String> keys, {String fallback = ''}) {
      for (final key in keys) {
        final value = json[key];
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isNotEmpty) return text;
      }
      return fallback;
    }

    int? intField(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value is num) return value.toInt();
        if (value is String) {
          final parsed = int.tryParse(value.trim());
          if (parsed != null) return parsed;
        }
      }
      return null;
    }

    return _ChironMockConnectionTestResult(
      ok: boolField(const ['ok'], fallback: false),
      mockOnly: boolField(const ['mock_only', 'mockOnly']),
      externalCallPerformed: boolField(const [
        'external_call_performed',
        'externalCallPerformed',
      ]),
      credentialDecryptOk: boolField(const [
        'credential_decrypt_ok',
        'credentialDecryptOk',
      ]),
      credentialPayloadValid: boolField(const [
        'credential_payload_valid',
        'credentialPayloadValid',
      ]),
      maskedIdentifier: textField(const [
        'masked_identifier',
        'maskedIdentifier',
      ]),
      lastConnectionStatus: textField(const [
        'last_connection_status',
        'lastConnectionStatus',
      ]),
      productionEnabled: boolField(const [
        'production_enabled',
        'productionEnabled',
      ]),
      officialSubmitEnabled: boolField(const [
        'official_submit_enabled',
        'officialSubmitEnabled',
      ]),
      updatedAt: textField(const ['updated_at', 'updatedAt']).isEmpty
          ? null
          : textField(const ['updated_at', 'updatedAt']),
      errorCode: textField(const ['error']).isEmpty
          ? null
          : textField(const ['error']),
      authScheme: textField(const ['auth_scheme', 'authScheme']),
      accessTokenObtained: boolField(const [
        'access_token_obtained',
        'accessTokenObtained',
      ]),
      tokenType: textField(const ['token_type', 'tokenType']),
      expiresInSeconds: intField(const [
        'expires_in_seconds',
        'expiresInSeconds',
      ]),
      sanitizedError:
          textField(const ['sanitized_error', 'sanitizedError']).isEmpty
          ? null
          : textField(const ['sanitized_error', 'sanitizedError']),
    );
  }
}

Future<_ChironMockConnectionTestResult> _runChironMockConnectionTestViaBooking({
  required String tenantId,
  required String companyId,
  String environment = ChironConnectionEnvironment.test,
}) async {
  final endpoint = _chironBookingScopedEndpoint(
    '/admin/chiron/connection/test',
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .post(
        endpoint,
        headers: auth.headers,
        body: jsonEncode(<String, dynamic>{
          'tenant_id': tenantId,
          'company_id': companyId,
          'environment': environment,
        }),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) {
    return const _ChironMockConnectionTestResult(
      ok: false,
      errorCode: 'invalid_response',
    );
  }
  final map = Map<String, dynamic>.from(decoded);
  // Chiron Connect 4B: failed live OAuth2 exchanges return HTTP 400 with a
  // structured body (auth_scheme/sanitized_error/last_connection_status) that
  // we want to surface verbatim to the UI. Generic non-2xx without that shape
  // is still treated as a plain error.
  if (res.statusCode < 200 || res.statusCode >= 300 || map['ok'] == false) {
    final externalCall = map['external_call_performed'] == true;
    if (externalCall) {
      return _ChironMockConnectionTestResult.fromJson(map);
    }
    return _ChironMockConnectionTestResult(
      ok: false,
      errorCode: _chironSafeApiErrorCode(map),
    );
  }
  return _ChironMockConnectionTestResult.fromJson(map);
}

class _ChironPersistedInternalTestStatus {
  const _ChironPersistedInternalTestStatus({
    this.status = '',
    this.passed = false,
    this.lastAt,
    this.environment,
    this.mockOnly = false,
    this.externalCallPerformed = false,
    this.credentialDecryptOk = false,
    this.credentialPayloadValid = false,
    this.maskedIdentifier = '',
    this.fingerprintShort = '',
  });

  final String status;
  final bool passed;
  final String? lastAt;
  final String? environment;
  final bool mockOnly;
  final bool externalCallPerformed;
  final bool credentialDecryptOk;
  final bool credentialPayloadValid;
  final String maskedIdentifier;
  final String fingerprintShort;

  bool get isPassed {
    final normalizedStatus = status.trim().toLowerCase();
    if (normalizedStatus == 'passed') return true;
    return passed;
  }

  factory _ChironPersistedInternalTestStatus.fromJson(
    Map<String, dynamic> json,
  ) {
    bool boolField(List<String> keys, {bool fallback = false}) {
      for (final key in keys) {
        final value = json[key];
        if (value is bool) return value;
        if (value is String) {
          final token = value.trim().toLowerCase();
          if (token == 'true') return true;
          if (token == 'false') return false;
        }
      }
      return fallback;
    }

    String textField(List<String> keys, {String fallback = ''}) {
      for (final key in keys) {
        final value = json[key];
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isNotEmpty) return text;
      }
      return fallback;
    }

    String? nullableTextField(List<String> keys) {
      final text = textField(keys);
      return text.isEmpty ? null : text;
    }

    return _ChironPersistedInternalTestStatus(
      status: textField(const ['internal_test_status', 'internalTestStatus']),
      passed: boolField(const ['internal_test_passed', 'internalTestPassed']),
      lastAt: nullableTextField(const [
        'last_internal_test_at',
        'lastInternalTestAt',
      ]),
      environment: nullableTextField(const [
        'last_internal_test_environment',
        'lastInternalTestEnvironment',
      ]),
      mockOnly: boolField(const [
        'last_internal_test_mock_only',
        'lastInternalTestMockOnly',
      ]),
      externalCallPerformed: boolField(const [
        'last_internal_test_external_call_performed',
        'lastInternalTestExternalCallPerformed',
      ]),
      credentialDecryptOk: boolField(const [
        'last_internal_test_credential_decrypt_ok',
        'lastInternalTestCredentialDecryptOk',
      ]),
      credentialPayloadValid: boolField(const [
        'last_internal_test_credential_payload_valid',
        'lastInternalTestCredentialPayloadValid',
      ]),
      maskedIdentifier: textField(const [
        'last_internal_test_masked_identifier',
        'lastInternalTestMaskedIdentifier',
      ]),
      fingerprintShort: textField(const [
        'last_internal_test_fingerprint_short',
        'lastInternalTestFingerprintShort',
      ]),
    );
  }
}

/// Chiron Connect 4C: lightweight acceptance-testflow progress parsed from the
/// /admin/chiron/config/status response. Kept local to this page so the shared
/// BackendChironConnectionStatus model (in app_config.dart) does not need to
/// change. Never carries secrets.
class _ChironTestflowProgress {
  const _ChironTestflowProgress({
    this.status = 'not_started',
    this.messagesRequired = 10,
    this.messagesSent = 0,
    this.departureRequired = 5,
    this.departureSent = 0,
    this.arrivalRequired = 5,
    this.arrivalSent = 0,
    this.ridesRequired = 5,
    this.ridesCompleted = 0,
    this.completedAt,
    this.lastError,
  });

  final String status;
  final int messagesRequired;
  final int messagesSent;
  final int departureRequired;
  final int departureSent;
  final int arrivalRequired;
  final int arrivalSent;
  final int ridesRequired;
  final int ridesCompleted;
  final String? completedAt;
  final String? lastError;

  bool get isComplete => status.trim().toLowerCase() == 'complete';
  bool get isInProgress => status.trim().toLowerCase() == 'in_progress';

  factory _ChironTestflowProgress.fromJson(Map<String, dynamic> json) {
    int intField(List<String> keys, int fallback) {
      for (final key in keys) {
        final value = json[key];
        if (value is num) return value.toInt();
        if (value is String) {
          final parsed = int.tryParse(value.trim());
          if (parsed != null) return parsed;
        }
      }
      return fallback;
    }

    String textField(List<String> keys, {String fallback = ''}) {
      for (final key in keys) {
        final value = json[key];
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isNotEmpty) return text;
      }
      return fallback;
    }

    String? nullableTextField(List<String> keys) {
      final text = textField(keys);
      return text.isEmpty ? null : text;
    }

    return _ChironTestflowProgress(
      status: textField(const [
        'testflow_status',
        'testflowStatus',
      ], fallback: 'not_started'),
      messagesRequired: intField(const [
        'test_messages_required',
        'testMessagesRequired',
      ], 10),
      messagesSent: intField(const [
        'test_messages_sent_count',
        'testMessagesSentCount',
      ], 0),
      departureRequired: intField(const [
        'test_departure_required',
        'testDepartureRequired',
      ], 5),
      departureSent: intField(const [
        'test_departure_sent_count',
        'testDepartureSentCount',
      ], 0),
      arrivalRequired: intField(const [
        'test_arrival_required',
        'testArrivalRequired',
      ], 5),
      arrivalSent: intField(const [
        'test_arrival_sent_count',
        'testArrivalSentCount',
      ], 0),
      ridesRequired: intField(const [
        'test_rides_required',
        'testRidesRequired',
      ], 5),
      ridesCompleted: intField(const [
        'test_rides_completed_count',
        'testRidesCompletedCount',
      ], 0),
      completedAt: nullableTextField(const [
        'testflow_completed_at',
        'testflowCompletedAt',
      ]),
      lastError: nullableTextField(const [
        'testflow_last_error',
        'testflowLastError',
      ]),
    );
  }
}

final ValueNotifier<_ChironPersistedInternalTestStatus?>
_chironPersistedInternalTestNotifier =
    ValueNotifier<_ChironPersistedInternalTestStatus?>(null);

void _publishChironDashboardStatusFetch({
  required BackendChironConnectionStatus status,
  required _ChironPersistedInternalTestStatus internalTest,
}) {
  updateBackendChironConnectionStatusCache(status);
  _chironPersistedInternalTestNotifier.value = status.testCredentialsStored
      ? internalTest
      : null;
}

Future<
  ({
    BackendChironConnectionStatus status,
    _ChironPersistedInternalTestStatus internalTest,
    _ChironTestflowProgress testflow,
  })
>
_fetchChironTestAccessBackendStatus({
  required String tenantId,
  required String companyId,
}) async {
  final endpoint = _chironBookingScopedEndpoint(
    '/admin/chiron/config/status',
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .get(endpoint, headers: auth.headers)
      .timeout(const Duration(seconds: 12));
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) {
    throw BackendChironConnectionApiException(
      error: 'invalid_response',
      statusCode: res.statusCode,
    );
  }
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode < 200 || res.statusCode >= 300 || map['ok'] == false) {
    throw BackendChironConnectionApiException(
      error: _chironSafeApiErrorCode(map),
      statusCode: res.statusCode,
    );
  }
  return (
    status: BackendChironConnectionStatus.fromJson(map),
    internalTest: _ChironPersistedInternalTestStatus.fromJson(map),
    testflow: _ChironTestflowProgress.fromJson(map),
  );
}

/// Chiron Connect 4C: reset the acceptance testflow counters/status only.
/// Credentials and the OAuth connection status are never touched server-side.
Future<_ChironTestflowProgress> _resetChironTestflowViaBooking({
  required String tenantId,
  required String companyId,
}) async {
  final endpoint = _chironBookingScopedEndpoint(
    '/admin/chiron/testflow/reset',
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .post(
        endpoint,
        headers: auth.headers,
        body: jsonEncode(<String, dynamic>{
          'tenant_id': tenantId,
          'company_id': companyId,
        }),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) {
    throw BackendChironConnectionApiException(
      error: 'invalid_response',
      statusCode: res.statusCode,
    );
  }
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode < 200 || res.statusCode >= 300 || map['ok'] == false) {
    throw BackendChironConnectionApiException(
      error: _chironSafeApiErrorCode(map),
      statusCode: res.statusCode,
    );
  }
  return _ChironTestflowProgress.fromJson(map);
}

String? _formatChironInternalTestTimestamp(String? iso) {
  if (iso == null || iso.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(iso.trim());
  if (parsed == null) return null;
  final local = parsed.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final year = local.year.toString();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day-$month-$year $hour:$minute';
}

/// RELEASE-P0-CHIRON-RESET-UX-2026-07-31: open the professional Chiron
/// testflow-reset confirmation dialog. Returns the fresh
/// `_ChironTestflowProgress` when the user confirmed and the backend reset
/// succeeded, `null` when the user cancelled or the backend rejected the
/// request. On backend failure the dialog stays open and shows a readable
/// (secret-free) error until the user cancels.
///
/// The dialog is a self-contained state machine (initial → busy → error →
/// closed) that owns the network call so that:
///   * a double tap on "Testflow resetten" can never produce two requests
///     (the primary button flips to disabled+progress the moment the first
///     tap begins);
///   * a backend failure never falsely flips the parent UI to a zeroed
///     state — the parent only trusts the return value.
Future<_ChironTestflowProgress?> showChironTestflowResetDialog({
  required BuildContext context,
  required AppLanguage lang,
  required bool productionActive,
  required Future<_ChironTestflowProgress> Function() onReset,
}) {
  return showDialog<_ChironTestflowProgress?>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return ChironTestflowResetConfirmDialog<_ChironTestflowProgress>(
        lang: lang,
        productionActive: productionActive,
        onReset: onReset,
      );
    },
  );
}

/// Content of the Chiron testflow reset confirmation dialog. Public so widget
/// tests can pump it in isolation without spinning up the full compliance
/// page.
///
/// The widget:
///   * pops the enclosing dialog with `null` on cancel;
///   * calls [onReset] on confirm and pops with the returned progress on
///     success;
///   * stays open with an in-dialog error banner on failure so the operator
///     sees exactly why the reset was refused;
///   * disables both action buttons for the entire duration of the request.
///
/// The generic [T] is the shape of the "fresh testflow progress" the caller
/// receives on success. Prod code always uses the file-private
/// `_ChironTestflowProgress`; widget tests substitute a lightweight stub so
/// the dialog can be pumped in isolation without importing internal types.
class ChironTestflowResetConfirmDialog<T> extends StatefulWidget {
  const ChironTestflowResetConfirmDialog({
    super.key,
    required this.lang,
    required this.productionActive,
    required this.onReset,
  });

  final AppLanguage lang;

  /// True when the compliance backend currently has production_enabled=true
  /// for this company. When true, the dialog surfaces an explicit precondition
  /// notice so the operator sees that the reset will disable production.
  final bool productionActive;

  /// Actually performs the reset. Called at most once per dialog invocation.
  final Future<T> Function() onReset;

  @override
  State<ChironTestflowResetConfirmDialog<T>> createState() =>
      _ChironTestflowResetConfirmDialogState<T>();
}

class _ChironTestflowResetConfirmDialogState<T>
    extends State<ChironTestflowResetConfirmDialog<T>> {
  bool _busy = false;
  String? _errorCode;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (widget.lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return en;
    }
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorCode = null;
    });
    T? progress;
    String? errorCode;
    try {
      progress = await widget.onReset();
    } on BackendChironConnectionApiException catch (err) {
      errorCode = err.error;
    } catch (_) {
      errorCode = 'unknown_error';
    }
    if (!mounted) return;
    if (progress != null) {
      Navigator.of(context).pop(progress);
      return;
    }
    setState(() {
      _busy = false;
      _errorCode = errorCode ?? 'unknown_error';
    });
  }

  void _cancel() {
    if (_busy) return;
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _chironTokens();
    final title = _t(
      nl: 'Chiron-testflow resetten?',
      en: 'Reset the Chiron testflow?',
      fr: 'Réinitialiser le flux de test Chiron ?',
      es: '¿Reiniciar el flujo de prueba de Chiron?',
    );
    final body = _t(
      nl: 'De voortgang van de acceptatietest wordt teruggezet naar nul. '
          'Productie wordt uitgeschakeld en de Chiron-testomgeving wordt '
          'opnieuw geactiveerd. Uw testgegevens en geslaagde OAuth2-verbinding '
          'blijven bewaard.',
      en: 'Acceptance-test progress will be reset to zero. Production is '
          'disabled and the Chiron test environment is re-activated. Your '
          'test credentials and successful OAuth2 connection remain intact.',
      fr: 'La progression du test d’acceptation sera remise à zéro. La '
          'production est désactivée et l’environnement de test Chiron est '
          'réactivé. Vos identifiants de test et votre connexion OAuth2 '
          'réussie sont conservés.',
      es: 'El progreso de la prueba de aceptación se restablece a cero. Se '
          'desactiva la producción y se reactiva el entorno de prueba de '
          'Chiron. Sus credenciales de prueba y la conexión OAuth2 exitosa '
          'se mantienen.',
    );
    final preconditionText = _t(
      nl: 'Om een nieuwe Chiron-acceptatietest te starten, wordt productie '
          'uitgeschakeld en wordt de testomgeving opnieuw geactiveerd.',
      en: 'To start a new Chiron acceptance test, production is disabled and '
          'the test environment is re-activated.',
      fr: 'Pour lancer un nouveau test d’acceptation Chiron, la production '
          'est désactivée et l’environnement de test est réactivé.',
      es: 'Para iniciar una nueva prueba de aceptación de Chiron, se '
          'desactiva la producción y se reactiva el entorno de prueba.',
    );
    final cancelLabel = _t(
      nl: 'Annuleren',
      en: 'Cancel',
      fr: 'Annuler',
      es: 'Cancelar',
    );
    final resetLabel = _t(
      nl: 'Testflow resetten',
      en: 'Reset testflow',
      fr: 'Réinitialiser le flux de test',
      es: 'Reiniciar flujo de prueba',
    );
    final busyLabel = _t(
      nl: 'Bezig met resetten…',
      en: 'Resetting…',
      fr: 'Réinitialisation…',
      es: 'Reiniciando…',
    );
    final errorLabel = _errorCode == null
        ? null
        : _t(
            nl: 'Testflow resetten is niet gelukt. '
                'De backend gaf: ${_errorCode!}. '
                'Probeer het opnieuw of neem contact op met support.',
            en: 'The testflow could not be reset. Backend reported: '
                '${_errorCode!}. Please try again or contact support.',
            fr: 'La réinitialisation du flux de test a échoué. Le backend a '
                'répondu : ${_errorCode!}. Réessayez ou contactez le support.',
            es: 'No se pudo reiniciar el flujo de prueba. El backend '
                'respondió: ${_errorCode!}. Vuelve a intentarlo o contacta '
                'con soporte.',
          );

    // Fully opaque surface — matches Fluxidi card treatment across the app so
    // the dialog reads as first-class UI in both light (cleanProfessional)
    // and dark (executive/steel) variants, and no lavender/lightgrey shows
    // through under any theme.
    final surface = tokens.card;
    final borderColor = tokens.border;
    final titleColor = tokens.textPrimary;
    final bodyColor = tokens.textSecondary;
    final subduedColor = tokens.textMuted;
    final warningColor = tokens.warning;
    final warningBg = tokens.warningSoft;
    final dangerColor = tokens.danger;
    final dangerBg = tokens.dangerSoft;

    // Primary button is filled with the accent color and uses
    // `palette.textOnAccent` — the per-theme foreground colour explicitly
    // curated by each business palette for accent backgrounds. This keeps
    // the button legible on every theme (dark accent-on-black, light accent-
    // on-white, neon accent-on-purple, etc.) at ≥ 3:1 (WCAG AA large-text
    // threshold, satisfied by our 14 sp bold label) instead of the fragile
    // "accent vs background" pair we would otherwise fall back to.
    final primaryFg = tokens.palette.textOnAccent;
    final primaryBg = tokens.accent;

    return Dialog(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        // Scroll the body when the precondition banner + error banner + long
        // localized text push the dialog past the available viewport height
        // (e.g. small phone landscape). The action buttons live INSIDE the
        // scrollable so they always remain reachable — Material treats a
        // scrollable dialog as accessible, which is what we want here.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                body,
                style: TextStyle(
                  fontSize: 14,
                  color: bodyColor,
                  height: 1.35,
                ),
              ),
              if (widget.productionActive) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: warningBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: warningColor.withOpacity(0.55),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 20,
                        color: warningColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          preconditionText,
                          style: TextStyle(
                            fontSize: 13,
                            color: titleColor,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (errorLabel != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: dangerBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: dangerColor.withOpacity(0.55)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 20,
                        color: dangerColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          errorLabel,
                          style: TextStyle(
                            fontSize: 13,
                            color: titleColor,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (_busy) ...[
                Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: primaryBg,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      busyLabel,
                      style: TextStyle(
                        color: subduedColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              // Wrap keeps the action row from overflowing on narrower
              // dialog widths (phone landscape, small tablet portrait). Both
              // touch targets stay at 44 dp tall which is Material's minimum
              // recommendation for accessible tap size.
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _busy ? null : _cancel,
                    style: TextButton.styleFrom(
                      foregroundColor: titleColor,
                      minimumSize: const Size(88, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(cancelLabel),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _confirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryBg,
                      foregroundColor: primaryFg,
                      disabledBackgroundColor: primaryBg.withOpacity(0.55),
                      disabledForegroundColor: primaryFg.withOpacity(0.7),
                      minimumSize: const Size(140, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(resetLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _ChironTestAccessCard extends StatefulWidget {
  const _ChironTestAccessCard({required this.lang});

  final AppLanguage lang;

  @override
  State<_ChironTestAccessCard> createState() => _ChironTestAccessCardState();
}

class _ChironTestAccessCardState extends State<_ChironTestAccessCard> {
  final TextEditingController _apiTokenController = TextEditingController();
  // Chiron Connect 4A: OAuth2 client credentials inputs (test/ACC).
  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _clientSecretController = TextEditingController();
  String _selectedAuthScheme =
      ChironCredentialAuthScheme.authSchemeOAuthClientCredentials;
  bool _loadingStatus = false;
  bool _saving = false;
  bool _testing = false;
  bool _clearingTestCredentials = false;
  String? _actionError;
  _ChironMockConnectionTestResult? _lastMockTest;
  _ChironPersistedInternalTestStatus? _persistedInternalTest;
  // Chiron Connect 4C: acceptance testflow progress (5 departures + 5 arrivals).
  _ChironTestflowProgress? _testflowProgress;
  String _lastConnectionStatus = 'never_tested';
  bool _resettingTestflow = false;
  bool _editingTestCredentials = false;
  late final ChironContextLoadCoordinator _loadCoordinator;

  @override
  void initState() {
    super.initState();
    _apiTokenController.addListener(_onCredentialFieldChanged);
    _clientIdController.addListener(_onCredentialFieldChanged);
    _clientSecretController.addListener(_onCredentialFieldChanged);
    _loadCoordinator = ChironContextLoadCoordinator(
      listenables: <Listenable>[
        activeCompanySessionNotifier,
        companyProfileNotifier,
      ],
      hasCompanySession: () => hasCompanyOwnerAuthContext(),
      companyId: () {
        final profile = companyProfileNotifier.value?.companyId.trim() ?? '';
        if (profile.isNotEmpty) return profile;
        return activeCompanySessionNotifier.value?.companyId.trim() ?? '';
      },
      runLoad: _performStatusLoad,
      onDiag: (stage) => debugPrint('[CHIRON_LOAD][DIAG] stage=$stage'),
    )..attach();
  }

  void _onCredentialFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _loadCoordinator.dispose();
    _apiTokenController.removeListener(_onCredentialFieldChanged);
    _clientIdController.removeListener(_onCredentialFieldChanged);
    _clientSecretController.removeListener(_onCredentialFieldChanged);
    _apiTokenController.dispose();
    _clientIdController.dispose();
    _clientSecretController.dispose();
    super.dispose();
  }

  AppLanguage get lang => widget.lang;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return en;
    }
  }

  ({String tenantId, String companyId})? _effectiveTenantCompanyIds() {
    final activeCompanyId =
        companyProfileNotifier.value?.companyId.trim() ?? '';
    if (activeCompanyId.isNotEmpty) {
      return (tenantId: activeCompanyId, companyId: activeCompanyId);
    }
    final sessionCompanyId =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (sessionCompanyId.isNotEmpty) {
      return (tenantId: sessionCompanyId, companyId: sessionCompanyId);
    }
    return null;
  }

  String _localizedApiError(String? code) {
    switch ((code ?? '').trim().toLowerCase()) {
      case 'missing_scope':
        return _t(
          nl: 'Bedrijfsscope ontbreekt.',
          en: 'Company scope is missing.',
          fr: 'Le périmètre entreprise est manquant.',
          es: 'Falta el ámbito de empresa.',
        );
      case 'missing_test_credentials':
        return _t(
          nl: 'Sla eerst testgegevens op.',
          en: 'Save test credentials first.',
          fr: 'Enregistrez d’abord les identifiants de test.',
          es: 'Guarda primero las credenciales de prueba.',
        );
      case 'production_connection_test_not_supported':
        return _t(
          nl: 'Productietest wordt nog niet ondersteund.',
          en: 'Production connection test is not supported yet.',
          fr: 'Le test de connexion en production n’est pas encore pris en charge.',
          es: 'La prueba de conexión de producción aún no está disponible.',
        );
      case 'forbidden_fields':
        return _t(
          nl: 'Ongeldige velden in het verzoek.',
          en: 'Invalid fields in the request.',
          fr: 'Champs non valides dans la requête.',
          es: 'Campos no válidos en la solicitud.',
        );
      case 'credential_encrypt_failed':
      case 'credential_decrypt_failed':
      case 'invalid_credential_payload':
      case 'invalid_api_token':
      case 'missing_api_token':
        return _t(
          nl: 'Testgegevens konden niet veilig verwerkt worden.',
          en: 'Test credentials could not be processed securely.',
          fr: 'Les identifiants de test n’ont pas pu être traités en toute sécurité.',
          es: 'No se pudieron procesar las credenciales de prueba de forma segura.',
        );
      default:
        return _t(
          nl: 'Actie mislukt. Probeer opnieuw.',
          en: 'Action failed. Please try again.',
          fr: 'Action échouée. Veuillez réessayer.',
          es: 'La acción falló. Inténtalo de nuevo.',
        );
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _chironDanger : null,
      ),
    );
  }

  String _releaseSafeWorkerError({String? code, String? sanitizedDetail}) {
    if (kReleaseMode) {
      return _localizedApiError(code);
    }
    final detail = sanitizedDetail?.trim() ?? '';
    if (detail.isNotEmpty) return detail;
    return _localizedApiError(code);
  }

  Future<void> _performStatusLoad(int gen) async {
    final scope = _effectiveTenantCompanyIds();
    if (scope == null) return;
    if (_loadCoordinator.shouldApplyGeneration(gen) && mounted) {
      setState(() {
        _loadingStatus = true;
        _actionError = null;
      });
    }
    try {
      final fetched = await _fetchChironTestAccessBackendStatus(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!_loadCoordinator.shouldApplyGeneration(gen) || !mounted) return;
      _publishChironDashboardStatusFetch(
        status: fetched.status,
        internalTest: fetched.internalTest,
      );
      setState(() {
        _testflowProgress = fetched.testflow;
        _lastConnectionStatus = fetched.status.lastConnectionStatus;
        if (fetched.status.testCredentialsStored) {
          _persistedInternalTest = fetched.internalTest;
          if (!_editingTestCredentials) {
            _apiTokenController.clear();
            _clientIdController.clear();
            _clientSecretController.clear();
          }
        } else {
          _persistedInternalTest = null;
          _lastMockTest = null;
          _editingTestCredentials = true;
        }
      });
    } catch (_) {
      if (!_loadCoordinator.shouldApplyGeneration(gen) || !mounted) return;
      setState(() {
        _actionError = _t(
          nl: 'Status kon niet geladen worden.',
          en: 'Status could not be loaded.',
          fr: 'Le statut n’a pas pu être chargé.',
          es: 'No se pudo cargar el estado.',
        );
      });
    } finally {
      if (_loadCoordinator.shouldApplyGeneration(gen) && mounted) {
        setState(() => _loadingStatus = false);
      }
    }
  }

  Future<void> _refreshStatus() async {
    _loadCoordinator.requestManualRefresh();
  }

  bool get _isOAuthSchemeSelected =>
      _selectedAuthScheme ==
      ChironCredentialAuthScheme.authSchemeOAuthClientCredentials;

  bool get _canSaveCredentials {
    final credentialsStored =
        backendChironConnectionStatusNotifier.value?.testCredentialsStored ??
        false;
    if (credentialsStored && !_editingTestCredentials) return false;
    if (_isOAuthSchemeSelected) {
      return _clientIdController.text.trim().isNotEmpty &&
          _clientSecretController.text.trim().isNotEmpty;
    }
    return _apiTokenController.text.trim().isNotEmpty;
  }

  Future<void> _saveTestCredentials() async {
    final scope = _effectiveTenantCompanyIds();
    if (scope == null) return;

    final isOAuth = _isOAuthSchemeSelected;
    final apiToken = _apiTokenController.text.trim();
    final clientId = _clientIdController.text.trim();
    final clientSecret = _clientSecretController.text.trim();

    if (isOAuth) {
      if (clientId.isEmpty || clientSecret.isEmpty) return;
    } else {
      if (apiToken.isEmpty) return;
    }

    setState(() {
      _saving = true;
      _actionError = null;
    });
    try {
      if (isOAuth) {
        await _saveChironOAuthClientCredentialsViaBooking(
          tenantId: scope.tenantId,
          companyId: scope.companyId,
          clientId: clientId,
          clientSecret: clientSecret,
        );
      } else {
        await _saveChironTestCredentialsViaBooking(
          tenantId: scope.tenantId,
          companyId: scope.companyId,
          apiToken: apiToken,
        );
      }
      // Screenshot safety: never retain credential material in text controllers
      // after save.
      _apiTokenController.clear();
      _clientIdController.clear();
      _clientSecretController.clear();
      _editingTestCredentials = false;
      await _refreshStatus();
      if (!mounted) return;
      _showSnack(
        _t(
          nl: 'Testgegevens opgeslagen.',
          en: 'Test credentials saved.',
          fr: 'Identifiants de test enregistrés.',
          es: 'Credenciales de prueba guardadas.',
        ),
      );
    } on BackendChironConnectionApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _actionError = _releaseSafeWorkerError(code: e.error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _actionError = _releaseSafeWorkerError(code: 'network_error');
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _testConnection() async {
    final scope = _effectiveTenantCompanyIds();
    if (scope == null) return;

    setState(() {
      _testing = true;
      _actionError = null;
    });
    try {
      final result = await _runChironMockConnectionTestViaBooking(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return;
      if (!result.ok) {
        // Chiron Connect 4B: a failed live OAuth2 exchange returns a sanitized
        // error string from the backend; surface it without ever showing
        // tokens or secrets. Fallback to localized error code otherwise.
        final sanitized = result.sanitizedError?.trim() ?? '';
        setState(() {
          _actionError = _releaseSafeWorkerError(
            code: result.errorCode,
            sanitizedDetail: result.isOAuthScheme ? sanitized : null,
          );
        });
        return;
      }
      setState(() {
        _lastMockTest = result;
      });
      await _refreshStatus();
      if (!mounted) return;
      // Chiron Connect 4B: success copy depends on whether the backend really
      // performed an external OAuth2 token exchange (oauth_client_credentials)
      // or merely the legacy mock-only credential roundtrip (api_token). The
      // access token itself is never shown.
      final showOAuthSuccess =
          result.isOAuthScheme && result.accessTokenObtained;
      _showSnack(
        showOAuthSuccess
            ? _t(
                nl: 'OAuth2-test geslaagd. Access token ontvangen.',
                en: 'OAuth2 test passed. Access token received.',
                fr: 'Test OAuth2 réussi. Jeton d’accès reçu.',
                es: 'Prueba OAuth2 superada. Token de acceso recibido.',
              )
            : _t(
                nl: 'Interne test geslaagd.',
                en: 'Internal test passed.',
                fr: 'Test interne réussi.',
                es: 'Prueba interna superada.',
              ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _actionError = _releaseSafeWorkerError(code: 'network_error');
      });
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  Future<bool> _confirmClearTestCredentials() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _chironPanel,
          title: Text(
            _t(
              nl: 'Testgegevens verwijderen?',
              en: 'Remove test credentials?',
              fr: 'Supprimer les identifiants de test ?',
              es: '¿Eliminar credenciales de prueba?',
            ),
            style: TextStyle(color: _chironTextPrimary),
          ),
          content: Text(
            _t(
              nl: 'De opgeslagen Chiron testgegevens worden veilig verwijderd. De interne teststatus wordt ook gewist. Officiële Chiron-instellingen en productie blijven onaangeraakt.',
              en: 'The saved Chiron test credentials will be securely removed. The internal test status will also be cleared. Official Chiron settings and production remain unchanged.',
              fr: 'Les identifiants de test Chiron enregistrés seront supprimés en toute sécurité. Le statut de test interne sera également effacé. Les paramètres Chiron officiels et la production restent inchangés.',
              es: 'Las credenciales de prueba de Chiron guardadas se eliminarán de forma segura. El estado de prueba interno también se borrará. La configuración oficial de Chiron y la producción no se modifican.',
            ),
            style: TextStyle(color: _chironTextSecondary, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: _chironTextSecondary,
              ),
              child: Text(
                _t(
                  nl: 'Annuleren',
                  en: 'Cancel',
                  fr: 'Annuler',
                  es: 'Cancelar',
                ),
              ),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: OutlinedButton.styleFrom(
                foregroundColor: _chironDanger,
                side: BorderSide(color: _chironDanger.withOpacity(0.55)),
              ),
              child: Text(
                _t(
                  nl: 'Verwijderen',
                  en: 'Remove',
                  fr: 'Supprimer',
                  es: 'Eliminar',
                ),
              ),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _clearTestCredentials() async {
    final scope = _effectiveTenantCompanyIds();
    if (scope == null) return;

    final confirmed = await _confirmClearTestCredentials();
    if (!confirmed || !mounted) return;

    setState(() {
      _clearingTestCredentials = true;
      _actionError = null;
    });
    try {
      await _clearChironTestCredentialsViaBooking(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      _apiTokenController.clear();
      _clientIdController.clear();
      _clientSecretController.clear();
      if (!mounted) return;
      setState(() {
        _lastMockTest = null;
        _persistedInternalTest = null;
        _editingTestCredentials = true;
      });
      await _refreshStatus();
      if (!mounted) return;
      _showSnack(
        _t(
          nl: 'Chiron testgegevens verwijderd.',
          en: 'Chiron test credentials removed.',
          fr: 'Identifiants de test Chiron supprimés.',
          es: 'Credenciales de prueba de Chiron eliminadas.',
        ),
      );
    } on BackendChironConnectionApiException catch (_) {
      if (!mounted) return;
      _showSnack(
        _t(
          nl: 'Testgegevens verwijderen is niet gelukt.',
          en: 'Could not remove test credentials.',
          fr: 'Impossible de supprimer les identifiants de test.',
          es: 'No se pudieron eliminar las credenciales de prueba.',
        ),
        isError: true,
      );
    } catch (_) {
      if (!mounted) return;
      _showSnack(
        _t(
          nl: 'Testgegevens verwijderen is niet gelukt.',
          en: 'Could not remove test credentials.',
          fr: 'Impossible de supprimer les identifiants de test.',
          es: 'No se pudieron eliminar las credenciales de prueba.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _clearingTestCredentials = false);
      }
    }
  }

  Future<void> _resetTestflow() async {
    final scope = _effectiveTenantCompanyIds();
    if (scope == null) return;
    if (_resettingTestflow) return;

    // RELEASE-P0-CHIRON-RESET-UX-2026-07-31: the dialog owns its own busy /
    // error state and drives the network call itself. That way a double tap
    // on "Testflow resetten" inside the dialog is guaranteed to produce only
    // one backend request (the button is disabled the moment the request
    // starts). The parent tracks `_resettingTestflow` so the outer
    // OutlinedButton on the compliance card is also disabled for the whole
    // duration.
    setState(() => _resettingTestflow = true);
    try {
      final progress = await showChironTestflowResetDialog(
        context: context,
        lang: lang,
        productionActive:
            backendChironConnectionStatusNotifier.value?.productionEnabled ??
                false,
        onReset: () async {
          return _resetChironTestflowViaBooking(
            tenantId: scope.tenantId,
            companyId: scope.companyId,
          );
        },
      );
      if (!mounted) return;
      if (progress != null) {
        setState(() => _testflowProgress = progress);
        // Refresh from the server so `backendChironConnectionStatusNotifier`,
        // `_persistedInternalTest`, and every derived chip on the page
        // reflect the fresh reset state. This is the ONLY place the parent
        // trusts the outcome; a failed reset never mutates the local UI.
        await _refreshStatus();
        if (!mounted) return;
        _showSnack(
          _t(
            nl: 'Acceptatietest opnieuw gestart.',
            en: 'Acceptance test reset.',
            fr: 'Test d’acceptation réinitialisé.',
            es: 'Prueba de aceptación reiniciada.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _resettingTestflow = false);
      }
    }
  }

  Widget _statusChip({
    required String label,
    required bool active,
    Color? activeColor,
  }) {
    final color = active ? (activeColor ?? _chironSuccess) : _chironTextMuted;
    final background = active ? color.withOpacity(0.16) : _chironPanel;
    final border = active ? color.withOpacity(0.55) : _chironBorder;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = _effectiveTenantCompanyIds();
    if (scope == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _chironPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _chironBorder),
        ),
        child: Text(
          _t(
            nl: 'Selecteer eerst een bedrijf om Chiron-testtoegang te beheren.',
            en: 'Select a company first to manage Chiron test access.',
            fr: 'Sélectionnez d’abord une entreprise pour gérer l’accès de test Chiron.',
            es: 'Selecciona primero una empresa para gestionar el acceso de prueba Chiron.',
          ),
          style: TextStyle(color: _chironTextMuted, fontSize: 12),
        ),
      );
    }

    return ValueListenableBuilder<BackendChironConnectionStatus?>(
      valueListenable: backendChironConnectionStatusNotifier,
      builder: (context, backendStatus, _) {
        final testCredentialsStored =
            backendStatus?.testCredentialsStored ?? false;
        final productionEnabled = backendStatus?.productionEnabled ?? false;
        final connectionPassed =
            _lastConnectionStatus.trim().toLowerCase() == 'test_passed';
        final persistedInternalPassed =
            testCredentialsStored &&
            (_persistedInternalTest?.isPassed ?? false);
        final sessionMockPassed =
            testCredentialsStored &&
            _lastMockTest?.credentialDecryptOk == true &&
            _lastMockTest?.credentialPayloadValid == true;
        final mockTestPassed = persistedInternalPassed || sessionMockPassed;
        final showCredentialEditor =
            !testCredentialsStored || _editingTestCredentials;
        final lastInternalCheckLabel = testCredentialsStored
            ? _formatChironInternalTestTimestamp(_persistedInternalTest?.lastAt)
            : null;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _chironPanel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _chironBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(
                  nl: 'Testgegevens & acceptatie',
                  en: 'Test credentials & acceptance',
                  fr: 'Identifiants de test et acceptation',
                  es: 'Credenciales de prueba y aceptación',
                ),
                style: TextStyle(
                  color: _chironGold,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _t(
                  nl: 'Als bedrijfsbeheerder controleert u hier de Chiron ACC/test-verbinding van uw onderneming.',
                  en: 'As company administrator, verify your company’s Chiron ACC/test connection here.',
                  fr: 'En tant qu’administrateur d’entreprise, vérifiez ici la connexion Chiron ACC/test de votre société.',
                  es: 'Como administrador de empresa, verifique aquí la conexión Chiron ACC/test de su compañía.',
                ),
                style: TextStyle(
                  color: _chironTextMuted,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                testCredentialsStored && connectionPassed
                    ? _t(
                        nl: 'Uw testgegevens zijn veilig opgeslagen. Fluxidi kan verbinden met Chiron ACC/test.',
                        en: 'Your test credentials are stored securely. Fluxidi can connect to Chiron ACC/test.',
                        fr: 'Vos identifiants de test sont enregistrés en sécurité. Fluxidi peut se connecter à Chiron ACC/test.',
                        es: 'Sus credenciales de prueba están guardadas de forma segura. Fluxidi puede conectar con Chiron ACC/test.',
                      )
                    : testCredentialsStored
                    ? _t(
                        nl: 'Uw testgegevens zijn veilig opgeslagen. Test de verbinding met Chiron ACC/test.',
                        en: 'Your test credentials are stored securely. Test the connection to Chiron ACC/test.',
                        fr: 'Vos identifiants de test sont enregistrés en sécurité. Testez la connexion à Chiron ACC/test.',
                        es: 'Sus credenciales de prueba están guardadas de forma segura. Pruebe la conexión con Chiron ACC/test.',
                      )
                    : _t(
                        nl: 'Voer de Chiron-testgegevens in en test de verbinding met Chiron ACC/test.',
                        en: 'Enter the Chiron test credentials and test the connection to Chiron ACC/test.',
                        fr: 'Saisissez les identifiants de test Chiron et testez la connexion à Chiron ACC/test.',
                        es: 'Introduzca las credenciales de prueba Chiron y pruebe la conexión con Chiron ACC/test.',
                      ),
                style: TextStyle(
                  color: _chironTextSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (testCredentialsStored)
                    _statusChip(
                      label: _t(
                        nl: 'Testgegevens opgeslagen',
                        en: 'Test credentials stored',
                        fr: 'Identifiants de test enregistrés',
                        es: 'Credenciales de prueba guardadas',
                      ),
                      active: true,
                    ),
                  if (mockTestPassed)
                    _statusChip(
                      label: _t(
                        nl: 'OAuth2-test geslaagd',
                        en: 'OAuth2 test passed',
                        fr: 'Test OAuth2 réussi',
                        es: 'Prueba OAuth2 superada',
                      ),
                      active: true,
                    ),
                  _statusChip(
                    // RELEASE-P0-CHIRON-RESET-UX-2026-07-31: when production
                    // is off AND the backend reports the test environment,
                    // surface an explicit "Testomgeving actief" label so a
                    // just-completed reset is visually unambiguous — a bare
                    // "Productie geblokkeerd" chip did not communicate that
                    // the acceptance test is now the active target.
                    label: productionEnabled
                        ? _t(
                            nl: 'Productie actief',
                            en: 'Production active',
                            fr: 'Production active',
                            es: 'Producción activa',
                          )
                        : (backendStatus?.environment ==
                                ChironConnectionEnvironment.test
                            ? _t(
                                nl: 'Testomgeving actief',
                                en: 'Test environment active',
                                fr: 'Environnement de test actif',
                                es: 'Entorno de prueba activo',
                              )
                            : _t(
                                nl: 'Productie geblokkeerd',
                                en: 'Production blocked',
                                fr: 'Production bloquée',
                                es: 'Producción bloqueada',
                              )),
                    active: true,
                    activeColor: productionEnabled
                        ? _chironSuccess
                        : _chironGold,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed:
                        _testing ||
                            _clearingTestCredentials ||
                            !testCredentialsStored
                        ? null
                        : _testConnection,
                    style: _chironTestAccessSecondaryButtonStyle(),
                    child: _testing
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _chironGold,
                            ),
                          )
                        : Text(
                            _t(
                              nl: 'Test verbinding',
                              en: 'Test connection',
                              fr: 'Tester la connexion',
                              es: 'Probar conexión',
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                  ),
                  if (testCredentialsStored)
                    OutlinedButton.icon(
                      onPressed: _saving || _testing || _clearingTestCredentials
                          ? null
                          : () {
                              setState(() {
                                _editingTestCredentials = true;
                                _apiTokenController.clear();
                                _clientIdController.clear();
                                _clientSecretController.clear();
                                _actionError = null;
                              });
                            },
                      style: _chironTestAccessSecondaryButtonStyle(),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: Text(
                        _t(
                          nl: 'Testgegevens vervangen',
                          en: 'Replace test credentials',
                          fr: 'Remplacer les identifiants de test',
                          es: 'Sustituir credenciales de prueba',
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
              if (!_loadCoordinator.prerequisitesReady) ...[
                const SizedBox(height: 10),
                Text(
                  _t(
                    nl: 'Bedrijfscontext wordt geladen…',
                    en: 'Loading company context…',
                    fr: 'Chargement du contexte entreprise…',
                    es: 'Cargando contexto de empresa…',
                  ),
                  style: TextStyle(color: _chironTextMuted, fontSize: 11),
                ),
              ],
              if (_loadingStatus) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _chironGold,
                  ),
                ),
              ],
              if (testCredentialsStored && mockTestPassed) ...[
                if (persistedInternalPassed &&
                    lastInternalCheckLabel != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _t(
                      nl: 'Laatste interne controle: $lastInternalCheckLabel',
                      en: 'Last internal check: $lastInternalCheckLabel',
                      fr: 'Dernier contrôle interne : $lastInternalCheckLabel',
                      es: 'Último control interno: $lastInternalCheckLabel',
                    ),
                    style: TextStyle(color: _chironTextMuted, fontSize: 11),
                  ),
                ],
              ],
              if (testCredentialsStored && showCredentialEditor) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _saving || _testing || _clearingTestCredentials
                          ? null
                          : _clearTestCredentials,
                      style: _chironTestAccessDangerButtonStyle(),
                      icon: _clearingTestCredentials
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _chironDanger,
                              ),
                            )
                          : const Icon(Icons.delete_outline, size: 16),
                      label: Text(
                        _t(
                          nl: 'Testgegevens verwijderen',
                          en: 'Remove test credentials',
                          fr: 'Supprimer les identifiants de test',
                          es: 'Eliminar credenciales de prueba',
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: _saving || _testing || _clearingTestCredentials
                          ? null
                          : () {
                              setState(() {
                                _editingTestCredentials = false;
                                _apiTokenController.clear();
                                _clientIdController.clear();
                                _clientSecretController.clear();
                                _actionError = null;
                              });
                            },
                      child: Text(
                        _t(
                          nl: 'Annuleren',
                          en: 'Cancel',
                          fr: 'Annuler',
                          es: 'Cancelar',
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
              if (_actionError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _actionError!,
                  style: TextStyle(color: _chironDanger, fontSize: 12),
                ),
              ],
              const SizedBox(height: 10),
              if (showCredentialEditor) ...[
                // Chiron Connect 4A: scheme chooser. OAuth2 client credentials
                // is the recommended default; legacy API token stays available.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(
                        _t(
                          nl: 'OAuth2 (aanbevolen)',
                          en: 'OAuth2 (recommended)',
                          fr: 'OAuth2 (recommandé)',
                          es: 'OAuth2 (recomendado)',
                        ),
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: _isOAuthSchemeSelected,
                      onSelected:
                          (_saving || _testing || _clearingTestCredentials)
                          ? null
                          : (selected) {
                              if (!selected) return;
                              setState(() {
                                _selectedAuthScheme = ChironCredentialAuthScheme
                                    .authSchemeOAuthClientCredentials;
                                _apiTokenController.clear();
                                _actionError = null;
                              });
                            },
                    ),
                    ChoiceChip(
                      label: Text(
                        _t(
                          nl: 'Legacy API-token',
                          en: 'Legacy API token',
                          fr: 'Jeton API hérité',
                          es: 'Token API heredado',
                        ),
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: !_isOAuthSchemeSelected,
                      onSelected:
                          (_saving || _testing || _clearingTestCredentials)
                          ? null
                          : (selected) {
                              if (!selected) return;
                              setState(() {
                                _selectedAuthScheme = ChironCredentialAuthScheme
                                    .authSchemeApiToken;
                                _clientIdController.clear();
                                _clientSecretController.clear();
                                _actionError = null;
                              });
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _t(
                    nl: 'Gebruik de test/ACC-gegevens uit het Chiron-portaal. Productie blijft geblokkeerd tot de testflow geslaagd is.',
                    en: 'Use the test/ACC details from the Chiron portal. Production stays blocked until the test flow has passed.',
                    fr: 'Utilisez les données test/ACC du portail Chiron. La production reste bloquée tant que le test n’est pas réussi.',
                    es: 'Usa los datos de test/ACC del portal de Chiron. La producción permanece bloqueada hasta que la prueba se complete.',
                  ),
                  style: TextStyle(
                    color: _chironTextMuted,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                if (_isOAuthSchemeSelected) ...[
                  TextField(
                    controller: _clientIdController,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: _t(
                        nl: 'Test Client ID',
                        en: 'Test Client ID',
                        fr: 'Client ID test',
                        es: 'Client ID de prueba',
                      ),
                      helperText: testCredentialsStored
                          ? _t(
                              nl: 'Vul opnieuw in om de opgeslagen Client ID te vervangen.',
                              en: 'Enter again to replace the stored Client ID.',
                              fr: 'Saisissez à nouveau pour remplacer le Client ID enregistré.',
                              es: 'Introduzca de nuevo para sustituir el Client ID guardado.',
                            )
                          : null,
                      labelStyle: TextStyle(
                        color: _chironTextMuted,
                        fontSize: 12,
                      ),
                      helperStyle: TextStyle(
                        color: _chironTextMuted,
                        fontSize: 11,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _chironBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _chironGold),
                      ),
                    ),
                    style: TextStyle(color: _chironTextPrimary, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _clientSecretController,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: _t(
                        nl: 'Test Client Secret',
                        en: 'Test Client Secret',
                        fr: 'Client Secret test',
                        es: 'Client Secret de prueba',
                      ),
                      helperText: testCredentialsStored
                          ? _t(
                              nl: 'Secret wordt nooit opnieuw getoond. Vul opnieuw in om te vervangen.',
                              en: 'The secret is never shown again. Enter again to replace it.',
                              fr: 'Le secret n’est jamais réaffiché. Saisissez à nouveau pour le remplacer.',
                              es: 'El secret nunca se vuelve a mostrar. Introdúzcalo de nuevo para sustituirlo.',
                            )
                          : null,
                      labelStyle: TextStyle(
                        color: _chironTextMuted,
                        fontSize: 12,
                      ),
                      helperStyle: TextStyle(
                        color: _chironTextMuted,
                        fontSize: 11,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _chironBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _chironGold),
                      ),
                    ),
                    style: TextStyle(color: _chironTextPrimary, fontSize: 13),
                  ),
                ] else ...[
                  TextField(
                    controller: _apiTokenController,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: _t(
                        nl: 'Chiron API-token',
                        en: 'Chiron API token',
                        fr: 'Jeton API Chiron',
                        es: 'Token API Chiron',
                      ),
                      helperText: testCredentialsStored
                          ? _t(
                              nl: 'Token wordt nooit opnieuw getoond. Vul opnieuw in om te vervangen.',
                              en: 'The token is never shown again. Enter again to replace it.',
                              fr: 'Le jeton n’est jamais réaffiché. Saisissez à nouveau pour le remplacer.',
                              es: 'El token nunca se vuelve a mostrar. Introdúzcalo de nuevo para sustituirlo.',
                            )
                          : null,
                      labelStyle: TextStyle(
                        color: _chironTextMuted,
                        fontSize: 12,
                      ),
                      helperStyle: TextStyle(
                        color: _chironTextMuted,
                        fontSize: 11,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _chironBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _chironGold),
                      ),
                    ),
                    style: TextStyle(color: _chironTextPrimary, fontSize: 13),
                  ),
                ],
              ] else ...[
                const SizedBox(height: 2),
                Text(
                  _t(
                    nl: 'Voor screenshots worden opgeslagen Chiron-credentials standaard verborgen. Kies “Testgegevens vervangen” om nieuwe waarden in te voeren.',
                    en: 'For screenshots, stored Chiron credentials are hidden by default. Choose “Replace test credentials” to enter new values.',
                    fr: 'Pour les captures d’écran, les identifiants Chiron enregistrés sont masqués par défaut. Choisissez « Remplacer » pour saisir de nouvelles valeurs.',
                    es: 'Para capturas de pantalla, las credenciales Chiron guardadas se ocultan por defecto. Elija “Sustituir” para introducir nuevos valores.',
                  ),
                  style: TextStyle(
                    color: _chironTextMuted,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
              if (showCredentialEditor) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed:
                          _saving ||
                              _testing ||
                              _clearingTestCredentials ||
                              !_canSaveCredentials
                          ? null
                          : _saveTestCredentials,
                      style: _chironTestAccessSecondaryButtonStyle(),
                      child: _saving
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _chironGold,
                              ),
                            )
                          : Text(
                              _t(
                                nl: 'Testgegevens opslaan',
                                en: 'Save test credentials',
                                fr: 'Enregistrer les identifiants de test',
                                es: 'Guardar credenciales de prueba',
                              ),
                              style: const TextStyle(fontSize: 12),
                            ),
                    ),
                  ],
                ),
              ],
              _buildTestflowProgressSection(),
            ],
          ),
        );
      },
    );
  }

  // Chiron Connect 4C: compact acceptance-testflow progress (5 departures +
  // 5 arrivals = 10 messages) plus a reset action. No production unlock here.
  Widget _buildTestflowProgressSection() {
    final progress = _testflowProgress ?? const _ChironTestflowProgress();
    final connectionPassed =
        _lastConnectionStatus.trim().toLowerCase() == 'test_passed';

    String statusLabel;
    Color statusColor;
    if (progress.isComplete) {
      statusLabel = _t(
        nl: 'Voltooid',
        en: 'Complete',
        fr: 'Terminé',
        es: 'Completado',
      );
      statusColor = _chironSuccess;
    } else if (progress.isInProgress) {
      statusLabel = _t(
        nl: 'Bezig',
        en: 'In progress',
        fr: 'En cours',
        es: 'En curso',
      );
      statusColor = _chironGold;
    } else {
      statusLabel = _t(
        nl: 'Nog niet gestart',
        en: 'Not started',
        fr: 'Pas encore commencé',
        es: 'Aún no iniciada',
      );
      statusColor = _chironTextMuted;
    }

    Widget line(String label, int sent, int required) {
      final met = sent >= required;
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 12, color: _chironTextMuted),
              ),
            ),
            Text(
              '$sent/$required',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: met ? _chironSuccess : _chironTextPrimary,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _chironPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _chironBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _t(
                    nl: 'Acceptatietest',
                    en: 'Acceptance test',
                    fr: 'Test d’acceptation',
                    es: 'Prueba de aceptación',
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _chironTextPrimary,
                  ),
                ),
              ),
              _statusChip(
                label: statusLabel,
                active: progress.isComplete || progress.isInProgress,
                activeColor: statusColor,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              nl: 'Voor productie zijn 5 vertrek- en 5 aankomstberichten nodig.',
              en: 'Production requires 5 departure and 5 arrival messages.',
              fr: 'La production nécessite 5 messages de départ et 5 d’arrivée.',
              es: 'La producción requiere 5 mensajes de salida y 5 de llegada.',
            ),
            style: TextStyle(fontSize: 12, color: _chironTextMuted),
          ),
          const SizedBox(height: 8),
          line(
            _t(
              nl: 'Voortgang',
              en: 'Progress',
              fr: 'Progression',
              es: 'Progreso',
            ),
            progress.messagesSent,
            progress.messagesRequired,
          ),
          line(
            _t(nl: 'Vertrek', en: 'Departure', fr: 'Départ', es: 'Salida'),
            progress.departureSent,
            progress.departureRequired,
          ),
          line(
            _t(nl: 'Aankomst', en: 'Arrival', fr: 'Arrivée', es: 'Llegada'),
            progress.arrivalSent,
            progress.arrivalRequired,
          ),
          line(
            _t(
              nl: 'Ritten afgerond',
              en: 'Rides completed',
              fr: 'Trajets terminés',
              es: 'Viajes completados',
            ),
            progress.ridesCompleted,
            progress.ridesRequired,
          ),
          if (!connectionPassed) ...[
            const SizedBox(height: 8),
            Text(
              _t(
                nl: 'Test eerst de OAuth2-verbinding voordat de acceptatietest kan starten.',
                en: 'Test the OAuth2 connection first before the acceptance test can start.',
                fr: 'Testez d’abord la connexion OAuth2 avant de démarrer le test d’acceptation.',
                es: 'Prueba primero la conexión OAuth2 antes de iniciar la prueba de aceptación.',
              ),
              style: TextStyle(fontSize: 12, color: _chironGold),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            _t(
              nl: 'Productie pas na geslaagde OAuth2-test én volledige acceptatietest.',
              en: 'Production only after a passed OAuth2 test and a complete acceptance test.',
              fr: 'Production uniquement après un test OAuth2 réussi et un test d’acceptation complet.',
              es: 'Producción solo tras una prueba OAuth2 superada y una prueba de aceptación completa.',
            ),
            style: TextStyle(fontSize: 11, color: _chironTextMuted),
          ),
          const SizedBox(height: 8),
          /* CHIRON-P0-2A: destructive Chiron testflow reset is hidden in
           * release builds. Its underlying booking-worker proxy remains
           * available for tooling/support usage. */
          if (!kReleaseMode)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _resettingTestflow ? null : _resetTestflow,
                style: _chironTestAccessSecondaryButtonStyle(),
                child: _resettingTestflow
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _chironGold,
                        ),
                      )
                    : Text(
                        _t(
                          nl: 'Testflow resetten',
                          en: 'Reset testflow',
                          fr: 'Réinitialiser le flux de test',
                          es: 'Reiniciar flujo de prueba',
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChironScoreSummaryPanel extends StatefulWidget {
  const _ChironScoreSummaryPanel({required this.lang});

  final AppLanguage lang;

  @override
  State<_ChironScoreSummaryPanel> createState() =>
      _ChironScoreSummaryPanelState();
}

class _ChironScoreSummaryPanelState extends State<_ChironScoreSummaryPanel> {
  late Future<_ChironScoreSummaryResponse> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadScoreSummary();
  }

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (widget.lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return en;
    }
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  ({String tenantId, String companyId})? _effectiveTenantCompanyIds() {
    final activeCompanyId =
        companyProfileNotifier.value?.companyId.trim() ?? '';
    if (activeCompanyId.isNotEmpty) {
      return (tenantId: activeCompanyId, companyId: activeCompanyId);
    }
    final sessionCompanyId =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (sessionCompanyId.isNotEmpty) {
      return (tenantId: sessionCompanyId, companyId: sessionCompanyId);
    }
    return null;
  }

  Future<_ChironScoreSummaryResponse> _loadScoreSummary() async {
    final effective = _effectiveTenantCompanyIds();
    if (effective == null) {
      return _ChironScoreSummaryResponse.error(
        errorMessage: _t(
          nl: 'Chiron score-overzicht kon niet geladen worden.',
          en: 'Chiron score overview could not be loaded.',
          fr: 'L’aperçu du score Chiron n’a pas pu être chargé.',
          es: 'No se pudo cargar el resumen de puntuación de Chiron.',
        ),
      );
    }

    /* CHIRON-P0-2A: score summary routes through the booking worker with
     * the active company-owner session bearer. The direct compliance admin
     * bearer is no longer used or shipped in the client. */
    if (!hasCompanyOwnerAuthContext()) {
      return _ChironScoreSummaryResponse.error(
        tenantId: effective.tenantId,
        companyId: effective.companyId,
        errorMessage: _t(
          nl: 'Chiron score-overzicht kon niet geladen worden.',
          en: 'Chiron score overview could not be loaded.',
          fr: 'L’aperçu du score Chiron n’a pas pu être chargé.',
          es: 'No se pudo cargar el resumen de puntuación de Chiron.',
        ),
      );
    }

    final uri = _chironBookingReadonlyEndpoint(
      '/admin/chiron/score-summary',
      tenantId: effective.tenantId,
      companyId: effective.companyId,
    );
    final auth = await resolveCompanyOwnerAuthHeaders(json: false);

    try {
      final res = await http
          .get(uri, headers: auth.headers)
          .timeout(const Duration(seconds: 10));
      final contentType = (res.headers['content-type'] ?? '').toLowerCase();
      Map<String, dynamic> payload = const <String, dynamic>{};
      if (contentType.contains('application/json') && res.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map) {
            payload = Map<String, dynamic>.from(decoded);
          }
        } catch (err) {
          debugPrint(
            '[$_chironBookingWorkerProxyLogTag][SCORE_SUMMARY] json_parse_failed status=${res.statusCode} err=$err',
          );
        }
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint(
          '[$_chironBookingWorkerProxyLogTag][SCORE_SUMMARY] non_success status=${res.statusCode}',
        );
        return _ChironScoreSummaryResponse.error(
          tenantId: _text(payload['tenant_id']).isEmpty
              ? effective.tenantId
              : _text(payload['tenant_id']),
          companyId: _text(payload['company_id']).isEmpty
              ? effective.companyId
              : _text(payload['company_id']),
          errorMessage: _t(
            nl: 'Chiron score-overzicht kon niet geladen worden.',
            en: 'Chiron score overview could not be loaded.',
            fr: 'L’aperçu du score Chiron n’a pas pu être chargé.',
            es: 'No se pudo cargar el resumen de puntuación de Chiron.',
          ),
        );
      }
      return _ChironScoreSummaryResponse.fromJson(payload);
    } catch (err) {
      debugPrint(
        '[$_chironBookingWorkerProxyLogTag][SCORE_SUMMARY] request_failed err=$err',
      );
      return _ChironScoreSummaryResponse.error(
        tenantId: effective.tenantId,
        companyId: effective.companyId,
        errorMessage: _t(
          nl: 'Chiron score-overzicht kon niet geladen worden.',
          en: 'Chiron score overview could not be loaded.',
          fr: 'L’aperçu du score Chiron n’a pas pu être chargé.',
          es: 'No se pudo cargar el resumen de puntuación de Chiron.',
        ),
      );
    }
  }

  ({String label, Color color, IconData icon}) _status(
    _ChironScoreSummaryCounts counts,
  ) {
    if (counts.blockerCount > 0) {
      return (
        label: _t(
          nl: 'Aandacht nodig',
          en: 'Needs attention',
          fr: 'Attention requise',
          es: 'Requiere atención',
        ),
        color: _chironDanger,
        icon: Icons.error_outline,
      );
    }
    if (counts.warningCount > 0) {
      return (
        label: _t(
          nl: 'Waarschuwingen',
          en: 'Warnings',
          fr: 'Avertissements',
          es: 'Advertencias',
        ),
        color: _chironWarning,
        icon: Icons.warning_amber_outlined,
      );
    }
    return (
      label: _t(nl: 'Klaar', en: 'Ready', fr: 'Prêt', es: 'Listo'),
      color: _chironSuccess,
      icon: Icons.check_circle_outline,
    );
  }

  Widget _messagePanel(String text, {Color? color}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _chironPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _chironBorder),
      ),
      child: Text(
        text,
        style: TextStyle(color: color ?? _chironTextMuted, fontSize: 12),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _chironCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _chironBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: _chironTextMuted, fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: _chironTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryPanel(_ChironScoreSummaryResponse summary) {
    if (summary.totalEvents == 0 || summary.newestEvents.isEmpty) {
      return _messagePanel(
        _t(
          nl: 'Nog geen Chiron-score beschikbaar.',
          en: 'No Chiron score available yet.',
          fr: 'Aucun score Chiron disponible pour le moment.',
          es: 'Aún no hay puntuación Chiron disponible.',
        ),
      );
    }

    final counts = summary.counts;
    final status = _status(counts);
    final latestScore = summary.newestEvents.first.score;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _chironPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _chironBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: status.color.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: status.color.withOpacity(0.55)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(status.icon, size: 14, color: status.color),
                    const SizedBox(width: 6),
                    Text(
                      status.label,
                      style: TextStyle(
                        color: status.color,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _t(
                  nl: 'Laatste Chiron-score',
                  en: 'Latest Chiron score',
                  fr: 'Dernier score Chiron',
                  es: 'Última puntuación Chiron',
                ),
                style: TextStyle(color: _chironTextMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metric(
                _t(
                  nl: 'Laatste score',
                  en: 'Latest score',
                  fr: 'Dernier score',
                  es: 'Última puntuación',
                ),
                latestScore == null ? '—' : '$latestScore',
              ),
              _metric(
                _t(
                  nl: 'Chiron-ready',
                  en: 'Chiron-ready',
                  fr: 'Chiron-ready',
                  es: 'Chiron-ready',
                ),
                '${counts.readyCount}',
              ),
              _metric(
                _t(
                  nl: 'Waarschuwingen',
                  en: 'Warnings',
                  fr: 'Avertissements',
                  es: 'Advertencias',
                ),
                '${counts.warningCount}',
              ),
              _metric(
                _t(
                  nl: 'Aandacht vereist',
                  en: 'Attention required',
                  fr: 'Attention requise',
                  es: 'Atención requerida',
                ),
                '${counts.blockerCount}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ChironScoreSummaryResponse>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _chironGold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _t(
                  nl: 'Chiron-status laden...',
                  en: 'Loading Chiron status...',
                  fr: 'Chargement du statut Chiron...',
                  es: 'Cargando estado Chiron...',
                ),
                style: TextStyle(color: _chironTextSecondary, fontSize: 12),
              ),
            ],
          );
        }

        final summary =
            snapshot.data ??
            _ChironScoreSummaryResponse.error(
              errorMessage: _t(
                nl: 'Chiron score-overzicht kon niet geladen worden.',
                en: 'Chiron score overview could not be loaded.',
                fr: 'L’aperçu du score Chiron n’a pas pu être chargé.',
                es: 'No se pudo cargar el resumen de puntuación de Chiron.',
              ),
            );
        if (!summary.ok) {
          return _messagePanel(summary.errorMessage, color: _chironWarning);
        }
        return _summaryPanel(summary);
      },
    );
  }
}

class _ChironReadinessPanel extends StatefulWidget {
  const _ChironReadinessPanel({required this.lang});

  final AppLanguage lang;

  @override
  State<_ChironReadinessPanel> createState() => _ChironReadinessPanelState();
}

class _ChironReadinessPanelState extends State<_ChironReadinessPanel> {
  late Future<_ChironReadinessResponse> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadReadiness();
  }

  void _refresh() {
    setState(() {
      _future = _loadReadiness();
    });
  }

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (widget.lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return en;
    }
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  ({String tenantId, String companyId})? _effectiveTenantCompanyIds() {
    final activeCompanyId =
        companyProfileNotifier.value?.companyId.trim() ?? '';
    if (activeCompanyId.isNotEmpty) {
      return (tenantId: activeCompanyId, companyId: activeCompanyId);
    }
    final sessionCompanyId =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (sessionCompanyId.isNotEmpty) {
      return (tenantId: sessionCompanyId, companyId: sessionCompanyId);
    }
    return null;
  }

  Future<_ChironReadinessResponse> _loadReadiness() async {
    final effective = _effectiveTenantCompanyIds();
    if (effective == null) {
      return _ChironReadinessResponse.missingScope(
        errorMessage: _t(
          nl: 'Geen bedrijfscontext beschikbaar.',
          en: 'No company context available.',
          fr: 'Aucun contexte entreprise disponible.',
          es: 'No hay contexto de empresa disponible.',
        ),
      );
    }

    /* CHIRON-P0-2A: readiness now goes through the booking worker's
     * company-owner authenticated proxy at bookingBaseUrl. */
    if (!hasCompanyOwnerAuthContext()) {
      return _ChironReadinessResponse.error(
        errorMessage: _t(
          nl: 'Niet gemachtigd om Chiron-readiness te laden.',
          en: 'Not authorized to load Chiron readiness.',
          fr: 'Non autorisé à charger la préparation Chiron.',
          es: 'No autorizado para cargar la preparación Chiron.',
        ),
        unauthorized: true,
      );
    }

    final uri = _chironBookingReadonlyEndpoint(
      '/admin/chiron/readiness',
      tenantId: effective.tenantId,
      companyId: effective.companyId,
    );
    final auth = await resolveCompanyOwnerAuthHeaders();
    try {
      final res = await http
          .post(
            uri,
            headers: auth.headers,
            body: jsonEncode(<String, dynamic>{
              'tenant_id': effective.tenantId,
              'company_id': effective.companyId,
              'limit': 20,
              'event_type': 'ride_stop',
            }),
          )
          .timeout(const Duration(seconds: 15));
      final contentType = (res.headers['content-type'] ?? '').toLowerCase();
      Map<String, dynamic> payload = const <String, dynamic>{};
      if (contentType.contains('application/json') && res.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map) {
            payload = Map<String, dynamic>.from(decoded);
          }
        } catch (err) {
          debugPrint(
            '[$_chironBookingWorkerProxyLogTag][READINESS_PANEL] json_parse_failed status=${res.statusCode} err=$err',
          );
        }
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        debugPrint(
          '[$_chironBookingWorkerProxyLogTag][READINESS_PANEL] auth_failed status=${res.statusCode}',
        );
        return _ChironReadinessResponse.error(
          errorMessage: _t(
            nl: 'Niet gemachtigd om Chiron-readiness te laden.',
            en: 'Not authorized to load Chiron readiness.',
            fr: 'Non autorisé à charger la préparation Chiron.',
            es: 'No autorizado para cargar la preparación Chiron.',
          ),
          unauthorized: true,
        );
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint(
          '[$_chironBookingWorkerProxyLogTag][READINESS_PANEL] non_success status=${res.statusCode}',
        );
        return _ChironReadinessResponse.error(
          errorMessage: _t(
            nl: 'Chiron-readiness kon niet geladen worden.',
            en: 'Chiron readiness could not be loaded.',
            fr: 'La préparation Chiron n’a pas pu être chargée.',
            es: 'No se pudo cargar la preparación Chiron.',
          ),
        );
      }
      return _ChironReadinessResponse.fromJson(payload);
    } catch (err) {
      debugPrint(
        '[$_chironBookingWorkerProxyLogTag][READINESS_PANEL] request_failed err=$err',
      );
      return _ChironReadinessResponse.error(
        errorMessage: _t(
          nl: 'Chiron-readiness kon niet geladen worden.',
          en: 'Chiron readiness could not be loaded.',
          fr: 'La préparation Chiron n’a pas pu être chargée.',
          es: 'No se pudo cargar la preparación Chiron.',
        ),
      );
    }
  }

  ({String label, Color color, IconData icon}) _overallStatusVisual(
    String overallStatus,
  ) {
    switch (overallStatus) {
      case 'blocked':
        return (
          label: _t(
            nl: 'Geblokkeerd',
            en: 'Blocked',
            fr: 'Bloqué',
            es: 'Bloqueado',
          ),
          color: _chironDanger,
          icon: Icons.block,
        );
      case 'required_review':
        return (
          label: _t(
            nl: 'Review nodig',
            en: 'Review needed',
            fr: 'Revue requise',
            es: 'Revisión necesaria',
          ),
          color: _chironWarning,
          icon: Icons.rate_review_outlined,
        );
      case 'format_valid':
        return (
          label: _t(
            nl: 'Formaat geldig',
            en: 'Format valid',
            fr: 'Format valide',
            es: 'Formato válido',
          ),
          color: _chironGold,
          icon: Icons.fact_check_outlined,
        );
      case 'ready_for_chiron_test':
        return (
          label: _t(
            nl: 'Klaar voor Chiron-test',
            en: 'Ready for Chiron test',
            fr: 'Prêt pour le test Chiron',
            es: 'Listo para prueba Chiron',
          ),
          color: _chironSuccess,
          icon: Icons.verified_outlined,
        );
      case 'not_applicable':
        return (
          label: _t(
            nl: 'Niet van toepassing',
            en: 'Not applicable',
            fr: 'Non applicable',
            es: 'No aplicable',
          ),
          color: _chironTextMuted,
          icon: Icons.remove_circle_outline,
        );
      default:
        return (
          label: _t(
            nl: 'Onbekend',
            en: 'Unknown',
            fr: 'Inconnu',
            es: 'Desconocido',
          ),
          color: _chironTextMuted,
          icon: Icons.help_outline,
        );
    }
  }

  String _issueGroupLabel(String fieldGroup) {
    switch (fieldGroup) {
      case 'business_identity':
        return _t(
          nl: 'Bedrijfsgegevens',
          en: 'Business data',
          fr: 'Données entreprise',
          es: 'Datos empresa',
        );
      case 'vehicle_identity':
        return _t(
          nl: 'Voertuig',
          en: 'Vehicle',
          fr: 'Véhicule',
          es: 'Vehículo',
        );
      case 'driver_identity':
        return _t(
          nl: 'Chauffeur',
          en: 'Driver',
          fr: 'Chauffeur',
          es: 'Conductor',
        );
      case 'ride_geometry':
        return _t(
          nl: 'GPS/afstand',
          en: 'GPS/distance',
          fr: 'GPS/distance',
          es: 'GPS/distancia',
        );
      case 'sequence':
        return _t(
          nl: 'Volgorde',
          en: 'Sequence',
          fr: 'Séquence',
          es: 'Secuencia',
        );
      case 'documents':
        return _t(
          nl: 'Documenten',
          en: 'Documents',
          fr: 'Documents',
          es: 'Documentos',
        );
      case 'registry':
        return _t(
          nl: 'Register',
          en: 'Registry',
          fr: 'Registre',
          es: 'Registro',
        );
      default:
        return fieldGroup.isEmpty ? '—' : fieldGroup;
    }
  }

  Widget _messagePanel(String text, {Color? color}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _chironPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _chironBorder),
      ),
      child: Text(
        text,
        style: TextStyle(color: color ?? _chironTextMuted, fontSize: 12),
      ),
    );
  }

  Widget _readinessMetricTile({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    // Mirrors _ChironScoreSummaryPanelState._metric styling for visual parity.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _chironCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _chironBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: _chironTextMuted, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? _chironTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _readinessKpiRow(_ChironReadinessSummary summary) {
    final tiles = <Widget>[
      _readinessMetricTile(
        label: _t(
          nl: 'geblokkeerd',
          en: 'blocked',
          fr: 'bloqué',
          es: 'bloqueado',
        ),
        value: '${summary.blockedCount}',
        valueColor: summary.blockedCount > 0 ? _chironDanger : null,
      ),
      _readinessMetricTile(
        label: _t(nl: 'review', en: 'review', fr: 'revue', es: 'revisión'),
        value: '${summary.reviewRequiredCount}',
        valueColor: summary.reviewRequiredCount > 0 ? _chironWarning : null,
      ),
      _readinessMetricTile(
        label: _t(nl: 'klaar', en: 'ready', fr: 'prêt', es: 'listo'),
        value: '${summary.officialReadyCount}',
        valueColor: summary.officialReadyCount > 0 ? _chironSuccess : null,
      ),
      if (summary.sequenceUnsafeCount > 0)
        _readinessMetricTile(
          label: _t(
            nl: 'volgorde',
            en: 'sequence',
            fr: 'séquence',
            es: 'secuencia',
          ),
          value: '${summary.sequenceUnsafeCount}',
          valueColor: _chironWarning,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        const gap = 8.0;
        final tileCount = tiles.length;
        final columns = maxWidth >= 520
            ? tileCount
            : maxWidth >= 260
            ? 2
            : 1;
        final tileWidth = columns == 1
            ? maxWidth
            : (maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: tileWidth, child: tile),
          ],
        );
      },
    );
  }

  Widget _issueChip(_ChironReadinessIssue issue) {
    final label = issue.fieldGroup.isNotEmpty
        ? _issueGroupLabel(issue.fieldGroup)
        : issue.code;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _chironCard,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _chironBorder),
      ),
      child: Text(
        '$label · ${issue.count}',
        style: TextStyle(
          color: _chironTextSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  void _openReportPage(
    BuildContext context,
    _ChironReadinessResponse response,
  ) {
    if (!response.ok || response.report.overallStatus.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Rapport nog niet geladen.',
              en: 'Report not loaded yet.',
              fr: 'Rapport pas encore chargé.',
              es: 'Informe aún no cargado.',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _ChironReadinessReportPage(lang: widget.lang, response: response),
      ),
    );
  }

  Widget _readinessPanel(_ChironReadinessResponse response) {
    if (response.processedCount == 0) {
      return _messagePanel(
        _t(
          nl: 'Nog geen Chiron-ritdata gevonden.',
          en: 'No Chiron ride data found yet.',
          fr: 'Aucune donnée de course Chiron trouvée.',
          es: 'Aún no se encontraron datos de viaje Chiron.',
        ),
      );
    }

    final report = response.report;
    final summary = report.summary;
    final technicalBlockers = _chironTechnicalBlockers(report.topBlockers);
    final statusVisual = technicalBlockers.isNotEmpty
        ? _overallStatusVisual('blocked')
        : (report.overallStatus == 'blocked'
              ? _overallStatusVisual('ready_for_chiron_test')
              : _overallStatusVisual(report.overallStatus));
    final topAction = technicalBlockers.isNotEmpty
        ? technicalBlockers.first.nextAction
        : (report.topWarnings
                  .where(
                    (issue) => !_chironReadinessIssueIsOptionalDocument(issue),
                  )
                  .isNotEmpty
              ? report.topWarnings
                    .where(
                      (issue) =>
                          !_chironReadinessIssueIsOptionalDocument(issue),
                    )
                    .first
                    .nextAction
              : '');
    final issueChips = <_ChironReadinessIssue>[];
    final seenGroups = <String>{};
    for (final issue in [
      ...technicalBlockers,
      ...report.topWarnings.where(
        (item) => !_chironReadinessIssueIsOptionalDocument(item),
      ),
    ]) {
      final key = issue.fieldGroup.isNotEmpty ? issue.fieldGroup : issue.code;
      if (seenGroups.contains(key)) continue;
      seenGroups.add(key);
      issueChips.add(issue);
      if (issueChips.length >= 3) break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _chironPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _chironBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _t(
                    nl: 'Chiron readiness',
                    en: 'Chiron readiness',
                    fr: 'Préparation Chiron',
                    es: 'Preparación Chiron',
                  ),
                  style: TextStyle(
                    color: _chironTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusVisual.color.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: statusVisual.color.withOpacity(0.55),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      statusVisual.icon,
                      size: 14,
                      color: statusVisual.color,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusVisual.label,
                      style: TextStyle(
                        color: statusVisual.color,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _readinessKpiRow(summary),
          if (topAction.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _t(
                nl: 'Topactie',
                en: 'Top action',
                fr: 'Action principale',
                es: 'Acción principal',
              ),
              style: TextStyle(
                color: _chironTextMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              topAction,
              style: TextStyle(color: _chironTextSecondary, fontSize: 12),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (issueChips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: issueChips.map(_issueChip).toList(),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            _t(
              nl: 'Preflightcontrole — geen officiële Chiron-submit uitgevoerd.',
              en: 'Preflight check — no official Chiron submission performed.',
              fr: 'Contrôle préalable — aucun envoi officiel Chiron effectué.',
              es: 'Comprobación previa — no se ha realizado ningún envío oficial a Chiron.',
            ),
            style: TextStyle(color: _chironTextFaint, fontSize: 10),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _refresh,
                icon: Icon(Icons.refresh, size: 16, color: _chironGold),
                label: Text(
                  _t(
                    nl: 'Controle opnieuw',
                    en: 'Refresh',
                    fr: 'Actualiser',
                    es: 'Actualizar',
                  ),
                  style: TextStyle(color: _chironGold, fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _chironBorder),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _openReportPage(context, response),
                icon: Icon(
                  Icons.article_outlined,
                  size: 16,
                  color: _chironTextMuted,
                ),
                label: Text(
                  _t(
                    nl: 'Bekijk rapport',
                    en: 'View report',
                    fr: 'Voir le rapport',
                    es: 'Ver informe',
                  ),
                  style: TextStyle(color: _chironTextMuted, fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _chironBorder.withOpacity(0.7)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ChironReadinessResponse>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _chironGold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _t(
                  nl: 'Chiron-readiness laden...',
                  en: 'Loading Chiron readiness...',
                  fr: 'Chargement de la préparation Chiron...',
                  es: 'Cargando preparación Chiron...',
                ),
                style: TextStyle(color: _chironTextSecondary, fontSize: 12),
              ),
            ],
          );
        }

        final response =
            snapshot.data ??
            _ChironReadinessResponse.error(
              errorMessage: _t(
                nl: 'Chiron-readiness kon niet geladen worden.',
                en: 'Chiron readiness could not be loaded.',
                fr: 'La préparation Chiron n’a pas pu être chargée.',
                es: 'No se pudo cargar la preparación Chiron.',
              ),
            );

        if (response.missingScope) {
          return _messagePanel(response.errorMessage, color: _chironWarning);
        }
        if (!response.ok) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _messagePanel(
                response.errorMessage,
                color: response.unauthorized ? _chironDanger : _chironWarning,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _refresh,
                  icon: Icon(Icons.refresh, size: 16, color: _chironGold),
                  label: Text(
                    _t(
                      nl: 'Controle opnieuw',
                      en: 'Refresh',
                      fr: 'Actualiser',
                      es: 'Actualizar',
                    ),
                    style: TextStyle(color: _chironGold, fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _chironBorder),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          );
        }
        return _readinessPanel(response);
      },
    );
  }
}

enum _ChironReadinessNavTarget {
  businessSettingsOfficialCompanyDetails,
  vehicles,
  drivers,
  rideRegister,
  backendMessages,
}

bool _chironReadinessIssueIsOptionalDocument(_ChironReadinessIssue issue) {
  final code = issue.code.trim().toLowerCase();
  final group = issue.fieldGroup.trim().toLowerCase();
  if (group == 'documents') return true;
  return code.contains('document');
}

List<_ChironReadinessIssue> _chironTechnicalBlockers(
  List<_ChironReadinessIssue> blockers,
) {
  return blockers
      .where((issue) => !_chironReadinessIssueIsOptionalDocument(issue))
      .toList(growable: false);
}

List<_ChironReadinessIssue> _chironOptionalDocumentBlockers(
  List<_ChironReadinessIssue> blockers,
) {
  return blockers
      .where(_chironReadinessIssueIsOptionalDocument)
      .toList(growable: false);
}

String _chironTechnicalReadinessScopeNote(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.en:
      return 'Fluxidi checks the technical Chiron connection and ride data. Legal permits and official Chiron access remain the operator\'s responsibility.';
    case AppLanguage.fr:
      return 'Fluxidi contrôle la connexion technique Chiron et les données de course. Les autorisations légales et l\'accès officiel Chiron restent la responsabilité de l\'exploitant.';
    case AppLanguage.es:
      return 'Fluxidi comprueba la conexión técnica con Chiron y los datos de viaje. Los permisos legales y el acceso oficial a Chiron siguen siendo responsabilidad del operador.';
    case AppLanguage.nl:
      return 'Fluxidi controleert de technische Chiron-koppeling en ritdata. Wettelijke vergunningen en officiële Chiron-toegang blijven de verantwoordelijkheid van de uitbater.';
  case AppLanguage.de:
    return 'Fluxidi checks the technical Chiron connection and ride data. Legal permits and official Chiron access remain the operator\'s responsibility.';
  }
}

String _companyChecklistScopeNote(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.en:
      return 'This score covers company profile, drivers and vehicles only. Optional documents are tracked separately below and do not block operational readiness.';
    case AppLanguage.fr:
      return 'Ce score couvre uniquement le profil entreprise, les chauffeurs et les véhicules. Les documents facultatifs sont suivis séparément ci-dessous et ne bloquent pas la préparation opérationnelle.';
    case AppLanguage.es:
      return 'Esta puntuación cubre solo perfil de empresa, conductores y vehículos. Los documentos opcionales se siguen por separado abajo y no bloquean la preparación operativa.';
    case AppLanguage.nl:
      return 'Deze score geldt alleen voor bedrijfsprofiel, chauffeurs en voertuigen. Optionele documenten staan apart hieronder en blokkeren de operationele gereedheid niet.';
  case AppLanguage.de:
    return 'This score covers company profile, drivers and vehicles only. Optional documents are tracked separately below and do not block operational readiness.';
  }
}

String _companyChecklistOptionalDocumentsNote(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.en:
      return 'Documents are optional and useful for follow-up, expiry tracking and controls. They do not block daily operational readiness.';
    case AppLanguage.fr:
      return 'Les documents sont facultatifs et utiles pour le suivi, le contrôle des échéances et les contrôles. Ils ne bloquent pas la préparation opérationnelle quotidienne.';
    case AppLanguage.es:
      return 'Los documentos son opcionales y útiles para el seguimiento, el control de vencimientos y las revisiones. No bloquean la preparación operativa diaria.';
    case AppLanguage.nl:
      return 'Documenten zijn optioneel en nuttig voor opvolging, vervaldatums en controles. Ze blokkeren de operationele gereedheid voor dagelijks gebruik niet.';
  case AppLanguage.de:
    return 'Documents are optional and useful for follow-up, expiry tracking and controls. They do not block daily operational readiness.';
  }
}

class _ChironReadinessIssueActionPlan {
  const _ChironReadinessIssueActionPlan({
    this.navTargets = const [],
    this.clarificationText,
    this.helpTitle,
    this.helpText,
  });

  final List<_ChironReadinessNavTarget> navTargets;
  final String? clarificationText;
  final String? helpTitle;
  final String? helpText;

  bool get isEmpty =>
      navTargets.isEmpty &&
      (clarificationText == null || clarificationText!.isEmpty) &&
      (helpText == null || helpText!.isEmpty);
}

class _ChironReadinessReportPage extends StatelessWidget {
  const _ChironReadinessReportPage({
    required this.lang,
    required this.response,
  });

  final AppLanguage lang;
  final _ChironReadinessResponse response;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return en;
    }
  }

  String _groupLabel(String fieldGroup) {
    switch (fieldGroup) {
      case 'business_identity':
        return _t(
          nl: 'Bedrijfsgegevens',
          en: 'Business data',
          fr: 'Données entreprise',
          es: 'Datos empresa',
        );
      case 'vehicle_identity':
        return _t(
          nl: 'Voertuig',
          en: 'Vehicle',
          fr: 'Véhicule',
          es: 'Vehículo',
        );
      case 'driver_identity':
        return _t(
          nl: 'Chauffeur',
          en: 'Driver',
          fr: 'Chauffeur',
          es: 'Conductor',
        );
      case 'ride_geometry':
        return _t(
          nl: 'GPS/afstand',
          en: 'GPS/distance',
          fr: 'GPS/distance',
          es: 'GPS/distancia',
        );
      case 'sequence':
        return _t(
          nl: 'Volgorde',
          en: 'Sequence',
          fr: 'Séquence',
          es: 'Secuencia',
        );
      case 'registry':
        return _t(
          nl: 'Officiële controles',
          en: 'Official checks',
          fr: 'Contrôles officiels',
          es: 'Controles oficiales',
        );
      case 'documents':
        return _t(
          nl: 'Documenten',
          en: 'Documents',
          fr: 'Documents',
          es: 'Documentos',
        );
      default:
        if (fieldGroup.isEmpty) {
          return _t(nl: 'Overig', en: 'Other', fr: 'Autre', es: 'Otro');
        }
        return fieldGroup;
    }
  }

  String _issueLabel(String code) {
    if (code.isEmpty) return code;
    switch (code) {
      case 'invalid_zero_coordinate_pair':
        return _t(
          nl: 'GPS-coördinaten zijn 0/0',
          en: 'GPS coordinates are 0/0',
          fr: 'Coordonnées GPS à 0/0',
          es: 'Coordenadas GPS en 0/0',
        );
      case 'placeholder_registration':
        return _t(
          nl: 'Demo-KBO gedetecteerd',
          en: 'Demo company number detected',
          fr: 'Numéro d\'entreprise démo détecté',
          es: 'Número de empresa demo detectado',
        );
      case 'placeholder_business_name':
        return _t(
          nl: 'Demo-bedrijfsnaam gedetecteerd',
          en: 'Demo business name detected',
          fr: 'Nom d\'entreprise démo détecté',
          es: 'Nombre de empresa demo detectado',
        );
      case 'placeholder_driver_pass':
        return _t(
          nl: 'Demo-bestuurderspas gedetecteerd',
          en: 'Demo driver pass detected',
          fr: 'Carte chauffeur démo détectée',
          es: 'Carnet de conductor demo detectado',
        );
      case 'placeholder_license_plate':
        return _t(
          nl: 'Demo-kenteken gedetecteerd',
          en: 'Demo license plate detected',
          fr: 'Plaque démo détectée',
          es: 'Matrícula demo detectada',
        );
      case 'invalid_flemish_taxi_plate':
        return _t(
          nl: 'Ongeldig Vlaams taxi-kenteken',
          en: 'Invalid Flemish taxi plate',
          fr: 'Plaque taxi flamande invalide',
          es: 'Matrícula taxi flamenca no válida',
        );
      case 'aankomstpunt_breedtegraad':
        return _t(
          nl: 'Aankomst GPS-breedtegraad ontbreekt',
          en: 'Arrival GPS latitude missing',
          fr: 'Latitude GPS d\'arrivée manquante',
          es: 'Latitud GPS de llegada faltante',
        );
      case 'aankomstpunt_lengtegraad':
        return _t(
          nl: 'Aankomst GPS-lengtegraad ontbreekt',
          en: 'Arrival GPS longitude missing',
          fr: 'Longitude GPS d\'arrivée manquante',
          es: 'Longitud GPS de llegada faltante',
        );
      case 'vertrekpunt_breedtegraad':
        return _t(
          nl: 'Vertrek GPS-breedtegraad ontbreekt',
          en: 'Departure GPS latitude missing',
          fr: 'Latitude GPS de départ manquante',
          es: 'Latitud GPS de salida faltante',
        );
      case 'vertrekpunt_lengtegraad':
        return _t(
          nl: 'Vertrek GPS-lengtegraad ontbreekt',
          en: 'Departure GPS longitude missing',
          fr: 'Longitude GPS de départ manquante',
          es: 'Longitud GPS de salida faltante',
        );
      case 'afstand':
        return _t(
          nl: 'Ritafstand ontbreekt of is 0',
          en: 'Trip distance missing or zero',
          fr: 'Distance de course manquante ou nulle',
          es: 'Distancia del viaje faltante o cero',
        );
      case 'missing_prior_vertrek_or_reservatie_in_batch':
        return _t(
          nl: 'Ritvolgorde niet volledig',
          en: 'Ride sequence incomplete',
          fr: 'Ordre des courses incomplet',
          es: 'Secuencia de viajes incompleta',
        );
      case 'taxi_plate_pattern_not_confirmed':
        return _t(
          nl: 'Taxi-kenteken niet bevestigd',
          en: 'Taxi plate not confirmed',
          fr: 'Plaque taxi non confirmée',
          es: 'Matrícula taxi no confirmada',
        );
      case 'vehicle_document_review_required':
        return _t(
          nl: 'Voertuigdocument controleren',
          en: 'Review vehicle document',
          fr: 'Contrôler le document véhicule',
          es: 'Revisar documento del vehículo',
        );
      case 'invalid_registration_format':
        return _t(
          nl: 'Ongeldig KBO-nummer',
          en: 'Invalid company number format',
          fr: 'Numéro d\'entreprise invalide',
          es: 'Formato de número de empresa no válido',
        );
      case 'invalid_business_name':
        return _t(
          nl: 'Ongeldige bedrijfsnaam',
          en: 'Invalid business name',
          fr: 'Nom d\'entreprise invalide',
          es: 'Nombre de empresa no válido',
        );
      case 'invalid_license_plate_format':
        return _t(
          nl: 'Ongeldig kentekenformaat',
          en: 'Invalid license plate format',
          fr: 'Format de plaque invalide',
          es: 'Formato de matrícula no válido',
        );
      case 'taxi_plate_exception_requires_review':
        return _t(
          nl: 'Kentekenuitzondering controleren',
          en: 'License plate exception needs review',
          fr: 'Exception de plaque à contrôler',
          es: 'Excepción de matrícula requiere revisión',
        );
      case 'invalid_driver_pass_format':
        return _t(
          nl: 'Ongeldig bestuurderspasnummer',
          en: 'Invalid driver pass number',
          fr: 'Numéro de carte chauffeur invalide',
          es: 'Número de carnet de conductor no válido',
        );
      case 'kostprijs':
        return _t(
          nl: 'Ritprijs ontbreekt',
          en: 'Trip price missing',
          fr: 'Prix de course manquant',
          es: 'Precio del viaje faltante',
        );
      case 'vertrektijdstip':
        return _t(
          nl: 'Vertrektijdstip ontbreekt',
          en: 'Departure timestamp missing',
          fr: 'Heure de départ manquante',
          es: 'Hora de salida faltante',
        );
      case 'aankomsttijdstip':
        return _t(
          nl: 'Aankomsttijdstip ontbreekt',
          en: 'Arrival timestamp missing',
          fr: 'Heure d\'arrivée manquante',
          es: 'Hora de llegada faltante',
        );
      case 'ritnummer':
        return _t(
          nl: 'Ritreferentie ontbreekt',
          en: 'Trip reference missing',
          fr: 'Référence de course manquante',
          es: 'Referencia del viaje faltante',
        );
      case 'broncreatiedatum':
        return _t(
          nl: 'Aanmaakdatum bronregistratie ontbreekt',
          en: 'Source record creation date missing',
          fr: 'Date de création source manquante',
          es: 'Fecha de creación del registro fuente faltante',
        );
      case 'driver_pass_document_review_required':
        return _t(
          nl: 'Bestuurderspasdocument controleren',
          en: 'Review driver pass document',
          fr: 'Contrôler le document carte chauffeur',
          es: 'Revisar carnet de conductor',
        );
      case 'driver_pass_document_expired':
        return _t(
          nl: 'Bestuurderspasdocument verlopen',
          en: 'Driver pass document expired',
          fr: 'Document carte chauffeur expiré',
          es: 'Carnet de conductor caducado',
        );
      case 'driver_pass_document_mismatch':
        return _t(
          nl: 'Bestuurderspas komt niet overeen',
          en: 'Driver pass document mismatch',
          fr: 'Carte chauffeur non concordante',
          es: 'Carnet de conductor no coincide',
        );
      case 'driver_pass_document_rejected':
        return _t(
          nl: 'Bestuurderspasdocument afgewezen',
          en: 'Driver pass document rejected',
          fr: 'Document carte chauffeur rejeté',
          es: 'Carnet de conductor rechazado',
        );
      case 'vehicle_document_expired':
        return _t(
          nl: 'Voertuigdocument verlopen',
          en: 'Vehicle document expired',
          fr: 'Document véhicule expiré',
          es: 'Documento del vehículo caducado',
        );
      case 'vehicle_document_mismatch':
        return _t(
          nl: 'Voertuigdocument komt niet overeen',
          en: 'Vehicle document mismatch',
          fr: 'Document véhicule non concordant',
          es: 'Documento del vehículo no coincide',
        );
      case 'vehicle_document_rejected':
        return _t(
          nl: 'Voertuigdocument afgewezen',
          en: 'Vehicle document rejected',
          fr: 'Document véhicule rejeté',
          es: 'Documento del vehículo rechazado',
        );
      case 'business_document_review_required':
        return _t(
          nl: 'Ondernemingsdocument controleren',
          en: 'Review business document',
          fr: 'Contrôler le document entreprise',
          es: 'Revisar documento de empresa',
        );
      case 'business_document_expired':
        return _t(
          nl: 'Ondernemingsdocument verlopen',
          en: 'Business document expired',
          fr: 'Document entreprise expiré',
          es: 'Documento de empresa caducado',
        );
      case 'business_document_mismatch':
        return _t(
          nl: 'Ondernemingsdocument komt niet overeen',
          en: 'Business document mismatch',
          fr: 'Document entreprise non concordant',
          es: 'Documento de empresa no coincide',
        );
      case 'business_document_rejected':
        return _t(
          nl: 'Ondernemingsdocument afgewezen',
          en: 'Business document rejected',
          fr: 'Document entreprise rejeté',
          es: 'Documento de empresa rechazado',
        );
      default:
        return code.replaceAll('_', ' ');
    }
  }

  String _fieldLabel(String field) {
    if (field.isEmpty) return field;
    switch (field) {
      case 'registratie':
        return _t(
          nl: 'KBO / ondernemingsnummer',
          en: 'Company number (KBO)',
          fr: 'Numéro d\'entreprise (BCE)',
          es: 'Número de empresa (KBO)',
        );
      case 'naam':
        return _t(
          nl: 'Bedrijfsnaam',
          en: 'Business name',
          fr: 'Nom d\'entreprise',
          es: 'Nombre de empresa',
        );
      case 'kentekenplaat':
        return _t(
          nl: 'Nummerplaat',
          en: 'License plate',
          fr: 'Plaque d\'immatriculation',
          es: 'Matrícula',
        );
      case 'bestuurderspasnummer':
        return _t(
          nl: 'Bestuurderspas',
          en: 'Driver pass',
          fr: 'Carte chauffeur',
          es: 'Carnet de conductor',
        );
      case 'vertrekpunt_lengtegraad':
        return _t(
          nl: 'Vertrek GPS-lengtegraad',
          en: 'Departure GPS longitude',
          fr: 'Longitude GPS départ',
          es: 'Longitud GPS salida',
        );
      case 'vertrekpunt_breedtegraad':
        return _t(
          nl: 'Vertrek GPS-breedtegraad',
          en: 'Departure GPS latitude',
          fr: 'Latitude GPS départ',
          es: 'Latitud GPS salida',
        );
      case 'aankomstpunt_lengtegraad':
        return _t(
          nl: 'Aankomst GPS-lengtegraad',
          en: 'Arrival GPS longitude',
          fr: 'Longitude GPS arrivée',
          es: 'Longitud GPS llegada',
        );
      case 'aankomstpunt_breedtegraad':
        return _t(
          nl: 'Aankomst GPS-breedtegraad',
          en: 'Arrival GPS latitude',
          fr: 'Latitude GPS arrivée',
          es: 'Latitud GPS llegada',
        );
      case 'afstand':
        return _t(
          nl: 'Ritafstand',
          en: 'Trip distance',
          fr: 'Distance de course',
          es: 'Distancia del viaje',
        );
      case 'status':
        return _t(nl: 'Status', en: 'Status', fr: 'Statut', es: 'Estado');
      case 'kostprijs':
        return _t(
          nl: 'Ritprijs',
          en: 'Trip price',
          fr: 'Prix de course',
          es: 'Precio del viaje',
        );
      case 'vertrektijdstip':
        return _t(
          nl: 'Vertrektijdstip',
          en: 'Departure time',
          fr: 'Heure de départ',
          es: 'Hora de salida',
        );
      case 'aankomsttijdstip':
        return _t(
          nl: 'Aankomsttijdstip',
          en: 'Arrival time',
          fr: 'Heure d\'arrivée',
          es: 'Hora de llegada',
        );
      case 'ritnummer':
        return _t(
          nl: 'Ritreferentie',
          en: 'Trip reference',
          fr: 'Référence de course',
          es: 'Referencia del viaje',
        );
      case 'broncreatiedatum':
        return _t(
          nl: 'Aanmaakdatum',
          en: 'Creation date',
          fr: 'Date de création',
          es: 'Fecha de creación',
        );
      default:
        return field.replaceAll('_', ' ');
    }
  }

  ({String label, Color color, IconData icon}) _statusVisual(String status) {
    switch (status) {
      case 'blocked':
        return (
          label: _t(
            nl: 'Geblokkeerd',
            en: 'Blocked',
            fr: 'Bloqué',
            es: 'Bloqueado',
          ),
          color: _chironDanger,
          icon: Icons.block,
        );
      case 'required_review':
        return (
          label: _t(
            nl: 'Review nodig',
            en: 'Review needed',
            fr: 'Revue requise',
            es: 'Revisión necesaria',
          ),
          color: _chironWarning,
          icon: Icons.rate_review_outlined,
        );
      case 'format_valid':
        return (
          label: _t(
            nl: 'Formaat geldig',
            en: 'Format valid',
            fr: 'Format valide',
            es: 'Formato válido',
          ),
          color: _chironGold,
          icon: Icons.fact_check_outlined,
        );
      case 'ready_for_chiron_test':
        return (
          label: _t(
            nl: 'Klaar voor Chiron-test',
            en: 'Ready for Chiron test',
            fr: 'Prêt pour le test Chiron',
            es: 'Listo para prueba Chiron',
          ),
          color: _chironSuccess,
          icon: Icons.verified_outlined,
        );
      case 'verified':
        return (
          label: _t(
            nl: 'Geverifieerd',
            en: 'Verified',
            fr: 'Vérifié',
            es: 'Verificado',
          ),
          color: _chironSuccess,
          icon: Icons.verified_outlined,
        );
      case 'missing':
        return (
          label: _t(
            nl: 'Ontbreekt',
            en: 'Missing',
            fr: 'Manquant',
            es: 'Faltante',
          ),
          color: _chironTextMuted,
          icon: Icons.help_outline,
        );
      case 'not_applicable':
        return (
          label: _t(
            nl: 'Niet van toepassing',
            en: 'Not applicable',
            fr: 'Non applicable',
            es: 'No aplicable',
          ),
          color: _chironTextMuted,
          icon: Icons.remove_circle_outline,
        );
      default:
        return (
          label: _t(
            nl: 'Onbekend',
            en: 'Unknown',
            fr: 'Inconnu',
            es: 'Desconocido',
          ),
          color: _chironTextMuted,
          icon: Icons.help_outline,
        );
    }
  }

  Widget _statusChip(String status) {
    final visual = _statusVisual(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: visual.color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: visual.color.withOpacity(0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, size: 14, color: visual.color),
          const SizedBox(width: 6),
          Text(
            visual.label,
            style: TextStyle(
              color: visual.color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // Chiron-6B-3H.1: softer, lifecycle-aware badges for "Controle per onderdeel".
  ({String label, Color color, IconData icon}) _fieldGroupStatusVisual(
    String groupKey,
    String status,
  ) {
    switch (status) {
      case 'blocked':
        if (groupKey == 'ride_geometry' || groupKey == 'sequence') {
          return (
            label: _t(
              nl: 'Aandacht in steekproef',
              en: 'Needs attention in sample',
              fr: 'Attention dans l\'échantillon',
              es: 'Atención en la muestra',
            ),
            color: _chironWarning,
            icon: Icons.warning_amber_outlined,
          );
        }
        return (
          label: _t(
            nl: 'Aandacht nodig',
            en: 'Needs attention',
            fr: 'Attention requise',
            es: 'Requiere atención',
          ),
          color: _chironWarning,
          icon: Icons.warning_amber_outlined,
        );
      case 'required_review':
        return (
          label: _t(
            nl: 'Review nodig',
            en: 'Review needed',
            fr: 'Revue requise',
            es: 'Revisión necesaria',
          ),
          color: _chironWarning,
          icon: Icons.rate_review_outlined,
        );
      case 'missing':
        if (groupKey == 'registry') {
          return (
            label: _t(
              nl: 'Niet uitgevoerd',
              en: 'Not performed',
              fr: 'Non exécuté',
              es: 'No ejecutado',
            ),
            color: _chironTextMuted,
            icon: Icons.info_outline,
          );
        }
        if (groupKey == 'documents') {
          return (
            label: _t(
              nl: 'Nog te controleren',
              en: 'To review',
              fr: 'À contrôler',
              es: 'Por revisar',
            ),
            color: _chironTextMuted,
            icon: Icons.fact_check_outlined,
          );
        }
        return _statusVisual(status);
      default:
        return _statusVisual(status);
    }
  }

  Widget _fieldGroupStatusChip(_ChironReadinessFieldGroup group) {
    final visual = _fieldGroupStatusVisual(group.group, group.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: visual.color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: visual.color.withOpacity(0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, size: 14, color: visual.color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              visual.label,
              style: TextStyle(
                color: visual.color,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _fieldGroupRideGeometryNote() {
    return _t(
      nl: 'Deze controle geldt voor geanalyseerde aankomst-events na START en STOP.',
      en: 'This check applies to analyzed arrival events after START and STOP.',
      fr: 'Ce contrôle s\'applique aux événements d\'arrivée analysés après START et STOP.',
      es: 'Este control se aplica a eventos de llegada analizados después de START y STOP.',
    );
  }

  bool _isSetupFieldGroup(String groupKey) {
    return groupKey == 'business_identity' ||
        groupKey == 'vehicle_identity' ||
        groupKey == 'driver_identity';
  }

  Widget _metricTile({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _chironCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _chironBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: _chironTextMuted, fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? _chironTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricGrid(List<Widget> tiles) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        const gap = 8.0;
        final tileCount = tiles.length;
        final columns = maxWidth >= 520
            ? (tileCount >= 4 ? 3 : tileCount)
            : maxWidth >= 260
            ? 2
            : 1;
        final tileWidth = columns == 1
            ? maxWidth
            : (maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: tileWidth, child: tile),
          ],
        );
      },
    );
  }

  Widget _panelBox({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _chironPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _chironBorder),
      ),
      child: child,
    );
  }

  bool _isSequenceIssue(String code) {
    if (code.isEmpty) return false;
    switch (code) {
      case 'missing_prior_vertrek_or_reservatie_in_batch':
        return true;
      default:
        return false;
    }
  }

  bool _readinessHaystackContains(String haystack, List<String> tokens) {
    for (final token in tokens) {
      if (token.isNotEmpty && haystack.contains(token)) return true;
    }
    return false;
  }

  bool _isDemoOrTestDriverPassIssue(String code) {
    if (code.isEmpty) return false;
    return _isPlaceholderIssue(code) && code.contains('driver');
  }

  String _demoDriverPassClarification() {
    return _t(
      nl: 'Demo- of testwaarden zijn bruikbaar voor app-tests, maar blokkeren officiële Chiron-doorgifte.',
      en: 'Demo or test values are fine for app testing, but they block official Chiron submission.',
      fr: 'Les valeurs démo ou test conviennent aux tests applicatifs, mais bloquent l’envoi officiel Chiron.',
      es: 'Los valores demo o de prueba sirven para pruebas de la app, pero bloquean el envío oficial a Chiron.',
    );
  }

  _ChironReadinessIssueActionPlan _driverReadinessActionPlan({
    String? issueCode,
  }) {
    final code = (issueCode ?? '').trim().toLowerCase();
    return _ChironReadinessIssueActionPlan(
      navTargets: const [_ChironReadinessNavTarget.drivers],
      clarificationText: _isDemoOrTestDriverPassIssue(code)
          ? _demoDriverPassClarification()
          : null,
    );
  }

  _ChironReadinessIssueActionPlan _resolveReadinessIssueAction(
    _ChironReadinessIssue issue,
  ) {
    final code = issue.code.trim().toLowerCase();
    final group = issue.fieldGroup.trim().toLowerCase();
    final haystack = '$code $group ${issue.nextAction.trim().toLowerCase()}';
    final optionalDocumentNote = _t(
      nl: 'Documenten zijn optioneel voor de technische Chiron-koppeling.',
      en: 'Documents are optional for the technical Chiron connection.',
      fr: 'Les documents sont facultatifs pour la connexion technique Chiron.',
      es: 'Los documentos son opcionales para la conexión técnica con Chiron.',
    );

    if (_isOptionalDocumentComplianceIssue(issue)) {
      if (group == 'vehicle_identity' ||
          _readinessHaystackContains(haystack, const [
            'vehicle_document',
            'kenteken',
            'taxi_plate',
            'plate',
          ])) {
        return _ChironReadinessIssueActionPlan(
          navTargets: const [_ChironReadinessNavTarget.vehicles],
          clarificationText: optionalDocumentNote,
        );
      }
      if (group == 'driver_identity' ||
          _readinessHaystackContains(haystack, const [
            'driver_pass',
            'bestuurders',
            'chauffeur',
            'driver',
          ])) {
        return _ChironReadinessIssueActionPlan(
          navTargets: const [_ChironReadinessNavTarget.drivers],
          clarificationText: optionalDocumentNote,
        );
      }
      return _ChironReadinessIssueActionPlan(
        clarificationText: optionalDocumentNote,
      );
    }

    if (_isSequenceIssue(code) ||
        group == 'sequence' ||
        _readinessHaystackContains(haystack, const [
          'missing_prior_vertrek',
          'reservatie_in_batch',
          'volgorde',
          'sequence',
        ])) {
      return _ChironReadinessIssueActionPlan(
        navTargets: const [_ChironReadinessNavTarget.rideRegister],
        helpTitle: _t(
          nl: 'Waarom zie ik dit?',
          en: 'Why am I seeing this?',
          fr: 'Pourquoi vois-je ceci ?',
          es: '¿Por qué veo esto?',
        ),
        helpText: _t(
          nl: 'Chiron verwacht een logische volgorde van rit-events (bijv. reservatie/vertrek vóór aankomst). Bureautests of onvolledige testritten kunnen deze melding geven. Controleer het rittenregister na een echte rit met START en STOP.',
          en: 'Chiron expects a logical order of ride events (e.g. reservation/departure before arrival). Desk tests or incomplete test rides can trigger this. Check the ride register after a real ride with START and STOP.',
          fr: 'Chiron attend un ordre logique des événements de course (p. ex. réservation/départ avant arrivée). Les tests bureau ou courses de test incomplètes peuvent déclencher cet avis. Vérifiez le registre après une vraie course avec START et STOP.',
          es: 'Chiron espera un orden lógico de eventos de viaje (p. ej. reserva/salida antes de llegada). Las pruebas de escritorio o viajes de prueba incompletos pueden provocarlo. Revise el registro tras un viaje real con START y STOP.',
        ),
      );
    }

    if (_isRideGeometryIssue(code) ||
        group == 'ride_geometry' ||
        _readinessHaystackContains(haystack, const [
          'gps',
          'latitude',
          'longitude',
          'breedtegraad',
          'lengtegraad',
          'coordinate',
          'coördinaat',
          'coordinaten',
          'invalid_zero_coordinate',
          'afstand',
        ])) {
      return _ChironReadinessIssueActionPlan(
        navTargets: const [
          _ChironReadinessNavTarget.rideRegister,
          _ChironReadinessNavTarget.backendMessages,
        ],
        helpTitle: _t(
          nl: 'Waarom zie ik dit?',
          en: 'Why am I seeing this?',
          fr: 'Pourquoi vois-je ceci ?',
          es: '¿Por qué veo esto?',
        ),
        helpText: _t(
          nl: 'Bureautests of ritten zonder echte locatiebeweging kunnen 0/0-coördinaten of afstand 0 geven. Maak een echte testrit met locatie/GPS actief om deze controle correct te valideren.',
          en: 'Desk tests or rides without real location movement can produce 0/0 coordinates or zero distance. Run a real test ride with location/GPS active to validate this check correctly.',
          fr: 'Les tests bureau ou courses sans déplacement réel peuvent produire des coordonnées 0/0 ou une distance nulle. Effectuez une vraie course test avec localisation/GPS actif pour valider ce contrôle.',
          es: 'Las pruebas de escritorio o viajes sin movimiento real pueden dar coordenadas 0/0 o distancia 0. Realice una prueba real con ubicación/GPS activo para validar este control.',
        ),
      );
    }

    if (group == 'business_identity' ||
        _readinessHaystackContains(haystack, const [
          'placeholder_business',
          'placeholder_registration',
          'invalid_registration',
          'invalid_business',
          'business_document',
          'business_name',
          'registratie',
          'kbo',
          'vies',
          'naam',
        ])) {
      return const _ChironReadinessIssueActionPlan(
        navTargets: [
          _ChironReadinessNavTarget.businessSettingsOfficialCompanyDetails,
        ],
      );
    }

    if (group == 'vehicle_identity' ||
        _readinessHaystackContains(haystack, const [
          'invalid_flemish_taxi_plate',
          'placeholder_license_plate',
          'invalid_license_plate',
          'taxi_plate',
          'kenteken',
          'kentekenplaat',
          'vehicle_document',
        ])) {
      return const _ChironReadinessIssueActionPlan(
        navTargets: [_ChironReadinessNavTarget.vehicles],
      );
    }

    if (group == 'driver_identity' ||
        _readinessHaystackContains(haystack, const [
          'placeholder_driver_pass',
          'invalid_driver_pass',
          'driver_pass',
          'bestuurderspas',
          'chauffeur',
        ])) {
      return _driverReadinessActionPlan(issueCode: code);
    }

    if (group == 'documents') {
      if (_readinessHaystackContains(haystack, const [
        'vehicle',
        'kenteken',
        'taxi',
        'plate',
      ])) {
        return const _ChironReadinessIssueActionPlan(
          navTargets: [_ChironReadinessNavTarget.vehicles],
        );
      }
      if (_readinessHaystackContains(haystack, const [
        'driver',
        'bestuurders',
        'chauffeur',
      ])) {
        return _driverReadinessActionPlan(issueCode: code);
      }
      if (_readinessHaystackContains(haystack, const [
        'business',
        'onderneming',
        'kbo',
      ])) {
        return const _ChironReadinessIssueActionPlan(
          navTargets: [
            _ChironReadinessNavTarget.businessSettingsOfficialCompanyDetails,
          ],
        );
      }
    }

    return const _ChironReadinessIssueActionPlan();
  }

  _ChironReadinessIssueActionPlan _resolveFieldGroupAction(
    _ChironReadinessFieldGroup group,
  ) {
    if (group.blockers.isNotEmpty) {
      return _resolveReadinessIssueAction(group.blockers.first);
    }
    if (group.warnings.isNotEmpty) {
      return _resolveReadinessIssueAction(group.warnings.first);
    }
    switch (group.group) {
      case 'business_identity':
        return const _ChironReadinessIssueActionPlan(
          navTargets: [
            _ChironReadinessNavTarget.businessSettingsOfficialCompanyDetails,
          ],
        );
      case 'vehicle_identity':
        return const _ChironReadinessIssueActionPlan(
          navTargets: [_ChironReadinessNavTarget.vehicles],
        );
      case 'driver_identity':
        final issueCode = group.blockers.isNotEmpty
            ? group.blockers.first.code
            : (group.warnings.isNotEmpty ? group.warnings.first.code : '');
        return _driverReadinessActionPlan(issueCode: issueCode);
      case 'ride_geometry':
        return _ChironReadinessIssueActionPlan(
          navTargets: const [
            _ChironReadinessNavTarget.rideRegister,
            _ChironReadinessNavTarget.backendMessages,
          ],
          helpTitle: _t(
            nl: 'Waarom zie ik dit?',
            en: 'Why am I seeing this?',
            fr: 'Pourquoi vois-je ceci ?',
            es: '¿Por qué veo esto?',
          ),
          helpText: _t(
            nl: 'Bureautests of ritten zonder echte locatiebeweging kunnen 0/0-coördinaten of afstand 0 geven. Maak een echte testrit met locatie/GPS actief om deze controle correct te valideren.',
            en: 'Desk tests or rides without real location movement can produce 0/0 coordinates or zero distance. Run a real test ride with location/GPS active to validate this check correctly.',
            fr: 'Les tests bureau ou courses sans déplacement réel peuvent produire des coordonnées 0/0 ou une distance nulle. Effectuez une vraie course test avec localisation/GPS actif pour valider ce contrôle.',
            es: 'Las pruebas de escritorio o viajes sin movimiento real pueden dar coordenadas 0/0 o distancia 0. Realice una prueba real con ubicación/GPS activo para validar este control.',
          ),
        );
      case 'sequence':
        return _ChironReadinessIssueActionPlan(
          navTargets: const [_ChironReadinessNavTarget.rideRegister],
          helpTitle: _t(
            nl: 'Waarom zie ik dit?',
            en: 'Why am I seeing this?',
            fr: 'Pourquoi vois-je ceci ?',
            es: '¿Por qué veo esto?',
          ),
          helpText: _t(
            nl: 'Chiron verwacht een logische volgorde van rit-events (bijv. reservatie/vertrek vóór aankomst). Bureautests of onvolledige testritten kunnen deze melding geven. Controleer het rittenregister na een echte rit met START en STOP.',
            en: 'Chiron expects a logical order of ride events (e.g. reservation/departure before arrival). Desk tests or incomplete test rides can trigger this. Check the ride register after a real ride with START and STOP.',
            fr: 'Chiron attend un ordre logique des événements de course (p. ex. réservation/départ avant arrivée). Les tests bureau ou courses de test incomplètes peuvent déclencher cet avis. Vérifiez le registre après une vraie course avec START et STOP.',
            es: 'Chiron espera un orden lógico de eventos de viaje (p. ej. reserva/salida antes de llegada). Las pruebas de escritorio o viajes de prueba incompletos pueden provocarlo. Revise el registro tras un viaje real con START y STOP.',
          ),
        );
      default:
        return const _ChironReadinessIssueActionPlan();
    }
  }

  String _readinessNavLabel(_ChironReadinessNavTarget target) {
    switch (target) {
      case _ChironReadinessNavTarget.businessSettingsOfficialCompanyDetails:
        return _t(
          nl: 'Open officiële bedrijfsgegevens',
          en: 'Open official company details',
          fr: 'Ouvrir informations officielles',
          es: 'Abrir datos oficiales de empresa',
        );
      case _ChironReadinessNavTarget.vehicles:
        return _t(
          nl: 'Open voertuigen',
          en: 'Open vehicles',
          fr: 'Ouvrir véhicules',
          es: 'Abrir vehículos',
        );
      case _ChironReadinessNavTarget.drivers:
        return _t(
          nl: 'Open chauffeurs',
          en: 'Open drivers',
          fr: 'Ouvrir chauffeurs',
          es: 'Abrir conductores',
        );
      case _ChironReadinessNavTarget.rideRegister:
        return _t(
          nl: 'Open rittenregister',
          en: 'Open ride register',
          fr: 'Ouvrir registre des trajets',
          es: 'Abrir registro de viajes',
        );
      case _ChironReadinessNavTarget.backendMessages:
        return _t(
          nl: 'Bekijk backendmeldingen',
          en: 'View backend messages',
          fr: 'Voir messages système',
          es: 'Ver mensajes del backend',
        );
    }
  }

  void _openReadinessNavTarget(
    BuildContext context,
    _ChironReadinessNavTarget target,
  ) {
    switch (target) {
      case _ChironReadinessNavTarget.businessSettingsOfficialCompanyDetails:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const BusinessSettingsPage(
              initialSection:
                  BusinessSettingsInitialSection.officialCompanyDetails,
            ),
          ),
        );
      case _ChironReadinessNavTarget.vehicles:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const VehicleManagementPage(),
          ),
        );
      case _ChironReadinessNavTarget.drivers:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => companyDriverManagementPage(),
          ),
        );
      case _ChironReadinessNavTarget.rideRegister:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const _ChironLocalLedgerPage(),
          ),
        );
      case _ChironReadinessNavTarget.backendMessages:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const _ChironRemoteCompliancePage(),
          ),
        );
    }
  }

  Widget _readinessIssueActionSection(
    BuildContext context,
    _ChironReadinessIssueActionPlan plan,
  ) {
    if (plan.isEmpty) return const SizedBox.shrink();

    final buttons = <Widget>[];
    for (final target in plan.navTargets) {
      buttons.add(
        OutlinedButton(
          onPressed: () => _openReadinessNavTarget(context, target),
          style: _chironTestAccessSecondaryButtonStyle(),
          child: Text(
            _readinessNavLabel(target),
            style: const TextStyle(fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (buttons.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: buttons),
        ],
        if (plan.clarificationText != null &&
            plan.clarificationText!.isNotEmpty) ...[
          SizedBox(height: buttons.isNotEmpty ? 6 : 8),
          Text(
            plan.clarificationText!,
            style: TextStyle(
              color: _chironTextFaint,
              fontSize: 11,
              height: 1.35,
              fontStyle: FontStyle.italic,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (plan.helpText != null && plan.helpText!.isNotEmpty) ...[
          const SizedBox(height: 6),
          if (plan.helpTitle != null && plan.helpTitle!.isNotEmpty)
            Text(
              plan.helpTitle!,
              style: TextStyle(
                color: _chironTextSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          if (plan.helpTitle != null && plan.helpTitle!.isNotEmpty)
            const SizedBox(height: 2),
          Text(
            plan.helpText!,
            style: TextStyle(
              color: _chironTextMuted,
              fontSize: 11,
              height: 1.35,
            ),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _issueCard(BuildContext context, _ChironReadinessIssue issue) {
    final technicalCode = issue.code;
    final title = technicalCode.isNotEmpty
        ? _issueLabel(technicalCode)
        : _groupLabel(issue.fieldGroup);
    final lifecycleNote = _isRideGeometryIssue(technicalCode)
        ? _gpsLifecycleNote()
        : _isPlaceholderIssue(technicalCode)
        ? _placeholderLifecycleNote()
        : '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _chironCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _chironBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: _chironTextPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _sampleFractionLabel(issue.count),
                style: TextStyle(
                  color: _chironGold,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          if (technicalCode.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              technicalCode,
              style: TextStyle(color: _chironTextFaint, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (issue.nextAction.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              issue.nextAction,
              style: TextStyle(color: _chironTextSecondary, fontSize: 12),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (lifecycleNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              lifecycleNote,
              style: TextStyle(color: _chironTextMuted, fontSize: 11),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          _readinessIssueActionSection(
            context,
            _resolveReadinessIssueAction(issue),
          ),
        ],
      ),
    );
  }

  Widget _fieldGroupCard(
    BuildContext context,
    _ChironReadinessFieldGroup group,
  ) {
    final firstBlocker = group.blockers.isNotEmpty
        ? group.blockers.first
        : null;
    final firstWarning = group.warnings.isNotEmpty
        ? group.warnings.first
        : null;
    final firstAction = group.nextActions.isNotEmpty
        ? group.nextActions.first
        : (firstBlocker?.nextAction ?? firstWarning?.nextAction ?? '');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _chironCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _chironBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _groupLabel(group.group),
                  style: TextStyle(
                    color: _chironTextPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: _fieldGroupStatusChip(group)),
            ],
          ),
          if (group.fields.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: group.fields
                  .map(
                    (field) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _chironPanel,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _chironBorder),
                      ),
                      child: Text(
                        _fieldLabel(field),
                        style: TextStyle(
                          color: _chironTextSecondary,
                          fontSize: 10,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          if (firstAction.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _t(
                nl: 'Volgende actie',
                en: 'Next action',
                fr: 'Action suivante',
                es: 'Siguiente acción',
              ),
              style: TextStyle(
                color: _chironTextMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              firstAction,
              style: TextStyle(color: _chironTextSecondary, fontSize: 12),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (group.group == 'ride_geometry' &&
              response.processedCount > 0 &&
              (group.status == 'blocked' ||
                  group.blockers.isNotEmpty ||
                  group.warnings.isNotEmpty)) ...[
            const SizedBox(height: 6),
            Text(
              _fieldGroupRideGeometryNote(),
              style: TextStyle(color: _chironTextMuted, fontSize: 11),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (_isSetupFieldGroup(group.group) &&
              group.status == 'blocked' &&
              group.blockers.any((b) => _isPlaceholderIssue(b.code))) ...[
            const SizedBox(height: 6),
            Text(
              _placeholderLifecycleNote(),
              style: TextStyle(color: _chironTextMuted, fontSize: 11),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (group.status == 'blocked' ||
              group.blockers.isNotEmpty ||
              group.warnings.isNotEmpty)
            _readinessIssueActionSection(
              context,
              _resolveFieldGroupAction(group),
            ),
        ],
      ),
    );
  }

  Widget _emptySection(String text) {
    return _panelBox(
      child: Text(
        text,
        style: TextStyle(color: _chironTextMuted, fontSize: 12),
      ),
    );
  }

  // Chiron-6B-3H: lifecycle / sample-aware helpers. The readiness endpoint
  // analyses at most 20 ride_stop/aankomst events. Counts are sample-scoped
  // and must never be presented as tenant-wide totals.

  bool _isRideGeometryIssue(String code) {
    if (code.isEmpty) return false;
    switch (code) {
      case 'invalid_zero_coordinate_pair':
      case 'aankomstpunt_breedtegraad':
      case 'aankomstpunt_lengtegraad':
      case 'vertrekpunt_breedtegraad':
      case 'vertrekpunt_lengtegraad':
      case 'afstand':
        return true;
      default:
        return false;
    }
  }

  bool _isPlaceholderIssue(String code) {
    return code.isNotEmpty && code.startsWith('placeholder_');
  }

  String _sampleFractionLabel(int count) {
    final processed = response.processedCount;
    if (processed <= 0) return '$count';
    return '$count/$processed';
  }

  String _gpsLifecycleNote() {
    return _t(
      nl: 'Deze controle geldt alleen voor geanalyseerde aankomst-events na START en STOP.',
      en: 'This check applies only to analyzed arrival events after START and STOP.',
      fr: 'Ce contrôle s\'applique uniquement aux événements d\'arrivée analysés après START et STOP.',
      es: 'Este control solo se aplica a eventos de llegada analizados después de START y STOP.',
    );
  }

  String _placeholderLifecycleNote() {
    return _t(
      nl: 'Deze melding kan herhaald worden per geanalyseerd rit-event zolang het profiel testgegevens bevat.',
      en: 'This message can repeat per analyzed ride event while the profile contains test data.',
      fr: 'Ce message peut se répéter par événement de course analysé tant que le profil contient des données de test.',
      es: 'Este mensaje puede repetirse por evento de viaje analizado mientras el perfil contenga datos de prueba.',
    );
  }

  String _sampleScopeNote() {
    final processed = response.processedCount;
    final matching = response.matchingEventCount;
    if (matching != null) {
      return _t(
        nl: 'Aantallen gelden voor de $processed geanalyseerde aankomst-events binnen $matching beschikbare aankomst-events, niet voor alle ritten.',
        en: 'Counts apply to the $processed analyzed arrival events within $matching available arrival events, not to all rides.',
        fr: 'Les chiffres s\'appliquent aux $processed événements d\'arrivée analysés sur $matching disponibles, pas à toutes les courses.',
        es: 'Los recuentos se aplican a los $processed eventos de llegada analizados de $matching disponibles, no a todos los viajes.',
      );
    }
    return _t(
      nl: 'Aantallen gelden voor de huidige steekproef van aankomst-events, niet voor alle ritten.',
      en: 'Counts apply to the current sample of arrival events, not to all rides.',
      fr: 'Les chiffres s\'appliquent à l\'échantillon actuel d\'événements d\'arrivée, pas à toutes les courses.',
      es: 'Los recuentos se aplican a la muestra actual de eventos de llegada, no a todos los viajes.',
    );
  }

  String _analyzedSampleLine() {
    final n = response.processedCount;
    final matching = response.matchingEventCount;
    if (matching != null && matching > 0) {
      return _t(
        nl: 'Geanalyseerd: laatste $n van $matching aankomst-events',
        en: 'Analyzed: latest $n of $matching arrival events',
        fr: 'Analysé : les $n derniers événements d\'arrivée sur $matching',
        es: 'Analizado: últimos $n de $matching eventos de llegada',
      );
    }
    return _t(
      nl: 'Geanalyseerd: laatste $n aankomst-events',
      en: 'Analyzed: latest $n arrival events',
      fr: 'Analysé : les $n derniers événements d\'arrivée',
      es: 'Analizado: últimos $n eventos de llegada',
    );
  }

  String _storageLine() {
    final n = response.scannedCount;
    return _t(
      nl: 'Opslag: $n compliance-events totaal, alle types inbegrepen',
      en: 'Storage: $n compliance events total, all types included',
      fr: 'Stockage : $n événements de conformité au total, tous types inclus',
      es: 'Almacenamiento: $n eventos de cumplimiento en total, todos los tipos incluidos',
    );
  }

  String _sampleBasedCheckNote() {
    return _t(
      nl: 'Ritregistratiecontrole op basis van een beperkte steekproef.',
      en: 'Ride registration check based on a limited sample.',
      fr: 'Contrôle d\'enregistrement de course basé sur un échantillon limité.',
      es: 'Control de registro de viaje basado en una muestra limitada.',
    );
  }

  String _notTestedYetTitle() {
    return _t(
      nl: 'Ritregistratie nog niet getest',
      en: 'Ride registration not tested yet',
      fr: 'Enregistrement de course pas encore testé',
      es: 'Registro de viaje aún no probado',
    );
  }

  String _notTestedYetBody() {
    return _t(
      nl: 'GPS, afstand en tijdlijn kunnen pas worden gecontroleerd na een echte rit met START en STOP.',
      en: 'GPS, distance, and timeline can only be checked after a real ride with START and STOP.',
      fr: 'Le GPS, la distance et la chronologie ne peuvent être contrôlés qu\'après une vraie course avec START et STOP.',
      es: 'GPS, distancia y cronología solo se pueden comprobar después de un viaje real con START y STOP.',
    );
  }

  String _noArrivalEventsLine() {
    return _t(
      nl: 'Nog geen aankomst-events geanalyseerd.',
      en: 'No arrival events analyzed yet.',
      fr: 'Aucun événement d\'arrivée analysé pour l\'instant.',
      es: 'Aún no se han analizado eventos de llegada.',
    );
  }

  String _noArrivalEventsFoundLine() {
    return _t(
      nl: 'Nog geen aankomst-events gevonden.',
      en: 'No arrival events found yet.',
      fr: 'Aucun événement d\'arrivée trouvé pour l\'instant.',
      es: 'Aún no se han encontrado eventos de llegada.',
    );
  }

  String _zeroProcessedArrivalLine() {
    final matching = response.matchingEventCount;
    if (matching != null && matching == 0) {
      return _noArrivalEventsFoundLine();
    }
    return _noArrivalEventsLine();
  }

  String _moreCandidatesLine() {
    return _t(
      nl: 'Meer aankomst-events beschikbaar dan in deze steekproef.',
      en: 'More arrival events are available than included in this sample.',
      fr: 'D\'autres événements d\'arrivée sont disponibles au-delà de cet échantillon.',
      es: 'Hay más eventos de llegada disponibles fuera de esta muestra.',
    );
  }

  String _firstTestRideHintLine() {
    return _t(
      nl: 'Ritregistratie is nog niet getest. Voer een eerste echte testrit uit met START en STOP.',
      en: 'Ride registration has not been tested yet. Perform a first real test ride with START and STOP.',
      fr: 'L\'enregistrement de course n\'a pas encore été testé. Effectuez une première course test réelle avec START et STOP.',
      es: 'El registro del viaje aún no se ha probado. Realice un primer viaje real de prueba con START y STOP.',
    );
  }

  String _technicalReadinessScopeNote() =>
      _chironTechnicalReadinessScopeNote(lang);

  String _optionalDocumentReadinessNote() {
    return _t(
      nl: 'Optioneel — blokkeert de technische Chiron-koppeling niet.',
      en: 'Optional — does not block the technical Chiron connection.',
      fr: 'Facultatif — ne bloque pas la connexion technique Chiron.',
      es: 'Opcional — no bloquea la conexión técnica con Chiron.',
    );
  }

  bool _isOptionalDocumentComplianceIssue(_ChironReadinessIssue issue) =>
      _chironReadinessIssueIsOptionalDocument(issue);

  ({String label, Color color, IconData icon}) _lifecycleStatusVisual() {
    final processed = response.processedCount;
    if (processed <= 0) {
      return (
        label: _t(
          nl: 'Nog niet getest',
          en: 'Not tested yet',
          fr: 'Pas encore testé',
          es: 'Aún no probado',
        ),
        color: _chironTextMuted,
        icon: Icons.hourglass_empty,
      );
    }
    final summary = response.report.summary;
    final hasTechnicalBlockers = _chironTechnicalBlockers(
      response.report.topBlockers,
    ).isNotEmpty;
    if (!hasTechnicalBlockers && summary.officialReadyCount == processed) {
      return (
        label: _t(
          nl: 'Steekproef klaar',
          en: 'Sample ready',
          fr: 'Échantillon prêt',
          es: 'Muestra lista',
        ),
        color: _chironSuccess,
        icon: Icons.verified_outlined,
      );
    }
    if (!hasTechnicalBlockers) {
      return (
        label: _t(
          nl: 'Technisch in orde',
          en: 'Technically healthy',
          fr: 'Techniquement en ordre',
          es: 'Técnicamente en orden',
        ),
        color: _chironSuccess,
        icon: Icons.check_circle_outline,
      );
    }
    return (
      label: _t(
        nl: 'Aandacht nodig in steekproef',
        en: 'Needs attention in sample',
        fr: 'Attention requise dans l\'échantillon',
        es: 'Requiere atención en la muestra',
      ),
      color: _chironWarning,
      icon: Icons.warning_amber_outlined,
    );
  }

  Widget _lifecycleStatusChip() {
    final visual = _lifecycleStatusVisual();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: visual.color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: visual.color.withOpacity(0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, size: 14, color: visual.color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              visual.label,
              style: TextStyle(
                color: visual.color,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rideRegistrationNotTestedPanel() {
    return _panelBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.directions_car_outlined,
                size: 16,
                color: _chironTextMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _notTestedYetTitle(),
                  style: TextStyle(
                    color: _chironTextPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _notTestedYetBody(),
            style: TextStyle(color: _chironTextSecondary, fontSize: 12),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _issueShareTitle(_ChironReadinessIssue issue) {
    final label = issue.code.isNotEmpty
        ? _issueLabel(issue.code)
        : _groupLabel(issue.fieldGroup);
    if (issue.code.isNotEmpty) {
      return '$label (${issue.code})';
    }
    return label;
  }

  String _buildShareText() {
    final report = response.report;
    final summary = report.summary;
    final processed = response.processedCount;
    final buffer = StringBuffer();

    buffer.writeln(
      _t(
        nl: 'Chiron readinessrapport',
        en: 'Chiron readiness report',
        fr: 'Rapport de préparation Chiron',
        es: 'Informe de preparación Chiron',
      ),
    );
    buffer.writeln();
    buffer.writeln(
      '${_t(nl: 'Status', en: 'Status', fr: 'Statut', es: 'Estado')}: '
      '${_lifecycleStatusVisual().label}',
    );
    if (processed > 0) {
      buffer.writeln(_analyzedSampleLine());
    } else {
      buffer.writeln(_zeroProcessedArrivalLine());
    }
    buffer.writeln(
      _t(
        nl: 'Compliance-events in opslag: ${response.scannedCount}, alle types inbegrepen',
        en: 'Stored compliance events: ${response.scannedCount}, all types included',
        fr: 'Événements de conformité stockés : ${response.scannedCount}, tous types inclus',
        es: 'Eventos de cumplimiento almacenados: ${response.scannedCount}, todos los tipos incluidos',
      ),
    );
    if (response.hasMoreCandidates) {
      buffer.writeln(_moreCandidatesLine());
    }
    if (processed > 0) {
      buffer.writeln(
        _t(
          nl: 'Aantallen gelden voor deze steekproef, niet voor alle ritten.',
          en: 'Counts apply to this sample, not to all rides.',
          fr: 'Les chiffres s\'appliquent à cet échantillon, pas à toutes les courses.',
          es: 'Los recuentos se aplican a esta muestra, no a todos los viajes.',
        ),
      );
    }
    buffer.writeln(
      _t(
        nl: 'Ritregistratie is pas volledig controleerbaar na een echte rit met START en STOP.',
        en: 'Ride registration can only be fully checked after a real ride with START and STOP.',
        fr: 'L\'enregistrement de course ne peut être entièrement contrôlé qu\'après une vraie course avec START et STOP.',
        es: 'El registro del viaje solo se puede comprobar por completo tras un viaje real con START y STOP.',
      ),
    );

    buffer.writeln();
    buffer.writeln(
      _t(
        nl: 'Tellingen binnen deze steekproef:',
        en: 'Counts within this sample:',
        fr: 'Comptages dans cet échantillon :',
        es: 'Recuentos dentro de esta muestra:',
      ),
    );
    String fracOrDash(int v) => processed > 0 ? _sampleFractionLabel(v) : '—';
    buffer.writeln(
      '${_t(nl: 'Geblokkeerd', en: 'Blocked', fr: 'Bloqué', es: 'Bloqueado')}: '
      '${fracOrDash(summary.blockedCount)}',
    );
    buffer.writeln(
      '${_t(nl: 'Review nodig', en: 'Review needed', fr: 'Revue requise', es: 'Revisión necesaria')}: '
      '${fracOrDash(summary.reviewRequiredCount)}',
    );
    buffer.writeln(
      '${_t(nl: 'Klaar voor Chiron-test', en: 'Ready for Chiron test', fr: 'Prêt pour le test Chiron', es: 'Listo para prueba Chiron')}: '
      '${fracOrDash(summary.officialReadyCount)}',
    );
    buffer.writeln(
      '${_t(nl: 'Volgordecontrole', en: 'Sequence check', fr: 'Contrôle de séquence', es: 'Control de secuencia')}: '
      '${fracOrDash(summary.sequenceUnsafeCount)}',
    );

    if (report.topBlockers.isNotEmpty) {
      final technicalBlockers = _chironTechnicalBlockers(report.topBlockers);
      final optionalDocumentBlockers = _chironOptionalDocumentBlockers(
        report.topBlockers,
      );
      buffer.writeln();
      buffer.writeln(
        _t(
          nl: 'Belangrijkste technische blockers (in steekproef):',
          en: 'Top technical blockers (in sample):',
          fr: 'Principaux blocages techniques (dans l\'échantillon) :',
          es: 'Principales bloqueos técnicos (en la muestra):',
        ),
      );
      if (technicalBlockers.isEmpty) {
        buffer.writeln(
          _t(
            nl: 'Geen technische blockers gevonden in deze steekproef.',
            en: 'No technical blockers found in this sample.',
            fr: 'Aucun blocage technique trouvé dans cet échantillon.',
            es: 'No se encontraron bloqueos técnicos en esta muestra.',
          ),
        );
      }
      var index = 1;
      for (final issue in technicalBlockers.take(10)) {
        buffer.writeln(
          '${index++}. ${_issueShareTitle(issue)} — ${_sampleFractionLabel(issue.count)}',
        );
        if (issue.nextAction.isNotEmpty) {
          buffer.writeln(
            '   ${_t(nl: 'Actie', en: 'Action', fr: 'Action', es: 'Acción')}: '
            '${issue.nextAction}',
          );
        }
      }
      if (optionalDocumentBlockers.isNotEmpty) {
        buffer.writeln();
        buffer.writeln(
          _t(
            nl: 'Optioneel documentenbeheer (blokkeert Chiron niet):',
            en: 'Optional document management (does not block Chiron):',
            fr: 'Gestion documentaire facultative (ne bloque pas Chiron) :',
            es: 'Gestión documental opcional (no bloquea Chiron):',
          ),
        );
        index = 1;
        for (final issue in optionalDocumentBlockers.take(10)) {
          buffer.writeln(
            '${index++}. ${_issueShareTitle(issue)} — ${_sampleFractionLabel(issue.count)}',
          );
          if (issue.nextAction.isNotEmpty) {
            buffer.writeln(
              '   ${_t(nl: 'Actie', en: 'Action', fr: 'Action', es: 'Acción')}: '
              '${issue.nextAction}',
            );
          }
        }
      }
    }

    buffer.writeln();
    buffer.writeln(_technicalReadinessScopeNote());

    if (report.topWarnings.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(
        _t(
          nl: 'Waarschuwingen (in steekproef):',
          en: 'Warnings (in sample):',
          fr: 'Avertissements (dans l\'échantillon) :',
          es: 'Advertencias (en la muestra):',
        ),
      );
      var index = 1;
      for (final issue in report.topWarnings.take(10)) {
        buffer.writeln(
          '${index++}. ${_issueShareTitle(issue)} — ${_sampleFractionLabel(issue.count)}',
        );
        if (issue.nextAction.isNotEmpty) {
          buffer.writeln(
            '   ${_t(nl: 'Actie', en: 'Action', fr: 'Action', es: 'Acción')}: '
            '${issue.nextAction}',
          );
        }
      }
    }

    if (report.policyNotes.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(
        _t(
          nl: 'Beleidsnotities:',
          en: 'Policy notes:',
          fr: 'Notes de politique :',
          es: 'Notas de política:',
        ),
      );
      for (final note in report.policyNotes) {
        buffer.writeln('- $note');
      }
    }

    return buffer.toString().trimRight();
  }

  Future<void> _shareReport(BuildContext context) async {
    if (!response.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Rapport niet beschikbaar.',
              en: 'Report not available.',
              fr: 'Rapport non disponible.',
              es: 'Informe no disponible.',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final text = _buildShareText();
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Rapport niet beschikbaar.',
              en: 'Report not available.',
              fr: 'Rapport non disponible.',
              es: 'Informe no disponible.',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final subject = _t(
      nl: 'Chiron readinessrapport',
      en: 'Chiron readiness report',
      fr: 'Rapport de préparation Chiron',
      es: 'Informe de preparación Chiron',
    );

    try {
      await Share.share(text, subject: subject);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Rapport gekopieerd.',
              en: 'Report copied.',
              fr: 'Rapport copié.',
              es: 'Informe copiado.',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = response.report;
    final summary = report.summary;
    final technicalBlockers = _chironTechnicalBlockers(report.topBlockers);
    final optionalDocumentBlockers = _chironOptionalDocumentBlockers(
      report.topBlockers,
    );

    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: _chironBg,
          appBar: AppBar(
            backgroundColor: _chironBg,
            foregroundColor: _chironTextPrimary,
            title: Text(
              _t(
                nl: 'Chiron readinessrapport',
                en: 'Chiron readiness report',
                fr: 'Rapport de préparation Chiron',
                es: 'Informe de preparación Chiron',
              ),
            ),
            actions: [
              IconButton(
                onPressed: () => _shareReport(context),
                tooltip: _t(
                  nl: 'Delen',
                  en: 'Share',
                  fr: 'Partager',
                  es: 'Compartir',
                ),
                icon: Icon(Icons.share_outlined, color: _chironGold),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _baseCard(
                title: _t(
                  nl: 'Status',
                  en: 'Status',
                  fr: 'Statut',
                  es: 'Estado',
                ),
                child: _panelBox(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _t(
                                nl: 'Status',
                                en: 'Status',
                                fr: 'Statut',
                                es: 'Estado',
                              ),
                              style: TextStyle(
                                color: _chironTextMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          _lifecycleStatusChip(),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (response.processedCount > 0) ...[
                        Text(
                          _analyzedSampleLine(),
                          style: TextStyle(
                            color: _chironTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _storageLine(),
                          style: TextStyle(
                            color: _chironTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                        if (response.hasMoreCandidates) ...[
                          const SizedBox(height: 4),
                          Text(
                            _moreCandidatesLine(),
                            style: TextStyle(
                              color: _chironTextSecondary,
                              fontSize: 12,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          _sampleBasedCheckNote(),
                          style: TextStyle(
                            color: _chironTextMuted,
                            fontSize: 11,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ] else ...[
                        Text(
                          _zeroProcessedArrivalLine(),
                          style: TextStyle(
                            color: _chironTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _firstTestRideHintLine(),
                          style: TextStyle(
                            color: _chironTextSecondary,
                            fontSize: 12,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _storageLine(),
                          style: TextStyle(
                            color: _chironTextMuted,
                            fontSize: 11,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (report.generatedAtUtc.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          report.generatedAtUtc,
                          style: TextStyle(
                            color: _chironTextFaint,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        _t(
                          nl: 'Preflightcontrole — geen officiële Chiron-submit uitgevoerd.',
                          en: 'Preflight check — no official Chiron submission performed.',
                          fr: 'Contrôle préalable — aucun envoi officiel Chiron effectué.',
                          es: 'Comprobación previa — no se ha realizado ningún envío oficial a Chiron.',
                        ),
                        style: TextStyle(color: _chironTextFaint, fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _technicalReadinessScopeNote(),
                        style: TextStyle(color: _chironTextMuted, fontSize: 11),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              if (response.processedCount == 0)
                _baseCard(
                  title: _t(
                    nl: 'Ritregistratie',
                    en: 'Ride registration',
                    fr: 'Enregistrement de course',
                    es: 'Registro de viaje',
                  ),
                  child: _rideRegistrationNotTestedPanel(),
                ),
              _baseCard(
                title: _t(
                  nl: 'Samenvatting',
                  en: 'Summary',
                  fr: 'Résumé',
                  es: 'Resumen',
                ),
                subtitle: _t(
                  nl: 'Tellingen binnen deze steekproef',
                  en: 'Counts within this sample',
                  fr: 'Comptages dans cet échantillon',
                  es: 'Recuentos dentro de esta muestra',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _metricGrid([
                      _metricTile(
                        label: _t(
                          nl: 'Geblokkeerd',
                          en: 'Blocked',
                          fr: 'Bloqué',
                          es: 'Bloqueado',
                        ),
                        value: response.processedCount > 0
                            ? _sampleFractionLabel(summary.blockedCount)
                            : '—',
                        valueColor: summary.blockedCount > 0
                            ? _chironDanger
                            : null,
                      ),
                      _metricTile(
                        label: _t(
                          nl: 'Review nodig',
                          en: 'Review needed',
                          fr: 'Revue requise',
                          es: 'Revisión necesaria',
                        ),
                        value: response.processedCount > 0
                            ? _sampleFractionLabel(summary.reviewRequiredCount)
                            : '—',
                        valueColor: summary.reviewRequiredCount > 0
                            ? _chironWarning
                            : null,
                      ),
                      _metricTile(
                        label: _t(
                          nl: 'Klaar',
                          en: 'Ready',
                          fr: 'Prêt',
                          es: 'Listo',
                        ),
                        value: response.processedCount > 0
                            ? _sampleFractionLabel(summary.officialReadyCount)
                            : '—',
                        valueColor: summary.officialReadyCount > 0
                            ? _chironSuccess
                            : null,
                      ),
                      _metricTile(
                        label: _t(
                          nl: 'Formaat geldig',
                          en: 'Format valid',
                          fr: 'Format valide',
                          es: 'Formato válido',
                        ),
                        value: response.processedCount > 0
                            ? _sampleFractionLabel(summary.formatValidCount)
                            : '—',
                      ),
                      _metricTile(
                        label: _t(
                          nl: 'Niet van toepassing',
                          en: 'Not applicable',
                          fr: 'Non applicable',
                          es: 'No aplicable',
                        ),
                        value: response.processedCount > 0
                            ? _sampleFractionLabel(summary.notApplicableCount)
                            : '—',
                      ),
                      _metricTile(
                        label: _t(
                          nl: 'Volgorde',
                          en: 'Sequence',
                          fr: 'Séquence',
                          es: 'Secuencia',
                        ),
                        value: response.processedCount > 0
                            ? _sampleFractionLabel(summary.sequenceUnsafeCount)
                            : '—',
                        valueColor: summary.sequenceUnsafeCount > 0
                            ? _chironWarning
                            : null,
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Text(
                      response.processedCount > 0
                          ? _sampleScopeNote()
                          : _t(
                              nl: 'Nog niet getest. Aantallen verschijnen na een eerste echte rit met START en STOP.',
                              en: 'Not tested yet. Counts appear after a first real ride with START and STOP.',
                              fr: 'Pas encore testé. Les chiffres apparaissent après une première course réelle avec START et STOP.',
                              es: 'Aún no probado. Los recuentos aparecen tras un primer viaje real con START y STOP.',
                            ),
                      style: TextStyle(color: _chironTextMuted, fontSize: 11),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _baseCard(
                title: _t(
                  nl: 'Belangrijkste technische blockers',
                  en: 'Top technical blockers',
                  fr: 'Principaux blocages techniques',
                  es: 'Principales bloqueos técnicos',
                ),
                child: technicalBlockers.isEmpty
                    ? _emptySection(
                        response.processedCount == 0
                            ? _t(
                                nl: 'Nog niet getest. Voer een echte rit met START en STOP uit voordat ritregistratie kan worden gecontroleerd.',
                                en: 'Not tested yet. Run a real ride with START and STOP before ride registration can be checked.',
                                fr: 'Pas encore testé. Effectuez une vraie course avec START et STOP avant de pouvoir contrôler l\'enregistrement de course.',
                                es: 'Aún no probado. Realice un viaje real con START y STOP antes de comprobar el registro del viaje.',
                              )
                            : _t(
                                nl: 'Geen technische blockers gevonden in deze steekproef.',
                                en: 'No technical blockers found in this sample.',
                                fr: 'Aucun blocage technique trouvé dans cet échantillon.',
                                es: 'No se encontraron bloqueos técnicos en esta muestra.',
                              ),
                      )
                    : Column(
                        children: technicalBlockers
                            .take(10)
                            .map((issue) => _issueCard(context, issue))
                            .toList(growable: false),
                      ),
              ),
              if (optionalDocumentBlockers.isNotEmpty)
                _baseCard(
                  title: _t(
                    nl: 'Optioneel documentenbeheer',
                    en: 'Optional document management',
                    fr: 'Gestion documentaire facultative',
                    es: 'Gestión documental opcional',
                  ),
                  subtitle: _optionalDocumentReadinessNote(),
                  child: Column(
                    children: optionalDocumentBlockers
                        .take(10)
                        .map((issue) => _issueCard(context, issue))
                        .toList(growable: false),
                  ),
                ),
              _baseCard(
                title: _t(
                  nl: 'Waarschuwingen',
                  en: 'Warnings',
                  fr: 'Avertissements',
                  es: 'Advertencias',
                ),
                child: report.topWarnings.isEmpty
                    ? _emptySection(
                        response.processedCount == 0
                            ? _t(
                                nl: 'Nog niet getest. Waarschuwingen zijn pas zichtbaar na geanalyseerde aankomst-events.',
                                en: 'Not tested yet. Warnings appear after analyzed arrival events.',
                                fr: 'Pas encore testé. Les avertissements apparaissent après des événements d\'arrivée analysés.',
                                es: 'Aún no probado. Las advertencias aparecen tras eventos de llegada analizados.',
                              )
                            : _t(
                                nl: 'Geen waarschuwingen gevonden in deze steekproef.',
                                en: 'No warnings found in this sample.',
                                fr: 'Aucun avertissement trouvé dans cet échantillon.',
                                es: 'No se encontraron advertencias en esta muestra.',
                              ),
                      )
                    : Column(
                        children: report.topWarnings
                            .take(10)
                            .map((issue) => _issueCard(context, issue))
                            .toList(growable: false),
                      ),
              ),
              _baseCard(
                title: _t(
                  nl: 'Controle per onderdeel',
                  en: 'Checks by area',
                  fr: 'Contrôle par composant',
                  es: 'Control por componente',
                ),
                child: report.fieldGroups.isEmpty
                    ? _emptySection(
                        _t(
                          nl: 'Geen onderdelen beschikbaar.',
                          en: 'No sections available.',
                          fr: 'Aucune section disponible.',
                          es: 'No hay secciones disponibles.',
                        ),
                      )
                    : Column(
                        children: report.fieldGroups
                            .map((group) => _fieldGroupCard(context, group))
                            .toList(growable: false),
                      ),
              ),
              _baseCard(
                title: _t(
                  nl: 'Beleidsnotities',
                  en: 'Policy notes',
                  fr: 'Notes de politique',
                  es: 'Notas de política',
                ),
                child: report.policyNotes.isEmpty
                    ? _emptySection(
                        _t(
                          nl: 'Geen officiële Chiron-submit uitgevoerd.',
                          en: 'No official Chiron submission performed.',
                          fr: 'Aucun envoi officiel Chiron effectué.',
                          es: 'No se ha realizado ningún envío oficial a Chiron.',
                        ),
                      )
                    : Column(
                        children: report.policyNotes
                            .map(
                              (note) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 14,
                                      color: _chironTextMuted,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        note,
                                        style: TextStyle(
                                          color: _chironTextSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
              ),
              if (report.sampleIssues.isNotEmpty)
                _baseCard(
                  title: _t(
                    nl: 'Technische voorbeelden',
                    en: 'Technical examples',
                    fr: 'Exemples techniques',
                    es: 'Ejemplos técnicos',
                  ),
                  child: Column(
                    children: report.sampleIssues
                        .take(5)
                        .map(
                          (sample) => Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _chironCard,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _chironBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _issueLabel(sample.issue),
                                  style: TextStyle(
                                    color: _chironTextPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (sample.issue.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    sample.issue,
                                    style: TextStyle(
                                      color: _chironTextFaint,
                                      fontSize: 10,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                if (sample.bookingId.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    sample.bookingId,
                                    style: TextStyle(
                                      color: _chironTextSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                                if (sample.eventType.isNotEmpty ||
                                    sample.officialStatus.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      if (sample.eventType.isNotEmpty)
                                        sample.eventType,
                                      if (sample.officialStatus.isNotEmpty)
                                        sample.officialStatus,
                                    ].join(' · '),
                                    style: TextStyle(
                                      color: _chironTextFaint,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

Widget _baseCard({
  required String title,
  required Widget child,
  String? subtitle,
}) {
  return Card(
    color: _chironCard,
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: _chironBorder),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: _chironGold,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(color: _chironTextSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _HubActionCard extends StatelessWidget {
  const _HubActionCard({
    required this.title,
    required this.subtitle,
    required this.trailingIcon,
    required this.onTap,
    this.note,
  });

  final String title;
  final String subtitle;
  final IconData trailingIcon;
  final VoidCallback onTap;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _chironCard,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _chironBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _chironGold,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _chironTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if ((note ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _chironPanel,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: _chironBorder),
                        ),
                        child: Text(
                          note!,
                          style: TextStyle(
                            color: _chironChipText,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(trailingIcon, color: _chironGold.withOpacity(0.95)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChironReadinessChecklistPage extends StatelessWidget {
  const _ChironReadinessChecklistPage();

  AppLanguage get _lang => appConfig.currentLanguage;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (_lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return en;
    }
  }

  bool _hasText(String? value) => (value ?? '').trim().isNotEmpty;

  DateTime? _parseDateOnly(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    final normalized = raw.length >= 10 ? raw.substring(0, 10) : raw;
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  Widget _metric({
    required String label,
    required String value,
    required bool ready,
    Color? accent,
  }) {
    final resolvedAccent = accent ?? (ready ? _chironSuccess : _chironWarning);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ready ? Icons.check_circle_outline : Icons.warning_amber_outlined,
            size: 16,
            color: resolvedAccent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: _chironTextSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: _chironTextPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  int _sectionScore(List<bool> checks) {
    if (checks.isEmpty) return 0;
    final ok = checks.where((v) => v).length;
    return ((ok * 100) / checks.length).round();
  }

  Widget _emptyState(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _chironPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _chironBorder),
      ),
      child: Text(
        text,
        style: TextStyle(color: _chironTextMuted, fontSize: 12),
      ),
    );
  }

  ({String label, Color color, IconData icon}) _overallStatus({
    required int score,
    required int criticalCount,
    required int attentionCount,
  }) {
    if (criticalCount > 0 || score < 50) {
      return (
        label: _t(nl: 'Kritiek', en: 'Critical', fr: 'Critique', es: 'Crítico'),
        color: _chironDanger,
        icon: Icons.error_outline,
      );
    }
    if (attentionCount > 0 || score < 80) {
      return (
        label: _t(
          nl: 'Aandacht nodig',
          en: 'Attention needed',
          fr: 'Attention requise',
          es: 'Atención requerida',
        ),
        color: _chironWarning,
        icon: Icons.warning_amber_rounded,
      );
    }
    return (
      label: _t(nl: 'In orde', en: 'Healthy', fr: 'En ordre', es: 'En orden'),
      color: _chironSuccess,
      icon: Icons.check_circle_outline,
    );
  }

  Widget _attentionGroup({
    required String title,
    required List<({String text, bool critical})> items,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: _chironGold,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          ...items.map((item) {
            final critical = item.critical;
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: critical ? _chironDangerSoft : _chironWarningSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: critical
                      ? _chironDanger.withOpacity(0.5)
                      : _chironWarning.withOpacity(0.45),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    critical
                        ? Icons.priority_high_rounded
                        : Icons.warning_amber_rounded,
                    size: 16,
                    color: critical ? _chironDanger : _chironWarning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.text,
                      style: TextStyle(
                        color: _chironTextSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _attentionActionCard({
    required String title,
    required String body,
    required String actionLabel,
    required IconData icon,
    required Color accent,
    VoidCallback? onTap,
  }) {
    const borderRadius = BorderRadius.all(Radius.circular(12));
    final content = Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withOpacity(0.35)),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _chironTextPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    color: _chironTextSecondary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withOpacity(0.35)),
                  ),
                  child: Text(
                    actionLabel,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _chironPanel,
        borderRadius: borderRadius,
        border: Border.all(color: _chironBorder),
      ),
      clipBehavior: onTap != null ? Clip.antiAlias : Clip.none,
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: borderRadius,
                onTap: onTap,
                child: content,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        appLanguageNotifier,
        companyProfileNotifier,
        localBackendBusinessProfileNotifier,
        localBackendTaxProfileNotifier,
        vehiclesNotifier,
        driversNotifier,
        driverDocumentsNotifier,
        businessThemeNotifier,
      ]),
      builder: (context, _) {
        final profile = companyProfileNotifier.value;
        final backendBiz = localBackendBusinessProfileNotifier.value;
        final backendTax = localBackendTaxProfileNotifier.value;

        final visibleVehicles = vehiclesNotifier.value
            .where(
              (v) => fleetRecordBelongsToActiveCompanyOrLegacy(v.companyId),
            )
            .toList(growable: false);
        final visibleDrivers = driversNotifier.value
            .where(
              (d) => fleetRecordBelongsToActiveCompanyOrLegacy(d.companyId),
            )
            .toList(growable: false);

        final vehicleCount = visibleVehicles.length;
        final vehiclesWithPlate = visibleVehicles
            .where((v) => _hasText(v.licensePlate))
            .length;
        final vehiclesWithExploitation = visibleVehicles
            .where((v) => _hasText(v.exploitationLicenseNumber))
            .length;
        final vehiclesWithRegistration = visibleVehicles
            .where((v) => _hasText(v.vehicleRegistrationNumber))
            .length;
        final vehiclesWithAssignedDriver = visibleVehicles
            .where((v) => _hasText(v.driverId))
            .length;

        final driverCount = visibleDrivers.length;
        final activeDriverCount = visibleDrivers
            .where((d) => d.isActive)
            .length;
        final driversWithCardNumber = visibleDrivers
            .where((d) => _hasText(d.taxiDriverCardNumber))
            .length;
        final driversWithCardExpiry = visibleDrivers
            .where((d) => _hasText(d.taxiDriverCardExpiry))
            .length;
        final driversMissingCardInfo = visibleDrivers
            .where(
              (d) =>
                  !_hasText(d.taxiDriverCardNumber) ||
                  !_hasText(d.taxiDriverCardExpiry),
            )
            .length;

        final allVisibleDocs = <DriverDocument>[];
        var coreGapCount = 0;
        for (final driver in visibleDrivers) {
          final docs = DriverDocumentsStore.instance.documentsVisibleForDriver(
            driver.id,
          );
          allVisibleDocs.addAll(docs);
          if (DriverDocumentsStore.instance.hasCoreDocumentGapForDriver(
            driver.id,
          )) {
            coreGapCount += 1;
          }
        }

        final totalDocs = allVisibleDocs.length;
        final approvedDocs = allVisibleDocs
            .where((d) => d.status == DriverDocumentStatuses.approved)
            .length;
        final pendingDocs = allVisibleDocs
            .where((d) => d.status == DriverDocumentStatuses.pendingReview)
            .length;
        final rejectedDocs = allVisibleDocs
            .where((d) => d.status == DriverDocumentStatuses.rejected)
            .length;
        final expiredDocs = allVisibleDocs
            .where(
              (d) =>
                  d.status == DriverDocumentStatuses.expired ||
                  d.isExpiredByDate,
            )
            .length;

        final today = DateTime.now();
        final todayDate = DateTime(today.year, today.month, today.day);
        final expirySoonLimit = todayDate.add(const Duration(days: 30));
        final expiringSoon = allVisibleDocs.where((d) {
          final parsed = _parseDateOnly(d.expiryDate);
          if (parsed == null) return false;
          if (parsed.isBefore(todayDate)) return false;
          return !parsed.isAfter(expirySoonLimit);
        }).length;

        final hasCompanyName =
            _hasText(profile?.companyName) ||
            _hasText(backendBiz?.companyName) ||
            _hasText(backendBiz?.legalName);
        final hasRegistration =
            _hasText(profile?.companyId) ||
            _hasText(backendBiz?.companyRegistrationNumber);
        final hasVat =
            _hasText(profile?.vatNumber) || _hasText(backendBiz?.vatNumber);
        final hasAddress =
            (_hasText(profile?.addressLine) || _hasText(backendBiz?.address)) &&
            (_hasText(profile?.postalCode) || _hasText(backendBiz?.postcode)) &&
            (_hasText(profile?.city) || _hasText(backendBiz?.city));
        final hasContactEmails =
            _hasText(profile?.companyEmail) ||
            _hasText(profile?.supportEmail) ||
            _hasText(profile?.billingEmail) ||
            _hasText(profile?.bookingEmail) ||
            _hasText(profile?.notificationEmail) ||
            _hasText(backendBiz?.email) ||
            _hasText(backendBiz?.bookingEmail) ||
            _hasText(backendBiz?.invoiceEmail);
        final hasTaxProfile = backendTax != null;

        final companyChecks = <bool>[
          hasCompanyName,
          hasRegistration,
          hasAddress,
          hasContactEmails,
          hasTaxProfile,
        ];
        final companyFieldsComplete = companyChecks.every((check) => check);
        final driverChecks = <bool>[
          driverCount > 0,
          activeDriverCount > 0,
          driverCount > 0 && driversWithCardNumber == driverCount,
          driverCount > 0 && driversWithCardExpiry == driverCount,
        ];
        final vehicleChecks = <bool>[
          vehicleCount > 0,
          vehicleCount > 0 && vehiclesWithPlate == vehicleCount,
          vehicleCount > 0 && vehiclesWithExploitation == vehicleCount,
          vehicleCount > 0 && vehiclesWithRegistration == vehicleCount,
          vehicleCount > 0 && vehiclesWithAssignedDriver == vehicleCount,
        ];
        final documentChecks = <bool>[
          coreGapCount == 0,
          rejectedDocs == 0,
          expiredDocs == 0,
        ];

        final companyScore = _sectionScore(companyChecks);
        final driverScore = _sectionScore(driverChecks);
        final vehicleScore = _sectionScore(vehicleChecks);
        final docScore = _sectionScore(documentChecks);
        final technicalScore = ((companyScore + driverScore + vehicleScore) / 3)
            .round();

        final companyAttention = <({String text, bool critical})>[];
        final driverAttention = <({String text, bool critical})>[];
        final vehicleAttention = <({String text, bool critical})>[];
        final docAttention = <({String text, bool critical})>[];

        if (!hasCompanyName) {
          companyAttention.add((
            text: _t(
              nl: 'Bedrijfsnaam/juridische naam ontbreekt.',
              en: 'Company/legal name is missing.',
              fr: 'Le nom de l entreprise est manquant.',
              es: 'Falta el nombre de la empresa/legal.',
            ),
            critical: true,
          ));
        }
        if (!hasRegistration) {
          companyAttention.add((
            text: _t(
              nl: 'Registratie/KBO/ondernemingsnummer ontbreekt.',
              en: 'Registration/KBO/company number is missing.',
              fr: 'Le numéro d entreprise est manquant.',
              es: 'Falta el número de registro/empresa.',
            ),
            critical: true,
          ));
        }
        if (!hasAddress) {
          companyAttention.add((
            text: _t(
              nl: 'Bedrijfsadres is onvolledig.',
              en: 'Company address is incomplete.',
              fr: 'L adresse de l entreprise est incomplète.',
              es: 'La dirección de la empresa está incompleta.',
            ),
            critical: true,
          ));
        }
        if (!hasContactEmails) {
          companyAttention.add((
            text: _t(
              nl: 'Contact-/e-mailvelden zijn onvolledig.',
              en: 'Contact/email fields are incomplete.',
              fr: 'Les champs contact/e-mail sont incomplets.',
              es: 'Los campos de contacto/correo están incompletos.',
            ),
            critical: false,
          ));
        }
        if (driversMissingCardInfo > 0) {
          driverAttention.add((
            text: _t(
              nl: '$driversMissingCardInfo chauffeur(s) missen kaartnummer en/of vervaldatum.',
              en: '$driversMissingCardInfo driver(s) missing card number and/or expiry.',
              fr: '$driversMissingCardInfo chauffeur(s) sans numéro et/ou expiration de carte.',
              es: '$driversMissingCardInfo conductor(es) sin número y/o vencimiento de tarjeta.',
            ),
            critical: false,
          ));
        }
        final vehiclesMissingRequired = visibleVehicles.where((v) {
          return !_hasText(v.licensePlate) ||
              !_hasText(v.exploitationLicenseNumber) ||
              !_hasText(v.vehicleRegistrationNumber) ||
              !_hasText(v.driverId);
        }).length;
        if (vehiclesMissingRequired > 0) {
          vehicleAttention.add((
            text: _t(
              nl: '$vehiclesMissingRequired voertuig(en) missen verplichte velden.',
              en: '$vehiclesMissingRequired vehicle(s) missing required fields.',
              fr: '$vehiclesMissingRequired véhicule(s) sans champs obligatoires.',
              es: '$vehiclesMissingRequired vehículo(s) sin campos obligatorios.',
            ),
            critical: false,
          ));
        }
        if (coreGapCount > 0) {
          docAttention.add((
            text: _t(
              nl: coreGapCount == 1
                  ? '1 chauffeur heeft nog geen belangrijke documenten geüpload.'
                  : '$coreGapCount chauffeurs hebben nog geen belangrijke documenten geüpload.',
              en: coreGapCount == 1
                  ? '1 driver has not uploaded key documents yet.'
                  : '$coreGapCount drivers have not uploaded key documents yet.',
              fr: coreGapCount == 1
                  ? '1 chauffeur n’a pas encore téléversé de documents importants.'
                  : '$coreGapCount chauffeurs n’ont pas encore téléversé de documents importants.',
              es: coreGapCount == 1
                  ? '1 conductor aún no ha cargado documentos importantes.'
                  : '$coreGapCount conductores aún no han cargado documentos importantes.',
            ),
            critical: false,
          ));
        }
        if (expiredDocs > 0 || rejectedDocs > 0) {
          docAttention.add((
            text: _t(
              nl: 'Er zijn verlopen of afgewezen documenten.',
              en: 'There are expired or rejected documents.',
              fr: 'Il y a des documents expirés ou rejetés.',
              es: 'Hay documentos caducados o rechazados.',
            ),
            critical: false,
          ));
        }

        final companyStatusLabel = profile == null
            ? ''
            : profile.isSuspended
            ? profile.verificationBadgeLabel(_lang)
            : profile.isVerified
            ? profile.verificationBadgeLabel(_lang)
            : companyFieldsComplete
            ? _t(
                nl: 'Compleet · verificatie openstaand',
                en: 'Complete · verification pending',
                fr: 'Complet · vérification en attente',
                es: 'Completo · verificación pendiente',
              )
            : profile.verificationBadgeLabel(_lang);
        final technicalAttention = <({String text, bool critical})>[
          ...companyAttention,
          ...driverAttention,
          ...vehicleAttention,
        ];
        final criticalAttentionCount = technicalAttention
            .where((x) => x.critical)
            .length;
        final status = _overallStatus(
          score: technicalScore,
          criticalCount: criticalAttentionCount,
          attentionCount: technicalAttention.length,
        );
        final optionalDocumentNote = _t(
          nl: 'Optioneel — telt niet mee voor operationele gereedheid.',
          en: 'Optional — not included in operational readiness.',
          fr: 'Facultatif — non inclus dans la préparation opérationnelle.',
          es: 'Opcional — no cuenta para la preparación operativa.',
        );
        final checklistScopeNote = _companyChecklistScopeNote(_lang);
        final optionalDocumentsHelperNote =
            _companyChecklistOptionalDocumentsNote(_lang);
        final showOperationalCompleteDocsPending =
            technicalScore >= 100 && docScore < 100;

        return Scaffold(
          backgroundColor: _chironBg,
          appBar: AppBar(
            backgroundColor: _chironBg,
            foregroundColor: _chironTextPrimary,
            title: Text(
              _t(
                nl: 'Bedrijfschecklist',
                en: 'Company checklist',
                fr: 'Checklist entreprise',
                es: 'Checklist de empresa',
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _baseCard(
                title: _t(
                  nl: 'Overzicht',
                  en: 'Overall summary',
                  fr: 'Résumé global',
                  es: 'Resumen general',
                ),
                subtitle: _t(
                  nl: 'Alleen-lezen overzicht. Er worden geen gegevens aangepast.',
                  en: 'Read-only overview. No data is modified.',
                  fr: 'Vue en lecture seule. Aucune donnée n est modifiée.',
                  es: 'Vista de solo lectura. No se modifican datos.',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _t(
                                  nl: 'Score operationele gegevens',
                                  en: 'Operational data score',
                                  fr: 'Score des données opérationnelles',
                                  es: 'Puntuación de datos operativos',
                                ),
                                style: TextStyle(color: _chironTextSecondary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _t(
                                  nl: 'Bedrijf, chauffeurs en voertuigen — exclusief documenten',
                                  en: 'Company, drivers and vehicles — excluding documents',
                                  fr: 'Entreprise, chauffeurs et véhicules — hors documents',
                                  es: 'Empresa, conductores y vehículos — sin documentos',
                                ),
                                style: TextStyle(
                                  color: _chironTextMuted,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '$technicalScore%',
                          style: TextStyle(
                            color: _chironTextPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: status.color.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: status.color.withOpacity(0.55),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(status.icon, size: 14, color: status.color),
                              const SizedBox(width: 6),
                              Text(
                                status.label,
                                style: TextStyle(
                                  color: status.color,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _t(
                            nl: 'Bedrijf $companyScore% • Chauffeurs $driverScore% • Voertuigen $vehicleScore%',
                            en: 'Company $companyScore% • Drivers $driverScore% • Vehicles $vehicleScore%',
                            fr: 'Entreprise $companyScore% • Chauffeurs $driverScore% • Véhicules $vehicleScore%',
                            es: 'Empresa $companyScore% • Conductores $driverScore% • Vehículos $vehicleScore%',
                          ),
                          style: TextStyle(
                            color: _chironTextMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: technicalScore / 100,
                      minHeight: 8,
                      backgroundColor: _chironProgressTrack,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        technicalScore >= 80
                            ? _chironSuccess
                            : (technicalScore >= 50
                                  ? _chironWarning
                                  : _chironWarning),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      checklistScopeNote,
                      style: TextStyle(color: _chironTextMuted, fontSize: 11),
                    ),
                    if (showOperationalCompleteDocsPending) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _chironTextMuted.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _chironBorder.withOpacity(0.85),
                          ),
                        ),
                        child: Text(
                          _t(
                            nl: 'Operationele gegevens zijn compleet ($technicalScore%). Optionele documenten: $docScore% — telt niet mee voor deze score.',
                            en: 'Operational data is complete ($technicalScore%). Optional documents: $docScore% — not included in this score.',
                            fr: 'Les données opérationnelles sont complètes ($technicalScore%). Documents facultatifs : $docScore% — non inclus dans ce score.',
                            es: 'Los datos operativos están completos ($technicalScore%). Documentos opcionales: $docScore% — no cuenta para esta puntuación.',
                          ),
                          style: TextStyle(
                            color: _chironTextSecondary,
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _metric(
                      label: _t(
                        nl: 'Aandachtspunten',
                        en: 'Attention items',
                        fr: 'Points d attention',
                        es: 'Puntos de atención',
                      ),
                      value: technicalAttention.length.toString(),
                      ready: technicalAttention.isEmpty,
                      accent: status.color,
                    ),
                  ],
                ),
              ),
              _baseCard(
                title: _t(
                  nl: 'Bedrijfsprofiel readiness',
                  en: 'Company profile readiness',
                  fr: 'Préparation profil entreprise',
                  es: 'Preparación de perfil de empresa',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (profile != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${_t(nl: 'Status', en: 'Status', fr: 'Statut', es: 'Estado')}:',
                              style: TextStyle(color: _chironTextSecondary),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: profile.isSuspended
                                    ? _chironTokens().statusSuspendedBg
                                    : profile.isVerified
                                    ? _chironTokens().statusVerifiedBg
                                    : _chironTokens().statusPendingBg,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                companyStatusLabel,
                                style: TextStyle(
                                  color: _chironTextPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    _metric(
                      label: _t(
                        nl: 'Bedrijfs-/juridische naam aanwezig',
                        en: 'Company/legal name present',
                        fr: 'Nom société/légal présent',
                        es: 'Nombre empresa/legal presente',
                      ),
                      value: hasCompanyName ? '1/1' : '0/1',
                      ready: hasCompanyName,
                    ),
                    _metric(
                      label: _t(
                        nl: 'Registratie/KBO aanwezig',
                        en: 'Registration/KBO present',
                        fr: 'Numéro d entreprise présent',
                        es: 'Registro/KBO presente',
                      ),
                      value: hasRegistration ? '1/1' : '0/1',
                      ready: hasRegistration,
                    ),
                    _metric(
                      label: _t(
                        nl: 'BTW-profiel aanwezig',
                        en: 'VAT profile present',
                        fr: 'Profil TVA présent',
                        es: 'Perfil IVA presente',
                      ),
                      value: (hasVat || hasTaxProfile) ? '1/1' : '0/1',
                      ready: hasVat || hasTaxProfile,
                    ),
                    _metric(
                      label: _t(
                        nl: 'Adres/postcode/stad aanwezig',
                        en: 'Address/postcode/city present',
                        fr: 'Adresse/code postal/ville présents',
                        es: 'Dirección/código postal/ciudad presentes',
                      ),
                      value: hasAddress ? '1/1' : '0/1',
                      ready: hasAddress,
                    ),
                    _metric(
                      label: _t(
                        nl: 'Contact/e-mailvelden aanwezig',
                        en: 'Contact/email fields present',
                        fr: 'Champs contact/e-mail présents',
                        es: 'Campos de contacto/correo presentes',
                      ),
                      value: hasContactEmails ? '1/1' : '0/1',
                      ready: hasContactEmails,
                    ),
                    if (profile == null && backendBiz == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _emptyState(
                          _t(
                            nl: 'Geen lokaal bedrijfsprofiel gevonden. Vul gegevens in via Bedrijfsinstellingen.',
                            en: 'No local company profile found. Fill details in Business settings.',
                            fr: 'Aucun profil entreprise local trouvé. Complétez les paramètres entreprise.',
                            es: 'No se encontró perfil local de empresa. Completa la configuración de empresa.',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _baseCard(
                title: _t(
                  nl: 'Chauffeurgegevens readiness',
                  en: 'Driver details readiness',
                  fr: 'Préparation chauffeurs',
                  es: 'Preparación conductores',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t(
                        nl: 'Dit controleert ingevulde chauffeursgegevens (kaartnummer, vervaldatum). Geüploade documentbestanden staan apart in de optionele documentenmap.',
                        en: 'This checks completed driver profile fields (card number, expiry). Uploaded document files are tracked separately in the optional document folder.',
                        fr: 'Ceci contrôle les données chauffeur renseignées (numéro de carte, expiration). Les fichiers de documents téléversés sont suivis séparément dans le dossier documentaire facultatif.',
                        es: 'Esto comprueba los datos de conductor completados (número de tarjeta, vencimiento). Los archivos de documentos cargados se siguen por separado en la carpeta documental opcional.',
                      ),
                      style: TextStyle(
                        color: _chironTextMuted,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _metric(
                      label: _t(
                        nl: 'Totaal chauffeurs',
                        en: 'Total drivers',
                        fr: 'Total chauffeurs',
                        es: 'Total conductores',
                      ),
                      value: driverCount.toString(),
                      ready: driverCount > 0,
                    ),
                    _metric(
                      label: _t(
                        nl: 'Actieve chauffeurs',
                        en: 'Active drivers',
                        fr: 'Chauffeurs actifs',
                        es: 'Conductores activos',
                      ),
                      value: activeDriverCount.toString(),
                      ready: activeDriverCount > 0,
                    ),
                    _metric(
                      label: _t(
                        nl: 'Met chauffeurskaartnummer',
                        en: 'With taxi driver card number',
                        fr: 'Avec numéro carte chauffeur',
                        es: 'Con número de tarjeta',
                      ),
                      value: '$driversWithCardNumber/$driverCount',
                      ready:
                          driverCount > 0 &&
                          driversWithCardNumber == driverCount,
                    ),
                    _metric(
                      label: _t(
                        nl: 'Met vervaldatum chauffeurskaart',
                        en: 'With taxi driver card expiry',
                        fr: 'Avec expiration carte chauffeur',
                        es: 'Con vencimiento de tarjeta',
                      ),
                      value: '$driversWithCardExpiry/$driverCount',
                      ready:
                          driverCount > 0 &&
                          driversWithCardExpiry == driverCount,
                    ),
                    _metric(
                      label: _t(
                        nl: 'Ontbrekende kaartinfo',
                        en: 'Missing card info',
                        fr: 'Infos carte manquantes',
                        es: 'Información de tarjeta faltante',
                      ),
                      value: driversMissingCardInfo.toString(),
                      ready: driversMissingCardInfo == 0,
                    ),
                    if (driverCount == 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _emptyState(
                          _t(
                            nl: 'Nog geen chauffeurs gevonden voor dit bedrijf.',
                            en: 'No drivers found for this company yet.',
                            fr: 'Aucun chauffeur trouvé pour cette entreprise.',
                            es: 'No se encontraron conductores para esta empresa.',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _baseCard(
                title: _t(
                  nl: 'Voertuig readiness',
                  en: 'Vehicle readiness',
                  fr: 'Préparation véhicules',
                  es: 'Preparación vehículos',
                ),
                child: Column(
                  children: [
                    _metric(
                      label: _t(
                        nl: 'Totaal voertuigen',
                        en: 'Total vehicles',
                        fr: 'Total véhicules',
                        es: 'Total vehículos',
                      ),
                      value: vehicleCount.toString(),
                      ready: vehicleCount > 0,
                    ),
                    _metric(
                      label: _t(
                        nl: 'Met nummerplaat',
                        en: 'With license plate',
                        fr: 'Avec plaque',
                        es: 'Con matrícula',
                      ),
                      value: '$vehiclesWithPlate/$vehicleCount',
                      ready:
                          vehicleCount > 0 && vehiclesWithPlate == vehicleCount,
                    ),
                    _metric(
                      label: _t(
                        nl: 'Met exploitatievergunningnummer',
                        en: 'With exploitation license number',
                        fr: 'Avec numéro licence exploitation',
                        es: 'Con número de licencia de explotación',
                      ),
                      value: '$vehiclesWithExploitation/$vehicleCount',
                      ready:
                          vehicleCount > 0 &&
                          vehiclesWithExploitation == vehicleCount,
                    ),
                    _metric(
                      label: _t(
                        nl: 'Met chassis/registratienummer',
                        en: 'With registration/VIN/chassis',
                        fr: 'Avec immatriculation/VIN/châssis',
                        es: 'Con matrícula/VIN/chasis',
                      ),
                      value: '$vehiclesWithRegistration/$vehicleCount',
                      ready:
                          vehicleCount > 0 &&
                          vehiclesWithRegistration == vehicleCount,
                    ),
                    _metric(
                      label: _t(
                        nl: 'Met toegewezen chauffeur',
                        en: 'With assigned driver',
                        fr: 'Avec chauffeur attribué',
                        es: 'Con conductor asignado',
                      ),
                      value: '$vehiclesWithAssignedDriver/$vehicleCount',
                      ready:
                          vehicleCount > 0 &&
                          vehiclesWithAssignedDriver == vehicleCount,
                    ),
                    if (vehicleCount == 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _emptyState(
                          _t(
                            nl: 'Nog geen voertuigen gevonden voor dit bedrijf.',
                            en: 'No vehicles found for this company yet.',
                            fr: 'Aucun véhicule trouvé pour cette entreprise.',
                            es: 'No se encontraron vehículos para esta empresa.',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _chironPanel.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _chironBorder.withOpacity(0.9)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.folder_open_outlined,
                          size: 16,
                          color: _chironTextMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _t(
                            nl: 'Optioneel — apart van operationele gegevens',
                            en: 'Optional — separate from operational data',
                            fr: 'Facultatif — séparé des données opérationnelles',
                            es: 'Opcional — separado de los datos operativos',
                          ),
                          style: TextStyle(
                            color: _chironTextMuted,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _baseCard(
                      title: _t(
                        nl: 'Optioneel documentenbeheer',
                        en: 'Optional document management',
                        fr: 'Gestion documentaire facultative',
                        es: 'Gestión documental opcional',
                      ),
                      subtitle: optionalDocumentNote,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            optionalDocumentsHelperNote,
                            style: TextStyle(
                              color: _chironTextMuted,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _t(
                                    nl: 'Volledigheid documentenmap',
                                    en: 'Document folder completeness',
                                    fr: 'Complétude du dossier documents',
                                    es: 'Completitud de la carpeta de documentos',
                                  ),
                                  style: TextStyle(color: _chironTextSecondary),
                                ),
                              ),
                              Text(
                                '$docScore%',
                                style: TextStyle(
                                  color: _chironTextPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: docScore / 100,
                            minHeight: 6,
                            backgroundColor: _chironProgressTrack,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              docScore >= 80
                                  ? _chironSuccess
                                  : _chironTextMuted,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _metric(
                            label: _t(
                              nl: 'Totaal geüploade documenten',
                              en: 'Total uploaded documents',
                              fr: 'Total documents téléversés',
                              es: 'Total documentos cargados',
                            ),
                            value: totalDocs.toString(),
                            ready: totalDocs > 0,
                          ),
                          _metric(
                            label: _t(
                              nl: 'Goedgekeurd',
                              en: 'Approved',
                              fr: 'Approuvés',
                              es: 'Aprobados',
                            ),
                            value: approvedDocs.toString(),
                            ready: approvedDocs == totalDocs && totalDocs > 0,
                          ),
                          _metric(
                            label: _t(
                              nl: 'In behandeling',
                              en: 'Pending',
                              fr: 'En cours',
                              es: 'Pendientes',
                            ),
                            value: pendingDocs.toString(),
                            ready: pendingDocs == 0,
                          ),
                          _metric(
                            label: _t(
                              nl: 'Afgewezen',
                              en: 'Rejected',
                              fr: 'Rejetés',
                              es: 'Rechazados',
                            ),
                            value: rejectedDocs.toString(),
                            ready: rejectedDocs == 0,
                          ),
                          _metric(
                            label: _t(
                              nl: 'Verlopen',
                              en: 'Expired',
                              fr: 'Expirés',
                              es: 'Caducados',
                            ),
                            value: expiredDocs.toString(),
                            ready: expiredDocs == 0,
                          ),
                          _metric(
                            label: _t(
                              nl: 'Verlopen binnen 30 dagen',
                              en: 'Expiring within 30 days',
                              fr: 'Expire sous 30 jours',
                              es: 'Caducan en 30 días',
                            ),
                            value: expiringSoon.toString(),
                            ready: expiringSoon == 0,
                          ),
                          _metric(
                            label: _t(
                              nl: 'Chauffeurs zonder belangrijke uploads',
                              en: 'Drivers missing key uploads',
                              fr: 'Chauffeurs sans téléversements importants',
                              es: 'Conductores sin cargas importantes',
                            ),
                            value: coreGapCount.toString(),
                            ready: coreGapCount == 0,
                          ),
                          if (totalDocs == 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: _emptyState(
                                _t(
                                  nl: 'Nog geen documenten gevonden. Beheer documenten via Chauffeurs beheren.',
                                  en: 'No documents found yet. Manage documents in Manage drivers.',
                                  fr: 'Aucun document trouvé. Gérez les documents dans Gérer les chauffeurs.',
                                  es: 'No se encontraron documentos. Gestiona documentos en Gestionar conductores.',
                                ),
                              ),
                            ),
                          if (coreGapCount > 0 || docAttention.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            if (coreGapCount > 0)
                              _attentionActionCard(
                                title: _t(
                                  nl: 'Chauffeurdocumenten aanvullen',
                                  en: 'Complete driver documents',
                                  fr: 'Compléter les documents chauffeurs',
                                  es: 'Completar documentos de conductores',
                                ),
                                body: _t(
                                  nl: coreGapCount == 1
                                      ? '1 chauffeur heeft nog geen belangrijke documenten geüpload. Dit is optioneel en helpt bij opvolging.'
                                      : '$coreGapCount chauffeurs hebben nog geen belangrijke documenten geüpload. Dit is optioneel en helpt bij opvolging.',
                                  en: coreGapCount == 1
                                      ? '1 driver has not uploaded key documents yet. This is optional and helps with follow-up.'
                                      : '$coreGapCount drivers have not uploaded key documents yet. This is optional and helps with follow-up.',
                                  fr: coreGapCount == 1
                                      ? '1 chauffeur n’a pas encore téléversé de documents importants. Facultatif et utile pour le suivi.'
                                      : '$coreGapCount chauffeurs n’ont pas encore téléversé de documents importants. Facultatif et utile pour le suivi.',
                                  es: coreGapCount == 1
                                      ? '1 conductor aún no ha cargado documentos importantes. Opcional y útil para el seguimiento.'
                                      : '$coreGapCount conductores aún no han cargado documentos importantes. Opcional y útil para el seguimiento.',
                                ),
                                actionLabel: _t(
                                  nl: 'Open chauffeurs',
                                  en: 'Open drivers',
                                  fr: 'Ouvrir chauffeurs',
                                  es: 'Abrir conductores',
                                ),
                                icon: Icons.badge_outlined,
                                accent: _chironTextMuted,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          companyDriverManagementPage(),
                                    ),
                                  );
                                },
                              ),
                            if (docAttention.isNotEmpty)
                              _attentionGroup(
                                title: _t(
                                  nl: 'Documentenmap',
                                  en: 'Document folder',
                                  fr: 'Dossier documents',
                                  es: 'Carpeta de documentos',
                                ),
                                items: docAttention,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _baseCard(
                title: _t(
                  nl: 'Aandacht nodig',
                  en: 'Attention needed',
                  fr: 'Attention requise',
                  es: 'Atención requerida',
                ),
                child: technicalAttention.isEmpty
                    ? _emptyState(
                        _t(
                          nl: 'Geen aandachtspunten gevonden.',
                          en: 'No attention items found.',
                          fr: 'Aucun point d attention.',
                          es: 'No se encontraron puntos de atención.',
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (vehiclesMissingRequired > 0)
                            _attentionActionCard(
                              title: _t(
                                nl: 'Voertuiggegevens aanvullen',
                                en: 'Complete vehicle details',
                                fr: 'Compléter les données véhicule',
                                es: 'Completar datos del vehículo',
                              ),
                              body: _t(
                                nl: vehiclesMissingRequired == 1
                                    ? '1 voertuig mist verplichte velden.'
                                    : '$vehiclesMissingRequired voertuigen missen verplichte velden.',
                                en: vehiclesMissingRequired == 1
                                    ? '1 vehicle is missing required fields.'
                                    : '$vehiclesMissingRequired vehicles are missing required fields.',
                                fr: vehiclesMissingRequired == 1
                                    ? '1 véhicule manque des champs obligatoires.'
                                    : '$vehiclesMissingRequired véhicules manquent des champs obligatoires.',
                                es: vehiclesMissingRequired == 1
                                    ? '1 vehículo no tiene campos obligatorios.'
                                    : '$vehiclesMissingRequired vehículos no tienen campos obligatorios.',
                              ),
                              actionLabel: _t(
                                nl: 'Voertuigen controleren',
                                en: 'Check vehicles',
                                fr: 'Vérifier les véhicules',
                                es: 'Revisar vehículos',
                              ),
                              icon: Icons.directions_car_filled_outlined,
                              accent: _chironWarning,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const VehicleManagementPage(),
                                  ),
                                );
                              },
                            ),
                          _attentionGroup(
                            title: _t(
                              nl: 'Bedrijf',
                              en: 'Company',
                              fr: 'Entreprise',
                              es: 'Empresa',
                            ),
                            items: companyAttention,
                          ),
                          _attentionGroup(
                            title: _t(
                              nl: 'Chauffeurs',
                              en: 'Drivers',
                              fr: 'Chauffeurs',
                              es: 'Conductores',
                            ),
                            items: driverAttention,
                          ),
                          _attentionGroup(
                            title: _t(
                              nl: 'Voertuigen',
                              en: 'Vehicles',
                              fr: 'Véhicules',
                              es: 'Vehículos',
                            ),
                            items: vehicleAttention,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChironLocalLedgerPage extends StatelessWidget {
  const _ChironLocalLedgerPage();

  AppLanguage get _lang => appConfig.currentLanguage;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (_lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return en;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      builder: (context, variant, _) {
        final tokens = _chironTokensForVariant(variant);
        return Theme(
          data: _chironMaterialTheme(tokens),
          child: Scaffold(
            backgroundColor: tokens.background,
            appBar: AppBar(
              backgroundColor: tokens.background,
              foregroundColor: tokens.textPrimary,
              title: Text(
                _t(
                  nl: 'Lokaal rittenregister',
                  en: 'Local ride register',
                  fr: 'Registre local des trajets',
                  es: 'Registro local de viajes',
                ),
              ),
            ),
            body: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _baseCard(
                  title: _t(
                    nl: 'Lokaal rittenregister',
                    en: 'Local ride register',
                    fr: 'Registre local des trajets',
                    es: 'Registro local de viajes',
                  ),
                  subtitle: _t(
                    nl: 'Laatste lokale ritten (alleen-lezen, geen synchronisatie).',
                    en: 'Latest local rides (read-only, no synchronization).',
                    fr: 'Derniers trajets locaux (lecture seule, sans synchronisation).',
                    es: 'Últimos viajes locales (solo lectura, sin sincronización).',
                  ),
                  child: _LocalComplianceLedgerSection(lang: _lang),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/* CHIRON-P0-2A: The former `_complianceApiBaseUrl` compile-time constant and
 * its companion `_complianceAdminToken` have been removed. Every user-facing
 * Chiron/compliance call now routes through the booking worker at
 * `appConfig.bookingBaseUrl` using `resolveCompanyOwnerAuthHeaders()`. The
 * platform admin bearer is not shipped in the client. Destructive
 * dev-reset routes are not exposed to company-owner sessions and are hidden
 * from the release-mode UI. */

/// CHIRON-P0-2A: shared error message used by every booking-worker Chiron
/// proxy call for a redacted "not authorized" path. Localized copy lives at
/// the call site; this label is emitted only in debug logs and NEVER
/// includes the raw bearer or the compliance payload body.
const String _chironBookingWorkerProxyLogTag = 'CHIRON_COMPANY_SESSION_PROXY';

/// CHIRON-P0-2A: builds a booking-worker-scoped Chiron URI. Every user-facing
/// readiness / score-summary / recent-events call routes through the booking
/// worker so the direct compliance admin bearer is never needed on the
/// device. Extra query parameters (limit, since, event_type) are passed
/// through as-is; the booking worker sanitizes them again before forwarding.
Uri _chironBookingReadonlyEndpoint(
  String path, {
  required String tenantId,
  required String companyId,
  Map<String, String>? extraQuery,
}) {
  final params = <String, String>{
    'tenant_id': tenantId,
    'company_id': companyId,
    'tenantId': tenantId,
    'companyId': companyId,
  };
  if (extraQuery != null) {
    for (final entry in extraQuery.entries) {
      if (entry.key.trim().isEmpty) continue;
      if (entry.value.trim().isEmpty) continue;
      params[entry.key] = entry.value;
    }
  }
  return Uri.parse('${appConfig.bookingBaseUrl}$path').replace(
    queryParameters: params,
  );
}

class _ChironScoreSummaryCounts {
  const _ChironScoreSummaryCounts({
    required this.readyCount,
    required this.warningCount,
    required this.blockerCount,
  });

  final int readyCount;
  final int warningCount;
  final int blockerCount;

  factory _ChironScoreSummaryCounts.fromJson(Map<String, dynamic> json) {
    return _ChironScoreSummaryCounts(
      readyCount: _parseChironInt(json['ready_count']),
      warningCount: _parseChironInt(json['warning_count']),
      blockerCount: _parseChironInt(json['blocker_count']),
    );
  }
}

class _ChironNewestEventSummary {
  const _ChironNewestEventSummary({required this.score});

  final int? score;

  factory _ChironNewestEventSummary.fromJson(Map<String, dynamic> json) {
    return _ChironNewestEventSummary(
      score: _parseNullableChironInt(json['score']),
    );
  }
}

class _ChironScoreSummaryResponse {
  const _ChironScoreSummaryResponse({
    required this.ok,
    required this.totalEvents,
    required this.counts,
    required this.newestEvents,
    required this.errorMessage,
  });

  final bool ok;
  final int totalEvents;
  final _ChironScoreSummaryCounts counts;
  final List<_ChironNewestEventSummary> newestEvents;
  final String errorMessage;

  factory _ChironScoreSummaryResponse.error({
    String tenantId = '',
    String companyId = '',
    required String errorMessage,
  }) {
    return _ChironScoreSummaryResponse(
      ok: false,
      totalEvents: 0,
      counts: const _ChironScoreSummaryCounts(
        readyCount: 0,
        warningCount: 0,
        blockerCount: 0,
      ),
      newestEvents: const <_ChironNewestEventSummary>[],
      errorMessage: errorMessage,
    );
  }

  factory _ChironScoreSummaryResponse.fromJson(Map<String, dynamic> json) {
    final scoreSummaryRaw = json['score_summary'];
    final scoreSummary = scoreSummaryRaw is Map
        ? Map<String, dynamic>.from(scoreSummaryRaw)
        : const <String, dynamic>{};
    final newestEventsRaw = json['newest_events'];
    final newestEvents = newestEventsRaw is List
        ? newestEventsRaw
              .whereType<Map>()
              .map(
                (event) => _ChironNewestEventSummary.fromJson(
                  Map<String, dynamic>.from(event),
                ),
              )
              .toList(growable: false)
        : const <_ChironNewestEventSummary>[];

    return _ChironScoreSummaryResponse(
      ok: json['ok'] == true,
      totalEvents: _parseChironInt(json['total_events']),
      counts: _ChironScoreSummaryCounts.fromJson(scoreSummary),
      newestEvents: newestEvents,
      errorMessage: '',
    );
  }
}

class _ChironReadinessSummary {
  const _ChironReadinessSummary({
    required this.officialReadyCount,
    required this.blockedCount,
    required this.reviewRequiredCount,
    required this.formatValidCount,
    required this.notApplicableCount,
    required this.sequenceUnsafeCount,
  });

  final int officialReadyCount;
  final int blockedCount;
  final int reviewRequiredCount;
  final int formatValidCount;
  final int notApplicableCount;
  final int sequenceUnsafeCount;

  factory _ChironReadinessSummary.fromJson(Map<String, dynamic> json) {
    return _ChironReadinessSummary(
      officialReadyCount: _parseChironInt(json['official_ready_count']),
      blockedCount: _parseChironInt(json['blocked_count']),
      reviewRequiredCount: _parseChironInt(json['review_required_count']),
      formatValidCount: _parseChironInt(json['format_valid_count']),
      notApplicableCount: _parseChironInt(json['not_applicable_count']),
      sequenceUnsafeCount: _parseChironInt(json['sequence_unsafe_count']),
    );
  }

  static const empty = _ChironReadinessSummary(
    officialReadyCount: 0,
    blockedCount: 0,
    reviewRequiredCount: 0,
    formatValidCount: 0,
    notApplicableCount: 0,
    sequenceUnsafeCount: 0,
  );
}

class _ChironReadinessIssue {
  const _ChironReadinessIssue({
    required this.code,
    required this.count,
    required this.fieldGroup,
    required this.nextAction,
  });

  final String code;
  final int count;
  final String fieldGroup;
  final String nextAction;

  factory _ChironReadinessIssue.fromJson(Map<String, dynamic> json) {
    return _ChironReadinessIssue(
      code: (json['code'] ?? json['issue'] ?? '').toString().trim(),
      count: _parseChironInt(json['count']),
      fieldGroup: (json['field_group'] ?? '').toString().trim(),
      nextAction: (json['next_action'] ?? '').toString().trim(),
    );
  }
}

class _ChironReadinessFieldGroup {
  const _ChironReadinessFieldGroup({
    required this.group,
    required this.status,
    required this.fields,
    required this.blockers,
    required this.warnings,
    required this.nextActions,
  });

  final String group;
  final String status;
  final List<String> fields;
  final List<_ChironReadinessIssue> blockers;
  final List<_ChironReadinessIssue> warnings;
  final List<String> nextActions;

  factory _ChironReadinessFieldGroup.fromJson(Map<String, dynamic> json) {
    List<_ChironReadinessIssue> parseIssues(dynamic raw) {
      if (raw is! List) return const <_ChironReadinessIssue>[];
      return raw
          .whereType<Map>()
          .map(
            (item) =>
                _ChironReadinessIssue.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
    }

    final fieldsRaw = json['fields'];
    final fields = fieldsRaw is List
        ? fieldsRaw
              .map((f) => (f ?? '').toString().trim())
              .where((f) => f.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    final nextActionsRaw = json['next_actions'];
    final nextActions = nextActionsRaw is List
        ? nextActionsRaw
              .map((a) => (a ?? '').toString().trim())
              .where((a) => a.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    return _ChironReadinessFieldGroup(
      group: (json['group'] ?? '').toString().trim(),
      status: (json['status'] ?? '').toString().trim(),
      fields: fields,
      blockers: parseIssues(json['blockers']),
      warnings: parseIssues(json['warnings']),
      nextActions: nextActions,
    );
  }
}

class _ChironReadinessSampleIssue {
  const _ChironReadinessSampleIssue({
    required this.issue,
    required this.bookingId,
    required this.eventType,
    required this.officialStatus,
  });

  final String issue;
  final String bookingId;
  final String eventType;
  final String officialStatus;

  factory _ChironReadinessSampleIssue.fromJson(Map<String, dynamic> json) {
    return _ChironReadinessSampleIssue(
      issue: (json['issue'] ?? json['code'] ?? '').toString().trim(),
      bookingId: (json['booking_id'] ?? '').toString().trim(),
      eventType: (json['event_type'] ?? '').toString().trim(),
      officialStatus: (json['official_status'] ?? '').toString().trim(),
    );
  }
}

class _ChironReadinessReport {
  const _ChironReadinessReport({
    required this.overallStatus,
    required this.generatedAtUtc,
    required this.summary,
    required this.topBlockers,
    required this.topWarnings,
    required this.nextActions,
    required this.fieldGroups,
    required this.sampleIssues,
    required this.policyNotes,
  });

  final String overallStatus;
  final String generatedAtUtc;
  final _ChironReadinessSummary summary;
  final List<_ChironReadinessIssue> topBlockers;
  final List<_ChironReadinessIssue> topWarnings;
  final List<String> nextActions;
  final List<_ChironReadinessFieldGroup> fieldGroups;
  final List<_ChironReadinessSampleIssue> sampleIssues;
  final List<String> policyNotes;

  factory _ChironReadinessReport.fromJson(Map<String, dynamic> json) {
    final summaryRaw = json['summary'];
    final summary = summaryRaw is Map
        ? _ChironReadinessSummary.fromJson(
            Map<String, dynamic>.from(summaryRaw),
          )
        : _ChironReadinessSummary.empty;

    List<_ChironReadinessIssue> parseIssues(dynamic raw) {
      if (raw is! List) return const <_ChironReadinessIssue>[];
      return raw
          .whereType<Map>()
          .map(
            (item) =>
                _ChironReadinessIssue.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
    }

    final policyNotesRaw = json['policy_notes'];
    final policyNotes = policyNotesRaw is List
        ? policyNotesRaw
              .map((note) => (note ?? '').toString().trim())
              .where((note) => note.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    final nextActionsRaw = json['next_actions'];
    final nextActions = nextActionsRaw is List
        ? nextActionsRaw
              .map((a) => (a ?? '').toString().trim())
              .where((a) => a.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    final fieldGroupsRaw = json['field_groups'];
    final fieldGroups = fieldGroupsRaw is List
        ? fieldGroupsRaw
              .whereType<Map>()
              .map(
                (g) => _ChironReadinessFieldGroup.fromJson(
                  Map<String, dynamic>.from(g),
                ),
              )
              .toList(growable: false)
        : const <_ChironReadinessFieldGroup>[];

    final sampleIssuesRaw = json['sample_issues'];
    final sampleIssues = sampleIssuesRaw is List
        ? sampleIssuesRaw
              .whereType<Map>()
              .map(
                (s) => _ChironReadinessSampleIssue.fromJson(
                  Map<String, dynamic>.from(s),
                ),
              )
              .toList(growable: false)
        : const <_ChironReadinessSampleIssue>[];

    return _ChironReadinessReport(
      overallStatus: (json['overall_status'] ?? '').toString().trim(),
      generatedAtUtc: (json['generated_at_utc'] ?? '').toString().trim(),
      summary: summary,
      topBlockers: parseIssues(json['top_blockers']),
      topWarnings: parseIssues(json['top_warnings']),
      nextActions: nextActions,
      fieldGroups: fieldGroups,
      sampleIssues: sampleIssues,
      policyNotes: policyNotes,
    );
  }

  static const empty = _ChironReadinessReport(
    overallStatus: '',
    generatedAtUtc: '',
    summary: _ChironReadinessSummary.empty,
    topBlockers: <_ChironReadinessIssue>[],
    topWarnings: <_ChironReadinessIssue>[],
    nextActions: <String>[],
    fieldGroups: <_ChironReadinessFieldGroup>[],
    sampleIssues: <_ChironReadinessSampleIssue>[],
    policyNotes: <String>[],
  );
}

class _ChironReadinessResponse {
  const _ChironReadinessResponse({
    required this.ok,
    required this.processedCount,
    required this.scannedCount,
    required this.report,
    required this.errorMessage,
    required this.missingScope,
    required this.unauthorized,
    this.limit,
    this.eventType,
    this.matchingEventCount,
    this.hasMoreCandidates = false,
  });

  final bool ok;
  final int processedCount;
  final int scannedCount;
  final _ChironReadinessReport report;
  final String errorMessage;
  final bool missingScope;
  final bool unauthorized;
  final int? limit;
  final String? eventType;
  final int? matchingEventCount;
  final bool hasMoreCandidates;

  factory _ChironReadinessResponse.error({
    required String errorMessage,
    bool unauthorized = false,
  }) {
    return _ChironReadinessResponse(
      ok: false,
      processedCount: 0,
      scannedCount: 0,
      report: _ChironReadinessReport.empty,
      errorMessage: errorMessage,
      missingScope: false,
      unauthorized: unauthorized,
    );
  }

  factory _ChironReadinessResponse.missingScope({
    required String errorMessage,
  }) {
    return _ChironReadinessResponse(
      ok: false,
      processedCount: 0,
      scannedCount: 0,
      report: _ChironReadinessReport.empty,
      errorMessage: errorMessage,
      missingScope: true,
      unauthorized: false,
    );
  }

  factory _ChironReadinessResponse.fromJson(Map<String, dynamic> json) {
    final reportRaw = json['readiness_report'];
    final report = reportRaw is Map
        ? _ChironReadinessReport.fromJson(Map<String, dynamic>.from(reportRaw))
        : _ChironReadinessReport.empty;
    final eventTypeRaw = (json['event_type'] ?? '').toString().trim();

    return _ChironReadinessResponse(
      ok: json['ok'] == true,
      processedCount: _parseChironInt(json['processed_count']),
      scannedCount: _parseChironInt(json['scanned_count']),
      report: report,
      errorMessage: '',
      missingScope: false,
      unauthorized: false,
      limit: _parseNullableChironInt(json['limit']),
      eventType: eventTypeRaw.isEmpty ? null : eventTypeRaw,
      matchingEventCount: _parseNullableChironInt(json['matching_event_count']),
      hasMoreCandidates: json['has_more_candidates'] == true,
    );
  }
}

int _parseChironInt(dynamic value) => _parseNullableChironInt(value) ?? 0;

int? _parseNullableChironInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    return int.tryParse(normalized) ?? double.tryParse(normalized)?.round();
  }
  return null;
}

class RemoteComplianceEvent {
  const RemoteComplianceEvent({
    required this.key,
    required this.eventId,
    required this.eventType,
    required this.rideType,
    required this.lifecycleStatus,
    required this.status,
    required this.bookingStatus,
    required this.rideStatus,
    required this.previousStatus,
    required this.actorRole,
    required this.source,
    required this.bookingId,
    required this.publicBookingReference,
    required this.planningReference,
    required this.receiptReference,
    required this.tripId,
    required this.syncState,
    required this.createdAtUtc,
    required this.timestamps,
    required this.payment,
    required this.fare,
    required this.provenance,
    required this.refundStatus,
    required this.refundProvider,
    required this.refundAmountCents,
    required this.refundId,
    required this.creditDecision,
    required this.refundedAt,
    required this.creditStatus,
    required this.creditedAmountCents,
    required this.creditedAt,
    required this.legId,
    required this.legType,
    required this.parentBookingId,
    required this.parentStatus,
    required this.legStatus,
    required this.legPriceInclVat,
    required this.parentPriceInclVat,
    required this.waitMin,
    required this.distanceKm,
    required this.startedAtUtc,
    required this.stoppedAtUtc,
    required this.roundtripDispatchMode,
    required this.parentAssignmentMode,
    required this.assignment,
  });

  final String key;
  final String eventId;
  final String eventType;
  final String rideType;
  final String lifecycleStatus;
  final String status;
  final String bookingStatus;
  final String rideStatus;
  final String previousStatus;
  final String actorRole;
  final String source;
  final String bookingId;
  final String publicBookingReference;
  final String planningReference;
  final String receiptReference;
  final String tripId;
  final String syncState;
  final String createdAtUtc;
  final Map<String, dynamic> timestamps;
  final Map<String, dynamic> payment;
  final Map<String, dynamic> fare;
  final Map<String, dynamic> provenance;
  final String refundStatus;
  final String refundProvider;
  final int? refundAmountCents;
  final String refundId;
  final String creditDecision;
  final String refundedAt;
  final String creditStatus;
  final int? creditedAmountCents;
  final String creditedAt;
  // Roundtrip operational-leg metadata: when the persisted event carries
  // leg_id / leg_type / parent_status the dashboard surfaces ritdeel chips
  // and refuses to promote the parent dossier to "afgerond" until the parent
  // booking_status_update itself flips to COMPLETED.
  final String legId;
  final String legType;
  final String parentBookingId;
  final String parentStatus;
  final String legStatus;
  final double? legPriceInclVat;
  final double? parentPriceInclVat;
  final double? waitMin;
  final double? distanceKm;
  final String startedAtUtc;
  final String stoppedAtUtc;
  final String roundtripDispatchMode;
  final String parentAssignmentMode;
  final Map<String, dynamic> assignment;

  bool get hasLegMetadata =>
      legId.isNotEmpty || legType.isNotEmpty || parentStatus.isNotEmpty;

  factory RemoteComplianceEvent.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> asMap(Object? value) {
      if (value is Map) return Map<String, dynamic>.from(value);
      return const <String, dynamic>{};
    }

    String text(String key) => (json[key] ?? '').toString().trim();
    int? parseCents(dynamic value) {
      if (value is num) return value.round();
      if (value is String) return int.tryParse(value.trim());
      return null;
    }

    String firstText(List<String> keys, {Map<String, dynamic>? source}) {
      final root = source ?? json;
      for (final key in keys) {
        final value = (root[key] ?? '').toString().trim();
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    int? firstCents(List<String> keys, {Map<String, dynamic>? source}) {
      final root = source ?? json;
      for (final key in keys) {
        final parsed = parseCents(root[key]);
        if (parsed != null) return parsed;
      }
      return null;
    }

    final provenance = asMap(json['provenance']);
    final payment = asMap(json['payment']);
    final fareMap = asMap(json['fare']);
    final timestamps = asMap(json['timestamps']);
    final refundStatus =
        firstText(const <String>[
          'refund_status',
          'refundStatus',
        ], source: json).isNotEmpty
        ? firstText(const <String>['refund_status', 'refundStatus'])
        : firstText(const <String>[
            'refund_status',
            'refundStatus',
          ], source: payment);
    final refundProvider =
        firstText(const <String>[
          'refund_provider',
          'refundProvider',
        ], source: json).isNotEmpty
        ? firstText(const <String>['refund_provider', 'refundProvider'])
        : firstText(const <String>[
            'refund_provider',
            'refundProvider',
          ], source: payment);
    final refundId =
        firstText(const <String>[
          'refund_id',
          'refundId',
          'mollie_refund_id',
          'mollieRefundId',
        ], source: json).isNotEmpty
        ? firstText(const <String>[
            'refund_id',
            'refundId',
            'mollie_refund_id',
            'mollieRefundId',
          ])
        : firstText(const <String>[
            'refund_id',
            'refundId',
            'mollie_refund_id',
            'mollieRefundId',
          ], source: payment);
    final creditDecision =
        firstText(const <String>[
          'credit_decision',
          'creditDecision',
        ], source: json).isNotEmpty
        ? firstText(const <String>['credit_decision', 'creditDecision'])
        : firstText(const <String>[
            'credit_decision',
            'creditDecision',
          ], source: payment);
    final refundedAt =
        firstText(const <String>[
          'refunded_at',
          'refundedAt',
        ], source: json).isNotEmpty
        ? firstText(const <String>['refunded_at', 'refundedAt'])
        : (firstText(const <String>[
                'refunded_at_utc',
              ], source: timestamps).isNotEmpty
              ? firstText(const <String>['refunded_at_utc'], source: timestamps)
              : firstText(const <String>['event_at_utc'], source: timestamps));
    final refundAmountCents =
        firstCents(const <String>[
          'refund_amount_cents',
          'refundAmountCents',
        ]) ??
        firstCents(const <String>[
          'refund_amount_cents',
          'refundAmountCents',
        ], source: payment);
    final creditStatus =
        firstText(const <String>[
          'credit_status',
          'creditStatus',
        ], source: json).isNotEmpty
        ? firstText(const <String>['credit_status', 'creditStatus'])
        : firstText(const <String>[
            'credit_status',
            'creditStatus',
          ], source: payment);
    final creditedAmountCents =
        firstCents(const <String>[
          'credited_amount_cents',
          'creditedAmountCents',
        ]) ??
        firstCents(const <String>[
          'credited_amount_cents',
          'creditedAmountCents',
        ], source: payment);
    final creditedAt =
        firstText(const <String>[
          'credited_at',
          'creditedAt',
        ], source: json).isNotEmpty
        ? firstText(const <String>['credited_at', 'creditedAt'])
        : (firstText(const <String>[
                'credited_at_utc',
              ], source: timestamps).isNotEmpty
              ? firstText(const <String>['credited_at_utc'], source: timestamps)
              : firstText(const <String>['event_at_utc'], source: timestamps));

    // Roundtrip operational-leg projection: read leg metadata that the
    // compliance worker now surfaces at the top level of recent-events. Older
    // events that pre-date the [COMPLIANCE_EVENT][LEG_METADATA] projection
    // still parse cleanly with empty strings, so the dashboard continues to
    // render exactly as before for one-way bookings.
    String legText(List<String> keys) => firstText(keys);
    double? legNumber(List<String> keys, {Map<String, dynamic>? source}) {
      final root = source ?? json;
      for (final key in keys) {
        final value = root[key];
        if (value is num && value.isFinite) return value.toDouble();
        if (value is String) {
          final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
          if (parsed != null && parsed.isFinite) return parsed;
        }
      }
      return null;
    }

    double? positiveLegNumber(
      List<String> keys, {
      Map<String, dynamic>? source,
    }) {
      final value = legNumber(keys, source: source);
      if (value == null || !value.isFinite || value <= 0) return null;
      return value;
    }

    final legIdResolved = legText(const <String>['leg_id', 'legId']);
    final legTypeResolved = legText(const <String>[
      'leg_type',
      'legType',
    ]).toLowerCase();
    final isLegScopedEvent =
        legIdResolved.isNotEmpty || legTypeResolved.isNotEmpty;
    final parentBookingIdResolved = legText(const <String>[
      'parent_booking_id',
      'parentBookingId',
    ]);
    final parentStatusResolved = legText(const <String>[
      'parent_status',
      'parentStatus',
    ]).toLowerCase();
    final legStatusResolved = legText(const <String>[
      'leg_status',
      'legStatus',
    ]).toLowerCase();
    final legPriceInclVatResolved =
        positiveLegNumber(const <String>[
          'leg_price_incl_vat',
          'legPriceInclVat',
        ]) ??
        (isLegScopedEvent
            ? (positiveLegNumber(const <String>[
                    'fare_total_amount',
                    'fareTotalAmount',
                  ]) ??
                  positiveLegNumber(const <String>[
                    'total_amount',
                    'totalAmount',
                  ], source: fareMap))
            : null);
    final parentPriceInclVatResolved = legNumber(const <String>[
      'parent_price_incl_vat',
      'parentPriceInclVat',
    ]);
    final waitMinResolved =
        legNumber(const <String>['wait_min', 'waitMin']) ??
        legNumber(const <String>['wait_min', 'waitMin'], source: payment);
    final distanceKmResolved =
        legNumber(const <String>['distance_km', 'distanceKm']) ??
        legNumber(const <String>[
          'distance_km',
          'distanceKm',
        ], source: asMap(json['fare']));
    final startedAtUtcResolved =
        legText(const <String>['started_at_utc', 'startedAtUtc']).isNotEmpty
        ? legText(const <String>['started_at_utc', 'startedAtUtc'])
        : firstText(const <String>[
            'started_at_utc',
            'startedAtUtc',
          ], source: timestamps);
    final stoppedAtUtcResolved =
        legText(const <String>['stopped_at_utc', 'stoppedAtUtc']).isNotEmpty
        ? legText(const <String>['stopped_at_utc', 'stoppedAtUtc'])
        : firstText(const <String>[
            'stopped_at_utc',
            'stoppedAtUtc',
          ], source: timestamps);
    final assignmentResolved = asMap(json['assignment']);
    if (legIdResolved.isNotEmpty ||
        legTypeResolved.isNotEmpty ||
        parentStatusResolved.isNotEmpty) {
      // ignore: avoid_print
      debugPrint(
        '[BACKEND_EVENTS][LEG_STATUS_SOURCE] event_type=${text('event_type')} booking=${text('booking_id')} leg_id=${legIdResolved.isEmpty ? "-" : legIdResolved} leg_type=${legTypeResolved.isEmpty ? "-" : legTypeResolved} leg_status=${legStatusResolved.isEmpty ? "-" : legStatusResolved} parent_status=${parentStatusResolved.isEmpty ? "-" : parentStatusResolved} parent_booking=${parentBookingIdResolved.isEmpty ? "-" : parentBookingIdResolved}',
      );
    }

    return RemoteComplianceEvent(
      key: text('key'),
      eventId: text('event_id'),
      eventType: text('event_type'),
      rideType: () {
        final direct = firstText(const <String>['ride_type', 'rideType']);
        if (direct.isNotEmpty) return direct;
        final fromProvenance = firstText(const <String>[
          'ride_type',
          'rideType',
        ], source: provenance);
        if (fromProvenance.isNotEmpty) return fromProvenance;
        final fromPayment = firstText(const <String>[
          'ride_type',
          'rideType',
        ], source: payment);
        if (fromPayment.isNotEmpty) return fromPayment;
        return '';
      }(),
      lifecycleStatus: text('lifecycle_status'),
      status: text('status'),
      bookingStatus: text('booking_status'),
      rideStatus: text('ride_status'),
      previousStatus: text('previous_status'),
      actorRole: text('actor_role'),
      source: text('source').isNotEmpty
          ? text('source')
          : ((provenance['source_endpoint'] ?? '').toString().trim()),
      bookingId: text('booking_id'),
      publicBookingReference: text('public_booking_reference').isNotEmpty
          ? text('public_booking_reference')
          : (text('publicBookingReference').isNotEmpty
                ? text('publicBookingReference')
                : (text('booking_reference').isNotEmpty
                      ? text('booking_reference')
                      : (text('bookingReference').isNotEmpty
                            ? text('bookingReference')
                            : (text('public_reference').isNotEmpty
                                  ? text('public_reference')
                                  : text('publicReference'))))),
      planningReference: text('planning_reference').isNotEmpty
          ? text('planning_reference')
          : text('planningReference'),
      receiptReference: text('receipt_reference').isNotEmpty
          ? text('receipt_reference')
          : text('receiptReference'),
      tripId: text('trip_id'),
      syncState: text('sync_state'),
      createdAtUtc: text('created_at_utc'),
      timestamps: asMap(json['timestamps']),
      payment: payment,
      fare: fareMap,
      provenance: provenance,
      refundStatus: refundStatus,
      refundProvider: refundProvider,
      refundAmountCents: refundAmountCents,
      refundId: refundId,
      creditDecision: creditDecision,
      refundedAt: refundedAt,
      creditStatus: creditStatus,
      creditedAmountCents: creditedAmountCents,
      creditedAt: creditedAt,
      legId: legIdResolved,
      legType: legTypeResolved,
      parentBookingId: parentBookingIdResolved,
      parentStatus: parentStatusResolved,
      legStatus: legStatusResolved,
      legPriceInclVat: legPriceInclVatResolved,
      parentPriceInclVat: parentPriceInclVatResolved,
      waitMin: waitMinResolved,
      distanceKm: distanceKmResolved,
      startedAtUtc: startedAtUtcResolved,
      stoppedAtUtc: stoppedAtUtcResolved,
      roundtripDispatchMode: legText(const <String>[
        'roundtrip_dispatch_mode',
        'roundtripDispatchMode',
      ]).toLowerCase(),
      parentAssignmentMode: legText(const <String>[
        'parent_assignment_mode',
        'parentAssignmentMode',
      ]).toLowerCase(),
      assignment: assignmentResolved,
    );
  }
}

class RemoteComplianceEventsResponse {
  const RemoteComplianceEventsResponse({
    required this.ok,
    required this.tenantId,
    required this.companyId,
    required this.limit,
    required this.count,
    required this.malformedCount,
    required this.events,
    this.errorMessage = '',
  });

  final bool ok;
  final String tenantId;
  final String companyId;
  final int limit;
  final int count;
  final int malformedCount;
  final List<RemoteComplianceEvent> events;
  final String errorMessage;
}

/// CHIRON-LAST-GOOD-DATA-PRESERVATION-1: process-scoped last-good events for
/// the Backendmeldingen section. Cleared/replaced on company scope change.
/// Never holds tokens or credentials.
final ChironLastGoodEventsCache<RemoteComplianceEventsResponse>
_chironLastGoodRemoteEventsCache =
    ChironLastGoodEventsCache<RemoteComplianceEventsResponse>();

class _ChironRemoteCompliancePage extends StatelessWidget {
  const _ChironRemoteCompliancePage();

  AppLanguage get _lang => appConfig.currentLanguage;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (_lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return en;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      builder: (context, variant, _) {
        final tokens = _chironTokensForVariant(variant);
        return Scaffold(
          backgroundColor: tokens.background,
          appBar: AppBar(
            backgroundColor: tokens.background,
            foregroundColor: tokens.textPrimary,
            title: Text(
              _t(
                nl: 'Backendmeldingen',
                en: 'Backend messages',
                fr: 'Messages système',
                es: 'Mensajes del sistema',
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _baseCard(
                title: _t(
                  nl: 'Backendmeldingen',
                  en: 'Backend messages',
                  fr: 'Messages système',
                  es: 'Mensajes del sistema',
                ),
                subtitle: _t(
                  nl: 'Alleen-lezen meldingen uit de compliancemodule.',
                  en: 'Read-only messages from the compliance module.',
                  fr: 'Messages en lecture seule provenant du module de conformité.',
                  es: 'Mensajes de solo lectura del módulo de cumplimiento.',
                ),
                child: _RemoteComplianceEventsSection(lang: _lang),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Patch 4A: client-side category filter for the Chiron/Backendmeldingen
// list. Strictly UI-local. No backend semantics depend on these tokens.
enum _RemoteComplianceCategoryFilter {
  alles,
  gepland,
  straatritten,
  betaald,
  geannuleerd,
  creditRefund,
}

class _RemoteComplianceEventsSection extends StatefulWidget {
  const _RemoteComplianceEventsSection({required this.lang});

  final AppLanguage lang;

  @override
  State<_RemoteComplianceEventsSection> createState() =>
      _RemoteComplianceEventsSectionState();
}

class _RemoteComplianceEventsSectionState
    extends State<_RemoteComplianceEventsSection> {
  final bool _isResettingRemoteEvents = false;
  late final ChironContextLoadCoordinator _loadCoordinator;
  // Patch 4A: local-only search + category filter for the
  // Backendmeldingen list. State is reset on widget disposal; nothing
  // persists outside this section.
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _RemoteComplianceCategoryFilter _categoryFilter =
      _RemoteComplianceCategoryFilter.alles;

  // CHIRON-LAST-GOOD-DATA-PRESERVATION-1: explicit presentation state.
  // Remounts restore last-good from [_chironLastGoodRemoteEventsCache];
  // first-ever load shows loading (never an empty unavailable seed).
  bool _loading = true;
  bool _staleWarning = false;
  RemoteComplianceEventsResponse? _display;
  String? _hardError;
  String _boundScopeKey = '';

  static String _scopeKey(String tenantId, String companyId) =>
      '${tenantId.trim()}|${companyId.trim()}';

  String _defaultUnavailableMessage() => _t(
    nl: 'Systeemmeldingen uit de compliancemodule zijn niet beschikbaar.',
    en: 'System messages from the compliance module are unavailable.',
    fr: 'Les messages système du module de conformité ne sont pas disponibles.',
    es: 'Los mensajes del sistema del módulo de cumplimiento no están disponibles.',
  );

  String _staleRefreshWarningMessage() => _t(
    nl: 'Vernieuwen mislukt. De laatst geladen gegevens worden getoond.',
    en: 'Refresh failed. Showing the last loaded data.',
    fr: 'Échec de l’actualisation. Affichage des dernières données chargées.',
    es: 'Error al actualizar. Se muestran los últimos datos cargados.',
  );

  void _applyPresentation(
    ChironLastGoodPresentation<RemoteComplianceEventsResponse> presentation,
  ) {
    _loading = presentation.showLoading;
    _staleWarning = presentation.showStaleWarning;
    _display = presentation.display;
    _hardError = presentation.hardErrorMessage;
  }

  void _restoreFromCacheForActiveScope() {
    final scope = _effectiveTenantCompanyIds();
    if (scope == null) {
      _boundScopeKey = '';
      _applyPresentation(
        initialChironEventsPresentation<RemoteComplianceEventsResponse>(
          cachedForActiveScope: null,
        ),
      );
      return;
    }
    _boundScopeKey = _scopeKey(scope.tenantId, scope.companyId);
    _chironLastGoodRemoteEventsCache.clearIfScopeMismatch(
      tenantId: scope.tenantId,
      companyId: scope.companyId,
    );
    final cached = _chironLastGoodRemoteEventsCache.peek(
      tenantId: scope.tenantId,
      companyId: scope.companyId,
    );
    _applyPresentation(
      initialChironEventsPresentation<RemoteComplianceEventsResponse>(
        cachedForActiveScope: cached,
      ),
    );
  }

  void _onAuthScopeChanged() {
    if (!mounted) return;
    final scope = _effectiveTenantCompanyIds();
    final nextKey = scope == null
        ? ''
        : _scopeKey(scope.tenantId, scope.companyId);
    if (nextKey == _boundScopeKey) return;
    setState(() {
      _restoreFromCacheForActiveScope();
    });
    if (scope != null && _loadCoordinator.prerequisitesReady) {
      _loadCoordinator.requestManualRefresh();
    }
  }

  @override
  void initState() {
    super.initState();
    _restoreFromCacheForActiveScope();
    activeCompanySessionNotifier.addListener(_onAuthScopeChanged);
    companyProfileNotifier.addListener(_onAuthScopeChanged);
    _loadCoordinator = ChironContextLoadCoordinator(
      listenables: <Listenable>[
        activeCompanySessionNotifier,
        companyProfileNotifier,
      ],
      hasCompanySession: () => hasCompanyOwnerAuthContext(),
      companyId: () {
        final profile = companyProfileNotifier.value?.companyId.trim() ?? '';
        if (profile.isNotEmpty) return profile;
        return activeCompanySessionNotifier.value?.companyId.trim() ?? '';
      },
      runLoad: _performRemoteEventsLoad,
      onDiag: (stage) => debugPrint('[CHIRON_LOAD][DIAG] stage=$stage'),
    )..attach();
  }

  @override
  void dispose() {
    activeCompanySessionNotifier.removeListener(_onAuthScopeChanged);
    companyProfileNotifier.removeListener(_onAuthScopeChanged);
    _loadCoordinator.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performRemoteEventsLoad(int gen) async {
    final result = await _loadRemoteEvents();
    // Preserve latest-wins / dispose guard — do not mutate UI when stale.
    if (!_loadCoordinator.shouldApplyGeneration(gen) || !mounted) return;

    final scope = _effectiveTenantCompanyIds();
    final activeTenant = scope?.tenantId ?? '';
    final activeCompany = scope?.companyId ?? '';
    final cached = (activeTenant.isEmpty || activeCompany.isEmpty)
        ? null
        : _chironLastGoodRemoteEventsCache.peek(
            tenantId: activeTenant,
            companyId: activeCompany,
          );

    if (result.ok) {
      // Only cache presentation data already scoped to the active company.
      final resultTenant = result.tenantId.trim().isNotEmpty
          ? result.tenantId.trim()
          : activeTenant;
      final resultCompany = result.companyId.trim().isNotEmpty
          ? result.companyId.trim()
          : activeCompany;
      if (resultTenant.isNotEmpty &&
          resultCompany.isNotEmpty &&
          resultTenant == activeTenant &&
          resultCompany == activeCompany) {
        _chironLastGoodRemoteEventsCache.remember(
          tenantId: resultTenant,
          companyId: resultCompany,
          payload: result,
        );
      }
    }

    final presentation =
        applyChironEventsLoadResult<RemoteComplianceEventsResponse>(
          resultOk: result.ok,
          successPayload: result.ok ? result : null,
          resultErrorMessage: result.errorMessage,
          cachedForActiveScope: cached,
          defaultHardError: _defaultUnavailableMessage(),
        );

    if (!mounted) return;
    setState(() {
      _boundScopeKey = _scopeKey(activeTenant, activeCompany);
      _applyPresentation(presentation);
    });
  }

  void _refresh() {
    _loadCoordinator.requestManualRefresh();
  }

  // Patch 4A: build a lowercased haystack of every field the search
  // bar can match. Strictly read-only over already-loaded events.
  void _appendMapCustomerNameSearchTokens(
    List<String> tokens,
    Map<String, dynamic> map,
  ) {
    if (map.isEmpty) return;
    String s(dynamic v) => (v ?? '').toString().trim().toLowerCase();
    void add(dynamic v) {
      final token = s(v);
      if (token.isNotEmpty) tokens.add(token);
    }

    for (final key in const <String>[
      'customer_name',
      'customerName',
      'passenger_name',
      'passengerName',
      'client_name',
      'clientName',
      'custName',
    ]) {
      add(map[key]);
    }

    for (final parentKey in const <String>['customer', 'passenger', 'client']) {
      final nested = map[parentKey];
      if (nested is Map) {
        add(nested['name']);
        add(nested['customer_name']);
        add(nested['customerName']);
        add(nested['passenger_name']);
        add(nested['passengerName']);
      }
    }

    final booking = map['booking'];
    if (booking is Map) {
      add(booking['customer_name']);
      add(booking['customerName']);
      add(booking['custName']);
      final customer = booking['customer'];
      if (customer is Map) {
        add(customer['name']);
        add(customer['customer_name']);
        add(customer['customerName']);
      }
    }

    final bookingDetails = map['booking_details'] ?? map['bookingDetails'];
    if (bookingDetails is Map) {
      add(bookingDetails['customer_name']);
      add(bookingDetails['customerName']);
      add(bookingDetails['custName']);
      // In booking_details, bare `name` is the customer/passenger label.
      add(bookingDetails['name']);
      final customer = bookingDetails['customer'];
      if (customer is Map) {
        add(customer['name']);
        add(customer['customer_name']);
        add(customer['customerName']);
      }
    }
  }

  String _buildSearchHaystack(RemoteComplianceEvent e) {
    String s(dynamic v) => (v ?? '').toString().trim().toLowerCase();
    final tokens = <String>[
      s(e.eventType),
      s(e.bookingId),
      s(e.publicBookingReference),
      s(e.planningReference),
      s(e.receiptReference),
      s(e.tripId),
      s(e.refundId),
      s(e.refundStatus),
      s(e.refundProvider),
      s(e.creditDecision),
      s(e.creditStatus),
      s(e.lifecycleStatus),
      s(e.status),
      s(e.bookingStatus),
      s(e.rideStatus),
      s(e.previousStatus),
      s(e.actorRole),
      s(e.source),
      s(e.rideType),
      s(e.payment['method']),
      s(e.payment['provider']),
      s(e.payment['source']),
      s(e.payment['payment_id']),
      s(e.payment['paymentId']),
      s(e.payment['mollie_refund_id']),
      s(e.payment['mollieRefundId']),
      s(e.payment['refund_id']),
      s(e.payment['refundId']),
      s(e.payment['refund_status']),
      s(e.payment['credit_status']),
      s(e.payment['credit_decision']),
    ];
    _appendMapCustomerNameSearchTokens(tokens, e.payment);
    _appendMapCustomerNameSearchTokens(tokens, e.fare);
    _appendMapCustomerNameSearchTokens(tokens, e.provenance);
    // Localised aliases for common payment-method tokens so a Dutch
    // search like "contant" or "qr" still matches backend tokens.
    final method = s(e.payment['method']);
    final source = s(e.payment['source']);
    for (final value in <String>[method, source]) {
      switch (value) {
        case 'cash':
          tokens
            ..add('contant')
            ..add('cash');
          break;
        case 'qr_code':
        case 'qrcode':
        case 'qr':
          tokens
            ..add('qr')
            ..add('qr_code');
          break;
        case 'card':
        case 'creditcard':
        case 'credit_card':
          tokens
            ..add('kaart')
            ..add('card');
          break;
        case 'pin':
          tokens
            ..add('pin')
            ..add('bancontact');
          break;
      }
    }
    return tokens.where((t) => t.isNotEmpty).join(' ');
  }

  bool _eventMatchesSearch(RemoteComplianceEvent e, String query) {
    if (query.isEmpty) return true;
    final haystack = _buildSearchHaystack(e);
    final tokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return true;
    for (final token in tokens) {
      if (!haystack.contains(token)) return false;
    }
    return true;
  }

  bool _eventMatchesCategory(
    RemoteComplianceEvent e,
    _RemoteComplianceCategoryFilter cat,
  ) {
    if (cat == _RemoteComplianceCategoryFilter.alles) return true;
    String s(dynamic v) => (v ?? '').toString().trim().toLowerCase();
    final eventType = s(e.eventType);
    final rideType = s(e.rideType);
    final lifecycle = s(e.lifecycleStatus);
    final status = s(e.status);
    final bookingStatus = s(e.bookingStatus);
    final rideStatus = s(e.rideStatus);
    final paymentStatus = s(e.payment['status']);
    final refundStatus = s(e.refundStatus);
    final creditDecision = s(e.creditDecision);
    final creditStatus = s(e.creditStatus);
    final refundId = s(e.refundId);

    bool isCancelled(String v) {
      return v == 'cancelled' ||
          v == 'canceled' ||
          v == 'geannuleerd' ||
          v == 'partially_cancelled' ||
          v == 'partially-cancelled';
    }

    switch (cat) {
      case _RemoteComplianceCategoryFilter.alles:
        return true;
      case _RemoteComplianceCategoryFilter.gepland:
        if (rideType == 'planned' || rideType == 'booking') return true;
        // Booking-scoped event types imply a planned dossier when the
        // ride_type is unknown. A direct ride is excluded explicitly.
        const bookingEventTypes = <String>{
          'booking_status_update',
          'booking_credit_decision',
          'booking_mollie_refund',
          'payment_update',
        };
        return bookingEventTypes.contains(eventType) && rideType != 'direct';
      case _RemoteComplianceCategoryFilter.straatritten:
        return rideType == 'direct';
      case _RemoteComplianceCategoryFilter.betaald:
        return paymentStatus == 'paid' ||
            (eventType == 'payment_update' && paymentStatus.isEmpty);
      case _RemoteComplianceCategoryFilter.geannuleerd:
        return isCancelled(lifecycle) ||
            isCancelled(status) ||
            isCancelled(bookingStatus) ||
            isCancelled(rideStatus);
      case _RemoteComplianceCategoryFilter.creditRefund:
        if (eventType == 'booking_credit_decision' ||
            eventType == 'booking_mollie_refund') {
          return true;
        }
        return refundStatus.isNotEmpty ||
            creditDecision.isNotEmpty ||
            creditStatus.isNotEmpty ||
            refundId.isNotEmpty;
    }
  }

  List<RemoteComplianceEvent> _applyFilters(
    List<RemoteComplianceEvent> events,
  ) {
    final query = _searchQuery.trim();
    if (query.isEmpty &&
        _categoryFilter == _RemoteComplianceCategoryFilter.alles) {
      return events;
    }
    return events
        .where(
          (e) =>
              _eventMatchesCategory(e, _categoryFilter) &&
              _eventMatchesSearch(e, query),
        )
        .toList(growable: false);
  }

  String _categoryFilterLabel(_RemoteComplianceCategoryFilter cat) {
    switch (cat) {
      case _RemoteComplianceCategoryFilter.alles:
        return _t(nl: 'Alles', en: 'All', fr: 'Tous', es: 'Todos');
      case _RemoteComplianceCategoryFilter.gepland:
        return _t(
          nl: 'Gepland',
          en: 'Planned',
          fr: 'Planifié',
          es: 'Planificado',
        );
      case _RemoteComplianceCategoryFilter.straatritten:
        return _t(
          nl: 'Straatritten',
          en: 'Street rides',
          fr: 'Courses directes',
          es: 'Viajes directos',
        );
      case _RemoteComplianceCategoryFilter.betaald:
        return _t(nl: 'Betaald', en: 'Paid', fr: 'Payé', es: 'Pagado');
      case _RemoteComplianceCategoryFilter.geannuleerd:
        return _t(
          nl: 'Geannuleerd',
          en: 'Cancelled',
          fr: 'Annulé',
          es: 'Cancelado',
        );
      case _RemoteComplianceCategoryFilter.creditRefund:
        return _t(
          nl: 'Credit/terugbetaling',
          en: 'Credit/refund',
          fr: 'Crédit/remb.',
          es: 'Crédito/reemb.',
        );
    }
  }

  bool get _hasActiveFilter =>
      _searchQuery.trim().isNotEmpty ||
      _categoryFilter != _RemoteComplianceCategoryFilter.alles;

  void _resetSearchAndCategory() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _categoryFilter = _RemoteComplianceCategoryFilter.alles;
    });
  }

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (widget.lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return en;
    }
  }

  String _fmtDateTime(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '—';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return text;
    final local = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  ({String tenantId, String companyId})? _effectiveTenantCompanyIds() {
    final activeCompanyId =
        companyProfileNotifier.value?.companyId.trim() ?? '';
    if (activeCompanyId.isNotEmpty) {
      return (tenantId: activeCompanyId, companyId: activeCompanyId);
    }
    final sessionCompanyId =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (sessionCompanyId.isNotEmpty) {
      return (tenantId: sessionCompanyId, companyId: sessionCompanyId);
    }
    debugPrint(
      '[CHIRON_REMOTE][SKIP_SCOPE] reason=missing_explicit_tenant_company_scope',
    );
    return null;
  }

  String _localizedUnknown() {
    return _t(nl: 'onbekend', en: 'unknown', fr: 'inconnu', es: 'desconocido');
  }

  String _localizedEventTypeLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'booking_status_update':
        return _t(
          nl: 'Statusupdate',
          en: 'Status update',
          fr: 'Mise à jour du statut',
          es: 'Actualización de estado',
        );
      case 'payment_update':
        return _t(
          nl: 'Betalingsupdate',
          en: 'Payment update',
          fr: 'Mise à jour du paiement',
          es: 'Actualización del pago',
        );
      case 'booking_mollie_refund':
        return _t(
          nl: 'Mollie-terugbetaling',
          en: 'Mollie refund',
          fr: 'Remboursement Mollie',
          es: 'Reembolso Mollie',
        );
      case 'booking_credit_decision':
        return _t(
          nl: 'Creditbeslissing',
          en: 'Credit decision',
          fr: 'Décision de crédit',
          es: 'Decisión de crédito',
        );
      case 'ride_stop':
        return _t(
          nl: 'Rit afgerond',
          en: 'Ride completed',
          fr: 'Course terminée',
          es: 'Viaje finalizado',
        );
      case 'ride_start':
        return _t(
          nl: 'Rit gestart',
          en: 'Ride started',
          fr: 'Course démarrée',
          es: 'Viaje iniciado',
        );
      case 'booking_created':
        return _t(
          nl: 'Boeking aangemaakt',
          en: 'Booking created',
          fr: 'Réservation créée',
          es: 'Reserva creada',
        );
      case 'booking_confirmed':
        return _t(
          nl: 'Boeking bevestigd',
          en: 'Booking confirmed',
          fr: 'Réservation confirmée',
          es: 'Reserva confirmada',
        );
      case 'unknown':
        return _localizedUnknown();
      default:
        return raw.trim().isEmpty ? '—' : _localizedUnknown();
    }
  }

  // Compact booking reference for diagnostic logs. Keeps the prefix that
  // matters operationally (the public reference / date segment) without
  // dumping a full UUID into the log line. Falls back to a literal dash so
  // the log column never collapses on empty inputs.
  String _chironLogBookingRef(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '-';
    if (trimmed.length <= 18) return trimmed;
    return '${trimmed.substring(0, 8)}…${trimmed.substring(trimmed.length - 6)}';
  }

  // Roundtrip operational-leg labels: shared by audit row title and audit
  // chips so the dashboard renders one canonical "Heenrit / Terugrit" token
  // per leg event. Returns empty string when the event is not leg-scoped so
  // single-leg bookings keep their existing labels unchanged.
  String _localizedRoundtripLegLabel(String rawLegType) {
    final token = rawLegType.trim().toLowerCase();
    switch (token) {
      case 'outbound':
        return _t(nl: 'Heenrit', en: 'Outbound', fr: 'Aller', es: 'Ida');
      case 'return':
        return _t(nl: 'Terugrit', en: 'Return', fr: 'Retour', es: 'Regreso');
      default:
        return '';
    }
  }

  String _localizedRideTypeLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'planned':
        return _t(
          nl: 'Geplande rit',
          en: 'Planned ride',
          fr: 'Trajet planifié',
          es: 'Viaje planificado',
        );
      case 'direct':
        return _t(
          nl: 'Directe rit',
          en: 'Direct ride',
          fr: 'Course directe',
          es: 'Viaje directo',
        );
      case 'booking':
        return _t(
          nl: 'Boeking',
          en: 'Booking',
          fr: 'Réservation',
          es: 'Reserva',
        );
      case 'unknown':
        return _localizedUnknown();
      default:
        return raw.trim().isEmpty ? '—' : _localizedUnknown();
    }
  }

  String _resolveAuditRideTypeToken(RemoteComplianceEvent e) {
    final candidates = <String>[
      e.rideType,
      _text(e.provenance['ride_type']),
      _text(e.provenance['rideType']),
      _text(e.payment['ride_type']),
      _text(e.payment['rideType']),
      _text(e.fare['ride_type']),
      _text(e.fare['rideType']),
    ];
    for (final candidate in candidates) {
      final token = _normalizeToken(candidate);
      if (token.isNotEmpty && token != 'unknown') return token;
    }
    return '';
  }

  String _localizedAuditRideTypeLabel(RemoteComplianceEvent e) {
    final resolved = _normalizeToken(_resolveAuditRideTypeToken(e));
    switch (resolved) {
      case 'planned':
      case 'plan':
      case 'scheduled':
        return _t(
          nl: 'Geplande rit',
          en: 'Planned ride',
          fr: 'Trajet planifié',
          es: 'Viaje planificado',
        );
      case 'direct':
      case 'direct_trip':
      case 'street_hail':
        return _t(
          nl: 'Directe rit',
          en: 'Direct ride',
          fr: 'Course directe',
          es: 'Viaje directo',
        );
      case 'booking':
        return _t(
          nl: 'Boeking',
          en: 'Booking',
          fr: 'Réservation',
          es: 'Reserva',
        );
      default:
        break;
    }

    final eventToken = _normalizeToken(e.eventType);
    if (eventToken == 'booking_mollie_refund' &&
        e.publicBookingReference.trim().isNotEmpty) {
      return _t(
        nl: 'Geplande rit',
        en: 'Planned ride',
        fr: 'Trajet planifié',
        es: 'Viaje planificado',
      );
    }
    if (eventToken == 'booking_credit_decision' ||
        eventToken == 'booking_status_update') {
      if (e.publicBookingReference.trim().isNotEmpty ||
          e.bookingId.trim().isNotEmpty) {
        return _t(
          nl: 'Geplande rit',
          en: 'Planned ride',
          fr: 'Trajet planifié',
          es: 'Viaje planificado',
        );
      }
      return _t(nl: 'Boeking', en: 'Booking', fr: 'Réservation', es: 'Reserva');
    }
    if (eventToken == 'booking_mollie_refund') {
      return _t(nl: 'Boeking', en: 'Booking', fr: 'Réservation', es: 'Reserva');
    }
    return _t(nl: 'Boeking', en: 'Booking', fr: 'Réservation', es: 'Reserva');
  }

  String _localizedPaymentStatusLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'paid':
        return _t(nl: 'betaald', en: 'paid', fr: 'payé', es: 'pagado');
      case 'unpaid':
        return _t(
          nl: 'onbetaald',
          en: 'unpaid',
          fr: 'non payé',
          es: 'no pagado',
        );
      case 'pending':
        return _t(
          nl: 'in behandeling',
          en: 'pending',
          fr: 'en attente',
          es: 'pendiente',
        );
      case 'failed':
        return _t(nl: 'mislukt', en: 'failed', fr: 'échoué', es: 'fallido');
      case 'unknown':
      case '':
        return _localizedUnknown();
      default:
        return _localizedUnknown();
    }
  }

  String _localizedPaymentMethodLabel(
    String raw, {
    String provider = '',
    String source = '',
  }) {
    switch (raw.trim().toLowerCase()) {
      case 'cash':
        return _t(nl: 'contant', en: 'cash', fr: 'espèces', es: 'efectivo');
      case 'bancontact':
        return 'Bancontact';
      case 'ideal':
        return 'iDEAL';
      case 'card':
      case 'creditcard':
      case 'card_payment':
      case 'pin':
        return _t(nl: 'kaart', en: 'Card', fr: 'Carte', es: 'Tarjeta');
      case 'apple_pay':
      case 'applepay':
        return 'Apple Pay';
      case 'google_pay':
      case 'googlepay':
        return 'Google Pay';
      case 'paypal':
        return 'PayPal';
      case 'manual':
        return _t(nl: 'manueel', en: 'Manual', fr: 'Manuel', es: 'Manual');
      case 'qr':
      case 'qr_code':
        return 'QR';
      case 'online_via_mollie':
        return _t(
          nl: 'online via Mollie',
          en: 'online via Mollie',
          fr: 'en ligne via Mollie',
          es: 'en línea vía Mollie',
        );
      case 'mollie':
      case 'online_payment':
      case 'online-payment':
      case 'online payment':
      case 'online':
        return _t(nl: 'online', en: 'online', fr: 'en ligne', es: 'en línea');
      case 'unknown':
      case '':
        break;
      default:
        break;
    }
    if (_isMollieOnlinePaymentContext(provider: provider, source: source)) {
      return _t(
        nl: 'online via Mollie',
        en: 'online via Mollie',
        fr: 'en ligne via Mollie',
        es: 'en línea vía Mollie',
      );
    }
    return _localizedUnknown();
  }

  bool _isMollieOnlinePaymentContext({
    required String provider,
    required String source,
  }) {
    final providerToken = provider.trim().toLowerCase();
    final sourceToken = source.trim().toLowerCase();
    return providerToken == 'mollie' ||
        sourceToken == 'mollie' ||
        sourceToken == 'online' ||
        sourceToken == 'online_payment' ||
        sourceToken == 'online-payment';
  }

  bool _hasDisplayablePaymentMethod({
    required String method,
    required String provider,
    required String source,
  }) {
    return _localizedPaymentMethodLabel(
          method,
          provider: provider,
          source: source,
        ) !=
        _localizedUnknown();
  }

  String _localizedSourceLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'in_car':
      case 'in_vehicle':
      case 'driver':
      case 'chauffeur':
      case 'manual':
        return _t(
          nl: 'in voertuig',
          en: 'in vehicle',
          fr: 'dans le véhicule',
          es: 'en el vehículo',
        );
      case 'online':
      case 'mollie':
        return _t(nl: 'online', en: 'online', fr: 'en ligne', es: 'en línea');
      case 'unknown':
      case '':
        return _localizedUnknown();
      default:
        return _localizedUnknown();
    }
  }

  String _localizedProviderLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'manual':
        return _t(nl: 'manueel', en: 'manual', fr: 'manuel', es: 'manual');
      case 'mollie':
        return 'Mollie';
      case 'unknown':
      case '':
        return _localizedUnknown();
      default:
        return _localizedUnknown();
    }
  }

  String _authoritativeSyncStateLabel(ChironSyncStatusPresentation presentation) {
    switch (presentation.authoritativeLabelKey) {
      case 'synced':
        return _t(
          nl: 'gesynchroniseerd',
          en: 'synced',
          fr: 'synchronisé',
          es: 'sincronizado',
        );
      case 'pending':
        return _t(
          nl: 'in wachtrij',
          en: 'pending',
          fr: 'en attente',
          es: 'pendiente',
        );
      case 'failed':
        return _t(nl: 'mislukt', en: 'failed', fr: 'échoué', es: 'fallido');
      default:
        return _localizedUnknown();
    }
  }

  String _localizedSyncStateLabel(String raw) {
    final presentation = classifyChironSyncState(raw);
    if (presentation.showChip) {
      return _authoritativeSyncStateLabel(presentation);
    }
    return _localizedUnknown();
  }

  /// Returns a renderable sync-state chip label ONLY for authoritative states.
  String? _renderableSyncStateChipLabel(String? raw) {
    final presentation = classifyChironSyncState(raw);
    if (!presentation.showChip) return null;
    return _authoritativeSyncStateLabel(presentation);
  }

  /// Aggregate sync-state chip across dossier events; null when all hide.
  String? _aggregateSyncStateChipLabel(List<RemoteComplianceEvent> sorted) {
    for (final event in sorted) {
      final label = _renderableSyncStateChipLabel(event.syncState);
      if (label != null) return label;
    }
    return null;
  }

  String _localizedProducerLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'booking_worker':
      case 'bookingsworker':
      case 'booking worker':
      case 'bookingmodule':
        return _t(
          nl: 'boekingsmodule',
          en: 'booking module',
          fr: 'module de réservation',
          es: 'módulo de reserva',
        );
      case 'tracking_worker':
      case 'trackingworker':
      case 'tracking worker':
      case 'trackingmodule':
        return _t(
          nl: 'ritmodule',
          en: 'ride module',
          fr: 'module de course',
          es: 'módulo de viaje',
        );
      case 'compliance_worker':
      case 'complianceworker':
      case 'compliance worker':
        return _t(
          nl: 'compliancemodule',
          en: 'compliance module',
          fr: 'module de conformité',
          es: 'módulo de cumplimiento',
        );
      case 'unknown':
        return _localizedUnknown();
      default:
        return raw.trim().isEmpty ? '—' : _localizedUnknown();
    }
  }

  Future<RemoteComplianceEventsResponse> _loadRemoteEvents() async {
    final effective = _effectiveTenantCompanyIds();
    if (effective == null) {
      return RemoteComplianceEventsResponse(
        ok: false,
        tenantId: '',
        companyId: '',
        limit: 100,
        count: 0,
        malformedCount: 0,
        events: const <RemoteComplianceEvent>[],
        errorMessage: _t(
          nl: 'Bedrijfscontext ontbreekt. Compliancegegevens kunnen niet veilig geladen worden.',
          en: 'Company context is missing. Compliance data cannot be loaded safely.',
          fr: 'Le contexte entreprise est manquant. Les données de conformité ne peuvent pas être chargées en toute sécurité.',
          es: 'Falta el contexto de empresa. Los datos de cumplimiento no pueden cargarse de forma segura.',
        ),
      );
    }
    final effectiveTenantId = effective.tenantId;
    final effectiveCompanyId = effective.companyId;

    /* CHIRON-P0-2A: /compliance/events/recent is now routed through the
     * booking worker with a company-owner session bearer, not the direct
     * compliance admin bearer. */
    if (!hasCompanyOwnerAuthContext()) {
      return RemoteComplianceEventsResponse(
        ok: false,
        tenantId: effectiveTenantId,
        companyId: effectiveCompanyId,
        limit: 100,
        count: 0,
        malformedCount: 0,
        events: const <RemoteComplianceEvent>[],
        errorMessage: _t(
          nl: 'Niet gemachtigd om backendmeldingen te laden.',
          en: 'Not authorized to load remote compliance events.',
          fr: 'Non autorisé à charger les événements de conformité distants.',
          es: 'No autorizado para cargar los eventos de cumplimiento remotos.',
        ),
      );
    }

    final uri = _chironBookingReadonlyEndpoint(
      '/compliance/events/recent',
      tenantId: effectiveTenantId,
      companyId: effectiveCompanyId,
      extraQuery: <String, String>{'limit': '100'},
    );
    final auth = await resolveCompanyOwnerAuthHeaders(json: false);
    try {
      final res = await http
          .get(uri, headers: auth.headers)
          .timeout(const Duration(seconds: 10));

      Map<String, dynamic> asMap(Object? value) {
        if (value is Map) return Map<String, dynamic>.from(value);
        return const <String, dynamic>{};
      }

      final contentType = (res.headers['content-type'] ?? '').toLowerCase();
      Map<String, dynamic> payload = const <String, dynamic>{};
      if (contentType.contains('application/json') && res.body.isNotEmpty) {
        try {
          payload = asMap(jsonDecode(res.body));
        } catch (err) {
          debugPrint(
            '[$_chironBookingWorkerProxyLogTag][EVENTS_RECENT] json_parse_failed status=${res.statusCode} err=$err',
          );
        }
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint(
          '[$_chironBookingWorkerProxyLogTag][EVENTS_RECENT] non_success status=${res.statusCode}',
        );
        final err = _text(payload['error']);
        return RemoteComplianceEventsResponse(
          ok: false,
          tenantId: _text(payload['tenant_id']),
          companyId: _text(payload['company_id']),
          limit: int.tryParse(_text(payload['limit'])) ?? 100,
          count: 0,
          malformedCount: 0,
          events: const <RemoteComplianceEvent>[],
          errorMessage: err.isEmpty
              ? _t(
                  nl: 'Backend compliance events ophalen mislukt.',
                  en: 'Failed to load backend compliance events.',
                  fr: 'Échec du chargement des événements conformité backend.',
                  es: 'No se pudieron cargar los eventos de cumplimiento backend.',
                )
              : err,
        );
      }

      final eventsRaw = payload['events'];
      final events = eventsRaw is List
          ? eventsRaw
                .whereType<Map>()
                .map(
                  (e) => RemoteComplianceEvent.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList(growable: false)
          : const <RemoteComplianceEvent>[];

      final typeCounts = <String, int>{};
      for (final event in events) {
        final token = event.eventType.trim().isEmpty
            ? 'unknown'
            : event.eventType.trim().toLowerCase();
        typeCounts[token] = (typeCounts[token] ?? 0) + 1;
      }
      debugPrint(
        '[CHIRON][EVENT_TYPES] types=${typeCounts.entries.map((entry) => '${entry.key}:${entry.value}').join(',')}',
      );

      return RemoteComplianceEventsResponse(
        ok: payload['ok'] == true,
        tenantId: _text(payload['tenant_id']),
        companyId: _text(payload['company_id']),
        limit: int.tryParse(_text(payload['limit'])) ?? 100,
        count: int.tryParse(_text(payload['count'])) ?? events.length,
        malformedCount: int.tryParse(_text(payload['malformed_count'])) ?? 0,
        events: events,
        errorMessage: '',
      );
    } catch (err) {
      debugPrint(
        '[$_chironBookingWorkerProxyLogTag][EVENTS_RECENT] request_failed err=$err',
      );
      return RemoteComplianceEventsResponse(
        ok: false,
        tenantId: effectiveTenantId,
        companyId: effectiveCompanyId,
        limit: 100,
        count: 0,
        malformedCount: 0,
        events: const <RemoteComplianceEvent>[],
        errorMessage: _t(
          nl: 'Kan backend compliance events niet laden. Controleer netwerk/verbinding.',
          en: 'Cannot load backend compliance events. Check network/connection.',
          fr: 'Impossible de charger les événements conformité backend. Vérifiez réseau/connexion.',
          es: 'No se pueden cargar eventos de cumplimiento backend. Verifica red/conexión.',
        ),
      );
    }
  }

  /* CHIRON-P0-2A: destructive backend-reset entrypoint. The direct compliance
   * admin bearer is no longer shipped in the client, and P0-2A intentionally
   * does NOT expose /admin/dev/reset-compliance-events through the booking
   * worker's company-session proxy. In release mode the triggering IconButton
   * is hidden entirely (see the build() gate), so this method is unreachable.
   * Even if invoked from a non-release build the method now short-circuits:
   * it does not attempt any network call, never references a compile-time
   * secret, and reports "unavailable in this build" to the caller. */
  Future<void> _resetRemoteComplianceEvents() async {
    if (_isResettingRemoteEvents) return;
    if (!mounted) return;
    debugPrint(
      '[CHIRON_REMOTE][RESET_UNAVAILABLE] reason=destructive_route_not_exposed_to_company_session build_mode=${kReleaseMode ? 'release' : 'debug_or_profile'}',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Backend cleanup is niet beschikbaar in deze build.',
            en: 'Backend cleanup is not available in this build.',
            fr: 'Le nettoyage backend n’est pas disponible dans cette version.',
            es: 'La limpieza del backend no está disponible en esta versión.',
          ),
        ),
      ),
    );
  }

  Widget _chip(String label) {
    if (label.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _chironPanel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _chironBorder),
      ),
      child: Text(
        label,
        style: TextStyle(color: _chironChipText, fontSize: 11),
      ),
    );
  }

  String _normalizeToken(String raw) {
    return raw.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
  }

  String? _eventKeyPart(String prefix, String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '—') return null;
    return '$prefix:${normalized.toLowerCase()}';
  }

  List<String> _remoteMatchKeys(RemoteComplianceEvent e) {
    return <String>[
      if (_eventKeyPart('booking', e.bookingId) != null)
        _eventKeyPart('booking', e.bookingId)!,
      if (_eventKeyPart('trip', e.tripId) != null)
        _eventKeyPart('trip', e.tripId)!,
    ];
  }

  DateTime? _remoteEventTime(RemoteComplianceEvent e) {
    DateTime? parseRaw(String raw) {
      final text = raw.trim();
      if (text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    final fromCreated = parseRaw(e.createdAtUtc);
    if (fromCreated != null) return fromCreated;

    final timestampCandidates = <dynamic>[
      e.timestamps['recorded_at_utc'],
      e.timestamps['event_at_utc'],
      e.timestamps['paid_at_utc'],
      e.timestamps['stopped_at_utc'],
      e.timestamps['started_at_utc'],
    ];
    for (final value in timestampCandidates) {
      final parsed = parseRaw(_text(value));
      if (parsed != null) return parsed;
    }
    return null;
  }

  bool _isNewerRemoteEvent(
    RemoteComplianceEvent candidate,
    RemoteComplianceEvent existing,
  ) {
    final candidateTime = _remoteEventTime(candidate);
    final existingTime = _remoteEventTime(existing);
    if (candidateTime != null && existingTime != null) {
      final byTime = candidateTime.compareTo(existingTime);
      if (byTime != 0) return byTime > 0;
    } else if (candidateTime != null) {
      return true;
    } else if (existingTime != null) {
      return false;
    }
    // Recent endpoint currently returns newest-first by key/time.
    return false;
  }

  Map<String, RemoteComplianceEvent> _latestPaymentUpdatesByKey(
    List<RemoteComplianceEvent> events,
  ) {
    final latest = <String, RemoteComplianceEvent>{};
    for (final event in events.where(
      (e) => _normalizeToken(e.eventType) == 'payment_update',
    )) {
      for (final key in _remoteMatchKeys(event)) {
        final existing = latest[key];
        if (existing == null || _isNewerRemoteEvent(event, existing)) {
          latest[key] = event;
        }
      }
    }
    return latest;
  }

  RemoteComplianceEvent? _effectivePaymentUpdateFor(
    RemoteComplianceEvent e,
    Map<String, RemoteComplianceEvent> latestPaymentUpdates,
  ) {
    RemoteComplianceEvent? best;
    for (final key in _remoteMatchKeys(e)) {
      final update = latestPaymentUpdates[key];
      if (update == null) continue;
      if (best == null || _isNewerRemoteEvent(update, best)) {
        best = update;
      }
    }
    return best;
  }

  bool _isMeaningfulPaymentStatus(String raw) {
    switch (_normalizeToken(raw)) {
      case 'paid':
      case 'pending':
      case 'failed':
      case 'unpaid':
        return true;
      default:
        return false;
    }
  }

  bool _isMeaningfulPaymentField(String raw) {
    final token = _normalizeToken(raw);
    return token.isNotEmpty && token != 'unknown';
  }

  String _resolveEffectivePaymentValue({
    required String baseValue,
    required String updateValue,
    required bool baseIsMeaningful,
    required bool updateIsMeaningful,
    required bool updateIsNewer,
  }) {
    if (!updateIsMeaningful) return baseValue;
    if (!baseIsMeaningful) return updateValue;
    return updateIsNewer ? updateValue : baseValue;
  }

  bool _isMeaningfulIdentity(String raw) {
    final token = _normalizeToken(raw);
    return token.isNotEmpty &&
        token != 'unknown' &&
        token != 'onbekend' &&
        token != '-' &&
        token != '—' &&
        token != 'null' &&
        token != 'undefined';
  }

  bool _looksLikeRemoteUuid(String value) {
    return RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}',
      caseSensitive: false,
    ).hasMatch(value);
  }

  bool _isTechnicalInternalReference(String? value) {
    final text = _text(value);
    if (text.isEmpty) return true;
    final token = _normalizeToken(text);
    if (token.isEmpty ||
        token == 'unknown' ||
        token == 'onbekend' ||
        token == '-' ||
        token == '—' ||
        token == 'null' ||
        token == 'undefined') {
      return true;
    }
    final lower = text.toLowerCase();
    if (lower.startsWith('trip_')) return true;
    if (lower.startsWith('trip-trip_')) return true;
    if (lower.contains('trip-trip_')) return true;
    if (_looksLikeRemoteUuid(lower)) return true;
    final hasUnderscoreOrHyphen = text.contains('_') || text.contains('-');
    final hasLetters = RegExp(r'[a-zA-Z]').hasMatch(text);
    final hasDigits = RegExp(r'\d').hasMatch(text);
    if (text.length >= 28 && hasUnderscoreOrHyphen && hasLetters && hasDigits) {
      return true;
    }
    return false;
  }

  String _localizedReferenceLabel() {
    return _t(
      nl: 'Referentie',
      en: 'Reference',
      fr: 'Référence',
      es: 'Referencia',
    );
  }

  String _localizedReceiptNumberLabel() {
    return _t(
      nl: 'Bonnummer',
      en: 'Receipt no.',
      fr: 'N° de reçu',
      es: 'N.º de recibo',
    );
  }

  String _localizedDraftReceiptLabel() {
    return _t(
      nl: 'Conceptbon',
      en: 'Draft receipt',
      fr: 'Reçu provisoire',
      es: 'Recibo provisional',
    );
  }

  String _localizedInternalBookingLabel() {
    return _t(
      nl: 'Interne boeking',
      en: 'Internal booking',
      fr: 'Réservation interne',
      es: 'Reserva interna',
    );
  }

  String _localizedPlanningLabel() {
    return _t(
      nl: 'Planningnummer',
      en: 'Planning no.',
      fr: 'N° de planning',
      es: 'N.º de planificación',
    );
  }

  String _localizedBookingNumberLabel() {
    return _t(
      nl: 'Boekingsnummer',
      en: 'Booking no.',
      fr: 'N° de réservation',
      es: 'N.º de reserva',
    );
  }

  String _localizedInternalTripLabel() {
    return _t(
      nl: 'Interne rit',
      en: 'Internal trip',
      fr: 'Course interne',
      es: 'Viaje interno',
    );
  }

  String _labelValue(String label, String value) {
    if (appConfig.currentLanguage == AppLanguage.fr) return '$label : $value';
    return '$label: $value';
  }

  bool _sameReference(String? a, String? b) {
    final left = _text(a);
    final right = _text(b);
    if (left.isEmpty || right.isEmpty) return false;
    return _normalizeToken(left) == _normalizeToken(right);
  }

  bool _isLegacyTripReceiptNumber(String? value) {
    final text = _text(value);
    if (text.isEmpty) return false;
    final token = _normalizeToken(text);
    if (token.startsWith('planne-')) return true;
    return RegExp(r'^planne-[a-z0-9]{3,}$').hasMatch(token);
  }

  bool _isDerivedPlannedTripReference({
    required String candidate,
    String? bookingId,
    String? tripId,
  }) {
    final token = _normalizeToken(candidate);
    if (token.startsWith('planned_')) return true;
    final booking = _text(bookingId);
    if (booking.isNotEmpty && _sameReference(candidate, 'planned_$booking')) {
      return true;
    }
    final trip = _text(tripId);
    if (trip.isNotEmpty &&
        _sameReference(candidate, trip) &&
        token.startsWith('planned_')) {
      return true;
    }
    return false;
  }

  bool _isRealReceiptReference({
    required String candidate,
    String? bookingId,
    String? tripId,
    String? planningReference,
    String? publicBookingReference,
  }) {
    final value = _text(candidate);
    if (value.isEmpty) return false;
    if (_isTechnicalInternalReference(value)) return false;
    if (_sameReference(value, bookingId)) return false;
    if (_sameReference(value, tripId)) return false;
    if (_sameReference(value, planningReference)) return false;
    if (_sameReference(value, publicBookingReference)) return false;
    if (_isLegacyTripReceiptNumber(value)) return false;
    if (_isDerivedPlannedTripReference(
      candidate: value,
      bookingId: bookingId,
      tripId: tripId,
    )) {
      return false;
    }
    return true;
  }

  ({String label, String value}) _businessReferenceForRemoteCard({
    required String rideType,
    required String publicBookingReference,
    required String planningReference,
    required String receiptReference,
    required String bookingId,
    required String tripId,
  }) {
    final receiptIsBusiness = _isRealReceiptReference(
      candidate: receiptReference,
      bookingId: bookingId,
      tripId: tripId,
      planningReference: planningReference,
      publicBookingReference: publicBookingReference,
    );
    if (receiptIsBusiness) {
      return (label: _localizedReceiptNumberLabel(), value: receiptReference);
    }
    final planningIsBusiness =
        planningReference.isNotEmpty &&
        !_isTechnicalInternalReference(planningReference);
    if (planningIsBusiness) {
      return (label: _localizedPlanningLabel(), value: planningReference);
    }
    final publicBookingIsBusiness =
        publicBookingReference.isNotEmpty &&
        !_isTechnicalInternalReference(publicBookingReference);
    if (publicBookingIsBusiness) {
      return (
        label: _localizedBookingNumberLabel(),
        value: publicBookingReference,
      );
    }
    final bookingIsBusiness =
        bookingId.isNotEmpty && !_isTechnicalInternalReference(bookingId);
    if (bookingIsBusiness) {
      return (label: _localizedInternalBookingLabel(), value: bookingId);
    }
    final tripIsBusiness =
        tripId.isNotEmpty && !_isTechnicalInternalReference(tripId);
    if (tripIsBusiness) {
      return (label: _localizedInternalTripLabel(), value: tripId);
    }
    final rideToken = _normalizeToken(rideType);
    if (rideToken == 'direct' || rideToken == 'planned') {
      return (
        label: _localizedReferenceLabel(),
        value: _localizedDraftReceiptLabel(),
      );
    }
    return (label: _localizedReferenceLabel(), value: '—');
  }

  bool _isLegScopedEvent(RemoteComplianceEvent event) {
    if (event.legType.trim().isNotEmpty) return true;
    if (event.legId.trim().isNotEmpty) return true;
    return false;
  }

  bool _isParentScopedStatusUpdate(RemoteComplianceEvent event) {
    if (_normalizeToken(event.eventType) != 'booking_status_update') {
      return false;
    }
    return !_isLegScopedEvent(event);
  }

  int _compareRemoteEventsNewestFirst(
    RemoteComplianceEvent a,
    RemoteComplianceEvent b,
  ) {
    final at = _remoteEventTime(a);
    final bt = _remoteEventTime(b);
    if (at != null && bt != null) return bt.compareTo(at);
    if (at != null) return -1;
    if (bt != null) return 1;
    return _text(b.eventId).compareTo(_text(a.eventId));
  }

  ({String status, String method, String source, String provider})
  _effectivePaymentForEvent(
    RemoteComplianceEvent e,
    Map<String, RemoteComplianceEvent> latestPaymentUpdates,
  ) {
    final paymentUpdate = _normalizeToken(e.eventType) == 'payment_update'
        ? null
        : _effectivePaymentUpdateFor(e, latestPaymentUpdates);
    final basePaymentStatus = _text(e.payment['status']);
    final basePaymentMethod = _text(e.payment['method']);
    final basePaymentSource = _text(e.payment['source']);
    final basePaymentProvider = _text(e.payment['provider']);
    final updatePaymentStatus = paymentUpdate == null
        ? ''
        : _text(paymentUpdate.payment['status']);
    final updatePaymentMethod = paymentUpdate == null
        ? ''
        : _text(paymentUpdate.payment['method']);
    final updatePaymentSource = paymentUpdate == null
        ? ''
        : _text(paymentUpdate.payment['source']);
    final updatePaymentProvider = paymentUpdate == null
        ? ''
        : _text(paymentUpdate.payment['provider']);
    final updateIsNewer =
        paymentUpdate != null && _isNewerRemoteEvent(paymentUpdate, e);

    return (
      status: _resolveEffectivePaymentValue(
        baseValue: basePaymentStatus,
        updateValue: updatePaymentStatus,
        baseIsMeaningful: _isMeaningfulPaymentStatus(basePaymentStatus),
        updateIsMeaningful: _isMeaningfulPaymentStatus(updatePaymentStatus),
        updateIsNewer: updateIsNewer,
      ),
      method: _resolveEffectivePaymentValue(
        baseValue: basePaymentMethod,
        updateValue: updatePaymentMethod,
        baseIsMeaningful: _isMeaningfulPaymentField(basePaymentMethod),
        updateIsMeaningful: _isMeaningfulPaymentField(updatePaymentMethod),
        updateIsNewer: updateIsNewer,
      ),
      source: _resolveEffectivePaymentValue(
        baseValue: basePaymentSource,
        updateValue: updatePaymentSource,
        baseIsMeaningful: _isMeaningfulPaymentField(basePaymentSource),
        updateIsMeaningful: _isMeaningfulPaymentField(updatePaymentSource),
        updateIsNewer: updateIsNewer,
      ),
      provider: _resolveEffectivePaymentValue(
        baseValue: basePaymentProvider,
        updateValue: updatePaymentProvider,
        baseIsMeaningful: _isMeaningfulPaymentField(basePaymentProvider),
        updateIsMeaningful: _isMeaningfulPaymentField(updatePaymentProvider),
        updateIsNewer: updateIsNewer,
      ),
    );
  }

  String _localizedDossierTitle(String rideType) {
    switch (_normalizeToken(rideType)) {
      case 'planned':
        return _t(
          nl: 'Geplande rit',
          en: 'Planned ride',
          fr: 'Course planifiée',
          es: 'Viaje planificado',
        );
      case 'direct':
        return _t(
          nl: 'Directe rit',
          en: 'Direct ride',
          fr: 'Course directe',
          es: 'Viaje directo',
        );
      default:
        return _t(
          nl: 'Rittendossier',
          en: 'Ride dossier',
          fr: 'Dossier de course',
          es: 'Expediente del viaje',
        );
    }
  }

  String _localizedRideStatus(List<RemoteComplianceEvent> events) {
    // Roundtrip operational-leg dossier status: the previous logic walked the
    // newest booking_status_update and, failing that, returned "afgerond" on
    // the presence of any ride_stop. For split_no_wait airport roundtrips
    // the outbound's leg-scoped ride_stop would prematurely promote the
    // parent dossier to "afgerond" even though the parent booking is still
    // PENDING and the return leg has not yet been driven. The dashboard MUST
    // mirror the backend operational-leg scope: only mark the parent as
    // completed when the parent booking_status_update itself flipped to
    // COMPLETED. If the parent is still PENDING but a leg ride_stop exists,
    // render "gedeeltelijk afgerond" so the operator can see the partial
    // progress without misreading it as a full completion.
    final sorted = [...events]..sort(_compareRemoteEventsNewestFirst);

    // 1. Parent-scope cancellation always wins. Leg-scoped cancellation
    // (e.g. return leg cancelled after outbound completed) stays visible in
    // the audit row, but must not poison the dossier/other-leg status chip.
    for (final event in sorted) {
      if (!_isParentScopedStatusUpdate(event)) continue;
      final statusTokens = <String>[
        _normalizeToken(event.lifecycleStatus),
        _normalizeToken(event.status),
        _normalizeToken(event.bookingStatus),
        _normalizeToken(event.rideStatus),
      ];
      if (statusTokens.contains('cancelled') ||
          statusTokens.contains('canceled')) {
        debugPrint(
          '[CHIRON_UI][ROUNDTRIP_STATUS_SOURCE] decision=cancelled source=booking_status_update booking=${_chironLogBookingRef(event.bookingId)} parent_status=${event.parentStatus.isEmpty ? "-" : event.parentStatus}',
        );
        return _t(
          nl: 'geannuleerd',
          en: 'cancelled',
          fr: 'annulée',
          es: 'cancelado',
        );
      }
    }

    // 2. Parent-scope booking_status_update is the source of truth for
    //    completion. Leg-scoped updates can mention COMPLETED as a transition
    //    side effect, but only the parent's lifecycle flips the dossier.
    RemoteComplianceEvent? latestParentStatusUpdate;
    for (final event in sorted) {
      final eventType = _normalizeToken(event.eventType);
      if (eventType != 'booking_status_update') continue;
      if (_isLegScopedEvent(event)) continue;
      latestParentStatusUpdate = event;
      break;
    }
    if (latestParentStatusUpdate != null) {
      final tokens = <String>[
        _normalizeToken(latestParentStatusUpdate.lifecycleStatus),
        _normalizeToken(latestParentStatusUpdate.status),
        _normalizeToken(latestParentStatusUpdate.bookingStatus),
        _normalizeToken(latestParentStatusUpdate.rideStatus),
      ];
      if (tokens.contains('completed')) {
        debugPrint(
          '[CHIRON_UI][ROUNDTRIP_STATUS_SOURCE] decision=completed source=parent_booking_status_update booking=${_chironLogBookingRef(latestParentStatusUpdate.bookingId)} tokens=${tokens.where((t) => t.isNotEmpty).join("|")}',
        );
        return _t(
          nl: 'afgerond',
          en: 'completed',
          fr: 'terminée',
          es: 'finalizado',
        );
      }
    }

    // 3. Roundtrip partial completion: parent has not reached COMPLETED yet,
    //    but at least one leg-scoped ride_stop (or a leg-scoped completion
    //    booking_status_update) is on file. Show "gedeeltelijk afgerond" so
    //    the dossier card matches the customer card's "In behandeling /
    //    partial" state instead of falsely claiming the booking is done.
    var hasLegCompletion = false;
    var hasAnyLegMetadata = false;
    for (final event in sorted) {
      if (event.hasLegMetadata) hasAnyLegMetadata = true;
      final eventType = _normalizeToken(event.eventType);
      if (eventType == 'ride_stop' && _isLegScopedEvent(event)) {
        hasLegCompletion = true;
      }
      if (eventType == 'booking_status_update' && _isLegScopedEvent(event)) {
        final legStatusTokens = <String>[
          _normalizeToken(event.legStatus),
          _normalizeToken(event.lifecycleStatus),
          _normalizeToken(event.status),
        ];
        if (legStatusTokens.contains('completed')) hasLegCompletion = true;
      }
    }
    if (hasLegCompletion) {
      debugPrint(
        '[CHIRON_UI][ROUNDTRIP_STATUS_SOURCE] decision=partially_completed source=leg_scoped_ride_stop parent_status=${latestParentStatusUpdate?.parentStatus.isNotEmpty == true ? latestParentStatusUpdate!.parentStatus : (latestParentStatusUpdate?.lifecycleStatus ?? "-")} leg_metadata_present=$hasAnyLegMetadata',
      );
      return _t(
        nl: 'gedeeltelijk afgerond',
        en: 'partially completed',
        fr: 'partiellement terminée',
        es: 'parcialmente completado',
      );
    }

    // 4. No leg metadata available — fall back to the prior single-leg logic
    //    so existing dossiers (and legacy events that pre-date the leg
    //    projection) keep their previous behaviour.
    if (latestParentStatusUpdate != null) {
      final tokens = <String>[
        _normalizeToken(latestParentStatusUpdate.lifecycleStatus),
        _normalizeToken(latestParentStatusUpdate.status),
        _normalizeToken(latestParentStatusUpdate.bookingStatus),
        _normalizeToken(latestParentStatusUpdate.rideStatus),
      ];
      if (tokens.contains('pending')) {
        debugPrint(
          '[CHIRON_UI][ROUNDTRIP_STATUS_SOURCE] decision=pending source=parent_booking_status_update booking=${_chironLogBookingRef(latestParentStatusUpdate.bookingId)}',
        );
        return _t(
          nl: 'in behandeling',
          en: 'pending',
          fr: 'en attente',
          es: 'pendiente',
        );
      }
    }
    final hasRideStop = sorted.any(
      (event) => _normalizeToken(event.eventType) == 'ride_stop',
    );
    if (hasRideStop) {
      // No leg metadata at all — keep legacy single-trip completion semantics.
      debugPrint(
        '[CHIRON_UI][ROUNDTRIP_STATUS_SOURCE] decision=completed source=ride_stop_legacy_fallback leg_metadata_present=$hasAnyLegMetadata',
      );
      return _t(
        nl: 'afgerond',
        en: 'completed',
        fr: 'terminée',
        es: 'finalizado',
      );
    }
    debugPrint(
      '[CHIRON_UI][ROUNDTRIP_STATUS_SOURCE] decision=unknown source=no_status_signal events=${sorted.length}',
    );
    return _localizedUnknown();
  }

  String _localizedActorRoleLabel(String raw) {
    switch (_normalizeToken(raw)) {
      case 'customer':
        return _t(nl: 'klant', en: 'customer', fr: 'client', es: 'cliente');
      case 'admin':
        return _t(nl: 'beheer', en: 'admin', fr: 'admin', es: 'admin');
      case 'driver':
        return _t(
          nl: 'chauffeur',
          en: 'driver',
          fr: 'chauffeur',
          es: 'conductor',
        );
      case 'system':
        return _t(nl: 'systeem', en: 'system', fr: 'système', es: 'sistema');
      case 'company':
        return _t(
          nl: 'bedrijf',
          en: 'company',
          fr: 'entreprise',
          es: 'empresa',
        );
      default:
        return _localizedUnknown();
    }
  }

  String _localizedAuditSourceLabel(String raw) {
    final token = _normalizeToken(raw);
    if (token == 'booking_status_update') {
      return _t(
        nl: 'statusupdate',
        en: 'status update',
        fr: 'mise à jour du statut',
        es: 'actualización de estado',
      );
    }
    if (token == 'booking_mollie_refund') {
      return _t(
        nl: 'Mollie-terugbetaling',
        en: 'Mollie refund',
        fr: 'Remboursement Mollie',
        es: 'Reembolso Mollie',
      );
    }
    if (token == 'booking_credit_decision') {
      return _t(
        nl: 'Creditbeslissing',
        en: 'Credit decision',
        fr: 'Décision de crédit',
        es: 'Decisión de crédito',
      );
    }
    if (token.contains('bookings') && token.contains('status')) {
      return _t(
        nl: 'boekingsstatus',
        en: 'booking status',
        fr: 'statut de réservation',
        es: 'estado de reserva',
      );
    }
    if (token.contains('track') &&
        token.contains('booking') &&
        token.contains('status')) {
      return _t(
        nl: 'boekingsstatus',
        en: 'booking status',
        fr: 'statut de réservation',
        es: 'estado de reserva',
      );
    }
    return _localizedUnknown();
  }

  String _localizedRefundStatusLabel(String raw) {
    switch (_normalizeToken(raw)) {
      case 'refunded':
      case 'completed':
      case 'success':
        return _t(
          nl: 'terugbetaald',
          en: 'refunded',
          fr: 'remboursé',
          es: 'reembolsado',
        );
      case 'mollie_refund_pending':
      case 'queued':
      case 'pending':
      case 'processing':
        return _t(
          nl: 'in behandeling',
          en: 'pending',
          fr: 'en attente',
          es: 'pendiente',
        );
      case 'failed':
        return _t(nl: 'mislukt', en: 'failed', fr: 'échoué', es: 'fallido');
      default:
        return raw.trim().isEmpty ? _localizedUnknown() : raw.trim();
    }
  }

  bool _isTerminalMollieRefundAuditStatus(String raw) {
    switch (_normalizeToken(raw)) {
      case 'refunded':
      case 'completed':
      case 'success':
      case 'paid':
      case 'succeeded':
        return true;
      default:
        return false;
    }
  }

  bool _isPendingMollieRefundAuditStatus(String raw) {
    switch (_normalizeToken(raw)) {
      case 'mollie_refund_pending':
      case 'queued':
      case 'pending':
      case 'processing':
        return true;
      default:
        return false;
    }
  }

  bool _isMollieRefundConfirmedAuditEvent(RemoteComplianceEvent e) {
    if (_normalizeToken(e.source) == 'refund_status_refresh') return true;
    if (_isTerminalMollieRefundAuditStatus(e.refundStatus)) return true;
    if (_isTerminalMollieRefundAuditStatus(e.status)) return true;
    if (_normalizeToken(e.lifecycleStatus) == 'refunded') {
      return !_isPendingMollieRefundAuditStatus(e.refundStatus) &&
          !_isPendingMollieRefundAuditStatus(e.status);
    }
    return false;
  }

  String _localizedRefundProviderLabel(String raw) {
    switch (_normalizeToken(raw)) {
      case 'mollie':
        return 'Mollie';
      case 'manual':
        return _t(nl: 'manueel', en: 'manual', fr: 'manuel', es: 'manual');
      default:
        return raw.trim().isEmpty ? _localizedUnknown() : raw.trim();
    }
  }

  String _localizedCreditDecisionLabel(String raw) {
    switch (_normalizeToken(raw)) {
      case 'full_credit':
        return _t(
          nl: 'volledige credit',
          en: 'full credit',
          fr: 'crédit complet',
          es: 'crédito total',
        );
      case 'partial_credit':
        return _t(
          nl: 'gedeeltelijke credit',
          en: 'partial credit',
          fr: 'crédit partiel',
          es: 'crédito parcial',
        );
      case 'no_refund':
        return _t(
          nl: 'geen terugbetaling',
          en: 'no refund',
          fr: 'pas de remboursement',
          es: 'sin reembolso',
        );
      case 'handled_manually':
        return _t(
          nl: 'handmatig afgehandeld',
          en: 'handled manually',
          fr: 'traité manuellement',
          es: 'gestionado manualmente',
        );
      default:
        return raw.trim().isEmpty ? _localizedUnknown() : raw.trim();
    }
  }

  String _formatRefundAmountCents(int? cents) {
    if (cents == null) return '';
    final value = (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
    return '€$value';
  }

  String _localizedCreditStatusLabel(String raw) {
    switch (_normalizeToken(raw)) {
      case 'credited':
        return _t(
          nl: 'gecrediteerd',
          en: 'credited',
          fr: 'crédité',
          es: 'acreditado',
        );
      case 'partial_credit':
        return _t(
          nl: 'gedeeltelijke credit',
          en: 'partial credit',
          fr: 'crédit partiel',
          es: 'crédito parcial',
        );
      case 'pending_credit':
        return _t(
          nl: 'credit in behandeling',
          en: 'pending credit',
          fr: 'crédit en attente',
          es: 'crédito pendiente',
        );
      case 'no_refund':
        return _t(
          nl: 'geen terugbetaling',
          en: 'no refund',
          fr: 'pas de remboursement',
          es: 'sin reembolso',
        );
      case 'handled_manually':
        return _t(
          nl: 'handmatig afgehandeld',
          en: 'handled manually',
          fr: 'traité manuellement',
          es: 'gestionado manualmente',
        );
      default:
        return raw.trim().isEmpty ? _localizedUnknown() : raw.trim();
    }
  }

  bool _eventIsCancelledStatusUpdate(RemoteComplianceEvent e) {
    if (_normalizeToken(e.eventType) != 'booking_status_update') return false;
    final statusToken = _normalizeToken(
      e.lifecycleStatus.isNotEmpty
          ? e.lifecycleStatus
          : (e.status.isNotEmpty ? e.status : e.bookingStatus),
    );
    return statusToken == 'cancelled' || statusToken == 'canceled';
  }

  String _localizedAuditEventTitle(RemoteComplianceEvent e) {
    final token = _normalizeToken(e.eventType);
    if (token == 'booking_status_update' && _eventIsCancelledStatusUpdate(e)) {
      return _t(
        nl: 'Annulatie',
        en: 'Cancellation',
        fr: 'Annulation',
        es: 'Cancelación',
      );
    }
    if (token == 'booking_mollie_refund') {
      if (_isMollieRefundConfirmedAuditEvent(e)) {
        return _t(
          nl: 'Mollie-terugbetaling bevestigd',
          en: 'Mollie refund confirmed',
          fr: 'Remboursement Mollie confirmé',
          es: 'Reembolso Mollie confirmado',
        );
      }
      return _t(
        nl: 'Mollie-terugbetaling aangevraagd',
        en: 'Mollie refund requested',
        fr: 'Remboursement Mollie demandé',
        es: 'Reembolso Mollie solicitado',
      );
    }
    if (token == 'booking_credit_decision') {
      return _t(
        nl: 'Creditbeslissing',
        en: 'Credit decision',
        fr: 'Décision de crédit',
        es: 'Decisión de crédito',
      );
    }
    return _localizedEventTypeLabel(e.eventType);
  }

  String _eventAuditTimestamp(RemoteComplianceEvent e) {
    return _fmtDateTime(_eventAuditTimestampRaw(e));
  }

  String _eventAuditTimestampRaw(RemoteComplianceEvent e) {
    final token = _normalizeToken(e.eventType);
    if (token == 'booking_mollie_refund' && e.refundedAt.isNotEmpty) {
      return e.refundedAt;
    }
    if (token == 'booking_credit_decision' && e.creditedAt.isNotEmpty) {
      return e.creditedAt;
    }
    return e.createdAtUtc;
  }

  DateTime? _parseAuditTimestampUtc(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  String _dossierLatestMessageTimestamp(List<RemoteComplianceEvent> events) {
    DateTime? bestTime;
    String bestRaw = '';
    for (final event in events) {
      final raw = _eventAuditTimestampRaw(event);
      final parsed = _parseAuditTimestampUtc(raw);
      if (parsed == null) continue;
      if (bestTime == null || parsed.isAfter(bestTime)) {
        bestTime = parsed;
        bestRaw = raw;
      }
    }
    if (bestRaw.isEmpty) {
      for (final event in events) {
        final raw = event.createdAtUtc.trim();
        if (raw.isEmpty) continue;
        final parsed = _parseAuditTimestampUtc(raw);
        if (parsed == null) continue;
        if (bestTime == null || parsed.isAfter(bestTime)) {
          bestTime = parsed;
          bestRaw = raw;
        }
      }
    }
    return bestRaw.isEmpty ? '—' : _fmtDateTime(bestRaw);
  }

  void _logChironLatestEventDiagnostic(
    List<RemoteComplianceEvent> events,
    RemoteComplianceEvent latestByStorage,
  ) {
    final bookingLabel = () {
      for (final event in events) {
        final bookingId = event.bookingId.trim();
        if (_isMeaningfulIdentity(bookingId)) return bookingId;
      }
      return '-';
    }();
    RemoteComplianceEvent? latestByDisplay;
    DateTime? bestDisplayTime;
    for (final event in events) {
      final parsed = _parseAuditTimestampUtc(_eventAuditTimestampRaw(event));
      if (parsed == null) continue;
      if (bestDisplayTime == null || parsed.isAfter(bestDisplayTime)) {
        bestDisplayTime = parsed;
        latestByDisplay = event;
      }
    }
    final storageDisplayed =
        latestByDisplay?.eventId.isNotEmpty == true &&
        latestByDisplay?.eventId == latestByStorage.eventId;
    debugPrint(
      '[CHIRON][LATEST_EVENT] booking=$bookingLabel event_type=${latestByStorage.eventType} timestamp=${latestByStorage.createdAtUtc} displayed=$storageDisplayed',
    );
    if (latestByDisplay != null &&
        latestByDisplay.eventId != latestByStorage.eventId) {
      debugPrint(
        '[CHIRON][LATEST_EVENT] booking=$bookingLabel event_type=${latestByDisplay.eventType} timestamp=${_eventAuditTimestampRaw(latestByDisplay)} displayed=true',
      );
    }
  }

  void _logChironPaymentMethodDiagnostic({
    required String bookingId,
    required String methodRaw,
    required String methodDisplay,
    required String provider,
    required String source,
  }) {
    debugPrint(
      '[CHIRON][PAYMENT_METHOD] booking=${bookingId.isEmpty ? "-" : bookingId} method_raw=${methodRaw.isEmpty ? "-" : methodRaw} method_display=${methodDisplay.isEmpty ? "-" : methodDisplay} provider=${provider.isEmpty ? "-" : provider} source=${source.isEmpty ? "-" : source}',
    );
  }

  void _logChironSyncStatusDiagnostic({
    required String bookingId,
    required String raw,
    required String display,
  }) {
    debugPrint(
      '[CHIRON][SYNC_STATUS] booking=${bookingId.isEmpty ? "-" : bookingId} raw=${raw.isEmpty ? "-" : raw} display=${display.isEmpty ? "-" : display}',
    );
  }

  RemoteComplianceEvent? _latestEventOfType(
    List<RemoteComplianceEvent> events,
    String eventType,
  ) {
    RemoteComplianceEvent? latest;
    final wanted = _normalizeToken(eventType);
    for (final event in events) {
      if (_normalizeToken(event.eventType) != wanted) continue;
      if (latest == null || _isNewerRemoteEvent(event, latest)) {
        latest = event;
      }
    }
    return latest;
  }

  RemoteComplianceEvent? _latestMollieRefundEvent(
    List<RemoteComplianceEvent> events,
  ) => _latestEventOfType(events, 'booking_mollie_refund');

  RemoteComplianceEvent? _bestMollieRefundEventForSummary(
    List<RemoteComplianceEvent> events,
  ) {
    RemoteComplianceEvent? latestTerminal;
    RemoteComplianceEvent? latestAny;
    for (final event in events) {
      if (_normalizeToken(event.eventType) != 'booking_mollie_refund') continue;
      if (latestAny == null || _isNewerRemoteEvent(event, latestAny)) {
        latestAny = event;
      }
      if (_isMollieRefundConfirmedAuditEvent(event)) {
        if (latestTerminal == null ||
            _isNewerRemoteEvent(event, latestTerminal)) {
          latestTerminal = event;
        }
      }
    }
    return latestTerminal ?? latestAny;
  }

  int _mollieRefundEventCount(List<RemoteComplianceEvent> events) {
    var count = 0;
    for (final event in events) {
      if (_normalizeToken(event.eventType) == 'booking_mollie_refund') {
        count += 1;
      }
    }
    return count;
  }

  void _logRefundAuditDiagnostic(
    List<RemoteComplianceEvent> events,
    RemoteComplianceEvent? summaryRefund,
  ) {
    final bookingLabel = () {
      final fromSummary = summaryRefund?.bookingId.trim() ?? '';
      if (fromSummary.isNotEmpty) return fromSummary;
      for (final event in events) {
        if (_normalizeToken(event.eventType) != 'booking_mollie_refund') {
          continue;
        }
        final bookingId = event.bookingId.trim();
        if (bookingId.isNotEmpty) return bookingId;
      }
      return '-';
    }();
    final latestStatus = () {
      if (summaryRefund == null) return '-';
      if (summaryRefund.refundStatus.trim().isNotEmpty) {
        return summaryRefund.refundStatus.trim();
      }
      if (summaryRefund.status.trim().isNotEmpty) {
        return summaryRefund.status.trim();
      }
      return '-';
    }();
    debugPrint(
      '[CHIRON][REFUND_AUDIT] booking=$bookingLabel latest_refund_status=$latestStatus refund_event_count=${_mollieRefundEventCount(events)}',
    );
  }

  RemoteComplianceEvent? _latestCreditDecisionEvent(
    List<RemoteComplianceEvent> events,
  ) => _latestEventOfType(events, 'booking_credit_decision');

  RemoteComplianceEvent? _latestPaymentUpdateEvent(
    List<RemoteComplianceEvent> events,
  ) => _latestEventOfType(events, 'payment_update');

  List<Widget> _actorAuditChip(RemoteComplianceEvent e) {
    final actorRole = _text(e.actorRole);
    if (actorRole.isEmpty || actorRole.toLowerCase() == 'unknown') {
      return const <Widget>[];
    }
    return [
      _chip(
        '${_t(nl: 'Actor', en: 'Actor', fr: 'Acteur', es: 'Actor')}: ${_localizedActorRoleLabel(actorRole)}',
      ),
    ];
  }

  List<Widget> _creditAuditChips(RemoteComplianceEvent e) {
    final chips = <Widget>[];
    if (e.creditDecision.isNotEmpty) {
      chips.add(
        _chip(
          '${_t(nl: 'Creditbeslissing', en: 'Credit decision', fr: 'Décision crédit', es: 'Decisión crédito')}: ${_localizedCreditDecisionLabel(e.creditDecision)}',
        ),
      );
    }
    if (e.creditStatus.isNotEmpty) {
      chips.add(
        _chip(
          '${_t(nl: 'Creditstatus', en: 'Credit status', fr: 'Statut crédit', es: 'Estado crédito')}: ${_localizedCreditStatusLabel(e.creditStatus)}',
        ),
      );
    }
    if (e.creditedAmountCents != null && e.creditedAmountCents! > 0) {
      chips.add(
        _chip(
          '${_t(nl: 'Creditbedrag', en: 'Credited amount', fr: 'Montant crédité', es: 'Importe acreditado')}: ${_formatRefundAmountCents(e.creditedAmountCents)}',
        ),
      );
    }
    if (e.creditedAt.isNotEmpty) {
      chips.add(
        _chip(
          '${_t(nl: 'Gecrediteerd op', en: 'Credited at', fr: 'Crédité le', es: 'Acreditado el')}: ${_fmtDateTime(e.creditedAt)}',
        ),
      );
    }
    chips.addAll(_actorAuditChip(e));
    return chips;
  }

  List<Widget> _mollieRefundAuditChips(RemoteComplianceEvent e) {
    final chips = <Widget>[];
    if (e.refundStatus.isNotEmpty) {
      chips.add(
        _chip(
          '${_t(nl: 'Terugbetalingsstatus', en: 'Refund status', fr: 'Statut remboursement', es: 'Estado reembolso')}: ${_localizedRefundStatusLabel(e.refundStatus)}',
        ),
      );
    }
    if (e.refundProvider.isNotEmpty) {
      chips.add(
        _chip(
          '${_t(nl: 'Terugbetalingsprovider', en: 'Refund provider', fr: 'Fournisseur remboursement', es: 'Proveedor reembolso')}: ${_localizedRefundProviderLabel(e.refundProvider)}',
        ),
      );
    }
    if (e.refundAmountCents != null && e.refundAmountCents! > 0) {
      chips.add(
        _chip(
          '${_t(nl: 'Terugbetaald bedrag', en: 'Refund amount', fr: 'Montant remboursé', es: 'Importe reembolsado')}: ${_formatRefundAmountCents(e.refundAmountCents)}',
        ),
      );
    }
    if (e.refundId.isNotEmpty) {
      chips.add(
        _chip(
          '${_t(nl: 'Mollie-terugbetalings-ID', en: 'Mollie refund ID', fr: 'ID remboursement Mollie', es: 'ID reembolso Mollie')}: ${e.refundId}',
        ),
      );
    }
    if (e.creditedAmountCents != null && e.creditedAmountCents! > 0) {
      chips.add(
        _chip(
          '${_t(nl: 'Creditbedrag', en: 'Credited amount', fr: 'Montant crédité', es: 'Importe acreditado')}: ${_formatRefundAmountCents(e.creditedAmountCents)}',
        ),
      );
    }
    if (e.creditDecision.isNotEmpty) {
      chips.add(
        _chip(
          '${_t(nl: 'Creditbeslissing', en: 'Credit decision', fr: 'Décision crédit', es: 'Decisión crédito')}: ${_localizedCreditDecisionLabel(e.creditDecision)}',
        ),
      );
    }
    chips.addAll(_actorAuditChip(e));
    if (e.refundedAt.isNotEmpty) {
      chips.add(
        _chip(
          '${_t(nl: 'Terugbetaald op', en: 'Refunded at', fr: 'Remboursé le', es: 'Reembolsado el')}: ${_fmtDateTime(e.refundedAt)}',
        ),
      );
    }
    return chips;
  }

  List<Widget> _mollieRefundSummaryChips(RemoteComplianceEvent e) {
    final chips = <Widget>[];
    if (e.refundStatus.isNotEmpty) {
      chips.add(
        _chip(
          '${_t(nl: 'Terugbetalingsstatus', en: 'Refund status', fr: 'Statut remboursement', es: 'Estado reembolso')}: ${_localizedRefundStatusLabel(e.refundStatus)}',
        ),
      );
    }
    if (e.refundProvider.isNotEmpty) {
      chips.add(
        _chip(
          '${_t(nl: 'Terugbetalingsprovider', en: 'Refund provider', fr: 'Fournisseur remboursement', es: 'Proveedor reembolso')}: ${_localizedRefundProviderLabel(e.refundProvider)}',
        ),
      );
    }
    if (e.refundAmountCents != null && e.refundAmountCents! > 0) {
      chips.add(
        _chip(
          '${_t(nl: 'Terugbetaald bedrag', en: 'Refund amount', fr: 'Montant remboursé', es: 'Importe reembolsado')}: ${_formatRefundAmountCents(e.refundAmountCents)}',
        ),
      );
    }
    if (e.refundId.isNotEmpty) {
      chips.add(
        _chip(
          '${_t(nl: 'Mollie-terugbetalings-ID', en: 'Mollie refund ID', fr: 'ID remboursement Mollie', es: 'ID reembolso Mollie')}: ${e.refundId}',
        ),
      );
    }
    if (e.creditedAmountCents != null && e.creditedAmountCents! > 0) {
      chips.add(
        _chip(
          '${_t(nl: 'Creditbedrag', en: 'Credited amount', fr: 'Montant crédité', es: 'Importe acreditado')}: ${_formatRefundAmountCents(e.creditedAmountCents)}',
        ),
      );
    }
    chips.addAll(_actorAuditChip(e));
    if (e.refundedAt.isNotEmpty) {
      chips.add(
        _chip(
          '${_t(nl: 'Terugbetaald op', en: 'Refunded at', fr: 'Remboursé le', es: 'Reembolsado el')}: ${_fmtDateTime(e.refundedAt)}',
        ),
      );
    }
    return chips;
  }

  List<Widget> _paymentUpdateAuditChips(
    RemoteComplianceEvent e,
    Map<String, RemoteComplianceEvent> latestPaymentUpdates, {
    String? aggregateSyncChipLabel,
  }) {
    final payment = _effectivePaymentForEvent(e, latestPaymentUpdates);
    final chips = <Widget>[];
    final syncLabel = _renderableSyncStateChipLabel(e.syncState);
    if (syncLabel != null && syncLabel != aggregateSyncChipLabel) {
      chips.add(
        _chip(
          '${_t(nl: 'Synchronisatie', en: 'Sync', fr: 'Synchronisation', es: 'Sincronización')}: $syncLabel',
        ),
      );
    }
    if (payment.status.isNotEmpty) {
      chips.add(
        _chip(
          '${_t(nl: 'Betaling', en: 'Payment', fr: 'Paiement', es: 'Pago')}: ${_localizedPaymentStatusLabel(payment.status)}',
        ),
      );
    }
    if (_hasDisplayablePaymentMethod(
      method: payment.method,
      provider: payment.provider,
      source: payment.source,
    )) {
      chips.add(
        _chip(
          '${_t(nl: 'Methode', en: 'Method', fr: 'Méthode', es: 'Método')}: ${_localizedPaymentMethodLabel(payment.method, provider: payment.provider, source: payment.source)}',
        ),
      );
    }
    if (payment.source.isNotEmpty &&
        payment.source.toLowerCase() != 'unknown') {
      chips.add(
        _chip(
          '${_t(nl: 'Bron', en: 'Source', fr: 'Source', es: 'Fuente')}: ${_localizedSourceLabel(payment.source)}',
        ),
      );
    }
    if (payment.provider.isNotEmpty &&
        payment.provider.toLowerCase() != 'unknown') {
      chips.add(
        _chip(
          '${_t(nl: 'Provider', en: 'Provider', fr: 'Fournisseur', es: 'Proveedor')}: ${_localizedProviderLabel(payment.provider)}',
        ),
      );
    }
    chips.addAll(_actorAuditChip(e));
    return chips;
  }

  List<Widget> _cancellationAuditChips(
    RemoteComplianceEvent e, {
    String? aggregateSyncChipLabel,
  }) {
    final chips = <Widget>[];
    final syncLabel = _renderableSyncStateChipLabel(e.syncState);
    if (syncLabel != null && syncLabel != aggregateSyncChipLabel) {
      chips.add(
        _chip(
          '${_t(nl: 'Synchronisatie', en: 'Sync', fr: 'Synchronisation', es: 'Sincronización')}: $syncLabel',
        ),
      );
    }
    chips.add(
      _chip(
        '${_t(nl: 'Status', en: 'Status', fr: 'Statut', es: 'Estado')}: ${_t(nl: 'geannuleerd', en: 'cancelled', fr: 'annulée', es: 'cancelado')}',
      ),
    );
    chips.addAll(_actorAuditChip(e));
    return chips;
  }

  List<Widget> _auditHistoryChips(
    RemoteComplianceEvent e,
    Map<String, RemoteComplianceEvent> latestPaymentUpdates, {
    String? aggregateSyncChipLabel,
  }) {
    final token = _normalizeToken(e.eventType);
    switch (token) {
      case 'payment_update':
        return _paymentUpdateAuditChips(
          e,
          latestPaymentUpdates,
          aggregateSyncChipLabel: aggregateSyncChipLabel,
        );
      case 'booking_status_update':
        if (_eventIsCancelledStatusUpdate(e)) {
          return _cancellationAuditChips(
            e,
            aggregateSyncChipLabel: aggregateSyncChipLabel,
          );
        }
        break;
      case 'booking_credit_decision':
        return _creditAuditChips(e);
      case 'booking_mollie_refund':
        return _mollieRefundAuditChips(e);
    }
    final payment = _effectivePaymentForEvent(e, latestPaymentUpdates);
    final producer = _text(e.provenance['producer']);
    final syncLabel = _renderableSyncStateChipLabel(e.syncState);
    return [
      if (syncLabel != null && syncLabel != aggregateSyncChipLabel)
        _chip(
          '${_t(nl: 'Synchronisatie', en: 'Sync', fr: 'Synchronisation', es: 'Sincronización')}: $syncLabel',
        ),
      if (payment.status.isNotEmpty)
        _chip(
          '${_t(nl: 'Betaling', en: 'Payment', fr: 'Paiement', es: 'Pago')}: ${_localizedPaymentStatusLabel(payment.status)}',
        ),
      ..._roundtripLegAuditChips(e),
      if (producer.isNotEmpty)
        _chip(
          '${_t(nl: 'Aangemaakt door', en: 'Created by', fr: 'Créé par', es: 'Creado por')}: ${_localizedProducerLabel(producer)}',
        ),
      ..._actorAuditChip(e),
    ];
  }

  // Roundtrip operational-leg audit chips: show leg type, leg amount, parent
  // total, distance and the actual stop/start timestamps when the event
  // carries them. These chips are additive — events without leg metadata
  // produce no chips so existing one-way audit rows are unchanged.
  List<Widget> _roundtripLegAuditChips(RemoteComplianceEvent e) {
    final chips = <Widget>[];
    final legLabel = _localizedRoundtripLegLabel(e.legType);
    if (legLabel.isNotEmpty) {
      chips.add(
        _chip(
          '${_t(nl: 'Ritdeel', en: 'Leg', fr: 'Segment', es: 'Tramo')}: $legLabel',
        ),
      );
    }
    final legStatusToken = e.legStatus.trim();
    if (legStatusToken.isNotEmpty) {
      chips.add(
        _chip(
          '${_t(nl: 'Legstatus', en: 'Leg status', fr: 'Statut du trajet', es: 'Estado del tramo')}: ${_localizedLifecycleStatusLabel(legStatusToken)}',
        ),
      );
    }
    final parentStatusToken = e.parentStatus.trim();
    if (parentStatusToken.isNotEmpty) {
      chips.add(
        _chip(
          '${_t(nl: 'Hoofdboeking', en: 'Parent booking', fr: 'Reservation parente', es: 'Reserva principal')}: ${_localizedLifecycleStatusLabel(parentStatusToken)}',
        ),
      );
    }
    final legAmount = e.legPriceInclVat;
    if (legAmount != null && legAmount.isFinite) {
      chips.add(
        _chip(
          '${_t(nl: 'Legbedrag', en: 'Leg amount', fr: 'Montant du segment', es: 'Importe del tramo')}: ${_formatComplianceAmountEur(legAmount)}',
        ),
      );
    }
    final parentAmount = e.parentPriceInclVat;
    if (parentAmount != null &&
        parentAmount.isFinite &&
        (legAmount == null || parentAmount != legAmount)) {
      chips.add(
        _chip(
          '${_t(nl: 'Totaal hoofdboeking', en: 'Parent total', fr: 'Total parent', es: 'Total principal')}: ${_formatComplianceAmountEur(parentAmount)}',
        ),
      );
    }
    final distanceKm = e.distanceKm;
    if (distanceKm != null && distanceKm.isFinite && distanceKm > 0) {
      chips.add(
        _chip(
          '${_t(nl: 'Afstand', en: 'Distance', fr: 'Distance', es: 'Distancia')}: ${distanceKm.toStringAsFixed(1)} km',
        ),
      );
    }
    final waitMin = e.waitMin;
    if (waitMin != null && waitMin.isFinite && waitMin > 0) {
      chips.add(
        _chip(
          '${_t(nl: 'Wachttijd', en: 'Wait time', fr: 'Temps dattente', es: 'Tiempo de espera')}: ${waitMin.toStringAsFixed(0)} min',
        ),
      );
    }
    final startedAt = e.startedAtUtc.trim();
    if (startedAt.isNotEmpty) {
      chips.add(
        _chip(
          '${_t(nl: 'Gestart', en: 'Started', fr: 'Demarre', es: 'Iniciado')}: ${_formatComplianceTimestampShort(startedAt)}',
        ),
      );
    }
    final stoppedAt = e.stoppedAtUtc.trim();
    if (stoppedAt.isNotEmpty) {
      chips.add(
        _chip(
          '${_t(nl: 'Gestopt', en: 'Stopped', fr: 'Arrete', es: 'Detenido')}: ${_formatComplianceTimestampShort(stoppedAt)}',
        ),
      );
    }
    return chips;
  }

  String _formatComplianceAmountEur(double value) {
    final fixed = value.toStringAsFixed(2).replaceAll('.', ',');
    return '€ $fixed';
  }

  String _formatComplianceTimestampShort(String iso) {
    final raw = iso.trim();
    if (raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    String two(int n) => n.toString().padLeft(2, '0');
    final local = dt.toLocal();
    return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }

  String _localizedLifecycleStatusLabel(String raw) {
    final token = _normalizeToken(raw);
    switch (token) {
      case 'completed':
      case 'complete':
      case 'finished':
        return _t(
          nl: 'afgerond',
          en: 'completed',
          fr: 'terminée',
          es: 'finalizado',
        );
      case 'cancelled':
      case 'canceled':
        return _t(
          nl: 'geannuleerd',
          en: 'cancelled',
          fr: 'annulée',
          es: 'cancelado',
        );
      case 'pending':
      case 'awaiting':
        return _t(
          nl: 'in behandeling',
          en: 'pending',
          fr: 'en attente',
          es: 'pendiente',
        );
      case 'scheduled':
      case 'planned':
      case 'in_planning':
      case 'confirmed':
        return _t(
          nl: 'gepland',
          en: 'scheduled',
          fr: 'planifiée',
          es: 'planificado',
        );
      case 'in_progress':
      case 'started':
      case 'active':
        return _t(
          nl: 'bezig',
          en: 'in progress',
          fr: 'en cours',
          es: 'en curso',
        );
      default:
        return raw.trim().isEmpty ? '-' : raw.trim().toLowerCase();
    }
  }

  Widget _auditHistoryRow(
    RemoteComplianceEvent e,
    Map<String, RemoteComplianceEvent> latestPaymentUpdates, {
    String? aggregateSyncChipLabel,
  }) {
    final eventTitle = _localizedAuditEventTitle(e);
    final rideTypeLabel = _localizedAuditRideTypeLabel(e);
    final legLabel = _localizedRoundtripLegLabel(e.legType);
    // Roundtrip operational-leg audit row: when the event carries leg_type
    // (Heenrit / Terugrit) append it so a leg-scoped ride_stop reads
    // "Rit afgerond • Geplande rit • Heenrit" instead of being indistinguishable
    // from a parent-level completion.
    final titleParts = <String>[eventTitle, rideTypeLabel];
    if (legLabel.isNotEmpty) {
      titleParts.add(legLabel);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _chironPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _chironBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titleParts.join(' • '),
            style: TextStyle(
              color: _chironTextPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _eventAuditTimestamp(e),
            style: TextStyle(color: _chironTextMuted, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _auditHistoryChips(
              e,
              latestPaymentUpdates,
              aggregateSyncChipLabel: aggregateSyncChipLabel,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dossierCard(
    List<RemoteComplianceEvent> events,
    Map<String, RemoteComplianceEvent> latestPaymentUpdates,
  ) {
    final sorted = [...events]..sort(_compareRemoteEventsNewestFirst);
    final latest = sorted.first;
    final bookingId = sorted
        .map((event) => event.bookingId.trim())
        .firstWhere((id) => _isMeaningfulIdentity(id), orElse: () => '');
    final publicBookingReference = sorted
        .map((event) => event.publicBookingReference.trim())
        .firstWhere((id) => _isMeaningfulIdentity(id), orElse: () => '');
    final planningReference = sorted
        .map((event) => event.planningReference.trim())
        .firstWhere((id) => _isMeaningfulIdentity(id), orElse: () => '');
    final receiptReference = sorted
        .map((event) => event.receiptReference.trim())
        .firstWhere((id) => _isMeaningfulIdentity(id), orElse: () => '');
    final tripId = sorted
        .map((event) => event.tripId.trim())
        .firstWhere((id) => _isMeaningfulIdentity(id), orElse: () => '');
    final latestPaymentUpdate = _latestPaymentUpdateEvent(sorted);
    final latestCreditDecision = _latestCreditDecisionEvent(sorted);
    final latestRefund = _bestMollieRefundEventForSummary(sorted);
    _logRefundAuditDiagnostic(sorted, latestRefund);
    _logChironLatestEventDiagnostic(sorted, latest);
    final payment = latestPaymentUpdate == null
        ? _effectivePaymentForEvent(latest, latestPaymentUpdates)
        : (
            status: _text(latestPaymentUpdate.payment['status']),
            method: _text(latestPaymentUpdate.payment['method']),
            source: _text(latestPaymentUpdate.payment['source']),
            provider: _text(latestPaymentUpdate.payment['provider']),
          );
    _logChironPaymentMethodDiagnostic(
      bookingId: bookingId,
      methodRaw: payment.method,
      methodDisplay: _localizedPaymentMethodLabel(
        payment.method,
        provider: payment.provider,
        source: payment.source,
      ),
      provider: payment.provider,
      source: payment.source,
    );
    _logChironSyncStatusDiagnostic(
      bookingId: bookingId,
      raw: latest.syncState,
      display: _localizedSyncStateLabel(latest.syncState),
    );
    final aggregateSyncChipLabel = _aggregateSyncStateChipLabel(sorted);
    final reference = _businessReferenceForRemoteCard(
      rideType: latest.rideType,
      publicBookingReference: publicBookingReference,
      planningReference: planningReference,
      receiptReference: receiptReference,
      bookingId: bookingId,
      tripId: tripId,
    );
    final showInternalBooking =
        bookingId.isNotEmpty &&
        bookingId != reference.value &&
        !_isTechnicalInternalReference(bookingId);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _chironCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _chironBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _localizedDossierTitle(latest.rideType),
            style: TextStyle(
              color: _chironTextPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _labelValue(reference.label, reference.value),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _chironTextSecondary, fontSize: 12),
          ),
          if (showInternalBooking) ...[
            const SizedBox(height: 2),
            Text(
              _labelValue(_localizedInternalBookingLabel(), bookingId),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _chironTextFaint, fontSize: 11),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${_t(nl: 'Laatste melding', en: 'Latest message', fr: 'Dernier message', es: 'Último mensaje')}: ${_dossierLatestMessageTimestamp(sorted)}',
            style: TextStyle(color: _chironTextMuted, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                '${_t(nl: 'Ritstatus', en: 'Ride status', fr: 'Statut de la course', es: 'Estado del viaje')}: ${_localizedRideStatus(sorted)}',
              ),
              if (aggregateSyncChipLabel != null)
                _chip(
                  '${_t(nl: 'Synchronisatie', en: 'Sync', fr: 'Synchronisation', es: 'Sincronización')}: $aggregateSyncChipLabel',
                ),
              if (payment.status.isNotEmpty)
                _chip(
                  '${_t(nl: 'Betaling', en: 'Payment', fr: 'Paiement', es: 'Pago')}: ${_localizedPaymentStatusLabel(payment.status)}',
                ),
              if (_hasDisplayablePaymentMethod(
                method: payment.method,
                provider: payment.provider,
                source: payment.source,
              ))
                _chip(
                  '${_t(nl: 'Methode', en: 'Method', fr: 'Méthode', es: 'Método')}: ${_localizedPaymentMethodLabel(payment.method, provider: payment.provider, source: payment.source)}',
                ),
              if (payment.source.isNotEmpty &&
                  payment.source.toLowerCase() != 'unknown')
                _chip(
                  '${_t(nl: 'Bron', en: 'Source', fr: 'Source', es: 'Fuente')}: ${_localizedSourceLabel(payment.source)}',
                ),
              if (payment.provider.isNotEmpty &&
                  payment.provider.toLowerCase() != 'unknown')
                _chip(
                  '${_t(nl: 'Provider', en: 'Provider', fr: 'Fournisseur', es: 'Proveedor')}: ${_localizedProviderLabel(payment.provider)}',
                ),
              if (latestCreditDecision != null)
                ..._creditAuditChips(latestCreditDecision),
              if (latestRefund != null)
                ..._mollieRefundSummaryChips(latestRefund),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _t(
              nl: 'Auditgeschiedenis',
              en: 'Audit history',
              fr: 'Historique d’audit',
              es: 'Historial de auditoría',
            ),
            style: TextStyle(
              color: _chironGold,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          ...sorted.map(
            (event) => _auditHistoryRow(
              event,
              latestPaymentUpdates,
              aggregateSyncChipLabel: aggregateSyncChipLabel,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _t(
                  nl: 'Compliancemodule',
                  en: 'Compliance module',
                  fr: 'Module de conformité',
                  es: 'Módulo de cumplimiento',
                ),
                style: TextStyle(color: _chironTextSecondary, fontSize: 12),
              ),
            ),
            IconButton(
              tooltip: _t(
                nl: 'Vernieuwen',
                en: 'Refresh',
                fr: 'Rafraîchir',
                es: 'Actualizar',
              ),
              onPressed: _refresh,
              icon: Icon(Icons.refresh, color: _chironGold.withOpacity(0.95)),
            ),
            /* CHIRON-P0-2A: destructive backend cleanup (reset compliance
             * events + its dry-run sibling) is hidden in release mode. The
             * booking-worker company-session proxy intentionally does not
             * expose these destructive routes, so the button would be a
             * no-op there anyway. */
            if (!kReleaseMode)
              IconButton(
                tooltip: _t(
                  nl: 'Backend test-events wissen',
                  en: 'Clear backend test events',
                  fr: 'Effacer les événements de test backend',
                  es: 'Borrar eventos de prueba del backend',
                ),
                onPressed: _isResettingRemoteEvents
                    ? null
                    : _resetRemoteComplianceEvents,
                icon: _isResettingRemoteEvents
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _chironGold,
                        ),
                      )
                    : Icon(
                        Icons.delete_forever,
                        color: _chironGold.withOpacity(0.95),
                      ),
              ),
          ],
        ),
        // Patch 4A: search field + horizontal category chips. Both
        // operate on already-loaded events; no network calls and no
        // change to the fetched event limit.
        const SizedBox(height: 8),
        TextField(
          controller: _searchController,
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
          style: TextStyle(color: _chironTextPrimary, fontSize: 13),
          cursorColor: _chironGold,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: _chironPanel,
            hintText: _t(
              nl: 'Zoek op boekingsnummer, interne boeking, terugbetalings-ID, betaalmethode...',
              en: 'Search by booking reference, booking id, refund id, payment method...',
              fr: 'Rechercher par référence, id de réservation, id de remboursement...',
              es: 'Buscar por referencia, id de reserva, id de reembolso...',
            ),
            hintStyle: TextStyle(color: _chironTextMuted, fontSize: 12),
            prefixIcon: Icon(
              Icons.search,
              size: 18,
              color: _chironTextSecondary,
            ),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: _t(
                      nl: 'Zoekopdracht wissen',
                      en: 'Clear search',
                      fr: 'Effacer la recherche',
                      es: 'Borrar búsqueda',
                    ),
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: _chironTextSecondary,
                    ),
                    onPressed: () {
                      setState(() {
                        _searchController.clear();
                        _searchQuery = '';
                      });
                    },
                  ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: _chironBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: _chironBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: _chironGold.withOpacity(0.7)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _RemoteComplianceCategoryFilter.values
                .map((cat) {
                  final selected = _categoryFilter == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        _categoryFilterLabel(cat),
                        style: TextStyle(
                          fontSize: 12,
                          color: selected ? _chironGold : _chironTextSecondary,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      selected: selected,
                      showCheckmark: false,
                      backgroundColor: _chironPanel,
                      selectedColor: _chironGold.withOpacity(0.16),
                      side: BorderSide(
                        color: selected
                            ? _chironGold.withOpacity(0.6)
                            : _chironBorder,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: selected
                              ? _chironGold.withOpacity(0.6)
                              : _chironBorder,
                        ),
                      ),
                      onSelected: (_) {
                        setState(() {
                          _categoryFilter = cat;
                        });
                      },
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: 12),
        if (!_loadCoordinator.prerequisitesReady)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _t(
                nl: 'Bedrijfscontext wordt geladen…',
                en: 'Loading company context…',
                fr: 'Chargement du contexte entreprise…',
                es: 'Cargando contexto de empresa…',
              ),
              style: TextStyle(color: _chironTextMuted, fontSize: 12),
            ),
          ),
        Builder(
          builder: (context) {
            // CHIRON-LAST-GOOD-DATA-PRESERVATION-1: first-ever load → loading;
            // remount with cache → keep last-good; hard error only without cache.
            if (_loading && _display == null) {
              return Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _chironGold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _t(
                      nl: 'Backendmeldingen laden...',
                      en: 'Loading backend messages...',
                      fr: 'Chargement des messages système...',
                      es: 'Cargando mensajes del sistema...',
                    ),
                    style: TextStyle(color: _chironTextSecondary, fontSize: 12),
                  ),
                ],
              );
            }

            final result = _display;
            if (result == null || !result.ok) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _chironPanel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _chironBorder),
                ),
                child: Text(
                  (_hardError == null || _hardError!.isEmpty)
                      ? _defaultUnavailableMessage()
                      : _hardError!,
                  style: TextStyle(color: _chironWarning, fontSize: 12),
                ),
              );
            }

            if (result.events.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_staleWarning)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _staleRefreshWarningMessage(),
                        style: TextStyle(color: _chironWarning, fontSize: 12),
                      ),
                    ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _chironPanel,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _chironBorder),
                    ),
                    child: Text(
                      _t(
                        nl: 'Geen backendmeldingen gevonden.',
                        en: 'No backend events found.',
                        fr: 'Aucun événement backend trouvé.',
                        es: 'No se encontraron eventos del backend.',
                      ),
                      style: TextStyle(color: _chironTextMuted, fontSize: 12),
                    ),
                  ),
                ],
              );
            }

            // Patch 4A: apply local search + category filter to the
            // already-loaded event list. The total `result.count` is
            // preserved for the header so the filter scope is clear
            // ("X van Y meldingen"). When the active filter yields
            // zero matches we render a friendly empty state instead
            // of the dossier list.
            final filteredEvents = _applyFilters(result.events);
            final latestPaymentUpdates = _latestPaymentUpdatesByKey(
              filteredEvents,
            );
            final grouped = groupChironDossiers<RemoteComplianceEvent>(
              events: filteredEvents,
              identitiesOf: (e) => ChironEventIdentities(
                bookingIdRaw: e.bookingId,
                tripIdRaw: e.tripId,
                eventIdRaw: e.eventId,
                createdAtUtcRaw: e.createdAtUtc,
              ),
              isMeaningfulIdentity: _isMeaningfulIdentity,
            );
            final dossiers = grouped.values.toList(growable: false)
              ..sort((a, b) {
                final newestA = [...a]..sort(_compareRemoteEventsNewestFirst);
                final newestB = [...b]..sort(_compareRemoteEventsNewestFirst);
                return _compareRemoteEventsNewestFirst(
                  newestA.first,
                  newestB.first,
                );
              });
            final headerText = _hasActiveFilter
                ? _t(
                    nl: 'Tenant ${result.tenantId} • Bedrijf ${result.companyId} • ${filteredEvents.length} van ${result.count} meldingen',
                    en: 'Tenant ${result.tenantId} • Company ${result.companyId} • ${filteredEvents.length} of ${result.count} events',
                    fr: 'Tenant ${result.tenantId} • Société ${result.companyId} • ${filteredEvents.length} sur ${result.count} événements',
                    es: 'Tenant ${result.tenantId} • Empresa ${result.companyId} • ${filteredEvents.length} de ${result.count} eventos',
                  )
                : _t(
                    nl: 'Tenant ${result.tenantId} • Bedrijf ${result.companyId} • ${result.count} meldingen',
                    en: 'Tenant ${result.tenantId} • Company ${result.companyId} • ${result.count} events',
                    fr: 'Tenant ${result.tenantId} • Société ${result.companyId} • ${result.count} événements',
                    es: 'Tenant ${result.tenantId} • Empresa ${result.companyId} • ${result.count} eventos',
                  );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_staleWarning)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _staleRefreshWarningMessage(),
                      style: TextStyle(color: _chironWarning, fontSize: 12),
                    ),
                  ),
                if (result.malformedCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _t(
                        nl: '${result.malformedCount} ongeldige melding(en) overgeslagen.',
                        en: '${result.malformedCount} malformed event(s) skipped.',
                        fr: '${result.malformedCount} événement(s) invalide(s) ignoré(s).',
                        es: '${result.malformedCount} evento(s) no válido(s) omitido(s).',
                      ),
                      style: TextStyle(color: _chironWarning, fontSize: 11),
                    ),
                  ),
                Text(
                  headerText,
                  style: TextStyle(color: _chironTextMuted, fontSize: 11),
                ),
                const SizedBox(height: 8),
                if (filteredEvents.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _chironPanel,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _chironBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t(
                            nl: 'Geen meldingen gevonden',
                            en: 'No messages found',
                            fr: 'Aucun message trouvé',
                            es: 'No se encontraron mensajes',
                          ),
                          style: TextStyle(
                            color: _chironTextPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _t(
                            nl: 'Pas je zoekopdracht of filter aan om meer resultaten te zien.',
                            en: 'Adjust your search or filter to see more results.',
                            fr: 'Ajustez votre recherche ou votre filtre pour voir plus de résultats.',
                            es: 'Ajusta tu búsqueda o filtro para ver más resultados.',
                          ),
                          style: TextStyle(
                            color: _chironTextMuted,
                            fontSize: 12,
                          ),
                        ),
                        if (_hasActiveFilter) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _resetSearchAndCategory,
                              icon: Icon(
                                Icons.filter_alt_off,
                                size: 16,
                                color: _chironGold,
                              ),
                              label: Text(
                                _t(
                                  nl: 'Filters wissen',
                                  en: 'Clear filters',
                                  fr: 'Effacer les filtres',
                                  es: 'Borrar filtros',
                                ),
                                style: TextStyle(
                                  color: _chironGold,
                                  fontSize: 12,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                else
                  ...dossiers.map(
                    (events) => _dossierCard(events, latestPaymentUpdates),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// Patch LR-1: client-side category filter for the local ride register.
enum _LocalRideRegisterCategoryFilter {
  alles,
  straatritten,
  geplandeRitten,
  betaald,
  nogTeBetalen,
  geannuleerd,
}

class _LocalComplianceLedgerSection extends StatefulWidget {
  const _LocalComplianceLedgerSection({required this.lang});

  final AppLanguage lang;

  @override
  State<_LocalComplianceLedgerSection> createState() =>
      _LocalComplianceLedgerSectionState();
}

class _LocalComplianceLedgerSectionState
    extends State<_LocalComplianceLedgerSection> {
  late final ComplianceLedgerReader _reader;
  ComplianceLedgerReadResult? _result;
  bool _isLoading = true;
  bool _refreshBusy = false;
  String? _loadError;
  bool _isClearingLocalTestData = false;
  bool _isClearingLocalCustomerBookings = false;
  late final ChironContextLoadCoordinator _loadCoordinator;
  Timer? _prereqTimeout;
  Timer? _hardDeadline;
  // Patch LR-1: local-only search + category filter for the ride register.
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _LocalRideRegisterCategoryFilter _categoryFilter =
      _LocalRideRegisterCategoryFilter.alles;

  static const Duration _hardLoadDeadline = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    // Resolve the reader in initState so test factories set before navigation
    // are honored (field initializers can race with test setup ordering).
    _reader = ComplianceLedgerReader.create();
    debugPrint(
      '[LOCAL_RIDE_REGISTER][READER] type=${_reader.runtimeType}',
    );
    _loadCoordinator = ChironContextLoadCoordinator(
      listenables: <Listenable>[
        activeCompanySessionNotifier,
        companyProfileNotifier,
      ],
      hasCompanySession: () => hasCompanyOwnerAuthContext(),
      companyId: () {
        final profile = companyProfileNotifier.value?.companyId.trim() ?? '';
        if (profile.isNotEmpty) return profile;
        return activeCompanySessionNotifier.value?.companyId.trim() ?? '';
      },
      runLoad: _performRegisterLoad,
      onDiag: (stage) => debugPrint('[CHIRON_LOAD][DIAG] stage=$stage'),
    );
    // Defer attach: the coordinator starts a load that setStates. Doing that
    // synchronously from initState (ancestor still building) aborts the load
    // and leaves the page stuck on "Loading local ledger...".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loadCoordinator.isDisposed) return;
      _loadCoordinator.attach();
    });
    // Terminal empty/error instead of an infinite "loading company context".
    _prereqTimeout = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      if (!_loadCoordinator.prerequisitesReady && _result == null) {
        _forceTerminal(
          error: 'missing_company_context',
          backendError: 'missing_company_context',
        );
      }
    });
    // Absolute last-resort: never leave the spinner past 12s even if a
    // generation is discarded or a native open never returns to Dart.
    _hardDeadline = Timer(_hardLoadDeadline, () {
      if (!mounted) return;
      if (_isLoading && _result == null) {
        debugPrint('[LOCAL_RIDE_REGISTER][UI_LOAD] error=hard_deadline');
        _forceTerminal(
          error: 'load_deadline',
          backendError: 'load_deadline',
        );
      }
    });
  }

  @override
  void dispose() {
    _prereqTimeout?.cancel();
    _hardDeadline?.cancel();
    _loadCoordinator.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _forceTerminal({required String error, required String backendError}) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _refreshBusy = false;
      _loadError = error;
      _result ??= ComplianceLedgerReadResult(
        entries: const <ComplianceLedgerEntry>[],
        fileExists: false,
        skippedMalformedLines: 0,
        isSyncingBackend: false,
        backendFetchOk: false,
        backendError: backendError,
      );
    });
  }

  /// Apply UI updates for [gen], or for any stale completion that would
  /// otherwise leave the page stuck on the first-paint spinner.
  bool _mayApply(int gen) {
    if (!mounted) return false;
    if (_loadCoordinator.shouldApplyGeneration(gen)) return true;
    return _isLoading && _result == null;
  }

  Future<void> _performRegisterLoad(int gen) async {
    debugPrint(
      '[LOCAL_RIDE_REGISTER][UI_LOAD] begin gen=$gen reader=${_reader.runtimeType}',
    );
    final keepVisibleCache = _result != null && _result!.entries.isNotEmpty;
    if (_loadCoordinator.shouldApplyGeneration(gen) && mounted) {
      setState(() {
        // Never blank already-visible cache while a refresh is in flight.
        _isLoading = !keepVisibleCache && _result == null;
        _refreshBusy = true;
        if (!keepVisibleCache) _loadError = null;
      });
    }
    try {
      final sw = Stopwatch()..start();
      final result = await _reader
          .loadRegisterGrouped(
            groupLimit: 20,
            onLocalLoaded: (local) {
              if (!_mayApply(gen)) return;
              setState(() {
                _result = local;
                _isLoading = false;
                final localErr = (local.backendError ?? '').trim();
                if (localErr == 'local_file_lock' ||
                    localErr == 'local_read_timeout') {
                  _loadError = localErr;
                }
              });
            },
          )
          .timeout(_hardLoadDeadline);
      debugPrint(
        '[LOCAL_RIDE_REGISTER][UI_LOAD] gen=$gen elapsed_ms=${sw.elapsedMilliseconds} '
        'backend_ok=${result.backendFetchOk} merged=${result.mergedCount} '
        'error=${result.backendError ?? '-'}',
      );
      if (!_mayApply(gen)) return;
      setState(() {
        // Keep prior rows when a refresh fails with empty payload.
        if (result.entries.isEmpty &&
            keepVisibleCache &&
            result.backendFetchOk == false) {
          _result = _result!.copyWith(
            backendFetchOk: false,
            backendError: result.backendError,
            isSyncingBackend: false,
          );
        } else {
          _result = result;
        }
        _isLoading = false;
        _refreshBusy = false;
        final err = (result.backendError ?? '').trim();
        if (result.backendFetchOk == false &&
            err.isNotEmpty &&
            (_result?.entries.isEmpty ?? true)) {
          _loadError = err;
        } else if (result.backendFetchOk == true) {
          _loadError = null;
        }
      });
    } on TimeoutException {
      debugPrint('[LOCAL_RIDE_REGISTER][UI_LOAD] gen=$gen error=timeout');
      if (!_mayApply(gen)) return;
      setState(() {
        _isLoading = false;
        _refreshBusy = false;
        if (_result == null || _result!.entries.isEmpty) {
          _loadError = 'backend_timeout';
          _result ??= const ComplianceLedgerReadResult(
            entries: <ComplianceLedgerEntry>[],
            fileExists: false,
            skippedMalformedLines: 0,
            isSyncingBackend: false,
            backendFetchOk: false,
            backendError: 'backend_timeout',
          );
        } else {
          _result = _result!.copyWith(
            backendFetchOk: false,
            backendError: 'backend_timeout',
            isSyncingBackend: false,
          );
        }
      });
    } catch (err) {
      final code = complianceLedgerLooksLikeLockError(err)
          ? 'local_file_lock'
          : 'load_failed';
      debugPrint(
        '[LOCAL_RIDE_REGISTER][UI_LOAD] gen=$gen error=$code',
      );
      if (!_mayApply(gen)) return;
      setState(() {
        _isLoading = false;
        _refreshBusy = false;
        if (_result == null || _result!.entries.isEmpty) {
          _loadError = code;
          _result ??= ComplianceLedgerReadResult(
            entries: const <ComplianceLedgerEntry>[],
            fileExists: false,
            skippedMalformedLines: 0,
            isSyncingBackend: false,
            backendFetchOk: false,
            backendError: code,
          );
        } else {
          _result = _result!.copyWith(
            backendFetchOk: false,
            backendError: code,
            isSyncingBackend: false,
          );
        }
      });
    } finally {
      if (mounted && _refreshBusy && _loadCoordinator.shouldApplyGeneration(gen)) {
        setState(() => _refreshBusy = false);
      }
    }
  }

  void _refresh() {
    if (_refreshBusy || _loadCoordinator.loadInFlight) return;
    // Synchronous busy latch so double-taps cannot enqueue two refreshes
    // before the async load body runs.
    _refreshBusy = true;
    if (mounted) setState(() {});
    _loadCoordinator.requestManualRefresh();
  }

  Future<void> _hideGroupFromRegister(List<ComplianceLedgerEntry> group) async {
    if (group.isEmpty) return;
    final groupKey = ComplianceLedgerReader.groupKeyFor(group.first);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final tokens = _chironTokens();
        return AlertDialog(
          backgroundColor: tokens.card,
          title: Text(
            _t(
              nl: 'Verbergen uit lokaal register?',
              en: 'Hide from local register?',
              fr: 'Masquer du registre local ?',
              es: '¿Ocultar del registro local?',
            ),
            style: TextStyle(color: tokens.textPrimary),
          ),
          content: Text(
            _t(
              nl: 'Dit verbergt alleen deze rit in het lokale register op dit toestel. Compliance- en auditgegevens op de backend blijven behouden.',
              en: 'This only hides this ride from the local register on this device. Compliance and audit records on the backend remain intact.',
              fr: 'Cela masque uniquement ce trajet du registre local sur cet appareil. Les données de conformité et d’audit backend restent intactes.',
              es: 'Esto solo oculta este viaje del registro local en este dispositivo. Los registros de cumplimiento y auditoría del backend permanecen intactos.',
            ),
            style: TextStyle(color: tokens.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                _t(
                  nl: 'Annuleren',
                  en: 'Cancel',
                  fr: 'Annuler',
                  es: 'Cancelar',
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                _t(nl: 'Verbergen', en: 'Hide', fr: 'Masquer', es: 'Ocultar'),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await _reader.hideGroupFromRegister(groupKey);
    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Rit verborgen uit lokaal register.',
            en: 'Ride hidden from local register.',
            fr: 'Trajet masqué du registre local.',
            es: 'Viaje oculto del registro local.',
          ),
        ),
      ),
    );
  }

  Future<void> _copyReference(ComplianceLedgerEntry entry) async {
    final reference = _businessReferenceForLocalCard(entry);
    final text = reference.value.trim();
    if (text.isEmpty || text == '—') return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Referentie gekopieerd.',
            en: 'Reference copied.',
            fr: 'Référence copiée.',
            es: 'Referencia copiada.',
          ),
        ),
      ),
    );
  }

  ({String tenantId, String companyId})? _effectiveTenantCompanyIds() {
    final activeCompanyId =
        companyProfileNotifier.value?.companyId.trim() ?? '';
    if (activeCompanyId.isNotEmpty) {
      return (tenantId: activeCompanyId, companyId: activeCompanyId);
    }
    final sessionCompanyId =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (sessionCompanyId.isNotEmpty) {
      return (tenantId: sessionCompanyId, companyId: sessionCompanyId);
    }
    return null;
  }

  Future<void> _clearLocalTestData() async {
    if (_isClearingLocalTestData) return;
    final effective = _effectiveTenantCompanyIds();
    if (effective == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final tokens = _chironTokens();
        return AlertDialog(
          backgroundColor: tokens.card,
          title: Text(
            _t(
              nl: 'Lokale rittenregister-testdata wissen?',
              en: 'Clear local ride-register test data?',
              fr: 'Effacer les données de test locales du registre des courses ?',
              es: '¿Borrar los datos de prueba locales del registro de viajes?',
            ),
            style: TextStyle(color: tokens.textPrimary),
          ),
          content: Text(
            _t(
              nl: 'Dit wist alleen lokale rittenregister/Chiron-testdata voor tenant/bedrijf ${effective.companyId} op dit toestel. Bedrijfsinstellingen, voertuigen, chauffeurs en backenddata blijven behouden.',
              en: 'This only clears local ride-register/Chiron test data for tenant/company ${effective.companyId} on this device. Company settings, vehicles, drivers and backend data are kept.',
              fr: 'Cela efface uniquement les données de test locales du registre des courses/aperçu Chiron pour le tenant/société ${effective.companyId} sur cet appareil. Les paramètres d’entreprise, véhicules, chauffeurs et données backend sont conservés.',
              es: 'Esto solo borra los datos de prueba locales del registro de viajes/vista Chiron para el tenant/empresa ${effective.companyId} en este dispositivo. La configuración de empresa, vehículos, conductores y datos backend se conservan.',
            ),
            style: TextStyle(color: tokens.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: tokens.textSecondary,
              ),
              child: Text(
                _t(
                  nl: 'Annuleren',
                  en: 'Cancel',
                  fr: 'Annuler',
                  es: 'Cancelar',
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.palette.textOnAccent,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                _t(nl: 'Wissen', en: 'Clear', fr: 'Effacer', es: 'Borrar'),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isClearingLocalTestData = true);
    try {
      debugPrint(
        '[LOCAL_SCOPE][CLEANUP] source=chiron_local_register tenant=${effective.tenantId} company=${effective.companyId}',
      );
      await _reader.clearLocalTestData();
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Lokale rittenregister-testdata gewist.',
              en: 'Local ride-register test data cleared.',
              fr: 'Données de test locales du registre effacées.',
              es: 'Datos de prueba locales del registro borrados.',
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Wissen mislukt. Probeer opnieuw.',
              en: 'Clear failed. Please try again.',
              fr: 'Échec de l’effacement. Réessayez.',
              es: 'Error al borrar. Inténtalo de nuevo.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isClearingLocalTestData = false);
      }
    }
  }

  Future<void> _clearLocalCustomerBookings() async {
    if (_isClearingLocalCustomerBookings) return;
    final effective = _effectiveTenantCompanyIds();
    if (effective == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final tokens = _chironTokens();
        return AlertDialog(
          backgroundColor: tokens.card,
          title: Text(
            _t(
              nl: 'Lokale klantboekingen wissen?',
              en: 'Clear local customer bookings?',
              fr: 'Effacer les réservations client locales ?',
              es: '¿Borrar reservas locales del cliente?',
            ),
            style: TextStyle(color: tokens.textPrimary),
          ),
          content: Text(
            _t(
              nl: 'Dit wist alleen lokale testboekingen voor tenant/bedrijf ${effective.companyId} op dit toestel (Klant > Mijn boekingen). Bedrijfsinstellingen, chauffeurs, voertuigen, prijzen en backend operationele boekingen blijven behouden.',
              en: 'This only clears local test bookings for tenant/company ${effective.companyId} on this device (Customer > My bookings). Company settings, drivers, vehicles, pricing and backend operational bookings are kept.',
              fr: 'Cela efface uniquement les réservations de test locales pour le tenant/société ${effective.companyId} sur cet appareil (Client > Mes réservations). Les paramètres société, chauffeurs, véhicules, tarifs et réservations backend restent conservés.',
              es: 'Esto solo borra reservas de prueba locales para el tenant/empresa ${effective.companyId} en este dispositivo (Cliente > Mis reservas). La configuración de empresa, conductores, vehículos, precios y reservas operativas del backend se conservan.',
            ),
            style: TextStyle(color: tokens.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: tokens.textSecondary,
              ),
              child: Text(
                _t(
                  nl: 'Annuleren',
                  en: 'Cancel',
                  fr: 'Annuler',
                  es: 'Cancelar',
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.palette.textOnAccent,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                _t(nl: 'Wissen', en: 'Clear', fr: 'Effacer', es: 'Borrar'),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isClearingLocalCustomerBookings = true);
    try {
      debugPrint(
        '[LOCAL_SCOPE][CLEANUP] source=chiron_customer_bookings tenant=${effective.tenantId} company=${effective.companyId}',
      );
      await CustomerBookingsStore.instance.clearLocalTestData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Lokale klantboekingen gewist.',
              en: 'Local customer bookings cleared.',
              fr: 'Réservations client locales effacées.',
              es: 'Reservas locales del cliente borradas.',
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Wissen mislukt. Probeer opnieuw.',
              en: 'Clear failed. Please try again.',
              fr: 'Échec de l’effacement. Réessayez.',
              es: 'Error al borrar. Inténtalo de nuevo.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isClearingLocalCustomerBookings = false);
      }
    }
  }

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (widget.lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return en;
    }
  }

  String _fmtDateTime(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String _ledgerToken(String raw) {
    return raw.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
  }

  String _backendChipLabel(bool? value) {
    if (value == true) {
      return _t(
        nl: 'Systeem: bevestigd',
        en: 'System: confirmed',
        fr: 'Système : confirmé',
        es: 'Sistema: confirmado',
      );
    }
    if (value == false) {
      return _t(
        nl: 'Systeem: niet bevestigd',
        en: 'System: not confirmed',
        fr: 'Système : non confirmé',
        es: 'Sistema: no confirmado',
      );
    }
    return _t(
      nl: 'Systeem: onbekend',
      en: 'System: unknown',
      fr: 'Système : inconnu',
      es: 'Sistema: desconocido',
    );
  }

  String _rideTypeLabel(String raw) {
    switch (_ledgerToken(raw)) {
      case 'direct':
        return _t(
          nl: 'Directe rit',
          en: 'Direct ride',
          fr: 'Course directe',
          es: 'Viaje directo',
        );
      case 'planned':
        return _t(
          nl: 'Geplande rit',
          en: 'Planned ride',
          fr: 'Trajet planifié',
          es: 'Viaje planificado',
        );
      default:
        return _t(
          nl: 'Geplande rit',
          en: 'Planned ride',
          fr: 'Trajet planifié',
          es: 'Viaje planificado',
        );
    }
  }

  String _validationStateLabel(String raw) {
    switch (_ledgerToken(raw)) {
      case 'exportable':
        return _t(
          nl: 'klaar voor export',
          en: 'ready to export',
          fr: 'prêt à exporter',
          es: 'listo para exportar',
        );
      case 'blocked':
        return _t(
          nl: 'Geblokkeerd',
          en: 'Blocked',
          fr: 'Bloqué',
          es: 'Bloqueado',
        );
      case 'payment_update':
        return _t(
          nl: 'Betaling bijgewerkt',
          en: 'Payment updated',
          fr: 'Paiement mis à jour',
          es: 'Pago actualizado',
        );
      default:
        return raw.trim().isEmpty ? '—' : raw.trim();
    }
  }

  String _paymentStatusLabel(String raw) {
    switch (_ledgerToken(raw)) {
      case 'paid':
      case 'succeeded':
      case 'success':
      case 'completed':
      case 'settled':
      case 'confirmed':
        return _t(nl: 'betaald', en: 'paid', fr: 'payé', es: 'pagado');
      case 'unpaid':
      case 'not_paid':
        return _t(
          nl: 'onbetaald',
          en: 'unpaid',
          fr: 'non payé',
          es: 'no pagado',
        );
      case 'pending':
      case 'open':
      case 'authorized':
      case 'authorised':
      case 'processing':
        return _t(
          nl: 'in behandeling',
          en: 'pending',
          fr: 'en attente',
          es: 'pendiente',
        );
      case 'failed':
      case 'error':
      case 'declined':
        return _t(nl: 'mislukt', en: 'failed', fr: 'échoué', es: 'fallido');
      case 'unknown':
      case '':
        return _t(
          nl: 'onbekend',
          en: 'unknown',
          fr: 'inconnu',
          es: 'desconocido',
        );
      default:
        return _t(
          nl: 'onbekend',
          en: 'unknown',
          fr: 'inconnu',
          es: 'desconocido',
        );
    }
  }

  String _paymentMethodLabel(String raw) {
    switch (_ledgerToken(raw)) {
      case 'cash':
      case 'contant':
        return _t(nl: 'contant', en: 'cash', fr: 'espèces', es: 'efectivo');
      case 'bancontact':
        return 'Bancontact';
      case 'card':
      case 'pin':
      case 'card_terminal':
      case 'terminal':
        return _t(nl: 'kaart', en: 'card', fr: 'carte', es: 'tarjeta');
      case 'qr':
      case 'qr_code':
        return 'QR';
      case 'mollie':
      case 'online':
        return _t(nl: 'online', en: 'online', fr: 'en ligne', es: 'en línea');
      case 'unknown':
      case '':
        return _t(
          nl: 'onbekend',
          en: 'unknown',
          fr: 'inconnu',
          es: 'desconocido',
        );
      default:
        return _t(
          nl: 'onbekend',
          en: 'unknown',
          fr: 'inconnu',
          es: 'desconocido',
        );
    }
  }

  String _paymentSourceLabel(String raw) {
    switch (_ledgerToken(raw)) {
      case 'in_car':
      case 'in_vehicle':
      case 'manual':
      case 'driver':
      case 'chauffeur':
        return _t(
          nl: 'in voertuig',
          en: 'in vehicle',
          fr: 'dans le véhicule',
          es: 'en el vehículo',
        );
      case 'online':
      case 'mollie':
        return _t(nl: 'online', en: 'online', fr: 'en ligne', es: 'en línea');
      case 'unknown':
      case '':
        return _t(
          nl: 'onbekend',
          en: 'unknown',
          fr: 'inconnu',
          es: 'desconocido',
        );
      default:
        return _t(
          nl: 'onbekend',
          en: 'unknown',
          fr: 'inconnu',
          es: 'desconocido',
        );
    }
  }

  String _paymentProviderLabel(String raw) {
    switch (_ledgerToken(raw)) {
      case 'manual':
        return _t(nl: 'manueel', en: 'manual', fr: 'manuel', es: 'manual');
      case 'mollie':
        return 'Mollie';
      case 'unknown':
      case '':
        return _t(
          nl: 'onbekend',
          en: 'unknown',
          fr: 'inconnu',
          es: 'desconocido',
        );
      default:
        return _t(
          nl: 'onbekend',
          en: 'unknown',
          fr: 'inconnu',
          es: 'desconocido',
        );
    }
  }

  String _paymentUpdatedLabel() {
    return _t(
      nl: 'Betaling bijgewerkt',
      en: 'Payment updated',
      fr: 'Paiement mis à jour',
      es: 'Pago actualizado',
    );
  }

  String _paymentUpdatedLaterLabel() {
    return _t(
      nl: 'Betaling later bijgewerkt',
      en: 'Payment updated later',
      fr: 'Paiement mis à jour plus tard',
      es: 'Pago actualizado más tarde',
    );
  }

  String _receiptLabel() {
    return _t(
      nl: 'Bonnummer',
      en: 'Receipt no.',
      fr: 'N° de reçu',
      es: 'N.º de recibo',
    );
  }

  String _planningLabel() {
    return _t(
      nl: 'Planningnummer',
      en: 'Planning no.',
      fr: 'N° de planning',
      es: 'N.º de planificación',
    );
  }

  String _bookingLabel() {
    return _t(
      nl: 'Boekingsnummer',
      en: 'Booking no.',
      fr: 'N° de réservation',
      es: 'N.º de reserva',
    );
  }

  String _localizedInternalBookingLabel() {
    return _t(
      nl: 'Interne boeking',
      en: 'Internal booking',
      fr: 'Réservation interne',
      es: 'Reserva interna',
    );
  }

  String _draftReceiptLabel() {
    return _t(
      nl: 'Conceptbon',
      en: 'Draft receipt',
      fr: 'Reçu provisoire',
      es: 'Recibo provisional',
    );
  }

  String _internalTripLabel() {
    return _t(
      nl: 'Interne rit',
      en: 'Internal trip',
      fr: 'Course interne',
      es: 'Viaje interno',
    );
  }

  bool _looksLikeUuid(String value) {
    return RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}',
      caseSensitive: false,
    ).hasMatch(value);
  }

  bool _looksTechnicalInternalReference(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return true;
    if (_isUnknownLikeToken(text)) return true;
    final lower = text.toLowerCase();
    if (lower.startsWith('trip_')) return true;
    if (lower.startsWith('trip-trip_')) return true;
    if (lower.contains('trip-trip_')) return true;
    if (_looksLikeUuid(lower)) return true;
    final hasUnderscoreOrHyphen = text.contains('_') || text.contains('-');
    final hasLetters = RegExp(r'[a-zA-Z]').hasMatch(text);
    final hasDigits = RegExp(r'\d').hasMatch(text);
    if (text.length >= 28 && hasUnderscoreOrHyphen && hasLetters && hasDigits) {
      return true;
    }
    return false;
  }

  bool _sameReference(String? a, String? b) {
    final left = _meaningfulDisplayToken(a);
    final right = _meaningfulDisplayToken(b);
    if (left == null || right == null) return false;
    return _ledgerToken(left) == _ledgerToken(right);
  }

  bool _isLegacyTripReceiptNumber(String? value) {
    final text = _meaningfulDisplayToken(value);
    if (text == null) return false;
    final token = _ledgerToken(text);
    if (token.startsWith('planne-')) return true;
    return RegExp(r'^planne-[a-z0-9]{3,}$').hasMatch(token);
  }

  bool _isDerivedPlannedTripReference({
    required String candidate,
    String? bookingId,
    String? tripId,
  }) {
    final token = _ledgerToken(candidate);
    if (token.startsWith('planned_')) return true;
    final canonical = _meaningfulDisplayToken(bookingId);
    if (canonical != null && _sameReference(candidate, 'planned_$canonical')) {
      return true;
    }
    final trip = _meaningfulDisplayToken(tripId);
    if (trip != null &&
        _sameReference(candidate, trip) &&
        _ledgerToken(candidate).startsWith('planned_')) {
      return true;
    }
    return false;
  }

  bool _isRealReceiptReference({
    required String candidate,
    String? bookingId,
    String? tripId,
    String? planningReference,
    String? publicBookingReference,
  }) {
    final value = _meaningfulDisplayToken(candidate);
    if (value == null) return false;
    if (_sameReference(value, bookingId)) return false;
    if (_sameReference(value, tripId)) return false;
    if (_sameReference(value, planningReference)) return false;
    if (_sameReference(value, publicBookingReference)) return false;
    if (_isLegacyTripReceiptNumber(value)) return false;
    if (_isDerivedPlannedTripReference(
      candidate: value,
      bookingId: bookingId,
      tripId: tripId,
    )) {
      return false;
    }
    return true;
  }

  ({String label, String value, String? internalBooking})
  _businessReferenceForLocalCard(ComplianceLedgerEntry entry) {
    final receiptRef = entry.receiptReference.trim();
    final planningRef = entry.planningReference.trim();
    final publicBookingRef = entry.publicBookingReference.trim();
    if (_isRealReceiptReference(
      candidate: receiptRef,
      bookingId: entry.bookingId,
      tripId: entry.tripId,
      planningReference: planningRef,
      publicBookingReference: publicBookingRef,
    )) {
      final canonical = entry.bookingId.trim();
      final showInternal =
          canonical.isNotEmpty &&
          canonical != receiptRef &&
          !_looksTechnicalInternalReference(canonical);
      return (
        label: _receiptLabel(),
        value: receiptRef,
        internalBooking: showInternal ? canonical : null,
      );
    }
    if (planningRef.isNotEmpty &&
        !_looksTechnicalInternalReference(planningRef)) {
      final canonical = entry.bookingId.trim();
      final showInternal =
          canonical.isNotEmpty &&
          canonical != planningRef &&
          !_looksTechnicalInternalReference(canonical);
      return (
        label: _planningLabel(),
        value: planningRef,
        internalBooking: showInternal ? canonical : null,
      );
    }
    if (publicBookingRef.isNotEmpty &&
        !_looksTechnicalInternalReference(publicBookingRef)) {
      final canonical = entry.bookingId.trim();
      final showInternal =
          canonical.isNotEmpty &&
          canonical != publicBookingRef &&
          !_looksTechnicalInternalReference(canonical);
      return (
        label: _bookingLabel(),
        value: publicBookingRef,
        internalBooking: showInternal ? canonical : null,
      );
    }
    final bookingId = entry.bookingId.trim();
    if (bookingId.isNotEmpty && !_looksTechnicalInternalReference(bookingId)) {
      return (
        label: _localizedInternalBookingLabel(),
        value: bookingId,
        internalBooking: null,
      );
    }
    final tripId = entry.tripId.trim();
    if (tripId.isNotEmpty && !_looksTechnicalInternalReference(tripId)) {
      return (
        label: _internalTripLabel(),
        value: tripId,
        internalBooking: null,
      );
    }
    final rideType = _ledgerToken(entry.rideType);
    if (rideType == 'direct' || rideType == 'planned') {
      return (
        label: _receiptLabel(),
        value: _draftReceiptLabel(),
        internalBooking: null,
      );
    }
    return (
      label: _t(
        nl: 'Referentie',
        en: 'Reference',
        fr: 'Référence',
        es: 'Referencia',
      ),
      value: '—',
      internalBooking: null,
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _chironPanel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _chironBorder),
      ),
      child: Text(
        label,
        style: TextStyle(color: _chironChipText, fontSize: 11),
      ),
    );
  }

  String _eventTypeLabel(String raw, {bool inferCompleted = false}) {
    final token = _ledgerToken(raw);
    switch (token) {
      case 'ride_stop':
      case 'ride_completed':
      case 'completed':
        return _t(
          nl: 'Rit afgerond',
          en: 'Ride completed',
          fr: 'Trajet terminé',
          es: 'Trayecto finalizado',
        );
      case 'payment_update':
        return _t(
          nl: 'Betalingsupdate',
          en: 'Payment update',
          fr: 'Paiement mis à jour',
          es: 'Actualización de pago',
        );
      default:
        if (inferCompleted) {
          return _t(
            nl: 'Rit afgerond',
            en: 'Ride completed',
            fr: 'Trajet terminé',
            es: 'Trayecto finalizado',
          );
        }
        return _t(
          nl: 'Gebeurtenis',
          en: 'Event',
          fr: 'Événement',
          es: 'Evento',
        );
    }
  }

  String _driverLabel() {
    return _t(nl: 'Chauffeur', en: 'Driver', fr: 'Chauffeur', es: 'Conductor');
  }

  String _vehicleLabel() {
    return _t(nl: 'Voertuig', en: 'Vehicle', fr: 'Véhicule', es: 'Vehículo');
  }

  String _driverNotLinkedLabel() {
    return _t(
      nl: 'Chauffeur niet gekoppeld',
      en: 'Driver not linked',
      fr: 'Chauffeur non lié',
      es: 'Conductor no vinculado',
    );
  }

  String _vehicleNotLinkedLabel() {
    return _t(
      nl: 'Voertuig niet gekoppeld',
      en: 'Vehicle not linked',
      fr: 'Véhicule non lié',
      es: 'Vehículo no vinculado',
    );
  }

  String _amountLabel() {
    return _t(nl: 'Bedrag', en: 'Amount', fr: 'Montant', es: 'Importe');
  }

  String _statusLabel() {
    return _t(nl: 'Status', en: 'Status', fr: 'Statut', es: 'Estado');
  }

  String _auditHistoryLabel() {
    return _t(
      nl: 'Auditgeschiedenis',
      en: 'Audit history',
      fr: 'Historique d’audit',
      es: 'Historial de auditoría',
    );
  }

  String _labelValue(String label, String value) {
    if (widget.lang == AppLanguage.fr) return '$label : $value';
    return '$label: $value';
  }

  String? _ledgerKeyPart(String prefix, String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '—') return null;
    return '$prefix:${normalized.toLowerCase()}';
  }

  String _ledgerGroupKey(ComplianceLedgerEntry e, int index) {
    final key = ComplianceLedgerReader.groupKeyFor(e);
    if (key.startsWith('event:index_')) {
      return 'event:index_$index';
    }
    return key;
  }

  DateTime? _ledgerSortTime(ComplianceLedgerEntry e) {
    return e.finalizedAtUtc ?? e.createdAtUtc ?? e.paidAtUtc ?? e.endedAtUtc;
  }

  bool _isNewerLedgerEntry(
    ComplianceLedgerEntry candidate,
    ComplianceLedgerEntry existing,
  ) {
    final candidateTime = _ledgerSortTime(candidate);
    final existingTime = _ledgerSortTime(existing);
    if (candidateTime != null && existingTime != null) {
      final byTime = candidateTime.compareTo(existingTime);
      if (byTime != 0) return byTime > 0;
    } else if (candidateTime != null) {
      return true;
    } else if (existingTime != null) {
      return false;
    }
    return candidate.sourceLineIndex > existing.sourceLineIndex;
  }

  List<List<ComplianceLedgerEntry>> _groupedLedgerEntries(
    List<ComplianceLedgerEntry> entries,
  ) {
    final grouped = <String, List<ComplianceLedgerEntry>>{};
    for (final indexed in entries.asMap().entries) {
      final entry = indexed.value;
      final key = _ledgerGroupKey(entry, indexed.key);
      grouped.putIfAbsent(key, () => <ComplianceLedgerEntry>[]).add(entry);
    }
    final groups = grouped.values.toList(growable: false);
    groups.sort((a, b) {
      final newestA = _newestLedgerEntry(a);
      final newestB = _newestLedgerEntry(b);
      return _compareLedgerEntries(newestB, newestA);
    });
    return groups;
  }

  int _compareLedgerEntries(ComplianceLedgerEntry a, ComplianceLedgerEntry b) {
    final at = _ledgerSortTime(a);
    final bt = _ledgerSortTime(b);
    if (at != null && bt != null) return at.compareTo(bt);
    if (at != null) return 1;
    if (bt != null) return -1;
    return a.sourceLineIndex.compareTo(b.sourceLineIndex);
  }

  ComplianceLedgerEntry _newestLedgerEntry(
    List<ComplianceLedgerEntry> entries,
  ) {
    final sorted = [...entries]..sort(_compareLedgerEntries);
    return sorted.isEmpty ? entries.first : sorted.last;
  }

  ComplianceLedgerEntry _summaryLedgerEntry(
    List<ComplianceLedgerEntry> entries,
  ) {
    final sorted = [...entries]..sort(_compareLedgerEntries);
    for (final entry in sorted.reversed) {
      if (_isLedgerCompletionEntry(entry)) return entry;
    }
    for (final entry in sorted.reversed) {
      if (!entry.isPaymentUpdate) return entry;
    }
    return sorted.last;
  }

  bool _isLedgerCompletionEventType(String raw) {
    switch (_ledgerToken(raw)) {
      case 'ride_stop':
      case 'ride_completed':
      case 'completed':
        return true;
      default:
        return false;
    }
  }

  bool _isLedgerCancellationEntry(ComplianceLedgerEntry entry) {
    if (entry.isPaymentUpdate) return false;
    final lifecycle = _ledgerToken(entry.lifecycleStatus);
    return lifecycle == 'cancelled' || lifecycle == 'canceled';
  }

  bool _isLedgerCompletionEntry(ComplianceLedgerEntry entry) {
    if (_isLedgerCompletionEventType(entry.eventType)) return true;
    if (entry.isPaymentUpdate) return false;
    final lifecycle = _ledgerToken(entry.lifecycleStatus);
    if (lifecycle == 'completed') return true;
    if (entry.endedAtUtc != null &&
        lifecycle != 'payment_updated' &&
        lifecycle != 'planned' &&
        lifecycle != 'pending') {
      return true;
    }
    if (_ledgerToken(entry.validationState) == 'exportable' &&
        (entry.endedAtUtc != null || entry.finalizedAtUtc != null)) {
      return true;
    }
    return false;
  }

  String? _storedLifecycleTokenFromEntry(ComplianceLedgerEntry entry) {
    final candidates = <String?>[
      entry.lifecycleStatus,
      _rawPathText(entry.raw, const ['lifecycle_status']),
      _rawPathText(entry.raw, const ['ride_status']),
      _rawPathText(entry.raw, const ['status']),
      _rawPathText(entry.raw, const ['booking', 'status']),
      _rawPathText(entry.raw, const ['booking', 'lifecycle_status']),
    ];
    for (final candidate in candidates) {
      final token = _ledgerToken(candidate ?? '');
      if (ComplianceLedgerReader.isMeaningfulLifecycleToken(token)) {
        return token;
      }
    }
    return null;
  }

  String _resolveLedgerLifecycleToken(List<ComplianceLedgerEntry> entries) {
    if (entries.any(_isLedgerCompletionEntry)) return 'completed';
    if (entries.any(_isLedgerCancellationEntry)) return 'cancelled';

    for (final entry in entries.where((e) => !e.isPaymentUpdate)) {
      final lifecycle = _ledgerToken(entry.lifecycleStatus);
      if (lifecycle == 'completed') return 'completed';
      if (lifecycle == 'cancelled' || lifecycle == 'canceled')
        return 'cancelled';
      if (lifecycle == 'in_progress' ||
          lifecycle == 'active' ||
          lifecycle == 'started') {
        return 'in_progress';
      }
      if (entry.startedAtUtc != null && entry.endedAtUtc == null) {
        return 'in_progress';
      }
    }

    for (final entry in entries) {
      final stored = _storedLifecycleTokenFromEntry(entry);
      if (stored == null) continue;
      if (stored == 'completed') return 'completed';
      if (stored == 'cancelled' || stored == 'canceled') return 'cancelled';
      if (stored == 'in_progress' ||
          stored == 'active' ||
          stored == 'started') {
        return 'in_progress';
      }
      if (stored == 'planned' || stored == 'pending') return 'planned';
    }

    return 'planned';
  }

  String _localizedLedgerLifecycleTitle(String lifecycle, String rideType) {
    switch (_ledgerToken(lifecycle)) {
      case 'completed':
        return _t(
          nl: 'Rit voltooid',
          en: 'Completed ride',
          fr: 'Course terminée',
          es: 'Viaje completado',
        );
      case 'cancelled':
      case 'canceled':
        return _t(
          nl: 'Rit geannuleerd',
          en: 'Cancelled ride',
          fr: 'Course annulée',
          es: 'Viaje cancelado',
        );
      case 'in_progress':
      case 'active':
      case 'started':
        return _t(
          nl: 'Rit bezig',
          en: 'Ride in progress',
          fr: 'Course en cours',
          es: 'Viaje en curso',
        );
      case 'planned':
      case 'pending':
      default:
        return _rideTypeLabel(rideType);
    }
  }

  String _localizedLedgerLifecycleStatusLabel(String lifecycle) {
    switch (_ledgerToken(lifecycle)) {
      case 'completed':
        return _t(
          nl: 'voltooid',
          en: 'completed',
          fr: 'terminée',
          es: 'completado',
        );
      case 'cancelled':
      case 'canceled':
        return _t(
          nl: 'geannuleerd',
          en: 'cancelled',
          fr: 'annulée',
          es: 'cancelado',
        );
      case 'in_progress':
      case 'active':
      case 'started':
        return _t(
          nl: 'bezig',
          en: 'in progress',
          fr: 'en cours',
          es: 'en curso',
        );
      case 'planned':
      case 'pending':
        return _t(
          nl: 'gepland',
          en: 'planned',
          fr: 'planifiée',
          es: 'planificado',
        );
      default:
        return _t(
          nl: 'onbekend',
          en: 'unknown',
          fr: 'inconnu',
          es: 'desconocido',
        );
    }
  }

  ComplianceLedgerEntry? _latestPaymentUpdateInGroup(
    List<ComplianceLedgerEntry> entries,
  ) {
    ComplianceLedgerEntry? latest;
    for (final entry in entries.where((e) => e.isPaymentUpdate)) {
      if (latest == null || _isNewerLedgerEntry(entry, latest)) {
        latest = entry;
      }
    }
    return latest;
  }

  String? _rawPathText(Map<String, dynamic> root, List<String> path) {
    dynamic cursor = root;
    for (final part in path) {
      if (cursor is! Map) return null;
      cursor = cursor[part];
    }
    final text = (cursor ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }

  bool _isUnknownLikeToken(String value) {
    final token = _ledgerToken(value);
    return token.isEmpty ||
        token == 'unknown' ||
        token == 'onbekend' ||
        token == 'null' ||
        token == 'undefined' ||
        token == '-' ||
        token == '—';
  }

  String? _meaningfulDisplayToken(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    if (_isUnknownLikeToken(text)) return null;
    return text;
  }

  String _driverProfileNotFoundLabel() {
    return _t(
      nl: 'Chauffeurprofiel niet gevonden',
      en: 'Driver profile not found',
      fr: 'Profil chauffeur introuvable',
      es: 'Perfil del conductor no encontrado',
    );
  }

  String _vehicleProfileNotFoundLabel() {
    return _t(
      nl: 'Voertuigprofiel niet gevonden',
      en: 'Vehicle profile not found',
      fr: 'Profil véhicule introuvable',
      es: 'Perfil del vehículo no encontrado',
    );
  }

  bool _profileIdMatches(String? candidate, String targetId) {
    final a = (candidate ?? '').trim();
    final b = targetId.trim();
    if (a.isEmpty || b.isEmpty) return false;
    return _ledgerToken(a) == _ledgerToken(b);
  }

  String? _lookupDriverProfileDisplay(String? driverId) {
    final id = (driverId ?? '').trim();
    if (id.isEmpty) return null;
    for (final driver in driversNotifier.value) {
      if (!_profileIdMatches(driver.id, id)) continue;
      final fullName = _meaningfulDisplayToken(driver.fullName);
      if (fullName != null) return fullName;
    }
    return null;
  }

  String? _lookupVehicleProfileDisplay(String? vehicleId) {
    final id = (vehicleId ?? '').trim();
    if (id.isEmpty) return null;
    for (final vehicle in vehiclesNotifier.value) {
      if (!_profileIdMatches(vehicle.id, id)) continue;
      final label = _friendlyVehicleProfileLabel(vehicle);
      if (label != null) return label;
    }
    return null;
  }

  String? _friendlyVehicleProfileLabel(VehicleProfile vehicle) {
    final vehicleName = _meaningfulDisplayToken(vehicle.vehicleName);
    final brandModel = _meaningfulDisplayToken(vehicle.brandModel);
    final licensePlate = _meaningfulDisplayToken(vehicle.licensePlate);
    final tier = _meaningfulDisplayToken(_localizedTierLabel(vehicle.tierId));
    if (vehicleName != null && licensePlate != null) {
      return '$vehicleName · $licensePlate';
    }
    if (brandModel != null && licensePlate != null) {
      return '$brandModel · $licensePlate';
    }
    if (tier != null && licensePlate != null) return '$tier · $licensePlate';
    if (licensePlate != null) return licensePlate;
    if (vehicleName != null) return vehicleName;
    if (brandModel != null) return brandModel;
    if (tier != null) return tier;
    return null;
  }

  String _localizedTierLabel(String rawTier) {
    switch (_ledgerToken(rawTier)) {
      case 'comfort':
        return _t(nl: 'Comfort', en: 'Comfort', fr: 'Confort', es: 'Confort');
      case 'private':
        return _t(nl: 'Privé', en: 'Private', fr: 'Privé', es: 'Privado');
      case 'premium':
        return 'Premium';
      default:
        return rawTier.trim();
    }
  }

  String _vehicleTierLabel(String rawTier) {
    switch (_ledgerToken(rawTier)) {
      case 'comfort':
        return _localizedTierLabel('comfort');
      case 'private':
        return _localizedTierLabel('private');
      case 'premium':
        return _localizedTierLabel('premium');
      default:
        return rawTier.trim();
    }
  }

  String _dedupeVehiclePrimary(String value, String plate) {
    final v = value.trim();
    final p = plate.trim();
    if (v.isEmpty) return v;
    if (p.isEmpty) return v;
    if (_ledgerToken(v) == _ledgerToken(p)) return '';
    return v;
  }

  /// Resolves a human-readable driver label for one compliance ledger entry.
  ///
  /// Resolution order (display-quality names always beat IDs):
  ///   1. Broad alias matrix in `entry.raw` (flat + nested driver / assigned_driver /
  ///      driver_profile / chauffeur / booking.driver / booking_details / payload).
  ///   2. Driver profile cache (`driversNotifier`) keyed by `entry.driverId` or
  ///      any `driver_id` alias inside `entry.raw`.
  ///   3. Local Ride Register hydration cache (populated whenever the receipt
  ///      is opened — surfaces the same driver the receipt shows).
  ///   4. `Driver profile not found` when a `driver_id` exists but no profile
  ///      / hydration label is available.
  ///   5. `Driver not linked` otherwise.
  String _driverDisplay(ComplianceLedgerEntry entry) {
    final raw = entry.raw;
    // 1) Broad alias matrix — expanded to also cover booking / booking_details /
    // payload subtrees, assigned_driver flat keys, employee_number, and the
    // existing driver_profile / chauffeur shapes.
    final candidates = <String?>[
      _rawPathText(raw, const ['driver', 'name']),
      _rawPathText(raw, const ['driver', 'fullName']),
      _rawPathText(raw, const ['driver', 'full_name']),
      _rawPathText(raw, const ['driver', 'display_name']),
      _rawPathText(raw, const ['driver', 'displayName']),
      _rawPathText(raw, const ['driver', 'driver_name']),
      _rawPathText(raw, const ['driver', 'driverName']),
      _rawPathText(raw, const ['assigned_driver', 'name']),
      _rawPathText(raw, const ['assigned_driver', 'fullName']),
      _rawPathText(raw, const ['assigned_driver', 'full_name']),
      _rawPathText(raw, const ['assigned_driver', 'display_name']),
      _rawPathText(raw, const ['assigned_driver', 'driver_name']),
      _rawPathText(raw, const ['assignedDriver', 'name']),
      _rawPathText(raw, const ['assignedDriver', 'fullName']),
      _rawPathText(raw, const ['assignedDriver', 'full_name']),
      _rawPathText(raw, const ['assignedDriver', 'displayName']),
      _rawPathText(raw, const ['assignedDriver', 'driverName']),
      _rawPathText(raw, const ['driver_profile', 'name']),
      _rawPathText(raw, const ['driver_profile', 'fullName']),
      _rawPathText(raw, const ['driverProfile', 'name']),
      _rawPathText(raw, const ['driverProfile', 'fullName']),
      _rawPathText(raw, const ['chauffeur', 'name']),
      _rawPathText(raw, const ['chauffeur', 'fullName']),
      _rawPathText(raw, const ['driver_name']),
      _rawPathText(raw, const ['driverName']),
      _rawPathText(raw, const ['assigned_driver_name']),
      _rawPathText(raw, const ['assignedDriverName']),
      _rawPathText(raw, const ['chauffeur_name']),
      _rawPathText(raw, const ['chauffeurName']),
      _rawPathText(raw, const ['paid_by_driver_name']),
      _rawPathText(raw, const ['paidByDriverName']),
      _rawPathText(raw, const ['driver_label']),
      _rawPathText(raw, const ['driverLabel']),
      _rawPathText(raw, const ['employee_number']),
      _rawPathText(raw, const ['employeeNumber']),
      // Booking / booking_details / payload subtrees (present on hydrated /
      // backend-restored compliance rows). These mirror what the receipt
      // payload already surfaces.
      _rawPathText(raw, const ['booking', 'driver_name']),
      _rawPathText(raw, const ['booking', 'driverName']),
      _rawPathText(raw, const ['booking', 'assigned_driver_name']),
      _rawPathText(raw, const ['booking', 'assignedDriverName']),
      _rawPathText(raw, const ['booking', 'driver', 'name']),
      _rawPathText(raw, const ['booking', 'driver', 'fullName']),
      _rawPathText(raw, const ['booking', 'assigned_driver', 'name']),
      _rawPathText(raw, const ['booking', 'assignedDriver', 'name']),
      _rawPathText(raw, const ['booking_details', 'driver_name']),
      _rawPathText(raw, const ['booking_details', 'driverName']),
      _rawPathText(raw, const ['booking_details', 'assigned_driver_name']),
      _rawPathText(raw, const ['booking_details', 'assignedDriverName']),
      _rawPathText(raw, const ['booking_details', 'employee_number']),
      _rawPathText(raw, const ['booking_details', 'employeeNumber']),
      _rawPathText(raw, const ['payload', 'driver_name']),
      _rawPathText(raw, const ['payload', 'driverName']),
      _rawPathText(raw, const ['record', 'driver_name']),
      _rawPathText(raw, const ['record', 'driverName']),
      _rawPathText(raw, const ['record', 'booking', 'driver_name']),
      _rawPathText(raw, const ['record', 'booking', 'driverName']),
    ];
    for (final value in candidates) {
      final meaningful = _meaningfulDisplayToken(value);
      if (meaningful != null) return meaningful;
    }

    // 2) Driver profile cache.
    final driverId = _meaningfulDisplayToken(
      _rawPathText(raw, const ['driver', 'driver_id']) ??
          _rawPathText(raw, const ['driver', 'driverId']) ??
          _rawPathText(raw, const ['driver', 'id']) ??
          _rawPathText(raw, const ['assigned_driver', 'driver_id']) ??
          _rawPathText(raw, const ['assigned_driver', 'driverId']) ??
          _rawPathText(raw, const ['assigned_driver', 'id']) ??
          _rawPathText(raw, const ['assignedDriver', 'driver_id']) ??
          _rawPathText(raw, const ['assignedDriver', 'driverId']) ??
          _rawPathText(raw, const ['assignedDriver', 'id']) ??
          _rawPathText(raw, const ['driver_id']) ??
          _rawPathText(raw, const ['driverId']) ??
          _rawPathText(raw, const ['assigned_driver_id']) ??
          _rawPathText(raw, const ['assignedDriverId']) ??
          _rawPathText(raw, const ['booking', 'driver_id']) ??
          _rawPathText(raw, const ['booking', 'driverId']) ??
          _rawPathText(raw, const ['booking', 'assigned_driver_id']) ??
          _rawPathText(raw, const ['booking', 'assignedDriverId']) ??
          _rawPathText(raw, const ['booking_details', 'driver_id']) ??
          _rawPathText(raw, const ['booking_details', 'driverId']) ??
          entry.driverId,
    );
    final profileDisplay = _lookupDriverProfileDisplay(driverId);
    if (profileDisplay != null) return profileDisplay;

    // 3) Local Ride Register hydration cache (populated when the receipt
    // was opened earlier in this session for the same booking / trip).
    final cached = lookupLocalRideAssignment(
      bookingId: entry.bookingId,
      tripId: entry.tripId,
    );
    final cachedDriver = _meaningfulDisplayToken(cached?.driverLabel);
    if (cachedDriver != null) return cachedDriver;

    // 4) / 5) profile-not-found vs. not-linked.
    if (driverId != null) return _driverProfileNotFoundLabel();
    return _driverNotLinkedLabel();
  }

  String _driverDisplayForGroup(List<ComplianceLedgerEntry> group) {
    final sorted = [...group]..sort((a, b) => _compareLedgerEntries(b, a));
    var profileMissing = false;
    for (final entry in sorted) {
      final value = _driverDisplay(entry);
      if (value == _driverProfileNotFoundLabel()) {
        profileMissing = true;
        continue;
      }
      if (value != _driverNotLinkedLabel()) {
        _logAssignmentResolve(
          group: group,
          driverFound: true,
          driverSource: _resolveDriverSourceForEntry(entry),
          vehicleFound: null,
        );
        return value;
      }
    }
    final fallback = profileMissing
        ? _driverProfileNotFoundLabel()
        : _driverNotLinkedLabel();
    _logAssignmentResolve(
      group: group,
      driverFound: false,
      driverSource: profileMissing ? 'profile_missing' : 'none',
      vehicleFound: null,
    );
    return fallback;
  }

  /// Resolves a human-readable vehicle label for one compliance ledger entry.
  ///
  /// Resolution order (display-quality labels always beat IDs):
  ///   1. Broad alias matrix in `entry.raw` for license plate + display label
  ///      across `vehicle` / `assigned_vehicle` / `assignedVehicle` /
  ///      `vehicle_profile` / `booking.vehicle` / `booking_details` / `payload`
  ///      subtrees. Composes "label · plate" when both exist.
  ///   2. Vehicle profile cache (`vehiclesNotifier`) keyed by `entry.vehicleId`
  ///      or any `vehicle_id` alias in `entry.raw`.
  ///   3. Local Ride Register hydration cache (populated when the receipt
  ///      was opened — same vehicle the receipt shows).
  ///   4. `Vehicle profile not found` when a `vehicle_id` exists but no
  ///      profile / hydration label is available.
  ///   5. `Vehicle not linked` otherwise.
  String _vehicleDisplay(ComplianceLedgerEntry entry) {
    final raw = entry.raw;
    final plateCandidates = <String?>[
      _rawPathText(raw, const ['vehicle', 'licensePlate']),
      _rawPathText(raw, const ['vehicle', 'license_plate']),
      _rawPathText(raw, const ['vehicle', 'plate']),
      _rawPathText(raw, const ['vehicle', 'registration']),
      _rawPathText(raw, const ['vehicle', 'registrationNumber']),
      _rawPathText(raw, const ['vehicle', 'registration_number']),
      _rawPathText(raw, const ['assigned_vehicle', 'licensePlate']),
      _rawPathText(raw, const ['assigned_vehicle', 'license_plate']),
      _rawPathText(raw, const ['assigned_vehicle', 'plate']),
      _rawPathText(raw, const ['assignedVehicle', 'licensePlate']),
      _rawPathText(raw, const ['assignedVehicle', 'license_plate']),
      _rawPathText(raw, const ['assignedVehicle', 'plate']),
      _rawPathText(raw, const ['vehicle_profile', 'licensePlate']),
      _rawPathText(raw, const ['vehicleProfile', 'licensePlate']),
      _rawPathText(raw, const ['license_plate']),
      _rawPathText(raw, const ['licensePlate']),
      _rawPathText(raw, const ['plate']),
      _rawPathText(raw, const ['registration_number']),
      _rawPathText(raw, const ['registrationNumber']),
      _rawPathText(raw, const ['booking', 'license_plate']),
      _rawPathText(raw, const ['booking', 'licensePlate']),
      _rawPathText(raw, const ['booking', 'plate']),
      _rawPathText(raw, const ['booking', 'vehicle', 'licensePlate']),
      _rawPathText(raw, const ['booking', 'vehicle', 'license_plate']),
      _rawPathText(raw, const ['booking', 'vehicle', 'plate']),
      _rawPathText(raw, const ['booking', 'assigned_vehicle', 'licensePlate']),
      _rawPathText(raw, const ['booking', 'assigned_vehicle', 'license_plate']),
      _rawPathText(raw, const ['booking', 'assignedVehicle', 'licensePlate']),
      _rawPathText(raw, const ['booking_details', 'license_plate']),
      _rawPathText(raw, const ['booking_details', 'licensePlate']),
      _rawPathText(raw, const ['booking_details', 'plate']),
      _rawPathText(raw, const ['payload', 'license_plate']),
      _rawPathText(raw, const ['payload', 'licensePlate']),
      _rawPathText(raw, const ['record', 'license_plate']),
      _rawPathText(raw, const ['record', 'licensePlate']),
      _rawPathText(raw, const ['record', 'booking', 'license_plate']),
      _rawPathText(raw, const ['record', 'booking', 'licensePlate']),
    ];
    String? plate;
    for (final candidate in plateCandidates) {
      final meaningful = _meaningfulDisplayToken(candidate);
      if (meaningful != null) {
        plate = meaningful;
        break;
      }
    }

    final labelCandidates = <String?>[
      _rawPathText(raw, const ['vehicle', 'label']),
      _rawPathText(raw, const ['vehicle', 'name']),
      _rawPathText(raw, const ['vehicle', 'vehicleLabel']),
      _rawPathText(raw, const ['vehicle', 'vehicle_label']),
      _rawPathText(raw, const ['vehicle', 'display_label']),
      _rawPathText(raw, const ['vehicle', 'displayLabel']),
      _rawPathText(raw, const ['assigned_vehicle', 'label']),
      _rawPathText(raw, const ['assigned_vehicle', 'name']),
      _rawPathText(raw, const ['assigned_vehicle', 'display_label']),
      _rawPathText(raw, const ['assigned_vehicle', 'displayLabel']),
      _rawPathText(raw, const ['assignedVehicle', 'label']),
      _rawPathText(raw, const ['assignedVehicle', 'name']),
      _rawPathText(raw, const ['assignedVehicle', 'displayLabel']),
      _rawPathText(raw, const ['vehicle_profile', 'label']),
      _rawPathText(raw, const ['vehicle_profile', 'name']),
      _rawPathText(raw, const ['vehicleProfile', 'label']),
      _rawPathText(raw, const ['vehicleProfile', 'name']),
      _rawPathText(raw, const ['vehicle_label']),
      _rawPathText(raw, const ['vehicleLabel']),
      _rawPathText(raw, const ['vehicle_name']),
      _rawPathText(raw, const ['vehicleName']),
      _rawPathText(raw, const ['assigned_vehicle_label']),
      _rawPathText(raw, const ['assignedVehicleLabel']),
      _rawPathText(raw, const ['assigned_vehicle_name']),
      _rawPathText(raw, const ['assignedVehicleName']),
      _rawPathText(raw, const ['booking', 'vehicle', 'label']),
      _rawPathText(raw, const ['booking', 'vehicle', 'name']),
      _rawPathText(raw, const ['booking', 'assigned_vehicle', 'label']),
      _rawPathText(raw, const ['booking', 'assigned_vehicle', 'name']),
      _rawPathText(raw, const ['booking', 'assignedVehicle', 'label']),
      _rawPathText(raw, const ['booking', 'vehicle_label']),
      _rawPathText(raw, const ['booking', 'vehicleLabel']),
      _rawPathText(raw, const ['booking', 'vehicle_name']),
      _rawPathText(raw, const ['booking', 'vehicleName']),
      _rawPathText(raw, const ['booking', 'assigned_vehicle_name']),
      _rawPathText(raw, const ['booking', 'assignedVehicleName']),
      _rawPathText(raw, const ['booking_details', 'vehicle_label']),
      _rawPathText(raw, const ['booking_details', 'vehicleLabel']),
      _rawPathText(raw, const ['booking_details', 'vehicle_name']),
      _rawPathText(raw, const ['booking_details', 'vehicleName']),
      _rawPathText(raw, const ['payload', 'vehicle_label']),
      _rawPathText(raw, const ['payload', 'vehicleLabel']),
      _rawPathText(raw, const ['record', 'vehicle', 'label']),
      _rawPathText(raw, const ['record', 'vehicle', 'name']),
      _rawPathText(raw, const ['record', 'booking', 'vehicle', 'label']),
      _rawPathText(raw, const ['record', 'booking', 'vehicle', 'name']),
      _rawPathText(raw, const ['record', 'booking', 'vehicle_label']),
      _rawPathText(raw, const ['record', 'booking', 'vehicleLabel']),
    ];
    String? vehicleLabel;
    for (final candidate in labelCandidates) {
      final meaningful = _meaningfulDisplayToken(candidate);
      if (meaningful != null) {
        vehicleLabel = meaningful;
        break;
      }
    }

    final make = _meaningfulDisplayToken(
      _rawPathText(raw, const ['vehicle', 'make']) ??
          _rawPathText(raw, const ['vehicle', 'brand']) ??
          _rawPathText(raw, const ['assigned_vehicle', 'make']) ??
          _rawPathText(raw, const ['assigned_vehicle', 'brand']) ??
          _rawPathText(raw, const ['booking', 'vehicle', 'make']) ??
          _rawPathText(raw, const ['booking', 'vehicle', 'brand']),
    );
    final model = _meaningfulDisplayToken(
      _rawPathText(raw, const ['vehicle', 'model']) ??
          _rawPathText(raw, const ['assigned_vehicle', 'model']) ??
          _rawPathText(raw, const ['booking', 'vehicle', 'model']),
    );
    final tierRaw = _meaningfulDisplayToken(
      _rawPathText(raw, const ['vehicle', 'tier']) ??
          _rawPathText(raw, const ['assigned_vehicle', 'tier']) ??
          _rawPathText(raw, const ['booking', 'vehicle', 'tier']),
    );
    final tier = tierRaw == null ? null : _vehicleTierLabel(tierRaw);

    if (vehicleLabel != null) {
      final primary = _dedupeVehiclePrimary(vehicleLabel, plate ?? '');
      if (primary.isNotEmpty && plate != null) return '$primary · $plate';
      if (primary.isNotEmpty) return primary;
      if (plate != null) return plate;
    }
    if (make != null && model != null && plate != null)
      return '$make $model · $plate';
    if (make != null && plate != null) return '$make · $plate';
    if (tier != null && plate != null) return '$tier · $plate';
    if (make != null && model != null) return '$make $model';
    if (make != null) return make;
    if (tier != null) return tier;
    if (plate != null) return plate;

    final fallbackCandidates = <String?>[
      _rawPathText(raw, const ['vehicle_registration_number']),
      _rawPathText(raw, const ['vehicleRegistrationNumber']),
    ];
    for (final value in fallbackCandidates) {
      final meaningful = _meaningfulDisplayToken(value);
      if (meaningful != null) return meaningful;
    }
    final vehicleId = _meaningfulDisplayToken(
      _rawPathText(raw, const ['vehicle', 'vehicle_id']) ??
          _rawPathText(raw, const ['vehicle', 'vehicleId']) ??
          _rawPathText(raw, const ['vehicle', 'id']) ??
          _rawPathText(raw, const ['assigned_vehicle', 'vehicle_id']) ??
          _rawPathText(raw, const ['assigned_vehicle', 'vehicleId']) ??
          _rawPathText(raw, const ['assigned_vehicle', 'id']) ??
          _rawPathText(raw, const ['assignedVehicle', 'vehicle_id']) ??
          _rawPathText(raw, const ['assignedVehicle', 'vehicleId']) ??
          _rawPathText(raw, const ['assignedVehicle', 'id']) ??
          _rawPathText(raw, const ['vehicle_id']) ??
          _rawPathText(raw, const ['vehicleId']) ??
          _rawPathText(raw, const ['assigned_vehicle_id']) ??
          _rawPathText(raw, const ['assignedVehicleId']) ??
          _rawPathText(raw, const ['booking', 'vehicle_id']) ??
          _rawPathText(raw, const ['booking', 'vehicleId']) ??
          _rawPathText(raw, const ['booking', 'assigned_vehicle_id']) ??
          _rawPathText(raw, const ['booking', 'assignedVehicleId']) ??
          _rawPathText(raw, const ['booking_details', 'vehicle_id']) ??
          _rawPathText(raw, const ['booking_details', 'vehicleId']) ??
          entry.vehicleId,
    );
    final profileDisplay = _lookupVehicleProfileDisplay(vehicleId);
    if (profileDisplay != null) return profileDisplay;

    // Local Ride Register hydration cache (populated when the receipt was
    // opened earlier in this session for the same booking / trip).
    final cached = lookupLocalRideAssignment(
      bookingId: entry.bookingId,
      tripId: entry.tripId,
    );
    final cachedVehicle = _meaningfulDisplayToken(cached?.vehicleLabel);
    if (cachedVehicle != null) return cachedVehicle;

    // Vehicle profile assignment fallback.
    //
    // Many compliance ledger rows (especially payment_update events for
    // direct taxi rides) carry only a `driver_id` — never a `vehicle_id` —
    // because no vehicle was sent in the payment payload. The company
    // bootstrap (`VEHICLE_ASSIGNMENT_BOOTSTRAP`) already knows which
    // vehicle is assigned to each driver via `VehicleProfile.driverId`. We
    // use that mapping as the final fallback so the dashboard card can show
    // "Elanore · T-000-010" instead of "Vehicle not linked".
    //
    // Read-only: no notifier values are mutated.
    final resolvedDriverId = _resolveDriverIdFromEntry(entry);
    final cachedDriverLabel = _meaningfulDisplayToken(cached?.driverLabel);
    final assignmentDisplay = _vehicleDisplayFromDriverAssignment(
      driverId: resolvedDriverId,
      driverLabel: cachedDriverLabel,
    );
    if (assignmentDisplay != null) return assignmentDisplay;

    if (vehicleId != null) return _vehicleProfileNotFoundLabel();
    return _vehicleNotLinkedLabel();
  }

  /// Extracts the most authoritative driver ID for [entry] across the same
  /// alias matrix that `_driverDisplay` walks. Used by the vehicle-by-driver
  /// fallback so it agrees with whatever `_driverDisplay` already resolved.
  String? _resolveDriverIdFromEntry(ComplianceLedgerEntry entry) {
    final raw = entry.raw;
    return _meaningfulDisplayToken(
      _rawPathText(raw, const ['driver', 'driver_id']) ??
          _rawPathText(raw, const ['driver', 'driverId']) ??
          _rawPathText(raw, const ['driver', 'id']) ??
          _rawPathText(raw, const ['assigned_driver', 'driver_id']) ??
          _rawPathText(raw, const ['assigned_driver', 'driverId']) ??
          _rawPathText(raw, const ['assigned_driver', 'id']) ??
          _rawPathText(raw, const ['assignedDriver', 'driver_id']) ??
          _rawPathText(raw, const ['assignedDriver', 'driverId']) ??
          _rawPathText(raw, const ['assignedDriver', 'id']) ??
          _rawPathText(raw, const ['driver_id']) ??
          _rawPathText(raw, const ['driverId']) ??
          _rawPathText(raw, const ['assigned_driver_id']) ??
          _rawPathText(raw, const ['assignedDriverId']) ??
          _rawPathText(raw, const ['booking', 'driver_id']) ??
          _rawPathText(raw, const ['booking', 'driverId']) ??
          _rawPathText(raw, const ['booking', 'assigned_driver_id']) ??
          _rawPathText(raw, const ['booking', 'assignedDriverId']) ??
          _rawPathText(raw, const ['booking_details', 'driver_id']) ??
          _rawPathText(raw, const ['booking_details', 'driverId']) ??
          entry.driverId,
    );
  }

  /// Resolves a display-quality vehicle label by looking up the company
  /// vehicle profile assigned to [driverId] (or — only as a last cautious
  /// resort — to a driver whose `fullName` matches [driverLabel]). Returns
  /// `null` when no vehicle profile is assigned to the resolved driver, or
  /// when the matched vehicle has no readable name / plate.
  ///
  /// Source category for the diagnostic: `vehicle_profile_assignment`.
  String? _vehicleDisplayFromDriverAssignment({
    required String? driverId,
    required String? driverLabel,
  }) {
    var effectiveDriverId = (driverId ?? '').trim();
    if (effectiveDriverId.isEmpty) {
      final label = _meaningfulDisplayToken(driverLabel);
      if (label == null) return null;
      // Cautious label-based match: only resolve the driver_id when a single
      // unique full-name match exists in the company driver list. Avoids
      // mis-assigning when two drivers share a first name etc.
      String? candidate;
      var ambiguous = false;
      final normalizedLabel = _ledgerToken(label);
      for (final driver in driversNotifier.value) {
        final fullName = _meaningfulDisplayToken(driver.fullName);
        if (fullName == null) continue;
        if (_ledgerToken(fullName) != normalizedLabel) continue;
        if (candidate != null && candidate != driver.id.trim()) {
          ambiguous = true;
          break;
        }
        candidate = driver.id.trim();
      }
      if (ambiguous || candidate == null || candidate.isEmpty) return null;
      effectiveDriverId = candidate;
    }
    if (effectiveDriverId.isEmpty) return null;

    VehicleProfile? best;
    for (final vehicle in vehiclesNotifier.value) {
      final assigned = (vehicle.driverId ?? '').trim();
      if (assigned.isEmpty) continue;
      if (!_profileIdMatches(assigned, effectiveDriverId)) continue;
      if (best == null) {
        best = vehicle;
        continue;
      }
      // Prefer the active vehicle when multiple link to the same driver.
      if (vehicle.isActive && !best.isActive) best = vehicle;
    }
    if (best == null) return null;
    final friendly = _friendlyVehicleProfileLabel(best);
    if (friendly != null) return friendly;
    // Final fallback: vehicle id (rare — VehicleProfile.id is the only
    // remaining identifier and is still safer than "Vehicle not linked").
    final idText = _meaningfulDisplayToken(best.id);
    return idText;
  }

  String _vehicleDisplayForGroup(List<ComplianceLedgerEntry> group) {
    final sorted = [...group]..sort((a, b) => _compareLedgerEntries(b, a));
    var profileMissing = false;
    for (final entry in sorted) {
      final value = _vehicleDisplay(entry);
      if (value == _vehicleProfileNotFoundLabel()) {
        profileMissing = true;
        continue;
      }
      if (value != _vehicleNotLinkedLabel()) {
        _logAssignmentResolve(
          group: group,
          driverFound: null,
          vehicleFound: true,
          vehicleSource: _resolveVehicleSourceForEntry(entry),
        );
        return value;
      }
    }
    final fallback = profileMissing
        ? _vehicleProfileNotFoundLabel()
        : _vehicleNotLinkedLabel();
    _logAssignmentResolve(
      group: group,
      driverFound: null,
      vehicleFound: false,
      vehicleSource: profileMissing ? 'profile_missing' : 'none',
    );
    return fallback;
  }

  // ---------------------------------------------------------------------------
  // Local Ride Register assignment resolve diagnostic.
  //
  // Logged whenever the dashboard resolves driver/vehicle labels for a card.
  // Only emits safe identifiers (booking masked, source category). No PII.
  // ---------------------------------------------------------------------------
  String _resolveDriverSourceForEntry(ComplianceLedgerEntry entry) {
    final raw = entry.raw;
    if (_meaningfulDisplayToken(_rawPathText(raw, const ['driver', 'name'])) !=
            null ||
        _meaningfulDisplayToken(
              _rawPathText(raw, const ['driver', 'full_name']),
            ) !=
            null ||
        _meaningfulDisplayToken(_rawPathText(raw, const ['driver_name'])) !=
            null) {
      return 'raw_alias';
    }
    if (_meaningfulDisplayToken(
          _rawPathText(raw, const ['assigned_driver', 'name']),
        ) !=
        null) {
      return 'assigned_driver_alias';
    }
    if (_meaningfulDisplayToken(
          _rawPathText(raw, const ['booking', 'driver_name']),
        ) !=
        null) {
      return 'booking_alias';
    }
    if (_meaningfulDisplayToken(entry.driverId) != null &&
        _lookupDriverProfileDisplay(entry.driverId) != null) {
      return 'driver_profile';
    }
    final cached = lookupLocalRideAssignment(
      bookingId: entry.bookingId,
      tripId: entry.tripId,
    );
    if (cached?.driverLabel != null) return 'hydration_cache';
    return 'unknown';
  }

  String _resolveVehicleSourceForEntry(ComplianceLedgerEntry entry) {
    final raw = entry.raw;
    if (_meaningfulDisplayToken(
              _rawPathText(raw, const ['vehicle', 'license_plate']),
            ) !=
            null ||
        _meaningfulDisplayToken(
              _rawPathText(raw, const ['vehicle', 'licensePlate']),
            ) !=
            null ||
        _meaningfulDisplayToken(_rawPathText(raw, const ['license_plate'])) !=
            null) {
      return 'raw_plate';
    }
    if (_meaningfulDisplayToken(
              _rawPathText(raw, const ['vehicle', 'label']),
            ) !=
            null ||
        _meaningfulDisplayToken(_rawPathText(raw, const ['vehicle_label'])) !=
            null) {
      return 'raw_label';
    }
    if (_meaningfulDisplayToken(
          _rawPathText(raw, const ['assigned_vehicle', 'label']),
        ) !=
        null) {
      return 'assigned_vehicle_alias';
    }
    if (_meaningfulDisplayToken(
          _rawPathText(raw, const ['booking', 'vehicle', 'label']),
        ) !=
        null) {
      return 'booking_alias';
    }
    if (_meaningfulDisplayToken(entry.vehicleId) != null &&
        _lookupVehicleProfileDisplay(entry.vehicleId) != null) {
      return 'vehicle_profile';
    }
    final cached = lookupLocalRideAssignment(
      bookingId: entry.bookingId,
      tripId: entry.tripId,
    );
    if (cached?.vehicleLabel != null) return 'hydration_cache';
    // Same vehicle-by-driver fallback used inside `_vehicleDisplay`. Reported
    // separately so [ASSIGNMENT_RESOLVE] logs can show when the dashboard
    // surfaced a vehicle purely via `VehicleProfile.driverId` matching.
    if (_vehicleDisplayFromDriverAssignment(
          driverId: _resolveDriverIdFromEntry(entry),
          driverLabel: cached?.driverLabel,
        ) !=
        null) {
      return 'vehicle_profile_assignment';
    }
    return 'unknown';
  }

  /// Per-card diagnostic emitted at the actual `_groupCard` render site so
  /// the log always reflects the labels the user sees. Distinct from
  /// `[ASSIGNMENT_RESOLVE]` (which fires inside the For-Group helpers and
  /// can be called multiple times). Safe payload only — masked booking /
  /// trip IDs plus category sources; no names, plates, phone, email, or
  /// addresses.
  void _logCardAssignmentDisplay({
    required List<ComplianceLedgerEntry> group,
    required bool driverFound,
    required bool vehicleFound,
    required String driverSource,
    required String vehicleSource,
  }) {
    if (group.isEmpty) return;
    final entry = group.first;
    final booking = _maskAssignmentLogValue(entry.bookingId);
    final trip = _maskAssignmentLogValue(entry.tripId);
    debugPrint(
      '[LOCAL_RIDE_REGISTER][CARD_ASSIGNMENT_DISPLAY]'
      ' booking=$booking trip=$trip'
      ' driver_found=$driverFound driver_source=$driverSource'
      ' vehicle_found=$vehicleFound vehicle_source=$vehicleSource',
    );
  }

  void _logAssignmentResolve({
    required List<ComplianceLedgerEntry> group,
    required bool? driverFound,
    required bool? vehicleFound,
    String? driverSource,
    String? vehicleSource,
  }) {
    if (group.isEmpty) return;
    final entry = group.first;
    final booking = entry.bookingId.trim();
    final masked = _maskAssignmentLogValue(booking);
    final fields = <String>[
      'booking=$masked',
      if (driverFound != null) 'driver_found=$driverFound',
      if (vehicleFound != null) 'vehicle_found=$vehicleFound',
      if (driverSource != null) 'driver_source=$driverSource',
      if (vehicleSource != null) 'vehicle_source=$vehicleSource',
    ];
    debugPrint('[LOCAL_RIDE_REGISTER][ASSIGNMENT_RESOLVE] ${fields.join(' ')}');
  }

  String _maskAssignmentLogValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '-';
    if (trimmed.length <= 4) return trimmed;
    return '${trimmed.substring(0, 2)}…${trimmed.substring(trimmed.length - 2)}';
  }

  bool get _hasActiveLedgerFilter =>
      _searchQuery.trim().isNotEmpty ||
      _categoryFilter != _LocalRideRegisterCategoryFilter.alles;

  void _resetLedgerSearchAndCategory() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _categoryFilter = _LocalRideRegisterCategoryFilter.alles;
    });
  }

  bool _isLedgerPaidPaymentToken(String raw) {
    switch (_ledgerToken(raw)) {
      case 'paid':
      case 'succeeded':
      case 'success':
      case 'completed':
      case 'settled':
      case 'confirmed':
        return true;
      default:
        return false;
    }
  }

  void _appendLedgerCustomerNameSearchTokens(
    List<String> tokens,
    Map<String, dynamic> raw,
  ) {
    String s(String? v) => (v ?? '').trim().toLowerCase();
    void add(String? v) {
      final token = s(v);
      if (token.isNotEmpty) tokens.add(token);
    }

    for (final path in const <List<String>>[
      ['customer_name'],
      ['customerName'],
      ['custName'],
      ['passenger_name'],
      ['passengerName'],
      ['client_name'],
      ['clientName'],
      ['customer', 'name'],
      ['customer', 'customer_name'],
      ['customer', 'customerName'],
      ['passenger', 'name'],
      ['client', 'name'],
      ['booking', 'customer_name'],
      ['booking', 'customerName'],
      ['booking', 'custName'],
      ['booking', 'customer', 'name'],
      ['booking_details', 'customer_name'],
      ['booking_details', 'customerName'],
      ['booking_details', 'custName'],
      ['booking_details', 'name'],
      ['booking_details', 'customer', 'name'],
      ['payload', 'customer_name'],
      ['payload', 'customerName'],
      ['payload', 'custName'],
    ]) {
      add(_rawPathText(raw, path));
    }
  }

  String _buildLedgerEntrySearchHaystack(ComplianceLedgerEntry entry) {
    String s(dynamic v) => (v ?? '').toString().trim().toLowerCase();
    final tokens = <String>[
      s(entry.tripId),
      s(entry.bookingId),
      s(entry.rideId),
      s(entry.sessionId),
      s(entry.publicBookingReference),
      s(entry.planningReference),
      s(entry.receiptReference),
      s(entry.invoiceReference),
      s(entry.pickupLabel),
      s(entry.dropoffLabel),
      s(entry.paymentStatus),
      s(entry.paymentMethod),
      s(entry.paymentSource),
      s(entry.paymentProvider),
      s(entry.paymentId),
      s(entry.eventType),
      s(entry.rideType),
      s(entry.lifecycleStatus),
      s(entry.driverId),
      s(entry.vehicleId),
      s(entry.currency),
      s(_paymentStatusLabel(entry.paymentStatus)),
      s(_paymentMethodLabel(entry.paymentMethod)),
      s(_paymentSourceLabel(entry.paymentSource)),
      s(_paymentProviderLabel(entry.paymentProvider)),
    ];
    if (entry.fareTotalEur != null) {
      tokens
        ..add(entry.fareTotalEur!.toStringAsFixed(2))
        ..add(s(entry.fareTotalEur));
    }
    final method = s(entry.paymentMethod);
    switch (method) {
      case 'cash':
      case 'contant':
        tokens
          ..add('contant')
          ..add('cash');
        break;
      case 'qr':
      case 'qr_code':
        tokens
          ..add('qr')
          ..add('qr_code');
        break;
      case 'card':
      case 'pin':
      case 'bancontact':
        tokens
          ..add('kaart')
          ..add('bancontact');
        break;
    }
    final driver = _driverDisplay(entry);
    if (driver != _driverNotLinkedLabel() &&
        driver != _driverProfileNotFoundLabel()) {
      tokens.add(s(driver));
    }
    final vehicle = _vehicleDisplay(entry);
    if (vehicle != _vehicleNotLinkedLabel() &&
        vehicle != _vehicleProfileNotFoundLabel()) {
      tokens.add(s(vehicle));
    }
    _appendLedgerCustomerNameSearchTokens(tokens, entry.raw);
    return tokens.where((t) => t.isNotEmpty).join(' ');
  }

  String _buildLedgerGroupSearchHaystack(List<ComplianceLedgerEntry> group) {
    return group.map(_buildLedgerEntrySearchHaystack).join(' ');
  }

  bool _ledgerGroupMatchesSearch(
    List<ComplianceLedgerEntry> group,
    String query,
  ) {
    if (query.isEmpty) return true;
    final haystack = _buildLedgerGroupSearchHaystack(group);
    final tokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return true;
    for (final token in tokens) {
      if (!haystack.contains(token)) return false;
    }
    return true;
  }

  bool _ledgerGroupMatchesCategory(List<ComplianceLedgerEntry> group) {
    if (_categoryFilter == _LocalRideRegisterCategoryFilter.alles) {
      return true;
    }
    final summary = _summaryLedgerEntry(group);
    final latestPaymentUpdate = _latestPaymentUpdateInGroup(group);
    final effectivePayment = latestPaymentUpdate ?? summary;
    final lifecycle = _ledgerToken(_resolveLedgerLifecycleToken(group));
    final rideType = _ledgerToken(summary.rideType);
    final paymentStatus = _ledgerToken(effectivePayment.paymentStatus);

    switch (_categoryFilter) {
      case _LocalRideRegisterCategoryFilter.alles:
        return true;
      case _LocalRideRegisterCategoryFilter.straatritten:
        // CHIRON-RELEASE-PRESENTATION-REPAIR-1: street rides are ride_type
        // direct only — do not pull planned ride_stop into this filter.
        return rideType == 'direct';
      case _LocalRideRegisterCategoryFilter.geplandeRitten:
        if (rideType == 'planned' || rideType == 'booking') return true;
        return group.any((entry) {
          final token = _ledgerToken(entry.rideType);
          return token == 'planned' || token == 'booking';
        });
      case _LocalRideRegisterCategoryFilter.betaald:
        return _isLedgerPaidPaymentToken(paymentStatus);
      case _LocalRideRegisterCategoryFilter.nogTeBetalen:
        if (lifecycle == 'cancelled' || lifecycle == 'canceled') return false;
        return !_isLedgerPaidPaymentToken(paymentStatus);
      case _LocalRideRegisterCategoryFilter.geannuleerd:
        return lifecycle == 'cancelled' || lifecycle == 'canceled';
    }
  }

  List<List<ComplianceLedgerEntry>> _applyLedgerGroupFilters(
    List<List<ComplianceLedgerEntry>> groups,
  ) {
    final query = _searchQuery.trim();
    if (query.isEmpty &&
        _categoryFilter == _LocalRideRegisterCategoryFilter.alles) {
      return groups;
    }
    return groups
        .where(
          (group) =>
              _ledgerGroupMatchesCategory(group) &&
              _ledgerGroupMatchesSearch(group, query),
        )
        .toList(growable: false);
  }

  String _ledgerCategoryFilterLabel(_LocalRideRegisterCategoryFilter cat) {
    switch (cat) {
      case _LocalRideRegisterCategoryFilter.alles:
        return _t(nl: 'Alles', en: 'All', fr: 'Tous', es: 'Todos');
      case _LocalRideRegisterCategoryFilter.straatritten:
        return _t(
          nl: 'Straatritten',
          en: 'Street rides',
          fr: 'Courses directes',
          es: 'Viajes directos',
        );
      case _LocalRideRegisterCategoryFilter.geplandeRitten:
        return _t(
          nl: 'Geplande ritten',
          en: 'Planned rides',
          fr: 'Trajets planifiés',
          es: 'Viajes planificados',
        );
      case _LocalRideRegisterCategoryFilter.betaald:
        return _t(nl: 'Betaald', en: 'Paid', fr: 'Payé', es: 'Pagado');
      case _LocalRideRegisterCategoryFilter.nogTeBetalen:
        return _t(
          nl: 'Nog te betalen',
          en: 'Unpaid',
          fr: 'À payer',
          es: 'Por pagar',
        );
      case _LocalRideRegisterCategoryFilter.geannuleerd:
        return _t(
          nl: 'Geannuleerd',
          en: 'Cancelled',
          fr: 'Annulé',
          es: 'Cancelado',
        );
    }
  }

  String _routeDisplay(ComplianceLedgerEntry entry) {
    final pickup = entry.pickupLabel.trim();
    final dropoff = entry.dropoffLabel.trim();
    if (pickup.isNotEmpty && dropoff.isNotEmpty) return '$pickup → $dropoff';
    if (pickup.isNotEmpty) return pickup;
    if (dropoff.isNotEmpty) return dropoff;
    return '—';
  }

  String? _fareDisplay(ComplianceLedgerEntry entry) {
    if (entry.fareTotalEur == null) return null;
    final currency = entry.currency.trim().isEmpty
        ? 'EUR'
        : entry.currency.trim();
    return '€ ${entry.fareTotalEur!.toStringAsFixed(2)} $currency';
  }

  Widget _auditEventRow(
    ComplianceLedgerEntry entry, {
    required ComplianceLedgerEntry? latestPaymentUpdate,
    required ComplianceLedgerEntry summaryEntry,
    required String groupLifecycle,
  }) {
    final eventToken = _ledgerToken(entry.eventType);
    final eventTime = _fmtDateTime(_ledgerSortTime(entry));
    final hasLaterPaymentUpdate =
        !entry.isPaymentUpdate &&
        latestPaymentUpdate != null &&
        _isNewerLedgerEntry(latestPaymentUpdate, entry);
    final isUnknownEventType = eventToken.isEmpty || eventToken == 'unknown';
    final inferCompleted =
        isUnknownEventType && _isLedgerCompletionEntry(entry);
    final auditLifecycle = entry.isPaymentUpdate
        ? ''
        : (_isLedgerCompletionEntry(entry)
              ? 'completed'
              : (_isLedgerCancellationEntry(entry)
                    ? 'cancelled'
                    : (_storedLifecycleTokenFromEntry(entry) ??
                          groupLifecycle)));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _chironPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _chironBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_eventTypeLabel(entry.eventType, inferCompleted: inferCompleted)} • ${_rideTypeLabel(entry.rideType)}',
            style: TextStyle(
              color: _chironTextPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            eventTime,
            style: TextStyle(color: _chironTextMuted, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (entry.isPaymentUpdate)
                _chip(_paymentUpdatedLabel())
              else
                _chip(
                  _labelValue(
                    _statusLabel(),
                    _localizedLedgerLifecycleStatusLabel(auditLifecycle),
                  ),
                ),
              _chip(_backendChipLabel(entry.backendConfirmed)),
              if (hasLaterPaymentUpdate) _chip(_paymentUpdatedLaterLabel()),
              if (!hasLaterPaymentUpdate) ...[
                if (entry.paymentStatus.trim().isNotEmpty)
                  _chip(
                    _labelValue(
                      _t(
                        nl: 'Betaling',
                        en: 'Payment',
                        fr: 'Paiement',
                        es: 'Pago',
                      ),
                      _paymentStatusLabel(entry.paymentStatus),
                    ),
                  ),
                if (entry.paymentMethod.trim().isNotEmpty &&
                    _ledgerToken(entry.paymentMethod) != 'unknown')
                  _chip(
                    _labelValue(
                      _t(
                        nl: 'Methode',
                        en: 'Method',
                        fr: 'Méthode',
                        es: 'Método',
                      ),
                      _paymentMethodLabel(entry.paymentMethod),
                    ),
                  ),
                if (entry.paymentSource.trim().isNotEmpty &&
                    _ledgerToken(entry.paymentSource) != 'unknown')
                  _chip(
                    _labelValue(
                      _t(nl: 'Bron', en: 'Source', fr: 'Source', es: 'Origen'),
                      _paymentSourceLabel(entry.paymentSource),
                    ),
                  ),
                if (entry.paymentProvider.trim().isNotEmpty &&
                    _ledgerToken(entry.paymentProvider) != 'unknown')
                  _chip(
                    _labelValue(
                      _t(
                        nl: 'Provider',
                        en: 'Provider',
                        fr: 'Fournisseur',
                        es: 'Proveedor',
                      ),
                      _paymentProviderLabel(entry.paymentProvider),
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _groupCard(List<ComplianceLedgerEntry> group) {
    final newest = _newestLedgerEntry(group);
    final summary = _summaryLedgerEntry(group);
    final latestPaymentUpdate = _latestPaymentUpdateInGroup(group);
    final effectivePayment = latestPaymentUpdate ?? summary;
    final lifecycle = _resolveLedgerLifecycleToken(group);
    final businessReference = _businessReferenceForLocalCard(summary);
    final title =
        '${_localizedLedgerLifecycleTitle(lifecycle, summary.rideType)} • ${_labelValue(businessReference.label, businessReference.value)}';
    final route = _routeDisplay(summary);
    final rideTime = _fmtDateTime(_ledgerSortTime(summary));
    final latestTime = _fmtDateTime(_ledgerSortTime(newest));
    final paymentUpdatedTime = latestPaymentUpdate == null
        ? null
        : _fmtDateTime(
            latestPaymentUpdate.paidAtUtc ??
                _ledgerSortTime(latestPaymentUpdate),
          );
    final fare = _fareDisplay(effectivePayment) ?? _fareDisplay(summary);
    final sortedAudit = [...group]..sort(_compareLedgerEntries);

    // Resolve driver / vehicle display ONCE per card so the visible labels,
    // the [CARD_ASSIGNMENT_DISPLAY] diagnostic, and the prewarm decision
    // all agree on the same outcome. The actual `_labelValue(...)` widgets
    // below use these strings directly — no second resolution pass.
    final driverDisplay = _driverDisplayForGroup(group);
    final vehicleDisplay = _vehicleDisplayForGroup(group);
    final driverResolved =
        driverDisplay != _driverNotLinkedLabel() &&
        driverDisplay != _driverProfileNotFoundLabel();
    final vehicleResolved =
        vehicleDisplay != _vehicleNotLinkedLabel() &&
        vehicleDisplay != _vehicleProfileNotFoundLabel();
    _logCardAssignmentDisplay(
      group: group,
      driverFound: driverResolved,
      vehicleFound: vehicleResolved,
      driverSource: driverResolved
          ? _resolveDriverSourceForEntry(group.first)
          : (driverDisplay == _driverProfileNotFoundLabel()
                ? 'profile_missing'
                : 'none'),
      vehicleSource: vehicleResolved
          ? _resolveVehicleSourceForEntry(group.first)
          : (vehicleDisplay == _vehicleProfileNotFoundLabel()
                ? 'profile_missing'
                : 'none'),
    );
    // When either side is unresolved AND we have a booking_id or trip_id
    // to query, schedule a non-blocking hydration. The cache notifier
    // wakes this widget when the prewarm completes, so the card refreshes
    // automatically without changing layout.
    if (!driverResolved || !vehicleResolved) {
      for (final entry in group) {
        if (entry.bookingId.trim().isEmpty && entry.tripId.trim().isEmpty) {
          continue;
        }
        requestLocalRideAssignmentPrewarm(entry);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _chironCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _chironBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: _chironTextPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          if ((businessReference.internalBooking ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              _labelValue(
                _localizedInternalBookingLabel(),
                businessReference.internalBooking!,
              ),
              style: TextStyle(color: _chironTextFaint, fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${_t(nl: 'Laatste melding', en: 'Latest message', fr: 'Dernier message', es: 'Último mensaje')}: $latestTime',
            style: TextStyle(color: _chironTextMuted, fontSize: 11),
          ),
          Text(
            '${_t(nl: 'Ritmoment', en: 'Ride time', fr: 'Heure du trajet', es: 'Hora del viaje')}: $rideTime',
            style: TextStyle(color: _chironTextMuted, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            route,
            style: TextStyle(color: _chironTextSecondary, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            _labelValue(_driverLabel(), driverDisplay),
            style: TextStyle(color: _chironTextSecondary, fontSize: 12),
          ),
          Text(
            _labelValue(_vehicleLabel(), vehicleDisplay),
            style: TextStyle(color: _chironTextSecondary, fontSize: 12),
          ),
          if (fare != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _labelValue(_amountLabel(), fare),
                style: TextStyle(
                  color: _chironGold,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                _labelValue(
                  _t(nl: 'Betaling', en: 'Payment', fr: 'Paiement', es: 'Pago'),
                  _paymentStatusLabel(effectivePayment.paymentStatus),
                ),
              ),
              if (effectivePayment.paymentMethod.trim().isNotEmpty &&
                  _ledgerToken(effectivePayment.paymentMethod) != 'unknown')
                _chip(
                  _labelValue(
                    _t(
                      nl: 'Methode',
                      en: 'Method',
                      fr: 'Méthode',
                      es: 'Método',
                    ),
                    _paymentMethodLabel(effectivePayment.paymentMethod),
                  ),
                ),
              if (effectivePayment.paymentSource.trim().isNotEmpty &&
                  _ledgerToken(effectivePayment.paymentSource) != 'unknown')
                _chip(
                  _labelValue(
                    _t(nl: 'Bron', en: 'Source', fr: 'Source', es: 'Origen'),
                    _paymentSourceLabel(effectivePayment.paymentSource),
                  ),
                ),
              if (effectivePayment.paymentProvider.trim().isNotEmpty &&
                  _ledgerToken(effectivePayment.paymentProvider) != 'unknown')
                _chip(
                  _labelValue(
                    _t(
                      nl: 'Provider',
                      en: 'Provider',
                      fr: 'Fournisseur',
                      es: 'Proveedor',
                    ),
                    _paymentProviderLabel(effectivePayment.paymentProvider),
                  ),
                ),
              _chip(_backendChipLabel(summary.backendConfirmed)),
              _chip(
                _labelValue(
                  _statusLabel(),
                  _localizedLedgerLifecycleStatusLabel(lifecycle),
                ),
              ),
              if (latestPaymentUpdate != null) _chip(_paymentUpdatedLabel()),
            ],
          ),
          if (paymentUpdatedTime != null) ...[
            const SizedBox(height: 6),
            Text(
              '${_paymentUpdatedLabel()}: $paymentUpdatedTime',
              style: TextStyle(color: _chironTextMuted, fontSize: 11),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => runComplianceRegisterReceiptAction(
                  context: context,
                  entry: summary,
                  action: ComplianceRegisterReceiptAction.viewDetails,
                ),
                icon: Icon(
                  Icons.visibility_outlined,
                  size: 16,
                  color: _chironGold,
                ),
                label: Text(
                  _t(
                    nl: 'Details',
                    en: 'View details',
                    fr: 'Détails',
                    es: 'Detalles',
                  ),
                  style: TextStyle(color: _chironGold, fontSize: 12),
                ),
              ),
              TextButton.icon(
                onPressed: () => runComplianceRegisterReceiptAction(
                  context: context,
                  entry: summary,
                  action: ComplianceRegisterReceiptAction.downloadReceipt,
                ),
                icon: Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 16,
                  color: _chironGold,
                ),
                label: Text(
                  _t(nl: 'Ritbon', en: 'Receipt', fr: 'Reçu', es: 'Recibo'),
                  style: TextStyle(color: _chironGold, fontSize: 12),
                ),
              ),
              if (summary.bookingId.trim().isNotEmpty)
                TextButton.icon(
                  onPressed: () => runComplianceRegisterReceiptAction(
                    context: context,
                    entry: summary,
                    action: ComplianceRegisterReceiptAction.downloadInvoice,
                  ),
                  icon: Icon(
                    Icons.receipt_long_outlined,
                    size: 16,
                    color: _chironGold,
                  ),
                  label: Text(
                    _t(
                      nl: 'Factuur',
                      en: 'Invoice',
                      fr: 'Facture',
                      es: 'Factura',
                    ),
                    style: TextStyle(color: _chironGold, fontSize: 12),
                  ),
                ),
              TextButton.icon(
                onPressed: () => runComplianceRegisterReceiptAction(
                  context: context,
                  entry: summary,
                  action: ComplianceRegisterReceiptAction.shareReceipt,
                ),
                icon: Icon(Icons.share_outlined, size: 16, color: _chironGold),
                label: Text(
                  _t(nl: 'Delen', en: 'Share', fr: 'Partager', es: 'Compartir'),
                  style: TextStyle(color: _chironGold, fontSize: 12),
                ),
              ),
              TextButton.icon(
                onPressed: () => _copyReference(summary),
                icon: Icon(Icons.copy_outlined, size: 16, color: _chironGold),
                label: Text(
                  _t(
                    nl: 'Referentie',
                    en: 'Reference',
                    fr: 'Référence',
                    es: 'Referencia',
                  ),
                  style: TextStyle(color: _chironGold, fontSize: 12),
                ),
              ),
              TextButton.icon(
                onPressed: () => _hideGroupFromRegister(group),
                icon: Icon(
                  Icons.visibility_off_outlined,
                  size: 16,
                  color: _chironGold,
                ),
                label: Text(
                  _t(
                    nl: 'Verbergen uit lokaal register',
                    en: 'Hide from local register',
                    fr: 'Masquer du registre local',
                    es: 'Ocultar del registro local',
                  ),
                  style: TextStyle(color: _chironGold, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            collapsedIconColor: _chironTextSecondary,
            iconColor: _chironTextSecondary,
            title: Text(
              _auditHistoryLabel(),
              style: TextStyle(
                color: _chironGold,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            children: sortedAudit
                .map(
                  (entry) => _auditEventRow(
                    entry,
                    latestPaymentUpdate: latestPaymentUpdate,
                    summaryEntry: summary,
                    groupLifecycle: lifecycle,
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _chironCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _chironBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _t(
                      nl: 'Lokaal rittenregister',
                      en: 'Local ride register',
                      fr: 'Registre local des trajets',
                      es: 'Registro local de viajes',
                    ),
                    style: TextStyle(
                      color: _chironGold,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('chiron_local_register_refresh'),
                  tooltip: _t(
                    nl: 'Vernieuwen',
                    en: 'Refresh',
                    fr: 'Rafraîchir',
                    es: 'Actualizar',
                  ),
                  onPressed: _refreshBusy ? null : _refresh,
                  icon: _refreshBusy
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _chironGold,
                          ),
                        )
                      : Icon(
                          Icons.refresh,
                          color: _chironGold.withOpacity(0.95),
                        ),
                ),
                if (!kReleaseMode) ...[
                  IconButton(
                    tooltip: _t(
                      nl: 'Lokale testdata wissen',
                      en: 'Clear local test data',
                      fr: 'Effacer les données de test locales',
                      es: 'Borrar datos de prueba locales',
                    ),
                    onPressed: _isClearingLocalTestData
                        ? null
                        : _clearLocalTestData,
                    icon: _isClearingLocalTestData
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _chironGold,
                            ),
                          )
                        : Icon(
                            Icons.delete_sweep,
                            color: _chironGold.withOpacity(0.95),
                          ),
                  ),
                  IconButton(
                    tooltip: _t(
                      nl: 'Lokale klantboekingen wissen',
                      en: 'Clear local customer bookings',
                      fr: 'Effacer les réservations client locales',
                      es: 'Borrar reservas locales del cliente',
                    ),
                    onPressed: _isClearingLocalCustomerBookings
                        ? null
                        : _clearLocalCustomerBookings,
                    icon: _isClearingLocalCustomerBookings
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _chironGold,
                            ),
                          )
                        : Icon(
                            Icons.person_remove,
                            color: _chironGold.withOpacity(0.95),
                          ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _t(
                nl: 'Lokale cache met backend/compliance als bron. Verbergen wist geen auditdata.',
                en: 'Local cache with backend/compliance as source of truth. Hiding does not delete audit data.',
                fr: 'Cache local avec backend/conformité comme source. Masquer ne supprime pas les données d’audit.',
                es: 'Caché local con backend/cumplimiento como fuente. Ocultar no elimina datos de auditoría.',
              ),
              style: TextStyle(color: _chironTextSecondary, fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              style: TextStyle(color: _chironTextPrimary, fontSize: 13),
              cursorColor: _chironGold,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: _chironPanel,
                hintText: _t(
                  nl: 'Zoek op rit-id, boekingsnummer, klant, chauffeur, kenteken, route...',
                  en: 'Search by trip id, booking reference, customer, driver, plate, route...',
                  fr: 'Rechercher par id trajet, référence, client, chauffeur, plaque, route...',
                  es: 'Buscar por id viaje, referencia, cliente, conductor, matrícula, ruta...',
                ),
                hintStyle: TextStyle(color: _chironTextMuted, fontSize: 12),
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: _chironTextSecondary,
                ),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: _t(
                          nl: 'Zoekopdracht wissen',
                          en: 'Clear search',
                          fr: 'Effacer la recherche',
                          es: 'Borrar búsqueda',
                        ),
                        icon: Icon(
                          Icons.close,
                          size: 18,
                          color: _chironTextSecondary,
                        ),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _chironBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _chironBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _chironGold.withOpacity(0.7)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _LocalRideRegisterCategoryFilter.values
                    .map((cat) {
                      final selected = _categoryFilter == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            _ledgerCategoryFilterLabel(cat),
                            style: TextStyle(
                              fontSize: 12,
                              color: selected
                                  ? _chironGold
                                  : _chironTextSecondary,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          selected: selected,
                          showCheckmark: false,
                          backgroundColor: _chironPanel,
                          selectedColor: _chironGold.withOpacity(0.16),
                          side: BorderSide(
                            color: selected
                                ? _chironGold.withOpacity(0.6)
                                : _chironBorder,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: selected
                                  ? _chironGold.withOpacity(0.6)
                                  : _chironBorder,
                            ),
                          ),
                          onSelected: (_) {
                            setState(() {
                              _categoryFilter = cat;
                            });
                          },
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                if (!_loadCoordinator.prerequisitesReady) {
                  if (_loadError != null) {
                    return Column(
                      key: const ValueKey('chiron_local_register_error'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t(
                            nl: 'Bedrijfscontext ontbreekt. Probeer te verversen.',
                            en: 'Company context is missing. Try refreshing.',
                            fr: 'Le contexte entreprise est manquant. Essayez d’actualiser.',
                            es: 'Falta el contexto de empresa. Intente actualizar.',
                          ),
                          style: TextStyle(
                            color: _chironTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: _refresh,
                          child: Text(
                            _t(
                              nl: 'Opnieuw laden',
                              en: 'Reload',
                              fr: 'Recharger',
                              es: 'Recargar',
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return Text(
                    _t(
                      nl: 'Bedrijfscontext wordt geladen…',
                      en: 'Loading company context…',
                      fr: 'Chargement du contexte entreprise…',
                      es: 'Cargando contexto de empresa…',
                    ),
                    style: TextStyle(
                      color: _chironTextSecondary,
                      fontSize: 12,
                    ),
                  );
                }

                if (_isLoading && _result == null) {
                  return Row(
                    key: const ValueKey('chiron_local_register_loading'),
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _chironGold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _t(
                          nl: 'Lokale ledger wordt geladen...',
                          en: 'Loading local ledger...',
                          fr: 'Chargement du ledger local...',
                          es: 'Cargando ledger local...',
                        ),
                        style: TextStyle(
                          color: _chironTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  );
                }

                if (_loadError != null &&
                    (_result == null || _result!.entries.isEmpty)) {
                  final lock = _loadError == 'local_file_lock';
                  return Column(
                    key: const ValueKey('chiron_local_register_error'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lock
                            ? _t(
                                nl: 'Lokale ledger is tijdelijk vergrendeld. Sluit andere Fluxidi-processen en probeer opnieuw.',
                                en: 'The local ledger is temporarily locked. Close other Fluxidi processes and try again.',
                                fr: 'Le ledger local est temporairement verrouillé. Fermez les autres processus Fluxidi et réessayez.',
                                es: 'El ledger local está temporalmente bloqueado. Cierre otros procesos de Fluxidi e inténtelo de nuevo.',
                              )
                            : _t(
                                nl: 'Rittenregister kon niet geladen worden. Probeer opnieuw.',
                                en: 'Ride register could not be loaded. Please try again.',
                                fr: 'Le registre des courses n’a pas pu être chargé. Réessayez.',
                                es: 'No se pudo cargar el registro de viajes. Inténtelo de nuevo.',
                              ),
                        style: TextStyle(
                          color: _chironTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        key: const ValueKey('chiron_local_register_retry'),
                        onPressed: _refreshBusy ? null : _refresh,
                        child: Text(
                          _t(
                            nl: 'Opnieuw laden',
                            en: 'Reload',
                            fr: 'Recharger',
                            es: 'Recargar',
                          ),
                        ),
                      ),
                    ],
                  );
                }

                final result =
                    _result ??
                    const ComplianceLedgerReadResult(
                      entries: <ComplianceLedgerEntry>[],
                      fileExists: false,
                      skippedMalformedLines: 0,
                    );
                final effective = _effectiveTenantCompanyIds();
                final hasScope = effective != null;

                if (!hasScope) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _chironPanel,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _chironBorder),
                    ),
                    child: Text(
                      _t(
                        nl: 'Bedrijfscontext ontbreekt. Compliancegegevens kunnen niet veilig geladen worden.',
                        en: 'Company context is missing. Compliance data cannot be loaded safely.',
                        fr: 'Le contexte entreprise est manquant. Les données de conformité ne peuvent pas être chargées en toute sécurité.',
                        es: 'Falta el contexto de empresa. Los datos de cumplimiento no pueden cargarse de forma segura.',
                      ),
                      style: TextStyle(color: _chironTextMuted, fontSize: 12),
                    ),
                  );
                }

                final allGroups = _groupedLedgerEntries(result.entries);
                final filteredGroups = _applyLedgerGroupFilters(allGroups);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (result.isSyncingBackend)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _chironGold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _t(
                                nl: 'Backend compliance wordt opgehaald...',
                                en: 'Fetching backend compliance...',
                                fr: 'Récupération conformité backend...',
                                es: 'Obteniendo cumplimiento backend...',
                              ),
                              style: TextStyle(
                                color: _chironTextSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!result.backendFetchOk &&
                        (result.backendError ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _t(
                            nl: 'Backend sync niet beschikbaar (${result.backendError}). Lokale cache wordt getoond.',
                            en: 'Backend sync unavailable (${result.backendError}). Showing local cache.',
                            fr: 'Sync backend indisponible (${result.backendError}). Cache local affiché.',
                            es: 'Sync backend no disponible (${result.backendError}). Mostrando caché local.',
                          ),
                          style: TextStyle(color: _chironWarning, fontSize: 11),
                        ),
                      ),
                    if (result.entries.isEmpty)
                      Container(
                        key: const ValueKey('chiron_local_register_empty'),
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _chironPanel,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _chironBorder),
                        ),
                        child: Text(
                          _t(
                            nl: 'Nog geen lokale ritten gevonden',
                            en: 'No local rides found yet',
                            fr: 'Aucun trajet local trouvé',
                            es: 'Aún no se encontraron viajes locales',
                          ),
                          style: TextStyle(
                            color: _chironTextMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (result.skippedMalformedLines > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${result.skippedMalformedLines} ${_t(nl: 'beschadigde ledgerregels overgeslagen.', en: 'malformed ledger lines skipped.', fr: 'lignes ledger endommagées ignorées.', es: 'líneas de ledger dañadas omitidas.')}',
                          style: TextStyle(color: _chironWarning, fontSize: 11),
                        ),
                      ),
                    if (allGroups.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _hasActiveLedgerFilter
                              ? _t(
                                  nl: '${filteredGroups.length} van ${allGroups.length} ritten',
                                  en: '${filteredGroups.length} of ${allGroups.length} rides',
                                  fr: '${filteredGroups.length} sur ${allGroups.length} trajets',
                                  es: '${filteredGroups.length} de ${allGroups.length} viajes',
                                )
                              : _t(
                                  nl: '${allGroups.length} ritten',
                                  en: '${allGroups.length} rides',
                                  fr: '${allGroups.length} trajets',
                                  es: '${allGroups.length} viajes',
                                ),
                          style: TextStyle(
                            color: _chironTextMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    if (filteredGroups.isEmpty && allGroups.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _chironPanel,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _chironBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t(
                                nl: 'Geen ritten gevonden',
                                en: 'No rides found',
                                fr: 'Aucun trajet trouvé',
                                es: 'No se encontraron viajes',
                              ),
                              style: TextStyle(
                                color: _chironTextPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _t(
                                nl: 'Pas je zoekopdracht of filter aan.',
                                en: 'Adjust your search or filter.',
                                fr: 'Ajustez votre recherche ou votre filtre.',
                                es: 'Ajusta tu búsqueda o filtro.',
                              ),
                              style: TextStyle(
                                color: _chironTextMuted,
                                fontSize: 12,
                              ),
                            ),
                            if (_hasActiveLedgerFilter) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _resetLedgerSearchAndCategory,
                                  icon: Icon(
                                    Icons.filter_alt_off,
                                    size: 16,
                                    color: _chironGold,
                                  ),
                                  label: Text(
                                    _t(
                                      nl: 'Filters wissen',
                                      en: 'Clear filters',
                                      fr: 'Effacer les filtres',
                                      es: 'Borrar filtros',
                                    ),
                                    style: TextStyle(
                                      color: _chironGold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    minimumSize: const Size(0, 32),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    else
                      ValueListenableBuilder<int>(
                        valueListenable: localRideAssignmentCacheRevision,
                        builder: (context, _, __) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: filteredGroups
                                .map(_groupCard)
                                .toList(growable: false),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
