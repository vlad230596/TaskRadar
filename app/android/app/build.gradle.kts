import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/*
 * Release signing: from `android/key.properties`, or from the environment.
 *
 * NOTHING SECRET LIVES IN THIS REPOSITORY. There is no keystore here, no
 * passwords and no alias -- the file this reads is gitignored
 * (`android/.gitignore`, plus the root `.gitignore`), and the keystore itself is
 * something the owner generates once and keeps forever. Losing it means Android
 * will refuse every future update of the installed app, so it is not a thing a
 * build script, or an agent, may create on someone's behalf. `RELEASE-ANDROID.md`
 * is the instruction for making one.
 *
 * Two sources, in this order, because there are two places a release is built:
 *
 * - `android/key.properties` -- the local machine. This is Flutter's documented
 *   convention (https://docs.flutter.dev/deployment/android), so the file looks
 *   the way anyone who has signed a Flutter app before expects it to;
 * - `TASKRADAR_ANDROID_*` environment variables -- CI, where a file would have to
 *   be written out of a secret anyway. The names are fixed by
 *   `.github/workflows/app-release.yml`, which decodes the keystore secret into
 *   a file and exports the path; if either side is renamed, the other must be
 *   renamed with it or CI and the desk will disagree silently.
 */
val keystoreProperties =
    Properties().apply {
        val file = rootProject.file("key.properties")
        if (file.exists()) file.inputStream().use { load(it) }
    }

fun signingSetting(propertyName: String, environmentName: String): String? =
    (keystoreProperties.getProperty(propertyName) ?: System.getenv(environmentName))
        ?.trim()
        ?.takeIf { it.isNotEmpty() }

val keystorePath = signingSetting("storeFile", "TASKRADAR_ANDROID_KEYSTORE_PATH")
val keystorePassword = signingSetting("storePassword", "TASKRADAR_ANDROID_KEYSTORE_PASSWORD")
val keyAliasName = signingSetting("keyAlias", "TASKRADAR_ANDROID_KEY_ALIAS")
val keyPasswordValue = signingSetting("keyPassword", "TASKRADAR_ANDROID_KEY_PASSWORD")

/** The whole configuration, or nothing: a half-filled one cannot sign anything. */
val releaseSigningMissing: List<String> =
    listOfNotNull(
        if (keystorePath == null) "storeFile / TASKRADAR_ANDROID_KEYSTORE_PATH" else null,
        if (keystorePassword == null) "storePassword / TASKRADAR_ANDROID_KEYSTORE_PASSWORD" else null,
        if (keyAliasName == null) "keyAlias / TASKRADAR_ANDROID_KEY_ALIAS" else null,
        if (keyPasswordValue == null) "keyPassword / TASKRADAR_ANDROID_KEY_PASSWORD" else null,
    )

val releaseSigningAvailable = releaseSigningMissing.isEmpty()

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

    signingConfigs {
        create("release") {
            // Only filled in when everything is present. An empty config is what
            // makes the guard below the single place that decides what happens
            // when it is not -- rather than AGP quietly producing
            // `app-release-unsigned.apk` and Flutter failing on a missing file.
            if (releaseSigningAvailable) {
                // Relative paths resolve against `android/app/`, which is where
                // the CI workflow writes the decoded keystore. An absolute path
                // (the usual choice on a desk) is used as-is.
                storeFile = file(keystorePath!!)
                storePassword = keystorePassword
                keyAlias = keyAliasName
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            /*
             * Signed with the real release key, or not built at all.
             *
             * Until F5 this line read `signingConfigs.getByName("debug")` with a
             * TODO next to it, and that is the bug being fixed: a debug-signed
             * APK installs and runs, so nothing looks wrong -- until the debug
             * keystore is regenerated (a fresh checkout, another machine, a
             * reinstalled SDK) and Android refuses to update the installed app,
             * leaving uninstall-and-lose-your-data as the only way forward. The
             * debug key is also not a secret, so anyone could sign an update for
             * this application id.
             *
             * A missing config now stops the build with a message (see the guard
             * at the bottom of this file) instead of silently producing an
             * artifact that is wrong in a way nobody notices for months. Debug
             * builds are untouched and still need no configuration at all.
             */
            signingConfig = signingConfigs.getByName("release")

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

/*
 * The loud failure.
 *
 * Checked when the task graph is ready rather than at configuration time,
 * because this file is configured for *every* build -- including
 * `flutter build apk --debug` and `flutter run`, which must keep working on a
 * machine that has never seen a keystore. The graph knows which build type was
 * actually asked for.
 *
 * Only this module's own release tasks count: `:app:assembleRelease` is what
 * `flutter build apk --release` runs, `:app:bundleRelease` is the AAB, and
 * `:app:packageRelease` is what a plugin might depend on directly. Matching
 * anything merely containing "Release" would also catch `lintVitalRelease` and
 * assorted plugin tasks that do not produce a signed artifact.
 */
val releaseTaskNames = Regex("^(assemble|bundle|package)Release$")
val modulePathPrefix = "${project.path}:"

gradle.taskGraph.whenReady {
    val buildingRelease =
        allTasks.any { task ->
            task.path.startsWith(modulePathPrefix) && releaseTaskNames.matches(task.name)
        }

    if (buildingRelease && !releaseSigningAvailable) {
        throw GradleException(
            """
            |
            |TaskRadar: release signing is not configured, so this build is refusing to continue.
            |
            |Missing: ${releaseSigningMissing.joinToString(", ")}
            |
            |A release APK MUST NOT be signed with the debug key: the debug key is not a
            |secret, and if it is ever regenerated Android will refuse to update the app
            |that was installed with it.
            |
            |Locally: create android/key.properties (gitignored) with
            |    storeFile=<absolute path to your .jks>
            |    storePassword=<...>
            |    keyAlias=<...>
            |    keyPassword=<...>
            |
            |In CI: set TASKRADAR_ANDROID_KEYSTORE_PATH, TASKRADAR_ANDROID_KEYSTORE_PASSWORD,
            |TASKRADAR_ANDROID_KEY_ALIAS and TASKRADAR_ANDROID_KEY_PASSWORD.
            |
            |No keystore yet? app/RELEASE-ANDROID.md explains how to create one -- and why
            |losing it means never being able to update the installed app again.
            |
            |Debug builds need none of this: flutter build apk --debug still works.
            |
            """.trimMargin(),
        )
    }
}
