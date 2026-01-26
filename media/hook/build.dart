import 'dart:convert';
import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';
import 'package:path/path.dart';

import '../../tool/build/utils/env_vars.dart';
import '../../tool/build/utils/required_directories.dart';
import '../../tool/build/android/setup_android.dart';
import '../../tool/build/utils/build_environment.dart';
import '../../tool/build/utils/target_mapping.dart';
import '../../tool/build/windows/setup_windows.dart';

final logger = Logger.detached('MediaBuilder')
  ..level = Level.ALL
  ..onRecord.listen((record) {
    final output = record.level >= Level.WARNING ? stderr : stdout;
    output.writeln(record);

    if (record.error != null) {
      output.writeln(record.error);
    }

    if (record.stackTrace != null) {
      output.writeln(record.stackTrace);
    }
  });

void main(List<String> args) async {
  await build(args, (BuildInput input, BuildOutputBuilder output) async {
    final String sourcePath = 'src/bindings/frb_generated.io.dart';
    final systemEnv = await _getShellEnvironment(input);
    await runLocalBuild(input, output, sourcePath, args, systemEnv);
  });
}

Future<void> runLocalBuild(
  BuildInput input,
  BuildOutputBuilder output,
  String assetName,
  List<String> args,
  Map<String, String> systemEnv,
) async {
  final targetOS = input.config.code.targetOS;
  final targetArchitecture = input.config.code.targetArchitecture;
  final iOSSdk = targetOS == OS.iOS ? input.config.code.iOS.targetSdk : null;
  final isSimulator = iOSSdk?.type == 'iphonesimulator';

  // Map 32-bit architectures to 64-bit (we only build 64-bit libraries)
  var effectiveArchitecture = targetArchitecture;
  if (targetOS == OS.android && targetArchitecture == Architecture.arm) {
    effectiveArchitecture = Architecture.arm64;
    logger.info('Overriding architecture from $targetArchitecture to arm64');
  }

  // Resolve paths
  final ffmpegDir = resolveFfmpegDir(input.packageRoot, targetOS, effectiveArchitecture, iOSSdk, systemEnv);
  final libheifPath = resolveLibheifDir(input.packageRoot, targetOS, effectiveArchitecture, isSimulator, systemEnv);
  final openh264Path = resolveOpenh264Dir(input.packageRoot, targetOS, effectiveArchitecture, systemEnv);

  // Setup environment variables
  final envVars = buildEnvVars(
    ffmpegDir: ffmpegDir,
    targetOS: targetOS,
    effectiveArchitecture: effectiveArchitecture,
    isSimulator: isSimulator,
    systemEnv: systemEnv,
    logger: logger,
    libheifPath: libheifPath,
    openh264Path: openh264Path,
  );

  // Platform-specific setup
  if (targetOS == OS.windows) {
    setupWindows(envVars, systemEnv, logger);
  }

  String? androidNdkHome;
  if (targetOS == OS.android) {
    androidNdkHome = await setupAndroid(
      envVars,
      input.packageRoot,
      effectiveArchitecture,
      systemEnv,
      cCompilerPath: input.config.code.cCompiler?.compiler,
      logger: logger,
    );
    _cleanAndroidTarget(input, effectiveArchitecture);
    if (androidNdkHome == null) {
      logger.shout('Android NDK not found, skipping build...');
      return;
    }
  }

  logger.info('''
Environment variables for ${targetOS.name} ${effectiveArchitecture.name}: 
  ${_getPrettyJSONString(envVars)}
    ''');

  // Build Rust code
  final rustBuilder = RustBuilder(
    assetName: assetName,
    cratePath: '../native',
    buildMode: input.config.linkingEnabled ? BuildMode.release : BuildMode.debug,
    enableDefaultFeatures: true,
    extraCargoEnvironmentVariables: envVars,
  );

  // Build with retry logic for Android
  await _buildWithRetry(rustBuilder, input, output, logger, targetOS, envVars, effectiveArchitecture);

  // Post-build tasks
  if (targetOS == OS.windows) {
    _copyWindowsDlls(input, output, envVars, assetName);
  }
  if (targetOS == OS.android && libheifPath != null && androidNdkHome != null) {
    _copyAndroidLibcxx(input, output, effectiveArchitecture, androidNdkHome, assetName);
  }
}

String _getPrettyJSONString(jsonObject) {
  var encoder = new JsonEncoder.withIndent("     ");
  return encoder.convert(jsonObject);
}

Future<Map<String, String>> _getShellEnvironment(BuildInput input) async {
  final buildEnvironmentFactory = const BuildEnvironmentFactory();
  final CodeConfig(:targetTriple, :cCompiler) = input.config.code;

  final envVars = buildEnvironmentFactory.createBuildEnvVars(
    targetOS: input.config.code.targetOS,
    targetTriple: targetTriple,
    cCompilerConfig: cCompiler,
  );
  print('envVars: ${_getPrettyJSONString(envVars)}');
  return envVars;
}

void _cleanAndroidTarget(BuildInput input, Architecture effectiveArchitecture) {
  final nativeAssetsDir = Directory.fromUri(input.outputDirectory);
  if (!nativeAssetsDir.existsSync()) return;

  final buildDirs = nativeAssetsDir.listSync().whereType<Directory>().toList();
  for (final buildDir in buildDirs) {
    final targetDir = Directory('${buildDir.path}/target');
    if (!targetDir.existsSync()) continue;

    // Delete ffmpeg-sys-next build directories
    final buildSubdir = Directory('${targetDir.path}/release/build');
    if (buildSubdir.existsSync()) {
      final ffmpegBuildDirs = buildSubdir
          .listSync(recursive: false)
          .whereType<Directory>()
          .where((d) => d.path.contains('ffmpeg-sys-next'))
          .toList();
      for (final d in ffmpegBuildDirs) {
        try {
          d.deleteSync(recursive: true);
          logger.info('Deleted ffmpeg-sys-next build directory');
        } catch (e) {
          logger.warning('Failed to delete build directory: $e');
        }
      }
    }

    // Delete target-specific directory
    final targetTriple = (effectiveArchitecture == Architecture.arm64 || effectiveArchitecture == Architecture.arm)
        ? 'aarch64-linux-android'
        : 'x86_64-linux-android';
    final targetSpecificDir = Directory('${targetDir.path}/$targetTriple');
    if (targetSpecificDir.existsSync()) {
      try {
        targetSpecificDir.deleteSync(recursive: true);
        logger.info('Deleted target directory to force rebuild');
      } catch (e) {
        logger.warning('Failed to delete target directory: $e');
      }
    }
  }
}

Future<void> _buildWithRetry(
  RustBuilder rustBuilder,
  BuildInput input,
  BuildOutputBuilder output,
  Logger logger,
  OS targetOS,
  Map<String, String> envVars,
  Architecture effectiveArchitecture,
) async {
  const maxRetries = 1;
  for (int attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      await rustBuilder.run(input: input, output: output, logger: logger);
      return;
    } catch (e) {
      final errorMsg = e.toString();
      if (errorMsg.contains('incompatible') &&
          errorMsg.contains('.rlib') &&
          attempt < maxRetries &&
          targetOS == OS.android) {
        logger.warning('Build failed due to incompatible .rlib files. Cleaning and retrying...');
        _cleanAndroidRlibs(input, effectiveArchitecture);
        continue;
      }
      rethrow;
    }
  }
}

void _cleanAndroidRlibs(BuildInput input, Architecture effectiveArchitecture) {
  final nativeAssetsDir = Directory.fromUri(input.outputDirectory);
  if (!nativeAssetsDir.existsSync()) return;

  final buildDirs = nativeAssetsDir.listSync().whereType<Directory>().toList();
  for (final buildDir in buildDirs) {
    final targetDir = Directory('${buildDir.path}/target');
    if (!targetDir.existsSync()) continue;

    final rlibFiles = targetDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.contains('libffmpeg_sys_next') && f.path.endsWith('.rlib'))
        .toList();

    for (final rlibFile in rlibFiles) {
      try {
        rlibFile.deleteSync();
        logger.info('Deleted .rlib file: ${rlibFile.path}');
      } catch (e) {
        logger.warning('Failed to delete .rlib file: $e');
      }
    }
  }
}

void _copyWindowsDlls(BuildInput input, BuildOutputBuilder output, Map<String, String> envVars, String assetsName) {
  final msys2Root = envVars['MSYS2_ROOT'] ?? r'C:\msys64';
  final mingwBin = '$msys2Root\\mingw64\\bin';
  final mingwDlls = ['libgcc_s_seh-1.dll', 'libwinpthread-1.dll'];

  for (final dllName in mingwDlls) {
    final dllFile = File(join(mingwBin, dllName));
    if (dllFile.existsSync()) {
      logger.info('Found DLL $dllName');
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: assetsName + '_' + dllName,
          linkMode: DynamicLoadingBundled(),
          file: toUri(dllFile.path),
        ),
        routing: ToAppBundle(),
      );
    } else {
      logger.warning('DLL $dllName not found');
    }
  }
}

void _copyAndroidLibcxx(
  BuildInput input,
  BuildOutputBuilder output,
  Architecture effectiveArchitecture,
  String androidNdkHome,
  String assetsName,
) {
  final ndkArch = effectiveArchitecture == Architecture.arm64 ? 'aarch64' : 'x86_64';
  final pathsToTry = [
    '$androidNdkHome/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/$ndkArch-linux-android/libc++_shared.so',
    '$androidNdkHome/toolchains/llvm/prebuilt/darwin-arm64/sysroot/usr/lib/$ndkArch-linux-android/libc++_shared.so',
  ];

  File? cxxSharedFile;
  for (final path in pathsToTry) {
    final file = File(path);
    if (file.existsSync()) {
      cxxSharedFile = file;
      break;
    }
  }

  if (cxxSharedFile == null) {
    logger.warning('libc++_shared.so not found in NDK');
    return;
  }

  logger.info('picked up libc++_shared.so from NDK ${cxxSharedFile.path}');

  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: assetsName + '_libc++_shared.so',
      linkMode: DynamicLoadingBundled(),
      file: toUri(cxxSharedFile.path),
    ),
    routing: ToAppBundle(),
  );
}
