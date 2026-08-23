import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_taxi_qr_isolation.dart';
import 'package:fluxidi_tracking/widgets/fluxidi_decode_sized_asset_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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

/// Which entry point opened the orientation / product-tour flow.
///
/// Drives Card 1's status pill + intro sentence so the "Setup
/// voltooid" reward moment is only shown when the tour is launched
/// right after the guided setup/settings flow has been completed.
/// Opening the same tour later from Help & guide uses the neutral
/// "Startgids" framing instead, where claiming setup is "complete"
/// would be misleading.
enum BusinessOrientationEntryMode {
  /// Opened from Help & guide or any general entry point — neutral
  /// "Startgids / Quick guide" framing. Safe default.
  generalGuide,

  /// Opened immediately after the guided setup/settings flow was
  /// completed — celebratory "Setup voltooid / Setup complete"
  /// framing.
  setupCompleted,
}

class BusinessOrientationFlowPage extends StatefulWidget {
  const BusinessOrientationFlowPage({
    super.key,
    required this.onFinish,
    this.onSkip,
    this.entryMode = BusinessOrientationEntryMode.generalGuide,
  });

  /// Entry context for the tour. Controls only Card 1's status pill
  /// and intro sentence (see [BusinessOrientationEntryMode]); the page
  /// order, navigation chrome and every other card stay identical.
  /// Defaults to the safe [BusinessOrientationEntryMode.generalGuide]
  /// so any general/Help entry point never falsely claims setup is
  /// complete.
  final BusinessOrientationEntryMode entryMode;

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

  /// Currently selected preview in the Card 5 (themes & branding)
  /// interactive Theme Showroom. Plain integer state — no nested
  /// PageView, no swipe carousel. The left/right arrows inside the
  /// tablet mockup decrement/increment this with wrap-around, and the
  /// whole orientation page rebuilds via [setState] so the preview's
  /// [AnimatedSwitcher] cross-fades to the new screenshot.
  int _themeShowroomIndex = 0;

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
      'assets/fluxidi/onboarding/card1_welcome_tablet_portrait_bg.webp';

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
      'assets/fluxidi/onboarding/card1_welcome_tablet_landscape_bg.webp';

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
      'assets/fluxidi/onboarding/card2_welcome_tablet_portrait_bg.webp';

  /// Card 2 tablet-landscape PNG — cockpit visual for the orientation
  /// flow's second card in landscape only.
  static const String _card2WelcomeTabletLandscapeAsset =
      'assets/fluxidi/onboarding/card2_welcome_tablet_landscape_bg.webp';

  /// Card 3 tablet PNGs — present on disk and covered by the
  /// `assets/fluxidi/onboarding/` folder already declared in
  /// pubspec. Reserved for the not-yet-designed "Bookings,
  /// cancellations & history" card and stored in the central model
  /// now so the future bespoke layout can pick them up without
  /// touching navigation. The current placeholder layout is
  /// text-only and never renders these, so there is no asset risk
  /// yet — the paths simply travel with the card data.
  static const String _card3TabletPortraitAsset =
      'assets/fluxidi/onboarding/card3_welcome_tablet_portrait_bg.webp';
  static const String _card3TabletLandscapeAsset =
      'assets/fluxidi/onboarding/card3_welcome_tablet_landscape_bg.webp';

  /// Card 4 tablet PNGs — vehicles & fleet management. The vehicle
  /// screenshot is baked into the artwork; Flutter overlays only the
  /// localised title + intro in the empty background area ABOVE the
  /// screenshot. Rendered full-viewport so overlay fractions line up
  /// with the visible asset.
  static const String _card4VehiclesFleetTabletPortraitAsset =
      'assets/fluxidi/onboarding/card4_welcome_tablet_portrait_bg.webp';
  static const String _card4VehiclesFleetTabletLandscapeAsset =
      'assets/fluxidi/onboarding/card4_welcome_tablet_landscape_bg.webp';

  // ---------------------------------------------------------------
  // Slide 4 — Settings & company profile (the Fluxidi "settings
  // engine" / business control center). Uses the dedicated card14
  // settings/cockpit artwork and overlays ALL localized copy in the
  // measured safe frames — the panels are the only painted chrome.
  //
  // NOTE: these assets are named `card14` but are intentionally used
  // for the `settings_profile` page 4/15 for now. This does NOT touch
  // Ride Receipts (card 14) logic, which keeps its own card12 assets.
  // ---------------------------------------------------------------

  static const String _settingsProfileTabletPortraitAsset =
      'assets/fluxidi/onboarding/card14_welcome_tablet_portrait_bg.webp';
  static const String _settingsProfileTabletLandscapeAsset =
      'assets/fluxidi/onboarding/card14_welcome_tablet_landscape_bg.webp';

  static const _Tr _settingsProfileTopTitle = _Tr(
    nl: 'Je bedrijfsklare cockpit',
    en: 'Your business-ready cockpit',
    fr: 'Votre cockpit prêt pour l’activité',
    es: 'Tu cockpit listo para operar',
  );

  static const _Tr _settingsProfileTopIntro = _Tr(
    nl:
        'Beheer de volledige white-label motor van je taxi- of vervoersbedrijf: '
        'identiteit, tarieven, betalingen, diensten en publicatie.',
    en:
        'Manage the full white-label engine of your taxi or mobility company: '
        'identity, pricing, payments, services and publishing.',
    fr:
        'Gérez le moteur white-label complet de votre société de taxi ou '
        'mobilité : identité, prix, paiements, services et publication.',
    es:
        'Gestiona el motor white-label completo de tu empresa de taxi o '
        'movilidad: identidad, precios, pagos, servicios y publicación.',
  );

  static const _Tr _settingsProfileLabel = _Tr(
    nl: 'SETTINGS ENGINE',
    en: 'SETTINGS ENGINE',
    fr: 'MOTEUR DE PARAMÈTRES',
    es: 'MOTOR DE AJUSTES',
  );

  static const _Tr _settingsProfileMainTitle = _Tr(
    nl: 'Configureer je bedrijf alsof het een professionele centrale is.',
    en: 'Configure your company like a professional dispatch center.',
    fr: 'Configurez votre entreprise comme une centrale professionnelle.',
    es: 'Configura tu empresa como una central profesional.',
  );

  static const _Tr _settingsProfileBody = _Tr(
    nl:
        'Fluxidi bundelt alle cruciale bedrijfsinstellingen in één cockpit. Je '
        'ziet meteen wat compleet is, wat aandacht vraagt en wat klaar is om '
        'veilig online te publiceren.',
    en:
        'Fluxidi brings all critical business settings into one cockpit. You '
        'instantly see what is complete, what needs attention and what is ready '
        'to publish safely.',
    fr:
        'Fluxidi regroupe tous les paramètres essentiels dans un seul cockpit. '
        'Vous voyez immédiatement ce qui est complet, ce qui demande attention '
        'et ce qui peut être publié en sécurité.',
    es:
        'Fluxidi reúne todos los ajustes críticos en un solo cockpit. Ves al '
        'instante qué está completo, qué necesita atención y qué está listo '
        'para publicarse con seguridad.',
  );

  static const List<_SettingsProfileFeature>
  _settingsProfileFeatures = <_SettingsProfileFeature>[
    _SettingsProfileFeature(
      icon: Icons.apartment_outlined,
      title: _Tr(
        nl: 'Bedrijfsfundament',
        en: 'Business foundation',
        fr: 'Base d’entreprise',
        es: 'Base de empresa',
      ),
      description: _Tr(
        nl:
            'Naam, adres, BTW, facturatie, logo, support en publieke '
            'partnerpagina.',
        en:
            'Name, address, VAT, billing, logo, support and public partner '
            'profile.',
        fr:
            'Nom, adresse, TVA, facturation, logo, support et profil '
            'partenaire public.',
        es:
            'Nombre, dirección, IVA, facturación, logo, soporte y perfil '
            'público de partner.',
      ),
    ),
    _SettingsProfileFeature(
      icon: Icons.qr_code_2_outlined,
      title: _Tr(
        nl: 'Boekingsmotor',
        en: 'Booking engine',
        fr: 'Moteur de réservation',
        es: 'Motor de reservas',
      ),
      description: _Tr(
        nl:
            'Publieke link, QR-flow, kalenderkoppeling, diensten, tiers en '
            'luchthavenregels.',
        en:
            'Public link, QR flow, calendar connection, services, tiers and '
            'airport rules.',
        fr:
            'Lien public, QR, calendrier, services, niveaux et règles '
            'aéroport.',
        es:
            'Enlace público, QR, calendario, servicios, niveles y reglas de '
            'aeropuerto.',
      ),
    ),
    _SettingsProfileFeature(
      icon: Icons.payments_outlined,
      title: _Tr(
        nl: 'Commerciële regels',
        en: 'Commercial rules',
        fr: 'Règles commerciales',
        es: 'Reglas comerciales',
      ),
      description: _Tr(
        nl:
            'Tarieven, toeslagen, annulatiebeleid, betaalmethodes en vaste '
            'luchthavenprijzen.',
        en:
            'Fares, surcharges, cancellation policy, payment methods and '
            'fixed airport prices.',
        fr:
            'Tarifs, suppléments, annulation, moyens de paiement et prix '
            'fixes aéroport.',
        es:
            'Tarifas, recargos, cancelación, métodos de pago y precios fijos '
            'de aeropuerto.',
      ),
    ),
    _SettingsProfileFeature(
      icon: Icons.verified_outlined,
      title: _Tr(
        nl: 'Publicatiecontrole',
        en: 'Publishing control',
        fr: 'Contrôle de publication',
        es: 'Control de publicación',
      ),
      description: _Tr(
        nl:
            'Statusbadges tonen wat klaar is, wat ontbreekt en wat actie '
            'vraagt.',
        en:
            'Status badges show what is ready, what is missing and what '
            'needs action.',
        fr:
            'Les statuts montrent ce qui est prêt, ce qui manque et ce qui '
            'demande action.',
        es:
            'Los estados muestran qué está listo, qué falta y qué requiere '
            'acción.',
      ),
    ),
  ];

  static const _Tr _settingsProfileFooter = _Tr(
    nl:
        'Minder losse tools. Meer controle. Klaar om te groeien per regio, '
        'bedrijf en chauffeur.',
    en:
        'Fewer scattered tools. More control. Ready to grow by region, company '
        'and driver.',
    fr:
        'Moins d’outils dispersés. Plus de contrôle. Prêt à grandir par région, '
        'entreprise et chauffeur.',
    es:
        'Menos herramientas sueltas. Más control. Listo para crecer por región, '
        'empresa y conductor.',
  );

  // ---------------------------------------------------------------
  // Slide 5 — Themes & branding: the interactive Fluxidi Theme
  // Showroom. A fixed tablet/mockup preview cycles through real
  // Fluxidi screenshots via in-preview left/right arrows (plain
  // integer state, no nested PageView / swipe carousel). Two coherent
  // dark-glass panels (title + explanation) frame the hero preview.
  //
  // The preview assets live in a dedicated TOP-LEVEL folder
  // (assets_card5_themes/) that is kept OUTSIDE the assets/fluxidi/
  // parent asset tree. The reason: in this Flutter version the parent
  // `- assets/fluxidi/` entry recursively bundles subfolders, so adding
  // an explicit child entry for the same files double-copies and throws
  // PathExistsException — while removing the child means the assets
  // aren't reliably found at runtime. Hosting card 5 assets under their
  // own top-level folder sidesteps both edge cases with exactly one
  // explicit registration in pubspec.yaml and never collides with any
  // other parent entry.
  // ---------------------------------------------------------------

  static const String _card5ThemesAssetDir = 'assets_card5_themes/';

  /// Cinematic background painted behind the vertical tablet preview in
  /// the hero zone of Card 5. The interactive tablet still floats on top
  /// — this asset is a backdrop only and is never used as the preview
  /// itself.
  static const String _themesShowroomHeroBgAsset =
      '${_card5ThemesAssetDir}card5_theme_showroom_hero_bg.png';

  static const _Tr _themesCategoryBusiness = _Tr(
    nl: 'Bedrijfscockpit',
    en: 'Business cockpit',
    fr: 'Cockpit business',
    es: 'Cockpit business',
  );

  static const _Tr _themesCategoryDriver = _Tr(
    nl: 'Chauffeursweergave',
    en: 'Driver view',
    fr: 'Vue chauffeur',
    es: 'Vista conductor',
  );

  static const _Tr _themesCategoryConfig = _Tr(
    nl: 'Configuratie',
    en: 'Configuration',
    fr: 'Configuration',
    es: 'Configuración',
  );

  /// The 10 Theme Showroom previews. Titles are brand names (kept the
  /// same across languages); the category localizes. Accent / secondary
  /// colors drive the tablet frame's border + glow per preview.
  static const List<_ThemeShowroomItem>
  _themeShowroomItems = <_ThemeShowroomItem>[
    _ThemeShowroomItem(
      title: 'Executive Gold',
      category: _themesCategoryBusiness,
      assetPath:
          '${_card5ThemesAssetDir}card5_theme_01_business_executive_gold.jpg',
      accentColor: Color(0xFFE5B641),
      secondaryColor: Color(0xFF7A5C12),
    ),
    _ThemeShowroomItem(
      title: 'Corporate Blue',
      category: _themesCategoryBusiness,
      assetPath:
          '${_card5ThemesAssetDir}card5_theme_02_business_corporate_blue.jpg',
      accentColor: Color(0xFF3B82F6),
      secondaryColor: Color(0xFF1E3A8A),
    ),
    _ThemeShowroomItem(
      title: 'Clean Professional',
      category: _themesCategoryBusiness,
      assetPath:
          '${_card5ThemesAssetDir}card5_theme_03_business_clean_professional.jpg',
      accentColor: Color(0xFF94A3B8),
      secondaryColor: Color(0xFF475569),
    ),
    _ThemeShowroomItem(
      title: 'Emerald Ivory',
      category: _themesCategoryBusiness,
      assetPath:
          '${_card5ThemesAssetDir}card5_theme_04_business_emerald_ivory.jpg',
      accentColor: Color(0xFF10B981),
      secondaryColor: Color(0xFF065F46),
    ),
    _ThemeShowroomItem(
      title: 'Fluxidi Neon Rush',
      category: _themesCategoryBusiness,
      assetPath: '${_card5ThemesAssetDir}card5_theme_05_business_neon_rush.jpg',
      accentColor: Color(0xFFEC4899),
      secondaryColor: Color(0xFF7C3AED),
    ),
    _ThemeShowroomItem(
      title: 'Night Gold',
      category: _themesCategoryDriver,
      assetPath: '${_card5ThemesAssetDir}card5_theme_06_driver_night_gold.jpg',
      accentColor: Color(0xFFE5B641),
      secondaryColor: Color(0xFF1F2937),
    ),
    _ThemeShowroomItem(
      title: 'Midnight Blue',
      category: _themesCategoryDriver,
      assetPath:
          '${_card5ThemesAssetDir}card5_theme_07_driver_midnight_blue.jpg',
      accentColor: Color(0xFF2563EB),
      secondaryColor: Color(0xFF0F172A),
    ),
    _ThemeShowroomItem(
      title: 'Midday Gold',
      category: _themesCategoryDriver,
      assetPath: '${_card5ThemesAssetDir}card5_theme_08_driver_midday_gold.jpg',
      accentColor: Color(0xFFF59E0B),
      secondaryColor: Color(0xFFB45309),
    ),
    _ThemeShowroomItem(
      title: 'Theme settings',
      category: _themesCategoryConfig,
      assetPath: '${_card5ThemesAssetDir}card5_theme_09_theme_settings_top.jpg',
      accentColor: Color(0xFFE5B641),
      secondaryColor: Color(0xFF334155),
    ),
    _ThemeShowroomItem(
      title: 'Theme options',
      category: _themesCategoryConfig,
      assetPath:
          '${_card5ThemesAssetDir}card5_theme_10_theme_settings_options.jpg',
      accentColor: Color(0xFFE5B641),
      secondaryColor: Color(0xFF334155),
    ),
  ];

  static const _Tr _themesTitle = _Tr(
    nl: 'Thema’s & uitstraling',
    en: 'Themes & branding',
    fr: 'Thèmes & image',
    es: 'Temas e imagen',
  );

  static const _Tr _themesIntro = _Tr(
    nl:
        'Laat Fluxidi aansluiten bij je merk. Kies een stijl voor je '
        'bedrijfscockpit, chauffeursweergave en mobiele ervaring.',
    en:
        'Make Fluxidi match your brand. Choose a style for your business '
        'cockpit, driver view and mobile experience.',
    fr:
        'Adaptez Fluxidi à votre marque. Choisissez un style pour le cockpit, '
        'la vue chauffeur et l’expérience mobile.',
    es:
        'Haz que Fluxidi encaje con tu marca. Elige un estilo para el cockpit, '
        'la vista del conductor y la experiencia móvil.',
  );

  static const _Tr _themesLabel = _Tr(
    nl: 'THEME SHOWROOM',
    en: 'THEME SHOWROOM',
    fr: 'SHOWROOM DES THÈMES',
    es: 'SHOWROOM DE TEMAS',
  );

  static const _Tr _themesMainTitle = _Tr(
    nl: 'Toon je bedrijf in je eigen stijl.',
    en: 'Show your company in your own style.',
    fr: 'Présentez votre entreprise dans votre propre style.',
    es: 'Muestra tu empresa con tu propio estilo.',
  );

  static const _Tr _themesBody = _Tr(
    nl:
        'Blader door echte Fluxidi-thema’s en zie hoe kleur, sfeer en layout de '
        'ervaring veranderen voor bedrijf, chauffeur en klant.',
    en:
        'Browse real Fluxidi themes and see how color, mood and layout change '
        'the experience for the company, driver and customer.',
    fr:
        'Parcourez de vrais thèmes Fluxidi et voyez comment les couleurs, '
        'l’ambiance et la mise en page transforment l’expérience.',
    es:
        'Explora temas reales de Fluxidi y descubre cómo color, ambiente y '
        'diseño transforman la experiencia.',
  );

  static const List<_SettingsProfileFeature> _themesFeatures =
      <_SettingsProfileFeature>[
        _SettingsProfileFeature(
          icon: Icons.dashboard_customize_outlined,
          title: _Tr(
            nl: 'Business cockpit',
            en: 'Business cockpit',
            fr: 'Cockpit business',
            es: 'Cockpit business',
          ),
          description: _Tr(
            nl:
                'Executive Gold, Corporate Blue, Clean Professional, Emerald '
                'Ivory en Neon Rush.',
            en:
                'Executive Gold, Corporate Blue, Clean Professional, Emerald '
                'Ivory and Neon Rush.',
            fr:
                'Executive Gold, Corporate Blue, Clean Professional, Emerald '
                'Ivory et Neon Rush.',
            es:
                'Executive Gold, Corporate Blue, Clean Professional, Emerald '
                'Ivory y Neon Rush.',
          ),
        ),
        _SettingsProfileFeature(
          icon: Icons.drive_eta_outlined,
          title: _Tr(
            nl: 'Chauffeursweergave',
            en: 'Driver view',
            fr: 'Vue chauffeur',
            es: 'Vista conductor',
          ),
          description: _Tr(
            nl: 'Night Gold, Midnight Blue, Midday Gold en Light Emerald voor onderweg.',
            en: 'Night Gold, Midnight Blue, Midday Gold and Light Emerald for the road.',
            fr: 'Night Gold, Midnight Blue, Midday Gold et Light Emerald pour la route.',
            es: 'Night Gold, Midnight Blue, Midday Gold y Light Emerald para la carretera.',
          ),
        ),
        _SettingsProfileFeature(
          icon: Icons.view_quilt_outlined,
          title: _Tr(
            nl: 'Layout & herkenbaarheid',
            en: 'Layout & recognition',
            fr: 'Layout & reconnaissance',
            es: 'Layout y reconocimiento',
          ),
          description: _Tr(
            nl: 'Compact of visueel, met een uitstraling die past bij je merk.',
            en: 'Compact or visual, with a look that matches your brand.',
            fr: 'Compact ou visuel, avec une image adaptée à votre marque.',
            es: 'Compacto o visual, con una imagen adaptada a tu marca.',
          ),
        ),
      ];

  static const _Tr _themesFooter = _Tr(
    nl: 'White-label gevoel zonder ingewikkelde designsoftware.',
    en: 'A white-label feel without complex design software.',
    fr: 'Un rendu white-label sans logiciel de design complexe.',
    es: 'Sensación white-label sin software de diseño complejo.',
  );

  // ---------------------------------------------------------------
  // Card 4 — Vehicles & fleet management. First controlled step:
  // title + intro overlay only (no bullets / feature list yet). Both
  // strings feed the bespoke tablet overlay and the phone icon-card
  // fallback.
  // ---------------------------------------------------------------

  static const _Tr _card4VehiclesFleetTitle = _Tr(
    nl: 'Voertuigen & vlootbeheer',
    en: 'Vehicles & fleet management',
    fr: 'Véhicules & gestion de flotte',
    es: 'Vehículos y gestión de flota',
  );

  static const _Tr _card4VehiclesFleetIntro = _Tr(
    nl:
        'Beheer elk voertuig centraal: status, chauffeurkoppeling, documenten, '
        'capaciteit, categorie en publieke profielweergave.',
    en:
        'Manage every vehicle centrally: status, driver links, documents, '
        'capacity, category and public profile visibility.',
    fr:
        'Gérez chaque véhicule au même endroit : statut, chauffeur, documents, '
        'capacité, catégorie et visibilité publique.',
    es:
        'Gestiona cada vehículo desde un solo lugar: estado, conductor, '
        'documentos, capacidad, categoría y perfil público.',
  );

  static const List<_OrientationBulletItem>
  _card4VehiclesFleetFeatures = <_OrientationBulletItem>[
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Vlootoverzicht',
        en: 'Fleet overview',
        fr: 'Vue de flotte',
        es: 'Vista de flota',
      ),
      description: _Tr(
        nl:
            'Zie hoeveel voertuigen je bedrijf heeft, welke actief zijn '
            'en welke al aan een chauffeur gekoppeld zijn.',
        en:
            'See how many vehicles your company has, which are active and '
            'which are already linked to a driver.',
        fr:
            'Voyez vos véhicules, ceux qui sont actifs et ceux déjà liés à '
            'un chauffeur.',
        es:
            'Consulta tus vehículos, cuáles están activos y cuáles ya '
            'tienen conductor vinculado.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Voertuiggegevens',
        en: 'Vehicle details',
        fr: 'Données véhicule',
        es: 'Datos del vehículo',
      ),
      description: _Tr(
        nl:
            'Voeg naam, nummerplaat, vergunning, registratie, '
            'VIN/chassisnummer en kleur toe.',
        en:
            'Add name, plate, operating licence, registration, VIN/chassis '
            'number and colour.',
        fr:
            'Ajoutez nom, plaque, licence, immatriculation, VIN/châssis '
            'et couleur.',
        es:
            'Añade nombre, matrícula, licencia, registro, VIN/chasis y '
            'color.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Capaciteit & categorie',
        en: 'Capacity & category',
        fr: 'Capacité & catégorie',
        es: 'Capacidad & categoría',
      ),
      description: _Tr(
        nl:
            'Stel passagiers, bagage, bagagecapaciteit en categorie zoals '
            'comfort, private of premium in.',
        en:
            'Set passengers, baggage, luggage capacity and category such '
            'as comfort, private or premium.',
        fr:
            'Définissez passagers, bagages, capacité et catégorie : '
            'confort, privé ou premium.',
        es:
            'Define pasajeros, equipaje, capacidad y categoría: comfort, '
            'private o premium.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Chauffeur & status',
        en: 'Driver & status',
        fr: 'Chauffeur & statut',
        es: 'Conductor & estado',
      ),
      description: _Tr(
        nl:
            'Koppel een chauffeur en zet voertuigen eenvoudig actief of '
            'inactief.',
        en:
            'Link a driver and set vehicles active or inactive with one '
            'clear workflow.',
        fr:
            'Associez un chauffeur et activez ou désactivez vos véhicules '
            'facilement.',
        es:
            'Vincula un conductor y activa o desactiva vehículos de forma '
            'clara.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Publiek profiel',
        en: 'Public profile',
        fr: 'Profil public',
        es: 'Perfil público',
      ),
      description: _Tr(
        nl:
            'Voeg voertuigfoto’s toe die zichtbaar kunnen worden op je '
            'publieke partnerprofiel.',
        en:
            'Add vehicle photos that can appear on your public partner '
            'profile.',
        fr: 'Ajoutez des photos visibles sur votre profil partenaire public.',
        es: 'Añade fotos visibles en tu perfil público de partner.',
      ),
    ),
  ];

  static const _Tr _card4VehiclesFleetFooter = _Tr(
    nl: '+ Nieuw voertuig toevoegen',
    en: '+ Add new vehicle',
    fr: '+ Ajouter un véhicule',
    es: '+ Añadir vehículo',
  );

  /// Card 5 tablet PNGs — Chiron / audit / ride register. The receipt
  /// and register screenshots are baked into the artwork; Flutter
  /// overlays only localised copy in measured safe zones.
  static const String _card5ChironDocumentsTabletPortraitAsset =
      'assets/fluxidi/onboarding/card5_welcome_tablet_portrait_bg.webp';
  static const String _card5ChironDocumentsTabletLandscapeAsset =
      'assets/fluxidi/onboarding/card5_welcome_tablet_landscape_bg.webp';

  /// Card 6 tablet PNGs — Drivers & documents. The driver management
  /// screenshots are baked into the artwork; Flutter overlays only the
  /// localised title/intro and the feature panel in measured safe
  /// zones (never over driver faces or important controls).
  static const String _card6DriverManagementTabletPortraitAsset =
      'assets/fluxidi/onboarding/card6_welcome_tablet_portrait_bg.webp';
  static const String _card6DriverManagementTabletLandscapeAsset =
      'assets/fluxidi/onboarding/card6_welcome_tablet_landscape_bg.webp';

  /// Card 7 tablet PNGs — Region Radar. The radar / service-area
  /// visual is baked into the artwork; Flutter overlays one bounded
  /// text panel in measured dark safe zones beside the visual.
  static const String _card7RegionRadarTabletPortraitAsset =
      'assets/fluxidi/onboarding/card7_welcome_tablet_portrait_bg.webp';
  static const String _card7RegionRadarTabletLandscapeAsset =
      'assets/fluxidi/onboarding/card7_welcome_tablet_landscape_bg.webp';

  /// Card 9 tablet PNGs — Public booking link / Scan to Book. The QR
  /// booking visual is baked into the artwork; Flutter overlays one
  /// bounded premium panel in measured dark safe zones.
  static const String _card9PublicBookingLinkTabletPortraitAsset =
      'assets/fluxidi/onboarding/card9_welcome_tablet_portrait_bg.webp';
  static const String _card9PublicBookingLinkTabletLandscapeAsset =
      'assets/fluxidi/onboarding/card9_welcome_tablet_landscape_bg.webp';

  /// Card 10 tablet PNGs — AI Dispatch. The dispatch cockpit visual is
  /// baked into the artwork; Flutter overlays measured premium panels
  /// in dark safe zones.
  static const String _card10AiDispatchTabletPortraitAsset =
      'assets/fluxidi/onboarding/card10_welcome_tablet_portrait_bg.webp';
  static const String _card10AiDispatchTabletLandscapeAsset =
      'assets/fluxidi/onboarding/card10_welcome_tablet_landscape_bg.webp';

  /// Card 8 tablet PNGs — Driver View / Chauffeurcockpit. The driver
  /// dashboard visual is baked into the artwork; Flutter overlays
  /// measured premium panels in dark safe zones.
  static const String _card8DriverViewTabletPortraitAsset =
      'assets/fluxidi/onboarding/card8_welcome_tablet_portrait_bg.webp';
  static const String _card8DriverViewTabletLandscapeAsset =
      'assets/fluxidi/onboarding/card8_welcome_tablet_landscape_bg.webp';

  /// Card 11 tablet PNGs — Calculator & ride pricing. The calculator
  /// visual is baked into the artwork; Flutter overlays measured
  /// premium panels in dark safe zones.
  static const String _card11CalculatorTabletPortraitAsset =
      'assets/fluxidi/onboarding/card11_welcome_tablet_portrait_bg.webp';
  static const String _card11CalculatorTabletLandscapeAsset =
      'assets/fluxidi/onboarding/card11_welcome_tablet_landscape_bg.webp';

  /// Card 12 tablet PNGs — Driver receipts, history & documents. The
  /// in-cockpit tablet visual is baked into the artwork; Flutter
  /// overlays measured premium panels in dark safe zones.
  static const String _card12DriverReceiptsTabletPortraitAsset =
      'assets/fluxidi/onboarding/card12_welcome_tablet_portrait_bg.webp';
  static const String _card12DriverReceiptsTabletLandscapeAsset =
      'assets/fluxidi/onboarding/card12_welcome_tablet_landscape_bg.webp';

  /// Card 13 tablet PNGs — Activate customers. The final customer-app
  /// visual is baked into the artwork; Flutter overlays one measured
  /// premium panel in the dark safe zone.
  static const String _card13ActivateCustomersTabletPortraitAsset =
      'assets/fluxidi/onboarding/card13_welcome_tablet_portrait_bg.webp';
  static const String _card13ActivateCustomersTabletLandscapeAsset =
      'assets/fluxidi/onboarding/card13_welcome_tablet_landscape_bg.webp';

  static const _Tr _chironDocumentsTitle = _Tr(
    nl: 'Chiron & rittenregister',
    en: 'Chiron & ride register',
    fr: 'Chiron & registre des courses',
    es: 'Chiron y registro de viajes',
  );

  static const _Tr _chironDocumentsIntro = _Tr(
    nl:
        'Hou ritten, betalingen, ritbonnen en compliancegegevens centraal bij '
        'voor Chiron en controles.',
    en:
        'Keep rides, payments, receipts and compliance records centralized for '
        'Chiron and inspections.',
    fr:
        'Centralisez courses, paiements, reçus et données de conformité pour '
        'Chiron et les contrôles.',
    es:
        'Centraliza viajes, pagos, recibos y datos de cumplimiento para Chiron '
        'e inspecciones.',
  );

  static const List<_OrientationBulletItem>
  _chironDocumentsFeatures = <_OrientationBulletItem>[
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Chiron-checklist',
        en: 'Chiron checklist',
        fr: 'Checklist Chiron',
        es: 'Checklist Chiron',
      ),
      description: _Tr(
        nl: 'Voeg de nodige documenten toe voor Vlaamse taxi-compliance.',
        en: 'Add the required documents for Flemish taxi compliance.',
        fr:
            'Ajoutez les documents requis pour la conformité taxi '
            'flamande.',
        es:
            'Añade los documentos requeridos para cumplimiento taxi '
            'flamenco.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Backend audit',
        en: 'Backend audit',
        fr: 'Audit backend',
        es: 'Auditoría backend',
      ),
      description: _Tr(
        nl:
            'Elke rit wordt geregistreerd met status, betaling, methode, '
            'bron en provider.',
        en:
            'Every ride is logged with status, payment, method, source and '
            'provider.',
        fr:
            'Chaque course garde statut, paiement, méthode, source et '
            'provider.',
        es: 'Cada viaje guarda estado, pago, método, origen y proveedor.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Niet verwijderbaar',
        en: 'Immutable history',
        fr: 'Historique protégé',
        es: 'Historial protegido',
      ),
      description: _Tr(
        nl:
            'Compliance-events blijven bewaard als betrouwbare '
            'auditgeschiedenis.',
        en: 'Compliance events remain stored as reliable audit history.',
        fr:
            'Les événements de conformité restent conservés comme preuve '
            'fiable.',
        es:
            'Los eventos de cumplimiento quedan guardados como historial '
            'fiable.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Lokaal rittenregister',
        en: 'Local ride register',
        fr: 'Registre local',
        es: 'Registro local',
      ),
      description: _Tr(
        nl:
            'Bekijk ritten per chauffeur, voertuig, datum, boekingscode en '
            'betaling.',
        en: 'Review rides by driver, vehicle, date, booking code and payment.',
        fr:
            'Consultez les courses par chauffeur, véhicule, date, code et '
            'paiement.',
        es:
            'Consulta viajes por conductor, vehículo, fecha, código y '
            'pago.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Ritbon & delen',
        en: 'Receipt & sharing',
        fr: 'Reçu & partage',
        es: 'Recibo y envío',
      ),
      description: _Tr(
        nl: 'Bekijk de ritbon-PDF en deel die met klant of overheid.',
        en: 'View the PDF receipt and share it with the customer or authority.',
        fr: 'Consultez le PDF et partagez-le avec client ou autorité.',
        es: 'Consulta el PDF y compártelo con cliente o autoridad.',
      ),
    ),
  ];

  static const _Tr _chironDocumentsFooter = _Tr(
    nl: 'Voor controle, administratie en vertrouwen',
    en: 'Built for inspections, admin and trust',
    fr: 'Pour contrôles, administration et confiance',
    es: 'Para inspecciones, administración y confianza',
  );

  // ---------------------------------------------------------------
  // Card 6 (slide 7) — Drivers & documents. Bespoke tablet hero:
  // localised title + intro plus a responsive framed feature panel
  // of stacked gold-dot mini-cards, overlaid on the baked-in driver
  // management artwork in measured safe zones.
  // ---------------------------------------------------------------

  static const _Tr _driverManagementTitle = _Tr(
    nl: 'Chauffeurs & documenten',
    en: 'Drivers & documents',
    fr: 'Chauffeurs & documents',
    es: 'Conductores y documentos',
  );

  static const _Tr _driverManagementIntro = _Tr(
    nl:
        'Beheer chauffeurs, documenten, codes, voertuigkoppelingen en '
        'beschikbaarheid vanuit één centrale cockpit.',
    en:
        'Manage drivers, documents, codes, vehicle links and availability '
        'from one central cockpit.',
    fr:
        'Gérez chauffeurs, documents, codes, liens véhicules et disponibilité '
        'depuis un cockpit central.',
    es:
        'Gestiona conductores, documentos, códigos, vehículos y disponibilidad '
        'desde un cockpit central.',
  );

  static const List<_OrientationBulletItem>
  _driverManagementFeatures = <_OrientationBulletItem>[
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Chauffeurprofielen',
        en: 'Driver profiles',
        fr: 'Profils chauffeur',
        es: 'Perfiles de conductor',
      ),
      description: _Tr(
        nl: 'Beheer telefoon, status, voertuigkoppeling en chauffeursfoto.',
        en: 'Manage phone, status, vehicle link and driver photo.',
        fr: 'Gérez téléphone, statut, véhicule lié et photo chauffeur.',
        es: 'Gestiona teléfono, estado, vehículo vinculado y foto del conductor.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Documentcontrole',
        en: 'Document control',
        fr: 'Contrôle documents',
        es: 'Control documental',
      ),
      description: _Tr(
        nl:
            'Volg rijbewijs, bestuurderspas, medische keuringen en '
            'vergunningen op.',
        en: 'Track licence, driver pass, medical checks and permits.',
        fr:
            'Suivez permis, carte chauffeur, visites médicales et '
            'autorisations.',
        es: 'Sigue licencia, tarjeta, revisión médica y permisos.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Codes & QR-koppeling',
        en: 'Codes & QR pairing',
        fr: 'Codes & QR',
        es: 'Códigos y QR',
      ),
      description: _Tr(
        nl:
            'Genereer chauffeurscodes en tijdelijke koppel-QR’s voor '
            'nieuwe toestellen.',
        en:
            'Generate driver codes and temporary pairing QR codes for '
            'new devices.',
        fr:
            'Générez codes chauffeur et QR temporaires pour nouveaux '
            'appareils.',
        es:
            'Genera códigos de conductor y QR temporales para nuevos '
            'dispositivos.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Status & beschikbaarheid',
        en: 'Status & availability',
        fr: 'Statut & disponibilité',
        es: 'Estado y disponibilidad',
      ),
      description: _Tr(
        nl:
            'Zie actieve, gepauzeerde en beschikbare chauffeurs in één '
            'overzicht.',
        en: 'See active, paused and available drivers at a glance.',
        fr:
            'Voyez chauffeurs actifs, en pause et disponibles d’un coup '
            'd’œil.',
        es:
            'Ve conductores activos, en pausa y disponibles de un '
            'vistazo.',
      ),
    ),
  ];

  // ---------------------------------------------------------------
  // Card 9 — Region Radar. Uses the existing card7 artwork because
  // this is the flow step immediately after Chiron.
  // ---------------------------------------------------------------

  static const _Tr _regionRadarTitle = _Tr(
    nl: 'Regioradar',
    en: 'Region Radar',
    fr: 'Radar régional',
    es: 'Radar regional',
  );

  static const _Tr _regionRadarIntro = _Tr(
    nl:
        'Zie waar potentiële klanten actief zijn, waar vraag groeit en '
        'stuur je bedrijf gerichter vooruit.',
    en:
        'See where potential customers are active, where demand grows and '
        'move your business forward with focus.',
    fr:
        'Voyez où les clients potentiels sont actifs, où la demande '
        'augmente et développez votre activité avec précision.',
    es:
        'Vea dónde hay clientes potenciales activos, dónde crece la '
        'demanda e impulse su negocio con enfoque.',
  );

  static const _Tr _regionRadarExplanationEyebrow = _Tr(
    nl: 'REGIONALE VRAAGINTELLIGENTIE',
    en: 'REGIONAL DEMAND INTELLIGENCE',
    fr: 'INTELLIGENCE RÉGIONALE DE LA DEMANDE',
    es: 'INTELIGENCIA REGIONAL DE DEMANDA',
  );

  static const _Tr _regionRadarExplanationHeading = _Tr(
    nl: 'Zet lokale signalen om in betere dekking.',
    en: 'Turn local signals into better coverage.',
    fr: 'Transformez les signaux locaux en meilleure couverture.',
    es: 'Convierta señales locales en mejor cobertura.',
  );

  static const _Tr _regionRadarExplanationIntro = _Tr(
    nl:
        'Region Radar helpt een taxibedrijf begrijpen waar potentiële '
        'klanten actief zijn, waar de vraag groeit en hoe ver het huidige '
        'servicegebied reikt.',
    en:
        'Region Radar helps a taxi company understand where potential '
        'customers are active, where demand is growing, and how far the '
        'current service radius reaches.',
    fr:
        'Region Radar aide une entreprise de taxi à comprendre où les '
        'clients potentiels sont actifs, où la demande augmente et '
        'jusqu’où s’étend la zone de service actuelle.',
    es:
        'Region Radar ayuda a una empresa de taxi a entender dónde hay '
        'clientes potenciales activos, dónde crece la demanda y hasta '
        'dónde llega la zona de servicio actual.',
  );

  static const List<_OrientationBulletItem> _regionRadarExplanationFeatures =
      <_OrientationBulletItem>[
        _OrientationBulletItem(
          title: _Tr(
            nl: 'Vraag in beeld',
            en: 'Demand insight',
            fr: 'Demande visible',
            es: 'Demanda visible',
          ),
          description: _Tr(
            nl:
                'Zie waar mensen taxi-service zoeken nog vóór die vraag '
                'zichtbaar wordt via boekingen.',
            en:
                'See where people are looking for taxi service before demand '
                'becomes visible through bookings.',
            fr:
                'Voyez où les personnes recherchent un service taxi avant '
                'que la demande ne devienne visible via les réservations.',
            es:
                'Vea dónde las personas buscan servicio de taxi antes de que '
                'esa demanda aparezca en las reservas.',
          ),
        ),
        _OrientationBulletItem(
          title: _Tr(
            nl: 'Slimmer servicegebied',
            en: 'Smarter coverage',
            fr: 'Couverture plus intelligente',
            es: 'Cobertura más inteligente',
          ),
          description: _Tr(
            nl:
                'Vergelijk interesse in de buurt, service-radius en '
                'groeizones in je werkgebied.',
            en:
                'Compare nearby interest, service radius and growth zones in '
                'your working area.',
            fr:
                'Comparez l’intérêt local, le rayon de service et les zones '
                'de croissance dans votre région.',
            es:
                'Compare interés cercano, radio de servicio y zonas de '
                'crecimiento en su área de trabajo.',
          ),
        ),
        _OrientationBulletItem(
          title: _Tr(
            nl: 'Gericht groeien',
            en: 'Grow with focus',
            fr: 'Croissance ciblée',
            es: 'Crecimiento enfocado',
          ),
          description: _Tr(
            nl:
                'Gebruik regiosignalen om te beslissen waar je adverteert, '
                'voertuigen inzet of lokale partners activeert.',
            en:
                'Use regional signals to decide where to advertise, add '
                'vehicles or activate local partners.',
            fr:
                'Utilisez les signaux régionaux pour décider où communiquer, '
                'ajouter des véhicules ou activer des partenaires locaux.',
            es:
                'Use señales regionales para decidir dónde anunciarse, '
                'añadir vehículos o activar socios locales.',
          ),
        ),
      ];

  static const _Tr _regionRadarExplanationClosing = _Tr(
    nl: 'Minder gokken. Betere dekking. Gerichter groeien.',
    en: 'Less guesswork. Better coverage. More focused growth.',
    fr: 'Moins d’intuition. Plus de couverture. Une croissance plus ciblée.',
    es: 'Menos suposiciones. Mejor cobertura. Crecimiento más enfocado.',
  );

  // ---------------------------------------------------------------
  // Card 10 — Public booking link / Scan to Book.
  // ---------------------------------------------------------------

  static const _Tr _publicBookingLinkTitle = _Tr(
    nl: 'Publieke boekingslink',
    en: 'Public booking link',
    fr: 'Lien de réservation public',
    es: 'Enlace público de reserva',
  );

  static const _Tr _publicBookingLinkIntro = _Tr(
    nl:
        'Laat klanten rechtstreeks boeken via QR-code, link of je '
        'publieke partnerprofiel.',
    en:
        'Let customers book directly through a QR code, link or public '
        'partner profile.',
    fr:
        'Permettez aux clients de réserver via QR code, lien ou profil '
        'partenaire public.',
    es:
        'Permita que los clientes reserven mediante QR, enlace o perfil '
        'público de socio.',
  );

  static const _Tr _publicBookingLinkExplanationEyebrow = _Tr(
    nl: 'DIRECT BOEKEN',
    en: 'DIRECT BOOKING',
    fr: 'RÉSERVATION DIRECTE',
    es: 'RESERVA DIRECTA',
  );

  static const _Tr _publicBookingLinkExplanationHeading = _Tr(
    nl: 'Maak boeken eenvoudig voor elke klant.',
    en: 'Make booking easy for every customer.',
    fr: 'Simplifiez la réservation pour chaque client.',
    es: 'Haga que reservar sea fácil para cada cliente.',
  );

  static const _Tr _publicBookingLinkExplanationIntro = _Tr(
    nl:
        'Deel één publieke boekinglink of QR-code en laat klanten meteen '
        'een rit aanvragen zonder extra uitleg.',
    en:
        'Share one public booking link or QR code and let customers '
        'request a ride instantly.',
    fr:
        'Partagez un lien public ou un QR code et laissez les clients '
        'demander une course immédiatement.',
    es:
        'Comparta un enlace público o código QR y permita que los '
        'clientes pidan un viaje al instante.',
  );

  static const List<_OrientationBulletItem>
  _publicBookingLinkExplanationFeatures = <_OrientationBulletItem>[
    _OrientationBulletItem(
      title: _Tr(
        nl: 'QR & link delen',
        en: 'Share QR & link',
        fr: 'Partager QR & lien',
        es: 'Compartir QR y enlace',
      ),
      description: _Tr(
        nl: 'Plaats je QR-code op kaartjes, balie, website of voertuig.',
        en: 'Use your QR code on cards, counters, websites or vehicles.',
        fr:
            'Utilisez le QR code sur cartes, comptoirs, site web ou '
            'véhicule.',
        es: 'Use el QR en tarjetas, mostradores, web o vehículo.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Sneller reserveren',
        en: 'Faster reservations',
        fr: 'Réservation plus rapide',
        es: 'Reservas más rápidas',
      ),
      description: _Tr(
        nl:
            'Klanten openen direct je boekingsflow en vullen hun '
            'ritgegevens in.',
        en:
            'Customers open your booking flow and enter their ride '
            'details directly.',
        fr: 'Les clients ouvrent directement votre flux de réservation.',
        es:
            'Los clientes abren el flujo de reserva e introducen los '
            'datos del viaje.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Meer aanvragen',
        en: 'More requests',
        fr: 'Plus de demandes',
        es: 'Más solicitudes',
      ),
      description: _Tr(
        nl:
            'Verlaag de drempel en maak van elk contactmoment een '
            'boekingskans.',
        en:
            'Lower the barrier and turn every contact moment into a '
            'booking opportunity.',
        fr:
            'Réduisez les étapes et transformez chaque contact en '
            'opportunité de réservation.',
        es:
            'Reduzca pasos y convierta cada contacto en una oportunidad '
            'de reserva.',
      ),
    ),
  ];

  static const _Tr _publicBookingLinkExplanationClosing = _Tr(
    nl: 'Minder stappen. Meer boekingen. Professioneler contact.',
    en: 'Fewer steps. More bookings. A more professional first contact.',
    fr:
        'Moins d’étapes. Plus de réservations. Un contact plus '
        'professionnel.',
    es: 'Menos pasos. Más reservas. Un contacto más profesional.',
  );

  // ---------------------------------------------------------------
  // Card 11 — AI Dispatch.
  // ---------------------------------------------------------------

  static const _Tr _aiDispatchTitle = _Tr(
    nl: 'AI Dispatch',
    en: 'AI Dispatch',
    fr: 'AI Dispatch',
    es: 'AI Dispatch',
  );

  static const _Tr _aiDispatchSubtitle = _Tr(
    nl:
        'Laat slimme planning ritten, chauffeurs en voertuigen sneller '
        'samenbrengen.',
    en: 'Let smart planning connect rides, drivers and vehicles faster.',
    fr:
        'Reliez plus vite courses, chauffeurs et véhicules grâce à une '
        'planification intelligente.',
    es:
        'Conecte viajes, conductores y vehículos más rápido con '
        'planificación inteligente.',
  );

  static const _Tr _aiDispatchExplanationEyebrow = _Tr(
    nl: 'SLIMME RITPLANNING',
    en: 'SMART RIDE PLANNING',
    fr: 'PLANIFICATION INTELLIGENTE',
    es: 'PLANIFICACIÓN INTELIGENTE',
  );

  static const _Tr _aiDispatchExplanationHeading = _Tr(
    nl: 'Vind sneller de juiste chauffeur voor elke rit.',
    en: 'Find the right driver faster for every ride.',
    fr: 'Trouvez plus vite le bon chauffeur pour chaque course.',
    es: 'Encuentre antes el conductor adecuado para cada viaje.',
  );

  static const _Tr _aiDispatchExplanationIntro = _Tr(
    nl:
        'AI Dispatch helpt ritaanvragen, beschikbaarheid, afstand en '
        'voertuigcapaciteit samen bekijken zodat je minder handmatig '
        'hoeft te puzzelen.',
    en:
        'AI Dispatch helps compare ride requests, availability, distance '
        'and vehicle capacity so you spend less time planning manually.',
    fr:
        'AI Dispatch aide à comparer demandes, disponibilités, distances '
        'et capacité véhicule pour réduire la planification manuelle.',
    es:
        'AI Dispatch ayuda a comparar solicitudes, disponibilidad, '
        'distancia y capacidad del vehículo para reducir la planificación '
        'manual.',
  );

  static const List<_OrientationBulletItem>
  _aiDispatchExplanationFeatures = <_OrientationBulletItem>[
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Slimme toewijzing',
        en: 'Smart assignment',
        fr: 'Attribution intelligente',
        es: 'Asignación inteligente',
      ),
      description: _Tr(
        nl:
            'Combineer locatie, beschikbaarheid en voertuigcapaciteit bij '
            'elke nieuwe rit.',
        en:
            'Combine location, availability and vehicle capacity for every '
            'new ride.',
        fr:
            'Combinez position, disponibilité et capacité véhicule pour '
            'chaque nouvelle course.',
        es:
            'Combine ubicación, disponibilidad y capacidad del vehículo para '
            'cada nuevo viaje.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Minder wachttijd',
        en: 'Less waiting time',
        fr: 'Moins d’attente',
        es: 'Menos espera',
      ),
      description: _Tr(
        nl:
            'Zie sneller welke chauffeur of wagen het best past bij de '
            'aanvraag.',
        en: 'See faster which driver or vehicle fits the request best.',
        fr:
            'Voyez plus vite quel chauffeur ou véhicule correspond le mieux '
            'à la demande.',
        es:
            'Vea antes qué conductor o vehículo encaja mejor con la '
            'solicitud.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Live cockpit',
        en: 'Live cockpit',
        fr: 'Cockpit en direct',
        es: 'Cockpit en vivo',
      ),
      description: _Tr(
        nl:
            'Volg actieve ritten, drukte en planning vanuit één centrale '
            'cockpit.',
        en:
            'Track active rides, demand and planning from one central '
            'cockpit.',
        fr:
            'Suivez courses actives, demande et planning depuis un cockpit '
            'central.',
        es:
            'Siga viajes activos, demanda y planificación desde un cockpit '
            'central.',
      ),
    ),
  ];

  static const _Tr _aiDispatchExplanationClosing = _Tr(
    nl: 'Minder puzzelen. Sneller plannen. Meer controle.',
    en: 'Less manual work. Faster planning. More control.',
    fr: 'Moins de travail manuel. Plus vite planifié. Plus de contrôle.',
    es: 'Menos trabajo manual. Planificación más rápida. Más control.',
  );

  // ---------------------------------------------------------------
  // Card 12 — Driver View / Chauffeurcockpit.
  // ---------------------------------------------------------------

  static const _Tr _driverViewTitle = _Tr(
    nl: 'Chauffeurcockpit',
    en: 'Driver cockpit',
    fr: 'Cockpit chauffeur',
    es: 'Cockpit del conductor',
  );

  static const _Tr _driverViewSubtitle = _Tr(
    nl:
        'Geef chauffeurs één duidelijke werkplek voor ritten, navigatie, '
        'documenten en snelle acties.',
    en:
        'Give drivers one clear workspace for rides, navigation, documents '
        'and quick actions.',
    fr:
        'Offrez aux chauffeurs un espace clair pour courses, navigation, '
        'documents et actions rapides.',
    es:
        'Dé a los conductores un espacio claro para viajes, navegación, '
        'documentos y acciones rápidas.',
  );

  static const _Tr _driverViewExplanationEyebrow = _Tr(
    nl: 'CHAUFFEURWERKPLEK',
    en: 'DRIVER WORKSPACE',
    fr: 'ESPACE CHAUFFEUR',
    es: 'ESPACIO DEL CONDUCTOR',
  );

  static const _Tr _driverViewExplanationHeading = _Tr(
    nl: 'Alles klaar voor elke rit.',
    en: 'Everything ready for every ride.',
    fr: 'Tout est prêt pour chaque course.',
    es: 'Todo listo para cada viaje.',
  );

  static const _Tr _driverViewExplanationIntro = _Tr(
    nl:
        'De chauffeur ziet planning, volgende rit, route-info en dagelijkse '
        'tools in één overzichtelijke cockpit.',
    en:
        'The driver sees planning, next ride, route information and daily '
        'tools in one clear cockpit.',
    fr:
        'Le chauffeur voit planning, prochaine course, itinéraire et outils '
        'quotidiens dans un cockpit clair.',
    es:
        'El conductor ve planificación, próximo viaje, ruta y herramientas '
        'diarias en un cockpit claro.',
  );

  static const List<_OrientationBulletItem>
  _driverViewExplanationFeatures = <_OrientationBulletItem>[
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Live ritinformatie',
        en: 'Live ride info',
        fr: 'Infos course en direct',
        es: 'Información en vivo',
      ),
      description: _Tr(
        nl: 'Bekijk volgende rit, status, klantinfo en route in één scherm.',
        en:
            'View next ride, status, customer details and route in one '
            'screen.',
        fr:
            'Consultez prochaine course, statut, client et itinéraire sur '
            'un seul écran.',
        es:
            'Vea próximo viaje, estado, cliente y ruta en una sola '
            'pantalla.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Direct navigeren',
        en: 'Direct navigation',
        fr: 'Navigation directe',
        es: 'Navegación directa',
      ),
      description: _Tr(
        nl:
            'Open navigatie of ritdetails zonder te zoeken tijdens het '
            'werk.',
        en: 'Open navigation or ride details without searching during work.',
        fr:
            'Ouvrez navigation ou détails de course sans chercher pendant '
            'le service.',
        es:
            'Abra navegación o detalles del viaje sin buscar durante el '
            'servicio.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Snelle tools',
        en: 'Quick tools',
        fr: 'Outils rapides',
        es: 'Herramientas rápidas',
      ),
      description: _Tr(
        nl:
            'Straatrit, calculator, bonnetjes, documenten en historiek '
            'binnen handbereik.',
        en:
            'Street ride, calculator, receipts, documents and history '
            'within reach.',
        fr:
            'Course directe, calculateur, reçus, documents et historique à '
            'portée de main.',
        es:
            'Viaje directo, calculadora, recibos, documentos e historial '
            'al alcance.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Meer rust onderweg',
        en: 'More focus on the road',
        fr: 'Plus de calme en route',
        es: 'Más calma en ruta',
      ),
      description: _Tr(
        nl: 'Minder schakelen tussen apps, meer focus op klant en rit.',
        en:
            'Less switching between apps, more focus on the customer and '
            'ride.',
        fr:
            'Moins de changements d\u2019apps, plus de focus sur le client '
            'et la course.',
        es: 'Menos cambios entre apps, más foco en el cliente y el viaje.',
      ),
    ),
  ];

  static const _Tr _driverViewExplanationClosing = _Tr(
    nl: 'Eén cockpit. Minder zoeken. Meer controle onderweg.',
    en: 'One cockpit. Less searching. More control on the road.',
    fr: 'Un cockpit. Moins de recherche. Plus de contrôle en route.',
    es: 'Un cockpit. Menos búsqueda. Más control en ruta.',
  );

  // ---------------------------------------------------------------
  // Card 13 — Calculator & ride pricing.
  // ---------------------------------------------------------------

  static const _Tr _calculatorTitle = _Tr(
    nl: 'Calculator & ritprijzen',
    en: 'Calculator & ride pricing',
    fr: 'Calculateur & prix de course',
    es: 'Calculadora y precios',
  );

  static const _Tr _calculatorSubtitle = _Tr(
    nl:
        'Bereken taxi-, luchthaven- en vaste ritprijzen vanuit één '
        'professionele flow.',
    en:
        'Calculate taxi, airport and fixed ride prices from one '
        'professional flow.',
    fr:
        'Calculez les prix taxi, aéroport et forfaitaires dans un flux '
        'professionnel.',
    es:
        'Calcule precios de taxi, aeropuerto y tarifas fijas desde un '
        'flujo profesional.',
  );

  static const _Tr _calculatorExplanationEyebrow = _Tr(
    nl: 'RITPRIJS & BOEKING',
    en: 'FARE CALCULATION',
    fr: 'PRIX & RÉSERVATION',
    es: 'PRECIO Y RESERVA',
  );

  static const _Tr _calculatorExplanationHeading = _Tr(
    nl: 'Van prijsberekening naar boeking in één stap.',
    en: 'From fare calculation to booking in one step.',
    fr: 'Du calcul du prix à la réservation en une étape.',
    es: 'Del cálculo del precio a la reserva en un paso.',
  );

  static const _Tr _calculatorExplanationIntro = _Tr(
    nl:
        'Fluxidi helpt duidelijke ritprijzen maken, zodat klanten sneller '
        'een correcte offerte en boekingsflow krijgen.',
    en:
        'Fluxidi helps build clear ride prices, so customers get a correct '
        'quote and booking flow faster.',
    fr:
        'Fluxidi aide à créer des prix clairs, pour donner plus vite un '
        'devis correct et un parcours de réservation.',
    es:
        'Fluxidi ayuda a crear precios claros, para que el cliente reciba '
        'antes una oferta correcta y pueda reservar.',
  );

  static const List<_OrientationBulletItem>
  _calculatorExplanationFeatures = <_OrientationBulletItem>[
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Taxi & luchthaven',
        en: 'Taxi & airport',
        fr: 'Taxi & aéroport',
        es: 'Taxi y aeropuerto',
      ),
      description: _Tr(
        nl:
            'Bereken gewone ritten, luchthaventransfers en terugritten met '
            'duidelijke invoer.',
        en:
            'Calculate regular rides, airport transfers and return flows '
            'with clear input.',
        fr:
            'Calculez courses classiques, transferts aéroport et retours '
            'avec une saisie claire.',
        es:
            'Calcule viajes normales, traslados al aeropuerto y vueltas '
            'con datos claros.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Slimme prijslogica',
        en: 'Smart pricing',
        fr: 'Prix intelligents',
        es: 'Precio inteligente',
      ),
      description: _Tr(
        nl:
            'Neem afstand, tijd, service, voertuigtype, wachttijd en '
            'extra\u2019s mee.',
        en:
            'Include distance, time, service, vehicle type, waiting time '
            'and extras.',
        fr:
            'Incluez distance, durée, service, véhicule, attente et '
            'options.',
        es:
            'Incluya distancia, tiempo, servicio, vehículo, espera y '
            'extras.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Vaste tarieven',
        en: 'Fixed rates',
        fr: 'Tarifs fixes',
        es: 'Tarifas fijas',
      ),
      description: _Tr(
        nl:
            'Gebruik bedrijfsinstellingen en vaste prijzen voor voorspelbare '
            'offertes.',
        en: 'Use company settings and fixed prices for predictable quotes.',
        fr:
            'Utilisez les réglages d\u2019entreprise et les forfaits pour '
            'des devis prévisibles.',
        es:
            'Use ajustes de empresa y precios fijos para ofertas '
            'previsibles.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Klaar om te boeken',
        en: 'Ready to book',
        fr: 'Prêt à réserver',
        es: 'Listo para reservar',
      ),
      description: _Tr(
        nl:
            'Zet een berekende prijs direct om naar een ritaanvraag of '
            'boeking.',
        en: 'Turn a calculated fare directly into a ride request or booking.',
        fr:
            'Transformez le prix calculé en demande de course ou '
            'réservation.',
        es:
            'Convierta el precio calculado directamente en solicitud o '
            'reserva.',
      ),
    ),
  ];

  static const _Tr _calculatorExplanationClosing = _Tr(
    nl: 'Minder manueel werk. Duidelijke prijzen. Sneller boeken.',
    en: 'Less manual work. Clear prices. Faster bookings.',
    fr: 'Moins de manuel. Des prix clairs. Des réservations plus rapides.',
    es: 'Menos trabajo manual. Precios claros. Reservas más rápidas.',
  );

  // ---------------------------------------------------------------
  // Card 14 — Ride receipts, history & documents (driver cockpit).
  // ---------------------------------------------------------------

  static const _Tr _driverReceiptsTitle = _Tr(
    nl: 'Ritbonnen, historiek & documenten',
    en: 'Receipts, history & documents',
    fr: 'Reçus, historique & documents',
    es: 'Recibos, historial y documentos',
  );

  static const _Tr _driverReceiptsSubtitle = _Tr(
    nl:
        'Geef chauffeurs één duidelijke plek voor ritbonnen, vorige ritten '
        'en documenten.',
    en:
        'Give drivers one clear place for receipts, previous rides and '
        'documents.',
    fr:
        'Donnez aux chauffeurs un espace clair pour reçus, courses passées '
        'et documents.',
    es:
        'Dé a los conductores un lugar claro para recibos, viajes '
        'anteriores y documentos.',
  );

  static const _Tr _driverReceiptsExplanationEyebrow = _Tr(
    nl: 'CHAUFFEURADMINISTRATIE',
    en: 'DRIVER ADMINISTRATION',
    fr: 'ADMINISTRATION CHAUFFEUR',
    es: 'ADMINISTRACIÓN DEL CONDUCTOR',
  );

  static const _Tr _driverReceiptsExplanationHeading = _Tr(
    nl: 'Alles terugvinden zonder zoeken.',
    en: 'Find everything without searching.',
    fr: 'Tout retrouver sans chercher.',
    es: 'Encuentre todo sin buscar.',
  );

  static const _Tr _driverReceiptsExplanationIntro = _Tr(
    nl:
        'De chauffeur opent ritbonnen, historiek en documenten rechtstreeks '
        'vanuit zijn cockpit.',
    en:
        'The driver opens receipts, history and documents directly from the '
        'cockpit.',
    fr:
        'Le chauffeur ouvre reçus, historique et documents directement '
        'depuis son cockpit.',
    es:
        'El conductor abre recibos, historial y documentos directamente '
        'desde su cockpit.',
  );

  static const List<_OrientationBulletItem> _driverReceiptsExplanationFeatures =
      <_OrientationBulletItem>[
        _OrientationBulletItem(
          title: _Tr(
            nl: 'Ritbonnen bij de hand',
            en: 'Receipts at hand',
            fr: 'Reçus à portée de main',
            es: 'Recibos a mano',
          ),
          description: _Tr(
            nl: 'Bekijk bedragen, ritdetails en bonnen per uitgevoerde rit.',
            en: 'View amounts, ride details and receipts per completed ride.',
            fr: 'Consultez montants, détails et reçus par course terminée.',
            es: 'Consulte importes, detalles y recibos por viaje realizado.',
          ),
        ),
        _OrientationBulletItem(
          title: _Tr(
            nl: 'Historiek per chauffeur',
            en: 'Driver ride history',
            fr: 'Historique chauffeur',
            es: 'Historial del conductor',
          ),
          description: _Tr(
            nl: 'Controleer vorige ritten, tijden, routes en betalingen.',
            en: 'Check previous rides, times, routes and payments.',
            fr: 'Vérifiez courses passées, horaires, trajets et paiements.',
            es: 'Revise viajes anteriores, horarios, rutas y pagos.',
          ),
        ),
        _OrientationBulletItem(
          title: _Tr(
            nl: 'Documenten overzichtelijk',
            en: 'Documents in order',
            fr: 'Documents organisés',
            es: 'Documentos ordenados',
          ),
          description: _Tr(
            nl:
                'Rijbewijs, vergunningen en chauffeursdocumenten blijven '
                'bereikbaar.',
            en: 'Licence, permits and driver documents stay accessible.',
            fr:
                'Permis, autorisations et documents chauffeur restent '
                'accessibles.',
            es:
                'Licencia, permisos y documentos del conductor siempre '
                'accesibles.',
          ),
        ),
      ];

  static const _Tr _driverReceiptsExplanationClosing = _Tr(
    nl: 'Minder zoeken. Sneller opvolgen. Meer rust onderweg.',
    en: 'Less searching. Faster follow-up. More calm on the road.',
    fr: 'Moins de recherche. Suivi plus rapide. Plus de calme en route.',
    es: 'Menos búsqueda. Seguimiento más rápido. Más calma en ruta.',
  );

  // ---------------------------------------------------------------
  // Card 15 — Activate customers / customer app adoption.
  // ---------------------------------------------------------------

  static const _Tr _activateCustomersTitle = _Tr(
    nl: 'Laat klanten de app gebruiken.',
    en: 'Let customers use the app.',
    fr: 'Invitez vos clients à utiliser l’app.',
    es: 'Haz que tus clientes usen la app.',
  );

  static const _Tr _activateCustomersIntro = _Tr(
    nl:
        'Moedig klanten aan om Fluxidi te downloaden. Zo wordt je service '
        'niet alleen geboekt, maar ook opnieuw gevonden.',
    en:
        'Encourage customers to download Fluxidi. Your service becomes easier '
        'to book, rediscover and reuse.',
    fr:
        'Encouragez vos clients à télécharger Fluxidi. Votre service devient '
        'plus facile à réserver, retrouver et réutiliser.',
    es:
        'Anima a tus clientes a descargar Fluxidi. Tu servicio será más fácil '
        'de reservar, reencontrar y volver a usar.',
  );

  static const _Tr _activateCustomersEyebrow = _Tr(
    nl: 'KLANTEN ACTIVEREN',
    en: 'ACTIVATE CUSTOMERS',
    fr: 'ACTIVER LES CLIENTS',
    es: 'ACTIVAR CLIENTES',
  );

  static const List<_OrientationBulletItem>
  _activateCustomersBenefits = <_OrientationBulletItem>[
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Meer dan taxi',
        en: 'More than taxi',
        fr: 'Plus qu’un taxi',
        es: 'Más que taxi',
      ),
      description: _Tr(
        nl:
            'Ritten, luchthavenvervoer, hotels, events en '
            'business-mobiliteit in één klantapp.',
        en:
            'Rides, airport transfers, hotels, events and business '
            'mobility in one customer app.',
        fr:
            'Courses, aéroports, hôtels, événements et mobilité business '
            'dans une seule app client.',
        es:
            'Viajes, aeropuertos, hoteles, eventos y movilidad business '
            'en una sola app cliente.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Jouw klantrelatie',
        en: 'Your customer relation',
        fr: 'Votre relation client',
        es: 'Tu relación con el cliente',
      ),
      description: _Tr(
        nl: 'Klanten ervaren jouw service, niet zomaar een anoniem platform.',
        en:
            'Customers experience your service, not just an anonymous '
            'platform.',
        fr:
            'Les clients vivent votre service, pas une plateforme '
            'anonyme.',
        es:
            'Los clientes viven tu servicio, no solo una plataforma '
            'anónima.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Meer herhaalritten',
        en: 'More repeat rides',
        fr: 'Plus de trajets répétés',
        es: 'Más viajes repetidos',
      ),
      description: _Tr(
        nl:
            'Favorieten, ritgeschiedenis en snelle acties maken opnieuw '
            'boeken eenvoudiger.',
        en:
            'Favorites, ride history and quick actions make booking again '
            'easier.',
        fr:
            'Favoris, historique et actions rapides facilitent les '
            'nouvelles réservations.',
        es:
            'Favoritos, historial y acciones rápidas facilitan volver a '
            'reservar.',
      ),
    ),
    _OrientationBulletItem(
      title: _Tr(
        nl: 'Over grenzen heen',
        en: 'Across countries',
        fr: 'Au-delà des frontières',
        es: 'Entre países',
      ),
      description: _Tr(
        nl:
            'Groei mee in de landen waar Fluxidi actief wordt en bereik '
            'klanten onderweg.',
        en:
            'Grow with the countries where Fluxidi becomes active and '
            'reach customers on the move.',
        fr:
            'Grandissez avec les pays où Fluxidi devient actif et touchez '
            'les clients en déplacement.',
        es:
            'Crece con los países donde Fluxidi esté activo y llega a '
            'clientes en movimiento.',
      ),
    ),
  ];

  static const _Tr _activateCustomersClosing = _Tr(
    nl: 'Jouw service. Meer mobiliteit. Meer terugkerende klanten.',
    en: 'Your service. More mobility. More returning customers.',
    fr: 'Votre service. Plus de mobilité. Plus de clients qui reviennent.',
    es: 'Tu servicio. Más movilidad. Más clientes que vuelven.',
  );

  static const Map<AppLanguage, String> _brochureAssetByLanguage =
      <AppLanguage, String>{
        AppLanguage.nl:
            'assets/fluxidi/brochures/fluxidi_platform_brochure_nl_final.pdf',
        AppLanguage.en:
            'assets/fluxidi/brochures/fluxidi_platform_brochure_en_final.pdf',
        AppLanguage.fr:
            'assets/fluxidi/brochures/fluxidi_platform_brochure_fr_final.pdf',
        AppLanguage.es:
            'assets/fluxidi/brochures/fluxidi_platform_brochure_es_final.pdf',
      };

  static const _Tr _brochureCtaLabel = _Tr(
    nl: 'Bewaar of deel Fluxidi brochure',
    en: 'Save or share Fluxidi brochure',
    fr: 'Enregistrer ou partager la brochure Fluxidi',
    es: 'Guardar o compartir folleto Fluxidi',
  );

  static const _Tr _brochureCtaHelper = _Tr(
    nl: 'Bewaar of deel het volledige platformoverzicht.',
    en: 'Save or share the full platform overview.',
    fr: 'Enregistrez ou partagez la présentation complète.',
    es: 'Guarde o comparta la presentación completa.',
  );

  static const _Tr _brochureShareError = _Tr(
    nl: 'De brochure kon niet worden geladen. Probeer het opnieuw.',
    en: 'Could not load the brochure. Please try again.',
    fr: 'Impossible de charger la brochure. Veuillez réessayer.',
    es: 'No se pudo cargar el folleto. Inténtelo de nuevo.',
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
      layout: _OrientationCardLayout.settingsProfileRich,
      icon: Icons.settings_outlined,
      title: _settingsProfileTopTitle,
      body: _settingsProfileTopIntro,
      portraitAsset: _settingsProfileTabletPortraitAsset,
      landscapeAsset: _settingsProfileTabletLandscapeAsset,
    ),
    // 5 — Themes & branding (interactive Theme Showroom). Foreground
    // interactive card (NOT a full-viewport hero) so the in-preview
    // left/right arrows receive taps. Stays at index 4.
    _OrientationCardData(
      id: 'themes_branding',
      layout: _OrientationCardLayout.themesBrandingRich,
      icon: Icons.palette_outlined,
      title: _themesTitle,
      body: _themesIntro,
    ),
    // 6 — Vehicles & fleet management (bespoke PNG + title/intro overlay
    // hero on tablet). title/body feed both the bespoke overlay and the
    // phone icon-card fallback.
    _OrientationCardData(
      id: 'vehicles_fleet_management',
      layout: _OrientationCardLayout.vehiclesFleet,
      icon: Icons.directions_car_outlined,
      title: _card4VehiclesFleetTitle,
      body: _card4VehiclesFleetIntro,
      portraitAsset: _card4VehiclesFleetTabletPortraitAsset,
      landscapeAsset: _card4VehiclesFleetTabletLandscapeAsset,
    ),
    // 7 — Drivers & documents (bespoke PNG + measured text overlay on
    // tablet). The card6 artwork carries the driver management
    // screenshots; Flutter overlays title/intro and a framed feature
    // panel in measured safe zones.
    _OrientationCardData(
      id: 'driver_management',
      layout: _OrientationCardLayout.driverManagementRich,
      icon: Icons.people_outline,
      title: _driverManagementTitle,
      body: _driverManagementIntro,
      portraitAsset: _card6DriverManagementTabletPortraitAsset,
      landscapeAsset: _card6DriverManagementTabletLandscapeAsset,
    ),
    // 8 — Chiron & ride register (bespoke PNG + measured text overlay
    // on tablet). The card5 artwork contains the receipt/audit/local
    // ride register visuals.
    _OrientationCardData(
      id: 'chiron_documents',
      layout: _OrientationCardLayout.chironDocumentsRich,
      icon: Icons.verified_user_outlined,
      title: _chironDocumentsTitle,
      body: _chironDocumentsIntro,
      portraitAsset: _card5ChironDocumentsTabletPortraitAsset,
      landscapeAsset: _card5ChironDocumentsTabletLandscapeAsset,
    ),
    // 9 — Demand radar / demand insight.
    _OrientationCardData(
      id: 'demand_radar',
      layout: _OrientationCardLayout.regionRadarRich,
      icon: Icons.radar,
      title: _regionRadarTitle,
      body: _regionRadarIntro,
      portraitAsset: _card7RegionRadarTabletPortraitAsset,
      landscapeAsset: _card7RegionRadarTabletLandscapeAsset,
    ),
    // 10 — Public booking link.
    _OrientationCardData(
      id: 'public_booking_link',
      layout: _OrientationCardLayout.publicBookingLinkRich,
      icon: Icons.link_outlined,
      title: _publicBookingLinkTitle,
      body: _publicBookingLinkIntro,
      portraitAsset: _card9PublicBookingLinkTabletPortraitAsset,
      landscapeAsset: _card9PublicBookingLinkTabletLandscapeAsset,
    ),
    // 11 — AI Dispatch (bespoke PNG + measured premium panels on tablet).
    _OrientationCardData(
      id: 'ai_dispatch',
      layout: _OrientationCardLayout.aiDispatchRich,
      icon: Icons.auto_awesome_outlined,
      title: _aiDispatchTitle,
      body: _aiDispatchSubtitle,
      portraitAsset: _card10AiDispatchTabletPortraitAsset,
      landscapeAsset: _card10AiDispatchTabletLandscapeAsset,
    ),
    // 12 — Driver View / Chauffeurcockpit (bespoke PNG + measured panels).
    _OrientationCardData(
      id: 'driver_view',
      layout: _OrientationCardLayout.driverViewRich,
      icon: Icons.drive_eta_outlined,
      title: _driverViewTitle,
      body: _driverViewSubtitle,
      portraitAsset: _card8DriverViewTabletPortraitAsset,
      landscapeAsset: _card8DriverViewTabletLandscapeAsset,
    ),
    // 13 — Calculator & ride pricing (bespoke PNG + measured panels).
    _OrientationCardData(
      id: 'calculator_streetride',
      layout: _OrientationCardLayout.calculatorRich,
      icon: Icons.calculate_outlined,
      title: _calculatorTitle,
      body: _calculatorSubtitle,
      portraitAsset: _card11CalculatorTabletPortraitAsset,
      landscapeAsset: _card11CalculatorTabletLandscapeAsset,
    ),
    // 14 — Ride receipts, history & documents (bespoke PNG + measured
    // panels).
    _OrientationCardData(
      id: 'ride_receipts',
      layout: _OrientationCardLayout.driverReceiptsRich,
      icon: Icons.receipt_long_outlined,
      title: _driverReceiptsTitle,
      body: _driverReceiptsSubtitle,
      portraitAsset: _card12DriverReceiptsTabletPortraitAsset,
      landscapeAsset: _card12DriverReceiptsTabletLandscapeAsset,
    ),
    // 15 — Activate your customers / share your link.
    _OrientationCardData(
      id: 'activate_customers',
      layout: _OrientationCardLayout.activateCustomersRich,
      icon: Icons.campaign_outlined,
      title: _activateCustomersTitle,
      body: _activateCustomersIntro,
      portraitAsset: _card13ActivateCustomersTabletPortraitAsset,
      landscapeAsset: _card13ActivateCustomersTabletLandscapeAsset,
    ),
  ];

  @override
  void initState() {
    super.initState();
    debugPrint('[ORIENTATION_FLOW][OPEN] totalPages=${_orientationCards().length}');
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
      case AppLanguage.de:
        return tr.en;
    }
  }

  String _brochureAssetPathForCurrentLanguage() {
    return _brochureAssetByLanguage[appLanguageNotifier.value] ??
        _brochureAssetByLanguage[AppLanguage.en]!;
  }

  Future<void> _sharePlatformBrochure() async {
    if (!mounted) return;
    try {
      final String assetPath = _brochureAssetPathForCurrentLanguage();
      final ByteData byteData = await rootBundle.load(assetPath);
      final Uint8List bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      final Directory tempDir = await getTemporaryDirectory();
      final String fileName = assetPath.split('/').last;
      final File file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(<XFile>[
        XFile(file.path),
      ], text: _t(_brochureCtaHelper));
    } catch (error, stackTrace) {
      debugPrint(
        '[ORIENTATION_FLOW][BROCHURE_SHARE_FAIL] error=$error '
        'stack=$stackTrace',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_t(_brochureShareError))));
    }
  }

  Widget _buildBrochureDownloadCta({
    required bool compact,
    bool landscapeFullHero = false,
  }) {
    final bool veryCompact = compact || landscapeFullHero;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _sharePlatformBrochure,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: _gold.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _gold.withOpacity(0.42)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: veryCompact ? 12 : 14,
              vertical: veryCompact ? 10 : 12,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.picture_as_pdf_outlined,
                  color: _gold,
                  size: veryCompact ? 20 : 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        _t(_brochureCtaLabel),
                        maxLines: veryCompact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: veryCompact ? 13 : 14,
                          height: 1.15,
                        ),
                      ),
                      if (!veryCompact) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          _t(_brochureCtaHelper),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                            fontSize: 11.5,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.ios_share_outlined,
                  color: _gold.withOpacity(0.85),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Central accessor for the product-tour cards. Everything that
  /// needs the tour length or a specific card (page indicator,
  /// Previous / Next, final-page CTA, the PageView builder) reads
  /// through this so the flow stays driven by a single source of
  /// truth. Returns the const [_cards] list as-is today; kept as a
  /// method so a future dynamic/filtered tour can slot in without
  /// touching call sites.
  List<_OrientationCardData> _orientationCards() {
    if (companyShouldShowTaxiBookingQr()) return _cards;
    return _cards
        .where((card) => card.id != 'public_booking_link')
        .toList(growable: false);
  }

  /// Convenience: the card currently shown, derived from [_index].
  _OrientationCardData get _currentCard => _orientationCards()[_index];

  /// Shared localized bullet list for the Company Cockpit slide.
  List<_OrientationBulletItem> _companyCockpitItems() =>
      _companyCockpitBulletItems;

  void _logCurrentPage() {
    debugPrint(
      '[ORIENTATION_FLOW][PAGE] index=${_index + 1}/${_orientationCards().length} '
      'card=${_orientationCards()[_index].id}',
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
        isWelcome: _orientationCards()[next].layout == _OrientationCardLayout.welcome,
        isTabletPortrait: size.width < size.height && size.shortestSide >= 600,
        isTabletLandscape: size.width > size.height && size.shortestSide >= 600,
      );
    });
  }

  Future<void> _goNext() async {
    if (!mounted) return;
    if (_index >= _orientationCards().length - 1) {
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
      '[ORIENTATION_FLOW][SKIP] from_index=${_index + 1}/${_orientationCards().length} '
      'card=${_orientationCards()[_index].id}',
    );
    (widget.onSkip ?? widget.onFinish).call();
  }

  /// Card 5 Theme Showroom: select the previous preview (wraps to the
  /// last). Pure local state — never touches the orientation
  /// PageController, so it cannot interfere with Previous/Next.
  void _themeShowroomPrev() {
    if (!mounted) return;
    final int count = _themeShowroomItems.length;
    setState(() {
      _themeShowroomIndex = (_themeShowroomIndex - 1 + count) % count;
    });
  }

  /// Card 5 Theme Showroom: select the next preview (wraps to the
  /// first).
  void _themeShowroomNext() {
    if (!mounted) return;
    final int count = _themeShowroomItems.length;
    setState(() {
      _themeShowroomIndex = (_themeShowroomIndex + 1) % count;
    });
  }

  void _finish() {
    if (!mounted) return;
    debugPrint(
      '[ORIENTATION_FLOW][FINISH] '
      'last_index=${_index + 1}/${_orientationCards().length}',
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
        final bool isSettingsProfileCard =
            currentCard.layout == _OrientationCardLayout.settingsProfileRich;
        final bool isVehiclesFleetCard =
            currentCard.layout == _OrientationCardLayout.vehiclesFleet;
        final bool isDriverManagementCard =
            currentCard.layout == _OrientationCardLayout.driverManagementRich;
        final bool isChironDocumentsCard =
            currentCard.layout == _OrientationCardLayout.chironDocumentsRich;
        final bool isRegionRadarCard =
            currentCard.layout == _OrientationCardLayout.regionRadarRich;
        final bool isPublicBookingLinkCard =
            currentCard.layout == _OrientationCardLayout.publicBookingLinkRich;
        final bool isAiDispatchCard =
            currentCard.layout == _OrientationCardLayout.aiDispatchRich;
        final bool isDriverViewCard =
            currentCard.layout == _OrientationCardLayout.driverViewRich;
        final bool isCalculatorCard =
            currentCard.layout == _OrientationCardLayout.calculatorRich;
        final bool isDriverReceiptsCard =
            currentCard.layout == _OrientationCardLayout.driverReceiptsRich;
        final bool isActivateCustomersCard =
            currentCard.layout == _OrientationCardLayout.activateCustomersRich;
        // Card 5 Theme Showroom is composed entirely in Flutter (no
        // baked artwork), so it owns a pure-black premium canvas on
        // every form factor rather than the shared navy palette.
        final bool isThemesBrandingCard =
            currentCard.layout == _OrientationCardLayout.themesBrandingRich;
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
        final bool isSettingsProfileTabletHero =
            isSettingsProfileCard && (isTabletPortrait || isTabletLandscape);
        // Card 4 artwork is on a near-black canvas like Cards 2 & 3, so
        // it gets the same immersive [_heroBg] scaffold on tablet.
        final bool isVehiclesFleetTabletHero =
            isVehiclesFleetCard && (isTabletPortrait || isTabletLandscape);
        final bool isDriverManagementTabletHero =
            isDriverManagementCard && (isTabletPortrait || isTabletLandscape);
        final bool isChironDocumentsTabletHero =
            isChironDocumentsCard && (isTabletPortrait || isTabletLandscape);
        final bool isRegionRadarTabletHero =
            isRegionRadarCard && (isTabletPortrait || isTabletLandscape);
        final bool isPublicBookingLinkTabletHero =
            isPublicBookingLinkCard && (isTabletPortrait || isTabletLandscape);
        final bool isAiDispatchTabletHero =
            isAiDispatchCard && (isTabletPortrait || isTabletLandscape);
        final bool isDriverViewTabletHero =
            isDriverViewCard && (isTabletPortrait || isTabletLandscape);
        final bool isCalculatorTabletHero =
            isCalculatorCard && (isTabletPortrait || isTabletLandscape);
        final bool isDriverReceiptsTabletHero =
            isDriverReceiptsCard && (isTabletPortrait || isTabletLandscape);
        final bool isActivateCustomersTabletHero =
            isActivateCustomersCard && (isTabletPortrait || isTabletLandscape);
        final Color scaffoldBackground = isThemesBrandingCard
            ? const Color(0xFF000000)
            : (isWelcomeTabletHero ||
                  isCentralCockpitTabletPortraitHero ||
                  isCentralCockpitTabletLandscapeHero ||
                  isSubscriptionTabletHero ||
                  isSettingsProfileTabletHero ||
                  isVehiclesFleetTabletHero ||
                  isDriverManagementTabletHero ||
                  isChironDocumentsTabletHero ||
                  isRegionRadarTabletHero ||
                  isPublicBookingLinkTabletHero ||
                  isAiDispatchTabletHero ||
                  isDriverViewTabletHero ||
                  isCalculatorTabletHero ||
                  isDriverReceiptsTabletHero ||
                  isActivateCustomersTabletHero)
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
        final bool useSettingsProfilePortraitFullHero =
            isSettingsProfileCard && isTabletPortrait;
        final bool useSettingsProfileLandscapeFullHero =
            isSettingsProfileCard && isTabletLandscape;
        // Card 4 uses the same full-viewport hero approach as Cards 2 & 3:
        // a PNG background behind the Stack with a localised overlay,
        // while the PageView slot is short-circuited to a transparent box
        // so the chrome floats on top.
        final bool useVehiclesFleetPortraitFullHero =
            isVehiclesFleetCard && isTabletPortrait;
        final bool useVehiclesFleetLandscapeFullHero =
            isVehiclesFleetCard && isTabletLandscape;
        final bool useDriverManagementPortraitFullHero =
            isDriverManagementCard && isTabletPortrait;
        final bool useDriverManagementLandscapeFullHero =
            isDriverManagementCard && isTabletLandscape;
        final bool useChironDocumentsPortraitFullHero =
            isChironDocumentsCard && isTabletPortrait;
        final bool useChironDocumentsLandscapeFullHero =
            isChironDocumentsCard && isTabletLandscape;
        final bool useRegionRadarPortraitFullHero =
            isRegionRadarCard && isTabletPortrait;
        final bool useRegionRadarLandscapeFullHero =
            isRegionRadarCard && isTabletLandscape;
        final bool usePublicBookingLinkPortraitFullHero =
            isPublicBookingLinkCard && isTabletPortrait;
        final bool usePublicBookingLinkLandscapeFullHero =
            isPublicBookingLinkCard && isTabletLandscape;
        final bool useAiDispatchPortraitFullHero =
            isAiDispatchCard && isTabletPortrait;
        final bool useAiDispatchLandscapeFullHero =
            isAiDispatchCard && isTabletLandscape;
        final bool useDriverViewPortraitFullHero =
            isDriverViewCard && isTabletPortrait;
        final bool useDriverViewLandscapeFullHero =
            isDriverViewCard && isTabletLandscape;
        final bool useCalculatorPortraitFullHero =
            isCalculatorCard && isTabletPortrait;
        final bool useCalculatorLandscapeFullHero =
            isCalculatorCard && isTabletLandscape;
        final bool useDriverReceiptsPortraitFullHero =
            isDriverReceiptsCard && isTabletPortrait;
        final bool useDriverReceiptsLandscapeFullHero =
            isDriverReceiptsCard && isTabletLandscape;
        final bool useActivateCustomersPortraitFullHero =
            isActivateCustomersCard && isTabletPortrait;
        final bool useActivateCustomersLandscapeFullHero =
            isActivateCustomersCard && isTabletLandscape;

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
              if (useSettingsProfilePortraitFullHero)
                Positioned.fill(
                  child: _buildSettingsProfileTabletPortraitFullViewportHero(),
                ),
              if (useSettingsProfileLandscapeFullHero)
                Positioned.fill(
                  child: _buildSettingsProfileTabletLandscapeFullViewportHero(),
                ),
              if (useVehiclesFleetPortraitFullHero)
                Positioned.fill(
                  child: _buildVehiclesFleetTabletPortraitFullViewportHero(),
                ),
              if (useVehiclesFleetLandscapeFullHero)
                Positioned.fill(
                  child: _buildVehiclesFleetTabletLandscapeFullViewportHero(),
                ),
              if (useDriverManagementPortraitFullHero)
                Positioned.fill(
                  child: _buildDriverManagementTabletPortraitFullViewportHero(),
                ),
              if (useDriverManagementLandscapeFullHero)
                Positioned.fill(
                  child:
                      _buildDriverManagementTabletLandscapeFullViewportHero(),
                ),
              if (useChironDocumentsPortraitFullHero)
                Positioned.fill(
                  child: _buildChironDocumentsTabletPortraitFullViewportHero(),
                ),
              if (useChironDocumentsLandscapeFullHero)
                Positioned.fill(
                  child: _buildChironDocumentsTabletLandscapeFullViewportHero(),
                ),
              if (useRegionRadarPortraitFullHero)
                Positioned.fill(
                  child: _buildRegionRadarTabletPortraitFullViewportHero(),
                ),
              if (useRegionRadarLandscapeFullHero)
                Positioned.fill(
                  child: _buildRegionRadarTabletLandscapeFullViewportHero(),
                ),
              if (usePublicBookingLinkPortraitFullHero)
                Positioned.fill(
                  child:
                      _buildPublicBookingLinkTabletPortraitFullViewportHero(),
                ),
              if (usePublicBookingLinkLandscapeFullHero)
                Positioned.fill(
                  child:
                      _buildPublicBookingLinkTabletLandscapeFullViewportHero(),
                ),
              if (useAiDispatchPortraitFullHero)
                Positioned.fill(
                  child: _buildAiDispatchTabletPortraitFullViewportHero(),
                ),
              if (useAiDispatchLandscapeFullHero)
                Positioned.fill(
                  child: _buildAiDispatchTabletLandscapeFullViewportHero(),
                ),
              if (useDriverViewPortraitFullHero)
                Positioned.fill(
                  child: _buildDriverViewTabletPortraitFullViewportHero(),
                ),
              if (useDriverViewLandscapeFullHero)
                Positioned.fill(
                  child: _buildDriverViewTabletLandscapeFullViewportHero(),
                ),
              if (useCalculatorPortraitFullHero)
                Positioned.fill(
                  child: _buildCalculatorTabletPortraitFullViewportHero(),
                ),
              if (useCalculatorLandscapeFullHero)
                Positioned.fill(
                  child: _buildCalculatorTabletLandscapeFullViewportHero(),
                ),
              if (useDriverReceiptsPortraitFullHero)
                Positioned.fill(
                  child: _buildDriverReceiptsTabletPortraitFullViewportHero(),
                ),
              if (useDriverReceiptsLandscapeFullHero)
                Positioned.fill(
                  child: _buildDriverReceiptsTabletLandscapeFullViewportHero(),
                ),
              if (useActivateCustomersPortraitFullHero)
                Positioned.fill(
                  child:
                      _buildActivateCustomersTabletPortraitFullViewportHero(),
                ),
              if (useActivateCustomersLandscapeFullHero)
                Positioned.fill(
                  child:
                      _buildActivateCustomersTabletLandscapeFullViewportHero(),
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
                          useSubscriptionLandscapeFullHero ||
                          useSettingsProfileLandscapeFullHero ||
                          useVehiclesFleetLandscapeFullHero ||
                          useChironDocumentsLandscapeFullHero,
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: _onPageChanged,
                        itemCount: _orientationCards().length,
                        itemBuilder: (ctx, i) {
                          final _OrientationCardData card = _orientationCards()[i];
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
                          if (card.layout ==
                                  _OrientationCardLayout.settingsProfileRich &&
                              (isTabletPortrait || isTabletLandscape)) {
                            return const SizedBox.expand();
                          }
                          // Card 4 tablet portrait/landscape: empty
                          // transparent slot. The dedicated full-
                          // viewport PNG hero behind this Stack is what
                          // the user sees; PageView keeps the swipe
                          // gesture.
                          if (card.layout ==
                                  _OrientationCardLayout.vehiclesFleet &&
                              (isTabletPortrait || isTabletLandscape)) {
                            return const SizedBox.expand();
                          }
                          if (card.layout ==
                                  _OrientationCardLayout.driverManagementRich &&
                              (isTabletPortrait || isTabletLandscape)) {
                            return const SizedBox.expand();
                          }
                          if (card.layout ==
                                  _OrientationCardLayout.chironDocumentsRich &&
                              (isTabletPortrait || isTabletLandscape)) {
                            return const SizedBox.expand();
                          }
                          if (card.layout ==
                                  _OrientationCardLayout.regionRadarRich &&
                              (isTabletPortrait || isTabletLandscape)) {
                            return const SizedBox.expand();
                          }
                          if (card.layout ==
                                  _OrientationCardLayout
                                      .publicBookingLinkRich &&
                              (isTabletPortrait || isTabletLandscape)) {
                            return const SizedBox.expand();
                          }
                          if (card.layout ==
                                  _OrientationCardLayout.aiDispatchRich &&
                              (isTabletPortrait || isTabletLandscape)) {
                            return const SizedBox.expand();
                          }
                          if (card.layout ==
                                  _OrientationCardLayout.driverViewRich &&
                              (isTabletPortrait || isTabletLandscape)) {
                            return const SizedBox.expand();
                          }
                          if (card.layout ==
                                  _OrientationCardLayout.calculatorRich &&
                              (isTabletPortrait || isTabletLandscape)) {
                            return const SizedBox.expand();
                          }
                          if (card.layout ==
                                  _OrientationCardLayout.driverReceiptsRich &&
                              (isTabletPortrait || isTabletLandscape)) {
                            return const SizedBox.expand();
                          }
                          if (card.layout ==
                                  _OrientationCardLayout
                                      .activateCustomersRich &&
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
                          // Card 5 Theme Showroom is an interactive
                          // foreground card (not a full-viewport hero),
                          // so it renders here and needs the full tablet
                          // width to host the large mockup preview.
                          final bool useFullWidthThemes =
                              card.layout ==
                                  _OrientationCardLayout.themesBrandingRich &&
                              (isTabletPortrait || isTabletLandscape);
                          return Align(
                            alignment: useFullWidthHeroPortrait
                                ? Alignment.topCenter
                                : Alignment.center,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    (useFullWidthHeroPortrait ||
                                        useFullWidthThemes)
                                    ? double.infinity
                                    : maxCardWidth,
                              ),
                              child: _buildCard(
                                card,
                                isCompactHeight,
                                isTabletPortrait: isTabletPortrait,
                                isTabletLandscape: isTabletLandscape,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    _buildBottomBar(
                      isCompactHeight,
                      isLast: _index == _orientationCards().length - 1,
                      landscapeFullHero:
                          useLandscapeFullHero ||
                          useCentralCockpitPortraitFullHero ||
                          useCentralCockpitLandscapeFullHero ||
                          useSubscriptionPortraitFullHero ||
                          useSubscriptionLandscapeFullHero ||
                          useSettingsProfilePortraitFullHero ||
                          useSettingsProfileLandscapeFullHero ||
                          useVehiclesFleetPortraitFullHero ||
                          useVehiclesFleetLandscapeFullHero ||
                          useChironDocumentsPortraitFullHero ||
                          useChironDocumentsLandscapeFullHero ||
                          useRegionRadarPortraitFullHero ||
                          useRegionRadarLandscapeFullHero ||
                          usePublicBookingLinkPortraitFullHero ||
                          usePublicBookingLinkLandscapeFullHero ||
                          useAiDispatchPortraitFullHero ||
                          useAiDispatchLandscapeFullHero ||
                          useDriverViewPortraitFullHero ||
                          useDriverViewLandscapeFullHero ||
                          useCalculatorPortraitFullHero ||
                          useCalculatorLandscapeFullHero ||
                          useActivateCustomersPortraitFullHero ||
                          useActivateCustomersLandscapeFullHero,
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
    final isLast = _index == _orientationCards().length - 1;
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
            '${_index + 1} / ${_orientationCards().length}',
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
          if (isLast) ...<Widget>[
            _buildBrochureDownloadCta(
              compact: compact,
              landscapeFullHero: landscapeFullHero,
            ),
            SizedBox(height: landscapeFullHero ? 6 : (compact ? 8 : 12)),
          ],
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
      children: List<Widget>.generate(_orientationCards().length, (i) {
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
    bool isTabletLandscape = false,
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
      case _OrientationCardLayout.settingsProfileRich:
        // Tablet portrait/landscape are short-circuited in [build]
        // (bespoke PNG hero behind the Stack); phones fall back to the
        // stable icon composition with the card's title + intro.
        return _buildOrientationCard(data, compact);
      case _OrientationCardLayout.themesBrandingRich:
        // Interactive Theme Showroom — rendered here in the foreground
        // (NOT a full-viewport hero) so the in-preview arrows receive
        // taps. Tablet portrait/landscape get the bespoke showroom;
        // phones fall back to a compact scrollable showroom.
        return _buildThemesBrandingCard(
          data,
          compact,
          isTabletPortrait: isTabletPortrait,
          isTabletLandscape: isTabletLandscape,
        );
      case _OrientationCardLayout.vehiclesFleet:
        // Tablet portrait/landscape are short-circuited in [build]
        // (bespoke PNG hero behind the Stack); phones fall back to the
        // stable icon composition with the card's title + intro.
        return _buildOrientationCard(data, compact);
      case _OrientationCardLayout.driverManagementRich:
        // Tablet portrait/landscape are short-circuited in [build]
        // (bespoke PNG hero behind the Stack); phones fall back to the
        // stable icon composition with the card's title + intro.
        return _buildOrientationCard(data, compact);
      case _OrientationCardLayout.chironDocumentsRich:
        // Tablet portrait/landscape are short-circuited in [build]
        // (bespoke PNG hero behind the Stack); phones fall back to the
        // stable icon composition with the card's title + intro.
        return _buildOrientationCard(data, compact);
      case _OrientationCardLayout.regionRadarRich:
        // Tablet portrait/landscape are short-circuited in [build]
        // (bespoke PNG hero behind the Stack); phones fall back to the
        // stable icon composition with the card's title + intro.
        return _buildOrientationCard(data, compact);
      case _OrientationCardLayout.publicBookingLinkRich:
        // Tablet portrait/landscape are short-circuited in [build]
        // (bespoke PNG hero behind the Stack); phones fall back to the
        // stable icon composition with the card's title + intro.
        return _buildOrientationCard(data, compact);
      case _OrientationCardLayout.aiDispatchRich:
        // Tablet portrait/landscape are short-circuited in [build]
        // (bespoke PNG hero behind the Stack); phones fall back to the
        // stable icon composition with the card's title + intro.
        return _buildOrientationCard(data, compact);
      case _OrientationCardLayout.driverViewRich:
        // Tablet portrait/landscape are short-circuited in [build]
        // (bespoke PNG hero behind the Stack); phones fall back to the
        // stable icon composition with the card's title + intro.
        return _buildOrientationCard(data, compact);
      case _OrientationCardLayout.calculatorRich:
        // Tablet portrait/landscape are short-circuited in [build]
        // (bespoke PNG hero behind the Stack); phones fall back to the
        // stable icon composition with the card's title + intro.
        return _buildOrientationCard(data, compact);
      case _OrientationCardLayout.driverReceiptsRich:
        // Tablet portrait/landscape are short-circuited in [build]
        // (bespoke PNG hero behind the Stack); phones fall back to the
        // stable icon composition with the card's title + intro.
        return _buildOrientationCard(data, compact);
      case _OrientationCardLayout.activateCustomersRich:
        // Tablet portrait/landscape are short-circuited in [build]
        // (bespoke PNG hero behind the Stack); phones fall back to the
        // stable icon composition with the card's title + intro.
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
        FluxidiDecodeSizedAssetImage(
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
        FluxidiDecodeSizedAssetImage(
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
  // Chiron documents — bespoke tablet hero (PNG + measured text).
  //
  // The card5 artwork contains receipt/audit/local ride register
  // screenshots. Flutter overlays only localised title, intro, and
  // compact feature rows in measured safe zones.
  // =================================================================

  double _chironDocumentsLangScale() {
    switch (appLanguageNotifier.value) {
      case AppLanguage.fr:
      case AppLanguage.es:
        return 0.92;
      case AppLanguage.nl:
      case AppLanguage.en:
      case AppLanguage.de:
        return 1.0;
    }
  }

  Widget _buildChironDocumentsTabletPortraitFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card5ChironDocumentsTabletPortraitAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][CHIRON_PORTRAIT_PNG_FAIL] error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(
          child: _buildChironDocumentsTabletOverlay(isPortrait: true),
        ),
      ],
    );
  }

  Widget _buildChironDocumentsTabletLandscapeFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card5ChironDocumentsTabletLandscapeAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][CHIRON_LANDSCAPE_PNG_FAIL] error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(
          child: _buildChironDocumentsTabletOverlay(isPortrait: false),
        ),
      ],
    );
  }

  Widget _buildChironDocumentsTabletOverlay({required bool isPortrait}) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        if (isPortrait ? h <= w : w <= h) {
          return const SizedBox.shrink();
        }

        final double heroLeft = isPortrait ? 0.44 : 0.37;
        final double heroTop = isPortrait ? 0.078 : 0.068;
        final double heroWidth = isPortrait ? 0.49 : 0.58;
        final double heroHeight = isPortrait ? 0.150 : 0.135;
        final double panelLeft = isPortrait ? 0.055 : 0.045;
        final double panelTop = isPortrait ? 0.220 : 0.430;
        final double panelWidth = isPortrait ? 0.800 : 0.390;
        final double panelHeight = isPortrait ? 0.205 : 0.300;
        final double heroW = w * heroWidth;
        final double heroH = h * heroHeight;
        final double textScale = MediaQuery.textScaleFactorOf(
          ctx,
        ).clamp(1.0, 1.12).toDouble();
        final double langScale = _chironDocumentsLangScale()
            .clamp(0.90, 1.0)
            .toDouble();
        final double scale = langScale / textScale;

        return Stack(
          children: <Widget>[
            Positioned(
              left: w * heroLeft,
              top: h * heroTop,
              width: heroW,
              height: heroH,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: heroW,
                    height: heroH,
                    child: _buildChironDocumentsHeroTextBlock(
                      scale: scale,
                      isPortrait: isPortrait,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: w * panelLeft,
              top: h * panelTop,
              width: w * panelWidth,
              height: h * panelHeight,
              child: isPortrait
                  ? _buildChironDocumentsPortraitFeaturePanel(
                      zoneWidth: w * panelWidth,
                      titleSize: 20.0 * scale,
                      bodySize: 16.0 * scale,
                      footerSize: 16.0 * scale,
                    )
                  : _buildChironDocumentsLandscapeFeaturePanel(
                      zoneWidth: w * panelWidth,
                      titleSize: 18.0 * scale,
                      bodySize: 14.0 * scale,
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChironDocumentsHeroTextBlock({
    required double scale,
    required bool isPortrait,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildChironDocumentsTitle((isPortrait ? 32.0 : 38.0) * scale),
          SizedBox(height: 8 * scale),
          _buildChironDocumentsIntro(
            (isPortrait ? 15.0 : 16.5) * scale,
            isPortrait ? 1.16 : 1.13,
          ),
        ],
      ),
    );
  }

  Widget _buildChironDocumentsTitle(double fontSize) {
    return Text(
      _t(_chironDocumentsTitle),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold,
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        height: 1.06,
        letterSpacing: 0.12,
        shadows: <Shadow>[
          Shadow(color: _gold.withOpacity(0.36), blurRadius: 14),
          Shadow(
            color: Colors.black.withOpacity(0.78),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }

  Widget _buildChironDocumentsIntro(double fontSize, double lineHeight) {
    return Text(
      _t(_chironDocumentsIntro),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: Colors.white.withOpacity(0.90),
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        height: lineHeight,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 8, offset: Offset(0, 1)),
        ],
      ),
    );
  }

  Widget _buildChironDocumentsPortraitFeaturePanel({
    required double zoneWidth,
    required double titleSize,
    required double bodySize,
    required double footerSize,
  }) {
    final double scale = _chironDocumentsLangScale()
        .clamp(0.90, 1.0)
        .toDouble();
    final double rowGap = 10.0 * scale;
    final double rowPaddingH = 11.0 * scale;
    final double rowPaddingV = 8.0 * scale;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: zoneWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < _chironDocumentsFeatures.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : rowGap),
                child: _buildChironDocumentsPortraitFeatureRow(
                  _chironDocumentsFeatures[i],
                  titleSize: titleSize,
                  bodySize: bodySize,
                  dotSize: 7.0 * scale,
                  rowPaddingH: rowPaddingH,
                  rowPaddingV: rowPaddingV,
                ),
              ),
            if (appLanguageNotifier.value != AppLanguage.fr) ...<Widget>[
              SizedBox(height: 6.0 * scale),
              _buildChironDocumentsFeatureFooter(footerSize),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChironDocumentsLandscapeFeaturePanel({
    required double zoneWidth,
    required double titleSize,
    required double bodySize,
  }) {
    final double scale = _chironDocumentsLangScale()
        .clamp(0.90, 1.0)
        .toDouble();
    final double rowGap = 8.0 * scale;
    final double rowPaddingH = 9.0 * scale;
    final double rowPaddingV = 7.0 * scale;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: zoneWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < _chironDocumentsFeatures.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : rowGap),
                child: _buildChironDocumentsLandscapeFeatureRow(
                  _chironDocumentsFeatures[i],
                  titleSize: titleSize,
                  bodySize: bodySize,
                  dotSize: 6.6 * scale,
                  rowPaddingH: rowPaddingH,
                  rowPaddingV: rowPaddingV,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChironDocumentsPortraitFeatureRow(
    _OrientationBulletItem feature, {
    required double titleSize,
    required double bodySize,
    required double dotSize,
    required double rowPaddingH,
    required double rowPaddingV,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withOpacity(0.12)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: rowPaddingH,
          vertical: rowPaddingV,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: dotSize,
              height: dotSize,
              margin: EdgeInsets.only(top: titleSize * 0.34),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _gold,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _gold.withOpacity(0.48),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            SizedBox(width: rowPaddingH * 0.72),
            Expanded(
              child: RichText(
                softWrap: true,
                overflow: TextOverflow.visible,
                text: TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: '${_t(feature.title)}: ',
                      style: TextStyle(
                        color: _gold,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800,
                        height: 1.10,
                        shadows: const <Shadow>[
                          Shadow(
                            color: Color(0xCC000000),
                            blurRadius: 6,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    TextSpan(
                      text: _t(feature.description),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.88),
                        fontSize: bodySize,
                        fontWeight: FontWeight.w500,
                        height: 1.10,
                        shadows: const <Shadow>[
                          Shadow(
                            color: Color(0xCC000000),
                            blurRadius: 6,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChironDocumentsLandscapeFeatureRow(
    _OrientationBulletItem feature, {
    required double titleSize,
    required double bodySize,
    required double dotSize,
    required double rowPaddingH,
    required double rowPaddingV,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withOpacity(0.12)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: rowPaddingH,
          vertical: rowPaddingV,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: dotSize,
                  height: dotSize,
                  margin: EdgeInsets.only(top: titleSize * 0.34),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _gold,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: _gold.withOpacity(0.48),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: rowPaddingH * 0.72),
                Flexible(
                  child: Text(
                    _t(feature.title),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: _gold,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
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
            SizedBox(height: 1.5 * _chironDocumentsLangScale()),
            Padding(
              padding: EdgeInsets.only(left: dotSize + rowPaddingH * 0.72),
              child: Text(
                _t(feature.description),
                softWrap: true,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.88),
                  fontSize: bodySize,
                  fontWeight: FontWeight.w500,
                  height: 1.08,
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
      ),
    );
  }

  Widget _buildChironDocumentsFeatureFooter(double fontSize) {
    return Text(
      _t(_chironDocumentsFooter),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        height: 1.08,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 7, offset: Offset(0, 1)),
        ],
      ),
    );
  }

  /// Per-language down-scale for the longer FR/ES Region Radar copy so
  /// responsive sizes land smaller before the outer [FittedBox] engages.
  double _regionRadarLangScale() {
    switch (appLanguageNotifier.value) {
      case AppLanguage.fr:
      case AppLanguage.es:
        return 0.92;
      case AppLanguage.nl:
      case AppLanguage.en:
      case AppLanguage.de:
        return 1.0;
    }
  }

  Widget _buildRegionRadarTabletPortraitFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card7RegionRadarTabletPortraitAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][REGION_RADAR_PORTRAIT_PNG_FAIL] '
              'error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(child: _buildRegionRadarTabletPortraitOverlay()),
      ],
    );
  }

  Widget _buildRegionRadarTabletLandscapeFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card7RegionRadarTabletLandscapeAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][REGION_RADAR_LANDSCAPE_PNG_FAIL] '
              'error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(child: _buildRegionRadarTabletLandscapeOverlay()),
      ],
    );
  }

  /// Region Radar portrait — title/intro in the top-right black safe
  /// zone marked on the card7 artwork (away from logo and radar).
  Widget _buildRegionRadarTabletPortraitOverlay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        if (h <= w) {
          return const SizedBox.shrink();
        }

        const double panelLeft = 0.395;
        const double panelTop = 0.038;
        const double panelWidth = 0.535;
        const double panelHeight = 0.112;
        const double contentLeft = 0.033;
        const double contentTop = 0.213;
        const double contentWidth = 0.918;
        const double contentHeight = 0.318;

        return Stack(
          children: <Widget>[
            Positioned(
              left: w * panelLeft,
              top: h * panelTop,
              width: w * panelWidth,
              height: h * panelHeight,
              child: _buildDemandRadarTextPanel(
                zoneWidth: w * panelWidth,
                zoneHeight: h * panelHeight,
                isPortrait: true,
              ),
            ),
            Positioned(
              left: w * contentLeft,
              top: h * contentTop,
              width: w * contentWidth,
              height: h * contentHeight,
              child: _buildDemandRadarExplanationFrame(
                zoneWidth: w * contentWidth,
                zoneHeight: h * contentHeight,
                isPortrait: true,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Region Radar landscape — title/intro in the top-center/right
  /// black safe zone, away from the Fluxidi logo and radar visual.
  Widget _buildRegionRadarTabletLandscapeOverlay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        if (w <= h) {
          return const SizedBox.shrink();
        }

        const double panelLeft = 0.355;
        const double panelTop = 0.063;
        const double panelWidth = 0.585;
        const double panelHeight = 0.143;
        const double contentLeft = 0.019;
        const double contentTop = 0.379;
        const double contentWidth = 0.323;
        const double contentHeight = 0.469;

        return Stack(
          children: <Widget>[
            Positioned(
              left: w * panelLeft,
              top: h * panelTop,
              width: w * panelWidth,
              height: h * panelHeight,
              child: _buildDemandRadarTextPanel(
                zoneWidth: w * panelWidth,
                zoneHeight: h * panelHeight,
                isPortrait: false,
              ),
            ),
            Positioned(
              left: w * contentLeft,
              top: h * contentTop,
              width: w * contentWidth,
              height: h * contentHeight,
              child: _buildDemandRadarExplanationFrame(
                zoneWidth: w * contentWidth,
                zoneHeight: h * contentHeight,
                isPortrait: false,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Framed title/intro panel for demand_radar only.
  Widget _buildDemandRadarTextPanel({
    required double zoneWidth,
    required double zoneHeight,
    required bool isPortrait,
  }) {
    final double langScale = _regionRadarLangScale();
    final double titleSize = (isPortrait ? 32.0 : 33.0) * langScale;
    final double introSize = (isPortrait ? 16.5 : 15.0) * langScale;
    final EdgeInsets padding = isPortrait
        ? const EdgeInsets.symmetric(horizontal: 22, vertical: 16)
        : const EdgeInsets.symmetric(horizontal: 24, vertical: 12);

    final Widget copy = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _t(_regionRadarTitle),
          softWrap: true,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: _gold,
            fontSize: titleSize,
            fontWeight: FontWeight.w900,
            height: 1.06,
            letterSpacing: 0.12,
            shadows: <Shadow>[
              Shadow(color: _gold.withOpacity(0.36), blurRadius: 14),
              Shadow(
                color: Colors.black.withOpacity(0.78),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        SizedBox(height: isPortrait ? 5.0 : 4.0),
        Text(
          _t(_regionRadarIntro),
          softWrap: true,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: Colors.white.withOpacity(0.90),
            fontSize: introSize,
            fontWeight: FontWeight.w500,
            height: isPortrait ? 1.14 : 1.12,
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
    );

    final double innerWidth = zoneWidth - padding.horizontal;

    return SizedBox(
      width: zoneWidth,
      height: zoneHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.52),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _gold.withOpacity(0.20)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: _regionRadarWholeBlockScaleDown(
                  maxWidth: constraints.maxWidth,
                  child: copy,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// One whole-block scale-down safety net for Region Radar panels.
  /// Applies to the complete content composition — never to individual
  /// text widgets, sentences, or lines.
  Widget _regionRadarWholeBlockScaleDown({
    required double maxWidth,
    required Widget child,
    Alignment alignment = Alignment.centerLeft,
  }) {
    return Align(
      alignment: alignment,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: SizedBox(width: maxWidth, child: child),
      ),
    );
  }

  /// One premium explanation panel inside the measured red content frame.
  Widget _buildDemandRadarExplanationFrame({
    required double zoneWidth,
    required double zoneHeight,
    required bool isPortrait,
  }) {
    return SizedBox(
      width: zoneWidth,
      height: zoneHeight,
      child: _buildDemandRadarExplanationPanel(
        zoneWidth: zoneWidth,
        zoneHeight: zoneHeight,
        isPortrait: isPortrait,
      ),
    );
  }

  Widget _buildDemandRadarExplanationPanel({
    required double zoneWidth,
    required double zoneHeight,
    required bool isPortrait,
  }) {
    final double langScale = _regionRadarLangScale();
    final EdgeInsets padding = isPortrait
        ? const EdgeInsets.fromLTRB(14, 11, 14, 9)
        : const EdgeInsets.fromLTRB(11, 8, 11, 6);
    final double eyebrowSize = (isPortrait ? 11.0 : 10.0) * langScale;
    final double headingSize = (isPortrait ? 25.0 : 21.0) * langScale;
    final double introSize = (isPortrait ? 16.0 : 13.5) * langScale;
    final double rowTitleSize = (isPortrait ? 17.5 : 14.5) * langScale;
    final double rowBodySize = (isPortrait ? 15.5 : 13.0) * langScale;
    final double closingSize = (isPortrait ? 16.0 : 13.5) * langScale;

    final Widget eyebrow = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _gold.withOpacity(0.26)),
      ),
      child: Text(
        _t(_regionRadarExplanationEyebrow),
        softWrap: true,
        overflow: TextOverflow.visible,
        style: TextStyle(
          color: _gold,
          fontSize: eyebrowSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.65,
          height: 1.12,
        ),
      ),
    );

    final Widget heading = Text(
      _t(_regionRadarExplanationHeading),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold,
        fontSize: headingSize,
        fontWeight: FontWeight.w900,
        height: 1.08,
        letterSpacing: 0.08,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final Widget intro = Text(
      _t(_regionRadarExplanationIntro),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: Colors.white.withOpacity(0.88),
        fontSize: introSize,
        fontWeight: FontWeight.w500,
        height: 1.14,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final Widget closing = Text(
      _t(_regionRadarExplanationClosing),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold.withOpacity(0.88),
        fontSize: closingSize,
        fontWeight: FontWeight.w700,
        height: 1.12,
        letterSpacing: 0.1,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final List<Widget> featureRows = <Widget>[
      for (int i = 0; i < _regionRadarExplanationFeatures.length; i++)
        _buildDemandRadarExplanationFeatureRow(
          _regionRadarExplanationFeatures[i],
          titleSize: rowTitleSize,
          bodySize: rowBodySize,
          showDivider: i > 0,
          compact: !isPortrait,
        ),
    ];

    final List<Widget> spacedFeatureRows = <Widget>[];
    for (int i = 0; i < featureRows.length; i++) {
      if (i > 0) {
        spacedFeatureRows.add(const SizedBox(height: 5.0));
      }
      spacedFeatureRows.add(featureRows[i]);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.54),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withOpacity(0.22)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.32),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double innerWidth = constraints.maxWidth;
            final double innerHeight = constraints.maxHeight;

            if (isPortrait) {
              return SizedBox(
                width: innerWidth,
                height: innerHeight,
                child: _buildDemandRadarExplanationPortraitBody(
                  eyebrow: eyebrow,
                  heading: heading,
                  intro: intro,
                  closing: closing,
                  featureRows: featureRows,
                ),
              );
            }

            // Landscape — approved layout; do not change.
            final Widget contentBlock = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                eyebrow,
                const SizedBox(height: 5),
                heading,
                const SizedBox(height: 5),
                intro,
                const SizedBox(height: 7),
                ...spacedFeatureRows,
                const SizedBox(height: 6),
                closing,
              ],
            );

            return SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: _regionRadarWholeBlockScaleDown(
                maxWidth: innerWidth,
                alignment: Alignment.topLeft,
                child: contentBlock,
              ),
            );
          },
        ),
      ),
    );
  }

  /// Portrait-only explanation body — fills the approved frame height.
  /// Left column anchors the footer low; right column spreads feature
  /// rows evenly. Landscape uses a separate approved path.
  Widget _buildDemandRadarExplanationPortraitBody({
    required Widget eyebrow,
    required Widget heading,
    required Widget intro,
    required Widget closing,
    required List<Widget> featureRows,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          flex: 42,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              eyebrow,
              const SizedBox(height: 7),
              heading,
              const SizedBox(height: 8),
              intro,
              const Spacer(flex: 2),
              closing,
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 58,
          child: Column(
            children: <Widget>[
              for (int i = 0; i < featureRows.length; i++)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: featureRows[i],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDemandRadarExplanationFeatureRow(
    _OrientationBulletItem feature, {
    required double titleSize,
    required double bodySize,
    required bool showDivider,
    required bool compact,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showDivider)
          Padding(
            padding: EdgeInsets.only(bottom: compact ? 4 : 5),
            child: Divider(
              color: _gold.withOpacity(0.14),
              height: 1,
              thickness: 1,
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: compact ? 6.5 : 7,
              height: compact ? 6.5 : 7,
              margin: EdgeInsets.only(top: titleSize * 0.34),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _gold,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _gold.withOpacity(0.45),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _t(feature.title),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: _gold,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w800,
                      height: 1.06,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 2 : 3),
                  Text(
                    _t(feature.description),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.86),
                      fontSize: bodySize,
                      fontWeight: FontWeight.w500,
                      height: 1.10,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // =================================================================
  // Card 10 — Public booking link / Scan to Book (bespoke tablet
  // heroes). Card9 artwork carries the QR visual; Flutter overlays
  // one premium parent panel inside measured safe zones.
  //
  // PORTRAIT content frame (frozen):
  //   left 0.381, top 0.023, width 0.587, height 0.261
  // LANDSCAPE content frame (frozen):
  //   left 0.009, top 0.377, width 0.356, height 0.446
  // =================================================================

  double _publicBookingLinkLangScale() {
    switch (appLanguageNotifier.value) {
      case AppLanguage.fr:
      case AppLanguage.es:
        return 0.92;
      case AppLanguage.nl:
      case AppLanguage.en:
      case AppLanguage.de:
        return 1.0;
    }
  }

  /// Whole-block scale-down safety for Public booking link only.
  Widget _publicBookingLinkWholeBlockScaleDown({
    required double maxWidth,
    required Widget child,
    Alignment alignment = Alignment.topLeft,
  }) {
    return Align(
      alignment: alignment,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: SizedBox(width: maxWidth, child: child),
      ),
    );
  }

  Widget _buildPublicBookingLinkTabletPortraitFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card9PublicBookingLinkTabletPortraitAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][PUBLIC_BOOKING_PORTRAIT_PNG_FAIL] '
              'error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(child: _buildPublicBookingLinkTabletPortraitOverlay()),
      ],
    );
  }

  Widget _buildPublicBookingLinkTabletLandscapeFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card9PublicBookingLinkTabletLandscapeAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][PUBLIC_BOOKING_LANDSCAPE_PNG_FAIL] '
              'error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(child: _buildPublicBookingLinkTabletLandscapeOverlay()),
      ],
    );
  }

  Widget _buildPublicBookingLinkTabletPortraitOverlay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        if (h <= w) {
          return const SizedBox.shrink();
        }

        const double contentLeft = 0.381;
        const double contentTop = 0.023;
        const double contentWidth = 0.587;
        const double contentHeight = 0.261;

        return Stack(
          children: <Widget>[
            Positioned(
              left: w * contentLeft,
              top: h * contentTop,
              width: w * contentWidth,
              height: h * contentHeight,
              child: _buildPublicBookingLinkExplanationPanel(
                zoneWidth: w * contentWidth,
                zoneHeight: h * contentHeight,
                isPortrait: true,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPublicBookingLinkTabletLandscapeOverlay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        if (w <= h) {
          return const SizedBox.shrink();
        }

        const double contentLeft = 0.009;
        const double contentTop = 0.377;
        const double contentWidth = 0.356;
        const double contentHeight = 0.446;

        return Stack(
          children: <Widget>[
            Positioned(
              left: w * contentLeft,
              top: h * contentTop,
              width: w * contentWidth,
              height: h * contentHeight,
              child: _buildPublicBookingLinkExplanationPanel(
                zoneWidth: w * contentWidth,
                zoneHeight: h * contentHeight,
                isPortrait: false,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPublicBookingLinkExplanationPanel({
    required double zoneWidth,
    required double zoneHeight,
    required bool isPortrait,
  }) {
    final double langScale = _publicBookingLinkLangScale();
    final EdgeInsets padding = isPortrait
        ? const EdgeInsets.fromLTRB(12, 8, 12, 7)
        : const EdgeInsets.fromLTRB(11, 10, 11, 8);
    final double titleSize = (isPortrait ? 22.0 : 20.0) * langScale;
    final double cardIntroSize = (isPortrait ? 13.5 : 12.5) * langScale;
    final double eyebrowSize = (isPortrait ? 9.5 : 9.5) * langScale;
    final double headingSize = (isPortrait ? 18.0 : 17.0) * langScale;
    final double introSize = (isPortrait ? 13.5 : 12.5) * langScale;
    final double rowTitleSize = (isPortrait ? 15.5 : 14.5) * langScale;
    final double rowBodySize = (isPortrait ? 13.5 : 12.5) * langScale;
    final double closingSize = (isPortrait ? 13.0 : 12.0) * langScale;

    final Widget title = Text(
      _t(_publicBookingLinkTitle),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold,
        fontSize: titleSize,
        fontWeight: FontWeight.w900,
        height: 1.06,
        letterSpacing: 0.1,
        shadows: <Shadow>[
          Shadow(color: _gold.withOpacity(0.36), blurRadius: 10),
          Shadow(
            color: Colors.black.withOpacity(0.75),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );

    final Widget cardIntro = Text(
      _t(_publicBookingLinkIntro),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: Colors.white.withOpacity(0.88),
        fontSize: cardIntroSize,
        fontWeight: FontWeight.w500,
        height: 1.12,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final Widget eyebrow = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _gold.withOpacity(0.26)),
      ),
      child: Text(
        _t(_publicBookingLinkExplanationEyebrow),
        softWrap: true,
        overflow: TextOverflow.visible,
        style: TextStyle(
          color: _gold,
          fontSize: eyebrowSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          height: 1.12,
        ),
      ),
    );

    final Widget heading = Text(
      _t(_publicBookingLinkExplanationHeading),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold,
        fontSize: headingSize,
        fontWeight: FontWeight.w900,
        height: 1.08,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final Widget intro = Text(
      _t(_publicBookingLinkExplanationIntro),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: Colors.white.withOpacity(0.88),
        fontSize: introSize,
        fontWeight: FontWeight.w500,
        height: 1.12,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final Widget closing = Text(
      _t(_publicBookingLinkExplanationClosing),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold.withOpacity(0.88),
        fontSize: closingSize,
        fontWeight: FontWeight.w700,
        height: 1.10,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final List<Widget> featureRows = <Widget>[
      for (int i = 0; i < _publicBookingLinkExplanationFeatures.length; i++)
        _buildPublicBookingLinkExplanationFeatureRow(
          _publicBookingLinkExplanationFeatures[i],
          titleSize: rowTitleSize,
          bodySize: rowBodySize,
          showDivider: i > 0,
          compact: !isPortrait,
        ),
    ];

    return SizedBox(
      width: zoneWidth,
      height: zoneHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.54),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _gold.withOpacity(0.22)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.32),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: padding,
          child: isPortrait
              ? LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    return SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: _publicBookingLinkWholeBlockScaleDown(
                        maxWidth: constraints.maxWidth,
                        child: _buildPublicBookingLinkExplanationPortraitBody(
                          title: title,
                          cardIntro: cardIntro,
                          eyebrow: eyebrow,
                          heading: heading,
                          intro: intro,
                          closing: closing,
                          featureRows: featureRows,
                        ),
                      ),
                    );
                  },
                )
              : _buildPublicBookingLinkExplanationLandscapeBody(
                  title: title,
                  cardIntro: cardIntro,
                  eyebrow: eyebrow,
                  heading: heading,
                  intro: intro,
                  closing: closing,
                  featureRows: featureRows,
                ),
        ),
      ),
    );
  }

  Widget _buildPublicBookingLinkExplanationPortraitBody({
    required Widget title,
    required Widget cardIntro,
    required Widget eyebrow,
    required Widget heading,
    required Widget intro,
    required Widget closing,
    required List<Widget> featureRows,
  }) {
    final List<Widget> spacedFeatureRows = <Widget>[];
    for (int i = 0; i < featureRows.length; i++) {
      if (i > 0) {
        spacedFeatureRows.add(const SizedBox(height: 6));
      }
      spacedFeatureRows.add(featureRows[i]);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: 44,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              title,
              const SizedBox(height: 3),
              cardIntro,
              const SizedBox(height: 5),
              eyebrow,
              const SizedBox(height: 4),
              heading,
              const SizedBox(height: 4),
              intro,
              const SizedBox(height: 7),
              closing,
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 56,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: spacedFeatureRows,
          ),
        ),
      ],
    );
  }

  Widget _buildPublicBookingLinkExplanationLandscapeBody({
    required Widget title,
    required Widget cardIntro,
    required Widget eyebrow,
    required Widget heading,
    required Widget intro,
    required Widget closing,
    required List<Widget> featureRows,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        title,
        const SizedBox(height: 4),
        cardIntro,
        const SizedBox(height: 6),
        eyebrow,
        const SizedBox(height: 5),
        heading,
        const SizedBox(height: 5),
        intro,
        const SizedBox(height: 6),
        Expanded(
          child: Column(
            children: <Widget>[
              for (int i = 0; i < featureRows.length; i++)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: featureRows[i],
                  ),
                ),
            ],
          ),
        ),
        closing,
      ],
    );
  }

  Widget _buildPublicBookingLinkExplanationFeatureRow(
    _OrientationBulletItem feature, {
    required double titleSize,
    required double bodySize,
    required bool showDivider,
    required bool compact,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showDivider)
          Padding(
            padding: EdgeInsets.only(bottom: compact ? 4 : 5),
            child: Divider(
              color: _gold.withOpacity(0.14),
              height: 1,
              thickness: 1,
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: compact ? 6.0 : 6.5,
              height: compact ? 6.0 : 6.5,
              margin: EdgeInsets.only(top: titleSize * 0.34),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _gold,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _gold.withOpacity(0.45),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _t(feature.title),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: _gold,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w800,
                      height: 1.06,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 2 : 3),
                  Text(
                    _t(feature.description),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.86),
                      fontSize: bodySize,
                      fontWeight: FontWeight.w500,
                      height: 1.10,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // =================================================================
  // Card 11 — AI Dispatch (bespoke tablet heroes). Card10 artwork
  // carries the dispatch cockpit visual; Flutter overlays measured
  // premium panels in dark safe zones.
  //
  // PORTRAIT title frame (frozen):
  //   left 0.377, top 0.028, width 0.584, height 0.169
  // PORTRAIT explanation frame (frozen):
  //   left 0.022, top 0.205, width 0.944, height 0.399
  // LANDSCAPE title frame (frozen):
  //   left 0.305, top 0.048, width 0.678, height 0.219
  // LANDSCAPE explanation frame (frozen):
  //   left 0.011, top 0.375, width 0.240, height 0.546
  // =================================================================

  double _aiDispatchLangScale() {
    switch (appLanguageNotifier.value) {
      case AppLanguage.fr:
      case AppLanguage.es:
        return 0.92;
      case AppLanguage.nl:
      case AppLanguage.en:
      case AppLanguage.de:
        return 1.0;
    }
  }

  /// Whole-block scale-down safety for AI Dispatch only.
  Widget _aiDispatchWholeBlockScaleDown({
    required double maxWidth,
    required Widget child,
    Alignment alignment = Alignment.topLeft,
  }) {
    return Align(
      alignment: alignment,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: SizedBox(width: maxWidth, child: child),
      ),
    );
  }

  Widget _buildAiDispatchTabletPortraitFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card10AiDispatchTabletPortraitAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][AI_DISPATCH_PORTRAIT_PNG_FAIL] '
              'error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(child: _buildAiDispatchTabletPortraitOverlay()),
      ],
    );
  }

  Widget _buildAiDispatchTabletLandscapeFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card10AiDispatchTabletLandscapeAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][AI_DISPATCH_LANDSCAPE_PNG_FAIL] '
              'error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(child: _buildAiDispatchTabletLandscapeOverlay()),
      ],
    );
  }

  Widget _buildAiDispatchTabletPortraitOverlay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        if (h <= w) {
          return const SizedBox.shrink();
        }

        const double titleLeft = 0.377;
        const double titleTop = 0.028;
        const double titleWidth = 0.584;
        const double titleHeight = 0.169;
        const double explainLeft = 0.022;
        const double explainTop = 0.205;
        const double explainWidth = 0.944;
        const double explainHeight = 0.399;

        return Stack(
          children: <Widget>[
            Positioned(
              left: w * titleLeft,
              top: h * titleTop,
              width: w * titleWidth,
              height: h * titleHeight,
              child: _buildAiDispatchPortraitTitlePanel(
                zoneWidth: w * titleWidth,
                zoneHeight: h * titleHeight,
              ),
            ),
            Positioned(
              left: w * explainLeft,
              top: h * explainTop,
              width: w * explainWidth,
              height: h * explainHeight,
              child: _buildAiDispatchPortraitExplanationPanel(
                zoneWidth: w * explainWidth,
                zoneHeight: h * explainHeight,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAiDispatchTabletLandscapeOverlay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        if (w <= h) {
          return const SizedBox.shrink();
        }

        const double titleLeft = 0.305;
        const double titleTop = 0.048;
        const double titleWidth = 0.678;
        const double titleHeight = 0.219;
        const double explainLeft = 0.011;
        const double explainTop = 0.375;
        const double explainWidth = 0.240;
        const double explainHeight = 0.546;

        return Stack(
          children: <Widget>[
            Positioned(
              left: w * titleLeft,
              top: h * titleTop,
              width: w * titleWidth,
              height: h * titleHeight,
              child: _buildAiDispatchLandscapeTitlePanel(
                zoneWidth: w * titleWidth,
                zoneHeight: h * titleHeight,
              ),
            ),
            Positioned(
              left: w * explainLeft,
              top: h * explainTop,
              width: w * explainWidth,
              height: h * explainHeight,
              child: _buildAiDispatchLandscapeExplanationPanel(
                zoneWidth: w * explainWidth,
                zoneHeight: h * explainHeight,
              ),
            ),
          ],
        );
      },
    );
  }

  BoxDecoration _aiDispatchPanelDecoration() {
    return BoxDecoration(
      color: Colors.black.withOpacity(0.54),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _gold.withOpacity(0.22)),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withOpacity(0.32),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  Widget _buildAiDispatchPortraitTitlePanel({
    required double zoneWidth,
    required double zoneHeight,
  }) {
    final double langScale = _aiDispatchLangScale();
    final EdgeInsets padding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 8,
    );
    final double titleSize = 30.0 * langScale;
    final double subtitleSize = 14.5 * langScale;

    final Widget copy = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _t(_aiDispatchTitle),
          softWrap: true,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: _gold,
            fontSize: titleSize,
            fontWeight: FontWeight.w900,
            height: 1.06,
            letterSpacing: 0.12,
            shadows: <Shadow>[
              Shadow(color: _gold.withOpacity(0.36), blurRadius: 14),
              Shadow(
                color: Colors.black.withOpacity(0.78),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _t(_aiDispatchSubtitle),
          softWrap: true,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: Colors.white.withOpacity(0.90),
            fontSize: subtitleSize,
            fontWeight: FontWeight.w500,
            height: 1.12,
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
    );

    return SizedBox(
      width: zoneWidth,
      height: zoneHeight,
      child: DecoratedBox(
        decoration: _aiDispatchPanelDecoration(),
        child: Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: _aiDispatchWholeBlockScaleDown(
                  maxWidth: constraints.maxWidth,
                  alignment: Alignment.centerLeft,
                  child: copy,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAiDispatchPortraitExplanationPanel({
    required double zoneWidth,
    required double zoneHeight,
  }) {
    final double langScale = _aiDispatchLangScale();
    final EdgeInsets padding = const EdgeInsets.fromLTRB(13, 10, 13, 8);
    final double eyebrowSize = 10.0 * langScale;
    final double headingSize = 20.0 * langScale;
    final double introSize = 14.0 * langScale;
    final double rowTitleSize = 15.0 * langScale;
    final double rowBodySize = 13.5 * langScale;
    final double closingSize = 13.0 * langScale;

    final Widget eyebrow = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _gold.withOpacity(0.26)),
      ),
      child: Text(
        _t(_aiDispatchExplanationEyebrow),
        softWrap: true,
        overflow: TextOverflow.visible,
        style: TextStyle(
          color: _gold,
          fontSize: eyebrowSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.55,
          height: 1.12,
        ),
      ),
    );

    final Widget heading = Text(
      _t(_aiDispatchExplanationHeading),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold,
        fontSize: headingSize,
        fontWeight: FontWeight.w900,
        height: 1.08,
        letterSpacing: 0.06,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final Widget intro = Text(
      _t(_aiDispatchExplanationIntro),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: Colors.white.withOpacity(0.88),
        fontSize: introSize,
        fontWeight: FontWeight.w500,
        height: 1.12,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final Widget closing = Text(
      _t(_aiDispatchExplanationClosing),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold.withOpacity(0.88),
        fontSize: closingSize,
        fontWeight: FontWeight.w700,
        height: 1.08,
        letterSpacing: 0.08,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final List<Widget> featureRows = <Widget>[
      for (int i = 0; i < _aiDispatchExplanationFeatures.length; i++)
        _buildAiDispatchExplanationFeatureRow(
          _aiDispatchExplanationFeatures[i],
          titleSize: rowTitleSize,
          bodySize: rowBodySize,
          showDivider: i > 0,
          compact: true,
        ),
    ];

    return SizedBox(
      width: zoneWidth,
      height: zoneHeight,
      child: DecoratedBox(
        decoration: _aiDispatchPanelDecoration(),
        child: Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    eyebrow,
                    const SizedBox(height: 4),
                    heading,
                    const SizedBox(height: 5),
                    intro,
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: featureRows,
                      ),
                    ),
                    const SizedBox(height: 4),
                    closing,
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAiDispatchLandscapeTitlePanel({
    required double zoneWidth,
    required double zoneHeight,
  }) {
    final double langScale = _aiDispatchLangScale();
    final EdgeInsets padding = const EdgeInsets.symmetric(
      horizontal: 22,
      vertical: 14,
    );
    final double titleSize = 33.0 * langScale;
    final double subtitleSize = 15.0 * langScale;

    final Widget copy = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _t(_aiDispatchTitle),
          softWrap: true,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: _gold,
            fontSize: titleSize,
            fontWeight: FontWeight.w900,
            height: 1.06,
            letterSpacing: 0.12,
            shadows: <Shadow>[
              Shadow(color: _gold.withOpacity(0.36), blurRadius: 14),
              Shadow(
                color: Colors.black.withOpacity(0.78),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _t(_aiDispatchSubtitle),
          softWrap: true,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: Colors.white.withOpacity(0.90),
            fontSize: subtitleSize,
            fontWeight: FontWeight.w500,
            height: 1.12,
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
    );

    return SizedBox(
      width: zoneWidth,
      height: zoneHeight,
      child: DecoratedBox(
        decoration: _aiDispatchPanelDecoration(),
        child: Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: _aiDispatchWholeBlockScaleDown(
                  maxWidth: constraints.maxWidth,
                  alignment: Alignment.centerLeft,
                  child: copy,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAiDispatchLandscapeExplanationPanel({
    required double zoneWidth,
    required double zoneHeight,
  }) {
    final double langScale = _aiDispatchLangScale();
    final EdgeInsets padding = const EdgeInsets.fromLTRB(11, 9, 11, 7);
    final double eyebrowSize = 10.0 * langScale;
    final double headingSize = 21.0 * langScale;
    final double introSize = 13.5 * langScale;
    final double rowTitleSize = 14.5 * langScale;
    final double rowBodySize = 13.0 * langScale;
    final double closingSize = 13.5 * langScale;

    final Widget eyebrow = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _gold.withOpacity(0.26)),
      ),
      child: Text(
        _t(_aiDispatchExplanationEyebrow),
        softWrap: true,
        overflow: TextOverflow.visible,
        style: TextStyle(
          color: _gold,
          fontSize: eyebrowSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.55,
          height: 1.12,
        ),
      ),
    );

    final Widget heading = Text(
      _t(_aiDispatchExplanationHeading),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold,
        fontSize: headingSize,
        fontWeight: FontWeight.w900,
        height: 1.08,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final Widget intro = Text(
      _t(_aiDispatchExplanationIntro),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: Colors.white.withOpacity(0.88),
        fontSize: introSize,
        fontWeight: FontWeight.w500,
        height: 1.12,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final Widget closing = Text(
      _t(_aiDispatchExplanationClosing),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold.withOpacity(0.88),
        fontSize: closingSize,
        fontWeight: FontWeight.w700,
        height: 1.10,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final List<Widget> featureRows = <Widget>[
      for (int i = 0; i < _aiDispatchExplanationFeatures.length; i++)
        _buildAiDispatchExplanationFeatureRow(
          _aiDispatchExplanationFeatures[i],
          titleSize: rowTitleSize,
          bodySize: rowBodySize,
          showDivider: i > 0,
          compact: true,
        ),
    ];

    final List<Widget> spacedFeatureRows = <Widget>[];
    for (int i = 0; i < featureRows.length; i++) {
      if (i > 0) {
        spacedFeatureRows.add(const SizedBox(height: 5));
      }
      spacedFeatureRows.add(featureRows[i]);
    }

    return SizedBox(
      width: zoneWidth,
      height: zoneHeight,
      child: DecoratedBox(
        decoration: _aiDispatchPanelDecoration(),
        child: Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget contentBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  eyebrow,
                  const SizedBox(height: 5),
                  heading,
                  const SizedBox(height: 5),
                  intro,
                  const SizedBox(height: 7),
                  ...spacedFeatureRows,
                  const SizedBox(height: 6),
                  closing,
                ],
              );

              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: _aiDispatchWholeBlockScaleDown(
                  maxWidth: constraints.maxWidth,
                  alignment: Alignment.topLeft,
                  child: contentBlock,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAiDispatchExplanationFeatureRow(
    _OrientationBulletItem feature, {
    required double titleSize,
    required double bodySize,
    required bool showDivider,
    required bool compact,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showDivider)
          Padding(
            padding: EdgeInsets.only(bottom: compact ? 4 : 5),
            child: Divider(
              color: _gold.withOpacity(0.14),
              height: 1,
              thickness: 1,
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: compact ? 6.5 : 7,
              height: compact ? 6.5 : 7,
              margin: EdgeInsets.only(top: titleSize * 0.34),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _gold,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _gold.withOpacity(0.45),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _t(feature.title),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: _gold,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w800,
                      height: 1.06,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 2 : 3),
                  Text(
                    _t(feature.description),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.86),
                      fontSize: bodySize,
                      fontWeight: FontWeight.w500,
                      height: 1.10,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // =================================================================
  // Card 12 — Driver View / Chauffeurcockpit (bespoke tablet heroes).
  // Card8 artwork carries the driver dashboard visual; Flutter
  // overlays measured premium panels in dark safe zones.
  //
  // PORTRAIT title frame (frozen):
  //   left 0.368, top 0.021, width 0.590, height 0.177
  // PORTRAIT explanation frame (frozen):
  //   left 0.012, top 0.199, width 0.259, height 0.722
  // LANDSCAPE title frame (frozen):
  //   left 0.352, top 0.050, width 0.610, height 0.056
  // LANDSCAPE explanation frame (frozen):
  //   left 0.011, top 0.371, width 0.332, height 0.523
  // =================================================================

  double _driverViewLangScale() {
    switch (appLanguageNotifier.value) {
      case AppLanguage.fr:
      case AppLanguage.es:
        return 0.92;
      case AppLanguage.nl:
      case AppLanguage.en:
      case AppLanguage.de:
        return 1.0;
    }
  }

  /// Whole-block scale-down safety for Driver View only.
  Widget _driverViewWholeBlockScaleDown({
    required double maxWidth,
    required Widget child,
    Alignment alignment = Alignment.topLeft,
  }) {
    return Align(
      alignment: alignment,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: SizedBox(width: maxWidth, child: child),
      ),
    );
  }

  BoxDecoration _driverViewPanelDecoration() {
    return BoxDecoration(
      color: Colors.black.withOpacity(0.54),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _gold.withOpacity(0.22)),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withOpacity(0.32),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  Widget _buildDriverViewTabletPortraitFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card8DriverViewTabletPortraitAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][DRIVER_VIEW_PORTRAIT_PNG_FAIL] '
              'error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(child: _buildDriverViewTabletPortraitOverlay()),
      ],
    );
  }

  Widget _buildDriverViewTabletLandscapeFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card8DriverViewTabletLandscapeAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][DRIVER_VIEW_LANDSCAPE_PNG_FAIL] '
              'error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(child: _buildDriverViewTabletLandscapeOverlay()),
      ],
    );
  }

  Widget _buildDriverViewTabletPortraitOverlay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        if (h <= w) {
          return const SizedBox.shrink();
        }

        const double titleLeft = 0.368;
        const double titleTop = 0.021;
        const double titleWidth = 0.590;
        const double titleHeight = 0.177;
        const double explainLeft = 0.012;
        const double explainTop = 0.199;
        const double explainWidth = 0.259;
        const double explainHeight = 0.722;

        return Stack(
          children: <Widget>[
            Positioned(
              left: w * titleLeft,
              top: h * titleTop,
              width: w * titleWidth,
              height: h * titleHeight,
              child: _buildDriverViewTitlePanel(
                zoneWidth: w * titleWidth,
                zoneHeight: h * titleHeight,
                isPortrait: true,
              ),
            ),
            Positioned(
              left: w * explainLeft,
              top: h * explainTop,
              width: w * explainWidth,
              height: h * explainHeight,
              child: _buildDriverViewExplanationPanel(
                zoneWidth: w * explainWidth,
                zoneHeight: h * explainHeight,
                isPortrait: true,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDriverViewTabletLandscapeOverlay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        if (w <= h) {
          return const SizedBox.shrink();
        }

        const double titleLeft = 0.352;
        const double titleTop = 0.050;
        const double titleWidth = 0.610;
        const double titleHeight = 0.056;
        const double explainLeft = 0.011;
        const double explainTop = 0.371;
        const double explainWidth = 0.332;
        const double explainHeight = 0.523;

        return Stack(
          children: <Widget>[
            Positioned(
              left: w * titleLeft,
              top: h * titleTop,
              width: w * titleWidth,
              height: h * titleHeight,
              child: _buildDriverViewTitlePanel(
                zoneWidth: w * titleWidth,
                zoneHeight: h * titleHeight,
                isPortrait: false,
              ),
            ),
            Positioned(
              left: w * explainLeft,
              top: h * explainTop,
              width: w * explainWidth,
              height: h * explainHeight,
              child: _buildDriverViewExplanationPanel(
                zoneWidth: w * explainWidth,
                zoneHeight: h * explainHeight,
                isPortrait: false,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDriverViewTitlePanel({
    required double zoneWidth,
    required double zoneHeight,
    required bool isPortrait,
  }) {
    final double langScale = _driverViewLangScale();
    final EdgeInsets padding = isPortrait
        ? const EdgeInsets.symmetric(horizontal: 18, vertical: 12)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 3);
    final double titleSize = (isPortrait ? 33.0 : 30.0) * langScale;
    final double subtitleSize = (isPortrait ? 16.5 : 13.5) * langScale;
    final double titleSubtitleGap = isPortrait ? 6.0 : 3.0;

    final Widget copy = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _t(_driverViewTitle),
          softWrap: true,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: _gold,
            fontSize: titleSize,
            fontWeight: FontWeight.w900,
            height: 1.06,
            letterSpacing: 0.12,
            shadows: <Shadow>[
              Shadow(color: _gold.withOpacity(0.36), blurRadius: 14),
              Shadow(
                color: Colors.black.withOpacity(0.78),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        SizedBox(height: titleSubtitleGap),
        Text(
          _t(_driverViewSubtitle),
          softWrap: true,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: Colors.white.withOpacity(0.90),
            fontSize: subtitleSize,
            fontWeight: FontWeight.w500,
            height: isPortrait ? 1.14 : 1.10,
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
    );

    return SizedBox(
      width: zoneWidth,
      height: zoneHeight,
      child: DecoratedBox(
        decoration: _driverViewPanelDecoration(),
        child: Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget composed = ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[copy],
                ),
              );

              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: _driverViewWholeBlockScaleDown(
                  maxWidth: constraints.maxWidth,
                  alignment: Alignment.centerLeft,
                  child: composed,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDriverViewExplanationPanel({
    required double zoneWidth,
    required double zoneHeight,
    required bool isPortrait,
  }) {
    final double langScale = _driverViewLangScale();
    final EdgeInsets padding = isPortrait
        ? const EdgeInsets.fromLTRB(12, 12, 12, 10)
        : const EdgeInsets.fromLTRB(12, 10, 12, 8);
    final double eyebrowSize = (isPortrait ? 10.5 : 10.5) * langScale;
    final double headingSize = (isPortrait ? 20.0 : 21.0) * langScale;
    final double introSize = (isPortrait ? 14.5 : 14.0) * langScale;
    final double rowTitleSize = (isPortrait ? 15.5 : 15.0) * langScale;
    final double rowBodySize = (isPortrait ? 14.0 : 13.5) * langScale;
    final double closingSize = (isPortrait ? 14.0 : 13.5) * langScale;
    final double sectionGap = isPortrait ? 7.0 : 6.0;
    final double rowGap = isPortrait ? 8.0 : 7.0;

    final Widget eyebrow = Container(
      padding: EdgeInsets.symmetric(
        horizontal: isPortrait ? 8 : 9,
        vertical: isPortrait ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _gold.withOpacity(0.26)),
      ),
      child: Text(
        _t(_driverViewExplanationEyebrow),
        softWrap: true,
        overflow: TextOverflow.visible,
        style: TextStyle(
          color: _gold,
          fontSize: eyebrowSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.55,
          height: 1.12,
        ),
      ),
    );

    final Widget heading = Text(
      _t(_driverViewExplanationHeading),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold,
        fontSize: headingSize,
        fontWeight: FontWeight.w900,
        height: 1.08,
        letterSpacing: 0.08,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final Widget intro = Text(
      _t(_driverViewExplanationIntro),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: Colors.white.withOpacity(0.88),
        fontSize: introSize,
        fontWeight: FontWeight.w500,
        height: 1.12,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final Widget closing = Text(
      _t(_driverViewExplanationClosing),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold.withOpacity(0.88),
        fontSize: closingSize,
        fontWeight: FontWeight.w700,
        height: 1.10,
        letterSpacing: 0.08,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final List<Widget> featureRows = <Widget>[
      for (int i = 0; i < _driverViewExplanationFeatures.length; i++)
        _buildDriverViewExplanationFeatureRow(
          _driverViewExplanationFeatures[i],
          titleSize: rowTitleSize,
          bodySize: rowBodySize,
          showDivider: i > 0,
          compact: !isPortrait,
        ),
    ];

    return SizedBox(
      width: zoneWidth,
      height: zoneHeight,
      child: DecoratedBox(
        decoration: _driverViewPanelDecoration(),
        child: Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget topBlock = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  eyebrow,
                  SizedBox(height: sectionGap),
                  heading,
                  SizedBox(height: sectionGap),
                  intro,
                ],
              );

              final List<Widget> spacedFeatureRows = <Widget>[];
              for (int i = 0; i < featureRows.length; i++) {
                if (i > 0) {
                  spacedFeatureRows.add(SizedBox(height: rowGap));
                }
                spacedFeatureRows.add(featureRows[i]);
              }

              final Widget rowsBlock = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: spacedFeatureRows,
              );

              final Widget composedPanel = ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                  maxWidth: constraints.maxWidth,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[topBlock, rowsBlock, closing],
                ),
              );

              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: _driverViewWholeBlockScaleDown(
                  maxWidth: constraints.maxWidth,
                  alignment: Alignment.topLeft,
                  child: composedPanel,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDriverViewExplanationFeatureRow(
    _OrientationBulletItem feature, {
    required double titleSize,
    required double bodySize,
    required bool showDivider,
    required bool compact,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showDivider)
          Padding(
            padding: EdgeInsets.only(bottom: compact ? 4 : 5),
            child: Divider(
              color: _gold.withOpacity(0.14),
              height: 1,
              thickness: 1,
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: compact ? 6.5 : 7,
              height: compact ? 6.5 : 7,
              margin: EdgeInsets.only(top: titleSize * 0.34),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _gold,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _gold.withOpacity(0.45),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            SizedBox(width: compact ? 7 : 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _t(feature.title),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: _gold,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w800,
                      height: 1.06,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 2 : 3),
                  Text(
                    _t(feature.description),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.86),
                      fontSize: bodySize,
                      fontWeight: FontWeight.w500,
                      height: 1.10,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // =================================================================
  // Card 13 — Calculator & ride pricing (bespoke tablet heroes).
  // Card11 artwork carries the calculator visual; Flutter overlays
  // measured premium panels in dark safe zones.
  //
  // PORTRAIT title frame (frozen):
  //   left 0.3551912568, top 0.0224609375, width 0.6276346604,
  //   height 0.1411132813
  // PORTRAIT explanation frame (frozen):
  //   left 0.0148321624, top 0.1992187500, width 0.9711163154,
  //   height 0.2866210938
  // LANDSCAPE title frame (frozen):
  //   left 0.3818359375, top 0.0468384075, width 0.5493164063,
  //   height 0.1725214676
  // LANDSCAPE explanation frame (frozen):
  //   left 0.0107421875, top 0.3692427791, width 0.3710937500,
  //   height 0.4824355972
  // =================================================================

  double _calculatorLangScale() {
    switch (appLanguageNotifier.value) {
      case AppLanguage.fr:
      case AppLanguage.es:
        return 0.92;
      case AppLanguage.nl:
      case AppLanguage.en:
      case AppLanguage.de:
        return 1.0;
    }
  }

  /// Whole-block scale-down safety for Calculator card only.
  Widget _calculatorWholeBlockScaleDown({
    required double maxWidth,
    required Widget child,
    Alignment alignment = Alignment.topLeft,
  }) {
    return Align(
      alignment: alignment,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: SizedBox(width: maxWidth, child: child),
      ),
    );
  }

  BoxDecoration _calculatorPanelDecoration() {
    return BoxDecoration(
      color: Colors.black.withOpacity(0.54),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _gold.withOpacity(0.22)),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withOpacity(0.32),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  Widget _buildCalculatorTabletPortraitFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card11CalculatorTabletPortraitAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][CALCULATOR_PORTRAIT_PNG_FAIL] '
              'error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(child: _buildCalculatorTabletPortraitOverlay()),
      ],
    );
  }

  Widget _buildCalculatorTabletLandscapeFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card11CalculatorTabletLandscapeAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][CALCULATOR_LANDSCAPE_PNG_FAIL] '
              'error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(child: _buildCalculatorTabletLandscapeOverlay()),
      ],
    );
  }

  Widget _buildCalculatorTabletPortraitOverlay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        if (h <= w) {
          return const SizedBox.shrink();
        }

        const double titleLeft = 0.3551912568;
        const double titleTop = 0.0224609375;
        const double titleWidth = 0.6276346604;
        const double titleHeight = 0.1411132813;
        const double explainLeft = 0.0148321624;
        const double explainTop = 0.1992187500;
        const double explainWidth = 0.9711163154;
        const double explainHeight = 0.2866210938;

        return Stack(
          children: <Widget>[
            Positioned(
              left: w * titleLeft,
              top: h * titleTop,
              width: w * titleWidth,
              height: h * titleHeight,
              child: _buildCalculatorTitlePanel(
                zoneWidth: w * titleWidth,
                zoneHeight: h * titleHeight,
                isPortrait: true,
              ),
            ),
            Positioned(
              left: w * explainLeft,
              top: h * explainTop,
              width: w * explainWidth,
              height: h * explainHeight,
              child: _buildCalculatorExplanationPanel(
                zoneWidth: w * explainWidth,
                zoneHeight: h * explainHeight,
                isPortrait: true,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCalculatorTabletLandscapeOverlay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        if (w <= h) {
          return const SizedBox.shrink();
        }

        const double titleLeft = 0.3818359375;
        const double titleTop = 0.0468384075;
        const double titleWidth = 0.5493164063;
        const double titleHeight = 0.1725214676;
        const double explainLeft = 0.0107421875;
        const double explainTop = 0.3692427791;
        const double explainWidth = 0.3710937500;
        const double explainHeight = 0.4824355972;

        return Stack(
          children: <Widget>[
            Positioned(
              left: w * titleLeft,
              top: h * titleTop,
              width: w * titleWidth,
              height: h * titleHeight,
              child: _buildCalculatorTitlePanel(
                zoneWidth: w * titleWidth,
                zoneHeight: h * titleHeight,
                isPortrait: false,
              ),
            ),
            Positioned(
              left: w * explainLeft,
              top: h * explainTop,
              width: w * explainWidth,
              height: h * explainHeight,
              child: _buildCalculatorExplanationPanel(
                zoneWidth: w * explainWidth,
                zoneHeight: h * explainHeight,
                isPortrait: false,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCalculatorTitlePanel({
    required double zoneWidth,
    required double zoneHeight,
    required bool isPortrait,
  }) {
    final double langScale = _calculatorLangScale();
    final EdgeInsets padding = isPortrait
        ? const EdgeInsets.symmetric(horizontal: 18, vertical: 12)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 10);
    final double titleSize = (isPortrait ? 33.0 : 32.0) * langScale;
    final double subtitleSize = (isPortrait ? 16.5 : 15.0) * langScale;
    final double titleSubtitleGap = isPortrait ? 6.0 : 5.0;

    final Widget copy = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _t(_calculatorTitle),
          softWrap: true,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: _gold,
            fontSize: titleSize,
            fontWeight: FontWeight.w900,
            height: 1.06,
            letterSpacing: 0.12,
            shadows: <Shadow>[
              Shadow(color: _gold.withOpacity(0.36), blurRadius: 14),
              Shadow(
                color: Colors.black.withOpacity(0.78),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        SizedBox(height: titleSubtitleGap),
        Text(
          _t(_calculatorSubtitle),
          softWrap: true,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: Colors.white.withOpacity(0.90),
            fontSize: subtitleSize,
            fontWeight: FontWeight.w500,
            height: isPortrait ? 1.14 : 1.12,
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
    );

    return SizedBox(
      width: zoneWidth,
      height: zoneHeight,
      child: DecoratedBox(
        decoration: _calculatorPanelDecoration(),
        child: Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // Stable content block: a single mainAxisSize.min Column
              // with fixed gaps and no Expanded/Spacer/spaceBetween
              // (those require a bounded main-axis under the outer
              // FittedBox, which passes unbounded constraints).
              final Widget composed = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[copy],
              );

              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: _calculatorWholeBlockScaleDown(
                  maxWidth: constraints.maxWidth,
                  alignment: Alignment.centerLeft,
                  child: composed,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCalculatorExplanationPanel({
    required double zoneWidth,
    required double zoneHeight,
    required bool isPortrait,
  }) {
    final double langScale = _calculatorLangScale();
    final EdgeInsets padding = isPortrait
        ? const EdgeInsets.fromLTRB(14, 11, 14, 9)
        : const EdgeInsets.fromLTRB(12, 10, 12, 8);
    final double eyebrowSize = (isPortrait ? 10.0 : 10.5) * langScale;
    final double headingSize = (isPortrait ? 20.0 : 21.0) * langScale;
    final double introSize = (isPortrait ? 14.0 : 14.0) * langScale;
    final double rowTitleSize = (isPortrait ? 15.0 : 15.0) * langScale;
    final double rowBodySize = (isPortrait ? 13.5 : 13.5) * langScale;
    final double closingSize = (isPortrait ? 13.0 : 13.5) * langScale;
    final double sectionGap = isPortrait ? 6.0 : 6.0;
    final double rowGap = isPortrait ? 6.0 : 7.0;

    final Widget eyebrow = Container(
      padding: EdgeInsets.symmetric(
        horizontal: isPortrait ? 8 : 9,
        vertical: isPortrait ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _gold.withOpacity(0.26)),
      ),
      child: Text(
        _t(_calculatorExplanationEyebrow),
        softWrap: true,
        overflow: TextOverflow.visible,
        style: TextStyle(
          color: _gold,
          fontSize: eyebrowSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.55,
          height: 1.12,
        ),
      ),
    );

    final Widget heading = Text(
      _t(_calculatorExplanationHeading),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold,
        fontSize: headingSize,
        fontWeight: FontWeight.w900,
        height: 1.08,
        letterSpacing: 0.08,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final Widget intro = Text(
      _t(_calculatorExplanationIntro),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: Colors.white.withOpacity(0.88),
        fontSize: introSize,
        fontWeight: FontWeight.w500,
        height: 1.12,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final Widget closing = Text(
      _t(_calculatorExplanationClosing),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold.withOpacity(0.88),
        fontSize: closingSize,
        fontWeight: FontWeight.w700,
        height: 1.10,
        letterSpacing: 0.08,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final List<Widget> featureRows = <Widget>[
      for (int i = 0; i < _calculatorExplanationFeatures.length; i++)
        _buildCalculatorExplanationFeatureRow(
          _calculatorExplanationFeatures[i],
          titleSize: rowTitleSize,
          bodySize: rowBodySize,
          showDivider: i > 0,
          compact: !isPortrait,
        ),
    ];

    return SizedBox(
      width: zoneWidth,
      height: zoneHeight,
      child: DecoratedBox(
        decoration: _calculatorPanelDecoration(),
        child: Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // Stable content block. The outer whole-block FittedBox
              // passes unbounded constraints to its child, so the
              // composed Column MUST use mainAxisSize.min with fixed
              // gaps only — no Expanded/Flexible/Spacer/spaceBetween,
              // which would trip the layout boundary assertion.
              final List<Widget> spacedFeatureRows = <Widget>[];
              for (int i = 0; i < featureRows.length; i++) {
                if (i > 0) {
                  spacedFeatureRows.add(SizedBox(height: rowGap));
                }
                spacedFeatureRows.add(featureRows[i]);
              }

              final Widget composedPanel = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  eyebrow,
                  SizedBox(height: sectionGap),
                  heading,
                  SizedBox(height: sectionGap),
                  intro,
                  SizedBox(height: sectionGap + 2),
                  ...spacedFeatureRows,
                  SizedBox(height: sectionGap + 2),
                  closing,
                ],
              );

              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: _calculatorWholeBlockScaleDown(
                  maxWidth: constraints.maxWidth,
                  alignment: Alignment.topLeft,
                  child: composedPanel,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCalculatorExplanationFeatureRow(
    _OrientationBulletItem feature, {
    required double titleSize,
    required double bodySize,
    required bool showDivider,
    required bool compact,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showDivider)
          Padding(
            padding: EdgeInsets.only(bottom: compact ? 4 : 5),
            child: Divider(
              color: _gold.withOpacity(0.14),
              height: 1,
              thickness: 1,
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: compact ? 6.5 : 7,
              height: compact ? 6.5 : 7,
              margin: EdgeInsets.only(top: titleSize * 0.34),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _gold,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _gold.withOpacity(0.45),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            SizedBox(width: compact ? 7 : 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _t(feature.title),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: _gold,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w800,
                      height: 1.06,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 2 : 3),
                  Text(
                    _t(feature.description),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.86),
                      fontSize: bodySize,
                      fontWeight: FontWeight.w500,
                      height: 1.10,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // =================================================================
  // Card 14 — Ride receipts, history & documents (bespoke tablet
  // heroes). Card12 artwork carries the in-cockpit tablet visual;
  // Flutter overlays measured premium panels in the dark safe zones.
  //
  // PORTRAIT title frame (frozen):
  //   left 0.357, top 0.023, width 0.625, height 0.139
  // PORTRAIT explanation frame (frozen):
  //   left 0.016, top 0.200, width 0.968, height 0.293
  // LANDSCAPE title frame (frozen):
  //   left 0.336, top 0.049, width 0.647, height 0.132
  // LANDSCAPE explanation frame (frozen):
  //   left 0.010, top 0.411, width 0.371, height 0.536
  //
  // The content blocks fed to the FittedBox(scaleDown) safety
  // wrapper MUST be mainAxisSize.min Columns with fixed
  // SizedBox gaps only — no Expanded/Flexible/Spacer/spaceBetween,
  // since the outer FittedBox passes unbounded constraints which
  // would trip the layout boundary assertion.
  // =================================================================

  double _driverReceiptsLangScale() {
    switch (appLanguageNotifier.value) {
      case AppLanguage.fr:
      case AppLanguage.es:
        return 0.92;
      case AppLanguage.nl:
      case AppLanguage.en:
      case AppLanguage.de:
        return 1.0;
    }
  }

  /// Whole-block scale-down safety for Driver Receipts only.
  Widget _driverReceiptsWholeBlockScaleDown({
    required double maxWidth,
    required Widget child,
    Alignment alignment = Alignment.topLeft,
  }) {
    return Align(
      alignment: alignment,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: SizedBox(width: maxWidth, child: child),
      ),
    );
  }

  BoxDecoration _driverReceiptsPanelDecoration() {
    return BoxDecoration(
      color: Colors.black.withOpacity(0.54),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _gold.withOpacity(0.22)),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withOpacity(0.32),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  Widget _buildDriverReceiptsTabletPortraitFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card12DriverReceiptsTabletPortraitAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][DRIVER_RECEIPTS_PORTRAIT_PNG_FAIL] '
              'error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(child: _buildDriverReceiptsTabletPortraitOverlay()),
      ],
    );
  }

  Widget _buildDriverReceiptsTabletLandscapeFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card12DriverReceiptsTabletLandscapeAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][DRIVER_RECEIPTS_LANDSCAPE_PNG_FAIL] '
              'error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(child: _buildDriverReceiptsTabletLandscapeOverlay()),
      ],
    );
  }

  Widget _buildDriverReceiptsTabletPortraitOverlay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        if (h <= w) {
          return const SizedBox.shrink();
        }

        const double titleLeft = 0.357;
        const double titleTop = 0.023;
        const double titleWidth = 0.625;
        const double titleHeight = 0.139;
        const double explainLeft = 0.016;
        const double explainTop = 0.200;
        const double explainWidth = 0.968;
        const double explainHeight = 0.293;

        return Stack(
          children: <Widget>[
            Positioned(
              left: w * titleLeft,
              top: h * titleTop,
              width: w * titleWidth,
              height: h * titleHeight,
              child: _buildDriverReceiptsTitlePanel(
                zoneWidth: w * titleWidth,
                zoneHeight: h * titleHeight,
                isPortrait: true,
              ),
            ),
            Positioned(
              left: w * explainLeft,
              top: h * explainTop,
              width: w * explainWidth,
              height: h * explainHeight,
              child: _buildDriverReceiptsExplanationPanel(
                zoneWidth: w * explainWidth,
                zoneHeight: h * explainHeight,
                isPortrait: true,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDriverReceiptsTabletLandscapeOverlay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        if (w <= h) {
          return const SizedBox.shrink();
        }

        const double titleLeft = 0.336;
        const double titleTop = 0.049;
        const double titleWidth = 0.647;
        const double titleHeight = 0.132;
        const double explainLeft = 0.010;
        const double explainTop = 0.411;
        const double explainWidth = 0.371;
        // Landscape only: pull the panel bottom up to ~0.851 of the
        // viewport (= 0.411 + 0.440) so it lands above the dots /
        // Previous / Next row (matching the approved Calculator
        // landscape safe bottom of ~0.852). Portrait frame ratios are
        // unchanged. The frozen-frame guidance still applies; this is
        // the explicit landscape overlap-fix amendment.
        const double explainHeight = 0.440;

        return Stack(
          children: <Widget>[
            Positioned(
              left: w * titleLeft,
              top: h * titleTop,
              width: w * titleWidth,
              height: h * titleHeight,
              child: _buildDriverReceiptsTitlePanel(
                zoneWidth: w * titleWidth,
                zoneHeight: h * titleHeight,
                isPortrait: false,
              ),
            ),
            Positioned(
              left: w * explainLeft,
              top: h * explainTop,
              width: w * explainWidth,
              height: h * explainHeight,
              child: _buildDriverReceiptsExplanationPanel(
                zoneWidth: w * explainWidth,
                zoneHeight: h * explainHeight,
                isPortrait: false,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDriverReceiptsTitlePanel({
    required double zoneWidth,
    required double zoneHeight,
    required bool isPortrait,
  }) {
    final double langScale = _driverReceiptsLangScale();
    final EdgeInsets padding = isPortrait
        ? const EdgeInsets.symmetric(horizontal: 18, vertical: 14)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
    final double titleSize = (isPortrait ? 30.0 : 28.0) * langScale;
    final double subtitleSize = (isPortrait ? 15.5 : 14.5) * langScale;
    final double accentToTitleGap = isPortrait ? 9.0 : 7.0;
    final double titleSubtitleGap = isPortrait ? 9.0 : 8.0;
    final double accentBarWidth = isPortrait ? 64.0 : 56.0;

    final Widget accentBar = Container(
      width: accentBarWidth,
      height: 3,
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.85),
        borderRadius: BorderRadius.circular(3),
        boxShadow: <BoxShadow>[
          BoxShadow(color: _gold.withOpacity(0.45), blurRadius: 10),
        ],
      ),
    );

    final Widget copy = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        accentBar,
        SizedBox(height: accentToTitleGap),
        Text(
          _t(_driverReceiptsTitle),
          softWrap: true,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: _gold,
            fontSize: titleSize,
            fontWeight: FontWeight.w900,
            height: 1.06,
            letterSpacing: 0.10,
            shadows: <Shadow>[
              Shadow(color: _gold.withOpacity(0.36), blurRadius: 14),
              Shadow(
                color: Colors.black.withOpacity(0.78),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        SizedBox(height: titleSubtitleGap),
        Text(
          _t(_driverReceiptsSubtitle),
          softWrap: true,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: Colors.white.withOpacity(0.90),
            fontSize: subtitleSize,
            fontWeight: FontWeight.w500,
            height: isPortrait ? 1.16 : 1.14,
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
    );

    return SizedBox(
      width: zoneWidth,
      height: zoneHeight,
      child: DecoratedBox(
        decoration: _driverReceiptsPanelDecoration(),
        child: Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // Stable block: mainAxisSize.min, no Expanded/Spacer/
              // spaceBetween/MainAxisAlignment.center under the outer
              // FittedBox's unbounded constraints. The whole-block
              // scale-down + centerLeft alignment vertically centers
              // the natural-sized title group inside the frozen frame.
              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: _driverReceiptsWholeBlockScaleDown(
                  maxWidth: constraints.maxWidth,
                  alignment: Alignment.centerLeft,
                  child: copy,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDriverReceiptsExplanationPanel({
    required double zoneWidth,
    required double zoneHeight,
    required bool isPortrait,
  }) {
    final double langScale = _driverReceiptsLangScale();
    // Portrait padding/gaps are the approved values. Landscape values
    // are tightened to keep the natural content height comfortable
    // inside the reduced landscape explanation frame (the landscape
    // explainHeight was pulled up to fix the overlap with the
    // dots / Previous / Next row).
    final EdgeInsets padding = isPortrait
        ? const EdgeInsets.fromLTRB(14, 14, 14, 14)
        : const EdgeInsets.fromLTRB(13, 12, 13, 12);
    final double eyebrowSize = (isPortrait ? 10.5 : 11.0) * langScale;
    final double headingSize = (isPortrait ? 20.0 : 21.5) * langScale;
    final double introSize = (isPortrait ? 14.0 : 14.5) * langScale;
    final double rowTitleSize = (isPortrait ? 15.0 : 15.5) * langScale;
    final double rowBodySize = (isPortrait ? 13.5 : 14.0) * langScale;
    final double closingSize = (isPortrait ? 13.0 : 13.5) * langScale;
    // Tuned so the natural content height fills most of the frozen
    // explanation frame and the centerLeft alignment of the whole-
    // block scale-down vertically centers any spare room. No
    // Expanded/Flexible/Spacer/spaceBetween anywhere inside the
    // FittedBox's unbounded subtree. Landscape gaps are smaller than
    // portrait because the landscape frame is shorter (overlap fix);
    // portrait values are the approved ones.
    final double eyebrowToHeadingGap = isPortrait ? 9.0 : 9.0;
    final double headingToIntroGap = isPortrait ? 7.0 : 7.0;
    final double introToFeaturesGap = isPortrait ? 14.0 : 12.0;
    final double rowGap = isPortrait ? 9.0 : 9.0;
    final double featuresToClosingGap = isPortrait ? 14.0 : 12.0;

    final Widget eyebrow = Align(
      alignment: Alignment.topLeft,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isPortrait ? 8 : 9,
          vertical: isPortrait ? 4 : 5,
        ),
        decoration: BoxDecoration(
          color: _gold.withOpacity(0.10),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _gold.withOpacity(0.26)),
        ),
        child: Text(
          _t(_driverReceiptsExplanationEyebrow),
          softWrap: true,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: _gold,
            fontSize: eyebrowSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.55,
            height: 1.12,
          ),
        ),
      ),
    );

    final Widget heading = Text(
      _t(_driverReceiptsExplanationHeading),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold,
        fontSize: headingSize,
        fontWeight: FontWeight.w900,
        height: 1.08,
        letterSpacing: 0.08,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final Widget intro = Text(
      _t(_driverReceiptsExplanationIntro),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: Colors.white.withOpacity(0.88),
        fontSize: introSize,
        fontWeight: FontWeight.w500,
        height: 1.16,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final Widget closing = Text(
      _t(_driverReceiptsExplanationClosing),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold.withOpacity(0.88),
        fontSize: closingSize,
        fontWeight: FontWeight.w700,
        height: 1.14,
        letterSpacing: 0.08,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    // Topical icons aligned with the three benefit rows so each row
    // reads as its own compact mini-card — Receipts / History /
    // Documents.
    const List<IconData> featureIcons = <IconData>[
      Icons.receipt_long_rounded,
      Icons.history_rounded,
      Icons.folder_open_rounded,
    ];

    final List<Widget> featureRows = <Widget>[
      for (int i = 0; i < _driverReceiptsExplanationFeatures.length; i++)
        _buildDriverReceiptsExplanationFeatureRow(
          _driverReceiptsExplanationFeatures[i],
          icon: featureIcons[i % featureIcons.length],
          titleSize: rowTitleSize,
          bodySize: rowBodySize,
          compact: isPortrait,
        ),
    ];

    return SizedBox(
      width: zoneWidth,
      height: zoneHeight,
      child: DecoratedBox(
        decoration: _driverReceiptsPanelDecoration(),
        child: Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // Stable block: single mainAxisSize.min Column, fixed
              // SizedBox gaps only. No Expanded/Flexible/Spacer/
              // spaceBetween under the outer FittedBox's unbounded
              // constraints. Content rhythm is achieved by tuned
              // inter-section gaps; the whole-block scale-down with
              // centerLeft alignment then vertically centers the
              // resulting block inside the frozen panel frame so
              // breathing space sits both above and below the copy
              // instead of all stacking at the top.
              final List<Widget> spacedFeatureRows = <Widget>[];
              for (int i = 0; i < featureRows.length; i++) {
                if (i > 0) {
                  spacedFeatureRows.add(SizedBox(height: rowGap));
                }
                spacedFeatureRows.add(featureRows[i]);
              }

              final Widget composedPanel = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  eyebrow,
                  SizedBox(height: eyebrowToHeadingGap),
                  heading,
                  SizedBox(height: headingToIntroGap),
                  intro,
                  SizedBox(height: introToFeaturesGap),
                  ...spacedFeatureRows,
                  SizedBox(height: featuresToClosingGap),
                  closing,
                ],
              );

              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: _driverReceiptsWholeBlockScaleDown(
                  maxWidth: constraints.maxWidth,
                  alignment: Alignment.centerLeft,
                  child: composedPanel,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDriverReceiptsExplanationFeatureRow(
    _OrientationBulletItem feature, {
    required IconData icon,
    required double titleSize,
    required double bodySize,
    required bool compact,
  }) {
    final double iconBox = compact ? 30.0 : 32.0;
    final double iconSize = compact ? 16.0 : 18.0;
    // Portrait (compact) keeps the approved 8 px vertical padding.
    // Landscape uses 7 px so each mini-card is a touch shorter and
    // the three rows fit comfortably inside the reduced landscape
    // explanation frame without leaning on the FittedBox safety net.
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 10,
        vertical: compact ? 8 : 7,
      ),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _gold.withOpacity(0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: iconBox,
            height: iconBox,
            decoration: BoxDecoration(
              color: _gold.withOpacity(0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _gold.withOpacity(0.36)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: _gold.withOpacity(0.20),
                  blurRadius: 8,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: _gold, size: iconSize),
          ),
          SizedBox(width: compact ? 9 : 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _t(feature.title),
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    color: _gold,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w800,
                    height: 1.06,
                    shadows: const <Shadow>[
                      Shadow(
                        color: Color(0xCC000000),
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: compact ? 2 : 3),
                Text(
                  _t(feature.description),
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.86),
                    fontSize: bodySize,
                    fontWeight: FontWeight.w500,
                    height: 1.12,
                    shadows: const <Shadow>[
                      Shadow(
                        color: Color(0xCC000000),
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =================================================================
  // Card 15 — Activate customers (bespoke tablet heroes).
  //
  // Card13 artwork carries the customer-app visual; Flutter overlays
  // one measured premium content block in the dark safe frame only.
  // The logo/tablet areas are intentionally left to the asset.
  //
  // LANDSCAPE text frame:
  //   left 0.012, top 0.365, width 0.414, height 0.528
  // PORTRAIT text frame:
  //   left 0.020, top 0.202, width 0.333, height 0.706
  // =================================================================

  double _activateCustomersLangScale() {
    switch (appLanguageNotifier.value) {
      case AppLanguage.fr:
      case AppLanguage.es:
        return 0.92;
      case AppLanguage.nl:
      case AppLanguage.en:
      case AppLanguage.de:
        return 1.0;
    }
  }

  Widget _activateCustomersWholeBlockScaleDown({
    required double maxWidth,
    required Widget child,
    Alignment alignment = Alignment.centerLeft,
  }) {
    return Align(
      alignment: alignment,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: SizedBox(width: maxWidth, child: child),
      ),
    );
  }

  BoxDecoration _activateCustomersPanelDecoration() {
    return BoxDecoration(
      color: Colors.black.withOpacity(0.56),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _gold.withOpacity(0.24)),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withOpacity(0.34),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  Widget _buildActivateCustomersTabletPortraitFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card13ActivateCustomersTabletPortraitAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][ACTIVATE_CUSTOMERS_PORTRAIT_PNG_FAIL] '
              'error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(child: _buildActivateCustomersTabletOverlay()),
      ],
    );
  }

  Widget _buildActivateCustomersTabletLandscapeFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card13ActivateCustomersTabletLandscapeAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][ACTIVATE_CUSTOMERS_LANDSCAPE_PNG_FAIL] '
              'error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(child: _buildActivateCustomersTabletOverlay()),
      ],
    );
  }

  Widget _buildActivateCustomersTabletOverlay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        final bool isPortrait = h > w;

        final double frameLeft = isPortrait ? 0.020 : 0.012;
        final double frameTop = isPortrait ? 0.202 : 0.360;
        final double frameWidth = isPortrait ? 0.333 : 0.414;
        final double frameHeight = isPortrait ? 0.706 : 0.455;

        return Stack(
          children: <Widget>[
            Positioned(
              left: w * frameLeft,
              top: h * frameTop,
              width: w * frameWidth,
              height: h * frameHeight,
              child: _buildActivateCustomersPanel(
                zoneWidth: w * frameWidth,
                zoneHeight: h * frameHeight,
                isPortrait: isPortrait,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActivateCustomersPanel({
    required double zoneWidth,
    required double zoneHeight,
    required bool isPortrait,
  }) {
    final double langScale = _activateCustomersLangScale();
    final EdgeInsets padding = isPortrait
        ? const EdgeInsets.fromLTRB(14, 16, 14, 16)
        : const EdgeInsets.fromLTRB(15, 10, 15, 10);
    final double eyebrowSize = (isPortrait ? 10.0 : 10.5) * langScale;
    final double titleSize = (isPortrait ? 23.0 : 25.0) * langScale;
    final double introSize = (isPortrait ? 13.0 : 13.5) * langScale;
    final double rowTitleSize = (isPortrait ? 13.4 : 14.0) * langScale;
    final double rowBodySize = (isPortrait ? 11.6 : 12.1) * langScale;
    final double closingSize = (isPortrait ? 12.1 : 12.6) * langScale;
    final double eyebrowToTitleGap = isPortrait ? 9.0 : 7.0;
    final double titleToIntroGap = isPortrait ? 9.0 : 6.0;
    final double introToRowsGap = isPortrait ? 15.0 : 9.0;
    final double rowGap = isPortrait ? 9.0 : 6.0;
    final double rowsToClosingGap = isPortrait ? 15.0 : 9.0;

    final Widget eyebrow = Align(
      alignment: Alignment.topLeft,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isPortrait ? 8 : 9,
          vertical: isPortrait ? 4 : 5,
        ),
        decoration: BoxDecoration(
          color: _gold.withOpacity(0.10),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _gold.withOpacity(0.26)),
        ),
        child: Text(
          _t(_activateCustomersEyebrow),
          softWrap: true,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: _gold,
            fontSize: eyebrowSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.55,
            height: 1.12,
          ),
        ),
      ),
    );

    final Widget title = Text(
      _t(_activateCustomersTitle),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold,
        fontSize: titleSize,
        fontWeight: FontWeight.w900,
        height: 1.08,
        letterSpacing: 0.08,
        shadows: <Shadow>[
          Shadow(color: _gold.withOpacity(0.30), blurRadius: 12),
          const Shadow(
            color: Color(0xCC000000),
            blurRadius: 7,
            offset: Offset(0, 1),
          ),
        ],
      ),
    );

    final Widget intro = Text(
      _t(_activateCustomersIntro),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: Colors.white.withOpacity(0.88),
        fontSize: introSize,
        fontWeight: FontWeight.w500,
        height: 1.18,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    final Widget closing = Text(
      _t(_activateCustomersClosing),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold.withOpacity(0.90),
        fontSize: closingSize,
        fontWeight: FontWeight.w800,
        height: 1.15,
        letterSpacing: 0.08,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );

    const List<IconData> benefitIcons = <IconData>[
      Icons.explore_rounded,
      Icons.verified_user_rounded,
      Icons.replay_rounded,
      Icons.public_rounded,
    ];

    final List<Widget> benefitRows = <Widget>[
      for (int i = 0; i < _activateCustomersBenefits.length; i++)
        _buildActivateCustomersBenefitRow(
          _activateCustomersBenefits[i],
          icon: benefitIcons[i % benefitIcons.length],
          titleSize: rowTitleSize,
          bodySize: rowBodySize,
          compact: isPortrait,
        ),
    ];

    return SizedBox(
      width: zoneWidth,
      height: zoneHeight,
      child: DecoratedBox(
        decoration: _activateCustomersPanelDecoration(),
        child: Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final List<Widget> spacedBenefitRows = <Widget>[];
              for (int i = 0; i < benefitRows.length; i++) {
                if (i > 0) {
                  spacedBenefitRows.add(SizedBox(height: rowGap));
                }
                spacedBenefitRows.add(benefitRows[i]);
              }

              final Widget composedPanel = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  eyebrow,
                  SizedBox(height: eyebrowToTitleGap),
                  title,
                  SizedBox(height: titleToIntroGap),
                  intro,
                  SizedBox(height: introToRowsGap),
                  ...spacedBenefitRows,
                  SizedBox(height: rowsToClosingGap),
                  closing,
                ],
              );

              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: _activateCustomersWholeBlockScaleDown(
                  maxWidth: constraints.maxWidth,
                  alignment: Alignment.centerLeft,
                  child: composedPanel,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildActivateCustomersBenefitRow(
    _OrientationBulletItem benefit, {
    required IconData icon,
    required double titleSize,
    required double bodySize,
    required bool compact,
  }) {
    final double iconBox = compact ? 28.0 : 30.0;
    final double iconSize = compact ? 15.0 : 17.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 9,
        vertical: compact ? 7 : 5,
      ),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _gold.withOpacity(0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: iconBox,
            height: iconBox,
            decoration: BoxDecoration(
              color: _gold.withOpacity(0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _gold.withOpacity(0.36)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: _gold.withOpacity(0.20),
                  blurRadius: 8,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: _gold, size: iconSize),
          ),
          SizedBox(width: compact ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _t(benefit.title),
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    color: _gold,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w800,
                    height: 1.06,
                    shadows: const <Shadow>[
                      Shadow(
                        color: Color(0xCC000000),
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: compact ? 2 : 3),
                Text(
                  _t(benefit.description),
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.86),
                    fontSize: bodySize,
                    fontWeight: FontWeight.w500,
                    height: 1.12,
                    shadows: const <Shadow>[
                      Shadow(
                        color: Color(0xCC000000),
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
      case AppLanguage.de:
        return 1.0;
    }
  }

  // =================================================================
  // Slide 4 — Settings & company profile: the Fluxidi "settings
  // engine" / business control center (bespoke tablet heroes).
  //
  // The card14 settings/cockpit artwork is rendered full-bleed and ALL
  // copy is overlaid by Flutter inside the measured safe zones. Two
  // coherent dark-glass panels (title + explanation) are the only
  // painted chrome; each panel uses exactly one whole-block
  // FittedBox(scaleDown) as its overflow safety net.
  //
  // PORTRAIT title frame (frozen):
  //   left 0.3653, top 0.0244, width 0.6112, height 0.1519
  // PORTRAIT explanation frame (frozen):
  //   left 0.0117, top 0.2012, width 0.9742, height 0.3179
  // LANDSCAPE title frame (frozen):
  //   left 0.3638, top 0.0422, width 0.6035, height 0.1920
  // LANDSCAPE explanation frame (frozen):
  //   left 0.0107, top 0.3646, width 0.3457, height 0.5488
  // =================================================================

  double _settingsProfileLangScale() {
    switch (appLanguageNotifier.value) {
      case AppLanguage.fr:
      case AppLanguage.es:
        return 0.90;
      case AppLanguage.nl:
        return 0.95;
      case AppLanguage.en:
      case AppLanguage.de:
        return 1.0;
    }
  }

  /// One whole-block scale-down safety net for a settings panel. The
  /// inner [SizedBox] fixes only the width to the available zone width
  /// so the natural (min-height) column can grow taller than the zone
  /// and the single [FittedBox] scales the WHOLE block down — never
  /// per-line, never per-sentence. Vertically centred so the balanced
  /// block fills the frame instead of hugging the top edge.
  Widget _settingsProfileWholeBlockScaleDown({
    required double zoneWidth,
    required Widget child,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: SizedBox(width: zoneWidth, child: child),
      ),
    );
  }

  Widget _buildSettingsProfileTabletPortraitFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _settingsProfileTabletPortraitAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][SETTINGS_PROFILE_PORTRAIT_PNG_FAIL] '
              'error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(
          child: _buildSettingsProfileTabletOverlay(isPortrait: true),
        ),
      ],
    );
  }

  Widget _buildSettingsProfileTabletLandscapeFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _settingsProfileTabletLandscapeAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][SETTINGS_PROFILE_LANDSCAPE_PNG_FAIL] '
              'error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(
          child: _buildSettingsProfileTabletOverlay(isPortrait: false),
        ),
      ],
    );
  }

  Widget _buildSettingsProfileTabletOverlay({required bool isPortrait}) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        if (isPortrait ? h <= w : w <= h) {
          return const SizedBox.shrink();
        }

        // Frozen, measured safe frames (fractions of the full viewport
        // so they line up exactly with the full-bleed card14 artwork).
        final double titleLeft = isPortrait ? 0.3653 : 0.3638;
        final double titleTop = isPortrait ? 0.0244 : 0.0422;
        final double titleWidth = isPortrait ? 0.6112 : 0.6035;
        final double titleHeight = isPortrait ? 0.1519 : 0.1920;
        final double explainLeft = isPortrait ? 0.0117 : 0.0107;
        final double explainTop = isPortrait ? 0.2012 : 0.3646;
        final double explainWidth = isPortrait ? 0.9742 : 0.3457;
        final double explainHeight = isPortrait ? 0.3179 : 0.5488;

        return Stack(
          children: <Widget>[
            Positioned(
              left: w * titleLeft,
              top: h * titleTop,
              width: w * titleWidth,
              height: h * titleHeight,
              child: _buildSettingsProfileTitlePanel(isPortrait: isPortrait),
            ),
            Positioned(
              left: w * explainLeft,
              top: h * explainTop,
              width: w * explainWidth,
              height: h * explainHeight,
              child: _buildSettingsProfileExplanationPanel(
                isPortrait: isPortrait,
              ),
            ),
          ],
        );
      },
    );
  }

  BoxDecoration _settingsProfilePanelDecoration({required bool prominent}) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Colors.black.withOpacity(prominent ? 0.60 : 0.52),
          Colors.black.withOpacity(prominent ? 0.46 : 0.40),
        ],
      ),
      borderRadius: BorderRadius.circular(prominent ? 18 : 16),
      border: Border.all(color: _gold.withOpacity(prominent ? 0.30 : 0.24)),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withOpacity(0.36),
          blurRadius: 18,
          offset: const Offset(0, 5),
        ),
        BoxShadow(
          color: _gold.withOpacity(0.06),
          blurRadius: 24,
          spreadRadius: 1,
        ),
      ],
    );
  }

  Widget _buildSettingsProfileTitlePanel({required bool isPortrait}) {
    final double scale = _settingsProfileLangScale();
    final EdgeInsets padding = isPortrait
        ? const EdgeInsets.fromLTRB(26, 18, 26, 18)
        : const EdgeInsets.fromLTRB(26, 16, 26, 16);
    final double titleSize = (isPortrait ? 33.0 : 38.0) * scale;
    final double introSize = (isPortrait ? 17.5 : 19.5) * scale;

    return DecoratedBox(
      decoration: _settingsProfilePanelDecoration(prominent: false),
      child: Padding(
        padding: padding,
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            return _settingsProfileWholeBlockScaleDown(
              zoneWidth: constraints.maxWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _t(_settingsProfileTopTitle),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: _gold,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w900,
                      height: 1.04,
                      letterSpacing: 0.12,
                      shadows: <Shadow>[
                        Shadow(color: _gold.withOpacity(0.36), blurRadius: 14),
                        Shadow(
                          color: Colors.black.withOpacity(0.78),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: isPortrait ? 9 : 10),
                  Text(
                    _t(_settingsProfileTopIntro),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.92),
                      fontSize: introSize,
                      fontWeight: FontWeight.w500,
                      height: 1.20,
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildSettingsProfileExplanationPanel({required bool isPortrait}) {
    final double scale = _settingsProfileLangScale();
    final EdgeInsets padding = isPortrait
        ? const EdgeInsets.fromLTRB(28, 24, 28, 24)
        : const EdgeInsets.fromLTRB(24, 22, 24, 22);
    final double labelSize = (isPortrait ? 11.5 : 11.0) * scale;
    final double titleSize = (isPortrait ? 27.0 : 25.0) * scale;
    final double bodySize = (isPortrait ? 16.0 : 16.0) * scale;
    final double featureTitleSize = (isPortrait ? 15.5 : 15.0) * scale;
    final double featureBodySize = (isPortrait ? 13.8 : 13.5) * scale;
    final double iconSize = (isPortrait ? 21.0 : 20.0) * scale;
    final double footerSize = (isPortrait ? 15.0 : 14.5) * scale;

    return DecoratedBox(
      decoration: _settingsProfilePanelDecoration(prominent: true),
      child: Padding(
        padding: padding,
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final double innerWidth = constraints.maxWidth;
            return _settingsProfileWholeBlockScaleDown(
              zoneWidth: innerWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _buildSettingsProfileLabel(labelSize),
                  SizedBox(height: isPortrait ? 12 : 12),
                  _buildSettingsProfileMainTitle(titleSize),
                  SizedBox(height: isPortrait ? 10 : 10),
                  _buildSettingsProfileBody(bodySize),
                  SizedBox(height: isPortrait ? 16 : 16),
                  isPortrait
                      ? _buildSettingsProfileFeatureGrid(
                          innerWidth: innerWidth,
                          titleSize: featureTitleSize,
                          bodySize: featureBodySize,
                          iconSize: iconSize,
                        )
                      : _buildSettingsProfileFeatureList(
                          titleSize: featureTitleSize,
                          bodySize: featureBodySize,
                          iconSize: iconSize,
                        ),
                  SizedBox(height: isPortrait ? 16 : 16),
                  Container(height: 1, color: _gold.withOpacity(0.20)),
                  SizedBox(height: isPortrait ? 12 : 12),
                  _buildSettingsProfileFooter(footerSize),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Landscape: vertical list of 4 compact feature rows (the
  /// explanation frame is narrow and tall).
  Widget _buildSettingsProfileFeatureList({
    required double titleSize,
    required double bodySize,
    required double iconSize,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < _settingsProfileFeatures.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
            child: _buildSettingsProfileFeatureCell(
              _settingsProfileFeatures[i],
              titleSize: titleSize,
              bodySize: bodySize,
              iconSize: iconSize,
            ),
          ),
      ],
    );
  }

  /// Portrait: compact 2x2 feature grid (the explanation frame is wide
  /// and short).
  Widget _buildSettingsProfileFeatureGrid({
    required double innerWidth,
    required double titleSize,
    required double bodySize,
    required double iconSize,
  }) {
    const double columnGap = 22;
    const double rowGap = 16;
    final double cellWidth = (innerWidth - columnGap) / 2;
    Widget cell(int index) => _buildSettingsProfileFeatureCell(
      _settingsProfileFeatures[index],
      titleSize: titleSize,
      bodySize: bodySize,
      iconSize: iconSize,
      width: cellWidth,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            cell(0),
            const SizedBox(width: columnGap),
            cell(1),
          ],
        ),
        const SizedBox(height: rowGap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            cell(2),
            const SizedBox(width: columnGap),
            cell(3),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingsProfileFeatureCell(
    _SettingsProfileFeature feature, {
    required double titleSize,
    required double bodySize,
    required double iconSize,
    double? width,
  }) {
    final Widget content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: EdgeInsets.all(iconSize * 0.32),
          decoration: BoxDecoration(
            color: _gold.withOpacity(0.12),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _gold.withOpacity(0.30)),
          ),
          child: Icon(feature.icon, size: iconSize, color: _gold),
        ),
        SizedBox(width: iconSize * 0.6),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _t(feature.title),
                softWrap: true,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  color: _gold,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                  shadows: const <Shadow>[
                    Shadow(
                      color: Color(0xCC000000),
                      blurRadius: 6,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _t(feature.description),
                softWrap: true,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.88),
                  fontSize: bodySize,
                  fontWeight: FontWeight.w500,
                  height: 1.14,
                  shadows: const <Shadow>[
                    Shadow(
                      color: Color(0xCC000000),
                      blurRadius: 6,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (width == null) {
      return content;
    }
    return SizedBox(width: width, child: content);
  }

  Widget _buildSettingsProfileLabel(double fontSize) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _gold.withOpacity(0.30)),
      ),
      child: Text(
        _t(_settingsProfileLabel),
        softWrap: true,
        overflow: TextOverflow.visible,
        style: TextStyle(
          color: _gold,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1.0,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildSettingsProfileMainTitle(double fontSize) {
    return Text(
      _t(_settingsProfileMainTitle),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold,
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        height: 1.08,
        shadows: <Shadow>[
          Shadow(color: _gold.withOpacity(0.28), blurRadius: 12),
          const Shadow(
            color: Color(0xCC000000),
            blurRadius: 7,
            offset: Offset(0, 1),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsProfileBody(double fontSize) {
    return Text(
      _t(_settingsProfileBody),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: Colors.white.withOpacity(0.90),
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        height: 1.22,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 7, offset: Offset(0, 1)),
        ],
      ),
    );
  }

  Widget _buildSettingsProfileFooter(double fontSize) {
    return Text(
      _t(_settingsProfileFooter),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        height: 1.16,
        letterSpacing: 0.05,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 7, offset: Offset(0, 1)),
        ],
      ),
    );
  }

  // =================================================================
  // Slide 5 — Themes & branding: interactive Fluxidi Theme Showroom.
  //
  // A foreground (NOT full-viewport-hero) interactive card so the
  // in-preview left/right arrows receive taps. The tablet mockup is the
  // hero element; left/right arrows + dots cycle [_themeShowroomIndex]
  // (plain int state, no nested PageView / swipe carousel) and the
  // preview cross-fades via [AnimatedSwitcher]. Two coherent dark-glass
  // panels (title + explanation) accompany the preview.
  // =================================================================

  double _themesLangScale() {
    switch (appLanguageNotifier.value) {
      case AppLanguage.fr:
      case AppLanguage.es:
        return 0.92;
      case AppLanguage.nl:
        return 0.96;
      case AppLanguage.en:
      case AppLanguage.de:
        return 1.0;
    }
  }

  Widget _buildThemesBrandingCard(
    _OrientationCardData data,
    bool compact, {
    required bool isTabletPortrait,
    required bool isTabletLandscape,
  }) {
    if (isTabletLandscape) {
      return _buildThemesShowroomTabletLandscape();
    }
    if (isTabletPortrait) {
      return _buildThemesShowroomTabletPortrait();
    }
    return _buildThemesShowroomPhone(compact);
  }

  Widget _buildThemesShowroomTabletLandscape() {
    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              flex: 44,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildThemesTitlePanel(isPortrait: false),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _buildThemesExplanationPanel(isPortrait: false),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 22),
            Expanded(
              flex: 56,
              child: _buildThemesHeroPreviewArea(
                buildPreview: (BoxConstraints constraints) =>
                    _buildThemesPreview(
                      maxWidth: constraints.maxWidth,
                      maxHeight: constraints.maxHeight,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemesShowroomTabletPortrait() {
    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildThemesTitlePanel(isPortrait: true),
            const SizedBox(height: 14),
            Expanded(
              child: _buildThemesHeroPreviewArea(
                buildPreview: (BoxConstraints constraints) =>
                    _buildThemesPreview(
                      maxWidth: constraints.maxWidth,
                      maxHeight: constraints.maxHeight,
                    ),
              ),
            ),
            const SizedBox(height: 14),
            _buildThemesExplanationPanel(isPortrait: true),
          ],
        ),
      ),
    );
  }

  Widget _buildThemesShowroomPhone(bool compact) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(18, compact ? 8 : 14, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildThemesTitlePanel(isPortrait: true),
          const SizedBox(height: 14),
          SizedBox(
            height: compact ? 360 : 480,
            child: _buildThemesHeroPreviewArea(
              buildPreview: (BoxConstraints constraints) => _buildThemesPreview(
                maxWidth: constraints.maxWidth,
                maxHeight: constraints.maxHeight,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _buildThemesExplanationPanel(isPortrait: true),
        ],
      ),
    );
  }

  /// Cinematic hero zone behind the interactive tablet preview on Card
  /// 5. Layers, bottom → top:
  ///   1. [_themesShowroomHeroBgAsset] — full-bleed [BoxFit.cover]
  ///      backdrop, centered. A silent [errorBuilder] keeps the area
  ///      black if the asset is missing rather than throwing.
  ///   2. A soft top→bottom dark wash so the floating tablet stays
  ///      legible regardless of the underlying artwork.
  ///   3. The existing vertical Samsung-style tablet preview produced by
  ///      [buildPreview], centered. The preview itself is unchanged —
  ///      same arrows, dots, caption, [AnimatedSwitcher], and
  ///      [_themeShowroomIndex] state.
  Widget _buildThemesHeroPreviewArea({
    required Widget Function(BoxConstraints constraints) buildPreview,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _themesShowroomHeroBgAsset,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stackTrace) {
                debugPrint(
                  '[ORIENTATION_FLOW][THEME_HERO_BG_FAIL] '
                  'asset=$_themesShowroomHeroBgAsset error=$error',
                );
                return const SizedBox.shrink();
              },
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.black.withOpacity(0.18),
                Colors.black.withOpacity(0.52),
              ],
            ),
          ),
        ),
        LayoutBuilder(
          builder: (BuildContext ctx, BoxConstraints constraints) {
            return Center(child: buildPreview(constraints));
          },
        ),
      ],
    );
  }

  /// Real Samsung-tablet portrait screenshot proportions (1752 × 2800).
  /// The mockup frame is sized to this ratio so vertical screenshots are
  /// never stretched into a landscape box.
  static const double _themesTabletAspect = 1752.0 / 2800.0;

  /// The fixed, vertical (portrait) tablet/mockup preview — the hero of
  /// Card 5. Sizes a tall device frame from [_themesTabletAspect] inside
  /// the available [maxWidth] × [maxHeight] box, paints a black bezel
  /// with an accent-tinted border + glow, and renders the active
  /// screenshot with a direct [Image.asset] ([BoxFit.contain], so the
  /// real screenshot is always visible and never cropped). A visible
  /// "Missing theme asset" panel replaces silent black if an asset fails
  /// to load. Left/right arrows + caption/dots overlay the frame.
  Widget _buildThemesPreview({
    required double maxWidth,
    required double maxHeight,
  }) {
    final _ThemeShowroomItem item = _themeShowroomItems[_themeShowroomIndex];
    final Color accent = item.accentColor;

    // Height-first: make the vertical tablet as tall as the box allows,
    // then clamp by width so it never overflows horizontally.
    double frameH = maxHeight;
    double frameW = frameH * _themesTabletAspect;
    if (frameW > maxWidth) {
      frameW = maxWidth;
      frameH = frameW / _themesTabletAspect;
    }

    return SizedBox(
      width: frameW,
      height: frameH,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          // Bezel + accent glow (back layer).
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: const Color(0xFF050505),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: accent.withOpacity(0.60), width: 2),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: accent.withOpacity(0.34),
                    blurRadius: 40,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.50),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
            ),
          ),
          // Screen — direct Image.asset so the screenshot always renders.
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: FluxidiDecodeSizedAssetImage(
                    item.assetPath,
                    key: ValueKey<String>(item.assetPath),
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder:
                        (
                          BuildContext context,
                          Object error,
                          StackTrace? stackTrace,
                        ) {
                          debugPrint(
                            '[ORIENTATION_FLOW][THEME_PREVIEW_FAIL] '
                            'asset=${item.assetPath} error=$error',
                          );
                          return _buildThemesPreviewMissing(item, accent);
                        },
                  ),
                ),
              ),
            ),
          ),
          // Left / right arrows — update _themeShowroomIndex only.
          Positioned(
            left: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: _buildThemesArrow(
                Icons.chevron_left,
                _themeShowroomPrev,
                accent,
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: _buildThemesArrow(
                Icons.chevron_right,
                _themeShowroomNext,
                accent,
              ),
            ),
          ),
          // Caption pill + dots inside the bottom of the frame.
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: _buildThemesPreviewCaption(item, accent),
          ),
        ],
      ),
    );
  }

  /// Visible fallback shown inside the tablet screen when a theme
  /// screenshot fails to load — never leaves the preview silently black.
  Widget _buildThemesPreviewMissing(_ThemeShowroomItem item, Color accent) {
    return Container(
      key: ValueKey<String>('missing-${item.assetPath}'),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1206),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.45)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.broken_image_outlined, color: _gold, size: 34),
          const SizedBox(height: 10),
          const Text(
            'Missing theme asset',
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              color: _gold,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.assetPath,
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              color: Colors.white.withOpacity(0.70),
              fontSize: 11,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemesArrow(IconData icon, VoidCallback onTap, Color accent) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withOpacity(0.55),
            border: Border.all(color: accent.withOpacity(0.70), width: 1.5),
            boxShadow: <BoxShadow>[
              BoxShadow(color: Colors.black.withOpacity(0.50), blurRadius: 10),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }

  Widget _buildThemesPreviewCaption(_ThemeShowroomItem item, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.60),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.45)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: accent.withOpacity(0.6),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: RichText(
                  textAlign: TextAlign.center,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  text: TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: item.title,
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      TextSpan(
                        text: '  ·  ${_t(item.category)}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.90),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildThemesDots(accent),
        ],
      ),
    );
  }

  Widget _buildThemesDots(Color accent) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < _themeShowroomItems.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _themeShowroomIndex ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == _themeShowroomIndex
                  ? accent
                  : Colors.white.withOpacity(0.28),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }

  BoxDecoration _themesPanelDecoration({required bool prominent}) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Colors.black.withOpacity(prominent ? 0.60 : 0.52),
          Colors.black.withOpacity(prominent ? 0.46 : 0.40),
        ],
      ),
      borderRadius: BorderRadius.circular(prominent ? 18 : 16),
      border: Border.all(color: _gold.withOpacity(prominent ? 0.30 : 0.24)),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withOpacity(0.36),
          blurRadius: 18,
          offset: const Offset(0, 5),
        ),
        BoxShadow(
          color: _gold.withOpacity(0.06),
          blurRadius: 24,
          spreadRadius: 1,
        ),
      ],
    );
  }

  Widget _buildThemesTitlePanel({required bool isPortrait}) {
    final double scale = _themesLangScale();
    final EdgeInsets padding = isPortrait
        ? const EdgeInsets.fromLTRB(24, 18, 24, 18)
        : const EdgeInsets.fromLTRB(22, 16, 22, 16);
    final double titleSize = (isPortrait ? 31.0 : 27.0) * scale;
    final double introSize = (isPortrait ? 16.5 : 15.5) * scale;

    return DecoratedBox(
      decoration: _themesPanelDecoration(prominent: false),
      child: Padding(
        padding: padding,
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            return _settingsProfileWholeBlockScaleDown(
              zoneWidth: constraints.maxWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _t(_themesTitle),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: _gold,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w900,
                      height: 1.04,
                      letterSpacing: 0.12,
                      shadows: <Shadow>[
                        Shadow(color: _gold.withOpacity(0.36), blurRadius: 14),
                        Shadow(
                          color: Colors.black.withOpacity(0.78),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: isPortrait ? 9 : 8),
                  Text(
                    _t(_themesIntro),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.92),
                      fontSize: introSize,
                      fontWeight: FontWeight.w500,
                      height: 1.20,
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildThemesExplanationPanel({required bool isPortrait}) {
    final double scale = _themesLangScale();
    final EdgeInsets padding = isPortrait
        ? const EdgeInsets.fromLTRB(24, 20, 24, 20)
        : const EdgeInsets.fromLTRB(20, 18, 20, 18);
    final double labelSize = (isPortrait ? 11.5 : 11.0) * scale;
    final double titleSize = (isPortrait ? 24.0 : 21.0) * scale;
    final double bodySize = (isPortrait ? 15.5 : 14.5) * scale;
    final double featureTitleSize = (isPortrait ? 15.0 : 14.5) * scale;
    final double featureBodySize = (isPortrait ? 13.5 : 13.0) * scale;
    final double iconSize = (isPortrait ? 20.0 : 19.0) * scale;
    final double footerSize = (isPortrait ? 14.5 : 14.0) * scale;

    return DecoratedBox(
      decoration: _themesPanelDecoration(prominent: true),
      child: Padding(
        padding: padding,
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            return _settingsProfileWholeBlockScaleDown(
              zoneWidth: constraints.maxWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _buildThemesLabelPill(labelSize),
                  const SizedBox(height: 12),
                  Text(
                    _t(_themesMainTitle),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: _gold,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                      shadows: <Shadow>[
                        Shadow(color: _gold.withOpacity(0.28), blurRadius: 12),
                        const Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 7,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _t(_themesBody),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.90),
                      fontSize: bodySize,
                      fontWeight: FontWeight.w500,
                      height: 1.22,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 7,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (int i = 0; i < _themesFeatures.length; i++)
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                      child: _buildSettingsProfileFeatureCell(
                        _themesFeatures[i],
                        titleSize: featureTitleSize,
                        bodySize: featureBodySize,
                        iconSize: iconSize,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Container(height: 1, color: _gold.withOpacity(0.20)),
                  const SizedBox(height: 12),
                  Text(
                    _t(_themesFooter),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: _gold,
                      fontSize: footerSize,
                      fontWeight: FontWeight.w800,
                      height: 1.16,
                      letterSpacing: 0.05,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 7,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildThemesLabelPill(double fontSize) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _gold.withOpacity(0.30)),
      ),
      child: Text(
        _t(_themesLabel),
        softWrap: true,
        overflow: TextOverflow.visible,
        style: TextStyle(
          color: _gold,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1.0,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  // =================================================================
  // Card 4 — Vehicles & fleet management (bespoke tablet heroes).
  //
  // Both orientations paint the dedicated card4 PNG full-bleed
  // ([BoxFit.fill], matching Card 3) behind the Stack and overlay only
  // the localised title + intro with Flutter — the vehicle screenshot
  // is baked into the artwork, never re-rendered here.
  //
  // First controlled step: title + intro ONLY (no bullets / feature
  // list yet). The title + intro sit in the empty background area
  // ABOVE the screenshot; the whole column is wrapped in a
  // [FittedBox] scale-down safety net so the longest NL/FR/ES copy
  // can never raise a yellow/black overflow band.
  // =================================================================

  /// Per-language down-scale for the longer FR/ES Card 4 copy so the
  /// responsive sizes already land smaller before the [FittedBox]
  /// safety net ever has to engage.
  double _card4LangFontScale() {
    switch (appLanguageNotifier.value) {
      case AppLanguage.fr:
      case AppLanguage.es:
        return 0.92;
      case AppLanguage.nl:
      case AppLanguage.en:
      case AppLanguage.de:
        return 1.0;
    }
  }

  Widget _buildVehiclesFleetTabletLandscapeFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card4VehiclesFleetTabletLandscapeAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][CARD4_LANDSCAPE_PNG_FAIL] error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(
          child: _buildVehiclesFleetTabletOverlay(isPortrait: false),
        ),
      ],
    );
  }

  Widget _buildVehiclesFleetTabletPortraitFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card4VehiclesFleetTabletPortraitAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][CARD4_PORTRAIT_PNG_FAIL] error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(
          child: _buildVehiclesFleetTabletOverlay(isPortrait: true),
        ),
      ],
    );
  }

  /// Title + intro overlay for Card 4, positioned in the empty
  /// background area ABOVE the baked-in vehicle screenshot. Zones are
  /// expressed as fractions of the FULL viewport so they line up with
  /// the full-bleed background asset.
  Widget _buildVehiclesFleetTabletOverlay({required bool isPortrait}) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        // The hero is only mounted by [build] on tablets in the
        // matching orientation, so a plain orientation guard keeps the
        // overlay in lock-step with the hero across tablet sizes.
        if (isPortrait ? h <= w : w <= h) {
          return const SizedBox.shrink();
        }

        // Title + intro zone — a strong hero block in the empty
        // black/gold background space ABOVE the baked-in vehicle
        // screenshot. Easy to tweak per orientation as named local
        // constants.
        final double titleLeft = isPortrait ? 0.365 : 0.405;
        final double titleTop = isPortrait ? 0.050 : 0.031;
        final double titleWidth = isPortrait ? 0.585 : 0.520;
        final double titleHeight = isPortrait ? 0.125 : 0.150;
        final double panelLeft = isPortrait ? 0.025 : 0.030;
        final double panelTop = isPortrait ? 0.280 : 0.405;
        final double panelWidth = isPortrait ? 0.250 : 0.255;
        final double panelHeight = isPortrait ? 0.655 : 0.405;

        final double scale = _card4LangFontScale().clamp(0.90, 1.0).toDouble();
        final double titleSize = (isPortrait ? 33.0 : 42.0) * scale;
        final double introSize = (isPortrait ? 15.5 : 18.0) * scale;
        final double titleIntroGap = isPortrait ? 8.0 : 10.0;
        final double panelTitleSize = (isPortrait ? 18.0 : 16.0) * scale;
        final double panelBodySize = (isPortrait ? 14.0 : 12.5) * scale;
        final double panelFooterSize = (isPortrait ? 14.5 : 13.0) * scale;

        return Stack(
          children: <Widget>[
            Positioned(
              left: w * titleLeft,
              top: h * titleTop,
              width: w * titleWidth,
              height: h * titleHeight,
              child: Padding(
                padding: isPortrait
                    ? const EdgeInsets.symmetric(horizontal: 4, vertical: 6)
                    : const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: w * titleWidth,
                      child: _buildVehiclesFleetHeroTextBlock(
                        titleSize: titleSize,
                        introSize: introSize,
                        introLineHeight: isPortrait ? 1.20 : 1.22,
                        titleIntroGap: titleIntroGap,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: w * panelLeft,
              top: h * panelTop,
              width: w * panelWidth,
              height: h * panelHeight,
              child: _buildVehiclesFleetFeaturePanel(
                zoneWidth: w * panelWidth,
                titleSize: panelTitleSize,
                bodySize: panelBodySize,
                footerSize: panelFooterSize,
                isPortrait: isPortrait,
                showFooter: true,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVehiclesFleetHeroTextBlock({
    required double titleSize,
    required double introSize,
    required double introLineHeight,
    required double titleIntroGap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildVehiclesFleetTitle(titleSize),
        SizedBox(height: titleIntroGap),
        _buildVehiclesFleetIntro(introSize, introLineHeight),
      ],
    );
  }

  Widget _buildVehiclesFleetTitle(double fontSize) {
    return Text(
      _t(_card4VehiclesFleetTitle),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold,
        fontSize: fontSize,
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
    );
  }

  Widget _buildVehiclesFleetIntro(double fontSize, double lineHeight) {
    return Text(
      _t(_card4VehiclesFleetIntro),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: Colors.white.withOpacity(0.90),
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        height: lineHeight,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 8, offset: Offset(0, 1)),
        ],
      ),
    );
  }

  Widget _buildVehiclesFleetFeaturePanel({
    required double zoneWidth,
    required double titleSize,
    required double bodySize,
    required double footerSize,
    required bool isPortrait,
    required bool showFooter,
  }) {
    final double scale = _card4LangFontScale().clamp(0.90, 1.0).toDouble();
    final double rowGap = (isPortrait ? 8.0 : 5.5) * scale;
    final double rowPaddingH = (isPortrait ? 9.0 : 7.0) * scale;
    final double rowPaddingV = (isPortrait ? 5.0 : 4.0) * scale;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: zoneWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < _card4VehiclesFleetFeatures.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : rowGap),
                child: _buildVehiclesFleetFeatureRow(
                  _card4VehiclesFleetFeatures[i],
                  titleSize: titleSize,
                  bodySize: bodySize,
                  dotSize: (isPortrait ? 6.5 : 6.0) * scale,
                  rowPaddingH: rowPaddingH,
                  rowPaddingV: rowPaddingV,
                ),
              ),
            if (showFooter) ...<Widget>[
              SizedBox(height: (isPortrait ? 9.0 : 6.5) * scale),
              _buildVehiclesFleetFeatureFooter(footerSize),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVehiclesFleetFeatureRow(
    _OrientationBulletItem feature, {
    required double titleSize,
    required double bodySize,
    required double dotSize,
    required double rowPaddingH,
    required double rowPaddingV,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withOpacity(0.12)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: rowPaddingH,
          vertical: rowPaddingV,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: dotSize,
              height: dotSize,
              margin: EdgeInsets.only(top: titleSize * 0.33),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _gold,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _gold.withOpacity(0.45),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            SizedBox(width: rowPaddingH * 0.72),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _t(feature.title),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: _gold,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w800,
                      height: 1.06,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _t(feature.description),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.86),
                      fontSize: bodySize,
                      fontWeight: FontWeight.w500,
                      height: 1.08,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
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

  Widget _buildVehiclesFleetFeatureFooter(double fontSize) {
    return Text(
      _t(_card4VehiclesFleetFooter),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        height: 1.08,
        letterSpacing: 0.08,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 7, offset: Offset(0, 1)),
        ],
      ),
    );
  }

  // =================================================================
  // Card 6 (slide 7) — Drivers & documents bespoke tablet hero.
  //
  // The card6 artwork carries the driver management screenshots and
  // Fluxidi wordmark. Flutter overlays only the localised title/intro
  // (hero block) and one premium parent explanation panel with four
  // evenly distributed feature rows in measured per-orientation safe
  // zones that avoid the driver faces, document controls and
  // screenshots.
  // =================================================================

  // =================================================================
  // Card 7 — Drivers & documents (bespoke tablet heroes).
  //
  // Measured safe-zone frame ratios (FROZEN — do not move until the
  // Region-Radar-style rebuild re-approves them). Artwork targets:
  // portrait 1752×2800, landscape 2800×1752.
  //
  // Flutter overlays ONLY:
  //   • top title/intro panel
  //   • lower-left explanation / feature panel
  //
  // Dashboard screenshots + phone mockup are BAKED into the card6
  // PNG — no separate Flutter Positioned widgets for visual areas.
  //
  // PORTRAIT title/intro panel:
  //   left 0.455, top 0.060, width 0.500, height 0.150
  // PORTRAIT explanation panel:
  //   left 0.040, top 0.515, width 0.365, height 0.345
  //
  // LANDSCAPE title/intro panel:
  //   left 0.445, top 0.070, width 0.460, height 0.150
  // LANDSCAPE explanation panel:
  //   left 0.018, top 0.385, width 0.320, height 0.430
  //
  // Visual/mockup areas (asset-only, approximate artwork zones):
  //   portrait dashboard ~ left 0.10, top 0.22, width 0.85, height 0.30
  //   portrait phone mockup ~ left 0.45, top 0.42, width 0.45, height 0.40
  // =================================================================

  /// Per-language down-scale for the longer FR/ES Card 6 copy so the
  /// fixed sizes already land slightly smaller before the [FittedBox]
  /// safety net ever has to engage. EN/NL stay at 1.0.
  double _driverManagementLangScale() {
    switch (appLanguageNotifier.value) {
      case AppLanguage.fr:
      case AppLanguage.es:
        return 0.92;
      case AppLanguage.nl:
      case AppLanguage.en:
      case AppLanguage.de:
        return 1.0;
    }
  }

  Widget _buildDriverManagementTabletLandscapeFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card6DriverManagementTabletLandscapeAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][CARD6_LANDSCAPE_PNG_FAIL] error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(
          child: _buildDriverManagementTabletOverlay(isPortrait: false),
        ),
      ],
    );
  }

  Widget _buildDriverManagementTabletPortraitFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
          _card6DriverManagementTabletPortraitAsset,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          errorBuilder: (ctx, error, stackTrace) {
            debugPrint(
              '[ORIENTATION_FLOW][CARD6_PORTRAIT_PNG_FAIL] error=$error',
            );
            return _buildWelcomeMediaUltimateFallback();
          },
        ),
        IgnorePointer(
          child: _buildDriverManagementTabletOverlay(isPortrait: true),
        ),
      ],
    );
  }

  /// Title/intro hero block + framed feature panel for Card 7,
  /// positioned in measured safe zones relative to the FULL viewport
  /// so the fractions line up with the full-bleed background asset.
  Widget _buildDriverManagementTabletOverlay({required bool isPortrait}) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        if (isPortrait ? h <= w : w <= h) {
          return const SizedBox.shrink();
        }

        final double titleLeft = isPortrait ? 0.455 : 0.445;
        final double titleTop = isPortrait ? 0.060 : 0.070;
        final double titleWidth = isPortrait ? 0.500 : 0.460;
        final double titleHeight = isPortrait ? 0.150 : 0.150;
        // Feature-panel safe zones: lower-left portrait free zone and
        // left-side landscape zone on the fixed driver artwork targets
        // (portrait 1752x2800, landscape 2800x1752). Four feature rows
        // live in ONE parent panel inside the bounded rectangle.
        final double panelLeft = isPortrait ? 0.040 : 0.018;
        final double panelTop = isPortrait ? 0.515 : 0.385;
        final double panelWidth = isPortrait ? 0.365 : 0.320;
        final double panelHeight = isPortrait ? 0.345 : 0.430;

        if (kDebugMode) {
          debugPrint(
            '[ORIENTATION_FLOW][DRIVER_MGMT_FRAME] '
            'orientation=${isPortrait ? 'portrait' : 'landscape'} '
            'title(left=${titleLeft.toStringAsFixed(3)}, '
            'top=${titleTop.toStringAsFixed(3)}, '
            'width=${titleWidth.toStringAsFixed(3)}, '
            'height=${titleHeight.toStringAsFixed(3)}) '
            'explanation(left=${panelLeft.toStringAsFixed(3)}, '
            'top=${panelTop.toStringAsFixed(3)}, '
            'width=${panelWidth.toStringAsFixed(3)}, '
            'height=${panelHeight.toStringAsFixed(3)}) '
            'visuals=baked_card6_png',
          );
        }

        final double scale = _driverManagementLangScale()
            .clamp(0.90, 1.0)
            .toDouble();
        final double titleSize = (isPortrait ? 33.0 : 42.0) * scale;
        final double introSize = (isPortrait ? 15.5 : 18.0) * scale;

        return Stack(
          children: <Widget>[
            Positioned(
              left: w * titleLeft,
              top: h * titleTop,
              width: w * titleWidth,
              height: h * titleHeight,
              child: Padding(
                padding: isPortrait
                    ? const EdgeInsets.symmetric(horizontal: 4, vertical: 6)
                    : const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    return SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: _regionRadarWholeBlockScaleDown(
                        maxWidth: constraints.maxWidth,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _buildDriverManagementTitle(titleSize),
                            SizedBox(height: isPortrait ? 8.0 : 10.0),
                            _buildDriverManagementIntro(
                              introSize,
                              isPortrait ? 1.20 : 1.22,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              left: w * panelLeft,
              top: h * panelTop,
              width: w * panelWidth,
              height: h * panelHeight,
              child: _buildDriverManagementExplanationPanel(
                zoneWidth: w * panelWidth,
                zoneHeight: h * panelHeight,
                isPortrait: isPortrait,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDriverManagementTitle(double fontSize) {
    return Text(
      _t(_driverManagementTitle),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: _gold,
        fontSize: fontSize,
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
    );
  }

  Widget _buildDriverManagementIntro(double fontSize, double lineHeight) {
    return Text(
      _t(_driverManagementIntro),
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: Colors.white.withOpacity(0.90),
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        height: lineHeight,
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), blurRadius: 8, offset: Offset(0, 1)),
        ],
      ),
    );
  }

  /// One premium explanation panel inside the measured safe frame.
  /// Four feature rows share a single parent panel — Region-Radar-style.
  Widget _buildDriverManagementExplanationPanel({
    required double zoneWidth,
    required double zoneHeight,
    required bool isPortrait,
  }) {
    final double langScale = _driverManagementLangScale();
    final EdgeInsets padding = isPortrait
        ? const EdgeInsets.fromLTRB(12, 10, 12, 8)
        : const EdgeInsets.fromLTRB(10, 8, 10, 6);
    final double rowTitleSize = (isPortrait ? 17.5 : 15.5) * langScale;
    final double rowBodySize = (isPortrait ? 15.5 : 13.5) * langScale;

    return SizedBox(
      width: zoneWidth,
      height: zoneHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.54),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _gold.withOpacity(0.22)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.32),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: padding,
          child: Column(
            children: <Widget>[
              for (int i = 0; i < _driverManagementFeatures.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: isPortrait ? 3.0 : 2.0,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _buildDriverManagementExplanationFeatureRow(
                        _driverManagementFeatures[i],
                        titleSize: rowTitleSize,
                        bodySize: rowBodySize,
                        showDivider: i > 0,
                        compact: !isPortrait,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Internal feature row — gold dot, title, body. No per-row card border.
  Widget _buildDriverManagementExplanationFeatureRow(
    _OrientationBulletItem feature, {
    required double titleSize,
    required double bodySize,
    required bool showDivider,
    required bool compact,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showDivider)
          Padding(
            padding: EdgeInsets.only(bottom: compact ? 5 : 6),
            child: Divider(
              color: _gold.withOpacity(0.14),
              height: 1,
              thickness: 1,
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: compact ? 6.5 : 7,
              height: compact ? 6.5 : 7,
              margin: EdgeInsets.only(top: titleSize * 0.34),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _gold,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _gold.withOpacity(0.45),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _t(feature.title),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: _gold,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w800,
                      height: 1.06,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 2 : 3),
                  Text(
                    _t(feature.description),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.86),
                      fontSize: bodySize,
                      fontWeight: FontWeight.w500,
                      height: 1.10,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSubscriptionTabletLandscapeFullViewportHero() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FluxidiDecodeSizedAssetImage(
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
        FluxidiDecodeSizedAssetImage(
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
                FluxidiDecodeSizedAssetImage(
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

  /// Card 1 status capsule — context-aware via [widget.entryMode].
  ///
  /// * [BusinessOrientationEntryMode.setupCompleted]: emerald tint +
  ///   check icon "Setup voltooid", celebrating that the guided setup
  ///   that just preceded this flow wired up the operator's business
  ///   profile.
  /// * [BusinessOrientationEntryMode.generalGuide]: neutral gold/dark
  ///   "Startgids" capsule matching the Fluxidi accent, used when the
  ///   tour is reopened from Help & guide where "completed" would be
  ///   misleading.
  ///
  /// Layout (padding, pill radius, icon size, font) is identical
  /// across both modes so neither variant overflows or clips in
  /// NL/EN/FR/ES.
  Widget _buildHeroSetupBadge() {
    final bool setupCompleted =
        widget.entryMode == BusinessOrientationEntryMode.setupCompleted;
    final Color fill = setupCompleted
        ? const Color(0x3322C55E) // ~20% emerald
        : _gold.withOpacity(0.16);
    final Color foreground = setupCompleted ? const Color(0xFF7DE2A4) : _gold;
    final IconData icon = setupCompleted
        ? Icons.check_circle
        : Icons.explore_outlined;
    final _Tr label = setupCompleted
        ? const _Tr(
            nl: 'Setup voltooid',
            en: 'Setup complete',
            fr: 'Configuration terminée',
            es: 'Configuración completada',
          )
        : const _Tr(
            nl: 'Startgids',
            en: 'Quick guide',
            fr: 'Guide de démarrage',
            es: 'Guía inicial',
          );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withOpacity(0.48)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 7),
          Text(
            _t(label),
            style: TextStyle(
              color: foreground,
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
    final bool setupCompleted =
        widget.entryMode == BusinessOrientationEntryMode.setupCompleted;
    final _Tr copy = setupCompleted
        ? const _Tr(
            nl: 'Je bedrijfsbasis is ingesteld. In deze korte rondleiding ontdek je hoe je boekingen, chauffeurs, voertuigen en klanten beheert.',
            en: 'Your business basis is set up. In this short tour, you will discover how to manage bookings, drivers, vehicles and customers.',
            fr: 'La base de votre entreprise est configurée. Dans cette courte visite, vous découvrirez comment gérer les réservations, les chauffeurs, les véhicules et les clients.',
            es: 'La base de tu empresa está configurada. En este breve recorrido descubrirás cómo gestionar reservas, conductores, vehículos y clientes.',
          )
        : const _Tr(
            nl: 'Ontdek in deze korte rondleiding hoe je boekingen, chauffeurs, voertuigen en klanten beheert.',
            en: 'In this short tour, discover how to manage bookings, drivers, vehicles and customers.',
            fr: 'Dans cette courte visite, découvrez comment gérer les réservations, les chauffeurs, les véhicules et les clients.',
            es: 'En este breve recorrido, descubre cómo gestionar reservas, conductores, vehículos y clientes.',
          );
    return Text(
      _t(copy),
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
    AppLanguage.de => ('Everything starts from your ', 'Fluxidi cockpit'),
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
          FluxidiDecodeSizedAssetImage(
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
/// * [regionRadarRich] — bespoke Region Radar card using card7 PNG
///   artwork with one bounded text panel on tablet; the generic icon
///   card on phones.
/// * [publicBookingLinkRich] — bespoke Scan to Book card using card9
///   PNG artwork with one bounded premium panel on tablet; the generic
///   icon card on phones.
/// * [aiDispatchRich] — bespoke AI Dispatch card using card10 PNG
///   artwork with measured premium panels on tablet; the generic icon
///   card on phones.
/// * [driverViewRich] — bespoke Driver View card using card8 PNG
///   artwork with measured premium panels on tablet; the generic icon
///   card on phones.
/// * [calculatorRich] — bespoke Calculator card using card11 PNG
///   artwork with measured premium panels on tablet; the generic icon
///   card on phones.
/// * [driverReceiptsRich] — bespoke Ride receipts / history / documents
///   card using card12 PNG artwork with measured premium panels on
///   tablet; the generic icon card on phones.
/// * [activateCustomersRich] — bespoke final Activate customers card
///   using card13 PNG artwork with one measured premium panel on tablet;
///   the generic icon card on phones.
/// * [iconCard] — the stable baseline icon + title + body composition.
/// * [placeholder] — a safe, centred, scroll-friendly "coming next"
///   card for product-tour stops that are not yet designed. Never
///   loads an image, so it cannot raise asset-not-found errors and
///   cannot overflow.
enum _OrientationCardLayout {
  welcome,
  companyCockpit,
  subscription,
  settingsProfileRich,
  themesBrandingRich,
  vehiclesFleet,
  driverManagementRich,
  chironDocumentsRich,
  regionRadarRich,
  publicBookingLinkRich,
  aiDispatchRich,
  driverViewRich,
  calculatorRich,
  driverReceiptsRich,
  activateCustomersRich,
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

/// A single feature for the Settings & company profile card: a small
/// gold icon plus localized title + short description. Distinct from
/// [_OrientationBulletItem] because the settings engine card uses
/// compact icon chips rather than plain gold bullet dots.
class _SettingsProfileFeature {
  const _SettingsProfileFeature({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final _Tr title;
  final _Tr description;
}

/// A single preview in the Card 5 (themes & branding) Theme Showroom.
/// [title] is a brand name (kept identical across languages); [category]
/// localizes. [accentColor]/[secondaryColor] drive the tablet frame's
/// border + glow so each theme reads with its own signature color.
class _ThemeShowroomItem {
  const _ThemeShowroomItem({
    required this.title,
    required this.category,
    required this.assetPath,
    required this.accentColor,
    this.secondaryColor,
  });

  final String title;
  final _Tr category;
  final String assetPath;
  final Color accentColor;
  final Color? secondaryColor;
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
