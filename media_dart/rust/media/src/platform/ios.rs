//! iOS: AVFoundation probe / thumbnail / export (`objc2-av-foundation` + UIKit PNG).

#![allow(deprecated)] // UIGraphics* bitmap helpers (deprecated by Apple) until we wire UIGraphicsImageRenderer + block2.

use std::ptr::NonNull;
use std::time::Duration;

use block2::RcBlock;
use objc2::Message;
use objc2::rc::{autoreleasepool, Retained};
use objc2_av_foundation::{
    AVAssetExportSession, AVAssetExportSessionStatus, AVAssetImageGenerator,
    AVAssetImageGeneratorDynamicRangePolicyForceSDR, AVAssetTrack, AVFileTypeMPEG4,
    AVMediaTypeAudio, AVMediaTypeVideo, AVURLAsset,
};
use objc2_av_foundation::{
    AVAssetExportPreset1280x720, AVAssetExportPreset1920x1080, AVAssetExportPreset640x480,
    AVAssetExportPreset960x540, AVAssetExportPresetMediumQuality,
};
use objc2_core_foundation::{CGPoint, CGRect, CGFloat, CGSize};
use objc2_core_media::{kCMTimeInvalid, CMTime, CMTimeFlags};
use objc2_foundation::{NSData, NSError, NSString, NSURL};
use objc2_ui_kit::{
    UIImage, UIImageOrientation,
    UIGraphicsBeginImageContextWithOptions, UIGraphicsEndImageContext,
    UIGraphicsGetImageFromCurrentImageContext,
};

use crate::api::{ThumbnailFormat, TimelineThumbnail, TranscodeProgress, VideoProbe};
use crate::frb_generated::StreamSink;

fn cmtime_to_duration_ms(t: CMTime) -> Option<i64> {
    let invalid = unsafe { kCMTimeInvalid };
    if t == invalid || !t.flags.contains(CMTimeFlags::Valid) {
        return None;
    }
    let secs = unsafe { t.seconds() };
    if !secs.is_finite() || secs < 0.0 {
        return None;
    }
    Some((secs * 1000.0).round() as i64)
}

fn nsdata_to_vec(data: &NSData) -> Vec<u8> {
    let len = data.length();
    if len == 0 {
        return Vec::new();
    }
    let mut v = vec![0u8; len];
    unsafe {
        data.getBytes_length(
            NonNull::new(v.as_mut_ptr().cast()).expect("non-null buffer"),
            len,
        );
    }
    v
}

fn ns_err(e: &NSError) -> String {
    e.localizedDescription().to_string()
}

/// JPEG/HEIC etc. often store pixels in sensor orientation; `UIImage` reports that via
/// `imageOrientation`. `imageByPreparingThumbnailOfSize` can bake the wrong orientation into
/// the thumbnail. Drawing into a bitmap context applies the orientation transform first.
fn ui_image_upright_if_needed(ui: &UIImage) -> Result<Option<Retained<UIImage>>, String> {
    let needs_fix = unsafe { ui.imageOrientation() != UIImageOrientation::Up };
    if !needs_fix {
        return Ok(None);
    }
    let size = unsafe { ui.size() };
    if size.width <= 0.0 || size.height <= 0.0 {
        return Err("thumbnail: invalid image size for orientation fix".into());
    }
    let scale = unsafe { ui.scale() };
    UIGraphicsBeginImageContextWithOptions(size, false, scale);
    let rect = CGRect::new(CGPoint::ZERO, size);
    ui.drawInRect(rect);
    let out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    out
        .map(Some)
        .ok_or_else(|| "thumbnail: could not normalize image orientation".into())
}

fn looks_like_static_image(path: &str) -> bool {
    let lower = path.to_ascii_lowercase();
    [
        ".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif", ".bmp", ".gif", ".tiff", ".tif",
    ]
    .iter()
    .any(|ext| lower.ends_with(ext))
}

fn encode_ui_image(ui: &UIImage, format: ThumbnailFormat) -> Result<Vec<u8>, String> {
    // `pngRepresentation` encodes the backing bitmap and does **not** apply `imageOrientation`;
    // `jpegRepresentation` typically does. Thumbnails from `imageByPreparingThumbnailOfSize` can
    // still carry a non-`.Up` orientation, so normalize pixels once before any format encodes.
    let upright: Retained<UIImage> = match ui_image_upright_if_needed(ui)? {
        None => ui.retain(),
        Some(img) => img,
    };
    let ui = &*upright;
    match format {
        ThumbnailFormat::Png => {
            let data = ui
                .png_representation()
                .ok_or_else(|| "thumbnail: PNG representation nil".to_string())?;
            Ok(nsdata_to_vec(&data))
        }
        ThumbnailFormat::Jpeg => {
            let data = ui
                .jpeg_representation(0.85 as CGFloat)
                .ok_or_else(|| "thumbnail: JPEG representation nil".to_string())?;
            Ok(nsdata_to_vec(&data))
        }
        ThumbnailFormat::Webp => Err(
            "thumbnail: WebP is not supported on iOS in this build; use PNG or JPEG".into(),
        ),
    }
}

/// Inspect a local file path using `AVURLAsset`.
pub fn probe_avasset(path: &str) -> Result<VideoProbe, String> {
    autoreleasepool(|_| {
        if path.trim().is_empty() {
            return Err("probe: empty path".into());
        }

        let path_str = NSString::from_str(path);
        let url = NSURL::fileURLWithPath(&path_str);

        let asset = unsafe { AVURLAsset::URLAssetWithURL_options(&url, None) };

        let duration_ms = cmtime_to_duration_ms(unsafe { asset.duration() });

        let tracks = unsafe { asset.tracks() };
        let n = tracks.count();

        let video_ty = unsafe { AVMediaTypeVideo.as_ref() }.ok_or_else(|| {
            "AVFoundation: AVMediaTypeVideo symbol missing (link error?)".to_string()
        })?;
        let audio_ty = unsafe { AVMediaTypeAudio.as_ref() }.ok_or_else(|| {
            "AVFoundation: AVMediaTypeAudio symbol missing (link error?)".to_string()
        })?;

        let mut probe = VideoProbe {
            duration_ms,
            width: None,
            height: None,
            video_bitrate: None,
            audio_bitrate: None,
            frame_rate: None,
            video_codec: None,
            audio_codec: None,
        };

        for i in 0..n {
            let track: Retained<AVAssetTrack> = tracks.objectAtIndex(i);
            let media_type = unsafe { track.mediaType() };

            if media_type.isEqualToString(video_ty) && probe.width.is_none() {
                let size = unsafe { track.naturalSize() };
                probe.width = Some(size.width as u32);
                probe.height = Some(size.height as u32);
                let br = unsafe { track.estimatedDataRate() };
                if br > 0.0 {
                    probe.video_bitrate = Some(br as i64);
                }
                let fps = unsafe { track.nominalFrameRate() };
                if fps > 0.0 {
                    probe.frame_rate = Some(f64::from(fps));
                }
                probe.video_codec = Some(media_type.to_string());
            } else if media_type.isEqualToString(audio_ty) && probe.audio_bitrate.is_none() {
                let br = unsafe { track.estimatedDataRate() };
                if br > 0.0 {
                    probe.audio_bitrate = Some(br as i64);
                }
                probe.audio_codec = Some(media_type.to_string());
            }
        }

        if probe.width.is_none() && looks_like_static_image(path) {
            if let Some(ui) = UIImage::imageWithContentsOfFile(&path_str) {
                let sz = unsafe { ui.size() };
                let scale = unsafe { ui.scale() };
                let w = (f64::from(sz.width) * f64::from(scale)).round();
                let h = (f64::from(sz.height) * f64::from(scale)).round();
                if w >= 1.0 && h >= 1.0 {
                    probe.width = Some(w as u32);
                    probe.height = Some(h as u32);
                    probe.video_codec = Some("image/static".into());
                }
            }
        }

        Ok(probe)
    })
}

fn static_image_thumbnail(
    path: &str,
    max_edge: u32,
    format: ThumbnailFormat,
) -> Result<Vec<u8>, String> {
    autoreleasepool(|_| {
        if path.trim().is_empty() {
            return Err("thumbnail: empty path".into());
        }
        let path_str = NSString::from_str(path);
        let Some(ui_loaded) = UIImage::imageWithContentsOfFile(&path_str) else {
            return Err("thumbnail: could not load image from path".into());
        };
        let ui_work = match ui_image_upright_if_needed(&ui_loaded)? {
            None => ui_loaded,
            Some(upright) => upright,
        };
        let edge = max_edge.max(1) as CGFloat;
        let thumb = ui_work.imageByPreparingThumbnailOfSize(CGSize {
            width: edge,
            height: edge,
        });
        let to_encode = thumb.as_deref().unwrap_or(&ui_work);
        encode_ui_image(to_encode, format)
    })
}

/// Thumbnail via `AVAssetImageGenerator` + `UIImage` PNG/JPEG representation.
pub fn thumbnail_image(
    path: &str,
    time_sec: f64,
    max_edge: u32,
    format: ThumbnailFormat,
) -> Result<Vec<u8>, String> {
    if looks_like_static_image(path) {
        return static_image_thumbnail(path, max_edge, format);
    }
    with_uiimage_at_time(path, time_sec, max_edge, |ui| encode_ui_image(ui, format))
}

fn with_uiimage_at_time<R>(
    path: &str,
    time_sec: f64,
    max_edge: u32,
    f: impl FnOnce(&UIImage) -> Result<R, String>,
) -> Result<R, String> {
    autoreleasepool(|_| {
        if path.trim().is_empty() {
            return Err("thumbnail: empty path".into());
        }
        let path_str = NSString::from_str(path);
        let url = NSURL::fileURLWithPath(&path_str);
        let asset = unsafe { AVURLAsset::URLAssetWithURL_options(&url, None) };

        let gen = unsafe { AVAssetImageGenerator::assetImageGeneratorWithAsset(&asset) };
        unsafe {
            gen.setAppliesPreferredTrackTransform(true);
            let edge = max_edge.max(1) as CGFloat;
            gen.setMaximumSize(CGSize {
                width: edge,
                height: edge,
            });
            gen.setDynamicRangePolicy(AVAssetImageGeneratorDynamicRangePolicyForceSDR);
        }

        let t = unsafe { CMTime::with_seconds(time_sec, 600) };
        #[allow(deprecated)]
        let cg = unsafe {
            gen.copyCGImageAtTime_actualTime_error(t, std::ptr::null_mut())
                .map_err(|e| ns_err(&e))?
        };

        let ui = UIImage::imageWithCGImage(&cg);
        f(&ui)
    })
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

/// Evenly spaced thumbnails over the asset duration; each frame is pushed to [sink].
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
    if path.trim().is_empty() {
        return Err("timeline: empty path".into());
    }
    let path_str = NSString::from_str(path);
    let url = NSURL::fileURLWithPath(&path_str);
    let asset = unsafe { AVURLAsset::URLAssetWithURL_options(&url, None) };
    let duration_ms = cmtime_to_duration_ms(unsafe { asset.duration() })
        .ok_or_else(|| "timeline: unknown duration".to_string())?;
    let dur_sec = duration_ms as f64 / 1000.0;
    if dur_sec <= 0.0 {
        return Err("timeline: zero duration".into());
    }

    let n = frame_count as f64;
    for i in 0..frame_count {
        let t = dur_sec * (i as f64 + 0.5) / n;
        let bytes = thumbnail_image(path, t, max_edge, format)?;
        let _ = sink.add(TimelineThumbnail {
            index: i,
            time_sec: t,
            image_bytes: bytes,
        });
    }
    Ok(())
}

fn preset_candidates_vec(max_width: u32) -> Vec<&'static NSString> {
    unsafe {
        if max_width <= 640 {
            vec![
                AVAssetExportPreset640x480,
                AVAssetExportPresetMediumQuality,
            ]
        } else if max_width <= 960 {
            vec![
                AVAssetExportPreset960x540,
                AVAssetExportPreset640x480,
                AVAssetExportPresetMediumQuality,
            ]
        } else if max_width <= 1280 {
            vec![
                AVAssetExportPreset1280x720,
                AVAssetExportPreset960x540,
                AVAssetExportPreset640x480,
                AVAssetExportPresetMediumQuality,
            ]
        } else {
            vec![
                AVAssetExportPreset1920x1080,
                AVAssetExportPreset1280x720,
                AVAssetExportPreset960x540,
                AVAssetExportPresetMediumQuality,
            ]
        }
    }
}

/// Re-encode with `AVAssetExportSession` (preset chosen from [max_width]; bitrates are encoder defaults).
pub fn transcode_export(
    input_path: &str,
    output_path: &str,
    _video_bitrate_kbps: u32,
    max_width: u32,
    _audio_bitrate_kbps: u32,
    sink: StreamSink<TranscodeProgress>,
) -> Result<(), String> {
    let _ = std::fs::remove_file(output_path);

    autoreleasepool(|_| {
        if input_path.trim().is_empty() || output_path.trim().is_empty() {
            return Err("transcode: empty path".into());
        }

        let in_str = NSString::from_str(input_path);
        let in_url = NSURL::fileURLWithPath(&in_str);
        let asset = unsafe { AVURLAsset::URLAssetWithURL_options(&in_url, None) };

        let mut session: Option<Retained<AVAssetExportSession>> = None;
        for preset in preset_candidates_vec(max_width) {
            if let Some(s) =
                unsafe { AVAssetExportSession::exportSessionWithAsset_presetName(&asset, preset) }
            {
                session = Some(s);
                break;
            }
        }
        let session = session.ok_or_else(|| {
            "transcode: no AVAssetExportSession preset compatible with this asset".to_string()
        })?;

        let out_str = NSString::from_str(output_path);
        let out_url = NSURL::fileURLWithPath(&out_str);

        let mpeg4 = unsafe { AVFileTypeMPEG4.as_ref() }
            .ok_or_else(|| "AVFileTypeMPEG4 missing".to_string())?;

        unsafe {
            session.setOutputURL(Some(&out_url));
            session.setOutputFileType(Some(mpeg4));
            session.setShouldOptimizeForNetworkUse(true);
        }

        let _ = sink.add(TranscodeProgress {
            phase: "starting".into(),
            fraction: 0.0,
            message: Some("AVAssetExportSession".into()),
        });

        let block = RcBlock::new(|| {});
        unsafe {
            session.exportAsynchronouslyWithCompletionHandler(&block);
        }

        loop {
            let status = unsafe { session.status() };
            match status {
                AVAssetExportSessionStatus::Completed => {
                    let _ = sink.add(TranscodeProgress {
                        phase: "finishing".into(),
                        fraction: 1.0,
                        message: Some("Complete".into()),
                    });
                    return Ok(());
                }
                AVAssetExportSessionStatus::Failed => {
                    let msg = unsafe { session.error() }
                        .map(|e| ns_err(&e))
                        .unwrap_or_else(|| "export failed (no NSError)".into());
                    return Err(format!("transcode: {msg}"));
                }
                AVAssetExportSessionStatus::Cancelled => {
                    return Err("transcode: cancelled".into());
                }
                _ => {
                    let p = unsafe { session.progress() };
                    let frac = f64::from(p).clamp(0.0, 1.0);
                    let _ = sink.add(TranscodeProgress {
                        phase: "encoding".into(),
                        fraction: frac,
                        message: None,
                    });
                    std::thread::sleep(Duration::from_millis(120));
                }
            }
        }
    })
}

pub fn video_to_gif(
    input_path: &str,
    output_path: &str,
    fps: u32,
    max_edge: u32,
    start_sec: Option<f64>,
    duration_sec: Option<f64>,
    sink: StreamSink<TranscodeProgress>,
) -> Result<(), String> {
    use crate::gif_encoder::{GifFrame, assemble_gif};

    let _ = sink.add(TranscodeProgress {
        phase: "starting".into(),
        fraction: 0.0,
        message: Some("Probing video".into()),
    });

    let probe = probe_avasset(input_path)?;
    let total_ms = probe.duration_ms.filter(|&ms| ms > 0)
        .ok_or_else(|| "gif: unknown or zero duration".to_string())?;
    let total_sec = total_ms as f64 / 1000.0;

    let begin = start_sec.unwrap_or(0.0).max(0.0);
    let end = match duration_sec {
        Some(d) => (begin + d).min(total_sec),
        None => total_sec,
    };
    let span = (end - begin).max(0.0);
    if span <= 0.0 {
        return Err("gif: zero-length segment after trim".into());
    }

    let fps = fps.max(1).min(50);
    let frame_count = ((span * fps as f64).ceil() as u32).max(1);
    let delay_ms = (1000.0 / fps as f64).round() as u32;

    let _ = sink.add(TranscodeProgress {
        phase: "encoding".into(),
        fraction: 0.0,
        message: Some(format!("Extracting {frame_count} frames")),
    });

    let mut frames = Vec::with_capacity(frame_count as usize);
    for i in 0..frame_count {
        let t = begin + span * (i as f64 / frame_count as f64);
        let png_bytes = thumbnail_image(input_path, t, max_edge, ThumbnailFormat::Png)?;
        frames.push(GifFrame { png_bytes });

        let frac = (i as f64 + 1.0) / frame_count as f64 * 0.9;
        let _ = sink.add(TranscodeProgress {
            phase: "encoding".into(),
            fraction: frac.clamp(0.0, 0.9),
            message: None,
        });
    }

    let _ = sink.add(TranscodeProgress {
        phase: "encoding".into(),
        fraction: 0.9,
        message: Some("Assembling GIF".into()),
    });

    assemble_gif(output_path, &frames, delay_ms)?;

    let _ = sink.add(TranscodeProgress {
        phase: "done".into(),
        fraction: 1.0,
        message: None,
    });
    Ok(())
}
