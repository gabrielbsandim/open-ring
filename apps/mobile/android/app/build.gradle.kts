import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeyFile = rootProject.file("key.properties")
val releaseKey: Properties? =
    releaseKeyFile.takeIf { it.exists() }?.let { file ->
        Properties().apply { file.inputStream().use { load(it) } }
    }
val buildsRelease = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }

if (releaseKey == null && buildsRelease) {
    logger.error(
        "WARNING: ${releaseKeyFile.path} not found. The release build is signed with the debug key " +
            "and cannot be uploaded to a store. See docs/release.md.",
    )
}

fun Properties.required(name: String): String =
    getProperty(name)?.takeIf { it.isNotBlank() } ?: error("android/key.properties is missing $name")

android {
    namespace = "gbs.openring.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "gbs.openring.app"
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        compose = true
    }

    signingConfigs {
        releaseKey?.let { key ->
            create("release") {
                storeFile = rootProject.file(key.required("storeFile"))
                storePassword = key.required("storePassword")
                keyAlias = key.required("keyAlias")
                keyPassword = key.required("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Without android/key.properties the debug key keeps `flutter build` and `flutter run --release` working.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
    implementation("androidx.glance:glance-appwidget:1.2.0")
}
