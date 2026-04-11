import 'dart:developer' as developer;
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';
import 'package:media_native_build/media_rust_target.dart';
import 'package:path/path.dart' as path;

/// eugeneware/ffmpeg-static release tag (keep in sync if you change download URLs).
const mediaFfmpegStaticTag = 'b6.1.1';

const _defaultStaticBase =
    'https://github.com/eugeneware/ffmpeg-static/releases/download/$mediaFfmpegStaticTag';

/// Base URL for static FFmpeg/ffprobe downloads (asset names unchanged).
///
/// Override with **`MEDIA_FFMPEG_STATIC_BASE_URL`** to point at your own mirror or
/// a release that contains **slim** builds (same file names as upstream, or replace
/// files under `native/ffmpeg/` after download).
String get mediaFfmpegStaticBaseUrl =>
    Platform.environment['MEDIA_FFMPEG_STATIC_BASE_URL']?.trim().isNotEmpty == true
        ? Platform.environment['MEDIA_FFMPEG_STATIC_BASE_URL']!.trim()
        : _defaultStaticBase;

const _btbnWinArm64Zip =
    'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-winarm64-gpl.zip';

Future<void> mediaEnsureFfmpegDownloadedForCodeConfig({
  required CodeConfig code,
  required String packageRoot,
  required Logger logger,
}) async {
  final folder = mediaFfmpegBundleDir(code);
  switch ((code.targetOS, code.targetArchitecture)) {
    case (OS.linux, Architecture.x64):
      await _downloadUnixPair(
        subdir: folder,
        ffAsset: 'ffmpeg-linux-x64',
        fpAsset: 'ffprobe-linux-x64',
        packageRoot: packageRoot,
        logger: logger,
      );
    case (OS.linux, Architecture.arm64):
      await _downloadUnixPair(
        subdir: folder,
        ffAsset: 'ffmpeg-linux-arm64',
        fpAsset: 'ffprobe-linux-arm64',
        packageRoot: packageRoot,
        logger: logger,
      );
    case (OS.macOS, Architecture.x64):
      await _downloadUnixPair(
        subdir: folder,
        ffAsset: 'ffmpeg-darwin-x64',
        fpAsset: 'ffprobe-darwin-x64',
        packageRoot: packageRoot,
        logger: logger,
      );
    case (OS.macOS, Architecture.arm64):
      await _downloadUnixPair(
        subdir: folder,
        ffAsset: 'ffmpeg-darwin-arm64',
        fpAsset: 'ffprobe-darwin-arm64',
        packageRoot: packageRoot,
        logger: logger,
      );
    case (OS.windows, Architecture.x64):
      await _downloadWindowsX64(packageRoot: packageRoot, logger: logger);
    case (OS.windows, Architecture.arm64):
      await _downloadWindowsArm64(packageRoot: packageRoot, logger: logger);
    default:
      throw UnsupportedError(
        'FFmpeg download: unexpected ${code.targetOS} ${code.targetArchitecture}',
      );
  }
}

/// Ensures FFmpeg binaries exist under `native/ffmpeg/<subdir>/` for [rustTriple].
Future<void> mediaEnsureFfmpegDownloadedForRustTriple({
  required String rustTriple,
  required String packageRoot,
  required Logger logger,
}) async {
  final subdir = mediaFfmpegBundleDirForRustTriple(rustTriple);
  if (subdir == null) {
    throw UnsupportedError('No FFmpeg bundle for rust triple $rustTriple');
  }
  switch (rustTriple) {
    case 'aarch64-unknown-linux-gnu':
      await _downloadUnixPair(
        subdir: subdir,
        ffAsset: 'ffmpeg-linux-arm64',
        fpAsset: 'ffprobe-linux-arm64',
        packageRoot: packageRoot,
        logger: logger,
      );
    case 'x86_64-unknown-linux-gnu':
      await _downloadUnixPair(
        subdir: subdir,
        ffAsset: 'ffmpeg-linux-x64',
        fpAsset: 'ffprobe-linux-x64',
        packageRoot: packageRoot,
        logger: logger,
      );
    case 'aarch64-apple-darwin':
      await _downloadUnixPair(
        subdir: subdir,
        ffAsset: 'ffmpeg-darwin-arm64',
        fpAsset: 'ffprobe-darwin-arm64',
        packageRoot: packageRoot,
        logger: logger,
      );
    case 'x86_64-apple-darwin':
      await _downloadUnixPair(
        subdir: subdir,
        ffAsset: 'ffmpeg-darwin-x64',
        fpAsset: 'ffprobe-darwin-x64',
        packageRoot: packageRoot,
        logger: logger,
      );
    case 'x86_64-pc-windows-msvc':
      await _downloadWindowsX64(packageRoot: packageRoot, logger: logger);
    case 'aarch64-pc-windows-msvc':
      await _downloadWindowsArm64(packageRoot: packageRoot, logger: logger);
    default:
      throw UnsupportedError('Unhandled rust triple for FFmpeg: $rustTriple');
  }
}

/// Copies ffmpeg/ffprobe into `rust/media/bundled/current` for macOS embed (before cargo).
Future<void> mediaSyncMacosFfmpegIntoRustCrate({
  required String packageRoot,
  required Logger logger,
  required String rustTriple,
}) async {
  if (!mediaRustTripleIsMacOsDesktop(rustTriple)) return;

  await mediaEnsureFfmpegDownloadedForRustTriple(
    rustTriple: rustTriple,
    packageRoot: packageRoot,
    logger: logger,
  );
  final folder = mediaFfmpegBundleDirForRustTriple(rustTriple)!;
  final srcFfmpeg = path.join(packageRoot, 'native', 'ffmpeg', folder, 'ffmpeg');
  final srcFfprobe = path.join(
    packageRoot,
    'native',
    'ffmpeg',
    folder,
    'ffprobe',
  );
  if (!File(srcFfmpeg).existsSync() || !File(srcFfprobe).existsSync()) {
    throw StateError('Bundled FFmpeg missing under native/ffmpeg/$folder');
  }
  final bundledDir = path.join(packageRoot, 'rust', 'media', 'bundled', 'current');
  Directory(bundledDir).createSync(recursive: true);
  File(srcFfmpeg).copySync(path.join(bundledDir, 'ffmpeg'));
  File(srcFfprobe).copySync(path.join(bundledDir, 'ffprobe'));
  await Process.run('chmod', [
    '+x',
    path.join(bundledDir, 'ffmpeg'),
    path.join(bundledDir, 'ffprobe'),
  ]);
  logger.config(
    'Synced ffmpeg/ffprobe into rust/media/bundled/current/ for macOS embed',
  );
}

Future<void> _httpDownloadToFile(Uri url, File out) async {
  final client = HttpClient();
  Object? lastError;
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      await out.parent.create(recursive: true);
      final sink = out.openWrite();
      try {
        await response.pipe(sink);
      } finally {
        await sink.close();
      }
      client.close(force: true);
      return;
    } catch (e, st) {
      lastError = e;
      developer.log(
        'download attempt ${attempt + 1} failed: $e',
        stackTrace: st,
        name: 'MediaFfmpegFetch',
      );
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }
  client.close(force: true);
  throw StateError('Failed to download $url after 3 attempts: $lastError');
}

Future<void> _downloadUnixPair({
  required String subdir,
  required String ffAsset,
  required String fpAsset,
  required String packageRoot,
  required Logger logger,
}) async {
  final root = path.join(packageRoot, 'native', 'ffmpeg', subdir);
  final ff = path.join(root, 'ffmpeg');
  final fp = path.join(root, 'ffprobe');
  if (File(ff).existsSync() && File(fp).existsSync()) return;

  await Directory(root).create(recursive: true);
  final ffPartial = File('$ff.partial');
  final fpPartial = File('$fp.partial');
  try {
    logger.config('Downloading bundled ffmpeg/ffprobe for $subdir…');
    await _httpDownloadToFile(
      Uri.parse('$mediaFfmpegStaticBaseUrl/$ffAsset'),
      ffPartial,
    );
    await _httpDownloadToFile(
      Uri.parse('$mediaFfmpegStaticBaseUrl/$fpAsset'),
      fpPartial,
    );
    if (File(ff).existsSync()) File(ff).deleteSync();
    if (File(fp).existsSync()) File(fp).deleteSync();
    ffPartial.renameSync(ff);
    fpPartial.renameSync(fp);
    await Process.run('chmod', ['+x', ff, fp]);
  } catch (e) {
    if (ffPartial.existsSync()) ffPartial.deleteSync();
    if (fpPartial.existsSync()) fpPartial.deleteSync();
    rethrow;
  }
}

Future<void> _downloadWindowsX64({
  required String packageRoot,
  required Logger logger,
}) async {
  const subdir = 'windows-x86_64';
  final root = path.join(packageRoot, 'native', 'ffmpeg', subdir);
  final ff = path.join(root, 'ffmpeg.exe');
  final fp = path.join(root, 'ffprobe.exe');
  if (File(ff).existsSync() && File(fp).existsSync()) return;

  await Directory(root).create(recursive: true);
  final ffPartial = File('$ff.partial');
  final fpPartial = File('$fp.partial');
  try {
    logger.config('Downloading bundled ffmpeg.exe/ffprobe.exe for $subdir…');
    await _httpDownloadToFile(
      Uri.parse('$mediaFfmpegStaticBaseUrl/ffmpeg-win32-x64'),
      ffPartial,
    );
    await _httpDownloadToFile(
      Uri.parse('$mediaFfmpegStaticBaseUrl/ffprobe-win32-x64'),
      fpPartial,
    );
    if (File(ff).existsSync()) File(ff).deleteSync();
    if (File(fp).existsSync()) File(fp).deleteSync();
    ffPartial.renameSync(ff);
    fpPartial.renameSync(fp);
  } catch (e) {
    if (ffPartial.existsSync()) ffPartial.deleteSync();
    if (fpPartial.existsSync()) fpPartial.deleteSync();
    rethrow;
  }
}

Future<void> _downloadWindowsArm64({
  required String packageRoot,
  required Logger logger,
}) async {
  const subdir = 'windows-aarch64';
  final root = path.join(packageRoot, 'native', 'ffmpeg', subdir);
  final ffOut = path.join(root, 'ffmpeg.exe');
  final fpOut = path.join(root, 'ffprobe.exe');
  if (File(ffOut).existsSync() && File(fpOut).existsSync()) return;

  logger.config('Downloading BtbN ffmpeg zip for $subdir…');
  final zipFile = File(
    path.join(Directory.systemTemp.path, 'media_ffmpeg_winarm64.zip'),
  );
  await _httpDownloadToFile(Uri.parse(_btbnWinArm64Zip), zipFile);
  final bytes = zipFile.readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);
  ArchiveFile? ffmpeg;
  ArchiveFile? ffprobe;
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final lower = file.name.toLowerCase();
    if (lower.endsWith(r'ffmpeg.exe') && ffmpeg == null) {
      ffmpeg = file;
    } else if (lower.endsWith(r'ffprobe.exe') && ffprobe == null) {
      ffprobe = file;
    }
  }
  zipFile.deleteSync();
  if (ffmpeg == null || ffprobe == null) {
    throw StateError(
      'BtbN zip missing ffmpeg.exe or ffprobe.exe (got ${ffmpeg != null}, ${ffprobe != null})',
    );
  }
  await Directory(root).create(recursive: true);
  File(ffOut).writeAsBytesSync(ffmpeg.content as List<int>);
  File(fpOut).writeAsBytesSync(ffprobe.content as List<int>);
}
