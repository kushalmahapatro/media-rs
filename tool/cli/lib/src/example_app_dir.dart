import 'dart:io';

import 'package:path/path.dart' as path;

/// Resolves [media_flutter/example] (directory containing [distribute_options.yaml]).
String resolveMediaExampleAppDir() {
  const yaml = 'distribute_options.yaml';
  bool hasDistYaml(String exampleDir) =>
      File(path.join(exampleDir, yaml)).existsSync();

  String? walkToExample(String start) {
    var dir = path.normalize(path.absolute(start));
    for (var i = 0; i < 40; i++) {
      final candidate = path.join(dir, 'media_flutter', 'example');
      if (hasDistYaml(candidate)) {
        return path.normalize(candidate);
      }
      final parent = path.dirname(dir);
      if (parent == dir) break;
      dir = parent;
    }
    return null;
  }

  final fromCwd = walkToExample(Directory.current.path);
  if (fromCwd != null) return fromCwd;

  final scriptDir = path.dirname(Platform.script.toFilePath());
  final fromScript = walkToExample(scriptDir);
  if (fromScript != null) return fromScript;

  final mediaCliRoot = path.normalize(path.join(scriptDir, '..'));
  return path.normalize(
    path.join(mediaCliRoot, '..', '..', 'media_flutter', 'example'),
  );
}
