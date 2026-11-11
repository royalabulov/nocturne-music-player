import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (not committed to git). A fresh clone without it
// (or with enabled=false) still runs debug builds and tests, but a release build stops: the
// debug key is public, so nothing signed with it may ship by accident.
// To try a release build locally anyway: ALLOW_DEBUG_SIGNING=true flutter build apk
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val useReleaseKey = keyProps.getProperty("enabled") == "true"

gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any {
        it.project == project && (it.name == "packageRelease" || it.name == "signReleaseBundle")
    }
    if (buildsRelease && !useReleaseKey && System.getenv("ALLOW_DEBUG_SIGNING") != "true") {
        throw GradleException(
            "Release build without a release key: android/key.properties is missing or has " +
                "enabled=false. Set ALLOW_DEBUG_SIGNING=true only for a local try-out.",
        )
    }
}

android {
    namespace = "com.nocturne"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications (scheduled reminders) needs java.time on old Androids
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.nocturne"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (useReleaseKey) {
                storeFile = rootProject.file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (useReleaseKey) "release" else "debug")
        }
    }

    // The YAMNet model is memory-mapped from assets → must not be compressed
    androidResources {
        noCompress += "tflite"
    }
}

dependencies {
    // Smart groups: YAMNet audio classifier (on-device, offline). LiteRT = TensorFlow Lite.
    implementation("com.google.ai.edge.litert:litert:1.4.2")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // PlaybackServiceControl talks to audio_service's AudioService, a MediaBrowserServiceCompat.
    // Same version audio_service already brings, so nothing new goes into the APK.
    implementation("androidx.media:media:1.7.0")

    constraints {
        // media3 1.4.1 (via just_audio) brings guava 33.0.0, open to GHSA-xxph-c9ww-hj94 (memory
        // blow-up when reading Java-serialized data; fixed in 33.7.2). The app never reads such
        // data, so it was not reachable, but the CI dependency scan (ci.yml) flags it.
        implementation("com.google.guava:guava:33.7.2-android") {
            because("GHSA-xxph-c9ww-hj94")
        }
    }

    // Unit tests of the native code (src/test), run on the JVM. Never part of the APK.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.17")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
