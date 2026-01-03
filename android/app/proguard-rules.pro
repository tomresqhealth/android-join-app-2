# Keep Daily Flutter plugin and related classes from being stripped/obfuscated
-keep class co.daily.** { *; }
-dontwarn co.daily.**

# Keep Flutter plugin registrant and plugin classes
-keep class io.flutter.plugins.** { *; }
# Keep only the core embedding entry points we actually use.
# Avoid keeping deferred components so R8 can strip them.
-keep class io.flutter.embedding.android.FlutterActivity { *; }
-keep class io.flutter.embedding.android.FlutterFragmentActivity { *; }
-keep class io.flutter.embedding.engine.FlutterEngine { *; }

# Ensure R8 doesn't fail on deferred components references that are unused
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
-dontwarn io.flutter.embedding.android.FlutterPlayStoreSplitApplication

# Keep Kotlin metadata (helps with reflection where used by some plugins)
-keepclassmembers class kotlin.Metadata { *; }

# Permission handler (transitive dependency used by many plugins)
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# Path provider (avoid stripping content providers or initializers)
-keep class io.flutter.plugins.pathprovider.** { *; }
-dontwarn io.flutter.plugins.pathprovider.**

# (Removed) Legacy Play Core keep rules. Not needed when using standard FlutterApplication.