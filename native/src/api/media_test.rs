#[cfg(test)]
mod tests {
    use crate::api::media::{
        decode_image_with_ffmpeg, OutputFormat, ThumbnailSizeType, VideoThumbnailParams,
    };
    use image::GenericImageView;
    use std::path::Path;

    /// Test HEIC image decoding to ensure full image is decoded
    #[test]
    fn test_heic_image_decoding() {
        let heic_path = "../native/image.HEIC";

        // Check if test file exists
        if !Path::new(heic_path).exists() {
            eprintln!("Skipping test: {} not found", heic_path);
            return;
        }

        // Test decoding
        match decode_image_with_ffmpeg(heic_path) {
            Ok(img) => {
                let (width, height) = img.dimensions();
                println!("✓ HEIC decoded successfully: {}x{}", width, height);

                // Verify dimensions are reasonable (not just a small portion)
                assert!(width > 100, "Image width should be > 100, got {}", width);
                assert!(height > 100, "Image height should be > 100, got {}", height);

                // Verify image has content (not all zeros or single color)
                let rgb_img = img.to_rgb8();
                let pixels = rgb_img.pixels().collect::<Vec<_>>();
                assert!(!pixels.is_empty(), "Image should have pixels");

                // Check that we have color variation (not a single color)
                let first_pixel = pixels[0];
                let has_variation = pixels.iter().any(|p| {
                    p[0] != first_pixel[0] || p[1] != first_pixel[1] || p[2] != first_pixel[2]
                });
                assert!(
                    has_variation,
                    "Image should have color variation (not a single color)"
                );

                println!("✓ HEIC image has valid dimensions and color variation");
            }
            Err(e) => {
                panic!("Failed to decode HEIC image: {:?}", e);
            }
        }
    }

    /// Test video thumbnail generation to ensure full frame is captured
    #[test]
    fn test_video_thumbnail_generation() {
        use crate::api::video::*;

        let video_path = "../native/video.MOV";

        // Check if test file exists
        if !Path::new(video_path).exists() {
            eprintln!("Skipping test: {} not found", video_path);
            return;
        }

        // Test thumbnail generation at a specific time
        let params = VideoThumbnailParams {
            time_ms: 1000, // 1 second
            size_type: Some(ThumbnailSizeType::Medium),
            format: Some(OutputFormat::PNG),
        };

        match generate_thumbnail(video_path, &params) {
            Ok((thumbnail_data, width, height)) => {
                println!(
                    "✓ Video thumbnail generated successfully: {}x{}",
                    width, height
                );

                // Verify dimensions are reasonable
                assert!(width > 50, "Thumbnail width should be > 50, got {}", width);
                assert!(
                    height > 50,
                    "Thumbnail height should be > 50, got {}",
                    height
                );

                // Verify we have image data
                assert!(!thumbnail_data.is_empty(), "Thumbnail should have data");
                assert!(
                    thumbnail_data.len() > 1000,
                    "Thumbnail data should be substantial"
                );

                // Verify it's a valid PNG (starts with PNG signature)
                assert_eq!(
                    &thumbnail_data[0..8],
                    &[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
                    "Thumbnail should be a valid PNG"
                );

                // Write thumbnail to file for visual inspection
                let temp_dir = "../native/temp";
                std::fs::create_dir_all(temp_dir).expect("Failed to create temp directory");
                let output_path = format!(
                    "{}/video_thumbnail_{}ms_{}x{}.png",
                    temp_dir, params.time_ms, width, height
                );
                std::fs::write(&output_path, &thumbnail_data)
                    .expect("Failed to write thumbnail to file");
                println!("  ✓ Saved thumbnail to: {}", output_path);

                println!("✓ Video thumbnail has valid dimensions and PNG format");
            }
            Err((e, w, h)) => {
                panic!(
                    "Failed to generate video thumbnail: {:?} (dimensions: {}x{})",
                    e, w, h
                );
            }
        }
    }

    /// Test MOV video thumbnail generation with rotation handling
    /// This specifically tests the rotation issue that was reported
    #[test]
    fn test_mov_video_thumbnail_rotation() {
        use crate::api::video::*;
        use ffmpeg_next as ffmpeg;

        let video_path = "../native/video.MOV";

        // Check if test file exists
        if !Path::new(video_path).exists() {
            eprintln!("Skipping test: {} not found", video_path);
            return;
        }

        // Initialize FFmpeg to get video info
        ffmpeg::init().expect("Failed to initialize FFmpeg");

        let ictx = ffmpeg::format::input(&video_path).expect("Failed to open video file");

        let stream = ictx
            .streams()
            .best(ffmpeg::media::Type::Video)
            .expect("No video stream found");

        let context = ffmpeg::codec::context::Context::from_parameters(stream.parameters())
            .expect("Failed to create codec context");
        let decoder = context
            .decoder()
            .video()
            .expect("Failed to get video decoder");

        let stored_width = decoder.width();
        let stored_height = decoder.height();

        // Get video info to check rotation
        use crate::api::video::get_video_info;
        let video_info = get_video_info(video_path).expect("Failed to get video info");

        println!("Video info:");
        println!("  Stored dimensions: {}x{}", stored_width, stored_height);
        println!(
            "  Display dimensions: {}x{}",
            video_info.width, video_info.height
        );
        println!("  Duration: {} ms", video_info.duration_ms);

        // Check if video is rotated (stored dimensions != display dimensions)
        let is_rotated = stored_width != video_info.width || stored_height != video_info.height;

        if is_rotated {
            println!(
                "  Video is rotated (stored: {}x{}, display: {}x{})",
                stored_width, stored_height, video_info.width, video_info.height
            );

            // For rotated videos, dimensions should be swapped
            assert!(
                (stored_width == video_info.height && stored_height == video_info.width)
                    || (stored_width == video_info.width && stored_height == video_info.height),
                "Display dimensions should match stored dimensions or be swapped for rotation"
            );
        }

        // Test thumbnail generation at multiple timestamps
        let test_times = vec![500, 1000, 2000]; // 0.5s, 1s, 2s

        for time_ms in test_times {
            let params = VideoThumbnailParams {
                time_ms,
                size_type: Some(ThumbnailSizeType::Medium),
                format: Some(OutputFormat::PNG),
            };

            match generate_thumbnail(video_path, &params) {
                Ok((thumbnail_data, thumb_width, thumb_height)) => {
                    println!(
                        "✓ Thumbnail at {}ms: {}x{}",
                        time_ms, thumb_width, thumb_height
                    );

                    // Verify dimensions are reasonable
                    assert!(
                        thumb_width > 50,
                        "Thumbnail width should be > 50, got {}",
                        thumb_width
                    );
                    assert!(
                        thumb_height > 50,
                        "Thumbnail height should be > 50, got {}",
                        thumb_height
                    );

                    // Verify it's a valid PNG
                    assert_eq!(
                        &thumbnail_data[0..8],
                        &[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
                        "Thumbnail should be a valid PNG"
                    );

                    // Write thumbnail to file for visual inspection
                    let temp_dir = "../native/temp";
                    std::fs::create_dir_all(temp_dir).expect("Failed to create temp directory");
                    let output_path = format!(
                        "{}/mov_thumbnail_{}ms_{}x{}.png",
                        temp_dir, time_ms, thumb_width, thumb_height
                    );
                    std::fs::write(&output_path, &thumbnail_data)
                        .expect("Failed to write thumbnail to file");
                    println!("  ✓ Saved thumbnail to: {}", output_path);

                    // Decode the PNG to verify it's correctly oriented
                    let img = image::load_from_memory(&thumbnail_data)
                        .expect("Failed to decode thumbnail PNG");

                    let (img_width, img_height) = img.dimensions();

                    // Thumbnail dimensions should match what we returned
                    assert_eq!(
                        img_width, thumb_width,
                        "Decoded image width should match returned width"
                    );
                    assert_eq!(
                        img_height, thumb_height,
                        "Decoded image height should match returned height"
                    );

                    // For rotated videos, verify aspect ratio matches display aspect ratio
                    if is_rotated {
                        let display_aspect = video_info.width as f32 / video_info.height as f32;
                        let thumb_aspect = thumb_width as f32 / thumb_height as f32;
                        let aspect_diff = (display_aspect - thumb_aspect).abs();

                        assert!(
                            aspect_diff < 0.1,
                            "Thumbnail aspect ratio should match display aspect ratio (display: {}, thumb: {}, diff: {})",
                            display_aspect, thumb_aspect, aspect_diff
                        );

                        println!(
                            "  ✓ Thumbnail aspect ratio matches display: {} (display: {})",
                            thumb_aspect, display_aspect
                        );
                    }

                    // Verify image has content (not all zeros or single color)
                    let rgb_img = img.to_rgb8();
                    let pixels: Vec<_> = rgb_img.pixels().take(1000).collect();
                    assert!(!pixels.is_empty(), "Thumbnail should have pixels");

                    // Check for color variation
                    if pixels.len() > 1 {
                        let first_pixel = pixels[0];
                        let has_variation = pixels.iter().any(|p| {
                            p[0] != first_pixel[0]
                                || p[1] != first_pixel[1]
                                || p[2] != first_pixel[2]
                        });

                        if !has_variation {
                            eprintln!("Warning: Thumbnail appears to be a single color - might indicate rotation issue");
                        } else {
                            println!("  ✓ Thumbnail has color variation");
                        }
                    }
                }
                Err((e, w, h)) => {
                    panic!(
                        "Failed to generate thumbnail at {}ms: {:?} (dimensions: {}x{})",
                        time_ms, e, w, h
                    );
                }
            }
        }

        println!("✓ All MOV video thumbnail tests passed with rotation handling");
    }

    /// Test image thumbnail generation with HEIC
    #[test]
    fn test_image_thumbnail_from_heic() {
        let heic_path = "../native/image.HEIC";

        // Check if test file exists
        if !Path::new(heic_path).exists() {
            eprintln!("Skipping test: {} not found", heic_path);
            return;
        }

        // Note: generate_image_thumbnail is async, so we'd need a runtime
        // For now, we'll test the synchronous decode function
        match decode_image_with_ffmpeg(heic_path) {
            Ok(img) => {
                let (width, height) = img.dimensions();
                println!("✓ HEIC decoded for thumbnail test: {}x{}", width, height);

                // Create a thumbnail
                let thumbnail = img.thumbnail(512, 512);
                let (thumb_w, thumb_h) = thumbnail.dimensions();

                assert!(
                    thumb_w <= 512,
                    "Thumbnail width should be <= 512, got {}",
                    thumb_w
                );
                assert!(
                    thumb_h <= 512,
                    "Thumbnail height should be <= 512, got {}",
                    thumb_h
                );

                // Verify aspect ratio is maintained
                let aspect_ratio = width as f32 / height as f32;
                let thumb_aspect = thumb_w as f32 / thumb_h as f32;
                let aspect_diff = (aspect_ratio - thumb_aspect).abs();
                assert!(
                    aspect_diff < 0.1,
                    "Thumbnail aspect ratio should match original (orig: {}, thumb: {}, diff: {})",
                    aspect_ratio,
                    thumb_aspect,
                    aspect_diff
                );

                println!("✓ HEIC thumbnail has correct dimensions and aspect ratio");
            }
            Err(e) => {
                panic!("Failed to decode HEIC for thumbnail: {:?}", e);
            }
        }
    }

    /// Test that decoded images have reasonable pixel distribution
    /// This helps detect if we're only getting a portion of the image
    #[test]
    fn test_image_pixel_distribution() {
        let heic_path = "../native/image.HEIC";

        if !Path::new(heic_path).exists() {
            eprintln!("Skipping test: {} not found", heic_path);
            return;
        }

        match decode_image_with_ffmpeg(heic_path) {
            Ok(img) => {
                let rgb_img = img.to_rgb8();
                let (width, height) = rgb_img.dimensions();

                // Sample pixels from different regions of the image
                // Top-left
                let top_left = rgb_img.get_pixel(0, 0);
                // Top-right
                let top_right = rgb_img.get_pixel(width - 1, 0);
                // Bottom-left
                let bottom_left = rgb_img.get_pixel(0, height - 1);
                // Bottom-right
                let bottom_right = rgb_img.get_pixel(width - 1, height - 1);
                // Center
                let center = rgb_img.get_pixel(width / 2, height / 2);

                println!("Pixel samples:");
                println!(
                    "  Top-left:     RGB({}, {}, {})",
                    top_left[0], top_left[1], top_left[2]
                );
                println!(
                    "  Top-right:    RGB({}, {}, {})",
                    top_right[0], top_right[1], top_right[2]
                );
                println!(
                    "  Bottom-left:  RGB({}, {}, {})",
                    bottom_left[0], bottom_left[1], bottom_left[2]
                );
                println!(
                    "  Bottom-right: RGB({}, {}, {})",
                    bottom_right[0], bottom_right[1], bottom_right[2]
                );
                println!(
                    "  Center:       RGB({}, {}, {})",
                    center[0], center[1], center[2]
                );

                // Check that we have variation across regions
                // If all corners are the same, we might only have a portion
                let corners_same = top_left == top_right
                    && top_right == bottom_left
                    && bottom_left == bottom_right;

                if corners_same {
                    eprintln!("Warning: All corners have the same color - might indicate partial decoding");
                } else {
                    println!("✓ Image has color variation across regions");
                }

                // Verify we can access pixels at all corners (no out-of-bounds)
                assert!(
                    width > 0 && height > 0,
                    "Image should have non-zero dimensions"
                );
            }
            Err(e) => {
                panic!("Failed to decode HEIC for pixel distribution test: {:?}", e);
            }
        }
    }
}
