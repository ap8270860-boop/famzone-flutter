import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/*
 | The Google Maps key, out of local.properties.
 |
 | local.properties is gitignored and machine-local, which is exactly the
 | right place for it: the key never enters the repository, every developer
 | can hold their own, and CI supplies it as an environment variable without
 | anything in the build script changing.
 |
 | Empty is a valid state and builds fine — the map renders as a grey grid
 | with "For development purposes only" across it, which is a far better
 | failure than a build that will not compile.
 */
val mapsApiKey: String = Properties().apply {
    val properties = rootProject.file("local.properties")

    if (properties.exists()) {
        FileInputStream(properties).use { load(it) }
    }
}.getProperty("MAPS_API_KEY") ?: ""

android {
    namespace = "co.sfamily.famzone"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        /*
         | Core library desugaring, required by flutter_local_notifications.
         |
         | The plugin uses java.time to schedule alarms, and java.time only
         | exists natively from Android 8.0 (API 26). This app's minSdk is 24,
         | so on 24 and 25 those classes are simply not there — desugaring is
         | what back-ports them into the APK.
         |
         | Without it the build fails at checkDebugAarMetadata rather than at
         | runtime, which is the good outcome: the alternative would be an app
         | that installs on a 2016 phone and crashes the moment somebody sets
         | a reminder.
         |
         | Raising minSdk to 26 would also fix it and is the wrong trade — it
         | would drop Android 7 devices, which are exactly the older, cheaper
         | phones a family safety app should still run on.
         */
        isCoreLibraryDesugaringEnabled = true

        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "co.sfamily.famzone"

        // Substituted into ${MAPS_API_KEY} in AndroidManifest.xml.
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Pinned rather than inherited: the record plugin needs 23,
        // and 24 is where the audio encoder behaviour stops varying
        // between manufacturers. Inheriting it means a Flutter
        // upgrade could quietly move it under us.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

/*
 | The other half of core library desugaring.
 |
 | Turning the flag on above is not enough — it tells AGP to rewrite the
 | bytecode, and this supplies the back-ported java.time classes it rewrites
 | calls into. Setting one without the other fails the build, which is at
 | least honest about it.
 |
 | 2.1.4 is the version flutter_local_notifications documents. Pinned exactly
 | rather than left to a range: this library is stitched into the bytecode of
 | every class that touches a date, and it is not somewhere for a build to
 | drift on its own.
 |
 | No multiDexEnabled, despite the plugin's README showing it. That flag
 | matters below API 21; this app's minSdk is 24, where multidex is native and
 | the flag does nothing.
 */
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
