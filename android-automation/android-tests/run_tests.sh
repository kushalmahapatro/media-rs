#!/bin/bash
#
# Run all tests for media-rs Android Automation
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="${SCRIPT_DIR}/logs"
OUTPUT_DIR="${SCRIPT_DIR}/output"
DASHBOARD_DIR="${SCRIPT_DIR}/dashboard"

echo "============================================================"
echo "media-rs Android Test Runner"
echo "============================================================"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Ensure directories exist
mkdir -p "${LOGS_DIR}" "${OUTPUT_DIR}" "${DASHBOARD_DIR}"

# Check for video files
VIDEO_COUNT=$(find "${SCRIPT_DIR}/test_videos" -type f 2>/dev/null | wc -l)
echo "Found ${VIDEO_COUNT} video files in test_videos directory"

if [ "${VIDEO_COUNT}" -eq 0 ]; then
    echo ""
    echo "No video files found. Please download test videos first:"
    echo "  ./download_videos.py"
    echo ""
    echo "Or add your own videos to: ${SCRIPT_DIR}/test_videos/"
    echo "============================================================"
    exit 1
fi

# Run the main test runner
python3 "${SCRIPT_DIR}/automation_core/test_runner.py"

EXIT_CODE=$?

echo ""
echo "============================================================"
echo "Test run completed with exit code: ${EXIT_CODE}"
echo ""
echo "Results available at:"
echo "  - Output: ${OUTPUT_DIR}"
echo "  - Logs: ${LOGS_DIR}"
echo "  - Dashboard: ${DASHBOARD_DIR}"
echo ""
echo "View the HTML dashboard to see visual test results:"
ls -1 "${DASHBOARD_DIR}"/*.html 2>/dev/null | tail -1 | xargs -I {} bash -c 'echo "  File: {}"'

echo "============================================================"

exit ${EXIT_CODE}
