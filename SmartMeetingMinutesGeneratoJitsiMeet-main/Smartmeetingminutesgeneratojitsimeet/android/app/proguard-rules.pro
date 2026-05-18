# Flutter default rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Kotlin
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# Kotlin coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}
-dontwarn kotlinx.coroutines.**

# Kotlinx
-keep class kotlinx.** { *; }
-dontwarn kotlinx.**

# Kotlin parcelize - this is what's missing!
-keep class kotlinx.parcelize.** { *; }
-keep @kotlinx.parcelize.Serializable class * { *; }
-keepclassmembers class * {
    @kotlinx.parcelize.Serializable *;
}
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# Don't warn about missing classes
-dontwarn kotlinx.parcelize.**
-dontwarn kotlin.reflect.jvm.internal.**

# Firebase / Firestore
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Play Core (deferred components - optional, not used by default)
-dontwarn com.google.android.play.core.**

# Giphy SDK (causing the issue)
-keep class com.giphy.sdk.** { *; }
-dontwarn com.giphy.sdk.**

# Keep model classes
-keep class com.example.smartmeetingminutesgeneratojitsimeet.** { *; }

# Prevent R8 from leaving Data object members always null
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
