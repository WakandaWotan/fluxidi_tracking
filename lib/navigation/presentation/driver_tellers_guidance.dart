// TELLERS-LIVE-NAV-INSTRUCTION-OVERLAY-1
//
// Pure presentation policy for the maneuver instruction shown on the Tellers
// live-navigation map.
//
// Everything here is a function of state the driver page ALREADY owns. This
// file deliberately contains no route steps, no maneuver index, no Directions
// parsing and no lane resolution: Tellers renders the same authoritative
// `ResponsiveManeuverPresentation` the main navigation banner renders, so the
// two surfaces can never disagree.

import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show immutable;
import 'package:fluxidi_tracking/navigation/presentation/driver_tellers_layout_geometry.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';

/// What the Tellers live map should show, if anything.
enum DriverTellersGuidancePhase {
  /// No overlay at all — never an empty card.
  hidden,

  /// Route is being (re)calculated; the stale maneuver must not stay visible.
  loading,

  /// An authoritative maneuver instruction is available.
  instruction,
}

/// Immutable render instruction handed to the Tellers view.
///
/// Carries the already-resolved presentation rather than any raw route data,
/// which is what keeps maneuver ownership in exactly one place.
@immutable
class DriverTellersGuidanceView {
  const DriverTellersGuidanceView({
    required this.phase,
    this.presentation,
    this.loadingText = '',
    this.routeVersion = 0,
  });

  const DriverTellersGuidanceView.hidden()
    : phase = DriverTellersGuidancePhase.hidden,
      presentation = null,
      loadingText = '',
      routeVersion = 0;

  final DriverTellersGuidancePhase phase;

  /// The same object the main navigation banner renders. Null unless
  /// [phase] is [DriverTellersGuidancePhase.instruction].
  final ResponsiveManeuverPresentation? presentation;

  /// Already-localized recalculation/loading copy, supplied by the driver page
  /// so no new strings are invented here.
  final String loadingText;

  /// The accepted route generation this view belongs to. A new route
  /// generation replaces the whole view rather than mutating it, so a stale
  /// maneuver can never survive a route replacement.
  final int routeVersion;

  bool get isVisible => phase != DriverTellersGuidancePhase.hidden;
}

/// True when a presentation carries something worth painting. Guards against
/// a degraded snapshot producing an empty dark card on the map.
bool driverTellersGuidanceHasContent(ResponsiveManeuverPresentation? p) {
  if (p == null) return false;
  if (p.isArrival) return true;
  return p.primaryInstruction.trim().isNotEmpty;
}

/// Resolves what the Tellers map should show.
///
/// The priority order mirrors the main navigation screen exactly:
/// instruction wins, then the loading/recalculation state, then nothing.
/// [showInstructionBanner] is the driver page's own `_showNavInstructionBanner()`
/// result — it already suppresses the maneuver while a reroute is in flight
/// without accepted ownership, which is what makes "hide the stale maneuver
/// during reroute" automatic here.
///
/// The Tellers overlay intentionally does NOT mirror the main screen's
/// route-unavailable / "follow the route" chrome. It is additive guidance: it
/// shows an authoritative instruction or nothing at all.
DriverTellersGuidanceView resolveDriverTellersGuidance({
  required bool tellersActive,
  required bool followCameraActive,
  required bool liveRideActive,
  required bool showInstructionBanner,
  required bool navStepsLoading,
  required bool isRerouting,
  required bool snapshotIsLoadingSource,
  required ResponsiveManeuverPresentation? presentation,
  required String loadingText,
  required int routeVersion,
}) {
  if (!tellersActive || !followCameraActive || !liveRideActive) {
    return const DriverTellersGuidanceView.hidden();
  }
  if (showInstructionBanner && driverTellersGuidanceHasContent(presentation)) {
    return DriverTellersGuidanceView(
      phase: DriverTellersGuidancePhase.instruction,
      presentation: presentation,
      routeVersion: routeVersion,
    );
  }
  if (navStepsLoading || isRerouting || snapshotIsLoadingSource) {
    return DriverTellersGuidanceView(
      phase: DriverTellersGuidancePhase.loading,
      loadingText: loadingText,
      routeVersion: routeVersion,
    );
  }
  return const DriverTellersGuidanceView.hidden();
}

/// Inset from the live-window edges, matching the existing label/selector
/// insets so the overlay lines up with the chrome already on the map.
const double kDriverTellersGuidanceInset = 8;

/// Vertical gap between the "Live navigatie" badge / Car-Arrow selector band
/// and the guidance card.
const double kDriverTellersGuidanceTopGap = 8;

/// Horizontal safety gap kept clear next to the Car/Arrow selector.
const double kDriverTellersGuidanceSelectorGap = 12;

/// The Car/Arrow selector and the "Live navigatie" badge paint at their own
/// intrinsic size, which can exceed the band the layout geometry reserves for
/// them (the compact selector paints 56 pt against a 40 pt band). The guidance
/// card clears the larger of the two, so it cannot slide under a control that
/// is taller than its reservation. Both figures are guarded by tests that
/// measure the real widgets.
const double kDriverTellersSelectorPaintedHeight = 56;
const double kDriverTellersLabelPaintedHeight = 32;

/// Smallest card that still fits the maneuver icon plus two useful text lines.
const double kDriverTellersGuidanceMinWidthTablet = 224;
const double kDriverTellersGuidanceMinWidthPhone = 196;

/// Vertical room the card needs before it is worth showing at all.
const double kDriverTellersGuidanceMinHeight = 54;

/// Share of the map pane the card may occupy. Portrait 72% (rule: 68–76%),
/// landscape 70% (rule: 65–76%).
const double kDriverTellersGuidancePortraitFraction = 0.72;
const double kDriverTellersGuidanceLandscapeFraction = 0.70;

/// Where the guidance card goes inside the Tellers live window, in coordinates
/// local to that window.
@immutable
class DriverTellersGuidanceLayout {
  const DriverTellersGuidanceLayout({
    required this.left,
    required this.top,
    required this.maxWidth,
    required this.fits,
  });

  final double left;
  final double top;
  final double maxWidth;

  /// False when the live window is too small to carry the card without
  /// crowding the map or its controls — a phone aperture, typically. The
  /// overlay is then simply not shown.
  final bool fits;
}

/// Computes the card's placement from the one authoritative Tellers geometry.
///
/// Two independent guarantees keep the Car/Arrow selector clear:
///
///  1. the card starts below the whole badge/selector band, and
///  2. its width reserves the selector's declared width plus a gap, so it
///     cannot reach the selector column even if the bands ever align.
///
/// The second rule is what the product contract asks for: a deterministic
/// reserved-right-space calculation rather than relying on the card happening
/// to sit lower than the selector.
DriverTellersGuidanceLayout resolveDriverTellersGuidanceLayout({
  required DriverTellersLayoutGeometry geometry,
  required bool selectorVisible,
}) {
  final Rect live = geometry.liveWindowRect;
  final double mapWidth = live.width;
  final double mapHeight = live.height;
  if (!mapWidth.isFinite ||
      !mapHeight.isFinite ||
      mapWidth <= 0 ||
      mapHeight <= 0) {
    return const DriverTellersGuidanceLayout(
      left: kDriverTellersGuidanceInset,
      top: kDriverTellersGuidanceInset,
      maxWidth: 0,
      fits: false,
    );
  }

  // Below the taller of the two top-band occupants, measured against their
  // painted heights rather than their (smaller) reserved bands.
  // Phone omits the Live-navigation badge (labelRect is zero) so guidance
  // can sit higher without reserving empty label space.
  final bool hasLiveLabel = geometry.labelRect.width > 0 &&
      geometry.labelRect.height > 0;
  final double labelBottom = hasLiveLabel
      ? geometry.labelRect.top +
          math.max(geometry.labelRect.height, kDriverTellersLabelPaintedHeight)
      : live.top;
  final double selectorBottom =
      geometry.selectorRect.top +
      math.max(
        geometry.selectorRect.height,
        kDriverTellersSelectorPaintedHeight,
      );
  final double bandBottom = selectorVisible
      ? (hasLiveLabel ? math.max(labelBottom, selectorBottom) : selectorBottom)
      : labelBottom;
  final double top = hasLiveLabel || selectorVisible
      ? (bandBottom - live.top) + kDriverTellersGuidanceTopGap
      : kDriverTellersGuidanceInset;

  final double usable = math.max(
    0.0,
    mapWidth - kDriverTellersGuidanceInset * 2,
  );
  final double reserved = selectorVisible
      ? math.max(0.0, geometry.selectorRect.width) +
            kDriverTellersGuidanceSelectorGap
      : 0.0;
  final double byReserve = math.max(0.0, usable - reserved);
  final double byFraction =
      mapWidth *
      (geometry.isLandscape
          ? kDriverTellersGuidanceLandscapeFraction
          : kDriverTellersGuidancePortraitFraction);
  final double maxWidth = math.min(byFraction, byReserve);

  final double minWidth = geometry.isTablet
      ? kDriverTellersGuidanceMinWidthTablet
      : kDriverTellersGuidanceMinWidthPhone;
  final double availableHeight =
      mapHeight - top - kDriverTellersGuidanceInset;
  final bool fits =
      maxWidth >= minWidth &&
      availableHeight >= kDriverTellersGuidanceMinHeight;

  return DriverTellersGuidanceLayout(
    left: kDriverTellersGuidanceInset,
    top: top,
    maxWidth: maxWidth,
    fits: fits,
  );
}
