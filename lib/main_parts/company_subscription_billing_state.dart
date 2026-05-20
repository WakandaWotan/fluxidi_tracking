part of '../main.dart';

class CompanySubscriptionBillingPage extends StatefulWidget {
  const CompanySubscriptionBillingPage({super.key});

  @override
  State<CompanySubscriptionBillingPage> createState() =>
      _CompanySubscriptionBillingPageState();
}

class _CompanySubscriptionBillingPageState
    extends State<CompanySubscriptionBillingPage> {
  late Future<BackendSubscriptionProfile> _future;
  static const Color _bg = Color(0xFF07080C);
  static const Color _panel = Color(0xFF101113);
  static const Color _panelSoft = Color(0xFF16120A);
  static const Color _gold = Color(0xFFE5B641);
  static const Color _green = Color(0xFF34D29A);
  static const Color _warn = Color(0xFFFFB457);

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  String _activeCompanyId() {
    final fromProfile = companyProfileNotifier.value?.companyId.trim() ?? '';
    if (fromProfile.isNotEmpty) return fromProfile;
    final resolved = resolvedCompanyId.trim();
    if (resolved.isNotEmpty) return resolved;
    return kTenantId;
  }

  Future<BackendSubscriptionProfile> _fetch() async {
    final scopeId = _activeCompanyId();
    return fetchBackendSubscriptionProfile(
      tenantId: scopeId,
      companyId: scopeId,
    );
  }

  String _planLabel(String plan) {
    switch (plan.trim().toLowerCase()) {
      case 'starter':
        return 'Starter';
      case 'pro':
        return 'Pro';
      case 'business':
        return _t(
          nl: 'Business',
          en: 'Business',
          fr: 'Business',
          es: 'Business',
        );
      case 'enterprise':
        return 'Enterprise';
      default:
        return plan.trim().isEmpty
            ? _t(
                nl: 'Onbekend',
                en: 'Unknown',
                fr: 'Inconnu',
                es: 'Desconocido',
              )
            : plan.trim();
    }
  }

  String _statusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'trialing':
      case 'trial':
      case 'trial_active':
        return _t(
          nl: 'Proefperiode',
          en: 'Trial',
          fr: 'Période d’essai',
          es: 'Periodo de prueba',
        );
      case 'active':
        return _t(nl: 'Actief', en: 'Active', fr: 'Actif', es: 'Activo');
      case 'past_due':
        return _t(
          nl: 'Betaling vereist',
          en: 'Payment required',
          fr: 'Paiement requis',
          es: 'Pago requerido',
        );
      case 'cancelled':
      case 'canceled':
        return _t(
          nl: 'Geannuleerd',
          en: 'Cancelled',
          fr: 'Annulé',
          es: 'Cancelado',
        );
      case 'inactive':
        return _t(
          nl: 'Inactief',
          en: 'Inactive',
          fr: 'Inactif',
          es: 'Inactivo',
        );
      case 'suspended':
        return _t(
          nl: 'Opgeschort',
          en: 'Suspended',
          fr: 'Suspendu',
          es: 'Suspendido',
        );
      default:
        return status.trim().isEmpty
            ? _t(
                nl: 'Onbekend',
                en: 'Unknown',
                fr: 'Inconnu',
                es: 'Desconocido',
              )
            : status.trim();
    }
  }

  ({Color bg, Color border, Color text}) _statusColors(String statusRaw) {
    final status = statusRaw.trim().toLowerCase();
    if (status == 'active') {
      return (
        bg: _green.withOpacity(0.14),
        border: _green.withOpacity(0.58),
        text: _green,
      );
    }
    if (status == 'trialing' || status == 'trial' || status == 'trial_active') {
      return (
        bg: _gold.withOpacity(0.15),
        border: _gold.withOpacity(0.48),
        text: _gold,
      );
    }
    if (status == 'past_due' || status == 'suspended') {
      return (
        bg: _warn.withOpacity(0.15),
        border: _warn.withOpacity(0.50),
        text: _warn,
      );
    }
    return (bg: Colors.white10, border: Colors.white24, text: Colors.white70);
  }

  String _featureLabel(String rawKey) {
    switch (rawKey.trim().toLowerCase()) {
      case 'ai_assistant':
        return _t(
          nl: 'AI assistent',
          en: 'AI assistant',
          fr: 'Assistant IA',
          es: 'Asistente de IA',
        );
      case 'airport_module':
        return _t(
          nl: 'Luchthavenmodule',
          en: 'Airport module',
          fr: 'Module aeroport',
          es: 'Modulo aeropuerto',
        );
      case 'live_dispatch':
        return _t(
          nl: 'Live dispatch',
          en: 'Live dispatch',
          fr: 'Dispatch en direct',
          es: 'Despacho en vivo',
        );
      case 'ev_dispatch':
        return _t(
          nl: 'EV-dispatch',
          en: 'EV dispatch',
          fr: 'Dispatch EV',
          es: 'Despacho EV',
        );
      case 'compliance_dashboard':
        return _t(
          nl: 'Complianceoverzicht',
          en: 'Compliance dashboard',
          fr: 'Tableau de conformité',
          es: 'Panel de cumplimiento',
        );
      case 'receipt_pdf':
        return _t(
          nl: 'PDF-ritbonnen',
          en: 'PDF receipts',
          fr: 'Reçus PDF',
          es: 'Recibos PDF',
        );
      case 'whatsapp_email_receipts':
        return _t(
          nl: 'WhatsApp/e-mail ritbonnen',
          en: 'WhatsApp/email receipts',
          fr: 'Reçus WhatsApp/e-mail',
          es: 'Recibos por WhatsApp/e-mail',
        );
      default:
        final normalized = rawKey
            .trim()
            .replaceAll('_', ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .toLowerCase();
        if (normalized.isEmpty) {
          return _t(
            nl: 'Onbekend',
            en: 'Unknown',
            fr: 'Inconnu',
            es: 'Desconocido',
          );
        }
        final words = normalized.split(' ');
        return words
            .map(
              (w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}',
            )
            .join(' ');
    }
  }

  String _addonActionLabel() {
    return _t(
      nl: 'Via beheer activeren',
      en: 'Activate via management',
      fr: 'Activer via gestion',
      es: 'Activar desde gestion',
    );
  }

  String _addonAvailableLabel() {
    return _t(
      nl: 'Beschikbaar als add-on',
      en: 'Available as add-on',
      fr: 'Disponible comme option',
      es: 'Disponible como complemento',
    );
  }

  Widget _chip({
    required String text,
    required Color bg,
    required Color border,
    required Color textColor,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: textColor),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _infoLine(String label, String value, {IconData? icon}) {
    final shown = value.trim().isEmpty ? '—' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: _gold.withOpacity(0.92)),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.white70, fontSize: 12.4),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(color: Colors.white.withOpacity(0.62)),
                  ),
                  TextSpan(
                    text: shown,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moduleRow({
    required String label,
    required bool active,
    String? subtitle,
    String? priceLabel,
    String? inactiveLabel,
  }) {
    final statusText = active
        ? _t(nl: 'Actief', en: 'Active', fr: 'Actif', es: 'Activo')
        : (inactiveLabel ?? _addonAvailableLabel());
    final statusBg = active
        ? _green.withOpacity(0.14)
        : _gold.withOpacity(0.13);
    final statusBorder = active
        ? _green.withOpacity(0.52)
        : _gold.withOpacity(0.42);
    final statusColor = active ? _green : _gold;
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? _green.withOpacity(0.42) : _gold.withOpacity(0.28),
        ),
      ),
      // Keep status/price chips below the title to avoid narrow-phone clipping.
      // This prevents fragmented wrapping like "AI-assi / stent".
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? _green.withOpacity(0.15)
                      : _gold.withOpacity(0.15),
                  border: Border.all(
                    color: active
                        ? _green.withOpacity(0.50)
                        : _gold.withOpacity(0.45),
                  ),
                ),
                child: Icon(
                  active ? Icons.check : Icons.add_circle_outline,
                  size: 13,
                  color: active ? _green : _gold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((subtitle ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                text: statusText,
                bg: statusBg,
                border: statusBorder,
                textColor: statusColor,
              ),
              if ((priceLabel ?? '').trim().isNotEmpty)
                _chip(
                  text: priceLabel!,
                  bg: _gold.withOpacity(0.13),
                  border: _gold.withOpacity(0.40),
                  textColor: _gold,
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddonInfo() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Activeren en facturatie verlopen via beheer.',
            en: 'Activation and billing are handled through management.',
            fr: 'L activation et la facturation passent par la gestion.',
            es: 'La activacion y la facturacion se gestionan desde administracion.',
          ),
        ),
      ),
    );
  }

  Widget _addonCard({
    required String title,
    required String price,
    required String subtitle,
    bool emphasized = false,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: emphasized ? _gold.withOpacity(0.52) : _gold.withOpacity(0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12.8,
            ),
          ),
          const SizedBox(height: 5),
          _chip(
            text: price,
            bg: _gold.withOpacity(0.14),
            border: _gold.withOpacity(0.5),
            textColor: _gold,
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white60, fontSize: 11.7),
          ),
          const SizedBox(height: 7),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: _showAddonInfo,
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold.withOpacity(0.98),
                side: BorderSide(color: _gold.withOpacity(0.40)),
                backgroundColor: _panel,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: Text(_addonActionLabel()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _usageCard({
    required String title,
    required int used,
    required int max,
    required String actionLabel,
  }) {
    final atOrOverLimit = max > 0 && used >= max;
    final accent = atOrOverLimit ? _warn : _green;
    final progress = max <= 0 ? 0.0 : (used / max).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.8,
                  ),
                ),
              ),
              _chip(
                text: '$used / $max',
                bg: accent.withOpacity(0.14),
                border: accent.withOpacity(0.50),
                textColor: accent,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          if (atOrOverLimit) ...[
            const SizedBox(height: 7),
            _chip(
              text: actionLabel,
              bg: _warn.withOpacity(0.15),
              border: _warn.withOpacity(0.50),
              textColor: _warn,
              icon: Icons.warning_amber_outlined,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              height: 26,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _t(
                    nl: 'Abonnement & facturatie',
                    en: 'Subscription & billing',
                    fr: 'Abonnement & facturation',
                    es: 'Suscripción y facturación',
                  ),
                  maxLines: 1,
                ),
              ),
            );
          },
        ),
      ),
      body: FutureBuilder<BackendSubscriptionProfile>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _t(
                    nl: 'Abonnementsgegevens konden niet worden geladen.',
                    en: 'Subscription data could not be loaded.',
                    fr: 'Les données d abonnement n ont pas pu être chargées.',
                    es: 'No se pudieron cargar los datos de suscripción.',
                  ),
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final profile = snap.data ?? BackendSubscriptionProfile.defaults();
          final statusColors = _statusColors(profile.status);
          final trialRange =
              '${profile.trialStartedAt.trim().isEmpty ? "—" : profile.trialStartedAt.trim()} / ${profile.trialEndsAt.trim().isEmpty ? "—" : profile.trialEndsAt.trim()}';
          return ValueListenableBuilder<List<VehicleProfile>>(
            valueListenable: vehiclesNotifier,
            builder: (context, vehicles, _) {
              final scopedVehicles = vehicles
                  .where(
                    (v) =>
                        fleetRecordBelongsToActiveCompanyOrLegacy(v.companyId),
                  )
                  .toList(growable: false);
              return ValueListenableBuilder<List<DriverProfile>>(
                valueListenable: driversNotifier,
                builder: (context, drivers, __) {
                  final scopedDrivers = drivers
                      .where(
                        (d) => fleetRecordBelongsToActiveCompanyOrLegacy(
                          d.companyId,
                        ),
                      )
                      .toList(growable: false);
                  final usedVehicles = scopedVehicles.length;
                  final usedDrivers = scopedDrivers.length;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                    children: [
                      _sectionCard(
                        title: _t(
                          nl: 'Huidig abonnement',
                          en: 'Current subscription',
                          fr: 'Abonnement actuel',
                          es: 'Suscripcion actual',
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _t(
                                          nl: 'Fluxidi Platform',
                                          en: 'Fluxidi Platform',
                                          fr: 'Fluxidi Platform',
                                          es: 'Fluxidi Platform',
                                        ),
                                        style: TextStyle(
                                          color: _gold,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _planLabel(profile.plan),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _chip(
                                  text: _statusLabel(profile.status),
                                  bg: statusColors.bg,
                                  border: statusColors.border,
                                  textColor: statusColors.text,
                                  icon: Icons.verified_outlined,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _chip(
                              text: _t(
                                nl: '€49 / maand · planweergave',
                                en: '€49 / month · plan display copy',
                                fr: '€49 / mois · affichage du plan',
                                es: '€49 / mes · copia visual del plan',
                              ),
                              bg: _gold.withOpacity(0.12),
                              border: _gold.withOpacity(0.40),
                              textColor: _gold,
                              icon: Icons.sell_outlined,
                            ),
                            const SizedBox(height: 8),
                            _infoLine(
                              _t(
                                nl: 'Facturatie-email',
                                en: 'Billing email',
                                fr: 'E-mail de facturation',
                                es: 'Correo de facturacion',
                              ),
                              profile.billingEmail,
                              icon: Icons.email_outlined,
                            ),
                            _infoLine(
                              _t(
                                nl: 'Proefperiode start/einde',
                                en: 'Trial start/end',
                                fr: 'Debut/fin essai',
                                es: 'Inicio/fin de prueba',
                              ),
                              trialRange,
                              icon: Icons.schedule_outlined,
                            ),
                            const SizedBox(height: 5),
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: [
                                _chip(
                                  text:
                                      '${profile.includedVehicles} ${_t(nl: "voertuig inbegrepen", en: "vehicle included", fr: "vehicule inclus", es: "vehiculo incluido")}',
                                  bg: _green.withOpacity(0.14),
                                  border: _green.withOpacity(0.45),
                                  textColor: _green,
                                  icon: Icons.check_circle_outline,
                                ),
                                _chip(
                                  text: _t(
                                    nl: '1 chauffeur inbegrepen',
                                    en: '1 driver included',
                                    fr: '1 chauffeur inclus',
                                    es: '1 conductor incluido',
                                  ),
                                  bg: _green.withOpacity(0.14),
                                  border: _green.withOpacity(0.45),
                                  textColor: _green,
                                  icon: Icons.check_circle_outline,
                                ),
                                _chip(
                                  text: _t(
                                    nl: '200 PDF-creaties per voertuig / maand',
                                    en: '200 PDF creations per vehicle / month',
                                    fr: '200 creations PDF par vehicule / mois',
                                    es: '200 creaciones PDF por vehiculo / mes',
                                  ),
                                  bg: _gold.withOpacity(0.13),
                                  border: _gold.withOpacity(0.40),
                                  textColor: _gold,
                                ),
                                _chip(
                                  text: _t(
                                    nl: 'Chiron-ready',
                                    en: 'Chiron-ready',
                                    fr: 'Chiron-ready',
                                    es: 'Chiron-ready',
                                  ),
                                  bg: _green.withOpacity(0.14),
                                  border: _green.withOpacity(0.45),
                                  textColor: _green,
                                ),
                                _chip(
                                  text: _t(
                                    nl: 'Peppol-ready structuur inbegrepen',
                                    en: 'Peppol-ready structure included',
                                    fr: 'Structure Peppol-ready incluse',
                                    es: 'Estructura Peppol-ready incluida',
                                  ),
                                  bg: _gold.withOpacity(0.13),
                                  border: _gold.withOpacity(0.40),
                                  textColor: _gold,
                                ),
                                _chip(
                                  text: _t(
                                    nl: 'Peppol-verzending via betaalde add-on',
                                    en: 'Peppol sending via paid add-on',
                                    fr: 'Envoi Peppol via option payante',
                                    es: 'Envio Peppol via complemento de pago',
                                  ),
                                  bg: _warn.withOpacity(0.14),
                                  border: _warn.withOpacity(0.44),
                                  textColor: _warn,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _sectionCard(
                        title: _t(
                          nl: 'Gebruik & limieten',
                          en: 'Usage & limits',
                          fr: 'Utilisation et limites',
                          es: 'Uso y limites',
                        ),
                        child: Column(
                          children: [
                            _usageCard(
                              title: _t(
                                nl: 'Voertuigen',
                                en: 'Vehicles',
                                fr: 'Vehicules',
                                es: 'Vehiculos',
                              ),
                              used: usedVehicles,
                              max: profile.maxVehicles,
                              actionLabel: _t(
                                nl: 'Extra voertuig activeren',
                                en: 'Activate extra vehicle',
                                fr: 'Activer un vehicule supplementaire',
                                es: 'Activar vehiculo extra',
                              ),
                            ),
                            const SizedBox(height: 8),
                            _usageCard(
                              title: _t(
                                nl: 'Chauffeurs',
                                en: 'Drivers',
                                fr: 'Chauffeurs',
                                es: 'Conductores',
                              ),
                              used: usedDrivers,
                              max: profile.maxDrivers,
                              actionLabel: _t(
                                nl: 'Extra chauffeur activeren',
                                en: 'Activate extra driver',
                                fr: 'Activer un chauffeur supplementaire',
                                es: 'Activar conductor extra',
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                              decoration: BoxDecoration(
                                color: _panelSoft,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _gold.withOpacity(0.30),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _t(
                                      nl: 'PDF-creaties',
                                      en: 'PDF creations',
                                      fr: 'Creations PDF',
                                      es: 'Creaciones PDF',
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.8,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _t(
                                      nl: 'Limiet: 200 per voertuig / maand',
                                      en: 'Limit: 200 per vehicle / month',
                                      fr: 'Limite : 200 par vehicule / mois',
                                      es: 'Limite: 200 por vehiculo / mes',
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12.1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _t(
                                      nl: 'Verbruik nog niet gekoppeld',
                                      en: 'Usage is not linked yet',
                                      fr: 'La consommation n est pas encore reliee',
                                      es: 'El consumo aun no esta vinculado',
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 11.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                              decoration: BoxDecoration(
                                color: _panelSoft,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _gold.withOpacity(0.30),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _t(
                                      nl: 'Peppol',
                                      en: 'Peppol',
                                      fr: 'Peppol',
                                      es: 'Peppol',
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.8,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      _chip(
                                        text: _t(
                                          nl: 'Niet actief',
                                          en: 'Not active',
                                          fr: 'Inactif',
                                          es: 'No activo',
                                        ),
                                        bg: Colors.white10,
                                        border: Colors.white24,
                                        textColor: Colors.white70,
                                      ),
                                      _chip(
                                        text: _t(
                                          nl: 'Beschikbaar als betaalde add-on',
                                          en: 'Available as paid add-on',
                                          fr: 'Disponible comme option payante',
                                          es: 'Disponible como complemento de pago',
                                        ),
                                        bg: _gold.withOpacity(0.13),
                                        border: _gold.withOpacity(0.40),
                                        textColor: _gold,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      _sectionCard(
                        title: _t(
                          nl: 'Betaalde uitbreidingen',
                          en: 'Paid add-ons',
                          fr: 'Extensions payantes',
                          es: 'Ampliaciones de pago',
                        ),
                        child: Column(
                          children: [
                            _addonCard(
                              title: _t(
                                nl: 'Extra voertuig',
                                en: 'Extra vehicle',
                                fr: 'Vehicule supplementaire',
                                es: 'Vehiculo extra',
                              ),
                              price: '+ €19 / maand',
                              subtitle: _addonAvailableLabel(),
                              emphasized: usedVehicles >= profile.maxVehicles,
                            ),
                            const SizedBox(height: 7),
                            _addonCard(
                              title: _t(
                                nl: 'Extra chauffeur',
                                en: 'Extra driver',
                                fr: 'Chauffeur supplementaire',
                                es: 'Conductor extra',
                              ),
                              price: '+ €9 / maand',
                              subtitle: _addonAvailableLabel(),
                              emphasized: usedDrivers >= profile.maxDrivers,
                            ),
                            const SizedBox(height: 7),
                            _addonCard(
                              title: _t(
                                nl: 'Peppol verzending',
                                en: 'Peppol sending',
                                fr: 'Envoi Peppol',
                                es: 'Envio Peppol',
                              ),
                              price: _t(
                                nl: 'betaalde add-on',
                                en: 'paid add-on',
                                fr: 'option payante',
                                es: 'complemento de pago',
                              ),
                              subtitle: _t(
                                nl: 'Per document of via bundel',
                                en: 'Per document or via bundle',
                                fr: 'Par document ou via lot',
                                es: 'Por documento o por paquete',
                              ),
                            ),
                            const SizedBox(height: 7),
                            _addonCard(
                              title: _t(
                                nl: 'Extra 500 PDF’s',
                                en: 'Extra 500 PDFs',
                                fr: '500 PDF supplementaires',
                                es: '500 PDF extra',
                              ),
                              price: '€5',
                              subtitle: _addonAvailableLabel(),
                            ),
                            const SizedBox(height: 7),
                            _addonCard(
                              title: _t(
                                nl: 'Extra 1.000 PDF’s',
                                en: 'Extra 1,000 PDFs',
                                fr: '1 000 PDF supplementaires',
                                es: '1.000 PDF extra',
                              ),
                              price: '€9',
                              subtitle: _addonAvailableLabel(),
                            ),
                            const SizedBox(height: 7),
                            _addonCard(
                              title: _t(
                                nl: 'Extra 5.000 PDF’s',
                                en: 'Extra 5,000 PDFs',
                                fr: '5 000 PDF supplementaires',
                                es: '5.000 PDF extra',
                              ),
                              price: '€29',
                              subtitle: _addonAvailableLabel(),
                            ),
                          ],
                        ),
                      ),
                      _sectionCard(
                        title: _t(
                          nl: 'Inbegrepen platformmogelijkheden',
                          en: 'Included platform capabilities',
                          fr: 'Fonctionnalités de plateforme incluses',
                          es: 'Capacidades de plataforma incluidas',
                        ),
                        child: Column(
                          children: [
                            _moduleRow(
                              label: _t(
                                nl: 'Eigen bedrijfsbranding / white-label basis',
                                en: 'Company branding / white-label base',
                                fr: 'Branding entreprise / base marque blanche',
                                es: 'Marca empresarial / base white-label',
                              ),
                              active:
                                  profile.features['white_label_branding'] ==
                                  true,
                              inactiveLabel: _t(
                                nl: 'Platformmogelijkheid',
                                en: 'Platform capability',
                                fr: 'Capacité plateforme',
                                es: 'Capacidad de plataforma',
                              ),
                              subtitle: _t(
                                nl: 'Onderdeel van Fluxidi Platform',
                                en: 'Part of Fluxidi Platform',
                                fr: 'Fait partie de Fluxidi Platform',
                                es: 'Parte de Fluxidi Platform',
                              ),
                            ),
                            _moduleRow(
                              label: _t(
                                nl: 'Online boekingsflow',
                                en: 'Online booking flow',
                                fr: 'Flux de réservation en ligne',
                                es: 'Flujo de reserva en línea',
                              ),
                              active:
                                  profile.features['public_booking'] == true,
                              inactiveLabel: _t(
                                nl: 'Platformmogelijkheid',
                                en: 'Platform capability',
                                fr: 'Capacité plateforme',
                                es: 'Capacidad de plataforma',
                              ),
                              subtitle: _t(
                                nl: 'Beschikbaar binnen het platformprofiel',
                                en: 'Available within the platform profile',
                                fr: 'Disponible dans le profil plateforme',
                                es: 'Disponible en el perfil de plataforma',
                              ),
                            ),
                            _moduleRow(
                              label: _t(
                                nl: 'PDF-ritbonnen met limieten',
                                en: 'PDF receipts with limits',
                                fr: 'Reçus PDF avec limites',
                                es: 'Recibos PDF con límites',
                              ),
                              active: profile.features['receipt_pdf'] == true,
                              inactiveLabel: _t(
                                nl: 'Platformmogelijkheid',
                                en: 'Platform capability',
                                fr: 'Capacité plateforme',
                                es: 'Capacidad de plataforma',
                              ),
                            ),
                            _moduleRow(
                              label: _t(
                                nl: 'WhatsApp/e-mail ritbonnen',
                                en: 'WhatsApp/email receipts',
                                fr: 'Reçus WhatsApp/e-mail',
                                es: 'Recibos por WhatsApp/correo',
                              ),
                              active:
                                  profile.features['whatsapp_email_receipts'] ==
                                  true,
                              inactiveLabel: _t(
                                nl: 'Platformmogelijkheid',
                                en: 'Platform capability',
                                fr: 'Capacité plateforme',
                                es: 'Capacidad de plataforma',
                              ),
                            ),
                            _moduleRow(
                              label: _t(
                                nl: 'Complianceoverzicht / Chiron-ready',
                                en: 'Compliance dashboard / Chiron-ready',
                                fr: 'Tableau conformité / Chiron-ready',
                                es: 'Panel de cumplimiento / Chiron-ready',
                              ),
                              active:
                                  profile.features['compliance_dashboard'] ==
                                  true,
                              inactiveLabel: _t(
                                nl: 'Platformmogelijkheid',
                                en: 'Platform capability',
                                fr: 'Capacité plateforme',
                                es: 'Capacidad de plataforma',
                              ),
                            ),
                            _moduleRow(
                              label: _t(
                                nl: 'Peppol-ready structuur',
                                en: 'Peppol-ready structure',
                                fr: 'Structure Peppol-ready',
                                es: 'Estructura Peppol-ready',
                              ),
                              active: true,
                              subtitle: _t(
                                nl: 'Inbegrepen als platformcapaciteit',
                                en: 'Included as platform capability',
                                fr: 'Inclus comme capacité plateforme',
                                es: 'Incluido como capacidad de plataforma',
                              ),
                            ),
                          ],
                        ),
                      ),
                      _sectionCard(
                        title: _t(
                          nl: 'Platformmodules',
                          en: 'Platform modules',
                          fr: 'Modules de plateforme',
                          es: 'Módulos de plataforma',
                        ),
                        child: Column(
                          children: [
                            _moduleRow(
                              label: _featureLabel('ai_assistant'),
                              active: profile.features['ai_assistant'] == true,
                              inactiveLabel: _t(
                                nl: 'Platformmodule',
                                en: 'Platform module',
                                fr: 'Module de plateforme',
                                es: 'Módulo de plataforma',
                              ),
                              subtitle: _t(
                                nl: 'Inbegrepen',
                                en: 'Included',
                                fr: 'Inclus',
                                es: 'Incluido',
                              ),
                            ),
                            _moduleRow(
                              label: _featureLabel('airport_module'),
                              active:
                                  profile.features['airport_module'] == true,
                              inactiveLabel: _t(
                                nl: 'Platformmodule',
                                en: 'Platform module',
                                fr: 'Module de plateforme',
                                es: 'Módulo de plataforma',
                              ),
                              subtitle: _t(
                                nl: 'Inbegrepen',
                                en: 'Included',
                                fr: 'Inclus',
                                es: 'Incluido',
                              ),
                            ),
                            _moduleRow(
                              label: _featureLabel('live_dispatch'),
                              active: profile.features['live_dispatch'] == true,
                              inactiveLabel: _t(
                                nl: 'Platformmodule',
                                en: 'Platform module',
                                fr: 'Module de plateforme',
                                es: 'Módulo de plataforma',
                              ),
                              subtitle: _t(
                                nl: 'Inbegrepen',
                                en: 'Included',
                                fr: 'Inclus',
                                es: 'Incluido',
                              ),
                            ),
                            _moduleRow(
                              label: _featureLabel('ev_dispatch'),
                              active: profile.features['ev_dispatch'] == true,
                              inactiveLabel: _t(
                                nl: 'Premium add-on',
                                en: 'Premium add-on',
                                fr: 'Option premium',
                                es: 'Complemento premium',
                              ),
                              subtitle: _t(
                                nl: 'Premium module',
                                en: 'Premium module',
                                fr: 'Module premium',
                                es: 'Módulo premium',
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: _panel,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _gold.withOpacity(0.24)),
                        ),
                        child: Text(
                          _t(
                            nl: 'In deze fase worden limieten en uitbreidingen weergegeven. Activeren en facturatie volgen via beheer.',
                            en: 'At this stage, limits and add-ons are shown for transparency. Activation and billing are handled through management.',
                            fr: 'À ce stade, les limites et options sont affichées à titre informatif. L’activation et la facturation passent par la gestion.',
                            es: 'En esta fase, los limites y complementos se muestran de forma informativa. La activacion y la facturacion se gestionan desde administracion.',
                          ),
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
