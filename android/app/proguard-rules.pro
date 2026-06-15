# ProGuard/R8 keep-правила для SimbA.
#
# ВКЛЮЧАЕТСЯ вместе с isMinifyEnabled=true в build.gradle.kts. Сейчас
# минификация выключена (см. комментарий там) — этот файл готов заранее,
# чтобы при включении не ловить рантайм-краши на вырезанных классах.
#
# Перед включением минификации ОБЯЗАТЕЛЬНО прогнать полный сценарий на
# реальном устройстве: вход по SMS, создание заказа с фото, карта, пуши.

# --- Flutter ---
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# --- Firebase / FCM ---
# Firebase активно использует рефлексию для (де)сериализации и реестра
# сервисов. Без keep'ов получение токена и обработка пушей падают.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# --- flutter_local_notifications ---
# Плагин держит ресиверы/сериализацию расписаний; gson-модели нельзя
# обфусцировать, иначе расписанные уведомления не восстанавливаются.
-keep class com.dexterous.** { *; }
-keepclassmembers class * { @com.google.gson.annotations.SerializedName <fields>; }

# --- flutter_secure_storage ---
# Работает поверх AndroidX Security (EncryptedSharedPreferences). Tink
# (крипто-движок под капотом) использует рефлексию для регистрации
# примитивов — без keep'ов расшифровка токена сессии падает.
-keep class androidx.security.crypto.** { *; }
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# --- geolocator ---
-keep class com.baseflow.geolocator.** { *; }

# --- общие ---
# Сохраняем имена enum-значений (часть кода сравнивает по .name).
-keepclassmembers enum * { *; }
# Аннотации и сигнатуры дженериков — для рефлексии и gson.
-keepattributes Signature,*Annotation*,EnclosingMethod,InnerClasses
