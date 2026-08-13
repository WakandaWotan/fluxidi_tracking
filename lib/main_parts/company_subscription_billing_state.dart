part of '../main.dart';

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
  static const Color _warn = Color(0xFFFFB457);

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
        fluxidiPlaySaasManagedOutsideMessage(
          languageCode: currentLanguageCode,
        ),
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
        fluxidiPlaySaasManagedOutsideMessage(
          languageCode: currentLanguageCode,
        ),
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
        fluxidiPlaySaasManagedOutsideMessage(
          languageCode: currentLanguageCode,
        ),
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
              _t(
                nl: 'Opzeggen',
                en: 'Cancel',
                fr: 'Résilier',
                es: 'Cancelar',
              ),
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
  Widget _extraVehicleCancellationControls(
    BackendSubscriptionProfile profile,
  ) {
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
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
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
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
                    .withOpacity(
                  _businessThemePalette.isDark ? 0.66 : 0.92,
                ),
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
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
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
              _t(
                nl: 'Opzeggen',
                en: 'Cancel',
                fr: 'Résilier',
                es: 'Cancelar',
              ),
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

  Widget _extraDriverCancellationControls(
    BackendSubscriptionProfile profile,
  ) {
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
              style: const TextStyle(fontSize: 12.2, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
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
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
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
                    .withOpacity(
                  _businessThemePalette.isDark ? 0.66 : 0.92,
                ),
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
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
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
        fluxidiPlaySaasManagedOutsideMessage(
          languageCode: currentLanguageCode,
        ),
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

  /// Footer for a PDF bundle add-on card — purchase only (no cancel CTA).
  Widget? _pdfBundleAddonFooter(
    BackendSubscriptionProfile profile,
    int pdfs,
  ) {
    if (!_pdfBundleIsActionable(pdfs)) return null;
    if (!kFluxidiCompanySaasCheckoutEnabled) {
      return _playSaasManagedOutsideNotice();
    }
    final bool isActive = _profileIsActive(profile);
    final bool starting = _pdfBundleBusyStarting(pdfs);
    final activeQty = _pdfBundleActiveQuantity(profile, pdfs);
    if (isActive && activeQty > 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chip(
            text: _t(
              nl: 'Actief: $activeQty × $pdfs PDF\u2019s gekocht',
              en: 'Active: $activeQty × $pdfs PDFs purchased',
              fr: 'Actif : $activeQty × $pdfs PDF achetés',
              es: 'Activo: $activeQty × $pdfs PDF comprados',
            ),
            bg: _green.withOpacity(0.14),
            border: _green.withOpacity(0.45),
            textColor: _green,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: starting
                ? null
                : () => _startPdfBundleCheckout(profile, pdfs),
            child: Text(
              _t(
                nl: 'Nog een pakket van $pdfs toevoegen',
                en: 'Add another $pdfs pack',
                fr: 'Ajouter un autre pack de $pdfs',
                es: 'Añadir otro paquete de $pdfs',
              ),
              style: TextStyle(
                color: _businessThemePalette.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      );
    }
    final button = SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: (!isActive || starting)
            ? null
            : () => _startPdfBundleCheckout(profile, pdfs),
        style: FilledButton.styleFrom(
          backgroundColor: _gold,
          foregroundColor: Colors.black,
          disabledBackgroundColor: _businessThemePalette.surfaceAlt.withOpacity(
            _businessThemePalette.isDark ? 0.66 : 0.92,
          ),
          disabledForegroundColor: _businessThemePalette.textMuted,
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: starting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black54,
                ),
              )
            : const Icon(Icons.picture_as_pdf_outlined, size: 18),
        label: Text(
          _activatePdfBundleLabel(pdfs),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ),
    );
    if (isActive) return button;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        button,
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
              _t(
                nl: 'Opzeggen',
                en: 'Cancel',
                fr: 'Résilier',
                es: 'Cancelar',
              ),
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
      final periodStart = profile.currentPeriodStart.trim();
      final periodEnd = profile.currentPeriodEnd.trim();
      final lockedCents =
          profile.lockedPriceCents ??
          profile.founderPriceCents ??
          catalog.founderPriceCents;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _chip(
            text: _t(
              nl: 'Abonnement actief',
              en: 'Subscription active',
              fr: 'Abonnement actif',
              es: 'Suscripción activa',
            ),
            bg: _green.withOpacity(0.14),
            border: _green.withOpacity(0.52),
            textColor: _green,
            icon: Icons.verified_outlined,
          ),
          if (profile.isFounderCustomer) ...[
            const SizedBox(height: 6),
            Wrap(
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
          ],
          if (periodStart.isNotEmpty || periodEnd.isNotEmpty) ...[
            const SizedBox(height: 6),
            _infoLine(
              _t(
                nl: 'Actief van',
                en: 'Active from',
                fr: 'Actif du',
                es: 'Activo desde',
              ),
              periodStart.isEmpty
                  ? '—'
                  : '${_humanDate(periodStart)} t/m ${periodEnd.isEmpty ? "—" : _humanDate(periodEnd)}',
              icon: Icons.event_available_outlined,
            ),
          ],
          if (_hasProviderSubscription(profile) &&
              profile.recurringAmountCents != null &&
              periodEnd.isNotEmpty) ...[
            const SizedBox(height: 6),
            _infoLine(
              _t(
                nl: 'Volgende betaling',
                en: 'Next payment',
                fr: 'Prochain paiement',
                es: 'Próximo pago',
              ),
              '${_priceFromCents(profile.recurringAmountCents!)} op ${_humanDate(periodEnd)}',
              icon: Icons.payments_outlined,
            ),
          ],
        ],
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
    final status = (profile.subscriptionStatus.trim().isNotEmpty
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

  Widget _addonCard({
    required String title,
    required String price,
    required String subtitle,
    bool emphasized = false,
    Widget? footer,
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
          // Patch 2.4B / 2.8 / 2.9: cards that pass a [footer] (Extra vehicle,
          // Extra driver, pdf_500, pdf_1000) render a real action button.
          // Cards without a footer (e.g. pdf_5000) keep the passive "coming
          // soon" chip from Patch 2.2C.
          footer ??
              Align(
                alignment: Alignment.centerLeft,
                child: _chip(
                  text: _comingSoonLabel(),
                  bg: _businessThemePalette.surfaceAlt.withOpacity(
                    _businessThemePalette.isDark ? 0.66 : 0.92,
                  ),
                  border: _businessThemePalette.border.withOpacity(0.7),
                  textColor: _businessThemePalette.textMuted,
                  icon: Icons.schedule_outlined,
                ),
              ),
        ],
      ),
    );
  }

  String _comingSoonLabel() => _t(
    nl: 'Binnenkort beschikbaar',
    en: 'Coming soon',
    fr: 'Bientôt disponible',
    es: 'Próximamente',
  );

  Widget _usageCard({
    required String title,
    required int used,
    required int max,
    required String actionLabel,
    bool enforced = true,
  }) {
    final atOrOverLimit = max > 0 && used >= max;
    // Patch 2.2C: vehicle/driver limits are not hard-enforced yet, so an
    // over-limit state should not look alarming. Only show the warning accent
    // and action chip when the limit is actually enforced.
    final showWarning = atOrOverLimit && enforced;
    final accent = showWarning ? _warn : _green;
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
          if (showWarning) ...[
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

  /// Patch 2.10: PDF creations usage bar. Mirrors [_usageCard] visuals (title,
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _green.withOpacity(0.42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              nl: 'PDF-creaties',
              en: 'PDF creations',
              fr: 'Créations PDF',
              es: 'Creaciones PDF',
            ),
            style: TextStyle(
              color: _businessThemePalette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 12.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              nl: 'Inbegrepen deze maand: $used van $includedCap gebruikt',
              en: 'Included this month: $used of $includedCap used',
              fr: 'Inclus ce mois : $used sur $includedCap utilisés',
              es: 'Incluidas este mes: $used de $includedCap usadas',
            ),
            style: TextStyle(
              color: _businessThemePalette.textMuted,
              fontSize: 12.1,
              height: 1.35,
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
                color: _businessThemePalette.textMuted,
                fontSize: 12.1,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            _t(
              nl: 'Aangekochte PDF-credits: $purchased resterend',
              en: 'Purchased PDF credits: $purchased remaining',
              fr: 'Crédits PDF achetés : $purchased restants',
              es: 'Créditos PDF comprados: $purchased restantes',
            ),
            style: TextStyle(
              color: _businessThemePalette.textPrimary,
              fontSize: 12.2,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _t(
              nl: 'Vervallen nooit',
              en: 'Never expire',
              fr: 'N\'expirent jamais',
              es: 'No caducan nunca',
            ),
            style: TextStyle(
              color: _businessThemePalette.textMuted,
              fontSize: 11.8,
              height: 1.35,
            ),
          ),
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
                color: _businessThemePalette.textMuted,
                fontSize: 11.8,
                height: 1.35,
              ),
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
            final effectiveStatus =
                profile.subscriptionStatus.trim().isNotEmpty
                ? profile.subscriptionStatus
                : profile.status;
            final isPaidActive =
                effectiveStatus.trim().toLowerCase() == 'active';
            final statusColors = _statusColors(effectiveStatus);
            final trialRange =
                '${profile.trialStartedAt.trim().isEmpty ? "—" : _humanDate(profile.trialStartedAt)} / ${profile.trialEndsAt.trim().isEmpty ? "—" : _humanDate(profile.trialEndsAt)}';
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
            // BE is the only market that ships Belgian-specific compliance
            // modules (Chiron, Billit/Peppol). Non-BE supported markets see
            // a generic automation pitch instead — no Chiron/Billit/Peppol
            // claims.
            final bool isBelgiumMarket = catalog.market == 'BE';
            // Patch 2.2C: gate the paid add-ons section on the real (profile)
            // market, not the display catalog (which falls back to BE for
            // unsupported countries). Unsupported markets must not see paid
            // add-ons that have no purchase path yet.
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
                    final bottomSafeInset =
                        MediaQuery.viewPaddingOf(context).bottom;
                    return ListView(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        12,
                        12,
                        24 + bottomSafeInset,
                      ),
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
                                          _planDisplayName(
                                            profile,
                                            catalog.market,
                                          ),
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
                                    text: _statusLabel(effectiveStatus),
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
                              if (!isPaidActive) ...[
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
                              ],
                              _buildEntitlementStateBanner(profile),
                              _buildActivationSection(profile, catalog),
                              _buildCancellationSection(profile),
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
                              if (!isPaidActive)
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
                                  if (isBelgiumMarket) ...[
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
                                  ] else ...[
                                    _chip(
                                      text: _t(
                                        nl: 'Automatisatie',
                                        en: 'Automation',
                                        fr: 'Automatisation',
                                        es: 'Automatización',
                                      ),
                                      bg: _green.withOpacity(0.14),
                                      border: _green.withOpacity(0.45),
                                      textColor: _green,
                                    ),
                                    _chip(
                                      text: _t(
                                        nl: 'Dispatch',
                                        en: 'Dispatch',
                                        fr: 'Dispatch',
                                        es: 'Despacho',
                                      ),
                                      bg: _green.withOpacity(0.14),
                                      border: _green.withOpacity(0.45),
                                      textColor: _green,
                                    ),
                                    _chip(
                                      text: _t(
                                        nl: 'Boekingslink',
                                        en: 'Booking link',
                                        fr: 'Lien de réservation',
                                        es: 'Enlace de reserva',
                                      ),
                                      bg: _green.withOpacity(0.14),
                                      border: _green.withOpacity(0.45),
                                      textColor: _green,
                                    ),
                                    _chip(
                                      text: _t(
                                        nl: 'Klantflow',
                                        en: 'Customer flow',
                                        fr: 'Parcours client',
                                        es: 'Flujo del cliente',
                                      ),
                                      bg: _green.withOpacity(0.14),
                                      border: _green.withOpacity(0.45),
                                      textColor: _green,
                                    ),
                                    _chip(
                                      text: _t(
                                        nl: 'Chauffeurs',
                                        en: 'Drivers',
                                        fr: 'Chauffeurs',
                                        es: 'Conductores',
                                      ),
                                      bg: _green.withOpacity(0.14),
                                      border: _green.withOpacity(0.45),
                                      textColor: _green,
                                    ),
                                    _chip(
                                      text: _t(
                                        nl: 'Voertuigen',
                                        en: 'Vehicles',
                                        fr: 'Véhicules',
                                        es: 'Vehículos',
                                      ),
                                      bg: _green.withOpacity(0.14),
                                      border: _green.withOpacity(0.45),
                                      textColor: _green,
                                    ),
                                    _chip(
                                      text: _t(
                                        nl: 'Ritbeheer',
                                        en: 'Ride admin',
                                        fr: 'Gestion des courses',
                                        es: 'Administración de viajes',
                                      ),
                                      bg: _green.withOpacity(0.14),
                                      border: _green.withOpacity(0.45),
                                      textColor: _green,
                                    ),
                                  ],
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
                                enforced: false,
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
                                enforced: false,
                                actionLabel: _t(
                                  nl: 'Extra chauffeur activeren',
                                  en: 'Activate extra driver',
                                  fr: 'Activer un chauffeur supplementaire',
                                  es: 'Activar conductor extra',
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _t(
                                    nl: 'Limieten worden binnenkort gekoppeld aan uitbreidingen.',
                                    en: 'Limits will be linked to add-ons soon.',
                                    fr: 'Les limites seront bientôt liées aux extensions.',
                                    es: 'Los límites se vincularán pronto a las ampliaciones.',
                                  ),
                                  style: TextStyle(
                                    color: _businessThemePalette.textMuted
                                        .withOpacity(0.86),
                                    fontSize: 11.6,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildPdfCreditsSection(profile, catalog),
                              if (isBelgiumMarket) ...[
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                          color:
                                              _businessThemePalette.textMuted,
                                          fontSize: 11.6,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (isSupportedMarket)
                          _sectionCard(
                            title: _t(
                              nl: 'Betaalde uitbreidingen',
                              en: 'Paid add-ons',
                              fr: 'Extensions payantes',
                              es: 'Ampliaciones de pago',
                            ),
                            child: Column(
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _t(
                                      nl: 'Extra voertuigen, chauffeurs en PDF-pakketten zijn beschikbaar als uitbreidingen. Je huidige abonnement blijft actief.',
                                      en: 'Extra vehicles, drivers and PDF packs are available as add-ons. Your current subscription stays active.',
                                      fr: 'Les véhicules, chauffeurs et packs PDF supplémentaires sont disponibles en option. Votre abonnement actuel reste actif.',
                                      es: 'Los vehículos, conductores y paquetes PDF adicionales están disponibles como ampliaciones. Tu suscripción actual sigue activa.',
                                    ),
                                    style: TextStyle(
                                      color: _businessThemePalette.textMuted,
                                      fontSize: 11.8,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 9),
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
                                    nl: 'Voegt 1 voertuigplek toe, inclusief ${catalog.includedDriversPerVehicle} extra chauffeurs. PDF-limieten worden later apart als uitbreiding gekoppeld.',
                                    en: 'Adds 1 vehicle slot, including ${catalog.includedDriversPerVehicle} extra drivers. PDF limits will be linked later as a separate add-on.',
                                    fr: 'Ajoute 1 emplacement de véhicule, dont ${catalog.includedDriversPerVehicle} chauffeurs supplémentaires. Les limites PDF seront ajoutées plus tard comme extension distincte.',
                                    es: 'Añade 1 plaza de vehículo, incluidos ${catalog.includedDriversPerVehicle} conductores extra. Los límites de PDF se vincularán más adelante como ampliación independiente.',
                                  ),
                                  emphasized:
                                      usedVehicles >= profile.maxVehicles,
                                  // Patch 2.4B: only the Extra vehicle card is
                                  // wired to the live add-on checkout route.
                                  footer: _extraVehicleAddonFooter(profile),
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
                                  footer: _extraDriverAddonFooter(profile),
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
                                    footer: _pdfBundleAddonFooter(
                                      profile,
                                      bundle.pdfs,
                                    ),
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
                                active: true,
                                subtitle: _t(
                                  nl: 'Inbegrepen',
                                  en: 'Included',
                                  fr: 'Inclus',
                                  es: 'Incluido',
                                ),
                              ),
                              _moduleRow(
                                label: _t(
                                  nl: 'Online boekingsflow',
                                  en: 'Online booking flow',
                                  fr: 'Flux de réservation en ligne',
                                  es: 'Flujo de reserva en línea',
                                ),
                                active: true,
                                subtitle: _t(
                                  nl: 'Inbegrepen',
                                  en: 'Included',
                                  fr: 'Inclus',
                                  es: 'Incluido',
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
                                subtitle: _t(
                                  nl: 'Inbegrepen',
                                  en: 'Included',
                                  fr: 'Inclus',
                                  es: 'Incluido',
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
                                subtitle: _t(
                                  nl: 'Inbegrepen',
                                  en: 'Included',
                                  fr: 'Inclus',
                                  es: 'Incluido',
                                ),
                              ),
                              if (isBelgiumMarket) ...[
                                _moduleRow(
                                  label: _t(
                                    nl: 'Complianceoverzicht / Chiron-ready',
                                    en: 'Compliance dashboard / Chiron-ready',
                                    fr: 'Tableau conformité / Chiron-ready',
                                    es: 'Panel de cumplimiento / Chiron-ready',
                                  ),
                                  active:
                                      profile
                                          .features['compliance_dashboard'] ==
                                      true,
                                  subtitle: _t(
                                    nl: 'Inbegrepen',
                                    en: 'Included',
                                    fr: 'Inclus',
                                    es: 'Incluido',
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
                                label: _featureLabel('airport_module'),
                                active: true,
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
