import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:video_player/video_player.dart';

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
/// * uses a silent looping MP4 + same-aspect PNG poster as the Card 1
///   tablet portrait hero background ONLY; every other card and every
///   other layout still relies on Material icons + gradient/glow,
/// * does NOT autoplay the *carousel* — manual nav via swipe +
///   Previous / Next / Skip / final "Go to cockpit" CTA (the welcome
///   hero video does loop silently in the background, but it never
///   advances the page),
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

  /// Silent, looping background video for Card 1 in tablet portrait.
  /// Built lazily from the bundled asset; the actual platform
  /// resources are only allocated by [VideoPlayerController.initialize]
  /// inside [_initBgVideo].
  late final VideoPlayerController _bgVideoController =
      VideoPlayerController.asset(_card1WelcomeTabletPortraitVideoAsset);

  /// True once [_initBgVideo] successfully initialised the video and
  /// kicked off looping silent playback. Until then we render the PNG
  /// poster instead.
  bool _bgVideoReady = false;

  /// True if [_initBgVideo] caught an error during initialisation,
  /// `setLooping`, `setVolume`, or `play`. Once latched, we stick
  /// with the PNG fallback for the rest of the flow's lifetime —
  /// the video is decorative, never essential.
  bool _bgVideoFailed = false;

  /// Silent, looping background video for Card 1 in tablet landscape.
  /// Mirrors [_bgVideoController] but bound to the dedicated
  /// landscape MP4 so the orientation can keep playing the right
  /// asset across device rotations without re-initialisation
  /// hitches.
  late final VideoPlayerController _bgLandscapeVideoController =
      VideoPlayerController.asset(_card1WelcomeTabletLandscapeVideoAsset);

  /// True once [_initBgLandscapeVideo] successfully initialised the
  /// landscape video and kicked off looping silent playback. Until
  /// then we render the landscape PNG poster instead.
  bool _bgLandscapeVideoReady = false;

  /// True if [_initBgLandscapeVideo] caught an error. Once latched,
  /// we stick with the landscape PNG fallback for the rest of the
  /// flow's lifetime — the video is decorative, never essential.
  bool _bgLandscapeVideoFailed = false;

  /// One-shot latch for the `[ORIENTATION_FLOW][LANDSCAPE_LAYOUT]`
  /// diagnostic line. Logged the first build the full-viewport
  /// landscape hero is rendered with the video controller already
  /// initialised, so QA can confirm the viewport / media sizing in
  /// real-device runs without spamming logs on every frame.
  bool _landscapeLayoutLogged = false;

  /// Which Card 1 tablet-hero video lane is currently supposed to
  /// be playing. [none] means both controllers stay paused (Cards
  /// 2-7, phone layouts, or welcome on a phone). Updated by
  /// [_syncHeroVideoPlayback] whenever the active page or tablet
  /// orientation changes.
  _HeroVideoLane _syncedHeroVideoLane = _HeroVideoLane.none;

  /// Guards lazy initialisation so each orientation's MP4 is only
  /// decoded when that lane is actually needed — avoids paying for
  /// two simultaneous platform decoders on tablet open.
  bool _portraitVideoInitStarted = false;
  bool _landscapeVideoInitStarted = false;

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

  /// Near-black canvas applied to the Scaffold ONLY while Card 1 is
  /// the active page in tablet portrait, so the immersive video hero
  /// reads as a full-screen black/gold premium experience rather
  /// than a video card floating on the navy app palette. Every other
  /// card / layout keeps [_bg] for visual continuity with the rest of
  /// the post-onboarding journey.
  static const Color _heroBg = Color(0xFF050505);

  /// Silent, looping portrait MP4 (1244 × 1660, 5 s, 24 fps) used as
  /// the Card 1 tablet portrait hero background. Audio track is muted
  /// at runtime via [VideoPlayerController.setVolume].
  static const String _card1WelcomeTabletPortraitVideoAsset =
      'assets/fluxidi/onboarding/card1_welcome_tablet_portrait_bg.mp4';

  /// Same-aspect PNG poster (1086 × 1448) used as the immediate
  /// fallback while the MP4 initialises and as the permanent
  /// fallback if MP4 init fails.
  static const String _card1WelcomeTabletPortraitFallbackAsset =
      'assets/fluxidi/onboarding/card1_welcome_tablet_portrait_bg.png';

  /// Intrinsic aspect ratio (width / height) of the MP4 frame. The
  /// rounded hero panel is sized to this exact ratio via
  /// [AspectRatio] so the video and PNG poster fill the panel
  /// edge-to-edge with no distortion or letterboxing.
  static const double _card1WelcomeMediaAspectRatio = 1244 / 1660;

  /// Silent, looping landscape MP4 (1586 × 992, 5 s) used as the
  /// Card 1 tablet landscape hero background. The 1.5988 aspect
  /// ratio matches the target tablet's logical landscape viewport
  /// (≈1408 × 880 → 1.6) almost perfectly, so the hero fills most
  /// of the slot with only a thin sliver of the dark hero canvas
  /// peeking through at the edges. Audio is muted at runtime via
  /// [VideoPlayerController.setVolume].
  static const String _card1WelcomeTabletLandscapeVideoAsset =
      'assets/fluxidi/onboarding/card1_welcome_tablet_landscape_bg.mp4';

  /// Same-aspect PNG poster (1586 × 992) used as the immediate
  /// fallback while the landscape MP4 initialises and as the
  /// permanent fallback if MP4 init fails.
  static const String _card1WelcomeTabletLandscapeFallbackAsset =
      'assets/fluxidi/onboarding/card1_welcome_tablet_landscape_bg.png';

  /// Intrinsic aspect ratio (width / height) of the landscape MP4
  /// frame (1586 / 992 ≈ 1.5988). The new asset's ratio matches the
  /// target tablet's logical landscape viewport (≈1.6) almost
  /// perfectly, so a full-viewport [BoxFit.cover] in
  /// [_buildWelcomeTabletLandscapeFullViewportHero] crops a
  /// negligible amount of pixels — visually a perfect fit, with
  /// zero black bands.
  static const double _card1WelcomeTabletLandscapeMediaAspectRatio = 1586 / 992;

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
    // Card 1 tablet-hero videos are initialised lazily and only one
    // lane plays at a time — see [_syncHeroVideoPlayback]. The first
    // [build] post-frame callback kicks off the lane that matches
    // the opening orientation so we never decode both MP4s at once.
  }

  @override
  void dispose() {
    _pageController.dispose();
    _entranceController.dispose();
    _accentController.dispose();
    _bgVideoController.dispose();
    _bgLandscapeVideoController.dispose();
    super.dispose();
  }

  /// Initialise the Card 1 tablet-portrait background video and mute
  /// it. Playback is owned by [_applyHeroVideoLane] so the landscape
  /// lane can stay paused while portrait is active. We deliberately
  /// swallow all errors: the video is decorative, the PNG poster
  /// covers the same panel, and a partially-onboarded operator must
  /// never see a broken hero. Exactly one success and one failure log
  /// are emitted to keep the orientation flow's logs focused.
  Future<void> _initBgVideo() async {
    try {
      await _bgVideoController.initialize();
      if (!mounted) return;
      await _bgVideoController.setLooping(true);
      // The bundled MP4 has an audio track; the orientation flow is
      // visual only, so we silence playback before [play] is called.
      await _bgVideoController.setVolume(0);
      if (!mounted) return;
      setState(() => _bgVideoReady = true);
      debugPrint('[ORIENTATION_FLOW][BG_VIDEO_OK] looping silent');
      // Play only if portrait is still the active lane — landscape
      // may have won the race if the operator rotated mid-init.
      await _applyHeroVideoLane(_syncedHeroVideoLane);
    } catch (error, stackTrace) {
      debugPrint(
        '[ORIENTATION_FLOW][BG_VIDEO_FAIL] error=$error stack=$stackTrace',
      );
      if (!mounted) return;
      setState(() => _bgVideoFailed = true);
    }
  }

  /// Initialise the Card 1 tablet-landscape background video and
  /// mute it. Playback is owned by [_applyHeroVideoLane] so the
  /// portrait lane can stay paused while landscape is active.
  /// Mirrors [_initBgVideo] otherwise: errors are swallowed, the
  /// landscape PNG poster covers the same panel, and at most one
  /// success / one failure log is emitted. The distinct
  /// `BG_LANDSCAPE_VIDEO_*` log tags make it obvious in QA logs
  /// which controller emitted which event.
  Future<void> _initBgLandscapeVideo() async {
    try {
      await _bgLandscapeVideoController.initialize();
      if (!mounted) return;
      await _bgLandscapeVideoController.setLooping(true);
      await _bgLandscapeVideoController.setVolume(0);
      if (!mounted) return;
      setState(() => _bgLandscapeVideoReady = true);
      debugPrint('[ORIENTATION_FLOW][BG_LANDSCAPE_VIDEO_OK] looping silent');
      await _applyHeroVideoLane(_syncedHeroVideoLane);
    } catch (error, stackTrace) {
      debugPrint(
        '[ORIENTATION_FLOW][BG_LANDSCAPE_VIDEO_FAIL] '
        'error=$error stack=$stackTrace',
      );
      if (!mounted) return;
      setState(() => _bgLandscapeVideoFailed = true);
    }
  }

  /// Starts portrait MP4 initialisation if not already in flight.
  void _ensurePortraitVideoInit() {
    if (_portraitVideoInitStarted || _bgVideoFailed) return;
    _portraitVideoInitStarted = true;
    unawaited(_initBgVideo());
  }

  /// Starts landscape MP4 initialisation if not already in flight.
  void _ensureLandscapeVideoInit() {
    if (_landscapeVideoInitStarted || _bgLandscapeVideoFailed) return;
    _landscapeVideoInitStarted = true;
    unawaited(_initBgLandscapeVideo());
  }

  /// Reconciles which Card 1 tablet-hero video should be playing
  /// after a page change or orientation change. Lazy-inits only the
  /// lane that is actually visible and pauses the other so we never
  /// keep two platform decoders running in parallel.
  void _syncHeroVideoPlayback({
    required bool isWelcome,
    required bool isTabletPortrait,
    required bool isTabletLandscape,
  }) {
    final _HeroVideoLane target;
    if (!isWelcome) {
      target = _HeroVideoLane.none;
    } else if (isTabletLandscape) {
      target = _HeroVideoLane.landscape;
    } else if (isTabletPortrait) {
      target = _HeroVideoLane.portrait;
    } else {
      target = _HeroVideoLane.none;
    }
    if (target == _syncedHeroVideoLane) return;
    _syncedHeroVideoLane = target;
    if (target == _HeroVideoLane.portrait) {
      _ensurePortraitVideoInit();
    } else if (target == _HeroVideoLane.landscape) {
      _ensureLandscapeVideoInit();
    }
    unawaited(_applyHeroVideoLane(target));
  }

  /// Applies play / pause to match [lane]. The inactive controller
  /// is always paused; the active lane plays only once its init
  /// helper has latched `*Ready` and not `*Failed` (PNG fallback
  /// otherwise). Errors are swallowed — the video is decorative.
  Future<void> _applyHeroVideoLane(_HeroVideoLane lane) async {
    try {
      if (_bgVideoController.value.isInitialized &&
          lane != _HeroVideoLane.portrait) {
        await _bgVideoController.pause();
      }
      if (_bgLandscapeVideoController.value.isInitialized &&
          lane != _HeroVideoLane.landscape) {
        await _bgLandscapeVideoController.pause();
      }
      if (lane == _HeroVideoLane.portrait &&
          _bgVideoReady &&
          !_bgVideoFailed &&
          !_bgVideoController.value.isPlaying) {
        await _bgVideoController.play();
      }
      if (lane == _HeroVideoLane.landscape &&
          _bgLandscapeVideoReady &&
          !_bgLandscapeVideoFailed &&
          !_bgLandscapeVideoController.value.isPlaying) {
        await _bgLandscapeVideoController.play();
      }
    } catch (_) {
      // Decorative hero — a pause/play hiccup during rotation must
      // never surface to the operator; PNG fallback covers the gap.
    }
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = MediaQuery.sizeOf(context);
      _syncHeroVideoPlayback(
        isWelcome: next == 0,
        isTabletPortrait: size.width < size.height && size.shortestSide >= 600,
        isTabletLandscape: size.width > size.height && size.shortestSide >= 600,
      );
    });
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
        // Minimum-safe tablet-portrait detection used ONLY by the
        // welcome card to opt into its video-background hero. Phones,
        // tablet-landscape, and Cards 2-7 ignore this flag and stay on
        // the generic icon + title + body composition.
        final bool isTabletPortrait =
            size.width < size.height && size.shortestSide >= 600;
        // Companion detection for the new Card 1 tablet-landscape
        // video hero. Same shortestSide >= 600 minimum-tablet bar,
        // mirrored to width > height. Phones (any orientation) and
        // Cards 2-7 ignore this flag and stay on the generic
        // icon + title + body composition.
        final bool isTabletLandscape =
            size.width > size.height && size.shortestSide >= 600;

        // Switch the Scaffold (and therefore the SafeArea cutouts +
        // page-chrome margins around the hero) to a near-black canvas
        // ONLY while Card 1 is the active page on a tablet (portrait
        // or landscape), so the immersive video hero stops reading
        // as a card floating on navy. All other states use the
        // regular navy palette, exactly as before. The change snaps
        // on page settle (driven by [_index]); this is acceptable
        // because the PageView's own swipe transition already pulls
        // the user's eye to the moving page content.
        final bool isWelcomeTabletHero =
            _index == 0 && (isTabletPortrait || isTabletLandscape);
        final Color scaffoldBackground = isWelcomeTabletHero ? _heroBg : _bg;

        // Card 1 tablet landscape uses a FULL-VIEWPORT background
        // hero rendered behind the SafeArea + Column, instead of a
        // slot-bound panel. The page-counter / Skip row and the
        // dots / Previous / Next row float on top of the video, so
        // the hero is no longer cramped between two horizontal
        // bars. Card 1 tablet portrait keeps its in-slot rounded
        // panel hero (approved + committed); Cards 2-7 and phone
        // layouts are unchanged.
        final bool useLandscapeFullHero = _index == 0 && isTabletLandscape;

        // Keep only one Card 1 tablet-hero decoder active. Runs
        // post-frame so [MediaQuery] is stable and we do not call
        // play/pause synchronously inside [build].
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _syncHeroVideoPlayback(
            isWelcome: _index == 0,
            isTabletPortrait: isTabletPortrait,
            isTabletLandscape: isTabletLandscape,
          );
        });

        return Scaffold(
          backgroundColor: scaffoldBackground,
          body: Stack(
            children: <Widget>[
              // Background layer — full-viewport landscape hero,
              // only when Card 1 is the active page in tablet
              // landscape. Sits behind the SafeArea + Column so the
              // existing topbar / bottom controls float on top of
              // the video.
              if (useLandscapeFullHero)
                Positioned.fill(
                  child: _buildWelcomeTabletLandscapeFullViewportHero(size),
                ),
              // Foreground layer — the existing chrome + PageView
              // composition. Identical to the pre-refactor layout
              // for portrait, phones, and Cards 2-7. For Card 1 in
              // tablet landscape, the PageView slot is intentionally
              // transparent so the background hero remains fully
              // visible underneath.
              SafeArea(
                child: Column(
                  children: <Widget>[
                    _buildTopBar(isCompactHeight),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: _onPageChanged,
                        itemCount: _cards.length,
                        itemBuilder: (ctx, i) {
                          final _OrientationCardData card = _cards[i];
                          // Card 1 tablet landscape: empty
                          // transparent slot. The dedicated full-
                          // viewport hero behind this Stack is what
                          // the user sees here. PageView still
                          // owns the swipe gesture, so swiping
                          // forward to Card 2 keeps working.
                          if (card.id == 'welcome' && isTabletLandscape) {
                            return const SizedBox.expand();
                          }
                          // Card 1 tablet portrait keeps the in-slot
                          // immersive video hero — bypass the 640 px
                          // generic card cap and anchor top-centre so
                          // the artwork's hero region sits high on
                          // the screen with the taller portrait
                          // artwork. Every other card / layout keeps
                          // the existing centred, capped behaviour.
                          final bool useFullWidthHeroPortrait =
                              card.id == 'welcome' && isTabletPortrait;
                          return Align(
                            alignment: useFullWidthHeroPortrait
                                ? Alignment.topCenter
                                : Alignment.center,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: useFullWidthHeroPortrait
                                    ? double.infinity
                                    : maxCardWidth,
                              ),
                              child: _buildCard(
                                card,
                                isCompactHeight,
                                isTabletPortrait: isTabletPortrait,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    _buildBottomBar(
                      isCompactHeight,
                      isLast: _index == _cards.length - 1,
                      landscapeFullHero: useLandscapeFullHero,
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

  Widget _buildBottomBar(
    bool compact, {
    required bool isLast,
    bool landscapeFullHero = false,
  }) {
    // Card 1 tablet-landscape full-hero mode uses a tighter bottom
    // bar so the dots / Previous / Next row collides less with the
    // artwork's bottom panels and the overlaid "Bookings / Drivers /
    // Link" captions. Portrait and Cards 2-7 keep the original
    // spacing exactly as approved.
    final double verticalButtonPadding = landscapeFullHero
        ? 10
        : (compact ? 10 : 14);
    final Widget barContent = Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        landscapeFullHero ? 4 : (compact ? 6 : 10),
        20,
        landscapeFullHero ? 8 : (compact ? 10 : 16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _buildDots(),
          SizedBox(height: landscapeFullHero ? 6 : (compact ? 8 : 14)),
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
    if (!landscapeFullHero) return barContent;
    // Subtle bottom scrim so dots / buttons stay legible over the
    // full-bleed video without extending so high that it covers the
    // "Bookings / Drivers / Link" captions anchored ~74 % up the
    // viewport. The gradient is confined to this bottom-bar column.
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.transparent, _heroBg.withOpacity(0.88)],
          stops: const <double>[0.0, 0.72],
        ),
      ),
      child: barContent,
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

  Widget _buildCard(
    _OrientationCardData data,
    bool compact, {
    required bool isTabletPortrait,
  }) {
    final double iconBoxSize = compact ? 44 : 64;

    // Card 1 tablet portrait gets the premium video hero background.
    // The Flutter text/badges/callout/labels overlay is layered on
    // top of the looping silent MP4 inside
    // [_buildWelcomeTabletPortraitVideoHero].
    //
    // Card 1 tablet landscape is intentionally NOT routed here — its
    // PageView slot is short-circuited to a transparent
    // [SizedBox.expand] in [build] so the dedicated full-viewport
    // hero behind the Stack remains fully visible.
    if (data.id == 'welcome' && isTabletPortrait) {
      return _buildWelcomeTabletPortraitVideoHero();
    }

    // Stable baseline composition shared by all other cards (welcome
    // on phones, plus Cards 2-7). The only difference between cards
    // is the [data] they bind — icon, title, body.
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

  /// Card 1 tablet-portrait hero: a rounded full-aspect-ratio panel
  /// playing the bundled MP4 silently on loop, with the same-aspect
  /// PNG poster as fallback while the video initialises and as the
  /// permanent fallback on init failure. The panel is sized via
  /// [AspectRatio] using [_card1WelcomeMediaAspectRatio] so video
  /// and PNG fill the rounded clip without distortion or letterboxing.
  ///
  /// Foreground content (setup badge, title, body, callout, mini
  /// tiles, Flutter F-mark) is intentionally NOT rendered here yet —
  /// this pass is video-background-only.
  Widget _buildWelcomeTabletPortraitVideoHero() {
    // Outer padding: 24 px each side horizontally so the hero uses
    // most of the tablet width without bleeding into the PageView's
    // gesture margin. 12 px top pulls the hero tight against the
    // page-counter / Skip row, and 16 px bottom keeps a small
    // breathing gap before the dots + Previous/Next row.
    //
    // We deliberately omit any inner [Center] here: combined with
    // the [Alignment.topCenter] applied by the outer
    // PageView itemBuilder for this layout, [AspectRatio] then
    // shrink-wraps to its computed size and Padding shrink-wraps to
    // the [AspectRatio] + insets. Result: the hero panel sits high
    // in the slot with deterministic 12 px / 16 px margins instead
    // of floating in the middle with a large empty band above.
    // Video plays only when the [VideoPlayerController] has
    // finished initialising AND the controller has not latched
    // an init / decode failure. The PNG poster covers both the
    // pre-init window and any post-failure state, so the operator
    // never sees a blank panel.
    final bool showVideo = _bgVideoReady && !_bgVideoFailed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: AspectRatio(
        aspectRatio: _card1WelcomeMediaAspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Video, only when fully initialised AND not failed.
              // The panel matches the video aspect exactly, so a
              // direct [VideoPlayer] (no FittedBox) renders the
              // frame edge-to-edge without distortion.
              if (showVideo) VideoPlayer(_bgVideoController),
              // PNG poster while the video loads, and permanently
              // when the video initialisation latched as failed.
              if (!showVideo)
                Image.asset(
                  _card1WelcomeTabletPortraitFallbackAsset,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, error, stackTrace) {
                    debugPrint('[ORIENTATION_FLOW][BG_PNG_FAIL] error=$error');
                    return _buildWelcomeMediaUltimateFallback();
                  },
                ),
              // Subtle dark vertical gradient overlay. Transparent
              // at the top so the artwork's hero region stays
              // vivid, ramping into ~30% navy at the bottom so
              // the text layer below stays readable.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Colors.transparent, _bg.withOpacity(0.30)],
                  ),
                ),
              ),
              // Localised Flutter text overlay (badge / title /
              // accent / body / callout / bottom labels). Sized to
              // the panel via [Positioned.fill] and wrapped in
              // [IgnorePointer] so the overlay never blocks
              // PageView swipes, the Skip / Previous / Next
              // buttons, or the page-counter row above the panel.
              // The artwork already paints the Fluxidi F-mark and
              // the three decorative panels, so we deliberately do
              // NOT layer a Flutter F-mark or any panel decorations
              // here — only the localised text that the video
              // cannot bake in without losing translation support.
              Positioned.fill(
                child: IgnorePointer(
                  child: _buildWelcomeTabletPortraitOverlay(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Localised text overlay layered on top of the Card 1
  /// tablet-portrait video hero. Layout uses [LayoutBuilder] +
  /// [Align] with normalised vertical fractions so each element
  /// keeps its relative position across whatever exact pixel size
  /// the [AspectRatio] above happened to compute. We deliberately
  /// avoid a generic [Column] here so the overlay never reflows the
  /// hero panel itself — the artwork's F-mark and decorative panels
  /// stay visible underneath.
  Widget _buildWelcomeTabletPortraitOverlay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        // Per-element max widths so long localised copy (NL/FR/ES)
        // doesn't sprawl edge-to-edge of the hero panel.
        final double titleMaxWidth = w * 0.86;
        final double bodyMaxWidth = w * 0.82;
        // Keep the callout text inside the empty callout frame
        // already painted into the MP4 — that frame spans roughly
        // ~60% of the hero width, so cap to w * 0.60 so the text
        // wraps inside the existing artwork frame instead of
        // bleeding past it.
        final double calloutMaxWidth = w * 0.60;
        final double labelsMaxWidth = w * 0.94;
        return Stack(
          children: <Widget>[
            // Setup-complete badge — green capsule centred under
            // the artwork's "FLUXIDI" wordmark (~32% of hero
            // height). The y-alignment formula maps a target
            // fractional height [f] to Align's y axis: y = 2f - 1.
            Align(
              alignment: const Alignment(0, -0.36),
              child: _buildHeroSetupBadge(),
            ),
            // Large white title — anchored at ~39% of hero height.
            Align(
              alignment: const Alignment(0, -0.22),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: titleMaxWidth),
                child: _buildHeroTitle(),
              ),
            ),
            // Thin gold accent line under the title (~44%).
            Align(
              alignment: const Alignment(0, -0.12),
              child: _buildHeroAccentLine(w),
            ),
            // Body paragraph (~50%).
            Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: bodyMaxWidth),
                child: _buildHeroBody(),
              ),
            ),
            // Callout text — centred inside the empty callout
            // frame already painted into the MP4 (~65% of hero
            // height). We deliberately do NOT render our own
            // capsule background / border here; the artwork
            // already supplies the frame, and stacking a Flutter
            // capsule on top would create a visible double-frame.
            //
            // The artwork's empty frame is biased a few pixels
            // right of the panel's geometric centre, so we apply
            // a paint-only [Transform.translate] of +10 px on top
            // of the [Align(0, 0.305)] anchor. Keeping this as a
            // pixel translation rather than a non-zero
            // [Alignment.x] makes the offset stable across
            // tablet widths (which would otherwise scale with the
            // alignment slack).
            Align(
              alignment: const Alignment(0, 0.305),
              child: Transform.translate(
                offset: const Offset(10, 0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: calloutMaxWidth),
                  child: _buildHeroCallout(),
                ),
              ),
            ),
            // Three short labels centred over the artwork's bottom
            // decorative panels (~79% of hero height). The
            // artwork's panels are laid out at left/centre/right
            // thirds, so an [Expanded]-divided [Row] with centred
            // text aligns visually without depending on pixel
            // positions of the video frame.
            Align(
              alignment: const Alignment(0, 0.58),
              child: SizedBox(
                width: labelsMaxWidth,
                child: _buildHeroBottomLabels(),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Setup-complete capsule — emerald tint + check icon. Localised
  /// to celebrate that the wizard step that just preceded this flow
  /// has indeed wired up the operator's business profile.
  Widget _buildHeroSetupBadge() {
    const Color successFill = Color(0x3322C55E); // ~20% emerald
    const Color successText = Color(0xFF7DE2A4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: successFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: successText.withOpacity(0.48)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.check_circle, size: 16, color: successText),
          const SizedBox(width: 7),
          Text(
            _t(
              const _Tr(
                nl: 'Setup voltooid',
                en: 'Setup complete',
                fr: 'Configuration terminée',
                es: 'Configuración completada',
              ),
            ),
            style: const TextStyle(
              color: successText,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  /// Hero title: large white bold text with a subtle drop-shadow
  /// so it remains legible even over the warmer regions of the
  /// MP4's golden-trail animation. [fontSize] defaults to the
  /// approved 38 px portrait headline; landscape passes a smaller
  /// value so the headline + accent + body trio fits the shorter
  /// landscape panel.
  Widget _buildHeroTitle({double fontSize = 38}) {
    return Text(
      _t(
        const _Tr(
          nl: 'Welkom bij Fluxidi',
          en: 'Welcome to Fluxidi',
          fr: 'Bienvenue chez Fluxidi',
          es: 'Bienvenido a Fluxidi',
        ),
      ),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        height: 1.1,
        letterSpacing: 0.2,
        shadows: const <Shadow>[
          Shadow(
            color: Color(0xCC000000),
            blurRadius: 16,
            offset: Offset(0, 2),
          ),
        ],
      ),
    );
  }

  /// Thin gold accent strip rendered between the title and body —
  /// width scales with the panel so the line keeps a consistent
  /// visual weight across tablet sizes (clamped to a sensible
  /// range so it never stretches absurdly wide or shrinks to a
  /// dot).
  Widget _buildHeroAccentLine(double panelWidth) {
    final double width = (panelWidth * 0.16).clamp(80.0, 160.0);
    return Container(
      height: 2,
      width: width,
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.85),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  /// Hero body paragraph — 3-4 line localised copy describing the
  /// orientation tour. Uses the new "business setup is ready"
  /// message rather than the generic [_OrientationCardData.body]
  /// because the layered hero needs short, action-oriented copy
  /// while the generic icon-card path on phones still wants the
  /// broader product positioning sentence.
  ///
  /// [fontSize] defaults to the approved 15 px portrait body size;
  /// [maxLines] is null by default (so portrait keeps its current
  /// natural-wrap behaviour). Landscape passes a smaller font and
  /// `maxLines: 3` as a safety net so a particularly long
  /// localisation trims gracefully rather than blowing the height
  /// budget.
  Widget _buildHeroBody({double fontSize = 15, int? maxLines}) {
    return Text(
      _t(
        const _Tr(
          nl: 'Je bedrijfsbasis is ingesteld. In deze korte rondleiding ontdek je hoe je boekingen, chauffeurs, voertuigen en klanten beheert.',
          en: "Your business setup is ready. In this short tour, you'll discover how to manage bookings, drivers, vehicles and customers.",
          fr: 'La base de votre entreprise est configurée. Dans cette courte visite, découvrez comment gérer les réservations, chauffeurs, véhicules et clients.',
          es: 'La base de tu empresa está configurada. En este breve recorrido descubrirás cómo gestionar reservas, conductores, vehículos y clientes.',
        ),
      ),
      textAlign: TextAlign.center,
      maxLines: maxLines,
      overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white.withOpacity(0.88),
        fontSize: fontSize,
        height: 1.5,
        shadows: const <Shadow>[
          Shadow(
            color: Color(0x99000000),
            blurRadius: 10,
            offset: Offset(0, 1),
          ),
        ],
      ),
    );
  }

  /// Callout content (sparkle icon + localised sentence) layered
  /// INSIDE the empty callout frame already painted into the
  /// Card 1 tablet-portrait MP4. We deliberately do NOT wrap this
  /// in a Container with a background / border — the artwork
  /// supplies the capsule; an additional Flutter capsule would
  /// create a visible double-frame.
  ///
  /// The sentence is split into [lead] / [gold] / "." spans so the
  /// "Fluxidi-cockpit" / "Fluxidi cockpit" / "cockpit Fluxidi"
  /// phrase reads in gold while the surrounding text stays white.
  /// Subtle drop-shadows keep readability stable across the MP4's
  /// brighter golden-trail frames and the PNG fallback.
  Widget _buildHeroCallout({double fontSize = 15}) {
    final (String lead, String gold) = switch (appLanguageNotifier.value) {
      AppLanguage.nl => ('Alles begint vanuit je ', 'Fluxidi-cockpit'),
      AppLanguage.en => ('Everything starts from your ', 'Fluxidi cockpit'),
      AppLanguage.fr => ('Tout commence depuis votre ', 'cockpit Fluxidi'),
      AppLanguage.es => ('Todo empieza desde tu ', 'cockpit Fluxidi'),
    };
    const List<Shadow> textShadows = <Shadow>[
      Shadow(color: Color(0xCC000000), blurRadius: 10, offset: Offset(0, 1)),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          Icons.auto_awesome_outlined,
          color: _gold,
          size: 18,
          shadows: textShadows,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                color: Colors.white.withOpacity(0.95),
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                height: 1.3,
                shadows: textShadows,
              ),
              children: <InlineSpan>[
                TextSpan(text: lead),
                TextSpan(
                  text: gold,
                  style: TextStyle(color: _gold, fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: '.'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  /// Three short localised labels (Bookings / Drivers / Booking
  /// link) overlaid above the artwork's bottom decorative panels.
  /// Each label gets a third of the row via [Expanded] so the
  /// labels track the artwork's left-/centre-/right-thirds layout
  /// without depending on pixel positions of the video frame.
  /// Labels stay strictly single-line ([maxLines: 1] +
  /// [TextOverflow.ellipsis]) so a particularly long localisation
  /// (FR "Lien de réservation") trims gracefully rather than
  /// blowing up the row height.
  ///
  /// [leftTranslateX] and [rightTranslateX] default to the approved
  /// portrait values (+46 / -46). Landscape passes wider nudges
  /// because its 4:3 panel spreads the artwork's bottom-thirds
  /// further from the row centre.
  Widget _buildHeroBottomLabels({
    double leftTranslateX = 46,
    double rightTranslateX = -46,
    double fontSize = 15,
  }) {
    // Slightly smaller than the title row so the labels read as
    // captions for the artwork's bottom panels rather than
    // competing with the main headline. [fontSize] defaults to
    // the approved 15 px portrait caption size; landscape passes
    // a smaller value so the row fits the shallow bottom band.
    final TextStyle labelStyle = TextStyle(
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
      shadows: const <Shadow>[
        Shadow(color: Color(0xCC000000), blurRadius: 10, offset: Offset(0, 1)),
      ],
    );
    // [translateX] is a paint-only nudge applied via
    // [Transform.translate] AFTER layout — the underlying
    // [Expanded] thirds keep the same width, so the
    // [maxLines: 1] + ellipsis behaviour is unchanged. Only the
    // left + right labels are shifted; the centre ("Drivers")
    // stays at translateX: 0 because the artwork's middle panel
    // already lines up with the row's central third. Positive
    // values shift the rendered text rightward; negative leftward.
    Widget label(_Tr tr, {double translateX = 0}) {
      return Expanded(
        child: Transform.translate(
          offset: Offset(translateX, 0),
          child: Text(
            _t(tr),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: labelStyle,
          ),
        ),
      );
    }

    return Row(
      children: <Widget>[
        label(
          const _Tr(
            nl: 'Boekingen',
            en: 'Bookings',
            fr: 'Réservations',
            es: 'Reservas',
          ),
          // Nudge rightward so "Bookings" lands above the centre
          // of the artwork's left panel rather than its left edge.
          translateX: leftTranslateX,
        ),
        label(
          const _Tr(
            nl: 'Chauffeurs',
            en: 'Drivers',
            fr: 'Chauffeurs',
            es: 'Conductores',
          ),
        ),
        label(
          // Compact localisation for the right panel — the
          // artwork already shows a QR + link icon, so the caption
          // can be a single word. Keeps FR/ES from being clipped
          // by the [maxLines: 1] + ellipsis at narrow widths,
          // while NL/EN keep parity by also using the short form.
          const _Tr(nl: 'Link', en: 'Link', fr: 'Lien', es: 'Enlace'),
          // Nudge leftward so "Link" lands above the centre of the
          // artwork's right panel rather than its right edge.
          translateX: rightTranslateX,
        ),
      ],
    );
  }

  /// Card 1 tablet-landscape hero, full-viewport variant.
  ///
  /// Renders the dedicated landscape MP4 (with PNG poster fallback)
  /// edge-to-edge across the entire scaffold body, so the page-
  /// counter / Skip row at the top and the dots / Previous / Next
  /// row at the bottom float on top of the video instead of
  /// squeezing it into the PageView's content slot.
  ///
  /// The new landscape asset's 1.5988 ratio matches the target
  /// tablet's logical landscape viewport (≈1408 × 880 → 1.6)
  /// almost perfectly, so a [BoxFit.cover] full-bleed crops a
  /// negligible amount of pixels (≈0.1 %) off the right/left edges
  /// — visually indistinguishable from a perfect fit — while
  /// guaranteeing the video fills the screen with zero black
  /// bands. The chrome is overlaid by the SafeArea + Column
  /// rendered as a sibling on top of this hero in [build], so the
  /// counter / Skip / dots / Previous / Next remain visible and
  /// tappable.
  ///
  /// We deliberately do NOT use [ClipRRect] here: the hero is
  /// supposed to feel near-fullscreen, and rounded corners that
  /// hide partly behind the chrome would read as a card cutout
  /// rather than a premium full-bleed background.
  Widget _buildWelcomeTabletLandscapeFullViewportHero(Size viewport) {
    // One-shot diagnostic so QA can confirm the actual viewport
    // and decoded media size on a real device. Only fires the
    // first build the video controller is initialised, so logs
    // stay focused. Mutating the latch from inside [build] is
    // safe: it's a debug-only side effect that does NOT trigger
    // a rebuild.
    if (!_landscapeLayoutLogged && _bgLandscapeVideoReady) {
      _landscapeLayoutLogged = true;
      final Size mediaSize = _bgLandscapeVideoController.value.size;
      debugPrint(
        '[ORIENTATION_FLOW][LANDSCAPE_LAYOUT] '
        'viewport=${viewport.width.toStringAsFixed(0)}x'
        '${viewport.height.toStringAsFixed(0)} '
        'media=${mediaSize.width.toStringAsFixed(0)}x'
        '${mediaSize.height.toStringAsFixed(0)} '
        'media_ratio='
        '${_card1WelcomeTabletLandscapeMediaAspectRatio.toStringAsFixed(4)}',
      );
    }
    // Video plays only when the [VideoPlayerController] has
    // finished initialising AND the controller has not latched
    // an init / decode failure. The PNG poster covers both the
    // pre-init window and any post-failure state, so the operator
    // never sees a blank background.
    final bool showVideo = _bgLandscapeVideoReady && !_bgLandscapeVideoFailed;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Video, full-bleed via [FittedBox]. [VideoPlayer] does
        // not accept a [BoxFit] directly, so we wrap it in a
        // FittedBox sized to the controller's intrinsic frame
        // dimensions and let FittedBox cover the full viewport.
        // The asset's near-perfect 1.5988 ratio against the
        // ≈1.6 viewport means cover crops <1 % — visually a
        // perfect fit, with zero black bands.
        if (showVideo)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _bgLandscapeVideoController.value.size.width,
              height: _bgLandscapeVideoController.value.size.height,
              child: VideoPlayer(_bgLandscapeVideoController),
            ),
          ),
        // PNG poster, full-bleed. [BoxFit.cover] mirrors the
        // video's full-bleed behaviour above so the swap from
        // poster to video is visually invisible.
        if (!showVideo)
          Image.asset(
            _card1WelcomeTabletLandscapeFallbackAsset,
            fit: BoxFit.cover,
            errorBuilder: (ctx, error, stackTrace) {
              debugPrint(
                '[ORIENTATION_FLOW][BG_LANDSCAPE_PNG_FAIL] error=$error',
              );
              return _buildWelcomeMediaUltimateFallback();
            },
          ),
        // Subtle dark vertical gradient overlay. Slightly dims
        // the very top and the lowest strip of the video so the
        // page-counter / Skip text and the bottom chrome stay
        // legible, while leaving the hero text / callout / label
        // band (≈25–76 % height) vivid. The bottom stop is pulled
        // up to 0.68 so we do not darken the "Bookings / Drivers /
        // Link" captions above the button row.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                _bg.withOpacity(0.32),
                Colors.transparent,
                Colors.transparent,
                _bg.withOpacity(0.28),
              ],
              stops: const <double>[0.0, 0.14, 0.68, 1.0],
            ),
          ),
        ),
        // Localised Flutter text overlay (badge / title / accent
        // / body / callout / bottom labels). Wrapped in
        // [IgnorePointer] so the overlay never blocks PageView
        // swipes, Skip / Previous / Next, or the page-counter
        // row above. The artwork paints the Fluxidi F-mark and
        // the bottom decorative panels, so we deliberately do
        // NOT layer a Flutter F-mark or any panel decorations
        // here — only the localised text that the video cannot
        // bake in without losing translation support.
        Positioned.fill(
          child: IgnorePointer(
            child: _buildWelcomeTabletLandscapeOverlay(viewport),
          ),
        ),
      ],
    );
  }

  /// Maps a normalised viewport height fraction [f] (0 = top edge,
  /// 1 = bottom edge) to an [Align] y-axis value. Used exclusively
  /// by the landscape full-viewport overlay so each element can be
  /// positioned as a percentage of screen height without reusing
  /// the portrait panel's alignment fractions.
  double _landscapeOverlayAlignY(double heightFraction) =>
      2 * heightFraction - 1;

  /// Localised text overlay layered on top of the Card 1
  /// tablet-landscape full-viewport hero. Uses landscape-specific
  /// height fractions tuned against the 16:10 asset on a ≈1408 ×
  /// 880 logical viewport — deliberately NOT the portrait overlay
  /// fractions, which were sized for a shorter in-slot panel.
  ///
  /// Vertical anchors (fraction of full viewport height):
  ///   setup badge ≈ 31 %  (between Fluxidi wordmark and title)
  ///   title       ≈ 36 %
  ///   accent line ≈ 43 %
  ///   body        ≈ 47 %  (approved — do not move)
  ///   callout     ≈ 59 %  (vertically centred in callout frame)
  ///   bottom caps ≈ 75 %  (between panel icon and horizontal line)
  ///
  /// The bottom "Bookings / Drivers / Link" row is shown only when
  /// the gap between its anchor and the estimated bottom-chrome top
  /// is at least 24 logical px; otherwise it is hidden rather than
  /// letting captions sit under the Previous / Next buttons.
  ///
  /// We deliberately do NOT render the Flutter F-mark or any frame
  /// / capsule decorations here — the artwork supplies those.
  Widget _buildWelcomeTabletLandscapeOverlay(Size viewport) {
    final double w = viewport.width;
    final double h = viewport.height;
    // Per-element max widths — tighter than portrait so long
    // localised copy (NL/FR/ES) does not sprawl across the wide
    // full-bleed panel.
    final double titleMaxWidth = w * 0.68;
    final double bodyMaxWidth = w * 0.48;
    final double calloutMaxWidth = w * 0.44;
    final double labelsMaxWidth = w * 0.90;
    // Compact landscape bottom bar reserve (dots + buttons +
    // padding) used to decide whether the bottom captions fit.
    const double landscapeBottomChromeReserve = 76.0;
    const double labelHeightFraction = 0.75;
    final double labelAnchorY = h * labelHeightFraction;
    final double chromeTopY = h - landscapeBottomChromeReserve;
    final bool showBottomLabels = (chromeTopY - labelAnchorY) >= 20;
    return Stack(
      children: <Widget>[
        // Setup-complete badge — green capsule centred between the
        // artwork's "FLUXIDI" wordmark and the welcome title (~31 %).
        Align(
          alignment: Alignment(0, _landscapeOverlayAlignY(0.31)),
          child: _buildHeroSetupBadge(),
        ),
        // Large white title (~36 %).
        Align(
          alignment: Alignment(0, _landscapeOverlayAlignY(0.36)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: titleMaxWidth),
            child: _buildHeroTitle(fontSize: 28),
          ),
        ),
        // Thin gold accent line under the title (~43 %).
        Align(
          alignment: Alignment(0, _landscapeOverlayAlignY(0.43)),
          child: _buildHeroAccentLine(w),
        ),
        // Body paragraph (~47 %). Pulled up from 52 % so the copy
        // sits cleanly between the accent line and the empty callout
        // frame. [maxLines: 2] keeps it compact on landscape.
        Align(
          alignment: Alignment(0, _landscapeOverlayAlignY(0.47)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: bodyMaxWidth),
            child: _buildHeroBody(fontSize: 13, maxLines: 2),
          ),
        ),
        // Callout text — vertically centred inside the empty callout
        // frame painted into the MP4 (~59 %). Horizontal position
        // is approved; tiny downward nudge from 58 %.
        Align(
          alignment: Alignment(0, _landscapeOverlayAlignY(0.59)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: calloutMaxWidth),
            child: _buildHeroCallout(fontSize: 13),
          ),
        ),
        // Three short captions between each panel's icon and its
        // horizontal rule (~75 %). Nudged up from 77 % so the row
        // clears the rule. "Drivers" stays centred; "Bookings" and
        // "Link" nudged outward via translateX; "Drivers" stays at 0.
        if (showBottomLabels)
          Align(
            alignment: Alignment(0, _landscapeOverlayAlignY(0.75)),
            child: SizedBox(
              width: labelsMaxWidth,
              child: _buildHeroBottomLabels(
                leftTranslateX: 154,
                rightTranslateX: -154,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }

  /// Last-resort fallback when BOTH the MP4 fails to initialise AND
  /// the PNG poster fails to decode. Renders a navy/gold gradient
  /// matching the rest of the orientation page so the operator never
  /// sees a broken or blank hero. In debug builds we surface a tiny
  /// muted-gold corner label so QA can spot the asset chain failed,
  /// but the user's eye is drawn to the gradient, not the diagnostic.
  Widget _buildWelcomeMediaUltimateFallback() {
    final Widget gradient = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[_panelTop, _panelBottom],
        ),
      ),
    );
    if (!kDebugMode) return gradient;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        gradient,
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              'media unavailable',
              style: TextStyle(
                color: _gold.withOpacity(0.55),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Which Card 1 tablet-hero background video lane should be active.
enum _HeroVideoLane { none, portrait, landscape }

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
