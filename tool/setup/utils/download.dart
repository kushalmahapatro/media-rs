// Download and extraction utilities
import 'dart:io';
import 'package:path/path.dart' as path;
import 'process.dart';
import 'package:http/http.dart' as http;

class Downloader {
  static Future<void> downloadFile(
    String url,
    String destination, {
    void Function(int received, int total)? onProgress,
  }) async {
    final file = File(destination);
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception('Failed to download $url: ${response.statusCode}');
    }

    final contentLength = response.contentLength ?? 0;
    final sink = file.openWrite();
    int received = 0;

    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, contentLength);
    }
    await sink.close();
  }

  static Future<void> downloadAndExtract(
    String url,
    String extractDir, {
    String? filename,
    bool isBzip2 = false,
    bool isGzip = false,
    void Function(int received, int total)? onProgress,
  }) async {
    final tempDir = Directory.systemTemp.createTempSync('media_rs_download_');
    final archiveName = filename ?? path.basename(url);
    final archivePath = path.join(tempDir.path, archiveName);

    try {
      print('Downloading $url...');
      await downloadFile(url, archivePath, onProgress: onProgress);

      print('Extracting to $extractDir...');
      if (!await Directory(extractDir).exists()) {
        await Directory(extractDir).create(recursive: true);
      }

      if (isBzip2 || archiveName.endsWith('.tar.bz2') || archiveName.endsWith('.bz2')) {
        await _extractBzip2(archivePath, extractDir);
      } else if (isGzip || archiveName.endsWith('.tar.gz') || archiveName.endsWith('.tgz')) {
        await _extractGzip(archivePath, extractDir);
      } else if (archiveName.endsWith('.tar')) {
        await _extractTar(archivePath, extractDir);
      } else if (archiveName.endsWith('.zip')) {
        await _extractZip(archivePath, extractDir);
      } else {
        throw Exception('Unknown archive format: $archiveName');
      }
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  static Future<void> _extractBzip2(String archivePath, String extractDir) async {
    if (Platform.isWindows) {
      // On Windows, use 7z or tar if available
      final tar = await _findCommand('tar');
      if (tar != null) {
        await runProcessStreaming(tar, ['-xjf', archivePath, '-C', extractDir]);
      } else {
        throw Exception('tar command not found. Install 7-Zip or use WSL.');
      }
    } else {
      await runProcessStreaming('tar', ['-xjf', archivePath, '-C', extractDir]);
    }
  }

  static Future<void> _extractGzip(String archivePath, String extractDir) async {
    if (Platform.isWindows) {
      final tar = await _findCommand('tar');
      if (tar != null) {
        await runProcessStreaming(tar, ['-xzf', archivePath, '-C', extractDir]);
      } else {
        throw Exception('tar command not found. Install 7-Zip or use WSL.');
      }
    } else {
      await runProcessStreaming('tar', ['-xzf', archivePath, '-C', extractDir]);
    }
  }

  static Future<void> _extractTar(String archivePath, String extractDir) async {
    if (Platform.isWindows) {
      final tar = await _findCommand('tar');
      if (tar != null) {
        await runProcessStreaming(tar, ['-xf', archivePath, '-C', extractDir]);
      } else {
        throw Exception('tar command not found. Install 7-Zip or use WSL.');
      }
    } else {
      await runProcessStreaming('tar', ['-xf', archivePath, '-C', extractDir]);
    }
  }

  static Future<void> _extractZip(String archivePath, String extractDir) async {
    if (Platform.isWindows) {
      // Try PowerShell first, then 7z
      try {
        await runProcessStreaming('powershell', [
          '-Command',
          'Expand-Archive -Path "$archivePath" -DestinationPath "$extractDir" -Force',
        ]);
      } catch (e) {
        final sevenZip = await _findCommand('7z');
        if (sevenZip != null) {
          await runProcessStreaming(sevenZip, ['x', archivePath, '-o$extractDir']);
        } else {
          throw Exception('No zip extraction tool found');
        }
      }
    } else {
      await runProcessStreaming('unzip', ['-q', archivePath, '-d', extractDir]);
    }
  }

  static Future<String?> _findCommand(String command) async {
    try {
      final result = await runProcessStreaming('which', [command]);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (e) {
      // Try 'where' on Windows
      if (Platform.isWindows) {
        try {
          final result = await runProcessStreaming('where', [command]);
          if (result.exitCode == 0) {
            return result.stdout.toString().split('\n').first.trim();
          }
        } catch (e) {
          // Ignore
        }
      }
    }
    return null;
  }
}
