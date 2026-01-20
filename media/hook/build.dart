import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:path/path.dart' as path;
import 'dart:developer' as developer;
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> args) async {
  await build(args, (BuildInput input, BuildOutputBuilder output) async {
    final String assetName = 'src/bindings/frb_generated.io.dart';
    await runLocalBuild(input, output, assetName, args);
  });
}

Future<void> runLocalBuild(BuildInput input, BuildOutputBuilder output, String assetName, List<String> args) async {
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

  final targetOS = input.config.code.targetOS;
  final targetArchitecture = input.config.code.targetArchitecture;
  final iOSSdk = targetOS == OS.iOS ? input.config.code.iOS.targetSdk : null;
  final outputDirectory = Directory.fromUri(input.outputDirectory);

  // Construct outputDirectoryShared from the pattern:
  // D:\media-rs\media-rs\.dart_tool\hooks_runner\shared\media\build\ + first 10 chars of outputDirectory name
  final outputDirName = outputDirectory.uri.pathSegments.last;
  final sharedDirName = outputDirName.length >= 10 ? outputDirName.substring(0, 10) : outputDirName;
  final packageRootDir = Directory.fromUri(input.packageRoot);
  final outputDirectorySharedPath = path.join(
    packageRootDir.parent.path,
    '.dart_tool',
    'hooks_runner',
    'shared',
    'media',
    'build',
    sharedDirName,
  );
  final outputDirectoryShared = Directory(outputDirectorySharedPath);

  // Use enum values directly for type-safe comparisons
  // CRITICAL: Override architecture for Android ARM builds to use arm64 instead of armv7
  // We only build 64-bit libraries, so map 32-bit ARM requests to 64-bit
  var effectiveArchitecture = targetArchitecture;
  if (targetOS == OS.android && targetArchitecture == Architecture.arm) {
    print('INFO: Overriding architecture from $targetArchitecture to arm64 (we only have 64-bit libraries)');
    effectiveArchitecture = Architecture.arm64;
  }

  // Logic to select subDir
  if (targetOS == OS.macOS) {
    subDir = '';
  } else if (targetOS == OS.iOS) {
    if (iOSSdk?.type == 'iphonesimulator') {
      if (effectiveArchitecture == Architecture.x64) {
        subDir = 'ios/simulator_x64';
      } else {
        subDir = 'ios/simulator_arm64';
      }
    } else if (effectiveArchitecture == Architecture.x64) {
      subDir = 'ios/simulator_x64';
    } else {
      subDir = 'ios/device';
    }
  } else if (targetOS == OS.android) {
    if (effectiveArchitecture == Architecture.arm64) {
      subDir = 'android/arm64-v8a';
    } else if (effectiveArchitecture == Architecture.arm) {
      // Map 32-bit ARM to 64-bit ARM since we only build for arm64-v8a
      // Modern Android devices are 64-bit, and this avoids missing build errors
      subDir = 'android/arm64-v8a';
      print('INFO: Mapping 32-bit ARM to 64-bit ARM (arm64-v8a)');
    } else if (effectiveArchitecture == Architecture.x64) {
      subDir = 'android/x86_64';
    } else if (effectiveArchitecture == Architecture.ia32) {
      // Map 32-bit x86 to 64-bit x86 since we only build for x86_64
      subDir = 'android/x86_64';
      print('INFO: Mapping 32-bit x86 to 64-bit x86 (x86_64)');
    }
  } else if (targetOS == OS.linux) {
    if (effectiveArchitecture == Architecture.x64) {
      subDir = 'linux/x86_64';
    } else if (effectiveArchitecture == Architecture.arm64) {
      subDir = 'linux/arm64';
    }
  } else if (targetOS == OS.windows) {
    // Default to x86_64 for now (Flutter desktop is typically x64).
    subDir = 'windows/x86_64';
  } else {
    // If still unknown, we might want to throw to avoid silent linking errors
    if (subDir.isEmpty) {
      // Just log warning? No, failing is better.
      // But for verification loops I'll let it slide if I can't determine it, but throw later.
    }
  }

  // Construct valid path
  // Allow override for easier bootstrapping on new machines (esp. Windows).
  final envFfmpegDir = Platform.environment['MEDIA_RS_FFMPEG_DIR'];
  final ffmpegDirUri = envFfmpegDir != null
      ? Uri.directory(envFfmpegDir)
      : input.packageRoot.resolve('../third_party/ffmpeg_install/$subDir');
  // Normalize path (remove trailing slash if empty subDir caused double slash?)
  // resolve handles it.
  final ffmpegDir = File.fromUri(ffmpegDirUri).path;

  try {
    final tempDir = Directory.systemTemp;
    File('${tempDir.path}/media_rs_final_ffmpeg_dir.txt').writeAsStringSync("FFmpegDir: '$ffmpegDir'");
  } catch (e) {}

  if (!Directory(ffmpegDir).existsSync()) {
    // If we are on macOS and building for android/ios but verified only on macos, this might trigger?
    // No, we cross compile.
    throw Exception("FFmpeg install not found at $ffmpegDir for $targetOS/$targetArchitecture");
  }

  // Ensure absolute paths for library search
  final ffmpegLibDir = '$ffmpegDir/lib';
  final ffmpegPkgConfigDir = '$ffmpegDir/lib/pkgconfig';

  // Construct RUSTFLAGS with proper path
  // Note: iOS deployment target is set in native/build.rs via rustc-link-arg
  final rustFlags = '-L $ffmpegLibDir';

  // Determine if building for simulator or device
  final bool isSimulator = iOSSdk?.type == 'iphonesimulator';

  // Check for libheif installation
  // For macOS, use macos/universal; for iOS, use ios/iphoneos or ios/iphonesimulator
  String? libheifPlatformPath;
  final envLibheifDir = Platform.environment['MEDIA_RS_LIBHEIF_DIR'];
  if (envLibheifDir != null && Directory(envLibheifDir).existsSync()) {
    libheifPlatformPath = envLibheifDir;
  } else if (targetOS == OS.macOS) {
    final macosLibheifUri = input.packageRoot.resolve('../third_party/libheif_install/macos/universal');
    final macosLibheifPath = File.fromUri(macosLibheifUri).path;
    if (Directory(macosLibheifPath).existsSync()) {
      libheifPlatformPath = macosLibheifPath;
    }
  } else if (targetOS == OS.iOS) {
    final iosPlatform = isSimulator ? 'iphonesimulator' : 'iphoneos';
    final iosArch = effectiveArchitecture == Architecture.arm64 ? 'arm64' : 'x86_64';
    final iosLibheifUri = input.packageRoot.resolve('../third_party/libheif_install/ios/$iosPlatform/$iosArch');
    final iosLibheifPath = File.fromUri(iosLibheifUri).path;
    if (Directory(iosLibheifPath).existsSync()) {
      libheifPlatformPath = iosLibheifPath;
    }
  } else if (targetOS == OS.android) {
    // For Android, use the ABI-specific path
    // Map 32-bit ARM to 64-bit ARM, and 32-bit x86 to 64-bit x86
    final androidAbi = (effectiveArchitecture == Architecture.arm64 || effectiveArchitecture == Architecture.arm)
        ? 'arm64-v8a'
        : 'x86_64';
    final androidLibheifUri = input.packageRoot.resolve('../third_party/libheif_install/android/$androidAbi');
    final androidLibheifPath = File.fromUri(androidLibheifUri).path;
    if (Directory(androidLibheifPath).existsSync()) {
      libheifPlatformPath = androidLibheifPath;
    }
  } else if (targetOS == OS.linux) {
    final linuxArch = effectiveArchitecture == Architecture.arm64 ? 'arm64' : 'x86_64';
    final linuxLibheifUri = input.packageRoot.resolve('../third_party/libheif_install/linux/$linuxArch');
    final linuxLibheifPath = File.fromUri(linuxLibheifUri).path;
    if (Directory(linuxLibheifPath).existsSync()) {
      libheifPlatformPath = linuxLibheifPath;
    }
  } else if (targetOS == OS.windows) {
    final winLibheifUri = input.packageRoot.resolve('../third_party/libheif_install/windows/x86_64');
    final winLibheifPath = File.fromUri(winLibheifUri).path;
    if (Directory(winLibheifPath).existsSync()) {
      libheifPlatformPath = winLibheifPath;
    }
  }

  // Determine path separator based on OS
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
    'RUSTFLAGS': rustFlags,
    'IPHONEOS_DEPLOYMENT_TARGET': '16.0',
    // Disable VideoToolbox linking since we built FFmpeg without it
    'DISABLE_VIDEOTOOLBOX': '1',
    // DO NOT set LIBHEIF_NO_PKG_CONFIG - we want to use our pre-built libheif via pkg-config
  };

  // On Windows, configure pkg-config and disable vcpkg for libheif-sys
  if (targetOS == OS.windows) {
    // Ensure PKG_CONFIG points to pkg-config (pkgconf provides compatibility)
    envVars['PKG_CONFIG'] = 'pkg-config';
    // Ensure pkg-config can find our libraries
    envVars['PKG_CONFIG_ALLOW_SYSTEM_LIBS'] = '1';
    // Add MinGW-w64 bin directory to PATH so pkg-config is found
    // This is needed because cargo runs in MSVC context, not MinGW
    // Try to detect MSYS2 path from environment, default to common location
    final msys2Root = Platform.environment['MSYS2_ROOT'] ?? r'C:\msys64';
    // Set MSYS2_ROOT for build.rs to find MinGW libraries
    envVars['MSYS2_ROOT'] = msys2Root;
    final mingwBin = '$msys2Root\\mingw64\\bin';
    final currentPath = Platform.environment['PATH'] ?? '';
    envVars['PATH'] = '$mingwBin;$currentPath';

    // Try to find LLVM/Clang for bindgen (needed for FFmpeg bindings)
    // Check common locations for clang.dll
    final vsInstallDir = Platform.environment['VSINSTALLDIR'];
    final possibleClangPaths = <String>[
      if (Platform.environment['LIBCLANG_PATH'] != null) Platform.environment['LIBCLANG_PATH']!,
      r'C:\Program Files\LLVM\bin',
      r'C:\Program Files (x86)\LLVM\bin',
      r'C:\msys64\mingw64\bin', // MSYS2 might have clang
      if (vsInstallDir != null) '$vsInstallDir\\VC\\Tools\\Llvm\\x64\\bin',
    ].where((path) => Directory(path).existsSync()).toList();

    // Check if clang.dll exists in any of these paths
    String? clangPath;
    for (final path in possibleClangPaths) {
      final clangDll = File('$path\\clang.dll');
      final libclangDll = File('$path\\libclang.dll');
      if (clangDll.existsSync() || libclangDll.existsSync()) {
        clangPath = path;
        break;
      }
    }

    if (clangPath != null) {
      envVars['LIBCLANG_PATH'] = clangPath;
      // Also add to PATH
      envVars['PATH'] = '$clangPath;$mingwBin;$currentPath';
      print('Windows: Found LLVM/Clang at $clangPath, set LIBCLANG_PATH');
    } else {
      // Try to run the install script
      final installScript = File(input.packageRoot.resolve('../scripts/support/install_llvm_windows.bat').toFilePath());
      if (installScript.existsSync()) {
        print('Windows: LLVM/Clang not found. Attempting automatic installation...');
        try {
          final result = Process.runSync(installScript.path, [], runInShell: true);
          if (result.exitCode == 0) {
            print('Windows: LLVM installation script completed successfully.');
            print('Windows: Please restart your terminal/IDE and try again.');
          } else {
            print('Windows: Installation script output: ${result.stdout}');
            print('Windows: Installation script error: ${result.stderr}');
          }
        } catch (e) {
          print('Windows: Failed to run installation script: $e');
        }
      }
      print('Windows: WARNING: LLVM/Clang not found. bindgen will fail.');
      print('Windows: To install LLVM automatically:');
      print('Windows:   1. Right-click: scripts/support/install_llvm_windows.bat');
      print('Windows:   2. Select "Run as administrator"');
      print('Windows:   3. Restart your terminal/IDE');
      print('Windows: Or install manually from: https://github.com/llvm/llvm-project/releases');
      print('Windows: Or install "C++ Clang tools for Windows" via Visual Studio Installer');
    }

    // Try to disable vcpkg by setting it to a non-existent path
    // libheif-sys should then fall back to pkg-config
    envVars['VCPKG_ROOT'] = r'C:\nonexistent_vcpkg_path';
    print('Windows: Added $mingwBin to PATH for pkg-config');
    print('Windows: Set VCPKG_ROOT to non-existent path to force pkg-config fallback');
  }

  // Configure OpenH264 directory for platforms where we build it
  final envOpenh264Dir = Platform.environment['MEDIA_RS_OPENH264_DIR'];
  if (envOpenh264Dir != null && Directory(envOpenh264Dir).existsSync()) {
    envVars['OPENH264_DIR'] = envOpenh264Dir;
    print('Using OpenH264 from env: $envOpenh264Dir');
  } else if (targetOS == OS.macOS) {
    final openh264Uri = input.packageRoot.resolve('../third_party/openh264_build_arm64');
    final openh264Path = File.fromUri(openh264Uri).path;
    if (Directory(openh264Path).existsSync()) {
      envVars['OPENH264_DIR'] = openh264Path;
      print('Using OpenH264 from: $openh264Path');
    } else {
      print(
        'Warning: OpenH264 build directory not found at $openh264Path; libopenh264 symbols may be missing at link time.',
      );
    }
  } else if (targetOS == OS.android) {
    // For Android, use the ABI-specific path
    // Map 32-bit ARM to 64-bit ARM, and 32-bit x86 to 64-bit x86
    final androidAbi = (effectiveArchitecture == Architecture.arm64 || effectiveArchitecture == Architecture.arm)
        ? 'arm64-v8a'
        : 'x86_64';
    final openh264Uri = input.packageRoot.resolve('../third_party/openh264_install/android/$androidAbi');
    final openh264Path = File.fromUri(openh264Uri).path;
    if (Directory(openh264Path).existsSync()) {
      envVars['OPENH264_DIR'] = openh264Path;
      print('Using OpenH264 from: $openh264Path');
    } else {
      // Try alternative path structure (build directory)
      final openh264BuildUri = input.packageRoot.resolve('../third_party/openh264_build_android_$androidAbi');
      final openh264BuildPath = File.fromUri(openh264BuildUri).path;
      if (Directory(openh264BuildPath).existsSync()) {
        envVars['OPENH264_DIR'] = openh264BuildPath;
        print('Using OpenH264 from: $openh264BuildPath');
      } else {
        print(
          'Warning: OpenH264 not found for Android $androidAbi. Hardware encoders may fail due to permissions. Consider building OpenH264 for Android.',
        );
      }
    }
  } else if (targetOS == OS.linux) {
    final linuxArch = effectiveArchitecture == Architecture.arm64 ? 'arm64' : 'x86_64';
    final openh264Uri = input.packageRoot.resolve('../third_party/openh264_install/linux/$linuxArch');
    final openh264Path = File.fromUri(openh264Uri).path;
    if (Directory(openh264Path).existsSync()) {
      envVars['OPENH264_DIR'] = openh264Path;
      print('Using OpenH264 from: $openh264Path');
    }
  } else if (targetOS == OS.windows) {
    // For Windows, use the x86_64 installation
    final openh264Uri = input.packageRoot.resolve('../third_party/openh264_install/windows/x86_64');
    final openh264Path = File.fromUri(openh264Uri).path;
    if (Directory(openh264Path).existsSync()) {
      envVars['OPENH264_DIR'] = openh264Path;
      print('Using OpenH264 from: $openh264Path');
    } else {
      print('Warning: OpenH264 not found for Windows. H.264 encoding may not work.');
    }
  }

  // Add libheif directory if it exists
  if (libheifPlatformPath != null) {
    envVars['LIBHEIF_DIR'] = libheifPlatformPath;
    print('Setting LIBHEIF_DIR=$libheifPlatformPath for libheif-sys');
    // Add libheif to PKG_CONFIG_PATH
    final libheifPkgConfigDir = '$libheifPlatformPath/lib/pkgconfig';
    if (Directory(libheifPkgConfigDir).existsSync()) {
      // Prepend libheif to PKG_CONFIG_PATH so it's checked first
      final currentPkgConfigPath = envVars['PKG_CONFIG_PATH'] ?? ffmpegPkgConfigDir;
      // Use the path separator determined earlier
      envVars['PKG_CONFIG_PATH'] = '$libheifPkgConfigDir$pathSeparator$currentPkgConfigPath';
      // Also update PKG_CONFIG_LIBDIR to include libheif
      final currentPkgConfigLibDir = envVars['PKG_CONFIG_LIBDIR'] ?? ffmpegPkgConfigDir;
      envVars['PKG_CONFIG_LIBDIR'] = '$libheifPkgConfigDir$pathSeparator$currentPkgConfigLibDir';

      // For Android cross-compilation, set PKG_CONFIG_SYSROOT_DIR
      if (targetOS == OS.android) {
        final androidNdkHome = Platform.environment['ANDROID_NDK_HOME'];
        if (androidNdkHome != null) {
          // Find the sysroot - try common locations
          // NDK 27+ typically uses darwin-x86_64 even on Apple Silicon (runs via Rosetta)
          final sysrootPath = '$androidNdkHome/toolchains/llvm/prebuilt/darwin-x86_64/sysroot';
          // Check if sysroot exists (might be in different location)
          if (Directory(sysrootPath).existsSync()) {
            envVars['PKG_CONFIG_SYSROOT_DIR'] = sysrootPath;
            print('Set PKG_CONFIG_SYSROOT_DIR for Android: $sysrootPath');
          } else {
            // Try alternative location
            final altSysrootPath = '$androidNdkHome/sysroot';
            if (Directory(altSysrootPath).existsSync()) {
              envVars['PKG_CONFIG_SYSROOT_DIR'] = altSysrootPath;
              print('Set PKG_CONFIG_SYSROOT_DIR for Android (alt): $altSysrootPath');
            } else {
              // Try darwin-arm64 as fallback (for newer NDK versions)
              final fallbackSysrootPath = '$androidNdkHome/toolchains/llvm/prebuilt/darwin-arm64/sysroot';
              if (Directory(fallbackSysrootPath).existsSync()) {
                envVars['PKG_CONFIG_SYSROOT_DIR'] = fallbackSysrootPath;
                print('Set PKG_CONFIG_SYSROOT_DIR for Android (fallback): $fallbackSysrootPath');
              }
            }
          }
        }
      }

      print('Added libheif to PKG_CONFIG_PATH: $libheifPkgConfigDir');
    } else {
      print('Warning: libheif pkg-config directory not found: $libheifPkgConfigDir');
    }
  } else {
    print('Warning: libheif_install not found for platform $targetOS/$effectiveArchitecture');
    print('libheif-sys will try to use embedded libheif or system libheif');
  }

  // Set C compiler flags for iOS builds to ensure __isPlatformVersionAtLeast is available
  if (targetOS == OS.iOS) {
    if (isSimulator) {
      envVars['CC_aarch64-apple-ios-sim'] = 'clang -mios-simulator-version-min=16.0';
      envVars['CFLAGS_aarch64-apple-ios-sim'] = '-mios-simulator-version-min=16.0';
    } else {
      envVars['CC_aarch64-apple-ios'] = 'clang -mios-version-min=16.0';
      envVars['CFLAGS_aarch64-apple-ios'] = '-mios-version-min=16.0';
    }
  }

  // CRITICAL: Change the crate fingerprint by modifying the links name in Cargo.toml
  // This is the proper way to force Cargo to treat builds with FFMPEG_DIR as different
  // from BUILD-enabled builds, ensuring no cached .rlib files with embedded object files are reused
  if (targetOS == OS.android && envVars.containsKey('FFMPEG_DIR')) {
    print('Modifying Cargo.toml to change crate fingerprint...');
    final packageRoot = input.packageRoot;
    final cargoTomlUri = packageRoot.resolve('../third_party/rust-ffmpeg-sys/Cargo.toml');
    final cargoToml = File.fromUri(cargoTomlUri);

    if (cargoToml.existsSync()) {
      try {
        // Read the Cargo.toml file
        String cargoTomlContent = cargoToml.readAsStringSync();

        // Check if links name is already modified
        if (!cargoTomlContent.contains('links = "ffmpeg_prebuilt"')) {
          // Modify the links name to force a different fingerprint
          // This ensures Cargo treats this as a completely different build
          cargoTomlContent = cargoTomlContent.replaceFirst('links   = "ffmpeg"', 'links   = "ffmpeg_prebuilt"');

          // Write the modified Cargo.toml
          cargoToml.writeAsStringSync(cargoTomlContent);
          print('✓ Modified Cargo.toml to use links = "ffmpeg_prebuilt"');
          print('  This changes the crate fingerprint and forces a complete rebuild');
        } else {
          print('Cargo.toml already uses links = "ffmpeg_prebuilt"');
        }
      } catch (e) {
        print('Warning: Failed to modify Cargo.toml: $e');
        // Fallback: delete the target directory
        final nativeAssetsDirUri = packageRoot.resolve('../.dart_tool/hooks_runner/shared/media/build');
        final nativeAssetsDir = Directory.fromUri(nativeAssetsDirUri);
        if (nativeAssetsDir.existsSync()) {
          final buildDirs = nativeAssetsDir.listSync().whereType<Directory>().toList();
          for (final buildDir in buildDirs) {
            final targetDir = '${buildDir.path}/target';
            if (Directory(targetDir).existsSync()) {
              // Map arm to aarch64 since we only build 64-bit libraries
              final targetTriple =
                  (effectiveArchitecture == Architecture.arm64 || effectiveArchitecture == Architecture.arm)
                  ? 'aarch64-linux-android'
                  : 'x86_64-linux-android';
              final targetSpecificDir = '$targetDir/$targetTriple';
              if (Directory(targetSpecificDir).existsSync()) {
                try {
                  Directory(targetSpecificDir).deleteSync(recursive: true);
                  print('✓ Deleted target-specific directory as fallback');
                } catch (e) {
                  print('Warning: Failed to delete target directory: $e');
                }
              }
            }
          }
        }
      }
    }
  }

  // CRITICAL: Delete the entire target directory for the specific target triple
  // This is the most reliable way to force a complete rebuild and ensure
  // no cached .rlib files with embedded object files are reused
  if (targetOS == OS.android && envVars.containsKey('FFMPEG_DIR')) {
    print('Forcing complete clean rebuild by deleting target directory...');
    final packageRoot = input.packageRoot;
    final nativeAssetsDir = outputDirectoryShared;
    if (nativeAssetsDir.existsSync()) {
      final buildDirs = nativeAssetsDir.listSync().whereType<Directory>().toList();
      for (final buildDir in buildDirs) {
        final targetDir = '${buildDir.path}/target';
        if (Directory(targetDir).existsSync()) {
          // CRITICAL: Delete ffmpeg-sys-next build directories first
          // These contain source/build artifacts from previous builds
          final buildSubdir = Directory('$targetDir/release/build');
          if (buildSubdir.existsSync()) {
            final ffmpegBuildDirs = buildSubdir
                .listSync(recursive: false)
                .whereType<Directory>()
                .where((d) => d.path.contains('ffmpeg-sys-next'))
                .toList();
            for (final ffmpegBuildDir in ffmpegBuildDirs) {
              print('Deleting ffmpeg-sys-next build directory: ${ffmpegBuildDir.path}');
              try {
                ffmpegBuildDir.deleteSync(recursive: true);
                print('✓ Deleted ffmpeg-sys-next build directory');
              } catch (e) {
                print('Warning: Failed to delete ffmpeg-sys-next build directory: $e');
              }
            }
          }

          // Determine the target triple
          // Map arm to aarch64 since we only build 64-bit libraries
          final targetTriple =
              (effectiveArchitecture == Architecture.arm64 || effectiveArchitecture == Architecture.arm)
              ? 'aarch64-linux-android'
              : 'x86_64-linux-android';
          final targetSpecificDir = '$targetDir/$targetTriple';

          // Delete the entire target-specific directory to force a complete rebuild
          // This ensures no cached .rlib files with embedded object files are reused
          if (Directory(targetSpecificDir).existsSync()) {
            print('Deleting target-specific directory: $targetSpecificDir');
            try {
              Directory(targetSpecificDir).deleteSync(recursive: true);
              print('✓ Deleted target-specific directory to force complete rebuild');
            } catch (e) {
              print('Warning: Failed to delete target directory: $e');
              // Fallback: delete just the .rlib files and build directories
              final rlibFiles = Directory(targetDir)
                  .listSync(recursive: true)
                  .whereType<File>()
                  .where((f) => f.path.contains('libffmpeg_sys_next') && f.path.endsWith('.rlib'))
                  .toList();
              for (final rlibFile in rlibFiles) {
                rlibFile.deleteSync();
              }
              final cachedBuildDirs = Directory(targetDir)
                  .listSync(recursive: true)
                  .whereType<Directory>()
                  .where((d) => d.path.contains('ffmpeg-sys-next'))
                  .toList();
              for (final cachedBuildDir in cachedBuildDirs) {
                try {
                  cachedBuildDir.deleteSync(recursive: true);
                } catch (e) {
                  // Ignore errors
                }
              }
              if (rlibFiles.isNotEmpty || cachedBuildDirs.isNotEmpty) {
                print(
                  '✓ Manually deleted ${rlibFiles.length} .rlib file(s) and ${cachedBuildDirs.length} build directory(ies)',
                );
              }
            }
          }
        }
      }
    }
  }

  // CRITICAL: Delete any existing .rlib files and fingerprint files immediately before building
  // This ensures Cargo doesn't reuse cached .rlib files with embedded object files
  if (targetOS == OS.android && envVars.containsKey('FFMPEG_DIR')) {
    print('Deleting any existing .rlib files and fingerprints before build...');
    final packageRoot = input.packageRoot;
    final nativeAssetsDir = outputDirectoryShared;
    if (nativeAssetsDir.existsSync()) {
      final buildDirs = nativeAssetsDir.listSync().whereType<Directory>().toList();
      for (final buildDir in buildDirs) {
        final targetDir = '${buildDir.path}/target';
        if (Directory(targetDir).existsSync()) {
          // Delete .rlib files
          final rlibFiles = Directory(targetDir)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.contains('libffmpeg_sys_next') && f.path.endsWith('.rlib'))
              .toList();
          for (final rlibFile in rlibFiles) {
            try {
              rlibFile.deleteSync();
              print('✓ Deleted .rlib file before build: ${rlibFile.path}');
            } catch (e) {
              print('Warning: Failed to delete .rlib file: $e');
            }
          }

          // Delete fingerprint files to force complete rebuild
          final fingerprintDirs = Directory(
            targetDir,
          ).listSync(recursive: true).whereType<Directory>().where((d) => d.path.endsWith('.fingerprint')).toList();
          for (final fingerprintDir in fingerprintDirs) {
            final fingerprintFiles = fingerprintDir
                .listSync(recursive: false)
                .whereType<File>()
                .where((f) => f.path.contains('ffmpeg-sys-next'))
                .toList();
            for (final fingerprintFile in fingerprintFiles) {
              try {
                fingerprintFile.deleteSync();
                print('✓ Deleted fingerprint file: ${fingerprintFile.path}');
              } catch (e) {
                // Ignore errors
              }
            }
          }
        }
      }
    }
  }

  // CRITICAL: Override target for Android ARM builds to use aarch64 instead of armv7
  // We only build 64-bit libraries, so map 32-bit ARM requests to 64-bit
  if (targetOS == OS.android && effectiveArchitecture == Architecture.arm) {
    // Force Rust to build for aarch64-linux-android instead of armv7-linux-androideabi
    envVars['CARGO_BUILD_TARGET'] = 'aarch64-linux-android';
    print('INFO: Overriding Rust target from armv7 to aarch64-linux-android (we only have 64-bit libraries)');
  }

  // For Windows builds, ensure MinGW DLLs are available BEFORE building
  // This way native_toolchain_rust can pick them up when packaging
  if (targetOS == OS.windows) {
    final msys2Root = envVars['MSYS2_ROOT'] ?? Platform.environment['MSYS2_ROOT'] ?? r'C:\msys64';
    final mingwBin = '$msys2Root\\mingw64\\bin';
    final mingwDlls = ['libgcc_s_seh-1.dll', 'libwinpthread-1.dll'];

    final packageRoot = input.packageRoot;
    final nativeAssetsDir = outputDirectoryShared;

    if (nativeAssetsDir.existsSync()) {
      final buildDirs = nativeAssetsDir.listSync().whereType<Directory>().toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

      if (buildDirs.isNotEmpty) {
        final buildDir = buildDirs.first;
        final targetTriple = 'x86_64-pc-windows-msvc';
        final libDir = Directory('${buildDir.path}/target/$targetTriple/release');
        // Pre-copy DLLs if directory exists (from previous build)
        if (libDir.existsSync()) {
          for (final dllName in mingwDlls) {
            final dllFile = File('$mingwBin\\$dllName');
            if (dllFile.existsSync()) {
              final destFile = File('${libDir.path}/$dllName');
              dllFile.copySync(destFile.path);
              print('✓ Pre-copied MinGW runtime DLL: $dllName (will be included in native assets)');
            }
          }
        }
      }
    }
  }

  final rustBuilder = RustBuilder(
    assetName: assetName,
    cratePath: '../native',
    buildMode: input.config.linkingEnabled ? BuildMode.release : BuildMode.debug,
    enableDefaultFeatures: true,
    extraCargoEnvironmentVariables: envVars,
  );

  final Logger logger = Logger.detached('MediaBuilder');
  logger.level = Level.CONFIG;
  logger.onRecord.listen(
    (LogRecord record) => developer.log('${record.level.name}: ${record.time}: ${record.message}'),
  );

  // Run the Rust build with retry logic
  // If build fails due to incompatible .rlib files, clean them and retry once
  int maxRetries = 1;
  for (int attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      await rustBuilder.run(input: input, output: output, logger: logger);
      // Build succeeded, break out of retry loop

      // For Windows builds, copy MinGW runtime DLLs immediately after build
      // This ensures they're available when native_toolchain_rust processes the output
      if (targetOS == OS.windows) {
        // Use the same MSYS2_ROOT that was set in envVars above
        final msys2Root = envVars['MSYS2_ROOT'] ?? Platform.environment['MSYS2_ROOT'] ?? r'C:\msys64';
        final mingwBin = '$msys2Root\\mingw64\\bin';

        // MinGW runtime DLLs required by FFmpeg
        final mingwDlls = ['libgcc_s_seh-1.dll', 'libwinpthread-1.dll'];

        // Find and copy each DLL to the target directory AND to native assets
        final packageRoot = input.packageRoot;
        // Use Uri.resolve to properly handle path construction and avoid double slashes
        final nativeAssetsDirUri = packageRoot.resolve('../.dart_tool/hooks_runner/shared/media/build');
        final nativeAssetsDir = Directory.fromUri(nativeAssetsDirUri);

        if (nativeAssetsDir.existsSync()) {
          // Find the most recent build directory
          final buildDirs = nativeAssetsDir.listSync().whereType<Directory>().toList()
            ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

          if (buildDirs.isNotEmpty) {
            final buildDir = buildDirs.first;
            // For Windows MSVC, the target triple is x86_64-pc-windows-msvc
            final targetTriple = 'x86_64-pc-windows-msvc';
            final libDir = Directory('${buildDir.path}/target/$targetTriple/release');
            if (libDir.existsSync()) {
              // Check if media.dll exists (build completed)
              final mediaDll = File('${libDir.path}/media.dll');
              if (mediaDll.existsSync()) {
                for (final dllName in mingwDlls) {
                  final dllFile = File('$mingwBin\\$dllName');
                  if (dllFile.existsSync()) {
                    // Copy to Rust build target directory
                    // native_toolchain_rust should pick up all DLLs in this directory
                    final destFile = File('${libDir.path}/$dllName');
                    // Always copy to ensure it's up to date
                    dllFile.copySync(destFile.path);
                    print('✓ Copied MinGW runtime DLL: $dllName to ${destFile.path}');
                    print('  This DLL should be bundled with the plugin DLL in the native assets');

                    // Also copy to any existing native_assets directories immediately
                    // This ensures they're available even if native_toolchain_rust doesn't pick them up
                    final packageRootDir = Directory.fromUri(packageRoot);
                    if (packageRootDir.existsSync()) {
                      final parentUri = packageRoot.resolve('..');
                      final potentialPaths = [
                        parentUri.resolve('example/build/native_assets/windows'),
                        parentUri.resolve('build/native_assets/windows'),
                      ];

                      for (final potentialPath in potentialPaths) {
                        final nativeAssetsDir = Directory.fromUri(potentialPath);
                        if (nativeAssetsDir.existsSync()) {
                          final outputDll = File('${nativeAssetsDir.path}/$dllName');
                          if (!outputDll.existsSync() ||
                              dllFile.lastModifiedSync().isAfter(outputDll.lastModifiedSync())) {
                            dllFile.copySync(outputDll.path);
                            print('✓ Also copied to native assets: ${outputDll.path}');
                          }
                        }
                      }
                    }
                  } else {
                    print('Warning: MinGW runtime DLL not found: $dllName at $mingwBin\\$dllName');
                  }
                }
              } else {
                print('Warning: media.dll not found in ${libDir.path}, skipping DLL copy');
              }
            }
          }
        }
      }

      break;
    } catch (e) {
      final errorMsg = e.toString();
      // Check if the error is related to incompatible .rlib files
      if (errorMsg.contains('incompatible') &&
          errorMsg.contains('.rlib') &&
          attempt < maxRetries &&
          targetOS == OS.android &&
          envVars.containsKey('FFMPEG_DIR')) {
        print('Build failed due to incompatible .rlib files. Cleaning and retrying...');
        // First, try to clean the .rlib files
        await _cleanRlibFiles(input, targetOS, envVars);
        // Also delete the .rlib files completely to force a fresh rebuild
        await _deleteRlibFiles(input, targetOS, envVars);
        print('Cleaned and deleted .rlib files, retrying build (attempt ${attempt + 2}/${maxRetries + 1})...');
        // Continue to retry
        continue;
      }
      // If not a retryable error or max retries reached, rethrow
      rethrow;
    }
  }

  // After build completes, copy MinGW DLLs to native assets directory
  // native_toolchain_rust may not automatically include additional DLLs,
  // so we copy them directly to where Flutter will find them
  if (targetOS == OS.windows) {
    final msys2Root = envVars['MSYS2_ROOT'] ?? Platform.environment['MSYS2_ROOT'] ?? r'C:\msys64';
    final mingwBin = '$msys2Root\\mingw64\\bin';
    final mingwDlls = ['libgcc_s_seh-1.dll', 'libwinpthread-1.dll'];

    final packageRoot = input.packageRoot;

    // Find where native_toolchain_rust placed the DLL
    // It should be in .dart_tool/hooks_runner/shared/media/build/*/target/x86_64-pc-windows-msvc/release/
    final nativeAssetsDirUri = packageRoot.resolve('../.dart_tool/hooks_runner/shared/media/build');
    final nativeAssetsDir = Directory.fromUri(nativeAssetsDirUri);

    if (nativeAssetsDir.existsSync()) {
      final buildDirs = nativeAssetsDir.listSync().whereType<Directory>().toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

      if (buildDirs.isNotEmpty) {
        final buildDir = buildDirs.first;
        final targetTriple = 'x86_64-pc-windows-msvc';
        final libDir = Directory('${buildDir.path}/target/$targetTriple/release');

        // Check if media.dll exists (build completed successfully)
        final mediaDll = File('${libDir.path}/media.dll');
        if (mediaDll.existsSync()) {
          // Ensure MinGW DLLs are in the same directory as media.dll
          // native_toolchain_rust should pick them up when packaging
          for (final dllName in mingwDlls) {
            final dllFile = File('$mingwBin\\$dllName');
            if (dllFile.existsSync()) {
              final destFile = File('${libDir.path}/$dllName');
              // Copy if not already there or if source is newer
              if (!destFile.existsSync() || dllFile.lastModifiedSync().isAfter(destFile.lastModifiedSync())) {
                dllFile.copySync(destFile.path);
                print('✓ Ensured MinGW runtime DLL is present: $dllName at ${destFile.path}');
              }
            } else {
              print('WARNING: MinGW DLL not found at source: $mingwBin\\$dllName');
            }
          }
        }
      }
    }
  }

  // Clean .rlib files again after build completes (in case new ones were created)
  if (targetOS == OS.android && envVars.containsKey('FFMPEG_DIR')) {
    final packageRoot = input.packageRoot;
    final nativeAssetsDir = Directory('$packageRoot/../.dart_tool/hooks_runner/shared/media/build');
    if (nativeAssetsDir.existsSync()) {
      final buildDirs = nativeAssetsDir.listSync().whereType<Directory>().toList();
      for (final buildDir in buildDirs) {
        final targetDir = '${buildDir.path}/target';
        if (Directory(targetDir).existsSync()) {
          final scriptDir = path.dirname(Platform.script.toFilePath());
          final cleanScript = path.join(scriptDir, '..', 'scripts', 'clean_rlib_immediate.sh');
          final cleanScriptFile = File(cleanScript);
          if (cleanScriptFile.existsSync()) {
            final result = await Process.run('bash', [cleanScript, targetDir], runInShell: true);
            if (result.exitCode == 0) {
              print('Cleaned .rlib files after build');
            }
          }
        }
      }
    }
  }

  // CRITICAL: Clean incompatible object files from rust-ffmpeg-sys .rlib files AFTER build
  // This is needed because Cargo caches .rlib files that contain object files
  // from previous BUILD-enabled builds, even when FFMPEG_DIR is set.
  if (targetOS == OS.android && envVars.containsKey('FFMPEG_DIR')) {
    print('Cleaning .rlib files after build...');
    final packageRoot = input.packageRoot;
    final nativeAssetsDir = Directory('$packageRoot/../.dart_tool/hooks_runner/shared/media/build');
    if (nativeAssetsDir.existsSync()) {
      final buildDirs = nativeAssetsDir.listSync().whereType<Directory>().toList();
      for (final buildDir in buildDirs) {
        final targetDir = '${buildDir.path}/target';
        if (Directory(targetDir).existsSync()) {
          // Find all rust-ffmpeg-sys .rlib files
          final rlibFiles = Directory(targetDir)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.contains('libffmpeg_sys_next') && f.path.endsWith('.rlib'))
              .toList();

          for (final rlibFile in rlibFiles) {
            print('Cleaning .rlib file: ${rlibFile.path}');
            try {
              // Extract, remove .o files, and repackage
              final tempDir = Directory.systemTemp.createTempSync('clean_rlib_');
              try {
                final result = await Process.run(
                  'ar',
                  ['x', rlibFile.path],
                  workingDirectory: tempDir.path,
                  runInShell: false,
                );
                if (result.exitCode == 0) {
                  // Remove all .o files
                  final oFiles = tempDir.listSync().whereType<File>().where((f) => f.path.endsWith('.o'));
                  for (final oFile in oFiles) {
                    oFile.deleteSync();
                  }
                  // Repackage the .rlib
                  final files = tempDir.listSync().whereType<File>().map((f) => path.basename(f.path)).toList();
                  if (files.isNotEmpty) {
                    final arResult = await Process.run(
                      'ar',
                      ['rcs', rlibFile.path, ...files],
                      workingDirectory: tempDir.path,
                      runInShell: false,
                    );
                    if (arResult.exitCode == 0) {
                      print('✓ Cleaned .rlib file: ${rlibFile.path}');
                    } else {
                      print('Warning: Failed to repackage .rlib: ${arResult.stderr}');
                    }
                  }
                }
              } finally {
                tempDir.deleteSync(recursive: true);
              }
            } catch (e) {
              print('Warning: Failed to clean .rlib file ${rlibFile.path}: $e');
            }
          }
        }
      }
    }
  }

  // For Android builds using libheif, copy libc++_shared.so from NDK to native assets
  // This ensures the shared library is bundled with the APK
  if (targetOS == OS.android && libheifPlatformPath != null) {
    final androidNdkHome = Platform.environment['ANDROID_NDK_HOME'];
    if (androidNdkHome != null) {
      // Determine the correct architecture for the library path
      final ndkArch = effectiveArchitecture == Architecture.arm64 ? 'aarch64' : 'x86_64';

      // Try common NDK paths for libc++_shared.so
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

      if (cxxSharedFile != null) {
        // Copy libc++_shared.so to the same directory as libmedia.so
        // This ensures it gets bundled with the APK alongside libmedia.so
        // Flutter native assets will pick up all .so files in the target/release directory
        final packageRoot = input.packageRoot;
        final nativeAssetsDir = Directory('$packageRoot/../.dart_tool/hooks_runner/shared/media/build');

        if (nativeAssetsDir.existsSync()) {
          // Find the most recent build directory
          final buildDirs = nativeAssetsDir.listSync().whereType<Directory>().toList()
            ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

          if (buildDirs.isNotEmpty) {
            final buildDir = buildDirs.first;
            // Copy to the same directory where libmedia.so is built
            // This is where Flutter native assets will find and bundle it
            // Map arm to aarch64 since we only build 64-bit libraries
            final targetTriple =
                (effectiveArchitecture == Architecture.arm64 || effectiveArchitecture == Architecture.arm)
                ? 'aarch64-linux-android'
                : 'x86_64-linux-android';
            final libDir = Directory('${buildDir.path}/target/$targetTriple/release');
            if (libDir.existsSync()) {
              final destFile = File('${libDir.path}/libc++_shared.so');
              cxxSharedFile.copySync(destFile.path);
              print('✓ Copied libc++_shared.so to: ${destFile.path}');
              print('  This library will be bundled with libmedia.so in the APK');
            } else {
              print('Warning: Target directory not found: ${libDir.path}');
            }
          }
        }
      } else {
        print('Warning: libc++_shared.so not found in NDK. Library may not be bundled with APK.');
      }
    }
  }
}

/// Helper function to clean .rlib files by extracting, removing .o files, and repackaging
/// Uses Python script for more robust archive manipulation
Future<void> _cleanRlibFiles(BuildInput input, OS targetOS, Map<String, String> envVars) async {
  if (targetOS != OS.android || !envVars.containsKey('FFMPEG_DIR')) {
    return;
  }

  // Try using Python script first (more robust)
  final packageRoot = input.packageRoot;
  final scriptPath = packageRoot.resolve('../scripts/support/clean_rlib_openh264.py');
  final scriptFile = File.fromUri(scriptPath);

  if (scriptFile.existsSync()) {
    print('Using Python script to clean .rlib files...');
    final nativeAssetsDir = Directory('$packageRoot/../.dart_tool/hooks_runner/shared/media/build');
    if (nativeAssetsDir.existsSync()) {
      final rlibFiles = nativeAssetsDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.contains('libffmpeg_sys_next') && f.path.endsWith('.rlib'))
          .toList();

      for (final rlibFile in rlibFiles) {
        try {
          final result = await Process.run('python3', [scriptFile.path, rlibFile.path], runInShell: true);
          if (result.exitCode == 0) {
            print('✓ Cleaned ${rlibFile.path}');
          } else {
            print('⚠ Failed to clean ${rlibFile.path}: ${result.stderr}');
          }
        } catch (e) {
          print('⚠ Error cleaning ${rlibFile.path}: $e');
        }
      }
      return; // Python script handled it
    }
  }

  // Fallback to original method if Python script doesn't exist
  final nativeAssetsDir = Directory('$packageRoot/../.dart_tool/hooks_runner/shared/media/build');
  if (!nativeAssetsDir.existsSync()) {
    return;
  }

  final buildDirs = nativeAssetsDir.listSync().whereType<Directory>().toList();
  for (final buildDir in buildDirs) {
    final targetDir = '${buildDir.path}/target';
    if (!Directory(targetDir).existsSync()) {
      continue;
    }

    // Find all rust-ffmpeg-sys .rlib files
    final rlibFiles = Directory(targetDir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.contains('libffmpeg_sys_next') && f.path.endsWith('.rlib'))
        .toList();

    for (final rlibFile in rlibFiles) {
      print('Cleaning .rlib file: ${rlibFile.path}');
      // Extract, remove .o files, and repackage
      final tempDir = Directory.systemTemp.createTempSync('clean_rlib_');
      try {
        final result = await Process.run('ar', ['x', rlibFile.path], workingDirectory: tempDir.path, runInShell: false);
        if (result.exitCode == 0) {
          // Remove all .o files
          final oFiles = tempDir.listSync().whereType<File>().where((f) => f.path.endsWith('.o'));
          int removedCount = 0;
          for (final oFile in oFiles) {
            oFile.deleteSync();
            removedCount++;
          }
          if (removedCount > 0) {
            print('  Removed $removedCount .o file(s) from .rlib');
          }
          // Repackage the .rlib
          final files = tempDir.listSync().whereType<File>().map((f) => path.basename(f.path)).toList();
          if (files.isNotEmpty) {
            final arResult = await Process.run(
              'ar',
              ['rcs', rlibFile.path, ...files],
              workingDirectory: tempDir.path,
              runInShell: false,
            );
            if (arResult.exitCode == 0) {
              print('✓ Cleaned .rlib file: ${rlibFile.path}');
            } else {
              print('Warning: Failed to repackage .rlib: ${arResult.stderr}');
            }
          }
        } else {
          print('Warning: Failed to extract .rlib: ${result.stderr}');
        }
      } catch (e) {
        print('Error cleaning .rlib file ${rlibFile.path}: $e');
      } finally {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (e) {
          // Ignore cleanup errors
        }
      }
    }
  }
}

/// Helper function to delete .rlib files completely
Future<void> _deleteRlibFiles(BuildInput input, OS targetOS, Map<String, String> envVars) async {
  if (targetOS != OS.android || !envVars.containsKey('FFMPEG_DIR')) {
    return;
  }

  final packageRoot = input.packageRoot;
  // Fix path: packageRoot is already 'media/', so '../' gives us the project root
  final nativeAssetsDirUri = packageRoot.resolve('../.dart_tool/hooks_runner/shared/media/build');
  final nativeAssetsDir = Directory.fromUri(nativeAssetsDirUri);
  if (!nativeAssetsDir.existsSync()) {
    return;
  }

  final buildDirs = nativeAssetsDir.listSync().whereType<Directory>().toList();
  for (final buildDir in buildDirs) {
    final targetDir = '${buildDir.path}/target';
    if (!Directory(targetDir).existsSync()) {
      continue;
    }

    // Find and delete all rust-ffmpeg-sys .rlib files
    final rlibFiles = Directory(targetDir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.contains('libffmpeg_sys_next') && f.path.endsWith('.rlib'))
        .toList();

    for (final rlibFile in rlibFiles) {
      print('Deleting .rlib file: ${rlibFile.path}');
      try {
        rlibFile.deleteSync();
        print('✓ Deleted .rlib file: ${rlibFile.path}');
      } catch (e) {
        print('Error deleting .rlib file ${rlibFile.path}: $e');
      }
    }
  }
}
