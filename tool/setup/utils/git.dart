// Git utilities
import 'dart:io';
import 'package:path/path.dart' as path;
import 'process.dart';

class Git {
  static Future<void> clone(String repository, String destination, {String? branch, int? depth}) async {
    final dir = Directory(destination);
    if (await dir.exists()) {
      // Check if it's already a git repo
      final gitDir = Directory(path.join(destination, '.git'));
      if (await gitDir.exists()) {
        print('Repository already exists at $destination');
        return;
      } else {
        // Directory exists but isn't a git repo, remove it
        await dir.delete(recursive: true);
      }
    }

    final args = <String>['clone'];
    if (depth != null) {
      args.addAll(['--depth', depth.toString()]);
    }
    if (branch != null) {
      args.addAll(['--branch', branch]);
    }
    args.addAll([repository, destination]);

    print('Cloning $repository${branch != null ? ' (branch: $branch)' : ''}...');
    final result = await runProcessStreaming('git', args);
    if (result.exitCode != 0) {
      throw Exception('Git clone failed: ${result.stderr}');
    }
  }

  static Future<void> checkout(String repositoryPath, String branch) async {
    final result = await runProcessStreaming('git', ['checkout', branch], workingDirectory: repositoryPath);
    if (result.exitCode != 0) {
      throw Exception('Git checkout failed: ${result.stderr}');
    }
  }
}
