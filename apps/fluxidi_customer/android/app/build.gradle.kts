import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Mapbox access token.
//
// Same single path as the existing app: the token becomes the
// @string/mapbox_access_token resource the manifest meta-data points at. It is
// never committed; it is read from -PMAPBOX_TOKEN, the environment, or
// android/local.properties. Debug builds may carry the placeholder, which only
// means no map tiles.
// ---------------------------------------------------------------------------
val mapboxTokenPlaceholder = "MAPBOX_TOKEN_NOT_SET"

fun resolveMapboxToken(): String {
    (project.findProperty("MAPBOX_TOKEN") as String?)?.let {
        if (it.isNotBlank()) return it.trim()
    }
    System.getenv("MAPBOX_TOKEN")?.let {
        if (it.isNotBlank()) return it.trim()
    }
    val localProps = rootProject.file("local.properties")
    if (localProps.exists()) {
        val p = Properties()
        localProps.inputStream().use { p.load(it) }
        (p.getProperty("MAPBOX_TOKEN") ?: p.getProperty("mapbox.token"))?.let {
            if (it.isNotBlank()) return it.trim()
        }
    }
    return ""
}

val mapboxAccessToken = resolveMapboxToken()

android {
    namespace = "com.fluxidi.customer.dev"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Development identity for the standalone customer app. Installs
        // alongside the existing com.fluxidi.tracking app. Not a final Play id.
        applicationId = "com.fluxidi.customer.dev"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        resValue(
            "string",
            "mapbox_access_token",
            if (mapboxAccessToken.isNotBlank()) mapboxAccessToken else mapboxTokenPlaceholder,
        )
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
