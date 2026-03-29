# media_flutter

**Flutter plugin** wrapping [**media_dart**](../media_dart/): adds an **Android Gradle library** so **Media3 Transformer** and JNI entry points resolve with the app’s class loader. **Re-exports** all of `package:media_dart/media_dart.dart`.

| | |
|--|--|
| **Platforms (plugin)** | **Android** only (`MediaPlugin` in `android/`) |
| **iOS / macOS / Windows / Linux** | No plugin native code; **`media_dart`** still builds and runs via **native assets** / hooks |

**Dart-only or non-Flutter clients:** depend on **`media_dart`** only.

**Docs:** [DOCUMENTATION.md](../DOCUMENTATION.md).

## Android module

| Piece | Purpose |
|-------|---------|
| [`MediaTranscoder.kt`](android/src/main/kotlin/dev/flutter/packages/media_flutter/MediaTranscoder.kt) | Media3 **Transformer** on main thread: H.264 + AAC, `Presentation` scale, **`TransformationRequest`** with **HDR tone-map to SDR (OpenGL)** so portrait/HDR phone video does not fall back to broken HEVC HDR encoders |
| [`MediaJni.kt`](android/src/main/kotlin/dev/flutter/packages/media_flutter/MediaJni.kt) | `System.loadLibrary("media")`, `transcodeProgress` JNI callback into Rust |
| [`MediaPlugin.kt`](android/src/main/kotlin/dev/flutter/packages/media_flutter/MediaPlugin.kt) | Standard Flutter plugin registration |

## Gradle / Media3

- **`androidx.media3:media3-transformer`** and **`media3-effect`** **1.5.1** (pinned).
- **`resolutionStrategy`** forces **all** `androidx.media3` artifacts to **1.5.1** so another dependency (e.g. **video_player**) cannot downgrade Transformer and cause **`NoSuchMethodError`** on `Transformer.Builder`.

**Consuming apps** that hit duplicate Media3 versions should also align versions (the **example** applies the same strategy in `example/android/build.gradle.kts`).

## Consume

```yaml
dependencies:
  media_flutter:
    path: packages/media/media_flutter
```

```dart
import 'package:media_flutter/media_flutter.dart';

await Media.init();
```

## Example

```bash
cd packages/media/media_flutter/example
flutter pub get
flutter run
```

See [example/README.md](example/README.md).
