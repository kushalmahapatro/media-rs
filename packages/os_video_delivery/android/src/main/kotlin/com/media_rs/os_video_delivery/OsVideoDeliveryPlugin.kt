package com.media_rs.os_video_delivery

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.TransformationRequest
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import com.google.common.collect.ImmutableList
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

@UnstableApi
class OsVideoDeliveryPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var context: Context? = null
    /** Serial queue for retriever/probe/thumbnail work so the Flutter UI thread stays responsive. */
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.media_rs/os_video_delivery")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val ctx = context ?: run {
            result.error("NO_CONTEXT", "Plugin not attached", null)
            return
        }
        when (call.method) {
            "probe" -> {
                val path = call.argument<String>("path")!!
                executor.execute {
                    try {
                        val map = probeVideo(ctx, path)
                        mainHandler.post { result.success(map) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("PROBE", e.message, null) }
                    }
                }
            }

            "estimateDelivery" -> {
                val path = call.argument<String>("path")!!
                @Suppress("UNCHECKED_CAST")
                val profiles = call.argument<List<Map<String, Any>>>("profiles")!!
                executor.execute {
                    try {
                        val info = probeVideoRaw(ctx, path)
                        val rows = profiles.map { p -> estimateRow(info, p) }
                        mainHandler.post { result.success(rows) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("ESTIMATE", e.message, null) }
                    }
                }
            }

            "transcode" -> {
                val inputPath = call.argument<String>("inputPath")!!
                val outputPath = call.argument<String>("outputPath")!!
                @Suppress("UNCHECKED_CAST")
                val profile = call.argument<Map<String, Any>>("profile")!!
                executor.execute {
                    try {
                        transcodeAwaitingOnWorker(ctx, inputPath, outputPath, profile)
                        mainHandler.post { result.success(outputPath) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("TRANSCODE", e.message, null) }
                    }
                }
            }

            "videoThumbnail" -> {
                val path = call.argument<String>("path")!!
                val timeMs = call.argument<Int>("timeMs") ?: 0
                val maxW = call.argument<Int>("maxWidth") ?: 0
                val maxH = call.argument<Int>("maxHeight") ?: 0
                val format = call.argument<String>("format") ?: "jpeg"
                val rotationHint = call.argument<Int>("rotationDegrees")
                executor.execute {
                    try {
                        val bytes =
                            videoThumbnail(ctx, path, timeMs, maxW, maxH, format, rotationHint)
                        mainHandler.post { result.success(bytes) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("THUMB", e.message, null) }
                    }
                }
            }

            else -> result.notImplemented()
        }
    }

    private data class ProbeInfo(
        val durationMs: Long,
        val width: Int,
        val height: Int,
        val rotation: Int,
        val bitrateBps: Int?,
    )

    private fun probeVideo(ctx: Context, path: String): Map<String, Any?> {
        val p = probeVideoRaw(ctx, path)
        return mapOf(
            "durationMs" to p.durationMs.toInt(),
            "displayWidth" to p.width,
            "displayHeight" to p.height,
            "rotationDegrees" to p.rotation,
            "bitrateBps" to p.bitrateBps,
        )
    }

    /**
     * Clockwise rotation (in degrees) to apply so the frame matches how the user expects to see it.
     * [MediaMetadataRetriever] often returns 0 here while the video track still has rotation in
     * [MediaFormat.KEY_ROTATION] (common for phone MP4/MOV).
     */
    private fun resolveVideoRotationDegrees(ctx: Context, path: String, uri: Uri): Int {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(ctx, uri)
            val fromMeta =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                    ?.toIntOrNull() ?: 0
            var r = ((fromMeta % 360) + 360) % 360
            if (r != 0) return r
        } finally {
            retriever.release()
        }
        return rotationDegreesFromVideoTrack(path, ctx, uri)
    }

    private fun rotationDegreesFromVideoTrack(path: String, ctx: Context, uri: Uri): Int {
        val extractor = MediaExtractor()
        try {
            if (path.startsWith("/")) {
                extractor.setDataSource(path)
            } else {
                extractor.setDataSource(ctx, uri, null)
            }
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/")) continue
                if (format.containsKey(MediaFormat.KEY_ROTATION)) {
                    val deg = format.getInteger(MediaFormat.KEY_ROTATION)
                    return ((deg % 360) + 360) % 360
                }
                return 0
            }
        } finally {
            extractor.release()
        }
        return 0
    }

    private fun probeVideoRaw(ctx: Context, path: String): ProbeInfo {
        val uri = if (path.startsWith("/")) Uri.fromFile(File(path)) else Uri.parse(path)
        val retriever = MediaMetadataRetriever()
        retriever.setDataSource(ctx, uri)
        val duration =
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                ?: 0L
        var w =
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
                ?: 0
        var h =
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
                ?: 0
        val bitrate =
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull()
        var rotation =
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
        rotation = ((rotation % 360) + 360) % 360
        retriever.release()
        if (rotation == 0) {
            rotation = rotationDegreesFromVideoTrack(path, ctx, uri)
        }

        // Display dimensions (rotation metadata from file)
        val dispW: Int
        val dispH: Int
        if (rotation == 90 || rotation == 270) {
            dispW = h
            dispH = w
        } else {
            dispW = w
            dispH = h
        }
        return ProbeInfo(duration, dispW, dispH, rotation, bitrate)
    }

    private fun estimateRow(info: ProbeInfo, profile: Map<String, Any>): Map<String, Any> {
        val id = profile["id"] as String
        val maxLong = (profile["maxLongEdgePx"] as Number).toInt()
        val vKbps = (profile["videoBitrateKbps"] as Number).toInt()
        val aKbps = (profile["audioBitrateKbps"] as Number).toInt()
        val muxOverhead = (profile["muxOverheadBytes"] as? Number)?.toLong() ?: 65536L
        val speedFactor =
            (profile["encodeRealtimeSpeedFactor"] as? Number)?.toDouble() ?: 2.5

        val (outW, outH) = fitLongEdge(info.width, info.height, maxLong)
        var vCap = vKbps
        info.bitrateBps?.let { bps ->
            val srcKbps = (bps / 1000).coerceAtLeast(1)
            if (srcKbps > aKbps && vCap + aKbps > srcKbps) {
                vCap = (srcKbps - aKbps).coerceAtLeast(1)
            }
        }
        val totalKbps = vCap.toLong() + aKbps.toLong()
        val rawEst = (totalKbps * 1000L * info.durationMs) / 8000L + muxOverhead
        val estSize = (rawEst * 92L) / 100L
        val estTime = (info.durationMs / speedFactor).toLong().coerceAtLeast(1L)

        return mapOf(
            "profileId" to id,
            "width" to outW,
            "height" to outH,
            "estimatedSizeBytes" to estSize.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
            "videoBitrateKbps" to vCap,
            "audioBitrateKbps" to aKbps,
            "estimatedEncodeTimeMs" to estTime.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
        )
    }

    private fun fitLongEdge(sw: Int, sh: Int, maxLong: Int): Pair<Int, Int> {
        if (sw <= 0 || sh <= 0) return Pair(0, 0)
        val longE = max(sw, sh)
        val shortE = min(sw, sh)
        if (longE <= maxLong) {
            return Pair(sw and 1.inv(), sh and 1.inv())
        }
        val scale = maxLong.toDouble() / longE.toDouble()
        val w = ((sw * scale).roundToInt() and 1.inv()).coerceAtLeast(2)
        val h = ((sh * scale).roundToInt() and 1.inv()).coerceAtLeast(2)
        return Pair(w, h)
    }

    private fun videoThumbnail(
        ctx: Context,
        path: String,
        timeMs: Int,
        maxW: Int,
        maxH: Int,
        format: String,
        rotationDegreesHint: Int?,
    ): ByteArray {
        val uri = if (path.startsWith("/")) Uri.fromFile(File(path)) else Uri.parse(path)
        val rotation =
            rotationDegreesHint?.let { ((it % 360) + 360) % 360 }
                ?: resolveVideoRotationDegrees(ctx, path, uri)

        val retriever = MediaMetadataRetriever()
        retriever.setDataSource(ctx, uri)
        val tw = if (maxW > 0) maxW else 512
        val th = if (maxH > 0) maxH else 512
        val bmp: Bitmap? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                retriever.getScaledFrameAtTime(
                    timeMs * 1000L,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    tw,
                    th,
                )
            } else {
                retriever.getFrameAtTime(
                    timeMs * 1000L,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                )
            }
        retriever.release()
        val frame = bmp ?: throw IllegalStateException("Could not decode frame")

        val oriented = orientBitmap(frame, rotation)
        val stream = ByteArrayOutputStream()
        if (format == "png") {
            oriented.compress(Bitmap.CompressFormat.PNG, 100, stream)
        } else {
            oriented.compress(Bitmap.CompressFormat.JPEG, 90, stream)
        }
        if (oriented !== frame) {
            oriented.recycle()
        }
        frame.recycle()
        return stream.toByteArray()
    }

    private fun orientBitmap(bmp: Bitmap, rotation: Int): Bitmap {
        if (rotation == 0) return bmp
        val m = android.graphics.Matrix()
        m.postRotate(rotation.toFloat())
        return Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
    }

    /**
     * Prepares [EditedMediaItem] on the worker thread (metadata + effects). Transformer itself
     * must be created and [Transformer.start] called on the main looper.
     */
    private fun buildEditedMediaItemForTranscode(
        ctx: Context,
        inputPath: String,
        profile: Map<String, Any>,
    ): EditedMediaItem {
        val maxLong = (profile["maxLongEdgePx"] as Number).toInt()

        val uri = if (inputPath.startsWith("/")) Uri.fromFile(File(inputPath)) else Uri.parse(inputPath)
        val mediaItem = MediaItem.fromUri(uri)

        val info = probeVideoRaw(ctx, inputPath)
        val videoEffects = ImmutableList.Builder<Effect>()
        if (info.width > 0 && info.height > 0) {
            val (outW, outH) = fitLongEdge(info.width, info.height, maxLong)
            if (outW > 0 && outH > 0 && (outW != info.width || outH != info.height)) {
                videoEffects.add(
                    Presentation.createForWidthAndHeight(
                        outW,
                        outH,
                        Presentation.LAYOUT_STRETCH_TO_FIT,
                    ),
                )
            }
        }

        val effects =
            Effects(
                ImmutableList.of<AudioProcessor>(),
                videoEffects.build(),
            )

        return EditedMediaItem.Builder(mediaItem)
            .setEffects(effects)
            .build()
    }

    /**
     * Runs on [executor]. Builds pipeline on the worker, then posts [Transformer] lifecycle to the
     * main thread and blocks the worker until export completes (UI stays responsive).
     */
    private fun transcodeAwaitingOnWorker(
        ctx: Context,
        inputPath: String,
        outputPath: String,
        profile: Map<String, Any>,
    ) {
        val videoKbps = (profile["videoBitrateKbps"] as Number).toInt()
        val edited = buildEditedMediaItemForTranscode(ctx, inputPath, profile)

        val latch = CountDownLatch(1)
        val errorRef = AtomicReference<Exception?>(null)

        mainHandler.post {
            try {
                val encoderFactory =
                    DefaultEncoderFactory.Builder(ctx)
                        .setRequestedVideoEncoderSettings(
                            VideoEncoderSettings.Builder()
                                .setBitrate(videoKbps * 1000)
                                .build(),
                        )
                        .build()

                // HDR sources default to HDR_MODE_KEEP_HDR, which forces HEVC and often hits flaky
                // software encoders (e.g. c2.google.hevc.encoder). Tone-map to SDR so H.264 works.
                val transformationRequest =
                    TransformationRequest.Builder()
                        .setVideoMimeType(MimeTypes.VIDEO_H264)
                        .setAudioMimeType(MimeTypes.AUDIO_AAC)
                        .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
                        .build()

                val transformer =
                    Transformer.Builder(ctx)
                        .setEncoderFactory(encoderFactory)
                        .setTransformationRequest(transformationRequest)
                        .addListener(
                            object : Transformer.Listener {
                                override fun onCompleted(
                                    composition: Composition,
                                    exportResult: ExportResult,
                                ) {
                                    latch.countDown()
                                }

                                override fun onError(
                                    composition: Composition,
                                    exportResult: ExportResult,
                                    exportException: ExportException,
                                ) {
                                    errorRef.set(exportException)
                                    latch.countDown()
                                }
                            },
                        )
                        .build()

                transformer.start(edited, outputPath)
            } catch (e: Exception) {
                errorRef.set(e)
                latch.countDown()
            }
        }

        if (!latch.await(120, TimeUnit.MINUTES)) {
            throw IllegalStateException("Transcode timed out")
        }
        errorRef.get()?.let { throw it }
    }
}
