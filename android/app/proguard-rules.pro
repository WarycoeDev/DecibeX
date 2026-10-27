# --- youtubedl-android / extractor ---
-keep class com.yausername.** { *; }
-keep class com.yausername.youtubedl_android.** { *; }
-keep class com.yausername.ffmpeg.** { *; }
-keep class com.yausername.aria2c.** { *; }

# --- extractor (Dart plugin) ---
-keep class com.ashiish.extractor.** { *; }

# --- JNI: no renombrar métodos nativos ---
-keepclasseswithmembernames class * {
    native <methods>;
}

# --- Reflexión usada por el plugin ---
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod