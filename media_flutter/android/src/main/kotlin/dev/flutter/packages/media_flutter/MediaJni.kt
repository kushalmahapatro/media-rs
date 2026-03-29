package dev.flutter.packages.media_flutter

/** JNI entry points implemented in `libmedia.so` (Rust). */
object MediaJni {
    init {
        System.loadLibrary("media")
    }

    @JvmStatic
    external fun transcodeProgress(ptr: Long, fraction: Double)
}
