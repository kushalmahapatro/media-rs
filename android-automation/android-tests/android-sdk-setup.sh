#!/bin/bash
#
# Android SDK Setup Commands
# Run these with sudo to install Android SDK for media-rs development
#

set -e

echo "============================================================"
echo "Android SDK Setup Script"
echo "============================================================"
echo ""

# Configuration
ANDROID_HOME="/opt/android-sdk"
SDK_TOOLS_VERSION="11076708"

# Step 1: Create directories
echo "Step 1: Creating Android SDK directories..."
sudo mkdir -p ${ANDROID_HOME}
sudo mkdir -p ${ANDROID_HOME}/platforms
sudo mkdir -p ${ANDROID_HOME}/build-tools

# Step 2: Download Android SDK Command-line Tools
echo ""
echo "Step 2: Downloading Android SDK command-line tools..."
cd "${ANDROID_HOME}"
wget -q --show-progress "https://dl.google.com/android/repository/commandlinetools-linux-${SDK_TOOLS_VERSION}.zip" -O "commandlinetools.zip" || \
curl -L -o "commandlinetools.zip" "https://dl.google.com/android/repository/commandlinetools-linux-${SDK_TOOLS_VERSION}.zip"

echo "✓ Downloaded SDK tools"

# Step 3: Extract SDK tools
echo ""
echo "Step 3: Extracting SDK tools..."
sudo unzip -q "commandlinetools.zip" -d "${ANDROID_HOME}/cmdline-tools/latest"
rm "commandlinetools.zip"

echo "✓ Extracted SDK tools"

# Step 4: Accept licenses
echo ""
echo "Step 4: Accepting Android licenses..."
yes | sudo "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --licenses

echo "✓ Accepted licenses"

# Step 5: Install required SDK components
echo ""
echo "Step 5: Installing required SDK components..."

# Install platform-tools
sudo "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" "platform-tools"

# Install Android platform (API 34)
sudo "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" "platforms;android-34"

# Install build-tools
sudo "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" "build-tools;34.0.0"

# Install NDK
sudo "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" "ndk;26.1.10909125"

# Install system images for ARM64 (needed for emulators)
echo ""
echo "Installing Android system images for emulators..."
sudo "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" \
    "system-images;android-34;google_apis;arm64-v8a" \
    "system-images;android-34;google_apis;x86_64"

echo "✓ Installed SDK components"

# Step 6: Create environment setup
echo ""
echo "Step 6: Creating environment setup script..."

# Create .bashrc update
cat >> ~/.bashrc << 'EOF'

# Android SDK
export ANDROID_HOME=/opt/android-sdk
export PATH="${ANDROID_HOME}:${ANDROID_HOME}/platform-tools:${PATH}"
export ANDROID_NDK_HOME="${ANDROID_HOME}/ndk/26.1.10909125"
export ANDROID_SDK_ROOT="${ANDROID_HOME}"

# Add Flutter path (if installed)
if [ -f ~/.fvm/flutter_sdk/bin/flutter ]; then
    export PATH="$HOME/.fvm/flutter_sdk/bin:$PATH"
    export PATH="$HOME/.fvm/flutter_sdk/bin/cache/dart-sdk/bin:$PATH"
    export PUB_CACHE="$HOME/.pub-cache"
    export PUB_HOSTED_URL="$HOME/.pub-cache/hosted/pub.dev"
    export FLUTTER_STORAGE_BASE_PATH="$HOME/.pub-cache"
fi
EOF

echo "✓ Updated .bashrc"

# Step 7: Install Java 17 (required for SDK tools)
echo ""
echo "Step 7: Installing Java 17 (required by Android SDK tools)..."
sudo apt-get update
sudo apt-get install -y openjdk-17-jdk

# Set JAVA_HOME
echo "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64" >> ~/.bashrc
echo "export PATH=\"$JAVA_HOME/bin:\$PATH\"" >> ~/.bashrc

# Step 8: Install essential tools
echo ""
echo "Step 8: Installing essential development tools..."
sudo apt-get install -y \
    wget \
    curl \
    unzip \
    git \
    ffmpeg \
    python3 \
    python3-pip \
    openjdk-17-jdk

echo "✓ Installed essential tools"

# Step 9: Create symbolic links for convenience
echo ""
echo "Step 9: Creating symbolic links..."
sudo ln -sf "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" /usr/local/bin/sdkmanager
sudo ln -sf "${ANDROID_HOME}/cmdline-tools/latest/bin/android" /usr/local/bin/android

echo "✓ Created symbolic links"

# Step 10: Verify installation
echo ""
echo "Step 10: Verifying installation..."
echo ""
echo "Checking Android SDK..."
which sdkmanager && echo "✓ sdkmanager available"
echo ""
echo "Checking Java..."
java -version 2>&1 | head -2
echo ""
echo "Checking FFmpeg..."
ffmpeg -version | head -1
echo ""

# Display installed SDK components
echo "Installed SDK components:"
echo "  - Platform Tools: $(ls -1 ${ANDROID_HOME}/platform-tools 2>/dev/null | tail -1 || echo 'not installed')"
echo "  - Android Platform: $(ls -1 ${ANDROID_HOME}/platforms/ 2>/dev/null | head -1 || echo 'not installed')"
echo "  - Build Tools: $(ls -1 ${ANDROID_HOME}/build-tools/ 2>/dev/null | head -1 || echo 'not installed')"
echo "  - NDK: $(ls -1 ${ANDROID_HOME}/ndk/ 2>/dev/null | head -1 || echo 'not installed')"
echo ""

# Display emulator images
echo "Installed system images:"
ls -la ${ANDROID_HOME}/system-images/ 2>/dev/null || echo "  (not yet installed)"
echo ""

# Summary
echo "============================================================"
echo "Android SDK Setup Complete!"
echo "============================================================"
echo ""
echo "Next steps:"
echo "  1. Source your shell: source ~/.bashrc"
echo "  2. Run: flutter doctor"
echo "  3. Create an emulator: sdkmanager --list"
echo ""
echo "To create an emulator, run:"
echo "  sdkmanager --sdk_add 'system-images;android-34;google_apis;arm64-v8a'"
echo ""
