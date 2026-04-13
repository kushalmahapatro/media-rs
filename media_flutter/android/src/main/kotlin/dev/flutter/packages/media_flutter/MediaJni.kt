package dev.flutter.packages.media_flutter

import android.graphics.Bitmap
import android.graphics.Matrix
import android.media.ExifInterface
import java.io.IOException

/** JNI entry points implemented in `libmedia.so` (Rust). */
object MediaJni {
    init {
        System.loadLibrary("media")
    }

    @JvmStatic
    external fun transcodeProgress(ptr: Long, fraction: Double)

    /**
     * Applies JPEG/HEIF EXIF orientation so pixels match display orientation.
     * Rust JNI cannot reliably invoke [Matrix.postRotate] on all ART builds; Kotlin bytecode does.
     */
    @JvmStatic
    fun applyExifOrientation(path: String, bitmap: Bitmap): Bitmap {
        return try {
            val exif = ExifInterface(path)
            val orientation = exif.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
            if (orientation == ExifInterface.ORIENTATION_UNDEFINED ||
                orientation == ExifInterface.ORIENTATION_NORMAL
            ) {
                return bitmap
            }
            val matrix = Matrix()
            when (orientation) {
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> {
                    matrix.postScale(-1f, 1f)
                    matrix.postRotate(90f)
                }
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_TRANSVERSE -> {
                    matrix.postScale(-1f, 1f)
                    matrix.postRotate(270f)
                }
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                else -> return bitmap
            }
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        } catch (_: IOException) {
            bitmap
        }
    }
}
