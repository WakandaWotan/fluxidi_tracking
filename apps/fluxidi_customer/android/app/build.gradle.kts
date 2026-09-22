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

val playRelease =
    (project.findProperty("FLUXIDI_CUSTOMER_PLAY") as String?) == "true" ||
        System.getenv("FLUXIDI_CUSTOMER_PLAY") == "true"

val customerApplicationId =
    if (playRelease) "com.fluxidi.customer" else "com.fluxidi.customer.dev"
val customerAppLabel = if (playRelease) "Fluxidi Klanten" else "Fluxidi Customer Dev"
val paymentReturnScheme = if (playRelease) "fluxidicustomer" else "fluxidicustomerdev"

val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

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
        // Local APKs keep com.fluxidi.customer.dev. A Play AAB sets
        // FLUXIDI_CUSTOMER_PLAY=true and uses the lasting com.fluxidi.customer
        // identity. The existing com.fluxidi.tracking app is never retargeted.
        applicationId = customerApplicationId
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders["appLabel"] = customerAppLabel
        manifestPlaceholders["paymentReturnScheme"] = paymentReturnScheme

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
        release {
            signingConfig =
                if (playRelease && hasReleaseKeystore) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

gradle.taskGraph.whenReady {
    val buildingPlayRelease = allTasks.any { task ->
        task.name.contains("Release", ignoreCase = true)
    } && playRelease
    if (!buildingPlayRelease) return@whenReady
    if (!hasReleaseKeystore) {
        throw GradleException(
            "Play release requires apps/fluxidi_customer/android/key.properties",
        )
    }
    val storeFilePath = keystoreProperties.getProperty("storeFile").orEmpty()
    if (storeFilePath.isBlank() || !file(storeFilePath).exists()) {
        throw GradleException("Play upload keystore is missing")
    }
    if (mapboxAccessToken.isBlank()) {
        throw GradleException("Play release requires MAPBOX_TOKEN")
    }
}

flutter {
    source = "../.."
}

// The customer app depends on fluxidi_tracking as a Flutter package, so
// Flutter copies that package's entire asset list (chauffeur themes, company
// themes, navigation signs, orientation videos). Those files stay in the
// golden app; this hook drops them from the customer bundle only.
fun flutterDartExecutable(): File {
    val localProps = Properties()
    rootProject.file("local.properties").inputStream().use { localProps.load(it) }
    val flutterSdk = localProps.getProperty("flutter.sdk")
        ?: throw GradleException("flutter.sdk ontbreekt in local.properties")
    val windows = System.getProperty("os.name").lowercase().contains("windows")
    return file("$flutterSdk/${if (windows) "bin/dart.bat" else "bin/dart"}")
}

fun stripUnusedBridgePackageAssetsAt(flutterAssets: File) {
    if (!flutterAssets.exists()) return
    val appDir = project.projectDir.parentFile.parentFile
    exec {
        workingDir = appDir
        commandLine(
            flutterDartExecutable().absolutePath,
            "run",
            "tool/strip_unused_bridge_package_assets.dart",
            flutterAssets.absolutePath,
        )
    }
}

fun stripUnusedBridgePackageAssets(buildName: String) {
    val intermediates = layout.buildDirectory.get().asFile.resolve("intermediates")
    val compileAssets =
        intermediates.resolve("flutter/$buildName/flutter_assets")
    stripUnusedBridgePackageAssetsAt(compileAssets)
    intermediates
        .walkTopDown()
        .maxDepth(8)
        .filter { file ->
            file.isDirectory &&
                file.name == "flutter_assets" &&
                file.absolutePath != compileAssets.absolutePath
        }
        .forEach { stripUnusedBridgePackageAssetsAt(it) }
}

afterEvaluate {
    tasks.matching { task ->
        task.name.startsWith("compileFlutterBuild") ||
            task.name.startsWith("copyFlutterAssets")
    }.configureEach {
        val buildName =
            name
                .removePrefix("compileFlutterBuild")
                .removePrefix("copyFlutterAssets")
                .lowercase()
        doLast {
            stripUnusedBridgePackageAssets(buildName)
        }
    }
}
