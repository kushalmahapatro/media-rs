import 'dart:io';

import 'package:logging/logging.dart';
import 'package:media_native_build/media_rust_target.dart';
import 'package:path/path.dart' as path;

/// Creates `platform-builds/macos/universal-apple-darwin/libmedia.dylib` via `lipo`
/// from the Apple Silicon and Intel thin libraries.
///
/// Call on a macOS host after [aarch64-apple-darwin] and [x86_64-apple-darwin]
/// exist under `platform-builds/macos/`.
Future<void> mediaLipoMacOsUniversalLib({
  required String workspaceRoot,
  required Logger logger,
}) async {
  if (!Platform.isMacOS) {
    throw UnsupportedError(
      'mediaLipoMacOsUniversalLib requires macOS (lipo is an Apple tool).',
    );
  }
  final macRoot = path.join(workspaceRoot, 'platform-builds', 'macos');
  final armLib = path.join(macRoot, 'aarch64-apple-darwin', 'libmedia.dylib');
  final intelLib = path.join(macRoot, 'x86_64-apple-darwin', 'libmedia.dylib');
  final outDir = path.join(macRoot, mediaUniversalAppleDarwinTriple);
  final outLib = path.join(outDir, 'libmedia.dylib');

  if (!File(armLib).existsSync()) {
    throw StateError('Missing Apple Silicon library: $armLib');
  }
  if (!File(intelLib).existsSync()) {
    throw StateError('Missing Intel library: $intelLib');
  }

  Directory(outDir).createSync(recursive: true);
  final r = await Process.run('lipo', [
    '-create',
    armLib,
    intelLib,
    '-output',
    outLib,
  ]);
  if (r.exitCode != 0) {
    throw StateError(
      'lipo failed (${r.exitCode}): ${r.stderr}${r.stdout}',
    );
  }
  logger.config('Wrote fat $outLib');
}

/// Creates `native/ffmpeg/darwin-universal/{ffmpeg,ffprobe}` with `lipo` from
/// [darwin-arm64] and [darwin-x64] trees under [packageRoot]/native/ffmpeg/.
Future<void> mediaLipoMacOsUniversalFfmpeg({
  required String packageRoot,
  required Logger logger,
}) async {
  if (!Platform.isMacOS) {
    throw UnsupportedError(
      'mediaLipoMacOsUniversalFfmpeg requires macOS (lipo is an Apple tool).',
    );
  }
  final root = path.join(packageRoot, 'native', 'ffmpeg');
  final armFf = path.join(root, 'darwin-arm64', 'ffmpeg');
  final armFp = path.join(root, 'darwin-arm64', 'ffprobe');
  final intelFf = path.join(root, 'darwin-x64', 'ffmpeg');
  final intelFp = path.join(root, 'darwin-x64', 'ffprobe');

  for (final f in [armFf, armFp, intelFf, intelFp]) {
    if (!File(f).existsSync()) {
      throw StateError(
        'Missing thin FFmpeg binary $f — run collect-native for both macOS triples '
        'or place slim builds under darwin-arm64/ and darwin-x64/ first.',
      );
    }
  }

  final outDir = path.join(root, 'darwin-universal');
  Directory(outDir).createSync(recursive: true);
  final outFf = path.join(outDir, 'ffmpeg');
  final outFp = path.join(outDir, 'ffprobe');

  for (final spec in [
    (armFf, intelFf, outFf),
    (armFp, intelFp, outFp),
  ]) {
    final r = await Process.run('lipo', [
      '-create',
      spec.$1,
      spec.$2,
      '-output',
      spec.$3,
    ]);
    if (r.exitCode != 0) {
      throw StateError(
        'lipo ${path.basename(spec.$3)} failed (${r.exitCode}): ${r.stderr}',
      );
    }
  }
  await Process.run('chmod', ['+x', outFf, outFp]);
  logger.config('Wrote fat ffmpeg/ffprobe in $outDir');
}
