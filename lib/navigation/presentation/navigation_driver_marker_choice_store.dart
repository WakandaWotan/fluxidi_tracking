import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'navigation_driver_marker_choice.dart';

/// NAV-VEHICLE-MODE-CAR-ARROW-1: persistent store for the driver navigation
/// marker choice (Car / Arrow).
///
/// Follows the existing preference pattern (see [FluxidiAppLockStore]) using
/// [FlutterSecureStorage]. The marker choice is stored independently from the
/// map style so switching the map style never changes the marker choice.
class FluxidiNavigationMarkerChoiceStore {
  FluxidiNavigationMarkerChoiceStore._();

  static final FluxidiNavigationMarkerChoiceStore instance =
      FluxidiNavigationMarkerChoiceStore._();

  /// Storage key for the persisted marker choice token (`car` / `arrow`).
  static const String storageKey = 'nav_marker_choice';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Loads and safely resolves the stored marker choice. Migrates any legacy
  /// (`fluxidi`, `classic`, …) or unknown value to the default Car and
  /// normalizes storage in place. Never throws; falls back to the default.
  Future<DriverNavigationMarkerChoiceResolution> load() async {
    try {
      final raw = await _storage.read(key: storageKey);
      final resolution = resolveStoredNavigationMarkerChoice(raw);
      if (resolution.needsRewrite) {
        try {
          await _storage.write(
            key: storageKey,
            value: driverNavigationMarkerChoiceStorageValue(resolution.choice),
          );
        } catch (_) {
          // Best-effort normalization only.
        }
      }
      return resolution;
    } catch (_) {
      return const DriverNavigationMarkerChoiceResolution(
        choice: kDriverNavigationMarkerChoiceDefault,
        source: DriverNavigationMarkerChoiceSource.restored,
        wasStored: false,
        needsRewrite: false,
      );
    }
  }

  /// Persists the user's marker choice. Never throws.
  Future<void> save(DriverNavigationMarkerChoice choice) async {
    try {
      await _storage.write(
        key: storageKey,
        value: driverNavigationMarkerChoiceStorageValue(choice),
      );
    } catch (_) {
      // Persistence is best-effort; the in-memory choice remains authoritative.
    }
  }
}
