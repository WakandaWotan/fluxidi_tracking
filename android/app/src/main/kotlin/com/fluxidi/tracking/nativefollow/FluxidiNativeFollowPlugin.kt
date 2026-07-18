package com.fluxidi.tracking.nativefollow

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * FLUXIDI NAV-STREETLEVEL-FLUID-MOTION-2 Phase 2A — Flutter plugin that wires
 * [FluxidiNativeFollowManager] to the [io.flutter.embedding.engine.FlutterEngine]
 * lifecycle and registers the typed Pigeon [NativeFollowHostApi] on the
 * default binary messenger.
 *
 * The plugin is registered from `MainActivity.configureFlutterEngine` — it
 * cannot be discovered by [io.flutter.embedding.engine.plugins.util.GeneratedPluginRegistrant]
 * because it is app-local (there is no pubspec entry for it).
 */
class FluxidiNativeFollowPlugin : FlutterPlugin {
  private var manager: FluxidiNativeFollowManager? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val manager = FluxidiNativeFollowManager()
    NativeFollowHostApi.setUp(binding.binaryMessenger, manager)
    manager.attach()
    this.manager = manager
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    NativeFollowHostApi.setUp(binding.binaryMessenger, null)
    manager?.detach()
    manager = null
  }
}
