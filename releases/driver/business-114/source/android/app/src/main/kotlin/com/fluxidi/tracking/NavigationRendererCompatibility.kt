package com.fluxidi.tracking

/** Narrow mitigation for the captured SM-X400/Android16 Mali Vulkan OOM.
 * This selects Flutter's existing Skia/OpenGL renderer, not software rendering.
 * Other device/OS combinations retain the engine default. Device soak pending.
 */
object NavigationRendererCompatibility {
  fun useLegacyRenderer(manufacturer: String, model: String, sdkInt: Int): Boolean =
    manufacturer.equals("samsung", ignoreCase = true) &&
      model.equals("SM-X400", ignoreCase = true) && sdkInt == 36
}
