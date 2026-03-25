/// Fixed delivery profile (bitrate ladder). Same values used for estimate + transcode.
class VideoDeliveryProfile {
  const VideoDeliveryProfile({
    required this.id,
    required this.maxLongEdgePx,
    required this.videoBitrateKbps,
    required this.audioBitrateKbps,
    this.muxOverheadBytes = 65536,
    this.encodeRealtimeSpeedFactor = 2.5,
  });

  /// Logical name, e.g. `hd720`, `sd480`.
  final String id;
  final int maxLongEdgePx;
  final int videoBitrateKbps;
  final int audioBitrateKbps;
  final int muxOverheadBytes;

  /// Heuristic: wall time ≈ duration / factor (e.g. 2.5 → ~2.5× realtime).
  final double encodeRealtimeSpeedFactor;

  static const VideoDeliveryProfile hd720 = VideoDeliveryProfile(
    id: 'hd720',
    maxLongEdgePx: 1280,
    videoBitrateKbps: 2500,
    audioBitrateKbps: 128,
  );

  static const VideoDeliveryProfile sd480 = VideoDeliveryProfile(
    id: 'sd480',
    maxLongEdgePx: 854,
    videoBitrateKbps: 1000,
    audioBitrateKbps: 96,
  );

  Map<String, dynamic> toMap() => {
        'id': id,
        'maxLongEdgePx': maxLongEdgePx,
        'videoBitrateKbps': videoBitrateKbps,
        'audioBitrateKbps': audioBitrateKbps,
        'muxOverheadBytes': muxOverheadBytes,
        'encodeRealtimeSpeedFactor': encodeRealtimeSpeedFactor,
      };

  static VideoDeliveryProfile fromMap(Map<String, dynamic> m) {
    return VideoDeliveryProfile(
      id: m['id'] as String,
      maxLongEdgePx: m['maxLongEdgePx'] as int,
      videoBitrateKbps: m['videoBitrateKbps'] as int,
      audioBitrateKbps: m['audioBitrateKbps'] as int,
      muxOverheadBytes: (m['muxOverheadBytes'] as int?) ?? 65536,
      encodeRealtimeSpeedFactor:
          (m['encodeRealtimeSpeedFactor'] as num?)?.toDouble() ?? 2.5,
    );
  }
}

class VideoSourceInfo {
  const VideoSourceInfo({
    required this.durationMs,
    required this.displayWidth,
    required this.displayHeight,
    this.rotationDegrees = 0,
    this.bitrateBps,
  });

  final int durationMs;
  final int displayWidth;
  final int displayHeight;
  final int rotationDegrees;
  final int? bitrateBps;

  static VideoSourceInfo fromMap(Map<Object?, Object?> m) {
    return VideoSourceInfo(
      durationMs: m['durationMs']! as int,
      displayWidth: m['displayWidth']! as int,
      displayHeight: m['displayHeight']! as int,
      rotationDegrees: (m['rotationDegrees'] as int?) ?? 0,
      bitrateBps: m['bitrateBps'] as int?,
    );
  }
}

class DeliveryEstimateRow {
  const DeliveryEstimateRow({
    required this.profileId,
    required this.width,
    required this.height,
    required this.estimatedSizeBytes,
    required this.videoBitrateKbps,
    required this.audioBitrateKbps,
    required this.estimatedEncodeTimeMs,
  });

  final String profileId;
  final int width;
  final int height;
  final int estimatedSizeBytes;
  final int videoBitrateKbps;
  final int audioBitrateKbps;
  final int estimatedEncodeTimeMs;

  static DeliveryEstimateRow fromMap(Map<Object?, Object?> m) {
    return DeliveryEstimateRow(
      profileId: m['profileId']! as String,
      width: m['width']! as int,
      height: m['height']! as int,
      estimatedSizeBytes: m['estimatedSizeBytes']! as int,
      videoBitrateKbps: m['videoBitrateKbps']! as int,
      audioBitrateKbps: m['audioBitrateKbps']! as int,
      estimatedEncodeTimeMs: m['estimatedEncodeTimeMs']! as int,
    );
  }
}

enum ThumbnailImageFormat { jpeg, png }
