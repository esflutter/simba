import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Google services — подхватывает google-services.json (в этом же модуле,
    // android/app/google-services.json) и инжектит Firebase-настройки в сборку.
    id("com.google.gms.google-services")
}

// Релизный ключ подписи читаем из android/key.properties (вне git).
// Файл с реальным keystore хранится у владельца проекта, не коммитится.
// Если файла нет — собираем debug-ключом (как раньше), чтобы локальная
// разработка и тестовые APK не требовали настройки. Перед публикацией в
// Google Play создать key.properties с путём к keystore и паролями.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
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
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // Реальный релизный ключ, если настроен key.properties; иначе
            // debug-ключ (для локальных/тестовых сборок). Google Play
            // примет только APK/AAB, подписанный настоящим release-ключом.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8/минификацию НЕ трогаем явно: Flutter включает её в release
            // по умолчанию (и так было во всех прежних сборках). Добавляем
            // только наши keep-правила поверх дефолтных Flutter — чтобы
            // обфускация не вырезала классы, которые Firebase, FCM и
            // защищённое хранилище дёргают рефлексией.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
