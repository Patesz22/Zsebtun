import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

configure<com.android.build.api.dsl.ApplicationExtension> {
    namespace = "com.patesz2.zsebtun"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            val storeFilePath = keystoreProperties.getProperty("storeFile")
            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
            }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    defaultConfig {
        applicationId = "com.patesz2.zsebtun"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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

val isWindows = System.getProperty("os.name").lowercase().contains("windows")

tasks.register<Exec>("runFlutterUnitTests") {
    description = "Executes Flutter unit tests prior to Android APK compilation."
    workingDir = rootProject.projectDir.parentFile
    if (isWindows) {
        commandLine("cmd", "/c", "flutter", "test")
    } else {
        commandLine("flutter", "test")
    }
}

gradle.projectsEvaluated {
    tasks.matching { task ->
        task.name.startsWith("assemble") || task.name.startsWith("bundle")
    }.configureEach {
        dependsOn("runFlutterUnitTests")
    }
}