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

  /// Card 3's reassurance note is intentionally NOT rendered on the
  /// tablet full-viewport subscription layouts for now — it crowded
  /// the page indicator / Previous-Next chrome. The localized string
  /// stays in the central model and [_buildSubscriptionBottomNote]
  /// stays wired behind this flag, so the note can be re-enabled
  /// later without re-plumbing. Kept as a non-const instance field on
  /// purpose so the guarded branch is never flagged as dead code.
  final bool _showSubscriptionBottomNoteOnTablet = false;

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

  /// Card 2 tablet-portrait PNG (1320 × 2112) — cockpit visual for the
  /// orientation flow's second card.
  static const String _card2WelcomeTabletPortraitAsset =
      'assets/fluxidi/onboarding/card2_welcome_tablet_portrait_bg.png';

  /// Card 2 tablet-landscape PNG — cockpit visual for the orientation
  /// flow's second card in landscape only.
  static const String _card2WelcomeTabletLandscapeAsset =
      'assets/fluxidi/onboarding/card2_welcome_tablet_landscape_bg.png';

  /// Card 3 tablet PNGs — present on disk and covered by the
  /// `assets/fluxidi/onboarding/` folder already declared in
  /// pubspec. Reserved for the not-yet-designed "Bookings,
  /// cancellations & history" card and stored in the central model
  /// now so the future bespoke layout can pick them up without
  /// touching navigation. The current placeholder layout is
  /// text-only and never renders these, so there is no asset risk
  /// yet — the paths simply travel with the card data.
  static const String _card3TabletPortraitAsset =
      'assets/fluxidi/onboarding/card3_welcome_tablet_portrait_bg.png';
  static const String _card3TabletLandscapeAsset =
      'assets/fluxidi/onboarding/card3_welcome_tablet_landscape_bg.png';

  /// Shared body copy for not-yet-designed product-tour stops. Kept
  /// deliberately generic — the real per-card explanations land when
  /// each card graduates from [_OrientationCardLayout.placeholder] to
  /// its bespoke layout. This is never a "final" string; it only
  /// keeps placeholder cards readable and translated during
  /// development.
  static const _Tr _placeholderBody = _Tr(
    nl: 'Dit onderdeel van de rondleiding wordt binnenkort toegevoegd.',
    en: 'This part of the tour is coming soon.',
    fr: 'Cette partie de la visite arrive bientôt.',
    es: 'Esta parte del recorrido estará disponible pronto.',
  );

  // ---------------------------------------------------------------
  // Card 3 — Subscription & scalability. All copy lives here in the
  // central model so the bespoke overlay simply binds it; no pricing
  // value is ever hardcoded (current prices stay on the website).
  // ---------------------------------------------------------------

  static const _Tr _card3SubscriptionTitle = _Tr(
    nl: 'Abonnement & schaalbaarheid',
    en: 'Subscription & scalability',
    fr: 'Abonnement & évolutivité',
    es: 'Suscripción y escalabilidad',
  );

  static const _Tr _card3SubscriptionBody = _Tr(
    nl:
        'Fluxidi groeit mee met je bedrijf. Je betaalt maandelijks voor '
        'software, automatisatie en opvolging — niet per rit. Jij behoudt '
        'je tarieven, klantenrelatie en bedrijfswerking.',
    en:
        'Fluxidi grows with your business. You pay monthly for software, '
        'automation and follow-up — not per ride. You keep your tariffs, '
        'customer relationship and business operation.',
    fr:
        'Fluxidi évolue avec votre entreprise. Vous payez chaque mois pour '
        'le logiciel, l\u2019automatisation et le suivi — pas par course. '
        'Vous gardez vos tarifs, votre relation client et votre '
        'fonctionnement.',
    es:
        'Fluxidi crece con tu empresa. Pagas mensualmente por software, '
        'automatización y seguimiento — no por viaje. Mantienes tus '
        'tarifas, la relación con tus clientes y tu forma de trabajar.',
  );

  static const _Tr _card3LeftCardTitle = _Tr(
    nl: 'Geen commissie per rit',
    en: 'No commission per ride',
    fr: 'Pas de commission par course',
    es: 'Sin comisión por viaje',
  );

  static const _Tr _card3LeftCardBody = _Tr(
    nl:
        'Fluxidi is geen ritcommissieplatform. Jij bepaalt je prijzen, '
        'klantenrelatie en werking. Fluxidi automatiseert wat tijd kost.',
    en:
        'Fluxidi is not a ride-commission platform. You define your prices, '
        'customer relationship and operation. Fluxidi automates what costs '
        'time.',
    fr:
        'Fluxidi n\u2019est pas une plateforme à commission par course. Vous '
        'définissez vos prix, votre relation client et votre fonctionnement. '
        'Fluxidi automatise ce qui prend du temps.',
    es:
        'Fluxidi no es una plataforma con comisión por viaje. Tú defines tus '
        'precios, la relación con tus clientes y tu operativa. Fluxidi '
        'automatiza lo que consume tiempo.',
  );

  static const List<_Tr> _card3LeftCardBullets = <_Tr>[
    _Tr(
      nl: 'Eigen tarieven',
      en: 'Own tariffs',
      fr: 'Vos propres tarifs',
      es: 'Tus propias tarifas',
    ),
    _Tr(
      nl: 'Eigen klantenrelatie',
      en: 'Own customer relationship',
      fr: 'Votre relation client',
      es: 'Tu relación con clientes',
    ),
    _Tr(
      nl: 'Geen percentage per rit',
      en: 'No percentage per ride',
      fr: 'Aucun pourcentage par course',
      es: 'Sin porcentaje por viaje',
    ),
    _Tr(
      nl: 'Automatisatie en opvolging',
      en: 'Automation and follow-up',
      fr: 'Automatisation et suivi',
      es: 'Automatización y seguimiento',
    ),
  ];

  static const _Tr _card3RightCardTitle = _Tr(
    nl: 'Schaalbaar uitbreiden',
    en: 'Scale as you grow',
    fr: 'Évoluez avec votre activité',
    es: 'Escala con tu empresa',
  );

  static const _Tr _card3RightCardBody = _Tr(
    nl:
        'Start met de platformbasis en breid later uit met extra voertuigen, '
        'chauffeurs en documentbundels wanneer je bedrijf groeit.',
    en:
        'Start with the platform base and expand later with extra vehicles, '
        'drivers and document bundles as your business grows.',
    fr:
        'Commencez avec la base du platforme et ajoutez ensuite des '
        'véhicules, chauffeurs et packs de documents lorsque votre activité '
        'grandit.',
    es:
        'Empieza con la base de la plataforma y amplía después con '
        'vehículos, conductores y paquetes de documentos a medida que tu '
        'empresa crece.',
  );

  static const List<_Tr> _card3RightCardBullets = <_Tr>[
    _Tr(
      nl: 'Platformbasis',
      en: 'Platform base',
      fr: 'Base de plateforme',
      es: 'Base de plataforma',
    ),
    _Tr(
      nl: 'Extra voertuigen',
      en: 'Extra vehicles',
      fr: 'Véhicules supplémentaires',
      es: 'Vehículos extra',
    ),
    _Tr(
      nl: 'Extra chauffeurs',
      en: 'Extra drivers',
      fr: 'Chauffeurs supplémentaires',
      es: 'Conductores extra',
    ),
    _Tr(
      nl: 'Documenten en PDF-volume',
      en: 'Documents and PDF volume',
      fr: 'Documents et volume PDF',
      es: 'Documentos y volumen PDF',
    ),
  ];

  static const _Tr _card3BottomStrip = _Tr(
    nl: 'Bekijk actuele plannen online',
    en: 'View current plans online',
    fr: 'Voir les formules actuelles en ligne',
    es: 'Ver planes actuales online',
  );

  static const _Tr _card3BottomNote = _Tr(
    nl: 'Actuele prijzen en proefperiodes blijven zichtbaar op de website.',
    en: 'Current prices and trial periods remain visible on the website.',
    fr:
        'Les prix et périodes d\u2019essai actuels restent visibles sur le '
        'site web.',
    es:
        'Los precios y periodos de prueba actuales están disponibles en el '
        'sitio web.',
  );

  /// Shared localized title for the Company Cockpit slide (all layouts).
  static const _Tr _card2CompanyCockpitTitle = _Tr(
    nl: 'Bedrijfscockpit',
    en: 'Company Cockpit',
    fr: 'Cockpit d\u2019entreprise',
    es: 'Panel de empresa',
  );

  /// Shared localized subtitle for the Company Cockpit slide (all layouts).
  static const _Tr _card2CompanyCockpitSubtitle = _Tr(
    nl:
        'Je cockpit brengt je belangrijkste tools samen. '
        'Beheer ritten, team, voertuigen en vraag.',
    en:
        'Your cockpit brings your key tools together. '
        'Manage rides, team, vehicles and demand.',
    fr:
        'Votre cockpit regroupe vos outils essentiels. '
        'Gérez les courses, l\u2019équipe, les véhicules et la demande.',
    es:
        'Tu panel reúne tus herramientas clave. '
        'Gestiona viajes, equipo, vehículos y demanda.',
  );

  /// Shared localized bullet items for the Company Cockpit slide (all layouts).
  static const List<_OrientationBulletItem> _companyCockpitBulletItems =
      <_OrientationBulletItem>[
        _OrientationBulletItem(
          title: _Tr(
            nl: 'Instellingen',
            en: 'Settings',
            fr: 'Paramètres',
            es: 'Ajustes',
          ),
          description: _Tr(
            nl: 'Profiel, branding en bedrijfsgegevens.',
            en: 'Profile, branding and company details.',
            fr: 'Profil, image de marque et données d\u2019entreprise.',
            es: 'Perfil, marca y datos de empresa.',
          ),
        ),
        _OrientationBulletItem(
          title: _Tr(
            nl: 'Abonnement',
            en: 'Plan',
            fr: 'Abonnement',
            es: 'Plan',
          ),
          description: _Tr(
            nl: 'Abonnement, facturatie en accountstatus.',
            en: 'Subscription, billing and account status.',
            fr: 'Abonnement, facturation et statut du compte.',
            es: 'Suscripción, facturación y estado de cuenta.',
          ),
        ),
        _OrientationBulletItem(
          title: _Tr(
            nl: 'Voertuigen',
            en: 'Vehicles',
            fr: 'Véhicules',
            es: 'Vehículos',
          ),
          description: _Tr(
            nl: 'Beheer en koppel voertuigen.',
            en: 'Manage and link vehicles.',
            fr: 'Gérez et associez les véhicules.',
            es: 'Gestiona y vincula vehículos.',
          ),
        ),
        _OrientationBulletItem(
          title: _Tr(nl: 'Chiron', en: 'Chiron', fr: 'Chiron', es: 'Chiron'),
          description: _Tr(
            nl: 'Compliance, documenten en controle.',
            en: 'Compliance, documents and control.',
            fr: 'Conformité, documents et contrôle.',
            es: 'Cumplimiento, documentos y control.',
          ),
        ),
        _OrientationBulletItem(
          title: _Tr(
            nl: 'Chauffeurs',
            en: 'Drivers',
            fr: 'Chauffeurs',
            es: 'Conductores',
          ),
          description: _Tr(
            nl: 'Chauffeurs, codes en documenten.',
            en: 'Drivers, codes and documents.',
            fr: 'Chauffeurs, codes et documents.',
            es: 'Conductores, códigos y documentos.',
          ),
        ),
        _OrientationBulletItem(
          title: _Tr(
            nl: 'Chauffeursweergave',
            en: 'Driver view',
            fr: 'Vue chauffeur',
            es: 'Vista del conductor',
          ),
          description: _Tr(
            nl: 'Open de chauffeurcockpit.',
            en: 'Open the driver cockpit.',
            fr: 'Ouvrez le cockpit chauffeur.',
            es: 'Abre el panel del conductor.',
          ),
        ),
        _OrientationBulletItem(
          title: _Tr(
            nl: 'Demand radar',
            en: 'Demand radar',
            fr: 'Radar de demande',
            es: 'Radar de demanda',
          ),
          description: _Tr(
            nl: 'Bekijk de vraag in je regio.',
            en: 'See demand in your region.',
            fr: 'Consultez la demande dans votre région.',
            es: 'Consulta la demanda en tu región.',
          ),
        ),
        _OrientationBulletItem(
          title: _Tr(
            nl: 'Boekingslink delen',
            en: 'Share booking link',
            fr: 'Partager le lien de réservation',
            es: 'Compartir enlace de reserva',
          ),
          description: _Tr(
            nl: 'Deel je link of QR-code.',
            en: 'Share your link or QR code.',
            fr: 'Partagez votre lien ou code QR.',
            es: 'Comparte tu enlace o código QR.',
          ),
        ),
        _OrientationBulletItem(
          title: _Tr(
            nl: 'Boekingen',
            en: 'Bookings',
            fr: 'Réservations',
            es: 'Reservas',
          ),
          description: _Tr(
            nl: 'Planning, ritstatus en opvolging.',
            en: 'Planning, ride status and follow-up.',
            fr: 'Planning, statut des courses et suivi.',
            es: 'Planificación, estado del viaje y seguimiento.',
          ),
        ),
        _OrientationBulletItem(
          title: _Tr(
            nl: 'AI Dispatch',
            en: 'AI Dispatch',
            fr: 'Dispatch IA',
            es: 'Despacho IA',
          ),
          description: _Tr(
            nl: 'Slimme dispatching voor je ritten.',
            en: 'Smart dispatching for your rides.',
            fr: 'Dispatching intelligent pour vos courses.',
            es: 'Despacho inteligente para tus viajes.',
          ),
        ),
      ];

  /// Card 2 tablet landscape — left explanation column button order.
  static const List<int> _card2LandscapeCol1Indices = <int>[0, 2, 4, 6, 8];

  /// Card 2 tablet landscape — right explanation column button order.
  static const List<int> _card2LandscapeCol2Indices = <int>[1, 3, 5, 7, 9];

  /// Central, dynamic product-tour definition. Page count, the page
  /// indicator, Previous / Next logic and the final-page CTA all
  /// derive from [_cards].length — nothing is hardcoded — so the tour
  /// can grow card-by-card without touching navigation.
  ///
  /// The first two entries (welcome, central_cockpit) are the
  /// already-approved cards and are intentionally left untouched
  /// visually: their bespoke heroes are routed via
  /// [_OrientationCardLayout]. Every later entry is a safe
  /// [_OrientationCardLayout.placeholder] stop for the planned
  /// 15-card tour; each carries a real localised topic title so the
  /// flow already reads correctly, while bodies stay intentionally
  /// generic until that card graduates to its bespoke layout.
  static const List<_OrientationCardData> _cards = <_OrientationCardData>[
    // 1 — Welcome (approved; bespoke video hero on tablet).
    _OrientationCardData(
      id: 'welcome',
      layout: _OrientationCardLayout.welcome,
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
    // 2 — Company Cockpit (approved; bespoke PNG + overlay hero on
    // tablet). Bullets and artwork are now carried by the central
    // model; the bespoke overlay renders identically to before.
    _OrientationCardData(
      id: 'central_cockpit',
      layout: _OrientationCardLayout.companyCockpit,
      icon: Icons.dashboard_outlined,
      title: _card2CompanyCockpitTitle,
      body: _card2CompanyCockpitSubtitle,
      bullets: _companyCockpitBulletItems,
      portraitAsset: _card2WelcomeTabletPortraitAsset,
      landscapeAsset: _card2WelcomeTabletLandscapeAsset,
    ),
    // 3 — Subscription & scalability (approved; bespoke PNG + overlay
    // hero on tablet). title/body feed both the bespoke overlay and
    // the phone icon-card fallback; the two info cards + bottom strip
    // bind their own central-model copy in the bespoke builders.
    _OrientationCardData(
      id: 'subscription_scalability',
      layout: _OrientationCardLayout.subscription,
      icon: Icons.workspace_premium_outlined,
      title: _card3SubscriptionTitle,
      body: _card3SubscriptionBody,
      portraitAsset: _card3TabletPortraitAsset,
      landscapeAsset: _card3TabletLandscapeAsset,
    ),
    // 4 — Settings & company profile.
    _OrientationCardData(
      id: 'settings_profile',
      layout: _OrientationCardLayout.placeholder,
      icon: Icons.settings_outlined,
      title: _Tr(
        nl: 'Instellingen & bedrijfsprofiel',
        en: 'Settings & company profile',
        fr: 'Paramètres et profil d\u2019entreprise',
        es: 'Ajustes y perfil de empresa',
      ),
      body: _placeholderBody,
    ),
    // 5 — Subscription & account status.
    _OrientationCardData(
      id: 'subscription_status',
      layout: _OrientationCardLayout.placeholder,
      icon: Icons.workspace_premium_outlined,
      title: _Tr(
        nl: 'Abonnement & accountstatus',
        en: 'Subscription & account status',
        fr: 'Abonnement et statut du compte',
        es: 'Suscripción y estado de la cuenta',
      ),
      body: _placeholderBody,
    ),
    // 6 — Vehicles.
    _OrientationCardData(
      id: 'vehicles',
      layout: _OrientationCardLayout.placeholder,
      icon: Icons.directions_car_outlined,
      title: _Tr(
        nl: 'Voertuigen',
        en: 'Vehicles',
        fr: 'Véhicules',
        es: 'Vehículos',
      ),
      body: _placeholderBody,
    ),
    // 7 — Drivers.
    _OrientationCardData(
      id: 'drivers',
      layout: _OrientationCardLayout.placeholder,
      icon: Icons.people_outline,
      title: _Tr(
        nl: 'Chauffeurs',
        en: 'Drivers',
        fr: 'Chauffeurs',
        es: 'Conductores',
      ),
      body: _placeholderBody,
    ),
    // 8 — Chiron & document control.
    _OrientationCardData(
      id: 'chiron_documents',
      layout: _OrientationCardLayout.placeholder,
      icon: Icons.verified_user_outlined,
      title: _Tr(
        nl: 'Chiron & documentbeheer',
        en: 'Chiron & document control',
        fr: 'Chiron et contrôle des documents',
        es: 'Chiron y control de documentos',
      ),
      body: _placeholderBody,
    ),
    // 9 — Demand radar / demand insight.
    _OrientationCardData(
      id: 'demand_radar',
      layout: _OrientationCardLayout.placeholder,
      icon: Icons.radar,
      title: _Tr(
        nl: 'Demand radar & inzicht',
        en: 'Demand radar & insight',
        fr: 'Radar de demande et analyse',
        es: 'Radar de demanda e información',
      ),
      body: _placeholderBody,
    ),
    // 10 — Public booking link.
    _OrientationCardData(
      id: 'public_booking_link',
      layout: _OrientationCardLayout.placeholder,
      icon: Icons.link_outlined,
      title: _Tr(
        nl: 'Publieke boekingslink',
        en: 'Public booking link',
        fr: 'Lien de réservation public',
        es: 'Enlace público de reserva',
      ),
      body: _placeholderBody,
    ),
    // 11 — AI Dispatch.
    _OrientationCardData(
      id: 'ai_dispatch',
      layout: _OrientationCardLayout.placeholder,
      icon: Icons.auto_awesome_outlined,
      title: _Tr(
        nl: 'AI Dispatch',
        en: 'AI Dispatch',
        fr: 'Dispatch IA',
        es: 'Despacho IA',
      ),
      body: _placeholderBody,
    ),
    // 12 — Driver view.
    _OrientationCardData(
      id: 'driver_view',
      layout: _OrientationCardLayout.placeholder,
      icon: Icons.drive_eta_outlined,
      title: _Tr(
        nl: 'Chauffeursweergave',
        en: 'Driver view',
        fr: 'Vue chauffeur',
        es: 'Vista del conductor',
      ),
      body: _placeholderBody,
    ),
    // 13 — Calculator, Streetride & driver rides.
    _OrientationCardData(
      id: 'calculator_streetride',
      layout: _OrientationCardLayout.placeholder,
      icon: Icons.calculate_outlined,
      title: _Tr(
        nl: 'Calculator, Streetride & chauffeursritten',
        en: 'Calculator, Streetride & driver rides',
        fr: 'Calculateur, Streetride et courses chauffeur',
        es: 'Calculadora, Streetride y viajes del conductor',
      ),
      body: _placeholderBody,
    ),
    // 14 — Ride receipts, history & documents.
    _OrientationCardData(
      id: 'ride_receipts',
      layout: _OrientationCardLayout.placeholder,
      icon: Icons.receipt_long_outlined,
      title: _Tr(
        nl: 'Ritbonnen, geschiedenis & documenten',
        en: 'Ride receipts, history & documents',
        fr: 'Reçus de course, historique et documents',
        es: 'Recibos de viaje, historial y documentos',
      ),
      body: _placeholderBody,
    ),
    // 15 — Activate your customers / share your link.
    _OrientationCardData(
      id: 'activate_customers',
      layout: _OrientationCardLayout.placeholder,
      icon: Icons.campaign_outlined,
      title: _Tr(
        nl: 'Activeer je klanten',
        en: 'Activate your customers',
        fr: 'Activez vos clients',
        es: 'Activa a tus clientes',
      ),
      body: _placeholderBody,
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

  /// Central accessor for the product-tour cards. Everything that
  /// needs the tour length or a specific card (page indicator,
  /// Previous / Next, final-page CTA, the PageView builder) reads
  /// through this so the flow stays driven by a single source of
  /// truth. Returns the const [_cards] list as-is today; kept as a
  /// method so a future dynamic/filtered tour can slot in without
  /// touching call sites.
  List<_OrientationCardData> _orientationCards() => _cards;

  /// Convenience: the card currently shown, derived from [_index].
  _OrientationCardData get _currentCard => _orientationCards()[_index];

  /// Shared localized bullet list for the Company Cockpit slide.
  List<_OrientationBulletItem> _companyCockpitItems() =>
      _companyCockpitBulletItems;

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
        isWelcome: _cards[next].layout == _OrientationCardLayout.welcome,
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
        // Route the bespoke heroes off the central card's layout type
        // rather than a hardcoded index, so adding/removing earlier
        // cards never silently re-points a hero at the wrong slide.
        final _OrientationCardData currentCard = _currentCard;
        final bool isWelcomeCard =
            currentCard.layout == _OrientationCardLayout.welcome;
        final bool isCompanyCockpitCard =
            currentCard.layout == _OrientationCardLayout.companyCockpit;
        final bool isSubscriptionCard =
            currentCard.layout == _OrientationCardLayout.subscription;
        final bool isWelcomeTabletHero =
            isWelcomeCard && (isTabletPortrait || isTabletLandscape);
        final bool isCentralCockpitTabletPortraitHero =
            isCompanyCockpitCard && isTabletPortrait;
        final bool isCentralCockpitTabletLandscapeHero =
            isCompanyCockpitCard && isTabletLandscape;
        // Card 3 artwork is on a near-black canvas like Card 2, so it
        // gets the same immersive [_heroBg] scaffold on tablet.
        final bool isSubscriptionTabletHero =
            isSubscriptionCard && (isTabletPortrait || isTabletLandscape);
        final Color scaffoldBackground =
            (isWelcomeTabletHero ||
                isCentralCockpitTabletPortraitHero ||
                isCentralCockpitTabletLandscapeHero ||
                isSubscriptionTabletHero)
            ? _heroBg
            : _bg;

        // Card 1 tablet landscape uses a FULL-VIEWPORT background
        // hero rendered behind the SafeArea + Column, instead of a
        // slot-bound panel. The page-counter / Skip row and the
        // dots / Previous / Next row float on top of the video, so
        // the hero is no longer cramped between two horizontal
        // bars. Card 1 tablet portrait keeps its in-slot rounded
        // panel hero (approved + committed); Cards 3-7 and phone
        // layouts are unchanged.
        final bool useLandscapeFullHero = isWelcomeCard && isTabletLandscape;
        final bool useCentralCockpitPortraitFullHero =
            isCompanyCockpitCard && isTabletPortrait;
        final bool useCentralCockpitLandscapeFullHero =
            isCompanyCockpitCard && isTabletLandscape;
        // Card 3 uses the same full-viewport hero approach as Card 2:
        // a PNG background behind the Stack with a localised overlay,
        // while the PageView slot is short-circuited to a transparent
        // box so the chrome floats on top.
        final bool useSubscriptionPortraitFullHero =
            isSubscriptionCard && isTabletPortrait;
        final bool useSubscriptionLandscapeFullHero =
            isSubscriptionCard && isTabletLandscape;

        // Keep only one Card 1 tablet-hero decoder active. Runs
        // post-frame so [MediaQuery] is stable and we do not call
        // play/pause synchronously inside [build].
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _syncHeroVideoPlayback(
            isWelcome: isWelcomeCard,
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
              if (useCentralCockpitPortraitFullHero)
                Positioned.fill(
                  child: _buildCentralCockpitTabletPortraitFullViewportHero(),
                ),
              if (useCentralCockpitLandscapeFullHero)
                Positioned.fill(
                  child: _buildCentralCockpitTabletLandscapeFullViewportHero(),
                ),
              if (useSubscriptionPortraitFullHero)
                Positioned.fill(
                  child: _buildSubscriptionTabletPortraitFullViewportHero(),
                ),
              if (useSubscriptionLandscapeFullHero)
                Positioned.fill(
                  child: _buildSubscriptionTabletLandscapeFullViewportHero(),
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
                    _buildTopBar(
                      isCompactHeight,
                      elevatedSkip:
                          useCentralCockpitLandscapeFullHero ||
                          useSubscriptionLandscapeFullHero,
                    ),
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
                          if (card.layout == _OrientationCardLayout.welcome &&
                              isTabletLandscape) {
                            return const SizedBox.expand();
                          }
                          if (card.layout ==
                                  _OrientationCardLayout.companyCockpit &&
                              isTabletPortrait) {
                            return const SizedBox.expand();
                          }
                          if (card.layout ==
                                  _OrientationCardLayout.companyCockpit &&
                              isTabletLandscape) {
                            return const SizedBox.expand();
                          }
                          // Card 3 tablet portrait/landscape: empty
                          // transparent slot. The dedicated full-
                          // viewport PNG hero behind this Stack is
                          // what the user sees; PageView keeps the
                          // swipe gesture.
                          if (card.layout ==
                                  _OrientationCardLayout.subscription &&
                              (isTabletPortrait || isTabletLandscape)) {
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
                              card.layout == _OrientationCardLayout.welcome &&
                              isTabletPortrait;
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
                      landscapeFullHero:
                          useLandscapeFullHero ||
                          useCentralCockpitPortraitFullHero ||
                          useCentralCockpitLandscapeFullHero ||
                          useSubscriptionPortraitFullHero ||
                          useSubscriptionLandscapeFullHero,
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

  Widget _buildTopBar(bool compact, {bool elevatedSkip = false}) {
    final isLast = _index == _cards.length - 1;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        compact ? 4 : 10,
        elevatedSkip ? 24 : 12,
        compact ? 2 : 4,
      ),
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
              style: TextButton.styleFrom(
                foregroundColor: elevatedSkip ? Colors.white : Colors.white70,
                backgroundColor: elevatedSkip
                    ? Colors.black.withOpacity(0.62)
                    : null,
                padding: EdgeInsets.symmetric(
                  horizontal: elevatedSkip ? 18 : 12,
                  vertical: elevatedSkip ? 10 : 4,
                ),
                minimumSize: Size(elevatedSkip ? 104 : 48, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: elevatedSkip
                      ? BorderSide(color: _gold.withOpacity(0.38))
                      : BorderSide.none,
                ),
              ),
              child: Text(
                _t(
                  const _Tr(
                    nl: 'Overslaan',
                    en: 'Skip',
                    fr: 'Ignorer',
                    es: 'Omitir',
                  ),
                ),
                style: TextStyle(
                  fontWeight: elevatedSkip ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: elevatedSkip ? 0.2 : 0,
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

  /// Per-card dispatcher: routes each card to its builder based on
  /// the central [_OrientationCardLayout]. Adding a new product-tour
  /// stop is therefore a data-only change in [_cards] — navigation,
  /// the page indicator, and this dispatcher all adapt automatically.
  ///
  /// Tablet portrait/landscape heroes for the welcome and company-
  /// cockpit cards are short-circuited to a transparent
  /// [SizedBox.expand] in [build] (the full-viewport hero sits behind
  /// the Stack), so those branches here only need to cover the phone
  /// fallback — the stable icon composition.
  Widget _buildCard(
    _OrientationCardData data,
    bool compact, {
    required bool isTabletPortrait,
  }) {
    switch (data.layout) {
      case _OrientationCardLayout.welcome:
        // Tablet portrait → the premium in-slot video hero. Phones
        // (and any non-tablet-portrait state that still reaches here)
        // fall back to the stable icon composition.
        if (isTabletPortrait) {
          return _buildWelcomeTabletPortraitVideoHero();
        }
        return _buildOrientationCard(data, compact);
      case _OrientationCardLayout.companyCockpit:
        // Tablet portrait/landscape are short-circuited in [build];
        // phones use the stable icon composition.
        return _buildOrientationCard(data, compact);
      case _OrientationCardLayout.subscription:
        // Tablet portrait/landscape are short-circuited in [build]
        // (bespoke PNG hero behind the Stack); phones fall back to the
        // stable icon composition with the card's title + body.
        return _buildOrientationCard(data, compact);
      case _OrientationCardLayout.iconCard:
        return _buildOrientationCard(data, compact);
      case _OrientationCardLayout.placeholder:
        return _buildPlaceholderOrientationCard(data, compact);
    }
  }

  /// Stable baseline composition shared by the icon-card layouts
  /// (welcome on phones, company cockpit on phones, and any future
  /// [_OrientationCardLayout.iconCard] stop). The only difference
  /// between cards is the [data] they bind — icon, title, body.
  ///
  /// Wrapped in a [SingleChildScrollView] so long localised bodies
  /// can never overflow; the body [Text] intentionally has no
  /// [maxLines] / [TextOverflow.ellipsis] so translations wrap in
  /// full instead of being clipped.
  Widget _buildOrientationCard(_OrientationCardData data, bool compact) {
    final double iconBoxSize = compact ? 44 : 64;
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

  /// Safe, centred placeholder for product-tour stops that are not
  /// yet designed ([_OrientationCardLayout.placeholder]).
  ///
  /// Deliberately overflow-proof and asset-free:
  /// * wrapped in a [SingleChildScrollView] + [Center] so it can
  ///   never produce a yellow/black overflow band, even with the
  ///   longest localisation and the smallest phone-landscape height;
  /// * renders NO image — it never touches [data.portraitAsset] /
  ///   [data.landscapeAsset], so it cannot raise asset-not-found
  ///   errors while artwork is still being produced;
  /// * the title wraps in full (gold, larger than the body) and the
  ///   body wraps in full (white/light grey) — no [maxLines] and no
  ///   [TextOverflow.ellipsis] on the explanatory text.
  ///
  /// A small "coming next" chip is shown ONLY in debug builds so the
  /// development scaffold is obvious while iterating; it is tree-
  /// shaken out of release/profile bundles via [kDebugMode].
  Widget _buildPlaceholderOrientationCard(
    _OrientationCardData data,
    bool compact,
  ) {
    final double iconBoxSize = compact ? 40 : 56;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: compact ? 8 : 20),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _gold.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _gold.withOpacity(0.22)),
                ),
                child: Icon(data.icon, color: _gold, size: iconBoxSize),
              ),
              SizedBox(height: compact ? 14 : 22),
              Text(
                _t(data.title),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _gold,
                  fontSize: compact ? 20 : 26,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: 0.1,
                ),
              ),
              SizedBox(height: compact ? 8 : 12),
              Text(
                _t(data.body),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.78),
                  fontSize: compact ? 13 : 15,
                  height: 1.5,
                ),
              ),
              if (kDebugMode) ...<Widget>[
                SizedBox(height: compact ? 14 : 20),
                _buildPlaceholderDevChip(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Debug-only "coming next" chip surfaced on placeholder cards so
  /// it is obvious during development which tour stops still need a
  /// bespoke layout. Removed from release/profile builds by the
  /// [kDebugMode] guard at the call site.
  Widget _buildPlaceholderDevChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _gold.withOpacity(0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.auto_awesome_outlined, size: 14, color: _gold),
          const SizedBox(width: 7),
          Text(
            _t(
              const _Tr(
                nl: 'Binnenkort',
                en: 'Coming next',
                fr: 'Bientôt',
                es: 'Próximamente',
              ),
            ),
            style: TextStyle(
              color: _gold,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  /// Card 2 tablet-landscape full-viewport hero: PNG background plus a
  /// localised overlay on the free black left area (card 2 landscape only).
  Widget _buildCentralCockpitTabletLandscapeFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Image.asset(
          _card2WelcomeTabletLandscapeAsset,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][CARD2_LANDSCAPE_PNG_FAIL] error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(child: _buildCentralCockpitTabletLandscapeOverlay()),
      ],
    );
  }

  Widget _buildCentralCockpitTabletLandscapeOverlay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        final bool isTabletLandscape = w >= 900 && h >= 600 && w > h;
        if (!isTabletLandscape) {
          return const SizedBox.shrink();
        }
        // Reserve bottom chrome (dots + Previous/Next) so text stays above it.
        const double bottomChromeReserve = 90.0;
        final double usableH = h - bottomChromeReserve;
        final double titleSize = (w * 0.036).clamp(36.0, 40.0);
        final double introSize = (w * 0.019).clamp(18.0, 20.0);
        final double bulletGridHeight = usableH * 0.38;
        return Stack(
          children: <Widget>[
            // Top text zone — empty black area between logo and cockpit.
            Positioned(
              left: w * 0.29,
              top: usableH * 0.095,
              width: w * 0.36,
              height: usableH * 0.24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _t(_card2CompanyCockpitTitle),
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: _gold,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                      letterSpacing: 0.15,
                      shadows: <Shadow>[
                        Shadow(color: _gold.withOpacity(0.45), blurRadius: 14),
                        Shadow(
                          color: Colors.black.withOpacity(0.75),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _t(_card2CompanyCockpitSubtitle),
                    maxLines: 3,
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.88),
                      fontSize: introSize,
                      height: 1.26,
                    ),
                  ),
                ],
              ),
            ),
            // Bullet grid — two columns, below logo wordmark, left of cockpit.
            Positioned(
              left: w * 0.065,
              top: usableH * 0.455,
              width: w * 0.55,
              height: bulletGridHeight,
              child: _buildCard2TabletLandscapeBulletGrid(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCard2TabletLandscapeBulletGrid() {
    final List<_OrientationBulletItem> items = _companyCockpitItems();
    final List<_OrientationBulletItem> leftItems = <_OrientationBulletItem>[
      for (final int i in _card2LandscapeCol1Indices) items[i],
    ];
    final List<_OrientationBulletItem> rightItems = <_OrientationBulletItem>[
      for (final int i in _card2LandscapeCol2Indices) items[i],
    ];

    Widget buildColumn(List<_OrientationBulletItem> columnItems) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < columnItems.length; i++) ...<Widget>[
            _buildCompanyCockpitBulletItem(
              columnItems[i],
              titleFontSize: 16.5,
              descriptionFontSize: 14.2,
              compactBullet: true,
            ),
            if (i != columnItems.length - 1) const SizedBox(height: 13),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: buildColumn(leftItems)),
        const SizedBox(width: 48),
        Expanded(child: buildColumn(rightItems)),
      ],
    );
  }

  Widget _buildCompanyCockpitBulletItem(
    _OrientationBulletItem item, {
    required double titleFontSize,
    required double descriptionFontSize,
    bool compactBullet = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        compactBullet
            ? _buildCard2LandscapeOverlayBullet()
            : _buildCard2OverlayBullet(),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _t(item.title),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: TextStyle(
                  color: _gold,
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                  letterSpacing: compactBullet ? 0.1 : 0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _t(item.description),
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.82),
                  fontSize: descriptionFontSize,
                  fontWeight: FontWeight.w500,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCard2LandscapeOverlayBullet() {
    return Container(
      width: 6,
      height: 6,
      margin: const EdgeInsets.only(top: 7),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _gold,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: _gold.withOpacity(0.55),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  /// Card 2 tablet-portrait full-viewport hero: PNG background plus a
  /// localised overlay on the free black left area and title zone.
  Widget _buildCentralCockpitTabletPortraitFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Image.asset(
          _card2WelcomeTabletPortraitAsset,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint('[ORIENTATION_FLOW][CARD2_PNG_FAIL] error=$error');
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(child: _buildCentralCockpitTabletPortraitOverlay()),
      ],
    );
  }

  Widget _buildCentralCockpitTabletPortraitOverlay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        // Logo reserved: x 0.00–0.36, y 0.00–0.23 — no Flutter text.
        final double titleLeft = w * 0.43;
        final double titleTop = h * 0.045;
        final double titleWidth = w * 0.48;
        final double explainLeft = w * 0.055;
        final double explainTop = h * 0.295;
        final double explainWidth = w * 0.300;
        final double explainHeight = h * 0.585;
        return Stack(
          children: <Widget>[
            Positioned(
              left: titleLeft,
              top: titleTop,
              width: titleWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _t(_card2CompanyCockpitTitle),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _gold,
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                      letterSpacing: 0.15,
                      shadows: <Shadow>[
                        Shadow(color: _gold.withOpacity(0.45), blurRadius: 14),
                        Shadow(
                          color: Colors.black.withOpacity(0.75),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _t(_card2CompanyCockpitSubtitle),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.86),
                      fontSize: 16.5,
                      height: 1.30,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: explainLeft,
              top: explainTop,
              width: explainWidth,
              height: explainHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  for (final _OrientationBulletItem item
                      in _companyCockpitItems())
                    _buildCompanyCockpitBulletItem(
                      item,
                      titleFontSize: 19,
                      descriptionFontSize: 14.5,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCard2OverlayBullet() {
    return Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.only(top: 7),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _gold,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: _gold.withOpacity(0.55),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  // =================================================================
  // Card 3 — Subscription & scalability (bespoke tablet heroes).
  //
  // Both orientations paint the dedicated card3 PNG full-bleed
  // ([BoxFit.cover]) behind the Stack and overlay the localised copy
  // with Flutter — the artwork supplies only the FLUXIDI wordmark and
  // the empty gold card / strip frames, never baked-in text.
  //
  // Every text block is overflow-proof: zone-sized copy is wrapped in
  // a [FittedBox] with [BoxFit.scaleDown] as a final safety net (on
  // top of responsive, per-breakpoint, language-aware font sizes), so
  // the longest NL/FR/ES strings shrink-to-fit rather than ever
  // raising a yellow/black overflow band. No important explanatory
  // text uses [TextOverflow.ellipsis]; all bodies wrap in full.
  // =================================================================

  /// Slightly trims the Card 3 base font sizes for the longer FR/ES
  /// copy so the responsive sizes already land smaller before the
  /// [FittedBox] safety net ever has to engage.
  double _card3LangFontScale() {
    switch (appLanguageNotifier.value) {
      case AppLanguage.fr:
      case AppLanguage.es:
        return 0.92;
      case AppLanguage.nl:
      case AppLanguage.en:
        return 1.0;
    }
  }

  Widget _buildSubscriptionTabletLandscapeFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Image.asset(
          _card3TabletLandscapeAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][CARD3_LANDSCAPE_PNG_FAIL] error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(child: _buildSubscriptionTabletLandscapeOverlay()),
      ],
    );
  }

  Widget _buildSubscriptionTabletLandscapeOverlay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        // The full hero is only mounted by [build] on tablets
        // (shortestSide >= 600) in landscape, so a simple orientation
        // guard here keeps the overlay in lock-step with the hero and
        // never suppresses the copy on smaller 600-class tablets.
        if (w <= h) {
          return const SizedBox.shrink();
        }
        final double scale = _card3LangFontScale().clamp(0.90, 1.0).toDouble();
        final double titleSize = 34 * scale;
        final double bodySize = 17 * scale;
        final double cardTitleSize = 21 * scale;
        final double cardBodySize = 14 * scale;
        final double bulletSize = 13.6 * scale;
        final double stripSize = (w * 0.017 * scale).clamp(16.0, 22.0);
        final double noteSize = (w * 0.011 * scale).clamp(12.0, 15.0);
        // Internal padding so each info block starts inset from the
        // top-left of its artwork card shape rather than hugging the
        // edge. Applied OUTSIDE the FittedBox so the inset is not
        // scaled away by the safety-net shrink.
        const EdgeInsets landscapeCardPadding = EdgeInsets.fromLTRB(
          52,
          4,
          36,
          68,
        );
        return Stack(
          children: <Widget>[
            Positioned(
              left: w * 0.315,
              top: h * 0.070,
              width: w * 0.48,
              height: h * 0.190,
              child: _buildSubscriptionTitleZone(
                zoneWidth: w * 0.48,
                titleSize: titleSize,
                bodySize: bodySize,
              ),
            ),
            Positioned(
              left: w * 0.019,
              top: h * 0.376,
              width: w * 0.464,
              height: h * 0.426,
              child: _buildSubscriptionInfoCard(
                zoneWidth: w * 0.464,
                padding: landscapeCardPadding,
                title: _card3LeftCardTitle,
                body: _card3LeftCardBody,
                bullets: _card3LeftCardBullets,
                titleSize: cardTitleSize,
                bodySize: cardBodySize,
                bulletSize: bulletSize,
                titleBodyGap: 6,
                bodyBulletsGap: 9,
                bulletGap: 4,
                bodyLineHeight: 1.13,
                bulletLineHeight: 1.10,
              ),
            ),
            Positioned(
              left: w * 0.518,
              top: h * 0.376,
              width: w * 0.464,
              height: h * 0.426,
              child: _buildSubscriptionInfoCard(
                zoneWidth: w * 0.464,
                padding: landscapeCardPadding,
                title: _card3RightCardTitle,
                body: _card3RightCardBody,
                bullets: _card3RightCardBullets,
                titleSize: cardTitleSize,
                bodySize: cardBodySize,
                bulletSize: bulletSize,
                titleBodyGap: 6,
                bodyBulletsGap: 9,
                bulletGap: 4,
                bodyLineHeight: 1.13,
                bulletLineHeight: 1.10,
              ),
            ),
            Positioned(
              left: w * 0.019,
              top: h * 0.765,
              width: w * 0.963,
              height: h * 0.111,
              child: _buildSubscriptionBottomStrip(
                fontSize: stripSize,
                isPortrait: false,
              ),
            ),
            if (_showSubscriptionBottomNoteOnTablet)
              Positioned(
                left: w * 0.08,
                top: h * 0.90,
                width: w * 0.84,
                height: h * 0.08,
                child: _buildSubscriptionBottomNote(
                  zoneWidth: w * 0.84,
                  fontSize: noteSize,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSubscriptionTabletPortraitFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Image.asset(
          _card3TabletPortraitAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][CARD3_PORTRAIT_PNG_FAIL] error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(child: _buildSubscriptionTabletPortraitOverlay()),
      ],
    );
  }

  Widget _buildSubscriptionTabletPortraitOverlay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        // Mirror of the landscape guard: the hero is only mounted on
        // tablet portrait, so a plain orientation check keeps the
        // overlay aligned with the hero across tablet sizes.
        if (h <= w) {
          return const SizedBox.shrink();
        }
        final double scale = _card3LangFontScale().clamp(0.90, 1.0).toDouble();
        final double titleSize = 29 * scale;
        final double bodySize = 15.5 * scale;
        final double cardTitleSize = 24 * scale;
        final double cardBodySize = 15 * scale;
        final double bulletSize = 14.5 * scale;
        final double stripSize = (w * 0.020 * scale).clamp(16.0, 22.0);
        final double noteSize = (w * 0.013 * scale).clamp(12.0, 15.0);
        // Internal padding so each stacked info block starts inset
        // from the top-left of its artwork card shape. Applied OUTSIDE
        // the FittedBox (see landscape) so the inset survives the
        // scale-down safety net.
        const EdgeInsets topCardPadding = EdgeInsets.fromLTRB(43, 35, 35, 26);
        const EdgeInsets bottomCardPadding = EdgeInsets.fromLTRB(
          43,
          21,
          35,
          26,
        );
        return Stack(
          children: <Widget>[
            Positioned(
              left: w * 0.42,
              top: h * 0.055,
              width: w * 0.50,
              height: h * 0.150,
              child: _buildSubscriptionTitleZone(
                zoneWidth: w * 0.50,
                titleSize: titleSize,
                bodySize: bodySize,
              ),
            ),
            Positioned(
              left: w * 0.053,
              top: h * 0.221,
              width: w * 0.893,
              height: h * 0.272,
              child: _buildSubscriptionInfoCard(
                zoneWidth: w * 0.893,
                padding: topCardPadding,
                title: _card3LeftCardTitle,
                body: _card3LeftCardBody,
                bullets: _card3LeftCardBullets,
                titleSize: cardTitleSize,
                bodySize: cardBodySize,
                bulletSize: bulletSize,
                titleBodyGap: 7,
                bodyBulletsGap: 10,
                bulletGap: 5,
                bodyLineHeight: 1.14,
                bulletLineHeight: 1.10,
              ),
            ),
            Positioned(
              left: w * 0.053,
              top: h * 0.521,
              width: w * 0.893,
              height: h * 0.254,
              child: _buildSubscriptionInfoCard(
                zoneWidth: w * 0.893,
                padding: bottomCardPadding,
                title: _card3RightCardTitle,
                body: _card3RightCardBody,
                bullets: _card3RightCardBullets,
                titleSize: cardTitleSize,
                bodySize: cardBodySize,
                bulletSize: bulletSize,
                titleBodyGap: 7,
                bodyBulletsGap: 10,
                bulletGap: 5,
                bodyLineHeight: 1.14,
                bulletLineHeight: 1.10,
              ),
            ),
            Positioned(
              left: w * 0.030,
              top: h * 0.836,
              width: w * 0.940,
              height: h * 0.058,
              child: _buildSubscriptionBottomStrip(
                fontSize: stripSize,
                isPortrait: true,
              ),
            ),
            if (_showSubscriptionBottomNoteOnTablet)
              Positioned(
                left: w * 0.08,
                top: h * 0.965,
                width: w * 0.84,
                height: h * 0.035,
                child: _buildSubscriptionBottomNote(
                  zoneWidth: w * 0.84,
                  fontSize: noteSize,
                ),
              ),
          ],
        );
      },
    );
  }

  /// Top title + body zone shared by both Card 3 orientations. Gold
  /// title is always larger than the white body. The whole column is
  /// scale-down-fitted to the zone so the longest copy can never
  /// overflow, while shorter copy keeps its full responsive size and
  /// stays anchored top-left.
  Widget _buildSubscriptionTitleZone({
    required double zoneWidth,
    required double titleSize,
    required double bodySize,
  }) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: zoneWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _t(_card3SubscriptionTitle),
              softWrap: true,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: _gold,
                fontSize: titleSize,
                fontWeight: FontWeight.w900,
                height: 1.06,
                letterSpacing: 0.15,
                shadows: <Shadow>[
                  Shadow(color: _gold.withOpacity(0.40), blurRadius: 14),
                  Shadow(
                    color: Colors.black.withOpacity(0.75),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _t(_card3SubscriptionBody),
              softWrap: true,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: Colors.white.withOpacity(0.90),
                fontSize: bodySize,
                height: 1.30,
                shadows: const <Shadow>[
                  Shadow(
                    color: Color(0xCC000000),
                    blurRadius: 8,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One info card (left or right) overlaid inside an artwork frame:
  /// gold title (larger), white body, then a gold-dot bullet list.
  /// The whole text column is scale-down-fitted to the artwork frame
  /// so long FR/ES copy never clips and never overflows.
  Widget _buildSubscriptionInfoCard({
    required double zoneWidth,
    required EdgeInsets padding,
    required _Tr title,
    required _Tr body,
    required List<_Tr> bullets,
    required double titleSize,
    required double bodySize,
    required double bulletSize,
    required double titleBodyGap,
    required double bodyBulletsGap,
    required double bulletGap,
    required double bodyLineHeight,
    required double bulletLineHeight,
  }) {
    return Padding(
      padding: padding,
      child: Align(
        alignment: Alignment.centerLeft,
        child: _buildScaleCappedSubscriptionColumn(
          scale: 1,
          minScale: 0.90,
          title: title,
          body: body,
          bullets: bullets,
          titleSize: titleSize,
          bodySize: bodySize,
          bulletSize: bulletSize,
          titleBodyGap: titleBodyGap,
          bodyBulletsGap: bodyBulletsGap,
          bulletGap: bulletGap,
          bodyLineHeight: bodyLineHeight,
          bulletLineHeight: bulletLineHeight,
        ),
      ),
    );
  }

  /// Builds the Card 3 info-column with a conservative retry that can
  /// reduce font/gap sizes down to 90% if the measured translated copy
  /// still exceeds the bounded Canva safe zone. This avoids the
  /// aggressive tiny-text behavior of a generic [FittedBox] while
  /// preventing RenderFlex overflow bands in the longest locales.
  Widget _buildScaleCappedSubscriptionColumn({
    required double scale,
    required double minScale,
    required _Tr title,
    required _Tr body,
    required List<_Tr> bullets,
    required double titleSize,
    required double bodySize,
    required double bulletSize,
    required double titleBodyGap,
    required double bodyBulletsGap,
    required double bulletGap,
    required double bodyLineHeight,
    required double bulletLineHeight,
  }) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final Widget column = _buildSubscriptionInfoColumn(
          scale: scale,
          title: title,
          body: body,
          bullets: bullets,
          titleSize: titleSize,
          bodySize: bodySize,
          bulletSize: bulletSize,
          titleBodyGap: titleBodyGap,
          bodyBulletsGap: bodyBulletsGap,
          bulletGap: bulletGap,
          bodyLineHeight: bodyLineHeight,
          bulletLineHeight: bulletLineHeight,
        );
        final TextPainter probe = TextPainter(
          textDirection: Directionality.of(ctx),
          maxLines: 1,
        );

        double textHeight(String value, TextStyle style, {int? maxLines}) {
          probe
            ..text = TextSpan(text: value, style: style)
            ..maxLines = maxLines
            ..layout(maxWidth: constraints.maxWidth);
          return probe.height;
        }

        final TextStyle titleStyle = _subscriptionInfoTitleStyle(
          titleSize * scale,
        );
        final TextStyle bodyStyle = _subscriptionInfoBodyStyle(
          bodySize * scale,
          bodyLineHeight,
        );
        final TextStyle bulletStyle = _subscriptionInfoBulletStyle(
          bulletSize * scale,
          bulletLineHeight,
        );
        final double estimatedHeight =
            textHeight(_t(title), titleStyle) +
            titleBodyGap * scale +
            textHeight(_t(body), bodyStyle, maxLines: 3) +
            bodyBulletsGap * scale +
            bullets.fold<double>(
              0,
              (sum, bullet) =>
                  sum +
                  bulletGap * scale +
                  textHeight(_t(bullet), bulletStyle, maxLines: 1),
            );
        final bool exceedsHeight = estimatedHeight > constraints.maxHeight;
        if (!exceedsHeight || scale <= minScale) return column;
        final double nextScale = (constraints.maxHeight / estimatedHeight)
            .clamp(minScale, scale)
            .toDouble();
        return _buildScaleCappedSubscriptionColumn(
          scale: nextScale,
          minScale: minScale,
          title: title,
          body: body,
          bullets: bullets,
          titleSize: titleSize,
          bodySize: bodySize,
          bulletSize: bulletSize,
          titleBodyGap: titleBodyGap,
          bodyBulletsGap: bodyBulletsGap,
          bulletGap: bulletGap,
          bodyLineHeight: bodyLineHeight,
          bulletLineHeight: bulletLineHeight,
        );
      },
    );
  }

  Widget _buildSubscriptionInfoColumn({
    required double scale,
    required _Tr title,
    required _Tr body,
    required List<_Tr> bullets,
    required double titleSize,
    required double bodySize,
    required double bulletSize,
    required double titleBodyGap,
    required double bodyBulletsGap,
    required double bulletGap,
    required double bodyLineHeight,
    required double bulletLineHeight,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _t(title),
          softWrap: true,
          overflow: TextOverflow.visible,
          style: _subscriptionInfoTitleStyle(titleSize * scale),
        ),
        SizedBox(height: titleBodyGap * scale),
        Text(
          _t(body),
          maxLines: 3,
          softWrap: true,
          overflow: TextOverflow.visible,
          style: _subscriptionInfoBodyStyle(bodySize * scale, bodyLineHeight),
        ),
        SizedBox(height: bodyBulletsGap * scale),
        for (final _Tr bullet in bullets)
          _buildSubscriptionBullet(
            bullet,
            bulletSize * scale,
            gap: bulletGap * scale,
            lineHeight: bulletLineHeight,
          ),
      ],
    );
  }

  TextStyle _subscriptionInfoTitleStyle(double fontSize) {
    return TextStyle(
      color: _gold,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      height: 1.10,
      letterSpacing: 0.1,
      shadows: <Shadow>[
        Shadow(
          color: Colors.black.withOpacity(0.70),
          blurRadius: 8,
          offset: const Offset(0, 1),
        ),
      ],
    );
  }

  TextStyle _subscriptionInfoBodyStyle(double fontSize, double lineHeight) {
    return TextStyle(
      color: Colors.white.withOpacity(0.90),
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      height: lineHeight,
      shadows: const <Shadow>[
        Shadow(color: Color(0xCC000000), blurRadius: 7, offset: Offset(0, 1)),
      ],
    );
  }

  TextStyle _subscriptionInfoBulletStyle(double fontSize, double lineHeight) {
    return TextStyle(
      color: Colors.white.withOpacity(0.92),
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      height: lineHeight,
      shadows: const <Shadow>[
        Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
      ],
    );
  }

  Widget _buildSubscriptionBullet(
    _Tr text,
    double fontSize, {
    required double gap,
    required double lineHeight,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: gap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _gold,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: _gold.withOpacity(0.55),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _t(text),
              maxLines: 1,
              softWrap: true,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: Colors.white.withOpacity(0.92),
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                height: lineHeight,
                shadows: const <Shadow>[
                  Shadow(
                    color: Color(0xCC000000),
                    blurRadius: 6,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom "view current plans online" strip overlaid on the
  /// artwork's gold bar. Dark, bold text (the bar is bright gold) plus
  /// an open-in-new glyph reads as a button without re-drawing one.
  ///
  /// TODO: Wire to current Fluxidi plans/pricing URL.
  /// This overlay is wrapped in [IgnorePointer] (so it never blocks
  /// PageView swipes or the Skip / Previous / Next controls) and this
  /// file imports no URL-launch helper, so the CTA is intentionally a
  /// non-clickable visual guide for now. No pricing value is shown —
  /// current prices stay on the website.
  Widget _buildSubscriptionBottomStrip({
    required double fontSize,
    required bool isPortrait,
  }) {
    final double subscriptionCtaDy = isPortrait ? 18 : -28;
    debugPrint(
      '[SUBSCRIPTION_CTA] isPortrait=$isPortrait dy=$subscriptionCtaDy',
    );
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Transform.translate(
          offset: Offset(0, subscriptionCtaDy),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(
                _t(_card3BottomStrip),
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  color: _bg,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  shadows: const <Shadow>[
                    Shadow(color: Color(0x40FFFFFF), blurRadius: 6),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.open_in_new, color: _bg, size: fontSize + 2),
            ],
          ),
        ),
      ),
    );
  }

  /// Small reassurance note under the strip (on the black canvas).
  /// White/light-grey, wraps in full, scale-down-fitted so it can
  /// never overflow its thin zone.
  Widget _buildSubscriptionBottomNote({
    required double zoneWidth,
    required double fontSize,
  }) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: SizedBox(
        width: zoneWidth,
        child: Text(
          _t(_card3BottomNote),
          textAlign: TextAlign.center,
          softWrap: true,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: Colors.white.withOpacity(0.72),
            fontSize: fontSize,
            height: 1.25,
            shadows: const <Shadow>[
              Shadow(
                color: Color(0xCC000000),
                blurRadius: 6,
                offset: Offset(0, 1),
              ),
            ],
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

/// Layout / template type that drives how a card in [_cards] is
/// rendered. This is the single switch the orientation flow uses to
/// decide which builder a card routes to, so the product tour can
/// grow card-by-card without rewriting navigation each time.
///
/// * [welcome] — bespoke Card 1 hero (silent looping MP4 + PNG poster
///   on tablet portrait/landscape; the generic icon card on phones).
/// * [companyCockpit] — bespoke Card 2 hero (PNG background + a
///   localised overlay on tablet portrait/landscape; the generic icon
///   card on phones).
/// * [subscription] — bespoke Card 3 hero (PNG background + a
///   localised overlay: title/body zone, two info cards, and a
///   bottom plans strip) on tablet portrait/landscape; the generic
///   icon card on phones.
/// * [iconCard] — the stable baseline icon + title + body composition.
/// * [placeholder] — a safe, centred, scroll-friendly "coming next"
///   card for product-tour stops that are not yet designed. Never
///   loads an image, so it cannot raise asset-not-found errors and
///   cannot overflow.
enum _OrientationCardLayout {
  welcome,
  companyCockpit,
  subscription,
  iconCard,
  placeholder,
}

class _OrientationCardData {
  const _OrientationCardData({
    required this.id,
    required this.layout,
    required this.icon,
    required this.title,
    required this.body,
    this.bullets = const <_OrientationBulletItem>[],
    this.portraitAsset,
    this.landscapeAsset,
  });

  /// Stable identifier used in `[ORIENTATION_FLOW][PAGE/SKIP]` logs so
  /// QA can grep for a specific card regardless of its position in the
  /// (dynamic, [_cards] driven) product-tour sequence.
  final String id;

  /// Which builder this card routes to. See [_OrientationCardLayout].
  final _OrientationCardLayout layout;

  final IconData icon;
  final _Tr title;
  final _Tr body;

  /// Localised bullet / highlight items. Empty for cards that don't
  /// use a bullet list (welcome, plain icon cards, placeholders).
  final List<_OrientationBulletItem> bullets;

  /// Optional tablet-portrait artwork path. `null` for cards without
  /// dedicated portrait artwork. Only rendered by the bespoke
  /// per-card heroes — the placeholder layout never reads it.
  final String? portraitAsset;

  /// Optional tablet-landscape artwork path. `null` for cards without
  /// dedicated landscape artwork. Only rendered by the bespoke
  /// per-card heroes — the placeholder layout never reads it.
  final String? landscapeAsset;
}

class _OrientationBulletItem {
  const _OrientationBulletItem({
    required this.title,
    required this.description,
  });

  final _Tr title;
  final _Tr description;
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
