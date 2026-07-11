plugins {
    id("com.android.library")
}

android {
    namespace = "org.amnezia.awg.tunnel"
    compileSdk = 36
    ndkVersion = "27.0.12077973"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        minSdk = 24
        ndk { abiFilters += "arm64-v8a" }
    }
    externalNativeBuild { cmake { path = file("tools/CMakeLists.txt") } }
    buildTypes {
        all {
            externalNativeBuild {
                cmake {
                    targets += listOf("libwg-go.so", "libwg.so", "libwg-quick.so")
                    arguments += "-DGRADLE_USER_HOME=${project.gradle.gradleUserHomeDir}"
                }
            }
        }
        getByName("release") {
            externalNativeBuild { cmake { arguments += "-DANDROID_PACKAGE_NAME=tech.router1.internal" } }
        }
        getByName("debug") {
            externalNativeBuild { cmake { arguments += "-DANDROID_PACKAGE_NAME=tech.router1.internal" } }
        }
    }
}

dependencies {
    implementation("androidx.annotation:annotation:1.9.1")
    implementation("androidx.collection:collection:1.4.5")
    compileOnly("com.google.code.findbugs:jsr305:3.0.2")
}
