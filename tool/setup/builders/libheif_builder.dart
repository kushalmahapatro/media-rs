// libheif builder (includes libde265 dependency)
import 'dart:io';
import 'package:path/path.dart' as path;
import '../platforms/platform.dart';
import '../build_systems/build_system.dart';
import '../utils/download.dart';
import '../utils/git.dart';
import '../utils/file_ops.dart';
import '../utils/process.dart';
import 'base_builder.dart';

class LibHeifBuilder extends BaseBuilder {
  static const String version = '1.20.2';
  static const String sourceName = 'libheif-$version';
  static const String sourceUrl =
      'https://github.com/strukturag/libheif/releases/download/v$version/libheif-$version.tar.gz';

  static const String de265Version = 'v1.0.15';
  static const String de265Repo = 'https://github.com/strukturag/libde265.git';

  LibHeifBuilder(super.projectRoot);

  @override
  String getName() => 'libheif';

  @override
  String getLibraryName() => 'libheif.a';

  @override
  Future<void> downloadSource() async {
    // Download libheif
    final sourceDir = getSourceDir(sourceName);
    final checkFile = path.join(sourceDir, 'CMakeLists.txt');

    if (await FileOps.exists(checkFile)) {
      print('libheif source already downloaded');
    } else {
      if (await Directory(sourceDir).exists()) {
        await FileOps.removeIfExists(sourceDir);
      }
      await Downloader.downloadAndExtract(
        sourceUrl,
        sourcesDir,
        isGzip: true,
        onProgress: (received, total) {
          if (total > 0) {
            final percent = (received / total * 100).toStringAsFixed(1);
            stdout.write('\rDownloading libheif: $percent%');
          }
        },
      );
      print('');
    }

    // Download libde265
    final de265Dir = getSourceDir('libde265');
    final de265CheckFile = path.join(de265Dir, 'CMakeLists.txt');

    if (await FileOps.exists(de265CheckFile)) {
      print('libde265 source already downloaded');
    } else {
      if (await Directory(de265Dir).exists()) {
        await FileOps.removeIfExists(de265Dir);
      }
      try {
        await Git.clone(de265Repo, de265Dir, branch: de265Version, depth: 1);
      } catch (e) {
        // Fallback to tarball
        print('Git clone failed, trying tarball...');
        await Downloader.downloadAndExtract(
          'https://github.com/strukturag/libde265/archive/$de265Version.tar.gz',
          sourcesDir,
          isGzip: true,
        );
        final extracted = Directory(path.join(sourcesDir, 'libde265-1.0.15'));
        if (await extracted.exists()) {
          await extracted.rename(de265Dir);
        }
      }
    }
  }

  @override
  Future<void> buildForPlatform(PlatformInfo platform, {bool skipOpenH264 = false}) async {
    switch (platform.platform) {
      case BuildPlatform.macos:
        await _buildMacOS(platform);
        break;
      case BuildPlatform.ios:
        await _buildIOS(platform);
        break;
      case BuildPlatform.android:
        await _buildAndroid(platform);
        break;
      case BuildPlatform.linux:
        await _buildLinux(platform);
        break;
      case BuildPlatform.windows:
        await _buildWindows(platform);
        break;
    }
  }

  Future<void> _buildMacOS(PlatformInfo platform) async {
    final archs = [Architecture.arm64, Architecture.x86_64];
    final libNames = ['libheif', 'libde265'];
    final archInstalls = <String, String>{};

    for (final arch in archs) {
      print('Building libheif for macOS $arch...');

      final buildDir = path.join(generatedDir, 'libheif_build_macos_${arch.name}');
      await FileOps.ensureDirectory(buildDir);

      // Build libde265 first
      final de265Install = path.join(buildDir, 'libde265_install');
      await _buildLibDe265(
        arch: arch,
        platform: 'macOS',
        buildPlatform: BuildPlatform.macos,
        installDir: de265Install,
        cmakeFlags: [
          if (arch == Architecture.arm64) '-DCMAKE_OSX_ARCHITECTURES=arm64' else '-DCMAKE_OSX_ARCHITECTURES=x86_64',
          '-DCMAKE_OSX_DEPLOYMENT_TARGET=11.0',
        ],
      );

      // Build libheif
      await _buildLibHeif(
        arch: arch,
        platform: 'macOS',
        buildPlatform: BuildPlatform.macos,
        buildDir: buildDir,
        de265Install: de265Install,
        cmakeFlags: [
          if (arch == Architecture.arm64) '-DCMAKE_OSX_ARCHITECTURES=arm64' else '-DCMAKE_OSX_ARCHITECTURES=x86_64',
          '-DCMAKE_OSX_DEPLOYMENT_TARGET=11.0',
        ],
      );

      // Copy to arch-specific install (only if build succeeded)
      final archInstall = path.join(getInstallDir(platform), arch.name);
      await FileOps.ensureDirectory(path.join(archInstall, 'lib'));
      await FileOps.ensureDirectory(path.join(archInstall, 'include'));

      // Check if build directories exist before copying
      final buildLibDir = path.join(buildDir, 'lib');
      final buildIncludeDir = path.join(buildDir, 'include');

      if (await Directory(buildLibDir).exists()) {
        await FileOps.copyRecursive(buildLibDir, path.join(archInstall, 'lib'));
      }
      if (await Directory(buildIncludeDir).exists()) {
        await FileOps.copyRecursive(buildIncludeDir, path.join(archInstall, 'include'));
      }
      await FileOps.copyRecursive(path.join(de265Install, 'lib'), path.join(archInstall, 'lib'));
      await FileOps.copyRecursive(path.join(de265Install, 'include'), path.join(archInstall, 'include'));

      archInstalls[arch.name] = archInstall;
      print('✓ libheif built for macOS $arch');
    }

    // Create universal binaries
    print('Creating universal binaries...');
    final universalDir = path.join(getInstallDir(platform), 'universal');
    await FileOps.ensureDirectory(path.join(universalDir, 'lib'));
    await FileOps.ensureDirectory(path.join(universalDir, 'include'));

    for (final libName in libNames) {
      final libFile = '$libName.a';
      final arm64Lib = path.join(archInstalls['arm64']!, 'lib', libFile);
      final x64Lib = path.join(archInstalls['x86_64']!, 'lib', libFile);

      if (await FileOps.exists(arm64Lib) && await FileOps.exists(x64Lib)) {
        final result = await runProcessStreaming('lipo', [
          '-create',
          arm64Lib,
          x64Lib,
          '-output',
          path.join(universalDir, 'lib', libFile),
        ]);
        if (result.exitCode != 0) {
          throw Exception('lipo failed: ${result.stderr}');
        }
        print('✓ Created universal $libFile');
      }
    }

    // Copy headers
    await FileOps.copyRecursive(path.join(archInstalls['arm64']!, 'include'), path.join(universalDir, 'include'));

    // Create pkg-config file
    await FileOps.ensureDirectory(path.join(universalDir, 'lib', 'pkgconfig'));
    final pcContent =
        '''
prefix=$universalDir
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libheif
Description: HEIF image codec library
Version: $version
Libs: -L\${libdir} -lheif -lde265
Cflags: -I\${includedir}
Requires:
''';
    await FileOps.writeTextFile(path.join(universalDir, 'lib', 'pkgconfig', 'libheif.pc'), pcContent);

    print('✓ macOS universal build complete!');
  }

  Future<void> _buildIOS(PlatformInfo platform) async {
    final targets = [
      {'arch': Architecture.arm64, 'platform': 'iphoneos', 'type': 'device'},
      {'arch': Architecture.arm64, 'platform': 'iphonesimulator', 'type': 'simulator'},
      {'arch': Architecture.x86_64, 'platform': 'iphonesimulator', 'type': 'simulator'},
    ];

    for (final target in targets) {
      final arch = target['arch'] as Architecture;
      final iosPlatform = target['platform'] as String;
      final type = target['type'] as String;

      print('Building libheif for iOS $iosPlatform ($arch)...');

      final sdkPath = await PlatformDetector.findXcodeSdkPath(iosPlatform);
      if (sdkPath == null) {
        throw Exception('Could not find Xcode SDK for $iosPlatform');
      }

      final cc = await PlatformDetector.findXcodeCompiler(iosPlatform);
      final cxx = await PlatformDetector.findXcodeCompiler(iosPlatform, cxx: true);

      if (cc == null || cxx == null) {
        throw Exception('Could not find Xcode compilers');
      }

      final minVersion = iosPlatform == 'iphonesimulator'
          ? '-mios-simulator-version-min=16.0'
          : '-miphoneos-version-min=16.0';

      final buildDir = path.join(generatedDir, 'libheif_build_ios_${arch.name}_$type');
      final platformInstall = path.join(getInstallDir(platform), iosPlatform, arch.name);

      await FileOps.ensureDirectory(buildDir);
      await FileOps.ensureDirectory(platformInstall);

      // Build libde265 first
      final de265Install = path.join(buildDir, 'libde265_install');
      await _buildLibDe265(
        arch: arch,
        platform: 'iOS-$iosPlatform',
        buildPlatform: BuildPlatform.ios,
        installDir: de265Install,
        cmakeFlags: [
          '-DCMAKE_SYSTEM_NAME=iOS',
          '-DCMAKE_OSX_SYSROOT=$sdkPath',
          '-DCMAKE_OSX_ARCHITECTURES=${arch.name}',
          '-DCMAKE_C_COMPILER=$cc',
          '-DCMAKE_CXX_COMPILER=$cxx',
          '-DCMAKE_C_FLAGS=$minVersion',
          '-DCMAKE_CXX_FLAGS=$minVersion',
          // For cross-compiling to iOS, avoid running test executables.
          '-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY',
        ],
        sanitizeEnv: true,
      );

      // Build libheif
      await _buildLibHeif(
        arch: arch,
        platform: 'iOS-$iosPlatform',
        buildPlatform: BuildPlatform.ios,
        buildDir: buildDir,
        de265Install: de265Install,
        cmakeFlags: [
          '-DCMAKE_SYSTEM_NAME=iOS',
          '-DCMAKE_OSX_SYSROOT=$sdkPath',
          '-DCMAKE_OSX_ARCHITECTURES=${arch.name}',
          '-DCMAKE_C_COMPILER=$cc',
          '-DCMAKE_CXX_COMPILER=$cxx',
          '-DCMAKE_C_FLAGS=$minVersion -fPIC',
          '-DCMAKE_CXX_FLAGS=$minVersion -fPIC',
          // For cross-compiling to iOS, avoid running test executables.
          '-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY',
        ],
        sanitizeEnv: true,
      );

      // Copy to platform install
      await FileOps.ensureDirectory(path.join(platformInstall, 'lib'));
      await FileOps.ensureDirectory(path.join(platformInstall, 'include'));

      // Verify buildDir/lib exists before copying
      final buildLibDir = Directory(path.join(buildDir, 'lib'));
      final buildIncludeDir = Directory(path.join(buildDir, 'include'));

      if (await buildLibDir.exists()) {
        await FileOps.copyRecursive(buildLibDir.path, path.join(platformInstall, 'lib'));
      } else {
        throw Exception('libheif build directory does not contain lib: ${buildLibDir.path}');
      }

      if (await buildIncludeDir.exists()) {
        await FileOps.copyRecursive(buildIncludeDir.path, path.join(platformInstall, 'include'));
      } else {
        throw Exception('libheif build directory does not contain include: ${buildIncludeDir.path}');
      }
      await FileOps.copyRecursive(path.join(de265Install, 'lib'), path.join(platformInstall, 'lib'));
      await FileOps.copyRecursive(path.join(de265Install, 'include'), path.join(platformInstall, 'include'));

      // Create pkg-config file
      await FileOps.ensureDirectory(path.join(platformInstall, 'lib', 'pkgconfig'));
      final pcContent =
          '''
prefix=$platformInstall
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libheif
Description: HEIF image codec library
Version: $version
Libs: -L\${libdir} -lheif -lde265
Cflags: -I\${includedir}
Requires:
''';
      await FileOps.writeTextFile(path.join(platformInstall, 'lib', 'pkgconfig', 'libheif.pc'), pcContent);

      print('✓ libheif built for iOS $iosPlatform $arch');
    }

    print('✓ iOS build complete!');
  }

  Future<void> _buildAndroid(PlatformInfo platform) async {
    final ndkHome = await PlatformDetector.findAndroidNdk();
    if (ndkHome == null) {
      throw Exception('ANDROID_NDK_HOME not set or invalid');
    }

    final toolchain = await PlatformDetector.findAndroidToolchain(ndkHome);
    if (toolchain == null) {
      throw Exception('Could not find Android NDK toolchain');
    }

    final abis = [
      {'arch': 'aarch64', 'abi': 'arm64-v8a'},
      {'arch': 'x86_64', 'abi': 'x86_64'},
    ];
    final apiLevel = 21;

    for (final abiInfo in abis) {
      final arch = abiInfo['arch'] as String;
      final abi = abiInfo['abi'] as String;

      print('Building libheif for Android $abi...');

      final buildDir = path.join(generatedDir, 'libheif_build_android_$abi');
      final abiInstallDir = path.join(getInstallDir(platform), abi);

      await FileOps.ensureDirectory(buildDir);
      await FileOps.ensureDirectory(abiInstallDir);

      final cc = path.join(toolchain, 'bin', '$arch-linux-android$apiLevel-clang');
      final cxx = path.join(toolchain, 'bin', '$arch-linux-android$apiLevel-clang++');
      final sysroot = path.join(toolchain, 'sysroot');

      // Build libde265 first
      final de265Install = path.join(buildDir, 'libde265_install');
      await _buildLibDe265Android(
        arch: arch,
        abi: abi,
        installDir: de265Install,
        ndkHome: ndkHome,
        toolchain: toolchain,
        cc: cc,
        cxx: cxx,
        sysroot: sysroot,
      );

      // Build libheif
      await _buildLibHeifAndroid(
        arch: arch,
        abi: abi,
        buildDir: buildDir,
        de265Install: de265Install,
        ndkHome: ndkHome,
        toolchain: toolchain,
        cc: cc,
        cxx: cxx,
        sysroot: sysroot,
      );

      // Copy to install dir
      await FileOps.ensureDirectory(path.join(abiInstallDir, 'lib'));
      await FileOps.ensureDirectory(path.join(abiInstallDir, 'include'));

      await FileOps.copyRecursive(path.join(buildDir, 'lib'), path.join(abiInstallDir, 'lib'));
      await FileOps.copyRecursive(path.join(buildDir, 'include'), path.join(abiInstallDir, 'include'));
      await FileOps.copyRecursive(path.join(de265Install, 'lib'), path.join(abiInstallDir, 'lib'));
      await FileOps.copyRecursive(path.join(de265Install, 'include'), path.join(abiInstallDir, 'include'));

      // Create pkg-config files
      await FileOps.ensureDirectory(path.join(abiInstallDir, 'lib', 'pkgconfig'));

      // Create libde265.pc with correct prefix
      final de265PcContent =
          '''
prefix=$abiInstallDir
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libde265
Description: H.265/HEVC video decoder.
URL: https://github.com/strukturag/libde265
Version: 1.0.15
Requires:
Libs: -lde265 -L\${libdir}
Libs.private: -lc++
Cflags: -I\${includedir}
''';
      await FileOps.writeTextFile(path.join(abiInstallDir, 'lib', 'pkgconfig', 'libde265.pc'), de265PcContent);

      // Create libheif.pc
      final heifPcContent =
          '''
prefix=$abiInstallDir
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libheif
Description: HEIF image codec library
Version: $version
Libs: -L\${libdir} -lheif -lde265
Cflags: -I\${includedir}
Requires:
''';
      await FileOps.writeTextFile(path.join(abiInstallDir, 'lib', 'pkgconfig', 'libheif.pc'), heifPcContent);

      print('✓ libheif built for Android $abi');
    }

    print('✓ Android build complete!');
  }

  Future<void> _buildLinux(PlatformInfo platform) async {
    final arch = PlatformDetector.detectHostArchitecture();
    final abiDir = arch == Architecture.arm64 ? 'arm64' : 'x86_64';

    print('Building libheif for Linux $abiDir...');

    final buildDir = path.join(generatedDir, 'libheif_build_linux_$abiDir');
    final installDir = getInstallDir(platform, subdir: abiDir);

    await FileOps.ensureDirectory(buildDir);
    await FileOps.ensureDirectory(installDir);

    // Build libde265 first
    final de265Install = path.join(buildDir, 'libde265_install');
    await _buildLibDe265(
      arch: arch,
      platform: 'Linux',
      buildPlatform: BuildPlatform.linux,
      installDir: de265Install,
      cmakeFlags: [],
    );

    // Build libheif
    await _buildLibHeif(
      arch: arch,
      platform: 'Linux',
      buildPlatform: BuildPlatform.linux,
      buildDir: buildDir,
      de265Install: de265Install,
      cmakeFlags: [],
    );

    // Copy to install dir
    await FileOps.ensureDirectory(path.join(installDir, 'lib'));
    await FileOps.ensureDirectory(path.join(installDir, 'include'));

    await FileOps.copyRecursive(path.join(buildDir, 'lib'), path.join(installDir, 'lib'));
    await FileOps.copyRecursive(path.join(buildDir, 'include'), path.join(installDir, 'include'));
    await FileOps.copyRecursive(path.join(de265Install, 'lib'), path.join(installDir, 'lib'));
    await FileOps.copyRecursive(path.join(de265Install, 'include'), path.join(installDir, 'include'));

    // Create pkg-config file
    await FileOps.ensureDirectory(path.join(installDir, 'lib', 'pkgconfig'));
    final pcContent =
        '''
prefix=$installDir
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libheif
Description: HEIF image codec library
Version: $version
Libs: -L\${libdir} -lheif -lde265
Cflags: -I\${includedir}
Requires:
''';
    await FileOps.writeTextFile(path.join(installDir, 'lib', 'pkgconfig', 'libheif.pc'), pcContent);

    print('libheif installed: $installDir');
  }

  Future<void> _buildWindows(PlatformInfo platform) async {
    final abiDir = 'x86_64';

    print('Building libheif for Windows $abiDir...');

    final buildDir = path.join(generatedDir, 'libheif_build_windows_$abiDir');
    final installDir = getInstallDir(platform, subdir: abiDir);
    final de265Install = path.join(buildDir, 'libde265_install');

    await FileOps.ensureDirectory(buildDir);
    await FileOps.ensureDirectory(installDir);

    // Find MinGW compilers (match bash script - uses x86_64-w64-mingw32-gcc)
    final compilerInfo = await PlatformDetector.findMinGWCompiler();
    // Use x86_64-w64-mingw32-gcc/g++ like the bash script does
    final cc = compilerInfo.cc;
    final cxx = compilerInfo.cc.replaceAll('gcc', 'g++');

    // Set up environment with MSYS2 paths
    final msys2Root = PlatformDetector.getMsys2Root();
    final usrBin = path.join(msys2Root, 'usr', 'bin'); // Contains make, cmake
    final mingwBin = path.join(msys2Root, 'mingw64', 'bin'); // Contains gcc, etc.
    final env = Map<String, String>.from(Platform.environment);
    // Add MSYS2 paths to PATH
    env['PATH'] = '$usrBin;$mingwBin;${env['PATH'] ?? ''}';

    // Find cmake executable
    final cmakeExe = await PlatformDetector.findCmake();

    // Build libde265 first
    final de265Dir = getSourceDir('libde265');
    final de265BuildDir = path.join(de265Dir, 'build_windows');

    await FileOps.ensureDirectory(de265BuildDir);
    await FileOps.removeIfExists(de265BuildDir);
    await FileOps.ensureDirectory(de265BuildDir);

    final de265CmakeArgs = <String>[
      '-DCMAKE_BUILD_TYPE=Release',
      '-DCMAKE_INSTALL_PREFIX=$de265Install',
      '-DCMAKE_SYSTEM_NAME=Windows',
      '-DCMAKE_C_COMPILER=$cc',
      '-DCMAKE_CXX_COMPILER=$cxx',
      '-DCMAKE_POSITION_INDEPENDENT_CODE=ON',
      '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
      '-DBUILD_SHARED_LIBS=OFF',
      '-DENABLE_SDL=OFF',
      '-DENABLE_DEC265=OFF',
      '-DENABLE_ENCODER=OFF',
    ];

    final de265BuildSystem = CMakeBuildSystem(cmakeArgs: de265CmakeArgs);
    await de265BuildSystem.configure(
      sourceDir: de265Dir,
      buildDir: de265BuildDir,
      platform: PlatformInfo(platform: BuildPlatform.windows, architecture: Architecture.x86_64),
      environment: env,
    );

    // Build de265 target
    final de265BuildResult = await runProcessStreaming(
      cmakeExe,
      ['--build', '.', '--target', 'de265', '--parallel', PlatformDetector.getCpuCores().toString()],
      workingDirectory: de265BuildDir,
      environment: env,
    );

    if (de265BuildResult.exitCode != 0) {
      throw Exception('libde265 build failed: ${de265BuildResult.stderr}');
    }

    // Manual install of libde265
    await FileOps.ensureDirectory(path.join(de265Install, 'lib'));
    await FileOps.ensureDirectory(path.join(de265Install, 'include', 'libde265'));
    await FileOps.ensureDirectory(path.join(de265Install, 'lib', 'pkgconfig'));

    // Find and copy library
    final de265Lib = await _findFile(de265BuildDir, 'libde265.a');
    if (de265Lib == null) {
      throw Exception('libde265.a not found after build');
    }
    await File(de265Lib).copy(path.join(de265Install, 'lib', 'libde265.a'));

    // Copy headers from source directory (match bash script: cp -r ../libde265/libde265/*.h)
    // From build_windows, ../libde265/libde265/ means source_dir/libde265/libde265/
    // Since de265Dir is already source_dir/libde265, headers are in libde265/ subdirectory
    final de265HeaderDir = Directory(path.join(de265Dir, 'libde265'));
    if (await de265HeaderDir.exists()) {
      // Copy all .h files from libde265/libde265/ (match bash script: cp -r ../libde265/libde265/*.h)
      await FileOps.copyRecursive(
        de265HeaderDir.path,
        path.join(de265Install, 'include', 'libde265'),
      );
    }
    
    // Also check build directory for generated headers (match bash script)
    final buildHeaderDir = Directory(path.join(de265BuildDir, 'libde265'));
    if (await buildHeaderDir.exists()) {
      // Copy any .h files from build directory
      try {
        await for (final entity in buildHeaderDir.list()) {
          if (entity is File && entity.path.endsWith('.h')) {
            await entity.copy(path.join(de265Install, 'include', 'libde265', path.basename(entity.path)));
          }
        }
      } catch (e) {
        // Ignore errors
      }
    }

    // Check for de265-version.h in build directory
    final versionHeader = await _findFile(de265BuildDir, 'de265-version.h');
    if (versionHeader != null) {
      await File(versionHeader).copy(path.join(de265Install, 'include', 'libde265', 'de265-version.h'));
    }

    // Verify at least one header was copied
    if (!await FileOps.exists(path.join(de265Install, 'include', 'libde265', 'de265.h'))) {
      // Try cmake install as fallback
      try {
        await runProcessStreaming(cmakeExe, ['--install', '.', '--component', 'de265'], workingDirectory: de265BuildDir, environment: env);
      } catch (e) {
        // Ignore
      }
      if (!await FileOps.exists(path.join(de265Install, 'include', 'libde265', 'de265.h'))) {
        throw Exception('Failed to install libde265 headers');
      }
    }

    // Build libheif
    final heifDir = getSourceDir(sourceName);
    final heifBuildDir = path.join(heifDir, 'build_windows');

    await FileOps.ensureDirectory(heifBuildDir);
    await FileOps.removeIfExists(heifBuildDir);
    await FileOps.ensureDirectory(heifBuildDir);

    final heifCmakeArgs = <String>[
      '-DCMAKE_BUILD_TYPE=Release',
      '-DCMAKE_INSTALL_PREFIX=$buildDir',
      '-DCMAKE_SYSTEM_NAME=Windows',
      '-DCMAKE_C_COMPILER=$cc',
      '-DCMAKE_CXX_COMPILER=$cxx',
      '-DCMAKE_POSITION_INDEPENDENT_CODE=ON',
      '-DBUILD_SHARED_LIBS=OFF',
      '-DENABLE_PLUGIN_LOADING=OFF',
      '-DWITH_AOM=OFF',
      '-DWITH_DAV1D=OFF',
      '-DWITH_RAV1E=OFF',
      '-DWITH_X265=OFF',
      '-DWITH_LIBDE265=ON',
      '-DLIBDE265_INCLUDE_DIR=${path.join(de265Install, 'include')}',
      '-DLIBDE265_LIBRARY=${path.join(de265Install, 'lib', 'libde265.a')}',
      '-DWITH_EXAMPLES=OFF',
      '-DWITH_TESTS=OFF',
      '-DWITH_UNCOMPRESSED_CODEC=OFF',
      '-DCMAKE_DISABLE_FIND_PACKAGE_AOM=ON',
      '-DCMAKE_DISABLE_FIND_PACKAGE_libsharpyuv=ON',
      '-DCMAKE_C_FLAGS=-fPIC',
      '-DCMAKE_CXX_FLAGS=-fPIC',
    ];

    final heifBuildSystem = CMakeBuildSystem(cmakeArgs: heifCmakeArgs);
    await heifBuildSystem.configure(
      sourceDir: heifDir,
      buildDir: heifBuildDir,
      platform: PlatformInfo(platform: BuildPlatform.windows, architecture: Architecture.x86_64),
      environment: env,
    );

    // Build heif target (reuse cmakeExe from above)
    final heifBuildResult = await runProcessStreaming(
      cmakeExe,
      ['--build', '.', '--target', 'heif', '--parallel', PlatformDetector.getCpuCores().toString()],
      workingDirectory: heifBuildDir,
      environment: env,
    );

    if (heifBuildResult.exitCode != 0) {
      throw Exception('libheif build failed: ${heifBuildResult.stderr}');
    }

    // Try cmake install first
    try {
      await runProcessStreaming(cmakeExe, ['--install', '.', '--component', 'libheif'], workingDirectory: heifBuildDir, environment: env);
      print('✓ Installed via cmake component');
    } catch (e) {
      print('⚠ cmake --install failed, trying manual install');
    }

    // Find libheif.a
    String? heifLib;
    if (await FileOps.exists(path.join(buildDir, 'lib', 'libheif.a'))) {
      heifLib = path.join(buildDir, 'lib', 'libheif.a');
    } else {
      heifLib = await _findFile(heifBuildDir, 'libheif.a');
      if (heifLib == null) {
        // Search for any heif library
        final found = await _findFile(heifBuildDir, '*heif*.a');
        if (found != null && !found.contains('libde265')) {
          heifLib = found;
        }
      }
    }

    if (heifLib == null) {
      throw Exception('libheif.a not found after build');
    }

    print('Found libheif.a at: $heifLib');

    // Install layout + pkg-config
    await FileOps.ensureDirectory(path.join(installDir, 'lib'));
    await FileOps.ensureDirectory(path.join(installDir, 'include'));
    await FileOps.ensureDirectory(path.join(installDir, 'lib', 'pkgconfig'));

    await File(heifLib).copy(path.join(installDir, 'lib', 'libheif.a'));
    if (await FileOps.exists(path.join(de265Install, 'lib', 'libde265.a'))) {
      await File(path.join(de265Install, 'lib', 'libde265.a')).copy(path.join(installDir, 'lib', 'libde265.a'));
    }

    // Copy headers
    if (await Directory(path.join(buildDir, 'include', 'libheif')).exists()) {
      await FileOps.copyRecursive(path.join(buildDir, 'include', 'libheif'), path.join(installDir, 'include', 'libheif'));
    } else if (await Directory(path.join(heifDir, 'libheif', 'api', 'libheif')).exists()) {
      await FileOps.copyRecursive(
        path.join(heifDir, 'libheif', 'api', 'libheif'),
        path.join(installDir, 'include', 'libheif'),
      );
    }

    // Verify libheif.a was copied
    if (!await FileOps.exists(path.join(installDir, 'lib', 'libheif.a'))) {
      throw Exception('Failed to copy libheif.a to ${path.join(installDir, 'lib')}');
    }
    print('✓ Copied libheif.a to ${path.join(installDir, 'lib')}');

    // Create pkg-config file (Windows paths need special handling)
    final installDirUnix = PlatformDetector.windowsToMsys2Path(installDir);
    final pcContent = '''
prefix=$installDirUnix
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libheif
Description: HEIF image codec library
Version: $version
Libs: -L\${libdir} -lheif -lde265
Cflags: -I\${includedir}
Requires:
''';
    await FileOps.writeTextFile(path.join(installDir, 'lib', 'pkgconfig', 'libheif.pc'), pcContent);

    print('libheif installed: $installDir');
  }

  /// Build libheif/libde265 with MSVC to generate .lib files (Windows only)
  /// This is needed because MinGW-built .a files have COMDAT incompatibility with MSVC linker
  Future<void> buildMSVC(PlatformInfo platform) async {
    if (platform.platform != BuildPlatform.windows) {
      throw Exception('buildMSVC is only supported on Windows');
    }

    final abiDir = 'x86_64';
    print('Building libheif/libde265 with MSVC for Windows $abiDir...');

    // Check if Visual Studio is available
    final cmakeExe = await PlatformDetector.findCmake();
    final env = Map<String, String>.from(Platform.environment);

    // Try to detect Visual Studio generator
    // CMake can detect Visual Studio automatically - try common generators in order
    final generators = ['Visual Studio 17 2022', 'Visual Studio 16 2019', 'Visual Studio 15 2017'];
    String selectedGenerator = generators.first; // Default to VS 2022
    
    print('Using CMake generator: $selectedGenerator');
    print('(If this fails, ensure Visual Studio is installed with C++ development tools)');

    final buildDir = path.join(generatedDir, 'libheif_build_windows_msvc_$abiDir');
    final installDir = getInstallDir(platform, subdir: abiDir);
    final de265Dir = getSourceDir('libde265');
    final heifDir = getSourceDir(sourceName);

    await FileOps.ensureDirectory(buildDir);
    await FileOps.removeIfExists(buildDir);
    await FileOps.ensureDirectory(buildDir);

    // Build libde265 with MSVC first
    final de265BuildDir = path.join(buildDir, 'libde265');
    await FileOps.ensureDirectory(de265BuildDir);

    print('Configuring libde265 with MSVC...');
    final de265CmakeArgs = <String>[
      '-G', selectedGenerator,
      '-A', 'x64',
      '-DCMAKE_BUILD_TYPE=Release',
      '-DCMAKE_INSTALL_PREFIX=$buildDir/libde265_install',
      '-DCMAKE_POLICY_VERSION_MINIMUM=3.5', // Required for newer CMake versions
      '-DBUILD_SHARED_LIBS=OFF',
      '-DENABLE_SDL=OFF',
      '-DENABLE_DEC265=OFF',
      '-DENABLE_ENCODER=OFF',
      de265Dir,
    ];

    final de265ConfigureResult = await runProcessStreaming(
      cmakeExe,
      de265CmakeArgs,
      workingDirectory: de265BuildDir,
      environment: env,
    );

    if (de265ConfigureResult.exitCode != 0) {
      throw Exception('Failed to configure libde265 with MSVC: ${de265ConfigureResult.stderr}');
    }

    print('Building libde265 with MSVC...');
    final de265BuildResult = await runProcessStreaming(
      cmakeExe,
      ['--build', '.', '--config', 'Release', '--target', 'de265', '--parallel', PlatformDetector.getCpuCores().toString()],
      workingDirectory: de265BuildDir,
      environment: env,
    );

    if (de265BuildResult.exitCode != 0) {
      throw Exception('Failed to build libde265 with MSVC: ${de265BuildResult.stderr}');
    }

    // Install libde265
    await runProcessStreaming(
      cmakeExe,
      ['--install', '.', '--config', 'Release'],
      workingDirectory: de265BuildDir,
      environment: env,
    );

    final de265Install = path.join(buildDir, 'libde265_install');

    // Build libheif with MSVC
    final heifBuildDir = path.join(buildDir, 'libheif');
    await FileOps.ensureDirectory(heifBuildDir);

    print('Configuring libheif with MSVC...');
    final heifCmakeArgs = <String>[
      '-G', selectedGenerator,
      '-A', 'x64',
      '-DCMAKE_BUILD_TYPE=Release',
      '-DCMAKE_INSTALL_PREFIX=$installDir',
      '-DCMAKE_POLICY_VERSION_MINIMUM=3.5', // Required for newer CMake versions
      '-DBUILD_SHARED_LIBS=OFF',
      '-DENABLE_PLUGIN_LOADING=OFF',
      '-DWITH_AOM=OFF',
      '-DWITH_DAV1D=OFF',
      '-DWITH_RAV1E=OFF',
      '-DWITH_X265=OFF',
      '-DWITH_LIBDE265=ON',
      '-DLIBDE265_INCLUDE_DIR=${path.join(de265Install, 'include')}',
      '-DLIBDE265_LIBRARY=${path.join(de265Install, 'lib', 'de265.lib')}',
      '-DWITH_EXAMPLES=OFF',
      '-DWITH_TESTS=OFF',
      '-DWITH_UNCOMPRESSED_CODEC=OFF',
      '-DCMAKE_DISABLE_FIND_PACKAGE_AOM=ON',
      '-DCMAKE_DISABLE_FIND_PACKAGE_libsharpyuv=ON',
      heifDir,
    ];

    final heifConfigureResult = await runProcessStreaming(
      cmakeExe,
      heifCmakeArgs,
      workingDirectory: heifBuildDir,
      environment: env,
    );

    if (heifConfigureResult.exitCode != 0) {
      throw Exception('Failed to configure libheif with MSVC: ${heifConfigureResult.stderr}');
    }

    print('Building libheif with MSVC...');
    final heifBuildResult = await runProcessStreaming(
      cmakeExe,
      ['--build', '.', '--config', 'Release', '--target', 'heif', '--parallel', PlatformDetector.getCpuCores().toString()],
      workingDirectory: heifBuildDir,
      environment: env,
    );

    if (heifBuildResult.exitCode != 0) {
      throw Exception('Failed to build libheif with MSVC: ${heifBuildResult.stderr}');
    }

    // Install libheif
    await runProcessStreaming(
      cmakeExe,
      ['--install', '.', '--config', 'Release', '--component', 'libheif'],
      workingDirectory: heifBuildDir,
      environment: env,
    );

    // Copy .lib files to install directory (MSVC produces .lib, not .a)
    await FileOps.ensureDirectory(path.join(installDir, 'lib'));

    // Find and copy libde265.lib
    final de265LibPath = path.join(de265Install, 'lib', 'de265.lib');
    if (await FileOps.exists(de265LibPath)) {
      await File(de265LibPath).copy(path.join(installDir, 'lib', 'de265.lib'));
      await File(de265LibPath).copy(path.join(installDir, 'lib', 'libde265.lib'));
    }

    // Find and copy libheif.lib
    final heifLibPath = path.join(installDir, 'lib', 'heif.lib');
    if (await FileOps.exists(heifLibPath)) {
      await File(heifLibPath).copy(path.join(installDir, 'lib', 'libheif.lib'));
    } else {
      // Try to find it in the build directory
      final heifLibInBuild = await _findFile(heifBuildDir, 'heif.lib');
      if (heifLibInBuild != null) {
        await File(heifLibInBuild).copy(path.join(installDir, 'lib', 'heif.lib'));
        await File(heifLibInBuild).copy(path.join(installDir, 'lib', 'libheif.lib'));
      }
    }

    print('✓ MSVC-built libheif/libde265 installed with .lib files');
  }

  // Helper methods for building libde265 and libheif
  Future<void> _buildLibDe265({
    required Architecture? arch,
    required String platform,
    required BuildPlatform buildPlatform,
    required String installDir,
    required List<String> cmakeFlags,
    bool sanitizeEnv = false,
  }) async {
    final de265Dir = getSourceDir('libde265');
    final buildDir = path.join(de265Dir, 'build_${platform}_${arch?.name ?? 'default'}');

    await FileOps.ensureDirectory(buildDir);
    await FileOps.removeIfExists(buildDir);
    await FileOps.ensureDirectory(buildDir);

    final cmakeArgs = <String>[
      '..',
      '-DCMAKE_BUILD_TYPE=Release',
      '-DCMAKE_INSTALL_PREFIX=$installDir',
      '-DCMAKE_POSITION_INDEPENDENT_CODE=ON',
      '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
      '-DBUILD_SHARED_LIBS=OFF',
      '-DENABLE_SDL=OFF',
      '-DENABLE_DEC265=OFF',
      '-DENABLE_ENCODER=OFF',
      ...cmakeFlags,
    ];

    Map<String, String>? env;
    if (sanitizeEnv) {
      env = Map<String, String>.from(Platform.environment);
      env.remove('LDFLAGS');
      env.remove('LIBRARY_PATH');
      env.remove('DYLD_LIBRARY_PATH');
      env.remove('DYLD_FALLBACK_LIBRARY_PATH');
      env.remove('CPATH');
      env.remove('C_INCLUDE_PATH');
      env.remove('CPLUS_INCLUDE_PATH');
    }

    final buildSystem = CMakeBuildSystem(cmakeArgs: cmakeArgs);
    await buildSystem.configure(
      sourceDir: de265Dir,
      buildDir: buildDir,
      platform: PlatformInfo(platform: buildPlatform, architecture: arch),
      environment: env,
    );

    // Manual install (CMake install may try to install CLI tools)
    await FileOps.ensureDirectory(path.join(installDir, 'lib'));
    await FileOps.ensureDirectory(path.join(installDir, 'include', 'libde265'));
    await FileOps.ensureDirectory(path.join(installDir, 'lib', 'pkgconfig'));

    // Copy headers first (needed before building libheif)
    final headerSourceDir = Directory(path.join(de265Dir, 'libde265'));
    if (await headerSourceDir.exists()) {
      final headers = ['de265.h', 'en265.h'];
      for (final header in headers) {
        final src = File(path.join(de265Dir, 'libde265', header));
        if (await src.exists()) {
          await src.copy(path.join(installDir, 'include', 'libde265', header));
        }
      }
    }

    // Copy de265-version.h - it's generated during CMake configure in build_dir/libde265/
    final versionHeaderDest = path.join(installDir, 'include', 'libde265', 'de265-version.h');
    if (!await File(versionHeaderDest).exists()) {
      // The version header is generated in build_dir/libde265/de265-version.h after configure
      final versionHeaderInBuild = File(path.join(buildDir, 'libde265', 'de265-version.h'));
      if (await versionHeaderInBuild.exists()) {
        await versionHeaderInBuild.copy(versionHeaderDest);
        print('✓ Copied de265-version.h from build directory');
      } else {
        // Fallback: search recursively
        final foundVersion = await _findFile(buildDir, 'de265-version.h');
        if (foundVersion != null) {
          await File(foundVersion).copy(versionHeaderDest);
          print('✓ Copied de265-version.h from $foundVersion');
        } else {
          throw Exception('de265-version.h not found after CMake configure. Expected at: ${versionHeaderInBuild.path}');
        }
      }
    }

    // Build only the de265 target
    final result = await runProcessStreaming(
      'cmake',
      ['--build', '.', '--target', 'de265', '--parallel', PlatformDetector.getCpuCores().toString()],
      workingDirectory: buildDir,
      environment: env,
    );

    if (result.exitCode != 0) {
      throw Exception('libde265 build failed: ${result.stderr}');
    }

    // Find and copy library
    final libFile = File(path.join(buildDir, 'libde265', 'libde265.a'));
    if (!await libFile.exists()) {
      // Try to find it
      final found = await _findFile(buildDir, 'libde265.a');
      if (found != null) {
        await File(found).copy(path.join(installDir, 'lib', 'libde265.a'));
      } else {
        throw Exception('libde265.a not found after build');
      }
    } else {
      await libFile.copy(path.join(installDir, 'lib', 'libde265.a'));
    }

    // Create pkg-config file
    final pcContent =
        '''
prefix=$installDir
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libde265
Description: H.265/HEVC decoder library
Version: 1.0.15
Libs: -L\${libdir} -lde265
Cflags: -I\${includedir}
''';
    await FileOps.writeTextFile(path.join(installDir, 'lib', 'pkgconfig', 'libde265.pc'), pcContent);
  }

  Future<void> _buildLibDe265Android({
    required String arch,
    required String abi,
    required String installDir,
    required String ndkHome,
    required String toolchain,
    required String cc,
    required String cxx,
    required String sysroot,
  }) async {
    final de265Dir = getSourceDir('libde265');
    final buildDir = path.join(de265Dir, 'build_android_$abi');

    await FileOps.ensureDirectory(buildDir);
    await FileOps.removeIfExists(buildDir);
    await FileOps.ensureDirectory(buildDir);

    final cmakeArgs = <String>[
      '..',
      '-DCMAKE_BUILD_TYPE=Release',
      '-DCMAKE_INSTALL_PREFIX=$installDir',
      '-DCMAKE_SYSTEM_NAME=Android',
      '-DCMAKE_SYSTEM_PROCESSOR=$arch',
      '-DCMAKE_ANDROID_ARCH_ABI=$abi',
      '-DCMAKE_ANDROID_NDK=$ndkHome',
      '-DCMAKE_ANDROID_STL_TYPE=c++_static',
      '-DCMAKE_C_COMPILER=$cc',
      '-DCMAKE_CXX_COMPILER=$cxx',
      '-DCMAKE_EXE_LINKER_FLAGS=',
      '-DCMAKE_SHARED_LINKER_FLAGS=',
      '-DCMAKE_MODULE_LINKER_FLAGS=',
      '-DCMAKE_POSITION_INDEPENDENT_CODE=ON',
      '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
      '-DBUILD_SHARED_LIBS=OFF',
      '-DENABLE_SDL=OFF',
      '-DENABLE_DEC265=OFF',
      '-DENABLE_ENCODER=OFF',
      '-DCMAKE_C_FLAGS=--sysroot=$sysroot -fPIC',
      '-DCMAKE_CXX_FLAGS=--sysroot=$sysroot -fPIC',
    ];

    final env = <String, String>{};
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

    final buildSystem = CMakeBuildSystem(cmakeArgs: cmakeArgs);
    await buildSystem.configure(
      sourceDir: de265Dir,
      buildDir: buildDir,
      platform: PlatformInfo(platform: BuildPlatform.android),
      environment: cleanEnv,
    );

    final result = await runProcessStreaming(
      'make',
      ['-j', PlatformDetector.getCpuCores().toString()],
      workingDirectory: buildDir,
      environment: cleanEnv,
    );

    if (result.exitCode != 0) {
      throw Exception('libde265 build failed: ${result.stderr}');
    }

    await buildSystem.install(buildDir: buildDir, installDir: installDir);

    // Ensure de265-version.h is present in the Android install as well.
    final versionHeaderDest = path.join(installDir, 'include', 'libde265', 'de265-version.h');
    if (!await File(versionHeaderDest).exists()) {
      final foundVersion = await _findFile(buildDir, 'de265-version.h');
      if (foundVersion != null) {
        await File(foundVersion).copy(versionHeaderDest);
      }
    }
  }

  Future<void> _buildLibHeif({
    required Architecture? arch,
    required String platform,
    required BuildPlatform buildPlatform,
    required String buildDir,
    required String de265Install,
    required List<String> cmakeFlags,
    bool sanitizeEnv = false,
  }) async {
    final heifDir = getSourceDir(sourceName);
    final heifBuildDir = path.join(heifDir, 'build_${platform}_${arch?.name ?? 'default'}');

    await FileOps.ensureDirectory(heifBuildDir);
    await FileOps.removeIfExists(heifBuildDir);
    await FileOps.ensureDirectory(heifBuildDir);

    final cmakeArgs = <String>[
      '..',
      '-DCMAKE_BUILD_TYPE=Release',
      '-DCMAKE_INSTALL_PREFIX=$buildDir',
      '-DCMAKE_POSITION_INDEPENDENT_CODE=ON',
      '-DBUILD_SHARED_LIBS=OFF',
      '-DENABLE_PLUGIN_LOADING=OFF',
      '-DWITH_AOM=OFF',
      '-DWITH_DAV1D=OFF',
      '-DWITH_RAV1E=OFF',
      '-DWITH_X265=OFF',
      '-DWITH_LIBDE265=ON',
      '-DLIBDE265_INCLUDE_DIR=${path.join(de265Install, 'include')}',
      '-DLIBDE265_LIBRARY=${path.join(de265Install, 'lib', 'libde265.a')}',
      '-DWITH_EXAMPLES=OFF',
      '-DWITH_TESTS=OFF',
      '-DWITH_UNCOMPRESSED_CODEC=OFF',
      '-DCMAKE_DISABLE_FIND_PACKAGE_AOM=ON',
      '-DCMAKE_DISABLE_FIND_PACKAGE_libsharpyuv=ON',
      ...cmakeFlags,
    ];

    Map<String, String>? env;
    if (sanitizeEnv) {
      env = Map<String, String>.from(Platform.environment);
      env.remove('LDFLAGS');
      env.remove('LIBRARY_PATH');
      env.remove('DYLD_LIBRARY_PATH');
      env.remove('DYLD_FALLBACK_LIBRARY_PATH');
      env.remove('CPATH');
      env.remove('C_INCLUDE_PATH');
      env.remove('CPLUS_INCLUDE_PATH');
    }

    final buildSystem = CMakeBuildSystem(cmakeArgs: cmakeArgs);
    await buildSystem.configure(
      sourceDir: heifDir,
      buildDir: heifBuildDir,
      platform: PlatformInfo(platform: buildPlatform, architecture: arch),
      environment: env,
    );

    // Build only the heif target
    final result = await runProcessStreaming(
      'make',
      ['-j', PlatformDetector.getCpuCores().toString(), 'heif'],
      workingDirectory: heifBuildDir,
      environment: env,
    );

    if (result.exitCode != 0) {
      throw Exception('libheif build failed: ${result.stderr}');
    }

    // Verify build succeeded by checking for the library
    final expectedLib = File(path.join(heifBuildDir, 'libheif', 'libheif.a'));
    if (!await expectedLib.exists()) {
      final foundLib = await _findFile(heifBuildDir, 'libheif.a');
      if (foundLib == null) {
        throw Exception('libheif.a not found after build - build may have failed');
      }
    }

    // Try cmake install, fallback to manual copy
    final installResult = await runProcessStreaming(
      'cmake',
      ['--install', '.', '--component', 'libheif'],
      workingDirectory: heifBuildDir,
      environment: env,
    );

    // Verify install succeeded and created expected directories
    final installLibDir = Directory(path.join(buildDir, 'lib'));

    if (installResult.exitCode != 0 ||
        !await installLibDir.exists() ||
        !await File(path.join(buildDir, 'lib', 'libheif.a')).exists()) {
      // Fallback to manual copy
      print('CMake install did not create expected files, using manual copy...');
      await FileOps.ensureDirectory(path.join(buildDir, 'lib'));
      await FileOps.ensureDirectory(path.join(buildDir, 'include', 'libheif'));

      final libFile = File(path.join(heifBuildDir, 'libheif', 'libheif.a'));
      if (await libFile.exists()) {
        await libFile.copy(path.join(buildDir, 'lib', 'libheif.a'));
      } else {
        final found = await _findFile(heifBuildDir, 'libheif.a');
        if (found != null) {
          await File(found).copy(path.join(buildDir, 'lib', 'libheif.a'));
        } else {
          throw Exception('libheif.a not found in build directory');
        }
      }

      // Copy headers
      final headerSource = Directory(path.join(heifDir, 'libheif', 'api', 'libheif'));
      if (await headerSource.exists()) {
        await FileOps.copyRecursive(headerSource.path, path.join(buildDir, 'include', 'libheif'));
      }
    }
  }

  Future<void> _buildLibHeifAndroid({
    required String arch,
    required String abi,
    required String buildDir,
    required String de265Install,
    required String ndkHome,
    required String toolchain,
    required String cc,
    required String cxx,
    required String sysroot,
  }) async {
    final heifDir = getSourceDir(sourceName);
    final heifBuildDir = path.join(heifDir, 'build_android_$abi');

    await FileOps.ensureDirectory(heifBuildDir);
    await FileOps.removeIfExists(heifBuildDir);
    await FileOps.ensureDirectory(heifBuildDir);

    final cmakeArgs = <String>[
      '..',
      '-DCMAKE_BUILD_TYPE=Release',
      '-DCMAKE_INSTALL_PREFIX=$buildDir',
      '-DCMAKE_SYSTEM_NAME=Android',
      '-DCMAKE_SYSTEM_PROCESSOR=$arch',
      '-DCMAKE_ANDROID_ARCH_ABI=$abi',
      '-DCMAKE_ANDROID_NDK=$ndkHome',
      '-DCMAKE_ANDROID_STL_TYPE=c++_static',
      '-DCMAKE_C_COMPILER=$cc',
      '-DCMAKE_CXX_COMPILER=$cxx',
      '-DCMAKE_EXE_LINKER_FLAGS=',
      '-DCMAKE_SHARED_LINKER_FLAGS=',
      '-DCMAKE_MODULE_LINKER_FLAGS=',
      '-DCMAKE_POSITION_INDEPENDENT_CODE=ON',
      '-DBUILD_SHARED_LIBS=OFF',
      '-DENABLE_PLUGIN_LOADING=OFF',
      '-DWITH_AOM=OFF',
      '-DWITH_DAV1D=OFF',
      '-DWITH_RAV1E=OFF',
      '-DWITH_X265=OFF',
      '-DWITH_LIBDE265=ON',
      '-DLIBDE265_INCLUDE_DIR=${path.join(de265Install, 'include')}',
      '-DLIBDE265_LIBRARY=${path.join(de265Install, 'lib', 'libde265.a')}',
      '-DWITH_EXAMPLES=OFF',
      '-DWITH_TESTS=OFF',
      '-DWITH_UNCOMPRESSED_CODEC=OFF',
      '-DCMAKE_DISABLE_FIND_PACKAGE_AOM=ON',
      '-DCMAKE_DISABLE_FIND_PACKAGE_libsharpyuv=ON',
      '-DCMAKE_C_FLAGS=--sysroot=$sysroot -fPIC',
      '-DCMAKE_CXX_FLAGS=--sysroot=$sysroot -fPIC',
    ];

    final env = <String, String>{};
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

    final buildSystem = CMakeBuildSystem(cmakeArgs: cmakeArgs);
    await buildSystem.configure(
      sourceDir: heifDir,
      buildDir: heifBuildDir,
      platform: PlatformInfo(platform: BuildPlatform.android),
      environment: cleanEnv,
    );

    final result = await runProcessStreaming(
      'make',
      ['-j', PlatformDetector.getCpuCores().toString(), 'heif'],
      workingDirectory: heifBuildDir,
      environment: cleanEnv,
    );

    if (result.exitCode != 0) {
      throw Exception('libheif build failed: ${result.stderr}');
    }

    // Try cmake install, fallback to manual copy
    final installResult = await runProcessStreaming(
      'cmake',
      ['--install', '.', '--component', 'libheif'],
      workingDirectory: heifBuildDir,
      environment: cleanEnv,
    );

    // Verify install succeeded and created expected directories
    final installLibDir = Directory(path.join(buildDir, 'lib'));

    if (installResult.exitCode != 0 ||
        !await installLibDir.exists() ||
        !await File(path.join(buildDir, 'lib', 'libheif.a')).exists()) {
      // Fallback to manual copy
      print('CMake install did not create expected files, using manual copy...');
      await FileOps.ensureDirectory(path.join(buildDir, 'lib'));
      await FileOps.ensureDirectory(path.join(buildDir, 'include', 'libheif'));

      final libFile = File(path.join(heifBuildDir, 'libheif', 'libheif.a'));
      if (await libFile.exists()) {
        await libFile.copy(path.join(buildDir, 'lib', 'libheif.a'));
      } else {
        final found = await _findFile(heifBuildDir, 'libheif.a');
        if (found != null) {
          await File(found).copy(path.join(buildDir, 'lib', 'libheif.a'));
        } else {
          throw Exception('libheif.a not found in build directory');
        }
      }

      // Copy headers
      final headerSource = Directory(path.join(heifDir, 'libheif', 'api', 'libheif'));
      if (await headerSource.exists()) {
        await FileOps.copyRecursive(headerSource.path, path.join(buildDir, 'include', 'libheif'));
      }
    }
  }

  Future<String?> _findFile(String dir, String filename) async {
    try {
      await for (final entity in Directory(dir).list(recursive: true)) {
        if (entity is File && path.basename(entity.path) == filename) {
          return entity.path;
        }
      }
    } catch (e) {
      // Ignore
    }
    return null;
  }
}
