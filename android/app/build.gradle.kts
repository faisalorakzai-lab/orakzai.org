import java.io.FileInputStream
import java.net.URI
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.exists()) {
    signingProperties.load(FileInputStream(signingPropertiesFile))
}
val ciKeystore = System.getenv("ANDROID_KEYSTORE_PATH")
val hasReleaseSigning = !ciKeystore.isNullOrBlank() || signingPropertiesFile.exists()

android {
    namespace = "org.orakzai.app"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "org.orakzai.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24 // Installed audio_session requires Android 7+.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        getByName("debug") {
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
        }
        create("release") {
            if (!ciKeystore.isNullOrBlank()) {
                storeFile = file(ciKeystore)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            } else if (signingPropertiesFile.exists()) {
                keyAlias = signingProperties["keyAlias"] as String
                keyPassword = signingProperties["keyPassword"] as String
                storeFile = file(signingProperties["storeFile"] as String)
                storePassword = signingProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            // A checking build must never replace an existing production app or
            // require uninstalling it merely because its signing key differs.
            applicationIdSuffix = ".checking"
            versionNameSuffix = "-checking"
        }
        release {
            // No debug-key fallback: configure android/key.properties before release.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                null
            }
        }
    }
}

flutter {
    source = "../.."
}

// Compatibility packaging for sideloaded checking APKs only. Keep production
// APK/AAB packaging unchanged; native libraries are extracted by Android here.
androidComponents {
    onVariants(selector().withBuildType("debug")) { variant ->
        variant.packaging.jniLibs.useLegacyPackaging.set(true)
    }
}

// Fail release builds before compilation, including builds outside GitHub Actions.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.contains("Release", ignoreCase = true) }) {
        val defines = (project.findProperty("dart-defines") as? String).orEmpty()
            .split(",").filter { it.isNotBlank() }
            .map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
        val api = defines.firstOrNull { it.startsWith("ORAKZAI_API_BASE_URL=") }
            ?.substringAfter("=")
        val uri = runCatching { URI(api.orEmpty()) }.getOrNull()
        val host = uri?.host.orEmpty().lowercase()
        require(uri?.scheme == "https" && host.isNotBlank() &&
            uri.userInfo == null && uri.query == null && uri.fragment == null &&
            host !in listOf("localhost", "0.0.0.0", "[::1]") &&
            !host.startsWith("10.") && !host.startsWith("127.") &&
            !host.startsWith("192.168.") && !host.startsWith("169.254.") &&
            !Regex("^172\\.(1[6-9]|2\\d|3[01])\\.").containsMatchIn(host)) {
            "Release requires --dart-define=ORAKZAI_API_BASE_URL=<public HTTPS API URL>"
        }
    }
}
