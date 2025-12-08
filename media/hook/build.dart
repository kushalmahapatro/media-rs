import 'dart:io';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> args) async {
  final debugFile = File('/tmp/media_rs_args.txt');
  debugFile.writeAsStringSync("Args: $args\n");

  await build(args, (BuildInput input, BuildOutputBuilder output) async {
    final String assetName = 'src/bindings/frb_generated.io.dart';
    await runLocalBuild(input, output, assetName, args);
  });
}

Future<void> runLocalBuild(
  BuildInput input,
  BuildOutputBuilder output,
  String assetName,
  List<String> args,
) async {
  // Assume project root is 3 levels up from media/hook/build.dart (media/hook/ -> media/ -> root)
  // Actually hook is probably run from a different CWD?
  // Native assets cli usually runs with specific CWD.
  // Best to use relative paths from the package root if possible or locate the project root.
  // In `native_toolchain_rust`, `cratePath` is `../native`.
  // So `third_party` is `../third_party` (relative to media package root? No, `native` is sibling to `media`).
  // `cratePath: '../native'` implies `media/` is CWD? No, usually `media/hook/build.dart` implies execution context.
  // Let's assume `../` relative to `media/` folder puts us in project root.
  // So `../../third_party/ffmpeg_install` relative to `media/hook/build.dart`?
  // Let's resolve absolute path.

  // Actually, simpler: define paths relative to CWD if we know it.
  // But let's look at `cratePath: '../native'`.
  // If `runLocalBuild` runs where `build.dart` is, then `../native` means `native` is sibling to `hook`? No.
  // `media` structure: `media/hook/build.dart`.
  // `native` structure: `native/Cargo.toml`.
  // If `cratePath` is `../native`, then CWD must be `media/`?
  // `native` is sibling to `media`.
  // So `../native` works if CWD is `media/`.
  // Project root is `..` relative to `media`.
  // So `third_party` is `../third_party`.

  // Resolve paths relative to the package root.
  // input.packageRoot points to the 'media' directory.
  // Determine the correct FFmpeg directory based on the target platform
  // Determine the correct FFmpeg directory based on the target platform
  String subDir = '';

  // Manual config parsing to ensure robust platform detection
  String osName = 'unknown';
  String archName = 'unknown';
  String iosSdk = 'unknown';
  String? configPath;

  try {
    // Look for config path in args
    // args is captured from main
    for (final arg in args) {
      if (arg.startsWith('--config=')) {
        configPath = arg.substring('--config='.length);
        break;
      }
    }

    if (configPath != null) {
      final configFile = File(configPath);
      if (configFile.existsSync()) {
        final jsonStr = await configFile.readAsString();
        final dynamic json = jsonDecode(jsonStr);

        if (json is Map) {
          final dynamic configMap = json['config'];
          if (configMap is Map) {
            // Check extensions.code_assets
            // The JSON structure verified:
            // "config": { "extensions": { "code_assets": { "target_os": "ios", "ios": { "target_sdk": "iphonesimulator" } } } }

            final dynamic extensions = configMap['extensions'];
            if (extensions is Map) {
              final dynamic codeAssets = extensions['code_assets'];
              if (codeAssets is Map) {
                if (codeAssets['target_os'] != null)
                  osName = codeAssets['target_os'].toString();
                if (codeAssets['target_architecture'] != null)
                  archName = codeAssets['target_architecture'].toString();

                final dynamic iosObj = codeAssets['ios'];
                if (iosObj is Map && iosObj['target_sdk'] != null) {
                  iosSdk = iosObj['target_sdk'].toString();
                }
              }
            }

            // Fallback to top level if not found in extensions
            if (osName == 'unknown') {
              if (configMap['target_os'] != null)
                osName = configMap['target_os'].toString();
              if (configMap['target_architecture'] != null)
                archName = configMap['target_architecture'].toString();
            }
          }
        }
      }
    }
  } catch (e) {
    developer.log("Error parsing config manually: $e");
  }

  // Debug print
  print("DEBUG: osName='$osName', archName='$archName', iosSdk='$iosSdk'");
  try {
    File('/tmp/media_rs_final_debug.txt').writeAsStringSync(
      "DEBUG: osName='$osName', archName='$archName', iosSdk='$iosSdk'\nConfigPath: $configPath\n",
    );
  } catch (e) {}

  // Logic to select subDir
  if (osName.toLowerCase().contains('macos')) {
    subDir = '';
  } else if (osName.toLowerCase().contains('ios')) {
    if (iosSdk.toLowerCase().contains('simulator')) {
      if (archName.toLowerCase().contains('x64') ||
          archName.toLowerCase().contains('x86_64')) {
        subDir = 'ios/simulator_x64';
      } else {
        subDir = 'ios/simulator_arm64';
      }
    } else if (archName.toLowerCase().contains('x64') ||
        archName.toLowerCase().contains('x86_64')) {
      subDir = 'ios/simulator_x64';
    } else {
      subDir = 'ios/device';
    }
  } else if (osName.toLowerCase().contains('android')) {
    if (archName.toLowerCase().contains('arm64')) {
      subDir = 'android/arm64-v8a';
    } else if (archName.toLowerCase().contains('arm') ||
        archName.toLowerCase().contains('v7')) {
      subDir = 'android/armeabi-v7a';
    } else if (archName.toLowerCase().contains('x64') ||
        archName.toLowerCase().contains('x86_64')) {
      subDir = 'android/x86_64';
    } else if (archName.toLowerCase().contains('x86') ||
        archName.toLowerCase().contains('ia32')) {
      subDir = 'android/x86';
    }
  } else {
    // If still unknown, we might want to throw to avoid silent linking errors
    if (subDir.isEmpty) {
      // Just log warning? No, failing is better.
      // But for verification loops I'll let it slide if I can't determine it, but throw later.
    }
  }

  try {
    File(
      '/tmp/media_rs_final_subdir.txt',
    ).writeAsStringSync("SubDir: '$subDir'");
  } catch (e) {}

  // Construct valid path
  final ffmpegDirUri = input.packageRoot.resolve(
    '../third_party/ffmpeg_install/$subDir',
  );
  // Normalize path (remove trailing slash if empty subDir caused double slash?)
  // resolve handles it.
  final ffmpegDir = File.fromUri(ffmpegDirUri).path;

  try {
    File(
      '/tmp/media_rs_final_ffmpeg_dir.txt',
    ).writeAsStringSync("FFmpegDir: '$ffmpegDir'");
  } catch (e) {}

  if (!Directory(ffmpegDir).existsSync()) {
    // If we are on macOS and building for android/ios but verified only on macos, this might trigger?
    // No, we cross compile.
    throw Exception(
      "FFmpeg install not found at $ffmpegDir for $osName/$archName",
    );
  }

  // Ensure absolute paths for library search
  final ffmpegLibDir = '$ffmpegDir/lib';
  final ffmpegPkgConfigDir = '$ffmpegDir/lib/pkgconfig';

  // Construct RUSTFLAGS with proper path
  // Note: iOS deployment target is set in native/build.rs via rustc-link-arg
  final rustFlags = '-L $ffmpegLibDir';

  // Determine if building for simulator or device
  final bool isSimulator =
      osName.toLowerCase().contains('ios') &&
      (iosSdk.toLowerCase().contains('simulator') ||
          subDir.contains('simulator'));

  // Check for libheif installation
  // For macOS, use macos/universal; for iOS, use ios/iphoneos or ios/iphonesimulator
  String? libheifPlatformPath;
  if (osName.toLowerCase() == 'macos') {
    final macosLibheifUri = input.packageRoot.resolve(
      '../third_party/libheif_install/macos/universal',
    );
    final macosLibheifPath = File.fromUri(macosLibheifUri).path;
    if (Directory(macosLibheifPath).existsSync()) {
      libheifPlatformPath = macosLibheifPath;
    }
  } else if (osName.toLowerCase().contains('ios')) {
    final iosPlatform = isSimulator ? 'iphonesimulator' : 'iphoneos';
    final iosArch = archName == 'arm64' ? 'arm64' : 'x86_64';
    final iosLibheifUri = input.packageRoot.resolve(
      '../third_party/libheif_install/ios/$iosPlatform/$iosArch',
    );
    final iosLibheifPath = File.fromUri(iosLibheifUri).path;
    if (Directory(iosLibheifPath).existsSync()) {
      libheifPlatformPath = iosLibheifPath;
    }
  } else if (osName.toLowerCase() == 'android') {
    // For Android, use the ABI-specific path
    final androidAbi = archName == 'arm64' ? 'arm64-v8a' : 'x86_64';
    final androidLibheifUri = input.packageRoot.resolve(
      '../third_party/libheif_install/android/$androidAbi',
    );
    final androidLibheifPath = File.fromUri(androidLibheifUri).path;
    if (Directory(androidLibheifPath).existsSync()) {
      libheifPlatformPath = androidLibheifPath;
    }
  }

  final envVars = <String, String>{
    'FFMPEG_DIR': ffmpegDir,
    'FFMPEG_LIB_DIR': ffmpegLibDir,
    'FFMPEG_INCLUDE_DIR': '$ffmpegDir/include',
    'FFMPEG_PKG_CONFIG_PATH': ffmpegPkgConfigDir,
    'PKG_CONFIG_PATH': ffmpegPkgConfigDir,
    'PKG_CONFIG_LIBDIR': ffmpegPkgConfigDir,
    'FFMPEG_STATIC': '1',
    'PKG_CONFIG_ALLOW_CROSS': '1',
    'RUSTFLAGS': rustFlags,
    'IPHONEOS_DEPLOYMENT_TARGET': '16.0',
    // Disable VideoToolbox linking since we built FFmpeg without it
    'DISABLE_VIDEOTOOLBOX': '1',
    // DO NOT set LIBHEIF_NO_PKG_CONFIG - we want to use our pre-built libheif via pkg-config
  };

  // Add libheif directory if it exists
  if (libheifPlatformPath != null) {
    envVars['LIBHEIF_DIR'] = libheifPlatformPath;
    // Add libheif to PKG_CONFIG_PATH
    final libheifPkgConfigDir = '$libheifPlatformPath/lib/pkgconfig';
    if (Directory(libheifPkgConfigDir).existsSync()) {
      // Prepend libheif to PKG_CONFIG_PATH so it's checked first
      final currentPkgConfigPath =
          envVars['PKG_CONFIG_PATH'] ?? ffmpegPkgConfigDir;
      envVars['PKG_CONFIG_PATH'] = '$libheifPkgConfigDir:$currentPkgConfigPath';
      // Also update PKG_CONFIG_LIBDIR to include libheif
      final currentPkgConfigLibDir =
          envVars['PKG_CONFIG_LIBDIR'] ?? ffmpegPkgConfigDir;
      envVars['PKG_CONFIG_LIBDIR'] =
          '$libheifPkgConfigDir:$currentPkgConfigLibDir';

      // For Android cross-compilation, set PKG_CONFIG_SYSROOT_DIR
      if (osName.toLowerCase() == 'android') {
        final androidNdkHome = Platform.environment['ANDROID_NDK_HOME'];
        if (androidNdkHome != null) {
          // Find the sysroot - try common locations
          // NDK 27+ typically uses darwin-x86_64 even on Apple Silicon (runs via Rosetta)
          final sysrootPath =
              '$androidNdkHome/toolchains/llvm/prebuilt/darwin-x86_64/sysroot';
          // Check if sysroot exists (might be in different location)
          if (Directory(sysrootPath).existsSync()) {
            envVars['PKG_CONFIG_SYSROOT_DIR'] = sysrootPath;
            print('Set PKG_CONFIG_SYSROOT_DIR for Android: $sysrootPath');
          } else {
            // Try alternative location
            final altSysrootPath = '$androidNdkHome/sysroot';
            if (Directory(altSysrootPath).existsSync()) {
              envVars['PKG_CONFIG_SYSROOT_DIR'] = altSysrootPath;
              print(
                'Set PKG_CONFIG_SYSROOT_DIR for Android (alt): $altSysrootPath',
              );
            } else {
              // Try darwin-arm64 as fallback (for newer NDK versions)
              final fallbackSysrootPath =
                  '$androidNdkHome/toolchains/llvm/prebuilt/darwin-arm64/sysroot';
              if (Directory(fallbackSysrootPath).existsSync()) {
                envVars['PKG_CONFIG_SYSROOT_DIR'] = fallbackSysrootPath;
                print(
                  'Set PKG_CONFIG_SYSROOT_DIR for Android (fallback): $fallbackSysrootPath',
                );
              }
            }
          }
        }
      }

      print('Added libheif to PKG_CONFIG_PATH: $libheifPkgConfigDir');
    } else {
      print(
        'Warning: libheif pkg-config directory not found: $libheifPkgConfigDir',
      );
    }
  } else {
    print('Warning: libheif_install not found for platform $osName/$archName');
    print('libheif-sys will try to use embedded libheif or system libheif');
  }

  // Set C compiler flags for iOS builds to ensure __isPlatformVersionAtLeast is available
  if (osName.toLowerCase().contains('ios')) {
    if (isSimulator) {
      envVars['CC_aarch64-apple-ios-sim'] =
          'clang -mios-simulator-version-min=16.0';
      envVars['CFLAGS_aarch64-apple-ios-sim'] =
          '-mios-simulator-version-min=16.0';
    } else {
      envVars['CC_aarch64-apple-ios'] = 'clang -mios-version-min=16.0';
      envVars['CFLAGS_aarch64-apple-ios'] = '-mios-version-min=16.0';
    }
  }

  final rustBuilder = RustBuilder(
    assetName: assetName,
    cratePath: '../native',
    buildMode: BuildMode.release,
    enableDefaultFeatures: true,
    extraCargoEnvironmentVariables: envVars,
  );

  final Logger logger = Logger.detached('MediaBuilder');
  logger.level = Level.CONFIG;
  logger.onRecord.listen(
    (LogRecord record) => developer.log(
      '${record.level.name}: ${record.time}: ${record.message}',
    ),
  );

  await rustBuilder.run(input: input, output: output, logger: logger);
}
