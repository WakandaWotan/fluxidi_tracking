package com.fluxidi.tracking

import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.media.*
import android.net.Uri
import android.os.*
import io.flutter.plugin.common.*
import org.junit.*
import org.junit.Assert.*
import org.mockito.*
import org.mockito.Mockito.*
import sun.misc.Unsafe

class NativeAlarmTest {
  data class ChannelState(val id:String,val importance:Int,var sound:Uri?,var vibrate:Boolean=true,
    var pattern:LongArray?=null,var userSound:Boolean=false,var userImportance:Boolean=false)
  data class Posted(val id:Int,val notification:Notification,val timeout:Long)
  companion object {
    private val resources=mutableListOf<AutoCloseable>()
    private val channels=linkedMapOf<String,NotificationChannel>()
    private val states=linkedMapOf<NotificationChannel,ChannelState>()
    private val posted=linkedMapOf<Int,Posted>()
    private val timers=linkedMapOf<Runnable,Long>()
    private val handlers=linkedMapOf<String,MethodChannel.MethodCallHandler>()
    private lateinit var context:Context
    private lateinit var manager:NotificationManager
    private var notifications=true
    private var permission=true
    private var notifyCalls=0
    private var failNextNotify=false
    private var serial=0
    private val services=mutableListOf<DriverRideNotifications>()
    private fun uri(value:String):Uri=mock(Uri::class.java).also{`when`(it.toString()).thenReturn(value)}
    private fun configureChannel(mock:NotificationChannel,state:ChannelState){
      states[mock]=state
      `when`(mock.id).thenReturn(state.id);`when`(mock.importance).thenReturn(state.importance)
      `when`(mock.sound).thenAnswer{state.sound};`when`(mock.shouldVibrate()).thenAnswer{state.vibrate}
      `when`(mock.vibrationPattern).thenAnswer{state.pattern}
      `when`(mock.hasUserSetSound()).thenAnswer{state.userSound};`when`(mock.hasUserSetImportance()).thenAnswer{state.userImportance}
      doAnswer{state.sound=it.getArgument(0);null}.`when`(mock).setSound(ArgumentMatchers.nullable(Uri::class.java),ArgumentMatchers.nullable(AudioAttributes::class.java))
      doAnswer{state.vibrate=it.getArgument(0);null}.`when`(mock).enableVibration(ArgumentMatchers.anyBoolean())
      doAnswer{state.pattern=it.getArgument(0);null}.`when`(mock).setVibrationPattern(ArgumentMatchers.nullable(LongArray::class.java))
    }
    @JvmStatic @BeforeClass fun setup(){
      val f=Unsafe::class.java.getDeclaredField("theUnsafe");f.isAccessible=true;val u=f.get(null) as Unsafe
      Class.forName("android.os.Build\$VERSION")
      val sdk=Build.VERSION::class.java.getDeclaredField("SDK_INT");u.putInt(u.staticFieldBase(sdk),u.staticFieldOffset(sdk),35)
      context=mock(Context::class.java);manager=mock(NotificationManager::class.java)
      `when`(context.packageName).thenReturn("com.fluxidi.tracking");`when`(context.applicationContext).thenReturn(context)
      `when`(context.getSystemService(Context.NOTIFICATION_SERVICE)).thenReturn(manager)
      `when`(context.checkSelfPermission(ArgumentMatchers.anyString())).thenAnswer{if(permission)PackageManager.PERMISSION_GRANTED else PackageManager.PERMISSION_DENIED}
      val pm=mock(PackageManager::class.java);`when`(context.packageManager).thenReturn(pm)
      `when`(manager.areNotificationsEnabled()).thenAnswer{notifications}
      `when`(manager.getNotificationChannel(ArgumentMatchers.anyString())).thenAnswer{channels[it.getArgument(0)]}
      doAnswer{val c=it.getArgument<NotificationChannel>(0);channels.putIfAbsent(c.id,c);null}.`when`(manager).createNotificationChannel(ArgumentMatchers.any(NotificationChannel::class.java))
      doAnswer{val id=it.getArgument<Int>(0);val n=it.getArgument<Notification>(1);if(failNextNotify){failNextNotify=false;throw SecurityException("synthetic denied")};notifyCalls++;posted[id]=Posted(id,n,timeouts[n]?:0);null}.`when`(manager).notify(ArgumentMatchers.anyInt(),ArgumentMatchers.any(Notification::class.java))
      doAnswer{posted.remove(it.getArgument<Int>(0));null}.`when`(manager).cancel(ArgumentMatchers.anyInt())
      val uris=mockStatic(Uri::class.java);resources.add(uris)
      uris.`when`<Uri>{Uri.parse(ArgumentMatchers.anyString())}.thenAnswer{uri(it.getArgument(0))}
      val ringtones=mockStatic(RingtoneManager::class.java);resources.add(ringtones)
      ringtones.`when`<Uri>{RingtoneManager.getDefaultUri(ArgumentMatchers.anyInt())}.thenAnswer{uri("content://settings/system/notification_sound")}
      val loopers=mockStatic(Looper::class.java);resources.add(loopers)
      loopers.`when`<Looper>{Looper.getMainLooper()}.thenReturn(mock(Looper::class.java))
      val pending=mockStatic(PendingIntent::class.java);resources.add(pending)
      pending.`when`<PendingIntent>{PendingIntent.getActivity(ArgumentMatchers.any(Context::class.java),ArgumentMatchers.anyInt(),ArgumentMatchers.any(Intent::class.java),ArgumentMatchers.anyInt())}.thenReturn(mock(PendingIntent::class.java))
      resources.add(mockConstruction(Intent::class.java,withSettings().defaultAnswer(Answers.RETURNS_SELF)))
      // PackageManager supplies an existing launch Intent; no Activity is launched.
      val intent=mock(Intent::class.java,Answers.RETURNS_SELF);`when`(pm.getLaunchIntentForPackage(ArgumentMatchers.anyString())).thenReturn(intent)
      resources.add(mockConstruction(Handler::class.java){h,_->
        `when`(h.postDelayed(ArgumentMatchers.any(Runnable::class.java),ArgumentMatchers.anyLong())).thenAnswer{timers[it.getArgument(0)]=it.getArgument(1);true}
        doAnswer{timers.remove(it.getArgument<Runnable>(0));null}.`when`(h).removeCallbacks(ArgumentMatchers.any(Runnable::class.java))
      })
      resources.add(mockConstruction(NotificationChannel::class.java){c,args->configureChannel(c,ChannelState(args.arguments()[0] as String,args.arguments()[2] as Int,null))})
      resources.add(mockConstruction(AudioAttributes.Builder::class.java,withSettings().defaultAnswer(Answers.RETURNS_SELF)){b,_->`when`(b.build()).thenReturn(mock(AudioAttributes::class.java))})
      resources.add(mockConstruction(Notification.BigTextStyle::class.java,withSettings().defaultAnswer(Answers.RETURNS_SELF)))
      resources.add(mockConstruction(Notification.Builder::class.java,withSettings().defaultAnswer(Answers.RETURNS_SELF)){b,_->
        val n=mock(Notification::class.java);timeouts[n]=0
        `when`(b.build()).thenReturn(n)
        `when`(b.setTimeoutAfter(ArgumentMatchers.anyLong())).thenAnswer{timeouts[n]=it.getArgument(0);b}
        `when`(b.setOnlyAlertOnce(ArgumentMatchers.anyBoolean())).thenAnswer{if(it.getArgument<Boolean>(0))n.flags=n.flags or Notification.FLAG_ONLY_ALERT_ONCE;b}
      })
      resources.add(mockConstruction(MethodChannel::class.java){c,args->
        val name=args.arguments()[1] as String
        doAnswer{val handler=it.getArgument<MethodChannel.MethodCallHandler?>(0);if(handler==null)handlers.remove(name)else handlers[name]=handler;null}.`when`(c).setMethodCallHandler(ArgumentMatchers.nullable(MethodChannel.MethodCallHandler::class.java))
      })
    }
    private val timeouts=linkedMapOf<Notification,Long>()
    @JvmStatic @AfterClass fun close(){resources.asReversed().forEach{it.close()}}
  }
  private val actor=DriverDutyActor("tenant","company","driver","vehicle")
  private val lease=DriverDutyLease(actor)
  private fun offer(id:String="offer-${serial++}",deadline:Long=System.currentTimeMillis()+60000)=DriverRideNotificationOffer(id,1,deadline,"pickup","destination",null,12.5)
  private fun invoke(method:String,offer:DriverRideNotificationOffer){
    var error:String?=null
    handlers.getValue("fluxidi/vehicle_ride_alert").onMethodCall(MethodCall(method,mapOf(
      "tenant_id" to actor.tenantId,"company_id" to actor.companyId,"driver_id" to actor.driverId,
      "vehicle_id" to actor.vehicleId,"offer_id" to offer.id,"version" to offer.version,"deadline_ms" to offer.deadlineMs)),object:MethodChannel.Result{
      override fun success(result:Any?){}
      override fun error(code:String,message:String?,details:Any?){error=code}
      override fun notImplemented(){error="missing_method"}
    });assertNull(error)
  }
  @Before fun reset(){notifications=true;permission=true;failNextNotify=false;notifyCalls=0;posted.clear();timers.clear();channels.clear();states.clear();DriverDutyService.ready=true;DriverDutyService.notifications=null}
  private fun service()=DriverRideNotifications(context).also{services.add(it)}
  @After fun cleanup(){services.forEach{it.clear()};services.clear()}
  @Test fun repeatsUntilDeadlineAndSamePollingDoesNotPostTwice(){
    val service=service();val o=offer()
    assertTrue(service.present(lease,o){true});val first=posted.values.single()
    assertTrue(first.notification.flags and Notification.FLAG_INSISTENT != 0)
    assertEquals(0,first.notification.flags and Notification.FLAG_ONLY_ALERT_ONCE)
    assertTrue(first.timeout>50000);assertTrue(service.present(lease,o){true});assertEquals(1,notifyCalls)
    assertTrue(states.getValue(channels.getValue(DriverRideNotifications.CHANNEL)).pattern!!.contentEquals(longArrayOf(0,350,200,350,900)))
    timers.values.toList().forEach{assertTrue(it>2500)}
    timers.keys.toList().forEach{it.run()};assertTrue(posted.isEmpty())
  }
  @Test fun foregroundIsNotA2500MillisecondOneShot(){
    val native=VehicleRideAlert(context,mock(BinaryMessenger::class.java)){true};val o=offer();invoke("play",o)
    assertTrue(posted.isNotEmpty());assertTrue(posted.values.single().notification.flags and Notification.FLAG_INSISTENT != 0)
    assertTrue(timers.values.all{it>2500});invoke("stop",o);assertTrue(posted.isEmpty());native.dispose()
  }
  @Test fun foregroundBackgroundAndResumeUseOneScopedNotification(){
    val service=service();DriverDutyService.notifications=service;val o=offer()
    val native=VehicleRideAlert(context,mock(BinaryMessenger::class.java)){true};invoke("play",o)
    val id=posted.keys.single();assertTrue(service.present(lease,o){true});assertEquals(1,notifyCalls)
    invoke("presented",o);assertTrue(posted.containsKey(id));invoke("handoff",o);assertTrue(posted.containsKey(id))
    invoke("sync",o);assertEquals(setOf(id),posted.keys);val afterResume=notifyCalls
    invoke("sync",o);assertEquals(afterResume,notifyCalls)
    invoke("stop",o);assertTrue(posted.isEmpty());native.dispose()
  }
  @Test fun legacyAppDefaultsAreRepairedWithoutChangingTheOldChannel(){
    val old=mock(NotificationChannel::class.java);val state=ChannelState("driver_ride_offers_v2",2,null,true,longArrayOf(0,180,120,180),false,false)
    configureChannel(old,state);channels[state.id]=old
    DriverRideNotifications.channel(context);val current=states.getValue(channels.getValue(DriverRideNotifications.CHANNEL))
    assertEquals(4,current.importance);assertTrue(current.sound.toString().contains("fluxidi_ride_chime"));assertNull(state.sound);assertEquals(2,state.importance)
  }
  @Test fun explicitUserMuteAndBlockRemainRespected(){
    val old=mock(NotificationChannel::class.java);val state=ChannelState("driver_ride_offers_v2",0,null,false,null,true,true)
    configureChannel(old,state);channels[state.id]=old
    assertFalse(DriverRideNotifications.allowed(context));val current=states.getValue(channels.getValue(DriverRideNotifications.CHANNEL))
    assertEquals(0,current.importance);assertNull(current.sound);assertFalse(current.vibrate)
  }
  @Test fun permissionDeniedDoesNotConsumeTheOfferClaim(){
    val service=service();val o=offer();permission=false
    assertFalse(service.present(lease,o){true});assertTrue(posted.isEmpty());permission=true
    assertTrue(service.present(lease,o){true});assertEquals(1,notifyCalls)
  }
  @Test fun failedPostingCanRetryWithoutASecondSuccessfulAlarm(){
    val service=service();val o=offer();failNextNotify=true
    assertFalse(service.present(lease,o){true});assertTrue(posted.isEmpty())
    assertTrue(service.present(lease,o){true});assertEquals(1,notifyCalls)
  }
  @Test fun changedDeadlineUpdatesOneNotificationAndOldTimerCannotCancelIt(){
    val service=service();val o=offer();service.present(lease,o){true}
    val oldTimer=timers.keys.single();val id=posted.keys.single();service.present(lease,o.copy(deadlineMs=o.deadlineMs+10000)){true}
    oldTimer.run();assertEquals(setOf(id),posted.keys);service.clearOffer(o.id);assertTrue(posted.isEmpty())
  }
  @Test fun invalidOrExpiredOfferNeverPosts(){
    val service=service();assertFalse(service.present(lease,offer(deadline=System.currentTimeMillis()-1)){true})
    assertFalse(service.present(lease,offer()){false});assertTrue(posted.isEmpty())
  }
  @Test fun handoffWithoutCurrentDutyStopsInsteadOfKeepingAnAlarm(){
    val native=VehicleRideAlert(context,mock(BinaryMessenger::class.java)){true};val o=offer();invoke("play",o)
    DriverDutyService.ready=false;invoke("handoff",o);assertTrue(posted.isEmpty());native.dispose()
  }
  @Test fun existingCurrentChannelUserChoicesAreNeverOverwritten(){
    val existing=mock(NotificationChannel::class.java)
    val state=ChannelState(DriverRideNotifications.CHANNEL,2,null,false,null,true,true)
    configureChannel(existing,state);channels[state.id]=existing
    DriverRideNotifications.channel(context)
    assertSame(existing,channels.getValue(state.id));assertNull(state.sound);assertFalse(state.vibrate)
  }
  @Test fun aConfirmedCancellationCannotBeRearmedByStalePolling(){
    val service=service();val o=offer();assertTrue(service.present(lease,o){true})
    service.clearOffer(o.id);assertTrue(posted.isEmpty())
    service.present(lease,o){true};assertTrue(posted.isEmpty())
  }
  @Test fun lateConfirmationCancelsOnlyItsOriginalOffer(){
    val service=service();val old=offer();service.present(lease,old){true}
    val oldId=posted.keys.single()
    val native=VehicleRideAlert(context,mock(BinaryMessenger::class.java)){true};val newer=offer();invoke("play",newer)
    assertEquals(2,posted.size);invoke("stopOffer",old)
    assertEquals(1,posted.size);assertFalse(posted.containsKey(oldId))
    invoke("stop",newer);native.dispose()
  }
}
