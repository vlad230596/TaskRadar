plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.taskradar.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        /*
         * Required by flutter_local_notifications (v10 and up), and required
         * *even for apps that never schedule anything* -- the plugin's own
         * classes reference `java.time`, which only exists natively from API 26
         * while this app ships to API 24. Without desugaring the build fails at
         * dex time with an error that names a JDK class and says nothing about
         * notifications.
         */
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // `flutter create` derives the application id from --org plus the Dart package
        // name, which would have produced "com.taskradar.taskradar". The agreed id is
        // "com.taskradar.app", so it is set explicitly here (and the Kotlin package /
        // `namespace` above were moved to match). Do not let a re-run of
        // `flutter create` revert this.
        applicationId = "com.taskradar.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            /*
             * Notifications and code/resource shrinking (F1).
             *
             * No `proguard-rules.pro` is needed for flutter_local_notifications:
             * from its v19 the GSON rules it depends on ship as consumer rules
             * inside the dependency, so R8 already knows to keep the classes the
             * plugin serialises its scheduled notifications with. (Before v19
             * they had to be copied into the app by hand -- if this project is
             * ever downgraded, that comes back.)
             *
             * The *resource* shrinker is the remaining hazard, and it is handled
             * by `src/main/res/raw/keep.xml`: the notification icon is resolved
             * from a string at runtime, so nothing references it from code and
             * it can be shrunk away, after which notifications silently stop
             * being posted in release builds only. See the comment in that file.
             */
        }
    }
}

dependencies {
    // Kept in step with the version flutter_local_notifications itself uses
    // (see its android/build.gradle). A lower one here would be silently
    // overridden by Gradle's conflict resolution; a wildly higher one is how
    // people end up with dex errors nobody can explain.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
