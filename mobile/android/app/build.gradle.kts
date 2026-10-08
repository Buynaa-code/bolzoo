import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Use the existing Play upload key. Never fall back to the debug identity.
// CI variables override the ignored local file without putting secrets in args.
val releaseKeyProperties = Properties()
val releaseKeyPropertiesFile = rootProject.file("key.properties")
if (releaseKeyPropertiesFile.isFile) {
    releaseKeyPropertiesFile.inputStream().use { releaseKeyProperties.load(it) }
}
fun releaseSigningValue(property: String, environment: String): String? =
    providers.environmentVariable(environment).orNull
        ?: releaseKeyProperties.getProperty(property)

val releaseStorePath = releaseSigningValue("storeFile", "HAMTDAA_ANDROID_STORE_FILE")
val releaseStorePassword = releaseSigningValue("storePassword", "HAMTDAA_ANDROID_STORE_PASSWORD")
val releaseKeyAlias = releaseSigningValue("keyAlias", "HAMTDAA_ANDROID_KEY_ALIAS")
val releaseKeyPassword = releaseSigningValue("keyPassword", "HAMTDAA_ANDROID_KEY_PASSWORD")
val releaseStoreFile = releaseStorePath?.takeIf { it.isNotBlank() }?.let { rootProject.file(it) }

val checkReleaseSigning = tasks.register("checkReleaseSigning") {
    group = "verification"
    description = "Checks release signing inputs without printing credentials."
    doLast {
        val missing = listOf(
            "storeFile / HAMTDAA_ANDROID_STORE_FILE" to releaseStorePath,
            "storePassword / HAMTDAA_ANDROID_STORE_PASSWORD" to releaseStorePassword,
            "keyAlias / HAMTDAA_ANDROID_KEY_ALIAS" to releaseKeyAlias,
            "keyPassword / HAMTDAA_ANDROID_KEY_PASSWORD" to releaseKeyPassword,
        ).filter { it.second.isNullOrBlank() }.map { it.first }
        if (missing.isNotEmpty()) {
            throw GradleException(
                "Release signing is not configured. Set ${missing.joinToString(", ")} " +
                    "in android/key.properties or the environment. See android/key.properties.example. " +
                    "Use the existing store upload key; debug signing is disabled for release builds."
            )
        }
        if (releaseStoreFile?.isFile != true || !releaseStoreFile.canRead()) {
            throw GradleException("The configured release keystore is missing or unreadable.")
        }
        if (releaseKeyAlias.equals("androiddebugkey", ignoreCase = true)) {
            throw GradleException("The Android debug key cannot sign a release build.")
        }
    }
}

// Cover direct packaging/signing tasks and aggregate release builds alike.
// Debug builds and IDE configuration do not need production credentials.
tasks.configureEach {
    if (name.contains("Release") && name != checkReleaseSigning.name) {
        dependsOn(checkReleaseSigning)
    }
}

android {
    namespace = "mn.moch.hamtdaa"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "mn.moch.hamtdaa"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseStoreFile
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
