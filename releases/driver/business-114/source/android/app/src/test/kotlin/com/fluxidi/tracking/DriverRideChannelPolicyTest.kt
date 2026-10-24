package com.fluxidi.tracking

import org.junit.Assert.*
import org.junit.Test

class DriverRideChannelPolicyTest {
  private val fresh="android.resource://com.fluxidi.tracking/raw/fluxidi_ride_chime"
  @Test fun newInstallHasSoundStrongPatternAndHighImportance(){
    val p=driverRideChannelPolicy(null,fresh)
    assertEquals(4,p.importance);assertEquals(fresh,p.sound);assertTrue(p.vibrate)
    assertArrayEquals(longArrayOf(0,350,200,350,900),p.pattern)
  }
  @Test fun unchosenLegacyDefaultsAreRepaired(){
    val p=driverRideChannelPolicy(DriverRideChannelSnapshot(2,null,true,longArrayOf(0,180,120,180),false,false),fresh)
    assertEquals(4,p.importance);assertEquals(fresh,p.sound)
    assertArrayEquals(longArrayOf(0,350,200,350,900),p.pattern)
  }
  @Test fun explicitUserSilentVibrationOffAndLowImportanceRemain(){
    val p=driverRideChannelPolicy(DriverRideChannelSnapshot(2,null,false,null,true,true),fresh)
    assertEquals(2,p.importance);assertNull(p.sound);assertFalse(p.vibrate)
  }
  @Test fun customUserSoundAndPatternArePreserved(){
    val custom=longArrayOf(0,100,400,100)
    val p=driverRideChannelPolicy(DriverRideChannelSnapshot(3,"content://user/custom",true,custom,true,true),fresh)
    assertEquals("content://user/custom",p.sound);assertEquals(3,p.importance);assertArrayEquals(custom,p.pattern)
  }
  @Test fun aBlockedChannelIsNeverRaisedEvenWithoutUserProvenance(){
    assertEquals(0,driverRideChannelPolicy(DriverRideChannelSnapshot(0,null,false,null,false,false),fresh).importance)
  }
  @Test fun oldAndroidWithoutUserChoiceEvidenceIsConservative(){
    val p=driverRideChannelPolicy(DriverRideChannelSnapshot(2,null,false,null,null,null),fresh)
    assertEquals(2,p.importance);assertNull(p.sound);assertFalse(p.vibrate)
  }
}
