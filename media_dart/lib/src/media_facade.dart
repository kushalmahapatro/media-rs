import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';
import 'package:path/path.dart' as p;

import 'package:media_dart/src/bindings/api.dart' as api;
import 'package:media_dart/src/bindings/frb_generated.dart';

/// High-level API: [init] once, then [probe], thumbnails, [timelineThumbnailsStream], [transcodeVideoStream].
class Media {
  Media._();

  static var _inited = false;

  /// Loads native `media` library. Prefer passing [libraryPath] when running
  /// the example (see README paths for debug/release artifacts).
  static Future<void> init({String? packageRoot, String? libraryPath}) async {
    if (_inited) return;

    if (libraryPath != null) {
      await RustLib.init(externalLibrary: ExternalLibrary.open(libraryPath));
    } else {
      final root = packageRoot ?? _findPackageRoot();
      final name = _libName();
      final debugLib = p.join(root, 'rust', 'media', 'target', 'debug', name);
      final releaseLib = p.join(root, 'rust', 'media', 'target', 'release', name);
      if (File(debugLib).existsSync()) {
        await RustLib.init(externalLibrary: ExternalLibrary.open(debugLib));
      } else if (File(releaseLib).existsSync()) {
        await RustLib.init(externalLibrary: ExternalLibrary.open(releaseLib));
      } else {
        await RustLib.init();
      }
    }
    _inited = true;
  }

  /// Directory that contains `rust/media/` (the [media_dart] package root).
  static String _findPackageRoot() {
    var dir = Directory.current;
    for (var i = 0; i < 14; i++) {
      final flat = File(p.join(dir.path, 'rust', 'media', 'Cargo.toml'));
      if (flat.existsSync()) return dir.path;
      final nested = File(
        p.join(dir.path, 'media_dart', 'rust', 'media', 'Cargo.toml'),
      );
      if (nested.existsSync()) {
        return p.join(dir.path, 'media_dart');
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return Directory.current.path;
  }

  static String _libName() {
    if (Platform.isMacOS) return 'libmedia.dylib';
    if (Platform.isLinux) return 'libmedia.so';
    if (Platform.isWindows) return 'media.dll';
    return 'libmedia.so';
  }

  static Future<api.VideoProbe> probe(String path) {
    _ensureInit();
    return api.probeVideo(path: path);
  }

  /// In-memory thumbnail; [maxEdge] caps the long side (aspect ratio preserved).
  static Future<Uint8List> thumbnailImage({
    required String path,
    double timeSec = 1.0,
    int maxEdge = 720,
    api.ThumbnailFormat format = api.ThumbnailFormat.png,
  }) {
    _ensureInit();
    return api.thumbnailImage(
      path: path,
      timeSec: timeSec,
      maxEdge: maxEdge,
      format: format,
    );
  }

  /// Writes one frame to [outputPath] and returns the resolved path (canonical when possible).
  static Future<String> thumbnailSaveToPath({
    required String path,
    required String outputPath,
    double timeSec = 1.0,
    int maxEdge = 720,
    api.ThumbnailFormat format = api.ThumbnailFormat.png,
  }) {
    _ensureInit();
    return api.thumbnailSaveToPath(
      path: path,
      outputPath: outputPath,
      timeSec: timeSec,
      maxEdge: maxEdge,
      format: format,
    );
  }

  /// Evenly spaced thumbnails over the video duration; events arrive one-by-one as Rust generates them.
  static Stream<api.TimelineThumbnail> timelineThumbnailsStream({
    required String path,
    required int frameCount,
    int maxEdge = 720,
    api.ThumbnailFormat format = api.ThumbnailFormat.png,
  }) {
    _ensureInit();
    return api.timelineThumbnails(
      path: path,
      frameCount: frameCount,
      maxEdge: maxEdge,
      format: format,
    );
  }

  /// Same as [thumbnailImage] with PNG output.
  static Future<Uint8List> thumbnailPng({
    required String path,
    double timeSec = 1.0,
    int maxEdge = 720,
  }) {
    return thumbnailImage(
      path: path,
      timeSec: timeSec,
      maxEdge: maxEdge,
      format: api.ThumbnailFormat.png,
    );
  }

  static Stream<api.TranscodeProgress> transcodeVideoStream({
    required String inputPath,
    required String outputPath,
    required int videoBitrateKbps,
    required int maxWidth,
    int audioBitrateKbps = 128,
  }) {
    _ensureInit();
    return api.transcodeVideo(
      inputPath: inputPath,
      outputPath: outputPath,
      videoBitrateKbps: videoBitrateKbps,
      maxWidth: maxWidth,
      audioBitrateKbps: audioBitrateKbps,
    );
  }

  static void _ensureInit() {
    if (!_inited) {
      throw StateError('Call Media.init() first.');
    }
  }
}
