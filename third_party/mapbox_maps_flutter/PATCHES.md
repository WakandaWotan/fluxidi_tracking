# FLUXIDI Local Patches — mapbox_maps_flutter

## Upstream provenance

- **Package name**: `mapbox_maps_flutter`
- **Upstream version**: `2.18.0` (unchanged; the vendored `pubspec.yaml` still declares `version: 2.18.0`)
- **Upstream homepage**: https://github.com/mapbox/mapbox-maps-flutter
- **Original license**: preserved verbatim in `LICENSE` at this directory root
- **Vendored on**: 2026-07-17
- **Source location vendored from**: pub cache `mapbox_maps_flutter-2.18.0` on the developer's machine
- **Bundled Mapbox Maps Android SDK**: `com.mapbox.maps:android-ndk27:11.18.0` (unchanged, see `android/build.gradle`)

This directory is a **pinned local vendor** of the upstream 2.18.0 sources with
the minimum-surface Android controller lifecycle patch documented below. It is
consumed by the app via a `dependency_overrides.mapbox_maps_flutter` `path:`
entry in `pubspec.yaml` at the repository root.

## Deviation summary from upstream 2.18.0

Only the Android side is touched. iOS, Dart, examples, tests, README, license,
and every other file in this vendor tree are byte-for-byte identical to
upstream 2.18.0. The Flutter plugin's Dart API surface is unchanged.

## FLUXIDI-PATCH-1 — MapView lifecycle exposure for companion plugins

### Files added

* `android/src/main/kotlin/com/mapbox/maps/mapbox_maps/MapboxMapViewRegistry.kt`

  A new file in the plugin's own Kotlin namespace defining a
  `MapboxMapViewRegistry` singleton with a `Listener` interface. The registry
  holds each live `MapView` behind a `java.lang.ref.WeakReference` keyed by
  the plugin's own `channelSuffix`. It is `synchronized`-thread-safe, supports
  late listener attachment with replay of the currently-live registration
  set, and exposes:

    * `register(mapInstanceId: String, mapView: MapView)`
    * `unregister(mapInstanceId: String)`
    * `get(mapInstanceId: String): MapView?`
    * `activeMapInstanceIds(): List<String>`
    * `addListener(listener: Listener)` (replays existing registrations)
    * `removeListener(listener: Listener)`
    * `clearForTest()` (internal, unit test only)

  No `Activity`, `Context`, `FlutterEngine`, or strong `MapView` reference is
  retained by the registry beyond a `WeakReference`.

### Files modified

* `lib/src/mapbox_map.dart`

  One additive Dart-side getter added to `MapboxMap`:

      String get fluxidiMapInstanceId =>
        _mapboxMapsPlatform.channelSuffix.toString();

  Exposes the plugin's existing internal `channelSuffix` as a stable
  `String` so companion plugins can address the exact per-map registry
  entry from Dart. Every other public API on `MapboxMap` is unchanged.

* `android/build.gradle`

  Changed the Mapbox Maps Android SDK dependency scope from `implementation`
  to `api`:

      // FLUXIDI Phase 2A local patch: exposed as `api` (not `implementation`)
      // so consumer app modules can compile against the Mapbox SDK types
      // they need to reach the custom LocationProvider / FollowPuck
      // integration without redeclaring the dependency or its authenticated
      // maven repo.
      api "com.mapbox.maps:android-ndk27:11.18.0"

  No SDK version change. Runtime classpath is unaffected — the same Mapbox
  SDK version, artifact and classes ship. The change only widens compile-
  time visibility so companion app modules can use the SDK types.

* `android/src/main/kotlin/com/mapbox/maps/mapbox_maps/MapboxMapController.kt`

  Two hook calls added — no other logic changed:

    1. In `init` (immediately after `this.mapboxMap = mapboxMap` and before
       any subsystem controller construction), a single line:

           MapboxMapViewRegistry.register(this.channelSuffix, mapView)

    2. At the *very top* of `override fun dispose()`, before the
       `mapView == null` early-return, a single line:

           MapboxMapViewRegistry.unregister(this.channelSuffix)

  This ordering guarantees:

    * Every valid `dispose()` call deterministically fires
      `onMapViewUnregistered` on every attached listener so companion plugins
      can restore the stock Mapbox `LocationProvider` on this exact MapView
      before its subsystems tear down.
    * A duplicate `dispose()` call is still a no-op — the registry's
      `unregister` is idempotent, and the existing `mapView == null` guard
      still short-circuits the rest of dispose.

Nothing else in `MapboxMapController.kt` is modified. Every existing call
path — Pigeon API setUp/tearDown, controller construction, method channel
routing, controller-level dispose behavior — remains byte-for-byte identical
to upstream 2.18.0.

## Reversibility

To revert to the upstream pub-cache version:

1. Remove the `dependency_overrides` block from the repository root
   `pubspec.yaml`.
2. `flutter pub get`

The Dart-side app code stays fully compatible with an unpatched 2.18.0
because the patch only *adds* one Kotlin file plus two lines of registration
calls. Consumers that do not subscribe to `MapboxMapViewRegistry` observe
no behavior change.

## Non-goals for this patch

* No upstream Mapbox SDK version change.
* No changes to any Dart file in `lib/`.
* No changes to the iOS Swift plugin under `ios/`.
* No changes to the Pigeon-generated code.
* No exposure of internal subsystem controllers.
* No new public Dart API surface on the plugin.

## Why patch here and not in a separate plugin

The plugin holds each `MapView` inside a `private var mapView: FlutterMapView?`
field on `MapboxMapController`. There is no upstream API to obtain a MapView
by its platform-view id or by any other supported identifier. A companion
plugin cannot legitimately reach the MapView without either reflection, a
global view search, or creating a duplicate MapView. All three of those
alternatives are forbidden by the Fluxidi Phase 2A architecture (`NAV-
STREETLEVEL-FLUID-MOTION-2`). This registry patch is the minimum, reversible
change that preserves upstream 2.18.0 semantics while exposing the exact
per-controller MapView lifecycle to a companion Kotlin plugin.
