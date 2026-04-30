import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver_documents_store.dart';

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

  bool _hasText(String? value) => (value ?? '').trim().isNotEmpty;

  DateTime? _parseDateOnly(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    final normalized = raw.length >= 10 ? raw.substring(0, 10) : raw;
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  Widget _card({
    required String title,
    required Widget child,
    String? subtitle,
  }) {
    return Card(
      color: const Color(0xFF141B2F),
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
                fontSize: 14,
              ),
            ),
            if (subtitle != null && subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _metric({
    required String label,
    required String value,
    required bool ready,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            ready ? Icons.check_circle_outline : Icons.warning_amber_outlined,
            size: 16,
            color: ready ? Colors.greenAccent : Colors.orangeAccent,
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

        final attention = <String>[];
        if (!hasCompanyName) {
          attention.add(
            _t(
              nl: 'Bedrijfsnaam/juridische naam ontbreekt.',
              en: 'Company/legal name is missing.',
              fr: 'Le nom de l entreprise est manquant.',
              es: 'Falta el nombre de la empresa/legal.',
            ),
          );
        }
        if (!hasRegistration) {
          attention.add(
            _t(
              nl: 'Registratie/KBO/ondernemingsnummer ontbreekt.',
              en: 'Registration/KBO/company number is missing.',
              fr: 'Le numéro d entreprise est manquant.',
              es: 'Falta el número de registro/empresa.',
            ),
          );
        }
        if (!hasAddress) {
          attention.add(
            _t(
              nl: 'Bedrijfsadres is onvolledig.',
              en: 'Company address is incomplete.',
              fr: 'L adresse de l entreprise est incomplète.',
              es: 'La dirección de la empresa está incompleta.',
            ),
          );
        }
        if (driversMissingCardInfo > 0) {
          attention.add(
            _t(
              nl: '$driversMissingCardInfo chauffeur(s) missen kaartnummer en/of vervaldatum.',
              en: '$driversMissingCardInfo driver(s) missing card number and/or expiry.',
              fr: '$driversMissingCardInfo chauffeur(s) sans numéro et/ou expiration de carte.',
              es: '$driversMissingCardInfo conductor(es) sin número y/o vencimiento de tarjeta.',
            ),
          );
        }
        final vehiclesMissingRequired = visibleVehicles.where((v) {
          return !_hasText(v.licensePlate) ||
              !_hasText(v.exploitationLicenseNumber) ||
              !_hasText(v.vehicleRegistrationNumber) ||
              !_hasText(v.driverId);
        }).length;
        if (vehiclesMissingRequired > 0) {
          attention.add(
            _t(
              nl: '$vehiclesMissingRequired voertuig(en) missen verplichte Chiron-velden.',
              en: '$vehiclesMissingRequired vehicle(s) missing required Chiron fields.',
              fr: '$vehiclesMissingRequired véhicule(s) sans champs Chiron requis.',
              es: '$vehiclesMissingRequired vehículo(s) sin campos Chiron requeridos.',
            ),
          );
        }
        if (coreGapCount > 0) {
          attention.add(
            _t(
              nl: '$coreGapCount chauffeur(s) hebben een kern-documentkloof.',
              en: '$coreGapCount driver(s) have a core document gap.',
              fr: '$coreGapCount chauffeur(s) ont un manque de documents clés.',
              es: '$coreGapCount conductor(es) tienen faltantes de documentos clave.',
            ),
          );
        }
        if (expiredDocs > 0 || rejectedDocs > 0) {
          attention.add(
            _t(
              nl: 'Er zijn verlopen of afgewezen documenten.',
              en: 'There are expired or rejected documents.',
              fr: 'Il y a des documents expirés ou rejetés.',
              es: 'Hay documentos caducados o rechazados.',
            ),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0B1020),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0B1020),
            title: Text(
              _t(
                nl: 'Chiron Compliance Dashboard',
                en: 'Chiron Compliance Dashboard',
                fr: 'Tableau de conformité Chiron',
                es: 'Panel de cumplimiento Chiron',
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _card(
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
                      value: attention.length.toString(),
                      ready: attention.isEmpty,
                    ),
                  ],
                ),
              ),
              _card(
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
                  ],
                ),
              ),
              _card(
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
                        child: Text(
                          _t(
                            nl: 'Nog geen chauffeurs gevonden voor dit bedrijf.',
                            en: 'No drivers found for this company yet.',
                            fr: 'Aucun chauffeur trouvé pour cette entreprise.',
                            es: 'No se encontraron conductores para esta empresa.',
                          ),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _card(
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
                        child: Text(
                          _t(
                            nl: 'Nog geen voertuigen gevonden voor dit bedrijf.',
                            en: 'No vehicles found for this company yet.',
                            fr: 'Aucun véhicule trouvé pour cette entreprise.',
                            es: 'No se encontraron vehículos para esta empresa.',
                          ),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _card(
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
                        child: Text(
                          _t(
                            nl: 'Nog geen documenten gevonden. Beheer documenten via Chauffeurs beheren.',
                            en: 'No documents found yet. Manage documents in Manage drivers.',
                            fr: 'Aucun document trouvé. Gérez les documents dans Gérer les chauffeurs.',
                            es: 'No se encontraron documentos. Gestiona documentos en Gestionar conductores.',
                          ),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _card(
                title: _t(
                  nl: 'Compliance ritlogboek',
                  en: 'Compliance ride ledger',
                  fr: 'Journal conformité des trajets',
                  es: 'Libro de rutas de cumplimiento',
                ),
                child: Text(
                  _t(
                    nl: 'Compliance ritlogboek wordt lokaal geschreven. Read-only viewer volgt in een aparte veilige stap.',
                    en: 'Compliance ride ledger is written locally. Read-only viewer will follow in a separate safe step.',
                    fr: 'Le journal de conformité est écrit localement. Un lecteur en lecture seule suivra dans une étape séparée.',
                    es: 'El libro de cumplimiento se escribe localmente. El visor de solo lectura llegará en un paso seguro aparte.',
                  ),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              _card(
                title: _t(
                  nl: 'Aandacht nodig',
                  en: 'Attention needed',
                  fr: 'Attention requise',
                  es: 'Atención requerida',
                ),
                child: attention.isEmpty
                    ? Text(
                        _t(
                          nl: 'Geen directe aandachtspunten gevonden.',
                          en: 'No immediate attention items found.',
                          fr: 'Aucun point d attention immédiat.',
                          es: 'No se encontraron elementos urgentes.',
                        ),
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 12,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: attention
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(top: 2),
                                      child: Icon(
                                        Icons.warning_amber_rounded,
                                        color: Colors.orangeAccent,
                                        size: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          height: 1.3,
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
            ],
          ),
        );
      },
    );
  }
}
