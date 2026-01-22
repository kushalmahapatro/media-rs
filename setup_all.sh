#!/bin/bash
set -euo pipefail

# One-stop dependency builder for this repo (entrypoint).
# This file lives at repo root. Supporting scripts live under scripts/support/.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

usage() {
  cat <<'EOF'
Usage:
  ./setup_all.sh [--all] [--macos] [--ios] [--android] [--linux] [--skip-openh264]

Defaults:
  - On macOS: builds macos + ios + android
  - On Linux: builds linux + android

Env:
  - ANDROID_NDK_HOME: required for --android
EOF
}

# Check what's holding the dpkg lock
check_lock_holders() {
  local holders=()
  
  # Check for unattended-upgrade processes
  if pgrep -f "unattended-upgrade" >/dev/null 2>&1; then
    local pids=$(pgrep -f "unattended-upgrade" | tr '\n' ' ')
    holders+=("unattended-upgrade (PIDs: $pids)")
  fi
  
  # Check for apt processes
  if pgrep -f "apt.*install\|apt.*update" >/dev/null 2>&1; then
    local pids=$(pgrep -f "apt.*install\|apt.*update" | tr '\n' ' ')
    holders+=("apt processes (PIDs: $pids)")
  fi
  
  # Check for dpkg processes
  if pgrep -f "dpkg" >/dev/null 2>&1; then
    local pids=$(pgrep -f "dpkg" | tr '\n' ' ')
    holders+=("dpkg processes (PIDs: $pids)")
  fi
  
  if [ ${#holders[@]} -gt 0 ]; then
    echo "Lock is held by: ${holders[*]}"
    return 0
  fi
  
  return 1
}

# Wait for dpkg lock to be released (for apt-based systems)
wait_for_dpkg_lock() {
  local max_wait=600  # 10 minutes max (increased for slow updates)
  local wait_time=0
  local lock_files=(
    "/var/lib/dpkg/lock-frontend"
    "/var/lib/dpkg/lock"
    "/var/cache/apt/archives/lock"
  )
  
  # Check if lock files exist and are in use
  check_lock() {
    local lock_file="$1"
    if [ ! -f "$lock_file" ]; then
      return 1  # Not locked
    fi
    
    # Try using lsof if available (more accurate)
    if command -v lsof >/dev/null 2>&1; then
      if sudo lsof "$lock_file" >/dev/null 2>&1; then
        return 0  # Locked
      fi
    elif command -v fuser >/dev/null 2>&1; then
      if sudo fuser "$lock_file" >/dev/null 2>&1; then
        return 0  # Locked
      fi
    else
      # Fallback: check if file is recent (modified within last 5 minutes)
      # This is less accurate but works without lsof/fuser
      local file_age=$(($(date +%s) - $(stat -c %Y "$lock_file" 2>/dev/null || echo 0)))
      if [ $file_age -lt 300 ]; then
        return 0  # Possibly locked (recent file)
      fi
    fi
    
    return 1  # Not locked
  }
  
  # Initial check
  local initially_locked=false
  for lock_file in "${lock_files[@]}"; do
    if check_lock "$lock_file"; then
      initially_locked=true
      break
    fi
  done
  
  if [ "$initially_locked" = false ]; then
    return 0  # No lock, proceed
  fi
  
  # Show what's holding the lock
  echo ""
  echo "Package manager is currently locked."
  if check_lock_holders; then
    echo ""
  fi
  echo "Waiting for lock to be released..."
  echo "This may take several minutes if automatic updates are running."
  echo ""
  
  while [ $wait_time -lt $max_wait ]; do
    local locked=false
    for lock_file in "${lock_files[@]}"; do
      if check_lock "$lock_file"; then
        locked=true
        break
      fi
    done
    
    if [ "$locked" = false ]; then
      echo "Lock released! Proceeding with installation..."
      return 0
    fi
    
    # Show progress every 30 seconds with lock holder info
    if [ $((wait_time % 30)) -eq 0 ] && [ $wait_time -gt 0 ]; then
      echo "[${wait_time}s] Still waiting... (checking lock status)"
      check_lock_holders 2>/dev/null || true
    fi
    
    sleep 2
    wait_time=$((wait_time + 2))
  done
  
  echo ""
  echo "ERROR: Package manager lock was not released within $max_wait seconds."
  echo ""
  check_lock_holders
  echo ""
  echo "Options:"
  echo "  1. Wait for automatic updates to finish (recommended)"
  echo "  2. Check status: ps aux | grep -E '(apt|dpkg|unattended)'"
  echo "  3. If stuck, you may need to stop automatic updates temporarily:"
  echo "     sudo systemctl stop unattended-upgrades"
  echo "     (Then restart after installation: sudo systemctl start unattended-upgrades)"
  return 1
}

# Check and install Linux build dependencies
install_linux_dependencies() {
  local missing_packages=()
  local package_manager=""
  local install_cmd=""
  local update_cmd=""
  local sudo_prefix=""
  
  # Check if running as root
  if [ "$EUID" -eq 0 ]; then
    sudo_prefix=""
  elif command -v sudo >/dev/null 2>&1; then
    sudo_prefix="sudo"
  else
    echo "WARNING: sudo not found. Some packages may need to be installed manually."
    sudo_prefix=""
  fi
  
  # Detect package manager
  if command -v apt-get >/dev/null 2>&1; then
    package_manager="apt"
    update_cmd="$sudo_prefix apt-get update -qq"
    install_cmd="$sudo_prefix apt-get install -y"
    # Check for required packages
    if ! command -v g++ >/dev/null 2>&1; then
      missing_packages+=("g++")
    fi
    if ! command -v gcc >/dev/null 2>&1; then
      missing_packages+=("gcc")
    fi
    if ! command -v make >/dev/null 2>&1; then
      missing_packages+=("make")
    fi
    if ! command -v cmake >/dev/null 2>&1; then
      missing_packages+=("cmake")
    fi
    if ! command -v pkg-config >/dev/null 2>&1; then
      missing_packages+=("pkg-config")
    fi
    if ! command -v git >/dev/null 2>&1; then
      missing_packages+=("git")
    fi
    if ! command -v curl >/dev/null 2>&1; then
      missing_packages+=("curl")
    fi
    if ! command -v nasm >/dev/null 2>&1 && ! command -v yasm >/dev/null 2>&1; then
      missing_packages+=("nasm")
    fi
    if ! command -v ld.lld >/dev/null 2>&1 && ! command -v lld >/dev/null 2>&1; then
      missing_packages+=("lld")
    fi
    # Flutter Linux desktop dependencies
    if ! pkg-config --exists gtk+-3.0 2>/dev/null; then
      missing_packages+=("libgtk-3-dev")
    fi
    if ! pkg-config --exists x11 2>/dev/null; then
      missing_packages+=("libx11-dev")
    fi
    if ! pkg-config --exists xrandr 2>/dev/null; then
      missing_packages+=("libxrandr-dev")
    fi
    if ! pkg-config --exists xinerama 2>/dev/null; then
      missing_packages+=("libxinerama-dev")
    fi
    if ! pkg-config --exists xcursor 2>/dev/null; then
      missing_packages+=("libxcursor-dev")
    fi
    if ! pkg-config --exists xi 2>/dev/null; then
      missing_packages+=("libxi-dev")
    fi
    if ! pkg-config --exists xfixes 2>/dev/null; then
      missing_packages+=("libxfixes-dev")
    fi
    # File picker dependencies (for file_picker Flutter plugin)
    if ! command -v zenity >/dev/null 2>&1; then
      missing_packages+=("zenity")
    fi
    # xdg-desktop-portal for modern file dialogs (optional but recommended)
    if ! dpkg -l | grep -q "^ii.*xdg-desktop-portal" 2>/dev/null; then
      missing_packages+=("xdg-desktop-portal")
    fi
    if ! dpkg -l | grep -q "^ii.*xdg-desktop-portal-gtk" 2>/dev/null; then
      missing_packages+=("xdg-desktop-portal-gtk")
    fi
  elif command -v yum >/dev/null 2>&1; then
    package_manager="yum"
    update_cmd=""
    install_cmd="$sudo_prefix yum install -y"
    # Check for required packages
    if ! command -v g++ >/dev/null 2>&1; then
      missing_packages+=("gcc-c++")
    fi
    if ! command -v gcc >/dev/null 2>&1; then
      missing_packages+=("gcc")
    fi
    if ! command -v make >/dev/null 2>&1; then
      missing_packages+=("make")
    fi
    if ! command -v cmake >/dev/null 2>&1; then
      missing_packages+=("cmake")
    fi
    if ! command -v pkg-config >/dev/null 2>&1; then
      missing_packages+=("pkgconfig")
    fi
    if ! command -v git >/dev/null 2>&1; then
      missing_packages+=("git")
    fi
    if ! command -v curl >/dev/null 2>&1; then
      missing_packages+=("curl")
    fi
    if ! command -v nasm >/dev/null 2>&1 && ! command -v yasm >/dev/null 2>&1; then
      missing_packages+=("nasm")
    fi
    if ! command -v ld.lld >/dev/null 2>&1 && ! command -v lld >/dev/null 2>&1; then
      missing_packages+=("lld")
    fi
  elif command -v dnf >/dev/null 2>&1; then
    package_manager="dnf"
    update_cmd=""
    install_cmd="$sudo_prefix dnf install -y"
    # Check for required packages
    if ! command -v g++ >/dev/null 2>&1; then
      missing_packages+=("gcc-c++")
    fi
    if ! command -v gcc >/dev/null 2>&1; then
      missing_packages+=("gcc")
    fi
    if ! command -v make >/dev/null 2>&1; then
      missing_packages+=("make")
    fi
    if ! command -v cmake >/dev/null 2>&1; then
      missing_packages+=("cmake")
    fi
    if ! command -v pkg-config >/dev/null 2>&1; then
      missing_packages+=("pkgconfig")
    fi
    if ! command -v git >/dev/null 2>&1; then
      missing_packages+=("git")
    fi
    if ! command -v curl >/dev/null 2>&1; then
      missing_packages+=("curl")
    fi
    if ! command -v nasm >/dev/null 2>&1 && ! command -v yasm >/dev/null 2>&1; then
      missing_packages+=("nasm")
    fi
    if ! command -v ld.lld >/dev/null 2>&1 && ! command -v lld >/dev/null 2>&1; then
      missing_packages+=("lld")
    fi
  elif command -v pacman >/dev/null 2>&1; then
    package_manager="pacman"
    update_cmd="$sudo_prefix pacman -Sy --noconfirm"
    install_cmd="$sudo_prefix pacman -S --noconfirm"
    # Check for required packages
    if ! command -v g++ >/dev/null 2>&1; then
      missing_packages+=("gcc")
    fi
    if ! command -v make >/dev/null 2>&1; then
      missing_packages+=("make")
    fi
    if ! command -v cmake >/dev/null 2>&1; then
      missing_packages+=("cmake")
    fi
    if ! command -v pkg-config >/dev/null 2>&1; then
      missing_packages+=("pkgconf")
    fi
    if ! command -v git >/dev/null 2>&1; then
      missing_packages+=("git")
    fi
    if ! command -v curl >/dev/null 2>&1; then
      missing_packages+=("curl")
    fi
    if ! command -v nasm >/dev/null 2>&1 && ! command -v yasm >/dev/null 2>&1; then
      missing_packages+=("nasm")
    fi
    if ! command -v ld.lld >/dev/null 2>&1 && ! command -v lld >/dev/null 2>&1; then
      missing_packages+=("lld")
    fi
  elif command -v zypper >/dev/null 2>&1; then
    package_manager="zypper"
    update_cmd=""
    install_cmd="$sudo_prefix zypper install -y"
    # Check for required packages
    if ! command -v g++ >/dev/null 2>&1; then
      missing_packages+=("gcc-c++")
    fi
    if ! command -v gcc >/dev/null 2>&1; then
      missing_packages+=("gcc")
    fi
    if ! command -v make >/dev/null 2>&1; then
      missing_packages+=("make")
    fi
    if ! command -v cmake >/dev/null 2>&1; then
      missing_packages+=("cmake")
    fi
    if ! command -v pkg-config >/dev/null 2>&1; then
      missing_packages+=("pkg-config")
    fi
    if ! command -v git >/dev/null 2>&1; then
      missing_packages+=("git")
    fi
    if ! command -v curl >/dev/null 2>&1; then
      missing_packages+=("curl")
    fi
    if ! command -v nasm >/dev/null 2>&1 && ! command -v yasm >/dev/null 2>&1; then
      missing_packages+=("nasm")
    fi
    if ! command -v ld.lld >/dev/null 2>&1 && ! command -v lld >/dev/null 2>&1; then
      missing_packages+=("lld")
    fi
  else
    echo "WARNING: Could not detect package manager (apt-get, yum, dnf, pacman, or zypper)."
    echo "Please ensure the following are installed: g++, gcc, make, cmake, pkg-config, git, curl, nasm/yasm, lld"
    echo "For file picker support: zenity, xdg-desktop-portal, xdg-desktop-portal-gtk"
    return 0
  fi
  
  if [ ${#missing_packages[@]} -eq 0 ]; then
    echo "All required build dependencies are already installed."
    return 0
  fi
  
  echo "Detected package manager: $package_manager"
  echo "Missing packages: ${missing_packages[*]}"
  echo "Installing missing dependencies..."
  
  # Wait for dpkg lock if using apt-based package manager
  if [ "$package_manager" = "apt" ]; then
    if ! wait_for_dpkg_lock; then
      echo ""
      echo "ERROR: Cannot proceed while package manager is locked."
      echo "Please wait for automatic updates to finish, then run the script again."
      echo "Or manually install the missing packages: ${missing_packages[*]}"
      exit 2
    fi
  fi
  
  # Update package lists if needed
  if [ -n "$update_cmd" ]; then
    echo "Updating package lists..."
    if ! $update_cmd; then
      echo "WARNING: Failed to update package lists. Continuing anyway..."
    fi
  fi
  
  # Install missing packages
  echo "Installing: ${missing_packages[*]}"
  if ! $install_cmd "${missing_packages[@]}"; then
    echo ""
    echo "ERROR: Failed to install some packages."
    echo ""
    echo "If you see a 'lock' error, another process (like automatic updates) is using the package manager."
    echo "Please wait for it to finish, then run the script again."
    echo ""
    echo "To install manually, run:"
    if [ "$package_manager" = "apt" ]; then
      echo "  $sudo_prefix apt-get update && $sudo_prefix apt-get install -y ${missing_packages[*]}"
    elif [ "$package_manager" = "yum" ] || [ "$package_manager" = "dnf" ]; then
      echo "  $sudo_prefix $package_manager install -y ${missing_packages[*]}"
    elif [ "$package_manager" = "pacman" ]; then
      echo "  $sudo_prefix pacman -S --noconfirm ${missing_packages[*]}"
    elif [ "$package_manager" = "zypper" ]; then
      echo "  $sudo_prefix zypper install -y ${missing_packages[*]}"
    fi
    exit 2
  fi
  
  echo "Successfully installed build dependencies."
}

want_all=false
want_macos=false
want_ios=false
want_android=false
want_linux=false
skip_openh264=false

for arg in "$@"; do
  case "$arg" in
    --all) want_all=true ;;
    --macos) want_macos=true ;;
    --ios) want_ios=true ;;
    --android) want_android=true ;;
    --linux) want_linux=true ;;
    --skip-openh264) skip_openh264=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $arg"; usage; exit 2 ;;
  esac
done

host_os="$(uname -s | tr '[:upper:]' '[:lower:]')"

if $want_all; then
  want_macos=true
  want_ios=true
  want_android=true
  want_linux=true
fi

# Sensible defaults
if ! $want_macos && ! $want_ios && ! $want_android && ! $want_linux; then
  if [[ "$host_os" == "darwin" ]]; then
    want_macos=true
    want_ios=true
    want_android=true
  elif [[ "$host_os" == "linux" ]]; then
    want_linux=true
    want_android=true
  else
    echo "Unsupported host OS for bash setup: $host_os"
    echo "On Windows, use: setup_all.bat"
    exit 2
  fi
fi

cd "$PROJECT_ROOT"

SUPPORT_DIR="$PROJECT_ROOT/scripts/support"
if [ ! -d "$SUPPORT_DIR" ]; then
  echo "ERROR: support scripts directory not found: $SUPPORT_DIR"
  exit 2
fi

echo "Repo: $PROJECT_ROOT"
echo "Host: $host_os"
echo "Targets: macos=$want_macos ios=$want_ios android=$want_android linux=$want_linux"

if $want_macos; then
  if [[ "$host_os" != "darwin" ]]; then
    echo "Skipping macOS deps: host is not macOS."
  else
    echo "=== macOS: libheif (universal) ==="
    "$SUPPORT_DIR/setup_libheif_all.sh" --macos-only
    echo "=== macOS: ffmpeg (universal) ==="
    if $skip_openh264; then
      "$SUPPORT_DIR/setup_ffmpeg.sh" --skip-openh264
    else
      "$SUPPORT_DIR/setup_ffmpeg.sh"
    fi
  fi
fi

if $want_ios; then
  if [[ "$host_os" != "darwin" ]]; then
    echo "Skipping iOS deps: host is not macOS."
  else
    echo "=== iOS: libheif ==="
    "$SUPPORT_DIR/setup_libheif_all.sh" --ios-only
    echo "=== iOS: ffmpeg ==="
    if $skip_openh264; then
      "$SUPPORT_DIR/setup_ffmpeg_ios.sh" --skip-openh264
    else
      "$SUPPORT_DIR/setup_ffmpeg_ios.sh"
    fi
  fi
fi

if $want_android; then
  if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
    echo "ERROR: ANDROID_NDK_HOME is required for Android builds."
    exit 2
  fi
  echo "=== Android: libheif ==="
  "$SUPPORT_DIR/setup_libheif_all.sh" --android-only
  echo "=== Android: ffmpeg (+openh264) ==="
  if $skip_openh264; then
    "$SUPPORT_DIR/setup_ffmpeg_android.sh" --skip-openh264
  else
    "$SUPPORT_DIR/setup_ffmpeg_android.sh"
  fi
fi

if $want_linux; then
  if [[ "$host_os" != "linux" ]]; then
    echo "Skipping Linux deps: host is not Linux."
  else
    echo "=== Checking Linux build dependencies ==="
    install_linux_dependencies
    echo "=== Linux: openh264 ==="
    "$SUPPORT_DIR/setup_openh264_linux.sh"
    echo "=== Linux: libheif ==="
    "$SUPPORT_DIR/setup_libheif_linux.sh"
    echo "=== Linux: ffmpeg (+openh264) ==="
    "$SUPPORT_DIR/setup_ffmpeg_linux.sh"
  fi
fi

echo "Done. third_party installs are ready."


