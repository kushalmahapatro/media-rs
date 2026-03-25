import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// Platform implementation via [MethodChannel].
class OsVideoDelivery {
  OsVideoDelivery._();

  static const MethodChannel _channel =
      MethodChannel('com.media_rs/os_video_delivery');

  static final OsVideoDelivery instance = OsVideoDelivery._();

  /// Whether this platform has a native implementation (Android / iOS / macOS).
  static bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  Future<VideoSourceInfo> probe(String path) async {
    final map = await _channel.invokeMapMethod<String, Object?>('probe', {
      'path': path,
    });
    if (map == null) {
      throw StateError('probe returned null');
    }
    return VideoSourceInfo.fromMap(map);
  }

  Future<List<DeliveryEstimateRow>> estimateDelivery({
    required String path,
    required List<VideoDeliveryProfile> profiles,
  }) async {
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'estimateDelivery',
      {
        'path': path,
        'profiles': profiles.map((p) => p.toMap()).toList(),
      },
    );
    if (raw == null) return [];
    return raw.map(DeliveryEstimateRow.fromMap).toList();
  }

  Future<String> transcode({
    required String inputPath,
    required String outputPath,
    required VideoDeliveryProfile profile,
  }) async {
    final out = await _channel.invokeMethod<String>('transcode', {
      'inputPath': inputPath,
      'outputPath': outputPath,
      'profile': profile.toMap(),
    });
    if (out == null || out.isEmpty) {
      throw StateError('transcode returned empty path');
    }
    return out;
  }

  /// When set, overrides Android retriever/track rotation (e.g. angle from FFmpeg `getVideoInfo`).
  Future<Uint8List> videoThumbnail({
    required String path,
    int timeMs = 0,
    int? maxWidth,
    int? maxHeight,
    ThumbnailImageFormat format = ThumbnailImageFormat.jpeg,
    int? rotationDegrees,
  }) async {
    final Map<String, Object?> args = {
      'path': path,
      'timeMs': timeMs,
      'maxWidth': maxWidth ?? 0,
      'maxHeight': maxHeight ?? 0,
      'format': format == ThumbnailImageFormat.png ? 'png' : 'jpeg',
    };
    if (rotationDegrees != null) {
      args['rotationDegrees'] = rotationDegrees;
    }
    final bytes = await _channel.invokeMethod<Uint8List>('videoThumbnail', args);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('videoThumbnail returned empty');
    }
    return bytes;
  }
}
