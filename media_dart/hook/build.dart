import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:media_native_build/media_ffmpeg_fetch.dart';
import 'package:media_native_build/media_platform_paths.dart';
import 'package:media_native_build/media_rust_target.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';
import 'package:path/path.dart' as path;

const _frbAssetName = 'lib/src/bindings/frb_generated.io.dart';
const version = 'v0.0.1';

/// Release asset base name: `{triple}.zip`
String releaseUrl(String tripleArchiveBase) =>
    'https://github.com/kushalmahapatro/media-rs/releases/download/$version/$tripleArchiveBase.zip';
void main(List<String> args) async {
  await build(args, (BuildInput input, BuildOutputBuilder output) async {
    final logger = Logger.detached('MediaHook')
      ..level = Level.CONFIG
      ..onRecord.listen((r) => stdout.writeln('${r.level.name}: ${r.message}'));

    if (!input.config.buildCodeAssets) return;

    final localBuild = _parseLocalBuild(input);
    final usePrebuild = _parseUsePrebuild(input);

    logger.config('localBuild: $localBuild, usePrebuild: $usePrebuild');

    if (localBuild) {
      await _buildFromSource(input: input, output: output, logger: logger);
    } else if (usePrebuild) {
      await _buildFromPlatformBuilds(
        input: input,
        output: output,
        logger: logger,
      );
    } else {
      await _buildFromGithubRelease(
        input: input,
        output: output,
        logger: logger,
      );
    }
  });
}

bool _parseLocalBuild(BuildInput input) {
  final v = input.userDefines['localBuild'];
  if (v == true) return true;
  if (v is String && v.toLowerCase() == 'true') return true;
  return false;
}

/// With `localBuild: false`, set `usePrebuild: true` to copy from repo `platform-builds/`.
/// If both are false/unset, prebuilts are downloaded from the GitHub release.
bool _parseUsePrebuild(BuildInput input) {
  final v = input.userDefines['usePrebuild'];
  if (v == true) return true;
  if (v is String && v.toLowerCase() == 'true') return true;
  return false;
}

Future<void> _buildFromSource({
  required BuildInput input,
  required BuildOutputBuilder output,
  required Logger logger,
}) async {
  final rustBuilder = RustBuilder(
    assetName: _frbAssetName,
    cratePath: 'rust/media',
    buildMode: input.config.linkingEnabled
        ? BuildMode.release
        : BuildMode.debug,
    enableDefaultFeatures: true,
  );

  await _syncMacosFfmpegIntoRustCrate(input: input, logger: logger);
  await rustBuilder.run(input: input, output: output, logger: logger);
  await _setupDesktopFfmpegCodeAssets(
    input: input,
    logger: logger,
    output: output,
  );
}

Future<void> _buildFromPlatformBuilds({
  required BuildInput input,
  required BuildOutputBuilder output,
  required Logger logger,
}) async {
  final packageRoot = path.fromUri(input.packageRoot);
  final triple = mediaRustTargetTriple(input.config.code);
  final srcDir = mediaPlatformBuildSourceDir(
    packageRoot: packageRoot,
    rustTriple: triple,
  );
  await _installPrebuiltFromDirectory(
    input: input,
    output: output,
    logger: logger,
    srcDir: srcDir,
    logLabel: 'platform-builds',
  );
}

Future<void> _buildFromGithubRelease({
  required BuildInput input,
  required BuildOutputBuilder output,
  required Logger logger,
}) async {
  final code = input.config.code;
  final tripleTarget = mediaRustTargetTriple(code);
  final url = Uri.parse(releaseUrl(tripleTarget));
  logger.config(
    'Downloading prebuilt library $version for $tripleTarget from release URL $url',
  );
  final libFile = mediaNativeLibraryFileName(code);

  final staging = path.join(
    path.fromUri(input.outputDirectory),
    '.media_prebuilt_release',
    version,
    tripleTarget,
  );
  final srcDir = path.join(staging, tripleTarget);
  final srcLib = path.join(srcDir, libFile);

  if (!File(srcLib).existsSync()) {
    logger.config('Downloading prebuilt $tripleTarget from release');
    Directory(staging).createSync(recursive: true);
    final zipFile = File(path.join(staging, 'prebuilt.zip'));
    await _httpDownloadToFile(url, zipFile);
    if (Directory(srcDir).existsSync()) {
      Directory(srcDir).deleteSync(recursive: true);
    }
    _extractZipToDirectory(zipFile.readAsBytesSync(), staging);
    zipFile.deleteSync();
    if (!File(srcLib).existsSync()) {
      throw StateError(
        'Downloaded archive missing expected library at $srcLib (URL $url)',
      );
    }
  } else {
    logger.config('Using cached prebuilt from $srcDir');
  }

  await _installLibraryFromDirectory(
    input: input,
    output: output,
    logger: logger,
    srcDir: srcDir,
    logLabel: 'GitHub release',
  );

  // For desktop platforms (Linux, Windows, macOS), download FFmpeg separately
  // since it's not included in the GitHub release
  if (input.config.code.targetOS == OS.linux ||
      input.config.code.targetOS == OS.windows ||
      input.config.code.targetOS == OS.macOS) {
    await _setupDesktopFfmpegCodeAssets(
      input: input,
      logger: logger,
      output: output,
    );
  }
}

Future<void> _installPrebuiltFromDirectory({
  required BuildInput input,
  required BuildOutputBuilder output,
  required Logger logger,
  required String srcDir,
  required String logLabel,
}) async {
  final code = input.config.code;
  final triple = mediaRustTargetTriple(code);

  final linkMode = mediaResolvedLinkMode(code);
  final libFile = mediaNativeLibraryFileName(code);

  final srcLib = path.join(srcDir, libFile);
  if (!File(srcLib).existsSync()) {
    throw StateError('$logLabel: prebuilt library is missing: $srcLib');
  }

  final destDir = mediaHookNativeOutputDir(
    outputDirectory: input.outputDirectory,
    rustTriple: triple,
  );
  Directory(destDir).createSync(recursive: true);
  final destLib = path.join(destDir, libFile);
  File(srcLib).copySync(destLib);
  logger.config('$logLabel: copied $srcLib to $destLib');

  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: _frbAssetName,
      linkMode: linkMode,
      file: Uri.file(path.normalize(path.absolute(destLib))),
    ),
  );
  output.dependencies.add(Uri.file(path.normalize(path.absolute(srcLib))));

  if (code.targetOS == OS.android || code.targetOS == OS.iOS) {
    logger.config('$logLabel: registered $libFile for ${code.targetOS}');
    return;
  }

  // Modified: macOS now works like Linux/Windows - FFmpeg as separate CodeAssets
  // instead of embedded in the dylib
  /*
  if (code.targetOS == OS.macOS) {
    logger.config(
      'macOS prebuilt: ffmpeg/ffprobe are embedded in $libFile; no extra CodeAssets.',
    );
    return;
  }
  */

  final isWin = code.targetOS == OS.windows;
  final ffmpegName = isWin ? 'ffmpeg.exe' : 'ffmpeg';
  final ffprobeName = isWin ? 'ffprobe.exe' : 'ffprobe';

  for (final name in [ffmpegName, ffprobeName]) {
    final src = path.join(srcDir, name);
    if (!File(src).existsSync()) {
      throw StateError(
        '$logLabel: prebuilt $name missing beside library in $srcDir',
      );
    }
    final dest = path.join(destDir, name);
    File(src).copySync(dest);
    output.dependencies.add(Uri.file(path.normalize(path.absolute(src))));
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: name,
        linkMode: DynamicLoadingBundled(),
        file: Uri.file(path.normalize(path.absolute(dest))),
      ),
    );
  }
  if (!isWin) {
    await Process.run('chmod', [
      '+x',
      path.join(destDir, ffmpegName),
      path.join(destDir, ffprobeName),
    ]);
  }
  logger.config(
    '$logLabel: registered $ffmpegName and $ffprobeName beside $libFile',
  );
}

/// Installs only the library from a directory (without FFmpeg).
/// Used for GitHub releases where FFmpeg is downloaded separately.
Future<void> _installLibraryFromDirectory({
  required BuildInput input,
  required BuildOutputBuilder output,
  required Logger logger,
  required String srcDir,
  required String logLabel,
}) async {
  final code = input.config.code;
  final triple = mediaRustTargetTriple(code);

  final linkMode = mediaResolvedLinkMode(code);
  final libFile = mediaNativeLibraryFileName(code);

  final srcLib = path.join(srcDir, libFile);
  if (!File(srcLib).existsSync()) {
    throw StateError('$logLabel: prebuilt library is missing: $srcLib');
  }

  final destDir = mediaHookNativeOutputDir(
    outputDirectory: input.outputDirectory,
    rustTriple: triple,
  );
  Directory(destDir).createSync(recursive: true);
  final destLib = path.join(destDir, libFile);
  File(srcLib).copySync(destLib);
  logger.config('$logLabel: copied $srcLib to $destLib');

  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: _frbAssetName,
      linkMode: linkMode,
      file: Uri.file(path.normalize(path.absolute(destLib))),
    ),
  );
  output.dependencies.add(Uri.file(path.normalize(path.absolute(srcLib))));

  logger.config('$logLabel: registered $libFile for ${code.targetOS}');
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
    } catch (e) {
      lastError = e;
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }
  client.close(force: true);
  throw StateError('Failed to download $url after 3 attempts: $lastError');
}

void _extractZipToDirectory(List<int> bytes, String destDir) {
  final archive = ZipDecoder().decodeBytes(bytes);
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final outPath = path.join(destDir, file.name);
    File(outPath).parent.createSync(recursive: true);
    File(outPath).writeAsBytesSync(file.content as List<int>);
  }
}

Future<void> _syncMacosFfmpegIntoRustCrate({
  required BuildInput input,
  required Logger logger,
}) async {
  if (!input.config.buildCodeAssets) return;
  final code = input.config.code;
  if (code.targetOS != OS.macOS) return;

  final packageRoot = path.fromUri(input.packageRoot);
  final triple = mediaRustTargetTriple(code);
  await mediaSyncMacosFfmpegIntoRustCrate(
    packageRoot: packageRoot,
    logger: logger,
    rustTriple: triple,
  );
}

Future<void> _setupDesktopFfmpegCodeAssets({
  required BuildInput input,
  required Logger logger,
  required BuildOutputBuilder output,
}) async {
  if (!input.config.buildCodeAssets) return;
  final code = input.config.code;
  if (code.targetOS == OS.android || code.targetOS == OS.iOS) return;

  final triple = mediaRustTargetTriple(code);
  final packageRoot = path.fromUri(input.packageRoot);

  if (code.targetOS != OS.macOS) {
    await mediaEnsureFfmpegDownloadedForCodeConfig(
      code: code,
      packageRoot: packageRoot,
      logger: logger,
    );
  }

  if (code.targetOS == OS.macOS) {
    logger.config(
      'macOS: ffmpeg/ffprobe embedded in libmedia.dylib (include_bytes); no CodeAssets for CLI tools.',
    );
    return;
  }

  final folder = mediaFfmpegBundleDir(code);
  final ffmpegDir = path.join(packageRoot, 'native', 'ffmpeg', folder);
  final destDir = mediaHookNativeOutputDir(
    outputDirectory: input.outputDirectory,
    rustTriple: triple,
  );

  final isWin = code.targetOS == OS.windows;
  final ffmpegName = isWin ? 'ffmpeg.exe' : 'ffmpeg';
  final ffprobeName = isWin ? 'ffprobe.exe' : 'ffprobe';
  final srcFfmpeg = path.join(ffmpegDir, ffmpegName);
  final srcFfprobe = path.join(ffmpegDir, ffprobeName);

  if (!File(srcFfmpeg).existsSync() || !File(srcFfprobe).existsSync()) {
    throw StateError(
      'Bundled FFmpeg missing under $ffmpegDir after download step.',
    );
  }

  Directory(destDir).createSync(recursive: true);

  final ffmpegPath = path.join(destDir, ffmpegName);
  File(srcFfmpeg).copySync(ffmpegPath);

  final ffprobePath = path.join(destDir, ffprobeName);
  File(srcFfprobe).copySync(ffprobePath);

  if (!isWin) {
    await Process.run('chmod', ['+x', ffmpegPath, ffprobePath]);
  }

  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: ffmpegName,
      linkMode: DynamicLoadingBundled(),
      file: Uri.file(path.normalize(path.absolute(ffmpegPath))),
    ),
  );
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: ffprobeName,
      linkMode: DynamicLoadingBundled(),
      file: Uri.file(path.normalize(path.absolute(ffprobePath))),
    ),
  );
  logger.config(
    'Registered CodeAssets for $ffmpegName and $ffprobeName in $destDir',
  );
}
