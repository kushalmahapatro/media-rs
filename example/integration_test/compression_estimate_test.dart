// Integration test: Compare compression estimate vs actual.
// Run: flutter test integration_test/compression_estimate_test.dart
// Requires: TEST_VIDEO_PATH env var or a test video at ./test_video.mp4
// Prerequisites: Run setup (dart run tool/setup.dart --windows/linux) to build native libs

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media/media.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Estimate vs actual: size and duration within ±15%',
      (WidgetTester tester) async {
    // Init media (loads native lib)
    await Media.init(kDebugMode: true);

    // Get test video path
    final testVideoPath = Platform.environment['TEST_VIDEO_PATH'] ??
        (await _findTestVideo()) ??
        '';
    if (testVideoPath.isEmpty || !await File(testVideoPath).exists()) {
      // Skip if no test video
      print(
        'Skipping: Set TEST_VIDEO_PATH or place test_video.mp4 in example dir',
      );
      return;
    }

    final tempDir = (await getTemporaryDirectory()).path;
    final outputPath = '$tempDir/compression_estimate_test_output.mp4';

    final params = CompressParams(
      targetBitrateKbps: 1000,
      preset: 'veryfast',
      crf: 23,
      width: 640,
      height: 360,
      sampleDurationMs: BigInt.from(1500),
    );

    // 1. Get estimate
    final estimate = await estimateCompression(
      path: testVideoPath,
      tempOutputPath: tempDir,
      params: params,
    );

    // 2. Perform compression and measure time
    final stopwatch = Stopwatch()..start();
    final resultPath = await compressVideo(
      path: testVideoPath,
      outputPath: outputPath,
      params: params,
    );
    stopwatch.stop();
    final actualDurationMs = stopwatch.elapsedMilliseconds;

    // 3. Get actual file size
    final outputFile = File(resultPath);
    final actualSize = await outputFile.length();

    // 4. Compare (tolerance ±15%)
    final estSize = estimate.estimatedSizeBytes.toInt();
    final estDuration = estimate.estimatedDurationMs.toInt();
    final sizeRatio = actualSize > 0 ? estSize / actualSize : 1.0;
    final durationRatio =
        actualDurationMs > 0 ? estDuration / actualDurationMs : 1.0;

    print(
      'Estimate: size=$estSize bytes, duration=$estDuration ms',
    );
    print(
      'Actual: size=$actualSize bytes, duration=$actualDurationMs ms',
    );
    print('Size ratio: $sizeRatio, Duration ratio: $durationRatio');

    expect(
      sizeRatio,
      inInclusiveRange(0.85, 1.15),
      reason: 'Estimated size $estSize should be ±15% of actual $actualSize',
    );
    expect(
      durationRatio,
      inInclusiveRange(0.85, 1.15),
      reason:
          'Estimated duration $estDuration ms should be ±15% of actual $actualDurationMs ms',
    );

    // Cleanup
    await outputFile.delete().catchError((_) {});
  });
}

Future<String?> _findTestVideo() async {
  final candidates = [
    'test_video.mp4',
    'sample_1280x720.mp4',
    'HDR.MOV',
    '../native/HDR.MOV',
  ];
  for (final name in candidates) {
    final f = File(name);
    if (await f.exists()) return f.absolute.path;
  }
  return null;
}
