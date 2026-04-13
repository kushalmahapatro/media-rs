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
const version = 'v0.1.2';

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

/// Workspace apps set `hooks.user_defines.media_dart: { ... }`; merge also exposes top-level keys.
dynamic _userDefineAny(BuildInput input, String key) {
  final nested = input.userDefines['media_dart'];
  if (nested is Map && nested.containsKey(key)) {
    return nested[key];
  }
  return input.userDefines[key];
}

bool _parseLocalBuild(BuildInput input) {
  final v = _userDefineAny(input, 'localBuild');
  if (v == true) return true;
  if (v is String && v.toLowerCase() == 'true') return true;
  return false;
}

/// Explicit `usePrebuild: false` → GitHub download. `true` → `platform-builds/`.
/// If unset, use `platform-builds/` when the expected library file already exists (in-repo dev);
/// otherwise GitHub (CI / clean clones).
bool _parseUsePrebuild(BuildInput input) {
  final v = _userDefineAny(input, 'usePrebuild');
  if (v == false) return false;
  if (v is String && v.toLowerCase() == 'false') return false;
  if (v == true) return true;
  if (v is String && v.toLowerCase() == 'true') return true;
  return _prebuiltLayoutExists(input);
}

bool _prebuiltLayoutExists(BuildInput input) {
  final packageRoot = path.fromUri(input.packageRoot);
  final code = input.config.code;
  final triple = mediaMacOsEffectivePrebuildTriple(
    code,
    useUniversalMacOsPrebuild: _parseMacosUniversalPrebuild(input),
  );
  final srcDir = mediaPlatformBuildSourceDir(
    packageRoot: packageRoot,
    rustTriple: triple,
  );
  final libFile = mediaNativeLibraryFileName(code);
  return File(path.join(srcDir, libFile)).existsSync();
}

/// When true, macOS prebuilts use [mediaUniversalAppleDarwinTriple] (fat dylib + FFmpeg)
/// from GitHub / `platform-builds`, matching Flutter’s default universal macOS app.
bool _parseMacosUniversalPrebuild(BuildInput input) {
  final v = _userDefineAny(input, 'macosUniversalPrebuild');
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
  final triple = mediaMacOsEffectivePrebuildTriple(
    input.config.code,
    useUniversalMacOsPrebuild: _parseMacosUniversalPrebuild(input),
  );
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
  final tripleTarget = mediaMacOsEffectivePrebuildTriple(
    code,
    useUniversalMacOsPrebuild: _parseMacosUniversalPrebuild(input),
  );
  final url = Uri.parse(releaseUrl(tripleTarget));
  logger.config(
    'Downloading prebuilt library $version for $tripleTarget from release URL $url',
  );
  final libFile = mediaNativeLibraryFileName(code);

  // Cache layout: `.media_prebuilt_release/<version>/` with one folder per triple
  // (matches zips from `mediaArchivePlatformBuildFolder`, which contain `<triple>/…`).
  final cacheRoot = path.join(
    path.fromUri(input.outputDirectory),
    '.media_prebuilt_release',
    version,
  );
  final downloadDir = path.join(cacheRoot, '.download');
  final srcDir = path.join(cacheRoot, tripleTarget);
  final srcLib = path.join(srcDir, libFile);

  if (!File(srcLib).existsSync()) {
    logger.config('Downloading prebuilt $tripleTarget from release');
    Directory(downloadDir).createSync(recursive: true);
    final zipFile = File(path.join(downloadDir, '$tripleTarget.zip'));
    await _httpDownloadToFile(url, zipFile);
    if (Directory(srcDir).existsSync()) {
      Directory(srcDir).deleteSync(recursive: true);
    }
    final bytes = zipFile.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final extractRoot = _releaseZipExtractRootFromArchive(
      archive,
      cacheRoot: cacheRoot,
      triple: tripleTarget,
    );
    _extractZipArchive(archive, extractRoot);
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

  // Linux/Windows: FFmpeg as separate CodeAssets. macOS: download to native/ffmpeg/ 
  // and copy to app bundle via post-build script (avoiding CodeAssets framework wrapping).
  if (input.config.code.targetOS == OS.linux ||
      input.config.code.targetOS == OS.windows) {
    await _downloadFfmpegFromRelease(
      input: input,
      logger: logger,
      output: output,
      tripleTarget: tripleTarget,
    );
  }
  
  // macOS: Download FFmpeg to native/ffmpeg/ but don't register as CodeAssets
  if (input.config.code.targetOS == OS.macOS) {
    await _downloadFfmpegForMacOS(
      input: input,
      logger: logger,
      tripleTarget: tripleTarget,
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

  if (code.targetOS == OS.macOS) {
    logger.config(
      '$logLabel: macOS — FFmpeg/ffprobe are embedded in $libFile at Rust compile time; '
      'not registered as separate CodeAssets (Flutter macOS requires dylibs for bundled assets).',
    );
    return;
  }

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

/// Release zips from this repo use a top-level [triple] directory; some FFmpeg
/// bundles may be flat (binaries at archive root).
String _releaseZipExtractRootFromArchive(
  Archive archive, {
  required String cacheRoot,
  required String triple,
}) {
  final prefix = '$triple/';
  final hasTriplePrefix = archive.files.any(
    (f) => f.isFile && (f.name == triple || f.name.startsWith(prefix)),
  );
  return hasTriplePrefix ? cacheRoot : path.join(cacheRoot, triple);
}

void _extractZipArchive(Archive archive, String destDir) {
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final outPath = path.join(destDir, file.name);
    File(outPath).parent.createSync(recursive: true);
    File(outPath).writeAsBytesSync(file.content as List<int>);
  }
}

/// Downloads FFmpeg and ffprobe from GitHub releases for desktop platforms
Future<void> _downloadFfmpegFromRelease({
  required BuildInput input,
  required Logger logger,
  required BuildOutputBuilder output,
  required String tripleTarget,
}) async {
  final code = input.config.code;
  if (code.targetOS == OS.macOS) {
    return;
  }
  final isWin = code.targetOS == OS.windows;
  final ffmpegName = isWin ? 'ffmpeg.exe' : 'ffmpeg';
  final ffprobeName = isWin ? 'ffprobe.exe' : 'ffprobe';

  // FFmpeg release URL: {triple}-ffmpeg.zip
  final ffmpegReleaseUrl =
      'https://github.com/kushalmahapatro/media-rs/releases/download/$version/${tripleTarget}-ffmpeg.zip';

  // Same idea as prebuilts: version-level cache, `.download/` for zips, one
  // folder per triple for extracted binaries (avoids deleting the zip dir).
  final cacheRoot = path.join(
    path.fromUri(input.outputDirectory),
    '.media_ffmpeg_release',
    version,
  );
  final downloadDir = path.join(cacheRoot, '.download');
  final tripleDir = path.join(cacheRoot, tripleTarget);
  final srcFfmpeg = path.join(tripleDir, ffmpegName);
  final srcFfprobe = path.join(tripleDir, ffprobeName);

  // Download FFmpeg if not cached
  if (!File(srcFfmpeg).existsSync() || !File(srcFfprobe).existsSync()) {
    logger.config(
      'Downloading FFmpeg for $tripleTarget from $ffmpegReleaseUrl',
    );
    Directory(downloadDir).createSync(recursive: true);
    final zipFile = File(path.join(downloadDir, '$tripleTarget-ffmpeg.zip'));

    try {
      await _httpDownloadToFile(Uri.parse(ffmpegReleaseUrl), zipFile);

      if (Directory(tripleDir).existsSync()) {
        Directory(tripleDir).deleteSync(recursive: true);
      }
      final bytes = zipFile.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      final extractRoot = _releaseZipExtractRootFromArchive(
        archive,
        cacheRoot: cacheRoot,
        triple: tripleTarget,
      );
      _extractZipArchive(archive, extractRoot);
      zipFile.deleteSync();

      if (!File(srcFfmpeg).existsSync() || !File(srcFfprobe).existsSync()) {
        throw StateError(
          'Downloaded FFmpeg archive missing expected binaries under $tripleDir',
        );
      }
      logger.config('Downloaded FFmpeg for $tripleTarget');
    } catch (e) {
      logger.config('Failed to download FFmpeg from release: $e');
      throw StateError(
        'Failed to download FFmpeg for $tripleTarget. '
        'Please ensure ${tripleTarget}-ffmpeg.zip exists in GitHub release $version.',
      );
    }
  } else {
    logger.config('Using cached FFmpeg for $tripleTarget from $tripleDir');
  }

  // Copy to output directory
  final destDir = mediaHookNativeOutputDir(
    outputDirectory: input.outputDirectory,
    rustTriple: tripleTarget,
  );
  Directory(destDir).createSync(recursive: true);

  final destFfmpeg = path.join(destDir, ffmpegName);
  final destFfprobe = path.join(destDir, ffprobeName);

  File(srcFfmpeg).copySync(destFfmpeg);
  File(srcFfprobe).copySync(destFfprobe);

  // Make executable on Unix
  if (!isWin) {
    await Process.run('chmod', ['+x', destFfmpeg, destFfprobe]);
  }

  // Register as CodeAssets
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: ffmpegName,
      linkMode: DynamicLoadingBundled(),
      file: Uri.file(path.normalize(path.absolute(destFfmpeg))),
    ),
  );
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: ffprobeName,
      linkMode: DynamicLoadingBundled(),
      file: Uri.file(path.normalize(path.absolute(destFfprobe))),
    ),
  );

  output.dependencies.add(Uri.file(path.normalize(path.absolute(srcFfmpeg))));
  output.dependencies.add(Uri.file(path.normalize(path.absolute(srcFfprobe))));

  logger.config(
    'GitHub release: registered $ffmpegName and $ffprobeName for $tripleTarget',
  );
}

/// Downloads FFmpeg for macOS to native/ffmpeg/ directory.
/// Does NOT register as CodeAssets - will be copied to app bundle via post-build script.
Future<void> _downloadFfmpegForMacOS({
  required BuildInput input,
  required Logger logger,
  required String tripleTarget,
}) async {
  final packageRoot = path.fromUri(input.packageRoot);
  final folder = mediaFfmpegBundleDirForRustTriple(tripleTarget)!;

  final ffmpegDir = path.join(packageRoot, 'native', 'ffmpeg', folder);
  final srcFfmpeg = path.join(ffmpegDir, 'ffmpeg');
  final srcFfprobe = path.join(ffmpegDir, 'ffprobe');
  
  // Download if not cached
  if (!File(srcFfmpeg).existsSync() || !File(srcFfprobe).existsSync()) {
    final ffmpegReleaseUrl =
        'https://github.com/kushalmahapatro/media-rs/releases/download/$version/${tripleTarget}-ffmpeg.zip';
    logger.config('Downloading FFmpeg for macOS $tripleTarget from $ffmpegReleaseUrl');
    
    Directory(ffmpegDir).createSync(recursive: true);
    final zipFile = File(path.join(ffmpegDir, 'ffmpeg.zip'));
    
    try {
      await _httpDownloadToFile(Uri.parse(ffmpegReleaseUrl), zipFile);
      
      // Extract
      final bytes = zipFile.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      final extractRoot = _releaseZipExtractRootFromArchive(
        archive,
        cacheRoot: ffmpegDir,
        triple: tripleTarget,
      );
      _extractZipArchive(archive, extractRoot);
      zipFile.deleteSync();
      
      // Make executable
      await Process.run('chmod', ['+x', srcFfmpeg, srcFfprobe]);
      
      logger.config('Downloaded FFmpeg for macOS $tripleTarget to $ffmpegDir');
    } catch (e) {
      logger.config('Failed to download FFmpeg: $e');
      throw StateError('Failed to download FFmpeg for $tripleTarget');
    }
  } else {
    logger.config('Using cached FFmpeg for macOS $tripleTarget from $ffmpegDir');
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
