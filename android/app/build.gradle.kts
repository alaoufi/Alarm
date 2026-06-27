plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mudhakkarati.app"
    compileSdk = 36 // مطلوب من بعض الإضافات (flutter_plugin_android_lifecycle)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // مطلوب لـ flutter_local_notifications (تكسير مكتبات Java الحديثة).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.alaoufi.alarm"
        minSdk = 26 // Android 8.0
        // مستوى مستهدف حديث مطلوب لقبول Google Play (يتطلب 34+ للتطبيقات الجديدة).
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    // مفتاح توقيع ثابت يُلتزم في المستودع، حتى تُثبَّت التحديثات فوق بعضها
    // دون خطأ «توقيع غير متطابق» (مشروع شخصي — لا يُنشر على المتجر).
    signingConfigs {
        create("release") {
            storeFile = file("alaoufi-release.jks")
            storePassword = "alaoufi2026"
            keyAlias = "alaoufi"
            keyPassword = "alaoufi2026"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // نعطّل التقليص حتى لا تُحذف أكواد تحتاجها الإضافات (سبب محتمل للانهيار).
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
