//! FRB API surface: probe, thumbnail, transcode (desktop via bundled FFmpeg when present), Android via platform APIs.

use crate::frb_generated::StreamSink;

#[derive(Clone, Debug)]
pub struct VideoProbe {
    pub duration_ms: Option<i64>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub video_bitrate: Option<i64>,
    pub audio_bitrate: Option<i64>,
    pub frame_rate: Option<f64>,
    pub video_codec: Option<String>,
    pub audio_codec: Option<String>,
}

#[derive(Clone, Debug)]
pub struct TranscodeProgress {
    pub phase: String,
    pub fraction: f64,
    pub message: Option<String>,
}

/// Thumbnail image encoding for [thumbnail_image] / [thumbnail_save_to_path] / [timeline_thumbnails].
#[derive(Clone, Copy, Debug)]
pub enum ThumbnailFormat {
    Png,
    Jpeg,
    Webp,
}

#[derive(Clone, Debug)]
pub struct TimelineThumbnail {
    pub index: u32,
    pub time_sec: f64,
    pub image_bytes: Vec<u8>,
}

pub async fn probe_video(path: String) -> Result<VideoProbe, String> {
    #[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
    {
        return crate::platform::desktop::probe_ffprobe(&path).await;
    }
    #[cfg(target_os = "android")]
    {
        return crate::platform::android::probe_media_extractor(&path);
    }
    #[cfg(target_os = "ios")]
    {
        return crate::platform::ios::probe_avasset(&path);
    }
    #[cfg(not(any(
        target_os = "linux",
        target_os = "macos",
        target_os = "windows",
        target_os = "android",
        target_os = "ios"
    )))]
    {
        let _ = path;
        Err("probe_video: unsupported target OS".to_string())
    }
}

pub async fn thumbnail_image(
    path: String,
    time_sec: f64,
    max_edge: u32,
    format: ThumbnailFormat,
) -> Result<Vec<u8>, String> {
    #[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
    {
        return crate::platform::desktop::thumbnail_ffmpeg(&path, time_sec, max_edge, format).await;
    }
    #[cfg(target_os = "android")]
    {
        return tokio::task::spawn_blocking(move || {
            crate::platform::android::thumbnail_image(&path, time_sec, max_edge, format)
        })
        .await
        .map_err(|e| format!("thumbnail_image: {e}"))?;
    }
    #[cfg(target_os = "ios")]
    {
        return tokio::task::spawn_blocking(move || {
            crate::platform::ios::thumbnail_image(&path, time_sec, max_edge, format)
        })
        .await
        .map_err(|e| format!("thumbnail_image: {e}"))?;
    }
    #[cfg(not(any(
        target_os = "linux",
        target_os = "macos",
        target_os = "windows",
        target_os = "android",
        target_os = "ios"
    )))]
    {
        let _ = (path, time_sec, max_edge, format);
        Err("thumbnail_image: unsupported target OS".to_string())
    }
}

pub async fn thumbnail_save_to_path(
    path: String,
    output_path: String,
    time_sec: f64,
    max_edge: u32,
    format: ThumbnailFormat,
) -> Result<String, String> {
    #[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
    {
        return crate::platform::desktop::thumbnail_save_ffmpeg(
            &path,
            &output_path,
            time_sec,
            max_edge,
            format,
        )
        .await;
    }
    #[cfg(target_os = "android")]
    {
        return tokio::task::spawn_blocking(move || {
            crate::platform::android::thumbnail_save_to_path(
                &path,
                &output_path,
                time_sec,
                max_edge,
                format,
            )
        })
        .await
        .map_err(|e| format!("thumbnail_save_to_path: {e}"))?;
    }
    #[cfg(target_os = "ios")]
    {
        return tokio::task::spawn_blocking(move || {
            crate::platform::ios::thumbnail_save_to_path(
                &path,
                &output_path,
                time_sec,
                max_edge,
                format,
            )
        })
        .await
        .map_err(|e| format!("thumbnail_save_to_path: {e}"))?;
    }
    #[cfg(not(any(
        target_os = "linux",
        target_os = "macos",
        target_os = "windows",
        target_os = "android",
        target_os = "ios"
    )))]
    {
        let _ = (path, output_path, time_sec, max_edge, format);
        Err("thumbnail_save_to_path: unsupported target OS".to_string())
    }
}

pub async fn timeline_thumbnails(
    path: String,
    frame_count: u32,
    max_edge: u32,
    format: ThumbnailFormat,
    sink: StreamSink<TimelineThumbnail>,
) -> Result<(), String> {
    #[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
    {
        return crate::platform::desktop::timeline_thumbnails_ffmpeg(
            &path,
            frame_count,
            max_edge,
            format,
            sink,
        )
        .await;
    }
    #[cfg(target_os = "android")]
    {
        return tokio::task::spawn_blocking(move || {
            crate::platform::android::timeline_thumbnails(
                &path,
                frame_count,
                max_edge,
                format,
                sink,
            )
        })
        .await
        .map_err(|e| format!("timeline_thumbnails: {e}"))?;
    }
    #[cfg(target_os = "ios")]
    {
        return tokio::task::spawn_blocking(move || {
            crate::platform::ios::timeline_thumbnails(&path, frame_count, max_edge, format, sink)
        })
        .await
        .map_err(|e| format!("timeline_thumbnails: {e}"))?;
    }
    #[cfg(not(any(
        target_os = "linux",
        target_os = "macos",
        target_os = "windows",
        target_os = "android",
        target_os = "ios"
    )))]
    {
        let _ = (path, frame_count, max_edge, format, sink);
        Err("timeline_thumbnails: unsupported target OS".to_string())
    }
}

pub async fn video_to_gif(
    input_path: String,
    output_path: String,
    fps: u32,
    max_edge: u32,
    start_sec: Option<f64>,
    duration_sec: Option<f64>,
    sink: StreamSink<TranscodeProgress>,
) -> Result<(), String> {
    #[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
    {
        return crate::platform::desktop::video_to_gif_ffmpeg(
            &input_path,
            &output_path,
            fps,
            max_edge,
            start_sec,
            duration_sec,
            sink,
        )
        .await;
    }
    #[cfg(target_os = "android")]
    {
        return tokio::task::spawn_blocking(move || {
            crate::platform::android::video_to_gif(
                &input_path,
                &output_path,
                fps,
                max_edge,
                start_sec,
                duration_sec,
                sink,
            )
        })
        .await
        .map_err(|e| format!("video_to_gif: {e}"))?;
    }
    #[cfg(target_os = "ios")]
    {
        return tokio::task::spawn_blocking(move || {
            crate::platform::ios::video_to_gif(
                &input_path,
                &output_path,
                fps,
                max_edge,
                start_sec,
                duration_sec,
                sink,
            )
        })
        .await
        .map_err(|e| format!("video_to_gif: {e}"))?;
    }
    #[cfg(not(any(
        target_os = "linux",
        target_os = "macos",
        target_os = "windows",
        target_os = "android",
        target_os = "ios"
    )))]
    {
        let _ = (input_path, output_path, fps, max_edge, start_sec, duration_sec, sink);
        Err("video_to_gif: unsupported OS".to_string())
    }
}

pub async fn transcode_video(
    input_path: String,
    output_path: String,
    video_bitrate_kbps: u32,
    max_width: u32,
    audio_bitrate_kbps: u32,
    sink: StreamSink<TranscodeProgress>,
) -> Result<(), String> {
    #[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
    {
        return crate::platform::desktop::transcode_ffmpeg(
            &input_path,
            &output_path,
            video_bitrate_kbps,
            max_width,
            audio_bitrate_kbps,
            sink,
        )
        .await;
    }
    #[cfg(target_os = "android")]
    {
        return tokio::task::spawn_blocking(move || {
            crate::platform::android::transcode_video(
                &input_path,
                &output_path,
                video_bitrate_kbps,
                max_width,
                audio_bitrate_kbps,
                sink,
            )
        })
        .await
        .map_err(|e| format!("transcode_video: {e}"))?;
    }
    #[cfg(target_os = "ios")]
    {
        return tokio::task::spawn_blocking(move || {
            crate::platform::ios::transcode_export(
                &input_path,
                &output_path,
                video_bitrate_kbps,
                max_width,
                audio_bitrate_kbps,
                sink,
            )
        })
        .await
        .map_err(|e| format!("transcode_video: {e}"))?;
    }
    #[cfg(not(any(
        target_os = "linux",
        target_os = "macos",
        target_os = "windows",
        target_os = "android",
        target_os = "ios"
    )))]
    {
        let _ = (
            input_path,
            output_path,
            video_bitrate_kbps,
            max_width,
            audio_bitrate_kbps,
            sink,
        );
        Err("transcode_video: unsupported OS".to_string())
    }
}
