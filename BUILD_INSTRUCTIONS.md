# Cross-Platform Build Instructions

## 🚫 Why You Can't Build All Platforms from macOS

Flutter requires native toolchains for each platform:

| Platform | Required Tools | Available on macOS? |
|----------|---------------|-------------------|
| Windows | Visual Studio, MSVC, Windows SDK | ❌ No |
| Linux | GTK3, CMake, Ninja, Linux headers | ❌ No |
| macOS | Xcode, CocoaPods | ✅ Yes |

---

## ✅ Option 1: GitHub Actions (Automated)

**Best for:** Automated releases, CI/CD

### Setup

1. The workflow file is already created: `.github/workflows/build-releases.yml`

2. Push to GitHub:
```bash
git add .github/workflows/build-releases.yml
git commit -m "Add cross-platform build workflow"
git push origin feat/windows-linux-mac-support
```

3. Trigger builds:
   - **Manual:** Go to GitHub → Actions → "Build Flutter Releases" → Run workflow
   - **Automatic:** Push a tag like `v0.0.2`

4. Download artifacts:
   - Go to Actions → Select the workflow run
   - Download: `media-windows-x64.zip`, `media-linux-x64.tar.gz`, `media-macos.dmg`

---

## ✅ Option 2: Manual Builds on Native OS

### Windows Build (on Windows PC)

**Requirements:**
- Windows 10/11
- Visual Studio 2022 (with C++ desktop development workload)
- Flutter SDK

**Steps:**
```powershell
# Clone the repo
git clone https://github.com/kushalmahapatro/media-rs.git
cd media-rs/media_flutter/example

# Get dependencies
flutter pub get

# Build
flutter build windows --release

# Output location:
# build/windows/x64/runner/Release/
```

**Create installer (optional):**
```powershell
# Option 1: Zip it
Compress-Archive -Path build/windows/x64/runner/Release/* -DestinationPath media-windows.zip

# Option 2: Use Inno Setup (download from jrsoftware.org)
# Create installer script and compile
```

**Files to distribute:**
- `media.exe` - The executable
- `media.dll` - Your native library
- `ffmpeg.exe`, `ffprobe.exe` - FFmpeg binaries (from release)
- All other DLLs and files in the Release folder

---

### Linux Build (on Linux PC)

**Requirements:**
- Ubuntu 20.04+ or similar Linux distribution
- Flutter SDK
- Build dependencies

**Steps:**
```bash
# Install dependencies
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev

# Clone the repo
git clone https://github.com/kushalmahapatro/media-rs.git
cd media-rs/media_flutter/example

# Get dependencies
flutter pub get

# Build
flutter build linux --release

# Output location:
# build/linux/x64/release/bundle/
```

**Create distribution packages:**

**Option 1: Tarball**
```bash
cd build/linux/x64/release/bundle
tar -czf media-linux-x64.tar.gz .
```

**Option 2: AppImage (portable)**
```bash
# Install appimagetool
wget https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x appimagetool-x86_64.AppImage

# Create AppDir structure
mkdir -p media.AppDir/usr/bin
cp -r build/linux/x64/release/bundle/* media.AppDir/usr/bin/
# Add .desktop file and icon
./appimagetool-x86_64.AppImage media.AppDir media-x86_64.AppImage
```

**Option 3: .deb package**
```bash
# Install dpkg-deb
sudo apt-get install dpkg-dev

# Create package structure
mkdir -p media-deb/DEBIAN
mkdir -p media-deb/usr/local/bin/media
cp -r build/linux/x64/release/bundle/* media-deb/usr/local/bin/media/

# Create control file
cat > media-deb/DEBIAN/control << EOF
Package: media
Version: 0.1.0
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Your Name <your@email.com>
Description: Media application
 A Flutter application for media processing
EOF

# Build package
dpkg-deb --build media-deb media-0.1.0-amd64.deb
```

**Fastforge / repo CLI (recommended for the example app):** from `media_flutter/example` run `dart run media_cli dist --jobs linux-deb` (Fastforge runs `flutter build linux` as needed). Packaging metadata is in `linux/packaging/deb/make_config.yaml`. Artifacts land under `dist/<version>/` (see `distribute_options.yaml`).

**Files in bundle:**
- `media` - The executable
- `lib/libmedia.so` - Your native library
- `lib/ffmpeg`, `lib/ffprobe` - FFmpeg binaries (from release)
- `data/` - Flutter assets
- Other library dependencies

---

## ✅ Option 3: Docker for Linux Builds (from macOS)

You can build Linux binaries from macOS using Docker:

**Create Dockerfile:**
```dockerfile
FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl git unzip xz-utils zip libglu1-mesa \
    clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Flutter
RUN git clone https://github.com/flutter/flutter.git -b stable /flutter
ENV PATH="/flutter/bin:${PATH}"
RUN flutter doctor

# Set working directory
WORKDIR /app

# Copy project
COPY . .

# Build
WORKDIR /app/media_flutter/example
RUN flutter pub get
RUN flutter build linux --release

# Output will be in /app/media_flutter/example/build/linux/x64/release/bundle
```

**Build commands:**
```bash
cd ~/Desktop/media-rs

# Build Docker image
docker build -t media-linux-builder .

# Extract the built bundle
docker create --name media-temp media-linux-builder
docker cp media-temp:/app/media_flutter/example/build/linux/x64/release/bundle ./build-linux
docker rm media-temp

# Create tarball
cd build-linux
tar -czf media-linux-x64.tar.gz .
```

---

## 📦 Distribution Checklist

### Windows
- [ ] `media.exe` + all DLLs
- [ ] `ffmpeg.exe`, `ffprobe.exe`
- [ ] Optional: Create installer with Inno Setup or NSIS
- [ ] Test on clean Windows 10/11

### Linux
- [ ] Complete `bundle/` directory OR
- [ ] `.AppImage` (single portable file) OR
- [ ] `.deb` package (for Debian/Ubuntu)
- [ ] Include `libmedia.so`, `ffmpeg`, `ffprobe`
- [ ] Test on Ubuntu 22.04 LTS

### macOS
- [ ] Universal `.app` bundle (arm64 + x86_64)
- [ ] Optional: Create `.dmg` with `create-dmg`
- [ ] Code sign (requires Apple Developer account)
- [ ] Test on Intel and Apple Silicon Macs

---

## 🚀 Quick Start Summary

| Method | Platforms | Effort | Best For |
|--------|-----------|--------|----------|
| **GitHub Actions** | All | Low | Releases, automation |
| **Native builds** | One at a time | Medium | Development, testing |
| **Docker (Linux only)** | Linux from Mac | Medium | Linux builds without Linux PC |

---

## 🔗 Useful Links

- [Flutter Desktop Documentation](https://docs.flutter.dev/desktop)
- [Windows Desktop Support](https://docs.flutter.dev/platform-integration/windows/building)
- [Linux Desktop Support](https://docs.flutter.dev/platform-integration/linux/building)
- [GitHub Actions for Flutter](https://docs.flutter.dev/deployment/cd#github-actions-setup)

---

**Next Steps:**
1. ✅ Commit the GitHub Actions workflow
2. ✅ Push to GitHub
3. ✅ Trigger a build or push a tag
4. ✅ Download and test the artifacts
