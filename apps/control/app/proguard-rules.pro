# Añade aquí las reglas de ofuscación específicas del proyecto.

# 1. Mantener las firmas genéricas y las anotaciones (Crítico para Retrofit, Gson y ViewModels)
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# 2. Proteger los Modelos de Datos (Data Classes) de la API
-keep class com.lito.planify.data.api.** { *; }

# 3. Proteger los ViewModels
-keep class com.lito.planify.viewmodel.** { *; }

# 4. Proteger el CrashReporter
-keep class com.lito.planify.util.CrashReporter { *; }

# 5. Reglas generales para Gson
-keep class sun.misc.Unsafe { *; }
-keep class com.google.gson.stream.** { *; }
-dontwarn sun.misc.**

# 6. Reglas específicas de Gson para TypeAdapters y subclases de TypeToken
#    (necesarias a partir de R8 3.0 para que `object : TypeToken<...>() {}` no pierda el tipo genérico)
-keep class * extends com.google.gson.TypeAdapter
-keep class * extends com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
