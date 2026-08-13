part of '../main.dart';

/// Premium card icon hierarchy roles. Sized from host LayoutBuilder width.
enum _PremiumIconRole { kpi, extension, pdfBalance, pdfPackage }

class CompanySubscriptionBillingPage extends StatefulWidget {
  const CompanySubscriptionBillingPage({super.key});

  @override
  State<CompanySubscriptionBillingPage> createState() =>
      _CompanySubscriptionBillingPageState();
}

class _CompanySubscriptionBillingPageState
    extends State<CompanySubscriptionBillingPage>
    with WidgetsBindingObserver {
  late Future<BackendSubscriptionProfile> _future;
  // Soft warn/danger derived from the current business palette so we never
  // hard-code Corporate Blue tones or amber; blends danger toward accent so
  // scheduled-cancel / cancel CTAs read legibly on both dark and light
  // surfaces without introducing a Corporate Blue hex or concept-image blue.
  Color get _warn {
    final p = _businessThemePalette;
    return Color.lerp(p.danger, p.accent, 0.30) ?? p.danger;
  }

  // Patch 2.2B activation wiring state.
  bool _activating = false;
  // Patch 2.4B: dedicated loading flag for the Extra vehicle add-on checkout so
  // it cannot be double-tapped and is independent of the base-activation flag.
  bool _startingAddonCheckout = false;
  // Patch 2.5: guard against double-tapping the cancel-subscription button.
  bool _cancelling = false;
  // Patch 2.6: guard against double-tapping the cancel-one-extra-vehicle button.
  bool _cancellingExtraVehicle = false;
  // Patch 2.8: dedicated loading flag for the Extra driver add-on checkout.
  bool _startingExtraDriverAddonCheckout = false;
  // Patch 2.8: guard against double-tapping the cancel-one-extra-driver button.
  bool _cancellingExtraDriver = false;
  // Undo cancel-at-period-end (base + add-ons).
  bool _undoingCancellation = false;
  bool _undoingExtraVehicle = false;
  bool _undoingExtraDriver = false;
  // Patch 2.9: per-bundle loading flags for the PDF add-on checkout so
  // each PDF tile is independent and cannot be double-tapped.
  bool _startingPdf500Checkout = false;
  bool _startingPdf1000Checkout = false;
  bool _startingPdf5000Checkout = false;
  // Set true while a Mollie checkout window is open so the next app resume
  // triggers exactly one profile refresh (no infinite resume loops). Shared by
  // both the base subscription checkout and the add-on checkout.
  bool _awaitingCheckoutReturn = false;

  /// Format an integer-cents price as "€XX" (no decimals when round, "€X.YY"
  /// otherwise). Currency is always shown as € for now; the catalog currency
  /// field would be consulted here if non-EUR markets are ever added.
  String _priceFromCents(int cents) {
    if (cents % 100 == 0) return '€${cents ~/ 100}';
    final whole = cents ~/ 100;
    final fraction = (cents % 100).toString().padLeft(2, '0');
    return '€$whole.$fraction';
  }

  bool _hasProviderSubscription(BackendSubscriptionProfile profile) =>
      profile.providerSubscriptionId.trim().startsWith('sub_');

  String? _consolidatedRenewalLine(BackendSubscriptionProfile profile) {
    if (!_hasProviderSubscription(profile)) return null;
    final cents = profile.recurringAmountCents;
    if (cents == null) return null;
    final periodEnd = profile.currentPeriodEnd.trim();
    if (periodEnd.isEmpty) return null;
    final date = _humanDate(periodEnd);
    return _t(
      nl: 'Volgende verlenging: ${_priceFromCents(cents)} op $date',
      en: 'Next renewal: ${_priceFromCents(cents)} on $date',
      fr: 'Prochain renouvellement : ${_priceFromCents(cents)} le $date',
      es: 'Próxima renovación: ${_priceFromCents(cents)} el $date',
    );
  }

  String _localizedMonthName(int month) {
    assert(month >= 1 && month <= 12);
    switch (currentLanguageCode) {
      case 'fr':
        const fr = [
          'janvier',
          'février',
          'mars',
          'avril',
          'mai',
          'juin',
          'juillet',
          'août',
          'septembre',
          'octobre',
          'novembre',
          'décembre',
        ];
        return fr[month - 1];
      case 'es':
        const es = [
          'enero',
          'febrero',
          'marzo',
          'abril',
          'mayo',
          'junio',
          'julio',
          'agosto',
          'septiembre',
          'octubre',
          'noviembre',
          'diciembre',
        ];
        return es[month - 1];
      case 'en':
        const en = [
          'January',
          'February',
          'March',
          'April',
          'May',
          'June',
          'July',
          'August',
          'September',
          'October',
          'November',
          'December',
        ];
        return en[month - 1];
      default:
        const nl = [
          'januari',
          'februari',
          'maart',
          'april',
          'mei',
          'juni',
          'juli',
          'augustus',
          'september',
          'oktober',
          'november',
          'december',
        ];
        return nl[month - 1];
    }
  }

  /// Localized long-form date from a backend ISO timestamp (device timezone).
  String _humanDate(String iso) {
    final raw = iso.trim();
    if (raw.isEmpty) return '—';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    return '${local.day} ${_localizedMonthName(local.month)} ${local.year}';
  }

  Future<bool> _confirmAddonProration(
    BackendSubscriptionCheckoutStartResult result,
  ) async {
    final proration = result.proration;
    if (proration == null || !proration.hasProration) return true;
    final proratedCents = proration.proratedCents!;
    final periodStart = _humanDate(proration.periodStart);
    final periodEnd = _humanDate(proration.periodEnd);
    final nextMonthly = proration.nextRenewalMonthlyCents;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        title: Text(
          _t(
            nl: 'Betaling bevestigen',
            en: 'Confirm payment',
            fr: 'Confirmer le paiement',
            es: 'Confirmar pago',
          ),
          style: TextStyle(color: _businessThemePalette.textPrimary),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _t(
                nl: 'Vandaag: ${_priceFromCents(proratedCents)} voor $periodStart t/m $periodEnd',
                en: 'Today: ${_priceFromCents(proratedCents)} for $periodStart through $periodEnd',
                fr: 'Aujourd\'hui : ${_priceFromCents(proratedCents)} pour $periodStart au $periodEnd',
                es: 'Hoy: ${_priceFromCents(proratedCents)} del $periodStart al $periodEnd',
              ),
              style: TextStyle(color: _businessThemePalette.textMuted),
            ),
            if (nextMonthly != null) ...[
              const SizedBox(height: 8),
              Text(
                _t(
                  nl: 'Vanaf $periodEnd: ${_priceFromCents(nextMonthly)} per maand',
                  en: 'From $periodEnd: ${_priceFromCents(nextMonthly)} per month',
                  fr: 'À partir du $periodEnd : ${_priceFromCents(nextMonthly)} par mois',
                  es: 'Desde el $periodEnd: ${_priceFromCents(nextMonthly)} al mes',
                ),
                style: TextStyle(color: _businessThemePalette.textMuted),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _t(
                nl: 'Doorgaan naar betaling',
                en: 'Continue to payment',
                fr: 'Continuer vers le paiement',
                es: 'Continuar al pago',
              ),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<bool> _launchAddonCheckoutUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (url.isEmpty || uri == null || !uri.isScheme('https')) {
      _showSnack(_genericAddonError());
      return false;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return false;
    if (!launched) {
      _showSnack(
        _t(
          nl: 'Kon het betaalvenster niet openen.',
          en: 'Could not open the payment window.',
          fr: 'Impossible d’ouvrir la fenêtre de paiement.',
          es: 'No se pudo abrir la ventana de pago.',
        ),
      );
      return false;
    }
    _awaitingCheckoutReturn = true;
    _showSnack(
      _t(
        nl: 'Betaalvenster geopend. Na betaling wordt je add-on automatisch bijgewerkt.',
        en: 'Payment window opened. After payment, your add-on will update automatically.',
        fr: 'Fenêtre de paiement ouverte. Après le paiement, votre option sera mise à jour automatiquement.',
        es: 'Ventana de pago abierta. Después del pago, tu complemento se actualizará automáticamente.',
      ),
    );
    return true;
  }

  String _planDisplayName(BackendSubscriptionProfile profile, String market) {
    final code = profile.planCode.trim().toLowerCase();
    if (code == 'fluxidi_pro' || code.isEmpty) {
      if (market == 'BE') {
        return _t(
          nl: 'Fluxidi Pro België',
          en: 'Fluxidi Pro Belgium',
          fr: 'Fluxidi Pro Belgique',
          es: 'Fluxidi Pro Bélgica',
        );
      }
      return _t(
        nl: 'Fluxidi Automatisatie',
        en: 'Fluxidi Automation',
        fr: 'Fluxidi Automatisation',
        es: 'Fluxidi Automatización',
      );
    }
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

  /// Secondary accent derived from the active palette (never a fixed mock blue).
  Color get _secondaryAccent => Color.lerp(_gold, _green, 0.42) ?? _gold;

  /// Icon role for premium card hierarchy sizing.
  ///
  /// Geometry is driven by the host [layoutWidth] from LayoutBuilder (and
  /// optional [cardWidth]), not solely by device form-factor queries.
  ({double circle, double glyph}) _premiumIconMetrics({
    required double layoutWidth,
    required _PremiumIconRole role,
    double? cardWidth,
  }) {
    final bool tabletClass = layoutWidth >= 600;
    late final double cMin;
    late final double cMax;
    late final double gMin;
    late final double gMax;
    switch (role) {
      case _PremiumIconRole.kpi:
        if (tabletClass) {
          cMin = 52;
          cMax = 60;
          gMin = 28;
          gMax = 34;
        } else {
          cMin = 42;
          cMax = 48;
          gMin = 24;
          gMax = 28;
        }
      case _PremiumIconRole.extension:
        if (tabletClass) {
          cMin = 56;
          cMax = 64;
          gMin = 30;
          gMax = 38;
        } else {
          cMin = 46;
          cMax = 54;
          gMin = 26;
          gMax = 32;
        }
      case _PremiumIconRole.pdfBalance:
        if (tabletClass) {
          cMin = 60;
          cMax = 68;
          gMin = 32;
          gMax = 40;
        } else {
          cMin = 50;
          cMax = 58;
          gMin = 28;
          gMax = 34;
        }
      case _PremiumIconRole.pdfPackage:
        if (tabletClass) {
          cMin = 46;
          cMax = 54;
          gMin = 26;
          gMax = 32;
        } else {
          cMin = 40;
          cMax = 46;
          gMin = 22;
          gMax = 28;
        }
    }
    final double ref = cardWidth ?? layoutWidth;
    final double t = tabletClass
        ? ((ref - 180) / 120).clamp(0.0, 1.0)
        : ((ref - 280) / 140).clamp(0.0, 1.0);
    return (circle: cMin + (cMax - cMin) * t, glyph: gMin + (gMax - gMin) * t);
  }

  Widget _premiumIconBadge({
    required IconData icon,
    required Color accent,
    required double layoutWidth,
    required _PremiumIconRole role,
    double? cardWidth,
    bool muted = false,
  }) {
    final palette = _businessThemePalette;
    final metrics = _premiumIconMetrics(
      layoutWidth: layoutWidth,
      role: role,
      cardWidth: cardWidth,
    );
    final Color fg = muted ? palette.textMuted : accent;
    final Color fill = muted
        ? palette.surfaceAlt.withOpacity(palette.isDark ? 0.85 : 0.95)
        : accent.withOpacity(palette.isDark ? 0.24 : 0.16);
    final Color ring = muted
        ? palette.border.withOpacity(0.95)
        : accent.withOpacity(palette.isDark ? 0.72 : 0.58);
    return Container(
      width: metrics.circle,
      height: metrics.circle,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 1.2),
      ),
      child: Icon(icon, size: metrics.glyph, color: fg),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _fetch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh once when the app returns to the foreground after we opened the
    // Mollie checkout window, so a completed payment is reflected without the
    // user manually refreshing. Guarded by [_awaitingCheckoutReturn] to avoid
    // refreshing on every unrelated resume.
    if (state == AppLifecycleState.resumed && _awaitingCheckoutReturn) {
      _awaitingCheckoutReturn = false;
      _refresh();
    }
  }

  /// Re-fetch the subscription profile and rebuild. Safe if unmounted.
  void _refresh() {
    if (!mounted) return;
    setState(() {
      _future = _fetch();
    });
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
    return fetchCompanySubscriptionProfile(
      tenantId: scopeId,
      companyId: scopeId,
    );
  }

  /// True when the resolved market is one of the six Fluxidi launch markets.
  /// Mirrors the backend `isFluxidiSupportedLaunchMarket` gate so the activate
  /// button is never shown for markets the backend will refuse.
  bool _isSupportedMarket(String market) => isFluxidiLaunchMarket(market);

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Resolve the effective market for a profile, falling back to the active
  /// company's market when the backend profile has not shipped one yet.
  String _effectiveMarket(BackendSubscriptionProfile profile) {
    final fromProfile = profile.market.trim();
    if (fromProfile.isNotEmpty) return fromProfile.toUpperCase();
    return resolveActiveCompanyPricingMarket();
  }

  /// Informational-only notice when Play distribution disables SaaS purchase.
  /// No checkout URL or external payment link is offered.
  Widget _playSaasManagedOutsideNotice() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _chip(
        text: fluxidiPlaySaasManagedOutsideMessage(
          languageCode: currentLanguageCode,
        ),
        bg: _businessThemePalette.surfaceAlt.withOpacity(
          _businessThemePalette.isDark ? 0.66 : 0.92,
        ),
        border: _businessThemePalette.border.withOpacity(0.7),
        textColor: _businessThemePalette.textMuted,
        icon: Icons.info_outline,
      ),
    );
  }

  /// Start the Fluxidi-owned subscription checkout and open the Mollie payment
  /// window externally. Never embeds Mollie in a WebView. Refreshes the profile
  /// when the backend reports the subscription is already active.
  Future<void> _startCheckout(BackendSubscriptionProfile profile) async {
    if (!kFluxidiCompanySaasCheckoutEnabled) {
      _showSnack(
        fluxidiPlaySaasManagedOutsideMessage(languageCode: currentLanguageCode),
      );
      return;
    }
    if (_activating) return;
    final scopeId = _activeCompanyId();
    if (scopeId == null || scopeId.trim().isEmpty) {
      _showSnack(
        _t(
          nl: 'Geen actief bedrijf gevonden. Probeer opnieuw.',
          en: 'No active company found. Please try again.',
          fr: 'Aucune entreprise active trouvée. Veuillez réessayer.',
          es: 'No se encontró ninguna empresa activa. Inténtalo de nuevo.',
        ),
      );
      return;
    }

    final market = _effectiveMarket(profile);
    if (!_isSupportedMarket(market)) {
      _showSnack(_unsupportedMarketMessage());
      return;
    }

    setState(() => _activating = true);
    try {
      final result = await startCompanySubscriptionCheckout(
        tenantId: scopeId,
        companyId: scopeId,
      );

      if (!mounted) return;

      if (result.alreadyActive) {
        _showSnack(
          _t(
            nl: 'Je abonnement is al actief.',
            en: 'Your subscription is already active.',
            fr: 'Votre abonnement est déjà actif.',
            es: 'Tu suscripción ya está activa.',
          ),
        );
        _refresh();
        return;
      }

      if (!result.ok) {
        if (result.isUnsupportedMarket) {
          _showSnack(_unsupportedMarketMessage());
        } else {
          _showSnack(
            _t(
              nl: 'Activeren is niet gelukt. Controleer je verbinding en probeer opnieuw.',
              en: 'Activation failed. Check your connection and try again.',
              fr: 'Échec de l’activation. Vérifiez votre connexion et réessayez.',
              es: 'Error en la activación. Comprueba tu conexión e inténtalo de nuevo.',
            ),
          );
        }
        return;
      }

      if (!result.hasCheckoutUrl) {
        _showSnack(
          _t(
            nl: 'Geen betaallink ontvangen. Probeer het later opnieuw.',
            en: 'No payment link received. Please try again later.',
            fr: 'Aucun lien de paiement reçu. Réessayez plus tard.',
            es: 'No se recibió ningún enlace de pago. Inténtalo más tarde.',
          ),
        );
        return;
      }

      final uri = Uri.tryParse(result.checkoutUrl);
      if (uri == null) {
        _showSnack(
          _t(
            nl: 'Ongeldige betaallink ontvangen.',
            en: 'Received an invalid payment link.',
            fr: 'Lien de paiement invalide reçu.',
            es: 'Se recibió un enlace de pago no válido.',
          ),
        );
        return;
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (!launched) {
        _showSnack(
          _t(
            nl: 'Kon het betaalvenster niet openen.',
            en: 'Could not open the payment window.',
            fr: 'Impossible d’ouvrir la fenêtre de paiement.',
            es: 'No se pudo abrir la ventana de pago.',
          ),
        );
        return;
      }

      // Mark that the next foreground resume should refresh the profile once.
      _awaitingCheckoutReturn = true;
      _showSnack(
        _t(
          nl: 'Betaalvenster geopend. Na betaling wordt je abonnement automatisch bijgewerkt.',
          en: 'Payment window opened. After payment, your subscription will update automatically.',
          fr: 'Fenêtre de paiement ouverte. Après le paiement, votre abonnement sera mis à jour automatiquement.',
          es: 'Ventana de pago abierta. Después del pago, tu suscripción se actualizará automáticamente.',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showSnack(
        _t(
          nl: 'Er ging iets mis. Probeer opnieuw.',
          en: 'Something went wrong. Please try again.',
          fr: 'Une erreur est survenue. Veuillez réessayer.',
          es: 'Algo salió mal. Inténtalo de nuevo.',
        ),
      );
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  String _unsupportedMarketMessage() => _t(
    nl: 'Nog niet beschikbaar in dit land.',
    en: 'Not available in this country yet.',
    fr: 'Pas encore disponible dans ce pays.',
    es: 'Aún no disponible en este país.',
  );

  // ---------------------------------------------------------------------------
  // Patch 2.4B: Extra vehicle add-on checkout wiring.
  //
  // Mirrors [_startCheckout] (base subscription) but targets the live add-on
  // route and only ever requests addon_code="extra_vehicle", quantity=1. The
  // backend is the sole source of truth for pricing — Flutter never sends a
  // price. Extra driver is wired in Patch 2.8; pdf_500 / pdf_1000 PDF bundles
  // in Patch 2.9; pdf_5000 in Patch 2.11.
  // ---------------------------------------------------------------------------

  String _activateExtraVehicleLabel() => _t(
    nl: 'Extra voertuig activeren',
    en: 'Activate extra vehicle',
    fr: 'Activer véhicule supplémentaire',
    es: 'Activar vehículo extra',
  );

  bool _profileIsActive(BackendSubscriptionProfile profile) =>
      profile.status.trim().toLowerCase() == 'active' ||
      profile.subscriptionStatus.trim().toLowerCase() == 'active';

  String _addonRequiresActiveMessage() => _t(
    nl: 'Add-ons kunnen pas geactiveerd worden zodra je Fluxidi-abonnement actief is.',
    en: 'Add-ons can only be activated once your Fluxidi subscription is active.',
    fr: 'Les options ne peuvent être activées qu’une fois votre abonnement Fluxidi actif.',
    es: 'Los complementos solo se pueden activar cuando tu suscripción Fluxidi esté activa.',
  );

  String _genericAddonError() => _t(
    nl: 'Activeren is niet gelukt. Controleer je verbinding en probeer opnieuw.',
    en: 'Activation failed. Check your connection and try again.',
    fr: 'Échec de l’activation. Vérifiez votre connexion et réessayez.',
    es: 'Error en la activación. Comprueba tu conexión e inténtalo de nuevo.',
  );

  /// Map a non-ok add-on checkout result to a localized, user-safe message.
  String _addonCheckoutErrorMessage(
    BackendSubscriptionCheckoutStartResult result,
  ) {
    final error = result.error.trim();
    if (result.statusCode == 401 || error == 'unauthorized') {
      return _t(
        nl: 'Je sessie is verlopen. Meld opnieuw aan.',
        en: 'Your session has expired. Please sign in again.',
        fr: 'Votre session a expiré. Veuillez vous reconnecter.',
        es: 'Tu sesión ha caducado. Vuelve a iniciar sesión.',
      );
    }
    if (error == 'addon_checkout_already_pending') {
      return _t(
        nl: 'Er staat al een add-on betaling klaar. Rond die eerst af of probeer later opnieuw.',
        en: 'An add-on payment is already pending. Complete it first or try again later.',
        fr: 'Un paiement d’option est déjà en attente. Terminez-le d’abord ou réessayez plus tard.',
        es: 'Ya hay un pago de complemento pendiente. Complétalo primero o inténtalo más tarde.',
      );
    }
    if (error == 'subscription_not_active') {
      return _addonRequiresActiveMessage();
    }
    if (result.isUnsupportedMarket) {
      return _t(
        nl: 'Deze add-on is nog niet beschikbaar in je land.',
        en: 'This add-on is not available in your country yet.',
        fr: 'Cette option n’est pas encore disponible dans votre pays.',
        es: 'Este complemento aún no está disponible en tu país.',
      );
    }
    return _genericAddonError();
  }

  /// Start the Extra vehicle add-on checkout and open the Mollie payment window
  /// externally (same pattern as [_startCheckout]). Guarded against
  /// double-taps by [_startingAddonCheckout].
  Future<void> _startExtraVehicleAddonCheckout(
    BackendSubscriptionProfile profile,
  ) async {
    if (!kFluxidiCompanySaasCheckoutEnabled) {
      _showSnack(
        fluxidiPlaySaasManagedOutsideMessage(languageCode: currentLanguageCode),
      );
      return;
    }
    if (_startingAddonCheckout) return;
    final scopeId = _activeCompanyId();
    if (scopeId == null || scopeId.trim().isEmpty) {
      _showSnack(
        _t(
          nl: 'Geen actief bedrijf gevonden. Probeer opnieuw.',
          en: 'No active company found. Please try again.',
          fr: 'Aucune entreprise active trouvée. Veuillez réessayer.',
          es: 'No se encontró ninguna empresa activa. Inténtalo de nuevo.',
        ),
      );
      return;
    }
    final market = _effectiveMarket(profile);
    if (!_isSupportedMarket(market)) {
      _showSnack(_unsupportedMarketMessage());
      return;
    }
    if (!_profileIsActive(profile)) {
      _showSnack(_addonRequiresActiveMessage());
      return;
    }

    setState(() => _startingAddonCheckout = true);
    try {
      final result = await startCompanySubscriptionAddonCheckout(
        tenantId: scopeId,
        companyId: scopeId,
        addonCode: 'extra_vehicle',
        quantity: 1,
        returnUrl:
            '${appConfig.bookingBaseUrl}/company/subscription/add-ons/checkout/return',
      );

      if (!mounted) return;

      if (!result.ok) {
        _showSnack(_addonCheckoutErrorMessage(result));
        return;
      }

      if (!await _confirmAddonProration(result)) return;

      final url = result.checkoutUrl.trim();
      await _launchAddonCheckoutUrl(url);
    } catch (_) {
      if (!mounted) return;
      _showSnack(
        _t(
          nl: 'Er ging iets mis. Probeer opnieuw.',
          en: 'Something went wrong. Please try again.',
          fr: 'Une erreur est survenue. Veuillez réessayer.',
          es: 'Algo salió mal. Inténtalo de nuevo.',
        ),
      );
    } finally {
      if (mounted) setState(() => _startingAddonCheckout = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Patch 2.8: Extra driver add-on checkout wiring.
  //
  // Mirrors [_startExtraVehicleAddonCheckout] but requests addon_code="extra_driver".
  // ---------------------------------------------------------------------------

  String _activateExtraDriverLabel() => _t(
    nl: 'Extra chauffeur activeren',
    en: 'Activate extra driver',
    fr: 'Activer chauffeur supplémentaire',
    es: 'Activar conductor extra',
  );

  Future<void> _startExtraDriverAddonCheckout(
    BackendSubscriptionProfile profile,
  ) async {
    if (!kFluxidiCompanySaasCheckoutEnabled) {
      _showSnack(
        fluxidiPlaySaasManagedOutsideMessage(languageCode: currentLanguageCode),
      );
      return;
    }
    if (_startingExtraDriverAddonCheckout) return;
    final scopeId = _activeCompanyId();
    if (scopeId == null || scopeId.trim().isEmpty) {
      _showSnack(
        _t(
          nl: 'Geen actief bedrijf gevonden. Probeer opnieuw.',
          en: 'No active company found. Please try again.',
          fr: 'Aucune entreprise active trouvée. Veuillez réessayer.',
          es: 'No se encontró ninguna empresa activa. Inténtalo de nuevo.',
        ),
      );
      return;
    }
    final market = _effectiveMarket(profile);
    if (!_isSupportedMarket(market)) {
      _showSnack(_unsupportedMarketMessage());
      return;
    }
    if (!_profileIsActive(profile)) {
      _showSnack(_addonRequiresActiveMessage());
      return;
    }

    setState(() => _startingExtraDriverAddonCheckout = true);
    try {
      final result = await startCompanySubscriptionAddonCheckout(
        tenantId: scopeId,
        companyId: scopeId,
        addonCode: 'extra_driver',
        quantity: 1,
        returnUrl:
            '${appConfig.bookingBaseUrl}/company/subscription/add-ons/checkout/return',
      );

      if (!mounted) return;

      if (!result.ok) {
        _showSnack(_addonCheckoutErrorMessage(result));
        return;
      }

      if (!await _confirmAddonProration(result)) return;

      final url = result.checkoutUrl.trim();
      await _launchAddonCheckoutUrl(url);
    } catch (_) {
      if (!mounted) return;
      _showSnack(
        _t(
          nl: 'Er ging iets mis. Probeer opnieuw.',
          en: 'Something went wrong. Please try again.',
          fr: 'Une erreur est survenue. Veuillez réessayer.',
          es: 'Algo salió mal. Inténtalo de nuevo.',
        ),
      );
    } finally {
      if (mounted) setState(() => _startingExtraDriverAddonCheckout = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Patch 2.6: cancel/downgrade one extra vehicle add-on at period end.
  //
  // Local state only; no payment, checkout, or Mollie call. The paid slot stays
  // usable until the effective date, after which the backend lazily lowers the
  // vehicle limit. Existing vehicles are never deleted.
  // ---------------------------------------------------------------------------

  /// Active paid extra-vehicle slots, preferring the explicit backend count and
  /// falling back to (maxVehicles - includedVehicles) for legacy profiles.
  int _extraVehicleActiveQuantity(BackendSubscriptionProfile profile) {
    if (profile.extraVehicleActiveQuantity > 0) {
      return profile.extraVehicleActiveQuantity;
    }
    final derived = profile.maxVehicles - profile.includedVehicles;
    return derived > 0 ? derived : 0;
  }

  /// Slots still cancelable right now (active minus already-scheduled).
  int _extraVehicleCancelableQuantity(BackendSubscriptionProfile profile) {
    final cancelable =
        _extraVehicleActiveQuantity(profile) -
        profile.extraVehicleCancelAtPeriodEndQuantity;
    return cancelable > 0 ? cancelable : 0;
  }

  String _extraVehicleEffectiveDate(BackendSubscriptionProfile profile) {
    final effective = profile.extraVehicleCancellationEffectiveAt.trim();
    if (effective.isNotEmpty) return _humanDate(effective);
    final periodEnd = profile.currentPeriodEnd.trim();
    if (periodEnd.isNotEmpty) return _humanDate(periodEnd);
    final trialEnds = profile.trialEndsAt.trim();
    if (trialEnds.isNotEmpty) return _humanDate(trialEnds);
    return '—';
  }

  Future<void> _confirmAndCancelOneExtraVehicle(
    BackendSubscriptionProfile profile,
  ) async {
    if (_cancellingExtraVehicle) return;
    final scopeId = _activeCompanyId();
    if (scopeId == null || scopeId.trim().isEmpty) {
      _showSnack(
        _t(
          nl: 'Geen actief bedrijf gevonden. Probeer opnieuw.',
          en: 'No active company found. Please try again.',
          fr: 'Aucune entreprise active trouvée. Veuillez réessayer.',
          es: 'No se encontró ninguna empresa activa. Inténtalo de nuevo.',
        ),
      );
      return;
    }

    final effective = _extraVehicleEffectiveDate(profile);
    final futureVehicles = (profile.maxVehicles - 1).clamp(
      profile.includedVehicles,
      profile.maxVehicles,
    );
    final futureDrivers = (profile.maxDrivers - 3).clamp(
      profile.includedVehicles * 3,
      profile.maxDrivers,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        title: Text(
          _t(
            nl: 'Eén extra voertuig opzeggen?',
            en: 'Cancel one extra vehicle?',
            fr: 'Résilier un véhicule supplémentaire ?',
            es: '¿Cancelar un vehículo extra?',
          ),
          style: TextStyle(color: _businessThemePalette.textPrimary),
        ),
        content: Text(
          _t(
            nl: '1 extra voertuig blijft actief tot $effective. Daarna: voertuigenlimiet $futureVehicles en chauffeurslimiet $futureDrivers (−1 voertuig, −3 chauffeurs). Basisabonnement en PDF-pakketten blijven actief. Bestaande voertuigen/chauffeurs worden niet verwijderd.',
            en: '1 extra vehicle stays active until $effective. Afterwards: vehicle limit $futureVehicles and driver limit $futureDrivers (−1 vehicle, −3 drivers). Base plan and PDF packs stay active. Existing vehicles/drivers are not removed.',
            fr: '1 véhicule supplémentaire reste actif jusqu\'au $effective. Ensuite : limite véhicules $futureVehicles et chauffeurs $futureDrivers (−1 véhicule, −3 chauffeurs). L\'abonnement de base et les packs PDF restent actifs. Aucune suppression de données.',
            es: '1 vehículo extra permanece activo hasta el $effective. Después: límite de vehículos $futureVehicles y de conductores $futureDrivers (−1 vehículo, −3 conductores). El plan base y los paquetes PDF siguen activos. No se eliminan datos.',
          ),
          style: TextStyle(color: _businessThemePalette.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(nl: 'Behouden', en: 'Keep', fr: 'Conserver', es: 'Mantener'),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _warn,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _t(nl: 'Opzeggen', en: 'Cancel', fr: 'Résilier', es: 'Cancelar'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cancellingExtraVehicle = true);
    try {
      final updated = await cancelOneExtraVehicleAddon(
        tenantId: scopeId,
        companyId: scopeId,
      );
      if (!mounted) return;
      _showSnack(
        _t(
          nl: '1 extra voertuig blijft actief tot ${_extraVehicleEffectiveDate(updated)}.',
          en: '1 extra vehicle stays active until ${_extraVehicleEffectiveDate(updated)}.',
          fr: '1 véhicule supplémentaire reste actif jusqu\'au ${_extraVehicleEffectiveDate(updated)}.',
          es: '1 vehículo extra permanece activo hasta el ${_extraVehicleEffectiveDate(updated)}.',
        ),
      );
      _refresh();
    } catch (_) {
      if (!mounted) return;
      _showSnack(
        _t(
          nl: 'Opzeggen is niet gelukt. Controleer je verbinding en probeer opnieuw.',
          en: 'Cancellation failed. Check your connection and try again.',
          fr: 'Échec de la résiliation. Vérifiez votre connexion et réessayez.',
          es: 'Error al cancelar. Comprueba tu conexión e inténtalo de nuevo.',
        ),
      );
    } finally {
      if (mounted) setState(() => _cancellingExtraVehicle = false);
    }
  }

  Future<void> _undoCancelOneExtraVehicle(
    BackendSubscriptionProfile profile,
  ) async {
    if (_undoingExtraVehicle) return;
    final scopeId = _activeCompanyId();
    if (scopeId == null || scopeId.trim().isEmpty) {
      _showSnack(
        _t(
          nl: 'Geen actief bedrijf gevonden. Probeer opnieuw.',
          en: 'No active company found. Please try again.',
          fr: 'Aucune entreprise active trouvée. Veuillez réessayer.',
          es: 'No se encontró ninguna empresa activa. Inténtalo de nuevo.',
        ),
      );
      return;
    }
    setState(() => _undoingExtraVehicle = true);
    try {
      final updated = await undoCancelOneExtraVehicleAddon(
        tenantId: scopeId,
        companyId: scopeId,
      );
      if (!mounted) return;
      _showSnack(
        _t(
          nl: 'Opzegging extra voertuig ongedaan gemaakt.',
          en: 'Extra vehicle cancellation undone.',
          fr: 'Résiliation du véhicule supplémentaire annulée.',
          es: 'Cancelación del vehículo extra deshecha.',
        ),
      );
      if (updated.providerAmountSyncPending) {
        _showSnack(
          _t(
            nl: 'Providerbedrag wordt opnieuw gesynchroniseerd.',
            en: 'Provider amount is being re-synced.',
            fr: 'Le montant fournisseur est resynchronisé.',
            es: 'El importe del proveedor se está resincronizando.',
          ),
        );
      }
      _refresh();
    } catch (_) {
      if (!mounted) return;
      _showSnack(
        _t(
          nl: 'Ongedaan maken is niet gelukt. Probeer opnieuw.',
          en: 'Undo failed. Please try again.',
          fr: 'Échec de l\'annulation. Veuillez réessayer.',
          es: 'No se pudo deshacer. Inténtalo de nuevo.',
        ),
      );
    } finally {
      if (mounted) setState(() => _undoingExtraVehicle = false);
    }
  }

  /// Cancel-one / scheduled-status / undo for the Extra vehicle add-on.
  Widget _extraVehicleCancellationControls(BackendSubscriptionProfile profile) {
    final scheduled = profile.extraVehicleCancelAtPeriodEndQuantity;
    final cancelable = _extraVehicleCancelableQuantity(profile);
    final activeQty = _extraVehicleActiveQuantity(profile);
    if (activeQty <= 0 && scheduled <= 0) {
      return const SizedBox.shrink();
    }

    final children = <Widget>[];
    final effectiveDate = _extraVehicleEffectiveDate(profile);
    final renewalLine = _consolidatedRenewalLine(profile);

    if (scheduled > 0) {
      children.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
          decoration: BoxDecoration(
            color: _warn.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _warn.withOpacity(0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(
                  nl: 'Opgezegd — actief t/m $effectiveDate',
                  en: 'Cancelled — active until $effectiveDate',
                  fr: 'Résilié — actif jusqu\'au $effectiveDate',
                  es: 'Cancelado — activo hasta el $effectiveDate',
                ),
                style: TextStyle(
                  color: _businessThemePalette.textPrimary,
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (renewalLine != null) ...[
                const SizedBox(height: 6),
                Text(
                  renewalLine,
                  style: TextStyle(
                    color: _businessThemePalette.textMuted,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _undoingExtraVehicle
                  ? null
                  : () => _undoCancelOneExtraVehicle(profile),
              style: OutlinedButton.styleFrom(
                foregroundColor: _green,
                side: BorderSide(color: _green.withOpacity(0.85)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                minimumSize: const Size.fromHeight(48),
              ),
              icon: _undoingExtraVehicle
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.undo_outlined, size: 18),
              label: Text(
                _t(
                  nl: 'Opzegging ongedaan maken',
                  en: 'Undo cancellation',
                  fr: 'Annuler la résiliation',
                  es: 'Deshacer cancelación',
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (cancelable > 0) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _cancellingExtraVehicle
                  ? null
                  : () => _confirmAndCancelOneExtraVehicle(profile),
              style: OutlinedButton.styleFrom(
                foregroundColor: _warn,
                side: BorderSide(color: _warn.withOpacity(0.85)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                minimumSize: const Size.fromHeight(48),
              ),
              icon: _cancellingExtraVehicle
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cancel_schedule_send_outlined, size: 18),
              label: Text(
                _t(
                  nl: 'Eén extra voertuig opzeggen',
                  en: 'Cancel one extra vehicle',
                  fr: 'Résilier un véhicule supplémentaire',
                  es: 'Cancelar un vehículo extra',
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// Footer for the Extra vehicle add-on card only. When the base subscription
  /// is active it renders the real activation button; otherwise it renders a
  /// disabled button plus copy explaining add-ons need an active subscription.
  Widget _extraVehicleAddonFooter(BackendSubscriptionProfile profile) {
    if (!kFluxidiCompanySaasCheckoutEnabled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _playSaasManagedOutsideNotice(),
          _extraVehicleCancellationControls(profile),
        ],
      );
    }
    final bool isActive = _profileIsActive(profile);
    final hasExtra = _extraVehicleActiveQuantity(profile) > 0;
    final purchaseLabel = hasExtra
        ? _t(
            nl: 'Nog één toevoegen',
            en: 'Add one more',
            fr: 'Ajouter un de plus',
            es: 'Añadir uno más',
          )
        : _activateExtraVehicleLabel();
    final purchaseButton = SizedBox(
      width: double.infinity,
      child: hasExtra
          ? OutlinedButton.icon(
              onPressed: (!isActive || _startingAddonCheckout)
                  ? null
                  : () => _startExtraVehicleAddonCheckout(profile),
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                side: BorderSide(color: _gold.withOpacity(0.85)),
                minimumSize: const Size.fromHeight(44),
              ),
              icon: _startingAddonCheckout
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_circle_outline, size: 18),
              label: Text(
                purchaseLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            )
          : FilledButton.icon(
              onPressed: (!isActive || _startingAddonCheckout)
                  ? null
                  : () => _startExtraVehicleAddonCheckout(profile),
              style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black,
                disabledBackgroundColor: _businessThemePalette.surfaceAlt
                    .withOpacity(_businessThemePalette.isDark ? 0.66 : 0.92),
                disabledForegroundColor: _businessThemePalette.textMuted,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _startingAddonCheckout
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black54,
                      ),
                    )
                  : const Icon(Icons.directions_car_filled_outlined, size: 18),
              label: Text(
                purchaseLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
    );
    if (isActive) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _extraVehicleCancellationControls(profile),
          const SizedBox(height: 8),
          purchaseButton,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        purchaseButton,
        const SizedBox(height: 6),
        Text(
          _addonRequiresActiveMessage(),
          style: TextStyle(
            color: _businessThemePalette.textMuted,
            fontSize: 11.4,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Patch 2.8: cancel/downgrade one extra driver add-on at period end.
  // ---------------------------------------------------------------------------

  /// Active paid extra-driver slots, preferring the explicit backend count and
  /// falling back to a one-time legacy derivation for pre-2.8 profiles.
  int _extraDriverActiveQuantity(BackendSubscriptionProfile profile) {
    if (profile.extraDriverActiveQuantity > 0) {
      return profile.extraDriverActiveQuantity;
    }
    final baseDrivers =
        profile.includedVehicles * profile.includedDriversPerVehicle;
    final vehicleAddonDrivers = _extraVehicleActiveQuantity(profile) * 3;
    final derived = profile.maxDrivers - baseDrivers - vehicleAddonDrivers;
    return derived > 0 ? derived : 0;
  }

  int _extraDriverCancelableQuantity(BackendSubscriptionProfile profile) {
    final cancelable =
        _extraDriverActiveQuantity(profile) -
        profile.extraDriverCancelAtPeriodEndQuantity;
    return cancelable > 0 ? cancelable : 0;
  }

  String _extraDriverEffectiveDate(BackendSubscriptionProfile profile) {
    final effective = profile.extraDriverCancellationEffectiveAt.trim();
    if (effective.isNotEmpty) return _humanDate(effective);
    final periodEnd = profile.currentPeriodEnd.trim();
    if (periodEnd.isNotEmpty) return _humanDate(periodEnd);
    final trialEnds = profile.trialEndsAt.trim();
    if (trialEnds.isNotEmpty) return _humanDate(trialEnds);
    return '—';
  }

  Future<void> _confirmAndCancelOneExtraDriver(
    BackendSubscriptionProfile profile,
  ) async {
    if (_cancellingExtraDriver) return;
    final scopeId = _activeCompanyId();
    if (scopeId == null || scopeId.trim().isEmpty) {
      _showSnack(
        _t(
          nl: 'Geen actief bedrijf gevonden. Probeer opnieuw.',
          en: 'No active company found. Please try again.',
          fr: 'Aucune entreprise active trouvée. Veuillez réessayer.',
          es: 'No se encontró ninguna empresa activa. Inténtalo de nuevo.',
        ),
      );
      return;
    }

    final effective = _extraDriverEffectiveDate(profile);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        title: Text(
          _t(
            nl: 'Eén extra chauffeur opzeggen?',
            en: 'Cancel one extra driver?',
            fr: 'Résilier un chauffeur supplémentaire ?',
            es: '¿Cancelar un conductor extra?',
          ),
          style: TextStyle(color: _businessThemePalette.textPrimary),
        ),
        content: Text(
          _t(
            nl: '1 extra chauffeur blijft actief tot $effective. Daarna wordt je chauffeurslimiet met 1 verlaagd. Bestaande chauffeurs worden niet verwijderd.',
            en: '1 extra driver stays active until $effective. Your driver limit drops by 1 after that. Existing drivers are not removed.',
            fr: '1 chauffeur supplémentaire reste actif jusqu\'au $effective. Votre limite de chauffeurs baissera ensuite de 1. Les chauffeurs existants ne sont pas supprimés.',
            es: '1 conductor extra permanece activo hasta el $effective. Tu límite de conductores bajará en 1 después. Los conductores existentes no se eliminan.',
          ),
          style: TextStyle(color: _businessThemePalette.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(nl: 'Behouden', en: 'Keep', fr: 'Conserver', es: 'Mantener'),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _warn,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _t(nl: 'Opzeggen', en: 'Cancel', fr: 'Résilier', es: 'Cancelar'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cancellingExtraDriver = true);
    try {
      final updated = await cancelOneExtraDriverAddon(
        tenantId: scopeId,
        companyId: scopeId,
      );
      if (!mounted) return;
      _showSnack(
        _t(
          nl: '1 extra chauffeur blijft actief tot ${_extraDriverEffectiveDate(updated)}.',
          en: '1 extra driver stays active until ${_extraDriverEffectiveDate(updated)}.',
          fr: '1 chauffeur supplémentaire reste actif jusqu\'au ${_extraDriverEffectiveDate(updated)}.',
          es: '1 conductor extra permanece activo hasta el ${_extraDriverEffectiveDate(updated)}.',
        ),
      );
      _refresh();
    } catch (_) {
      if (!mounted) return;
      _showSnack(
        _t(
          nl: 'Opzeggen is niet gelukt. Controleer je verbinding en probeer opnieuw.',
          en: 'Cancellation failed. Check your connection and try again.',
          fr: 'Échec de la résiliation. Vérifiez votre connexion et réessayez.',
          es: 'Error al cancelar. Comprueba tu conexión e inténtalo de nuevo.',
        ),
      );
    } finally {
      if (mounted) setState(() => _cancellingExtraDriver = false);
    }
  }

  Future<void> _undoCancelOneExtraDriver(
    BackendSubscriptionProfile profile,
  ) async {
    if (_undoingExtraDriver) return;
    final scopeId = _activeCompanyId();
    if (scopeId == null || scopeId.trim().isEmpty) {
      _showSnack(
        _t(
          nl: 'Geen actief bedrijf gevonden. Probeer opnieuw.',
          en: 'No active company found. Please try again.',
          fr: 'Aucune entreprise active trouvée. Veuillez réessayer.',
          es: 'No se encontró ninguna empresa activa. Inténtalo de nuevo.',
        ),
      );
      return;
    }
    setState(() => _undoingExtraDriver = true);
    try {
      final updated = await undoCancelOneExtraDriverAddon(
        tenantId: scopeId,
        companyId: scopeId,
      );
      if (!mounted) return;
      _showSnack(
        _t(
          nl: 'Opzegging extra chauffeur ongedaan gemaakt.',
          en: 'Extra driver cancellation undone.',
          fr: 'Résiliation du chauffeur supplémentaire annulée.',
          es: 'Cancelación del conductor extra deshecha.',
        ),
      );
      if (updated.providerAmountSyncPending) {
        _showSnack(
          _t(
            nl: 'Providerbedrag wordt opnieuw gesynchroniseerd.',
            en: 'Provider amount is being re-synced.',
            fr: 'Le montant fournisseur est resynchronisé.',
            es: 'El importe del proveedor se está resincronizando.',
          ),
        );
      }
      _refresh();
    } catch (_) {
      if (!mounted) return;
      _showSnack(
        _t(
          nl: 'Ongedaan maken is niet gelukt. Probeer opnieuw.',
          en: 'Undo failed. Please try again.',
          fr: 'Échec de l\'annulation. Veuillez réessayer.',
          es: 'No se pudo deshacer. Inténtalo de nuevo.',
        ),
      );
    } finally {
      if (mounted) setState(() => _undoingExtraDriver = false);
    }
  }

  Widget _extraDriverCancellationControls(BackendSubscriptionProfile profile) {
    final scheduled = profile.extraDriverCancelAtPeriodEndQuantity;
    final cancelable = _extraDriverCancelableQuantity(profile);
    final activeQty = _extraDriverActiveQuantity(profile);
    if (activeQty <= 0 && scheduled <= 0) {
      return const SizedBox.shrink();
    }

    final children = <Widget>[];
    final effectiveDate = _extraDriverEffectiveDate(profile);
    final renewalLine = _consolidatedRenewalLine(profile);

    if (scheduled > 0) {
      children.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
          decoration: BoxDecoration(
            color: _warn.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _warn.withOpacity(0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(
                  nl: 'Opgezegd — actief t/m $effectiveDate',
                  en: 'Cancelled — active until $effectiveDate',
                  fr: 'Résilié — actif jusqu\'au $effectiveDate',
                  es: 'Cancelado — activo hasta el $effectiveDate',
                ),
                style: TextStyle(
                  color: _businessThemePalette.textPrimary,
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (renewalLine != null) ...[
                const SizedBox(height: 6),
                Text(
                  renewalLine,
                  style: TextStyle(
                    color: _businessThemePalette.textMuted,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _undoingExtraDriver
                  ? null
                  : () => _undoCancelOneExtraDriver(profile),
              style: OutlinedButton.styleFrom(
                foregroundColor: _green,
                side: BorderSide(color: _green.withOpacity(0.85)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                minimumSize: const Size.fromHeight(48),
              ),
              icon: _undoingExtraDriver
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.undo_outlined, size: 18),
              label: Text(
                _t(
                  nl: 'Opzegging ongedaan maken',
                  en: 'Undo cancellation',
                  fr: 'Annuler la résiliation',
                  es: 'Deshacer cancelación',
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (cancelable > 0) {
      children.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _cancellingExtraDriver
                ? null
                : () => _confirmAndCancelOneExtraDriver(profile),
            style: TextButton.styleFrom(
              foregroundColor: _businessThemePalette.textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            icon: _cancellingExtraDriver
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.person_remove_outlined, size: 16, color: _warn),
            label: Text(
              _t(
                nl: 'Eén extra chauffeur opzeggen',
                en: 'Cancel one extra driver',
                fr: 'Résilier un chauffeur supplémentaire',
                es: 'Cancelar un conductor extra',
              ),
              style: const TextStyle(
                fontSize: 12.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _extraDriverAddonFooter(BackendSubscriptionProfile profile) {
    if (!kFluxidiCompanySaasCheckoutEnabled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _playSaasManagedOutsideNotice(),
          _extraDriverCancellationControls(profile),
        ],
      );
    }
    final bool isActive = _profileIsActive(profile);
    final hasExtra = _extraDriverActiveQuantity(profile) > 0;
    final purchaseLabel = hasExtra
        ? _t(
            nl: 'Nog één toevoegen',
            en: 'Add one more',
            fr: 'Ajouter un de plus',
            es: 'Añadir uno más',
          )
        : _activateExtraDriverLabel();
    final purchaseButton = SizedBox(
      width: double.infinity,
      child: hasExtra
          ? OutlinedButton.icon(
              onPressed: (!isActive || _startingExtraDriverAddonCheckout)
                  ? null
                  : () => _startExtraDriverAddonCheckout(profile),
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                side: BorderSide(color: _gold.withOpacity(0.85)),
                minimumSize: const Size.fromHeight(44),
              ),
              icon: _startingExtraDriverAddonCheckout
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_circle_outline, size: 18),
              label: Text(
                purchaseLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            )
          : FilledButton.icon(
              onPressed: (!isActive || _startingExtraDriverAddonCheckout)
                  ? null
                  : () => _startExtraDriverAddonCheckout(profile),
              style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black,
                disabledBackgroundColor: _businessThemePalette.surfaceAlt
                    .withOpacity(_businessThemePalette.isDark ? 0.66 : 0.92),
                disabledForegroundColor: _businessThemePalette.textMuted,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _startingExtraDriverAddonCheckout
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black54,
                      ),
                    )
                  : const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: Text(
                purchaseLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
    );
    if (isActive) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _extraDriverCancellationControls(profile),
          const SizedBox(height: 8),
          purchaseButton,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        purchaseButton,
        const SizedBox(height: 6),
        Text(
          _addonRequiresActiveMessage(),
          style: TextStyle(
            color: _businessThemePalette.textMuted,
            fontSize: 11.4,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Patch 2.9 / 2.11: PDF bundle add-ons (pdf_500 / pdf_1000 / pdf_5000). Same
  // checkout + cancel-at-period-end lifecycle as the Extra driver add-on. All
  // three bundles are actionable (5000 wired in Patch 2.11). The purchased
  // allowance increases pdf_monthly_allowance on the backend; it is not enforced
  // by a gate yet.
  // ---------------------------------------------------------------------------

  /// The pdf_500 / pdf_1000 / pdf_5000 bundles all have a real lifecycle
  /// (Patch 2.9 wired 500/1000; Patch 2.11 added 5000).
  bool _pdfBundleIsActionable(int pdfs) =>
      pdfs == 500 || pdfs == 1000 || pdfs == 5000;

  String _pdfBundleAddonCode(int pdfs) {
    if (pdfs == 500) return 'pdf_500';
    if (pdfs == 1000) return 'pdf_1000';
    return 'pdf_5000';
  }

  int _pdfBundleActiveQuantity(BackendSubscriptionProfile profile, int pdfs) {
    if (pdfs == 500) return profile.pdf500ActiveQuantity;
    if (pdfs == 1000) return profile.pdf1000ActiveQuantity;
    if (pdfs == 5000) return profile.pdf5000ActiveQuantity;
    return 0;
  }

  bool _pdfBundleBusyStarting(int pdfs) {
    if (pdfs == 500) return _startingPdf500Checkout;
    if (pdfs == 1000) return _startingPdf1000Checkout;
    return _startingPdf5000Checkout;
  }

  void _setPdfBundleStarting(int pdfs, bool value) {
    if (pdfs == 500) {
      _startingPdf500Checkout = value;
    } else if (pdfs == 1000) {
      _startingPdf1000Checkout = value;
    } else {
      _startingPdf5000Checkout = value;
    }
  }

  String _activatePdfBundleLabel(int pdfs) => _t(
    nl: 'Extra $pdfs PDF\u2019s activeren',
    en: 'Activate $pdfs extra PDFs',
    fr: 'Activer $pdfs PDF supplémentaires',
    es: 'Activar $pdfs PDF extra',
  );

  Future<void> _startPdfBundleCheckout(
    BackendSubscriptionProfile profile,
    int pdfs,
  ) async {
    if (!kFluxidiCompanySaasCheckoutEnabled) {
      _showSnack(
        fluxidiPlaySaasManagedOutsideMessage(languageCode: currentLanguageCode),
      );
      return;
    }
    if (!_pdfBundleIsActionable(pdfs)) return;
    if (_pdfBundleBusyStarting(pdfs)) return;
    final scopeId = _activeCompanyId();
    if (scopeId == null || scopeId.trim().isEmpty) {
      _showSnack(
        _t(
          nl: 'Geen actief bedrijf gevonden. Probeer opnieuw.',
          en: 'No active company found. Please try again.',
          fr: 'Aucune entreprise active trouvée. Veuillez réessayer.',
          es: 'No se encontró ninguna empresa activa. Inténtalo de nuevo.',
        ),
      );
      return;
    }
    final market = _effectiveMarket(profile);
    if (!_isSupportedMarket(market)) {
      _showSnack(_unsupportedMarketMessage());
      return;
    }
    if (!_profileIsActive(profile)) {
      _showSnack(_addonRequiresActiveMessage());
      return;
    }

    setState(() => _setPdfBundleStarting(pdfs, true));
    try {
      final result = await startCompanySubscriptionAddonCheckout(
        tenantId: scopeId,
        companyId: scopeId,
        addonCode: _pdfBundleAddonCode(pdfs),
        quantity: 1,
        returnUrl:
            '${appConfig.bookingBaseUrl}/company/subscription/add-ons/checkout/return',
      );

      if (!mounted) return;

      if (!result.ok) {
        _showSnack(_addonCheckoutErrorMessage(result));
        return;
      }

      if (!await _confirmAddonProration(result)) return;

      final url = result.checkoutUrl.trim();
      await _launchAddonCheckoutUrl(url);
    } catch (_) {
      if (!mounted) return;
      _showSnack(
        _t(
          nl: 'Er ging iets mis. Probeer opnieuw.',
          en: 'Something went wrong. Please try again.',
          fr: 'Une erreur est survenue. Veuillez réessayer.',
          es: 'Algo salió mal. Inténtalo de nuevo.',
        ),
      );
    } finally {
      if (mounted) setState(() => _setPdfBundleStarting(pdfs, false));
    }
  }

  // Note: the legacy PDF bundle footer widget was removed in the premium
  // redesign; the new `_buildPdfCreditsSection` builds one purchase card per
  // bundle and calls `_startPdfBundleCheckout` directly with cleaner copy
  // ("eenmalig", "Kopen") without the previous quantity chip / "extra pack"
  // secondary action.

  // ---------------------------------------------------------------------------
  // Patch 2.5: minimal subscription cancellation (cancel-at-period-end).
  //
  // The subscription stays active/trialing until the effective date; this only
  // schedules the cancellation via POST /company/subscription/cancel. No
  // payment, no checkout, no Mollie call is triggered from here.
  // ---------------------------------------------------------------------------

  bool _profileIsActiveOrTrialing(BackendSubscriptionProfile profile) {
    final status = profile.subscriptionStatus.trim().toLowerCase();
    final legacy = profile.status.trim().toLowerCase();
    return status == 'active' ||
        status == 'trialing' ||
        legacy == 'active' ||
        legacy == 'trialing';
  }

  String _effectiveCancelDate(BackendSubscriptionProfile profile) {
    final effective = profile.cancellationEffectiveAt.trim();
    if (effective.isNotEmpty) return _humanDate(effective);
    final periodEnd = profile.currentPeriodEnd.trim();
    if (periodEnd.isNotEmpty) return _humanDate(periodEnd);
    final trialEnds = profile.trialEndsAt.trim();
    if (trialEnds.isNotEmpty) return _humanDate(trialEnds);
    return '—';
  }

  Future<void> _confirmAndCancelSubscription(
    BackendSubscriptionProfile profile,
  ) async {
    if (_cancelling) return;
    final scopeId = _activeCompanyId();
    if (scopeId == null || scopeId.trim().isEmpty) {
      _showSnack(
        _t(
          nl: 'Geen actief bedrijf gevonden. Probeer opnieuw.',
          en: 'No active company found. Please try again.',
          fr: 'Aucune entreprise active trouvée. Veuillez réessayer.',
          es: 'No se encontró ninguna empresa activa. Inténtalo de nuevo.',
        ),
      );
      return;
    }

    final effective = _effectiveCancelDate(profile);
    final consequenceLines = _baseCancelConsequenceLines(profile, effective);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        title: Text(
          _t(
            nl: 'Abonnement opzeggen?',
            en: 'Cancel subscription?',
            fr: 'Résilier l\'abonnement ?',
            es: '¿Cancelar la suscripción?',
          ),
          style: TextStyle(color: _businessThemePalette.textPrimary),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final line in consequenceLines) ...[
                Text(
                  '• $line',
                  style: TextStyle(
                    color: _businessThemePalette.textMuted,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(nl: 'Behouden', en: 'Keep', fr: 'Conserver', es: 'Mantener'),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _warn,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _t(nl: 'Opzeggen', en: 'Cancel', fr: 'Résilier', es: 'Cancelar'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cancelling = true);
    try {
      final updated = await cancelCompanySubscription(
        tenantId: scopeId,
        companyId: scopeId,
      );
      if (!mounted) return;
      if (updated.providerCancelPending) {
        _showSnack(
          _t(
            nl: 'Opzegging gepland tot ${_effectiveCancelDate(updated)}. Providerstop wordt opnieuw geprobeerd — controleer later opnieuw.',
            en: 'Cancellation scheduled until ${_effectiveCancelDate(updated)}. Provider stop will be retried — check again later.',
            fr: 'Résiliation planifiée jusqu\'au ${_effectiveCancelDate(updated)}. L\'arrêt fournisseur sera réessayé — vérifiez plus tard.',
            es: 'Cancelación programada hasta el ${_effectiveCancelDate(updated)}. Se reintentará detener el proveedor — comprueba más tarde.',
          ),
        );
      } else {
        _showSnack(
          _t(
            nl: 'Je abonnement en betaalde uitbreidingen blijven actief tot ${_effectiveCancelDate(updated)}. Daarna geen verlenging meer.',
            en: 'Your subscription and paid add-ons stay active until ${_effectiveCancelDate(updated)}. Nothing renews after that.',
            fr: 'Votre abonnement et extensions payantes restent actifs jusqu\'au ${_effectiveCancelDate(updated)}. Plus de renouvellement ensuite.',
            es: 'Tu suscripción y ampliaciones de pago siguen activas hasta el ${_effectiveCancelDate(updated)}. No se renovarán después.',
          ),
        );
      }
      _refresh();
    } catch (_) {
      if (!mounted) return;
      _showSnack(
        _t(
          nl: 'Opzeggen is niet gelukt. Controleer je verbinding en probeer opnieuw.',
          en: 'Cancellation failed. Check your connection and try again.',
          fr: 'Échec de la résiliation. Vérifiez votre connexion et réessayez.',
          es: 'Error al cancelar. Comprueba tu conexión e inténtalo de nuevo.',
        ),
      );
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<void> _undoCancelSubscription(
    BackendSubscriptionProfile profile,
  ) async {
    if (_undoingCancellation) return;
    final scopeId = _activeCompanyId();
    if (scopeId == null || scopeId.trim().isEmpty) {
      _showSnack(
        _t(
          nl: 'Geen actief bedrijf gevonden. Probeer opnieuw.',
          en: 'No active company found. Please try again.',
          fr: 'Aucune entreprise active trouvée. Veuillez réessayer.',
          es: 'No se encontró ninguna empresa activa. Inténtalo de nuevo.',
        ),
      );
      return;
    }
    setState(() => _undoingCancellation = true);
    try {
      final updated = await undoCancelCompanySubscription(
        tenantId: scopeId,
        companyId: scopeId,
      );
      if (!mounted) return;
      _showSnack(
        _t(
          nl: 'Opzegging ongedaan gemaakt. Je abonnement blijft actief.',
          en: 'Cancellation undone. Your subscription stays active.',
          fr: 'Résiliation annulée. Votre abonnement reste actif.',
          es: 'Cancelación deshecha. Tu suscripción sigue activa.',
        ),
      );
      if (updated.providerAmountSyncPending) {
        _showSnack(
          _t(
            nl: 'Providerbedrag wordt opnieuw gesynchroniseerd.',
            en: 'Provider amount is being re-synced.',
            fr: 'Le montant fournisseur est resynchronisé.',
            es: 'El importe del proveedor se está resincronizando.',
          ),
        );
      }
      _refresh();
    } catch (_) {
      if (!mounted) return;
      _showSnack(
        _t(
          nl: 'Ongedaan maken is niet gelukt. Probeer opnieuw.',
          en: 'Undo failed. Please try again.',
          fr: 'Échec de l\'annulation. Veuillez réessayer.',
          es: 'No se pudo deshacer. Inténtalo de nuevo.',
        ),
      );
    } finally {
      if (mounted) setState(() => _undoingCancellation = false);
    }
  }

  /// Bullet lines for the base-cancel confirmation dialog (NL/EN/FR/ES).
  List<String> _baseCancelConsequenceLines(
    BackendSubscriptionProfile profile,
    String effective,
  ) {
    final lines = <String>[
      _t(
        nl: 'Basisplan blijft actief tot $effective.',
        en: 'Base plan stays active until $effective.',
        fr: 'Le plan de base reste actif jusqu\'au $effective.',
        es: 'El plan base permanece activo hasta el $effective.',
      ),
    ];
    final v = _extraVehicleActiveQuantity(profile);
    if (v > 0) {
      lines.add(
        _t(
          nl: '$v extra voertuig(en) (€19/maand excl. btw, +3 chauffeurs per stuk) eindigen op $effective.',
          en: '$v extra vehicle(s) (€19/month excl. VAT, +3 drivers each) end on $effective.',
          fr: '$v véhicule(s) supplémentaire(s) (19 €/mois HT, +3 chauffeurs chacun) se terminent le $effective.',
          es: '$v vehículo(s) extra (19 €/mes sin IVA, +3 conductores cada uno) terminan el $effective.',
        ),
      );
    }
    final d = profile.extraDriverActiveQuantity;
    if (d > 0) {
      lines.add(
        _t(
          nl: '$d aparte extra chauffeur(s) eindigen op $effective.',
          en: '$d separate extra driver(s) end on $effective.',
          fr: '$d chauffeur(s) supplémentaire(s) séparés se terminent le $effective.',
          es: '$d conductor(es) extra separados terminan el $effective.',
        ),
      );
    }
    lines.add(
      _t(
        nl: 'Na $effective geen automatische verlenging meer van basis of uitbreidingen.',
        en: 'After $effective there is no further automatic renewal of the base plan or add-ons.',
        fr: 'Après le $effective, plus aucun renouvellement automatique du plan ou des extensions.',
        es: 'Después del $effective no habrá más renovación automática del plan ni de las ampliaciones.',
      ),
    );
    lines.add(
      _t(
        nl: 'Aangekochte PDF-credits vervallen nooit en blijven beschikbaar.',
        en: 'Purchased PDF credits never expire and remain available.',
        fr: 'Les crédits PDF achetés n\'expirent jamais et restent disponibles.',
        es: 'Los créditos PDF comprados no caducan y siguen disponibles.',
      ),
    );
    if (profile.isFounderCustomer || profile.lockedPriceCents == 5900) {
      lines.add(
        _t(
          nl: 'Founderprijs €59 geldt zolang dit abonnement actief blijft. Bij latere heractivatie kan de normale prijs €69/maand gelden.',
          en: 'The €59 founder price applies while this subscription stays active. Later reactivation may use the normal €69/month price.',
          fr: 'Le tarif fondateur de 59 € s\'applique tant que cet abonnement reste actif. Une réactivation ultérieure peut utiliser le tarif normal de 69 €/mois.',
          es: 'El precio fundador de 59 € aplica mientras esta suscripción siga activa. Una reactivación posterior puede usar el precio normal de 69 €/mes.',
        ),
      );
    }
    return lines;
  }

  /// Cancel button (active/trialing, not yet scheduled) or a passive status
  /// card (already scheduled). Renders nothing for any other state.
  Widget _buildCancellationSection(BackendSubscriptionProfile profile) {
    if (profile.cancelAtPeriodEnd) {
      final pendingProvider = profile.providerCancelPending;
      final effective = _effectiveCancelDate(profile);
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
          decoration: BoxDecoration(
            color: _warn.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _warn.withOpacity(0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(
                  nl: 'Opgezegd — actief t/m $effective',
                  en: 'Cancelled — active until $effective',
                  fr: 'Résilié — actif jusqu\'au $effective',
                  es: 'Cancelado — activo hasta el $effective',
                ),
                style: TextStyle(
                  color: _businessThemePalette.textPrimary,
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _t(
                  nl: 'Vandaag wordt niets aangerekend',
                  en: 'Nothing is charged today',
                  fr: 'Rien n\'est facturé aujourd\'hui',
                  es: 'Hoy no se cobra nada',
                ),
                style: TextStyle(
                  color: _businessThemePalette.textMuted,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
              if (pendingProvider) ...[
                const SizedBox(height: 8),
                Text(
                  _t(
                    nl: 'Providerstop nog niet bevestigd. Fluxidi probeert dit automatisch opnieuw — er wordt geen nieuwe verlenging gestart vanuit de app.',
                    en: 'Provider stop not confirmed yet. Fluxidi will retry automatically — the app will not start a new renewal.',
                    fr: 'Arrêt fournisseur pas encore confirmé. Fluxidi réessaiera automatiquement — l\'app ne démarrera pas de nouveau renouvellement.',
                    es: 'Parada del proveedor aún no confirmada. Fluxidi reintentará automáticamente — la app no iniciará una nueva renovación.',
                  ),
                  style: TextStyle(
                    color: _businessThemePalette.textMuted,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _undoingCancellation
                      ? null
                      : () => _undoCancelSubscription(profile),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _green,
                    side: BorderSide(color: _green.withOpacity(0.85)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: _undoingCancellation
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.undo_outlined, size: 18),
                  label: Text(
                    _t(
                      nl: 'Opzegging ongedaan maken',
                      en: 'Undo cancellation',
                      fr: 'Annuler la résiliation',
                      es: 'Deshacer cancelación',
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_profileIsActiveOrTrialing(profile)) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _cancelling
              ? null
              : () => _confirmAndCancelSubscription(profile),
          style: OutlinedButton.styleFrom(
            foregroundColor: _warn,
            side: BorderSide(color: _warn.withOpacity(0.85)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            minimumSize: const Size.fromHeight(48),
          ),
          icon: _cancelling
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cancel_schedule_send_outlined, size: 18),
          label: Text(
            _t(
              nl: 'Abonnement opzeggen',
              en: 'Cancel subscription',
              fr: 'Résilier l\'abonnement',
              es: 'Cancelar suscripción',
            ),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
      ),
    );
  }

  /// Activation / active-state / unsupported-market section for the current
  /// subscription card. Drives the only call site of [_startCheckout].
  Widget _buildActivationSection(
    BackendSubscriptionProfile profile,
    SubscriptionPlanCatalogEntry catalog,
  ) {
    final bool isActive =
        profile.status.trim().toLowerCase() == 'active' ||
        profile.subscriptionStatus.trim().toLowerCase() == 'active';
    final String rawMarket = _effectiveMarket(profile);
    final bool isSupported = _isSupportedMarket(rawMarket);

    if (isActive) {
      // Status, active period and next payment are shown once in the premium
      // hero. Keep only founder-slot chips that the hero banner does not cover.
      final lockedCents =
          profile.lockedPriceCents ??
          profile.founderPriceCents ??
          catalog.founderPriceCents;
      if (!profile.isFounderCustomer) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            if (lockedCents != null)
              _chip(
                text: _t(
                  nl: 'Founderprijs vastgezet: ${_priceFromCents(lockedCents)}/maand',
                  en: 'Founder price locked: ${_priceFromCents(lockedCents)}/month',
                  fr: 'Prix fondateur verrouillé : ${_priceFromCents(lockedCents)}/mois',
                  es: 'Precio fundador fijado: ${_priceFromCents(lockedCents)}/mes',
                ),
                bg: _gold.withOpacity(0.13),
                border: _gold.withOpacity(0.45),
                textColor: _gold,
                icon: Icons.lock_outline,
              ),
            if (profile.founderSlotNumber != null)
              _chip(
                text: _t(
                  nl: 'Founderslot #${profile.founderSlotNumber}',
                  en: 'Founder slot #${profile.founderSlotNumber}',
                  fr: 'Slot fondateur #${profile.founderSlotNumber}',
                  es: 'Plaza fundador #${profile.founderSlotNumber}',
                ),
                bg: _gold.withOpacity(0.13),
                border: _gold.withOpacity(0.45),
                textColor: _gold,
                icon: Icons.workspace_premium_outlined,
              ),
          ],
        ),
      );
    }

    // Not active. Unsupported market -> info only, no activate button.
    if (!isSupported) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _chip(
          text: _unsupportedMarketMessage(),
          bg: _businessThemePalette.surfaceAlt.withOpacity(
            _businessThemePalette.isDark ? 0.66 : 0.92,
          ),
          border: _businessThemePalette.border.withOpacity(0.7),
          textColor: _businessThemePalette.textMuted,
          icon: Icons.public_off_outlined,
        ),
      );
    }

    // Play distribution: consumption-only — no activate / Mollie purchase CTA.
    if (!kFluxidiCompanySaasCheckoutEnabled) {
      return _playSaasManagedOutsideNotice();
    }

    // Supported + not active (trialing / inactive) -> activate button.
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _activating ? null : () => _startCheckout(profile),
          style: FilledButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: _activating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black54,
                  ),
                )
              : const Icon(Icons.rocket_launch_outlined, size: 18),
          label: Text(
            _t(
              nl: 'Abonnement activeren',
              en: 'Activate subscription',
              fr: 'Activer l’abonnement',
              es: 'Activar suscripción',
            ),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
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
    return subscriptionStatusLabel(
      statusRaw: status,
      languageCode: currentLanguageCode,
    );
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
    if (status == 'past_due' ||
        status == 'grace_period' ||
        status == 'suspended' ||
        status == 'payment_required' ||
        status == 'cancelled' ||
        status == 'canceled') {
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

  Widget _buildEntitlementStateBanner(BackendSubscriptionProfile profile) {
    final status =
        (profile.subscriptionStatus.trim().isNotEmpty
                ? profile.subscriptionStatus
                : profile.status)
            .trim()
            .toLowerCase();
    final warning = subscriptionDunningWarningMessage(
      statusRaw: status,
      languageCode: currentLanguageCode,
    );
    final blocked = subscriptionBlockedStateMessage(
      statusRaw: status,
      languageCode: currentLanguageCode,
      cancelAtPeriodEnd: profile.cancelAtPeriodEnd,
    );
    final text = blocked ?? warning;
    if (text == null || text.trim().isEmpty) return const SizedBox.shrink();
    final isHard = blocked != null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
        decoration: BoxDecoration(
          color: (isHard ? _warn : _gold).withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: (isHard ? _warn : _gold).withOpacity(0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isHard ? Icons.block : Icons.warning_amber_outlined,
              size: 18,
              color: isHard ? _warn : _gold,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: _businessThemePalette.textPrimary,
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
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

  // The legacy `_addonAvailableLabel` (which returned "Beschikbaar als
  // add-on") is intentionally not defined here anymore. The premium redesign
  // no longer surfaces that wording, and the source-contract test asserts the
  // string is gone from this file.

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

  // Note: the legacy `_moduleRow`, `_addonCard`, `_comingSoonLabel` and
  // `_usageCard` widgets were removed in the premium redesign. Included
  // capabilities are now rendered by `_buildIncludedFeatures` as compact
  // check-rows, monthly add-ons by `_buildMonthlyAddonsSection`, and usage
  // KPIs by `_buildUsageLimitsRow`.

  /// Compact responsive grid of feature check-rows for the "Inbegrepen
  /// mogelijkheden" section. Preserves the previously-listed Fluxidi
  /// capabilities (branding, booking, PDF receipts, WhatsApp/email, and
  /// Belgian Chiron/Billit-Peppol) but in a lighter visual form.
  Widget _buildIncludedFeatures(
    BackendSubscriptionProfile profile,
    SubscriptionPlanCatalogEntry catalog,
    bool isBelgiumMarket,
  ) {
    final palette = _businessThemePalette;
    Widget row(String label, {bool active = true, String? note}) {
      final Color dotColor = active ? _green : palette.textMuted;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _panelSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.border.withOpacity(0.85)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              active ? Icons.check_circle_rounded : Icons.schedule_outlined,
              size: 18,
              color: dotColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  if ((note ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      note!,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    final entries = <Widget>[
      row(
        _t(
          nl: 'Eigen bedrijfsbranding / white-label basis',
          en: 'Company branding / white-label base',
          fr: 'Branding entreprise / base marque blanche',
          es: 'Marca empresarial / base white-label',
        ),
      ),
      row(
        _t(
          nl: 'Online boekingsflow',
          en: 'Online booking flow',
          fr: 'Flux de réservation en ligne',
          es: 'Flujo de reserva en línea',
        ),
      ),
      row(
        _t(
          nl: 'PDF-ritbonnen met limieten',
          en: 'PDF receipts with limits',
          fr: 'Reçus PDF avec limites',
          es: 'Recibos PDF con límites',
        ),
        active: profile.features['receipt_pdf'] != false,
      ),
      row(
        _t(
          nl: 'WhatsApp/e-mail ritbonnen',
          en: 'WhatsApp/email receipts',
          fr: 'Reçus WhatsApp/e-mail',
          es: 'Recibos por WhatsApp/correo',
        ),
        active: profile.features['whatsapp_email_receipts'] != false,
      ),
      row(_featureLabel('airport_module')),
      row(
        _featureLabel('live_dispatch'),
        active: false,
        note: _t(
          nl: 'Binnenkort beschikbaar',
          en: 'Coming soon',
          fr: 'Bientôt disponible',
          es: 'Próximamente',
        ),
      ),
      row(
        _t(
          nl: 'Geen commissie op ritten',
          en: 'No commission on rides',
          fr: 'Aucune commission sur les courses',
          es: 'Sin comisión sobre los viajes',
        ),
      ),
      row(
        _t(
          nl: '${catalog.includedVehicleCount} voertuig inbegrepen · ${catalog.includedDriversPerVehicle} chauffeurs / voertuig',
          en: '${catalog.includedVehicleCount} vehicle included · ${catalog.includedDriversPerVehicle} drivers / vehicle',
          fr: '${catalog.includedVehicleCount} véhicule inclus · ${catalog.includedDriversPerVehicle} chauffeurs / véhicule',
          es: '${catalog.includedVehicleCount} vehículo incluido · ${catalog.includedDriversPerVehicle} conductores / vehículo',
        ),
      ),
      row(
        _t(
          nl: '${catalog.includedPdfCreationsPerVehicleMonth} PDF-creaties per voertuig / maand',
          en: '${catalog.includedPdfCreationsPerVehicleMonth} PDF creations per vehicle / month',
          fr: '${catalog.includedPdfCreationsPerVehicleMonth} créations PDF par véhicule / mois',
          es: '${catalog.includedPdfCreationsPerVehicleMonth} creaciones PDF por vehículo / mes',
        ),
      ),
      if (isBelgiumMarket) ...[
        row(
          _t(
            nl: 'Complianceoverzicht / Chiron-ready',
            en: 'Compliance dashboard / Chiron-ready',
            fr: 'Tableau conformité / Chiron-ready',
            es: 'Panel de cumplimiento / Chiron-ready',
          ),
          active: profile.features['compliance_dashboard'] != false,
        ),
        row(
          _t(
            nl: 'Billit/Peppol-ready structuur',
            en: 'Billit/Peppol-ready structure',
            fr: 'Structure Billit/Peppol-ready',
            es: 'Estructura Billit/Peppol-ready',
          ),
          note: _t(
            nl: 'Externe Billit/providerkosten voor rekening van het bedrijf.',
            en: 'External Billit/provider costs are paid by the company.',
            fr: 'Les frais Billit/fournisseur externes sont à la charge de l\'entreprise.',
            es: 'Los costes externos de Billit/proveedor corren a cargo de la empresa.',
          ),
        ),
      ],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final int cols = width >= 720 ? 2 : 1;
        final double spacing = 8;
        final double cardW = cols == 1
            ? width
            : (width - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final e in entries) SizedBox(width: cardW, child: e)],
        );
      },
    );
  }

  /// PDF creations usage bar (premium redesign). Uses a title,
  /// used/total badge, progress bar) and adds an allowance breakdown plus a
  /// helper line.
  ///
  /// Total monthly allowance = [baseAllowance] (included PDFs per vehicle/month
  /// x vehicle slots) + [addonAllowance] (purchased PDF add-ons). The backend
  /// `pdf_monthly_allowance` stores ONLY the add-on portion, so base and add-on
  /// are summed here with no double counting.
  ///
  /// [used] is a display-only placeholder until real PDF-creation tracking is
  /// wired; [tracked] flips the helper text once a real counter feeds it.
  /// Format a non-negative integer with a locale-appropriate thousands
  /// separator (dot for NL/DE, thin space for FR/ES, comma for EN).
  String _formatThousands(int value) {
    final v = value.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < v.length; i++) {
      if (i > 0 && (v.length - i) % 3 == 0) {
        switch (currentLanguageCode) {
          case 'en':
            buf.write(',');
            break;
          case 'fr':
          case 'es':
            buf.write('\u202F');
            break;
          case 'nl':
          default:
            buf.write('.');
            break;
        }
      }
      buf.write(v[i]);
    }
    return (value < 0 ? '-' : '') + buf.toString();
  }

  String _pdfOneTimeLabel() =>
      _t(nl: 'eenmalig', en: 'one-time', fr: 'ponctuel', es: 'único');

  String _pdfBuyLabel() =>
      _t(nl: 'Kopen', en: 'Buy', fr: 'Acheter', es: 'Comprar');

  /// Premium PDF-credits section with a full-width balance card at the top,
  /// three responsive purchase cards below (500/€5, 1000/€9, 5000/€29) and an
  /// optional purchase-history expander.
  ///
  /// Included capacity = `includedPdfCreationsPerVehicleMonth * maxVehicles`
  /// (typically `200 * maxVehicles`). Purchased credits never expire and are
  /// separate from the monthly included bundle.
  Widget _buildPdfCreditsSection(
    BackendSubscriptionProfile profile,
    SubscriptionPlanCatalogEntry catalog,
  ) {
    final vehicleSlots = profile.maxVehicles > 0 ? profile.maxVehicles : 1;
    final includedCap =
        catalog.includedPdfCreationsPerVehicleMonth * vehicleSlots;
    final used = profile.pdfMonthlyUsed > 0 ? profile.pdfMonthlyUsed : 0;
    final purchased = profile.purchasedPdfCredits;
    final periodEnd = profile.currentPeriodEnd.trim();
    final lastGranted = profile.pdfPurchasedLastGrantedAt.trim();
    final palette = _businessThemePalette;
    final bool isActive = _profileIsActive(profile);
    final bool checkoutEnabled = kFluxidiCompanySaasCheckoutEnabled;

    final purchasedText = _formatThousands(purchased);
    final includedText = _t(
      nl: 'Inbegrepen deze maand: $used van $includedCap',
      en: 'Included this month: $used of $includedCap',
      fr: 'Inclus ce mois : $used sur $includedCap',
      es: 'Incluidas este mes: $used de $includedCap',
    );

    Widget buildBalance(double layoutWidth) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: _panelSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _gold.withOpacity(palette.isDark ? 0.55 : 0.42),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _premiumIconBadge(
                  icon: Icons.picture_as_pdf_outlined,
                  accent: _gold,
                  layoutWidth: layoutWidth,
                  role: _PremiumIconRole.pdfBalance,
                  cardWidth: layoutWidth,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t(
                          nl: '$purchasedText credits resterend',
                          en: '$purchasedText credits remaining',
                          fr: '$purchasedText crédits restants',
                          es: '$purchasedText créditos restantes',
                        ),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _t(
                          nl: 'Aangekochte PDF-credits · Vervallen nooit',
                          en: 'Purchased PDF credits · Never expire',
                          fr: 'Crédits PDF achetés · N\'expirent jamais',
                          es: 'Créditos PDF comprados · No caducan nunca',
                        ),
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12.4,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.border.withOpacity(0.9)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    includedText,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  if (periodEnd.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _t(
                        nl: 'Nieuwe maandbundel op ${_humanDate(periodEnd)}',
                        en: 'New monthly bundle on ${_humanDate(periodEnd)}',
                        fr: 'Nouveau lot mensuel le ${_humanDate(periodEnd)}',
                        es: 'Nuevo paquete mensual el ${_humanDate(periodEnd)}',
                      ),
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (lastGranted.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _t(
                        nl: 'Laatst aangekocht op ${_humanDate(lastGranted)}',
                        en: 'Last purchased on ${_humanDate(lastGranted)}',
                        fr: 'Dernier achat le ${_humanDate(lastGranted)}',
                        es: 'Última compra el ${_humanDate(lastGranted)}',
                      ),
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget buildBundleCard(
      PdfBundleOffer bundle, {
      required double layoutWidth,
      required double cardWidth,
    }) {
      final pdfs = bundle.pdfs;
      final actionable = _pdfBundleIsActionable(pdfs);
      final busy = actionable && _pdfBundleBusyStarting(pdfs);
      final ownedQty = _pdfBundleActiveQuantity(profile, pdfs);
      final canPress = actionable && isActive && checkoutEnabled && !busy;
      return Container(
        width: cardWidth,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: _panelSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _gold.withOpacity(palette.isDark ? 0.50 : 0.38),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _premiumIconBadge(
                  icon: Icons.picture_as_pdf_outlined,
                  accent: _gold,
                  layoutWidth: layoutWidth,
                  role: _PremiumIconRole.pdfPackage,
                  cardWidth: cardWidth,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _t(
                      nl: '${_formatThousands(pdfs)} PDF\u2019s',
                      en: '${_formatThousands(pdfs)} PDFs',
                      fr: '${_formatThousands(pdfs)} PDF',
                      es: '${_formatThousands(pdfs)} PDF',
                    ),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _priceFromCents(bundle.priceCents),
                  style: TextStyle(
                    color: _gold,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _pdfOneTimeLabel(),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (ownedQty > 0) ...[
              const SizedBox(height: 6),
              _chip(
                text: _t(
                  nl: '$ownedQty gekocht',
                  en: '$ownedQty purchased',
                  fr: '$ownedQty achetés',
                  es: '$ownedQty comprados',
                ),
                bg: _green.withOpacity(0.16),
                border: _green.withOpacity(0.55),
                textColor: _green,
                icon: Icons.check_circle_outline,
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canPress
                    ? () => _startPdfBundleCheckout(profile, pdfs)
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: palette.textOnAccent,
                  disabledBackgroundColor: palette.surfaceAlt.withOpacity(
                    palette.isDark ? 0.66 : 0.92,
                  ),
                  disabledForegroundColor: palette.textMuted,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: busy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.textOnAccent.withOpacity(0.75),
                        ),
                      )
                    : const Icon(Icons.shopping_cart_outlined, size: 18),
                label: Text(
                  _pdfBuyLabel(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final bundles = catalog.pdfBundles;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final int cols = width >= 720 ? 3 : (width >= 420 ? 2 : 1);
        final double spacing = 10;
        final double cardW = cols == 1
            ? width
            : (width - spacing * (cols - 1)) / cols;
        final purchaseCards = <Widget>[
          for (final bundle in bundles)
            buildBundleCard(bundle, layoutWidth: width, cardWidth: cardW),
        ];
        final history = _pdfPurchaseHistoryExpander(profile);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildBalance(width),
            const SizedBox(height: 12),
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: purchaseCards,
            ),
            if (!isActive && checkoutEnabled) ...[
              const SizedBox(height: 8),
              Text(
                _addonRequiresActiveMessage(),
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
            if (!checkoutEnabled) ...[
              const SizedBox(height: 8),
              _playSaasManagedOutsideNotice(),
            ],
            if (history != null) ...[const SizedBox(height: 8), history],
          ],
        );
      },
    );
  }

  /// Optional compact history expander summarising how many of each bundle
  /// have been purchased so far. Returns null when there is nothing to show.
  Widget? _pdfPurchaseHistoryExpander(BackendSubscriptionProfile profile) {
    final entries = <(int, int)>[
      (500, profile.pdf500ActiveQuantity),
      (1000, profile.pdf1000ActiveQuantity),
      (5000, profile.pdf5000ActiveQuantity),
    ].where((e) => e.$2 > 0).toList(growable: false);
    if (entries.isEmpty) return null;
    final palette = _businessThemePalette;
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: Colors.transparent,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: _panelSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.border.withOpacity(0.85)),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          iconColor: palette.textSecondary,
          collapsedIconColor: palette.textSecondary,
          title: Text(
            _t(
              nl: 'Aankoophistoriek',
              en: 'Purchase history',
              fr: 'Historique des achats',
              es: 'Historial de compras',
            ),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          children: [
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 16,
                      color: palette.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _t(
                          nl: '${e.$2} × pakket ${_formatThousands(e.$1)}',
                          en: '${e.$2} × ${_formatThousands(e.$1)} pack',
                          fr: '${e.$2} × pack de ${_formatThousands(e.$1)}',
                          es: '${e.$2} × paquete de ${_formatThousands(e.$1)}',
                        ),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Premium hero card for the current subscription. Displays plan title,
  /// market, status, monthly recurring amount, breakdown of active add-ons,
  /// billing dates, next payment, billing email, entitlement banner,
  /// activation/cancellation controls, and (only when the customer is a real
  /// founder or has the founder price locked) a small founder banner.
  Widget _buildSubscriptionHero(
    BackendSubscriptionProfile profile,
    SubscriptionPlanCatalogEntry catalog,
  ) {
    final palette = _businessThemePalette;
    final effectiveStatus = profile.subscriptionStatus.trim().isNotEmpty
        ? profile.subscriptionStatus
        : profile.status;
    final isPaidActive = effectiveStatus.trim().toLowerCase() == 'active';
    final statusColors = _statusColors(effectiveStatus);

    final int? lockedCents = profile.lockedPriceCents;
    final int? founderCents =
        profile.founderPriceCents ?? catalog.founderPriceCents;
    final bool isFounderLocked =
        profile.isFounderCustomer ||
        (lockedCents != null &&
            founderCents != null &&
            lockedCents == founderCents);

    // Big monthly amount: prefer the actual provider recurring when linked,
    // else fall back to locked/normal price.
    final int monthlyCents =
        (_hasProviderSubscription(profile) &&
            profile.recurringAmountCents != null)
        ? profile.recurringAmountCents!
        : (lockedCents ?? catalog.normalPriceCents);
    final String monthlyText = _priceFromCents(monthlyCents);

    // Breakdown line only when at least one paid add-on is active.
    final int vQty = _extraVehicleActiveQuantity(profile);
    final int dQty = _extraDriverActiveQuantity(profile);
    final int baseCents = lockedCents ?? catalog.normalPriceCents;
    final String baseText = _priceFromCents(baseCents);
    final String extraVehicleText = _priceFromCents(
      catalog.extraVehiclePriceCents,
    );
    final String extraDriverText = _priceFromCents(
      catalog.extraDriverPriceCents,
    );
    final breakdownParts = <String>[
      _t(
        nl: 'Basis $baseText',
        en: 'Base $baseText',
        fr: 'Base $baseText',
        es: 'Base $baseText',
      ),
    ];
    if (vQty > 0) {
      breakdownParts.add(
        _t(
          nl: '$vQty × extra voertuig $extraVehicleText',
          en: '$vQty × extra vehicle $extraVehicleText',
          fr: '$vQty × véhicule supplémentaire $extraVehicleText',
          es: '$vQty × vehículo extra $extraVehicleText',
        ),
      );
    }
    if (dQty > 0) {
      breakdownParts.add(
        _t(
          nl: '$dQty × extra chauffeur $extraDriverText',
          en: '$dQty × extra driver $extraDriverText',
          fr: '$dQty × chauffeur supplémentaire $extraDriverText',
          es: '$dQty × conductor extra $extraDriverText',
        ),
      );
    }
    final String breakdownText = breakdownParts.join(' • ');

    final periodStart = profile.currentPeriodStart.trim();
    final periodEnd = profile.currentPeriodEnd.trim();
    final renewalLine = _consolidatedRenewalLine(profile);

    final marketDisplay = _marketDisplayName(catalog.market);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _gold.withOpacity(palette.isDark ? 0.60 : 0.45),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(_gold.withOpacity(0.10), palette.surface),
            palette.surfaceAlt,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
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
                        nl: 'Fluxidi Pro',
                        en: 'Fluxidi Pro',
                        fr: 'Fluxidi Pro',
                        es: 'Fluxidi Pro',
                      ),
                      style: TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      marketDisplay.isEmpty
                          ? _planDisplayName(profile, catalog.market)
                          : marketDisplay,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _chip(
                text: _statusLabel(effectiveStatus),
                bg: statusColors.bg,
                border: statusColors.border,
                textColor: statusColors.text,
                icon: Icons.verified_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                monthlyText,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _t(
                    nl: '/ maand excl. btw',
                    en: '/ month excl. VAT',
                    fr: '/ mois HT',
                    es: '/ mes sin IVA',
                  ),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (vQty > 0 || dQty > 0) ...[
            const SizedBox(height: 6),
            Text(
              breakdownText,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
          if (isFounderLocked) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
              decoration: BoxDecoration(
                color: _gold.withOpacity(palette.isDark ? 0.14 : 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _gold.withOpacity(0.55)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.workspace_premium_outlined,
                    size: 18,
                    color: _gold,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _t(
                        nl: 'Founderprijs vastgezet zolang dit abonnement actief blijft.',
                        en: 'Founder price locked for as long as this subscription stays active.',
                        fr: 'Tarif fondateur verrouillé tant que cet abonnement reste actif.',
                        es: 'Precio fundador fijado mientras esta suscripción siga activa.',
                      ),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          _buildEntitlementStateBanner(profile),
          if (periodStart.isNotEmpty || periodEnd.isNotEmpty) ...[
            const SizedBox(height: 10),
            _infoLine(
              _t(
                nl: 'Actief van',
                en: 'Active from',
                fr: 'Actif du',
                es: 'Activo desde',
              ),
              periodStart.isEmpty
                  ? '—'
                  : '${_humanDate(periodStart)} → ${periodEnd.isEmpty ? "—" : _humanDate(periodEnd)}',
              icon: Icons.event_available_outlined,
            ),
          ],
          if (renewalLine != null) ...[
            _infoLine(
              _t(
                nl: 'Volgende betaling',
                en: 'Next payment',
                fr: 'Prochain paiement',
                es: 'Próximo pago',
              ),
              renewalLine.replaceFirst(RegExp(r'^[^:]+:\s*'), ''),
              icon: Icons.payments_outlined,
            ),
          ],
          if (profile.billingEmail.trim().isNotEmpty)
            _infoLine(
              _t(
                nl: 'Facturatie-email',
                en: 'Billing email',
                fr: 'E-mail de facturation',
                es: 'Correo de facturación',
              ),
              profile.billingEmail,
              icon: Icons.email_outlined,
            ),
          if (!isPaidActive) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _chip(
                  text: _t(
                    nl: '2 weken gratis proefperiode',
                    en: '2 weeks free trial',
                    fr: '2 semaines d\'essai gratuit',
                    es: '2 semanas de prueba gratis',
                  ),
                  bg: _green.withOpacity(0.16),
                  border: _green.withOpacity(0.55),
                  textColor: _green,
                  icon: Icons.schedule_outlined,
                ),
              ],
            ),
            const SizedBox(height: 4),
            _infoLine(
              _t(
                nl: 'Proefperiode start/einde',
                en: 'Trial start/end',
                fr: 'Début/fin essai',
                es: 'Inicio/fin de prueba',
              ),
              '${profile.trialStartedAt.trim().isEmpty ? "—" : _humanDate(profile.trialStartedAt)} / ${profile.trialEndsAt.trim().isEmpty ? "—" : _humanDate(profile.trialEndsAt)}',
              icon: Icons.schedule_outlined,
            ),
          ],
          _buildActivationSection(profile, catalog),
          _buildCancellationSection(profile),
        ],
      ),
    );
  }

  /// Human-readable market/country label for the hero title.
  String _marketDisplayName(String marketRaw) {
    switch (marketRaw.trim().toUpperCase()) {
      case 'BE':
        return _t(nl: 'België', en: 'Belgium', fr: 'Belgique', es: 'Bélgica');
      case 'NL':
        return _t(
          nl: 'Nederland',
          en: 'Netherlands',
          fr: 'Pays-Bas',
          es: 'Países Bajos',
        );
      case 'FR':
        return _t(nl: 'Frankrijk', en: 'France', fr: 'France', es: 'Francia');
      case 'ES':
        return _t(nl: 'Spanje', en: 'Spain', fr: 'Espagne', es: 'España');
      case 'LU':
        return _t(
          nl: 'Luxemburg',
          en: 'Luxembourg',
          fr: 'Luxembourg',
          es: 'Luxemburgo',
        );
      case 'DE':
        return _t(
          nl: 'Duitsland',
          en: 'Germany',
          fr: 'Allemagne',
          es: 'Alemania',
        );
      case 'PT':
        return _t(
          nl: 'Portugal',
          en: 'Portugal',
          fr: 'Portugal',
          es: 'Portugal',
        );
      default:
        return '';
    }
  }

  /// KPI row (Vehicles / Drivers / PDF this month). Responsive:
  /// - width >= 720: 3 equal cards side-by-side
  /// - width >= 420: 2 columns wrap
  /// - else: 1 column stacked
  Widget _buildUsageLimitsRow(
    BackendSubscriptionProfile profile,
    SubscriptionPlanCatalogEntry catalog,
    int usedVehicles,
    int usedDrivers,
  ) {
    final palette = _businessThemePalette;
    final vehicleSlots = profile.maxVehicles > 0 ? profile.maxVehicles : 1;
    final int pdfCap =
        catalog.includedPdfCreationsPerVehicleMonth * vehicleSlots;
    final int pdfUsed = profile.pdfMonthlyUsed > 0 ? profile.pdfMonthlyUsed : 0;

    Widget kpi({
      required IconData icon,
      required String title,
      required int used,
      required int max,
      required Color accent,
      required double layoutWidth,
      required double cardWidth,
    }) {
      final double progress = max <= 0 ? 0.0 : (used / max).clamp(0.0, 1.0);
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: _panelSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border.withOpacity(0.9)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _premiumIconBadge(
                  icon: icon,
                  accent: accent,
                  layoutWidth: layoutWidth,
                  role: _PremiumIconRole.kpi,
                  cardWidth: cardWidth,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _formatThousands(used),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '/ ${_formatThousands(max)}',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: progress,
                backgroundColor: palette.border.withOpacity(
                  palette.isDark ? 0.55 : 0.65,
                ),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final int cols = width >= 720 ? 3 : (width >= 420 ? 2 : 1);
        final double spacing = 10;
        final double cardW = cols == 1
            ? width
            : (width - spacing * (cols - 1)) / cols;
        final cards = <Widget>[
          SizedBox(
            width: cardW,
            child: kpi(
              icon: Icons.directions_car_filled_outlined,
              title: _t(
                nl: 'Voertuigen',
                en: 'Vehicles',
                fr: 'Véhicules',
                es: 'Vehículos',
              ),
              used: usedVehicles,
              max: profile.maxVehicles,
              accent: _green,
              layoutWidth: width,
              cardWidth: cardW,
            ),
          ),
          SizedBox(
            width: cardW,
            child: kpi(
              icon: Icons.badge_outlined,
              title: _t(
                nl: 'Chauffeurs',
                en: 'Drivers',
                fr: 'Chauffeurs',
                es: 'Conductores',
              ),
              used: usedDrivers,
              max: profile.maxDrivers,
              accent: _secondaryAccent,
              layoutWidth: width,
              cardWidth: cardW,
            ),
          ),
          SizedBox(
            width: cardW,
            child: kpi(
              icon: Icons.picture_as_pdf_outlined,
              title: _t(
                nl: 'PDF deze maand',
                en: 'PDF this month',
                fr: 'PDF ce mois',
                es: 'PDF este mes',
              ),
              used: pdfUsed,
              max: pdfCap,
              accent: _gold,
              layoutWidth: width,
              cardWidth: cardW,
            ),
          ),
        ];
        return Wrap(spacing: spacing, runSpacing: spacing, children: cards);
      },
    );
  }

  /// Monthly add-ons section: extra vehicle + extra driver.
  /// Restyled cards preserving the existing footer widgets so cancel / undo /
  /// paid-through / renewal states keep working unchanged.
  Widget _buildMonthlyAddonsSection(
    BackendSubscriptionProfile profile,
    SubscriptionPlanCatalogEntry catalog,
  ) {
    final palette = _businessThemePalette;
    final int vQty = _extraVehicleActiveQuantity(profile);
    final int dQty = _extraDriverActiveQuantity(profile);

    Widget card({
      required IconData icon,
      required Color accent,
      required String title,
      required String priceLabel,
      required String benefitLabel,
      required int qtyActive,
      required String qtyBadge,
      required Widget footer,
      required double layoutWidth,
      required double cardWidth,
    }) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: _panelSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _gold.withOpacity(palette.isDark ? 0.48 : 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _premiumIconBadge(
                  icon: icon,
                  accent: accent,
                  layoutWidth: layoutWidth,
                  role: _PremiumIconRole.extension,
                  cardWidth: cardWidth,
                  muted: qtyActive <= 0,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _chip(
                  text: qtyBadge,
                  bg: qtyActive > 0
                      ? _green.withOpacity(0.16)
                      : palette.surface,
                  border: qtyActive > 0
                      ? _green.withOpacity(0.55)
                      : palette.border.withOpacity(0.9),
                  textColor: qtyActive > 0 ? _green : palette.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              priceLabel,
              style: TextStyle(
                color: _gold,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              benefitLabel,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            footer,
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final bool twoCols = width >= 720;
        final double spacing = 10;
        final double cardW = twoCols ? (width - spacing) / 2 : width;
        final vehicleCard = card(
          icon: Icons.directions_car_filled_outlined,
          accent: _green,
          title: _t(
            nl: 'Extra voertuig',
            en: 'Extra vehicle',
            fr: 'Véhicule supplémentaire',
            es: 'Vehículo extra',
          ),
          priceLabel: _t(
            nl: '+ ${_priceFromCents(catalog.extraVehiclePriceCents)} / maand',
            en: '+ ${_priceFromCents(catalog.extraVehiclePriceCents)} / month',
            fr: '+ ${_priceFromCents(catalog.extraVehiclePriceCents)} / mois',
            es: '+ ${_priceFromCents(catalog.extraVehiclePriceCents)} / mes',
          ),
          benefitLabel: _t(
            nl: 'Voegt 1 voertuigplek toe, inclusief ${catalog.includedDriversPerVehicle} chauffeurs.',
            en: 'Adds 1 vehicle slot, including ${catalog.includedDriversPerVehicle} drivers.',
            fr: 'Ajoute 1 emplacement de véhicule, y compris ${catalog.includedDriversPerVehicle} chauffeurs.',
            es: 'Añade 1 plaza de vehículo, incluidos ${catalog.includedDriversPerVehicle} conductores.',
          ),
          qtyActive: vQty,
          qtyBadge: _t(
            nl: '$vQty actief',
            en: '$vQty active',
            fr: '$vQty actif',
            es: '$vQty activo',
          ),
          footer: _extraVehicleAddonFooter(profile),
          layoutWidth: width,
          cardWidth: cardW,
        );

        final driverCard = card(
          icon: Icons.badge_outlined,
          accent: _secondaryAccent,
          title: _t(
            nl: 'Extra chauffeur',
            en: 'Extra driver',
            fr: 'Chauffeur supplémentaire',
            es: 'Conductor extra',
          ),
          priceLabel: _t(
            nl: '+ ${_priceFromCents(catalog.extraDriverPriceCents)} / maand',
            en: '+ ${_priceFromCents(catalog.extraDriverPriceCents)} / month',
            fr: '+ ${_priceFromCents(catalog.extraDriverPriceCents)} / mois',
            es: '+ ${_priceFromCents(catalog.extraDriverPriceCents)} / mes',
          ),
          benefitLabel: _t(
            nl: 'Voegt 1 chauffeur toe zonder een voertuigplek te openen.',
            en: 'Adds 1 driver without opening a new vehicle slot.',
            fr: 'Ajoute 1 chauffeur sans ouvrir de nouvel emplacement.',
            es: 'Añade 1 conductor sin abrir una plaza de vehículo.',
          ),
          qtyActive: dQty,
          qtyBadge: _t(
            nl: '$dQty actief',
            en: '$dQty active',
            fr: '$dQty actif',
            es: '$dQty activo',
          ),
          footer: _extraDriverAddonFooter(profile),
          layoutWidth: width,
          cardWidth: cardW,
        );

        if (!twoCols) {
          return Column(
            children: [vehicleCard, const SizedBox(height: 10), driverCard],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: vehicleCard),
            SizedBox(width: spacing),
            Expanded(child: driverCard),
          ],
        );
      },
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
          actions: [
            IconButton(
              tooltip: _t(
                nl: 'Vernieuwen',
                en: 'Refresh',
                fr: 'Actualiser',
                es: 'Actualizar',
              ),
              icon: const Icon(Icons.refresh),
              onPressed: _activating ? null : _refresh,
            ),
          ],
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
            // Country-aware catalog drives all visible pricing copy. If the
            // backend profile didn't ship catalog fields the resolver fills
            // in BE/NL/FR/ES/PT defaults from the active company's market.
            final catalog = resolveSubscriptionCatalogEntryForMarket(
              profile.market.trim().isNotEmpty
                  ? profile.market
                  : resolveActiveCompanyPricingMarket(),
            );
            // BE is the only market that ships Belgian-specific compliance
            // modules (Chiron, Billit/Peppol). Non-BE supported markets see
            // a generic automation pitch instead — no Chiron/Billit/Peppol
            // claims.
            final bool isBelgiumMarket = catalog.market == 'BE';
            // Gate the paid add-ons section on the real (profile) market, not
            // the display catalog (which falls back to BE for unsupported
            // countries). Unsupported markets must not see paid add-ons that
            // have no purchase path yet.
            final bool isSupportedMarket = _isSupportedMarket(
              _effectiveMarket(profile),
            );
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
                    // Use viewPadding so gesture/nav bars are respected even
                    // when nested MediaQuery.padding was consumed.
                    final bottomSafeInset = MediaQuery.viewPaddingOf(
                      context,
                    ).bottom;
                    return ListView(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        12,
                        12,
                        24 + bottomSafeInset,
                      ),
                      children: [
                        _buildSubscriptionHero(profile, catalog),
                        _sectionCard(
                          title: _t(
                            nl: 'Gebruik & limieten',
                            en: 'Usage & limits',
                            fr: 'Utilisation & limites',
                            es: 'Uso & límites',
                          ),
                          child: _buildUsageLimitsRow(
                            profile,
                            catalog,
                            usedVehicles,
                            usedDrivers,
                          ),
                        ),
                        if (isSupportedMarket)
                          _sectionCard(
                            title: _t(
                              nl: 'Maandelijkse uitbreidingen',
                              en: 'Monthly add-ons',
                              fr: 'Options mensuelles',
                              es: 'Ampliaciones mensuales',
                            ),
                            child: _buildMonthlyAddonsSection(profile, catalog),
                          ),
                        _sectionCard(
                          title: _t(
                            nl: 'PDF-credits',
                            en: 'PDF credits',
                            fr: 'Crédits PDF',
                            es: 'Créditos PDF',
                          ),
                          child: _buildPdfCreditsSection(profile, catalog),
                        ),
                        _sectionCard(
                          title: _t(
                            nl: 'Inbegrepen mogelijkheden',
                            en: 'Included capabilities',
                            fr: 'Fonctionnalités incluses',
                            es: 'Capacidades incluidas',
                          ),
                          child: _buildIncludedFeatures(
                            profile,
                            catalog,
                            isBelgiumMarket,
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          decoration: BoxDecoration(
                            color: _panel,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _businessThemePalette.border.withOpacity(
                                _businessThemePalette.isDark ? 0.75 : 0.85,
                              ),
                            ),
                          ),
                          child: Text(
                            isBelgiumMarket
                                ? _t(
                                    nl: 'Externe Billit/providerkosten en Mollie-transactiekosten zijn voor rekening van het bedrijf en lopen via je eigen account.',
                                    en: 'External Billit/provider costs and Mollie transaction fees are paid by the company via its own account.',
                                    fr: 'Les frais Billit/fournisseur externes et les frais de transaction Mollie sont à la charge de l\'entreprise via son propre compte.',
                                    es: 'Los costes externos de Billit/proveedor y las comisiones de transacción de Mollie corren a cargo de la empresa a través de su propia cuenta.',
                                  )
                                : _t(
                                    nl: 'Mollie-transactiekosten zijn voor rekening van het bedrijf en lopen via je eigen account.',
                                    en: 'Mollie transaction fees are paid by the company via its own account.',
                                    fr: 'Les frais de transaction Mollie sont à la charge de l\'entreprise via son propre compte.',
                                    es: 'Las comisiones de transacción de Mollie corren a cargo de la empresa a través de su propia cuenta.',
                                  ),
                            style: TextStyle(
                              color: _businessThemePalette.textSecondary,
                              fontSize: 12,
                              height: 1.35,
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
