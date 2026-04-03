# macOS Support - Dual Mode (CLI & Flutter)

## 🎯 Overview

This implementation supports **both CLI and Flutter apps** on macOS with automatic FFmpeg handling.

## 📁 How It Works

### For Flutter Apps (Automatic)

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Hook downloads FFmpeg to media_dart/native/ffmpeg/      │
│    (darwin-arm64/ or darwin-x64/)                           │
├─────────────────────────────────────────────────────────────┤
│ 2. Flutter builds the app                                   │
│    → Creates MyApp.app                                      │
├─────────────────────────────────────────────────────────────┤
│ 3. Podspec script_phase runs automatically                 │
│    → Copies ffmpeg/ffprobe to Contents/Frameworks/         │
│    → No manual steps needed!                                │
├─────────────────────────────────────────────────────────────┤
│ 4. Runtime: bundled_tools.rs finds FFmpeg                 │
│    → Looks in Contents/Frameworks/ first                    │
└─────────────────────────────────────────────────────────────┘
```

**User experience:** Just add `media_flutter` to pubspec.yaml and build. FFmpeg is copied automatically.

### For CLI Apps (Dart-only)

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Hook downloads FFmpeg to media_dart/native/ffmpeg/      │
│    (same as Flutter)                                        │
├─────────────────────────────────────────────────────────────┤
│ 2. User runs: dart compile exe my_app.dart                  │
├─────────────────────────────────────────────────────────────┤
│ 3. User copies ffmpeg/ffprobe next to the executable       │
│    (or adds to PATH)                                        │
├─────────────────────────────────────────────────────────────┤
│ 4. Runtime: bundled_tools.rs finds FFmpeg                 │
│    → Looks next to libmedia.dylib                           │
└─────────────────────────────────────────────────────────────┘
```

**User experience:** Download FFmpeg manually or use the helper script.

---

## 🔧 Setup Instructions

### Flutter App

**pubspec.yaml:**
```yaml
dependencies:
  media_flutter: ^0.1.0
```

**Build:**
```bash
flutter build macos --release
# FFmpeg is copied automatically via podspec script_phase
```

**Verify:**
```bash
ls build/macos/Build/Products/Release/MyApp.app/Contents/Frameworks/
# Should show: media.framework, ffmpeg, ffprobe
```

### CLI App

**pubspec.yaml:**
```yaml
dependencies:
  media_dart: ^0.1.0
```

**Setup FFmpeg:**
```bash
# Download FFmpeg first
cd your_project
dart run media_dart:hook/build.dart

# Or manually copy to native/ffmpeg/darwin-arm64/
```

**Build:**
```bash
dart compile exe bin/my_app.dart -o my_cli

# Copy FFmpeg next to the CLI binary
cp native/ffmpeg/darwin-arm64/ffmpeg my_cli_ffmpeg
cp native/ffmpeg/darwin-arm64/ffprobe my_cli_ffprobe
```

**Or use the helper:**
```bash
# From media_dart package
dart run media_dart:setup_macos_cli
```

---

## 📂 Directory Structure

### Flutter App Bundle
```
MyApp.app/
└── Contents/
    ├── Frameworks/
    │   ├── media.framework/      # Small lib (~5-10 MB)
    │   ├── ffmpeg                # FFmpeg binary (~22 MB)
    │   └── ffprobe               # FFprobe binary (~22 MB)
    └── MacOS/
        └── MyApp                 # Flutter executable
```

### CLI App
```
my_cli_app/
├── my_cli                      # Compiled executable
├── libmedia.dylib              # Small lib (~5-10 MB)
├── ffmpeg                      # FFmpeg binary (~22 MB)
└── ffprobe                     # FFprobe binary (~22 MB)
```

---

## 🔍 How bundled_tools.rs Detects FFmpeg

```rust
// macOS detection logic (simplified)
fn sibling_tool(name: &str) -> PathBuf {
    // 1. Try next to libmedia.dylib (CLI apps)
    if let Some(dir) = dylib_parent_dir() {
        let p = dir.join(name);
        if p.is_file() {
            return p;
        }
        
        // 2. Try Contents/Frameworks/ (Flutter apps)
        if let Some(frameworks) = dir.parent().map(|p| p.join("Frameworks")) {
            let p = frameworks.join(name);
            if p.is_file() {
                return p;
            }
        }
    }
    
    panic!("FFmpeg not found");
}
```

---

## ✅ Compatibility

| Scenario | Detection Method | Works? |
|----------|-----------------|--------|
| Flutter macOS app | `Contents/Frameworks/` | ✅ Yes |
| CLI with bundled FFmpeg | Next to libmedia.dylib | ✅ Yes |
| CLI with FFmpeg in PATH | Fallback to $PATH | ⚠️ Not implemented |
| Embedded FFmpeg | `include_bytes!` | ✅ Compile-time flag |

---

## 🐛 Troubleshooting

### FFmpeg not found (Flutter)

**Check:**
```bash
# 1. Verify hook ran
ls media_dart/native/ffmpeg/darwin-arm64/
# Should show: ffmpeg, ffprobe

# 2. Check if podspec script ran
ls build/macos/Build/Products/Release/MyApp.app/Contents/Frameworks/ffmpeg

# 3. Rebuild if missing
flutter clean
flutter build macos --release --verbose
```

### FFmpeg not found (CLI)

**Check:**
```bash
# 1. Download FFmpeg
dart run media_dart:hook/build.dart

# 2. Verify location
ls native/ffmpeg/darwin-arm64/

# 3. Copy next to your binary
cp native/ffmpeg/darwin-arm64/ffmpeg ./
cp native/ffmpeg/darwin-arm64/ffprobe ./
```

---

## 📊 File Sizes

| Component | Size | Notes |
|-----------|------|-------|
| libmedia.dylib | ~5-10 MB | Small library only |
| ffmpeg | ~22 MB (arm64) / ~76 MB (x86_64) | Separate binary |
| ffprobe | ~22 MB (arm64) / ~76 MB (x86_64) | Separate binary |
| **Total Flutter app** | **~50-70 MB** | With separate FFmpeg |
| **Old embedded approach** | **~241 MB** | FFmpeg in library |

**Savings:** ~170 MB smaller! 🎉

---

## 🔗 Related Files

- `media_flutter/macos/media_flutter.podspec` - Podspec with script_phase
- `media_dart/rust/media/src/bundled_tools.rs` - Runtime detection
- `media_dart/hook/build.dart` - Download logic
- `tool/native_build/lib/media_macos_bundle.dart` - Helper functions
