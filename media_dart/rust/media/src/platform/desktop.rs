//! Desktop (Linux / macOS / Windows): FFprobe + FFmpeg CLI.
//! Uses `ffmpeg` / `ffprobe` next to `libmedia` (downloaded and copied by the Dart hook).

use std::process::Stdio;
use std::time::Instant;

use crate::bundled_tools::{ffmpeg_path, ffprobe_path};
use crate::frb_generated::StreamSink;
use serde_json::Value;
use tokio::io::{AsyncBufReadExt, AsyncReadExt, BufReader};
use tokio::process::Command;

use crate::api::{ThumbnailFormat, TimelineThumbnail, TranscodeProgress, VideoProbe};

/// On Windows, suppress the console window that appears when spawning a console-subsystem
/// binary (ffmpeg/ffprobe). This also removes the ~10-30 ms latency from window creation
/// and teardown that compounds across multiple calls.
#[cfg(windows)]
fn suppress_console(cmd: &mut tokio::process::Command) {
    // CREATE_NO_WINDOW = 0x08000000
    cmd.creation_flags(0x08000000);
}

/// Coded size vs display size: phone/camera files often store landscape dimensions with 90°/270°
/// rotation metadata. Match Android `MediaFormat` `rotation-degrees` swap so probe matches players.
fn display_size_for_rotation(width: u32, height: u32, rotation_degrees: i32) -> (u32, u32) {
    let r = rotation_degrees.rem_euclid(360);
    if r == 90 || r == 270 {
        (height, width)
    } else {
        (width, height)
    }
}

/// FFprobe JSON: `side_data_list` (Display Matrix) or legacy `tags.rotate`.
fn ffprobe_stream_rotation_degrees(stream: &Value) -> i32 {
    if let Some(list) = stream.get("side_data_list").and_then(|x| x.as_array()) {
        for item in list {
            if item
                .get("side_data_type")
                .and_then(|x| x.as_str())
                .is_some_and(|t| t == "Display Matrix")
            {
                if let Some(rot) = item.get("rotation").and_then(|x| x.as_i64()) {
                    return rot as i32;
                }
            }
        }
    }
    if let Some(tags) = stream.get("tags") {
        if let Some(rot_val) = tags.get("rotate") {
            if let Some(v) = rot_val.as_i64() {
                return v as i32;
            }
            if let Some(s) = rot_val.as_str() {
                if let Ok(v) = s.parse::<i32>() {
                    return v;
                }
            }
        }
    }
    0
}

pub async fn probe_ffprobe(path: &str) -> Result<VideoProbe, String> {
    let mut cmd = Command::new(ffprobe_path());
    #[cfg(windows)]
    suppress_console(&mut cmd);
    let out = cmd
        .args([
            "-v",
            "quiet",
            "-print_format",
            "json",
            "-show_format",
            "-show_streams",
            path,
        ])
        .output()
        .await
        .map_err(|e| format!("ffprobe spawn: {e}"))?;

    if !out.status.success() {
        return Err(format!(
            "ffprobe failed (status {:?}): {}",
            out.status.code(),
            String::from_utf8_lossy(&out.stderr)
        ));
    }

    let v: Value = serde_json::from_slice(&out.stdout)
        .map_err(|e| format!("ffprobe JSON: {e}"))?;

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

    if let Some(fmt) = v.get("format") {
        if let Some(d) = fmt.get("duration").and_then(|x| x.as_str()) {
            if let Ok(sec) = d.parse::<f64>() {
                probe.duration_ms = Some((sec * 1000.0) as i64);
            }
        }
    }

    if let Some(streams) = v.get("streams").and_then(|s| s.as_array()) {
        for s in streams {
            let ctype = s
                .get("codec_type")
                .and_then(|x| x.as_str())
                .unwrap_or("");
            if ctype == "video" && probe.width.is_none() {
                let coded_w = s.get("width").and_then(|x| x.as_u64()).map(|u| u as u32);
                let coded_h = s.get("height").and_then(|x| x.as_u64()).map(|u| u as u32);
                if let (Some(cw), Some(ch)) = (coded_w, coded_h) {
                    let rot = ffprobe_stream_rotation_degrees(s);
                    let (dw, dh) = display_size_for_rotation(cw, ch, rot);
                    probe.width = Some(dw);
                    probe.height = Some(dh);
                }
                if let Some(br) = s.get("bit_rate").and_then(|x| x.as_str()) {
                    probe.video_bitrate = br.parse::<i64>().ok();
                }
                probe.video_codec = s
                    .get("codec_name")
                    .and_then(|x| x.as_str())
                    .map(String::from);
                if let Some(rfps) = s.get("r_frame_rate").and_then(|x| x.as_str()) {
                    probe.frame_rate = parse_fraction(rfps);
                }
            } else if ctype == "audio" && probe.audio_bitrate.is_none() {
                if let Some(br) = s.get("bit_rate").and_then(|x| x.as_str()) {
                    probe.audio_bitrate = br.parse::<i64>().ok();
                }
                probe.audio_codec = s
                    .get("codec_name")
                    .and_then(|x| x.as_str())
                    .map(String::from);
            }
        }
    }

    Ok(probe)
}

fn parse_fraction(s: &str) -> Option<f64> {
    let parts: Vec<&str> = s.split('/').collect();
    if parts.len() == 2 {
        let n: f64 = parts[0].parse().ok()?;
        let d: f64 = parts[1].parse().ok()?;
        if d != 0.0 {
            return Some(n / d);
        }
    }
    s.parse::<f64>().ok()
}

/// FFmpeg `scale` that caps the **longest** side to `max_edge` (even dimensions via `-2`),
/// consistent with Android transcode sizing and Dart `presetMaxLongEdge` / probe UI.
///
/// `scale=min(max_edge,iw):-2` only limits **width** (`iw`), so portrait video kept a tall
/// long edge (e.g. 640×1138) and disagreed with preset tiers.
fn scale_long_edge_vf(max_edge: u32) -> String {
    let m = max_edge.max(1);
    format!(
        "scale=w='if(gte(iw\\,ih)\\,min(iw\\,{m})\\,-2)':h='if(gte(iw\\,ih)\\,-2\\,min(ih\\,{m}))'"
    )
}

/// Same extension set as mobile static-image thumbnailing (ffmpeg still-image demuxer).
fn looks_like_static_image(path: &str) -> bool {
    let lower = path.to_ascii_lowercase();
    [
        ".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif", ".bmp", ".gif", ".tiff", ".tif",
    ]
    .iter()
    .any(|ext| lower.ends_with(ext))
}

fn append_thumbnail_output_args(cmd: &mut Command, format: ThumbnailFormat, to_stdout: bool) {
    match format {
        ThumbnailFormat::Png => {
            if to_stdout {
                cmd.args(["-f", "image2pipe", "-vcodec", "png", "-"]);
            } else {
                cmd.args(["-vcodec", "png"]);
            }
        }
        ThumbnailFormat::Jpeg => {
            if to_stdout {
                cmd.args(["-f", "image2pipe", "-vcodec", "mjpeg", "-"]);
            } else {
                cmd.args(["-vcodec", "mjpeg"]);
            }
        }
        ThumbnailFormat::Webp => {
            if to_stdout {
                cmd.args(["-c:v", "libwebp", "-quality", "80", "-f", "webp", "-"]);
            } else {
                cmd.args(["-vcodec", "libwebp", "-quality", "80"]);
            }
        }
    }
}

/// Single-frame thumbnail to stdout (PNG / MJPEG / WebP), long edge capped by [max_edge].
///
/// Still images skip `-ss`: seeking past t=0 often yields no frame for image-only inputs.
pub async fn thumbnail_ffmpeg(
    path: &str,
    time_sec: f64,
    max_edge: u32,
    format: ThumbnailFormat,
) -> Result<Vec<u8>, String> {
    let vf = scale_long_edge_vf(max_edge);
    let mut cmd = Command::new(ffmpeg_path());
    #[cfg(windows)]
    suppress_console(&mut cmd);
    cmd.args(["-hide_banner", "-loglevel", "error"]);
    if looks_like_static_image(path) {
        cmd.args(["-i", path, "-frames:v", "1", "-vf", &vf]);
    } else {
        let ss = format!("{time_sec:.3}");
        cmd.args(["-ss", &ss, "-i", path, "-frames:v", "1", "-vf", &vf]);
    }
    append_thumbnail_output_args(&mut cmd, format, true);
    let out = cmd
        .output()
        .await
        .map_err(|e| format!("ffmpeg spawn: {e}"))?;

    if !out.status.success() {
        return Err(format!(
            "ffmpeg thumbnail failed: {}",
            String::from_utf8_lossy(&out.stderr)
        ));
    }

    if out.stdout.is_empty() {
        return Err("ffmpeg produced empty image".into());
    }

    Ok(out.stdout)
}

pub async fn thumbnail_save_ffmpeg(
    path: &str,
    output_path: &str,
    time_sec: f64,
    max_edge: u32,
    format: ThumbnailFormat,
) -> Result<String, String> {
    let vf = scale_long_edge_vf(max_edge);
    let mut cmd = Command::new(ffmpeg_path());
    #[cfg(windows)]
    suppress_console(&mut cmd);
    cmd.args(["-hide_banner", "-loglevel", "error"]);
    if looks_like_static_image(path) {
        cmd.args(["-i", path, "-frames:v", "1", "-vf", &vf]);
    } else {
        let ss = format!("{time_sec:.3}");
        cmd.args(["-ss", &ss, "-i", path, "-frames:v", "1", "-vf", &vf]);
    }
    append_thumbnail_output_args(&mut cmd, format, false);
    cmd.args(["-y", output_path]);
    let out = cmd
        .output()
        .await
        .map_err(|e| format!("ffmpeg spawn: {e}"))?;

    if !out.status.success() {
        return Err(format!(
            "ffmpeg thumbnail save failed: {}",
            String::from_utf8_lossy(&out.stderr)
        ));
    }

    Ok(std::path::Path::new(output_path)
        .canonicalize()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|_| output_path.to_string()))
}

pub async fn timeline_thumbnails_ffmpeg(
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
        let bytes = thumbnail_ffmpeg(path, 0.0, max_edge, format).await?;
        for i in 0..frame_count {
            let _ = sink.add(TimelineThumbnail {
                index: i,
                time_sec: 0.0,
                image_bytes: bytes.clone(),
            });
        }
        return Ok(());
    }
    let probe = probe_ffprobe(path).await?;
    let dur_sec = probe
        .duration_ms
        .filter(|&ms| ms > 0)
        .map(|ms| ms as f64 / 1000.0)
        .ok_or_else(|| "timeline: unknown or zero duration (ffprobe)".to_string())?;

    let n = frame_count as f64;
    for i in 0..frame_count {
        let t = dur_sec * (i as f64 + 0.5) / n;
        let bytes = thumbnail_ffmpeg(path, t, max_edge, format).await?;
        let _ = sink.add(TimelineThumbnail {
            index: i,
            time_sec: t,
            image_bytes: bytes,
        });
    }
    Ok(())
}

async fn drain_progress_stdout(
    stdout: tokio::process::ChildStdout,
    sink: StreamSink<TranscodeProgress>,
    total_ms: f64,
) -> Result<(), String> {
    /// FFmpeg `-progress pipe:1` can emit many lines per second; forwarding each one to Dart
    /// triggers a rebuild and can freeze the UI (especially on mobile / low-end devices).
    const MIN_EMIT_INTERVAL_MS: u128 = 120;
    let mut reader = BufReader::new(stdout).lines();
    let mut last_emit: Option<Instant> = None;
    let mut last_fraction: Option<f64> = None;
    while let Ok(Some(line)) = reader.next_line().await {
        if let Some(rest) = line.strip_prefix("out_time_ms=") {
            if let Ok(us) = rest.trim().parse::<i64>() {
                let ms = us / 1000;
                let frac = (ms as f64 / total_ms).clamp(0.0, 0.999);
                let elapsed_ok = last_emit.map_or(true, |t| t.elapsed().as_millis() >= MIN_EMIT_INTERVAL_MS);
                let jump = last_fraction.map_or(true, |p| (frac - p).abs() >= 0.02);
                if elapsed_ok || jump {
                    last_emit = Some(Instant::now());
                    last_fraction = Some(frac);
                    let _ = sink.add(TranscodeProgress {
                        phase: "encoding".into(),
                        fraction: frac,
                        message: None,
                    });
                }
            }
        }
    }
    Ok(())
}

async fn read_stderr_to_string(stderr: Option<tokio::process::ChildStderr>) -> String {
    let mut buf = Vec::new();
    if let Some(mut s) = stderr {
        let _ = s.read_to_end(&mut buf).await;
    }
    let text = String::from_utf8_lossy(&buf).trim().to_string();
    if text.is_empty() {
        "(no stderr; try running the same ffmpeg command in a terminal)".into()
    } else {
        text
    }
}

pub async fn transcode_ffmpeg(
    input_path: &str,
    output_path: &str,
    video_bitrate_kbps: u32,
    max_width: u32,
    audio_bitrate_kbps: u32,
    sink: StreamSink<TranscodeProgress>,
) -> Result<(), String> {
    let _ = sink.add(TranscodeProgress {
        phase: "starting".into(),
        fraction: 0.0,
        message: Some("Launching FFmpeg".into()),
    });

    let probe = probe_ffprobe(input_path).await?;
    let total_ms = probe.duration_ms.unwrap_or(0).max(1) as f64;

    let br = format!("{}k", video_bitrate_kbps);
    let abr = format!("{}k", audio_bitrate_kbps);
    let vf = scale_long_edge_vf(max_width.max(2));

    // macOS Homebrew FFmpeg often ships without libx264; VideoToolbox is always available.
    #[cfg(target_os = "macos")]
    let video_args: Vec<String> = vec![
        "-c:v".into(),
        "h264_videotoolbox".into(),
        "-b:v".into(),
        br.clone(),
        "-allow_sw".into(),
        "1".into(),
        "-pix_fmt".into(),
        "yuv420p".into(),
    ];
    #[cfg(not(target_os = "macos"))]
    let video_args: Vec<String> = vec![
        "-c:v".into(),
        "libx264".into(),
        "-preset".into(),
        "fast".into(),
        "-b:v".into(),
        br.clone(),
    ];

    let mut cmd = Command::new(ffmpeg_path());
    #[cfg(windows)]
    suppress_console(&mut cmd);
    cmd.args([
        "-hide_banner",
        "-nostats",
        "-progress",
        "pipe:1",
        "-loglevel",
        "error",
        "-i",
        input_path,
    ]);
    for i in (0..video_args.len()).step_by(2) {
        cmd.arg(&video_args[i]);
        if i + 1 < video_args.len() {
            cmd.arg(&video_args[i + 1]);
        }
    }
    cmd.args([
        "-vf",
        &vf,
        "-c:a",
        "aac",
        "-b:a",
        &abr,
        "-movflags",
        "+faststart",
        "-y",
        output_path,
    ]);
    cmd.stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);

    let mut child = cmd
        .spawn()
        .map_err(|e| format!("ffmpeg transcode spawn: {e}"))?;

    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "ffmpeg: no stdout for -progress".to_string())?;
    let stderr = child.stderr.take();

    let progress_fut = drain_progress_stdout(stdout, sink, total_ms);
    let stderr_fut = read_stderr_to_string(stderr);
    let (progress_res, stderr_text, status) =
        tokio::join!(progress_fut, stderr_fut, child.wait());
    progress_res?;

    let status = status.map_err(|e| format!("ffmpeg wait: {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!(
            "ffmpeg transcode failed ({status}): {stderr_text}"
        ))
    }
}
