use serde::{Deserialize, Serialize};

use crate::api::video;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoInfo {
    pub duration_ms: u64,
    pub width: u32,
    pub height: u32,
    pub size_bytes: u64,
    pub bitrate: Option<u64>,
    pub codec_name: Option<String>,
    pub format_name: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThumbnailParams {
    pub time_ms: u64,   // position to grab frame
    pub max_width: u32, // scale down
    pub max_height: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompressParams {
    pub target_bitrate_kbps: u32,
    pub preset: Option<String>, // e.g. "veryfast"
    pub crf: Option<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompressProgress {
    pub processed_ms: u64,
    pub total_ms: u64,
    pub speed_x: f32,
}

/// Exposed via FRB
pub fn get_video_info(path: String) -> anyhow::Result<VideoInfo> {
    video::get_video_info(&path)
}

/// returns PNG bytes of a thumbnail
pub fn generate_thumbnail(path: String, params: ThumbnailParams) -> anyhow::Result<Vec<u8>> {
    video::generate_thumbnail(&path, &params)
}
