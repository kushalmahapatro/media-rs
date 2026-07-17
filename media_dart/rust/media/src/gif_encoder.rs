//! Assembles PNG frame bytes into an animated GIF file using NeuQuant color quantization.
//!
//! Used on Android and iOS where there is no system GIF encoder; desktop uses FFmpeg instead.

#![allow(dead_code)]

use std::fs::File;
use std::io::BufWriter;

use color_quant::NeuQuant;
use image::codecs::gif::{GifEncoder, Repeat};
use image::codecs::png::PngDecoder;
use image::{DynamicImage, Frame, RgbaImage};

/// A single frame to be included in the animated GIF.
pub struct GifFrame {
    pub png_bytes: Vec<u8>,
}

/// Assembles PNG frames into an animated GIF with palette quantization.
///
/// `delay_ms` is the inter-frame delay in milliseconds (e.g. 100 for 10 fps).
pub fn assemble_gif(
    output_path: &str,
    frames: &[GifFrame],
    delay_ms: u32,
) -> Result<(), String> {
    if frames.is_empty() {
        return Err("gif: no frames to encode".into());
    }

    let file = File::create(output_path)
        .map_err(|e| format!("gif: create output file: {e}"))?;
    let writer = BufWriter::new(file);

    let mut encoder = GifEncoder::new_with_speed(writer, 10);
    encoder
        .set_repeat(Repeat::Infinite)
        .map_err(|e| format!("gif: set repeat: {e}"))?;

    for gif_frame in frames {
        let rgba = decode_png_to_rgba(&gif_frame.png_bytes)?;
        let (w, h) = (rgba.width(), rgba.height());
        let pixels = rgba.into_raw();

        let frame = quantize_to_gif_frame(&pixels, w, h, delay_ms)?;
        encoder
            .encode_frame(frame)
            .map_err(|e| format!("gif: encode frame: {e}"))?;
    }

    Ok(())
}

fn decode_png_to_rgba(png_bytes: &[u8]) -> Result<RgbaImage, String> {
    let cursor = std::io::Cursor::new(png_bytes);
    let decoder = PngDecoder::new(cursor)
        .map_err(|e| format!("gif: decode PNG frame: {e}"))?;
    let img = DynamicImage::from_decoder(decoder)
        .map_err(|e| format!("gif: convert PNG to image: {e}"))?;
    Ok(img.to_rgba8())
}

fn quantize_to_gif_frame(
    pixels: &[u8],
    width: u32,
    height: u32,
    delay_ms: u32,
) -> Result<Frame, String> {
    let nq = NeuQuant::new(10, 256, pixels);
    let palette = nq.color_map_rgb();

    let mut indexed: Vec<u8> = Vec::with_capacity((width * height) as usize);
    for pixel in pixels.chunks(4) {
        indexed.push(nq.index_of(pixel) as u8);
    }

    let mut frame_buf = RgbaImage::new(width, height);
    for (i, idx) in indexed.iter().enumerate() {
        let pi = *idx as usize * 3;
        let x = (i as u32) % width;
        let y = (i as u32) / width;
        frame_buf.put_pixel(
            x, y,
            image::Rgba([palette[pi], palette[pi + 1], palette[pi + 2], 255]),
        );
    }

    let delay = image::Delay::from_numer_denom_ms(delay_ms, 1);
    Ok(Frame::from_parts(frame_buf, 0, 0, delay))
}
