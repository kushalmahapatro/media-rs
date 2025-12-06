use std::path::{Path, PathBuf};

use crate::api::media::{CompressParams, CompressionEstimate, OutputFormat, ThumbnailSizeType};
use anyhow::{Context, Error, Result};
use ffmpeg_next::{self as ffmpeg};

use crate::api::media::VideoThumbnailParams;

fn init_ffmpeg() -> Result<()> {
    ffmpeg::init().context("Failed to initialize ffmpeg")
}

pub fn get_video_info(path: &str) -> Result<crate::api::media::VideoInfo> {
    init_ffmpeg()?;

    let ictx = ffmpeg::format::input(&path)?;
    let stream = ictx
        .streams()
        .best(ffmpeg::media::Type::Video)
        .ok_or(anyhow::anyhow!("No video stream found"))?;

    let context = ffmpeg::codec::context::Context::from_parameters(stream.parameters())?;
    let decoder = context.decoder().video()?;

    let width = decoder.width();
    let height = decoder.height();
    let duration = ictx.duration(); // AV_TIME_BASE

    let duration_ms = (duration as f64 / ffmpeg::ffi::AV_TIME_BASE as f64 * 1000.0) as u64;
    let size_bytes = std::fs::metadata(path)?.len();

    // Estimate bitrate if missing (size * 8 / seconds)
    let bitrate = if ictx.bit_rate() > 0 {
        Some(ictx.bit_rate() as u64)
    } else {
        if duration_ms > 0 {
            Some((size_bytes * 8 * 1000) / duration_ms)
        } else {
            None
        }
    };

    let codec_name = decoder.codec().map(|c| c.name().to_string());
    let format_name = ictx.format().name().to_string();

    // Generate Suggestions
    let suggestions = generate_resolution_presets(width, height, bitrate.unwrap_or(0));

    Ok(crate::api::media::VideoInfo {
        duration_ms,
        width,
        height,
        size_bytes,
        bitrate,
        codec_name: Some(codec_name.unwrap_or_default()),
        format_name: Some(format_name),
        suggestions,
    })
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

pub fn generate_thumbnail(path: &str, params: &VideoThumbnailParams) -> Result<Vec<u8>> {
    init_ffmpeg()?;

    let mut ictx =
        ffmpeg::format::input(&path).with_context(|| format!("Failed to open input: {}", path))?;

    let stream_index = ictx
        .streams()
        .best(ffmpeg::media::Type::Video)
        .ok_or_else(|| anyhow::anyhow!("No video stream found"))?
        .index();

    let duration_us = ictx.duration();

    // target timestamp in microseconds (AV_TIME_BASE)
    let mut ts = params.time_ms as i64 * 1000;

    // Clamp to duration if available
    if duration_us != ffmpeg::ffi::AV_NOPTS_VALUE {
        if ts > duration_us {
            ts = duration_us;
        }
    }

    // seek expects timestamp in AV_TIME_BASE if no stream is specified (or implicit default)
    // Actually rust-ffmpeg `seek` on input context:
    // "Seek to the given timestamp (in AV_TIME_BASE) in the input stream."
    ictx.seek(ts, ts..ts)?;

    let mut decoder = {
        let stream = ictx
            .stream(stream_index)
            .ok_or_else(|| anyhow::anyhow!("Video stream not found"))?;
        let codec_params = stream.parameters();
        ffmpeg::codec::context::Context::from_parameters(codec_params)?
            .decoder()
            .video()?
    };

    let mut scaler = None::<ffmpeg::software::scaling::Context>;
    let mut decoded = ffmpeg::util::frame::video::Video::empty();
    let mut rgb_frame = ffmpeg::util::frame::video::Video::empty();

    for (stream, packet) in ictx.packets() {
        if stream.index() != stream_index {
            continue;
        }

        decoder.send_packet(&packet)?;
        while decoder.receive_frame(&mut decoded).is_ok() {
            // lazily init scaler based on real video size
            if scaler.is_none() {
                let src_w = decoded.width();
                let src_h = decoded.height();

                let size = params
                    .size_type
                    .unwrap_or_else(|| ThumbnailSizeType::Medium)
                    .dimensions();

                let (dst_w, dst_h) = scale_to_fit(src_w, src_h, size.0, size.1);

                rgb_frame = ffmpeg::util::frame::video::Video::new(
                    ffmpeg::format::Pixel::RGB24,
                    dst_w,
                    dst_h,
                );

                scaler = Some(ffmpeg::software::scaling::Context::get(
                    decoded.format(),
                    src_w,
                    src_h,
                    ffmpeg::format::Pixel::RGB24,
                    dst_w,
                    dst_h,
                    ffmpeg::software::scaling::flag::Flags::BILINEAR,
                )?);
            }

            if let Some(ref mut scaler_ctx) = scaler {
                let output_format = params.format.unwrap_or(OutputFormat::PNG);
                scaler_ctx.run(&decoded, &mut rgb_frame)?;
                // encode rgb_frame as PNG
                return encode_png_from_rgb_frame(&rgb_frame, output_format);
            }
        }
    }

    Err(anyhow::anyhow!("Could not decode frame for thumbnail"))
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

fn encode_png_from_rgb_frame(
    frame: &ffmpeg::util::frame::video::Video,
    format: OutputFormat,
) -> Result<Vec<u8>> {
    use image::codecs::jpeg::JpegEncoder;
    use image::codecs::png::PngEncoder;
    use image::codecs::webp::WebPEncoder;
    use image::ExtendedColorType;
    use image::{ImageBuffer, ImageEncoder, Rgb};

    let width = frame.width();
    let height = frame.height();

    // frame data is RGB24: contiguous buffer
    let data = frame.data(0);
    let stride = frame.stride(0) as usize;

    // Copy into tightly-packed buffer (no stride padding)
    let mut buf = Vec::with_capacity((width * height * 3) as usize);
    for y in 0..height {
        let row_start = (y as usize) * stride;
        let row = &data[row_start..row_start + (width as usize * 3)];
        buf.extend_from_slice(row);
    }

    let img: ImageBuffer<Rgb<u8>, _> = ImageBuffer::from_raw(width, height, buf)
        .ok_or_else(|| anyhow::anyhow!("Failed to create image buffer"))?;

    let mut out = Vec::new();
    match format {
        OutputFormat::PNG => {
            let encoder = PngEncoder::new(&mut out);
            encoder.write_image(img.as_raw(), width, height, ExtendedColorType::Rgb8)?;
        }
        OutputFormat::JPEG => {
            let encoder = JpegEncoder::new(&mut out);
            encoder.write_image(img.as_raw(), width, height, ExtendedColorType::Rgb8)?;
        }
        OutputFormat::WEBP => {
            let encoder = WebPEncoder::new_lossless(&mut out);
            encoder.write_image(img.as_raw(), width, height, ExtendedColorType::Rgb8)?;
        }
    }

    Ok(out)
}

pub fn get_file_name_without_extension(path: &str) -> PathBuf {
    let filename_with_extension = Path::new(&path)
        .file_name()
        .ok_or_else(|| anyhow::anyhow!("Path doesn't have file name"))
        .unwrap();

    let filename_without_extension = PathBuf::from(filename_with_extension).with_extension("");
    filename_without_extension
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
                "Failed to create thumbnail output directory: {}",
                base_output_dir.display()
            )
        })
        .unwrap();
    Ok(base_output_dir)
}

pub fn estimate_compression(
    path: &str,
    temp_output_path: &str,
    params: &CompressParams,
) -> Result<CompressionEstimate> {
    init_ffmpeg()?;

    let filename_without_extension = get_file_name_without_extension(&path);
    let base_output_dir = check_output_path(&temp_output_path)?;

    let info = get_video_info(path)?;
    let total_duration_ms = info.duration_ms;

    // Safety check: if video is very short (< 5s), just run a single sample from 0
    if total_duration_ms < 5000 {
        let temp_path = format!(
            "{}/{}.est.temp.mp4",
            base_output_dir.display(),
            filename_without_extension.display()
        );
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

    // Heuristics
    let sample_duration_ms = 5000u64; // 2s warmup + 3s active

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

    // Run concurrent sampling to reduce wait time.
    // We sum the speed of all threads to estimate total system throughput,
    // which effectively compensates for the CPU contention (or lack thereof).
    let results: Vec<Result<(f64, f64)>> = std::thread::scope(|s| {
        let handles: Vec<_> = points
            .iter()
            .enumerate()
            .map(|(i, &point)| {
                let path = path.to_owned();
                let params = params.clone();
                let base_output_dir = base_output_dir.to_owned();
                let filename_without_extension = filename_without_extension.to_owned();
                s.spawn(move || {
                    let start_ms = (total_duration_ms as f64 * point) as u64;

                    // Ensure we don't seek past end (minus sample duration)
                    let actual_start_ms = if start_ms + sample_duration_ms > total_duration_ms {
                        total_duration_ms.saturating_sub(sample_duration_ms)
                    } else {
                        start_ms
                    };

                    let temp_path = format!(
                        "{}/{}.est.part.{}.mp4",
                        base_output_dir.display(),
                        filename_without_extension.display(),
                        i
                    );

                    let result = perform_compression(
                        &path,
                        &temp_path,
                        &params,
                        Some(actual_start_ms),
                        Some(sample_duration_ms),
                    );
                    std::fs::remove_file(&temp_path).ok();

                    match result {
                        Ok(stats) => {
                            if stats.processed_duration_ms > 0 && stats.elapsed_ms > 0 {
                                let speed =
                                    stats.processed_duration_ms as f64 / stats.elapsed_ms as f64;
                                let size_rate = stats.encoded_size_bytes as f64
                                    / stats.processed_duration_ms as f64;
                                Ok((speed, size_rate))
                            } else {
                                Err(anyhow::anyhow!("Zero duration processed"))
                            }
                        }
                        Err(e) => Err(e),
                    }
                })
            })
            .collect();

        handles.into_iter().map(|h| h.join().unwrap()).collect()
    });

    let mut total_speed_x = 0.0;
    let mut total_size_per_ms = 0.0;
    let mut valid_samples = 0;

    for (i, res) in results.into_iter().enumerate() {
        if let Ok((speed, size_rate)) = res {
            println!(
                "Sample {}: Speed={:.2}x, SizeRate={:.2} bytes/ms",
                i, speed, size_rate
            );
            total_speed_x += speed;
            total_size_per_ms += size_rate;
            valid_samples += 1;
        } else {
            println!("Sample {}: Failed", i);
        }
    }

    println!("Total Speed (Sum): {:.2}x", total_speed_x);

    // Fallback if all samples failed
    if valid_samples == 0 {
        let temp_path = format!(
            "{}/{}.est.fallback.mp4",
            base_output_dir.display(),
            filename_without_extension.display()
        );
        let result =
            perform_compression(path, &temp_path, params, Some(0), Some(sample_duration_ms));
        std::fs::remove_file(&temp_path).ok();

        if let Ok(stats) = result {
            if stats.processed_duration_ms > 0 && stats.elapsed_ms > 0 {
                let speed = stats.processed_duration_ms as f64 / stats.elapsed_ms as f64;
                let size_rate =
                    stats.encoded_size_bytes as f64 / stats.processed_duration_ms as f64;
                total_speed_x += speed;
                total_size_per_ms += size_rate;
                valid_samples += 1;
            }
        }
    }

    if valid_samples == 0 {
        return Err(anyhow::anyhow!("Failed to estimate compression"));
    }

    // Size Use Average Video Rate
    let avg_video_rate_per_ms = total_size_per_ms / valid_samples as f64;

    // Speed Use Sum
    let estimated_speed = total_speed_x;

    let estimated_duration_ms = (total_duration_ms as f64 / estimated_speed) as u64;

    let estimated_size_bytes = if let Some(fixed_size) = bitrate_mode_size {
        fixed_size
    } else {
        // Video Estimate
        let video_est = avg_video_rate_per_ms * total_duration_ms as f64;

        // Audio Estimate (Constant 192kbps = 24 bytes/ms)
        // We add this because we skipped audio in sampling to avoid PCM skew.
        let audio_est = (192.0 / 8.0) * total_duration_ms as f64;

        (video_est + audio_est) as u64
    };

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
    init_ffmpeg()?;

    let filename_without_extension = get_file_name_without_extension(&path);
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
        let base_output_dir = check_output_path(&output_path)?;
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

    let mut ictx = ffmpeg::format::input(&path)?;
    let mut octx = ffmpeg::format::output(&output_path_str)?;

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

    let codec = ffmpeg_next::encoder::find(ffmpeg::codec::Id::H264)
        .ok_or_else(|| anyhow::anyhow!("codec not found"))?;

    // Calculate target dimensions
    // Calculate target dimensions (Clamped)
    let (target_width, target_height) = calculate_dimensions(
        decoder.width(),
        decoder.height(),
        params.width,
        params.height,
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

    if global_header {
        encoder_setup.set_flags(ffmpeg::codec::flag::Flags::GLOBAL_HEADER);
    }

    // 2. Open encoder
    let mut opts = ffmpeg::Dictionary::new();
    if let Some(ref p) = params.preset {
        opts.set("preset", p);
    }
    // Adding tune can sometimes help init requirements
    // opts.set("tune", "zerolatency");

    if let Some(crf) = params.crf {
        opts.set("crf", &crf.to_string());
    }
    // Set bitrate in dictionary as fallback/primary depending on CRF
    opts.set("b", &format!("{}", params.target_bitrate_kbps * 1000));
    opts.set("profile", "high");

    let mut encoder = encoder_setup
        .open_as_with(codec, opts)
        .map_err(|e| anyhow::anyhow!("Error opening encoder (native h264): {e:?}"))?;

    // 2. Add video stream
    let video_ost_index = {
        let mut ost = octx.add_stream(codec)?;
        ost.set_parameters(&encoder);
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
            let input_stream = ictx.stream(idx).unwrap();
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
                // audio_fifo = Some(fifo);
            }
        }
    }

    octx.write_header()?;

    // Capture timebase after header is written as it might change
    let ost_time_base = octx.stream(video_ost_index).unwrap().time_base();
    let audio_ost_time_base = audio_ost_index.map(|i| octx.stream(i).unwrap().time_base());
    let audio_ist_time_base = audio_stream_index.map(|i| ictx.stream(i).unwrap().time_base());

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
                            // Resample
                            // Calculate output samples manually (resampler.get_out_samples not exposed?)
                            // Formula: in_samples * out_rate / in_rate + padding
                            let in_rate = decoder.rate() as u64;
                            let out_rate = encoder.rate() as u64;
                            let in_samples = decoded_audio.samples() as u64;

                            // Add generous padding for rounding/compensation
                            let out_samples_est = (in_samples * out_rate / in_rate) + 128;

                            let mut resampled = ffmpeg::util::frame::audio::Audio::new(
                                encoder.format(),
                                out_samples_est as usize,
                                encoder.channel_layout(),
                            );
                            resampled.set_rate(encoder.rate());

                            resampler.run(&decoded_audio, &mut resampled)?;

                            // Manual Buffering
                            // Append planar data to buffers
                            if left_buffer.is_none() {
                                left_buffer = Some(Vec::new());
                            }
                            if right_buffer.is_none() {
                                right_buffer = Some(Vec::new());
                            }

                            let lb = left_buffer.as_mut().unwrap();
                            let rb = right_buffer.as_mut().unwrap();

                            if resampled.planes() >= 2 {
                                let p0 = resampled.plane::<f32>(0);
                                let p1 = resampled.plane::<f32>(1);
                                lb.extend_from_slice(p0);
                                rb.extend_from_slice(p1);
                            } else {
                                // Mono to Stereo logic if needed, or just map p0 to both?
                                // Resampler was set to Stereo, so it should output 2 planes (FLTP).
                                // If not, maybe just 1 plane with interleaved? No, FLTP is planar.
                                // If 1 plane, it might be mono. I'll clone p0.
                                let p0 = resampled.plane::<f32>(0);
                                lb.extend_from_slice(p0);
                                rb.extend_from_slice(p0);
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
                                    encoded_pkt.rescale_ts(
                                        encoder.time_base(),
                                        audio_ost_time_base.unwrap(),
                                    );
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
        encoded_size_bytes += encoded.size() as u64;
        encoded
            .write_interleaved(&mut octx)
            .context("Final write_interleaved failed")?;
    }

    // Flush Audio Encoder (Transcode path only)
    if let (Some(encoder), Some(out_idx), Some(out_tb)) =
        (audio_encoder.as_mut(), audio_ost_index, audio_ost_time_base)
    {
        // Flush remaining buffer
        if let (Some(lb), Some(rb)) = (left_buffer.as_mut(), right_buffer.as_mut()) {
            if lb.len() > 0 {
                let frame_size = 1024; // Standard frame size
                let pad_len = frame_size - lb.len();
                if pad_len > 0 {
                    // Pad with silence
                    lb.extend(std::iter::repeat(0.0).take(pad_len));
                    rb.extend(std::iter::repeat(0.0).take(pad_len));
                }

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
        stats_start_time.unwrap().elapsed().as_millis()
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

    Ok(CompressionStats {
        processed_duration_ms: final_processed_ms,
        elapsed_ms: final_elapsed_ms,
        encoded_size_bytes: final_encoded_size,
        output_file_path: output_path.to_string_lossy().to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::Command;

    fn generate_test_video(path: &str) {
        // Generate 30 seconds of video
        let output = Command::new("ffmpeg")
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
            .output()
            .expect("Failed to execute ffmpeg");

        if !output.status.success() {
            panic!("ffmpeg failed: {}", String::from_utf8_lossy(&output.stderr));
        }
    }

    #[test]
    fn test_estimate_compression_works() {
        let test_file = "test_video_estimate.mp4";
        generate_test_video(test_file);

        let params = crate::api::media::CompressParams {
            target_bitrate_kbps: 1000,
            preset: Some("veryfast".to_string()),
            crf: Some(23),
            width: None,
            height: None,
        };

        let result = estimate_compression(test_file, "./temp", &params);

        // Cleanup
        let _ = std::fs::remove_file(test_file);

        if let Err(e) = &result {
            println!("Compression estimation error: {:?}", e);
        }

        assert!(result.is_ok());
        let estimate = result.unwrap();
        println!(
            "Estimated size: {}, duration: {}",
            estimate.estimated_size_bytes, estimate.estimated_duration_ms
        );

        assert!(estimate.estimated_size_bytes > 0);
        // Duration should be roughly 3000ms (we asked for 3s testsrc)
        // Estimation logic samples 5s or 20% of video.
        // For 3s video (<10s), start is 0, duration is min(5000, 3000) = 3000.
        // It should process the whole thing.
        // on fast machines (like M-series Mac) this can be very fast (< 200ms)
        assert!(estimate.estimated_duration_ms > 0 && estimate.estimated_duration_ms < 5000);
    }

    #[test]
    fn test_compression_preserves_audio() {
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

        // Generate video with audio
        let output = Command::new("ffmpeg")
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
            .output()
            .expect("Failed to execute ffmpeg");

        if !output.status.success() {
            panic!("ffmpeg failed: {}", String::from_utf8_lossy(&output.stderr));
        }

        let params = crate::api::media::CompressParams {
            target_bitrate_kbps: 1000,
            preset: Some("veryfast".to_string()), // Match user preset if possible, user didn't specify but implies speed
            crf: Some(23),
            width: Some(640),
            height: Some(360),
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
}
