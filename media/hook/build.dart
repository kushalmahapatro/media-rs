import 'dart:convert';
import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';
import 'package:path/path.dart';

import 'build_environment.dart';

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

String? _getEnv(Map<String, String> systemEnv, String key) {
  return Platform.environment[key] ?? systemEnv[key];
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
  final ffmpegDir = _resolveFfmpegDir(input, targetOS, effectiveArchitecture, iOSSdk, systemEnv);
  final libheifPath = _resolveLibheifDir(input, targetOS, effectiveArchitecture, isSimulator, systemEnv);
  final openh264Path = _resolveOpenh264Dir(input, targetOS, effectiveArchitecture, systemEnv);

  // Setup environment variables
  final envVars = _buildEnvVars(
    ffmpegDir: ffmpegDir,
    targetOS: targetOS,
    effectiveArchitecture: effectiveArchitecture,
    isSimulator: isSimulator,
    libheifPath: libheifPath,
    openh264Path: openh264Path,
    systemEnv: systemEnv,
  );

  // Platform-specific setup
  if (targetOS == OS.windows) {
    _setupWindows(envVars, input, systemEnv);
  }

  String? androidNdkHome;
  if (targetOS == OS.android) {
    androidNdkHome = await _setupAndroid(envVars, input, effectiveArchitecture, systemEnv);
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
    _copyWindowsDlls(input, output, envVars);
  }
  if (targetOS == OS.android && libheifPath != null && androidNdkHome != null) {
    _copyAndroidLibcxx(input, output, effectiveArchitecture, androidNdkHome, assetName);
  }
}

String _getPrettyJSONString(jsonObject) {
  var encoder = new JsonEncoder.withIndent("     ");
  return encoder.convert(jsonObject);
}

String _resolveFfmpegDir(
  BuildInput input,
  OS targetOS,
  Architecture effectiveArchitecture,
  dynamic iOSSdk,
  Map<String, String> systemEnv,
) {
  final envDir = _getEnv(systemEnv, 'MEDIA_RS_FFMPEG_DIR');
  if (envDir != null) return envDir;

  final subDir = _getFfmpegSubDir(targetOS, effectiveArchitecture, iOSSdk);
  final uri = input.packageRoot.resolve('../third_party/ffmpeg_install/$subDir');
  final dir = File.fromUri(uri).path;

  if (!Directory(dir).existsSync()) {
    throw Exception("FFmpeg install not found at $dir for $targetOS/$effectiveArchitecture");
  }
  return dir;
}

String _getFfmpegSubDir(OS targetOS, Architecture arch, dynamic iOSSdk) {
  switch (targetOS) {
    case OS.macOS:
      return '';
    case OS.iOS:
      if (iOSSdk?.type == 'iphonesimulator') {
        return arch == Architecture.x64 ? 'ios/simulator_x64' : 'ios/simulator_arm64';
      }
      return arch == Architecture.x64 ? 'ios/simulator_x64' : 'ios/device';
    case OS.android:
      if (arch == Architecture.arm64 || arch == Architecture.arm) {
        return 'android/arm64-v8a';
      }
      return 'android/x86_64';
    case OS.linux:
      return arch == Architecture.arm64 ? 'linux/arm64' : 'linux/x86_64';
    case OS.windows:
      return 'windows/x86_64';
    default:
      throw Exception('Unsupported OS: $targetOS');
  }
}

String? _resolveLibheifDir(
  BuildInput input,
  OS targetOS,
  Architecture effectiveArchitecture,
  bool isSimulator,
  Map<String, String> systemEnv,
) {
  final envDir = _getEnv(systemEnv, 'MEDIA_RS_LIBHEIF_DIR');
  if (envDir != null && Directory(envDir).existsSync()) return envDir;

  final packageRoot = input.packageRoot;
  String? path;

  switch (targetOS) {
    case OS.macOS:
      path = File.fromUri(packageRoot.resolve('../third_party/libheif_install/macos/universal')).path;
      break;
    case OS.iOS:
      final platform = isSimulator ? 'iphonesimulator' : 'iphoneos';
      final arch = effectiveArchitecture == Architecture.arm64 ? 'arm64' : 'x86_64';
      path = File.fromUri(packageRoot.resolve('../third_party/libheif_install/ios/$platform/$arch')).path;
      break;
    case OS.android:
      final abi = (effectiveArchitecture == Architecture.arm64 || effectiveArchitecture == Architecture.arm)
          ? 'arm64-v8a'
          : 'x86_64';
      path = File.fromUri(packageRoot.resolve('../third_party/libheif_install/android/$abi')).path;
      break;
    case OS.linux:
      final arch = effectiveArchitecture == Architecture.arm64 ? 'arm64' : 'x86_64';
      path = File.fromUri(packageRoot.resolve('../third_party/libheif_install/linux/$arch')).path;
      break;
    case OS.windows:
      path = File.fromUri(packageRoot.resolve('../third_party/libheif_install/windows/x86_64')).path;
      break;
    default:
      return null;
  }

  return Directory(path).existsSync() ? path : null;
}

String? _resolveOpenh264Dir(
  BuildInput input,
  OS targetOS,
  Architecture effectiveArchitecture,
  Map<String, String> systemEnv,
) {
  final envDir = _getEnv(systemEnv, 'MEDIA_RS_OPENH264_DIR');
  if (envDir != null && Directory(envDir).existsSync()) return envDir;

  final packageRoot = input.packageRoot;
  String? path;

  switch (targetOS) {
    case OS.macOS:
      path = File.fromUri(packageRoot.resolve('../third_party/openh264_build_arm64')).path;
      break;
    case OS.android:
      final abi = (effectiveArchitecture == Architecture.arm64 || effectiveArchitecture == Architecture.arm)
          ? 'arm64-v8a'
          : 'x86_64';
      path = File.fromUri(packageRoot.resolve('../third_party/openh264_install/android/$abi')).path;
      if (!Directory(path).existsSync()) {
        path = File.fromUri(packageRoot.resolve('../third_party/openh264_build_android_$abi')).path;
      }
      break;
    case OS.linux:
      final arch = effectiveArchitecture == Architecture.arm64 ? 'arm64' : 'x86_64';
      path = File.fromUri(packageRoot.resolve('../third_party/openh264_install/linux/$arch')).path;
      break;
    case OS.windows:
      path = File.fromUri(packageRoot.resolve('../third_party/openh264_install/windows/x86_64')).path;
      break;
    default:
      return null;
  }

  return Directory(path).existsSync() ? path : null;
}

Map<String, String> _buildEnvVars({
  required String ffmpegDir,
  required OS targetOS,
  required Architecture effectiveArchitecture,
  required bool isSimulator,
  String? libheifPath,
  String? openh264Path,
  required Map<String, String> systemEnv,
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
        final androidNdkHome = _getEnv(systemEnv, 'ANDROID_NDK_HOME');
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

void _setupWindows(Map<String, String> envVars, BuildInput input, Map<String, String> systemEnv) {
  final msys2Root = _getEnv(systemEnv, 'MSYS2_ROOT') ?? r'C:\msys64';
  final mingwBin = '$msys2Root\\mingw64\\bin';
  final currentPath = _getEnv(systemEnv, 'PATH') ?? '';

  envVars['PKG_CONFIG'] = 'pkg-config';
  envVars['PKG_CONFIG_ALLOW_SYSTEM_LIBS'] = '1';
  envVars['MSYS2_ROOT'] = msys2Root;
  envVars['PATH'] = '$mingwBin;$currentPath';
  envVars['VCPKG_ROOT'] = r'C:\nonexistent_vcpkg_path';

  // Find LLVM/Clang
  final vsInstallDir = _getEnv(systemEnv, 'VSINSTALLDIR');
  final possibleClangPaths = <String>[
    if (_getEnv(systemEnv, 'LIBCLANG_PATH') != null) _getEnv(systemEnv, 'LIBCLANG_PATH')!,
    r'C:\Program Files\LLVM\bin',
    r'C:\Program Files (x86)\LLVM\bin',
    r'C:\msys64\mingw64\bin',
    if (vsInstallDir != null) '$vsInstallDir\\VC\\Tools\\Llvm\\x64\\bin',
  ].where((p) => Directory(p).existsSync()).toList();

  String? clangPath;
  for (final p in possibleClangPaths) {
    if (File('$p\\clang.dll').existsSync() || File('$p\\libclang.dll').existsSync()) {
      clangPath = p;
      break;
    }
  }

  if (clangPath != null) {
    envVars['LIBCLANG_PATH'] = clangPath;
    envVars['PATH'] = '$clangPath;$mingwBin;$currentPath';
    logger.info('Windows: Found LLVM/Clang at $clangPath');
  } else {
    final installScript = File(input.packageRoot.resolve('../scripts/support/install_llvm_windows.bat').toFilePath());
    if (installScript.existsSync()) {
      logger.info('Windows: LLVM/Clang not found. Run: ${installScript.path}');
    }
    logger.warning('Windows: LLVM/Clang not found. bindgen will fail.');
  }
}

Future<Map<String, String>> _getShellEnvironment(BuildInput input) async {
  final buildEnvironmentFactory = const BuildEnvironmentFactory();
  final envVars = buildEnvironmentFactory.createBuildEnvVars(input.config.code);
  print('envVars: ${_getPrettyJSONString(envVars)}');
  return envVars;
}

Future<String?> _setupAndroid(
  Map<String, String> envVars,
  BuildInput input,
  Architecture effectiveArchitecture,
  Map<String, String> systemEnv,
) async {
  // Modify Cargo.toml to change crate fingerprint
  final cargoTomlUri = input.packageRoot.resolve('../third_party/rust-ffmpeg-sys/Cargo.toml');
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

  String? androidNdkHome;

  final compiler = input.config.code.cCompiler?.compiler;
  if (compiler != null) {
    androidNdkHome = compiler.path.split('/toolchains').first;
    logger.info('Extracted Android NDK from build system config: $androidNdkHome');
  } else {
    logger.warning('C compiler not found in build system config');
    return null;
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
      final apiLevel = _getEnv(systemEnv, 'ANDROID_API_LEVEL') ?? '21';

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
  _cleanAndroidTarget(input, effectiveArchitecture);
  return androidNdkHome;
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

void _copyWindowsDlls(BuildInput input, BuildOutputBuilder output, Map<String, String> envVars) {
  final msys2Root = envVars['MSYS2_ROOT'] ?? r'C:\msys64';
  final mingwBin = '$msys2Root\\mingw64\\bin';
  final mingwDlls = ['libgcc_s_seh-1.dll', 'libwinpthread-1.dll'];

  final nativeAssetsDir = Directory.fromUri(input.outputDirectory);
  if (!nativeAssetsDir.existsSync()) return;

  final buildDirs = nativeAssetsDir.listSync().whereType<Directory>().toList()
    ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

  if (buildDirs.isEmpty) return;

  final buildDir = buildDirs.first;
  final libDir = Directory('${buildDir.path}/target/x86_64-pc-windows-msvc/release');
  if (!libDir.existsSync()) return;

  final mediaDll = File('${libDir.path}/media.dll');
  if (!mediaDll.existsSync()) return;

  for (final dllName in mingwDlls) {
    final dllFile = File('$mingwBin\\$dllName');
    if (dllFile.existsSync()) {
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: dllName,
          linkMode: DynamicLoadingBundled(),
          file: toUri(dllFile.path),
        ),
        routing: ToAppBundle(),
      );
      // final destFile = File('${libDir.path}/$dllName');
      // dllFile.copySync(destFile.path);
      // print('✓ Copied MinGW runtime DLL: $dllName');
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
