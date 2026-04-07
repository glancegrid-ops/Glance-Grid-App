plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("com.chaquo.python")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.glance_grid_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.glance_grid_app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    ndkVersion = "27.0.12077973"
}

chaquopy {
    defaultConfig {
         version = "3.10"
        pip {
            install("numpy")
            install("opencv-python-headless==4.5.1.48")
            // // (opencv-python is loaded via mtcnn dependency and is tied to Chaquopy-supported versions)
             install("fastapi")
            install("pyyaml")
            install("mtcnn==0.1.1")
            // TensorFlow and TensorFlow Lite NOT available in Chaquopy 13.1 index.
            // DeepFace requires TensorFlow. TFLite also unavailable.
            // Face detection works via MTCNN + OpenCV Haar Cascade fallback.
            // deepface_enabled flag is set via config YAML and reported in JSON.
        }
    }
}

flutter {
    source = "../.."
}
