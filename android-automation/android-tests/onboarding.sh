#!/bin/bash
#
# Onboarding script for media-rs Android Automation
# Downloads test videos, creates dashboard, and sets up the environment
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_VIDEOS_DIR="${SCRIPT_DIR}/test_videos"
DOWNLOAD_LOG="${SCRIPT_DIR}/logs/onboarding.log"

echo "============================================================"
echo "media-rs Android Automation - Onboarding"
echo "============================================================"
echo ""
echo "This script will:"
echo "  1. Download sample test videos"
echo "  2. Create test manifest"
echo "  3. Set up automated testing environment"
echo ""
echo "Would you like to proceed? (y/n)"
read -r response

if [[ "${response}" != "[Yy]" ]]; then
    echo "Onboarding aborted."
    exit 1
fi

echo ""
echo "Setting up test environment..."
mkdir -p "${TEST_VIDEOS_DIR}"

echo ""
echo "Downloading sample test videos..."
echo "This may take a few minutes depending on your internet speed."
echo ""

# Download videos
python3 "${SCRIPT_DIR}/download_videos.py" < /dev/null || {
    echo ""
    echo "Warning: Some videos failed to download."
    echo "You can manually download them from:"
    echo "  https://sample-videos.com/"
    echo "  Or use your own video files from gallery/files."
}

echo ""
echo "Onboarding complete!"
echo ""
echo "Next steps:"
echo "  1. Run tests: ./run_tests.sh"
echo "  2. View dashboard: ${SCRIPT_DIR}/dashboard/"
echo ""
echo "Test videos are available at:"
echo "  ${TEST_VIDEOS_DIR}/"
echo ""
