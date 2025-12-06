use anyhow::{Context, Result};
use ffmpeg_next as ffmpeg;
use std::fs;

use crate::api::media::{ThumbnailParams, VideoInfo};

fn init_ffmpeg() -> Result<()> {
    ffmpeg::init().context("Failed to initialize ffmpeg")
}

pub fn get_video_info(path: &str) -> Result<VideoInfo> {
    init_ffmpeg()?;

    let metadata = fs::metadata(path).with_context(|| format!("Unable to stat file: {}", path))?;
    let size_bytes = metadata.len();

    let ictx =
        ffmpeg::format::input(&path).with_context(|| format!("Failed to open input: {}", path))?;

    let format = ictx.format();
    let format_name = Some(format.name().to_string());

    let mut width = 0;
    let mut height = 0;
    let mut codec_name = None;
    let mut bitrate = None;
    let mut duration_ms = 0u64;

    for (_, stream) in ictx.streams().enumerate() {
        if stream.parameters().medium() == ffmpeg::media::Type::Video {
            // Create a context to extract details
            if let Ok(ctx) = ffmpeg::codec::context::Context::from_parameters(stream.parameters()) {
                if let Ok(video) = ctx.decoder().video() {
                    width = video.width();
                    height = video.height();
                    bitrate = Some(video.bit_rate() as u64);
                    if let Some(codec) = ffmpeg::codec::encoder::find(video.id()) {
                        codec_name = Some(codec.name().to_string());
                    }
                }
            }

            let duration = stream.duration();
            let tb = stream.time_base();
            if duration != ffmpeg::ffi::AV_NOPTS_VALUE {
                let seconds = duration as f64 * f64::from(tb);
                duration_ms = (seconds * 1000.0) as u64;
            } else {
                let d = ictx.duration();
                if d != ffmpeg::ffi::AV_NOPTS_VALUE {
                    duration_ms = (d as u64) / 1000;
                }
            }

            break;
        }
    }

    Ok(VideoInfo {
        duration_ms,
        width,
        height,
        size_bytes,
        bitrate,
        codec_name,
        format_name,
    })
}

pub fn generate_thumbnail(path: &str, params: &ThumbnailParams) -> Result<Vec<u8>> {
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

                let (dst_w, dst_h) =
                    scale_to_fit(src_w, src_h, params.max_width, params.max_height);

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
                scaler_ctx.run(&decoded, &mut rgb_frame)?;
                // encode rgb_frame as PNG
                return encode_png_from_rgb_frame(&rgb_frame);
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

fn encode_png_from_rgb_frame(frame: &ffmpeg::util::frame::video::Video) -> Result<Vec<u8>> {
    use image::codecs::png::PngEncoder;
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
    let encoder = PngEncoder::new(&mut out);
    encoder.write_image(img.as_raw(), width, height, ExtendedColorType::Rgb8)?;

    Ok(out)
}
