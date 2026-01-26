use anyhow::{Context, Result};
use std::path::{Path, PathBuf};
use std::process::Command;
#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;
use tracing::{debug, error, info, warn};

use crate::api::media::CompressParams;

/// Statistics from a compression operation
#[derive(Debug, Clone)]
pub struct CompressionStats {
    pub encoded_size_bytes: u64,
    pub processed_duration_ms: u64,
    pub elapsed_ms: u64,
}

/// FFmpeg process wrapper for cross-platform video compression
pub struct FFmpegProcess {
    ffmpeg_path: PathBuf,
}

impl FFmpegProcess {
    /// Create a new FFmpeg process wrapper by locating the FFmpeg binary
    pub fn new() -> Result<Self> {
        let ffmpeg_path = Self::locate_ffmpeg_binary()?;
        debug!("FFmpegProcess initialized with binary: {}", ffmpeg_path.display());
        Ok(Self { ffmpeg_path })
    }

    /// Locate the FFmpeg binary on the system
    fn locate_ffmpeg_binary() -> Result<PathBuf> {
        // 1. Priority: FFMPEG_DIR environment variable (User override or setup script)
        if let Ok(dir) = std::env::var("FFMPEG_DIR") {
            let dir_path = PathBuf::from(&dir);
            debug!("Checking FFMPEG_DIR: {}", dir);
            
            #[cfg(target_os = "windows")]
            let candidates = [
                dir_path.join("bin").join("ffmpeg.exe"),
                dir_path.join("ffmpeg.exe"),
                dir_path.clone(), // If user pointed directly to executable
            ];
            
            #[cfg(not(target_os = "windows"))]
            let candidates = [
                dir_path.join("bin").join("ffmpeg"),
                dir_path.join("ffmpeg"),
                dir_path.clone(),
            ];
            
            for path in &candidates {
                if path.exists() && path.is_file() {
                    info!("Found FFmpeg from FFMPEG_DIR: {}", path.display());
                    return Ok(path.clone());
                }
            }
        }

        // 2. Try platform-specific paths first (from our build)
        let platform_paths = Self::get_platform_ffmpeg_paths();
        
        for path in &platform_paths {
            if path.exists() {
                info!("Found FFmpeg binary at: {}", path.display());
                return Ok(path.clone());
            }
        }
        
        // Fallback: try to find ffmpeg in PATH
        debug!("FFmpeg not found in platform-specific paths, trying PATH");
        
        #[cfg(target_os = "windows")]
        let binary_name = "ffmpeg.exe";
        #[cfg(not(target_os = "windows"))]
        let binary_name = "ffmpeg";
        
        // Try using 'which' command
        if let Ok(output) = Command::new("which").arg(binary_name).output() {
            if output.status.success() {
                let path_str = String::from_utf8_lossy(&output.stdout).trim().to_string();
                let path = PathBuf::from(path_str);
                if path.exists() {
                    info!("Found FFmpeg in PATH: {}", path.display());
                    return Ok(path);
                }
            }
        }
        
        // On Windows, also try 'where' command
        #[cfg(target_os = "windows")]
        {
            let mut cmd = Command::new("where");
            cmd.arg(binary_name);
            cmd.creation_flags(0x08000000); // CREATE_NO_WINDOW
            
            if let Ok(output) = cmd.output() {
                if output.status.success() {
                    let path_str = String::from_utf8_lossy(&output.stdout)
                        .lines()
                        .next()
                        .unwrap_or("")
                        .trim()
                        .to_string();
                    let path = PathBuf::from(path_str);
                    if path.exists() {
                        info!("Found FFmpeg using 'where': {}", path.display());
                        return Ok(path);
                    }
                }
            }
        }
        
        Err(anyhow::anyhow!(
            "FFmpeg binary not found. Please ensure FFmpeg is installed.\n\
             Run the setup script: dart tool/setup.dart --{}\n\
             Or install FFmpeg and add it to your PATH.",
            Self::get_platform_name()
        ))
    }

    /// Get platform-specific FFmpeg binary paths
    fn get_platform_ffmpeg_paths() -> Vec<PathBuf> {
        let mut paths = Vec::new();
        
        // Get the workspace root (go up from executable to find third_party)
        if let Ok(exe_path) = std::env::current_exe() {
            // Try to find third_party directory
            let mut current = exe_path.parent();
            while let Some(dir) = current {
                let third_party = dir.join("third_party").join("generated").join("ffmpeg_install");
                if third_party.exists() {
                    // Found third_party, add platform-specific path
                    let platform_path = Self::get_platform_ffmpeg_path(&third_party);
                    paths.push(platform_path);
                    break;
                }
                current = dir.parent();
            }
        }
        
        // Also try relative to current directory
        let cwd_third_party = PathBuf::from("third_party")
            .join("generated")
            .join("ffmpeg_install");
        if cwd_third_party.exists() {
            paths.push(Self::get_platform_ffmpeg_path(&cwd_third_party));
        }
        
        paths
    }

    /// Get platform-specific FFmpeg path within the install directory
    fn get_platform_ffmpeg_path(install_dir: &Path) -> PathBuf {
        #[cfg(target_os = "windows")]
        {
            install_dir.join("windows").join("x86_64").join("bin").join("ffmpeg.exe")
        }
        
        #[cfg(target_os = "linux")]
        {
            install_dir.join("linux").join("x86_64").join("bin").join("ffmpeg")
        }
        
        #[cfg(target_os = "macos")]
        {
            install_dir.join("macos").join("x86_64").join("bin").join("ffmpeg")
        }
        
        #[cfg(target_os = "android")]
        {
            // Android uses different architecture paths
            install_dir.join("android").join("arm64-v8a").join("bin").join("ffmpeg")
        }
        
        #[cfg(target_os = "ios")]
        {
            install_dir.join("ios").join("arm64").join("bin").join("ffmpeg")
        }
    }

    /// Get platform name for error messages
    fn get_platform_name() -> &'static str {
        #[cfg(target_os = "windows")]
        return "windows";
        #[cfg(target_os = "linux")]
        return "linux";
        #[cfg(target_os = "macos")]
        return "macos";
        #[cfg(target_os = "android")]
        return "android";
        #[cfg(target_os = "ios")]
        return "ios";
    }

    /// Compress a video segment using FFmpeg process
    pub fn compress_segment(
        &self,
        input_path: &str,
        output_path: &str,
        params: &CompressParams,
        start_ms: Option<u64>,
        duration_ms: Option<u64>,
    ) -> Result<CompressionStats> {
        debug!(
            "compress_segment: input={}, output={}, start={:?}, duration={:?}",
            input_path, output_path, start_ms, duration_ms
        );

        let args = self.build_command_args(input_path, output_path, params, start_ms, duration_ms)?;
        
        debug!("FFmpeg command: {} {}", self.ffmpeg_path.display(), args.join(" "));
        
        let start_time = std::time::Instant::now();
        
        let mut cmd = Command::new(&self.ffmpeg_path);
        cmd.args(&args);
        
        #[cfg(target_os = "windows")]
        cmd.creation_flags(0x08000000); // CREATE_NO_WINDOW
        
        let output = cmd
            .output()
            .context("Failed to execute FFmpeg process")?;
        
        let elapsed_ms = start_time.elapsed().as_millis() as u64;
        
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            error!("FFmpeg process failed: {}", stderr);
            return Err(anyhow::anyhow!("FFmpeg process failed: {}", stderr));
        }
        
        // Parse output to get statistics
        let stats = self.parse_output(&output.stderr, elapsed_ms, duration_ms)?;
        
        debug!("compress_segment completed: {:?}", stats);
        Ok(stats)
    }

    /// Build FFmpeg command arguments
    fn build_command_args(
        &self,
        input_path: &str,
        output_path: &str,
        params: &CompressParams,
        start_ms: Option<u64>,
        duration_ms: Option<u64>,
    ) -> Result<Vec<String>> {
        let mut args = Vec::new();
        
        // Input file
        args.push("-i".to_string());
        args.push(input_path.to_string());
        
        // Start time (seek)
        if let Some(start) = start_ms {
            args.push("-ss".to_string());
            args.push(Self::format_timestamp(start));
        }
        
        // Duration
        if let Some(duration) = duration_ms {
            args.push("-t".to_string());
            args.push(Self::format_timestamp(duration));
        }
        
        // Video codec
        args.push("-c:v".to_string());
        args.push("libopenh264".to_string());
        
        // Bitrate
        if params.target_bitrate_kbps > 0 {
            args.push("-b:v".to_string());
            args.push(format!("{}k", params.target_bitrate_kbps));
        }
        
        // CRF (quality)
        if let Some(crf) = params.crf {
            args.push("-crf".to_string());
            args.push(crf.to_string());
        }
        
        // Scale (resolution)
        if let (Some(width), Some(height)) = (params.width, params.height) {
            args.push("-vf".to_string());
            args.push(format!("scale={}:{}", width, height));
        }
        
        // No audio (faster encoding)
        args.push("-an".to_string());
        
        // Overwrite output
        args.push("-y".to_string());
        
        // Output file
        args.push(output_path.to_string());
        
        Ok(args)
    }

    /// Generate a thumbnail for a video using FFmpeg process
    pub fn generate_thumbnail(
        &self,
        input_path: &str,
        time_ms: u64,
        params: &crate::api::media::VideoThumbnailParams,
    ) -> Result<(Vec<u8>, u32, u32)> {
        use crate::api::media::{OutputFormat, ThumbnailSizeType};
        
        debug!("generate_thumbnail: input={}, time={}ms", input_path, time_ms);
        
        let mut args = Vec::new();
        
        // Input file
        args.push("-i".to_string());
        args.push(input_path.to_string());
        
        // Seek to timestamp
        args.push("-ss".to_string());
        args.push(Self::format_timestamp(time_ms));
        
        // Only 1 frame
        args.push("-frames:v".to_string());
        args.push("1".to_string());
        
        // Scale if needed
        if let Some(size_type) = &params.size_type {
            let (target_w, target_h) = size_type.dimensions();
            if target_w > 0 && target_h > 0 {
                args.push("-vf".to_string());
                // Force scale to specific dimensions (or aspect ratio logic could be applied here)
                // For now, consistent with existing logic:
                args.push(format!("scale={}:{}", target_w, target_h));
            }
        }
        
        // Output format
        let format = params.format.unwrap_or(OutputFormat::PNG);
        match format {
            OutputFormat::JPEG => {
                args.push("-f".to_string());
                args.push("image2pipe".to_string());
                args.push("-vcodec".to_string());
                args.push("mjpeg".to_string());
            },
            OutputFormat::PNG => {
                args.push("-f".to_string());
                args.push("image2pipe".to_string());
                args.push("-vcodec".to_string());
                args.push("png".to_string());
            },
            OutputFormat::WEBP => {
                args.push("-f".to_string());
                args.push("image2pipe".to_string());
                args.push("-vcodec".to_string());
                args.push("libwebp".to_string());
            },
        }
        
        // Output to stdout
        args.push("-".to_string());
        
        debug!("FFmpeg thumbnail command: {} {}", self.ffmpeg_path.display(), args.join(" "));
        
        let mut cmd = Command::new(&self.ffmpeg_path);
        cmd.args(&args);
        
        #[cfg(target_os = "windows")]
        cmd.creation_flags(0x08000000); // CREATE_NO_WINDOW
        
        let output = cmd
            .output()
            .context("Failed to execute FFmpeg process for thumbnail")?;
            
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            
            // Check if it's just that the timestamp is past end of file
            // (FFmpeg might exit with error or just empty output)
            if stderr.contains("Output file is empty") || output.stdout.is_empty() {
                // Try seeking to 0 as fallback? Or return error?
                // For now, return error with context
                return Err(anyhow::anyhow!("FFmpeg thumbnail failed (video likely shorter than timestamp): {}", stderr));
            }
            
            return Err(anyhow::anyhow!("FFmpeg thumbnail process failed: {}", stderr));
        }
        
        let image_data = output.stdout;
        if image_data.is_empty() {
            return Err(anyhow::anyhow!("FFmpeg generated empty thumbnail data"));
        }
        
        // Load image to get dimensions
        let img = image::load_from_memory(&image_data)
            .context("Failed to decode generated thumbnail image")?;
            
        let width = img.width();
        let height = img.height();
        
        Ok((image_data, width, height))
    }

    /// Format milliseconds as FFmpeg timestamp (HH:MM:SS.mmm)
    fn format_timestamp(ms: u64) -> String {
        let total_seconds = ms / 1000;
        let milliseconds = ms % 1000;
        let hours = total_seconds / 3600;
        let minutes = (total_seconds % 3600) / 60;
        let seconds = total_seconds % 60;
        
        format!("{:02}:{:02}:{:02}.{:03}", hours, minutes, seconds, milliseconds)
    }

    /// Parse FFmpeg output to extract statistics
    fn parse_output(
        &self,
        stderr: &[u8],
        elapsed_ms: u64,
        expected_duration_ms: Option<u64>,
    ) -> Result<CompressionStats> {
        let output_str = String::from_utf8_lossy(stderr);
        
        // FFmpeg outputs progress to stderr in format:
        // frame=   45 fps= 30 q=28.0 size=     256kB time=00:00:01.50 bitrate=1398.1kbits/s speed=1.00x
        
        let mut encoded_size_bytes = 0u64;
        let mut processed_duration_ms = 0u64;
        
        // Find the last progress line (most recent stats)
        for line in output_str.lines().rev() {
            if line.contains("size=") && line.contains("time=") {
                // Parse size
                if let Some(size_str) = Self::extract_value(line, "size=") {
                    encoded_size_bytes = Self::parse_size(&size_str).unwrap_or(0);
                }
                
                // Parse time
                if let Some(time_str) = Self::extract_value(line, "time=") {
                    processed_duration_ms = Self::parse_timestamp(&time_str).unwrap_or(0);
                }
                
                break;
            }
        }
        
        // If we couldn't parse from progress, try to get file size
        if encoded_size_bytes == 0 {
            // The output file should exist, try to get its size
            // This is a fallback - we'll use the expected duration
            processed_duration_ms = expected_duration_ms.unwrap_or(0);
        }
        
        Ok(CompressionStats {
            encoded_size_bytes,
            processed_duration_ms,
            elapsed_ms,
        })
    }

    /// Extract value from FFmpeg progress line
    fn extract_value(line: &str, key: &str) -> Option<String> {
        if let Some(start) = line.find(key) {
            let value_start = start + key.len();
            let rest = &line[value_start..];
            // Take until next space or end
            let value = rest.split_whitespace().next()?;
            Some(value.to_string())
        } else {
            None
        }
    }

    /// Parse size string (e.g., "256kB", "1024B", "2MB")
    fn parse_size(size_str: &str) -> Option<u64> {
        let size_str = size_str.trim();
        
        if size_str.ends_with("kB") {
            let num = size_str.trim_end_matches("kB").parse::<f64>().ok()?;
            Some((num * 1024.0) as u64)
        } else if size_str.ends_with("MB") {
            let num = size_str.trim_end_matches("MB").parse::<f64>().ok()?;
            Some((num * 1024.0 * 1024.0) as u64)
        } else if size_str.ends_with("GB") {
            let num = size_str.trim_end_matches("GB").parse::<f64>().ok()?;
            Some((num * 1024.0 * 1024.0 * 1024.0) as u64)
        } else if size_str.ends_with("B") {
            size_str.trim_end_matches("B").parse::<u64>().ok()
        } else {
            // Try parsing as plain number (bytes)
            size_str.parse::<u64>().ok()
        }
    }

    /// Parse timestamp string (HH:MM:SS.mmm) to milliseconds
    fn parse_timestamp(time_str: &str) -> Option<u64> {
        let parts: Vec<&str> = time_str.split(':').collect();
        if parts.len() != 3 {
            return None;
        }
        
        let hours = parts[0].parse::<u64>().ok()?;
        let minutes = parts[1].parse::<u64>().ok()?;
        
        // Seconds may have decimal part
        let seconds_parts: Vec<&str> = parts[2].split('.').collect();
        let seconds = seconds_parts[0].parse::<u64>().ok()?;
        let milliseconds = if seconds_parts.len() > 1 {
            // Pad or truncate to 3 digits
            let ms_str = format!("{:0<3}", seconds_parts[1]);
            ms_str[..3].parse::<u64>().ok()?
        } else {
            0
        };
        
        Some(hours * 3600 * 1000 + minutes * 60 * 1000 + seconds * 1000 + milliseconds)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_timestamp() {
        assert_eq!(FFmpegProcess::format_timestamp(0), "00:00:00.000");
        assert_eq!(FFmpegProcess::format_timestamp(1500), "00:00:01.500");
        assert_eq!(FFmpegProcess::format_timestamp(65000), "00:01:05.000");
        assert_eq!(FFmpegProcess::format_timestamp(3661500), "01:01:01.500");
    }

    #[test]
    fn test_parse_size() {
        assert_eq!(FFmpegProcess::parse_size("256kB"), Some(256 * 1024));
        assert_eq!(FFmpegProcess::parse_size("2MB"), Some(2 * 1024 * 1024));
        assert_eq!(FFmpegProcess::parse_size("1024B"), Some(1024));
        assert_eq!(FFmpegProcess::parse_size("1024"), Some(1024));
    }

    #[test]
    fn test_parse_timestamp() {
        assert_eq!(FFmpegProcess::parse_timestamp("00:00:01.500"), Some(1500));
        assert_eq!(FFmpegProcess::parse_timestamp("00:01:05.000"), Some(65000));
        assert_eq!(FFmpegProcess::parse_timestamp("01:01:01.500"), Some(3661500));
    }
}
