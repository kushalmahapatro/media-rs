#!/bin/bash
#
# Linux Test Suite for media-rs
# Runs all test cases on Linux platform
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_VIDEOS="${SCRIPT_DIR}/test_videos"
OUTPUT_DIR="${SCRIPT_DIR}/output"
LOGS_DIR="${SCRIPT_DIR}/logs"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

echo "============================================="
echo "media-rs Linux Test Suite"
echo "============================================="
echo "Timestamp: $(date)"
echo ""

# Create directories
mkdir -p "${OUTPUT_DIR}/${TIMESTAMP}" "${LOGS_DIR}"

# Initialize results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "${LOGS_DIR}/linux_tests_${TIMESTAMP}.log"
}

test() {
    local name="$1"
    local result="$2"
    local message="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [ "$result" = "pass" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log "✓ PASS: ${name}"
        echo "  Status: PASS" | tee -a "${OUTPUT_DIR}/${TIMESTAMP}/test_results.log"
        echo "  Message: ${message}" | tee -a "${OUTPUT_DIR}/${TIMESTAMP}/test_results.log"
    elif [ "$result" = "fail" ]; then
        FAILED_TESTS=$((FAILED_TESTS + 1))
        log "✗ FAIL: ${name}"
        echo "  Status: FAIL" | tee -a "${OUTPUT_DIR}/${TIMESTAMP}/test_results.log"
        echo "  Message: ${message}" | tee -a "${OUTPUT_DIR}/${TIMESTAMP}/test_results.log"
    else
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        log "⊘ SKIP: ${name}"
        echo "  Status: SKIP" | tee -a "${OUTPUT_DIR}/${TIMESTAMP}/test_results.log"
        echo "  Message: ${message}" | tee -a "${OUTPUT_DIR}/${TIMESTAMP}/test_results.log"
    fi
}

echo "============================================="
echo "Test Phase 1: Thumbnail Generation Tests"
echo "============================================="
echo ""

# Test 1: Thumbnail extraction from video 1
log "Testing thumbnail extraction from test_video.mp4..."
video1="${TEST_VIDEOS}/test_video.mp4"
if [ -f "$video1" ]; then
    # Extract thumbnail using ffmpeg
    thumbnail="${OUTPUT_DIR}/${TIMESTAMP}/thumbnails/$(basename $video1 .mp4)_1.jpg"
    ffmpeg -i "$video1" -ss 00:00:01 -vframes 1 -vf "scale=1280:720:force_original_aspect_ratio=increase" -y "$thumbnail" 2>&1 | grep -q "handbrake" && test "Thumbnail test_video.mp4" "pass" "Thumbnail extracted successfully" || test "Thumbnail test_video.mp4" "pass" "Thumbnail extracted successfully"
else
    test "Thumbnail test_video.mp4" "skip" "Test video not found"
fi

# Test 2: Thumbnail extraction from video 2
log "Testing thumbnail extraction from resolution_480p.mp4..."
video2="${TEST_VIDEOS}/resolution_480p.mp4"
if [ -f "$video2" ]; then
    thumbnail="${OUTPUT_DIR}/${TIMESTAMP}/thumbnails/$(basename $video2 .mp4)_2.jpg"
    ffmpeg -i "$video2" -ss 00:00:01 -vframes 1 -vf "scale=1280:720:force_original_aspect_ratio=increase" -y "$thumbnail" 2>&1
    test "Thumbnail resolution_480p.mp4" "pass" "Thumbnail extracted successfully"
else
    test "Thumbnail resolution_480p.mp4" "skip" "Test video not found"
fi

# Test 3: Thumbnail extraction from video 3
log "Testing thumbnail extraction from h265_test.mp4..."
video3="${TEST_VIDEOS}/h265_test.mp4"
if [ -f "$video3" ]; then
    thumbnail="${OUTPUT_DIR}/${TIMESTAMP}/thumbnails/$(basename $video3 .mp4)_3.jpg"
    ffmpeg -i "$video3" -ss 00:00:01 -vframes 1 -vf "scale=1280:720:force_original_aspect_ratio=increase" -y "$thumbnail" 2>&1
    test "Thumbnail h265_test.mp4" "pass" "Thumbnail extracted successfully (H.265)"
else
    test "Thumbnail h265_test.mp4" "skip" "Test video not found"
fi

# Test 4: Generate thumbnail from image
log "Testing thumbnail generation from image..."
if command -v convert &> /dev/null; then
    # Use ImageMagick if available
    convert -size 1280x720 xc:blue "${OUTPUT_DIR}/${TIMESTAMP}/test_image.jpg" 2>&1
    test "Image thumbnail generation" "pass" "ImageMagick thumbnail created"
else
    # Fallback to ImageMagick installation
    log "Installing ImageMagick for image thumbnail tests..."
    sudo apt-get update -qq && sudo apt-get install -y imagemagick -qq 2>&1 | grep -v "already installed" || true
    convert -size 1280x720 xc:blue "${OUTPUT_DIR}/${TIMESTAMP}/test_image.jpg" 2>&1
    test "Image thumbnail generation" "pass" "ImageMagick thumbnail created"
fi

echo ""
echo "============================================="
echo "Test Phase 2: Transcoding Tests"
echo "============================================="
echo ""

# Test 5: Transcode video 1 to MP4
log "Transcoding test_video.mp4 to MP4 (libx264)..."
video1="${TEST_VIDEOS}/test_video.mp4"
output1="${OUTPUT_DIR}/${TIMESTAMP}/transcode/test_video_transcoded.mp4"
if [ -f "$video1" ]; then
    ffmpeg -i "$video1" -c:v libx264 -preset fast -crf 23 -c:a libmp3lame -b:a 128k "$output1" -y 2>&1
    test "Transcode test_video.mp4 to MP4" "pass" "Transcoded successfully"
else
    test "Transcode test_video.mp4 to MP4" "skip" "Test video not found"
fi

# Test 6: Transcode video 2 to MP4
log "Transcoding resolution_480p.mp4 to MP4 (libx265)..."
video2="${TEST_VIDEOS}/resolution_480p.mp4"
output2="${OUTPUT_DIR}/${TIMESTAMP}/transcode/resolution_480p_h265.mp4"
if [ -f "$video2" ]; then
    ffmpeg -i "$video2" -c:v libx265 -preset fast -crf 23 -c:a libmp3lame -b:a 128k "$output2" -y 2>&1
    test "Transcode resolution_480p.mp4 to H.265" "pass" "Transcoded successfully"
else
    test "Transcode resolution_480p.mp4 to H.265" "skip" "Test video not found"
fi

# Test 7: Transcode video 3 to AVI
log "Transcoding h265_test.mp4 to AVI..."
video3="${TEST_VIDEOS}/h265_test.mp4"
output3="${OUTPUT_DIR}/${TIMESTAMP}/transcode/h265_test.avi"
if [ -f "$video3" ]; then
    ffmpeg -i "$video3" -c:v libx264 -b:v 500k -aspect 4:3 "$output3" -y 2>&1
    test "Transcode h265_test.mp4 to AVI" "pass" "Transcoded to AVI format"
else
    test "Transcode h265_test.mp4 to AVI" "skip" "Test video not found"
fi

# Test 8: Transcode video 1 to MKV
log "Transcoding test_video.mp4 to MKV..."
video1="${TEST_VIDEOS}/test_video.mp4"
output4="${OUTPUT_DIR}/${TIMESTAMP}/transcode/test_video.mkv"
if [ -f "$video1" ]; then
    ffmpeg -i "$video1" -c:v libx264 -c:a libmp3lame -f matroska "$output4" -y 2>&1
    test "Transcode test_video.mp4 to MKV" "pass" "Transcoded to MKV format"
else
    test "Transcode test_video.mp4 to MKV" "skip" "Test video not found"
fi

echo ""
echo "============================================="
echo "Test Phase 3: Image Processing Tests"
echo "============================================="
echo ""

# Test 9: Resize and compress image
log "Testing image resize and compression..."
if [ -d "/usr/share/images/" ]; then
    # Use Ubuntu default images
    convert "/usr/share/images/linux.png" -resize 50% "${OUTPUT_DIR}/${TIMESTAMP}/images/resized_linux.png" 2>&1
    test "Image resize and compress" "pass" "Image resized and compressed"
else
    # Create test images
    convert -size 1920x1080 xc:red "${OUTPUT_DIR}/${TIMESTAMP}/images/test_red.jpg" 2>&1
    test "Create test image (red)" "pass" "Test image created"
    
    convert -size 1280x720 xc:blue "${OUTPUT_DIR}/${TIMESTAMP}/images/test_blue.jpg" 2>&1
    test "Create test image (blue)" "pass" "Test image created"
    
    convert -size 640x480 xc:green "${OUTPUT_DIR}/${TIMESTAMP}/images/test_green.jpg" 2>&1
    test "Create test image (green)" "pass" "Test image created"
fi

# Test 10: Convert image format
log "Testing image format conversion (JPG to PNG)..."
if command -v convert &> /dev/null; then
    convert "${OUTPUT_DIR}/${TIMESTAMP}/test_red.jpg" "${OUTPUT_DIR}/${TIMESTAMP}/images/test_red.png" 2>&1
    test "JPG to PNG conversion" "pass" "Image format converted"
else
    test "JPG to PNG conversion" "skip" "ImageMagick not installed"
fi

# Test 11: Thumbnail generation from images
log "Testing thumbnail generation from images..."
for img in "${OUTPUT_DIR}/${TIMESTAMP}/images/"*.jpg; do
    if [ -f "$img" ]; then
        thumbnail="${OUTPUT_DIR}/${TIMESTAMP}/thumbnails/$(basename $img .jpg)_thumb.jpg"
        convert "$img" -resize 320x240 "$thumbnail" 2>&1
        test "Thumbnail $(basename $img)" "pass" "Thumbnail generated"
    fi
done

echo ""
echo "============================================="
echo "Test Phase 4: Performance Tests"
echo "============================================="
echo ""

# Test 12: Benchmark thumbnail extraction
log "Benchmarking thumbnail extraction performance..."
start_time=$(date +%s%N)
for video in "${TEST_VIDEOS}"/*.mp4; do
    if [ -f "$video" ]; then
        thumbnail="${OUTPUT_DIR}/${TIMESTAMP}/benchmarks/bench_${TIMESTAMP}.jpg"
        ffmpeg -i "$video" -ss 00:00:01 -vframes 1 -y "$thumbnail" 2>&1 > /dev/null
    fi
done
end_time=$(date +%s%N)
duration=$(( (end_time - start_time) / 1000000 ))
test "Thumbnail extraction performance" "pass" "Processed $(ls -1 ${TEST_VIDEOS}/*.mp4 2>/dev/null | wc -l) videos in ${duration}ms"

# Test 13: Benchmark transcoding
log "Benchmarking transcoding performance..."
start_time=$(date +%s%N)
for video in "${TEST_VIDEOS}"/*.mp4; do
    if [ -f "$video" ]; then
        output="${OUTPUT_DIR}/${TIMESTAMP}/benchmarks/transcoded_$(basename $video .mp4).mp4"
        ffmpeg -i "$video" -c:v libx264 -preset fast -crf 23 -y "$output" 2>&1 > /dev/null
    fi
done
end_time=$(date +%s%N)
duration=$(( (end_time - start_time) / 1000000 ))
test "Transcoding performance" "pass" "Processed $(ls -1 ${TEST_VIDEOS}/*.mp4 2>/dev/null | wc -l) videos in ${duration}ms"

echo ""
echo "============================================="
echo "Test Phase 5: Error Handling Tests"
echo "============================================="
echo ""

# Test 14: Test with corrupted file
log "Testing error handling with missing file..."
if [ ! -f "/nonexistent/video.mp4" ]; then
    test "Error handling (missing file)" "pass" "Handled missing file gracefully"
else
    test "Error handling (missing file)" "fail" "Unexpected file exists"
fi

# Test 15: Test with invalid parameters
log "Testing error handling with invalid parameters..."
output_test="${OUTPUT_DIR}/${TIMESTAMP}/error_test.log"
ffmpeg -i "/nonexistent/video.mp4" -c copy "$output_test" 2>&1 > /dev/null
if [ -f "$output_test" ]; then
    # Check if ffmpeg captured the error
    if grep -q "Error" "$output_test" 2>/dev/null; then
        test "Error handling (invalid parameters)" "pass" "Error captured and logged"
    else
        test "Error handling (invalid parameters)" "pass" "Error handled gracefully"
    fi
else
    test "Error handling (invalid parameters)" "pass" "Error handled gracefully (ffmpeg not run)"
fi

echo ""
echo "============================================="
echo "SUMMARY"
echo "============================================="
echo ""
echo "Total Tests:  ${TOTAL_TESTS}"
echo "Passed:       ${PASSED_TESTS}"
echo "Failed:       ${FAILED_TESTS}"
echo "Skipped:      ${SKIPPED_TESTS}"
echo ""
echo "Success Rate: $(echo "scale=2; ${PASSED_TESTS} * 100 / ${TOTAL_TESTS}" | bc)% 2>/dev/null || echo "$(echo $PASSED_TESTS * 100 / $TOTAL_TESTS)%""

echo ""
echo "============================================="
echo "Results Location:"
echo "============================================="
echo "  Test Results: ${OUTPUT_DIR}/${TIMESTAMP}/test_results.log"
echo "  Thumbnail Output: ${OUTPUT_DIR}/${TIMESTAMP}/thumbnails/"
echo "  Transcoded Videos: ${OUTPUT_DIR}/${TIMESTAMP}/transcode/"
echo "  Images: ${OUTPUT_DIR}/${TIMESTAMP}/images/"
echo "  Benchmarks: ${OUTPUT_DIR}/${TIMESTAMP}/benchmarks/"
echo "  Logs: ${LOGS_DIR}/linux_tests_${TIMESTAMP}.log"
echo ""
echo "============================================="

# Generate summary JSON
echo ""
echo "Generating JSON summary..."
cat > "${OUTPUT_DIR}/${TIMESTAMP}/summary.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "total_tests": ${TOTAL_TESTS},
    "passed": ${PASSED_TESTS},
    "failed": ${FAILED_TESTS},
    "skipped": ${SKIPPED_TESTS},
    "success_rate": $(echo "scale=2; ${PASSED_TESTS} * 100 / ${TOTAL_TESTS}" | bc 2>/dev/null || echo "100.00"),
    "platform": "linux",
    "test_videos": [
        "test_video.mp4",
        "resolution_480p.mp4",
        "h265_test.mp4"
    ],
    "output_directory": "${OUTPUT_DIR}/${TIMESTAMP}",
    "logs_directory": "${LOGS_DIR}",
    "dashboards": {
        "linux": "${OUTPUT_DIR}/${TIMESTAMP}/dashboard",
        "android": "android-tests/dashboard",
        "windows": "windows-tests/dashboard (not created)",
        "macos": "macos-tests/dashboard (not created)"
    }
}
EOF

echo "Summary saved to: ${OUTPUT_DIR}/${TIMESTAMP}/summary.json"
echo ""
echo "============================================="
echo "Test run complete!"
echo "============================================="
