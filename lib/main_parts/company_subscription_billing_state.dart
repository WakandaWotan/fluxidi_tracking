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
  static const Color _warn = Color(0xFFFFB457);

  /// Format an integer-cents price as "€XX" (no decimals when round, "€X.YY"
  /// otherwise). Currency is always shown as € for now; the catalog currency
  /// field would be consulted here if non-EUR markets are ever added.
  String _priceFromCents(int cents) {
    if (cents % 100 == 0) return '€${cents ~/ 100}';
    final whole = cents ~/ 100;
    final fraction = (cents % 100).toString().padLeft(2, '0');
    return '€$whole.$fraction';
  }

  String _planDisplayName(BackendSubscriptionProfile profile) {
    final code = profile.planCode.trim().toLowerCase();
    if (code == 'fluxidi_pro' || code.isEmpty) return 'Fluxidi Pro';
    // Legacy plan values keep their old display.
    return _planLabel(profile.plan);
  }

  BusinessThemePalette get _businessThemePalette =>
      paletteForBusinessTheme(businessThemeNotifier.value);
  Color get _bg => _businessThemePalette.background;
  Color get _panel => _businessThemePalette.surface;
  Color get _panelSoft => _businessThemePalette.surfaceAlt;
  Color get _gold => _businessThemePalette.accent;
  Color get _green => _businessThemePalette.success;

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

  String? _activeCompanyId() {
    final fromProfile = companyProfileNotifier.value?.companyId.trim() ?? '';
    if (fromProfile.isNotEmpty) return fromProfile;
    final fromSession =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (fromSession.isNotEmpty) return fromSession;
    return null;
  }

  Future<BackendSubscriptionProfile> _fetch() async {
    final scopeId = _activeCompanyId();
    if (scopeId == null || scopeId.trim().isEmpty) {
      debugPrint(
        '[SUBSCRIPTION_SCOPE][SKIP] reason=missing_strict_company_scope action=fetch_subscription_profile',
      );
      return BackendSubscriptionProfile.defaults();
    }
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
    return (
      bg: _businessThemePalette.surfaceAlt.withOpacity(
        _businessThemePalette.isDark ? 0.72 : 0.9,
      ),
      border: _businessThemePalette.border.withOpacity(0.7),
      text: _businessThemePalette.textMuted,
    );
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
            style: TextStyle(
              color: _businessThemePalette.textPrimary,
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
                style: TextStyle(
                  color: _businessThemePalette.textMuted,
                  fontSize: 12.4,
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                      color: _businessThemePalette.textMuted.withOpacity(0.84),
                    ),
                  ),
                  TextSpan(
                    text: shown,
                    style: TextStyle(
                      color: _businessThemePalette.textPrimary,
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
    bool comingSoon = false,
  }) {
    // Coming-soon modules use a neutral grey accent so users do not confuse
    // them with "Actief" (green) or paid add-ons (gold). When comingSoon is
    // true the `active` flag is forced to false and the inactiveLabel is the
    // visible badge text.
    final neutralColor = _businessThemePalette.textMuted;
    final neutralBg = _businessThemePalette.surfaceAlt.withOpacity(
      _businessThemePalette.isDark ? 0.66 : 0.92,
    );
    final neutralBorder = _businessThemePalette.border.withOpacity(
      _businessThemePalette.isDark ? 0.52 : 0.78,
    );
    final effectiveActive = comingSoon ? false : active;
    final statusText = comingSoon
        ? (inactiveLabel ??
              _t(
                nl: 'Binnenkort',
                en: 'Coming soon',
                fr: 'Bientôt',
                es: 'Próximamente',
              ))
        : (effectiveActive
              ? _t(nl: 'Actief', en: 'Active', fr: 'Actif', es: 'Activo')
              : (inactiveLabel ?? _addonAvailableLabel()));
    final statusBg = comingSoon
        ? neutralBg
        : (effectiveActive
              ? _green.withOpacity(0.14)
              : _gold.withOpacity(0.13));
    final statusBorder = comingSoon
        ? neutralBorder
        : (effectiveActive
              ? _green.withOpacity(0.52)
              : _gold.withOpacity(0.42));
    final statusColor = comingSoon
        ? neutralColor
        : (effectiveActive ? _green : _gold);
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: comingSoon
              ? neutralBorder
              : (effectiveActive
                    ? _green.withOpacity(0.42)
                    : _gold.withOpacity(0.28)),
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
                  color: comingSoon
                      ? neutralColor.withOpacity(0.15)
                      : (effectiveActive
                            ? _green.withOpacity(0.15)
                            : _gold.withOpacity(0.15)),
                  border: Border.all(
                    color: comingSoon
                        ? neutralColor.withOpacity(0.45)
                        : (effectiveActive
                              ? _green.withOpacity(0.50)
                              : _gold.withOpacity(0.45)),
                  ),
                ),
                child: Icon(
                  comingSoon
                      ? Icons.schedule_outlined
                      : (effectiveActive
                            ? Icons.check
                            : Icons.add_circle_outline),
                  size: 13,
                  color: comingSoon
                      ? neutralColor
                      : (effectiveActive ? _green : _gold),
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
                      style: TextStyle(
                        color: _businessThemePalette.textPrimary,
                        fontSize: 12.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((subtitle ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: _businessThemePalette.textMuted,
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
            nl: 'Na je proefperiode ontvang je automatisch een melding om je abonnement te activeren en verder gebruik te maken van Fluxidi.',
            en: 'After your trial, you\'ll automatically receive a prompt to activate your subscription and keep using Fluxidi.',
            fr: 'Après votre période d\'essai, vous recevrez automatiquement une invitation à activer votre abonnement et à continuer à utiliser Fluxidi.',
            es: 'Después de tu prueba, recibirás automáticamente un aviso para activar tu suscripción y seguir usando Fluxidi.',
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
            style: TextStyle(
              color: _businessThemePalette.textPrimary,
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
            style: TextStyle(
              color: _businessThemePalette.textMuted,
              fontSize: 11.7,
            ),
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
                  style: TextStyle(
                    color: _businessThemePalette.textPrimary,
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
              backgroundColor: _businessThemePalette.border.withOpacity(
                _businessThemePalette.isDark ? 0.30 : 0.55,
              ),
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
    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: _businessThemePalette.textPrimary,
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
                    style: TextStyle(color: _businessThemePalette.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final profile = snap.data ?? BackendSubscriptionProfile.defaults();
            final statusColors = _statusColors(profile.status);
            final trialRange =
                '${profile.trialStartedAt.trim().isEmpty ? "—" : profile.trialStartedAt.trim()} / ${profile.trialEndsAt.trim().isEmpty ? "—" : profile.trialEndsAt.trim()}';
            // Country-aware catalog drives all visible pricing copy. If the
            // backend profile didn't ship catalog fields the resolver fills
            // in BE/NL/FR/ES/PT defaults from the active company's market.
            final catalog = resolveSubscriptionCatalogEntryForMarket(
              profile.market.trim().isNotEmpty
                  ? profile.market
                  : resolveActiveCompanyPricingMarket(),
            );
            final normalPriceText = _priceFromCents(catalog.normalPriceCents);
            final founderPriceText = catalog.founderPriceCents != null
                ? _priceFromCents(catalog.founderPriceCents!)
                : '';
            final hasFounderOffer =
                catalog.founderPriceCents != null &&
                catalog.founderSlotsLimit != null;
            return ValueListenableBuilder<List<VehicleProfile>>(
              valueListenable: vehiclesNotifier,
              builder: (context, vehicles, _) {
                final scopedVehicles = vehicles
                    .where(
                      (v) => fleetRecordBelongsToActiveCompanyOrLegacy(
                        v.companyId,
                      ),
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
                                          _planDisplayName(profile),
                                          style: TextStyle(
                                            color: _businessThemePalette
                                                .textPrimary,
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
                                  nl: '$normalPriceText / maand excl. btw',
                                  en: '$normalPriceText / month excl. VAT',
                                  fr: '$normalPriceText / mois HT',
                                  es: '$normalPriceText / mes sin IVA',
                                ),
                                bg: _gold.withOpacity(0.12),
                                border: _gold.withOpacity(0.40),
                                textColor: _gold,
                                icon: Icons.sell_outlined,
                              ),
                              if (hasFounderOffer) ...[
                                const SizedBox(height: 6),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    8,
                                    10,
                                    8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _gold.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _gold.withOpacity(0.45),
                                    ),
                                  ),
                                  child: Text(
                                    _t(
                                      nl: 'Eerste ${catalog.founderSlotsLimit} bedrijven: $founderPriceText/maand excl. btw zolang het abonnement actief blijft. Daarna normale prijs: $normalPriceText/maand.',
                                      en: 'First ${catalog.founderSlotsLimit} companies: $founderPriceText/month excl. VAT for as long as the subscription stays active. Normal price afterwards: $normalPriceText/month.',
                                      fr: 'Premières ${catalog.founderSlotsLimit} entreprises : $founderPriceText/mois HT tant que l\'abonnement reste actif. Prix normal ensuite : $normalPriceText/mois.',
                                      es: 'Primeras ${catalog.founderSlotsLimit} empresas: $founderPriceText/mes sin IVA mientras la suscripción siga activa. Precio normal después: $normalPriceText/mes.',
                                    ),
                                    style: TextStyle(
                                      color: _gold,
                                      fontSize: 11.8,
                                      fontWeight: FontWeight.w700,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              // Visible trial copy is intentionally expressed in
                              // weeks ("2 weken / 2 weeks") even though the
                              // catalog keeps trialDays = 14 internally. Do not
                              // surface the day count in the UI.
                              _chip(
                                text: _t(
                                  nl: '2 weken gratis proefperiode',
                                  en: '2 weeks free trial',
                                  fr: '2 semaines d\'essai gratuit',
                                  es: '2 semanas de prueba gratis',
                                ),
                                bg: _green.withOpacity(0.14),
                                border: _green.withOpacity(0.48),
                                textColor: _green,
                                icon: Icons.schedule_outlined,
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
                                        '${catalog.includedVehicleCount} ${_t(nl: "voertuig inbegrepen", en: "vehicle included", fr: "vehicule inclus", es: "vehiculo incluido")}',
                                    bg: _green.withOpacity(0.14),
                                    border: _green.withOpacity(0.45),
                                    textColor: _green,
                                    icon: Icons.check_circle_outline,
                                  ),
                                  _chip(
                                    text: _t(
                                      nl: '${catalog.includedDriversPerVehicle} chauffeurs per voertuig inbegrepen',
                                      en: '${catalog.includedDriversPerVehicle} drivers per vehicle included',
                                      fr: '${catalog.includedDriversPerVehicle} chauffeurs par véhicule inclus',
                                      es: '${catalog.includedDriversPerVehicle} conductores por vehículo incluidos',
                                    ),
                                    bg: _green.withOpacity(0.14),
                                    border: _green.withOpacity(0.45),
                                    textColor: _green,
                                    icon: Icons.check_circle_outline,
                                  ),
                                  _chip(
                                    text: _t(
                                      nl: '${catalog.includedPdfCreationsPerVehicleMonth} PDF-creaties per voertuig / maand',
                                      en: '${catalog.includedPdfCreationsPerVehicleMonth} PDF creations per vehicle / month',
                                      fr: '${catalog.includedPdfCreationsPerVehicleMonth} créations PDF par véhicule / mois',
                                      es: '${catalog.includedPdfCreationsPerVehicleMonth} creaciones PDF por vehículo / mes',
                                    ),
                                    bg: _gold.withOpacity(0.13),
                                    border: _gold.withOpacity(0.40),
                                    textColor: _gold,
                                  ),
                                  _chip(
                                    text: _t(
                                      nl: 'Chiron-ready inbegrepen',
                                      en: 'Chiron-ready included',
                                      fr: 'Chiron-ready inclus',
                                      es: 'Chiron-ready incluido',
                                    ),
                                    bg: _green.withOpacity(0.14),
                                    border: _green.withOpacity(0.45),
                                    textColor: _green,
                                  ),
                                  _chip(
                                    text: _t(
                                      nl: 'Billit/Peppol-ready inbegrepen',
                                      en: 'Billit/Peppol-ready included',
                                      fr: 'Billit/Peppol-ready inclus',
                                      es: 'Billit/Peppol-ready incluido',
                                    ),
                                    bg: _green.withOpacity(0.14),
                                    border: _green.withOpacity(0.45),
                                    textColor: _green,
                                  ),
                                  _chip(
                                    text: _t(
                                      nl: 'Geen commissie op ritten',
                                      en: 'No commission on rides',
                                      fr: 'Aucune commission sur les courses',
                                      es: 'Sin comisión sobre los viajes',
                                    ),
                                    bg: _green.withOpacity(0.14),
                                    border: _green.withOpacity(0.45),
                                    textColor: _green,
                                    icon: Icons.do_not_disturb_on_outlined,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _t(
                                  nl: 'Externe Billit/providerkosten en Mollie-transactiekosten zijn voor rekening van het bedrijf en lopen via je eigen account.',
                                  en: 'External Billit/provider costs and Mollie transaction fees are paid by the company via its own account.',
                                  fr: 'Les frais Billit/fournisseur externes et les frais de transaction Mollie sont à la charge de l\'entreprise via son propre compte.',
                                  es: 'Los costes externos de Billit/proveedor y las comisiones de transacción de Mollie corren a cargo de la empresa a través de su propia cuenta.',
                                ),
                                style: TextStyle(
                                  color: _businessThemePalette.textMuted
                                      .withOpacity(0.88),
                                  fontSize: 11.6,
                                  height: 1.3,
                                ),
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
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  9,
                                  10,
                                  10,
                                ),
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
                                      style: TextStyle(
                                        color:
                                            _businessThemePalette.textPrimary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12.8,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      _t(
                                        nl: 'Limiet: ${catalog.includedPdfCreationsPerVehicleMonth} per voertuig / maand',
                                        en: 'Limit: ${catalog.includedPdfCreationsPerVehicleMonth} per vehicle / month',
                                        fr: 'Limite : ${catalog.includedPdfCreationsPerVehicleMonth} par véhicule / mois',
                                        es: 'Límite: ${catalog.includedPdfCreationsPerVehicleMonth} por vehículo / mes',
                                      ),
                                      style: TextStyle(
                                        color: _businessThemePalette.textMuted,
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
                                      style: TextStyle(
                                        color: _businessThemePalette.textMuted
                                            .withOpacity(0.86),
                                        fontSize: 11.8,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  9,
                                  10,
                                  10,
                                ),
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
                                      style: TextStyle(
                                        color:
                                            _businessThemePalette.textPrimary,
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
                                            nl: 'Billit/Peppol-ready inbegrepen',
                                            en: 'Billit/Peppol-ready included',
                                            fr: 'Billit/Peppol-ready inclus',
                                            es: 'Billit/Peppol-ready incluido',
                                          ),
                                          bg: _green.withOpacity(0.14),
                                          border: _green.withOpacity(0.45),
                                          textColor: _green,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      _t(
                                        nl: 'Externe Billit/providerkosten zijn voor rekening van het bedrijf en lopen via je eigen Billit-account.',
                                        en: 'External Billit/provider costs are paid by the company via its own Billit account.',
                                        fr: 'Les frais Billit/fournisseur externes sont à la charge de l\'entreprise via son propre compte Billit.',
                                        es: 'Los costes externos de Billit/proveedor corren a cargo de la empresa a través de su propia cuenta Billit.',
                                      ),
                                      style: TextStyle(
                                        color: _businessThemePalette.textMuted,
                                        fontSize: 11.6,
                                        height: 1.3,
                                      ),
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
                                  fr: 'Véhicule supplémentaire',
                                  es: 'Vehículo extra',
                                ),
                                price: _t(
                                  nl: '+ ${_priceFromCents(catalog.extraVehiclePriceCents)} / maand',
                                  en: '+ ${_priceFromCents(catalog.extraVehiclePriceCents)} / month',
                                  fr: '+ ${_priceFromCents(catalog.extraVehiclePriceCents)} / mois',
                                  es: '+ ${_priceFromCents(catalog.extraVehiclePriceCents)} / mes',
                                ),
                                subtitle: _t(
                                  nl: 'Inclusief ${catalog.includedDriversPerVehicle} extra chauffeurs en ${catalog.includedPdfCreationsPerVehicleMonth} extra PDF-creaties per maand.',
                                  en: 'Includes ${catalog.includedDriversPerVehicle} extra drivers and ${catalog.includedPdfCreationsPerVehicleMonth} extra PDF creations per month.',
                                  fr: 'Inclut ${catalog.includedDriversPerVehicle} chauffeurs supplémentaires et ${catalog.includedPdfCreationsPerVehicleMonth} créations PDF supplémentaires par mois.',
                                  es: 'Incluye ${catalog.includedDriversPerVehicle} conductores extra y ${catalog.includedPdfCreationsPerVehicleMonth} creaciones PDF extra al mes.',
                                ),
                                emphasized: usedVehicles >= profile.maxVehicles,
                              ),
                              const SizedBox(height: 7),
                              _addonCard(
                                title: _t(
                                  nl: 'Extra chauffeur',
                                  en: 'Extra driver',
                                  fr: 'Chauffeur supplémentaire',
                                  es: 'Conductor extra',
                                ),
                                price: _t(
                                  nl: '+ ${_priceFromCents(catalog.extraDriverPriceCents)} / maand',
                                  en: '+ ${_priceFromCents(catalog.extraDriverPriceCents)} / month',
                                  fr: '+ ${_priceFromCents(catalog.extraDriverPriceCents)} / mois',
                                  es: '+ ${_priceFromCents(catalog.extraDriverPriceCents)} / mes',
                                ),
                                subtitle: _addonAvailableLabel(),
                                emphasized: usedDrivers >= profile.maxDrivers,
                              ),
                              for (final bundle in catalog.pdfBundles) ...[
                                const SizedBox(height: 7),
                                _addonCard(
                                  title: _t(
                                    nl: 'Extra ${bundle.pdfs} PDF\u2019s',
                                    en: 'Extra ${bundle.pdfs} PDFs',
                                    fr: '${bundle.pdfs} PDF supplémentaires',
                                    es: '${bundle.pdfs} PDF extra',
                                  ),
                                  price: _priceFromCents(bundle.priceCents),
                                  subtitle: _addonAvailableLabel(),
                                ),
                              ],
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
                                    profile
                                        .features['whatsapp_email_receipts'] ==
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
                                  nl: 'Billit/Peppol-ready structuur',
                                  en: 'Billit/Peppol-ready structure',
                                  fr: 'Structure Billit/Peppol-ready',
                                  es: 'Estructura Billit/Peppol-ready',
                                ),
                                active: true,
                                subtitle: _t(
                                  nl: 'Inbegrepen. Externe Billit/providerkosten zijn voor rekening van het bedrijf.',
                                  en: 'Included. External Billit/provider costs are paid by the company.',
                                  fr: 'Inclus. Les frais Billit/fournisseur externes sont à la charge de l\'entreprise.',
                                  es: 'Incluido. Los costes externos de Billit/proveedor corren a cargo de la empresa.',
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
                                active:
                                    profile.features['ai_assistant'] == true,
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
                                // Live dispatch is not production-ready yet,
                                // so always display it as coming-soon (neutral
                                // styling) regardless of any feature flag.
                                active: false,
                                comingSoon: true,
                                inactiveLabel: _t(
                                  nl: 'Binnenkort',
                                  en: 'Coming soon',
                                  fr: 'Bientôt',
                                  es: 'Próximamente',
                                ),
                                subtitle: _t(
                                  nl: 'Binnenkort beschikbaar',
                                  en: 'Coming soon',
                                  fr: 'Bientôt disponible',
                                  es: 'Próximamente',
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
                              nl: 'Na je proefperiode ontvang je automatisch een melding om je abonnement te activeren en verder gebruik te maken van Fluxidi.',
                              en: 'After your trial, you\'ll automatically receive a prompt to activate your subscription and keep using Fluxidi.',
                              fr: 'Après votre période d\'essai, vous recevrez automatiquement une invitation à activer votre abonnement et à continuer à utiliser Fluxidi.',
                              es: 'Después de tu prueba, recibirás automáticamente un aviso para activar tu suscripción y seguir usando Fluxidi.',
                            ),
                            style: TextStyle(
                              color: _businessThemePalette.textMuted
                                  .withOpacity(0.88),
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
      ),
    );
  }
}
