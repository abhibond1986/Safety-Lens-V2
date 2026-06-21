# Flutter-specific ProGuard rules
# Keep Flutter engine
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep Dart native methods
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Keep http client (needed for API calls)
-keep class org.apache.http.** { *; }
-dontwarn org.apache.http.**
-dontwarn android.net.**

# Keep Gson / JSON serialization if used
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# Geolocator
-keep class com.baseflow.geolocator.** { *; }

# Image picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# Connectivity plus
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# Don't warn about missing classes from optional dependencies
-dontwarn com.google.android.play.core.**
-dontwarn com.google.firebase.**
