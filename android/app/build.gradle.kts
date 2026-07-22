plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val fabulaKeystorePath = System.getenv("FABULA_KEYSTORE_PATH")
val fabulaKeystorePassword = System.getenv("FABULA_KEYSTORE_PASSWORD")
val fabulaKeyAlias = System.getenv("FABULA_KEY_ALIAS")
val fabulaKeyPassword = System.getenv("FABULA_KEY_PASSWORD")

val hasFabulaReleaseSigning = listOf(
    fabulaKeystorePath,
    fabulaKeystorePassword,
    fabulaKeyAlias,
    fabulaKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "tech.router1.fabula"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "tech.router1.fabula"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasFabulaReleaseSigning) {
            create("fabulaRelease") {
                storeFile = file(fabulaKeystorePath!!)
                storePassword = fabulaKeystorePassword
                keyAlias = fabulaKeyAlias
                keyPassword = fabulaKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (!hasFabulaReleaseSigning) {
                throw GradleException(
                    "Fabula release signing is not configured. " +
                        "Refusing to publish an APK with an ephemeral debug key.",
                )
            }
            signingConfig = signingConfigs.getByName("fabulaRelease")
        }
    }
}

dependencies {
    implementation(files("../libs/tunnel-release.aar"))
    implementation("androidx.annotation:annotation:1.9.1")
    implementation("androidx.collection:collection:1.4.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
