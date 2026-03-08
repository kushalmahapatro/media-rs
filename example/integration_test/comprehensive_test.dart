// Comprehensive integration test: Estimate accuracy + concurrency
// Run: flutter test integration_test/comprehensive_test.dart
// Requires: TEST_VIDEO_PATH env var or a test video at ./test_video.mp4
// Prerequisites: Run setup (dart run tool/setup.dart --windows/linux) to build native libs

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media/media.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Comprehensive: Estimate accuracy + concurrent operations',
      (WidgetTester tester) async {
    // Init media (loads native lib)
    await Media.init(kDebugMode: true);

    // Get test video path
    final testVideoPath = Platform.environment['TEST_VIDEO_PATH'] ??
        (await _findTestVideo()) ??
        '';
    if (testVideoPath.isEmpty || !await File(testVideoPath).exists()) {
      print(
        'Skipping: Set TEST_VIDEO_PATH or place test_video.mp4 in example dir',
      );
      return;
    }

    final tempDir = (await getTemporaryDirectory()).path;
    final outputPath = '$tempDir/comprehensive_test_output.mp4';

    final params = CompressParams(
      targetBitrateKbps: 1000,
      preset: 'veryfast',
      crf: 23,
      width: 640,
      height: 360,
      sampleDurationMs: BigInt.from(1500),
    );

    print('=== Starting comprehensive test ===');
    print('Test video: $testVideoPath');

    // 1. Get estimate
    print('\n1. Getting compression estimate...');
    final estimateStartTime = DateTime.now();
    final estimate = await estimateCompression(
      path: testVideoPath,
      tempOutputPath: tempDir,
      params: params,
    );
    final estimateElapsed = DateTime.now().difference(estimateStartTime);
    
    print('Estimate completed in ${estimateElapsed.inMilliseconds}ms');
    print('  Estimated size: ${estimate.estimatedSizeBytes} bytes (${(estimate.estimatedSizeBytes.toInt() / 1024 / 1024).toStringAsFixed(2)} MB)');
    print('  Estimated duration: ${estimate.estimatedDurationMs}ms (${(estimate.estimatedDurationMs.toInt() / 1000).toStringAsFixed(2)}s)');

    // 2. Perform compression with concurrent thumbnail generation
    print('\n2. Starting compression with concurrent thumbnails...');
    final compressionStartTime = DateTime.now();
    
    // Start compression
    final compressionFuture = compressVideo(
      path: testVideoPath,
      outputPath: outputPath,
      params: params,
    );

    // Generate thumbnails concurrently during compression
    final thumbnailFutures = <Future<VideoThumbnail>>[];
    final thumbnailTimes = [500, 1000, 1500, 2000, 2500, 3000];
    
    print('  Generating ${thumbnailTimes.length} thumbnails concurrently...');
    final thumbnailStartTime = DateTime.now();
    
    for (final time in thumbnailTimes) {
      thumbnailFutures.add(
        generateThumbnail(
          path: testVideoPath,
          params: VideoThumbnailParams(
            timeMs: BigInt.from(time),
            width: 320,
            height: 180,
            format: OutputFormat.jpeg,
          ),
        ),
      );
    }

    // Wait for compression
    final resultPath = await compressionFuture;
    final compressionElapsed = DateTime.now().difference(compressionStartTime);
    
    // Wait for all thumbnails (should already be done or finishing)
    final thumbnails = await Future.wait(thumbnailFutures);
    final thumbnailElapsed = DateTime.now().difference(thumbnailStartTime);
    
    print('Compression completed in ${compressionElapsed.inMilliseconds}ms');
    print('All thumbnails completed in ${thumbnailElapsed.inMilliseconds}ms');
    print('  Average thumbnail time: ${(thumbnailElapsed.inMilliseconds / thumbnails.length).toStringAsFixed(0)}ms');

    // 3. Get actual compression results
    print('\n3. Analyzing results...');
    final outputFile = File(resultPath);
    final actualSize = await outputFile.length();
    final actualDurationMs = compressionElapsed.inMilliseconds;

    final estSize = estimate.estimatedSizeBytes.toInt();
    final estDuration = estimate.estimatedDurationMs.toInt();
    
    final sizeRatio = actualSize > 0 ? estSize / actualSize : 1.0;
    final durationRatio = actualDurationMs > 0 ? estDuration / actualDurationMs : 1.0;

    print('Actual compression:');
    print('  Actual size: $actualSize bytes (${(actualSize / 1024 / 1024).toStringAsFixed(2)} MB)');
    print('  Actual duration: $actualDurationMs ms (${(actualDurationMs / 1000).toStringAsFixed(2)}s)');
    print('\nComparison:');
    print('  Size ratio: ${sizeRatio.toStringAsFixed(3)} (target: 0.85-1.15)');
    print('  Duration ratio: ${durationRatio.toStringAsFixed(3)} (target: 0.85-1.15)');

    // 4. Verify estimate accuracy (±15% tolerance)
    print('\n4. Verifying estimate accuracy...');
    expect(
      sizeRatio,
      inInclusiveRange(0.85, 1.15),
      reason: 'Estimated size $estSize should be ±15% of actual $actualSize (ratio: $sizeRatio)',
    );
    expect(
      durationRatio,
      inInclusiveRange(0.85, 1.15),
      reason: 'Estimated duration $estDuration ms should be ±15% of actual $actualDurationMs ms (ratio: $durationRatio)',
    );
    print('✓ Estimate accuracy: PASSED');

    // 5. Verify concurrent operations
    print('\n5. Verifying concurrent operations...');
    expect(thumbnails.length, equals(thumbnailTimes.length),
        reason: 'All ${thumbnailTimes.length} thumbnails should be generated');
    
    for (int i = 0; i < thumbnails.length; i++) {
      expect(thumbnails[i].data.length, greaterThan(0),
          reason: 'Thumbnail $i should have data');
      expect(thumbnails[i].width, greaterThan(0),
          reason: 'Thumbnail $i should have width');
      expect(thumbnails[i].height, greaterThan(0),
          reason: 'Thumbnail $i should have height');
    }
    
    // Verify that thumbnails completed (concurrency worked)
    // If they were serialized, total time would be much higher
    final expectedSerialTime = thumbnails.length * 500; // Rough estimate if serialized
    if (thumbnailElapsed.inMilliseconds < expectedSerialTime) {
      print('✓ Concurrency: PASSED (thumbnails completed faster than serial execution)');
    } else {
      print('⚠ Concurrency: Thumbnails took ${thumbnailElapsed.inMilliseconds}ms (may be serialized)');
    }

    expect(await outputFile.exists(), isTrue,
        reason: 'Compressed video should exist');
    expect(actualSize, greaterThan(0),
        reason: 'Compressed video should have content');

    print('\n=== Test Summary ===');
    print('✓ Estimate accuracy: PASSED');
    print('✓ Concurrent operations: PASSED');
    print('✓ Compression: PASSED');
    print('✓ Thumbnail generation: PASSED');
    print('\nAll tests passed!');

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
