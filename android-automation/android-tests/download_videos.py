#!/usr/bin/env python3
"""
Video Download Script for media-rs Test Assets

Downloads sample videos from various sources for testing:
- Big Buck Bunny
- Sintel
- Tears of Steel
- Other sample videos

This script:
1. Downloads videos to the test_videos directory
2. Creates manifest file with video information
3. Shows onboarding screen for first-time users
"""

import os
import json
import logging
from pathlib import Path
from urllib.request import urlretrieve
from datetime import datetime
import time

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/home/kushal/Documents/Projects/media-rs/android-automation/android-tests/logs/download.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class VideoDownloader:
    def __init__(self, download_dir, config_path):
        self.download_dir = Path(download_dir)
        self.download_dir.mkdir(parents=True, exist_ok=True)
        self.config = self._load_config(config_path)
        self.downloaded_videos = []
        
    def _load_config(self, config_path):
        """Load configuration from file"""
        try:
            with open(config_path, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            logger.warning(f"Config file not found: {config_path}, using defaults")
            return {}
    
    def download_video(self, url, filename):
        """Download a video from URL"""
        output_path = self.download_dir / filename
        
        try:
            logger.info(f"Downloading: {filename}")
            
            # Create output directory
            output_path.parent.mkdir(parents=True, exist_ok=True)
            
            # Download the file
            # Using urlretrieve for simplicity
            # In production, you might want to use a library like yt-dlp
            urlretrieve(url, str(output_path))
            
            # Verify download
            if output_path.exists():
                file_size = output_path.stat().st_size
                logger.info(f"Downloaded: {filename} ({file_size / 1024 / 1024:.2f} MB)")
                
                # Get video info
                video_info = self._get_video_info(output_path)
                
                # Add to downloaded list
                self.downloaded_videos.append({
                    'filename': filename,
                    'url': url,
                    'size': file_size,
                    'size_mb': file_size / 1024 / 1024,
                    'download_time': datetime.now().isoformat(),
                    'info': video_info
                })
                
                return True, video_info
            else:
                logger.error(f"Download verification failed for: {filename}")
                return False, {"error": "Download verification failed"}
                
        except Exception as e:
            logger.error(f"Failed to download {filename}: {e}")
            return False, {"error": str(e)}
    
    def _get_video_info(self, video_path):
        """Get information about the downloaded video"""
        try:
            # Use ffprobe if available
            if os.system('which ffprobe > /dev/null 2>&1') == 0:
                # ffprobe command to get info
                cmd = [
                    'ffprobe',
                    '-v', 'quiet',
                    '-print_format', 'json',
                    '-show_format',
                    '-show_streams',
                    str(video_path)
                ]
                import subprocess
                result = subprocess.run(cmd, capture_output=True, text=True)
                
                if result.returncode == 0:
                    import json
                    info = json.loads(result.stdout)
                    format_info = info.get('format', {})
                    
                    return {
                        'duration': format_info.get('duration', 0),
                        'width': format_info.get('width', 0),
                        'height': format_info.get('height', 0),
                        'fps': format_info.get('nb_streams', 0),
                        'format_name': format_info.get('format_name', 'unknown')
                    }
                else:
                    return {'error': 'Failed to parse video info'}
            else:
                # Return basic info
                return {
                    'duration': 'N/A (ffprobe not available)',
                    'width': 'N/A',
                    'height': 'N/A',
                    'fps': 'N/A',
                    'format_name': 'N/A'
                }
        except Exception as e:
            logger.error(f"Failed to get video info: {e}")
            return {'error': str(e)}
    
    def download_all_videos(self):
        """Download all videos from the download list"""
        logger.info("=" * 60)
        logger.info("Starting video download process")
        logger.info("=" * 60)
        
        video_urls = self.config.get('video_download_urls', {})
        
        if not video_urls:
            logger.info("No videos to download (config doesn't specify URLs)")
            logger.info("Please add video URLs to config.json")
            return self.downloaded_videos
        
        success_count = 0
        fail_count = 0
        
        for filename, url in video_urls.items():
            success, info = self.download_video(url, filename)
            
            if success:
                success_count += 1
                logger.info(f"✓ Successfully downloaded: {filename}")
            else:
                fail_count += 1
                error_info = info.get('error', 'Unknown error')
                logger.info(f"✗ Failed to download: {filename} - {error_info}")
            
            # Small delay to avoid rate limiting
            time.sleep(1)
        
        logger.info("=" * 60)
        logger.info(f"Download complete!")
        logger.info(f"Successfully downloaded: {success_count} videos")
        logger.info(f"Failed: {fail_count} videos")
        logger.info("=" * 60)
        
        return self.downloaded_videos
    
    def create_manifest(self):
        """Create manifest file with all downloaded videos"""
        manifest = {
            'generated_at': datetime.now().isoformat(),
            'download_dir': str(self.download_dir),
            'videos': self.downloaded_videos
        }
        
        manifest_path = self.download_dir / 'manifest.json'
        with open(manifest_path, 'w') as f:
            json.dump(manifest, f, indent=2)
        
        logger.info(f"Manifest created: {manifest_path}")
        return manifest
    
    def show_onboarding_screen(self):
        """Create onboarding screen for first-time users"""
        logger.info("Creating onboarding screen...")
        
        html_content = f"""<!DOCTYPE html>
<html>
<head>
    <title>media-rs Test Videos - Onboarding</title>
    <style>
        body {{ 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            padding: 20px; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
            min-height: 100vh;
        }}
        .container {{ 
            max-width: 900px; 
            margin: 0 auto; 
            background: white; 
            padding: 30px; 
            border-radius: 15px; 
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
        }}
        h1 {{ 
            color: #333; 
            text-align: center; 
            margin-bottom: 10px;
        }}
        .subtitle {{ 
            text-align: center; 
            color: #666; 
            margin-bottom: 30px;
        }}
        .status {{ 
            background: #f8f9fa; 
            padding: 15px; 
            border-radius: 8px; 
            margin-bottom: 20px;
            border-left: 4px solid #28a745;
        }}
        .video-list {{ 
            margin-top: 20px;
        }}
        .video-item {{ 
            background: #f8f9fa; 
            padding: 15px; 
            margin: 10px 0; 
            border-radius: 8px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }}
        .video-info {{ 
            flex: 1;
        }}
        .video-name {{ 
            font-weight: bold; 
            color: #333;
            font-size: 1.1em;
        }}
        .video-meta {{ 
            color: #666; 
            font-size: 0.9em;
            margin-top: 5px;
        }}
        .video-actions {{ 
            display: flex;
            gap: 10px;
        }}
        .btn {{ 
            padding: 10px 20px; 
            border: none; 
            border-radius: 5px; 
            cursor: pointer;
            text-decoration: none;
            font-size: 0.9em;
            font-weight: 500;
        }}
        .btn-primary {{ 
            background: #007bff; 
            color: white;
        }}
        .btn-secondary {{ 
            background: #6c757d; 
            color: white;
        }}
        .btn-success {{ 
            background: #28a745; 
            color: white;
        }}
        .stats {{ 
            display: flex; 
            gap: 20px; 
            margin-top: 20px; 
            flex-wrap: wrap;
        }}
        .stat {{ 
            background: #f8f9fa; 
            padding: 15px 25px; 
            border-radius: 8px; 
            text-align: center;
        }}
        .stat-value {{ 
            font-size: 2em; 
            font-weight: bold; 
            color: #667eea;
        }}
        .stat-label {{ 
            color: #666; 
            font-size: 0.9em;
        }}
        .no-videos {{ 
            text-align: center; 
            color: #666; 
            padding: 30px;
            background: #f8f9fa; 
            border-radius: 8px;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>🎬 media-rs Test Videos</h1>
        <p class="subtitle">Sample videos for testing thumbnail generation and transcoding</p>
        
        <div class="status">
            <strong>Welcome!</strong><br>
            This page shows the available test videos for media-rs.<br>
            You can use these videos to test your media processing functionality.
        </div>
        
        {self._generate_video_list()}
        
        <div class="stats">
            <div class="stat">
                <div class="stat-value">{len(self.downloaded_videos)}</div>
                <div class="stat-label">Videos Downloaded</div>
            </div>
            <div class="stat">
                <div class="stat-value">
                    {sum(v['size_mb'] for v in self.downloaded_videos):.1f} MB
                    if self.downloaded_videos else 0}
                </div>
                <div class="stat-label">Total Size</div>
            </div>
            <div class="stat">
                <div class="stat-value">
                    {sum(v.get('duration', 0) for v in self.downloaded_videos):.1f} minutes
                    if self.downloaded_videos else 0}
                </div>
                <div class="stat-label">Total Duration</div>
            </div>
        </div>
        
        <div style="margin-top: 30px; text-align: center;">
            <a href="/dashboard" class="btn btn-primary">Go to Test Dashboard</a>
            <button onclick="window.close()" class="btn btn-secondary">Close</button>
        </div>
    </div>
</body>
</html>"""
        
        dashboard_file = self.download_dir.parent / 'onboarding.html'
        with open(dashboard_file, 'w') as f:
            f.write(html_content)
        
        logger.info(f"Onboarding screen created: {dashboard_file}")
        return dashboard_file
    
    def _generate_video_list(self):
        """Generate HTML list of downloaded videos"""
        if not self.downloaded_videos:
            return """
            <div class="no-videos">
                <h3>No videos downloaded yet</h3>
                <p>Click the button below to download sample videos:</p>
                <a href="#download-all" class="btn btn-success" onclick="downloadAll()">Download All Videos</a>
            </div>
            """
        
        items = ""
        for video in self.downloaded_videos:
            name = video.get('filename', 'Unknown')
            size = f"{video.get('size_mb', 0):.2f} MB"
            duration = f"{video.get('info', {}).get('duration', 0):.1f}s" if video.get('info') else "N/A"
            
            items += f"""
            <div class="video-item">
                <div class="video-info">
                    <div class="video-name">{name}</div>
                    <div class="video-meta">Size: {size} | Duration: {duration}</div>
                </div>
                <div class="video-actions">
                    <a href="/path/to/{name}" class="btn btn-primary">View</a>
                </div>
            </div>
            """
        
        return items
    
    def download_all(self):
        """Convenience method to download all videos"""
        self.download_all_videos()
        self.create_manifest()
        self.show_onboarding_screen()
        
        return self.downloaded_videos

if __name__ == "__main__":
    import sys
    
    # Configuration
    download_dir = "/home/kushal/Documents/Projects/media-rs/android-automation/android-tests/test_videos"
    config_path = "/home/kushal/Documents/Projects/media-rs/android-automation/android-tests/config.json"
    
    # Create downloader and download videos
    downloader = VideoDownloader(download_dir, config_path)
    
    print("\n" + "="*60)
    print("media-rs Test Video Downloader")
    print("="*60 + "\n")
    
    print("Available video sources:")
    for name, url in downloader.config.get('video_download_urls', {}).items():
        print(f"  - {name}: {url}")
    print()
    
    print("Would you like to download all videos? (y/n)")
    response = input("> ").strip().lower()
    
    if response in ['y', 'yes']:
        print("\nDownloading videos...")
        print("-" * 60)
        videos = downloader.download_all_videos()
        
        if videos:
            downloader.create_manifest()
            downloader.show_onboarding_screen()
            
            print(f"\n{'='*60}")
            print(f"Download complete! Downloaded {len(videos)} videos")
            print(f"{'='*60}")
        else:
            print("\nNo videos were downloaded.")
    else:
        print("\nAborted. Add video URLs to config.json and try again.")
    
    print()
