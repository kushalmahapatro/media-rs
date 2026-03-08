// Integration test: Test concurrent FFmpeg operations
// Run: flutter test integration_test/concurrency_test.dart
// Requires: TEST_VIDEO_PATH env var or a test video at ./test_video.mp4
// Prerequisites: Run setup (dart run tool/setup.dart --windows/linux) to build native libs

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media/media.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Concurrent operations: thumbnails during compression',
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
    final outputPath = '$tempDir/concurrent_test_output.mp4';

    final params = CompressParams(
      targetBitrateKbps: 1000,
      preset: 'veryfast',
      crf: 23,
      width: 640,
      height: 360,
      sampleDurationMs: BigInt.from(1500),
    );

    // Start compression
    final compressionFuture = compressVideo(
      path: testVideoPath,
      outputPath: outputPath,
      params: params,
    );

    // While compression is running, generate multiple thumbnails concurrently
    final thumbnailParams = VideoThumbnailParams(
      timeMs: BigInt.from(1000),
      width: 320,
      height: 180,
      format: OutputFormat.jpeg,
    );

    final thumbnailFutures = <Future<VideoThumbnail>>[];
    final thumbnailTimes = [500, 1000, 1500, 2000, 2500];
    
    print('Starting ${thumbnailTimes.length} concurrent thumbnail generations during compression...');
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

    // Wait for all thumbnails to complete
    final thumbnails = await Future.wait(thumbnailFutures);
    final thumbnailElapsed = DateTime.now().difference(thumbnailStartTime);
    
    print('All ${thumbnails.length} thumbnails completed in ${thumbnailElapsed.inMilliseconds}ms');
    print('Average time per thumbnail: ${thumbnailElapsed.inMilliseconds / thumbnails.length}ms');

    // Wait for compression to complete
    final resultPath = await compressionFuture;
    print('Compression completed: $resultPath');

    // Verify thumbnails were generated
    expect(thumbnails.length, equals(thumbnailTimes.length),
        reason: 'All thumbnails should be generated');
    
    for (int i = 0; i < thumbnails.length; i++) {
      expect(thumbnails[i].data.length, greaterThan(0),
          reason: 'Thumbnail $i should have data');
      expect(thumbnails[i].width, greaterThan(0),
          reason: 'Thumbnail $i should have width');
      expect(thumbnails[i].height, greaterThan(0),
          reason: 'Thumbnail $i should have height');
      print('Thumbnail $i: ${thumbnails[i].width}x${thumbnails[i].height}, ${thumbnails[i].data.length} bytes');
    }

    // Verify compression output exists
    final outputFile = File(resultPath);
    expect(await outputFile.exists(), isTrue,
        reason: 'Compressed video should exist');
    
    final outputSize = await outputFile.length();
    expect(outputSize, greaterThan(0),
        reason: 'Compressed video should have content');

    print('✓ Concurrent operations test passed!');
    print('  - Compression: ${outputSize} bytes');
    print('  - Thumbnails: ${thumbnails.length} generated concurrently');
    print('  - Total thumbnail time: ${thumbnailElapsed.inMilliseconds}ms');

    // Cleanup
    await outputFile.delete().catchError((_) {});
  });

  testWidgets('Concurrent operations: estimate during thumbnail generation',
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

    final params = CompressParams(
      targetBitrateKbps: 1000,
      preset: 'veryfast',
      crf: 23,
      width: 640,
      height: 360,
      sampleDurationMs: BigInt.from(1500),
    );

    // Start estimate
    final estimateFuture = estimateCompression(
      path: testVideoPath,
      tempOutputPath: tempDir,
      params: params,
    );

    // While estimate is running, generate thumbnails concurrently
    final thumbnailFutures = <Future<VideoThumbnail>>[];
    final thumbnailTimes = [1000, 2000, 3000];
    
    print('Starting ${thumbnailTimes.length} concurrent thumbnail generations during estimation...');
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

    // Wait for all thumbnails to complete
    final thumbnails = await Future.wait(thumbnailFutures);
    final thumbnailElapsed = DateTime.now().difference(thumbnailStartTime);
    
    // Wait for estimate to complete
    final estimate = await estimateFuture;
    
    print('Estimate completed: ${estimate.estimatedSizeBytes} bytes, ${estimate.estimatedDurationMs}ms');
    print('All ${thumbnails.length} thumbnails completed in ${thumbnailElapsed.inMilliseconds}ms');

    // Verify estimate
    expect(estimate.estimatedSizeBytes.toInt(), greaterThan(0),
        reason: 'Estimate should have size');
    expect(estimate.estimatedDurationMs.toInt(), greaterThan(0),
        reason: 'Estimate should have duration');

    // Verify thumbnails
    expect(thumbnails.length, equals(thumbnailTimes.length),
        reason: 'All thumbnails should be generated');
    
    for (int i = 0; i < thumbnails.length; i++) {
      expect(thumbnails[i].data.length, greaterThan(0),
          reason: 'Thumbnail $i should have data');
    }

    print('✓ Concurrent estimate and thumbnails test passed!');
    print('  - Estimate: ${estimate.estimatedSizeBytes} bytes, ${estimate.estimatedDurationMs}ms');
    print('  - Thumbnails: ${thumbnails.length} generated concurrently');

    // Cleanup
    // (no files to clean up for this test)
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
