//! Android: `MediaExtractor` probe + `MediaMetadataRetriever` thumbnails + **Media3 Transformer**
//! transcode (H.264/AAC, scaled) with NDK **remux** fallback when the plugin classes are missing.

use std::fs::{File, OpenOptions};
use std::os::unix::io::AsRawFd;
use std::sync::OnceLock;
use std::thread;
use std::time::Instant;

use jni::objects::{JByteArray, JClass, JObject, JString, JValue};
use jni::{JavaVM, JNIEnv};
use mediacodec::{BufferInfo, MediaExtractor, MediaMuxer, OutputFormat};

use crate::api::{ThumbnailFormat, TimelineThumbnail, TranscodeProgress, VideoProbe};
use crate::frb_generated::StreamSink;

static ANDROID_JAVA_VM: OnceLock<JavaVM> = OnceLock::new();

/// Registered from [JNI_OnLoad](crate::JNI_OnLoad) when the JVM loads `libmedia.so` via
/// `System.loadLibrary` (optional; often unused with Flutter native assets).
pub(crate) unsafe fn register_java_vm(vm: *mut jni::sys::JavaVM) -> jni::sys::jint {
    if let Ok(jvm) = JavaVM::from_raw(vm) {
        let _ = ANDROID_JAVA_VM.set(jvm);
    }
    jni::sys::JNI_VERSION_1_6
}

// Flutter native assets use dynamic_loading_bundle (no JNI_OnLoad). JavaVM via JNI_GetCreatedJavaVMs
// from libnativehelper (linked in build.rs).
#[link(name = "nativehelper", kind = "dylib")]
unsafe extern "C" {
    fn JNI_GetCreatedJavaVMs(
        vm_buf: *mut *mut jni::sys::JavaVM,
        buf_len: jni::sys::jsize,
        n_vms: *mut jni::sys::jsize,
    ) -> jni::sys::jint;
}

unsafe fn java_vm_via_get_created_java_vms() -> Result<JavaVM, String> {
    let mut buf = [std::ptr::null_mut::<jni::sys::JavaVM>(); 1];
    let mut n: jni::sys::jsize = 0;
    let st = JNI_GetCreatedJavaVMs(buf.as_mut_ptr(), 1, &mut n);
    if st != jni::sys::JNI_OK {
        return Err(format!("JNI_GetCreatedJavaVMs returned {st}"));
    }
    if n < 1 || buf[0].is_null() {
        return Err(format!("JNI_GetCreatedJavaVMs: unexpected n={n}"));
    }
    JavaVM::from_raw(buf[0]).map_err(|e| format!("JavaVM::from_raw: {e}"))
}

pub fn probe_media_extractor(path: &str) -> Result<VideoProbe, String> {
    let mut probe = with_jni_env(|env| probe_media_extractor_jni(env, path))?;
    probe_image_dimensions_if_needed(path, &mut probe)?;
    Ok(probe)
}

/// [MediaExtractor] + [MediaFormat] via JNI (probe only; mux/remux uses NDK via vendored `mediacodec` rlib).
fn probe_media_extractor_jni<'local>(
    env: &mut JNIEnv<'local>,
    path: &str,
) -> Result<VideoProbe, String> {
    let mut probe = VideoProbe {
        duration_ms: None,
        width: None,
        height: None,
        video_bitrate: None,
        audio_bitrate: None,
        frame_rate: None,
        video_codec: None,
        audio_codec: None,
    };

    let jpath = env.new_string(path).map_err(|e| format!("path jstring: {e}"))?;
    let ex_class = env
        .find_class("android/media/MediaExtractor")
        .map_err(|e| format!("MediaExtractor class: {e}"))?;
    let extractor = env
        .new_object(&ex_class, "()V", &[])
        .map_err(|e| format!("new MediaExtractor: {e}"))?;

    let mut run = || -> Result<(), String> {
        // Still images / bad paths throw from setDataSource; fall back to BitmapFactory bounds probe.
        match env.call_method(
            &extractor,
            "setDataSource",
            "(Ljava/lang/String;)V",
            &[JValue::Object(&jpath)],
        ) {
            Ok(_) => {}
            Err(_) => {
                let _ = env.exception_clear();
                return Ok(());
            }
        }

        let n = env
            .call_method(&extractor, "getTrackCount", "()I", &[])
            .map_err(|e| format!("getTrackCount: {e}"))?
            .i()
            .map_err(|_| "getTrackCount not int")?;

        for i in 0..n {
            let format_obj = env
                .call_method(
                    &extractor,
                    "getTrackFormat",
                    "(I)Landroid/media/MediaFormat;",
                    &[JValue::Int(i)],
                )
                .map_err(|e| format!("getTrackFormat({i}): {e}"))?
                .l()
                .map_err(|_| "getTrackFormat not object")?;
            if format_obj.is_null() {
                continue;
            }

            let mime = media_format_get_string(env, &format_obj, "mime")?.unwrap_or_default();

            if mime.starts_with("video/") && probe.width.is_none() {
                let w = media_format_try_i32(env, &format_obj, "width")?.map(|v| v as u32);
                let h = media_format_try_i32(env, &format_obj, "height")?.map(|v| v as u32);
                let rot = media_format_try_i32(env, &format_obj, "rotation-degrees")?.unwrap_or(0);
                if let (Some(wv), Some(hv)) = (w, h) {
                    let (dw, dh) = display_size_for_rotation(wv, hv, rot);
                    probe.width = Some(dw);
                    probe.height = Some(dh);
                } else {
                    probe.width = w;
                    probe.height = h;
                }
                if let Some(br) = media_format_try_i32(env, &format_obj, "bitrate")? {
                    probe.video_bitrate = Some(i64::from(br));
                }
                probe.video_codec = Some(mime);
                if let Some(dus) = media_format_try_i64(env, &format_obj, "durationUs")? {
                    probe.duration_ms = Some(dus / 1000);
                }
            } else if mime.starts_with("audio/") && probe.audio_bitrate.is_none() {
                if let Some(br) = media_format_try_i32(env, &format_obj, "bitrate")? {
                    probe.audio_bitrate = Some(i64::from(br));
                }
                probe.audio_codec = Some(mime);
            }
        }
        Ok(())
    };

    let result = run();
    let _ = env.call_method(&extractor, "release", "()V", &[]);
    result?;
    Ok(probe)
}

fn media_format_get_string<'local>(
    env: &mut JNIEnv<'local>,
    format: &JObject<'local>,
    key: &str,
) -> Result<Option<String>, String> {
    let jkey = env.new_string(key).map_err(|e| format!("key {key}: {e}"))?;
    let v = env
        .call_method(
            format,
            "getString",
            "(Ljava/lang/String;)Ljava/lang/String;",
            &[JValue::Object(&jkey)],
        )
        .map_err(|e| format!("MediaFormat.getString({key}): {e}"))?
        .l()
        .map_err(|_| "getString not ref")?;
    if v.is_null() {
        return Ok(None);
    }
    let jstr = JString::from(v);
    let s = env
        .get_string(&jstr)
        .map_err(|e| format!("Java string {key}: {e}"))?;
    Ok(Some(s.into()))
}

fn media_format_try_i32<'local>(
    env: &mut JNIEnv<'local>,
    format: &JObject<'local>,
    key: &str,
) -> Result<Option<i32>, String> {
    let jkey = env.new_string(key).map_err(|e| format!("key {key}: {e}"))?;
    let has = env
        .call_method(
            format,
            "containsKey",
            "(Ljava/lang/String;)Z",
            &[JValue::Object(&jkey)],
        )
        .map_err(|e| format!("containsKey({key}): {e}"))?
        .z()
        .unwrap_or(false);
    if !has {
        return Ok(None);
    }
    let v = env
        .call_method(
            format,
            "getInteger",
            "(Ljava/lang/String;)I",
            &[JValue::Object(&jkey)],
        )
        .map_err(|e| format!("getInteger({key}): {e}"))?
        .i()
        .map_err(|_| "getInteger not int")?;
    Ok(Some(v))
}

fn media_format_try_i64<'local>(
    env: &mut JNIEnv<'local>,
    format: &JObject<'local>,
    key: &str,
) -> Result<Option<i64>, String> {
    let jkey = env.new_string(key).map_err(|e| format!("key {key}: {e}"))?;
    let has = env
        .call_method(
            format,
            "containsKey",
            "(Ljava/lang/String;)Z",
            &[JValue::Object(&jkey)],
        )
        .map_err(|e| format!("containsKey({key}): {e}"))?
        .z()
        .unwrap_or(false);
    if !has {
        return Ok(None);
    }
    let v = env
        .call_method(
            format,
            "getLong",
            "(Ljava/lang/String;)J",
            &[JValue::Object(&jkey)],
        )
        .map_err(|e| format!("getLong({key}): {e}"))?
        .j()
        .map_err(|_| "getLong not long")?;
    Ok(Some(v))
}

fn android_java_vm() -> Result<&'static JavaVM, String> {
    if let Some(vm) = ANDROID_JAVA_VM.get() {
        return Ok(vm);
    }
    let jvm = unsafe { java_vm_via_get_created_java_vms() }?;
    match ANDROID_JAVA_VM.set(jvm) {
        Ok(()) => {}
        Err(dup) => drop(dup),
    }
    ANDROID_JAVA_VM
        .get()
        .ok_or_else(|| "Android JavaVM: OnceLock empty after init".into())
}

fn with_jni_env<T>(f: impl for<'local> FnOnce(&mut JNIEnv<'local>) -> Result<T, String>) -> Result<T, String> {
    let vm = android_java_vm().map_err(|e| {
        format!(
            "{e} (Flutter native assets skip JNI_OnLoad; we use JNI_GetCreatedJavaVMs from libnativehelper.)"
        )
    })?;
    let mut env = vm
        .attach_current_thread()
        .map_err(|e| format!("JNI attach: {e}"))?;
    f(&mut env)
}

/// [MediaMetadataRetriever] `option` argument: nearest frame in time or to sync sample.
const OPTION_CLOSEST: i32 = 3;
const OPTION_CLOSEST_SYNC: i32 = 2;

fn retriever_duration_ms<'local>(
    env: &mut JNIEnv<'local>,
    retriever: &JObject<'local>,
) -> Result<Option<i64>, String> {
    const METADATA_KEY_DURATION: i32 = 9;
    let js = env
        .call_method(
            retriever,
            "extractMetadata",
            "(I)Ljava/lang/String;",
            &[JValue::Int(METADATA_KEY_DURATION)],
        )
        .map_err(|e| format!("extractMetadata(DURATION): {e}"))?
        .l()
        .map_err(|_| "extractMetadata not ref")?;
    if js.is_null() {
        return Ok(None);
    }
    let jstr = JString::from(js);
    let s = env
        .get_string(&jstr)
        .map_err(|e| format!("duration string: {e}"))?;
    let ms: i64 = s
        .to_string_lossy()
        .parse()
        .map_err(|_| "duration: parse int".to_string())?;
    Ok((ms > 0).then_some(ms))
}

fn clamp_time_sec(time_sec: f64, duration_ms: Option<i64>) -> f64 {
    let t = time_sec.max(0.0);
    let Some(ms) = duration_ms.filter(|&m| m > 0) else {
        return t;
    };
    let dur = ms as f64 / 1000.0;
    let max_t = (dur * 0.999).max(0.0);
    t.min(max_t)
}

/// [MediaMetadataRetriever.getFrameAtTime] often returns null for some timestamps (long GOP, HDR,
/// edge of file). Try closest / sync / small offsets, then start of stream, then any frame (`-1`).
fn get_frame_bitmap<'local>(
    env: &mut JNIEnv<'local>,
    retriever: &JObject<'local>,
    time_us: i64,
) -> Result<JObject<'local>, String> {
    let time_us = time_us.max(0);
    let mut attempts: Vec<(i64, i32)> = Vec::with_capacity(12);
    for opt in [OPTION_CLOSEST, OPTION_CLOSEST_SYNC] {
        attempts.push((time_us, opt));
    }
    for delta in [333_333i64, -333_333, 1_000_000, -1_000_000, 2_000_000] {
        attempts.push(((time_us + delta).max(0), OPTION_CLOSEST));
    }
    attempts.push((0, OPTION_CLOSEST));
    attempts.push((-1, OPTION_CLOSEST));

    for (t, opt) in attempts {
        let bitmap = env
            .call_method(
                retriever,
                "getFrameAtTime",
                "(JI)Landroid/graphics/Bitmap;",
                &[JValue::Long(t), JValue::Int(opt)],
            )
            .map_err(|e| format!("getFrameAtTime: {e}"))?
            .l()
            .map_err(|_| "getFrameAtTime not object")?;
        if !bitmap.is_null() {
            return Ok(bitmap);
        }
    }
    Err("getFrameAtTime returned null (exhausted fallbacks)".into())
}

fn maybe_scale_bitmap<'local>(
    env: &mut JNIEnv<'local>,
    bitmap: &JObject<'local>,
    max_edge: u32,
) -> Result<JObject<'local>, String> {
    if max_edge < 2 {
        return env
            .new_local_ref(bitmap)
            .map_err(|e| format!("new_local_ref: {e}"));
    }
    let w = env
        .call_method(bitmap, "getWidth", "()I", &[])
        .map_err(|e| format!("getWidth: {e}"))?
        .i()
        .map_err(|_| "getWidth not int")?;
    let h = env
        .call_method(bitmap, "getHeight", "()I", &[])
        .map_err(|e| format!("getHeight: {e}"))?
        .i()
        .map_err(|_| "getHeight not int")?;
    let long_edge = w.max(h);
    if long_edge <= max_edge as i32 {
        return env
            .new_local_ref(bitmap)
            .map_err(|e| format!("new_local_ref: {e}"));
    }
    let scale = max_edge as f32 / long_edge as f32;
    let nw = ((w as f32) * scale).round() as i32;
    let nh = ((h as f32) * scale).round() as i32;
    let scaled = env
        .call_static_method(
            "android/graphics/Bitmap",
            "createScaledBitmap",
            "(Landroid/graphics/Bitmap;IIZ)Landroid/graphics/Bitmap;",
            &[
                JValue::Object(bitmap),
                JValue::Int(nw),
                JValue::Int(nh),
                JValue::Bool(1),
            ],
        )
        .map_err(|e| format!("createScaledBitmap: {e}"))?
        .l()
        .map_err(|_| "createScaledBitmap failed")?;
    if env.is_same_object(bitmap, &scaled).unwrap_or(false) {
        return Ok(scaled);
    }
    let _ = env.call_method(bitmap, "recycle", "()V", &[]);
    Ok(scaled)
}

fn compress_bitmap<'local>(
    env: &mut JNIEnv<'local>,
    bitmap: &JObject<'local>,
    format: ThumbnailFormat,
) -> Result<Vec<u8>, String> {
    let fmt_class = env
        .find_class("android/graphics/Bitmap$CompressFormat")
        .map_err(|e| format!("CompressFormat class: {e}"))?;
    let fmt_name = match format {
        ThumbnailFormat::Png => "PNG",
        ThumbnailFormat::Jpeg => "JPEG",
        ThumbnailFormat::Webp => {
            let sdk = env
                .get_static_field("android/os/Build$VERSION", "SDK_INT", "I")
                .map_err(|e| format!("SDK_INT: {e}"))?
                .i()
                .map_err(|_| "SDK_INT type")?;
            if sdk < 14 {
                return Err("WebP thumbnail requires Android API 14+".into());
            }
            "WEBP"
        }
    };
    let compress_fmt = env
        .get_static_field(&fmt_class, fmt_name, "Landroid/graphics/Bitmap$CompressFormat;")
        .map_err(|e| format!("static {fmt_name}: {e}"))?
        .l()
        .map_err(|_| format!("missing CompressFormat::{fmt_name}"))?;

    let stream_class = env
        .find_class("java/io/ByteArrayOutputStream")
        .map_err(|e| format!("ByteArrayOutputStream: {e}"))?;
    let stream = env
        .new_object(&stream_class, "()V", &[])
        .map_err(|e| format!("new ByteArrayOutputStream: {e}"))?;

    let quality = match format {
        ThumbnailFormat::Png => 100,
        ThumbnailFormat::Jpeg => 90,
        ThumbnailFormat::Webp => 90,
    };

    env.call_method(
        bitmap,
        "compress",
        "(Landroid/graphics/Bitmap$CompressFormat;ILjava/io/OutputStream;)Z",
        &[
            JValue::Object(&compress_fmt),
            JValue::Int(quality),
            JValue::Object(&stream),
        ],
    )
    .map_err(|e| format!("compress: {e}"))?;

    let bytes_obj = env
        .call_method(&stream, "toByteArray", "()[B", &[])
        .map_err(|e| format!("toByteArray: {e}"))?
        .l()
        .map_err(|_| "toByteArray not object")?;
    let arr = JByteArray::try_from(bytes_obj).map_err(|_| "toByteArray: not byte[]")?;
    env.convert_byte_array(arr)
        .map_err(|e| format!("convert_byte_array: {e}"))
}

fn looks_like_static_image(path: &str) -> bool {
    let lower = path.to_ascii_lowercase();
    [
        ".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif", ".bmp", ".gif", ".tiff", ".tif",
    ]
    .iter()
    .any(|ext| lower.ends_with(ext))
}

/// Decode a still image with [BitmapFactory] (video pipeline cannot thumbnail these).
fn static_image_thumbnail(
    path: &str,
    max_edge: u32,
    format: ThumbnailFormat,
) -> Result<Vec<u8>, String> {
    with_jni_env(|env| {
        let jpath = env.new_string(path).map_err(|e| format!("path jstring: {e}"))?;
        let bmp_factory = env
            .find_class("android/graphics/BitmapFactory")
            .map_err(|e| format!("BitmapFactory: {e}"))?;
        let bitmap = env
            .call_static_method(
                &bmp_factory,
                "decodeFile",
                "(Ljava/lang/String;)Landroid/graphics/Bitmap;",
                &[JValue::Object(&jpath)],
            )
            .map_err(|e| format!("decodeFile: {e}"))?
            .l()
            .map_err(|_| "decodeFile not object")?;
        if bitmap.is_null() {
            return Err("BitmapFactory.decodeFile returned null".into());
        }
        let scaled = maybe_scale_bitmap(env, &bitmap, max_edge)?;
        let out = compress_bitmap(env, &scaled, format)?;
        let _ = env.call_method(&scaled, "recycle", "()V", &[]);
        Ok(out)
    })
}

fn probe_image_dimensions_if_needed(path: &str, probe: &mut VideoProbe) -> Result<(), String> {
    if probe.width.is_some() {
        return Ok(());
    }
    // decodeFile needs a real filesystem path (not content://).
    if path.starts_with("content://") {
        return Ok(());
    }
    with_jni_env(|env| {
        let jpath = env.new_string(path).map_err(|e| format!("path: {e}"))?;
        let opts_class = env
            .find_class("android/graphics/BitmapFactory$Options")
            .map_err(|e| format!("Options: {e}"))?;
        let opts = env
            .new_object(&opts_class, "()V", &[])
            .map_err(|e| format!("new Options: {e}"))?;
        env.set_field(&opts, "inJustDecodeBounds", "Z", JValue::Bool(1))
            .map_err(|e| format!("inJustDecodeBounds: {e}"))?;
        let bmp_factory = env
            .find_class("android/graphics/BitmapFactory")
            .map_err(|e| format!("BitmapFactory: {e}"))?;
        env.call_static_method(
            &bmp_factory,
            "decodeFile",
            "(Ljava/lang/String;Landroid/graphics/BitmapFactory$Options;)Landroid/graphics/Bitmap;",
            &[JValue::Object(&jpath), JValue::Object(&opts)],
        )
        .map_err(|e| format!("decodeFile bounds: {e}"))?;
        let w = env
            .get_field(&opts, "outWidth", "I")
            .map_err(|e| format!("outWidth: {e}"))?
            .i()
            .map_err(|_| "outWidth type")?;
        let h = env
            .get_field(&opts, "outHeight", "I")
            .map_err(|e| format!("outHeight: {e}"))?
            .i()
            .map_err(|_| "outHeight type")?;
        if w > 0 && h > 0 {
            probe.width = Some(w as u32);
            probe.height = Some(h as u32);
            probe.video_codec = Some("image/static".into());
        }
        Ok(())
    })
}

fn frame_bytes_at_time(
    path: &str,
    time_sec: f64,
    max_edge: u32,
    format: ThumbnailFormat,
) -> Result<Vec<u8>, String> {
    with_jni_env(|env| {
        let jpath = env.new_string(path).map_err(|e| format!("path jstring: {e}"))?;

        let ret_class = env
            .find_class("android/media/MediaMetadataRetriever")
            .map_err(|e| format!("MediaMetadataRetriever: {e}"))?;
        let retriever = env
            .new_object(&ret_class, "()V", &[])
            .map_err(|e| format!("new retriever: {e}"))?;

        env.call_method(
            &retriever,
            "setDataSource",
            "(Ljava/lang/String;)V",
            &[JValue::Object(&jpath)],
        )
        .map_err(|e| format!("setDataSource: {e}"))?;

        let duration_ms = retriever_duration_ms(env, &retriever)?;
        let clamped_sec = clamp_time_sec(time_sec, duration_ms);
        let time_us = ((clamped_sec * 1_000_000.0).round() as i64).max(0);
        let bitmap = get_frame_bitmap(env, &retriever, time_us)?;

        let scaled = maybe_scale_bitmap(env, &bitmap, max_edge)?;
        let out = compress_bitmap(env, &scaled, format)?;
        if !env.is_same_object(&bitmap, &scaled).unwrap_or(false) {
            let _ = env.call_method(&bitmap, "recycle", "()V", &[]);
        }
        let _ = env.call_method(&scaled, "recycle", "()V", &[]);
        let _ = env.call_method(&retriever, "release", "()V", &[]);
        Ok(out)
    })
}

pub fn thumbnail_image(
    path: &str,
    time_sec: f64,
    max_edge: u32,
    format: ThumbnailFormat,
) -> Result<Vec<u8>, String> {
    if looks_like_static_image(path) {
        return static_image_thumbnail(path, max_edge, format);
    }
    frame_bytes_at_time(path, time_sec, max_edge, format)
}

pub fn thumbnail_save_to_path(
    path: &str,
    output_path: &str,
    time_sec: f64,
    max_edge: u32,
    format: ThumbnailFormat,
) -> Result<String, String> {
    let bytes = thumbnail_image(path, time_sec, max_edge, format)?;
    std::fs::write(output_path, &bytes).map_err(|e| format!("thumbnail save: {e}"))?;
    Ok(std::path::Path::new(output_path)
        .canonicalize()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|_| output_path.to_string()))
}

pub fn timeline_thumbnails(
    path: &str,
    frame_count: u32,
    max_edge: u32,
    format: ThumbnailFormat,
    sink: StreamSink<TimelineThumbnail>,
) -> Result<(), String> {
    if frame_count == 0 {
        return Ok(());
    }
    if looks_like_static_image(path) {
        return Err("timeline: still images have no timeline; use a single thumbnail".into());
    }
    let probe = probe_media_extractor(path)?;
    let probe_dur_ms = probe.duration_ms.filter(|&ms| ms > 0);

    // One retriever + one JNI attach: reopening per frame is slow and breaks on some devices.
    with_jni_env(|env| {
        let jpath = env.new_string(path).map_err(|e| format!("path jstring: {e}"))?;
        let ret_class = env
            .find_class("android/media/MediaMetadataRetriever")
            .map_err(|e| format!("MediaMetadataRetriever: {e}"))?;
        let retriever = env
            .new_object(&ret_class, "()V", &[])
            .map_err(|e| format!("new retriever: {e}"))?;

        env.call_method(
            &retriever,
            "setDataSource",
            "(Ljava/lang/String;)V",
            &[JValue::Object(&jpath)],
        )
        .map_err(|e| format!("timeline setDataSource: {e}"))?;

        let dur_ms = probe_dur_ms
            .or(retriever_duration_ms(env, &retriever)?)
            .ok_or_else(|| "timeline: unknown or zero duration".to_string())?;
        let dur_sec = dur_ms as f64 / 1000.0;
        let n = frame_count as f64;

        for i in 0..frame_count {
            let t = dur_sec * (i as f64 + 0.5) / n;
            let t = clamp_time_sec(t, Some(dur_ms));
            let time_us = ((t * 1_000_000.0).round() as i64).max(0);
            let bitmap = get_frame_bitmap(env, &retriever, time_us)
                .map_err(|e| format!("timeline: index {i} (~{t:.2}s): {e}"))?;

            let scaled = maybe_scale_bitmap(env, &bitmap, max_edge)?;
            let out = compress_bitmap(env, &scaled, format)?;
            if !env.is_same_object(&bitmap, &scaled).unwrap_or(false) {
                let _ = env.call_method(&bitmap, "recycle", "()V", &[]);
            }
            let _ = env.call_method(&scaled, "recycle", "()V", &[]);

            let _ = sink.add(TimelineThumbnail {
                index: i,
                time_sec: t,
                image_bytes: out,
            });
            thread::yield_now();
        }

        let _ = env.call_method(&retriever, "release", "()V", &[]);
        Ok(())
    })
}

fn application_context<'local>(env: &mut JNIEnv<'local>) -> Result<JObject<'local>, String> {
    let at = env
        .find_class("android/app/ActivityThread")
        .map_err(|e| format!("ActivityThread: {e}"))?;
    let app = env
        .call_static_method(&at, "currentApplication", "()Landroid/app/Application;", &[])
        .map_err(|e| format!("currentApplication: {e}"))?
        .l()
        .map_err(|_| "currentApplication not an object")?;
    if app.is_null() {
        return Err("currentApplication returned null".into());
    }
    Ok(app)
}

/// Load a class from the app/plugin DEX using the application [`Context`]'s [`ClassLoader`].
///
/// [`JNIEnv::find_class`] on a thread attached only via [`JavaVM::attach_current_thread`] uses the
/// system class loader, which cannot see Flutter plugin classes (crash: `ClassNotFoundException` with
/// `DexPathList[[directory "."], ...]`).
fn find_app_class<'local>(
    env: &mut JNIEnv<'local>,
    app: &JObject<'local>,
    dot_name: &str,
) -> Result<JClass<'local>, String> {
    let loader = env
        .call_method(
            app,
            "getClassLoader",
            "()Ljava/lang/ClassLoader;",
            &[],
        )
        .map_err(|e| format!("Context.getClassLoader: {e}"))?
        .l()
        .map_err(|_| "getClassLoader not object")?;
    if loader.is_null() {
        return Err("getClassLoader returned null".into());
    }
    let jname = env
        .new_string(dot_name)
        .map_err(|e| format!("class name jstring: {e}"))?;
    let cls_obj = env
        .call_method(
            &loader,
            "loadClass",
            "(Ljava/lang/String;)Ljava/lang/Class;",
            &[JValue::Object(&jname)],
        )
        .map_err(|e| format!("ClassLoader.loadClass({dot_name}): {e}"))?
        .l()
        .map_err(|_| "loadClass not object")?;
    Ok(JClass::from(cls_obj))
}

fn open_input_extractor(input_path: &str) -> Result<(MediaExtractor, Option<File>), String> {
    if input_path.starts_with("content://") {
        return with_jni_env(|_env| {
            MediaExtractor::from_url(input_path)
                .map(|ex| (ex, None))
                .map_err(|e| format!("MediaExtractor::from_url: {e:?}"))
        });
    }
    match File::open(input_path) {
        Ok(f) => {
            let len = f
                .metadata()
                .map_err(|e| format!("input metadata: {e}"))?
                .len();
            let fd = f.as_raw_fd();
            let ex = MediaExtractor::from_fd(fd, 0, len)
                .map_err(|e| format!("MediaExtractor::from_fd: {e:?}"))?;
            Ok((ex, Some(f)))
        }
        Err(e_open) => {
            let ex = MediaExtractor::from_url(input_path).map_err(|e| {
                format!("MediaExtractor: open file ({e_open}); from_url: {e:?}")
            })?;
            Ok((ex, None))
        }
    }
}

/// Coded frame size vs display size: many phones store landscape dimensions with `rotation-degrees`
/// 90/270 for portrait capture. Use display size so scale targets match what decoders present.
fn display_size_for_rotation(width: u32, height: u32, rotation_degrees: i32) -> (u32, u32) {
    let r = rotation_degrees.rem_euclid(360);
    if r == 90 || r == 270 {
        (height, width)
    } else {
        (width, height)
    }
}

fn probe_video_size_for_transcode(input_path: &str) -> Result<(u32, u32), String> {
    let (extractor, _keep) = open_input_extractor(input_path)?;
    for i in 0..extractor.track_count() {
        let Some(fmt) = extractor.track_format(i) else {
            continue;
        };
        if !fmt.is_video() {
            continue;
        }
        let w = fmt.get_i32("width").unwrap_or(0).max(0) as u32;
        let h = fmt.get_i32("height").unwrap_or(0).max(0) as u32;
        let rot = fmt.get_i32("rotation-degrees").unwrap_or(0);
        let (w, h) = display_size_for_rotation(w, h, rot);
        if w > 0 && h > 0 {
            return Ok((w, h));
        }
    }
    Err("transcode: no video track or missing width/height".into())
}

/// Long-edge cap (even dimensions); same geometry as desktop FFmpeg transcode/thumbnail scaling.
fn scale_to_max_long_edge(src_w: u32, src_h: u32, max_long_edge: u32) -> (i32, i32) {
    if src_w == 0 || src_h == 0 {
        return (src_w as i32, src_h as i32);
    }
    let long_edge = src_w.max(src_h);
    if long_edge <= max_long_edge {
        return (src_w as i32, src_h as i32);
    }
    let scale = max_long_edge as f64 / long_edge as f64;
    let mut ow = ((src_w as f64) * scale).floor() as i32;
    let mut oh = ((src_h as f64) * scale).floor() as i32;
    ow = (ow / 2) * 2;
    oh = (oh / 2) * 2;
    (ow.max(2), oh.max(2))
}

fn transcode_video_media3(
    input_path: &str,
    output_path: &str,
    video_bitrate_kbps: u32,
    audio_bitrate_kbps: u32,
    out_w: i32,
    out_h: i32,
    sink: StreamSink<TranscodeProgress>,
) -> Result<(), String> {
    let (tx, rx) = std::sync::mpsc::channel::<TranscodeProgress>();
    let ptr_tx = tx.clone();
    let forwarder = thread::spawn(move || {
        while let Ok(p) = rx.recv() {
            let _ = sink.add(p);
        }
    });

    let _ = tx.send(TranscodeProgress {
        phase: "starting".into(),
        fraction: 0.0,
        message: Some(format!(
            "Android: re-encoding to {}x{} @ {} kb/s video, {} kb/s audio (Media3)",
            out_w,
            out_h,
            video_bitrate_kbps,
            audio_bitrate_kbps
        )),
    });

    let progress_ptr = Box::into_raw(Box::new(ptr_tx)) as i64;

    let jni_result = with_jni_env(|env| {
        let app = application_context(env)?;
        let cls = find_app_class(env, &app, "dev.flutter.packages.media_flutter.MediaTranscoder")
            .map_err(|e| format!("MediaTranscoder class (is the Flutter plugin applied?): {e}"))?;
        let j_in = env
            .new_string(input_path)
            .map_err(|e| format!("jstring in: {e}"))?;
        let j_out = env
            .new_string(output_path)
            .map_err(|e| format!("jstring out: {e}"))?;
        let ret = env
            .call_static_method(
                cls,
                "runTranscode",
                "(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;IIIIJ)Ljava/lang/String;",
                &[
                    JValue::Object(&app),
                    JValue::Object(&j_in),
                    JValue::Object(&j_out),
                    JValue::Int(video_bitrate_kbps as i32),
                    JValue::Int(out_w),
                    JValue::Int(out_h),
                    JValue::Int(audio_bitrate_kbps as i32),
                    JValue::Long(progress_ptr),
                ],
            )
            .map_err(|e| format!("MediaTranscoder.runTranscode: {e}"))?;

        let err_obj = ret
            .l()
            .map_err(|_| "runTranscode did not return an object")?;
        if err_obj.is_null() {
            return Ok(());
        }
        let jstr = JString::from(err_obj);
        let chars = env
            .get_string(&jstr)
            .map_err(|e| format!("error message jstring: {e}"))?;
        Err(chars.to_string_lossy().into_owned())
    });

    unsafe {
        drop(Box::from_raw(
            progress_ptr as *mut std::sync::mpsc::Sender<TranscodeProgress>,
        ));
    }
    drop(tx);
    let _ = forwarder.join();

    jni_result?;
    Ok(())
}

fn muxer_duration_us(extractor: &MediaExtractor) -> i64 {
    for i in 0..extractor.track_count() {
        let Some(fmt) = extractor.track_format(i) else {
            continue;
        };
        if !fmt.is_video() && !fmt.is_audio() {
            continue;
        }
        if let Some(us) = fmt.get_i64("durationUs") {
            if us > 0 {
                return us;
            }
        }
    }
    1
}

/// Re-encodes with **AndroidX Media3 Transformer** (H.264 + AAC, scaled to `max_width` long edge)
/// when the Flutter plugin’s Kotlin classes are on the classpath; otherwise **remux** (stream copy).
pub fn transcode_video(
    input_path: &str,
    output_path: &str,
    video_bitrate_kbps: u32,
    max_width: u32,
    audio_bitrate_kbps: u32,
    sink: StreamSink<TranscodeProgress>,
) -> Result<(), String> {
    let (sw, sh) = probe_video_size_for_transcode(input_path)?;
    let (out_w, out_h) = scale_to_max_long_edge(sw, sh, max_width.max(2));

    let use_media3 = with_jni_env(|env| {
        let app = match application_context(env) {
            Ok(a) => a,
            Err(_) => return Ok(false),
        };
        Ok(find_app_class(env, &app, "dev.flutter.packages.media_flutter.MediaTranscoder").is_ok())
    })
    .unwrap_or(false);

    if use_media3 {
        transcode_video_media3(
            input_path,
            output_path,
            video_bitrate_kbps,
            audio_bitrate_kbps,
            out_w,
            out_h,
            sink,
        )
    } else {
        transcode_video_remux_dispatch(input_path, output_path, sink)
    }
}

fn transcode_video_remux_dispatch(
    input_path: &str,
    output_path: &str,
    sink: StreamSink<TranscodeProgress>,
) -> Result<(), String> {
    let in_path = input_path.to_string();
    let out_path = output_path.to_string();

    if !in_path.starts_with("content://") {
        if let Ok(f) = File::open(&in_path) {
            if let Ok(len) = f.metadata().map(|m| m.len()) {
                let fd = f.as_raw_fd();
                if let Ok(extractor) = MediaExtractor::from_fd(fd, 0, len) {
                    return transcode_video_remux(extractor, Some(f), &out_path, sink);
                }
            }
        }
    }

    with_jni_env(|_env| {
        let extractor = MediaExtractor::from_url(&in_path)
            .map_err(|e| format!("MediaExtractor::from_url: {e:?}"))?;
        transcode_video_remux(extractor, None::<File>, &out_path, sink)
    })
}

fn transcode_video_remux(
    mut extractor: MediaExtractor,
    _input_keep: Option<File>,
    output_path: &str,
    sink: StreamSink<TranscodeProgress>,
) -> Result<(), String> {
    let _ = sink.add(TranscodeProgress {
        phase: "starting".into(),
        fraction: 0.0,
        message: Some(
            "Android remux fallback: stream copy (install/use the media plugin for H.264 resize)."
                .into(),
        ),
    });

    let duration_us = muxer_duration_us(&extractor);
    let track_count = extractor.track_count();
    if track_count == 0 {
        return Err("transcode: no tracks in input".into());
    }

    let mut ext_to_mux = vec![-1isize; track_count];

    let out_file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(output_path)
        .map_err(|e| format!("open output: {e}"))?;
    let fd = out_file.as_raw_fd();

    let mut muxer = MediaMuxer::new(fd, OutputFormat::Mpeg4)
        .ok_or_else(|| "MediaMuxer::new returned null".to_string())?;

    let mut sample_buf_cap = 4 * 1024 * 1024;
    for i in 0..track_count {
        let Some(fmt) = extractor.track_format(i) else {
            continue;
        };
        if !fmt.is_video() && !fmt.is_audio() {
            continue;
        }
        if let Some(m) = fmt.get_i32("max-input-size") {
            sample_buf_cap = sample_buf_cap.max((m as usize).clamp(65536, 32 * 1024 * 1024));
        }
        let mux_idx = muxer
            .add_track(fmt)
            .map_err(|e| format!("muxer add_track: {e:?}"))?;
        ext_to_mux[i] = mux_idx;
        extractor.select_track(i);
    }

    if muxer.track_count() == 0 {
        return Err("transcode: no video/audio tracks to mux".into());
    }

    muxer
        .start()
        .map_err(|e| format!("muxer start: {e:?}"))?;

    let mut buf = vec![0u8; sample_buf_cap];
    let mut last_emit = Instant::now();
    let mut last_frac = -1.0_f64;
    let mut samples: u32 = 0;

    while extractor.has_next() {
        let Some((track, n, time_us, flags)) = extractor.read_sample_bytes(&mut buf) else {
            break;
        };
        if track < 0 {
            break;
        }
        let ti = track as usize;
        if ti >= ext_to_mux.len() || ext_to_mux[ti] < 0 {
            continue;
        }
        let mux_track = ext_to_mux[ti] as usize;
        if n > 0 {
            let info = BufferInfo::muxer_sample(n as i32, time_us, flags);
            muxer
                .write_sample_data(mux_track, &buf[..n], &info)
                .map_err(|e| format!("write_sample_data: {e:?}"))?;
        }

        samples = samples.wrapping_add(1);
        if samples.is_multiple_of(256) {
            std::thread::yield_now();
        }

        let frac = (time_us as f64 / duration_us as f64).clamp(0.0, 0.999);
        let elapsed_ok = last_emit.elapsed().as_millis() >= 200;
        let jump = (frac - last_frac).abs() >= 0.03;
        if elapsed_ok || jump {
            last_emit = Instant::now();
            last_frac = frac;
            let _ = sink.add(TranscodeProgress {
                phase: "muxing".into(),
                fraction: frac,
                message: None,
            });
        }
    }

    muxer.stop().map_err(|e| format!("muxer stop: {e:?}"))?;
    drop(out_file);

    let _ = sink.add(TranscodeProgress {
        phase: "done".into(),
        fraction: 1.0,
        message: None,
    });
    Ok(())
}

/// Progress hook from [MediaJni.transcodeProgress] on the Android main thread.
#[no_mangle]
pub unsafe extern "system" fn Java_dev_flutter_packages_media_1flutter_MediaJni_transcodeProgress(
    mut _env: JNIEnv,
    _class: JClass,
    ptr: jni::sys::jlong,
    fraction: jni::sys::jdouble,
) {
    if ptr == 0 {
        return;
    }
    let tx = &*(ptr as *const std::sync::mpsc::Sender<TranscodeProgress>);
    let frac = (fraction as f64).clamp(0.0, 1.0);
    let phase = if frac >= 0.999 {
        "done".into()
    } else {
        "encoding".into()
    };
    let _ = tx.send(TranscodeProgress {
        phase,
        fraction: frac,
        message: None,
    });
}
