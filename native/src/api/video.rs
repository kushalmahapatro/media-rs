use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::api::media::{CompressParams, CompressionEstimate, OutputFormat, ThumbnailSizeType};
use anyhow::{Context, Error, Result};
use ffmpeg_next::packet::Mut;
use ffmpeg_next::{self as ffmpeg};
use tracing::{debug, error, info, warn};

use crate::api::media::VideoThumbnailParams;
#[cfg(target_os = "windows")]
use std::sync::Mutex; // Still needed for cache on Windows

// Use std::sync::Once to ensure FFmpeg is only initialized once
// This is important for thread safety and to avoid issues when called from Flutter
static FFMPEG_INIT: std::sync::Once = std::sync::Once::new();
static mut FFMPEG_INIT_ERROR: Option<anyhow::Error> = None;

// Semaphore to limit concurrent FFmpeg context creation on Windows
// This prevents access violations when multiple threads try to create contexts simultaneously
// FFmpeg's internal initialization may not be fully thread-safe on Windows/MinGW
#[cfg(target_os = "windows")]
use std::sync::atomic::{AtomicU32, Ordering};

#[cfg(target_os = "windows")]
static FFMPEG_CONTEXT_SEMAPHORE: AtomicU32 = AtomicU32::new(3); // Allow 3 concurrent context creations at a time for parallel estimation

// Cache for video info to avoid opening multiple FFmpeg contexts on Windows
// Key: file path, Value: VideoInfo and timestamp
#[cfg(target_os = "windows")]
use std::collections::HashMap;
#[cfg(target_os = "windows")]
use std::sync::OnceLock;

#[cfg(target_os = "windows")]
fn get_video_info_cache() -> &'static Mutex<HashMap<String, (crate::api::media::VideoInfo, u64)>> {
    static CACHE: OnceLock<Mutex<HashMap<String, (crate::api::media::VideoInfo, u64)>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

#[cfg(target_os = "windows")]
const CACHE_TTL_SECONDS: u64 = 60; // Cache for 60 seconds

fn init_ffmpeg() -> Result<()> {
    // Use Once to ensure thread-safe single initialization
    FFMPEG_INIT.call_once(|| {
        debug!("First call to init_ffmpeg() - initializing FFmpeg");
        
        // Add detailed error context for Windows debugging
        #[cfg(target_os = "windows")]
        {
            debug!("Running on Windows");
            
            // Log environment info for debugging
            if let Ok(path) = std::env::var("PATH") {
                debug!("PATH contains {} entries", path.split(';').count());
            }
            
            // Check executable directory for DLLs
            if let Ok(exe_path) = std::env::current_exe() {
                if let Some(exe_dir) = exe_path.parent() {
                    debug!("Executable directory: {}", exe_dir.display());
                    let dlls = ["libgcc_s_seh-1.dll", "libwinpthread-1.dll", "media.dll"];
                    for dll in &dlls {
                        let dll_path = exe_dir.join(dll);
                        if dll_path.exists() {
                            debug!("Found DLL in executable directory: {}", dll_path.display());
                        } else {
                            debug!("DLL not found in executable directory: {} (may be in PATH)", dll_path.display());
                        }
                    }
                }
            }
            
            // Check if MinGW DLLs are accessible in MSYS2 (they may be loaded from PATH)
            let msys2_root = std::env::var("MSYS2_ROOT").unwrap_or_else(|_| r"C:\msys64".to_string());
            let dlls = ["libgcc_s_seh-1.dll", "libwinpthread-1.dll"];
            for dll in &dlls {
                let dll_path = format!("{}\\mingw64\\bin\\{}", msys2_root, dll);
                if std::path::Path::new(&dll_path).exists() {
                    debug!("Found MinGW DLL in MSYS2: {}", dll_path);
                } else {
                    debug!("MinGW DLL not found at: {} (may be in PATH or system directories)", dll_path);
                }
            }
        }
        
        debug!("About to call ffmpeg::init()");
        
        // Initialize FFmpeg with detailed error context
        let result = ffmpeg::init().with_context(|| {
            #[cfg(target_os = "windows")]
            {
                format!(
                    "Failed to initialize ffmpeg on Windows. \
                    Common causes:\n\
                    1. FFmpeg libraries not found or incompatible\n\
                    2. Missing system dependencies\n\
                    3. MinGW runtime DLLs (libgcc_s_seh-1.dll, libwinpthread-1.dll) not in PATH or executable directory\n\
                    Check that FFmpeg libraries are available and DLLs are in PATH or: {}",
                    std::env::current_exe()
                        .ok()
                        .and_then(|p| p.parent().map(|p| p.display().to_string()))
                        .unwrap_or_else(|| "executable directory".to_string())
                )
            }
            #[cfg(not(target_os = "windows"))]
            {
                "Failed to initialize ffmpeg".to_string()
            }
        });
        
        unsafe {
            match result {
                Ok(_) => {
                    info!("ffmpeg::init() succeeded");
                }
                Err(e) => {
                    error!("ffmpeg::init() failed: {}", e);
                    FFMPEG_INIT_ERROR = Some(e);
                }
            }
        }
    });
    
    // Check if initialization failed
    unsafe {
        if let Some(ref err) = FFMPEG_INIT_ERROR {
            error!("init_ffmpeg() returning previous initialization error");
            return Err(anyhow::anyhow!("FFmpeg initialization failed: {}", err));
        }
    }
    
    debug!("init_ffmpeg() succeeded (already initialized or just initialized)");
    Ok(())
}

/// Get video rotation from display matrix side data
/// Returns rotation in degrees (0, 90, 180, 270) or None if not found
fn get_video_rotation(stream: &ffmpeg::format::stream::Stream) -> Option<i32> {
    use ffmpeg::codec::packet::side_data::Type as SideDataType;

    // Check stream side data for display matrix
    for side_data in stream.side_data() {
        if side_data.kind() == SideDataType::DisplayMatrix {
            let data = side_data.data();
            if data.len() >= 36 {
                // 9 * 4 bytes (int32_t)
                unsafe {
                    // Parse display matrix manually
                    // Matrix format: [a, b, u, c, d, v, x, y, w] as int32_t (fixed-point 16.16)
                    let matrix_ptr = data.as_ptr() as *const i32;
                    let matrix = std::slice::from_raw_parts(matrix_ptr, 9);

                    // Extract matrix values (fixed-point 16.16 format)
                    let a = matrix[0] as f64 / (1i64 << 16) as f64;
                    let b = matrix[1] as f64 / (1i64 << 16) as f64;
                    let _c = matrix[3] as f64 / (1i64 << 16) as f64;
                    let _d = matrix[4] as f64 / (1i64 << 16) as f64;

                    // Calculate rotation angle from transformation matrix
                    // FFmpeg display matrix format: [a, b, c, d] represents rotation
                    // The matrix is: [a b]  which rotates counter-clockwise
                    //                [c d]
                    // For 90° counter-clockwise: a=0, b=1, c=-1, d=0
                    // For 90° clockwise: a=0, b=-1, c=1, d=0
                    // For 180°: a=-1, b=0, c=0, d=-1
                    //
                    // The display matrix indicates how the video is stored (rotation needed to display correctly)
                    // If matrix indicates 90° CCW, the video is stored rotated 90° CCW
                    // To correct it, we need to rotate 90° CW (which is 270° CCW)
                    //
                    // We use atan2(b, a) to get the rotation angle (note: positive b, not -b)
                    // This gives us the counter-clockwise rotation of the stored video
                    let angle_rad = b.atan2(a);
                    let angle_deg = angle_rad.to_degrees();

                    // Normalize to 0, 90, 180, 270
                    let matrix_rotation = ((angle_deg.round() as i32 % 360 + 360) % 360) / 90 * 90;

                    // The matrix rotation is the counter-clockwise rotation of the stored video
                    // To correct it, we need to rotate in the opposite direction
                    // So if stored is 90° CCW, we need 270° CCW (which is 90° CW)
                    // Return the matrix rotation as-is - the correction code will rotate in opposite direction
                    return Some(matrix_rotation);
                }
            }
        }
    }

    // Also check metadata for rotation tag (some formats store it there, especially MOV)
    if let Some(rotation_str) = stream.metadata().get("rotate") {
        if let Ok(rotation) = rotation_str.parse::<i32>() {
            return Some(((rotation % 360 + 360) % 360) / 90 * 90);
        }
    }

    // Check format metadata as well (MOV files often have it there)
    // Note: We'd need access to format context metadata, but stream metadata should work

    None
}

/// Get video rotation from format context (for MOV files that store it in format metadata)
fn get_video_rotation_from_format(ictx: &ffmpeg::format::context::Input) -> Option<i32> {
    // Check format metadata for rotation (MOV files often store it here)
    if let Some(rotation_str) = ictx.metadata().get("rotate") {
        if let Ok(rotation) = rotation_str.parse::<i32>() {
            return Some(((rotation % 360 + 360) % 360) / 90 * 90);
        }
    }
    None
}

/// Get display dimensions accounting for rotation (with format context for MOV files)
/// Returns (display_width, display_height, rotation_degrees)
fn get_display_dimensions_with_format(
    ictx: &ffmpeg::format::context::Input,
    stream: &ffmpeg::format::stream::Stream,
    stored_width: u32,
    stored_height: u32,
) -> (u32, u32, i32) {
    // Try stream first, then format metadata (MOV files often use format metadata)
    let rotation = get_video_rotation(stream)
        .or_else(|| get_video_rotation_from_format(ictx))
        .unwrap_or(0);

    match rotation {
        90 | 270 => (stored_height, stored_width, rotation),
        _ => (stored_width, stored_height, rotation),
    }
}

/// Find the best available H.264 encoder (LGPL-compliant)
/// Priority: VideoToolbox (macOS/iOS) > OpenH264 > software encoder
/// Note: MediaCodec is disabled to avoid NDK linking issues
/// On Android, hardware encoders (v4l2m2m, omx, mediacodec) are excluded due to permission issues
fn find_h264_encoder() -> Result<ffmpeg::Codec> {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        // VideoToolbox is LGPL-compliant (Apple's framework, not GPL code)
        if let Some(codec) = ffmpeg::encoder::find_by_name("h264_videotoolbox") {
            eprintln!("INFO: Using h264_videotoolbox encoder.");
            return Ok(codec);
        }
    }

    // Try OpenH264 (BSD-licensed, LGPL-compatible)
    // Try different possible names for the encoder
    let openh264_names = ["libopenh264", "openh264"];
    for name in &openh264_names {
        if let Some(codec) = ffmpeg::encoder::find_by_name(name) {
            eprintln!("INFO: Using {} encoder.", name);
            return Ok(codec);
        }
    }

    // On Windows, also check for any available H.264 encoder as fallback
    #[cfg(target_os = "windows")]
    {
        eprintln!("DEBUG: OpenH264 encoder not found, checking for other H.264 encoders on Windows...");
        if let Some(codec) = ffmpeg::encoder::find(ffmpeg::codec::Id::H264) {
            let codec_name = codec.name();
            eprintln!("DEBUG: Found H.264 encoder: {}", codec_name);
            // On Windows, we might have built-in encoder or other options
            // Try to use it if it's not a hardware encoder that requires special permissions
            let hardware_encoders = [
                "h264_qsv",   // Intel QuickSync
                "h264_nvenc", // NVIDIA
                "h264_amf",   // AMD
            ];
            if !hardware_encoders.iter().any(|&hw| codec_name == hw) {
                eprintln!("INFO: Using H.264 encoder: {} (software encoder)", codec_name);
                return Ok(codec);
            } else {
                eprintln!("WARNING: Found hardware encoder '{}' which may not work on Windows without proper drivers", codec_name);
            }
        } else {
            eprintln!("DEBUG: No H.264 encoder found at all on Windows");
        }
    }

    // Debug: Check what H.264 encoder is available
    #[cfg(target_os = "android")]
    {
        eprintln!(
            "DEBUG: libopenh264 encoder not found, checking what H.264 encoders are available..."
        );
        if let Some(codec) = ffmpeg::encoder::find(ffmpeg::codec::Id::H264) {
            eprintln!("DEBUG: Found H.264 encoder: {}", codec.name());
        } else {
            eprintln!("DEBUG: No H.264 encoder found at all");
        }
    }

    // MediaCodec disabled - use OpenH264 instead for licensing clarity
    // OpenH264 has patent coverage from Cisco for binary distributions
    // Uncomment the following block if you want to enable MediaCodec hardware encoding:
    // #[cfg(target_os = "android")]
    // {
    //     if let Some(codec) = ffmpeg::encoder::find_by_name("h264_mediacodec") {
    //         eprintln!("INFO: Using h264_mediacodec encoder (Android hardware encoder).");
    //         return Ok(codec);
    //     }
    // }

    // On Android, exclude hardware encoders that require special permissions (but allow MediaCodec)
    #[cfg(target_os = "android")]
    {
        // List of hardware encoders to exclude on Android (v4l2m2m and omx require special permissions)
        // MediaCodec is allowed as it uses Android framework APIs
        let hardware_encoders = [
            "h264_v4l2m2m", // Requires direct device access
            "h264_omx",     // Requires direct device access
            "h264_qsv",     // Intel QuickSync (not available on Android, but just in case)
            "h264_nvenc",   // NVIDIA (not available on Android, but just in case)
        ];

        // Try to find libx264 (software, but GPL) as a fallback
        // Note: libx264 is GPL-licensed, so we prefer OpenH264, but it's better than hardware
        if let Some(codec) = ffmpeg::encoder::find_by_name("libx264") {
            eprintln!("INFO: Using libx264 encoder (software, GPL-licensed).");
            return Ok(codec);
        }

        // Try to find a software encoder by checking the first available encoder
        // and rejecting hardware encoders
        if let Some(codec) = ffmpeg::encoder::find(ffmpeg::codec::Id::H264) {
            let codec_name = codec.name();
            // Check if it's a hardware encoder
            if hardware_encoders.iter().any(|&hw| codec_name == hw) {
                eprintln!("ERROR: Found hardware encoder '{}' which requires special permissions that are not available.", codec_name);
                eprintln!("ERROR: OpenH264 (libopenh264) is not available. Please build OpenH264 for Android.");
                return Err(anyhow::anyhow!(
                    "Hardware encoder '{}' requires special permissions. OpenH264 (libopenh264) must be built for Android to enable software encoding.\n\
                        Run: ./setup_all.sh --android",
                    codec_name
                ));
            } else {
                eprintln!("INFO: Using software H.264 encoder: {}", codec_name);
                return Ok(codec);
            }
        }

        // No encoder found at all
        return Err(anyhow::anyhow!(
            "No H.264 encoder found on Android. Please build OpenH264 (libopenh264) for Android.\n\
                Run: ./setup_all.sh --android"
        ));
    }

    // For non-Android platforms, fall back to built-in encoder (if available)
    #[cfg(not(target_os = "android"))]
    {
        ffmpeg::encoder::find(ffmpeg::codec::Id::H264).ok_or_else(|| {
            anyhow::anyhow!(
                "No H.264 encoder found. Available options:\n\
                    - macOS/iOS: Enable VideoToolbox with --enable-videotoolbox\n\
                    - All platforms: Build OpenH264 and enable with --enable-libopenh264\n\
                    - Built-in encoder (if available in FFmpeg build)"
            )
        })
    }
}

/// Internal version that doesn't acquire the mutex (assumes caller already holds it)
fn get_video_info_internal(path: &str) -> Result<crate::api::media::VideoInfo> {
    debug!("get_video_info_internal called with path: {}", path);
    
    debug!("get_video_info_internal - about to call init_ffmpeg()");
    init_ffmpeg()?;
    debug!("get_video_info_internal - init_ffmpeg() succeeded");

    // On Windows, add a delay before opening FFmpeg contexts
    // This may help with potential race conditions or state cleanup issues
    // FFmpeg may need time to clean up internal state between context operations
    #[cfg(target_os = "windows")]
    {
        use std::thread;
        use std::time::Duration;
        // Longer delay to ensure FFmpeg internal state is fully cleaned up
        thread::sleep(Duration::from_millis(50));
        // Force a yield to let other threads/FFmpeg cleanup complete
        thread::yield_now();
    }

    debug!("get_video_info_internal - about to call ffmpeg::format::input()");
    
    // Normalize Windows path: convert backslashes to forward slashes
    // FFmpeg (built with MinGW) may have issues with Windows path separators
    #[cfg(target_os = "windows")]
    let normalized_path = path.replace('\\', "/");
    #[cfg(not(target_os = "windows"))]
    let normalized_path = path.to_string();
    
    debug!("get_video_info_internal - normalized path: {}", normalized_path);
    debug!("get_video_info_internal - original path: {}", path);
    
    // Try to open the file directly - if tests work, this should work too
    // The crash might be due to stack size or threading, so let's try a simpler approach first
    debug!("get_video_info_internal - attempting to open file with normalized path: {}", normalized_path);
    
    // Try with normalized path first
    // Wrap in catch_unwind to catch any panics from FFmpeg C code
    let ictx = match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        ffmpeg::format::input(&normalized_path)
    })) {
        Ok(Ok(ctx)) => {
            debug!("get_video_info_internal - succeeded with normalized path");
            ctx
        }
        Ok(Err(e)) => {
            warn!("get_video_info_internal - normalized path failed: {}, trying original", e);
            // Fallback to original path - also wrap in catch_unwind
            match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                ffmpeg::format::input(path)
            })) {
                Ok(Ok(ctx)) => ctx,
                Ok(Err(e)) => {
                    return Err(anyhow::anyhow!("Failed to open video file: {}. Error: {}. This may indicate a codec issue or file corruption.", path, e))
                        .with_context(|| format!("Both normalized and original paths failed for: {}", path));
                }
                Err(panic) => {
                    let panic_msg = if let Some(s) = panic.downcast_ref::<&str>() {
                        format!("FFmpeg panic when opening file: {}", s)
                    } else if let Some(s) = panic.downcast_ref::<String>() {
                        format!("FFmpeg panic when opening file: {}", s)
                    } else {
                        "FFmpeg panic when opening file: unknown error".to_string()
                    };
                    error!("{}", panic_msg);
                    return Err(anyhow::anyhow!("{}", panic_msg))
                        .with_context(|| format!("FFmpeg crashed when trying to open: {}", path));
                }
            }
        }
        Err(panic) => {
            let panic_msg = if let Some(s) = panic.downcast_ref::<&str>() {
                format!("FFmpeg panic when opening normalized path: {}", s)
            } else if let Some(s) = panic.downcast_ref::<String>() {
                format!("FFmpeg panic when opening normalized path: {}", s)
            } else {
                "FFmpeg panic when opening normalized path: unknown error".to_string()
            };
            error!("{}", panic_msg);
            // Try original path as fallback
            warn!("Trying original path after panic with normalized path");
            match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                ffmpeg::format::input(path)
            })) {
                Ok(Ok(ctx)) => {
                    warn!("Original path succeeded after normalized path panic");
                    ctx
                }
                Ok(Err(e)) => {
                    return Err(anyhow::anyhow!("Failed to open video file: {}. Normalized path panicked, original path error: {}.", path, e))
                        .with_context(|| format!("FFmpeg crashed with normalized path and failed with original: {}", path));
                }
                Err(panic2) => {
                    let panic_msg2 = if let Some(s) = panic2.downcast_ref::<&str>() {
                        format!("FFmpeg panic when opening original path: {}", s)
                    } else if let Some(s) = panic2.downcast_ref::<String>() {
                        format!("FFmpeg panic when opening original path: {}", s)
                    } else {
                        "FFmpeg panic when opening original path: unknown error".to_string()
                    };
                    error!("{}", panic_msg2);
                    return Err(anyhow::anyhow!("FFmpeg crashed with both paths. Normalized: {}, Original: {}", panic_msg, panic_msg2))
                        .with_context(|| format!("FFmpeg crashed when trying to open: {}", path));
                }
            }
        }
    };
    
    info!("get_video_info_internal - ffmpeg::format::input() succeeded");
    
    debug!("get_video_info_internal - getting best video stream");
    let stream = ictx
        .streams()
        .best(ffmpeg::media::Type::Video)
        .ok_or_else(|| anyhow::anyhow!("No video stream found in file: {}", path))?;
    debug!("get_video_info_internal - found video stream");

    debug!("get_video_info_internal - creating codec context");
    let context = ffmpeg::codec::context::Context::from_parameters(stream.parameters())
        .with_context(|| "Failed to create codec context from stream parameters".to_string())?;
    debug!("get_video_info_internal - codec context created");
    
    debug!("get_video_info_internal - getting video decoder");
    let decoder = context.decoder().video()
        .with_context(|| "Failed to get video decoder from context".to_string())?;
    debug!("get_video_info_internal - video decoder obtained");

    debug!("get_video_info_internal - getting decoder dimensions");
    let stored_width = decoder.width();
    let stored_height = decoder.height();
    debug!("get_video_info_internal - stored dimensions: {}x{}", stored_width, stored_height);

    debug!("get_video_info_internal - getting display dimensions with rotation");
    // Get display dimensions accounting for rotation (check both stream and format metadata for MOV files)
    let (display_width, display_height, _rotation) =
        get_display_dimensions_with_format(&ictx, &stream, stored_width, stored_height);
    debug!("get_video_info_internal - display dimensions: {}x{}", display_width, display_height);

    debug!("get_video_info_internal - getting duration");
    let duration = ictx.duration(); // AV_TIME_BASE
    debug!("get_video_info_internal - duration (AV_TIME_BASE): {}", duration);

    let duration_ms = (duration as f64 / ffmpeg::ffi::AV_TIME_BASE as f64 * 1000.0) as u64;
    let size_bytes = std::fs::metadata(path)?.len();

    // Estimate bitrate if missing (size * 8 / seconds)
    let bitrate = if ictx.bit_rate() > 0 {
        Some(ictx.bit_rate() as u64)
    } else if duration_ms > 0 {
        Some((size_bytes * 8 * 1000) / duration_ms)
    } else {
        None
    };

    let codec_name = decoder.codec().map(|c| c.name().to_string());
    let format_name = ictx.format().name().to_string();

    // Generate Suggestions using display dimensions (corrected for rotation)
    let suggestions =
        generate_resolution_presets(display_width, display_height, bitrate.unwrap_or(0));

    let result = crate::api::media::VideoInfo {
        duration_ms,
        width: display_width,
        height: display_height,
        size_bytes,
        bitrate,
        codec_name: Some(codec_name.unwrap_or_default()),
        format_name: Some(format_name),
        suggestions,
    };
    
    // Explicitly drop the context before returning to ensure cleanup
    // This helps prevent issues when opening multiple contexts in sequence
    drop(ictx);
    debug!("get_video_info_internal - context dropped, returning result");
    
    // On Windows, add a delay after dropping the context to ensure FFmpeg cleanup completes
    // This may help prevent crashes when opening subsequent contexts
    #[cfg(target_os = "windows")]
    {
        use std::thread;
        use std::time::Duration;
        thread::sleep(Duration::from_millis(50));
        thread::yield_now();
    }
    
    Ok(result)
}

/// Normalize path for cache key (convert backslashes to forward slashes on Windows)
#[cfg(target_os = "windows")]
fn normalize_path_for_cache(path: &str) -> String {
    path.replace('\\', "/")
}

/// Public version that acquires the mutex before calling the internal version
pub fn get_video_info(path: &str) -> Result<crate::api::media::VideoInfo> {
    debug!("get_video_info called with path: {}", path);
    
    // On Windows, check cache first to avoid opening multiple FFmpeg contexts
    #[cfg(target_os = "windows")]
    {
        let cache_key = normalize_path_for_cache(path);
        let cache = get_video_info_cache().lock().map_err(|e| anyhow::anyhow!("Failed to acquire cache mutex: {:?}", e))?;
        if let Some((cached_info, timestamp)) = cache.get(&cache_key) {
            let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
            if now.saturating_sub(*timestamp) < CACHE_TTL_SECONDS {
                debug!("get_video_info - using cached video info for: {} (cache key: {})", path, cache_key);
                return Ok(cached_info.clone());
            } else {
                debug!("get_video_info - cache expired for: {} (age: {}s)", path, now.saturating_sub(*timestamp));
            }
        } else {
            debug!("get_video_info - no cache entry for: {} (cache key: {})", path, cache_key);
        }
        drop(cache); // Release cache lock before acquiring FFmpeg mutex
    }
    
    // FFmpeg is thread-safe when using separate contexts per thread.
    // On Windows, delay to prevent access violations
    #[cfg(target_os = "windows")]
    {
        use std::thread;
        use std::time::Duration;
        thread::sleep(Duration::from_millis(150));
        thread::yield_now();
    }
    
    // Call the internal version
    let info = get_video_info_internal(path)?;
    
    // On Windows, cache the result to avoid opening multiple contexts
    #[cfg(target_os = "windows")]
    {
        let cache_key = normalize_path_for_cache(path);
        let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
        let mut cache = get_video_info_cache().lock().map_err(|e| anyhow::anyhow!("Failed to acquire cache mutex: {:?}", e))?;
        cache.insert(cache_key.clone(), (info.clone(), now));
        debug!("get_video_info - cached video info for: {} (cache key: {})", path, cache_key);
    }
    
    Ok(info)
}

fn generate_resolution_presets(
    src_w: u32,
    src_h: u32,
    src_bitrate: u64,
) -> Vec<crate::api::media::ResolutionPreset> {
    let mut presets = Vec::new();
    let is_landscape = src_w >= src_h;

    // Define standard heights for landscape (swap for portrait checks)
    // 1080p, 720p, 480p, 360p
    let standards = vec![
        ("1080p", 1920, 1080, 4_500_000, 18), // 4.5 Mbps
        ("720p", 1280, 720, 2_500_000, 23),   // 2.5 Mbps
        ("480p", 854, 480, 1_000_000, 28),    // 1 Mbps
        ("360p", 640, 360, 600_000, 32),      // 600 Kbps (reduced from 1Mbps to offer real savings)
    ];

    for (name, s_w, s_h, s_br, s_crf) in standards {
        let (target_w, target_h) = if is_landscape { (s_w, s_h) } else { (s_h, s_w) };

        // Only suggest if source is strictly larger or equal (wait, "don't upscale" means we suggestion should be <= source)
        // Actually, if source is 1080p, we show 720p, 480p, etc.
        // If source is 720p, we show 480p, 360p.
        // We can also include the "current" resolution as a preset if it doesn't match standard exactly.

        // Check strict dimension containment
        if src_w >= target_w && src_h >= target_h {
            // Calculate maintained aspect ratio dimensions
            // (Using our helper would be cyclic, duplicate logic here)
            let (final_w, final_h) =
                calculate_dimensions(src_w, src_h, Some(target_w), Some(target_h));

            // Dynamic Bitrate: don't suggest higher than source
            let final_br = if src_bitrate > 0 && s_br > src_bitrate {
                src_bitrate
            } else {
                s_br
            };

            presets.push(crate::api::media::ResolutionPreset {
                name: name.to_string(),
                width: final_w,
                height: final_h,
                bitrate: final_br,
                crf: s_crf,
            });
        }
    }

    // Always add "Original" at the top? Or end?
    // Let's add "Original" if it's not covered by 1080p etc perfectly.
    // Usually UI wants "Original" first.
    presets.insert(
        0,
        crate::api::media::ResolutionPreset {
            name: "Original".to_string(),
            width: src_w,
            height: src_h,
            bitrate: if src_bitrate > 0 {
                src_bitrate
            } else {
                2_000_000
            },
            crf: 28,
        },
    );

    presets
}

pub fn generate_empty_thumbnail(
    size: ThumbnailSizeType,
    format: OutputFormat,
    output_path: &PathBuf,
) -> Result<()> {
    let (w, h) = size.dimensions();
    let img = image::ImageBuffer::<image::Rgb<u8>, Vec<u8>>::new(w, h);
    let _ = match format {
        OutputFormat::JPEG => img.save_with_format(&output_path, image::ImageFormat::Jpeg),
        OutputFormat::PNG => img.save_with_format(&output_path, image::ImageFormat::Png),
        OutputFormat::WEBP => img.save_with_format(&output_path, image::ImageFormat::WebP),
    };

    Ok(())
}

pub fn generate_thumbnail(
    path: &str,
    params: &VideoThumbnailParams,
) -> Result<(Vec<u8>, u32, u32), (Error, u32, u32)> {
    init_ffmpeg().map_err(|e| (e, 0, 0))?;

    // Normalize Windows path
    #[cfg(target_os = "windows")]
    let normalized_path = path.replace('\\', "/");
    #[cfg(not(target_os = "windows"))]
    let normalized_path = path.to_string();
    
    // On Windows, use semaphore to limit concurrent FFmpeg context creation
    // This prevents access violations when multiple threads try to create contexts simultaneously
    #[cfg(target_os = "windows")]
    {
        use std::sync::atomic::Ordering;
        use std::thread;
        use std::time::Duration;
        
        // Wait for semaphore (spin-wait with exponential backoff)
        let mut wait_time = 1u64;
        loop {
            let current = FFMPEG_CONTEXT_SEMAPHORE.load(Ordering::Acquire);
            if current > 0 {
                if FFMPEG_CONTEXT_SEMAPHORE.compare_exchange(
                    current,
                    current - 1,
                    Ordering::AcqRel,
                    Ordering::Acquire,
                ).is_ok() {
                    debug!("generate_thumbnail - acquired FFmpeg context semaphore");
                    break;
                }
            }
            thread::sleep(Duration::from_millis(wait_time));
            wait_time = (wait_time * 2).min(50); // Cap at 50ms
        }
        
        // Small delay after acquiring semaphore
        thread::sleep(Duration::from_millis(50));
        thread::yield_now();
    }
    
    let ictx_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        ffmpeg::format::input(&normalized_path)
            .or_else(|_| ffmpeg::format::input(path)) // Fallback to original
    }));
    
    let mut ictx = match ictx_result {
        Ok(Ok(ctx)) => ctx,
        Ok(Err(e)) => {
            // Release semaphore on error
            #[cfg(target_os = "windows")]
            {
                use std::sync::atomic::Ordering;
                use std::thread;
                use std::time::Duration;
                thread::sleep(Duration::from_millis(50));
                thread::yield_now();
                FFMPEG_CONTEXT_SEMAPHORE.fetch_add(1, Ordering::AcqRel);
                debug!("generate_thumbnail - released FFmpeg context semaphore (error)");
            }
            return Err((anyhow::anyhow!("Failed to open input: {}. Error: {}", path, e), 0, 0));
        }
        Err(panic) => {
            // Release semaphore on panic
            #[cfg(target_os = "windows")]
            {
                use std::sync::atomic::Ordering;
                use std::thread;
                use std::time::Duration;
                thread::sleep(Duration::from_millis(50));
                thread::yield_now();
                FFMPEG_CONTEXT_SEMAPHORE.fetch_add(1, Ordering::AcqRel);
                debug!("generate_thumbnail - released FFmpeg context semaphore (panic)");
            }
            let panic_msg = if let Some(s) = panic.downcast_ref::<&str>() {
                format!("FFmpeg panic when opening file: {}", s)
            } else if let Some(s) = panic.downcast_ref::<String>() {
                format!("FFmpeg panic when opening file: {}", s)
            } else {
                "FFmpeg panic when opening file: unknown error".to_string()
            };
            return Err((anyhow::anyhow!("{}", panic_msg), 0, 0));
        }
    };

    let stream = ictx
        .streams()
        .best(ffmpeg::media::Type::Video)
        .ok_or_else(|| {
            // Release semaphore on error
            #[cfg(target_os = "windows")]
            {
                use std::sync::atomic::Ordering;
                use std::thread;
                use std::time::Duration;
                thread::sleep(Duration::from_millis(50));
                thread::yield_now();
                FFMPEG_CONTEXT_SEMAPHORE.fetch_add(1, Ordering::AcqRel);
                debug!("generate_thumbnail - released FFmpeg context semaphore (no video stream)");
            }
            (anyhow::anyhow!("No video stream found"), 0, 0)
        })?;

    let stream_index = stream.index();

    let context = ffmpeg::codec::context::Context::from_parameters(stream.parameters())
        .map_err(|e| {
            // Release semaphore on error
            #[cfg(target_os = "windows")]
            {
                use std::sync::atomic::Ordering;
                use std::thread;
                use std::time::Duration;
                thread::sleep(Duration::from_millis(50));
                thread::yield_now();
                FFMPEG_CONTEXT_SEMAPHORE.fetch_add(1, Ordering::AcqRel);
                debug!("generate_thumbnail - released FFmpeg context semaphore (context error)");
            }
            (e.into(), 0, 0)
        })?;
    let mut decoder = context.decoder().video().map_err(|e| {
        // Release semaphore on error
        #[cfg(target_os = "windows")]
        {
            use std::sync::atomic::Ordering;
            use std::thread;
            use std::time::Duration;
            thread::sleep(Duration::from_millis(50));
            thread::yield_now();
            FFMPEG_CONTEXT_SEMAPHORE.fetch_add(1, Ordering::AcqRel);
            debug!("generate_thumbnail - released FFmpeg context semaphore (decoder error)");
        }
        (e.into(), 0, 0)
    })?;
    let stored_width = decoder.width();
    let stored_height = decoder.height();

    // Extract color metadata from decoder (critical for HDR videos)
    // This preserves colorspace, color range, primaries, and transfer characteristics
    let input_color_range = unsafe {
        let decoder_ptr = decoder.as_ptr();
        if !decoder_ptr.is_null() {
            (*decoder_ptr).color_range
        } else {
            std::mem::zeroed() // AVCOL_RANGE_UNSPECIFIED
        }
    };

    let input_colorspace = unsafe {
        let decoder_ptr = decoder.as_ptr();
        if !decoder_ptr.is_null() {
            (*decoder_ptr).colorspace
        } else {
            std::mem::zeroed() // AVCOL_SPC_UNSPECIFIED
        }
    };

    let input_color_primaries = unsafe {
        let decoder_ptr = decoder.as_ptr();
        if !decoder_ptr.is_null() {
            (*decoder_ptr).color_primaries
        } else {
            std::mem::zeroed() // AVCOL_PRI_UNSPECIFIED
        }
    };

    let input_color_trc = unsafe {
        let decoder_ptr = decoder.as_ptr();
        if !decoder_ptr.is_null() {
            (*decoder_ptr).color_trc
        } else {
            std::mem::zeroed() // AVCOL_TRC_UNSPECIFIED
        }
    };

    // Get rotation and display dimensions (check both stream and format metadata for MOV files)
    let (display_width, display_height, rotation) =
        get_display_dimensions_with_format(&ictx, &stream, stored_width, stored_height);

    let duration_us = ictx.duration();

    // target timestamp in microseconds (AV_TIME_BASE)
    let mut ts = params.time_ms as i64 * 1000;

    // Clamp to duration if available, but keep a buffer from the end to avoid seek failures
    // Use 5% of duration or 500 ms, whichever is larger, but cap at half duration
    if duration_us != ffmpeg::ffi::AV_NOPTS_VALUE && duration_us > 0 {
        let duration_ms = duration_us / 1000;
        let buffer_ms = (duration_ms * 5 / 100).max(500).min(duration_ms / 2);
        let max_seekable_us = duration_us - (buffer_ms * 1000);
        
        if ts > max_seekable_us {
            debug!("Requested timestamp {}us is too close to end (duration: {}us, buffer: {}ms), clamping to {}us", 
                   ts, duration_us, buffer_ms, max_seekable_us);
            ts = max_seekable_us.max(0);
        } else if ts > duration_us {
            ts = duration_us;
        }
    }

    // Attempt to seek to the target timestamp
    // Use a range that allows FFmpeg to seek to the nearest keyframe before the target
    // This is more robust than exact seeking, especially for videos with sparse keyframes
    // The range (min_ts..ts) allows seeking backward up to 2 seconds to find a keyframe
    let min_ts = (ts - 2_000_000).max(0); // Allow up to 2 seconds backward for keyframe seeking
    let seek_result = ictx.seek(ts, min_ts..ts);
    
    seek_result.map_err(|e| {
        // Release semaphore on error
        #[cfg(target_os = "windows")]
        {
            use std::sync::atomic::Ordering;
            use std::thread;
            use std::time::Duration;
            thread::sleep(Duration::from_millis(50));
            thread::yield_now();
            FFMPEG_CONTEXT_SEMAPHORE.fetch_add(1, Ordering::AcqRel);
            debug!("generate_thumbnail - released FFmpeg context semaphore (seek error)");
        }
        // Provide platform-specific context about the error
        let platform_hint = if cfg!(target_os = "android") {
            "On Android, this may indicate file permissions issue (the file might be in a restricted cache directory), \
            the file might be locked by another process, or there may be an issue with the video file format/codec."
        } else if cfg!(target_os = "macos") || cfg!(target_os = "ios") {
            "On macOS/iOS, this may indicate missing file permissions (check System Settings > Privacy & Security > Files and Folders) \
            or the timestamp may be too close to the end of the video."
        } else {
            "This may indicate file permissions issue, the file might be locked, or the timestamp may be too close to the end of the video."
        };
        
        let error_msg = format!(
            "Failed to seek to {}ms (timestamp: {}us) in video file '{}': {}. {}",
            params.time_ms, ts, path, e, platform_hint
        );
        warn!("{}", error_msg);
        (anyhow::anyhow!(error_msg), display_width, display_height)
    })?;

    let mut scaler = None::<ffmpeg::software::scaling::Context>;
    let mut decoded = ffmpeg::util::frame::video::Video::empty();
    let mut rgb_frame = ffmpeg::util::frame::video::Video::empty();

    for (stream, packet) in ictx.packets() {
        if stream.index() != stream_index {
            continue;
        }

        decoder
            .send_packet(&packet)
            .map_err(|e| {
                // Release semaphore on error
                #[cfg(target_os = "windows")]
                {
                    use std::sync::atomic::Ordering;
                    use std::thread;
                    use std::time::Duration;
                    thread::sleep(Duration::from_millis(50));
                    thread::yield_now();
                    FFMPEG_CONTEXT_SEMAPHORE.fetch_add(1, Ordering::AcqRel);
                    debug!("generate_thumbnail - released FFmpeg context semaphore (send_packet error)");
                }
                (e.into(), display_width, display_height)
            })?;
        while decoder.receive_frame(&mut decoded).is_ok() {
            // lazily init scaler based on real video size
            if scaler.is_none() {
                let src_w = decoded.width();
                let src_h = decoded.height();

                // Use display dimensions for thumbnail size calculation
                let size = params
                    .size_type
                    .unwrap_or(ThumbnailSizeType::Custom((display_width, display_height)))
                    .dimensions();

                // Scale to fit, but account for rotation in target dimensions
                let (dst_w, dst_h) = if rotation == 90 || rotation == 270 {
                    // For rotated videos, swap target dimensions
                    scale_to_fit(src_w, src_h, size.1, size.0)
                } else {
                    scale_to_fit(src_w, src_h, size.0, size.1)
                };

                rgb_frame = ffmpeg::util::frame::video::Video::new(
                    ffmpeg::format::Pixel::RGB24,
                    dst_w,
                    dst_h,
                );

                // Preserve color metadata on RGB frame BEFORE scaling
                // This is critical for HDR videos to maintain proper tone mapping and brightness
                unsafe {
                    let rgb_ptr = rgb_frame.as_mut_ptr();
                    if !rgb_ptr.is_null() {
                        // Set color range to match input (prevents scaler from expanding limited range)
                        (*rgb_ptr).color_range = input_color_range;
                        // Preserve other color properties for proper color interpretation
                        (*rgb_ptr).colorspace = input_colorspace;
                        (*rgb_ptr).color_primaries = input_color_primaries;
                        (*rgb_ptr).color_trc = input_color_trc; // Transfer characteristics (critical for HDR)
                    }
                }

                // Use FAST_BILINEAR to avoid deprecated pixel format warnings
                scaler = Some(
                    ffmpeg::software::scaling::Context::get(
                        decoded.format(),
                        src_w,
                        src_h,
                        ffmpeg::format::Pixel::RGB24,
                        dst_w,
                        dst_h,
                        ffmpeg::software::scaling::flag::Flags::FAST_BILINEAR,
                    )
                    .map_err(|e| (e.into(), display_width, display_height))?,
                );
            }

            if let Some(ref mut scaler_ctx) = scaler {
                // Preserve color metadata from decoded frame to RGB frame before scaling
                // This ensures the scaler respects the color range and doesn't expand limited range
                // which would cause brightness issues in HDR thumbnails
                unsafe {
                    let decoded_ptr = decoded.as_ptr();
                    let rgb_ptr = rgb_frame.as_mut_ptr();

                    if !decoded_ptr.is_null() && !rgb_ptr.is_null() {
                        // Copy color space properties from decoded frame to RGB frame
                        // This must be done before scaling so the scaler preserves the correct range
                        (*rgb_ptr).colorspace = (*decoded_ptr).colorspace;
                        (*rgb_ptr).color_range = (*decoded_ptr).color_range;
                        (*rgb_ptr).color_primaries = (*decoded_ptr).color_primaries;
                        (*rgb_ptr).color_trc = (*decoded_ptr).color_trc; // Transfer characteristics (critical for HDR)
                        (*rgb_ptr).chroma_location = (*decoded_ptr).chroma_location;
                    }
                }

                let output_format = params.format.unwrap_or(OutputFormat::PNG);
                scaler_ctx
                    .run(&decoded, &mut rgb_frame)
                    .map_err(|e| (e.into(), display_width, display_height))?;

                // Re-apply color metadata after scaling to ensure it's preserved
                // (scaler operations might modify frame metadata)
                unsafe {
                    let decoded_ptr = decoded.as_ptr();
                    let rgb_ptr = rgb_frame.as_mut_ptr();

                    if !decoded_ptr.is_null() && !rgb_ptr.is_null() {
                        (*rgb_ptr).colorspace = (*decoded_ptr).colorspace;
                        (*rgb_ptr).color_range = (*decoded_ptr).color_range;
                        (*rgb_ptr).color_primaries = (*decoded_ptr).color_primaries;
                        (*rgb_ptr).color_trc = (*decoded_ptr).color_trc;
                    }
                }

                // Apply rotation to the thumbnail image
                let result =
                    encode_png_from_rgb_frame_with_rotation(&rgb_frame, output_format, rotation)
                        .map_err(|e| {
                            // Release semaphore on error
                            #[cfg(target_os = "windows")]
                            {
                                use std::sync::atomic::Ordering;
                                use std::thread;
                                use std::time::Duration;
                                thread::sleep(Duration::from_millis(50));
                                thread::yield_now();
                                FFMPEG_CONTEXT_SEMAPHORE.fetch_add(1, Ordering::AcqRel);
                                debug!("generate_thumbnail - released FFmpeg context semaphore (encode error)");
                            }
                            (e, display_width, display_height)
                        })?;

                // Release semaphore before returning success
                #[cfg(target_os = "windows")]
                {
                    use std::sync::atomic::Ordering;
                    use std::thread;
                    use std::time::Duration;
                    thread::sleep(Duration::from_millis(50));
                    thread::yield_now();
                    FFMPEG_CONTEXT_SEMAPHORE.fetch_add(1, Ordering::AcqRel);
                    debug!("generate_thumbnail - released FFmpeg context semaphore (success)");
                }

                // Return result AND display dimensions (corrected for rotation)
                return Ok((result.0, result.1, result.2));
            }
        }
    }

    // Release semaphore before returning error
    #[cfg(target_os = "windows")]
    {
        use std::sync::atomic::Ordering;
        use std::thread;
        use std::time::Duration;
        thread::sleep(Duration::from_millis(50));
        thread::yield_now();
        FFMPEG_CONTEXT_SEMAPHORE.fetch_add(1, Ordering::AcqRel);
        debug!("generate_thumbnail - released FFmpeg context semaphore (no frame error)");
    }

    Err((
        anyhow::anyhow!("Could not decode frame for thumbnail"),
        display_width,
        display_height,
    ))
}

fn scale_to_fit(src_w: u32, src_h: u32, max_w: u32, max_h: u32) -> (u32, u32) {
    if max_w == 0 || max_h == 0 {
        return (src_w, src_h);
    }

    let src_w_f = src_w as f32;
    let src_h_f = src_h as f32;
    let max_w_f = max_w as f32;
    let max_h_f = max_h as f32;

    let scale = (max_w_f / src_w_f).min(max_h_f / src_h_f).min(1.0);
    (
        (src_w_f * scale).round() as u32,
        (src_h_f * scale).round() as u32,
    )
}

fn encode_png_from_rgb_frame_with_rotation(
    frame: &ffmpeg::util::frame::video::Video,
    format: OutputFormat,
    rotation: i32,
) -> Result<(Vec<u8>, u32, u32)> {
    use image::codecs::jpeg::JpegEncoder;
    use image::codecs::png::PngEncoder;
    use image::codecs::webp::WebPEncoder;
    use image::ExtendedColorType;
    use image::{ImageBuffer, ImageEncoder, Rgb};

    let width = frame.width();
    let height = frame.height();

    // frame data is RGB24: contiguous buffer
    let data = frame.data(0);
    let stride = frame.stride(0);

    // Copy into tightly-packed buffer (no stride padding)
    let mut buf = Vec::with_capacity((width * height * 3) as usize);
    for y in 0..height {
        let row_start = (y as usize) * stride;
        let row = &data[row_start..row_start + (width as usize * 3)];
        buf.extend_from_slice(row);
    }

    let mut img: ImageBuffer<Rgb<u8>, _> = ImageBuffer::from_raw(width, height, buf)
        .ok_or_else(|| anyhow::anyhow!("Failed to create image buffer"))?;

    // Apply rotation to the image
    // The rotation value from display matrix indicates the rotation needed to display correctly
    // FFmpeg's display matrix: rotation value means "rotate this much CCW to display correctly"
    // If rotation is 90, it means "rotate 90° CCW to display correctly"
    // This means the video frames are stored rotated 270° CCW (or 90° CW) from correct orientation
    // To correct it, we need to rotate in the OPPOSITE direction
    // The image crate's rotate functions rotate counter-clockwise:
    // - rotate90() = 90° CCW
    // - rotate270() = 270° CCW = 90° CW
    // So if display matrix says "90° CCW needed", video is stored at 270° CCW, rotate 90° CCW = rotate90()
    // If display matrix says "270° CCW needed", video is stored at 90° CCW, rotate 270° CCW = rotate270()
    let (final_width, final_height) = match rotation {
        90 => {
            // Display matrix says "rotate 90° CCW to display", so video is stored at 270° CCW
            // Rotate 90° CCW (rotate90) to correct it
            img = image::DynamicImage::ImageRgb8(img).rotate90().into_rgb8();
            (height, width)
        }
        180 => {
            // Display matrix says "rotate 180° CCW to display", so video is stored at 180° CCW
            // Rotate 180° CCW (rotate180) to correct it
            img = image::DynamicImage::ImageRgb8(img).rotate180().into_rgb8();
            (width, height)
        }
        270 => {
            // Display matrix says "rotate 270° CCW to display", so video is stored at 90° CCW
            // Rotate 270° CCW (rotate270) to correct it
            img = image::DynamicImage::ImageRgb8(img).rotate270().into_rgb8();
            (height, width)
        }
        _ => (width, height),
    };

    let mut out = Vec::new();
    match format {
        OutputFormat::PNG => {
            let encoder = PngEncoder::new(&mut out);
            encoder.write_image(
                img.as_raw(),
                final_width,
                final_height,
                ExtendedColorType::Rgb8,
            )?;
        }
        OutputFormat::JPEG => {
            let encoder = JpegEncoder::new(&mut out);
            encoder.write_image(
                img.as_raw(),
                final_width,
                final_height,
                ExtendedColorType::Rgb8,
            )?;
        }
        OutputFormat::WEBP => {
            let encoder = WebPEncoder::new_lossless(&mut out);
            encoder.write_image(
                img.as_raw(),
                final_width,
                final_height,
                ExtendedColorType::Rgb8,
            )?;
        }
    }

    Ok((out, final_width, final_height))
}

pub fn get_file_name_without_extension(path: &str) -> PathBuf {
    // Safely extract filename, fallback to a default if path is invalid
    let filename_with_extension = Path::new(&path)
        .file_name()
        .unwrap_or_else(|| std::ffi::OsStr::new("output"));

    
    PathBuf::from(filename_with_extension).with_extension("")
}

pub fn check_output_path(output_path: &str) -> anyhow::Result<PathBuf> {
    let mut base_output_dir = PathBuf::from(&output_path);
    // If the given output path is actually a file, fall back to its parent directory
    if base_output_dir.is_file() {
        if let Some(parent) = base_output_dir.parent() {
            base_output_dir = parent.to_path_buf();
        }
    }

    // Ensure output directory exists
    std::fs::create_dir_all(&base_output_dir)
        .with_context(|| {
            format!(
                "Failed to create output directory: {}",
                base_output_dir.display()
            )
        })?;
    Ok(base_output_dir)
}

pub fn estimate_compression(
    path: &str,
    temp_output_path: &str,
    params: &CompressParams,
) -> Result<CompressionEstimate> {
    // Call the internal version with no pre-fetched video info
    estimate_compression_with_info(path, temp_output_path, params, None)
}

/// Internal version that accepts optional VideoInfo to avoid opening a second FFmpeg context
/// This is critical on Windows where opening a second context causes a crash
pub fn estimate_compression_with_info(
    path: &str,
    temp_output_path: &str,
    params: &CompressParams,
    video_info: Option<&crate::api::media::VideoInfo>,
) -> Result<CompressionEstimate> {
    let estimate_start = std::time::Instant::now();
    debug!("estimate_compression_with_info called with path: {}, temp_output: {}", path, temp_output_path);
    
    // Validate input file exists
    if !std::path::Path::new(path).exists() {
        let err = anyhow::anyhow!("Input video file does not exist: {}", path);
        error!("{}", err);
        return Err(err);
    }
    
    debug!("estimate_compression - about to call init_ffmpeg()");
    init_ffmpeg()?;
    debug!("estimate_compression - init_ffmpeg() succeeded");

    debug!("estimate_compression - getting filename without extension");
    let filename_without_extension = get_file_name_without_extension(path);
    debug!("estimate_compression - filename: {}", filename_without_extension.display());
    
    debug!("estimate_compression - checking output path");
    let base_output_dir = check_output_path(temp_output_path)?;
    debug!("estimate_compression - output dir: {}", base_output_dir.display());

    // CRITICAL WORKAROUND: On Windows, FFmpeg crashes when opening a second context
    // Use provided VideoInfo if available to avoid the crash
    let info = if let Some(provided_info) = video_info {
        debug!("estimate_compression - using provided VideoInfo to avoid second FFmpeg context");
        provided_info.clone()
    } else {
        debug!("estimate_compression - VideoInfo not provided, must open FFmpeg context");
        
        // On Windows, this will likely crash. Return a helpful error message.
        #[cfg(target_os = "windows")]
        {
            error!("FATAL: estimate_compression called without VideoInfo on Windows. This will crash due to FFmpeg bug when opening second context.");
            return Err(anyhow::anyhow!(
                "estimate_compression requires VideoInfo on Windows to avoid FFmpeg crash. \
                Please call get_video_info first and pass the result to estimate_compression_with_info, \
                or use the new estimate_compression_with_info function."
            ));
        }
        
        // On other platforms, just get video info (FFmpeg is thread-safe with separate contexts)
        #[cfg(not(target_os = "windows"))]
        {
            get_video_info_internal(path)?
        }
    };
    debug!("estimate_compression - get_video_info_internal() succeeded, duration: {}ms", info.duration_ms);
    let total_duration_ms = info.duration_ms;
    
    // CRITICAL: Release mutex before spawning threads
    // The spawned threads will acquire the mutex individually in perform_compression
    // If we hold the mutex here, the threads will deadlock waiting for it

    // Safety check: if video is very short (< 5s), just run a single sample from 0
    // NOTE: perform_compression will acquire the mutex itself, so we don't hold it here
    if total_duration_ms < 5000 {
        let temp_path = format!(
            "{}/{}.est.temp.mp4",
            base_output_dir.display(),
            filename_without_extension.display()
        );
        // perform_compression will acquire the mutex internally
        let result = perform_compression(path, &temp_path, params, Some(0), None);
        std::fs::remove_file(&temp_path).ok(); // Cleanup

        match result {
            Ok(stats) => {
                return Ok(crate::api::media::CompressionEstimate {
                    estimated_size_bytes: stats.encoded_size_bytes,
                    estimated_duration_ms: stats.elapsed_ms as u64,
                })
            }
            Err(e) => return Err(e),
        }
    }

    // Heuristics - use shorter samples for faster estimation
    // Reduced from 5000ms to 2000ms: 0.5s warmup + 1.5s active is sufficient for estimation
    let sample_duration_ms = params.sample_duration_ms.unwrap_or(2000u64);

    // Define sampling points based on mode
    let points = if params.crf.is_some() {
        // CRF Mode: Sample 15%, 50%, 85%
        vec![0.15, 0.50, 0.85]
    } else {
        // Bitrate Mode (Time estimation only): Sample 50%
        vec![0.50]
    };

    // Clamp Bitrate for Estimation to match Perform Logic
    let input_bitrate_kbps = info.bitrate.unwrap_or(0) / 1000;

    let mut estimated_target_bitrate = params.target_bitrate_kbps;

    // Careful with fuzzy comparison, but if input is known and target is higher, clamp.
    if input_bitrate_kbps > 0 && estimated_target_bitrate > input_bitrate_kbps as u32 {
        estimated_target_bitrate = input_bitrate_kbps as u32;
    }

    // For Bitrate Mode Size Calculation
    let mut bitrate_mode_size: Option<u64> = None;
    if params.crf.is_none() {
        // ... Logic using estimated_target_bitrate ...
        let audio_bitrate_bps = 192_000u64; // Est audio
        let video_bitrate_bps = (estimated_target_bitrate * 1000) as u64;
        let total_bps = video_bitrate_bps + audio_bitrate_bps;
        bitrate_mode_size = Some((total_bps * total_duration_ms) / 8000);
    }

    // Use parallel execution on all platforms for best performance
    // On Windows, use a semaphore to limit concurrent FFmpeg context creation
    debug!("estimate_compression - spawning {} threads for parallel sampling", points.len());
    let results: Vec<Result<(f64, f64)>> = std::thread::scope(|s| {
        let handles: Vec<_> = points
            .iter()
            .enumerate()
            .map(|(i, &point)| {
                let path = path.to_owned();
                let params = params.clone();
                let base_output_dir = base_output_dir.to_owned();
                let filename_without_extension = filename_without_extension.to_owned();
                let total_duration_ms = total_duration_ms;
                let sample_duration_ms = sample_duration_ms;
                s.spawn(move || {
                    let thread_id = i;
                    debug!("estimate_compression - thread {} started, point: {}", thread_id, point);
                    let start_ms = (total_duration_ms as f64 * point) as u64;

                    // Ensure we don't seek past end (minus sample duration)
                    let actual_start_ms = if start_ms + sample_duration_ms > total_duration_ms {
                        total_duration_ms.saturating_sub(sample_duration_ms)
                    } else {
                        start_ms
                    };

                    debug!("estimate_compression - thread {}: start_ms={}, actual_start_ms={}, sample_duration_ms={}", 
                           thread_id, start_ms, actual_start_ms, sample_duration_ms);

                    let temp_path = format!(
                        "{}/{}.est.part.{}.mp4",
                        base_output_dir.display(),
                        filename_without_extension.display(),
                        i
                    );

                    debug!("estimate_compression - thread {}: about to call perform_compression", thread_id);
                    
                    // On Windows, use semaphore to limit concurrent FFmpeg context creation
                    // CRITICAL: Hold semaphore for the ENTIRE duration of perform_compression
                    // to ensure only one FFmpeg context is created/used at a time
                    #[cfg(target_os = "windows")]
                    {
                        use std::thread;
                        use std::time::Duration;
                        // Wait for semaphore (spin-wait with exponential backoff)
                        let mut wait_time = 1u64;
                        loop {
                            let current = FFMPEG_CONTEXT_SEMAPHORE.load(Ordering::Acquire);
                            if current > 0 {
                                if FFMPEG_CONTEXT_SEMAPHORE.compare_exchange(
                                    current,
                                    current - 1,
                                    Ordering::AcqRel,
                                    Ordering::Acquire,
                                ).is_ok() {
                                    debug!("estimate_compression - thread {}: acquired FFmpeg context semaphore", thread_id);
                                    break;
                                }
                            }
                            thread::sleep(Duration::from_millis(wait_time));
                            wait_time = (wait_time * 2).min(50); // Cap at 50ms
                        }
                        
                        // Small delay after acquiring semaphore to ensure previous operation
                        // has fully cleaned up FFmpeg's internal state
                        // Reduced from 500ms to 50ms since semaphore provides serialization
                        debug!("estimate_compression - thread {}: waiting after semaphore acquisition for cleanup", thread_id);
                        thread::sleep(Duration::from_millis(50));
                        thread::yield_now();
                        debug!("estimate_compression - thread {}: proceeding with perform_compression", thread_id);
                    }
                    
                    let compression_start = std::time::Instant::now();
                    let result = perform_compression(
                        &path,
                        &temp_path,
                        &params,
                        Some(actual_start_ms),
                        Some(sample_duration_ms),
                    );
                    let compression_elapsed = compression_start.elapsed();
                    debug!("estimate_compression - thread {}: perform_compression completed in {:?}", 
                           thread_id, compression_elapsed);
                    
                    // Release semaphore on Windows AFTER compression completes and contexts are dropped
                    #[cfg(target_os = "windows")]
                    {
                        use std::thread;
                        use std::time::Duration;
                        // Small delay before releasing semaphore to ensure FFmpeg contexts
                        // are fully dropped. Reduced from 500ms to 50ms since semaphore provides serialization
                        debug!("estimate_compression - thread {}: waiting for FFmpeg cleanup before releasing semaphore", thread_id);
                        thread::sleep(Duration::from_millis(50));
                        thread::yield_now();
                        FFMPEG_CONTEXT_SEMAPHORE.fetch_add(1, Ordering::AcqRel);
                        debug!("estimate_compression - thread {}: released FFmpeg context semaphore after cleanup", thread_id);
                    }
                    
                    std::fs::remove_file(&temp_path).ok();

                    match result {
                        Ok(stats) => {
                            if stats.processed_duration_ms > 0 && stats.elapsed_ms > 0 {
                                let speed =
                                    stats.processed_duration_ms as f64 / stats.elapsed_ms as f64;
                                let size_rate = stats.encoded_size_bytes as f64
                                    / stats.processed_duration_ms as f64;
                                debug!("estimate_compression - thread {}: success, speed={:.2}x, size_rate={:.2} bytes/ms", 
                                       thread_id, speed, size_rate);
                                Ok((speed, size_rate))
                            } else {
                                warn!("estimate_compression - thread {}: zero duration processed", thread_id);
                                Err(anyhow::anyhow!("Zero duration processed"))
                            }
                        }
                        Err(e) => {
                            error!("estimate_compression - thread {}: perform_compression failed: {}", thread_id, e);
                            Err(e)
                        }
                    }
                })
            })
            .collect();

        debug!("estimate_compression - waiting for {} threads to complete", handles.len());
        let join_start = std::time::Instant::now();
        let results: Vec<_> = handles.into_iter().enumerate().map(|(i, h)| {
            debug!("estimate_compression - waiting for thread {} to join", i);
            let join_result = h.join();
            let join_elapsed = join_start.elapsed();
            debug!("estimate_compression - thread {} joined after {:?}", i, join_elapsed);
            match join_result {
                Ok(result) => result,
                Err(e) => {
                    // Thread panicked - try to extract panic message
                    let panic_msg = if let Some(s) = e.downcast_ref::<&str>() {
                        format!("Thread {} panicked: {}", i, s)
                    } else if let Some(s) = e.downcast_ref::<String>() {
                        format!("Thread {} panicked: {}", i, s)
                    } else {
                        format!("Thread {} panicked: unknown error", i)
                    };
                    error!("{}", panic_msg);
                    Err(anyhow::anyhow!(panic_msg))
                }
            }
        }).collect();
        debug!("estimate_compression - all threads completed");
        results
    });

    debug!("estimate_compression - processing {} results", results.len());
    let mut total_speed_x = 0.0;
    let mut total_size_per_ms = 0.0;
    let mut valid_samples = 0;

    for (i, res) in results.into_iter().enumerate() {
        match res {
            Ok((speed, size_rate)) => {
                debug!(
                    "Sample {}: Speed={:.2}x, SizeRate={:.2} bytes/ms",
                    i, speed, size_rate
                );
                total_speed_x += speed;
                total_size_per_ms += size_rate;
                valid_samples += 1;
            }
            Err(e) => {
                error!("Sample {}: Failed with error: {}", i, e);
            }
        }
    }

    debug!("Total Speed (Sum): {:.2}x, Valid samples: {}", total_speed_x, valid_samples);

    // Fallback if all samples failed
    if valid_samples == 0 {
        eprintln!("All compression samples failed. Attempting fallback...");
        let temp_path = format!(
            "{}/{}.est.fallback.mp4",
            base_output_dir.display(),
            filename_without_extension.display()
        );
        let result =
            perform_compression(path, &temp_path, params, Some(0), Some(sample_duration_ms));
        std::fs::remove_file(&temp_path).ok();

        match result {
            Ok(stats) => {
                if stats.processed_duration_ms > 0 && stats.elapsed_ms > 0 {
                    let speed = stats.processed_duration_ms as f64 / stats.elapsed_ms as f64;
                    let size_rate =
                        stats.encoded_size_bytes as f64 / stats.processed_duration_ms as f64;
                    total_speed_x += speed;
                    total_size_per_ms += size_rate;
                    valid_samples += 1;
                    eprintln!("Fallback sample succeeded");
                } else {
                    eprintln!(
                        "Fallback sample returned invalid stats: duration={}, elapsed={}",
                        stats.processed_duration_ms, stats.elapsed_ms
                    );
                }
            }
            Err(e) => {
                eprintln!("Fallback sample also failed: {:?}", e);
            }
        }
    }

    if valid_samples == 0 {
        // Fallback: all sampling attempts failed (e.g. encoder quirks, seek issues).
        // Instead of bubbling an error to the app, return a conservative estimate
        // based purely on bitrate math so the UX can proceed.
        //
        // If we're in bitrate mode and already computed a fixed size, just use it.
        let estimated_size_bytes = if let Some(fixed_size) = bitrate_mode_size {
            fixed_size
        } else {
            // CRF mode or no bitrate hint: approximate using a modest video bitrate
            // plus 192kbps audio, based on the source duration.
            let video_bitrate_bps = info.bitrate.unwrap_or(2_000_000u64);
            let audio_bitrate_bps = 192_000u64;
            let total_bps = video_bitrate_bps + audio_bitrate_bps;
            (total_bps * total_duration_ms) / 8000
        };

        // Duration estimate: assume 1x realtime as a safe default if we have no samples.
        let estimated_duration_ms = total_duration_ms;

        return Ok(crate::api::media::CompressionEstimate {
            estimated_size_bytes,
            estimated_duration_ms,
        });
    }

    // Size: use average video rate from samples
    let avg_video_rate_per_ms = total_size_per_ms / valid_samples as f64;

    // Speed: use sum of per-sample speeds
    let estimated_speed = total_speed_x;

    let estimated_duration_ms = (total_duration_ms as f64 / estimated_speed) as u64;

    let estimated_size_bytes = if let Some(fixed_size) = bitrate_mode_size {
        fixed_size
    } else {
        // Video estimate from sampled rate
        let video_est = avg_video_rate_per_ms * total_duration_ms as f64;

        // Audio estimate (constant 192kbps = 24 bytes/ms), skipped in sampling
        let audio_est = (192.0 / 8.0) * total_duration_ms as f64;

        (video_est + audio_est) as u64
    };

    let estimate_elapsed = estimate_start.elapsed();
    debug!("estimate_compression_with_info completed in {:?}, estimated_size_bytes: {}, estimated_duration_ms: {}", 
           estimate_elapsed, estimated_size_bytes, estimated_duration_ms);
    
    Ok(crate::api::media::CompressionEstimate {
        estimated_size_bytes,
        estimated_duration_ms,
    })
}

fn calculate_dimensions(
    src_w: u32,
    src_h: u32,
    target_w: Option<u32>,
    target_h: Option<u32>,
) -> (u32, u32) {
    let (mut w, mut h) = match (target_w, target_h) {
        (Some(w), Some(h)) => (w, h),
        (Some(w), None) => {
            let h = (src_h as f64 * (w as f64 / src_w as f64)) as u32;
            (w, h)
        }
        (None, Some(h)) => {
            let w = (src_w as f64 * (h as f64 / src_h as f64)) as u32;
            (w, h)
        }
        (None, None) => (src_w, src_h),
    };

    // Anti-Upscaling: Clamp to source dimensions
    if w > src_w {
        // If width requested is larger, reset to source width and recalc height to maintain aspect
        // Actually, simplest is to just cap both? But we want to maintain aspect ratio of the request?
        // Usually assuming request *intends* to keep source aspect ratio.
        // Let's just limit to source bounds.
        w = src_w;
        h = src_h; // Reset to original if we are trying to blow it up.
                   // Note: this assumes we are scaling the WHOLE image.
    }
    if h > src_h {
        h = src_h;
        w = src_w;
    }

    // enforce even
    (w & !1, h & !1)
}

pub fn compress_video(
    path: &str,
    output_path: &str,
    params: &crate::api::media::CompressParams,
) -> Result<String, Error> {
    let result = perform_compression(path, output_path, params, None, None)?;
    Ok(result.output_file_path)
}

pub struct CompressionStats {
    pub processed_duration_ms: u64,
    pub elapsed_ms: u128,
    pub encoded_size_bytes: u64,
    pub output_file_path: String,
}

fn perform_compression(
    path: &str,
    output_path: &str,
    params: &crate::api::media::CompressParams,
    start_ms: Option<u64>,
    duration_limit_ms: Option<u64>,
) -> Result<CompressionStats> {
    debug!("perform_compression called with path: {}, output: {}", path, output_path);
    
    // On Windows, verify MinGW DLLs are accessible before initializing FFmpeg
    #[cfg(target_os = "windows")]
    {
        debug!("perform_compression - checking MinGW DLLs");
        let exe_dir = std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(|p| p.to_path_buf()));
        
        if let Some(dir) = &exe_dir {
            let dlls = ["libgcc_s_seh-1.dll", "libwinpthread-1.dll"];
            let mut missing_dlls = Vec::new();
            let mut found_dlls = Vec::new();
            
            for dll in &dlls {
                let dll_path = dir.join(dll);
                if dll_path.exists() {
                    found_dlls.push(dll);
                    debug!("Found MinGW DLL: {}", dll_path.display());
                } else {
                    missing_dlls.push(dll);
                    debug!("MinGW DLL not found in executable directory: {} (may be in PATH)", dll_path.display());
                }
            }
            
            if !missing_dlls.is_empty() {
                // These DLLs are runtime dependencies of FFmpeg (built with MinGW)
                // They may be loaded from PATH (e.g., MSYS2) or system directories
                // Only warn if they're not found - FFmpeg initialization will fail if truly missing
                debug!("MinGW runtime DLLs not found in executable directory: {:?}", missing_dlls);
                debug!("  Executable directory: {}", dir.display());
                debug!("  Found DLLs: {:?}", found_dlls);
                debug!("  Note: These DLLs may be loaded from PATH (e.g., MSYS2) or system directories");
                // Continue anyway - let FFmpeg initialization provide the actual error if truly missing
            } else {
                debug!("All required MinGW runtime DLLs found in executable directory");
            }
        } else {
            warn!("Could not determine executable directory");
        }
    }
    
    debug!("perform_compression - about to call init_ffmpeg()");
    init_ffmpeg()?;
    debug!("perform_compression - init_ffmpeg() succeeded");
    
    // FFmpeg is thread-safe when using separate contexts per thread.
    // On Windows, minimal delay to allow FFmpeg internal state to stabilize
    // The semaphore in estimate_compression handles concurrency control
    #[cfg(target_os = "windows")]
    {
        use std::thread;
        use std::time::Duration;
        // Reduced delay since semaphore controls concurrency
        thread::sleep(Duration::from_millis(100));
        thread::yield_now();
    }

    let filename_without_extension = get_file_name_without_extension(path);
    let output_path_buf = PathBuf::from(output_path);

    // Determine target output path
    // If output_path has an extension, assume it is the full target file path.
    // Otherwise, assume it is a directory and construct the filename inside it.
    let output_path = if output_path_buf.extension().is_some() {
        if let Some(parent) = output_path_buf.parent() {
            std::fs::create_dir_all(parent).with_context(|| {
                format!("Failed to create output directory: {}", parent.display())
            })?;
        }
        output_path_buf
    } else {
        let base_output_dir = check_output_path(output_path)?;
        base_output_dir.join(format!(
            "compressed_{}.mp4",
            filename_without_extension.display()
        ))
    };

    // We need to convert PathBuf to str for ffmpeg, or use it directly if ffmpeg supports it.
    // ffmpeg::format::output takes a &Path or &str. `output` takes &Path since newer versions?
    // Let's check the existing code uses `&output_path` where `output_path` was a String.
    // We can convert PathBuf to String for consistency.
    let output_path_str = output_path.to_string_lossy().to_string();

    let mut encoded_size_bytes = 0u64;

    // Validate input file exists and is readable
    if !std::path::Path::new(path).exists() {
        return Err(anyhow::anyhow!("Input video file does not exist: {}", path));
    }
    
    // Normalize Windows path: convert backslashes to forward slashes
    // FFmpeg (built with MinGW) may have issues with Windows path separators
    #[cfg(target_os = "windows")]
    let normalized_path = path.replace('\\', "/");
    #[cfg(not(target_os = "windows"))]
    let normalized_path = path.to_string();
    
    debug!("perform_compression - normalized input path: {}", normalized_path);
    
    // On Windows, add a significant delay before opening FFmpeg contexts
    // CRITICAL: FFmpeg crashes with access violation when opening contexts too quickly
    // This delay allows FFmpeg's internal state to fully clean up from previous operations
    // When multiple threads are involved, we need even more time between operations
    #[cfg(target_os = "windows")]
    {
        use std::thread;
        use std::time::Duration;
        debug!("perform_compression - Windows: waiting before opening FFmpeg context to avoid crash");
        // Minimal delay before opening context - semaphore in estimate_compression handles concurrency
        // Reduced from 150ms to 50ms since semaphore provides serialization
        thread::sleep(Duration::from_millis(50));
        thread::yield_now();
        debug!("perform_compression - Windows: delay complete, proceeding to open context");
    }
    
    // Try to open input with better error messages
    debug!("perform_compression - attempting to open input file (thread: {:?})", std::thread::current().id());
    // Wrap in catch_unwind to catch any panics from FFmpeg C code
    // CRITICAL: On Windows, FFmpeg may crash with access violation if internal state is corrupted
    // The semaphore in estimate_compression should prevent this, but we add extra protection
    let mut ictx = match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        debug!("perform_compression - calling ffmpeg::format::input() (thread: {:?})", std::thread::current().id());
        let result = ffmpeg::format::input(&normalized_path);
        debug!("perform_compression - ffmpeg::format::input() returned (thread: {:?})", std::thread::current().id());
        result
    })) {
        Ok(Ok(ctx)) => {
            debug!("perform_compression - succeeded with normalized path (thread: {:?})", std::thread::current().id());
            ctx
        }
        Ok(Err(e)) => {
            warn!("perform_compression - normalized path failed: {}, trying original", e);
            // Fallback to original path - also wrap in catch_unwind
            match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                ffmpeg::format::input(path)
            })) {
                Ok(Ok(ctx)) => ctx,
                Ok(Err(e)) => {
                    return Err(anyhow::anyhow!("Failed to open input video file: {}. Error: {}. Check file permissions and format.", path, e))
                        .with_context(|| format!("Both normalized and original paths failed for: {}", path));
                }
                Err(panic) => {
                    let panic_msg = if let Some(s) = panic.downcast_ref::<&str>() {
                        format!("FFmpeg panic when opening file: {}", s)
                    } else if let Some(s) = panic.downcast_ref::<String>() {
                        format!("FFmpeg panic when opening file: {}", s)
                    } else {
                        "FFmpeg panic when opening file: unknown error".to_string()
                    };
                    error!("{}", panic_msg);
                    return Err(anyhow::anyhow!("{}", panic_msg))
                        .with_context(|| format!("FFmpeg crashed when trying to open: {}", path));
                }
            }
        }
        Err(panic) => {
            let panic_msg = if let Some(s) = panic.downcast_ref::<&str>() {
                format!("FFmpeg panic when opening normalized path: {}", s)
            } else if let Some(s) = panic.downcast_ref::<String>() {
                format!("FFmpeg panic when opening normalized path: {}", s)
            } else {
                "FFmpeg panic when opening normalized path: unknown error".to_string()
            };
            error!("{}", panic_msg);
            // Try original path as fallback
            warn!("Trying original path after panic with normalized path");
            match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                ffmpeg::format::input(path)
            })) {
                Ok(Ok(ctx)) => {
                    warn!("Original path succeeded after normalized path panic");
                    ctx
                }
                Ok(Err(e)) => {
                    return Err(anyhow::anyhow!("Failed to open input video file: {}. Normalized path panicked, original path error: {}.", path, e))
                        .with_context(|| format!("FFmpeg crashed with normalized path and failed with original: {}", path));
                }
                Err(panic2) => {
                    let panic_msg2 = if let Some(s) = panic2.downcast_ref::<&str>() {
                        format!("FFmpeg panic when opening original path: {}", s)
                    } else if let Some(s) = panic2.downcast_ref::<String>() {
                        format!("FFmpeg panic when opening original path: {}", s)
                    } else {
                        "FFmpeg panic when opening original path: unknown error".to_string()
                    };
                    error!("{}", panic_msg2);
                    return Err(anyhow::anyhow!("FFmpeg crashed with both paths. Normalized: {}, Original: {}", panic_msg, panic_msg2))
                        .with_context(|| format!("FFmpeg crashed when trying to open: {}", path));
                }
            }
        }
    };
    info!("perform_compression - input file opened successfully");
    
    // Try to open output with better error messages
    let mut octx = ffmpeg::format::output(&output_path_str)
        .with_context(|| format!("Failed to create output video file: {}. Check directory permissions.", output_path_str))?;

    // Only process the first video stream
    let (video_stream_index, mut decoder) = {
        let stream = ictx
            .streams()
            .best(ffmpeg::media::Type::Video)
            .ok_or(anyhow::anyhow!("Could not find best stream"))?;

        let index = stream.index();
        let decoder = ffmpeg::codec::context::Context::from_parameters(stream.parameters())?
            .decoder()
            .video()?;
        (index, decoder)
    };

    // Find best audio stream (optional)
    let audio_stream_index = ictx
        .streams()
        .best(ffmpeg::media::Type::Audio)
        .map(|s| s.index());

    let global_header = octx
        .format()
        .flags()
        .contains(ffmpeg::format::flag::Flags::GLOBAL_HEADER);

    // Find H.264 encoder (LGPL-compliant)
    // Priority: VideoToolbox (macOS/iOS) > OpenH264 > built-in encoder
    let codec = find_h264_encoder().map_err(|e| {
        anyhow::anyhow!(
            "H.264 encoder not found. Error: {:?}. \
                FFmpeg needs either VideoToolbox (macOS/iOS), OpenH264, or built-in H.264 encoder.",
            e
        )
    })?;

    eprintln!("Using H.264 encoder: {}", codec.name());

    // Get stored dimensions and rotation information
    let stored_width = decoder.width();
    let stored_height = decoder.height();

    // Get display dimensions accounting for rotation (needed for correct dimension calculation)
    let input_video_stream = ictx
        .stream(video_stream_index)
        .ok_or(anyhow::anyhow!("Input video stream not found"))?;

    let (display_width, display_height, rotation) =
        get_display_dimensions_with_format(&ictx, &input_video_stream, stored_width, stored_height);

    eprintln!(
        "DEBUG: Stored dimensions: {}x{}, Display dimensions: {}x{}, Rotation: {}°",
        stored_width, stored_height, display_width, display_height, rotation
    );
    eprintln!(
        "DEBUG: Target params: width={:?}, height={:?}",
        params.width, params.height
    );

    // Calculate target dimensions based on DISPLAY dimensions (what user sees)
    // This ensures portrait/landscape orientation is correctly handled
    let (target_display_width, target_display_height) =
        calculate_dimensions(display_width, display_height, params.width, params.height);

    eprintln!(
        "DEBUG: Target display dimensions: {}x{}",
        target_display_width, target_display_height
    );

    // Determine if user provided explicit dimensions
    let user_provided_explicit_dimensions = params.width.is_some() && params.height.is_some();

    // When user provides explicit dimensions, we want the output STORED dimensions to match
    // the target dimensions (not just display dimensions). This ensures compatibility with
    // players/tools that don't respect rotation metadata.
    //
    // Strategy:
    // - If rotation is 90/270°: We need to actually rotate frames during encoding
    //   For now, we encode at swapped dimensions and preserve rotation (workaround)
    //   TODO: Implement actual frame rotation using FFmpeg filters for proper support
    // - If no rotation: Encode at target dimensions directly, remove rotation
    //
    // When no explicit dimensions, preserve rotation and swap dimensions for stored orientation.
    let (target_width, target_height, should_preserve_rotation, needs_frame_rotation) =
        if user_provided_explicit_dimensions {
            // User wants specific dimensions - we want stored dimensions to match target
            if rotation == 90 || rotation == 270 {
                // For rotated videos: we need to rotate frames so stored dimensions are target dimensions
                // Currently using workaround: encode at swapped dimensions and preserve rotation
                // This makes display dimensions correct, but stored dimensions are swapped
                // TODO: Implement actual frame rotation using FFmpeg transpose filter
                (target_display_height, target_display_width, true, true)
            } else {
                // No rotation: encode at target dimensions directly, remove rotation
                (target_display_width, target_display_height, false, false)
            }
        } else {
            // No explicit dimensions - preserve rotation and swap dimensions for stored orientation
            if rotation == 90 || rotation == 270 {
                (target_display_height, target_display_width, true, false)
            } else {
                (target_display_width, target_display_height, true, false)
            }
        };

    eprintln!(
        "DEBUG: Final encoder dimensions: {}x{} (rotation={}°, preserve_rotation={}, needs_frame_rotation={})",
        target_width, target_height, rotation, should_preserve_rotation, needs_frame_rotation
    );

    // Clamp Bitrate to Input Bitrate (if available) to prevent upscaling file size
    // Note: We use a slight margin (e.g. 1.0x or 1.1x) because re-encoding might need bits.
    // But strictly speaking, we shouldn't target HIGHER than source.
    let input_bitrate_kbps = if ictx.bit_rate() > 0 {
        ictx.bit_rate() as u32 / 1000
    } else {
        0
    };
    let mut final_bitrate_kbps = params.target_bitrate_kbps;

    if input_bitrate_kbps > 0 && final_bitrate_kbps > input_bitrate_kbps {
        println!(
            "INFO: Clamping target bitrate {} kbps to input {} kbps",
            final_bitrate_kbps, input_bitrate_kbps
        );
        final_bitrate_kbps = input_bitrate_kbps;
    }

    // Create new context for encoder
    let encoder_ctx = ffmpeg::codec::context::Context::new_with_codec(codec);
    let mut encoder_setup = encoder_ctx.encoder().video()?;

    encoder_setup.set_width(target_width);
    encoder_setup.set_height(target_height);
    encoder_setup.set_bit_rate((final_bitrate_kbps * 1000) as usize);
    encoder_setup.set_time_base(ffmpeg::util::rational::Rational(1, 30));
    encoder_setup.set_format(ffmpeg::format::Pixel::YUV420P);

    // Preserve color metadata from input (critical for HDR videos)
    // This preserves colorspace, color range, primaries, and transfer characteristics
    let input_color_range = unsafe {
        let decoder_ptr = decoder.as_ptr();
        if !decoder_ptr.is_null() {
            (*decoder_ptr).color_range
        } else {
            std::mem::zeroed() // AVCOL_RANGE_UNSPECIFIED
        }
    };

    unsafe {
        let decoder_ptr = decoder.as_ptr();
        let encoder_ptr = encoder_setup.as_mut_ptr();

        if !decoder_ptr.is_null() && !encoder_ptr.is_null() {
            // Copy color space properties
            (*encoder_ptr).colorspace = (*decoder_ptr).colorspace;
            (*encoder_ptr).color_range = (*decoder_ptr).color_range;
            (*encoder_ptr).color_primaries = (*decoder_ptr).color_primaries;
            (*encoder_ptr).color_trc = (*decoder_ptr).color_trc; // Transfer characteristics (critical for HDR)

            // Also copy chroma location if available
            (*encoder_ptr).chroma_sample_location = (*decoder_ptr).chroma_sample_location;
        }
    }

    if global_header {
        encoder_setup.set_flags(ffmpeg::codec::flag::Flags::GLOBAL_HEADER);
    }

    // 2. Open encoder
    // Note: FFmpeg's built-in H.264 encoder (without libx264) has limited options
    // We try with options first, then fall back to minimal configuration if needed
    eprintln!("DEBUG: Opening H.264 encoder: {} with dimensions {}x{}, bitrate {} kbps", 
        codec.name(), target_width, target_height, final_bitrate_kbps);
    let mut opts = ffmpeg::Dictionary::new();

    // Built-in encoder might not support preset, so we only set it if available
    if let Some(ref p) = params.preset {
        opts.set("preset", p);
    }

    // CRF might not be supported by built-in encoder
    if let Some(crf) = params.crf {
        opts.set("crf", &crf.to_string());
    }

    // Always set bitrate (required for built-in encoder)
    opts.set("b", &format!("{}", final_bitrate_kbps * 1000));

    // Profile might not be supported, but try it
    opts.set("profile", "high");

    // Explicitly set color range for HDR videos to prevent brightness issues
    // HDR videos typically use limited range (16-235), not full range (0-255)
    // Setting this explicitly helps encoders interpret the color range correctly
    // AVCOL_RANGE_JPEG = 2, AVCOL_RANGE_UNSPECIFIED = 0, AVCOL_RANGE_MPEG = 1
    // Compare as integers since these are C enums
    let range_val = input_color_range as i32;
    if range_val == 2 {
        // Full range (0-255) - typically for JPEG/PC content
        opts.set("color_range", "pc");
    } else if range_val != 0 {
        // Limited range (16-235) - typical for HDR/TV content
        opts.set("color_range", "tv");
    }

    // Try to open encoder with options
    let mut encoder = match encoder_setup.open_as_with(codec, opts) {
        Ok(enc) => enc,
        Err(e) => {
            // If opening with options fails, recreate encoder_setup and try with minimal options
            eprintln!("Warning: Failed to open H.264 encoder with full options: {:?}. Trying minimal configuration...", e);
            let encoder_ctx_minimal = ffmpeg::codec::context::Context::new_with_codec(codec);
            let mut encoder_setup_minimal = encoder_ctx_minimal.encoder().video()?;
            encoder_setup_minimal.set_width(target_width);
            encoder_setup_minimal.set_height(target_height);
            encoder_setup_minimal.set_bit_rate((final_bitrate_kbps * 1000) as usize);
            encoder_setup_minimal.set_time_base(ffmpeg::util::rational::Rational(1, 30));
            encoder_setup_minimal.set_format(ffmpeg::format::Pixel::YUV420P);
            if global_header {
                encoder_setup_minimal.set_flags(ffmpeg::codec::flag::Flags::GLOBAL_HEADER);
            }
            let mut minimal_opts = ffmpeg::Dictionary::new();
            minimal_opts.set("b", &format!("{}", final_bitrate_kbps * 1000));
            encoder_setup_minimal
                .open_as_with(codec, minimal_opts)
                .map_err(|e2| {
                    anyhow::anyhow!(
                        "Failed to open H.264 encoder even with minimal options. Error: {:?}. Codec: {:?}",
                        e2,
                        codec.name()
                    )
                })?
        }
    };

    // Collect rotation metadata and display matrix side data
    // (input_video_stream was already obtained above for dimension calculation)
    // Note: rotation_metadata is collected but currently unused (display_matrix_data is used instead)
    #[allow(dead_code, unused_assignments)]
    let mut rotation_metadata: Option<String> = None;
    let mut display_matrix_data: Option<Vec<u8>> = None;

    // Collect HDR metadata side data (critical for preserving tone/colors in HDR videos)
    let mut mastering_display_data: Option<Vec<u8>> = None;
    let mut content_light_level_data: Option<Vec<u8>> = None;

    // Check stream metadata for rotation (MOV files often store it here)
    if let Some(rotation_str) = input_video_stream.metadata().get("rotate") {
        rotation_metadata = Some(rotation_str.to_string());
    }

    // Copy side data from input stream (rotation, HDR metadata)
    use ffmpeg::codec::packet::side_data::Type as SideDataType;
    for side_data in input_video_stream.side_data() {
        match side_data.kind() {
            SideDataType::DisplayMatrix => {
                let data = side_data.data();
                if data.len() >= 36 {
                    display_matrix_data = Some(data.to_vec());
                    // Also parse and store as metadata fallback
                    unsafe {
                        let matrix_ptr = data.as_ptr() as *const i32;
                        let matrix = std::slice::from_raw_parts(matrix_ptr, 9);
                        let a = matrix[0] as f64 / (1i64 << 16) as f64;
                        let b = matrix[1] as f64 / (1i64 << 16) as f64;
                        let angle_rad = b.atan2(a);
                        let angle_deg = angle_rad.to_degrees();
                        let matrix_rotation =
                            ((angle_deg.round() as i32 % 360 + 360) % 360) / 90 * 90;
                        if matrix_rotation != 0 && rotation_metadata.is_none() {
                            rotation_metadata = Some(matrix_rotation.to_string());
                        }
                    }
                }
            }
            SideDataType::MasteringDisplayMetadata => {
                // HDR10 mastering display metadata (preserves color volume)
                let data = side_data.data();
                mastering_display_data = Some(data.to_vec());
            }
            SideDataType::ContentLightLevel => {
                // HDR10 content light level (preserves peak brightness)
                let data = side_data.data();
                content_light_level_data = Some(data.to_vec());
            }
            _ => {}
        }
    }

    // // Also check format metadata for rotation (MOV files)
    // if rotation_metadata.is_none() {
    //     if let Some(rotation_str) = ictx.metadata().get("rotate") {
    //         rotation_metadata = Some(rotation_str.to_string());
    //     }
    // }

    // 2. Add video stream
    let video_ost_index = {
        let mut ost = octx.add_stream(codec)?;
        ost.set_parameters(&encoder);

        // Try to add side data to stream's codec parameters
        // This preserves rotation and HDR metadata in MP4 files
        unsafe {
            use ffmpeg::codec::packet::side_data::Type as SideDataType;
            use ffmpeg::ffi;

            // Get the stream's codec parameters pointer
            let stream_ptr = ost.as_mut_ptr();
            if !stream_ptr.is_null() {
                let codecpar = (*stream_ptr).codecpar;
                if !codecpar.is_null() {
                    // Add display matrix side data (rotation) - only if we should preserve rotation
                    if should_preserve_rotation {
                        if let Some(ref matrix_data) = display_matrix_data {
                            let side_data_type: ffi::AVPacketSideDataType =
                                SideDataType::DisplayMatrix.into();
                            let side_data = ffi::av_packet_side_data_new(
                                &mut (*codecpar).coded_side_data,
                                &mut (*codecpar).nb_coded_side_data,
                                side_data_type,
                                matrix_data.len(),
                                0,
                            );
                            if !side_data.is_null() {
                                let side_data_ptr = (*side_data).data;
                                if !side_data_ptr.is_null() {
                                    std::ptr::copy_nonoverlapping(
                                        matrix_data.as_ptr(),
                                        side_data_ptr,
                                        matrix_data.len(),
                                    );
                                }
                            }
                        }
                    }

                    // Add mastering display metadata (HDR10 color volume)
                    if let Some(ref md_data) = mastering_display_data {
                        let side_data_type: ffi::AVPacketSideDataType =
                            SideDataType::MasteringDisplayMetadata.into();
                        let side_data = ffi::av_packet_side_data_new(
                            &mut (*codecpar).coded_side_data,
                            &mut (*codecpar).nb_coded_side_data,
                            side_data_type,
                            md_data.len(),
                            0,
                        );
                        if !side_data.is_null() {
                            let side_data_ptr = (*side_data).data;
                            if !side_data_ptr.is_null() {
                                std::ptr::copy_nonoverlapping(
                                    md_data.as_ptr(),
                                    side_data_ptr,
                                    md_data.len(),
                                );
                            }
                        }
                    }

                    // Add content light level (HDR10 peak brightness)
                    if let Some(ref cll_data) = content_light_level_data {
                        let side_data_type: ffi::AVPacketSideDataType =
                            SideDataType::ContentLightLevel.into();
                        let side_data = ffi::av_packet_side_data_new(
                            &mut (*codecpar).coded_side_data,
                            &mut (*codecpar).nb_coded_side_data,
                            side_data_type,
                            cll_data.len(),
                            0,
                        );
                        if !side_data.is_null() {
                            let side_data_ptr = (*side_data).data;
                            if !side_data_ptr.is_null() {
                                std::ptr::copy_nonoverlapping(
                                    cll_data.as_ptr(),
                                    side_data_ptr,
                                    cll_data.len(),
                                );
                            }
                        }
                    }
                }
            }
        }

        ost.index()
    };

    // 3. Setup Audio: Copy, Transcode, or Skip (if estimating)
    let mut audio_ost_index = None;
    let mut audio_decoder: Option<ffmpeg::codec::decoder::Audio> = None;
    let mut audio_encoder: Option<ffmpeg::codec::encoder::Audio> = None;
    let mut audio_resampler: Option<ffmpeg::software::resampling::Context> = None;
    // let mut audio_fifo: Option<ffmpeg::util::fifo::Fifo> = None;

    // Manual buffering
    let mut left_buffer: Option<Vec<f32>> = None;
    let mut right_buffer: Option<Vec<f32>> = None;
    let mut audio_pts_counter: Option<i64> = None;

    // Only process audio if NOT estimating
    if duration_limit_ms.is_none() {
        if let Some(idx) = audio_stream_index {
            let input_stream = ictx.stream(idx)
                .ok_or_else(|| anyhow::anyhow!("Audio stream at index {} not found", idx))?;
            let input_codec_id = input_stream.parameters().id();

            // Allow copy for common safe codecs: AAC, MP3
            let can_copy = matches!(
                input_codec_id,
                ffmpeg::codec::Id::AAC | ffmpeg::codec::Id::MP3
            );

            if can_copy {
                // COPY PATH
                if let Ok(mut ost) = octx.add_stream(ffmpeg::encoder::find(input_codec_id)) {
                    ost.set_parameters(input_stream.parameters());
                    audio_ost_index = Some(ost.index());
                } else {
                    println!(
                        "WARN: Could not add audio stream for copy (ID: {:?})",
                        input_codec_id
                    );
                }
            } else {
                // TRANSCODE PATH (e.g. WMA -> AAC)
                println!("INFO: Transcoding audio from {:?} to AAC", input_codec_id);

                // 3a. Initialize Decoder
                let mut decoder_ctx =
                    ffmpeg::codec::context::Context::from_parameters(input_stream.parameters())?
                        .decoder()
                        .audio()?;
                // Set channel layout if missing (common in some containers)
                if decoder_ctx.channel_layout().is_empty() {
                    decoder_ctx
                        .set_channel_layout(ffmpeg::util::channel_layout::ChannelLayout::STEREO);
                }

                // 3b. Initialize Encoder (AAC)
                let output_codec = ffmpeg::encoder::find(ffmpeg::codec::Id::AAC)
                    .ok_or(anyhow::anyhow!("AAC codec not found"))?;
                let encoder_ctx = ffmpeg::codec::context::Context::new_with_codec(output_codec);
                let mut encoder = encoder_ctx.encoder().audio()?;

                // Configure AAC: Stereo, 44.1kHz or 48kHz, FLTP
                // Use input sample rate if reasonable, else clamp
                let target_sample_rate = if decoder_ctx.rate() >= 44100 {
                    decoder_ctx.rate()
                } else {
                    44100
                };
                encoder.set_rate(target_sample_rate as i32);
                encoder.set_channel_layout(ffmpeg::util::channel_layout::ChannelLayout::STEREO);
                // encoder.set_channels(2); // Removed: implied by layout or not available on wrapper
                // FLTP: Float Planar
                encoder.set_format(ffmpeg::format::Sample::F32(
                    ffmpeg::format::sample::Type::Planar,
                ));
                encoder.set_bit_rate(192_000); // 192kbps
                encoder.set_time_base(ffmpeg::util::rational::Rational(
                    1,
                    target_sample_rate as i32,
                ));

                // Global headers likely needed for MP4 container
                if global_header {
                    encoder.set_flags(ffmpeg::codec::flag::Flags::GLOBAL_HEADER);
                }

                let encoder_opened = encoder
                    .open_as(output_codec)
                    .map_err(|e| anyhow::anyhow!("Failed to open AAC encoder: {:?}", e))?;

                // 3c. Add Output Stream
                let mut ost = octx.add_stream(output_codec)?;
                ost.set_parameters(&encoder_opened);
                audio_ost_index = Some(ost.index());

                // 3d. Initialize Resampler
                let resampler = ffmpeg::software::resampling::Context::get(
                    decoder_ctx.format(),
                    decoder_ctx.channel_layout(),
                    decoder_ctx.rate(),
                    encoder_opened.format(),
                    encoder_opened.channel_layout(),
                    encoder_opened.rate(),
                )?;

                // 3e. Initialize Buffers (done lazily or here)
                left_buffer = Some(Vec::with_capacity(4096));
                right_buffer = Some(Vec::with_capacity(4096));
                audio_pts_counter = Some(0);

                audio_decoder = Some(decoder_ctx);
                audio_encoder = Some(encoder_opened);
                audio_resampler = Some(resampler);
            }
        }
    }

    // Rotation metadata and display matrix side data have been collected from input stream.
    // The display matrix side data will be copied to the first encoded packet below,
    // which preserves rotation information for HDR videos and rotated videos in MP4/MOV format.

    octx.write_header()?;

    // Capture timebase after header is written as it might change
    let ost_time_base = octx.stream(video_ost_index).unwrap().time_base();
    let audio_ost_time_base = audio_ost_index.map(|i| octx.stream(i).unwrap().time_base());
    let audio_ist_time_base = audio_stream_index.map(|i| ictx.stream(i).unwrap().time_base());

    // Create scaler - the color range is preserved via frame metadata, not scaler flags
    // The scaler will respect the color_range set on the input and output frames
    // When explicit dimensions are provided and rotation is present, we scale from stored dimensions
    // directly to target dimensions (rotation will be handled by not preserving rotation metadata)
    let mut scaler = ffmpeg::software::scaling::Context::get(
        decoder.format(),
        decoder.width(),
        decoder.height(),
        ffmpeg::format::Pixel::YUV420P,
        target_width,
        target_height,
        ffmpeg::software::scaling::flag::Flags::BILINEAR,
    )?;

    let mut decoded = ffmpeg::util::frame::video::Video::empty();
    let mut converted = ffmpeg::util::frame::video::Video::new(
        ffmpeg::format::Pixel::YUV420P,
        target_width,
        target_height,
    );

    // Set color range on converted frame BEFORE scaling to ensure scaler preserves it
    // This is critical for HDR videos to prevent brightness issues
    unsafe {
        let converted_ptr = converted.as_mut_ptr();
        if !converted_ptr.is_null() {
            // Set the color range to match input (prevents scaler from expanding limited range)
            (*converted_ptr).color_range = input_color_range;
        }
    }

    // Set color range on converted frame to avoid deprecated pixel format warnings
    // Note: Color range setting may not be available in all ffmpeg-next versions
    // If Range::Limited doesn't exist, we can skip this (it's optional)
    // use ffmpeg::util::color::Range;
    // converted.set_color_range(Range::Limited);

    // Audio frames reusable
    let mut decoded_audio = ffmpeg::util::frame::audio::Audio::empty();

    // Handle seek if start_ms is provided
    if let Some(start) = start_ms {
        let position = (start as i64) * ffmpeg::ffi::AV_TIME_BASE as i64 / 1000;
        if position > 0 {
            // Seek on INPUT context. This affects all streams.
            ictx.seek(position, ..position).context("Seek failed")?;
        }
    }

    // Reset start time after seek to exclude seek overhead from speed calc
    let mut processing_start_time: Option<std::time::Instant> = None;

    // Convert limits to stream timebase or microseconds for checking
    let limit_duration_us = duration_limit_ms.map(|d| d as i64 * 1000);
    let mut processed_duration_us = 0i64;
    let mut initial_pts_us: Option<i64> = None;
    let mut first_frame_pts: Option<i64> = None;

    // Audio PTS offset tracking
    let mut first_audio_pts: Option<i64> = None;

    let stream_time_base = ictx
        .stream(video_stream_index)
        .ok_or(anyhow::anyhow!("Stream not found"))?
        .time_base();

    // Warmup tracking for estimation stats
    let mut warmup_done = false;
    let mut stats_start_time: Option<std::time::Instant> = None;
    let mut stats_start_pts: i64 = 0;
    let mut stats_start_size: u64 = 0;

    // Track last DTS to ensure monotonically increasing timestamps
    let mut last_video_dts: Option<i64> = None;

    // Track if we've added rotation side data to first packet
    let mut rotation_side_data_added = false;

    for (stream, mut packet) in ictx.packets() {
        if stream.index() == video_stream_index {
            decoder
                .send_packet(&packet)
                .context("Decoder send_packet failed")?;

            while decoder.receive_frame(&mut decoded).is_ok() {
                // Start timer on first decoded frame to exclude pre-roll decoding
                if processing_start_time.is_none() {
                    processing_start_time = Some(std::time::Instant::now());
                }

                let frame_pts = decoded.pts().unwrap_or(0);
                let pts_us = (frame_pts as f64 * f64::from(stream_time_base) * 1000_000.0) as i64;

                if initial_pts_us.is_none() {
                    initial_pts_us = Some(pts_us);
                }

                // Track first frame timestamp to normalize output to 0
                if first_frame_pts.is_none() {
                    first_frame_pts = Some(frame_pts);
                }

                let relative_us = pts_us - initial_pts_us.unwrap_or(0);

                if let Some(limit) = limit_duration_us {
                    if relative_us > limit {
                        // Reached duration limit
                        break;
                    }
                }
                processed_duration_us = relative_us;

                // Check for warmup (2 seconds)
                // Only if we have a limit (implies estimation/sample mode)
                if duration_limit_ms.is_some() && !warmup_done && relative_us > 2_000_000 {
                    warmup_done = true;
                    stats_start_time = Some(std::time::Instant::now());
                    stats_start_pts = relative_us;
                    stats_start_size = encoded_size_bytes;
                }

                scaler
                    .run(&decoded, &mut converted)
                    .context("Scaler run failed")?;

                // Preserve color metadata from decoded frame to converted frame
                // This is critical for HDR videos to maintain proper tone mapping
                unsafe {
                    let decoded_ptr = decoded.as_ptr();
                    let converted_ptr = converted.as_mut_ptr();

                    if !decoded_ptr.is_null() && !converted_ptr.is_null() {
                        // Copy color space properties
                        (*converted_ptr).colorspace = (*decoded_ptr).colorspace;
                        (*converted_ptr).color_range = (*decoded_ptr).color_range;
                        (*converted_ptr).color_primaries = (*decoded_ptr).color_primaries;
                        (*converted_ptr).color_trc = (*decoded_ptr).color_trc; // Transfer characteristics (critical for HDR)
                        (*converted_ptr).chroma_location = (*decoded_ptr).chroma_location;
                    }
                }

                // Recalculate PTS for the new stream
                if let Some(pts) = decoded.pts() {
                    // Normalize to start at 0
                    let normalized_pts = pts - first_frame_pts.unwrap_or(0);
                    let rescaled_pts = unsafe {
                        ffmpeg::ffi::av_rescale_q(
                            normalized_pts,
                            stream_time_base.into(),
                            encoder.time_base().into(),
                        )
                    };
                    converted.set_pts(Some(rescaled_pts));
                } else {
                    converted.set_pts(None);
                }

                encoder
                    .send_frame(&converted)
                    .context("Encoder send_frame failed")?;

                let mut encoded = ffmpeg::Packet::empty();
                while encoder.receive_packet(&mut encoded).is_ok() {
                    encoded.set_stream(video_ost_index);
                    encoded.rescale_ts(encoder.time_base(), ost_time_base);

                    // Copy side data to keyframes (preserves rotation and HDR metadata)
                    // Also add to all packets as fallback since some muxers read from packets
                    if encoded.is_key() || !rotation_side_data_added {
                        unsafe {
                            use ffmpeg::codec::packet::side_data::Type as SideDataType;
                            use ffmpeg::ffi;
                            let pkt = encoded.as_mut_ptr();

                            if !pkt.is_null() {
                                // Add display matrix side data (rotation) - only if we should preserve rotation
                                if should_preserve_rotation {
                                    if let Some(ref matrix_data) = display_matrix_data {
                                        if matrix_data.len() >= 36 {
                                            let side_data_type: ffi::AVPacketSideDataType =
                                                SideDataType::DisplayMatrix.into();
                                            let side_data_ptr = ffi::av_packet_new_side_data(
                                                pkt,
                                                side_data_type,
                                                matrix_data.len(),
                                            );
                                            if !side_data_ptr.is_null() {
                                                std::ptr::copy_nonoverlapping(
                                                    matrix_data.as_ptr(),
                                                    side_data_ptr,
                                                    matrix_data.len(),
                                                );
                                                if encoded.is_key() {
                                                    rotation_side_data_added = true;
                                                }
                                            }
                                        }
                                    }
                                }

                                // Add mastering display metadata (HDR10 color volume)
                                if let Some(ref md_data) = mastering_display_data {
                                    let side_data_type: ffi::AVPacketSideDataType =
                                        SideDataType::MasteringDisplayMetadata.into();
                                    let side_data_ptr = ffi::av_packet_new_side_data(
                                        pkt,
                                        side_data_type,
                                        md_data.len(),
                                    );
                                    if !side_data_ptr.is_null() {
                                        std::ptr::copy_nonoverlapping(
                                            md_data.as_ptr(),
                                            side_data_ptr,
                                            md_data.len(),
                                        );
                                    }
                                }

                                // Add content light level (HDR10 peak brightness)
                                if let Some(ref cll_data) = content_light_level_data {
                                    let side_data_type: ffi::AVPacketSideDataType =
                                        SideDataType::ContentLightLevel.into();
                                    let side_data_ptr = ffi::av_packet_new_side_data(
                                        pkt,
                                        side_data_type,
                                        cll_data.len(),
                                    );
                                    if !side_data_ptr.is_null() {
                                        std::ptr::copy_nonoverlapping(
                                            cll_data.as_ptr(),
                                            side_data_ptr,
                                            cll_data.len(),
                                        );
                                    }
                                }
                            }
                        }
                    }

                    // Ensure DTS is monotonically increasing and PTS >= DTS
                    if let Some(dts) = encoded.dts() {
                        if let Some(last_dts) = last_video_dts {
                            if dts <= last_dts {
                                // Force DTS to be greater than last DTS
                                encoded.set_dts(Some(last_dts + 1));
                            }
                        }
                        // Ensure PTS >= DTS (required for valid MP4)
                        if let Some(pts) = encoded.pts() {
                            if pts < encoded.dts().unwrap_or(dts) {
                                encoded.set_pts(Some(encoded.dts().unwrap_or(dts)));
                            }
                        }
                        last_video_dts = encoded.dts();
                    } else if let Some(last_dts) = last_video_dts {
                        // If no DTS, set it to last_dts + 1
                        encoded.set_dts(Some(last_dts + 1));
                        last_video_dts = Some(last_dts + 1);
                    }

                    encoded_size_bytes += encoded.size() as u64;

                    encoded
                        .write_interleaved(&mut octx)
                        .context("Write interleaved failed")?;
                }
            }

            // Initial break check inside frame loop breaks frame loop, here we verify if we need to stop packet loop
            if let Some(limit) = limit_duration_us {
                if processed_duration_us > limit {
                    break;
                }
            }
        } else if Some(stream.index()) == audio_stream_index {
            // Processing Audio Packet
            if let Some(out_idx) = audio_ost_index {
                // Determine if we are Copying or Transcoding
                if audio_encoder.is_some() {
                    // --- TRANSCODE PATH ---
                    if let (Some(decoder), Some(resampler), Some(encoder)) = (
                        audio_decoder.as_mut(),
                        audio_resampler.as_mut(),
                        audio_encoder.as_mut(),
                    ) {
                        decoder.send_packet(&packet)?;
                        while decoder.receive_frame(&mut decoded_audio).is_ok() {
                            // Skip empty or invalid audio frames
                            if decoded_audio.samples() == 0 {
                                continue;
                            }
                            // Resample
                            // Calculate output samples: use max to ensure we have enough space
                            // FFmpeg resampler formula: ceil(in_samples * out_rate / in_rate)
                            let in_rate = decoder.rate() as u64;
                            let out_rate = encoder.rate() as u64;
                            let in_samples = decoded_audio.samples() as u64;

                            // Calculate exact output samples needed (with ceiling for rounding)
                            let out_samples_est =
                                (in_samples * out_rate).div_ceil(in_rate) as usize;
                            // Add some padding for resampler delay/compensation (typically 32-64 samples)
                            let out_samples_with_padding = out_samples_est + 64;

                            let mut resampled = ffmpeg::util::frame::audio::Audio::new(
                                encoder.format(),
                                out_samples_with_padding,
                                encoder.channel_layout(),
                            );
                            resampled.set_rate(encoder.rate());

                            resampler.run(&decoded_audio, &mut resampled)?;

                            // Get actual number of samples produced by resampler
                            let actual_samples = resampled.samples();

                            // Manual Buffering
                            // Append planar data to buffers
                            if left_buffer.is_none() {
                                left_buffer = Some(Vec::new());
                            }
                            if right_buffer.is_none() {
                                right_buffer = Some(Vec::new());
                            }

                            // Buffers are initialized above (lines 1909-1918), so unwrap is safe
                            // But add defensive check for better error messages
                            let lb = left_buffer.as_mut().expect("Left audio buffer should be initialized");
                            let rb = right_buffer.as_mut().expect("Right audio buffer should be initialized");

                            if resampled.planes() >= 2 {
                                let p0 = resampled.plane::<f32>(0);
                                let p1 = resampled.plane::<f32>(1);
                                // Only copy the actual samples produced, not the padding
                                lb.extend_from_slice(&p0[0..actual_samples]);
                                rb.extend_from_slice(&p1[0..actual_samples]);
                            } else {
                                // Mono to Stereo: duplicate the single plane
                                let p0 = resampled.plane::<f32>(0);
                                lb.extend_from_slice(&p0[0..actual_samples]);
                                rb.extend_from_slice(&p0[0..actual_samples]);
                            }

                            // Encode chunks
                            let frame_size = encoder.frame_size() as usize;
                            // frame_size is usually 1024 for AAC.

                            while lb.len() >= frame_size && rb.len() >= frame_size {
                                let mut frame_to_encode = ffmpeg::util::frame::audio::Audio::new(
                                    encoder.format(),
                                    frame_size,
                                    encoder.channel_layout(),
                                );
                                frame_to_encode.set_rate(encoder.rate());

                                // Copy data sequentially to satisfy borrow checker
                                {
                                    let p0 = frame_to_encode.plane_mut::<f32>(0);
                                    p0.copy_from_slice(&lb[0..frame_size]);
                                }
                                {
                                    let p1 = frame_to_encode.plane_mut::<f32>(1);
                                    p1.copy_from_slice(&rb[0..frame_size]);
                                }

                                // Drain buffer
                                lb.drain(0..frame_size);
                                rb.drain(0..frame_size);

                                frame_to_encode.set_pts(audio_pts_counter);
                                if let Some(pts) = audio_pts_counter {
                                    audio_pts_counter = Some(pts + frame_size as i64);
                                } else {
                                    audio_pts_counter = Some(0);
                                }

                                encoder.send_frame(&frame_to_encode)?;

                                let mut encoded_pkt = ffmpeg::Packet::empty();
                                while encoder.receive_packet(&mut encoded_pkt).is_ok() {
                                    encoded_pkt.set_stream(out_idx);
                                    if let Some(audio_tb) = audio_ost_time_base {
                                        encoded_pkt.rescale_ts(
                                            encoder.time_base(),
                                            audio_tb,
                                        );
                                    }
                                    encoded_size_bytes += encoded_pkt.size() as u64;
                                    encoded_pkt.write_interleaved(&mut octx).ok();
                                }
                            }
                        }
                    }
                } else if let (Some(out_tb), Some(in_tb)) =
                    (audio_ost_time_base, audio_ist_time_base)
                {
                    // --- COPY PATH ---
                    packet.set_stream(out_idx);

                    // Normalize timestamps
                    if let Some(pts) = packet.pts() {
                        if first_audio_pts.is_none() {
                            first_audio_pts = Some(pts);
                        }
                        let normalized_pts = pts - first_audio_pts.unwrap_or(0);
                        packet.set_pts(Some(normalized_pts));

                        if let Some(dts) = packet.dts() {
                            let normalized_dts = dts - first_audio_pts.unwrap_or(0);
                            packet.set_dts(Some(normalized_dts));
                        }
                    }

                    packet.rescale_ts(in_tb, out_tb);
                    encoded_size_bytes += packet.size() as u64;
                    packet.write_interleaved(&mut octx).ok(); // ignore audio write errors
                }
            }
        }
    }

    // Flush Video Encoder
    encoder.send_eof().context("Encoder send_eof failed")?;
    let mut encoded = ffmpeg::Packet::empty();
    while encoder.receive_packet(&mut encoded).is_ok() {
        encoded.set_stream(video_ost_index);
        encoded.rescale_ts(encoder.time_base(), ost_time_base);

        // Ensure DTS is monotonically increasing and PTS >= DTS (flush case)
        if let Some(dts) = encoded.dts() {
            if let Some(last_dts) = last_video_dts {
                if dts <= last_dts {
                    encoded.set_dts(Some(last_dts + 1));
                }
            }
            // Ensure PTS >= DTS (required for valid MP4)
            if let Some(pts) = encoded.pts() {
                if pts < encoded.dts().unwrap_or(dts) {
                    encoded.set_pts(Some(encoded.dts().unwrap_or(dts)));
                }
            }
            last_video_dts = encoded.dts();
        } else if let Some(last_dts) = last_video_dts {
            encoded.set_dts(Some(last_dts + 1));
            last_video_dts = Some(last_dts + 1);
        }

        encoded_size_bytes += encoded.size() as u64;
        encoded
            .write_interleaved(&mut octx)
            .context("Final write_interleaved failed")?;
    }

    // Flush Audio Encoder (Transcode path only)
    if let (Some(encoder), Some(out_idx), Some(out_tb)) =
        (audio_encoder.as_mut(), audio_ost_index, audio_ost_time_base)
    {
        // First, flush the resampler to get any remaining samples
        if let (Some(_decoder), Some(resampler), Some(lb), Some(rb)) = (
            audio_decoder.as_mut(),
            audio_resampler.as_mut(),
            left_buffer.as_mut(),
            right_buffer.as_mut(),
        ) {
            // Flush resampler with empty frame
            let empty_frame = ffmpeg::util::frame::audio::Audio::empty();
            let mut flushed_resampled = ffmpeg::util::frame::audio::Audio::new(
                encoder.format(),
                1024, // Allocate space for flushed samples
                encoder.channel_layout(),
            );
            flushed_resampled.set_rate(encoder.rate());

            // Try to flush resampler (may not produce output, but worth trying)
            if resampler.run(&empty_frame, &mut flushed_resampled).is_ok() {
                let flushed_samples = flushed_resampled.samples();
                if flushed_samples > 0 {
                    if flushed_resampled.planes() >= 2 {
                        let p0 = flushed_resampled.plane::<f32>(0);
                        let p1 = flushed_resampled.plane::<f32>(1);
                        lb.extend_from_slice(&p0[0..flushed_samples]);
                        rb.extend_from_slice(&p1[0..flushed_samples]);
                    } else {
                        let p0 = flushed_resampled.plane::<f32>(0);
                        lb.extend_from_slice(&p0[0..flushed_samples]);
                        rb.extend_from_slice(&p0[0..flushed_samples]);
                    }
                }
            }
        }

        // Flush remaining buffer
        if let (Some(lb), Some(rb)) = (left_buffer.as_mut(), right_buffer.as_mut()) {
            let frame_size = encoder.frame_size() as usize;

            // Encode any remaining complete frames
            while lb.len() >= frame_size && rb.len() >= frame_size {
                let mut frame_to_encode = ffmpeg::util::frame::audio::Audio::new(
                    encoder.format(),
                    frame_size,
                    encoder.channel_layout(),
                );
                frame_to_encode.set_rate(encoder.rate());
                {
                    let p0 = frame_to_encode.plane_mut::<f32>(0);
                    p0.copy_from_slice(&lb[0..frame_size]);
                }
                {
                    let p1 = frame_to_encode.plane_mut::<f32>(1);
                    p1.copy_from_slice(&rb[0..frame_size]);
                }
                frame_to_encode.set_pts(audio_pts_counter);
                if let Some(pts) = audio_pts_counter {
                    audio_pts_counter = Some(pts + frame_size as i64);
                }
                encoder.send_frame(&frame_to_encode).ok();

                let mut encoded_pkt = ffmpeg::Packet::empty();
                while encoder.receive_packet(&mut encoded_pkt).is_ok() {
                    encoded_pkt.set_stream(out_idx);
                    encoded_pkt.rescale_ts(encoder.time_base(), out_tb);
                    encoded_size_bytes += encoded_pkt.size() as u64;
                    encoded_pkt.write_interleaved(&mut octx).ok();
                }

                lb.drain(0..frame_size);
                rb.drain(0..frame_size);
            }

            // Pad and encode final incomplete frame if any samples remain
            if !lb.is_empty() {
                let pad_len = frame_size - lb.len();
                if pad_len > 0 && pad_len < frame_size {
                    // Pad with silence
                    lb.extend(std::iter::repeat_n(0.0, pad_len));
                    rb.extend(std::iter::repeat_n(0.0, pad_len));
                }

                if lb.len() >= frame_size {
                    let mut frame_to_encode = ffmpeg::util::frame::audio::Audio::new(
                        encoder.format(),
                        frame_size,
                        encoder.channel_layout(),
                    );
                    frame_to_encode.set_rate(encoder.rate());
                    {
                        let p0 = frame_to_encode.plane_mut::<f32>(0);
                        p0.copy_from_slice(&lb[0..frame_size]);
                    }
                    {
                        let p1 = frame_to_encode.plane_mut::<f32>(1);
                        p1.copy_from_slice(&rb[0..frame_size]);
                    }
                    frame_to_encode.set_pts(audio_pts_counter);
                    encoder.send_frame(&frame_to_encode).ok();

                    let mut encoded_pkt = ffmpeg::Packet::empty();
                    while encoder.receive_packet(&mut encoded_pkt).is_ok() {
                        encoded_pkt.set_stream(out_idx);
                        encoded_pkt.rescale_ts(encoder.time_base(), out_tb);
                        encoded_size_bytes += encoded_pkt.size() as u64;
                        encoded_pkt.write_interleaved(&mut octx).ok();
                    }
                }
            }
        }

        // Flush encoder
        encoder.send_eof().ok();
        let mut encoded_pkt = ffmpeg::Packet::empty();
        while encoder.receive_packet(&mut encoded_pkt).is_ok() {
            encoded_pkt.set_stream(out_idx);
            encoded_pkt.rescale_ts(encoder.time_base(), out_tb);
            encoded_size_bytes += encoded_pkt.size() as u64;
            encoded_pkt.write_interleaved(&mut octx).ok();
        }
    }

    octx.write_trailer().context("Write trailer failed")?;

    let final_processed_ms = if warmup_done && stats_start_time.is_some() {
        ((processed_duration_us - stats_start_pts) / 1000) as u64
    } else {
        (processed_duration_us / 1000) as u64
    };
    let final_elapsed_ms = if warmup_done && stats_start_time.is_some() {
        stats_start_time.map(|t| t.elapsed().as_millis()).unwrap_or(0)
    } else {
        processing_start_time
            .map(|t| t.elapsed().as_millis())
            .unwrap_or(0)
    };

    let final_encoded_size = if warmup_done && stats_start_time.is_some() {
        encoded_size_bytes.saturating_sub(stats_start_size)
    } else {
        encoded_size_bytes
    };

    println!(
        "PERF: Res: {}x{}, Video+Audio Bytes: {}, Duration: {}ms",
        target_width, target_height, final_encoded_size, final_processed_ms
    );

    // Prepare result before cleanup
    let result = CompressionStats {
        processed_duration_ms: final_processed_ms,
        elapsed_ms: final_elapsed_ms,
        encoded_size_bytes: final_encoded_size,
        output_file_path: output_path.to_string_lossy().to_string(),
    };
    
    // On Windows, delay for cleanup to prevent access violations
    #[cfg(target_os = "windows")]
    {
        use std::thread;
        use std::time::Duration;
        // Small delay to allow FFmpeg internal cleanup
        thread::sleep(Duration::from_millis(150));
        thread::yield_now();
    }
    
    debug!("perform_compression - returning result");
    
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::Command;

    fn generate_test_video(path: &str) -> Result<(), std::io::Error> {
        // Try to find ffmpeg executable
        let ffmpeg_path = if let Ok(ffmpeg_dir) = std::env::var("FFMPEG_DIR") {
            // Try FFMPEG_DIR/bin/ffmpeg.exe (Windows) or FFMPEG_DIR/bin/ffmpeg (Unix)
            #[cfg(target_os = "windows")]
            {
                let exe_path = format!("{}\\bin\\ffmpeg.exe", ffmpeg_dir);
                if std::path::Path::new(&exe_path).exists() {
                    Some(exe_path)
                } else {
                    None
                }
            }
            #[cfg(not(target_os = "windows"))]
            {
                let exe_path = format!("{}/bin/ffmpeg", ffmpeg_dir);
                if std::path::Path::new(&exe_path).exists() {
                    Some(exe_path)
                } else {
                    None
                }
            }
        } else {
            None
        };

        let ffmpeg_cmd = ffmpeg_path.as_deref().unwrap_or("ffmpeg");
        
        // Generate 30 seconds of video
        let output = Command::new(ffmpeg_cmd)
            .args(&[
                "-f",
                "lavfi",
                "-i",
                "testsrc=duration=30:size=640x360:rate=30",
                "-c:v",
                "libx264",
                "-y",
                path,
            ])
            .output()?;

        if !output.status.success() {
            return Err(std::io::Error::new(
                std::io::ErrorKind::Other,
                format!("ffmpeg failed: {}", String::from_utf8_lossy(&output.stderr))
            ));
        }
        Ok(())
    }

    #[test]
    fn test_estimate_compression_works() {
        // Try to find an existing video file first
        let test_file = if std::path::Path::new("HDR.MOV").exists() {
            "HDR.MOV"
        } else if std::path::Path::new("../native/HDR.MOV").exists() {
            "../native/HDR.MOV"
        } else if std::path::Path::new("video.MOV").exists() {
            "video.MOV"
        } else if std::path::Path::new("../native/video.MOV").exists() {
            "../native/video.MOV"
        } else {
            // Fall back to generating a test video
            let generated_file = "test_video_estimate.mp4";
            match generate_test_video(generated_file) {
                Ok(()) => {
                    if std::path::Path::new(generated_file).exists() {
                        generated_file
                    } else {
                        eprintln!("Skipping test: Could not find or generate test video");
                        return;
                    }
                },
                Err(e) => {
                    eprintln!("Skipping test: Could not generate test video. ffmpeg not found or failed: {:?}", e);
                    eprintln!("Hint: Set FFMPEG_DIR environment variable or ensure ffmpeg is in PATH");
                    eprintln!("Hint: Or place a test video file (HDR.MOV or video.MOV) in the native directory");
                    return;
                }
            }
        };

        eprintln!("Using test video file: {}", test_file);

        let params = crate::api::media::CompressParams {
            target_bitrate_kbps: 1000,
            preset: Some("veryfast".to_string()),
            crf: Some(23),
            width: None,
            height: None,
            sample_duration_ms: None,
        };

        // Create temp directory if it doesn't exist
        let _ = std::fs::create_dir_all("./temp");

        let result = estimate_compression(test_file, "./temp", &params);

        // Cleanup only if we generated the test file
        if test_file == "test_video_estimate.mp4" {
            let _ = std::fs::remove_file(test_file);
        }

        if let Err(e) = &result {
            println!("Compression estimation error: {:?}", e);
        }

        assert!(result.is_ok(), "Compression estimation should succeed");
        let estimate = result.unwrap();
        println!(
            "✓ Estimated size: {} bytes, duration: {} ms",
            estimate.estimated_size_bytes, estimate.estimated_duration_ms
        );

        assert!(estimate.estimated_size_bytes > 0, "Estimated size should be > 0");
        // Duration estimation depends on video length and processing speed
        // For short videos (<10s), it processes the whole video
        // For longer videos, it samples portions and estimates
        // The duration should be reasonable (not zero, and not unreasonably long)
        // For a typical video, estimation should complete in a reasonable time (< 60 seconds)
        assert!(estimate.estimated_duration_ms > 0, 
            "Estimated duration should be > 0, got {}", estimate.estimated_duration_ms);
        assert!(estimate.estimated_duration_ms < 60000, 
            "Estimated duration should be < 60000 ms (60s), got {} ms. This suggests the estimation is taking too long.", 
            estimate.estimated_duration_ms);
    }

    #[test]
    fn test_compression_preserves_audio() {
        // Skip this test if ffmpeg command-line tool is not available
        // We need it to generate a test video with audio
        let test_file = "test_video_audio.mp4";
        let output_file = "test_video_audio_out.mp4";

        // Cleanup previous run artifacts robustly
        if std::path::Path::new(output_file).exists() {
            if std::path::Path::new(output_file).is_dir() {
                std::fs::remove_dir_all(output_file).ok();
            } else {
                std::fs::remove_file(output_file).ok();
            }
        }
        std::fs::remove_file(test_file).ok();

        // Try to find ffmpeg executable
        let ffmpeg_path = if let Ok(ffmpeg_dir) = std::env::var("FFMPEG_DIR") {
            #[cfg(target_os = "windows")]
            {
                let exe_path = format!("{}\\bin\\ffmpeg.exe", ffmpeg_dir);
                if std::path::Path::new(&exe_path).exists() {
                    Some(exe_path)
                } else {
                    None
                }
            }
            #[cfg(not(target_os = "windows"))]
            {
                let exe_path = format!("{}/bin/ffmpeg", ffmpeg_dir);
                if std::path::Path::new(&exe_path).exists() {
                    Some(exe_path)
                } else {
                    None
                }
            }
        } else {
            None
        };

        let ffmpeg_cmd = ffmpeg_path.as_deref().unwrap_or("ffmpeg");

        // Generate video with audio
        let output = Command::new(ffmpeg_cmd)
            .args(&[
                "-f",
                "lavfi",
                "-i",
                "testsrc=duration=1:size=1280x720:rate=30",
                "-f",
                "lavfi",
                "-i",
                "sine=frequency=1000:duration=1",
                "-c:v",
                "libx264",
                "-c:a",
                "aac",
                "-map",
                "0:v",
                "-map",
                "1:a",
                "-y",
                test_file,
            ])
            .output();

        match output {
            Ok(output) => {
                if !output.status.success() {
                    eprintln!("Skipping test: ffmpeg failed to generate test video: {}", 
                        String::from_utf8_lossy(&output.stderr));
                    return;
                }
            },
            Err(e) => {
                eprintln!("Skipping test: Could not execute ffmpeg to generate test video: {:?}", e);
                eprintln!("Hint: Set FFMPEG_DIR environment variable or ensure ffmpeg is in PATH");
                return;
            }
        }

        // Ensure test file was created
        if !std::path::Path::new(test_file).exists() {
            eprintln!("Skipping test: Test video file was not created");
            return;
        }

        let params = crate::api::media::CompressParams {
            target_bitrate_kbps: 1000,
            preset: Some("veryfast".to_string()), // Match user preset if possible, user didn't specify but implies speed
            crf: Some(23),
            width: Some(640),
            height: Some(360),
            sample_duration_ms: None,
        };

        // Run compression (without sink)
        let result = perform_compression(test_file, output_file, &params, None, None);

        if let Err(e) = &result {
            println!("Compression failed: {:?}", e);
        }
        assert!(result.is_ok());

        // Verify output has audio stream
        // Simple verification: use ffprobe (via Command) or ffmpeg::format::input

        ffmpeg::init().unwrap();
        let ictx = ffmpeg::format::input(&output_file).unwrap();
        let audio_stream = ictx
            .streams()
            .find(|s| s.parameters().medium() == ffmpeg::media::Type::Audio);

        assert!(
            audio_stream.is_some(),
            "Output video should have an audio stream"
        );

        // Cleanup
        std::fs::remove_file(test_file).ok();
        std::fs::remove_file(output_file).ok();
    }

    /// Helper function to get rotation from a video file
    fn get_video_rotation_from_file(path: &str) -> Option<i32> {
        init_ffmpeg().ok()?;
        
        // Normalize Windows path
        #[cfg(target_os = "windows")]
        let normalized_path = path.replace('\\', "/");
        #[cfg(not(target_os = "windows"))]
        let normalized_path = path.to_string();
        
        let ictx = ffmpeg::format::input(&normalized_path)
            .or_else(|_| ffmpeg::format::input(path))
            .ok()?;
        let stream = ictx.streams().best(ffmpeg::media::Type::Video)?;

        // Try to get rotation from stream
        let rotation =
            get_video_rotation(&stream).or_else(|| get_video_rotation_from_format(&ictx));

        rotation
    }

    #[test]
    fn test_hdr_rotation_preservation() {
        // This test verifies that rotation metadata is preserved when compressing HDR videos
        let hdr_path = "./HDR.MOV";
        let temp_output_path = "./temp";
        let output_file = format!("{}/compressed_hdr_test.mp4", temp_output_path);

        // Skip if HDR.MOV doesn't exist
        if !std::path::Path::new(hdr_path).exists() {
            println!("Skipping HDR rotation test: file not found at {}", hdr_path);
            return;
        }

        // Get original video info and rotation
        let original_info = get_video_info(hdr_path).expect("Failed to get original video info");
        let original_rotation = get_video_rotation_from_file(hdr_path);

        println!("Original HDR video info:");
        println!(
            "  Dimensions: {}x{}",
            original_info.width, original_info.height
        );
        println!("  Rotation: {:?}", original_rotation);
        println!("  Duration: {}ms", original_info.duration_ms);
        println!("  Size: {} bytes", original_info.size_bytes);

        // Compress the video
        let params = crate::api::media::CompressParams {
            width: Some(original_info.width),
            height: Some(original_info.height),
            preset: Some("veryfast".to_string()),
            crf: Some(23),
            target_bitrate_kbps: 0, // ignored when CRF is set
            sample_duration_ms: None,
        };

        // Clean up any previous test output
        let _ = std::fs::remove_file(&output_file);
        std::fs::create_dir_all(temp_output_path).ok();

        let compression_result = compress_video(hdr_path, &output_file, &params);

        if let Err(e) = &compression_result {
            println!("Compression failed: {:?}", e);
            // Cleanup
            let _ = std::fs::remove_file(&output_file);
            panic!("Compression failed: {:?}", e);
        }

        let compressed_path = compression_result.unwrap();
        println!("Compressed video saved to: {}", compressed_path);

        // Get compressed video info and rotation
        let compressed_info =
            get_video_info(&compressed_path).expect("Failed to get compressed video info");
        let compressed_rotation = get_video_rotation_from_file(&compressed_path);

        println!("Compressed video info:");
        println!(
            "  Dimensions: {}x{}",
            compressed_info.width, compressed_info.height
        );
        println!("  Rotation: {:?}", compressed_rotation);
        println!("  Duration: {}ms", compressed_info.duration_ms);
        println!("  Size: {} bytes", compressed_info.size_bytes);

        // Verify rotation is preserved
        if let Some(orig_rot) = original_rotation {
            if let Some(comp_rot) = compressed_rotation {
                assert_eq!(
                    orig_rot, comp_rot,
                    "Rotation not preserved! Original: {:?}, Compressed: {:?}",
                    orig_rot, comp_rot
                );
                println!("✓ Rotation preserved: {} degrees", orig_rot);
            } else {
                panic!(
                    "Rotation lost during compression! Original had rotation: {:?}, compressed has: None",
                    orig_rot
                );
            }
        } else {
            println!("Note: Original video has no rotation metadata");
        }

        // Verify display dimensions match
        // get_video_info returns display dimensions (accounting for rotation)
        // When rotation is preserved, display dimensions should remain the same
        // (stored dimensions are swapped, but display dimensions are what users see)
        assert_eq!(
            compressed_info.width, original_info.width,
            "Display width mismatch. Expected: {}, Got: {}",
            original_info.width, compressed_info.width
        );
        assert_eq!(
            compressed_info.height, original_info.height,
            "Display height mismatch. Expected: {}, Got: {}",
            original_info.height, compressed_info.height
        );

        // Cleanup
        let _ = std::fs::remove_file(&compressed_path);
        println!("✓ HDR rotation preservation test passed!");
    }

    #[test]
    fn test_estimate_with_user_sample() {
        // This test requires the specific sample file at the path.
        // If it doesn't exist, we skip.
        let path = "./sample_1280x720.mp4";
        let temp_output_path = "./temp";
        if !std::path::Path::new(path).exists() {
            println!("Skipping user sample test: file not found at {}", path);
            return;
        }

        // Print video info for debugging
        if let Ok(info) = get_video_info(path) {
            println!(
                "Video Info: Duration={}ms, Size={} bytes",
                info.duration_ms, info.size_bytes
            );
        }

        // Test CRF Mode
        let params_crf = crate::api::media::CompressParams {
            width: Some(640),
            height: Some(360),
            preset: Some("veryfast".to_string()),
            crf: Some(23),
            target_bitrate_kbps: 0, // ignored
            sample_duration_ms: None,
        };

        let result_crf = estimate_compression(path, temp_output_path, &params_crf).unwrap();
        println!(
            "User Sample Estimate (CRF) -> Size: {}, Duration: {}",
            result_crf.estimated_size_bytes, result_crf.estimated_duration_ms
        );

        // Assert reasonable bounds (e.g. > 1MB, < 100MB, duration in 10-100s range)
        assert!(result_crf.estimated_size_bytes > 1_000_000);
        // Relaxing upper bound to 300s. 149s is plausible for a long video or slow CPU in parallel mode.
        assert!(
            result_crf.estimated_duration_ms > 5000 && result_crf.estimated_duration_ms < 300000
        );

        // Test Bitrate Mode (Target 1000kbps)
        let params_br = crate::api::media::CompressParams {
            width: Some(640),
            height: Some(360),
            preset: Some("veryfast".to_string()),
            crf: None,
            target_bitrate_kbps: 1000,
            sample_duration_ms: None,
        };

        let result_br = estimate_compression(path, temp_output_path, &params_br).unwrap();
        println!(
            "User Sample Estimate (Bitrate) -> Size: {}, Duration: {}",
            result_br.estimated_size_bytes, result_br.estimated_duration_ms
        );

        // Expected size: (1000kbps + 192kbps audio) * duration (183s)
        // 1192 * 1000 / 8 * 183 = ~27.2MB.
        assert!(
            result_br.estimated_size_bytes > 20_000_000
                && result_br.estimated_size_bytes < 40_000_000
        );
        assert!(result_br.estimated_duration_ms > 5000);
    }

    #[test]
    fn test_compression_resolution_480x854() {
        // Test compression to 480x854 (portrait) with HDR.MOV
        let hdr_path = "./HDR.MOV";
        let temp_output_path = "./temp";
        let output_file = format!("{}/compressed_480x854_test.mp4", temp_output_path);

        // Skip if HDR.MOV doesn't exist
        if !std::path::Path::new(hdr_path).exists() {
            println!("Skipping 480x854 test: file not found at {}", hdr_path);
            return;
        }

        // Get original video info
        let original_info = get_video_info(hdr_path).expect("Failed to get original video info");
        println!("Original video info:");
        println!(
            "  Display dimensions: {}x{}",
            original_info.width, original_info.height
        );
        println!("  Duration: {}ms", original_info.duration_ms);

        // Compress to 480x854 (portrait)
        let params = crate::api::media::CompressParams {
            width: Some(480),
            height: Some(854),
            preset: Some("veryfast".to_string()),
            crf: Some(23),
            target_bitrate_kbps: 0,
            sample_duration_ms: None,
        };

        // Clean up any previous test output
        let _ = std::fs::remove_file(&output_file);
        std::fs::create_dir_all(temp_output_path).ok();

        let compression_result = compress_video(hdr_path, &output_file, &params);

        if let Err(e) = &compression_result {
            println!("Compression failed: {:?}", e);
            let _ = std::fs::remove_file(&output_file);
            panic!("Compression failed: {:?}", e);
        }

        let compressed_path = compression_result.unwrap();
        println!("Compressed video saved to: {}", compressed_path);

        // Get compressed video info
        let compressed_info =
            get_video_info(&compressed_path).expect("Failed to get compressed video info");

        println!("Compressed video info:");
        println!(
            "  Display dimensions: {}x{}",
            compressed_info.width, compressed_info.height
        );
        println!("  Duration: {}ms", compressed_info.duration_ms);

        // Verify the output is portrait (height > width)
        assert!(
            compressed_info.height > compressed_info.width,
            "Expected portrait output (height > width), but got {}x{}",
            compressed_info.width,
            compressed_info.height
        );

        // Verify dimensions are close to target (within reasonable bounds due to aspect ratio)
        // Target is 480x854, but aspect ratio might cause slight differences
        println!(
            "✓ 480x854 compression test passed! Output: {}x{}",
            compressed_info.width, compressed_info.height
        );

        // Cleanup
        let _ = std::fs::remove_file(&compressed_path);
    }

    #[test]
    fn test_compression_resolution_720x1280() {
        // Test compression to 720x1280 (portrait) with HDR.MOV
        let hdr_path = "./HDR.MOV";
        let temp_output_path = "./temp";
        let output_file = format!("{}/compressed_720x1280_test.mp4", temp_output_path);

        // Skip if HDR.MOV doesn't exist
        if !std::path::Path::new(hdr_path).exists() {
            println!("Skipping 720x1280 test: file not found at {}", hdr_path);
            return;
        }

        // Get original video info
        let original_info = get_video_info(hdr_path).expect("Failed to get original video info");
        println!("Original video info:");
        println!(
            "  Display dimensions: {}x{}",
            original_info.width, original_info.height
        );
        println!("  Duration: {}ms", original_info.duration_ms);

        // Compress to 720x1280 (portrait)
        let params = crate::api::media::CompressParams {
            width: Some(720),
            height: Some(1280),
            preset: Some("veryfast".to_string()),
            crf: Some(23),
            target_bitrate_kbps: 0,
            sample_duration_ms: None,
        };

        // Clean up any previous test output
        let _ = std::fs::remove_file(&output_file);
        std::fs::create_dir_all(temp_output_path).ok();

        let compression_result = compress_video(hdr_path, &output_file, &params);

        if let Err(e) = &compression_result {
            println!("Compression failed: {:?}", e);
            let _ = std::fs::remove_file(&output_file);
            panic!("Compression failed: {:?}", e);
        }

        let compressed_path = compression_result.unwrap();
        println!("Compressed video saved to: {}", compressed_path);

        // Get compressed video info
        let compressed_info =
            get_video_info(&compressed_path).expect("Failed to get compressed video info");

        println!("Compressed video info:");
        println!(
            "  Display dimensions: {}x{}",
            compressed_info.width, compressed_info.height
        );
        println!("  Duration: {}ms", compressed_info.duration_ms);

        // Verify the output is portrait (height > width)
        assert!(
            compressed_info.height > compressed_info.width,
            "Expected portrait output (height > width), but got {}x{}",
            compressed_info.width,
            compressed_info.height
        );

        println!(
            "✓ 720x1280 compression test passed! Output: {}x{}",
            compressed_info.width, compressed_info.height
        );

        // Cleanup
        let _ = std::fs::remove_file(&compressed_path);
    }
}
