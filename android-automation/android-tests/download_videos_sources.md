# Reliable Video Download Sources for Testing

## Official & Reliable Sources

### 1. Sample Videos (Official)
**Website:** https://sample-videos.com/

**Available Videos:**
- Big Buck Bunny (various resolutions)
- Sintel (Open movie)
- Tears of Steel (Open movie)
- Bear River
- Tiger
- Couple
- Yoyo

**Direct Links:**
```bash
# MP4 videos (720p)
curl -L -o /path/to/video.mp4 "https://sample-videos.com/video123/mp4/720/Big_Buck_Bunny.mp4"
curl -L -o /path/to/video.mp4 "https://sample-videos.com/video123/mp4/720/Sintel.mp4"
curl -L -o /path/to/video.mp4 "https://sample-videos.com/video123/mp4/720/Tears_of_Steel.mp4"
curl -L -o /path/to/video.mp4 "https://sample-videos.com/video123/mp4/720/Bear_River.mp4"
curl -L -o /path/to/video.mp4 "https://sample-videos.com/video123/mp4/720/Tiger.mp4"
curl -L -o /path/to/video.mp4 "https://sample-videos.com/video123/mp4/720/Couple.mp4"
curl -L -o /path/to/video.mp4 "https://sample-videos.com/video123/mp4/720/Yoyo.mp4"
```

**Available Formats:**
- MP4 (H.264, H.265)
- WEBM (VP8, VP9, AV1)
- Ogg (Theora, Vorbis, Opus)
- AVI
- MOV
- MKV
- 3GP
- FLV
- MPEG

**Image Formats:**
- JPG/JPEG
- PNG
- GIF
- BMP
- WEBP

### 2. Open Movie Project
**Website:** https://openmovieproject.org/

**Movies:**
- Big Buck Bunny (1080p available)
- Sintel
- Tears of Steel
- Yellow Submarine
- Cosmo Dawn
- Spring
- Barn

**Direct Downloads:**
```bash
# Example: Big Buck Bunny from Open Movie Project
curl -L -o /path/to/bb.mp4 "https://peach.blender.org/wp-content/uploads/big_buck_bunny_720p.mp4"
```

### 3. Open Movie Database (OMDb)
**Website:** https://www.freesound.org/

**Free Stock Videos:**
- Creative Commons licensed videos
- Various formats and resolutions
- Good for testing different codecs

### 4. Internet Archive
**Website:** https://archive.org/

**Search for videos:**
- Open movie projects
- Educational content
- Public domain videos

### 5. FreeStockFootage.com
**Website:** https://freestockfootage.com/

**Available:**
- Free stock videos
- Various categories
- Multiple resolutions

### 6. Pexels Videos
**Website:** https://www.pexels.com/videos/

**Features:**
- Free stock videos
- Creative Commons
- High quality
- Various formats

### 7. Pixabay Videos
**Website:** https://pixabay.com/videos/

**Features:**
- Free videos
- No attribution required
- Various categories

### 8. Mixkit
**Website:** https://mixkit.co/free-stock-footage/

**Free videos:**
- High quality
- Creative Commons
- Various formats

### 9. Coverr
**Website:** https://coverr.co/

**Free videos:**
- Creative Commons
- Various resolutions
- Good for backgrounds

## Image Download Sources

### Official Sources

#### 1. Unsplash (High Quality)
**Website:** https://unsplash.com/photos

**Download command:**
```bash
# Using wget or curl with direct URL
# Example: Get direct URL from unsplash.com/photos/[slug]/download
curl -L "https://images.unsplash.com/photo-[id]?w=1920&q=80" -o /path/to/image.jpg
```

#### 2. Pexels
**Website:** https://www.pexels.com/photos/

#### 3. Pixabay
**Website:** https://pixabay.com/images/

#### 4. Flickr (Creative Commons)
**Website:** https://www.flickr.com/search/?license=1

#### 5. Open Photo (Open Photo Project)
**Website:** https://openphoto.co/

#### 6. Wikimedia Commons
**Website:** https://commons.wikimedia.org/wiki/Main_Page

## Generating Test Assets Programmatically

### Using FFmpeg

```bash
# Create video from color + audio
ffmpeg -f lavfi -i color=c=red:s=1280x720:r=24 \
    -f lavfi -i sine=frequency=440:duration=30 \
    -c:v libx264 -pix_fmt yuv420p \
    -c:a aac -b:a 128k \
    output.mp4 -y

# Create with H.265
ffmpeg -f lavfi -i color=c=blue:s=1920x1080:r=24 \
    -f lavfi -i sine=frequency=880:duration=30 \
    -c:v libx265 -pix_fmt yuv420p \
    -c:a aac -b:a 128k \
    output_h265.mp4 -y

# Various resolutions
for res in 480 720 1080; do
    ffmpeg -f lavfi -i color=c=green:s=1280x${res}:r=24 \
        -f lavfi -i sine=frequency=440:duration=20 \
        -c:v libx264 -pix_fmt yuv420p \
        "resolution_${res}p.mp4" -y
done

# Create test images
convert -size 1920x1080 xc:red test_red.jpg
convert -size 1280x720 xc:blue test_blue.jpg
convert -size 640x480 xc:green test_green.jpg
convert -size 320x240 xc:white test_white.png
```

### Using ImageMagick

```bash
# Create test images
convert -size 1920x1080 xc:red -quality 90 test_red.jpg
convert -size 1280x720 xc:blue -quality 90 test_blue.jpg
convert -size 640x480 xc:green -quality 90 test_green.jpg
convert -size 320x240 xc:white test_white.png
convert -size 800x600 gradient:red-blue -quality 90 test_gradient.jpg
```

### Creating Composite Test Images

```bash
# Create images with text overlay
convert -size 1280x720 xc:blue \
    -gravity center \
    -pointsize 72 \
    -font /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf \
    -fill white \
    -annotate 0 "Test Image" \
    test_with_text.jpg

# Create gradient backgrounds
convert -size 1920x1080 gradient:red-blue test_gradient.jpg
convert -size 1280x720 gradient:orange-purple test_gradient2.jpg
```

## Batch Download Script

```bash
#!/bin/bash
# download_test_assets.sh

OUTPUT_DIR="/path/to/videos"
mkdir -p "${OUTPUT_DIR}"

echo "Downloading test videos from sample-videos.com..."

# Download sample videos
VIDEOS=(
    "Big_Buck_Bunny"
    "Sintel"
    "Tears_of_Steel"
    "Bear_River"
    "Tiger"
    "Couple"
    "Yoyo"
)

for video in "${VIDEOS[@]}"; do
    curl -L -o "${OUTPUT_DIR}/${video}.mp4" \
        "https://sample-videos.com/video123/mp4/720/${video}.mp4" 2>&1 | \
        grep -i "download\|complete" || echo "Failed: ${video}.mp4"
done

echo ""
echo "Downloading test images..."

# Download sample images (from unsplash or create locally)
IMAGES=(
    "nature"
    "technology"
    "architecture"
    "portrait"
)

for img in "${IMAGES[@]}"; do
    # Convert to local test images
    convert -size 1280x720 xc:blue \
        -fill white \
        -gravity center \
        -annotate 0 "Test: ${img}" \
        "${OUTPUT_DIR}/${img}.jpg"
done

echo ""
echo "All test assets downloaded/created!"
echo "Output directory: ${OUTPUT_DIR}"
```

## Verification Commands

```bash
# Check downloaded videos
for video in /path/to/videos/*.mp4; do
    echo "=== $(basename $video) ==="
    ffprobe -v quiet -show_format -show_streams "$video" 2>/dev/null | grep -E "duration|width|height|bit_rate"
done

# Check image files
for img in /path/to/images/*.jpg; do
    echo "=== $(basename $img) ==="
    identify "$img" 2>/dev/null | grep -v "Warning\|ERROR" || file "$img"
done
```

## Notes

1. **Sample Videos** is the most reliable and consistent source
2. **Open Movie Project** offers full movies for comprehensive testing
3. **ImageMagick** is perfect for creating consistent test assets
4. **FFmpeg** can generate synthetic videos for codec testing
5. Always verify downloaded content with ffprobe
6. Keep a manifest of all test assets for reproducibility
