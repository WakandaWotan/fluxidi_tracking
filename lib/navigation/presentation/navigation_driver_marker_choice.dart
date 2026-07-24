import '../../app_strings.dart';

/// NAV-VEHICLE-MODE-CAR-ARROW-1: the two — and only two — public navigation
/// marker choices. This replaces the experimental 3D vehicle presentation
/// choice (2D / Fluxidi / Classic). The map style (light / dark / 3D
/// buildings / satellite) is an independent setting and never gates this
/// choice.
enum DriverNavigationMarkerChoice { car, arrow }

/// Default marker for a fresh install and for any legacy/unknown stored value.
const DriverNavigationMarkerChoice kDriverNavigationMarkerChoiceDefault =
    DriverNavigationMarkerChoice.car;

/// Where a resolved marker choice originated (bounded diagnostics only).
enum DriverNavigationMarkerChoiceSource { user, restored, legacyMigration }

String driverNavigationMarkerChoiceSourceLabel(
  DriverNavigationMarkerChoiceSource source,
) {
  switch (source) {
    case DriverNavigationMarkerChoiceSource.user:
      return 'user';
    case DriverNavigationMarkerChoiceSource.restored:
      return 'restored';
    case DriverNavigationMarkerChoiceSource.legacyMigration:
      return 'legacy_migration';
  }
}

/// Stable persistence token written to storage. Never localized.
String driverNavigationMarkerChoiceStorageValue(
  DriverNavigationMarkerChoice choice,
) {
  switch (choice) {
    case DriverNavigationMarkerChoice.car:
      return 'car';
    case DriverNavigationMarkerChoice.arrow:
      return 'arrow';
  }
}

/// Bounded-diagnostics log label (identical to the storage token).
String driverNavigationMarkerChoiceLogLabel(
  DriverNavigationMarkerChoice choice,
) =>
    driverNavigationMarkerChoiceStorageValue(choice);

/// NAV-TELLERS-MARKER-CHOICE-APPLY-1: the bitmap source the single Mapbox
/// vehicle annotation renders for a given choice.
enum DriverNavigationMarkerIconSource {
  /// Existing yellow top-down taxi PNG asset (the "Car" choice).
  taxiPng,

  /// Rasterised 2D navigation arrow glyph (the "Arrow" choice).
  arrowGlyph,
}

/// Pure mapping from a marker [choice] to the Mapbox annotation icon source.
///
/// Arrow resolves to [DriverNavigationMarkerIconSource.arrowGlyph] only when
/// its rasterised bytes are available; otherwise it safely falls back to the
/// taxi PNG so the single annotation always has a valid bitmap and Car/Arrow
/// never share the wrong cached bytes.
DriverNavigationMarkerIconSource driverNavigationMarkerIconSourceFor(
  DriverNavigationMarkerChoice choice, {
  bool arrowAvailable = true,
}) {
  if (choice == DriverNavigationMarkerChoice.arrow && arrowAvailable) {
    return DriverNavigationMarkerIconSource.arrowGlyph;
  }
  return DriverNavigationMarkerIconSource.taxiPng;
}

/// Pure decision: does the live Mapbox annotation need an icon swap (delete +
/// recreate, since Mapbox cannot change a bitmap image in place) to reflect the
/// currently [selected] choice? [applied] is the choice the live annotation
/// last rendered (null when there is no live annotation yet). Idempotent:
/// re-selecting the already-applied choice returns false → no recreation.
bool driverNavigationMarkerNeedsIconSwap({
  required DriverNavigationMarkerChoice? applied,
  required DriverNavigationMarkerChoice selected,
}) =>
    applied != selected;

/// Localized driver-facing label (NL / EN / FR / ES).
String driverNavigationMarkerChoiceLabel(
  DriverNavigationMarkerChoice choice,
  AppLanguage language,
) {
  switch (language) {
    case AppLanguage.nl:
      return choice == DriverNavigationMarkerChoice.car ? 'Auto' : 'Pijl';
    case AppLanguage.fr:
      return choice == DriverNavigationMarkerChoice.car ? 'Voiture' : 'Flèche';
    case AppLanguage.es:
      return choice == DriverNavigationMarkerChoice.car ? 'Coche' : 'Flecha';
    case AppLanguage.en:
      return choice == DriverNavigationMarkerChoice.car ? 'Car' : 'Arrow';
  }
}

/// Outcome of resolving a stored raw marker-choice string.
class DriverNavigationMarkerChoiceResolution {
  const DriverNavigationMarkerChoiceResolution({
    required this.choice,
    required this.source,
    required this.wasStored,
    required this.needsRewrite,
  });

  /// The resolved (never-null) marker choice.
  final DriverNavigationMarkerChoice choice;

  /// Where the resolved value came from.
  final DriverNavigationMarkerChoiceSource source;

  /// Whether a non-empty value was actually present in storage.
  final bool wasStored;

  /// Whether storage should be normalized to [choice] (legacy migration).
  final bool needsRewrite;
}

/// Safely resolves a stored raw value into a valid marker choice.
///
/// - `car` / `arrow` → restored as-is.
/// - Legacy 3D values (`fluxidi`, `classic`, `taxi2d`, `fluxidi3d`,
///   `classic3d`, `fluxidi_taxi`, `classic_taxi`, `classic_flying_taxi`,
///   `2d`) and any unknown non-empty value → migrated to [car].
/// - Empty / null → default [car] (fresh install, not a migration).
///
/// Never throws and never yields an empty/unknown choice.
DriverNavigationMarkerChoiceResolution resolveStoredNavigationMarkerChoice(
  String? raw,
) {
  final value = (raw ?? '').trim().toLowerCase();
  if (value.isEmpty) {
    return const DriverNavigationMarkerChoiceResolution(
      choice: kDriverNavigationMarkerChoiceDefault,
      source: DriverNavigationMarkerChoiceSource.restored,
      wasStored: false,
      needsRewrite: false,
    );
  }
  if (value == 'car') {
    return const DriverNavigationMarkerChoiceResolution(
      choice: DriverNavigationMarkerChoice.car,
      source: DriverNavigationMarkerChoiceSource.restored,
      wasStored: true,
      needsRewrite: false,
    );
  }
  if (value == 'arrow') {
    return const DriverNavigationMarkerChoiceResolution(
      choice: DriverNavigationMarkerChoice.arrow,
      source: DriverNavigationMarkerChoiceSource.restored,
      wasStored: true,
      needsRewrite: false,
    );
  }
  // Any legacy 3D value or unknown token migrates safely to the default car.
  return const DriverNavigationMarkerChoiceResolution(
    choice: kDriverNavigationMarkerChoiceDefault,
    source: DriverNavigationMarkerChoiceSource.legacyMigration,
    wasStored: true,
    needsRewrite: true,
  );
}
