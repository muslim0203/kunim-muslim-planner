import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (docs/release-android.md). The key itself never lives in the
// repository: `android/key.properties` points at a file outside it, or, on CI,
// the KUNIM_ANDROID_* environment variables do. Both are read here so a local
// build and a workflow run use the same code path.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingValue(key: String, variable: String): String? =
    keyProperties.getProperty(key) ?: System.getenv(variable)

fun requireSigningValue(key: String, variable: String): String =
    signingValue(key, variable)
        ?: throw GradleException(
            "Release signing: `$key` is missing from android/key.properties " +
                "and `$variable` is not set (see docs/release-android.md).",
        )

val keystorePath = signingValue("storeFile", "KUNIM_ANDROID_KEYSTORE")

android {
    namespace = "com.kunim.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications (prayer/habit reminders, plan section 10)
        // needs java.time on API < 26 paths, so core library desugaring is
        // required -- without it :app:checkDebugAarMetadata fails the build.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.kunim.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Plan section 1 / ADR-0001: Android 8.0 (API 26) is the floor.
        // UsageStatsManager event handling in phase 6 assumes API 26+.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePath != null) {
            create("release") {
                storeFile = file(keystorePath)
                // Missing on purpose rather than empty: an empty password
                // fails inside the signer with an unreadable message, so say
                // what is wrong while the build is still being configured.
                storePassword = requireSigningValue("storePassword", "KUNIM_ANDROID_STORE_PASSWORD")
                keyAlias = requireSigningValue("keyAlias", "KUNIM_ANDROID_KEY_ALIAS")
                keyPassword = requireSigningValue("keyPassword", "KUNIM_ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Without a key configured the release build is signed with the
            // debug key, so `flutter run --release` and a quick APK for a test
            // phone keep working. Play refuses a debug certificate, so such a
            // build cannot reach users by accident.
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }
}


kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
