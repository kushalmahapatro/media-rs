# ✅ macOS Plugin Update - Automatic FFmpeg Copy

## 🎯 What Changed

**Before:** Users had to manually run `./macos/copy_ffmpeg.sh` after building

**Now:** FFmpeg copies **automatically** via CocoaPods script_phase! 🎉

---

## 📦 Changes Made

### 1. Moved Script to Plugin
- **Old location:** `media_flutter/example/macos/copy_ffmpeg.sh` (example-specific)
- **New location:** `media_flutter/macos/copy_ffmpeg.sh` (plugin-wide)
- ✅ Now part of the plugin, works for all users!

### 2. Added Podspec Auto-Copy
```ruby
s.script_phases = [
  {
    :name => 'Copy FFmpeg Binaries',
    :script => 'bash "${PODS_TARGET_SRCROOT}/copy_ffmpeg.sh" ...',
    :execution_position => :after_compile
  }
]
```
- Runs automatically after Xcode compiles
- Works for both Debug and Release builds
- Won't fail build if FFmpeg missing (just warns)

### 3. Smart FFmpeg Detection
The script now searches **3 locations**:
1. Development mode: `../../media_dart/native/ffmpeg/`
2. Pub cache: `~/.pub-cache/hosted/*/media_dart-*/native/ffmpeg/`
3. User project: `native/ffmpeg/`

This works in **all scenarios**:
- ✅ Local development (mono-repo)
- ✅ Published packages (pub.dev)
- ✅ Manual FFmpeg placement

---

## 🚀 What You Need to Do (M1 Mac)

### Step 1: Pull Latest Changes
```bash
cd ~/Projects/media-rs
git pull origin feat/windows-linux-mac-support
```

### Step 2: Clean Build Cache
```bash
cd media_flutter/example
flutter clean
rm -rf macos/Pods macos/Flutter/ephemeral
```

### Step 3: Rebuild
```bash
# This will automatically copy FFmpeg via Podspec!
flutter build macos --release

# Or for debug mode
flutter run
```

### Step 4: Verify FFmpeg Copied
```bash
ls -lh build/macos/Build/Products/Release/media.app/Contents/Frameworks/
# Should show: media.framework, ffmpeg, ffprobe
```

### Step 5: Create DMG
```bash
melos run dist-macos-dmg
```

---

## 📊 Expected Results

### File Sizes
- **media.framework:** ~2.5 MB (universal arm64 + x86_64)
- **ffmpeg:** 22 MB (arm64) or 76 MB (x86_64)
- **ffprobe:** 22 MB (arm64) or 76 MB (x86_64)
- **Total app:** ~50-200 MB (depending on architecture)

### Build Output
You should see in the Xcode build log:
```
📦 Found FFmpeg in development mode: /Users/km/Projects/media-rs/media_dart/native/ffmpeg/darwin-arm64
✅ Copied FFmpeg to build/.../media.app/Contents/Frameworks
   - ffmpeg: 22M
   - ffprobe: 22M
```

---

## 🎉 Benefits

### For End Users
- ✅ **No manual steps** - just `flutter build macos`
- ✅ **Works automatically** - Podspec handles everything
- ✅ **Both Debug & Release** - copies to whichever you build

### For Plugin Authors
- ✅ **Part of the package** - no need to document manual steps
- ✅ **Smart detection** - works in dev and published modes
- ✅ **Non-breaking** - won't fail builds if FFmpeg missing

### For Package Users
- ✅ **Zero configuration** - add to pubspec.yaml and build
- ✅ **One download** - run `dart run media_dart:hook/build.dart` once
- ✅ **Auto-updates** - FFmpeg copies on every build

---

## 🐛 Troubleshooting

### If FFmpeg Doesn't Copy

**Check Podspec ran:**
```bash
# Look for this in build output:
# "Copy FFmpeg Binaries" script phase
```

**Run script manually:**
```bash
cd ~/Projects/media-rs/media_flutter/macos
./copy_ffmpeg.sh ../../example/build/macos/Build/Products/Release/media.app
```

**Check FFmpeg exists:**
```bash
ls -la ~/Projects/media-rs/media_dart/native/ffmpeg/darwin-arm64/
# Should show: ffmpeg, ffprobe (not in subdirectories!)
```

### If Build Fails

**Clean everything:**
```bash
flutter clean
rm -rf macos/Pods macos/Flutter
pod cache clean --all
flutter pub get
flutter build macos --release
```

---

## 📖 Documentation

- **Plugin README:** `media_flutter/macos/README.md` (new!)
- **Architecture guide:** `MACOS_DUAL_MODE.md`
- **Script source:** `media_flutter/macos/copy_ffmpeg.sh`

---

## ✅ Summary

**You're absolutely right** - the script should be part of media_flutter, not the example!

Now:
1. Script is in `media_flutter/macos/` (plugin-wide)
2. Podspec calls it automatically
3. Works for all users out of the box
4. Smart detection finds FFmpeg in any scenario

**Pull the latest changes and rebuild - FFmpeg will copy automatically!** 🚀
