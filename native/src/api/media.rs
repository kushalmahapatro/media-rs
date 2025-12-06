use crate::api::video::{self, check_output_path, get_file_name_without_extension};
use crate::frb_generated::StreamSink;
use anyhow::{Context, Error};
use serde::{Deserialize, Serialize};

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
    pub time_ms: u64, // position to grab framen
    pub size_type: Option<ThumbnailSizeType>,
    pub format: Option<OutputFormat>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImageThumbnailParams {
    pub size_type: Option<ThumbnailSizeType>,
    pub format: Option<OutputFormat>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompressParams {
    pub target_bitrate_kbps: u32,
    pub preset: Option<String>, // e.g. "veryfast"
    pub crf: Option<u8>,
    pub width: Option<u32>,
    pub height: Option<u32>,
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
) -> Result<String, Error> {
    let thumbnail = video::generate_thumbnail(&path, &params)?;

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

    std::fs::write(output_path, thumbnail)?;

    Ok(output_path_str)
}

pub fn generate_video_timeline_thumbnails(
    path: String,
    output_path: String,
    params: Option<ImageThumbnailParams>,
    num_thumbnails: u32,
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

    let video_info = video::get_video_info(&path).unwrap();
    let duration_ms = video_info.duration_ms;
    let time_ms = duration_ms / num_thumbnails as u64;

    for i in 0..num_thumbnails {
        let params = VideoThumbnailParams {
            time_ms: time_ms * i as u64,
            size_type: Some(size),
            format: Some(output_format),
        };
        let thumbnail = video::generate_thumbnail(&path, &params).unwrap();
        let output_path = base_output_dir.join(format!(
            "thumbnail_{}_{}.{}",
            filename_without_extension.display(),
            i,
            output_format.extension()
        ));
        let output_path_str = output_path.to_string_lossy().to_string();
        std::fs::write(output_path, thumbnail).unwrap();
        sink.add(output_path_str)
            .map_err(|_| anyhow::anyhow!("Sink closed"))?;
    }
    Ok(())
}

pub async fn generate_image_thumbnail(
    path: String,
    output_path: String,
    params: Option<ImageThumbnailParams>,
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

    let output_file_name = format!(
        "thumbnail_{}.{}",
        filename_without_extension.display(),
        output_format.extension()
    );
    let output_path = base_output_dir.join(output_file_name);
    let output_path_str = output_path.to_string_lossy().to_string();

    let img = image::open(path).context("Failed to open or decode image file")?;

    let thumbnail = img.thumbnail(size.0, size.1);

    match output_format {
        OutputFormat::JPEG => {
            thumbnail
                .save_with_format(output_path, image::ImageFormat::Jpeg)
                .context("Failed to save JPEG thumbnail")?;
        }
        OutputFormat::PNG => {
            thumbnail
                .save_with_format(output_path, image::ImageFormat::Png)
                .context("Failed to save PNG thumbnail")?;
        }
        OutputFormat::WEBP => {
            thumbnail
                .save_with_format(output_path, image::ImageFormat::WebP)
                .context("Failed to save WebP thumbnail")?;
        }
    }

    Ok(output_path_str)
}

pub fn estimate_compression(
    path: String,
    temp_output_path: String,
    params: CompressParams,
) -> Result<CompressionEstimate, Error> {
    let result = video::estimate_compression(&path, &temp_output_path, &params);
    match result {
        Ok(stats) => Ok(stats),
        Err(e) => Err(e.into()),
    }
}

pub fn compress_video(
    path: String,
    output_path: String,
    params: CompressParams,
) -> Result<String, Error> {
    let result = video::compress_video(&path, &output_path, &params);
    match result {
        Ok(stats) => Ok(stats),
        Err(e) => Err(e.into()),
    }
}
