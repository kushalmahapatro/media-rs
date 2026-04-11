import 'dart:io';

import 'package:archive/archive.dart';
import 'package:media_native_build/media_platform_paths.dart';
import 'package:media_native_build/media_rust_target.dart';
import 'package:path/path.dart' as path;

/// Writes `{rustTriple}-ffmpeg.zip` in [outputDirectory] for GitHub releases.
///
/// Layout matches [media_dart] hook extraction: entries `rustTriple/ffmpeg` (or
/// `.exe` on Windows) and matching ffprobe.
Future<void> mediaWriteFfmpegReleaseZip({
  required String packageRoot,
  required String workspaceRoot,
  required String rustTriple,
  required String outputDirectory,
  String? versionSubdirectory,
}) async {
  final isWin = rustTriple.contains('windows');
  final ffmpegName = isWin ? 'ffmpeg.exe' : 'ffmpeg';
  final ffprobeName = isWin ? 'ffprobe.exe' : 'ffprobe';

  final String srcDir;
  if (mediaRustTripleIsMacOsDesktop(rustTriple) ||
      rustTriple == mediaUniversalAppleDarwinTriple) {
    final sub = mediaFfmpegBundleDirForRustTriple(rustTriple);
    if (sub == null) {
      throw StateError('No FFmpeg bundle mapping for $rustTriple');
    }
    srcDir = path.join(packageRoot, 'native', 'ffmpeg', sub);
  } else {
    srcDir = mediaPlatformBuildSourceDir(
      packageRoot: packageRoot,
      rustTriple: rustTriple,
    );
  }

  final srcFf = path.join(srcDir, ffmpegName);
  final srcFp = path.join(srcDir, ffprobeName);
  if (!File(srcFf).existsSync() || !File(srcFp).existsSync()) {
    throw StateError(
      'FFmpeg release zip: missing $srcFf or $srcFp (for $rustTriple)',
    );
  }

  var outRoot = path.normalize(outputDirectory);
  if (versionSubdirectory != null && versionSubdirectory.isNotEmpty) {
    outRoot = path.join(outRoot, versionSubdirectory);
  }
  Directory(outRoot).createSync(recursive: true);
  final outFile = path.join(outRoot, '$rustTriple-ffmpeg.zip');

  final ffBytes = File(srcFf).readAsBytesSync();
  final fpBytes = File(srcFp).readAsBytesSync();

  final archive = Archive()
    ..addFile(
      ArchiveFile('$rustTriple/$ffmpegName', ffBytes.length, ffBytes),
    )
    ..addFile(
      ArchiveFile('$rustTriple/$ffprobeName', fpBytes.length, fpBytes),
    );

  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw StateError('ZipEncoder returned null for $rustTriple');
  }
  File(outFile).writeAsBytesSync(encoded);
}

/// Triples that have `ffmpeg` + `ffprobe` available for `{triple}-ffmpeg.zip`.
List<String> mediaDiscoverFfmpegReleaseTriples({
  required String packageRoot,
  required String workspaceRoot,
}) {
  final out = <String>[];
  final macNative = path.join(packageRoot, 'native', 'ffmpeg');

  void addMac(String triple, String subdir) {
    final d = path.join(macNative, subdir);
    final ff = path.join(d, 'ffmpeg');
    final fp = path.join(d, 'ffprobe');
    if (File(ff).existsSync() && File(fp).existsSync()) {
      out.add(triple);
    }
  }

  addMac('aarch64-apple-darwin', 'darwin-arm64');
  addMac('x86_64-apple-darwin', 'darwin-x64');
  addMac(mediaUniversalAppleDarwinTriple, 'darwin-universal');

  for (final os in ['linux', 'windows']) {
    final root = path.join(workspaceRoot, 'platform-builds', os);
    if (!Directory(root).existsSync()) continue;
    for (final e in Directory(root).listSync(followLinks: false)) {
      if (e is! Directory) continue;
      final triple = path.basename(e.path);
      final isWin = os == 'windows';
      final ff = path.join(e.path, isWin ? 'ffmpeg.exe' : 'ffmpeg');
      final fp = path.join(e.path, isWin ? 'ffprobe.exe' : 'ffprobe');
      if (File(ff).existsSync() && File(fp).existsSync()) {
        out.add(triple);
      }
    }
  }

  out.sort();
  return out;
}
