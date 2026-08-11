// NAV-PRESENTATION-COMPACT-BANNER-LANES-TELLERS-1 / Commit 3
//
// Driver-facing "Tellers" presentation. Read-only view over live ride meters.
// Does not own GPS, fare, waiting, route progress, or the Mapbox map.

import 'package:flutter/foundation.dart' show ValueListenable, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_tellers_guidance.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_tellers_layout_geometry.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_signage_tablet_readability.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_tablet_branded_header.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_marker_choice.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_flags.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_vehicle_choice_selector.dart';
import 'package:fluxidi_tracking/widgets/driver_nav_banners.dart';

export 'package:fluxidi_tracking/navigation/presentation/driver_tellers_layout_geometry.dart';

/// Presentation mode for the driver navigation surface.
enum DriverNavPresentationMode {
  /// Live map + maneuver banner (default).
  navigation,

  /// Opaque Tellers overlay; navigation subtree stays mounted underneath.
  tellers,
}

/// Pure toggle owner — idempotent, no side effects on engines.
class DriverNavPresentationModeController {
  DriverNavPresentationMode _mode = DriverNavPresentationMode.navigation;

  DriverNavPresentationMode get mode => _mode;

  bool get isTellers => _mode == DriverNavPresentationMode.tellers;

  /// Returns true when the mode actually changed.
  bool showTellers() {
    if (_mode == DriverNavPresentationMode.tellers) return false;
    _mode = DriverNavPresentationMode.tellers;
    return true;
  }

  bool showNavigation() {
    if (_mode == DriverNavPresentationMode.navigation) return false;
    _mode = DriverNavPresentationMode.navigation;
    return true;
  }

  void reset() {
    _mode = DriverNavPresentationMode.navigation;
  }
}

/// NAV-STYLE-MANAGER-CRASH-TELLERS-MARKER-1 Commit 2: single owner of the
/// selected vehicle marker presentation. Exactly one owner at a time — never
/// both a Flutter HUD marker and a Mapbox annotation marker.
///
/// NAV-TELLERS-SINGLE-MAP-MARKER-OWNER-1: in Tellers the ONE vehicle marker is
/// now the same native Mapbox annotation used by ordinary Navigation, projected
/// at the Tellers marker anchor by the follow-camera padding. The screen-fixed
/// Flutter Car/Arrow child inside the Tellers live window is no longer painted
/// (field-proven duplicate). The legacy `tellersLiveWindow` enum value is
/// retained for source compat but the resolver never returns it.
enum DriverVehicleMarkerPresentationOwner {
  /// No marker (idle / no live follow).
  none,

  /// Normal Street-Level screen-fixed HUD owns the visual; Mapbox 2D opacity 0.
  navigationHud,

  /// Native Mapbox annotation owns the visual (no Flutter HUD marker). Used by
  /// both ordinary Navigation (no HUD overlay flag) AND by Tellers.
  mapboxAnnotation,

  /// DEPRECATED (NAV-TELLERS-SINGLE-MAP-MARKER-OWNER-1). Kept for source
  /// compatibility; the resolver never returns it. Do not add new callers.
  @Deprecated(
    'Tellers now uses Mapbox annotation as the single marker owner; see '
    'NAV-TELLERS-SINGLE-MAP-MARKER-OWNER-1.',
  )
  tellersLiveWindow,
}

/// Resolves the single vehicle-marker presentation owner.
DriverVehicleMarkerPresentationOwner resolveDriverVehicleMarkerPresentationOwner({
  required bool tellersActive,
  required bool followLiveActive,
  required bool showDriverHudOverlay,
}) {
  if (!followLiveActive) return DriverVehicleMarkerPresentationOwner.none;
  // NAV-TELLERS-SINGLE-MAP-MARKER-OWNER-1: Tellers uses the same Mapbox
  // annotation as ordinary Navigation. Camera padding places that annotation
  // at the Tellers marker anchor; no second Flutter Car/Arrow is painted.
  if (tellersActive) {
    return DriverVehicleMarkerPresentationOwner.mapboxAnnotation;
  }
  if (showDriverHudOverlay) {
    return DriverVehicleMarkerPresentationOwner.navigationHud;
  }
  return DriverVehicleMarkerPresentationOwner.mapboxAnnotation;
}

/// Bounded, PII-free diagnostic label for a marker presentation owner.
String driverVehicleMarkerPresentationOwnerLabel(
  DriverVehicleMarkerPresentationOwner owner,
) {
  switch (owner) {
    case DriverVehicleMarkerPresentationOwner.none:
      return 'none';
    case DriverVehicleMarkerPresentationOwner.navigationHud:
      return 'hud';
    case DriverVehicleMarkerPresentationOwner.mapboxAnnotation:
      return 'mapbox';
    // ignore: deprecated_member_use_from_same_package
    case DriverVehicleMarkerPresentationOwner.tellersLiveWindow:
      return 'tellers_live_window';
  }
}

/// NAV-TELLERS-STREETLEVEL-SCREEN-UP-MARKER-1: rotation-alignment mode for
/// the single Mapbox driver point annotation. Maps 1:1 onto Mapbox
/// `IconRotationAlignment`:
///   - [DriverMarkerRotationAlignment.map] → `IconRotationAlignment.MAP`
///     (marker rotates with the map — pre-fix default).
///   - [DriverMarkerRotationAlignment.viewport] →
///     `IconRotationAlignment.VIEWPORT` (marker fixed relative to the
///     device screen).
enum DriverMarkerRotationAlignment { map, viewport }

/// NAV-TELLERS-STREETLEVEL-SCREEN-UP-MARKER-1: resolved rotation policy for
/// one frame of the driver marker pipeline. Pure, Mapbox-free.
///
/// Field-proven defect: in Tellers Streetlevel the single visible Mapbox
/// annotation uses `IconRotationAlignment.MAP` with the raw pose bearing
/// written into `iconRotate`, while the follow camera separately smooths
/// its own bearing. The visible screen rotation of the marker becomes
/// `poseBearing - smoothedCameraBearing`, which is non-zero mid-turn and
/// shows the Car/Arrow as diagonal relative to the physical screen and the
/// route.
///
/// Hard Streetlevel invariant (Car and Arrow):
///   - marker nose always points to the physical screen top;
///   - map + route rotate underneath the marker;
///   - marker screen rotation is always 0°;
///   - independent of portrait ↔ landscape, turning, Centreren,
///     Car ↔ Arrow switching, Navigation ↔ Tellers switching.
class DriverMarkerRotationPolicy {
  const DriverMarkerRotationPolicy._(this.alignment, this.forceIconRotateZero);

  /// Legacy behaviour: marker rotates with the map; `iconRotate` receives
  /// the authoritative pose bearing (raw / smoothed by the surrounding
  /// pipeline). Used in Overview / North-up, and whenever the Mapbox
  /// annotation is not the visible owner (e.g. Flutter HUD owns).
  static const DriverMarkerRotationPolicy mapRoadBearing =
      DriverMarkerRotationPolicy._(DriverMarkerRotationAlignment.map, false);

  /// Streetlevel screen-up: marker is fixed to the viewport top;
  /// `iconRotate` is forced to 0 regardless of the incoming pose bearing so
  /// the map and route rotate UNDERNEATH the marker.
  static const DriverMarkerRotationPolicy viewportScreenUp =
      DriverMarkerRotationPolicy._(
    DriverMarkerRotationAlignment.viewport,
    true,
  );

  /// Where the icon rotation is anchored.
  final DriverMarkerRotationAlignment alignment;

  /// When true, the caller must write `iconRotate = 0` regardless of any
  /// route / GPS / pose bearing supplied. When false, the caller writes the
  /// authoritative pose bearing unchanged.
  final bool forceIconRotateZero;

  /// Resolves the `iconRotate` value to apply to the annotation for a given
  /// [poseBearing]. In the screen-up policy the result is always 0; in the
  /// legacy policy the pose bearing passes through unchanged.
  double iconRotateFor(double poseBearing) =>
      forceIconRotateZero ? 0.0 : poseBearing;

  /// Bounded, PII-free diagnostic label.
  String get logLabel {
    switch (alignment) {
      case DriverMarkerRotationAlignment.map:
        return 'map_road_bearing';
      case DriverMarkerRotationAlignment.viewport:
        return 'viewport_screen_up';
    }
  }
}

/// NAV-TELLERS-STREETLEVEL-SCREEN-UP-MARKER-1: Streetlevel + Mapbox-owned
/// visible marker → [DriverMarkerRotationPolicy.viewportScreenUp].
///
/// Any other combination (Overview / North-up view, or the Mapbox
/// annotation being HIDDEN behind the Flutter HUD in ordinary Streetlevel
/// Navigation, or no live marker owner) preserves the legacy
/// [DriverMarkerRotationPolicy.mapRoadBearing]. Ordinary Streetlevel with
/// the Flutter HUD covering the (hidden) Mapbox marker is unchanged.
///
/// [isStreetlevel] is the driver cockpit / street-view predicate (typically
/// `NavigationPresentationState.useDriverCockpitCamera`).
/// [owner] is the single-owner resolution from
/// [resolveDriverVehicleMarkerPresentationOwner].
DriverMarkerRotationPolicy resolveDriverMarkerRotationPolicy({
  required bool isStreetlevel,
  required DriverVehicleMarkerPresentationOwner owner,
}) {
  if (!isStreetlevel) return DriverMarkerRotationPolicy.mapRoadBearing;
  switch (owner) {
    case DriverVehicleMarkerPresentationOwner.mapboxAnnotation:
      return DriverMarkerRotationPolicy.viewportScreenUp;
    // NAV-FIXED-HUD-PRESENTATION-1: the HUD owns the visual and the Mapbox
    // annotation sits behind it at opacity 0. Opacity is applied over an
    // async channel, so a style swap, manager recreate or marker restore can
    // expose that annotation for a frame. Forcing screen-up here means such
    // a frame can never show a diagonal Car/Arrow.
    case DriverVehicleMarkerPresentationOwner.navigationHud:
      return DriverMarkerRotationPolicy.viewportScreenUp;
    // ignore: deprecated_member_use_from_same_package
    case DriverVehicleMarkerPresentationOwner.tellersLiveWindow:
    case DriverVehicleMarkerPresentationOwner.none:
      return DriverMarkerRotationPolicy.mapRoadBearing;
  }
}

/// True when the Mapbox 2D taxi/arrow annotation must be hidden because a
/// Flutter presentation owner currently owns the single marker visual.
bool driverHideMapboxMarkerForPresentationOwner(
  DriverVehicleMarkerPresentationOwner owner,
) {
  // NAV-TELLERS-SINGLE-MAP-MARKER-OWNER-1: [tellersLiveWindow] is deprecated
  // and never returned by the resolver, but the check is kept as a
  // defense-in-depth guarantee: if a stale caller ever hands us that value,
  // hiding the Mapbox marker (behind whatever Flutter owner it implied)
  // remains the safe fallback.
  return owner == DriverVehicleMarkerPresentationOwner.navigationHud ||
      // ignore: deprecated_member_use_from_same_package
      owner == DriverVehicleMarkerPresentationOwner.tellersLiveWindow;
}

/// NAV-TELLERS-COMPOSITION-CORRECTION-1 + NAV-STYLE-MANAGER-CRASH-TELLERS-MARKER-1:
/// one-HUD-at-a-time visibility decision. Separates cockpit HUD, follow overlays,
/// vehicle-marker visibility and Tellers marker presentation so Tellers can keep
/// exactly one vehicle marker visible without re-enabling the normal cockpit.
@immutable
class DriverNavHudVisibility {
  /// Normal bottom cockpit (KPI row + primary nav controls) and top strip.
  final bool cockpitHud;

  /// Follow-mode navigation overlays (maneuver banner, recenter, camera/zoom
  /// controls, normal marker selector). Does NOT gate the Tellers marker.
  final bool navBannerHud;

  /// The dedicated Tellers presentation HUD.
  final bool tellersHud;

  /// Exactly one selected vehicle marker should be presented (Navigation or
  /// Tellers). Never duplicates under the other mode's anchor.
  final bool vehicleMarkerVisible;

  /// Tellers live-window marker presentation (Flutter HUD clipped in window).
  final bool tellersMarkerPresentationVisible;

  /// Compact Car/Arrow selector inside the Tellers live window.
  final bool tellersMarkerSelectorVisible;

  /// Resolved single marker presentation owner.
  final DriverVehicleMarkerPresentationOwner markerOwner;

  const DriverNavHudVisibility({
    required this.cockpitHud,
    required this.navBannerHud,
    required this.tellersHud,
    required this.vehicleMarkerVisible,
    required this.tellersMarkerPresentationVisible,
    required this.tellersMarkerSelectorVisible,
    required this.markerOwner,
  });

  /// While Tellers is active, the normal cockpit HUD and follow overlays are
  /// suppressed, but the selected vehicle marker remains visible inside the
  /// live-navigation window. GPS/route/camera/fare/timers stay live.
  factory DriverNavHudVisibility.resolve({
    required bool showCockpit,
    required bool cameraFollow,
    required bool tellersActive,
    bool followLiveActive = false,
    bool showDriverHudOverlay = false,
  }) {
    final owner = resolveDriverVehicleMarkerPresentationOwner(
      tellersActive: tellersActive,
      followLiveActive: followLiveActive || cameraFollow,
      showDriverHudOverlay: showDriverHudOverlay,
    );
    return DriverNavHudVisibility(
      cockpitHud: showCockpit && !tellersActive,
      navBannerHud: cameraFollow && !tellersActive,
      tellersHud: tellersActive,
      vehicleMarkerVisible: owner != DriverVehicleMarkerPresentationOwner.none,
      // NAV-TELLERS-SINGLE-MAP-MARKER-OWNER-1: no Flutter Car/Arrow child is
      // painted inside the Tellers live window; the single Mapbox annotation
      // is projected onto the marker anchor by the follow-camera padding.
      tellersMarkerPresentationVisible: false,
      tellersMarkerSelectorVisible: tellersActive &&
          (followLiveActive || cameraFollow),
      markerOwner: owner,
    );
  }
}

/// NAV-PARKING-2 Commit 4: latest-wins owner for the temporary Tellers camera
/// viewport/padding. Pure and side-effect free — it only tracks a monotonic
/// generation so a stale Tellers camera callback (from a viewport that has
/// since been closed or superseded) can be rejected, and closing can never
/// resurrect an old viewport. It does NOT create a camera/GPS owner.
class DriverTellersViewportController {
  int _generation = 0;
  bool _active = false;

  bool get active => _active;
  int get generation => _generation;

  /// Activate (or re-activate latest-wins) the Tellers viewport. Returns the
  /// token the caller must present when a deferred camera callback fires.
  int open() {
    _generation += 1;
    _active = true;
    return _generation;
  }

  /// Restore normal follow presentation. Bumps the generation so any pending
  /// Tellers viewport callback becomes stale and cannot resurrect the viewport.
  void close() {
    if (!_active && _generation == 0) return;
    _generation += 1;
    _active = false;
  }

  /// True only when [token] belongs to the current active viewport.
  bool isCallbackValid(int token) => _active && token == _generation;

  void reset() {
    _generation += 1;
    _active = false;
  }
}

/// Snapshot of authoritative live values for the Tellers screen.
///
/// Money is already formatted by the existing display policy; this model does
/// not introduce a second rounding rule or finalize fare.
class DriverRideMetersSnapshot {
  const DriverRideMetersSnapshot({
    required this.fareText,
    required this.distanceTravelledText,
    required this.rideDurationText,
    required this.waitingTimeText,
    required this.statusText,
    this.fareLabel = 'Tarief',
    this.usesFixedPrice = false,
    this.etaText = '',
    this.remainingDistanceText = '',
    this.speedText = '',
    this.tariffName = '',
    this.companyName = '',
  });

  final String fareText;

  /// Fare tile label. Planned rides use `Vaste prijs`; street/direct keep
  /// the existing `Tarief` meter name.
  final String fareLabel;

  /// True when [fareText] is the authoritative planned booking fixed price
  /// (never the live meter). Same SoT as cockpit fare presentation.
  final bool usesFixedPrice;
  final String distanceTravelledText;
  final String rideDurationText;
  final String waitingTimeText;
  final String statusText;
  final String etaText;
  final String remainingDistanceText;

  /// Formatted GPS speed for PiP secondary "Current" KPI (presentation only).
  /// Empty when unknown — never a fabricated value.
  final String speedText;
  final String tariffName;
  final String companyName;
}

/// Localized product title for the Tellers / Counters surface.
String driverTellersTitle(AppLanguage language) {
  return const LocalizedText(
    nl: 'Tellers',
    en: 'Counters',
    fr: 'Compteurs',
    es: 'Contadores',
  ).of(language);
}

/// Localized back-to-navigation control on the Tellers surface.
String driverTellersNavigationLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'Navigatie',
    en: 'Navigation',
    fr: 'Navigation',
    es: 'Navegación',
  ).of(language);
}

String driverTellersDistanceLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'Afstand',
    en: 'Distance',
    fr: 'Distance',
    es: 'Distancia',
  ).of(language);
}

String driverTellersDurationLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'Ritduur',
    en: 'Ride time',
    fr: 'Durée du trajet',
    es: 'Duración',
  ).of(language);
}

String driverTellersWaitingLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'Wachttijd',
    en: 'Waiting time',
    fr: 'Temps d’attente',
    es: 'Tiempo de espera',
  ).of(language);
}

String driverTellersFareLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'Tarief',
    en: 'Fare',
    fr: 'Tarif',
    es: 'Tarifa',
  ).of(language);
}

String driverTellersFixedPriceLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'Vaste prijs',
    en: 'Fixed price',
    fr: 'Prix fixe',
    es: 'Precio fijo',
  ).of(language);
}

/// Bottom summary card label for street / metered rides.
String driverTellersEstimatedRidePriceLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'Geschatte ritprijs',
    en: 'Estimated ride price',
    fr: 'Prix de course estimé',
    es: 'Precio estimado del viaje',
  ).of(language);
}

/// Bottom summary card label for planned fixed-price rides.
String driverTellersFixedRidePriceLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'Vaste ritprijs',
    en: 'Fixed ride price',
    fr: 'Prix de course fixe',
    es: 'Precio fijo del viaje',
  ).of(language);
}

String driverTellersPauseLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'Pauze',
    en: 'Pause',
    fr: 'Pause',
    es: 'Pausa',
  ).of(language);
}

String driverTellersResumeLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'Hervatten',
    en: 'Resume',
    fr: 'Reprendre',
    es: 'Reanudar',
  ).of(language);
}

/// Localized Tellers status chip text. Dutch must show `Rit actief` /
/// `Rit gepauzeerd` — never the English `Ride active` / `Ride paused`.
String driverTellersStatusText({
  required AppLanguage language,
  required bool isWaiting,
  required bool liveRideActive,
}) {
  if (isWaiting) {
    return const LocalizedText(
      nl: 'Rit gepauzeerd',
      en: 'Ride paused',
      fr: 'Course en pause',
      es: 'Viaje en pausa',
    ).of(language);
  }
  if (liveRideActive) {
    return const LocalizedText(
      nl: 'Rit actief',
      en: 'Ride active',
      fr: 'Course active',
      es: 'Viaje activo',
    ).of(language);
  }
  return const LocalizedText(
    nl: 'Stand-by',
    en: 'Stand-by',
    fr: 'Veille',
    es: 'En espera',
  ).of(language);
}

/// Localized label/tooltip for the Tellers recenter control.
String driverTellersRecenterLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'Centreren',
    en: 'Recenter',
    fr: 'Recentrer',
    es: 'Recentrar',
  ).of(language);
}

/// Pure contract for a Tellers recenter tap. Proves the action must keep the
/// driver in Tellers and preserve the current View 1–13 level — never create a
/// second camera/location owner.
@immutable
class DriverTellersRecenterContract {
  const DriverTellersRecenterContract({
    required this.viewLevelBefore,
    required this.tellersActiveBefore,
  });

  final int viewLevelBefore;
  final bool tellersActiveBefore;

  /// Recenter restores follow via the existing camera owner; it never leaves
  /// Tellers and never changes View level.
  bool get staysInTellers => tellersActiveBefore;
  bool get preservesViewLevel => true;
  bool get usesExistingCameraOwner => true;
  bool get createsSecondLocationOwner => false;

  bool isIdempotentAfter({
    required int viewLevelAfter,
    required bool tellersActiveAfter,
  }) {
    return viewLevelAfter == viewLevelBefore &&
        tellersActiveAfter == tellersActiveBefore;
  }
}

/// NAV-TELLERS-ROTATION-COMPOSITION-AND-POSE-LOCK-1 (Commit 1): pure last-valid
/// geometry latch. A transitional orientation frame can hand us a zero/partial
/// viewport; this retains the previous COMPLETE geometry until a new valid one
/// resolves, so the aperture is never installed with an incomplete size and the
/// viewport generation bumps exactly once per committed layout change.
///
/// NAV-ORIENTATION-VIEWPORT-STABILITY-P0-1: additionally accepts an optional
/// [epoch] on each commit. When the caller reports a new viewport epoch (e.g.
/// after a portrait ↔ landscape flip), the FIRST valid candidate at the new
/// epoch is held as a "settling" candidate rather than committed immediately —
/// the previous committed geometry keeps rendering. Only when a subsequent
/// commit at the same epoch presents an equivalent candidate is that geometry
/// promoted to the current committed layout. This prevents valid-but-
/// transitional MediaQuery observations (interim safe insets, mid-rotation
/// intermediate sizes) from being treated as the settled viewport.
class DriverTellersGeometryLatch {
  DriverTellersLayoutGeometry? _lastValid;
  int _generation = 0;
  int? _committedEpoch;
  int? _settlingEpoch;
  DriverTellersLayoutGeometry? _settlingCandidate;

  DriverTellersLayoutGeometry? get lastValid => _lastValid;
  int get generation => _generation;

  /// NAV-ORIENTATION-VIEWPORT-STABILITY-P0-1: last committed epoch (null until
  /// the first commit).
  int? get committedEpoch => _committedEpoch;

  /// NAV-ORIENTATION-VIEWPORT-STABILITY-P0-1: true when a new epoch's first
  /// valid candidate has been observed but not yet confirmed by a second
  /// matching observation. During settling, [commit] keeps returning the
  /// previously committed geometry so the aperture never flashes with an
  /// unstable transitional layout.
  bool get isSettling => _settlingCandidate != null;

  /// Returns the geometry to render. When [candidate] is valid it is latched
  /// (and [generation] bumps once if the committed layout actually changed);
  /// when invalid the last valid geometry is retained. Returns [candidate] only
  /// as a last resort when nothing valid has ever been committed.
  ///
  /// When [epoch] is provided and differs from the last committed epoch, the
  /// first valid candidate at the new epoch is deferred until a second matching
  /// valid candidate at the same epoch arrives (two-observation stability
  /// rule). The initial commit (no previous [_lastValid]) is always accepted
  /// so the first frame after page open renders correctly.
  DriverTellersLayoutGeometry commit(
    DriverTellersLayoutGeometry candidate, {
    int? epoch,
  }) {
    if (!candidate.isValid) return _lastValid ?? candidate;
    if (epoch != null &&
        _lastValid != null &&
        _committedEpoch != null &&
        epoch != _committedEpoch) {
      final settling = _settlingCandidate;
      if (settling != null &&
          _settlingEpoch == epoch &&
          _sameLayout(settling, candidate)) {
        _committedEpoch = epoch;
        _settlingCandidate = null;
        _settlingEpoch = null;
        return _acceptCommitted(candidate);
      }
      _settlingCandidate = candidate;
      _settlingEpoch = epoch;
      return _lastValid!;
    }
    _settlingCandidate = null;
    _settlingEpoch = null;
    if (epoch != null) _committedEpoch = epoch;
    return _acceptCommitted(candidate);
  }

  DriverTellersLayoutGeometry _acceptCommitted(
    DriverTellersLayoutGeometry candidate,
  ) {
    final prev = _lastValid;
    if (prev == null || !_sameLayout(prev, candidate)) {
      _generation += 1;
    }
    _lastValid = candidate;
    return candidate;
  }

  static bool _sameLayout(
    DriverTellersLayoutGeometry a,
    DriverTellersLayoutGeometry b,
  ) {
    return a.viewportSize == b.viewportSize &&
        a.isLandscape == b.isLandscape &&
        a.isTablet == b.isTablet &&
        a.liveWindowRect == b.liveWindowRect;
  }
}

/// Large, theme-aware Tellers overlay. Opaque — does not show satellite/map
/// behind the meters. Map style selection is unrelated to this UI theme.
///
/// NAV-TELLERS-ROTATION-COMPOSITION-AND-POSE-LOCK-1 (Commit 1): stateful only to
/// own a [DriverTellersGeometryLatch] so the last complete geometry is retained
/// across a transitional orientation frame. All visual composition lives in
/// [_DriverRideMetersContent] and is driven by the single committed geometry.
class DriverRideMetersView extends StatefulWidget {
  const DriverRideMetersView({
    super.key,
    required this.snapshot,
    required this.onBackToNavigation,
    this.onStop,
    this.onToggleWait,
    this.onRecenter,
    this.isWaiting = false,
    this.themeListenable,
    this.compact = false,
    this.isTablet = false,
    this.isLandscape = false,
    this.showLiveWindow = true,
    this.showVehicleMarker = true,
    this.showMarkerSelector = true,
    this.markerChoice = DriverNavigationMarkerChoice.car,
    this.onMarkerChoiceSelected,
    this.markerLanguage = AppLanguage.nl,
    this.vehicleMarkerIconSize,
    this.viewportEpoch,
    this.guidance = const DriverTellersGuidanceView.hidden(),
    this.brandLogo,
  });

  final DriverRideMetersSnapshot snapshot;
  final VoidCallback onBackToNavigation;
  final VoidCallback? onStop;
  final VoidCallback? onToggleWait;
  final VoidCallback? onRecenter;
  final bool isWaiting;
  final ValueListenable<DriverThemeVariant>? themeListenable;
  final bool compact;
  final bool isTablet;
  final bool isLandscape;
  final bool showLiveWindow;
  final bool showVehicleMarker;
  final bool showMarkerSelector;
  final DriverNavigationMarkerChoice markerChoice;
  final ValueChanged<DriverNavigationMarkerChoice>? onMarkerChoiceSelected;
  final AppLanguage markerLanguage;
  final double? vehicleMarkerIconSize;

  /// TABLET-TELLERS-COCKPIT-P1: tenant-scoped logo for the compact branded
  /// header. Phone ignores this (visual path unchanged).
  final Widget? brandLogo;

  /// NAV-ORIENTATION-VIEWPORT-STABILITY-P0-1: monotonic viewport/orientation
  /// epoch supplied by the driver page. When present, the internal
  /// [DriverTellersGeometryLatch] requires two consecutive matching valid
  /// candidates at the same epoch before promoting a new committed geometry
  /// so a transitional post-rotation MediaQuery observation cannot become the
  /// authoritative aperture.
  final int? viewportEpoch;

  /// TELLERS-LIVE-NAV-INSTRUCTION-OVERLAY-1: what the live map should show as
  /// the current maneuver instruction.
  ///
  /// Resolved entirely by the driver page from the SAME authoritative
  /// navigation state the main maneuver banner uses, so Tellers can never
  /// disagree with it. This view owns no route steps, no maneuver index and no
  /// lane resolution — it only paints what it is handed.
  final DriverTellersGuidanceView guidance;

  @override
  State<DriverRideMetersView> createState() => _DriverRideMetersViewState();
}

class _DriverRideMetersViewState extends State<DriverRideMetersView> {
  final DriverTellersGeometryLatch _geometryLatch = DriverTellersGeometryLatch();

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final reserveActionBar = widget.onStop != null ||
        widget.onToggleWait != null ||
        widget.onRecenter != null;
    final candidate = DriverTellersLayoutGeometry.resolve(
      viewportSize: media.size,
      safeTop: media.padding.top,
      safeBottom: media.padding.bottom,
      safeLeft: media.padding.left,
      safeRight: media.padding.right,
      isLandscape: widget.isLandscape,
      isTablet: widget.isTablet,
      reserveActionBar: reserveActionBar,
    );
    // Retain the last VALID geometry until a new complete one resolves so a
    // transitional (zero/partial) rotation frame never installs an incomplete
    // aperture over the retained MapWidget.
    //
    // NAV-ORIENTATION-VIEWPORT-STABILITY-P0-1: additionally scope commits to
    // the driver page's viewport epoch. After a portrait ↔ landscape flip the
    // first valid candidate is held until a second matching candidate at the
    // same epoch confirms the settled viewport.
    final geometry = _geometryLatch.commit(
      candidate,
      epoch: widget.viewportEpoch,
    );
    return _DriverRideMetersContent(
      snapshot: widget.snapshot,
      onBackToNavigation: widget.onBackToNavigation,
      onStop: widget.onStop,
      onToggleWait: widget.onToggleWait,
      onRecenter: widget.onRecenter,
      isWaiting: widget.isWaiting,
      themeListenable: widget.themeListenable,
      compact: widget.compact,
      isTablet: widget.isTablet,
      isLandscape: widget.isLandscape,
      showLiveWindow: widget.showLiveWindow,
      showVehicleMarker: widget.showVehicleMarker,
      showMarkerSelector: widget.showMarkerSelector,
      markerChoice: widget.markerChoice,
      onMarkerChoiceSelected: widget.onMarkerChoiceSelected,
      markerLanguage: widget.markerLanguage,
      vehicleMarkerIconSize: widget.vehicleMarkerIconSize,
      guidance: widget.guidance,
      brandLogo: widget.brandLogo,
      geometry: geometry,
    );
  }
}

class _DriverRideMetersContent extends StatelessWidget {
  const _DriverRideMetersContent({
    required this.snapshot,
    required this.onBackToNavigation,
    this.onStop,
    this.onToggleWait,
    this.onRecenter,
    this.isWaiting = false,
    this.themeListenable,
    this.compact = false,
    this.isTablet = false,
    this.isLandscape = false,
    this.showLiveWindow = true,
    this.showVehicleMarker = true,
    this.showMarkerSelector = true,
    this.markerChoice = DriverNavigationMarkerChoice.car,
    this.onMarkerChoiceSelected,
    this.markerLanguage = AppLanguage.nl,
    this.vehicleMarkerIconSize,
    this.guidance = const DriverTellersGuidanceView.hidden(),
    this.brandLogo,
    required this.geometry,
  });

  final DriverRideMetersSnapshot snapshot;
  final VoidCallback onBackToNavigation;
  final VoidCallback? onStop;
  final VoidCallback? onToggleWait;

  /// NAV-TELLERS-RECENTER-CONTROL-1: between Pauze and Stop. Invokes the
  /// existing authoritative recenter/follow action — never a second camera or
  /// location owner.
  final VoidCallback? onRecenter;
  final bool isWaiting;
  final ValueListenable<DriverThemeVariant>? themeListenable;
  final bool compact;
  final bool isTablet;
  final bool isLandscape;

  /// NAV-PARKING-2 Commit 4: when true the layout reserves a transparent
  /// cut-out region over the retained MapWidget so the single mounted map is
  /// the live navigation window. No second MapWidget is ever created here.
  final bool showLiveWindow;

  /// NAV-STYLE-MANAGER-CRASH-TELLERS-MARKER-1: show the one selected vehicle
  /// marker (Car/Arrow) clipped inside the live-navigation window.
  final bool showVehicleMarker;

  /// Compact Car/Arrow selector inside the live window (uses existing choice
  /// state — never a second owner).
  final bool showMarkerSelector;

  final DriverNavigationMarkerChoice markerChoice;
  final ValueChanged<DriverNavigationMarkerChoice>? onMarkerChoiceSelected;
  final AppLanguage markerLanguage;
  final double? vehicleMarkerIconSize;

  /// TELLERS-LIVE-NAV-INSTRUCTION-OVERLAY-1: authoritative maneuver guidance,
  /// resolved by the driver page. Rendered as-is; never recomputed here.
  final DriverTellersGuidanceView guidance;

  /// Tenant logo for the tablet branded header (presentation only).
  final Widget? brandLogo;

  /// The single committed (last-valid) Tellers geometry to render. Resolved and
  /// latched by [_DriverRideMetersViewState] so an incomplete transitional
  /// viewport never installs a partial aperture.
  final DriverTellersLayoutGeometry geometry;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DriverThemeVariant>(
      valueListenable: themeListenable ?? driverThemeNotifier,
      builder: (context, variant, _) {
        final palette = paletteForDriverTheme(variant);
        // NAV-TELLERS-EXACT-LIVE-VIEWPORT-1: one authoritative geometry drives
        // the map aperture, opaque chrome, gold frame, marker/selector/label
        // and (via the same resolve) camera padding. NO full-screen transparent
        // Material / AnimatedOpacity / BackdropFilter over the HC MapWidget.
        return KeyedSubtree(
          key: const ValueKey<String>('driver_tellers_view'),
          child: showLiveWindow
              ? _buildExactViewportStack(palette, geometry)
              : SafeArea(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 20 : 12,
                      vertical: isLandscape ? 8 : 12,
                    ),
                    child: _buildMetersPanel(
                      palette,
                      withControls: true,
                      fillHeight: isLandscape,
                    ),
                  ),
                ),
        );
      },
    );
  }

  /// TELLERS-LIVE-NAV-INSTRUCTION-OVERLAY-1: the current maneuver instruction,
  /// painted inside the live map below the "Live navigatie" badge and the
  /// Car/Arrow selector.
  ///
  /// Reuses the very widgets the main navigation screen uses — the same
  /// [DriverTurnInstructionBanner] fed by the same authoritative
  /// [ResponsiveManeuverPresentation], and the same [DriverNavLoadingBanner]
  /// with the driver page's own localized copy. Nothing about the maneuver is
  /// decided here, so the two surfaces cannot drift apart.
  ///
  /// Returns null when there is nothing authoritative to show, or when the
  /// aperture is too small to carry the card (typically a phone), so a cramped
  /// layout never gets an empty dark rectangle over its map.
  /// Tablet cockpit moves maneuver into the branded header — avoid a second
  /// instruction card over the live map aperture.
  bool get _tabletHeaderOwnsGuidance => isTablet && guidance.isVisible;

  Positioned? _buildGuidanceOverlay({
    required DriverTellersLayoutGeometry geometry,
    required bool selectorVisible,
  }) {
    if (!guidance.isVisible) return null;
    if (_tabletHeaderOwnsGuidance) return null;
    final layout = resolveDriverTellersGuidanceLayout(
      geometry: geometry,
      selectorVisible: selectorVisible,
    );
    if (!layout.fits) return null;

    final Widget card;
    switch (guidance.phase) {
      case DriverTellersGuidancePhase.instruction:
        final p = guidance.presentation!;
        // NAV-SIGNAGE-FIELD-QUALITY-P0-1: Tellers + navigatie split on tablet
        // must use dedicated split readability metrics — never phone-mini.
        final splitReadability = isTablet
            ? NavSignageTabletReadabilityMetrics.forSplitNav(
                availableBannerWidth: layout.maxWidth,
              )
            : null;
        card = DriverTurnInstructionBanner(
          // Lighter and smaller than the primary navigation banner, but the
          // same widget, the same icon resolver and the same localized text.
          compact: true,
          isTablet: isTablet,
          isArrival: p.isArrival,
          isHighwayLike: p.isHighwayLike,
          distancePrefix: '',
          distanceText: p.distanceLabel,
          primaryText: p.primaryInstruction,
          secondaryText: p.secondaryInstruction,
          icon: driverManeuverVisualIconData(p.maneuverVisual),
          presentation: p,
          tabletReadability: splitReadability,
          themeListenable: themeListenable,
        );
      case DriverTellersGuidancePhase.loading:
        card = DriverNavLoadingBanner(
          compact: true,
          isTablet: isTablet,
          text: guidance.loadingText,
          themeListenable: themeListenable,
        );
      case DriverTellersGuidancePhase.hidden:
        return null;
    }

    return Positioned(
      left: layout.left,
      top: layout.top,
      width: layout.maxWidth,
      child: KeyedSubtree(
        key: const ValueKey<String>('driver_tellers_guidance'),
        // The banner is content-aware and left-aligns itself inside this box,
        // so a short instruction stays compact while a long one grows only to
        // the map-pane maximum.
        child: card,
      ),
    );
  }

  /// Full-viewport Stack: opaque chrome slabs leave only [liveWindowRect]
  /// uncovered; meters/controls panels and the gold live frame are positioned
  /// from the same geometry.
  Widget _buildExactViewportStack(
    DriverThemePalette palette,
    DriverTellersLayoutGeometry geometry,
  ) {
    final chrome = driverTellersOpaqueChromeRects(geometry);
    final corners = driverTellersCornerBleedBlockers(geometry);
    final live = geometry.liveWindowRect;
    final meters = geometry.metersPanelRect;
    final controls = geometry.controlsRect;
    final price = geometry.priceSummaryRect;
    // Tablet cockpit: vertical chrome in both orientations. Phone landscape
    // still nests controls inside the left meters panel.
    final controlsInMetersPanel = isLandscape && !isTablet;

    // NAV-ORIENTATION-VIEWPORT-STABILITY-P0-1: explicit hard-edge clip on the
    // Tellers exact-viewport Stack — a stale Positioned child computed from a
    // previous-epoch geometry can never paint outside the current viewport
    // bounds during a portrait ↔ landscape transition.
    return Stack(
      key: const ValueKey<String>('driver_tellers_geometry_stack'),
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        // Opaque aperture chrome — fully covers every region outside the live
        // window (outer margins, gaps, system-inset bands, inter-panel space).
        for (var i = 0; i < chrome.length; i++)
          if (chrome[i].width > 0 && chrome[i].height > 0)
            Positioned(
              key: ValueKey<String>('driver_tellers_chrome_$i'),
              left: chrome[i].left,
              top: chrome[i].top,
              width: chrome[i].width,
              height: chrome[i].height,
              child: RepaintBoundary(
                child: ColoredBox(color: palette.background),
              ),
            ),
        // Rounded-corner bleed blockers inside the live rect corners.
        for (var i = 0; i < corners.length; i++)
          Positioned(
            key: ValueKey<String>('driver_tellers_corner_$i'),
            left: corners[i].left,
            top: corners[i].top,
            width: corners[i].width,
            height: corners[i].height,
            child: IgnorePointer(
              child: ColoredBox(color: palette.background),
            ),
          ),
        // Opaque meters panel (phone landscape: left 44%; else top chrome).
        Positioned(
          left: meters.left,
          top: meters.top,
          width: meters.width,
          height: meters.height,
          child: _buildMetersPanel(
            palette,
            withControls: controlsInMetersPanel,
            // Phone fills tall 2×2 tiles; tablet cockpit stays compact.
            fillHeight: !isTablet,
          ),
        ),
        if (isTablet && price.width > 0 && price.height > 0)
          Positioned(
            left: price.left,
            top: price.top,
            width: price.width,
            height: price.height,
            child: _buildPriceSummaryCard(palette),
          ),
        // Portrait phone + tablet action bar (skipped when rect is zero).
        if (!controlsInMetersPanel &&
            controls.width > 0 &&
            controls.height > 0)
          Positioned(
            left: controls.left,
            top: controls.top,
            width: controls.width,
            height: controls.height,
            child: RepaintBoundary(
              child: Container(
                key: const ValueKey<String>('driver_tellers_controls_panel'),
                padding: EdgeInsets.all(isTablet ? 8 : 8),
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: BorderRadius.circular(isTablet ? 16 : 20),
                  border: Border.all(color: palette.border.withOpacity(0.5)),
                ),
                child: _buildFooterActions(palette),
              ),
            ),
          ),
        // Exact live aperture — genuinely uncovered interior + gold frame.
        Positioned(
          left: live.left,
          top: live.top,
          width: live.width,
          height: live.height,
          child: _buildLiveWindow(palette, geometry),
        ),
      ],
    );
  }

  Widget _buildMetersPanel(
    DriverThemePalette palette, {
    required bool withControls,
    bool fillHeight = false,
  }) {
    // TABLET-TELLERS-COCKPIT-P1: compact brand header + title + dense KPIs.
    // Phone path unchanged (header + 2×2 + status [+ landscape controls]).
    final content = isTablet
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.max,
            children: [
              // Brand + maneuver always reserved (never collapses into KPIs).
              _buildTabletBrandedNavHeader(palette),
              SizedBox(height: kTellersTabletCockpitInnerGap),
              SizedBox(
                height: kTellersTabletCockpitTitleH,
                child: _buildHeader(palette, compact: true),
              ),
              SizedBox(height: kTellersTabletCockpitInnerGap),
              // Fixed KPI band — never Expanded into leftover scraps.
              SizedBox(
                key: const ValueKey<String>('driver_tellers_kpi_band'),
                height: driverTellersTabletFourAcrossKpis(
                  geometry.metersPanelRect.width,
                )
                    ? kTellersTabletCockpitKpiRowH
                    : kTellersTabletCockpitKpiWrapH,
                child: _buildMetersGrid(
                  palette,
                  fillHeight: true,
                  compact: true,
                ),
              ),
              if (withControls) ...[
                SizedBox(height: isLandscape ? 6 : 8),
                _buildFooterActions(palette),
              ],
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
            children: [
              _buildHeader(palette),
              SizedBox(height: isLandscape ? 8 : 12),
              if (fillHeight)
                Expanded(child: _buildMetersGrid(palette, fillHeight: true))
              else
                _buildMetersGrid(palette),
              SizedBox(height: isLandscape ? 6 : 10),
              _buildStatusChip(palette),
              if (withControls) ...[
                SizedBox(height: isLandscape ? 8 : 12),
                _buildFooterActions(palette),
              ],
            ],
          );
    // NAV-PHONE-DRIVER-VIEW-FLICKER-1: fully OPAQUE panel (no per-frame alpha
    // blending over the HC platform view) isolated in its own RepaintBoundary,
    // so fare/timer/location ticks repaint only this panel and never the map.
    return RepaintBoundary(
      child: Container(
        key: const ValueKey<String>('driver_tellers_meters_panel'),
        padding: EdgeInsets.all(isTablet ? 10 : 10),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(isTablet ? 16 : 20),
          border: Border.all(color: palette.border.withOpacity(0.5)),
        ),
        child: content,
      ),
    );
  }

  /// Compact transparent brand + maneuver strip — same conceptual family as
  /// [NavTabletBrandedHeader], theme-accent border, no second signage system.
  Widget _buildTabletBrandedNavHeader(DriverThemePalette palette) {
    final brandH = isLandscape
        ? kTellersTabletCockpitBrandHLandscape
        : kTellersTabletCockpitBrandHPortrait;
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = NavTabletBrandedHeaderMetrics.resolve(
          availableWidth: constraints.maxWidth,
          isLandscape: isLandscape,
          cardHeight: brandH,
          gap: 8,
          includeMenu: false,
          // Tellers cockpit must stay compact — never inherit nav's 110/120 floor.
          minCardHeight: isLandscape ? 48 : 60,
          maxCardHeight: isLandscape ? 64 : 84,
        );
        final maneuver = _buildTabletHeaderManeuver(metrics);
        return KeyedSubtree(
          key: const ValueKey<String>('driver_tellers_tablet_branded_header'),
          child: SizedBox(
            height: metrics.cardHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  key: const ValueKey<String>('driver_tellers_tablet_brand_slot'),
                  width: metrics.brandWidth,
                  height: metrics.cardHeight,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(metrics.radius),
                      border: Border.all(
                        color: palette.accent.withOpacity(0.55),
                        width: 1.2,
                      ),
                    ),
                    child: Center(
                      child: brandLogo ??
                          Text(
                            'Fluxidi',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: isLandscape ? 16 : 18,
                              color: palette.textPrimary,
                            ),
                          ),
                    ),
                  ),
                ),
                SizedBox(width: metrics.gap),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SizedBox(
                      key: const ValueKey<String>(
                        'driver_tellers_tablet_maneuver_slot',
                      ),
                      height: metrics.cardHeight,
                      width: double.infinity,
                      child: maneuver != null
                          ? ClipRect(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: metrics.maneuverMaxWidth,
                                  child: maneuver,
                                ),
                              ),
                            )
                          : _buildTabletManeuverPlaceholder(palette),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Reserved maneuver chrome when guidance is momentarily hidden so the
  /// header never collapses to logo-only.
  Widget _buildTabletManeuverPlaceholder(DriverThemePalette palette) {
    final label = driverTellersLiveNavigationLabel(markerLanguage);
    return Container(
      key: const ValueKey<String>('driver_tellers_tablet_maneuver_placeholder'),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surface.withOpacity(palette.isDark ? 0.85 : 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border.withOpacity(0.55)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: isLandscape ? 13 : 14,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary.withOpacity(0.8),
        ),
      ),
    );
  }

  Widget? _buildTabletHeaderManeuver(NavTabletBrandedHeaderMetrics metrics) {
    if (!guidance.isVisible) return null;
    switch (guidance.phase) {
      case DriverTellersGuidancePhase.instruction:
        final p = guidance.presentation!;
        // Compact header band: reuse the same banner widget + presentation,
        // but skip split-nav readability metrics that assume a taller map card.
        return DriverTurnInstructionBanner(
          compact: true,
          isTablet: true,
          isArrival: p.isArrival,
          isHighwayLike: p.isHighwayLike,
          distancePrefix: '',
          distanceText: p.distanceLabel,
          primaryText: p.primaryInstruction,
          secondaryText: p.secondaryInstruction,
          icon: driverManeuverVisualIconData(p.maneuverVisual),
          presentation: p,
          themeListenable: themeListenable,
        );
      case DriverTellersGuidancePhase.loading:
        return DriverNavLoadingBanner(
          compact: true,
          isTablet: true,
          text: guidance.loadingText,
          themeListenable: themeListenable,
        );
      case DriverTellersGuidancePhase.hidden:
        return null;
    }
  }

  Widget _buildPriceSummaryCard(DriverThemePalette palette) {
    final label = snapshot.usesFixedPrice
        ? driverTellersFixedRidePriceLabel(markerLanguage)
        : driverTellersEstimatedRidePriceLabel(markerLanguage);
    return RepaintBoundary(
      child: Container(
        key: const ValueKey<String>('driver_tellers_price_summary'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: palette.surface.withOpacity(palette.isDark ? 0.94 : 0.98),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: palette.accent.withOpacity(0.75),
            width: 1.4,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isLandscape ? 13 : 14,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary.withOpacity(0.78),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              key: const ValueKey<String>('driver_tellers_price_summary_amount'),
              snapshot.fareText,
              maxLines: 1,
              style: TextStyle(
                fontSize: isLandscape ? 22 : 24,
                fontWeight: FontWeight.w900,
                color: palette.textPrimary,
                height: 1.05,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// NAV-TELLERS-EXACT-LIVE-VIEWPORT-1: live aperture whose gold frame, label,
  /// selector and marker anchor are all positioned from [geometry]. The
  /// interior stays genuinely uncovered so the single retained MapWidget shows
  /// through — no second MapWidget, no full-screen transparent Material.
  Widget _buildLiveWindow(
    DriverThemePalette palette,
    DriverTellersLayoutGeometry geometry,
  ) {
    // NAV-TELLERS-SINGLE-MAP-MARKER-OWNER-1: no Flutter Car/Arrow child is
    // painted inside the Tellers live window. The single vehicle marker is the
    // Mapbox annotation ordinary Navigation already owns, projected at the
    // Tellers marker anchor by the follow-camera padding (see
    // NAV-TELLERS-ROUTE-CENTERLINE-LOCK-1). [showVehicleMarker] and
    // [vehicleMarkerIconSize] are retained on the widget's public API for
    // source compat but no longer control any paint here.
    final live = geometry.liveWindowRect;
    // Convert absolute geometry rects into local coords inside this Positioned.
    final labelLocal = geometry.labelRect.shift(-live.topLeft);
    final selectorLocal = geometry.selectorRect.shift(-live.topLeft);
    final markerLocal = geometry.markerAnchor - live.topLeft;
    final liveLabel = driverTellersLiveNavigationLabel(markerLanguage);
    final selectorVisible =
        showMarkerSelector && onMarkerChoiceSelected != null;
    final guidanceOverlay = _buildGuidanceOverlay(
      geometry: geometry,
      selectorVisible: selectorVisible,
    );

    return RepaintBoundary(
      child: Container(
        key: const ValueKey<String>('driver_tellers_live_window'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(geometry.cornerRadius),
          border: Border.all(
            color: palette.accent.withOpacity(0.7),
            width: 2,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Label / selector use geometry insets (top-left / top-right) but
            // intrinsic width so the compact selector never overflows the
            // reserved band on narrow phone apertures.
            Positioned(
              left: labelLocal.left,
              top: labelLocal.top,
              child: Container(
                key: const ValueKey<String>('driver_tellers_live_label'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  liveLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isTablet ? 12 : 11,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary.withOpacity(0.85),
                  ),
                ),
              ),
            ),
            if (selectorVisible)
              Positioned(
                top: selectorLocal.top,
                right: 8,
                child: KeyedSubtree(
                  key: const ValueKey<String>('driver_tellers_marker_selector'),
                  child: NavigationDriverMarkerChoiceSelector(
                    selectedChoice: markerChoice,
                    onSelected: onMarkerChoiceSelected!,
                    accentColor: palette.accent,
                    textColor: palette.textPrimary,
                    surfaceColor: palette.surface,
                    language: markerLanguage,
                    compactLandscape: true,
                  ),
                ),
              ),
            if (guidanceOverlay != null) guidanceOverlay,
            // NAV-TELLERS-SINGLE-MAP-MARKER-OWNER-1: intentionally NO Flutter
            // Car/Arrow child here — the single Mapbox annotation is the only
            // vehicle marker owner in Tellers. Placing a second Flutter Car
            // caused field-visible duplicates.
            // NAV-TELLERS-ROTATION-COMPOSITION-AND-POSE-LOCK-1 (Commit 2):
            // development-only crosshair at the marker road-contact anchor
            // (== camera target anchor). Never rendered in release, and only
            // when explicitly enabled via FLUXIDI_NAV_TELLERS_POSE_DEBUG.
            if (kNavTellersPoseDebugEnabled && !kReleaseMode)
              Positioned(
                left: markerLocal.dx - 12,
                top: markerLocal.dy - 12,
                width: 24,
                height: 24,
                child: const IgnorePointer(
                  child: KeyedSubtree(
                    key: ValueKey<String>('driver_tellers_pose_debug_crosshair'),
                    child: _TellersPoseDebugCrosshair(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(DriverThemePalette palette) {
    // NAV-PARKING-2 Commit 4: status is a small secondary element, never a
    // fifth equal meter tile.
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const ValueKey<String>('driver_tellers_status'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: palette.border.withOpacity(0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isWaiting ? const Color(0xFFFFB020) : palette.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              snapshot.statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isTablet ? 13 : 12,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary.withOpacity(0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(DriverThemePalette palette, {bool compact = false}) {
    final title = driverTellersTitle(markerLanguage);
    final navLabel = driverTellersNavigationLabel(markerLanguage);
    final titleSize = compact
        ? (isLandscape ? 18.0 : 20.0)
        : (isTablet ? 28.0 : 22.0);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.w900,
              color: palette.textPrimary,
            ),
          ),
        ),
        Semantics(
          button: true,
          label: navLabel,
          child: FilledButton.icon(
            key: const ValueKey<String>('driver_tellers_back_nav'),
            onPressed: onBackToNavigation,
            icon: Icon(Icons.map_outlined, size: compact ? 18 : 20),
            label: Text(navLabel),
            style: FilledButton.styleFrom(
              backgroundColor: palette.accent,
              foregroundColor: palette.isDark ? Colors.black : Colors.white,
              minimumSize: Size(compact ? 40 : 48, compact ? 36 : 48),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 14,
                vertical: compact ? 6 : 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// NAV-PARKING-2 Commit 4: exactly FOUR principal meter tiles.
  /// Phone: balanced 2×2. Tablet cockpit: 4-across when width allows, else 2×2.
  Widget _buildMetersGrid(
    DriverThemePalette palette, {
    bool fillHeight = false,
    bool compact = false,
  }) {
    final defaultFare = driverTellersFareLabel(markerLanguage);
    final fareLabel = snapshot.fareLabel.trim().isEmpty
        ? defaultFare
        : snapshot.fareLabel.trim();
    final distanceLabel = driverTellersDistanceLabel(markerLanguage);
    final durationLabel = driverTellersDurationLabel(markerLanguage);
    final waitingLabel = driverTellersWaitingLabel(markerLanguage);
    final fare = _MeterTile(
      key: const ValueKey('teller_fare'),
      label: fareLabel,
      value: snapshot.fareText,
      semanticLabel: '$fareLabel ${snapshot.fareText}',
      palette: palette,
      emphasize: true,
      isTablet: isTablet,
      isLandscape: isLandscape,
      compact: compact,
    );
    final distance = _MeterTile(
      key: const ValueKey('teller_distance'),
      label: distanceLabel,
      value: snapshot.distanceTravelledText,
      semanticLabel: '$distanceLabel ${snapshot.distanceTravelledText}',
      palette: palette,
      isTablet: isTablet,
      isLandscape: isLandscape,
      compact: compact,
    );
    final duration = _MeterTile(
      key: const ValueKey('teller_duration'),
      label: durationLabel,
      value: snapshot.rideDurationText,
      semanticLabel: '$durationLabel ${snapshot.rideDurationText}',
      palette: palette,
      isTablet: isTablet,
      isLandscape: isLandscape,
      compact: compact,
    );
    final waiting = _MeterTile(
      key: const ValueKey('teller_waiting'),
      label: waitingLabel,
      value: snapshot.waitingTimeText,
      semanticLabel: '$waitingLabel ${snapshot.waitingTimeText}',
      palette: palette,
      isTablet: isTablet,
      isLandscape: isLandscape,
      compact: compact,
    );

    Widget row(Widget a, Widget b) => Row(
          crossAxisAlignment: fillHeight
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.center,
          children: [
            Expanded(child: a),
            SizedBox(width: compact ? 8 : 10),
            Expanded(child: b),
          ],
        );

    if (compact) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final fourAcross =
              driverTellersTabletFourAcrossKpis(constraints.maxWidth);
          if (fourAcross) {
            return Row(
              key: const ValueKey<String>('driver_tellers_kpi_row_4'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: fare),
                const SizedBox(width: 8),
                Expanded(child: distance),
                const SizedBox(width: 8),
                Expanded(child: duration),
                const SizedBox(width: 8),
                Expanded(child: waiting),
              ],
            );
          }
          return Column(
            key: const ValueKey<String>('driver_tellers_kpi_wrap_2x2'),
            children: [
              Expanded(child: row(fare, distance)),
              const SizedBox(height: 8),
              Expanded(child: row(duration, waiting)),
            ],
          );
        },
      );
    }

    // Balanced 2x2 in all phone layouts. When [fillHeight] the rows expand to
    // consume the available column height (tall, high-weight tiles).
    if (fillHeight) {
      return Column(
        children: [
          Expanded(child: row(fare, distance)),
          const SizedBox(height: 10),
          Expanded(child: row(duration, waiting)),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row(fare, distance),
        const SizedBox(height: 10),
        row(duration, waiting),
      ],
    );
  }

  Widget _buildFooterActions(DriverThemePalette palette) {
    // NAV-TELLERS-RECENTER-CONTROL-1: desired order Pauze | Recenter | Stop.
    // Pauze/Stop stay large Expanded buttons; Recenter is a central icon
    // button at the driving min touch-target (48).
    final actions = <Widget>[];
    if (onToggleWait != null) {
      actions.add(
        Expanded(
          child: OutlinedButton(
            key: const ValueKey('driver_tellers_wait'),
            onPressed: onToggleWait,
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.textPrimary,
              side: BorderSide(color: palette.border),
              minimumSize: const Size(48, 48),
            ),
            child: Text(
              isWaiting
                  ? driverTellersResumeLabel(markerLanguage)
                  : driverTellersPauseLabel(markerLanguage),
            ),
          ),
        ),
      );
    }
    if (onRecenter != null) {
      if (actions.isNotEmpty) actions.add(const SizedBox(width: 10));
      final recenterLabel = driverTellersRecenterLabel(markerLanguage);
      actions.add(
        SizedBox(
          width: 48,
          height: 48,
          child: Tooltip(
            message: recenterLabel,
            child: OutlinedButton(
              key: const ValueKey('driver_tellers_recenter'),
              onPressed: onRecenter,
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.textPrimary,
                side: BorderSide(color: palette.border),
                minimumSize: const Size(48, 48),
                padding: EdgeInsets.zero,
              ),
              child: Semantics(
                button: true,
                label: recenterLabel,
                child: const Icon(Icons.my_location, size: 22),
              ),
            ),
          ),
        ),
      );
    }
    if (onStop != null) {
      if (actions.isNotEmpty) actions.add(const SizedBox(width: 10));
      actions.add(
        Expanded(
          child: OutlinedButton(
            key: const ValueKey('driver_tellers_stop'),
            onPressed: onStop,
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.textPrimary,
              side: BorderSide(color: palette.accent.withOpacity(0.8)),
              minimumSize: const Size(48, 48),
            ),
            child: const Text('Stop'),
          ),
        ),
      );
    }
    if (actions.isEmpty) return const SizedBox.shrink();
    return Row(
      key: const ValueKey('driver_tellers_controls'),
      children: actions,
    );
  }
}

/// NAV-TELLERS-ROTATION-COMPOSITION-AND-POSE-LOCK-1 (Commit 2): development-only
/// crosshair drawn at the marker road-contact anchor. Enabled only behind
/// [kNavTellersPoseDebugEnabled]; never a normal profile/release element.
class _TellersPoseDebugCrosshair extends StatelessWidget {
  const _TellersPoseDebugCrosshair();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _TellersPoseDebugCrosshairPainter());
  }
}

class _TellersPoseDebugCrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF00FF)
      ..strokeWidth = 1.5;
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), paint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), paint);
  }

  @override
  bool shouldRepaint(covariant _TellersPoseDebugCrosshairPainter oldDelegate) =>
      false;
}

class _MeterTile extends StatelessWidget {
  const _MeterTile({
    super.key,
    required this.label,
    required this.value,
    required this.semanticLabel,
    required this.palette,
    required this.isTablet,
    required this.isLandscape,
    this.emphasize = false,
    this.compact = false,
  });

  final String label;
  final String value;
  final String semanticLabel;
  final DriverThemePalette palette;
  final bool isTablet;
  final bool isLandscape;
  final bool emphasize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final valueSize = compact
        ? (isLandscape ? 22.0 : 24.0)
        : isTablet
            ? (isLandscape ? 36.0 : 40.0)
            : (isLandscape ? 18.0 : 28.0);
    final labelSize = compact
        ? (isLandscape ? 11.0 : 12.0)
        : (isTablet ? 14.0 : 12.0);
    return Semantics(
      label: semanticLabel,
      child: Container(
        constraints: compact
            ? const BoxConstraints(minHeight: 72)
            : const BoxConstraints(),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : (isTablet ? 18 : 12),
          vertical: compact ? 8 : (isTablet ? 16 : 10),
        ),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: palette.surface.withOpacity(palette.isDark ? 0.94 : 0.98),
          borderRadius: BorderRadius.circular(compact ? 12 : 16),
          border: Border.all(
            color: emphasize
                ? palette.accent.withOpacity(0.85)
                : palette.border.withOpacity(0.7),
            width: emphasize ? 1.8 : 1.1,
          ),
        ),
        // NAV-TELLERS-EXACT-LIVE-VIEWPORT-1: in Expanded geometry bands the
        // value scales down; in unconstrained panels it sizes naturally.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bounded = constraints.hasBoundedHeight &&
                constraints.maxHeight < double.infinity;
            final valueText = FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: valueSize,
                  fontWeight: FontWeight.w900,
                  color: palette.textPrimary,
                  height: 1.05,
                ),
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: labelSize,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary.withOpacity(0.72),
                  ),
                ),
                SizedBox(height: compact ? 2 : 4),
                if (bounded) Flexible(child: valueText) else valueText,
              ],
            );
          },
        ),
      ),
    );
  }
}
