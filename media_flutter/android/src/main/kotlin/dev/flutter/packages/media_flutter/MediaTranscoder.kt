package dev.flutter.packages.media_flutter

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.AudioEncoderSettings
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * H.264 + AAC transcode with target resolution (long-edge cap; same geometry as desktop FFmpeg transcode).
 *
 * Must run [Transformer] on the main looper thread; this method blocks the caller until export
 * finishes (same pattern as synchronous JNI from Rust).
 */
@UnstableApi
object MediaTranscoder {
    init {
        // Ensure `transcodeProgress` resolves before first export.
        MediaJni.javaClass
    }

    /**
     * @return `null` on success, or an error message.
     */
    @JvmStatic
    fun runTranscode(
        context: Context,
        inPath: String,
        outPath: String,
        videoBitrateKbps: Int,
        outWidth: Int,
        outHeight: Int,
        audioBitrateKbps: Int,
        progressPtr: Long,
    ): String? {
        val latch = CountDownLatch(1)
        val err = AtomicReference<String?>(null)

        val presentation =
            Presentation.createForWidthAndHeight(
                outWidth,
                outHeight,
                Presentation.LAYOUT_SCALE_TO_FIT,
            )
        val effects =
            Effects(
                /* audioProcessors */ emptyList(),
                /* videoEffects */ listOf(presentation),
            )
        // `File(contentUri)` is invalid — Transformer would write an empty/corrupt MP4 (~few KB).
        val uri =
            when {
                inPath.startsWith("content://") -> Uri.parse(inPath)
                inPath.startsWith("file://") -> Uri.parse(inPath)
                else -> Uri.fromFile(File(inPath))
            }
        val edited =
            EditedMediaItem.Builder(MediaItem.fromUri(uri))
                .setEffects(effects)
                .build()

        val videoBps = videoBitrateKbps * 1000
        val audioBps = audioBitrateKbps * 1000

        // Media3 1.9+: mime types on Transformer.Builder; HDR mode on Composition.Builder
        // (legacy TransformationRequest API removed upstream).
        val composition =
            Composition.Builder(EditedMediaItemSequence.Builder(edited).build())
                .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
                .build()

        val encoderFactory =
            DefaultEncoderFactory.Builder(context)
                .setRequestedVideoEncoderSettings(
                    VideoEncoderSettings.Builder()
                        .setBitrate(videoBps)
                        .build(),
                )
                .setRequestedAudioEncoderSettings(
                    AudioEncoderSettings.Builder()
                        .setBitrate(audioBps)
                        .build(),
                )
                .build()

        Handler(Looper.getMainLooper()).post {
            try {
                val transformer =
                    Transformer.Builder(context)
                        .setVideoMimeType(MimeTypes.VIDEO_H264)
                        .setAudioMimeType(MimeTypes.AUDIO_AAC)
                        .setEncoderFactory(encoderFactory)
                        .addListener(
                            object : Transformer.Listener {
                                override fun onCompleted(
                                    composition: Composition,
                                    exportResult: ExportResult,
                                ) {
                                    MediaJni.transcodeProgress(progressPtr, 1.0)
                                    latch.countDown()
                                }

                                override fun onError(
                                    composition: Composition,
                                    exportResult: ExportResult,
                                    exportException: ExportException,
                                ) {
                                    err.set(
                                        exportException.message
                                            ?: exportException.toString(),
                                    )
                                    latch.countDown()
                                }
                            },
                        )
                        .build()
                MediaJni.transcodeProgress(progressPtr, 0.02)
                File(outPath).parentFile?.mkdirs()
                transformer.start(composition, outPath)
            } catch (e: Throwable) {
                err.set(e.message ?: e.toString())
                latch.countDown()
            }
        }

        if (!latch.await(45, TimeUnit.MINUTES)) {
            return "Android transcode timed out"
        }
        return err.get()
    }
}
