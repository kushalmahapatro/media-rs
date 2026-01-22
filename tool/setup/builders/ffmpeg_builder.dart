// FFmpeg builder
import 'dart:io';
import 'package:path/path.dart' as path;
import '../platforms/platform.dart';
import '../build_systems/build_system.dart';
import '../utils/download.dart';
import '../utils/file_ops.dart';
import '../utils/process.dart';
import 'base_builder.dart';

class FFmpegBuilder extends BaseBuilder {
  static const String version = '8.0.1';
  static const String sourceName = 'ffmpeg-$version';
  static const String sourceUrl = 'https://ffmpeg.org/releases/ffmpeg-$version.tar.bz2';

  FFmpegBuilder(super.projectRoot);

  @override
  String getName() => 'ffmpeg';

  @override
  String getLibraryName() => 'libavcodec.a';

  @override
  Future<void> downloadSource() async {
    final sourceDir = getSourceDir(sourceName);
    final checkFile = path.join(sourceDir, 'ffbuild', 'common.mak');

    if (await FileOps.exists(checkFile)) {
      print('FFmpeg source already downloaded');
      return;
    }

    // Remove incomplete download
    if (await Directory(sourceDir).exists()) {
      print('Removing incomplete FFmpeg source...');
      await FileOps.removeIfExists(sourceDir);
    }

    await Downloader.downloadAndExtract(
      sourceUrl,
      sourcesDir,
      isBzip2: true,
      onProgress: (received, total) {
        if (total > 0) {
          final percent = (received / total * 100).toStringAsFixed(1);
          stdout.write('\rDownloading: $percent%');
        }
      },
    );
    print('');
  }

  @override
  Future<void> buildForPlatform(PlatformInfo platform, {bool skipOpenH264 = false}) async {
    switch (platform.platform) {
      case BuildPlatform.macos:
        await _buildMacOS(platform, skipOpenH264: skipOpenH264);
        break;
      case BuildPlatform.ios:
        await _buildIOS(platform, skipOpenH264: skipOpenH264);
        break;
      case BuildPlatform.android:
        await _buildAndroid(platform, skipOpenH264: skipOpenH264);
        break;
      case BuildPlatform.linux:
        await _buildLinux(platform, skipOpenH264: skipOpenH264);
        break;
      case BuildPlatform.windows:
        await _buildWindows(platform, skipOpenH264: skipOpenH264);
        break;
    }
  }

  Future<void> _buildMacOS(PlatformInfo platform, {bool skipOpenH264 = false}) async {
    final archs = [Architecture.arm64, Architecture.x86_64];
    final installDirs = <String>[];
    final libNames = ['libavcodec', 'libavformat', 'libavutil', 'libswresample', 'libswscale'];

    for (final arch in archs) {
      print('Building FFmpeg for macOS $arch...');
      final sourceDir = getSourceDir(sourceName);
      // For FFmpeg, we build in-tree (in the source directory) and use --prefix
      // to control where the artifacts are installed for each arch.
      final archInstallDir = path.join(generatedDir, 'ffmpeg_build_${arch.name}');
      await FileOps.ensureDirectory(archInstallDir);

      // CRITICAL: Clean before each architecture build to avoid mixing architectures
      print('Cleaning previous build artifacts...');
      try {
        await runProcessStreaming('make', ['distclean'], workingDirectory: sourceDir);
        // Ignore errors - distclean may fail if nothing to clean
      } catch (e) {
        // Ignore
      }

      final configureArgs = await _getMacOSConfigureArgs(arch, archInstallDir, skipOpenH264);

      final buildSystem = AutotoolsBuildSystem(configureArgs: configureArgs);
      await buildSystem.configure(
        sourceDir: sourceDir,
        // FFmpeg's configure expects to run in the source tree.
        buildDir: sourceDir,
        platform: PlatformInfo(platform: BuildPlatform.macos, architecture: arch),
      );
      await buildSystem.build(buildDir: sourceDir, cores: PlatformDetector.getCpuCores());
      await buildSystem.install(buildDir: sourceDir, installDir: archInstallDir);

      // Validate build outputs
      final expectedLibs = ['libavcodec.a', 'libavformat.a', 'libavutil.a', 'libswresample.a', 'libswscale.a'];
      for (final libName in expectedLibs) {
        final libPath = path.join(archInstallDir, 'lib', libName);
        if (!await FileOps.exists(libPath)) {
          throw Exception('FFmpeg build incomplete for $arch: $libName not found at $libPath');
        }
        final libStat = await File(libPath).stat();
        if (libStat.size == 0) {
          throw Exception('FFmpeg library $libName for $arch is empty - build may have failed');
        }
      }

      installDirs.add(archInstallDir);
    }

    // Create universal binaries
    print('Creating universal binaries...');
    final installDir = getInstallDir(platform);
    await FileOps.ensureDirectory(path.join(installDir, 'lib'));
    await FileOps.ensureDirectory(path.join(installDir, 'include'));

    // Copy headers from arm64 install dir
    await FileOps.copyRecursive(path.join(installDirs.first, 'include'), path.join(installDir, 'include'));

    // Lipo libraries
    for (final libName in libNames) {
      final libFile = '$libName.a';
      final libs = installDirs.map((d) => path.join(d, 'lib', libFile)).toList();
      final output = path.join(installDir, 'lib', libFile);

      // Verify all input libraries exist
      for (final lib in libs) {
        if (!await FileOps.exists(lib)) {
          throw Exception('Cannot create universal binary: missing $lib');
        }
      }

      print('Creating universal $libFile...');
      final result = await runProcessStreaming('lipo', ['-create', ...libs, '-output', output]);
      if (result.exitCode != 0) {
        throw Exception('lipo failed for $libFile: ${result.stderr}');
      }

      // Validate output
      if (!await FileOps.exists(output)) {
        throw Exception('lipo did not create output file: $output');
      }
      final outputStat = await File(output).stat();
      if (outputStat.size == 0) {
        throw Exception('lipo created empty file: $output');
      }
    }

    // Copy and fix pkg-config files
    await FileOps.ensureDirectory(path.join(installDir, 'lib', 'pkgconfig'));
    await FileOps.copyRecursive(
      path.join(installDirs.first, 'lib', 'pkgconfig'),
      path.join(installDir, 'lib', 'pkgconfig'),
    );

    // Fix prefix in pkg-config files
    final pcFiles = Directory(
      path.join(installDir, 'lib', 'pkgconfig'),
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.pc'));

    for (final pcFile in pcFiles) {
      await FileOps.replaceInFileRegex(pcFile.path, RegExp(r'^prefix=.*', multiLine: true), 'prefix=$installDir');
    }
  }

  Future<List<String>> _getMacOSConfigureArgs(Architecture arch, String buildDir, bool skipOpenH264) async {
    final args = <String>[
      '--prefix=$buildDir',
      '--pkg-config-flags=--static',
      '--enable-static',
      '--disable-shared',
      '--disable-programs',
      '--disable-doc',
      '--enable-swscale',
      '--enable-avcodec',
      '--enable-avformat',
      '--enable-avutil',
      '--enable-videotoolbox',
      '--enable-zlib',
      '--disable-avdevice',
      '--disable-avfilter',
      '--disable-debug',
      '--disable-ffplay',
      '--disable-ffprobe',
      '--disable-gpl',
      '--disable-nonfree',
      '--arch=${arch.name}',
      '--cc=clang -arch ${arch.name}',
    ];

    // Check for OpenH264 (optional on macOS)
    if (!skipOpenH264) {
      final openh264Dir = path.join(generatedDir, 'openh264_install');
      if (await FileOps.exists(path.join(openh264Dir, 'lib', 'libopenh264.a'))) {
        args.addAll([
          '--enable-libopenh264',
          '--enable-encoder=libopenh264',
          '--enable-decoder=libopenh264',
          '--extra-cflags=-I${path.join(openh264Dir, 'include')}',
          '--extra-ldflags=-L${path.join(openh264Dir, 'lib')}',
        ]);
      }
    }

    return args;
  }

  Future<void> _buildIOS(PlatformInfo platform, {bool skipOpenH264 = false}) async {
    final sourceDir = getSourceDir(sourceName);
    final installDir = getInstallDir(platform);

    // iOS targets: device (arm64) and simulator (arm64, x86_64)
    final targets = [
      {'arch': Architecture.arm64, 'platform': 'iphoneos', 'type': 'device', 'subdir': 'device'},
      {'arch': Architecture.arm64, 'platform': 'iphonesimulator', 'type': 'simulator', 'subdir': 'simulator_arm64'},
      {'arch': Architecture.x86_64, 'platform': 'iphonesimulator', 'type': 'simulator', 'subdir': 'simulator_x64'},
    ];

    for (final target in targets) {
      final arch = target['arch'] as Architecture;
      final iosPlatform = target['platform'] as String;
      final subdir = target['subdir'] as String;

      print('Building FFmpeg for iOS ($iosPlatform - ${arch.name})...');

      final sdkPath = await PlatformDetector.findXcodeSdkPath(iosPlatform);
      if (sdkPath == null) {
        throw Exception('Could not find Xcode SDK for $iosPlatform');
      }

      final cc = await PlatformDetector.findXcodeCompiler(iosPlatform);
      final cxx = await PlatformDetector.findXcodeCompiler(iosPlatform, cxx: true);
      final hostCc = await PlatformDetector.findXcodeCompiler('macosx');
      final hostSdk = await PlatformDetector.findXcodeSdkPath('macosx');

      if (cc == null || cxx == null || hostCc == null || hostSdk == null) {
        throw Exception('Could not find Xcode compilers');
      }

      final minVersion = iosPlatform == 'iphonesimulator'
          ? '-mios-simulator-version-min=16.0'
          : '-miphoneos-version-min=16.0';

      final buildDir = path.join(generatedDir, 'ffmpeg_build_ios_${iosPlatform}_${arch.name}');
      final targetDir = path.join(installDir, subdir);

      await FileOps.ensureDirectory(buildDir);
      await FileOps.ensureDirectory(targetDir);

      // Clean previous build - FFmpeg builds in-tree
      print('Cleaning previous build artifacts...');
      try {
        await runProcessStreaming('make', ['distclean'], workingDirectory: sourceDir);
      } catch (e) {
        // Ignore
      }

      final configureArgs = <String>[
        '--prefix=$buildDir',
        '--pkg-config-flags=--static',
        '--enable-static',
        '--disable-shared',
        '--disable-programs',
        '--disable-doc',
        '--enable-swscale',
        '--enable-avcodec',
        '--enable-avformat',
        '--enable-avutil',
        '--enable-videotoolbox',
        '--enable-zlib',
        '--disable-avdevice',
        '--disable-avfilter',
        '--disable-debug',
        '--disable-ffplay',
        '--disable-ffprobe',
        '--disable-gpl',
        '--disable-nonfree',
        '--arch=${arch.name}',
        '--target-os=darwin',
        '--enable-cross-compile',
        '--sysroot=$sdkPath',
        '--cc=$cc',
        '--cxx=$cxx',
        '--host-cc=$hostCc',
        '--host-cflags=-isysroot $hostSdk',
        '--host-ldflags=-isysroot $hostSdk',
        '--extra-cflags=-arch ${arch.name} $minVersion',
        '--extra-ldflags=-arch ${arch.name} $minVersion',
      ];

      if (arch == Architecture.arm64) {
        configureArgs.add('--enable-neon');
      } else if (arch == Architecture.x86_64) {
        configureArgs.add('--disable-x86asm');
      }

      // Sanitize environment for iOS builds
      final env = <String, String>{'SDKROOT': hostSdk};
      // Remove problematic environment variables
      final cleanEnv = Map<String, String>.from(Platform.environment);
      cleanEnv.remove('LDFLAGS');
      cleanEnv.remove('CFLAGS');
      cleanEnv.remove('CPPFLAGS');
      cleanEnv.remove('CXXFLAGS');
      cleanEnv.remove('LIBRARY_PATH');
      cleanEnv.remove('CPATH');
      cleanEnv.remove('C_INCLUDE_PATH');
      cleanEnv.remove('CPLUS_INCLUDE_PATH');
      cleanEnv.addAll(env);

      final buildSystem = AutotoolsBuildSystem(configureArgs: configureArgs);
      // FFmpeg builds in-tree (in source directory)
      await buildSystem.configure(
        sourceDir: sourceDir,
        buildDir: sourceDir,
        platform: PlatformInfo(platform: BuildPlatform.ios, architecture: arch, sdkPath: sdkPath),
        environment: cleanEnv,
      );
      await buildSystem.build(buildDir: sourceDir, cores: PlatformDetector.getCpuCores());
      await buildSystem.install(buildDir: sourceDir, installDir: buildDir);

      // Copy to target dir
      await FileOps.ensureDirectory(path.join(targetDir, 'lib'));
      await FileOps.ensureDirectory(path.join(targetDir, 'include'));
      await FileOps.ensureDirectory(path.join(targetDir, 'lib', 'pkgconfig'));

      await FileOps.copyRecursive(path.join(buildDir, 'include'), path.join(targetDir, 'include'));

      // Copy libraries
      final libDir = Directory(path.join(buildDir, 'lib'));
      if (await libDir.exists()) {
        await for (final entity in libDir.list()) {
          if (entity is File && entity.path.endsWith('.a')) {
            await entity.copy(path.join(targetDir, 'lib', path.basename(entity.path)));
          }
        }
      }

      // Copy and fix pkg-config files
      await FileOps.copyRecursive(path.join(buildDir, 'lib', 'pkgconfig'), path.join(targetDir, 'lib', 'pkgconfig'));

      // Fix pkg-config files
      final pcFiles = Directory(
        path.join(targetDir, 'lib', 'pkgconfig'),
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.pc'));

      for (final pcFile in pcFiles) {
        var content = await FileOps.readTextFile(pcFile.path);
        content = content.replaceAll(RegExp(r'^prefix=.*', multiLine: true), 'prefix=$targetDir');
        content = content.replaceAll(RegExp(r'^libdir=.*', multiLine: true), 'libdir=\${prefix}/lib');
        content = content.replaceAll(RegExp(r'^includedir=.*', multiLine: true), 'includedir=\${prefix}/include');
        await FileOps.writeTextFile(pcFile.path, content);
      }

      print('✓ FFmpeg built for iOS $iosPlatform ${arch.name}');
    }

    print('FFmpeg iOS build complete!');
    print('Device (arm64): ${path.join(installDir, 'device')}');
    print('Simulator (arm64): ${path.join(installDir, 'simulator_arm64')}');
    print('Simulator (x86_64): ${path.join(installDir, 'simulator_x64')}');
  }

  Future<void> _buildAndroid(PlatformInfo platform, {bool skipOpenH264 = false}) async {
    final ndkHome = await PlatformDetector.findAndroidNdk();
    if (ndkHome == null) {
      throw Exception('ANDROID_NDK_HOME not set or invalid');
    }

    final toolchain = await PlatformDetector.findAndroidToolchain(ndkHome);
    if (toolchain == null) {
      throw Exception('Could not find Android NDK toolchain');
    }

    // Android ABIs to build.
    // NOTE: For arm64-v8a we use cpu=armv8-a to avoid FFmpeg generating
    // unsupported -mcpu=arm64 flags (clang expects e.g. armv8-a instead).
    final abis = [
      {'arch': 'aarch64', 'abi': 'arm64-v8a', 'api': 21, 'cpu': 'armv8-a'},
      {'arch': 'x86_64', 'abi': 'x86_64', 'api': 21, 'cpu': 'generic'},
    ];

    final sourceDir = getSourceDir(sourceName);
    final installDir = getInstallDir(platform);

    for (final abiInfo in abis) {
      final arch = abiInfo['arch'] as String;
      final abi = abiInfo['abi'] as String;
      final apiLevel = abiInfo['api'] as int;
      final cpu = abiInfo['cpu'] as String;

      print('Building FFmpeg for Android $abi (API $apiLevel)...');

      final buildDir = path.join(generatedDir, 'ffmpeg_build_android_$abi');
      final abiInstallDir = path.join(installDir, abi);

      await FileOps.ensureDirectory(buildDir);
      await FileOps.ensureDirectory(abiInstallDir);

      // Clean previous build
      try {
        await runProcessStreaming('make', ['distclean'], workingDirectory: sourceDir);
        // Remove generated config files
        final configFiles = [
          path.join(sourceDir, 'ffbuild', '.config'),
          path.join(sourceDir, 'ffbuild', 'config.fate'),
          path.join(sourceDir, 'ffbuild', 'config.log'),
          path.join(sourceDir, 'ffbuild', 'config.mak'),
          path.join(sourceDir, 'ffbuild', 'config.sh'),
        ];
        for (final configFile in configFiles) {
          await FileOps.removeIfExists(configFile);
        }
      } catch (e) {
        // Ignore
      }

      // Set up toolchain
      final cc = path.join(toolchain, 'bin', '$arch-linux-android$apiLevel-clang');
      final cxx = path.join(toolchain, 'bin', '$arch-linux-android$apiLevel-clang++');
      final ar = path.join(toolchain, 'bin', 'llvm-ar');
      final ranlib = path.join(toolchain, 'bin', 'llvm-ranlib');
      final strip = path.join(toolchain, 'bin', 'llvm-strip');
      final nm = path.join(toolchain, 'bin', 'llvm-nm');
      final crossPrefix = path.join(toolchain, 'bin', '$arch-linux-android-');
      final sysroot = path.join(toolchain, 'sysroot');

      // Verify toolchain binaries exist
      if (!await FileOps.exists(cc)) {
        throw Exception(
          'C compiler not found: $cc\n'
          'Please check your Android NDK installation at: $ndkHome',
        );
      }
      if (!await FileOps.exists(cxx)) {
        throw Exception(
          'C++ compiler not found: $cxx\n'
          'Please check your Android NDK installation at: $ndkHome',
        );
      }

      // Check for OpenH264 and validate
      final openh264Dir = path.join(generatedDir, 'openh264_install', 'android', abi);
      final openh264Lib = path.join(openh264Dir, 'lib', 'libopenh264.a');
      if (!skipOpenH264) {
        if (!await FileOps.exists(openh264Lib)) {
          throw Exception(
            'OpenH264 not found for $abi at $openh264Lib.\n'
            'Please build OpenH264 first: dart run tool/setup.dart --android',
          );
        }
        // Validate library is not empty
        final libStat = await File(openh264Lib).stat();
        if (libStat.size == 0) {
          throw Exception(
            'OpenH264 library for $abi is empty or corrupted.\n'
            'Please rebuild OpenH264: dart run tool/setup.dart --android',
          );
        }

        // For x86_64, check if library might have incompatible object files
        // by attempting to read it as an archive (basic validation)
        if (abi == 'x86_64') {
          try {
            final arCheck = await runProcessStreaming(ar, ['t', openh264Lib], workingDirectory: sourceDir);
            // If ar fails, the library is likely corrupted
            if (arCheck.exitCode != 0) {
              throw Exception(
                'OpenH264 library for $abi appears corrupted (ar failed to read it).\n'
                'Please rebuild OpenH264: dart run tool/setup.dart --android',
              );
            }
          } catch (e) {
            // If ar command itself fails, warn but continue
            print('⚠ Warning: Could not validate OpenH264 library structure: $e');
          }
        }
      }

      // Convert OpenH264 directory to absolute path for pkg-config
      final openh264DirAbsolute = path.absolute(openh264Dir);

      final extraCflags = <String>[];
      final extraLdflags = <String>[];
      final extraLibs = <String>['-lm'];

      if (arch == 'aarch64') {
        extraCflags.add('-march=armv8-a');
      } else if (arch == 'x86_64') {
        extraCflags.addAll(['-march=x86-64', '-msse4.2', '-mpopcnt', '-m64']);
      }

      final configureArgs = <String>[
        '--prefix=$buildDir',
        '--pkg-config-flags=--static',
        '--pkg-config=pkg-config',
        '--enable-static',
        '--disable-shared',
        '--disable-programs',
        '--disable-doc',
        '--enable-swscale',
        '--enable-avcodec',
        '--enable-avformat',
        '--enable-avutil',
        '--enable-zlib',
        '--disable-avdevice',
        '--disable-avfilter',
        '--disable-debug',
        '--disable-ffplay',
        '--disable-ffprobe',
        '--disable-gpl',
        '--disable-nonfree',
        '--target-os=android',
        '--enable-cross-compile',
        '--arch=$arch',
        '--cpu=$cpu',
        '--disable-runtime-cpudetect',
        '--cc=$cc',
        '--cxx=$cxx',
        '--ar=$ar',
        '--ranlib=$ranlib',
        '--strip=$strip',
        '--nm=$nm',
        '--cross-prefix=$crossPrefix',
        '--sysroot=$sysroot',
        '--host-cc=clang',
        '--host-cflags=',
        '--host-ldflags=',
        '--enable-jni',
        '--disable-mediacodec',
      ];

      if (arch == 'aarch64') {
        configureArgs.add('--enable-neon');
      } else if (arch == 'x86_64' || arch == 'x86') {
        configureArgs.add('--disable-x86asm');
      }

      // Add OpenH264 support
      if (!skipOpenH264 && await FileOps.exists(path.join(openh264DirAbsolute, 'lib', 'libopenh264.a'))) {
        extraCflags.add('-I${path.join(openh264DirAbsolute, 'include')}');
        extraLdflags.add('-L${path.join(openh264DirAbsolute, 'lib')}');
        extraLibs.add('-lc++_shared');
        configureArgs.addAll(['--enable-libopenh264', '--enable-encoder=libopenh264', '--enable-decoder=libopenh264']);
      }

      configureArgs.add('--extra-cflags=${extraCflags.join(' ')} --sysroot=$sysroot -fPIC');
      configureArgs.add('--extra-ldflags=${extraLdflags.join(' ')} --sysroot=$sysroot');
      configureArgs.add('--extra-libs=${extraLibs.join(' ')}');

      // Set up environment
      // IMPORTANT: reset per-ABI flags/env so we don't accidentally mix architectures.
      // Match bash script behavior: unset PKG_CONFIG variables first, then set them
      final env = <String, String>{
        'CC': cc,
        'CXX': cxx,
        'AR': ar,
        'RANLIB': ranlib,
        'STRIP': strip,
        'NM': nm,
        'AS': cc,
        'LD': path.join(toolchain, 'bin', 'ld'),
        'CFLAGS': '${extraCflags.join(' ')} --sysroot=$sysroot',
        'LDFLAGS': '${extraLdflags.join(' ')} --sysroot=$sysroot',
        'CROSS_COMPILE': '1',
        'CROSS_COMPILE_SKIP_RUNTIME_TEST': '1',
        'PKG_CONFIG_ALLOW_CROSS': '1',
      };

      // Match bash script: set OpenH264 pkg-config paths first, then set PKG_CONFIG_SYSROOT_DIR
      if (!skipOpenH264 && await FileOps.exists(path.join(openh264DirAbsolute, 'lib', 'pkgconfig'))) {
        // Use absolute paths for pkg-config (required for cross-compilation)
        final pkgConfigPath = path.absolute(path.join(openh264DirAbsolute, 'lib', 'pkgconfig'));
        env['PKG_CONFIG_LIBDIR'] = pkgConfigPath;
        env['PKG_CONFIG_PATH'] = pkgConfigPath;
      }

      // Help pkg-config operate correctly for cross builds (FFmpeg configure uses it for feature checks)
      // Note: The bash script sets this unconditionally, even when OpenH264 is present
      // The paths in the .pc file will be fixed after configure if needed
      env['PKG_CONFIG_SYSROOT_DIR'] = sysroot;

      final buildSystem = AutotoolsBuildSystem(configureArgs: configureArgs);
      // FFmpeg builds in-tree (in source directory)
      await buildSystem.configure(
        sourceDir: sourceDir,
        buildDir: sourceDir,
        platform: PlatformInfo(platform: BuildPlatform.android),
        environment: env,
      );

      // Verify OpenH264 was enabled
      final configMak = File(path.join(sourceDir, 'ffbuild', 'config.mak'));
      if (await configMak.exists()) {
        final configContent = await configMak.readAsString();
        if (!skipOpenH264 && !configContent.contains('CONFIG_LIBOPENH264=yes')) {
          throw Exception('OpenH264 was not enabled in FFmpeg config.mak');
        }
      }

      await buildSystem.build(buildDir: sourceDir, cores: PlatformDetector.getCpuCores());
      await buildSystem.install(buildDir: sourceDir, installDir: buildDir);

      // Validate build outputs
      final expectedLibs = ['libavcodec.a', 'libavformat.a', 'libavutil.a', 'libswresample.a', 'libswscale.a'];
      for (final libName in expectedLibs) {
        final libPath = path.join(buildDir, 'lib', libName);
        if (!await FileOps.exists(libPath)) {
          throw Exception('FFmpeg build incomplete: $libName not found at $libPath');
        }
        final libStat = await File(libPath).stat();
        if (libStat.size == 0) {
          throw Exception('FFmpeg library $libName is empty - build may have failed');
        }
      }

      // Copy to install dir
      await FileOps.ensureDirectory(path.join(abiInstallDir, 'lib'));
      await FileOps.ensureDirectory(path.join(abiInstallDir, 'include'));
      await FileOps.ensureDirectory(path.join(abiInstallDir, 'lib', 'pkgconfig'));

      await FileOps.copyRecursive(path.join(buildDir, 'include'), path.join(abiInstallDir, 'include'));

      // Copy libraries
      final libDir = Directory(path.join(buildDir, 'lib'));
      if (await libDir.exists()) {
        await for (final entity in libDir.list()) {
          if (entity is File && entity.path.endsWith('.a')) {
            await entity.copy(path.join(abiInstallDir, 'lib', path.basename(entity.path)));
          }
        }
      }

      // Copy and fix pkg-config files
      await FileOps.copyRecursive(
        path.join(buildDir, 'lib', 'pkgconfig'),
        path.join(abiInstallDir, 'lib', 'pkgconfig'),
      );

      // Fix pkg-config files
      final pcFiles = Directory(
        path.join(abiInstallDir, 'lib', 'pkgconfig'),
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.pc'));

      for (final pcFile in pcFiles) {
        var content = await FileOps.readTextFile(pcFile.path);
        content = content.replaceAll(RegExp(r'^prefix=.*', multiLine: true), 'prefix=$abiInstallDir');
        content = content.replaceAll(RegExp(r'^exec_prefix=.*', multiLine: true), 'exec_prefix=\${prefix}');
        content = content.replaceAll(RegExp(r'^libdir=.*', multiLine: true), 'libdir=\${prefix}/lib');
        content = content.replaceAll(RegExp(r'^includedir=.*', multiLine: true), 'includedir=\${prefix}/include');
        await FileOps.writeTextFile(pcFile.path, content);
      }

      print('✓ FFmpeg built for Android $abi');
    }

    print('FFmpeg Android build complete!');
  }

  Future<void> _buildLinux(PlatformInfo platform, {bool skipOpenH264 = false}) async {
    final arch = PlatformDetector.detectHostArchitecture();
    final abiDir = arch == Architecture.arm64 ? 'arm64' : 'x86_64';
    final ffmpegArch = arch == Architecture.arm64 ? 'aarch64' : 'x86_64';

    print('Building FFmpeg for Linux $abiDir...');

    final buildDir = path.join(generatedDir, 'ffmpeg_build_linux_$abiDir');
    final installDir = getInstallDir(platform, subdir: abiDir);
    final sourceDir = getSourceDir(sourceName);

    // Check for OpenH264
    final openh264Dir = path.join(generatedDir, 'openh264_install', 'linux', abiDir);
    // Convert to absolute path for pkg-config (required for proper resolution)
    final openh264DirAbsolute = path.absolute(openh264Dir);
    if (!skipOpenH264 && !await FileOps.exists(path.join(openh264DirAbsolute, 'lib', 'libopenh264.a'))) {
      throw Exception('OpenH264 not found. Build it first with: dart tool/setup.dart --linux');
    }

    // Clean build artifacts but preserve source files (like shell script)
    print('Cleaning previous build artifacts...');
    try {
      await runProcessStreaming('make', ['distclean'], workingDirectory: sourceDir);
      // Remove only generated files, not source files like ffbuild/library.mak
      final configFiles = ['config.h', 'config.asm', 'config.mak', 'config.sh'];
      for (final configFile in configFiles) {
        await FileOps.removeIfExists(path.join(sourceDir, configFile));
      }
      // Clean ffbuild but preserve source .mak files
      final ffbuildDir = Directory(path.join(sourceDir, 'ffbuild'));
      if (await ffbuildDir.exists()) {
        await for (final entity in ffbuildDir.list(recursive: true)) {
          if (entity is File && (entity.path.endsWith('.o') || entity.path.endsWith('.d'))) {
            await entity.delete();
          }
          if (entity is File && entity.path.contains('config.')) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      // Ignore
    }

    // Start with a clean environment map (don't inherit Platform.environment here)
    // We'll merge it in build_system, but we want to control PKG_CONFIG vars explicitly
    final env = <String, String>{
      'PKG_CONFIG_ALLOW_CROSS': '1',
    };

    // Explicitly clear PKG_CONFIG_LIBDIR if it exists in system env (like Windows script does)
    // PKG_CONFIG_LIBDIR restricts search to only that directory, which can break other dependencies
    if (Platform.environment.containsKey('PKG_CONFIG_LIBDIR')) {
      env['PKG_CONFIG_LIBDIR'] = '';
    }

    // Determine pkg-config command to use (wrapper if needed, system otherwise)
    String pkgConfigCmd = 'pkg-config';

    // Set up pkg-config paths for OpenH264 (match bash script: only set PKG_CONFIG_PATH)
    if (!skipOpenH264 && await FileOps.exists(path.join(openh264DirAbsolute, 'lib', 'pkgconfig'))) {
      final pkgConfigPath = path.absolute(path.join(openh264DirAbsolute, 'lib', 'pkgconfig'));
      final existingPkgConfigPath = Platform.environment['PKG_CONFIG_PATH'] ?? '';
      // Match bash script: prepend our path, append existing if present
      env['PKG_CONFIG_PATH'] = existingPkgConfigPath.isNotEmpty 
          ? '$pkgConfigPath:$existingPkgConfigPath'
          : pkgConfigPath;
      
      // Create a pkg-config wrapper to handle FFmpeg's old "package >= version" syntax
      // FFmpeg's configure uses "openh264 >= 1.3.0" which modern pkg-config doesn't support
      // The wrapper converts it to "--atleast-version=1.3.0 openh264"
      final wrapperDir = path.join(generatedDir, 'pkg-config-wrapper');
      await FileOps.ensureDirectory(wrapperDir);
      final wrapperScript = path.join(wrapperDir, 'pkg-config');
      final wrapperContent = r'''#!/bin/bash
# pkg-config wrapper to handle FFmpeg's old "package >= version" syntax
# Converts "package >= version" to "--atleast-version=version package"
# Handles both cases: single quoted argument "package >= version" and separate arguments package >= version
# Also handles the case where shell interprets >= as redirection, leaving only package and version

args=()
i=0
package_arg=""
while [ $i -lt $# ]; do
  i=$((i + 1))
  arg="${!i}"
  
  # Check if this argument is a package name and the next two are ">=" and a version
  # This handles the case where shell splits "package >= version" into three arguments
  if [ $i -lt $# ]; then
    next_i=$((i + 1))
    next_arg="${!next_i}"
    if [ "$next_arg" = ">=" ] && [ $next_i -lt $# ]; then
      version_i=$((next_i + 1))
      version_arg="${!version_i}"
      # Check if version_arg looks like a version number
      if echo "$version_arg" | grep -qE '^[0-9.]+$'; then
        # This is "package >= version" pattern - convert it
        args+=("--atleast-version=$version_arg" "$arg")
        i=$version_i  # Skip the ">=" and version arguments by setting i to version position
        # The while loop will increment i at the start of next iteration, effectively skipping processed args
        continue
      fi
    fi
  fi
  
  # Check if argument matches "package >= version" pattern (single quoted string)
  if echo "$arg" | grep -qE '^[a-zA-Z0-9_-]+\s+>=\s+[0-9.]+$'; then
    # Extract package and version
    package=$(echo "$arg" | sed -E 's/^([a-zA-Z0-9_-]+)\s+>=\s+[0-9.]+$/\1/')
    version=$(echo "$arg" | sed -E 's/^[a-zA-Z0-9_-]+\s+>=\s+([0-9.]+)$/\1/')
    args+=("--atleast-version=$version" "$package")
  # Check if this looks like a package name (alphanumeric with dashes/underscores, not starting with -)
  elif echo "$arg" | grep -qE '^[a-zA-Z0-9_-]+$' && [ "${arg#-}" = "$arg" ]; then
    # This might be a package name - check if next argument is a version number
    # This handles the case where shell consumed >= as redirection
    if [ $i -lt $# ]; then
      next_i=$((i + 1))
      next_arg="${!next_i}"
      if echo "$next_arg" | grep -qE '^[0-9.]+$'; then
        # This looks like "package version" pattern (where >= was consumed by shell)
        # Check if we're in a context where this makes sense (after --exists or similar)
        # Look for --exists, --atleast-version, or similar flags in previous args
        found_check_flag=false
        for j in $(seq 1 $((i-1))); do
          prev_arg="${!j}"
          if [ "$prev_arg" = "--exists" ] || [ "$prev_arg" = "--print-errors" ] || [ "$prev_arg" = "--atleast-version" ]; then
            found_check_flag=true
            break
          fi
        done
        if [ "$found_check_flag" = "true" ]; then
          # This is likely "package >= version" where >= was consumed
          args+=("--atleast-version=$next_arg" "$arg")
          i=$next_i
          continue
        fi
      fi
    fi
    args+=("$arg")
  else
    args+=("$arg")
  fi
done

exec /usr/bin/pkg-config "${args[@]}"
''';
      await FileOps.writeTextFile(wrapperScript, wrapperContent);
      // Make wrapper executable
      await runProcessStreaming('chmod', ['+x', wrapperScript]);
      
      // Use the wrapper instead of system pkg-config
      pkgConfigCmd = wrapperScript;
      env['PKG_CONFIG'] = wrapperScript;
      
      // Debug: verify pkg-config can find it before configure
      print('Verifying pkg-config setup...');
      print('  PKG_CONFIG_PATH: ${env['PKG_CONFIG_PATH']}');
      print('  PKG_CONFIG_ALLOW_CROSS: ${env['PKG_CONFIG_ALLOW_CROSS']}');
      print('  PKG_CONFIG: ${env['PKG_CONFIG']}');
      final testEnv = <String, String>{...Platform.environment, ...env};
      final testResult = await runProcessStreaming(
        wrapperScript,
        ['--exists', '--atleast-version=1.3.0', 'openh264'],
        environment: testEnv,
      );
      if (testResult.exitCode == 0) {
        final version = await runProcessStreaming(
          wrapperScript,
          ['--modversion', 'openh264'],
          environment: testEnv,
        );
        print('  ✓ pkg-config test passed: openh264 version ${version.stdout.trim()}');
      } else {
        print('  ⚠ Warning: pkg-config test failed, but continuing anyway');
        print('  stderr: ${testResult.stderr}');
      }
    } else {
      // If no OpenH264, still preserve existing PKG_CONFIG_PATH
      final existingPkgConfigPath = Platform.environment['PKG_CONFIG_PATH'];
      if (existingPkgConfigPath != null && existingPkgConfigPath.isNotEmpty) {
        env['PKG_CONFIG_PATH'] = existingPkgConfigPath;
      }
    }

    final configureArgs = <String>[
      '--prefix=$buildDir',
      '--pkg-config-flags=--static',
      '--pkg-config=$pkgConfigCmd',
      '--enable-static',
      '--disable-shared',
      '--disable-programs',
      '--disable-doc',
      '--enable-avcodec',
      '--enable-avformat',
      '--enable-avutil',
      '--enable-swscale',
      '--enable-swresample',
      '--enable-zlib',
      '--disable-avdevice',
      '--disable-avfilter',
      '--disable-debug',
      '--disable-ffplay',
      '--disable-ffprobe',
      '--disable-gpl',
      '--disable-nonfree',
      '--arch=$ffmpegArch',
    ];

    if (!skipOpenH264 && await FileOps.exists(path.join(openh264DirAbsolute, 'lib', 'libopenh264.a'))) {
      configureArgs.addAll([
        '--enable-libopenh264',
        '--enable-encoder=libopenh264',
        '--enable-decoder=libopenh264',
        '--extra-cflags=-I${path.join(openh264DirAbsolute, 'include')}',
        '--extra-ldflags=-L${path.join(openh264DirAbsolute, 'lib')}',
      ]);
      // OpenH264 is a C++ library, so we need to link against libstdc++
      configureArgs.add('--extra-libs=-lm -lpthread -lstdc++');
    } else {
      configureArgs.add('--extra-libs=-lm -lpthread');
    }

    final buildSystem = AutotoolsBuildSystem(configureArgs: configureArgs);
    // FFmpeg builds in-tree (in source directory)
    await buildSystem.configure(
      sourceDir: sourceDir,
      buildDir: sourceDir,
      platform: PlatformInfo(platform: BuildPlatform.linux, architecture: arch),
      environment: env,
    );
    await buildSystem.build(buildDir: sourceDir, cores: PlatformDetector.getCpuCores());
    await buildSystem.install(buildDir: sourceDir, installDir: buildDir);

    // Copy to install dir and fix pkg-config
    await FileOps.ensureDirectory(path.join(installDir, 'lib'));
    await FileOps.ensureDirectory(path.join(installDir, 'include'));
    await FileOps.ensureDirectory(path.join(installDir, 'lib', 'pkgconfig'));

    await FileOps.copyRecursive(path.join(buildDir, 'include'), path.join(installDir, 'include'));
    await FileOps.copyRecursive(path.join(buildDir, 'lib'), path.join(installDir, 'lib'));

    // Fix pkg-config files
    final pcFiles = Directory(
      path.join(installDir, 'lib', 'pkgconfig'),
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.pc'));

    for (final pcFile in pcFiles) {
      var content = await FileOps.readTextFile(pcFile.path);
      content = content.replaceAll(RegExp(r'^prefix=.*', multiLine: true), 'prefix=$installDir');
      content = content.replaceAll(RegExp(r'^exec_prefix=.*', multiLine: true), 'exec_prefix=\${prefix}');
      content = content.replaceAll(RegExp(r'^libdir=.*', multiLine: true), 'libdir=\${prefix}/lib');
      content = content.replaceAll(RegExp(r'^includedir=.*', multiLine: true), 'includedir=\${prefix}/include');
      await FileOps.writeTextFile(pcFile.path, content);
    }

    print('FFmpeg installed: $installDir');
  }

  Future<void> _buildWindows(PlatformInfo platform, {bool skipOpenH264 = false}) async {
    throw UnimplementedError('Windows build not yet fully implemented in Dart');
  }
}
