import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';

/// First-version Fluxidi business orientation / product-tour flow.
///
/// Shown ONCE, immediately after [BusinessFirstRunWizardPage] reports
/// successful completion (its `onFinished` callback) and BEFORE
/// `_navigateToBusinessHomeWithBootstrapHydration` lands the freshly
/// onboarded operator on BusinessHomePage. The wizard's separate
/// "Finish setup later" path (`onSkipped`) intentionally bypasses this
/// flow — operators who explicitly defer setup land directly on the
/// cockpit, exactly as before.
///
/// This page is app-only and side-effect free:
/// * does NOT touch any backend / Chiron / booking / pricing / payment
///   / driver / customer / airport / hotel / event / public-booking
///   logic,
/// * does NOT add image assets — uses Material icons + gradient/glow
///   only,
/// * does NOT autoplay — manual nav via swipe + Previous / Next / Skip
///   / final "Go to cockpit" CTA,
/// * does NOT keep its own persistent state (one-shot orientation).
class BusinessOrientationFlowPage extends StatefulWidget {
  const BusinessOrientationFlowPage({
    super.key,
    required this.onFinish,
    this.onSkip,
  });

  /// Invoked when the operator presses the final-page "Go to cockpit"
  /// CTA. The host is responsible for navigating onwards (typically via
  /// `_navigateToBusinessHomeWithBootstrapHydration` so token hydration
  /// and inventory backfill stay identical to the wizard's pre-existing
  /// completion path).
  final VoidCallback onFinish;

  /// Invoked when the operator presses the top-right "Skip" action on
  /// any non-final page. When null, this falls through to [onFinish] so
  /// the user always lands on BusinessHomePage rather than getting
  /// stuck on the orientation flow.
  final VoidCallback? onSkip;

  @override
  State<BusinessOrientationFlowPage> createState() =>
      _BusinessOrientationFlowPageState();
}

class _BusinessOrientationFlowPageState
    extends State<BusinessOrientationFlowPage>
    with TickerProviderStateMixin {
  late final PageController _pageController = PageController();

  /// Card-content fade-in + slide-up. Reset and forwarded once per page
  /// change so each card "lands" with a subtle entrance animation.
  late final AnimationController _entranceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  /// Subtle accent-line pulse (looped). Drives both the line's width
  /// and opacity so the card has a low-noise breathing accent without
  /// pulling attention away from the title/body.
  late final AnimationController _accentController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  int _index = 0;

  /// Premium navy / gold palette — matches the dark-navy/gold styling
  /// already used by [CompanyOnboardingPage] and
  /// [BusinessFirstRunSetupChoicePage] so the post-onboarding journey
  /// feels visually continuous before the (theme-aware) cockpit takes
  /// over.
  static const Color _bg = Color(0xFF0B1020);
  static const Color _panelTop = Color(0xFF121A2E);
  static const Color _panelBottom = Color(0xFF0F1726);
  static const Color _gold = Color(0xFFE5B641);

  static const List<_OrientationCardData> _cards = <_OrientationCardData>[
    _OrientationCardData(
      id: 'welcome',
      icon: Icons.celebration_outlined,
      title: _Tr(
        nl: 'Welkom bij Fluxidi',
        en: 'Welcome to Fluxidi',
        fr: 'Bienvenue sur Fluxidi',
        es: 'Bienvenido a Fluxidi',
      ),
      body: _Tr(
        nl: 'Het premium platform voor uw taxibedrijf. We laten u in een paar stappen zien hoe u alles kunt beheren.',
        en: "The premium platform for your taxi business. We'll walk you through how to manage everything in just a few steps.",
        fr: 'La plateforme premium pour votre entreprise de taxi. Découvrez en quelques étapes comment tout gérer.',
        es: 'La plataforma premium para tu empresa de taxis. Te mostraremos en pocos pasos cómo gestionarlo todo.',
      ),
    ),
    _OrientationCardData(
      id: 'central_cockpit',
      icon: Icons.dashboard_outlined,
      title: _Tr(
        nl: 'Uw centrale cockpit',
        en: 'Your central cockpit',
        fr: 'Votre cockpit central',
        es: 'Tu cabina central',
      ),
      body: _Tr(
        nl: 'Vanaf uw hoofdscherm beheert u boekingen, chauffeurs, prijzen en meer — alles op één plek.',
        en: 'From your home screen you manage bookings, drivers, pricing and more — all in one place.',
        fr: 'Depuis votre tableau de bord, gérez réservations, chauffeurs, tarifs et plus encore — au même endroit.',
        es: 'Desde tu pantalla principal gestionas reservas, conductores, tarifas y más — todo en un solo lugar.',
      ),
    ),
    _OrientationCardData(
      id: 'manage_bookings',
      icon: Icons.event_available_outlined,
      title: _Tr(
        nl: 'Beheer boekingen centraal',
        en: 'Manage bookings centrally',
        fr: 'Gérez vos réservations en un seul endroit',
        es: 'Gestiona tus reservas centralmente',
      ),
      body: _Tr(
        nl: 'Bekijk al uw ritten in één overzicht. Bevestig, wijs toe of pas aan zonder van scherm te wisselen.',
        en: 'See all your rides in one overview. Confirm, assign or adjust without switching screens.',
        fr: "Visualisez toutes vos courses dans une seule vue. Confirmez, attribuez ou ajustez sans changer d'écran.",
        es: 'Visualiza todos tus viajes en una sola vista. Confirma, asigna o ajusta sin cambiar de pantalla.',
      ),
    ),
    _OrientationCardData(
      id: 'manage_drivers_vehicles',
      icon: Icons.local_taxi_outlined,
      title: _Tr(
        nl: 'Beheer chauffeurs en voertuigen',
        en: 'Manage drivers and vehicles',
        fr: 'Gérez chauffeurs et véhicules',
        es: 'Gestiona conductores y vehículos',
      ),
      body: _Tr(
        nl: 'Voeg chauffeurs toe, koppel voertuigen en houd documenten up-to-date — vanaf uw telefoon of tablet.',
        en: 'Add drivers, link vehicles and keep documents up to date — from your phone or tablet.',
        fr: 'Ajoutez vos chauffeurs, associez les véhicules et gardez les documents à jour — depuis votre téléphone ou tablette.',
        es: 'Añade conductores, vincula vehículos y mantén los documentos al día — desde tu móvil o tablet.',
      ),
    ),
    _OrientationCardData(
      id: 'public_booking_link',
      icon: Icons.share_outlined,
      title: _Tr(
        nl: 'Deel uw publieke boekingslink',
        en: 'Share your public booking link',
        fr: 'Partagez votre lien de réservation public',
        es: 'Comparte tu enlace público de reserva',
      ),
      body: _Tr(
        nl: 'Met uw eigen Fluxidi-link kunnen klanten direct online boeken — zonder telefoontje. Plaats hem op uw site, social media of QR-flyers.',
        en: 'Your own Fluxidi link lets customers book online directly — no phone call required. Add it to your site, socials or QR flyers.',
        fr: 'Votre lien Fluxidi permet à vos clients de réserver en ligne directement — sans appel. Ajoutez-le à votre site, vos réseaux sociaux ou vos flyers QR.',
        es: 'Tu enlace Fluxidi permite a los clientes reservar en línea — sin llamadas. Ponlo en tu web, redes sociales o folletos QR.',
      ),
    ),
    _OrientationCardData(
      id: 'customer_app',
      icon: Icons.smartphone_outlined,
      title: _Tr(
        nl: 'Stimuleer klanten om de Fluxidi-app te gebruiken',
        en: 'Encourage customers to use the Fluxidi app',
        fr: "Incitez vos clients à utiliser l'application Fluxidi",
        es: 'Anima a tus clientes a usar la app Fluxidi',
      ),
      body: _Tr(
        nl: 'Tevreden klanten boeken sneller en vaker via de Fluxidi-app. Deel het downloadlink-icoon vanuit uw cockpit.',
        en: 'Happy customers book faster and more often via the Fluxidi app. Share the download link icon straight from your cockpit.',
        fr: "Les clients satisfaits réservent plus vite et plus souvent via l'application Fluxidi. Partagez le lien de téléchargement depuis votre cockpit.",
        es: 'Los clientes satisfechos reservan más rápido y con más frecuencia desde la app Fluxidi. Comparte el icono del enlace de descarga desde tu cabina.',
      ),
    ),
    _OrientationCardData(
      id: 'ready_to_start',
      icon: Icons.rocket_launch_outlined,
      title: _Tr(
        nl: 'Klaar om te beginnen',
        en: 'Ready to start',
        fr: 'Prêt à démarrer',
        es: 'Listo para empezar',
      ),
      body: _Tr(
        nl: 'Alles is opgezet. U kunt nu uw cockpit openen en uw eerste rit ontvangen.',
        en: 'Everything is set up. You can now open your cockpit and take your first ride.',
        fr: 'Tout est prêt. Vous pouvez maintenant ouvrir votre cockpit et recevoir votre première course.',
        es: 'Todo está listo. Ahora puedes abrir tu cabina y recibir tu primer viaje.',
      ),
    ),
  ];

  @override
  void initState() {
    super.initState();
    debugPrint('[ORIENTATION_FLOW][OPEN] totalPages=${_cards.length}');
    _logCurrentPage();
    _entranceController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _entranceController.dispose();
    _accentController.dispose();
    super.dispose();
  }

  String _t(_Tr tr) {
    switch (appLanguageNotifier.value) {
      case AppLanguage.nl:
        return tr.nl;
      case AppLanguage.en:
        return tr.en;
      case AppLanguage.fr:
        return tr.fr;
      case AppLanguage.es:
        return tr.es;
    }
  }

  void _logCurrentPage() {
    debugPrint(
      '[ORIENTATION_FLOW][PAGE] index=${_index + 1}/${_cards.length} '
      'card=${_cards[_index].id}',
    );
  }

  void _onPageChanged(int next) {
    if (!mounted) return;
    setState(() => _index = next);
    _logCurrentPage();
    // Re-trigger entrance animation so each new card gets a subtle
    // fade + slide-up. Using forward(from: 0) is safe here regardless
    // of the controller's previous status.
    _entranceController.forward(from: 0);
  }

  Future<void> _goNext() async {
    if (!mounted) return;
    if (_index >= _cards.length - 1) {
      _finish();
      return;
    }
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _goPrev() async {
    if (!mounted) return;
    if (_index == 0) return;
    await _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _skip() {
    if (!mounted) return;
    debugPrint(
      '[ORIENTATION_FLOW][SKIP] from_index=${_index + 1}/${_cards.length} '
      'card=${_cards[_index].id}',
    );
    (widget.onSkip ?? widget.onFinish).call();
  }

  void _finish() {
    if (!mounted) return;
    debugPrint(
      '[ORIENTATION_FLOW][FINISH] '
      'last_index=${_index + 1}/${_cards.length}',
    );
    widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appLanguageNotifier,
      builder: (context, _) {
        final size = MediaQuery.sizeOf(context);
        // Phone landscape detection: tight vertical space → compact
        // padding, smaller icon, tighter button height. Mirrors the
        // height-based check used in `role_entry_page` for compact
        // phone-landscape detection. Used by every card for vertical
        // pacing.
        final bool isCompactHeight = size.height < 540;
        // Cap card width on tablet portrait/landscape so the long body
        // text never stretches into a single ugly line. Phones use the
        // full width of the parent constraint.
        final bool isTablet = size.shortestSide >= 600;
        final double maxCardWidth = isTablet ? 640 : double.infinity;

        return Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            child: Column(
              children: <Widget>[
                _buildTopBar(isCompactHeight),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: _onPageChanged,
                    itemCount: _cards.length,
                    itemBuilder: (ctx, i) {
                      return Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxCardWidth),
                          child: _buildCard(_cards[i], isCompactHeight),
                        ),
                      );
                    },
                  ),
                ),
                _buildBottomBar(
                  isCompactHeight,
                  isLast: _index == _cards.length - 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar(bool compact) {
    final isLast = _index == _cards.length - 1;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, compact ? 4 : 10, 12, compact ? 2 : 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            '${_index + 1} / ${_cards.length}',
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          // The Skip action is intentionally hidden on the final page —
          // the primary CTA there is "Go to cockpit", which already
          // ends the flow. Showing two ways out on the last page would
          // dilute the CTA.
          if (!isLast)
            TextButton(
              onPressed: _skip,
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: Text(
                _t(
                  const _Tr(
                    nl: 'Overslaan',
                    en: 'Skip',
                    fr: 'Ignorer',
                    es: 'Omitir',
                  ),
                ),
              ),
            )
          else
            // Reserve symmetric trailing space so the page counter
            // stays in the same horizontal slot as the user advances —
            // prevents the counter from jumping right when Skip
            // disappears on the final page.
            const SizedBox(height: 36, width: 36),
        ],
      ),
    );
  }

  Widget _buildBottomBar(bool compact, {required bool isLast}) {
    final double verticalButtonPadding = compact ? 10 : 14;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, compact ? 6 : 10, 20, compact ? 10 : 16),
      child: Column(
        children: <Widget>[
          _buildDots(),
          SizedBox(height: compact ? 8 : 14),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _index == 0 ? null : _goPrev,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white24,
                    side: BorderSide(
                      color: _index == 0 ? Colors.white12 : Colors.white24,
                    ),
                    padding: EdgeInsets.symmetric(
                      vertical: verticalButtonPadding,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_back_ios_new, size: 13),
                  label: Text(
                    _t(
                      const _Tr(
                        nl: 'Vorige',
                        en: 'Previous',
                        fr: 'Précédent',
                        es: 'Anterior',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _goNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: _bg,
                    padding: EdgeInsets.symmetric(
                      vertical: verticalButtonPadding,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(
                    isLast ? Icons.rocket_launch_outlined : Icons.arrow_forward,
                    size: 16,
                  ),
                  label: Text(
                    isLast
                        ? _t(
                            const _Tr(
                              nl: 'Naar cockpit',
                              en: 'Go to cockpit',
                              fr: 'Aller au cockpit',
                              es: 'Ir a la cabina',
                            ),
                          )
                        : _t(
                            const _Tr(
                              nl: 'Volgende',
                              en: 'Next',
                              fr: 'Suivant',
                              es: 'Siguiente',
                            ),
                          ),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(_cards.length, (i) {
        final bool active = i == _index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 18 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: active ? _gold : Colors.white24,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _buildCard(_OrientationCardData data, bool compact) {
    final double iconBoxSize = compact ? 44 : 64;

    // Stable baseline composition shared by all 7 cards (welcome
    // through "ready to start"). The only difference between cards
    // is the [data] they bind — icon, title, body. A future pass
    // may re-introduce a richer welcome layout, but for now Card 1
    // intentionally renders through this same path so we have a
    // known-good visual baseline before any redesign.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: compact ? 6 : 16),
      child: SingleChildScrollView(
        // ClampingScrollPhysics so the card doesn't bounce on iOS in
        // the rare case its content is taller than the viewport
        // (e.g. very tight phone-landscape with large system fonts).
        physics: const ClampingScrollPhysics(),
        child: Container(
          padding: EdgeInsets.all(compact ? 18 : 24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[_panelTop, _panelBottom],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _gold.withOpacity(0.18)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: _gold.withOpacity(0.06),
                blurRadius: 24,
                spreadRadius: 1,
              ),
            ],
          ),
          child: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[
              _entranceController,
              _accentController,
            ]),
            builder: (ctx, _) {
              final fade = CurvedAnimation(
                parent: _entranceController,
                curve: Curves.easeOutCubic,
              );
              final slide = Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(fade);
              final double accent = _accentController.value;
              final Widget body = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    height: 3,
                    width: 56 + (accent * 32),
                    decoration: BoxDecoration(
                      color: _gold.withOpacity(0.55 + accent * 0.45),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  SizedBox(height: compact ? 12 : 18),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _gold.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _gold.withOpacity(0.22)),
                    ),
                    child: Icon(data.icon, color: _gold, size: iconBoxSize),
                  ),
                  SizedBox(height: compact ? 10 : 18),
                  Text(
                    _t(data.title),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 18 : 22,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      letterSpacing: 0.1,
                    ),
                  ),
                  SizedBox(height: compact ? 6 : 10),
                  Text(
                    _t(data.body),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.78),
                      fontSize: compact ? 12.5 : 14,
                      height: 1.45,
                    ),
                  ),
                ],
              );
              return SlideTransition(
                position: slide,
                child: FadeTransition(opacity: fade, child: body),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OrientationCardData {
  const _OrientationCardData({
    required this.id,
    required this.icon,
    required this.title,
    required this.body,
  });

  /// Stable identifier used in `[ORIENTATION_FLOW][PAGE/SKIP]` logs so
  /// QA can grep for a specific card regardless of its position in the
  /// deterministic 7-card sequence.
  final String id;
  final IconData icon;
  final _Tr title;
  final _Tr body;
}

class _Tr {
  const _Tr({
    required this.nl,
    required this.en,
    required this.fr,
    required this.es,
  });

  final String nl;
  final String en;
  final String fr;
  final String es;
}
