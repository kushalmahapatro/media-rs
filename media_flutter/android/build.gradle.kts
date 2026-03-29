plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

group = "dev.flutter.packages.media_flutter"

android {
    namespace = "dev.flutter.packages.media_flutter"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }
}

// Another dependency (e.g. ExoPlayer / video_player) may pull an older media3-transformer; then
// Transformer.Builder at runtime lacks setTransformationRequest → NoSuchMethodError.
configurations.configureEach {
    resolutionStrategy.eachDependency {
        if (requested.group == "androidx.media3") {
            useVersion("1.5.1")
        }
    }
}

dependencies {
    // Pin versions explicitly — `media3-bom` is not published for every line (e.g. 1.5.1).
    implementation("androidx.media3:media3-transformer:1.5.1")
    implementation("androidx.media3:media3-effect:1.5.1")
}
