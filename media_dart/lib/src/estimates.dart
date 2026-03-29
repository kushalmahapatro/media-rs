import 'dart:convert';
import 'dart:math' as math;

import 'package:media_dart/src/bindings/api.dart';

import 'estimates_platform_stub.dart'
    if (dart.library.io) 'estimates_platform_io.dart' as estimates_platform;
import 'transcode_encode_k_stub.dart'
    if (dart.library.io) 'transcode_encode_k_io.dart';

/// Telegram Android–style tier labels (see DrKLO Telegram `MediaController` bitrates).
enum VideoPreset {
  /// ~750 kb/s video cap, long edge 640.
  p360,

  /// ~1 Mb/s, long edge 848.
  p480,

  /// ~2.6 Mb/s, long edge 1280.
  p720,

  /// ~6.8 Mb/s, long edge 1920.
  p1080,
}

/// Target **video** bitrate (bits per second) for each preset.
int presetVideoBitrateBps(VideoPreset p) {
  switch (p) {
    case VideoPreset.p360:
      return 750_000;
    case VideoPreset.p480:
      return 1_000_000;
    case VideoPreset.p720:
      return 2_621_440;
    case VideoPreset.p1080:
      return 6_800_000;
  }
}

/// Long edge of the source video in pixels, or `0` if width/height are unknown.
int sourceLongEdge(VideoProbe probe) {
  final w = probe.width ?? 0;
  final h = probe.height ?? 0;
  if (w <= 0 || h <= 0) return 0;
  return math.max(w, h);
}

/// Presets whose target long edge does not exceed the source long edge.
///
/// If dimensions are unknown (`sourceLongEdge` is 0), every preset is returned so the UI can still offer a choice.
Iterable<VideoPreset> presetsFittingSource(VideoProbe probe) sync* {
  final src = sourceLongEdge(probe);
  for (final p in VideoPreset.values) {
    if (src == 0 || presetMaxLongEdge(p) <= src) {
      yield p;
    }
  }
}

/// Max long edge (pixels) for scaling heuristics.
int presetMaxLongEdge(VideoPreset p) {
  switch (p) {
    case VideoPreset.p360:
      return 640;
    case VideoPreset.p480:
      return 848;
    case VideoPreset.p720:
      return 1280;
    case VideoPreset.p1080:
      return 1920;
  }
}

/// Default assumed AAC audio bitrate when unknown (bits/s).
const int defaultAudioBitrateBps = 128_000;

/// Confidence for heuristic estimates.
enum EstimateConfidence { high, medium, low }

/// Estimated output size for a preset (bytes, approximate).
class CompressionSizeEstimate {
  final int estimatedBytes;
  final VideoPreset preset;
  final EstimateConfidence confidence;

  const CompressionSizeEstimate({
    required this.estimatedBytes,
    required this.preset,
    required this.confidence,
  });
}

/// Effective video bitrate: `min(source, preset)` when source known.
int effectiveVideoBitrateBps(VideoProbe probe, VideoPreset preset) {
  final cap = presetVideoBitrateBps(preset);
  final src = probe.videoBitrate;
  if (src == null) return cap;
  return math.min(src.toInt(), cap);
}

/// Typical **video** bits/s from `AVAssetExportSession` quality presets on iOS, which are
/// much higher than the Telegram-style caps in [presetVideoBitrateBps] and do not honor
/// the Rust layer's ignored `video_bitrate_kbps` argument.
int iosExportSessionTypicalVideoBitrateBps(VideoPreset preset) {
  switch (preset) {
    case VideoPreset.p360:
      return 3_200_000;
    case VideoPreset.p480:
      return 4_000_000;
    case VideoPreset.p720:
      return 6_000_000;
    case VideoPreset.p1080:
      return 12_000_000;
  }
}

/// Rough container overhead multiplier on top of raw A/V bits.
double _containerFudge() => 1.04;

/// Estimate compressed file size: `(vBps + aBps) * durationSeconds / 8 * fudge`.
CompressionSizeEstimate estimateCompressedSize({
  required VideoProbe probe,
  required VideoPreset preset,
  int audioBitrateBps = defaultAudioBitrateBps,
  bool includeAudio = true,
}) {
  final durMs = probe.durationMs?.toInt();
  if (durMs == null || durMs <= 0) {
    return CompressionSizeEstimate(
      estimatedBytes: 0,
      preset: preset,
      confidence: EstimateConfidence.low,
    );
  }
  final seconds = durMs / 1000.0;
  final iosExport = estimates_platform.encoderIgnoresPerBitrateCap();
  final vBps = (iosExport
          ? iosExportSessionTypicalVideoBitrateBps(preset)
          : effectiveVideoBitrateBps(probe, preset))
      .toDouble();
  final aBps = includeAudio ? audioBitrateBps.toDouble() : 0.0;
  final rawBits = (vBps + aBps) * seconds;
  final bytes = (rawBits / 8.0 * _containerFudge()).round();
  final conf = iosExport
      ? EstimateConfidence.medium
      : (probe.videoBitrate != null
          ? EstimateConfidence.high
          : EstimateConfidence.low);
  return CompressionSizeEstimate(
    estimatedBytes: bytes,
    preset: preset,
    confidence: conf,
  );
}

/// Whether the encode-time figure comes from on-device measurements or a generic fallback.
enum EncodeEstimateSource {
  /// `wall / media_duration` from [TranscodeCalibration] for this [VideoPreset] on this device.
  calibrated,

  /// No calibration yet (or [estimateEncodeWallClock] forced [k]); generic formula.
  heuristic,
}

/// Wall-clock encode time (not media duration).
class EncodeTimeEstimate {
  final Duration estimated;
  final EstimateConfidence confidence;
  final EncodeEstimateSource source;

  /// Past transcode samples merged into [source] == [EncodeEstimateSource.calibrated]; else `0`.
  final int calibrationSampleCount;

  const EncodeTimeEstimate({
    required this.estimated,
    required this.confidence,
    this.source = EncodeEstimateSource.heuristic,
    this.calibrationSampleCount = 0,
  });

  double get estimatedSeconds => estimated.inMilliseconds / 1000.0;
}

/// Running average of **wall-clock seconds per second of source media** for each [VideoPreset].
///
/// Used only when [estimateEncodeWallClock] is called with [useCalibration] true. After each
/// finished transcode, call [recordObservation] to feed those ratios.
class TranscodeCalibration {
  TranscodeCalibration._();

  /// Shared store; persist [exportJson] / [importJson] from the app (e.g. application support dir).
  static final TranscodeCalibration instance = TranscodeCalibration._();

  final Map<VideoPreset, _RatioEma> _byPreset = {};

  /// Weight of each new sample in the exponential moving average.
  static const double emaAlpha = 0.35;

  /// Records one finished transcode. [wallClockMs] is total wall time for the job.
  void recordObservation({
    required int sourceDurationMs,
    required int wallClockMs,
    required VideoPreset preset,
  }) {
    if (sourceDurationMs <= 0 || wallClockMs < 0) return;
    final durSec = sourceDurationMs / 1000.0;
    final ratio = (wallClockMs / 1000.0) / durSec;
    if (!ratio.isFinite || ratio < 0) return;
    final prev = _byPreset[preset];
    if (prev == null) {
      _byPreset[preset] = _RatioEma(ratio, 1);
    } else {
      prev.merge(ratio, emaAlpha);
    }
  }

  /// Smoothed wall seconds per media second for [preset], or `null` if unknown.
  double? ratioForPreset(VideoPreset preset) => _byPreset[preset]?.value;

  int sampleCountForPreset(VideoPreset preset) => _byPreset[preset]?.count ?? 0;

  /// JSON for disk; schema version `v1`.
  String exportJson() {
    final Map<String, Object?> inner = {};
    for (final e in _byPreset.entries) {
      inner[e.key.name] = {'ratio': e.value.value, 'n': e.value.count};
    }
    return jsonEncode({'v1': inner});
  }

  /// Restores state from [exportJson]. Unknown keys are ignored.
  void importJson(String jsonStr) {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map) return;
    final inner = decoded['v1'];
    if (inner is! Map) return;
    for (final preset in VideoPreset.values) {
      final raw = inner[preset.name];
      if (raw is! Map) continue;
      final r = raw['ratio'];
      final n = raw['n'];
      if (r is num && n is int && n > 0) {
        _byPreset[preset] = _RatioEma(r.toDouble(), n);
      }
    }
  }

  void clear() => _byPreset.clear();
}

class _RatioEma {
  double value;
  int count;

  _RatioEma(this.value, this.count);

  void merge(double newRatio, double alpha) {
    value = alpha * newRatio + (1.0 - alpha) * value;
    count++;
  }
}

/// Wall-clock encode time: by default a resolution-aware **heuristic** (typically close enough
/// for UI progress). Set [useCalibration] to true to prefer [calibration] (past measured
/// wall/media ratios) when available for [preset].
///
/// Pass [k] to override the heuristic multiplier only (ignored when calibrated path is used).
EncodeTimeEstimate estimateEncodeWallClock({
  required VideoProbe probe,
  required VideoPreset preset,
  double? k,
  TranscodeCalibration? calibration,
  bool useCalibration = false,
}) {
  final durMs = probe.durationMs?.toInt() ?? 0;
  if (durMs <= 0) {
    return const EncodeTimeEstimate(
      estimated: Duration.zero,
      confidence: EstimateConfidence.low,
    );
  }
  final durSec = durMs / 1000.0;
  if (useCalibration) {
    final cal = calibration ?? TranscodeCalibration.instance;
    final ratio = cal.ratioForPreset(preset);
    final n = cal.sampleCountForPreset(preset);
    if (ratio != null && ratio > 0) {
      final seconds = durSec * ratio;
      final conf = n >= 3 ? EstimateConfidence.high : EstimateConfidence.medium;
      return EncodeTimeEstimate(
        estimated: Duration(milliseconds: (seconds * 1000).round()),
        confidence: conf,
        source: EncodeEstimateSource.calibrated,
        calibrationSampleCount: n,
      );
    }
  }

  final kEff = k ?? defaultTranscodeEncodeK();
  final srcW = probe.width ?? 0;
  final srcH = probe.height ?? 0;
  final srcPixels = (srcW * srcH).clamp(1, 1 << 28);
  final longEdge = math.max(srcW, srcH);
  final tgtEdge = presetMaxLongEdge(preset);
  final scaleDown = longEdge > 0 ? (longEdge / tgtEdge).clamp(1.0, 8.0) : 1.0;
  final nominalOutArea = (tgtEdge * tgtEdge * 9 / 16.0).clamp(1.0, 1e12);
  final pixelRatio = srcPixels / nominalOutArea;
  var complexity = math.sqrt(pixelRatio) * math.log(scaleDown + 1) / math.ln2;
  complexity = complexity.clamp(0.0, 14.0);
  final seconds = durSec * kEff * (1.0 + 0.24 * complexity);
  final conf = (probe.width != null && probe.height != null)
      ? EstimateConfidence.medium
      : EstimateConfidence.low;
  return EncodeTimeEstimate(
    estimated: Duration(milliseconds: (seconds * 1000).round()),
    confidence: conf,
    source: EncodeEstimateSource.heuristic,
    calibrationSampleCount: 0,
  );
}
