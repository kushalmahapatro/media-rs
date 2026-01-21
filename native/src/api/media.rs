use crate::api::video::{self, check_output_path, get_file_name_without_extension};
use crate::frb_generated::StreamSink;
use anyhow::{Context, Error};
use image::{DynamicImage, ImageBuffer, Rgb};
use serde::{Deserialize, Serialize};
use tracing::{debug, error, info};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResolutionPreset {
    pub name: String,
    pub width: u32,
    pub height: u32,
    pub bitrate: u64,
    pub crf: u8,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoInfo {
    pub duration_ms: u64,
    pub width: u32,
    pub height: u32,
    pub size_bytes: u64,
    pub bitrate: Option<u64>,
    pub codec_name: Option<String>,
    pub format_name: Option<String>,
    pub suggestions: Vec<ResolutionPreset>,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
pub enum OutputFormat {
    WEBP,
    JPEG,
    PNG,
}

impl OutputFormat {
    pub fn extension(&self) -> &str {
        match self {
            OutputFormat::WEBP => "webp",
            OutputFormat::JPEG => "jpeg",
            OutputFormat::PNG => "png",
        }
    }
}

/// Represents fixed sizes of a thumbnail
#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
pub enum ThumbnailSizeType {
    Icon,
    Small,
    Medium,
    Large,
    Larger,
    Custom((u32, u32)),
}

impl ThumbnailSizeType {
    pub fn dimensions(&self) -> (u32, u32) {
        match self {
            ThumbnailSizeType::Icon => (64, 64),
            ThumbnailSizeType::Small => (128, 128),
            ThumbnailSizeType::Medium => (256, 256),
            ThumbnailSizeType::Large => (512, 512),
            ThumbnailSizeType::Larger => (1024, 1024),
            ThumbnailSizeType::Custom(size) => *size,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoThumbnailParams {
    pub time_ms: u64,                         // position to grab framen
    pub size_type: Option<ThumbnailSizeType>, // if None, use default size as per the videos aspect ratio
    pub format: Option<OutputFormat>,         // defaults to PNG
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImageThumbnailParams {
    pub size_type: Option<ThumbnailSizeType>, // if None, use default size as per the aspect ratio
    pub format: Option<OutputFormat>,         // defaults to PNG
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompressParams {
    pub target_bitrate_kbps: u32, // target bitrate in kbps
    pub preset: Option<String>,   // e.g. "veryfast"
    pub crf: Option<u8>,          // quality, 0-51, lower is better
    pub width: Option<u32>,       // if None, use original width
    pub height: Option<u32>,
    pub sample_duration_ms: Option<u64>, // if None, use original height
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompressProgress {
    pub processed_ms: u64,
    pub total_ms: u64,
    pub speed_x: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompressionEstimate {
    pub estimated_size_bytes: u64,
    pub estimated_duration_ms: u64,
}

/// Exposed via FRB
pub fn get_video_info(path: String) -> anyhow::Result<VideoInfo> {
    video::get_video_info(&path)
}

pub async fn generate_video_thumbnail(
    path: String,
    output_path: String,
    params: VideoThumbnailParams,
    empty_image_fallback: Option<bool>,
) -> Result<String, Error> {
    let result = video::generate_thumbnail(&path, &params);

    let filename_without_extension = get_file_name_without_extension(&path);
    let base_output_dir = check_output_path(&output_path)?;
    let output_format = params.format.unwrap_or(OutputFormat::PNG);

    let output_file_name = format!(
        "thumbnail_{}_{}.{}",
        filename_without_extension.display(),
        params.time_ms,
        output_format.extension()
    );
    let output_path = base_output_dir.join(output_file_name);
    let output_path_str = output_path.to_string_lossy().to_string();

    match result {
        Ok((thumbnail, _, _)) => {
            std::fs::write(&output_path, thumbnail).with_context(|| {
                format!("Failed to write thumbnail to: {}", output_path.display())
            })?;
            Ok(output_path_str)
        }
        Err((e, w, h)) => {
            error!("Error generating thumbnail (fallback to empty): {:?}", e);
            if empty_image_fallback.unwrap_or(false) {
                let size = if w > 0 && h > 0 {
                    ThumbnailSizeType::Custom((w, h))
                } else {
                    params.size_type.unwrap_or(ThumbnailSizeType::Medium)
                };

                video::generate_empty_thumbnail(size, output_format, &output_path)?;
                Ok(output_path_str)
            } else {
                Err(e)
            }
        }
    }
}

pub fn generate_video_timeline_thumbnails(
    path: String,
    output_path: String,
    params: Option<ImageThumbnailParams>,
    num_thumbnails: u32,
    empty_image_fallback: Option<bool>,
    sink: StreamSink<String>,
) -> anyhow::Result<()> {
    let filename_without_extension = get_file_name_without_extension(&path);
    let base_output_dir = check_output_path(&output_path)?;

    let (output_format, size) = match params {
        Some(params) => (
            params.format.unwrap_or(OutputFormat::PNG),
            params.size_type.unwrap_or(ThumbnailSizeType::Medium),
        ),
        None => (OutputFormat::PNG, ThumbnailSizeType::Medium),
    };

    // Get video info (this acquires and releases the mutex)
    let video_info = video::get_video_info(&path)
        .map_err(|e| anyhow::anyhow!("Failed to get video info for timeline generation: {}", e))?;
    let duration_ms = video_info.duration_ms;
    
    // Validate: num_thumbnails should not exceed duration_ms
    if num_thumbnails > duration_ms as u32 {
        let error = anyhow::anyhow!(
            "Number of thumbnails ({}) cannot exceed video duration ({}ms)",
            num_thumbnails,
            duration_ms
        );
        let _ = sink.add_error(error).map_err(|_| anyhow::anyhow!("Sink closed"))?;
        return Ok(());
    }
    
    // Keep a buffer of 1.5 seconds from the end
    const BUFFER_MS: u64 = 1500; // 1.5 seconds
    let effective_duration_ms = if duration_ms > BUFFER_MS {
        duration_ms - BUFFER_MS
    } else {
        // If video is shorter than buffer, use at least 1ms to avoid division by zero
        duration_ms.max(1)
    };
    
    let time_ms = effective_duration_ms / num_thumbnails as u64;

    // Generate thumbnails sequentially
    // Each generate_thumbnail call will acquire and release the mutex individually
    // This prevents conflicts with other FFmpeg operations
    for i in 0..num_thumbnails {
        let mut time = time_ms * i as u64;
        // Clamp to effective duration (which already has the buffer applied)
        if time > effective_duration_ms {
            time = effective_duration_ms;
        }
        let params = VideoThumbnailParams {
            time_ms: time,
            size_type: Some(size),
            format: Some(output_format),
        };
        // generate_thumbnail will acquire the mutex internally
        let thumbnail = video::generate_thumbnail(&path, &params);
        let output_path = base_output_dir.join(format!(
            "thumbnail_{}_{}.{}",
            filename_without_extension.display(),
            i,
            output_format.extension()
        ));
        let output_path_str = output_path.to_string_lossy().to_string();

        match thumbnail {
            Ok(thumbnail) => {
                std::fs::write(&output_path, thumbnail.0).unwrap();
                sink.add(output_path_str)
                    .map_err(|_| anyhow::anyhow!("Sink closed"))?;
            }
            Err((e, w, h)) => {
                eprintln!("Error generating thumbnail: {:?}", e);
                if empty_image_fallback.unwrap_or(false) {
                    let size = if w > 0 && h > 0 {
                        ThumbnailSizeType::Custom((w, h))
                    } else {
                        size
                    };
                    video::generate_empty_thumbnail(size, output_format, &output_path)?;
                    sink.add(output_path_str)
                        .map_err(|_| anyhow::anyhow!("Sink closed"))?;
                }
            }
        }
    }
    Ok(())
}

pub async fn generate_image_thumbnail(
    path: String,
    output_path: String,
    params: Option<ImageThumbnailParams>,
    suffix: Option<String>,
) -> Result<String, Error> {
    let filename_without_extension = get_file_name_without_extension(&path);
    let base_output_dir = check_output_path(&output_path)?;

    let (output_format, size) = match params {
        Some(params) => (
            params.format.unwrap_or(OutputFormat::PNG),
            params
                .size_type
                .unwrap_or(ThumbnailSizeType::Medium)
                .dimensions(),
        ),
        None => (OutputFormat::PNG, ThumbnailSizeType::Medium.dimensions()),
    };
    let mut suffix = suffix.unwrap_or_default();
    if suffix.is_empty() {
        suffix = "".to_string();
    } else {
        suffix = format!("_{}", suffix);
    }

    let output_file_name = format!(
        "thumbnail_{}{}.{}",
        filename_without_extension.display(),
        suffix,
        output_format.extension()
    );
    let output_path = base_output_dir.join(output_file_name);
    let output_path_str = output_path.to_string_lossy().to_string();

    // Try to decode image - use libheif for HEIC (via image crate integration), FFmpeg for other formats
    // The image crate integration in libheif-rs v2.5+ handles HEIC decoding automatically
    let img = if path.to_lowercase().ends_with(".heic") || path.to_lowercase().ends_with(".heif") {
        // For HEIC files, try image crate first (which will use libheif via integration)
        // If that fails, fall back to direct libheif decoding, then FFmpeg
        match image::open(&path) {
            Ok(img) => img,
            Err(image_err) => {
                // Try direct libheif decoding
                match decode_heic_with_libheif(&path) {
                    Ok(img) => img,
                    Err(heif_err) => {
                        // Fall back to FFmpeg
                        decode_image_with_ffmpeg(&path).with_context(|| {
                            format!(
                                "Failed to decode HEIC image. image crate error: {:?}, libheif error: {:?}",
                                image_err, heif_err
                            )
                        })?
                    }
                }
            }
        }
    } else {
        // For non-HEIC files, try FFmpeg first, then image crate
        match decode_image_with_ffmpeg(&path) {
            Ok(img) => img,
            Err(ffmpeg_err) => {
                // Fall back to image crate for common formats
                image::open(&path).with_context(|| {
                    format!(
                        "Failed to open or decode image file. FFmpeg error: {:?}",
                        ffmpeg_err
                    )
                })?
            }
        }
    };

    let thumbnail = img.thumbnail(size.0, size.1);

    match output_format {
        OutputFormat::JPEG => {
            thumbnail
                .save_with_format(&output_path, image::ImageFormat::Jpeg)
                .context("Failed to save JPEG thumbnail")?;
        }
        OutputFormat::PNG => {
            thumbnail
                .save_with_format(&output_path, image::ImageFormat::Png)
                .context("Failed to save PNG thumbnail")?;
        }
        OutputFormat::WEBP => {
            thumbnail
                .save_with_format(&output_path, image::ImageFormat::WebP)
                .context("Failed to save WebP thumbnail")?;
        }
    }

    Ok(output_path_str)
}

/// Decode HEIC/HEIF images using libheif-rs (more reliable than FFmpeg for HEIC)
fn decode_heic_with_libheif(path: &str) -> Result<DynamicImage, Error> {
    use libheif_rs::{ColorSpace, HeifContext, LibHeif, RgbChroma};

    // Read file into memory
    let data =
        std::fs::read(path).with_context(|| format!("Failed to read HEIC file: {}", path))?;

    // Decode HEIC using libheif
    let ctx = HeifContext::read_from_bytes(&data)
        .with_context(|| format!("Failed to parse HEIC file: {}", path))?;

    let handle = ctx
        .primary_image_handle()
        .with_context(|| format!("Failed to get primary image handle from HEIC: {}", path))?;

    // Create libheif instance for decoding
    let lib_heif = LibHeif::new();

    // Decode to RGB (libheif handles the conversion internally)
    let img = lib_heif
        .decode(&handle, ColorSpace::Rgb(RgbChroma::Rgb), None)
        .with_context(|| format!("Failed to decode HEIC image: {}", path))?;

    let width = img.width();
    let height = img.height();

    // Get the interleaved RGB plane
    let planes = img.planes();
    let plane = planes
        .interleaved
        .ok_or_else(|| anyhow::anyhow!("HEIC image does not have interleaved RGB plane"))?;

    let stride = plane.stride;
    let plane_data = &plane.data;

    // Convert libheif buffer → image crate buffer
    // libheif gives you a buffer with stride; we need tightly-packed RGB
    let mut rgb = Vec::with_capacity((width * height * 3) as usize);
    for y in 0..height {
        let row_start = (y as usize) * stride;
        let row_end = row_start + (width * 3) as usize;
        if row_end <= plane_data.len() {
            rgb.extend_from_slice(&plane_data[row_start..row_end]);
        } else {
            return Err(anyhow::anyhow!(
                "HEIC frame data incomplete: row {} exceeds buffer (stride={}, width={}, data_len={})",
                y, stride, width, plane_data.len()
            ));
        }
    }

    // Create RGB8 image buffer
    let img_buf: ImageBuffer<Rgb<u8>, Vec<u8>> = ImageBuffer::from_raw(width, height, rgb)
        .ok_or_else(|| anyhow::anyhow!("Failed to build image buffer from HEIC data"))?;

    Ok(DynamicImage::ImageRgb8(img_buf))
}

/// Decode an image file using FFmpeg (supports HEIC and other formats not supported by image crate)
#[cfg(test)]
pub fn decode_image_with_ffmpeg(path: &str) -> Result<DynamicImage, Error> {
    decode_image_with_ffmpeg_impl(path)
}

#[cfg(not(test))]
fn decode_image_with_ffmpeg(path: &str) -> Result<DynamicImage, Error> {
    decode_image_with_ffmpeg_impl(path)
}

fn decode_image_with_ffmpeg_impl(path: &str) -> Result<DynamicImage, Error> {
    use ffmpeg_next as ffmpeg;

    ffmpeg::init().context("Failed to initialize ffmpeg")?;

    // Normalize Windows path
    #[cfg(target_os = "windows")]
    let normalized_path = path.replace('\\', "/");
    #[cfg(not(target_os = "windows"))]
    let normalized_path = path.to_string();
    
    let mut ictx = ffmpeg::format::input(&normalized_path)
        .or_else(|_| ffmpeg::format::input(path)) // Fallback to original
        .with_context(|| format!("Failed to open image file with FFmpeg: {}", path))?;

    // Find the best video stream (images are treated as single-frame videos in FFmpeg)
    let stream = ictx
        .streams()
        .best(ffmpeg::media::Type::Video)
        .ok_or_else(|| anyhow::anyhow!("No video/image stream found in file"))?;

    let stream_index = stream.index();
    let context = ffmpeg::codec::context::Context::from_parameters(stream.parameters())?;
    let mut decoder = context.decoder().video()?;

    // Start with decoder dimensions, but track the maximum dimensions from all frames
    // HEIC images may decode with progressive dimensions, so we need to track the largest
    let mut max_width = decoder.width();
    let mut max_height = decoder.height();

    let mut decoded = ffmpeg::util::frame::video::Video::empty();
    let mut frame_decoded = false;

    // Process all packets - HEIC may decode in multiple passes or tiles
    for (stream, packet) in ictx.packets() {
        if stream.index() != stream_index {
            continue;
        }

        decoder.send_packet(&packet)?;

        // Receive all frames from this packet
        while decoder.receive_frame(&mut decoded).is_ok() {
            frame_decoded = true;
            let frame_w = decoded.width();
            let frame_h = decoded.height();

            if frame_w > 0 && frame_h > 0 {
                // Track the maximum dimensions (HEIC might decode in tiles)
                if frame_w > max_width {
                    max_width = frame_w;
                }
                if frame_h > max_height {
                    max_height = frame_h;
                }
            }
        }
    }

    // Flush decoder to get any remaining frames (critical for HEIC)
    // HEIC often requires flushing to get the final complete frame
    decoder.send_eof().ok();
    while decoder.receive_frame(&mut decoded).is_ok() {
        frame_decoded = true;
        let frame_w = decoded.width();
        let frame_h = decoded.height();
        if frame_w > 0 && frame_h > 0 {
            // Track the maximum dimensions
            if frame_w > max_width {
                max_width = frame_w;
            }
            if frame_h > max_height {
                max_height = frame_h;
            }
        }
    }

    if !frame_decoded {
        return Err(anyhow::anyhow!("Failed to decode any frame from image"));
    }

    // Now decode with the correct dimensions to get the full image
    // Reinitialize decoder to decode from the beginning
    drop(ictx); // Drop the old input context
    
    // Normalize Windows path
    #[cfg(target_os = "windows")]
    let normalized_path = path.replace('\\', "/");
    #[cfg(not(target_os = "windows"))]
    let normalized_path = path.to_string();
    
    let mut ictx = ffmpeg::format::input(&normalized_path)
        .or_else(|_| ffmpeg::format::input(path)) // Fallback to original
        .with_context(|| format!("Failed to reopen image file with FFmpeg: {}", path))?;

    let stream = ictx
        .streams()
        .best(ffmpeg::media::Type::Video)
        .ok_or_else(|| anyhow::anyhow!("No video/image stream found in file"))?;

    let context = ffmpeg::codec::context::Context::from_parameters(stream.parameters())?;
    let mut decoder = context.decoder().video()?;

    // Create RGB frame with maximum dimensions to ensure we capture the full image
    // We'll keep the largest frame we decode (which should be the complete image)
    let mut rgb_frame =
        ffmpeg::util::frame::video::Video::new(ffmpeg::format::Pixel::RGB24, max_width, max_height);

    let stream_index = stream.index();
    let mut decoded = ffmpeg::util::frame::video::Video::empty();
    let mut scaler: Option<ffmpeg::software::scaling::Context> = None;
    let mut last_frame_width = 0u32;
    let mut last_frame_height = 0u32;
    let mut best_frame_size = 0u32;

    // Process all packets again with correct dimensions
    // For HEIC, we want to keep the largest frame (which should be the complete image)
    for (stream, packet) in ictx.packets() {
        if stream.index() != stream_index {
            continue;
        }

        decoder.send_packet(&packet)?;
        while decoder.receive_frame(&mut decoded).is_ok() {
            if decoded.width() > 0 && decoded.height() > 0 {
                let frame_size = decoded.width() * decoded.height();

                // Only use frames that match the maximum dimensions we found
                // This ensures we get the complete image, not partial tiles or upscaled partial frames
                // HEIC may decode in progressive passes, so we wait for the full-resolution frame
                if decoded.width() == max_width && decoded.height() == max_height {
                    // This is the complete frame at full resolution
                    // Create or update scaler based on actual frame dimensions
                    if scaler.is_none()
                        || decoded.width() != last_frame_width
                        || decoded.height() != last_frame_height
                    {
                        scaler = Some(ffmpeg::software::scaling::Context::get(
                            decoded.format(),
                            decoded.width(),
                            decoded.height(),
                            ffmpeg::format::Pixel::RGB24,
                            max_width,
                            max_height,
                            ffmpeg::software::scaling::flag::Flags::FAST_BILINEAR,
                        )?);
                        last_frame_width = decoded.width();
                        last_frame_height = decoded.height();
                    }

                    if let Some(ref mut scaler_ctx) = scaler {
                        // Scale this complete frame to RGB
                        scaler_ctx.run(&decoded, &mut rgb_frame)?;
                        best_frame_size = frame_size;
                    }
                } else if frame_size > best_frame_size {
                    // If we get a larger frame than expected, update max dimensions
                    // This shouldn't happen often, but handle it just in case
                    if decoded.width() > max_width {
                        max_width = decoded.width();
                    }
                    if decoded.height() > max_height {
                        max_height = decoded.height();
                    }
                    // Recreate rgb_frame with new dimensions
                    rgb_frame = ffmpeg::util::frame::video::Video::new(
                        ffmpeg::format::Pixel::RGB24,
                        max_width,
                        max_height,
                    );
                    best_frame_size = frame_size;
                }
            }
        }
    }

    // Flush decoder to get final complete frame
    decoder.send_eof().ok();
    while decoder.receive_frame(&mut decoded).is_ok() {
        if decoded.width() > 0 && decoded.height() > 0 {
            let frame_size = decoded.width() * decoded.height();

            // Only use frames that match the maximum dimensions
            if decoded.width() == max_width && decoded.height() == max_height {
                // This is the complete frame at full resolution
                if scaler.is_none()
                    || decoded.width() != last_frame_width
                    || decoded.height() != last_frame_height
                {
                    scaler = Some(ffmpeg::software::scaling::Context::get(
                        decoded.format(),
                        decoded.width(),
                        decoded.height(),
                        ffmpeg::format::Pixel::RGB24,
                        max_width,
                        max_height,
                        ffmpeg::software::scaling::flag::Flags::FAST_BILINEAR,
                    )?);
                    last_frame_width = decoded.width();
                    last_frame_height = decoded.height();
                }

                if let Some(ref mut scaler_ctx) = scaler {
                    scaler_ctx.run(&decoded, &mut rgb_frame)?;
                    best_frame_size = frame_size;
                }
            } else if frame_size > best_frame_size {
                // Update max dimensions if we find a larger frame
                if decoded.width() > max_width {
                    max_width = decoded.width();
                }
                if decoded.height() > max_height {
                    max_height = decoded.height();
                }
                rgb_frame = ffmpeg::util::frame::video::Video::new(
                    ffmpeg::format::Pixel::RGB24,
                    max_width,
                    max_height,
                );
                best_frame_size = frame_size;
            }
        }
    }

    // Verify we got a complete frame
    if best_frame_size == 0 {
        return Err(anyhow::anyhow!(
            "Failed to decode any complete frame from image"
        ));
    }

    // Convert FFmpeg RGB frame to image::DynamicImage
    let data = rgb_frame.data(0);
    let stride = rgb_frame.stride(0) as usize;
    let actual_width_usize = max_width as usize;
    let actual_height_usize = max_height as usize;

    let mut buf = Vec::with_capacity(actual_width_usize * actual_height_usize * 3);

    // Copy frame data, handling stride correctly
    for y in 0..actual_height_usize {
        let row_start = y * stride;
        let row_end = row_start + (actual_width_usize * 3);
        if row_end <= data.len() {
            buf.extend_from_slice(&data[row_start..row_end]);
        } else {
            // If stride is larger than expected, only copy what we need
            let available = data.len().saturating_sub(row_start);
            let to_copy = (actual_width_usize * 3).min(available);
            if to_copy > 0 {
                buf.extend_from_slice(&data[row_start..row_start + to_copy]);
                // Pad with zeros if needed (shouldn't happen for valid frames)
                if to_copy < (actual_width_usize * 3) {
                    buf.resize(actual_width_usize * actual_height_usize * 3, 0);
                    break;
                }
            } else {
                return Err(anyhow::anyhow!(
                    "Frame data incomplete: row {} exceeds buffer (stride={}, width={}, data_len={})",
                    y,
                    stride,
                    max_width,
                    data.len()
                ));
            }
        }
    }

    let img_buffer = image::ImageBuffer::<image::Rgb<u8>, _>::from_raw(max_width, max_height, buf)
        .ok_or_else(|| anyhow::anyhow!("Failed to create image buffer from FFmpeg frame"))?;

    Ok(image::DynamicImage::ImageRgb8(img_buffer))
}

pub fn estimate_compression(
    path: String,
    temp_output_path: String,
    params: CompressParams,
) -> Result<CompressionEstimate, Error> {
    tracing::debug!("estimate_compression called with path: {}, temp_output: {}", path, temp_output_path);
    
    // Validate input file exists
    if !std::path::Path::new(&path).exists() {
        let err = anyhow::anyhow!("Input file does not exist: {}", path);
        error!("{}", err);
        return Err(err);
    }
    
    // On Windows, we MUST have VideoInfo to avoid FFmpeg crash
    // Get it first if not provided
    #[cfg(target_os = "windows")]
    {
        debug!("Windows: Getting video info first to avoid FFmpeg crash on second context");
        let video_info = match video::get_video_info(&path) {
            Ok(info) => info,
            Err(e) => {
                error!("Failed to get video info: {}", e);
                return Err(e.into());
            }
        };
        
        // Use the version that accepts VideoInfo
        debug!("About to call video::estimate_compression_with_info");
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            video::estimate_compression_with_info(&path, &temp_output_path, &params, Some(&video_info))
        }));
        
        match result {
            Ok(Ok(stats)) => {
                info!("estimate_compression succeeded");
                return Ok(stats);
            },
            Ok(Err(e)) => {
                error!("estimate_compression returned error: {}", e);
                return Err(e.into());
            },
            Err(panic) => {
                let panic_msg = if let Some(s) = panic.downcast_ref::<&str>() {
                    format!("Panic in estimate_compression: {}", s)
                } else if let Some(s) = panic.downcast_ref::<String>() {
                    format!("Panic in estimate_compression: {}", s)
                } else {
                    "Panic in estimate_compression: unknown error".to_string()
                };
                error!("FATAL: {}", panic_msg);
                return Err(anyhow::anyhow!(panic_msg));
            }
        }
    }
    
    // On other platforms, use the normal path
    #[cfg(not(target_os = "windows"))]
    {
        // Catch panics to prevent app crashes
        debug!("About to call video::estimate_compression");
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            video::estimate_compression(&path, &temp_output_path, &params)
        }));
        
        match result {
            Ok(Ok(stats)) => {
                info!("estimate_compression succeeded");
                Ok(stats)
            },
            Ok(Err(e)) => {
                error!("estimate_compression returned error: {}", e);
                Err(e)
            },
            Err(panic) => {
                let panic_msg = if let Some(s) = panic.downcast_ref::<&str>() {
                    format!("Panic in estimate_compression: {}", s)
                } else if let Some(s) = panic.downcast_ref::<String>() {
                    format!("Panic in estimate_compression: {}", s)
                } else {
                    "Panic in estimate_compression: unknown error".to_string()
                };
                error!("FATAL: {}", panic_msg);
                Err(anyhow::anyhow!(panic_msg))
            }
        }
    }
}

pub fn compress_video(
    path: String,
    output_path: String,
    params: CompressParams,
) -> Result<String, Error> {
    tracing::debug!("compress_video called with path: {}, output: {}", path, output_path);
    
    // Validate input file exists
    if !std::path::Path::new(&path).exists() {
        let err = anyhow::anyhow!("Input file does not exist: {}", path);
        error!("{}", err);
        return Err(err);
    }
    
    // Catch panics to prevent app crashes on Windows
    debug!("About to call video::compress_video");
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        video::compress_video(&path, &output_path, &params)
    }));

    match result {
        Ok(Ok(stats)) => {
            info!("compress_video succeeded");
            Ok(stats)
        },
        Ok(Err(e)) => {
            error!("compress_video returned error: {}", e);
            Err(e)
        },
        Err(panic) => {
            let panic_msg = if let Some(s) = panic.downcast_ref::<&str>() {
                format!("Panic in compress_video: {}", s)
            } else if let Some(s) = panic.downcast_ref::<String>() {
                format!("Panic in compress_video: {}", s)
            } else {
                "Panic in compress_video: unknown error".to_string()
            };
            error!("FATAL: {}", panic_msg);
            Err(anyhow::anyhow!(panic_msg))
        }
    }
}
