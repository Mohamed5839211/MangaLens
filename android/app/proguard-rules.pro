# ML Kit Text Recognition ProGuard Rules
# Ignore missing classes from other language packs that are not imported (like Devanagari, etc.)
-dontwarn com.google.mlkit.vision.text.**
-dontwarn com.google.android.gms.internal.mlkit_vision_text_common.**
