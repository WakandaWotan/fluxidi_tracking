package com.fluxidi.tracking;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import androidx.annotation.NonNull;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;
import java.nio.charset.StandardCharsets;
import java.net.URI;
import java.util.HashMap;
import java.util.Map;
import org.json.JSONObject;
import org.maplibre.android.geometry.LatLngBounds;
import org.maplibre.android.offline.OfflineManager;
import org.maplibre.android.offline.OfflineRegion;
import org.maplibre.android.offline.OfflineRegionError;
import org.maplibre.android.offline.OfflineRegionStatus;
import org.maplibre.android.offline.OfflineTilePyramidRegionDefinition;

/** Adapter for existing native MapLibre offline packs; no GPS or booking work. */
public final class FluxidiOfflineDownloadBridge {
  private final Context context;
  private final MethodChannel channel;
  private final Handler main = new Handler(Looper.getMainLooper());
  private final ConnectivityManager connectivity;
  private Session current;
  private boolean disposed;
  private static final String SOURCE = "fluxidi_driver_offline_maplibre_v1";

  private static final class Session {
    final MethodChannel.Result result;
    final String key;
    final boolean wifiOnly;
    final long resourceLimit;
    OfflineRegion region;
    ConnectivityManager.NetworkCallback callback;
    boolean done;
    long lastProgress;
    Session(MethodChannel.Result result, String key, boolean wifiOnly, long limit) {
      this.result=result;this.key=key;this.wifiOnly=wifiOnly;this.resourceLimit=limit;
    }
  }

  public FluxidiOfflineDownloadBridge(Context context, BinaryMessenger messenger) {
    this.context=context.getApplicationContext();
    connectivity=(ConnectivityManager)this.context.getSystemService(Context.CONNECTIVITY_SERVICE);
    channel=new MethodChannel(messenger,"fluxidi/offline_maps");
    channel.setMethodCallHandler((call,result)->{
      if (!"download".equals(call.method)) { result.notImplemented(); return; }
      if (disposed||current!=null) { result.error("offline_busy","Offline download already active",null); return; }
      try {
        Map<String,Object> args=call.arguments();
        String style=(String)args.get("style"),key=(String)args.get("logical_key");
        URI uri=URI.create(style);
        if (!"https".equals(uri.getScheme())||uri.getUserInfo()!=null||uri.getQuery()!=null||uri.getFragment()!=null
            ||!("fluxidi-maplibre-be-nl.fluxidi.workers.dev".equals(uri.getHost())||"maps.fluxidi.com".equals(uri.getHost()))
            ||!uri.getPath().matches("/r/be-nl-20261013-rectangle-v1/data/full/style-(light|dark)\\.json")
            ||key==null||!key.matches("[a-f0-9]{64}")) throw new IllegalArgumentException();
        double west=number(args,"west"),south=number(args,"south"),east=number(args,"east"),north=number(args,"north");
        double min=number(args,"minZoom"),max=number(args,"maxZoom");
        if (!(west>=2&&east<=7.8&&south>=49.1&&north<=54&&west<east&&south<north&&min>=0&&max<=16&&min<=max)) throw new IllegalArgumentException();
        long limit=((Number)args.get("remainingResources")).longValue();
        if(limit<1||limit>50000)throw new IllegalArgumentException();
        Map<String,Object> metadata=(Map<String,Object>)args.get("metadata");
        if(!SOURCE.equals(metadata.get("source"))||!key.equals(metadata.get("logical_key")))throw new IllegalArgumentException();
        Session session=new Session(result,key,Boolean.TRUE.equals(args.get("wifiOnly")),limit);
        if(!networkAllowed(session)) { result.error("wifiRequired","Use an unmetered Wi-Fi network",null);return; }
        current=session;
        if(session.wifiOnly){
          session.callback=new ConnectivityManager.NetworkCallback(){
            @Override public void onCapabilitiesChanged(@NonNull Network n,@NonNull NetworkCapabilities c){ main.post(()->checkNetwork(session)); }
            @Override public void onLost(@NonNull Network n){ main.post(()->checkNetwork(session)); }
          };
          if(Build.VERSION.SDK_INT>=24)connectivity.registerDefaultNetworkCallback(session.callback);
          else connectivity.registerNetworkCallback(new NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(),session.callback);
        }
        OfflineManager manager=OfflineManager.Companion.getInstance(this.context);
        manager.listOfflineRegions(new OfflineManager.ListOfflineRegionsCallback(){
          @Override public void onList(@NonNull OfflineRegion[] regions){
            if(session.done)return;
            for(OfflineRegion region:regions){try{
              JSONObject meta=new JSONObject(new String(region.getMetadata(),StandardCharsets.UTF_8));
              if(SOURCE.equals(meta.optString("source"))&&key.equals(meta.optString("logical_key"))
                  &&style.equals(region.getDefinition().getStyleURL())){start(session,region);return;}
            }catch(Exception ignored){}}
            OfflineTilePyramidRegionDefinition definition=new OfflineTilePyramidRegionDefinition(style,
              LatLngBounds.from(north,east,south,west),min,max,thisContextDensity(),false);
            manager.createOfflineRegion(definition,new JSONObject(metadata).toString().getBytes(StandardCharsets.UTF_8),
              new OfflineManager.CreateOfflineRegionCallback(){
                @Override public void onCreate(@NonNull OfflineRegion region){start(session,region);}
                @Override public void onError(@NonNull String error){fail(session,"offlineCreateFailed");}
              });
          }
          @Override public void onError(@NonNull String error){fail(session,"offlineListFailed");}
        });
      } catch(Exception e) {
        if(current!=null)fail(current,"offlineConfiguration");else result.error("offlineConfiguration","Own offline map configuration invalid",null);
      }
    });
  }
  private float thisContextDensity(){return context.getResources().getDisplayMetrics().density;}
  private static double number(Map<String,Object> args,String name){double n=((Number)args.get(name)).doubleValue();if(!Double.isFinite(n))throw new IllegalArgumentException();return n;}
  private boolean networkAllowed(Session s){
    if(!s.wifiOnly)return true;
    Network active=connectivity.getActiveNetwork();NetworkCapabilities c=active==null?null:connectivity.getNetworkCapabilities(active);
    return c!=null&&c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)&&c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)&&!connectivity.isActiveNetworkMetered();
  }
  private void checkNetwork(Session s){if(!s.done&&!networkAllowed(s))fail(s,"wifiRequired");}
  private void start(Session s,OfflineRegion region){
    if(disposed||s.done||current!=s||!networkAllowed(s)){region.setDownloadState(OfflineRegion.STATE_INACTIVE);if(!s.done)fail(s,"wifiRequired");return;}
    s.region=region;
    region.setObserver(new OfflineRegion.OfflineRegionObserver(){
      @Override public void onStatusChanged(@NonNull OfflineRegionStatus status){
        if(s.done)return;
        if(status.getCompletedResourceCount()>s.resourceLimit){fail(s,"offlineResourceLimit");return;}
        if(status.isComplete()){
          Map<String,Object> result=new HashMap<>();result.put("id",region.getId());result.put("complete",true);
          finish(s);s.result.success(result);return;
        }
        long now=SystemClock.uptimeMillis();if(now-s.lastProgress<100)return;s.lastProgress=now;
        Map<String,Object> progress=new HashMap<>();progress.put("logical_key",s.key);
        progress.put("completed",status.getCompletedResourceCount());progress.put("required",status.getRequiredResourceCount());progress.put("bytes",status.getCompletedResourceSize());
        channel.invokeMethod("progress",progress);
      }
      @Override public void onError(@NonNull OfflineRegionError error){
        // Stop the current attempt with its partial pack retained. No retry loop
        // or false completion after a gateway/quota/network response.
        fail(s,"offlineResourceUnavailable");
      }
      @Override public void mapboxTileCountLimitExceeded(long limit){fail(s,"offlineResourceLimit");}
    });
    if(!networkAllowed(s)){fail(s,"wifiRequired");return;}
    region.setDownloadState(OfflineRegion.STATE_ACTIVE);
  }
  private void finish(Session s){
    if(s.done)return;s.done=true;
    if(s.region!=null){s.region.setDownloadState(OfflineRegion.STATE_INACTIVE);s.region.setObserver(null);}
    if(s.callback!=null){try{connectivity.unregisterNetworkCallback(s.callback);}catch(Exception ignored){}}
    if(current==s)current=null;
  }
  private void fail(Session s,String code){if(s.done)return;finish(s);s.result.error(code,"Own offline download paused; partial data retained",null);}
  public void dispose(){disposed=true;if(current!=null)fail(current,"offlineOwnerClosed");channel.setMethodCallHandler(null);}
}
