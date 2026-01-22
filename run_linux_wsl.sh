#!/bin/bash
# Helper script to run Flutter Linux app with proper display setup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if we're in WSL2
if grep -qi microsoft /proc/version 2>/dev/null; then
  echo "WSL2 detected. Setting up display..."
  
  # Try to detect Windows host IP for X11 forwarding
  if [ -z "${DISPLAY:-}" ] || [ "$DISPLAY" = ":0" ]; then
    # Try WSLg first (Windows 11)
    if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -d "/mnt/wslg" ]; then
      echo "WSLg detected - display should work automatically"
      export DISPLAY=:0
    else
      # Try to get Windows host IP
      WIN_IP=$(cat /etc/resolv.conf 2>/dev/null | grep nameserver | awk '{print $2; exit;}' || echo "")
      if [ -n "$WIN_IP" ]; then
        export DISPLAY="$WIN_IP:0.0"
        echo "Set DISPLAY to $DISPLAY"
        echo "Make sure you have an X11 server running on Windows (VcXsrv, X410, etc.)"
      else
        export DISPLAY=:0
        echo "Using DISPLAY=:0 (make sure X11 server is configured)"
      fi
    fi
  fi
fi

# Check if display is accessible
if ! xset q &>/dev/null; then
  echo ""
  echo "⚠️  WARNING: Cannot connect to X11 display server!"
  echo ""
  echo "For WSL2, you need to:"
  echo "  1. Install an X11 server on Windows:"
  echo "     - VcXsrv (free): https://sourceforge.net/projects/vcxsrv/"
  echo "     - X410 (paid): Microsoft Store"
  echo "     - Or use WSLg (Windows 11 only)"
  echo ""
  echo "  2. Start the X server on Windows"
  echo ""
  echo "  3. For VcXsrv:"
  echo "     - Allow public networks"
  echo "     - Disable access control"
  echo ""
  echo "  4. Then run this script again"
  echo ""
  exit 1
fi

echo "Display is accessible. Running Flutter app..."
echo ""

# Set environment variables to help with EGL/graphics issues
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export MESA_GL_VERSION_OVERRIDE=3.3

# Try to find and run the app
if [ -d "example" ]; then
  cd example
  echo "Running from example directory..."
  flutter run -d linux --verbose 2>&1 | tee /tmp/flutter_run.log
elif [ -f "build/linux/x64/debug/bundle/example" ]; then
  echo "Running built binary directly..."
  cd build/linux/x64/debug/bundle
  ./example 2>&1 | tee /tmp/flutter_run.log
elif [ -d "build/linux/x64/debug" ]; then
  echo "Looking for executable in build directory..."
  EXECUTABLE=$(find build/linux/x64/debug -type f -executable -name "*example*" 2>/dev/null | head -1)
  if [ -n "$EXECUTABLE" ]; then
    echo "Found: $EXECUTABLE"
    "$EXECUTABLE" 2>&1 | tee /tmp/flutter_run.log
  else
    echo "Error: Could not find executable"
    echo "Try running: flutter build linux"
    exit 1
  fi
else
  echo "Error: Could not find app to run"
  echo "Please run: flutter build linux"
  exit 1
fi

echo ""
echo "If the app didn't appear, check /tmp/flutter_run.log for errors"
