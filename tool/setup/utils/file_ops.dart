// File operations utilities
import 'dart:io';
import 'package:path/path.dart' as path;

class FileOps {
  static Future<void> copyRecursive(String source, String destination) async {
    final sourceDir = Directory(source);
    if (!await sourceDir.exists()) {
      throw Exception('Source directory does not exist: $source');
    }

    final destDir = Directory(destination);
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    await for (final entity in sourceDir.list(recursive: true)) {
      final relativePath = path.relative(entity.path, from: source);
      final destPath = path.join(destination, relativePath);

      if (entity is File) {
        final destFile = File(destPath);
        await destFile.parent.create(recursive: true);
        await entity.copy(destPath);
      } else if (entity is Directory) {
        await Directory(destPath).create(recursive: true);
      }
    }
  }

  static Future<void> ensureDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  static Future<bool> exists(String path) async {
    try {
      final file = File(path);
      final dir = Directory(path);
      return await file.exists() || await dir.exists();
    } catch (e) {
      return false;
    }
  }

  static Future<void> removeIfExists(String path) async {
    final file = File(path);
    final dir = Directory(path);
    
    if (await file.exists()) {
      await file.delete();
    } else if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  static Future<void> writeTextFile(String path, String content) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  static Future<String> readTextFile(String path) async {
    final file = File(path);
    return await file.readAsString();
  }

  static Future<void> replaceInFile(
    String filePath,
    String oldString,
    String newString,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist: $filePath');
    }

    String content = await file.readAsString();
    content = content.replaceAll(oldString, newString);
    await file.writeAsString(content);
  }

  static Future<void> replaceInFileRegex(
    String filePath,
    Pattern pattern,
    String replacement,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist: $filePath');
    }

    String content = await file.readAsString();
    content = content.replaceAll(pattern, replacement);
    await file.writeAsString(content);
  }
}

