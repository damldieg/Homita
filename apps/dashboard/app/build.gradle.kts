import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

// URL del backend de Homita para cada instalación, sin dejarla en el código. Se busca, por este orden, en
// apps/dashboard/homita.properties (ver homita.properties.example), en -Phomita.baseUrl=… y en la variable de entorno
// HOMITA_BASE_URL. La release no se compila sin ella; la debug apunta por defecto al backend local del emulador.
val homita = Properties().apply {
    rootProject.file("homita.properties").takeIf { it.isFile }?.reader()?.use { load(it) }
}
fun homitaSetting(name: String, env: String): String? =
    (homita.getProperty(name) ?: providers.gradleProperty(name).orNull ?: providers.environmentVariable(env).orNull)
        ?.trim()?.takeIf { it.isNotEmpty() }?.let { if (it.endsWith("/")) it else "$it/" }

val releaseBaseUrl = homitaSetting("homita.baseUrl", "HOMITA_BASE_URL")
val debugBaseUrl = homitaSetting("homita.debugBaseUrl", "HOMITA_DEBUG_BASE_URL") ?: "http://10.0.2.2:54321/functions/v1/api/"
fun cleartext(url: String?) = (url?.startsWith("http://") == true).toString()

// Firma de release (dashboard-actualizacion-remota): la clave es de Damian y vive fuera del repo.
val releaseStoreFile: String? = providers.gradleProperty("homita.releaseStoreFile").orNull
val releaseSigningReady = releaseStoreFile != null && file(releaseStoreFile).exists()
// Si la propiedad apunta a un archivo que no existe, se avisa en vez de firmar en silencio con debug (R1-09).
if (releaseStoreFile != null && !releaseSigningReady) {
    logger.warn("homita.releaseStoreFile apunta a un archivo que no existe: la release se firma con debug")
}

android {
    namespace = "com.dld.homita.dashboard"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.dld.homita.dashboard"
        minSdk = 29 // XORO CPF 10PF: Android 10
        targetSdk = 37
        // La publicación fija la versión (scripts/dashboard/publish.sh): -Phomita.versionCode=N -Phomita.versionName=X
        versionCode = (project.findProperty("homita.versionCode") as String?)?.toInt() ?: 1
        versionName = (project.findProperty("homita.versionName") as String?) ?: "1.0"
        // El RTC del marco no conserva la hora: cualquier fecha anterior a la compilación es falsa.
        buildConfigField("long", "BUILD_TIME", "${System.currentTimeMillis()}L")
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = providers.gradleProperty("homita.releaseStorePassword").get()
                keyAlias = providers.gradleProperty("homita.releaseKeyAlias").get()
                keyPassword = providers.gradleProperty("homita.releaseKeyPassword").get()
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            buildConfigField("String", "BASE_URL", "\"${releaseBaseUrl.orEmpty()}\"")
            manifestPlaceholders["cleartext"] = cleartext(releaseBaseUrl)
            // Firma de release: clave privada de Damian (propiedades en ~/.gradle/gradle.properties, nunca en el repo).
            // Sin ellas, la release sigue firmada con debug para la instalación local por ADB (no publicable).
            signingConfig = if (releaseSigningReady) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
        debug {
            buildConfigField("String", "BASE_URL", "\"$debugBaseUrl\"")
            manifestPlaceholders["cleartext"] = cleartext(debugBaseUrl)
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

// Sin URL, la release se para antes de compilar nada (la debug y los tests no la necesitan)
val checkHomitaBaseUrl = tasks.register("checkHomitaBaseUrl") {
    val url = releaseBaseUrl
    doLast {
        if (url == null) throw GradleException(
            "Falta la URL del backend: copia apps/dashboard/homita.properties.example a apps/dashboard/homita.properties " +
                "y rellena homita.baseUrl (o usa -Phomita.baseUrl=… o HOMITA_BASE_URL)."
        )
    }
}
tasks.matching { it.name == "preReleaseBuild" }.configureEach { dependsOn(checkHomitaBaseUrl) }

dependencies {
    implementation("androidx.core:core-ktx:1.19.1")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.11.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.11.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.11.0")
    implementation(platform("androidx.compose:compose-bom:2026.09.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended:1.7.8")
    implementation("com.airbnb.android:lottie:6.7.1")

    implementation("com.squareup.retrofit2:retrofit:3.0.0")
    implementation("com.squareup.retrofit2:converter-gson:3.0.0")

    testImplementation("junit:junit:4.13.2")
}
