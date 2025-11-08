plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android") // ✅ Correct Kotlin plugin ID
    id("com.google.gms.google-services") // ✅ Firebase plugin
    id("dev.flutter.flutter-gradle-plugin") // ✅ Must come last
}

android {
    namespace = "com.example.smartbilling"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "com.example.smartbilling"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

   buildTypes {
    getByName("release") {
        // Temporary debug signing for testing
        signingConfig = signingConfigs.getByName("debug")

        // ✅ Disable both shrinkers to prevent Gradle crash
        isMinifyEnabled = false
        isShrinkResources = false
    }

    getByName("debug") {
        // Optional, ensures debug also won’t shrink
        isMinifyEnabled = false
        isShrinkResources = false
    }
}

}

flutter {
    source = "../.."
}

dependencies {
    // ✅ Import Firebase BoM to manage versions automatically
    implementation(platform("com.google.firebase:firebase-bom:33.3.0"))

    // ✅ Firebase dependencies
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-storage")

    // ✅ (Optional) Crashlytics, Messaging, etc. — uncomment if needed
    // implementation("com.google.firebase:firebase-crashlytics")
    // implementation("com.google.firebase:firebase-messaging")
}
