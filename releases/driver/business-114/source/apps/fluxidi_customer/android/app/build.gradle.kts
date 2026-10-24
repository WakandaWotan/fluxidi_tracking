import java.util.Properties
import java.util.Base64
import java.net.URI

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

// One Dart entrypoint; the compiled runtime selects both native and Dart identity.
val customerDefines = (project.findProperty("dart-defines") as String?).orEmpty()
    .split(",").filter { it.isNotBlank() }.associate { encoded ->
        val decoded = String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
        decoded.substringBefore("=") to decoded.substringAfter("=", "")
    }
val customerRuntime = customerDefines["FLUXIDI_RUNTIME_ENV"].orEmpty()
if (customerRuntime !in listOf("", "production", "prod", "local_test", "local", "staging")) {
    throw GradleException("Unknown FLUXIDI_RUNTIME_ENV")
}
val customerStaging = customerRuntime == "staging"
val customerApplicationId = if (customerStaging) "com.fluxidi.customer.staging" else "com.fluxidi.customer"
val customerAppLabel = if (customerStaging) "Fluxidi Klanten Staging" else "Fluxidi Klanten"
val paymentReturnScheme = if (customerStaging) "fluxidicustomerstaging" else "fluxidicustomer"
if (playRelease && customerStaging) throw GradleException("Production Play flag cannot use staging runtime")
if ((project.findProperty("FLUXIDI_CUSTOMER_STAGING") as String?) == "true" ||
    System.getenv("FLUXIDI_CUSTOMER_STAGING") == "true") {
    throw GradleException("Legacy E2E staging flag removed: use FLUXIDI_RUNTIME_ENV=staging")
}
for (key in listOf("FLUXIDI_E2E_BUILD", "FLUXIDI_CUSTOMER_STAGING", "FLUXIDI_LOCAL_QA_CUSTOMER_SESSION")) {
    if (customerDefines[key] == "true") throw GradleException("Customer app forbids $key")
}
for (key in listOf("FLUXIDI_E2E_TEST_TOKEN", "FLUXIDI_LOCAL_QA_ADMIN_TOKEN", "ADMIN_TOKEN")) {
    if (!customerDefines[key].isNullOrBlank()) throw GradleException("Customer app forbids $key")
}
for ((key, expected) in mapOf(
    "FLUXIDI_CUSTOMER_APPLICATION_ID" to customerApplicationId,
    "FLUXIDI_ANDROID_APPLICATION_ID" to customerApplicationId,
    "FLUXIDI_CUSTOMER_APP_NAME" to customerAppLabel,
    "FLUXIDI_CUSTOMER_DEEP_LINK_SCHEME" to paymentReturnScheme,
    "FLUXIDI_CUSTOMER_ENV_LABEL" to ""
)) {
    if (customerDefines.containsKey(key) && customerDefines[key] != expected) {
        throw GradleException("$key contradicts FLUXIDI_RUNTIME_ENV")
    }
}
val customerStagingHosts = mapOf(
    "BOOKING_BASE_URL" to "fluxidi-booking-api-staging.fluxidi.workers.dev",
    "PUBLIC_BOOKING_BASE_URL" to "fluxidi-booking-api-staging.fluxidi.workers.dev",
    "FLUXIDI_PUBLIC_BOOKING_BASE_URL" to "fluxidi-booking-api-staging.fluxidi.workers.dev",
    "WORKER_BASE_URL" to "fluxidi-tracking-api-staging.fluxidi.workers.dev",
    "NAVIGATION_WORKER_BASE_URL" to "fluxidi-navigation-api-staging.fluxidi.workers.dev"
)
for ((key, stagingHost) in customerStagingHosts) {
    val value = customerDefines[key].orEmpty()
    val uri = try { URI(value) } catch (_: Exception) { null }
    if (customerStaging) {
        if (uri?.scheme != "https" || uri.host != stagingHost ||
            uri.userInfo != null || uri.port != -1 || !uri.query.isNullOrEmpty() ||
            !uri.fragment.isNullOrEmpty() || uri.path !in listOf("", "/")) {
            throw GradleException("Staging requires explicit HTTPS $key for $stagingHost; no production fallback")
        }
    } else if (uri?.host in customerStagingHosts.values || value.contains("-e2e")) {
        throw GradleException("Normal customer build must not use staging/E2E $key")
    }
}

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
        // Normal and staging APKs share source with isolated Android identities.
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
                if ((playRelease || customerStaging) && hasReleaseKeystore) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any { task ->
        task.name.contains("Release", ignoreCase = true)
    }
    val buildingPlayRelease = buildingRelease && playRelease
    if (buildingRelease && customerStaging) {
        if (customerApplicationId != "com.fluxidi.customer.staging") {
            throw GradleException(
                "Customer staging package must be com.fluxidi.customer.staging",
            )
        }
        if (paymentReturnScheme != "fluxidicustomerstaging") {
            throw GradleException(
                "Customer staging payment scheme must stay fluxidicustomerstaging",
            )
        }
        if (!hasReleaseKeystore) {
            throw GradleException(
                "Customer staging requires apps/fluxidi_customer/android/key.properties",
            )
        }
        if (mapboxAccessToken.isBlank()) {
            throw GradleException("Customer staging requires MAPBOX_TOKEN")
        }
        val storeFilePath = keystoreProperties.getProperty("storeFile").orEmpty()
        if (storeFilePath.isBlank() || !file(storeFilePath).exists()) {
            throw GradleException("Customer staging upload keystore is missing")
        }
    }
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
