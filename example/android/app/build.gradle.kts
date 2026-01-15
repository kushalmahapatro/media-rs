plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.example"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.example"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Only build for 64-bit architectures (we only have 64-bit native libraries)
        // This prevents building for 32-bit ARM (armeabi-v7a) which we don't support
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    
    packaging {
        jniLibs {
            // Ensure libc++_shared.so is included when using libheif (C++ library)
            // This is required because libheif links against c++_shared
            // Pick the first occurrence if multiple versions exist
            pickFirsts += "**/libc++_shared.so"
        }
    }
    
    // Copy libc++_shared.so from NDK to jniLibs directory
    // This ensures it's bundled in the APK's lib/arm64-v8a/ directory
    val ndkHome = System.getenv("ANDROID_NDK_HOME") ?: System.getProperty("android.ndk.path") ?: ""
    if (ndkHome.isNotEmpty()) {
        val copyCxxShared = tasks.register("copyCxxShared") {
            doLast {
                val abis = listOf("arm64-v8a", "x86_64")
                val ndkArchs = mapOf("arm64-v8a" to "aarch64", "x86_64" to "x86_64")
                val hostTag = "darwin-x86_64" // NDK 27+ typically uses this even on Apple Silicon
                
                abis.forEach { abi ->
                    val ndkArch = ndkArchs[abi] ?: return@forEach
                    val sourceFile = File("$ndkHome/toolchains/llvm/prebuilt/$hostTag/sysroot/usr/lib/$ndkArch-linux-android/libc++_shared.so")
                    if (sourceFile.exists()) {
                        // Copy directly to jniLibs directory - this is where Gradle bundles native libraries
                        val destDir = File("${project.projectDir}/src/main/jniLibs/$abi")
                        destDir.mkdirs()
                        val destFile = File(destDir, "libc++_shared.so")
                        sourceFile.copyTo(destFile, overwrite = true)
                        println("✓ Copied libc++_shared.so for $abi to ${destFile.path}")
                    } else {
                        println("Warning: libc++_shared.so not found at ${sourceFile.path}")
                    }
                }
            }
        }
        // Run before merging native libs (for both debug and release)
        // Use afterEvaluate to ensure tasks exist before configuring them
        afterEvaluate {
            tasks.matching { it.name.startsWith("merge") && it.name.endsWith("NativeLibs") }.configureEach {
                dependsOn(copyCxxShared)
            }
        }
    }
}

flutter {
    source = "../.."
}
