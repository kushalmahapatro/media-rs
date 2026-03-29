import 'dart:io';

import 'package:media_native_build/media_rust_target.dart';
import 'package:path/path.dart' as path;

/// Output format for GitHub-style release assets (`{triple}.zip`, etc.).
enum MediaPrebuiltArchiveFormat {
  zip,
  tarGz,
}

extension MediaPrebuiltArchiveFormatX on MediaPrebuiltArchiveFormat {
  String get fileExtension => switch (this) {
        MediaPrebuiltArchiveFormat.zip => 'zip',
        MediaPrebuiltArchiveFormat.tarGz => 'tar.gz',
      };
}

/// Lists Rust triples that have a non-empty directory under [workspaceRoot]/platform-builds/.
List<String> mediaDiscoverPlatformBuildTriples(String workspaceRoot) {
  final buildsRoot = Directory(path.join(workspaceRoot, 'platform-builds'));
  if (!buildsRoot.existsSync()) return const [];
  final names = <String>{};
  for (final entity in buildsRoot.listSync(followLinks: false)) {
    if (entity is! Directory) continue;
    for (final tripleEntity in entity.listSync(followLinks: false)) {
      if (tripleEntity is! Directory) continue;
      if (_directoryHasFiles(tripleEntity)) {
        names.add(path.basename(tripleEntity.path));
      }
    }
  }
  final out = names.toList()..sort();
  return out;
}

bool _directoryHasFiles(Directory dir) {
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is File) return true;
  }
  return false;
}

/// Creates `{triple}.zip` or `{triple}.tar.gz` suitable for GitHub releases.
///
/// The archive contains a single top-level directory named [rustTriple] (e.g.
/// `aarch64-apple-darwin/libmedia.dylib`, …) so extracting into
/// `platform-builds/<os>/` restores the layout expected by the hook.
Future<void> mediaArchivePlatformBuildFolder({
  required String workspaceRoot,
  required String rustTriple,
  required MediaPrebuiltArchiveFormat format,
  required String outputDirectory,
  required bool release,
  String? versionSubdirectory,
}) async {
  final osDir = mediaPlatformBuildsOsDirName(rustTriple);
  final platformOsRoot = path.join(workspaceRoot, 'platform-builds', osDir);
  final srcDir = path.join(platformOsRoot, rustTriple);
  if (!Directory(srcDir).existsSync()) {
    throw StateError('Missing platform-build folder: $srcDir');
  }

  var outRoot = path.normalize(outputDirectory);
  if (versionSubdirectory != null && versionSubdirectory.isNotEmpty) {
    outRoot = path.join(outRoot, versionSubdirectory);
  }
  Directory(outRoot).createSync(recursive: true);

  final baseName = release ? rustTriple : '$rustTriple-debug';
  final outFile = path.join(
    outRoot,
    '$baseName.${format.fileExtension}',
  );

  switch (format) {
    case MediaPrebuiltArchiveFormat.zip:
      await _writeZipArchive(
        sourceDir: platformOsRoot,
        baseName: rustTriple,
        outFile: outFile,
      );
    case MediaPrebuiltArchiveFormat.tarGz:
      await _runProcess(
        'tar',
        ['-czf', outFile, '-C', platformOsRoot, rustTriple],
      );
  }
}

/// Writes a zip of [sourceDir]/[baseName]/ using the system `zip` or `tar -a`.
Future<void> _writeZipArchive({
  required String sourceDir,
  required String baseName,
  required String outFile,
}) async {
  if (Platform.isWindows) {
    await _runProcess(
      'tar',
      ['-a', '-c', '-f', outFile, '-C', sourceDir, baseName],
    );
    return;
  }
  final zip = _findZipExecutable();
  await _runProcess(zip, ['-qr', outFile, baseName], workingDirectory: sourceDir);
}

String _findZipExecutable() {
  for (final candidate in ['/usr/bin/zip', '/bin/zip', 'zip']) {
    if (candidate == 'zip') return candidate;
    if (File(candidate).existsSync()) return candidate;
  }
  return 'zip';
}

Future<void> _runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final r = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: false,
  );
  if (r.exitCode != 0) {
    final err = (r.stderr as String).trim();
    final out = (r.stdout as String).trim();
    throw StateError(
      '$executable ${arguments.join(' ')} failed (${r.exitCode})'
      '${err.isNotEmpty ? ': $err' : ''}'
      '${out.isNotEmpty ? '\n$out' : ''}',
    );
  }
}
