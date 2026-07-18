import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Fluxidi release configuration (signing + Mapbox token).
//
// Secrets are NEVER committed. They are read from local, gitignored inputs:
//   - android/key.properties      : release/upload keystore credentials
//   - MAPBOX_TOKEN                 : Mapbox public access token, resolved from
//                                    -PMAPBOX_TOKEN, the environment, or
//                                    local.properties
//
// Release builds fail fast when this material is missing. They never silently
// fall back to debug signing or to the MAPBOX_TOKEN_NOT_SET placeholder.
// ---------------------------------------------------------------------------

val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

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
    namespace = "com.fluxidi.tracking"
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
        applicationId = "com.fluxidi.tracking"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Single authoritative Mapbox token path: the token is injected as the
        // @string/mapbox_access_token resource referenced by the manifest
        // meta-data. Debug/profile builds may use the placeholder; release
        // builds are blocked below when the real token is missing.
        resValue(
            "string",
            "mapbox_access_token",
            if (mapboxAccessToken.isNotBlank()) mapboxAccessToken else mapboxTokenPlaceholder,
        )
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                val storeFilePath = keystoreProperties.getProperty("storeFile")
                if (storeFilePath != null && storeFilePath.isNotBlank()) {
                    storeFile = file(storeFilePath)
                }
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        getByName("debug") {
            // Debug builds keep debug signing.
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            // Release builds MUST use the dedicated release/upload signing
            // config. No silent debug fallback.
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// Fail fast for release builds when required secure material is missing, so the
// project can never produce a falsely "release" AAB signed with debug
// credentials or shipping the placeholder Mapbox token.
gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any { task ->
        val name = task.name
        name.contains("Release") &&
            (name.startsWith("assemble") || name.startsWith("bundle") || name.startsWith("package"))
    }
    if (buildingRelease) {
        if (!hasReleaseKeystore) {
            throw GradleException(
                "RELEASE_KEYSTORE_CREATION_REQUIRED: android/key.properties not found. " +
                    "A release build must be signed with a dedicated upload keystore. " +
                    "Create the keystore and android/key.properties (storeFile, storePassword, keyAlias, keyPassword). " +
                    "Debug signing is not permitted for release builds.",
            )
        }
        if (mapboxAccessToken.isBlank() || mapboxAccessToken == mapboxTokenPlaceholder) {
            throw GradleException(
                "MAPBOX_RELEASE_TOKEN_REQUIRED: no Mapbox access token provided. " +
                    "Supply MAPBOX_TOKEN via -PMAPBOX_TOKEN=..., an environment variable, or local.properties. " +
                    "Release builds must not ship the MAPBOX_TOKEN_NOT_SET placeholder.",
            )
        }
    }
}

flutter {
    source = "../.."
}

// FLUXIDI NAV-STREETLEVEL-FLUID-MOTION-2 Phase 2A — JVM unit test setup for
// the app-local native-follow bridge and the vendored plugin's registry.
// Only affects the `test` source set; no impact on the shipped APK.
dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.mockito:mockito-core:5.11.0")
    testImplementation("org.mockito:mockito-inline:5.2.0")
    testImplementation("org.mockito.kotlin:mockito-kotlin:5.2.1")
    testImplementation("org.jetbrains.kotlin:kotlin-test-junit:1.9.22")
}
