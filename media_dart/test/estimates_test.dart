import 'package:media_dart/media_dart.dart';
import 'package:test/test.dart';

void main() {
  test('estimateCompressedSize uses min(source, preset)', () {
    final probe = VideoProbe(
      durationMs: 60_000,
      width: 1280,
      height: 720,
      videoBitrate: 10_000_000,
      audioBitrate: null,
      frameRate: 30,
      videoCodec: 'h264',
      audioCodec: 'aac',
    );
    final est = estimateCompressedSize(probe: probe, preset: VideoPreset.p720);
    final cap = presetVideoBitrateBps(VideoPreset.p720);
    final seconds = 60.0;
    final expectedBits = (cap + defaultAudioBitrateBps) * seconds * 1.04;
    expect(est.estimatedBytes, (expectedBits / 8).round());
    expect(est.confidence, EstimateConfidence.high);
  });

  test('unknown source bitrate falls back to preset cap', () {
    final probe = VideoProbe(
      durationMs: 10_000,
      width: 1920,
      height: 1080,
      videoBitrate: null,
      audioBitrate: null,
      frameRate: null,
      videoCodec: null,
      audioCodec: null,
    );
    final est = estimateCompressedSize(probe: probe, preset: VideoPreset.p480);
    expect(est.confidence, EstimateConfidence.low);
    expect(est.estimatedBytes, greaterThan(0));
  });

  test('estimateEncodeWallClock scales with duration and explicit k', () {
    TranscodeCalibration.instance.clear();
    final probe = VideoProbe(
      durationMs: 60_000,
      width: 1280,
      height: 720,
      videoBitrate: 5_000_000,
      audioBitrate: null,
      frameRate: 30,
      videoCodec: 'h264',
      audioCodec: 'aac',
    );
    // Fixed k avoids platform-specific defaults in CI.
    final eta = estimateEncodeWallClock(
      probe: probe,
      preset: VideoPreset.p720,
      k: 1.0,
    );
    // 720p same tier as p720: complexity term ~1 → ~1.24× duration at k=1.
    expect(eta.estimatedSeconds, greaterThanOrEqualTo(70.0));
    expect(eta.estimatedSeconds, lessThanOrEqualTo(82.0));
    expect(eta.confidence, EstimateConfidence.medium);
    expect(eta.source, EncodeEstimateSource.heuristic);
  });

  test('calibration overrides heuristic with measured wall/media ratio', () {
    final cal = TranscodeCalibration.instance;
    cal.clear();
    cal.recordObservation(
      sourceDurationMs: 600_000,
      wallClockMs: 120_000,
      preset: VideoPreset.p360,
    );
    final probe = VideoProbe(
      durationMs: 600_000,
      width: 1920,
      height: 1080,
      videoBitrate: 8_000_000,
      audioBitrate: null,
      frameRate: 30,
      videoCodec: 'h264',
      audioCodec: 'aac',
    );
    final eta = estimateEncodeWallClock(
      probe: probe,
      preset: VideoPreset.p360,
      calibration: cal,
      useCalibration: true,
    );
    expect(eta.source, EncodeEstimateSource.calibrated);
    expect(eta.estimatedSeconds, closeTo(120.0, 0.5));
    expect(eta.calibrationSampleCount, 1);
    cal.clear();
  });

  test('TranscodeCalibration import/export roundtrip', () {
    final a = TranscodeCalibration.instance;
    a.clear();
    a.recordObservation(
      sourceDurationMs: 100_000,
      wallClockMs: 25_000,
      preset: VideoPreset.p480,
    );
    final json = a.exportJson();
    a.clear();
    expect(a.ratioForPreset(VideoPreset.p480), isNull);
    a.importJson(json);
    expect(a.ratioForPreset(VideoPreset.p480), isNotNull);
    a.clear();
  });
}
