package com.fluxidi.tracking
import org.junit.Assert.*
import org.junit.Test
class NavigationRendererCompatibilityTest {
  @Test fun affectedTabletAndroid16UsesCompatibilityRenderer() {
    assertTrue(NavigationRendererCompatibility.useLegacyRenderer("samsung", "SM-X400", 36))
    assertTrue(NavigationRendererCompatibility.useLegacyRenderer("Samsung", "sm-x400", 36))
  }
  @Test fun otherDevicesAndVersionsKeepDefault() {
    for (sdk in listOf(24, 35, 37)) assertFalse(NavigationRendererCompatibility.useLegacyRenderer("samsung", "SM-X400", sdk))
    assertFalse(NavigationRendererCompatibility.useLegacyRenderer("samsung", "SM-S938B", 36))
    assertFalse(NavigationRendererCompatibility.useLegacyRenderer("google", "SM-X400", 36))
  }
}
