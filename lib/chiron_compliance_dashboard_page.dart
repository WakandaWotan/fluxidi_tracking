import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/compliance_ledger_reader.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver_documents_store.dart';
import 'package:http/http.dart' as http;

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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1020),
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
          _baseCard(
            title: _t(
              nl: 'Overzicht',
              en: 'Overview',
              fr: 'Aperçu',
              es: 'Resumen',
            ),
            child: Text(
              _t(
                nl: 'Alleen-lezen compliance overzicht.',
                en: 'Read-only compliance overview.',
                fr: 'Aperçu de conformité en lecture seule.',
                es: 'Resumen de cumplimiento de solo lectura.',
              ),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
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
              nl: 'Controleer bedrijf, chauffeurs, voertuigen en documenten.',
              en: 'Check company, drivers, vehicles and documents.',
              fr: 'Vérifiez l’entreprise, les chauffeurs, les véhicules et les documents.',
              es: 'Revisa empresa, conductores, vehículos y documentos.',
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
              en: 'Backend compliance inbox',
              fr: 'Boîte conformité backend',
              es: 'Bandeja de cumplimiento backend',
            ),
            subtitle: _t(
              nl: 'Bekijk recente backendmeldingen uit de Compliance Worker.',
              en: 'View recent backend compliance events from the Compliance Worker.',
              fr: 'Consultez les événements récents de conformité backend du Compliance Worker.',
              es: 'Consulta eventos recientes de cumplimiento backend del Compliance Worker.',
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
    );
  }
}

Widget _baseCard({
  required String title,
  required Widget child,
  String? subtitle,
}) {
  return Card(
    color: const Color(0xFF141B2F),
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0x22FFFFFF)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFFFD54F),
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
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
      color: const Color(0xFF141B2F),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0x22FFFFFF)),
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
                      style: const TextStyle(
                        color: Color(0xFFFFD54F),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
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
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0x22FFFFFF)),
                        ),
                        child: Text(
                          note!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(trailingIcon, color: Colors.white70),
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
    final resolvedAccent =
        accent ?? (ready ? Colors.greenAccent : Colors.orangeAccent);
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
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
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
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white60, fontSize: 12),
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
        color: Colors.redAccent,
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
        color: Colors.orangeAccent,
        icon: Icons.warning_amber_rounded,
      );
    }
    return (
      label: _t(nl: 'In orde', en: 'Healthy', fr: 'En ordre', es: 'En orden'),
      color: Colors.greenAccent,
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
            style: const TextStyle(
              color: Color(0xFFFFD54F),
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
                color: critical
                    ? const Color(0x33FF5A5A)
                    : Colors.orange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: critical
                      ? Colors.redAccent.withOpacity(0.5)
                      : Colors.orangeAccent.withOpacity(0.45),
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
                    color: critical ? Colors.redAccent : Colors.orangeAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.text,
                      style: const TextStyle(
                        color: Colors.white70,
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
        final overallScore =
            ((companyScore + driverScore + vehicleScore + docScore) / 4)
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
              nl: '$vehiclesMissingRequired voertuig(en) missen verplichte Chiron-velden.',
              en: '$vehiclesMissingRequired vehicle(s) missing required Chiron fields.',
              fr: '$vehiclesMissingRequired véhicule(s) sans champs Chiron requis.',
              es: '$vehiclesMissingRequired vehículo(s) sin campos Chiron requeridos.',
            ),
            critical: false,
          ));
        }
        if (coreGapCount > 0) {
          docAttention.add((
            text: _t(
              nl: '$coreGapCount chauffeur(s) hebben een kern-documentkloof.',
              en: '$coreGapCount driver(s) have a core document gap.',
              fr: '$coreGapCount chauffeur(s) ont un manque de documents clés.',
              es: '$coreGapCount conductor(es) tienen faltantes de documentos clave.',
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
            critical: true,
          ));
        }

        final allAttention = <({String text, bool critical})>[
          ...companyAttention,
          ...driverAttention,
          ...vehicleAttention,
          ...docAttention,
        ];
        final criticalAttentionCount = allAttention
            .where((x) => x.critical)
            .length;
        final status = _overallStatus(
          score: overallScore,
          criticalCount: criticalAttentionCount,
          attentionCount: allAttention.length,
        );

        return Scaffold(
          backgroundColor: const Color(0xFF0B1020),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0B1020),
            title: Text(
              _t(
                nl: 'Checklist & readiness',
                en: 'Checklist & readiness',
                fr: 'Checklist et préparation',
                es: 'Checklist y preparación',
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
                      children: [
                        Expanded(
                          child: Text(
                            _t(
                              nl: 'Readiness score',
                              en: 'Readiness score',
                              fr: 'Score de préparation',
                              es: 'Puntuación de preparación',
                            ),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        Text(
                          '$overallScore%',
                          style: const TextStyle(
                            color: Colors.white,
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
                            nl: 'Bedrijf $companyScore% • Chauffeurs $driverScore% • Voertuigen $vehicleScore% • Documenten $docScore%',
                            en: 'Company $companyScore% • Drivers $driverScore% • Vehicles $vehicleScore% • Documents $docScore%',
                            fr: 'Entreprise $companyScore% • Chauffeurs $driverScore% • Véhicules $vehicleScore% • Documents $docScore%',
                            es: 'Empresa $companyScore% • Conductores $driverScore% • Vehículos $vehicleScore% • Documentos $docScore%',
                          ),
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: overallScore / 100,
                      minHeight: 8,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        overallScore >= 80
                            ? Colors.greenAccent
                            : (overallScore >= 50
                                  ? Colors.amberAccent
                                  : Colors.orangeAccent),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _metric(
                      label: _t(
                        nl: 'Aandachtspunten',
                        en: 'Attention needed',
                        fr: 'Points d attention',
                        es: 'Atención requerida',
                      ),
                      value: allAttention.length.toString(),
                      ready: allAttention.isEmpty,
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
                              style: const TextStyle(color: Colors.white70),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: profile.isSuspended
                                    ? const Color(0xFF3A1010)
                                    : profile.isVerified
                                    ? const Color(0xFF12331F)
                                    : const Color(0xFF2A2410),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                profile.verificationBadgeLabel(_lang),
                                style: const TextStyle(
                                  color: Colors.white,
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
                  nl: 'Chauffeur readiness',
                  en: 'Driver readiness',
                  fr: 'Préparation chauffeurs',
                  es: 'Preparación conductores',
                ),
                child: Column(
                  children: [
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
              _baseCard(
                title: _t(
                  nl: 'Chauffeur documentstatus',
                  en: 'Driver document status',
                  fr: 'Statut des documents chauffeurs',
                  es: 'Estado de documentos de conductores',
                ),
                child: Column(
                  children: [
                    _metric(
                      label: _t(
                        nl: 'Totaal documenten',
                        en: 'Total documents',
                        fr: 'Total documents',
                        es: 'Total documentos',
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
                        nl: 'Kern-documentkloof (chauffeurs)',
                        en: 'Core document gap (drivers)',
                        fr: 'Manque de documents clés',
                        es: 'Brecha de documentos clave',
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
                child: allAttention.isEmpty
                    ? _emptyState(
                        _t(
                          nl: 'Geen directe aandachtspunten gevonden.',
                          en: 'No immediate attention items found.',
                          fr: 'Aucun point d attention immédiat.',
                          es: 'No se encontraron elementos urgentes.',
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                          _attentionGroup(
                            title: _t(
                              nl: 'Documenten',
                              en: 'Documents',
                              fr: 'Documents',
                              es: 'Documentos',
                            ),
                            items: docAttention,
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1020),
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
              nl: 'Laatste lokale compliance-records in read-only modus.',
              en: 'Latest local compliance records in read-only mode.',
              fr: 'Derniers enregistrements locaux de conformité en lecture seule.',
              es: 'Últimos registros locales de cumplimiento en modo de solo lectura.',
            ),
            child: _LocalComplianceLedgerSection(lang: _lang),
          ),
        ],
      ),
    );
  }
}

const String _complianceApiBaseUrl = String.fromEnvironment(
  'COMPLIANCE_API_BASE_URL',
  defaultValue: 'https://fluxidi-compliance-api.fluxidi.workers.dev',
);
const String _complianceAdminToken = String.fromEnvironment(
  'ADMIN_TOKEN',
  defaultValue: '',
);

class RemoteComplianceEvent {
  const RemoteComplianceEvent({
    required this.key,
    required this.eventId,
    required this.eventType,
    required this.rideType,
    required this.bookingId,
    required this.tripId,
    required this.syncState,
    required this.createdAtUtc,
    required this.timestamps,
    required this.payment,
    required this.fare,
    required this.provenance,
  });

  final String key;
  final String eventId;
  final String eventType;
  final String rideType;
  final String bookingId;
  final String tripId;
  final String syncState;
  final String createdAtUtc;
  final Map<String, dynamic> timestamps;
  final Map<String, dynamic> payment;
  final Map<String, dynamic> fare;
  final Map<String, dynamic> provenance;

  factory RemoteComplianceEvent.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> asMap(Object? value) {
      if (value is Map) return Map<String, dynamic>.from(value);
      return const <String, dynamic>{};
    }

    String text(String key) => (json[key] ?? '').toString().trim();

    return RemoteComplianceEvent(
      key: text('key'),
      eventId: text('event_id'),
      eventType: text('event_type'),
      rideType: text('ride_type'),
      bookingId: text('booking_id'),
      tripId: text('trip_id'),
      syncState: text('sync_state'),
      createdAtUtc: text('created_at_utc'),
      timestamps: asMap(json['timestamps']),
      payment: asMap(json['payment']),
      fare: asMap(json['fare']),
      provenance: asMap(json['provenance']),
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1020),
        title: Text(
          _t(
            nl: 'Backendmeldingen',
            en: 'Backend events',
            fr: 'Événements du backend',
            es: 'Eventos del backend',
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _baseCard(
            title: _t(
              nl: 'Backendmeldingen',
              en: 'Backend compliance inbox',
              fr: 'Boîte de conformité backend',
              es: 'Bandeja de cumplimiento backend',
            ),
            subtitle: _t(
              nl: 'Alleen-lezen meldingen uit de backend Compliance Worker.',
              en: 'Read-only events from the backend Compliance Worker.',
              fr: 'Événements en lecture seule depuis le Compliance Worker backend.',
              es: 'Eventos de solo lectura desde el Compliance Worker backend.',
            ),
            child: _RemoteComplianceEventsSection(lang: _lang),
          ),
        ],
      ),
    );
  }
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
  late Future<RemoteComplianceEventsResponse> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadRemoteEvents();
  }

  void _refresh() {
    setState(() {
      _future = _loadRemoteEvents();
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

  String _localizedUnknown() {
    return _t(nl: 'onbekend', en: 'unknown', fr: 'inconnu', es: 'desconocido');
  }

  String _localizedEventTypeLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'payment_update':
        return _t(
          nl: 'Betalingsupdate',
          en: 'Payment update',
          fr: 'Mise à jour du paiement',
          es: 'Actualización del pago',
        );
      case 'ride_stop':
        return _t(
          nl: 'Rit afgerond',
          en: 'Ride completed',
          fr: 'Course terminée',
          es: 'Viaje finalizado',
        );
      case 'unknown':
        return _localizedUnknown();
      default:
        return raw.trim().isEmpty ? '—' : _localizedUnknown();
    }
  }

  String _localizedRideTypeLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'planned':
        return _t(
          nl: 'geplande rit',
          en: 'planned ride',
          fr: 'course planifiée',
          es: 'viaje planificado',
        );
      case 'direct':
        return _t(
          nl: 'directe rit',
          en: 'direct ride',
          fr: 'course directe',
          es: 'viaje directo',
        );
      case 'unknown':
        return _localizedUnknown();
      default:
        return raw.trim().isEmpty ? '—' : _localizedUnknown();
    }
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

  String _localizedPaymentMethodLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'cash':
        return _t(nl: 'contant', en: 'cash', fr: 'espèces', es: 'efectivo');
      case 'bancontact':
        return 'Bancontact';
      case 'card':
      case 'pin':
        return _t(nl: 'kaart', en: 'card', fr: 'carte', es: 'tarjeta');
      case 'qr':
        return 'QR';
      case 'mollie':
      case 'online_payment':
      case 'online-payment':
      case 'online payment':
      case 'online':
        return _t(nl: 'online', en: 'online', fr: 'en ligne', es: 'en línea');
      case 'unknown':
      case '':
        return _localizedUnknown();
      default:
        return _localizedUnknown();
    }
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

  String _localizedSyncStateLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'not_configured':
        return _t(
          nl: 'niet ingesteld',
          en: 'not configured',
          fr: 'non configuré',
          es: 'no configurado',
        );
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
      case 'unknown':
      case '':
        return _localizedUnknown();
      default:
        return _localizedUnknown();
    }
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
    final activeCompanyId =
        companyProfileNotifier.value?.companyId.trim() ?? '';
    final resolvedId = resolvedCompanyId.trim();
    final effectiveTenantId = activeCompanyId.isNotEmpty
        ? activeCompanyId
        : (resolvedId.isNotEmpty ? resolvedId : kTenantId);
    final effectiveCompanyId = activeCompanyId.isNotEmpty
        ? activeCompanyId
        : (resolvedId.isNotEmpty ? resolvedId : kTenantId);

    final token = _complianceAdminToken.trim();
    if (token.isEmpty) {
      return RemoteComplianceEventsResponse(
        ok: false,
        tenantId: effectiveTenantId,
        companyId: effectiveCompanyId,
        limit: 10,
        count: 0,
        malformedCount: 0,
        events: const <RemoteComplianceEvent>[],
        errorMessage: _t(
          nl: 'Admin token ontbreekt voor backendmeldingen.',
          en: 'Admin token is missing for remote compliance events.',
          fr: 'Le jeton admin manque pour les événements de conformité distants.',
          es: 'Falta el token admin para eventos remotos de cumplimiento.',
        ),
      );
    }

    final uri = Uri.parse('$_complianceApiBaseUrl/compliance/events/recent')
        .replace(
          queryParameters: <String, String>{
            'tenant_id': effectiveTenantId,
            'company_id': effectiveCompanyId,
            'limit': '10',
          },
        );
    try {
      final res = await http
          .get(
            uri,
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'x-admin-token': token,
            },
          )
          .timeout(const Duration(seconds: 10));

      Map<String, dynamic> asMap(Object? value) {
        if (value is Map) return Map<String, dynamic>.from(value);
        return const <String, dynamic>{};
      }

      final decoded = jsonDecode(res.body);
      final payload = asMap(decoded);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final err = _text(payload['error']);
        return RemoteComplianceEventsResponse(
          ok: false,
          tenantId: _text(payload['tenant_id']),
          companyId: _text(payload['company_id']),
          limit: int.tryParse(_text(payload['limit'])) ?? 10,
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

      return RemoteComplianceEventsResponse(
        ok: payload['ok'] == true,
        tenantId: _text(payload['tenant_id']),
        companyId: _text(payload['company_id']),
        limit: int.tryParse(_text(payload['limit'])) ?? 10,
        count: int.tryParse(_text(payload['count'])) ?? events.length,
        malformedCount: int.tryParse(_text(payload['malformed_count'])) ?? 0,
        events: events,
        errorMessage: '',
      );
    } catch (_) {
      return RemoteComplianceEventsResponse(
        ok: false,
        tenantId: effectiveTenantId,
        companyId: effectiveCompanyId,
        limit: 10,
        count: 0,
        malformedCount: 0,
        events: const <RemoteComplianceEvent>[],
        errorMessage: _t(
          nl: 'Kan backend compliance events niet laden. Controleer netwerk/token.',
          en: 'Cannot load backend compliance events. Check network/token.',
          fr: 'Impossible de charger les événements conformité backend. Vérifiez réseau/jeton.',
          es: 'No se pueden cargar eventos de cumplimiento backend. Verifica red/token.',
        ),
      );
    }
  }

  Widget _chip(String label) {
    if (label.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 11),
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

  String _localizedDraftReceiptLabel() {
    return _t(
      nl: 'Conceptbon',
      en: 'Draft receipt',
      fr: 'Reçu provisoire',
      es: 'Recibo provisional',
    );
  }

  String _labelValue(String label, String value) {
    if (appConfig.currentLanguage == AppLanguage.fr) return '$label : $value';
    return '$label: $value';
  }

  ({String label, String value}) _businessReferenceForRemoteCard({
    required String rideType,
    required String bookingId,
    required String tripId,
  }) {
    final bookingIsBusiness =
        bookingId.isNotEmpty && !_isTechnicalInternalReference(bookingId);
    if (bookingIsBusiness) {
      return (
        label: _t(
          nl: 'Boeking',
          en: 'Booking',
          fr: 'Réservation',
          es: 'Reserva',
        ),
        value: bookingId,
      );
    }
    final tripIsBusiness =
        tripId.isNotEmpty && !_isTechnicalInternalReference(tripId);
    if (tripIsBusiness) {
      return (label: _localizedReferenceLabel(), value: tripId);
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

  String _dossierGroupKey(RemoteComplianceEvent e, int index) {
    if (_isMeaningfulIdentity(e.bookingId)) {
      return 'booking:${e.bookingId.trim().toLowerCase()}';
    }
    if (_isMeaningfulIdentity(e.tripId)) {
      return 'trip:${e.tripId.trim().toLowerCase()}';
    }
    final eventId = _text(e.eventId);
    if (eventId.isNotEmpty) return 'event:${eventId.toLowerCase()}';
    final createdAt = _text(e.createdAtUtc);
    if (createdAt.isNotEmpty) return 'event:${createdAt.toLowerCase()}';
    return 'event:index_$index';
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
    final hasRideStop = events.any(
      (event) => _normalizeToken(event.eventType) == 'ride_stop',
    );
    if (hasRideStop) {
      return _t(
        nl: 'afgerond',
        en: 'completed',
        fr: 'terminée',
        es: 'finalizado',
      );
    }
    return _localizedUnknown();
  }

  Widget _auditHistoryRow(
    RemoteComplianceEvent e,
    Map<String, RemoteComplianceEvent> latestPaymentUpdates,
  ) {
    final payment = _effectivePaymentForEvent(e, latestPaymentUpdates);
    final producer = _text(e.provenance['producer']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_localizedEventTypeLabel(e.eventType)} • ${_localizedRideTypeLabel(e.rideType)}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _fmtDateTime(e.createdAtUtc),
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                '${_t(nl: 'Synchronisatie', en: 'Sync', fr: 'Synchronisation', es: 'Sincronización')}: ${_localizedSyncStateLabel(e.syncState)}',
              ),
              if (payment.status.isNotEmpty)
                _chip(
                  '${_t(nl: 'Betaling', en: 'Payment', fr: 'Paiement', es: 'Pago')}: ${_localizedPaymentStatusLabel(payment.status)}',
                ),
              if (payment.method.isNotEmpty &&
                  payment.method.toLowerCase() != 'unknown')
                _chip(
                  '${_t(nl: 'Methode', en: 'Method', fr: 'Méthode', es: 'Método')}: ${_localizedPaymentMethodLabel(payment.method)}',
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
              if (producer.isNotEmpty)
                _chip(
                  '${_t(nl: 'Aangemaakt door', en: 'Created by', fr: 'Créé par', es: 'Creado por')}: ${_localizedProducerLabel(producer)}',
                ),
            ],
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
    final tripId = sorted
        .map((event) => event.tripId.trim())
        .firstWhere((id) => _isMeaningfulIdentity(id), orElse: () => '');
    final payment = _effectivePaymentForEvent(latest, latestPaymentUpdates);
    final reference = _businessReferenceForRemoteCard(
      rideType: latest.rideType,
      bookingId: bookingId,
      tripId: tripId,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _localizedDossierTitle(latest.rideType),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _labelValue(reference.label, reference.value),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            '${_t(nl: 'Laatste event', en: 'Latest event', fr: 'Dernier événement', es: 'Último evento')}: ${_fmtDateTime(latest.createdAtUtc)}',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                '${_t(nl: 'Ritstatus', en: 'Ride status', fr: 'Statut de la course', es: 'Estado del viaje')}: ${_localizedRideStatus(sorted)}',
              ),
              _chip(
                '${_t(nl: 'Synchronisatie', en: 'Sync', fr: 'Synchronisation', es: 'Sincronización')}: ${_localizedSyncStateLabel(latest.syncState)}',
              ),
              if (payment.status.isNotEmpty)
                _chip(
                  '${_t(nl: 'Betaling', en: 'Payment', fr: 'Paiement', es: 'Pago')}: ${_localizedPaymentStatusLabel(payment.status)}',
                ),
              if (payment.method.isNotEmpty &&
                  payment.method.toLowerCase() != 'unknown')
                _chip(
                  '${_t(nl: 'Methode', en: 'Method', fr: 'Méthode', es: 'Método')}: ${_localizedPaymentMethodLabel(payment.method)}',
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
            style: const TextStyle(
              color: Color(0xFFFFD54F),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          ...sorted.map(
            (event) => _auditHistoryRow(event, latestPaymentUpdates),
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
                  nl: 'Compliance-module (backend)',
                  en: 'Compliance module (backend)',
                  fr: 'Module de conformité (backend)',
                  es: 'Módulo de cumplimiento (backend)',
                ),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
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
              icon: const Icon(Icons.refresh, color: Colors.white70),
            ),
          ],
        ),
        FutureBuilder<RemoteComplianceEventsResponse>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _t(
                      nl: 'Backendmeldingen laden...',
                      en: 'Loading backend events...',
                      fr: 'Chargement des événements backend...',
                      es: 'Cargando eventos del backend...',
                    ),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              );
            }

            final result =
                snapshot.data ??
                RemoteComplianceEventsResponse(
                  ok: false,
                  tenantId: kTenantId,
                  companyId: kCompanyId,
                  limit: 10,
                  count: 0,
                  malformedCount: 0,
                  events: const <RemoteComplianceEvent>[],
                  errorMessage: _t(
                    nl: 'Onbekende fout bij laden van backendmeldingen.',
                    en: 'Unknown error while loading backend events.',
                    fr: 'Erreur inconnue lors du chargement des événements backend.',
                    es: 'Error desconocido al cargar los eventos del backend.',
                  ),
                );

            if (!result.ok) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x22FFFFFF)),
                ),
                child: Text(
                  result.errorMessage.isEmpty
                      ? _t(
                          nl: 'Remote compliance events niet beschikbaar.',
                          en: 'Remote compliance events are unavailable.',
                          fr: 'Événements conformité distants indisponibles.',
                          es: 'Eventos remotos de cumplimiento no disponibles.',
                        )
                      : result.errorMessage,
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 12,
                  ),
                ),
              );
            }

            if (result.events.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x22FFFFFF)),
                ),
                child: Text(
                  _t(
                    nl: 'Geen backendmeldingen gevonden.',
                    en: 'No backend events found.',
                    fr: 'Aucun événement backend trouvé.',
                    es: 'No se encontraron eventos del backend.',
                  ),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              );
            }

            final latestPaymentUpdates = _latestPaymentUpdatesByKey(
              result.events,
            );
            final grouped = <String, List<RemoteComplianceEvent>>{};
            for (final entry in result.events.asMap().entries) {
              final index = entry.key;
              final event = entry.value;
              final groupKey = _dossierGroupKey(event, index);
              grouped
                  .putIfAbsent(groupKey, () => <RemoteComplianceEvent>[])
                  .add(event);
            }
            final dossiers = grouped.values.toList(growable: false)
              ..sort((a, b) {
                final newestA = [...a]..sort(_compareRemoteEventsNewestFirst);
                final newestB = [...b]..sort(_compareRemoteEventsNewestFirst);
                return _compareRemoteEventsNewestFirst(
                  newestA.first,
                  newestB.first,
                );
              });
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 11,
                      ),
                    ),
                  ),
                Text(
                  _t(
                    nl: 'Tenant ${result.tenantId} • Bedrijf ${result.companyId} • ${result.count} meldingen',
                    en: 'Tenant ${result.tenantId} • Company ${result.companyId} • ${result.count} events',
                    fr: 'Tenant ${result.tenantId} • Société ${result.companyId} • ${result.count} événements',
                    es: 'Tenant ${result.tenantId} • Empresa ${result.companyId} • ${result.count} eventos',
                  ),
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 8),
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

class _LocalComplianceLedgerSection extends StatefulWidget {
  const _LocalComplianceLedgerSection({required this.lang});

  final AppLanguage lang;

  @override
  State<_LocalComplianceLedgerSection> createState() =>
      _LocalComplianceLedgerSectionState();
}

class _LocalComplianceLedgerSectionState
    extends State<_LocalComplianceLedgerSection> {
  late Future<ComplianceLedgerReadResult> _future;
  final ComplianceLedgerReader _reader = ComplianceLedgerReader();

  @override
  void initState() {
    super.initState();
    _future = _reader.readLatest(limit: 20);
  }

  void _refresh() {
    setState(() {
      _future = _reader.readLatest(limit: 20);
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
          nl: 'Straatrit',
          en: 'Street ride',
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
    return _t(nl: 'Bon', en: 'Receipt', fr: 'Reçu', es: 'Recibo');
  }

  String _draftReceiptLabel() {
    return _t(
      nl: 'Conceptbon',
      en: 'Draft receipt',
      fr: 'Reçu provisoire',
      es: 'Recibo provisional',
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

  String? _bestBusinessReference(ComplianceLedgerEntry entry) {
    final candidates = <String>[
      entry.receiptReference.trim(),
      entry.bookingId.trim(),
      entry.tripId.trim(),
      entry.rideId.trim(),
      entry.eventId.trim(),
    ];
    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      if (_looksTechnicalInternalReference(candidate)) continue;
      return candidate;
    }
    return null;
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ),
    );
  }

  String _eventTypeLabel(String raw, {bool inferCompleted = false}) {
    final token = _ledgerToken(raw);
    switch (token) {
      case 'ride_stop':
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
    final booking = _ledgerKeyPart('booking', e.bookingId);
    if (booking != null) return booking;
    final trip = _ledgerKeyPart('trip', e.tripId);
    if (trip != null) return trip;
    final receipt = _ledgerKeyPart('receipt', e.receiptReference);
    if (receipt != null) return receipt;
    final event = _ledgerKeyPart('event', e.eventId);
    if (event != null) return event;
    return 'event:index_$index';
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
      if (!entry.isPaymentUpdate) return entry;
    }
    return sorted.last;
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

  String _driverDisplay(ComplianceLedgerEntry entry) {
    final candidates = <String?>[
      _rawPathText(entry.raw, const ['driver', 'name']),
      _rawPathText(entry.raw, const ['driver', 'fullName']),
      _rawPathText(entry.raw, const ['driver', 'full_name']),
      _rawPathText(entry.raw, const ['driver', 'display_name']),
      _rawPathText(entry.raw, const ['driver', 'displayName']),
      _rawPathText(entry.raw, const ['assigned_driver', 'name']),
      _rawPathText(entry.raw, const ['assigned_driver', 'fullName']),
      _rawPathText(entry.raw, const ['assigned_driver', 'full_name']),
      _rawPathText(entry.raw, const ['assignedDriver', 'name']),
      _rawPathText(entry.raw, const ['assignedDriver', 'fullName']),
      _rawPathText(entry.raw, const ['driver_profile', 'name']),
      _rawPathText(entry.raw, const ['driver_profile', 'fullName']),
      _rawPathText(entry.raw, const ['driverProfile', 'name']),
      _rawPathText(entry.raw, const ['driverProfile', 'fullName']),
      _rawPathText(entry.raw, const ['chauffeur', 'name']),
      _rawPathText(entry.raw, const ['chauffeur', 'fullName']),
      _rawPathText(entry.raw, const ['driver_name']),
      _rawPathText(entry.raw, const ['driverName']),
      _rawPathText(entry.raw, const ['chauffeur_name']),
      _rawPathText(entry.raw, const ['chauffeurName']),
      _rawPathText(entry.raw, const ['paid_by_driver_name']),
      _rawPathText(entry.raw, const ['paidByDriverName']),
      _rawPathText(entry.raw, const ['driver_label']),
      _rawPathText(entry.raw, const ['driverLabel']),
    ];
    for (final value in candidates) {
      final meaningful = _meaningfulDisplayToken(value);
      if (meaningful != null) return meaningful;
    }
    final driverId = _meaningfulDisplayToken(
      _rawPathText(entry.raw, const ['driver', 'driver_id']) ??
          _rawPathText(entry.raw, const ['driver', 'id']) ??
          _rawPathText(entry.raw, const ['assigned_driver', 'driver_id']) ??
          _rawPathText(entry.raw, const ['assigned_driver', 'id']) ??
          _rawPathText(entry.raw, const ['driver_id']) ??
          entry.driverId,
    );
    final profileDisplay = _lookupDriverProfileDisplay(driverId);
    if (profileDisplay != null) return profileDisplay;
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
      if (value != _driverNotLinkedLabel()) return value;
    }
    if (profileMissing) return _driverProfileNotFoundLabel();
    return _driverNotLinkedLabel();
  }

  String _vehicleDisplay(ComplianceLedgerEntry entry) {
    final plateCandidates = <String?>[
      _rawPathText(entry.raw, const ['vehicle', 'licensePlate']),
      _rawPathText(entry.raw, const ['vehicle', 'license_plate']),
      _rawPathText(entry.raw, const ['vehicle', 'plate']),
      _rawPathText(entry.raw, const ['vehicle', 'registration']),
      _rawPathText(entry.raw, const ['vehicle', 'registrationNumber']),
      _rawPathText(entry.raw, const ['vehicle', 'registration_number']),
      _rawPathText(entry.raw, const ['assigned_vehicle', 'licensePlate']),
      _rawPathText(entry.raw, const ['assigned_vehicle', 'license_plate']),
      _rawPathText(entry.raw, const ['assigned_vehicle', 'plate']),
      _rawPathText(entry.raw, const ['assignedVehicle', 'licensePlate']),
      _rawPathText(entry.raw, const ['vehicle_profile', 'licensePlate']),
      _rawPathText(entry.raw, const ['vehicleProfile', 'licensePlate']),
      _rawPathText(entry.raw, const ['license_plate']),
      _rawPathText(entry.raw, const ['licensePlate']),
      _rawPathText(entry.raw, const ['plate']),
      _rawPathText(entry.raw, const ['registration_number']),
      _rawPathText(entry.raw, const ['registrationNumber']),
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
      _rawPathText(entry.raw, const ['vehicle', 'label']),
      _rawPathText(entry.raw, const ['vehicle', 'name']),
      _rawPathText(entry.raw, const ['vehicle', 'vehicleLabel']),
      _rawPathText(entry.raw, const ['vehicle', 'vehicle_label']),
      _rawPathText(entry.raw, const ['vehicle', 'display_label']),
      _rawPathText(entry.raw, const ['vehicle', 'displayLabel']),
      _rawPathText(entry.raw, const ['assigned_vehicle', 'label']),
      _rawPathText(entry.raw, const ['assigned_vehicle', 'name']),
      _rawPathText(entry.raw, const ['assignedVehicle', 'label']),
      _rawPathText(entry.raw, const ['assignedVehicle', 'name']),
      _rawPathText(entry.raw, const ['vehicle_profile', 'label']),
      _rawPathText(entry.raw, const ['vehicle_profile', 'name']),
      _rawPathText(entry.raw, const ['vehicleProfile', 'label']),
      _rawPathText(entry.raw, const ['vehicleProfile', 'name']),
      _rawPathText(entry.raw, const ['vehicle_label']),
      _rawPathText(entry.raw, const ['vehicleLabel']),
      _rawPathText(entry.raw, const ['vehicle_name']),
      _rawPathText(entry.raw, const ['vehicleName']),
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
      _rawPathText(entry.raw, const ['vehicle', 'make']) ??
          _rawPathText(entry.raw, const ['vehicle', 'brand']),
    );
    final model = _meaningfulDisplayToken(
      _rawPathText(entry.raw, const ['vehicle', 'model']),
    );
    final tierRaw = _meaningfulDisplayToken(
      _rawPathText(entry.raw, const ['vehicle', 'tier']),
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
      _rawPathText(entry.raw, const ['vehicle_registration_number']),
      _rawPathText(entry.raw, const ['vehicleRegistrationNumber']),
    ];
    for (final value in fallbackCandidates) {
      final meaningful = _meaningfulDisplayToken(value);
      if (meaningful != null) return meaningful;
    }
    final vehicleId = _meaningfulDisplayToken(
      _rawPathText(entry.raw, const ['vehicle', 'vehicle_id']) ??
          _rawPathText(entry.raw, const ['vehicle', 'id']) ??
          _rawPathText(entry.raw, const ['assigned_vehicle', 'vehicle_id']) ??
          _rawPathText(entry.raw, const ['assigned_vehicle', 'id']) ??
          _rawPathText(entry.raw, const ['vehicle_id']) ??
          entry.vehicleId,
    );
    final profileDisplay = _lookupVehicleProfileDisplay(vehicleId);
    if (profileDisplay != null) return profileDisplay;
    if (vehicleId != null) return _vehicleProfileNotFoundLabel();
    return _vehicleNotLinkedLabel();
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
      if (value != _vehicleNotLinkedLabel()) return value;
    }
    if (profileMissing) return _vehicleProfileNotFoundLabel();
    return _vehicleNotLinkedLabel();
  }

  String _routeDisplay(ComplianceLedgerEntry entry) {
    final pickup = entry.pickupLabel.trim();
    final dropoff = entry.dropoffLabel.trim();
    if (pickup.isNotEmpty && dropoff.isNotEmpty) return '$pickup → $dropoff';
    if (pickup.isNotEmpty) return pickup;
    if (dropoff.isNotEmpty) return dropoff;
    return '—';
  }

  String _referenceDisplay(ComplianceLedgerEntry entry) {
    final businessReference = _bestBusinessReference(entry);
    if (businessReference != null) {
      return '${_receiptLabel()} $businessReference';
    }
    final rideType = _ledgerToken(entry.rideType);
    if (rideType == 'direct' || rideType == 'planned') {
      return _draftReceiptLabel();
    }
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
  }) {
    final eventToken = _ledgerToken(entry.eventType);
    final eventTime = _fmtDateTime(_ledgerSortTime(entry));
    final hasLaterPaymentUpdate =
        !entry.isPaymentUpdate &&
        latestPaymentUpdate != null &&
        _isNewerLedgerEntry(latestPaymentUpdate, entry);
    final isUnknownEventType = eventToken.isEmpty || eventToken == 'unknown';
    final inferCompleted =
        isUnknownEventType &&
        (_ledgerToken(entry.validationState) == 'exportable' ||
            identical(entry, summaryEntry));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_eventTypeLabel(entry.eventType, inferCompleted: inferCompleted)} • ${_rideTypeLabel(entry.rideType)}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            eventTime,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (entry.isPaymentUpdate &&
                  _ledgerToken(entry.validationState) == 'payment_update')
                _chip(_paymentUpdatedLabel())
              else
                _chip(
                  _labelValue(
                    _statusLabel(),
                    _validationStateLabel(entry.validationState),
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
    final title =
        '${_rideTypeLabel(summary.rideType)} • ${_referenceDisplay(summary)}';
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
    final sortedAudit = [...group]..sort((a, b) => _compareLedgerEntries(b, a));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_t(nl: 'Laatste event', en: 'Latest event', fr: 'Dernier événement', es: 'Último evento')}: $latestTime',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          Text(
            '${_t(nl: 'Ritmoment', en: 'Ride time', fr: 'Heure du trajet', es: 'Hora del viaje')}: $rideTime',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            route,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            _labelValue(_driverLabel(), _driverDisplayForGroup(group)),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            _labelValue(_vehicleLabel(), _vehicleDisplayForGroup(group)),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (fare != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _labelValue(_amountLabel(), fare),
                style: const TextStyle(
                  color: Color(0xFFFFD54F),
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
                  _validationStateLabel(summary.validationState),
                ),
              ),
              if (latestPaymentUpdate != null) _chip(_paymentUpdatedLabel()),
            ],
          ),
          if (paymentUpdatedTime != null) ...[
            const SizedBox(height: 6),
            Text(
              '${_paymentUpdatedLabel()}: $paymentUpdatedTime',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            collapsedIconColor: Colors.white70,
            iconColor: Colors.white70,
            title: Text(
              _auditHistoryLabel(),
              style: const TextStyle(
                color: Color(0xFFFFD54F),
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
      color: const Color(0xFF141B2F),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0x22FFFFFF)),
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
                    style: const TextStyle(
                      color: Color(0xFFFFD54F),
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
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
                  icon: const Icon(Icons.refresh, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _t(
                nl: 'Laatste lokale records (read-only, geen synchronisatie).',
                en: 'Latest local records (read-only, no sync).',
                fr: 'Derniers enregistrements locaux (lecture seule, sans synchronisation).',
                es: 'Últimos registros locales (solo lectura, sin sincronización).',
              ),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 10),
            FutureBuilder<ComplianceLedgerReadResult>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _t(
                          nl: 'Lokale ledger wordt geladen...',
                          en: 'Loading local ledger...',
                          fr: 'Chargement du ledger local...',
                          es: 'Cargando ledger local...',
                        ),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  );
                }

                final result =
                    snapshot.data ??
                    const ComplianceLedgerReadResult(
                      entries: <ComplianceLedgerEntry>[],
                      fileExists: false,
                      skippedMalformedLines: 0,
                    );

                if (result.entries.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x22FFFFFF)),
                    ),
                    child: Text(
                      _t(
                        nl: 'Nog geen lokale compliance-ritten gevonden.',
                        en: 'No local compliance rides found yet.',
                        fr: 'Aucun trajet de conformité local trouvé.',
                        es: 'Aún no se encontraron trayectos locales de cumplimiento.',
                      ),
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  );
                }

                final groupedEntries = _groupedLedgerEntries(result.entries);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (result.skippedMalformedLines > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${result.skippedMalformedLines} ${_t(nl: 'beschadigde ledgerregels overgeslagen.', en: 'malformed ledger lines skipped.', fr: 'lignes ledger endommagées ignorées.', es: 'líneas de ledger dañadas omitidas.')}',
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ...groupedEntries.map(_groupCard),
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
