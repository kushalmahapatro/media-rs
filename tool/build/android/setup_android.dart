import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';

import '../utils/required_directories.dart';

Future<String?> setupAndroid(
  Map<String, String> envVars,
  Uri packageRoot,
  Architecture effectiveArchitecture,
  Map<String, String> systemEnv, {
  String? ndkHomePath,
  Uri? cCompilerPath,
  required Logger logger,
}) async {
  // Modify Cargo.toml to change crate fingerprint
  final cargoTomlUri = packageRoot.resolve('${Directory.current.path}/../third_party/rust-ffmpeg-sys/Cargo.toml');
  final cargoToml = File.fromUri(cargoTomlUri);

  if (cargoToml.existsSync()) {
    try {
      String content = cargoToml.readAsStringSync();
      if (!content.contains('links = "ffmpeg_prebuilt"')) {
        content = content.replaceFirst('links   = "ffmpeg"', 'links   = "ffmpeg_prebuilt"');
        cargoToml.writeAsStringSync(content);
        logger.info('Modified Cargo.toml to use links = "ffmpeg_prebuilt"');
      }
    } catch (e) {
      logger.warning('Failed to modify Cargo.toml: $e');
    }
  }

  String? androidNdkHome = ndkHomePath;
  if (androidNdkHome == null) {
    final compiler = cCompilerPath;
    if (compiler != null) {
      androidNdkHome = compiler.path.split('/toolchains').first;
      logger.info('Extracted Android NDK from build system config: $androidNdkHome');
    } else {
      logger.warning('C compiler not found in build system config');
      return null;
    }
  }

  final targetTriple = (effectiveArchitecture == Architecture.arm64 || effectiveArchitecture == Architecture.arm)
      ? 'aarch64-linux-android'
      : 'x86_64-linux-android';

  // Find sysroot path (similar to what cargo-ndk does)
  final sysrootPaths = [
    '$androidNdkHome/toolchains/llvm/prebuilt/darwin-x86_64/sysroot',
    '$androidNdkHome/sysroot',
    '$androidNdkHome/toolchains/llvm/prebuilt/darwin-arm64/sysroot',
    '$androidNdkHome/toolchains/llvm/prebuilt/linux-x86_64/sysroot',
  ];

  String? sysrootPath;
  for (final path in sysrootPaths) {
    if (Directory(path).existsSync()) {
      sysrootPath = path;
      break;
    }
  }

  if (sysrootPath != null) {
    // Set CARGO_NDK_SYSROOT_PATH (required by ffmpeg-sys-next build script)
    envVars['CARGO_NDK_SYSROOT_PATH'] = sysrootPath;
    logger.info('Set CARGO_NDK_SYSROOT_PATH to: $sysrootPath');

    // Find toolchain directory
    final toolchainPaths = [
      '$androidNdkHome/toolchains/llvm/prebuilt/darwin-x86_64',
      '$androidNdkHome/toolchains/llvm/prebuilt/darwin-arm64',
      '$androidNdkHome/toolchains/llvm/prebuilt/linux-x86_64',
    ];

    String? toolchainPath;
    for (final path in toolchainPaths) {
      if (Directory(path).existsSync()) {
        toolchainPath = path;
        break;
      }
    }

    if (toolchainPath != null) {
      // Determine API level (default to 21 for compatibility)
      final apiLevel = getEnv(systemEnv, 'ANDROID_API_LEVEL') ?? '21';

      // Set CC and CFLAGS for the target (required by ffmpeg-sys-next build script)
      final ccPath = '$toolchainPath/bin/$targetTriple$apiLevel-clang';
      if (File(ccPath).existsSync()) {
        envVars['CC_$targetTriple'] = ccPath;

        // Set CFLAGS for the target (build script adds -fPIC separately)
        final cflags = '--sysroot=$sysrootPath';
        envVars['CFLAGS_$targetTriple'] = cflags;

        logger.info('Set CC_$targetTriple to: $ccPath');
        logger.info('Set CFLAGS_$targetTriple to: $cflags');
      } else {
        logger.warning('Android CC path not found: $ccPath');
      }
    } else {
      logger.warning('Android NDK toolchain not found');
    }
  } else {
    logger.warning('Android NDK sysroot not found. ffmpeg-sys-next build may fail.');
  }

  // Clean target directory to force rebuild
  return androidNdkHome;
}
