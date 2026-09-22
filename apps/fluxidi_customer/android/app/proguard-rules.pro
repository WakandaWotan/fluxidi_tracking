# R8 8.9 full mode merged DartExecutor into
# androidx.appcompat.view.ViewPropertyAnimatorCompatSet. The merged
# constructor called MethodChannel.setMethodCallHandler before
# binaryMessenger existed, so every cold start of the Play release died in
# FragmentActivity.onStart:
#   NullPointerException in DartExecutor.setMessageHandler
# Keeping these classes stops that merge. Do not keep the whole embedding:
# PlayStoreDeferredComponentManager references Play Core, which this app
# does not ship.
-keep class io.flutter.embedding.engine.dart.** { *; }
-keep class io.flutter.embedding.engine.systemchannels.** { *; }
-keep class io.flutter.plugin.common.** { *; }

# Device unlock and the encrypted session vault must survive shrinking.
-keep class io.flutter.plugins.localauth.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }

-dontwarn com.google.android.play.core.**
