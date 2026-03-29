# `package:media` (compatibility shim)

This directory is a **Flutter package** that re-exports [**media_flutter**](media_flutter/) via [`lib/media.dart`](lib/media.dart).

| | |
|--|--|
| **Pub name** | `media` |
| **SDK** | Dart ^3.10, Flutter >=3.22 |
| **Use when** | An app already depends on `path: …/packages/media` and imports `package:media/...` |

**Prefer for new code:** depend on [`media_dart`](media_dart/) (Dart + native hooks) and/or [`media_flutter`](media_flutter/) (Flutter + Android plugin) directly.

## Layout

```
packages/media/
├── lib/media.dart          # export 'package:media_flutter/media_flutter.dart'
├── pubspec.yaml            # flutter + media_flutter path
├── DOCUMENTATION.md        # API + per-platform behavior
├── media_dart/             # Rust + FRB + hooks + estimates (no Flutter SDK)
└── media_flutter/          # Android plugin + re-export of media_dart
    └── example/            # demo app (package name: media_example)
```

## Documentation

- **[DOCUMENTATION.md](DOCUMENTATION.md)** — APIs, types, probe / thumbnail / timeline / transcode / estimates per OS, JNI & Media3 notes.
- **[media_dart/README.md](media_dart/README.md)** — consuming `media_dart`, FFmpeg hook, regenerating FRB bindings.
- **[media_flutter/README.md](media_flutter/README.md)** — Android plugin & Gradle.
- **[media_flutter/example/README.md](media_flutter/example/README.md)** — running the sample app.
