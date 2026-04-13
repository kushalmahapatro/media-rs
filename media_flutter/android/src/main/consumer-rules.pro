# Called only from Rust JNI (not visible to R8 static analysis).
-keepclassmembers class dev.flutter.packages.media_flutter.MediaJni {
    public static android.graphics.Bitmap applyExifOrientation(java.lang.String,android.graphics.Bitmap);
}
