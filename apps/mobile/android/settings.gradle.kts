// Standard Flutter Gradle Kotlin DSL settings file (matches the shape
// `flutter create` generates for Flutter 3.22+ / AGP 8.x). Hand-written here
// because Flutter is not installed on this machine — verify against
// `flutter create --platforms=android .` output once it is (see
// ../PLATFORM-SETUP.md for what else that command needs to fill in, e.g.
// the Gradle wrapper jar/properties under android/gradle/wrapper/).
pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // NOTE: AGP/Kotlin versions below are conservative guesses for
    // Flutter 3.22 (Dec 2025-era). Confirm against `flutter create` output
    // on a real machine before relying on them.
    id("com.android.application") version "8.3.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.23" apply false
}

include(":app")
