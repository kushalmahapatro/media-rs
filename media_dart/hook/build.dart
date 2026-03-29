import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:media_native_build/media_ffmpeg_fetch.dart';
import 'package:media_native_build/media_platform_paths.dart';
import 'package:media_native_build/media_rust_target.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';
import 'package:path/path.dart' as path;

const _frbAssetName = 'lib/src/bindings/frb_generated.io.dart';

void main(List<String> args) async {
  await build(args, (BuildInput input, BuildOutputBuilder output) async {
    final logger = Logger.detached('MediaHook')
      ..level = Level.CONFIG
      ..onRecord.listen((r) => stdout.writeln('${r.level.name}: ${r.message}'));

    if (!input.config.buildCodeAssets) return;

    final localBuild = _parseLocalBuild(input);

    if (localBuild) {
      await _buildFromSource(input: input, output: output, logger: logger);
    } else {
      await _buildFromPrebuilts(input: input, output: output, logger: logger);
    }
  });
}

bool _parseLocalBuild(BuildInput input) {
  final v = input.userDefines['localBuild'];
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

Future<void> _buildFromPrebuilts({
  required BuildInput input,
  required BuildOutputBuilder output,
  required Logger logger,
}) async {
  final code = input.config.code;
  final packageRoot = path.fromUri(input.packageRoot);
  final triple = mediaRustTargetTriple(code);
  final cargoMode = mediaCargoBuildModeFolder(
    release: input.config.linkingEnabled,
  );
  final linkMode = mediaResolvedLinkMode(code);
  final libFile = mediaNativeLibraryFileName(code);

  final srcDir = mediaPlatformBuildSourceDir(
    packageRoot: packageRoot,
    rustTriple: triple,
  );
  final srcLib = path.join(srcDir, libFile);
  if (!File(srcLib).existsSync()) {
    throw StateError(
      'localBuild is false but prebuilt library is missing: $srcLib',
    );
  }

  final destDir = mediaHookNativeOutputDir(
    outputDirectory: input.outputDirectory,
    rustTriple: triple,
    cargoModeFolder: cargoMode,
  );
  Directory(destDir).createSync(recursive: true);
  final destLib = path.join(destDir, libFile);
  File(srcLib).copySync(destLib);
  logger.config('Prebuilt: copied $srcLib to $destLib');

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
    logger.config('Prebuilt: registered $libFile for ${code.targetOS}');
    return;
  }

  if (code.targetOS == OS.macOS) {
    logger.config(
      'macOS prebuilt: ffmpeg/ffprobe are embedded in $libFile; no extra CodeAssets.',
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
        'localBuild is false but prebuilt $name missing beside library in $srcDir',
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
    'Prebuilt: registered $ffmpegName and $ffprobeName beside $libFile',
  );
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
    cargoModeFolder: mediaCargoBuildModeFolder(
      release: input.config.linkingEnabled,
    ),
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
