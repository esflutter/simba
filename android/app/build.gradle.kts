plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Google services — подхватывает google-services.json (в этом же модуле,
    // android/app/google-services.json) и инжектит Firebase-настройки в сборку.
    id("com.google.gms.google-services")
}

android {
    namespace = "com.simba.simba"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Core library desugaring — даёт доступ к java.time и подобным
        // на Android < 26. Требуется пакетом flutter_local_notifications
        // (он строится на java.time для расписания уведомлений).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.simba.simba"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Принудительно 23 (Android 6.0). На API 21-22 AndroidX Security
        // не поддерживает EncryptedSharedPreferences, а наш токен сессии
        // лежит именно там. 5.0/5.1 — доли процента устройств, отказ
        // оправдан безопасностью.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
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

dependencies {
    // Парный артефакт к isCoreLibraryDesugaringEnabled выше — без него
    // флаг ничего не даёт. Минимум 2.0.4 требует flutter_local_notifications 21.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
