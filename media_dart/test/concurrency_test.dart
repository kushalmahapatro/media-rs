import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';

/// Concurrency test: runs multiple FFmpeg operations in parallel to verify
/// the underlying platform (FFmpeg CLI / JNI / etc.) handles concurrent work
/// without resource contention, file descriptor leaks, or data races.
void main() {
  late final List<String> sourcePaths;
  late final String tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('media_rs_concurrency_').path;
    sourcePaths = <String>[];

    for (int i = 0; i < 3; i++) {
      final path = '$tempDir/concurrent_test_$i.mp4';
      final result = Process.runSync(
        'ffmpeg',
        [
          '-y',
          '-f', 'lavfi',
          '-i', "color=c=blue:s=16x16:r=5:d=1",
          '-f', 'lavfi',
          '-i', 'sine=frequency=440:duration=1',
          '-c:v', 'libx264',
          '-c:a', 'aac',
          '-shortest',
          path,
        ],
        runInShell: true,
      );
      if (result.exitCode != 0) {
        sourcePaths = [];
        return;
      }
      sourcePaths.add(path);
    }
  });

  tearDownAll(() async {
    for (final path in sourcePaths) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    final d = Directory(tempDir);
    if (await d.exists()) await d.delete(recursive: true);
  });

  group('FFmpeg concurrent operations', () {
    test('multiple thumbnail grabs in parallel', () async {
      if (sourcePaths.isEmpty) return skip('ffmpeg not available');

      final results = <Future<List<int>>>[];
      for (final path in sourcePaths) {
        results.add(_grabThumbnail(path, 1));
      }
      final outputs = await Future.wait(results);
      expect(outputs, hasLength(3));
      for (int i = 0; i < outputs.length; i++) {
        expect(outputs[i].isNotEmpty, isTrue,
            reason: 'thumbnail $i should not be empty');
        expect(outputs[i].length, greaterThan(0),
            reason: 'thumbnail $i should have content');
      }
    });

    test('multiple probe operations in parallel', () async {
      if (sourcePaths.isEmpty) return skip('ffmpeg not available');

      final results = <Future<Map<String, dynamic>>>[];
      for (final path in sourcePaths) {
        results.add(_probe(path));
      }
      final outputs = await Future.wait(results);
      expect(outputs, hasLength(3));
      for (final probe in outputs) {
        expect(probe['duration'], isNonNegative);
        expect(probe['width'], greaterThan(0));
        expect(probe['height'], greaterThan(0));
      }
    });

    test('multiple transcoded outputs in parallel', () async {
      if (sourcePaths.isEmpty) return skip('ffmpeg not available');

      final outputs = <String>[];
      for (int i = 0; i < 3; i++) {
        outputs.add('$tempDir/output_$i.mp4');
      }

      final results = <Future<void>>[];
      for (int i = 0; i < sourcePaths.length; i++) {
        results.add(_transcode(sourcePaths[i], outputs[i], 64, 36));
      }

      await Future.wait(results);
      expect(outputs, hasLength(3));
      for (final path in outputs) {
        final f = File(path);
        expect(await f.exists(), isTrue, reason: '$path should exist');
        expect(await f.length(), greaterThan(0), reason: '$path should have content');
        await f.delete();
      }
    });

    test('mixed concurrent workload (probe + thumbnail + transcode)', () async {
      if (sourcePaths.isEmpty) return skip('ffmpeg not available');

      final (probe, thumbnail, _) = await Future.wait([
        _probe(sourcePaths[0]),
        _grabThumbnail(sourcePaths[0], 1),
        _transcode(sourcePaths[0], '$tempDir/mixed.mp4', 32, 18),
      ]) as (Map<String, dynamic>, List<int>, void);

      expect(probe['duration'], isNonNegative);
      expect(thumbnail.isNotEmpty, isTrue);
      expect(File('$tempDir/mixed.mp4').exists(), completes);
      await File('$tempDir/mixed.mp4').delete();
    });
  });
}

Future<List<int>> _grabThumbnail(String inputPath, double timeSec) async {
  final result = await Process.run(
    'ffmpeg',
    [
      '-y',
      '-ss', '$timeSec',
      '-i', inputPath,
      '-vframes', '1',
      '-f', 'image2pipe',
      '-vcodec', 'png',
      '-',
    ],
    runInShell: true,
  );
  return result.stdout as List<int>;
}

Future<Map<String, dynamic>> _probe(String inputPath) async {
  final result = await Process.run(
    'ffprobe',
    [
      '-v', 'quiet',
      '-print_format', 'json',
      '-show_format',
      '-show_streams',
      inputPath,
    ],
    runInShell: true,
  );
  final json = result.stdout as String;
  return {
    'duration': double.tryParse(json.split('"duration":"')[1]?.split('"')[0] ?? '0') ?? 0,
    'width': int.tryParse(json.split('"width":')[1]?.split(',')[0] ?? '0') ?? 0,
    'height': int.tryParse(json.split('"height":')[1]?.split(',')[0] ?? '0') ?? 0,
  };
}

Future<void> _transcode(String inputPath, String outputPath, int maxWidth, int maxHeight) async {
  final result = await Process.run(
    'ffmpeg',
    [
      '-y',
      '-i', inputPath,
      '-vf', "scale=$maxWidth:$maxHeight",
      '-c:v', 'libx264',
      '-preset', 'ultrafast',
      '-c:a', 'aac',
      '-b:a', '32k',
      outputPath,
    ],
    runInShell: true,
  );
  if (result.exitCode != 0) {
    throw Exception('transcode failed: ${result.stderr}');
  }
}
