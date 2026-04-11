import 'dart:io';

import 'package:logging/logging.dart';
import 'package:media_native_build/media_rust_target.dart';
import 'package:path/path.dart' as path;

/// Copies FFmpeg binaries directly to macOS app bundle (bypassing CodeAssets).
/// 
/// This is used for macOS to avoid Flutter's framework wrapping which fails
/// on executables (MH_EXECUTE). Instead, we copy directly to the app bundle
/// during the build process.
/// 
/// Call this from a post-build script or build phase in Xcode.
Future<void> copyMacosFfmpegToAppBundle({
  required String appBundlePath,
  required String rustTriple,
  required Logger logger,
}) async {
  // Find FFmpeg in native/ffmpeg/<triple>/
  final packageRoot = Directory.current.path; // Assumes running from media_dart
  final ffmpegDir = path.join(
    packageRoot,
    'native',
    'ffmpeg',
    mediaFfmpegBundleDirName(rustTriple),
  );
  
  final srcFfmpeg = path.join(ffmpegDir, 'ffmpeg');
  final srcFfprobe = path.join(ffmpegDir, 'ffprobe');
  
  if (!File(srcFfmpeg).existsSync() || !File(srcFfprobe).existsSync()) {
    throw StateError(
      'FFmpeg binaries not found at $ffmpegDir. '
      'Run hook/build.dart first to download them.',
    );
  }
  
  // Target: MyApp.app/Contents/Frameworks/ (same as libmedia.dylib)
  final destDir = path.join(appBundlePath, 'Contents', 'Frameworks');
  Directory(destDir).createSync(recursive: true);
  
  final destFfmpeg = path.join(destDir, 'ffmpeg');
  final destFfprobe = path.join(destDir, 'ffprobe');
  
  File(srcFfmpeg).copySync(destFfmpeg);
  File(srcFfprobe).copySync(destFfprobe);
  
  // Make executable
  await Process.run('chmod', ['+x', destFfmpeg, destFfprobe]);
  
  logger.config('Copied ffmpeg/ffprobe to $destDir');
}

/// Returns the FFmpeg bundle directory name under `native/ffmpeg/` for a rust triple.
String mediaFfmpegBundleDirName(String rustTriple) {
  final d = mediaFfmpegBundleDirForRustTriple(rustTriple);
  if (d == null) {
    throw UnsupportedError('No FFmpeg bundle for $rustTriple');
  }
  return d;
}
