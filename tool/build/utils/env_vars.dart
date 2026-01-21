import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';

import 'required_directories.dart';

Map<String, String> buildEnvVars({
  required String ffmpegDir,
  required OS targetOS,
  required Architecture effectiveArchitecture,
  required bool isSimulator,
  required Map<String, String> systemEnv,
  required Logger logger,
  String? openh264Path,
  String? libheifPath,
}) {
  final ffmpegLibDir = '$ffmpegDir/lib';
  final ffmpegPkgConfigDir = '$ffmpegDir/lib/pkgconfig';
  final pathSeparator = targetOS == OS.windows ? ';' : ':';

  final envVars = <String, String>{
    'FFMPEG_DIR': ffmpegDir,
    'FFMPEG_LIB_DIR': ffmpegLibDir,
    'FFMPEG_INCLUDE_DIR': '$ffmpegDir/include',
    'FFMPEG_PKG_CONFIG_PATH': ffmpegPkgConfigDir,
    'PKG_CONFIG_PATH': ffmpegPkgConfigDir,
    'PKG_CONFIG_LIBDIR': ffmpegPkgConfigDir,
    'FFMPEG_STATIC': '1',
    'PKG_CONFIG_ALLOW_CROSS': '1',
    'RUSTFLAGS': '-L $ffmpegLibDir',
    'IPHONEOS_DEPLOYMENT_TARGET': '16.0',
    'DISABLE_VIDEOTOOLBOX': '1',
  };

  // iOS compiler flags
  if (targetOS == OS.iOS) {
    if (isSimulator) {
      envVars['CC_aarch64-apple-ios-sim'] = 'clang -mios-simulator-version-min=16.0';
      envVars['CFLAGS_aarch64-apple-ios-sim'] = '-mios-simulator-version-min=16.0';
    } else {
      envVars['CC_aarch64-apple-ios'] = 'clang -mios-version-min=16.0';
      envVars['CFLAGS_aarch64-apple-ios'] = '-mios-version-min=16.0';
    }
  }

  // Android target override
  if (targetOS == OS.android && effectiveArchitecture == Architecture.arm) {
    envVars['CARGO_BUILD_TARGET'] = 'aarch64-linux-android';
  }

  // OpenH264
  if (openh264Path != null) {
    envVars['OPENH264_DIR'] = openh264Path;
    logger.info('Using OpenH264 from: $openh264Path');
  }

  // Libheif
  if (libheifPath != null) {
    envVars['LIBHEIF_DIR'] = libheifPath;
    final libheifPkgConfigDir = '$libheifPath/lib/pkgconfig';
    if (Directory(libheifPkgConfigDir).existsSync()) {
      final currentPkgConfigPath = envVars['PKG_CONFIG_PATH'] ?? ffmpegPkgConfigDir;
      envVars['PKG_CONFIG_PATH'] = '$libheifPkgConfigDir$pathSeparator$currentPkgConfigPath';
      envVars['PKG_CONFIG_LIBDIR'] =
          '$libheifPkgConfigDir$pathSeparator${envVars['PKG_CONFIG_LIBDIR'] ?? ffmpegPkgConfigDir}';

      // Android sysroot
      if (targetOS == OS.android) {
        final androidNdkHome = getEnv(systemEnv, 'ANDROID_NDK_HOME');
        if (androidNdkHome != null) {
          final sysrootPaths = [
            '$androidNdkHome/toolchains/llvm/prebuilt/darwin-x86_64/sysroot',
            '$androidNdkHome/sysroot',
            '$androidNdkHome/toolchains/llvm/prebuilt/darwin-arm64/sysroot',
          ];
          for (final sysrootPath in sysrootPaths) {
            if (Directory(sysrootPath).existsSync()) {
              envVars['PKG_CONFIG_SYSROOT_DIR'] = sysrootPath;
              break;
            }
          }
        }
      }
      logger.info('Added libheif to PKG_CONFIG_PATH: $libheifPkgConfigDir');
    }
  } else {
    logger.warning('libheif_install not found, libheif-sys will try embedded or system libheif');
  }

  return envVars;
}
