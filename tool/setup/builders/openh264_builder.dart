// OpenH264 builder
import 'dart:io';
import 'package:path/path.dart' as path;
import '../platforms/platform.dart';
import '../utils/git.dart';
import '../utils/file_ops.dart';
import '../utils/process.dart';
import 'base_builder.dart';

class OpenH264Builder extends BaseBuilder {
  static const String repository = 'https://github.com/cisco/openh264.git';
  static const String branch = 'master';

  OpenH264Builder(super.projectRoot);

  @override
  String getName() => 'openh264';

  @override
  String getLibraryName() => 'libopenh264.a';

  @override
  Future<void> downloadSource() async {
    final sourceDir = getSourceDir('openh264');
    final checkFile = path.join(sourceDir, 'Makefile');

    if (await FileOps.exists(checkFile)) {
      print('OpenH264 source already downloaded');
      return;
    }

    // Remove incomplete download
    if (await Directory(sourceDir).exists()) {
      print('Removing incomplete OpenH264 source...');
      await FileOps.removeIfExists(sourceDir);
    }

    try {
      await Git.clone(repository, sourceDir, branch: branch, depth: 1);
    } catch (e) {
      print('Git clone failed, trying alternative method...');
      // Could implement tarball download as fallback
      rethrow;
    }
  }

  @override
  Future<void> buildForPlatform(PlatformInfo platform, {bool skipOpenH264 = false}) async {
    switch (platform.platform) {
      case BuildPlatform.android:
        await _buildAndroid(platform);
        break;
      case BuildPlatform.linux:
        await _buildLinux(platform);
        break;
      case BuildPlatform.windows:
        await _buildWindows(platform);
        break;
      case BuildPlatform.macos:
      case BuildPlatform.ios:
        // OpenH264 is optional on macOS/iOS (VideoToolbox is used instead)
        print('OpenH264 is optional on ${platform.name}, skipping...');
        break;
    }
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

    // Android ABIs to build
    final abis = [
      {
        'abi': 'arm64-v8a',
        'api': 21,
        // CPU name used by OpenH264 makefiles.
        'cpu': 'arm64',
        // Toolchain target triple prefix used by NDK clang.
        'toolchainArch': 'aarch64',
      },
      {
        'abi': 'x86_64',
        'api': 21,
        'cpu': 'x86_64',
        'toolchainArch': 'x86_64',
      },
    ];

    for (final abiInfo in abis) {
      final abi = abiInfo['abi'] as String;
      final apiLevel = abiInfo['api'] as int;
      final cpu = abiInfo['cpu'] as String;
      final toolchainArch = abiInfo['toolchainArch'] as String;

      print('Building OpenH264 for Android $abi (API $apiLevel)...');

      final buildDir = path.join(generatedDir, 'openh264_build_android_$abi');
      final installDir = path.join(generatedDir, 'openh264_install', 'android', abi);
      final sourceDir = getSourceDir('openh264');

      await FileOps.ensureDirectory(buildDir);
      await FileOps.ensureDirectory(installDir);

      // Set up Android toolchain.
      // NOTE: For 64-bit ARM, the NDK uses 'aarch64-linux-android' as the
      // target triple, not 'arm64-linux-android'.
      final cc = path.join(toolchain, 'bin', '${toolchainArch}-linux-android$apiLevel-clang');
      final cxx = path.join(toolchain, 'bin', '${toolchainArch}-linux-android$apiLevel-clang++');
      final ar = path.join(toolchain, 'bin', 'llvm-ar');
      final ranlib = path.join(toolchain, 'bin', 'llvm-ranlib');
      final sysroot = path.join(toolchain, 'sysroot');

      // Check if already built and validate
      final expectedLib = path.join(installDir, 'lib', 'libopenh264.a');
      if (await FileOps.exists(expectedLib)) {
        // Validate library integrity, especially for x86_64 which had issues with cpu-features
        bool isValid = true;
        if (abi == 'x86_64') {
          try {
            final arCheck = await runProcessStreaming(ar, ['t', expectedLib], workingDirectory: sourceDir);
            if (arCheck.exitCode != 0) {
              print('⚠ OpenH264 library for $abi appears corrupted (ar failed), will rebuild...');
              isValid = false;
            } else {
              // Check if cpu-features.o exists and might be incompatible
              final output = arCheck.stdout;
              if (output.contains('cpu-features.o')) {
                // Try to extract and check the object file
                // For now, if we detect cpu-features.o in x86_64, rebuild to be safe
                // (The cleanup should have removed it, so if it's there, it might be from an old build)
                print('⚠ OpenH264 library for $abi contains cpu-features.o, will rebuild to ensure compatibility...');
                isValid = false;
              }
            }
          } catch (e) {
            print('⚠ Could not validate OpenH264 library for $abi, will rebuild: $e');
            isValid = false;
          }
        }
        
        if (isValid) {
          print('OpenH264 already built for Android $abi, skipping...');
          continue;
        } else {
          // Remove corrupted library and rebuild
          print('Removing corrupted OpenH264 library for $abi...');
          await FileOps.removeIfExists(expectedLib);
          await FileOps.removeIfExists(path.join(installDir, 'lib', 'pkgconfig', 'openh264.pc'));
        }
      }

      // Verify toolchain binaries exist
      if (!await FileOps.exists(cc)) {
        throw Exception('C compiler not found: $cc\nPlease check your Android NDK installation.');
      }
      if (!await FileOps.exists(cxx)) {
        throw Exception('C++ compiler not found: $cxx\nPlease check your Android NDK installation.');
      }

      // Build extra CFLAGS based on architecture (to override Makefile's -arch flags)
      final extraCflags = <String>['-fPIC'];
      if (cpu == 'arm64') {
        extraCflags.add('-march=armv8-a');
      } else if (cpu == 'x86_64') {
        extraCflags.addAll(['-march=x86-64', '-msse4.2', '-mpopcnt', '-m64']);
      }
      extraCflags.add('-I${path.join(sysroot, 'usr', 'include')}');

      // Verify that cpu-features.c exists (required by OpenH264's Makefile)
      final cpuFeaturesFile = path.join(ndkHome, 'sources', 'android', 'cpufeatures', 'cpu-features.c');
      if (!await FileOps.exists(cpuFeaturesFile)) {
        throw Exception(
          'Required file not found: $cpuFeaturesFile\n'
          'This file is required by OpenH264\'s Android build.\n'
          'Please ensure you have a complete Android NDK installation.',
        );
      }

      // For x86_64, disable assembly to avoid requiring nasm
      final disableAsm = cpu == 'x86_64';

      final env = <String, String>{
        'CC': cc,
        'CXX': cxx,
        'AR': ar,
        'RANLIB': ranlib,
        'SYSROOT': sysroot,
        'PREFIX': installDir,
        'OS': 'android',
        'ARCH': cpu, // OpenH264 Makefile expects: arm, arm64, x86, x86_64
        'TARGET': 'android-$apiLevel',
        'NDKROOT': ndkHome,
        'NDKLEVEL': apiLevel.toString(), // Explicitly set NDKLEVEL to ensure compiler path is correct
        // Explicitly set CFLAGS/CXXFLAGS to override Makefile's -arch flags
        'CFLAGS': extraCflags.join(' '),
        'CXXFLAGS': extraCflags.join(' '),
        'LDFLAGS': '-L${path.join(sysroot, 'usr', 'lib')}',
      };

      if (disableAsm) {
        env['USE_ASM'] = 'No';
        print('INFO: Disabling assembly optimizations for $abi (nasm not required)');
      }

      // Clean previous build thoroughly (important to avoid cached paths)
      try {
        await runProcessStreaming('make', ['clean'], workingDirectory: sourceDir);
        // Remove all object files and dependency files that might have cached paths
        final sourceDirObj = Directory(sourceDir);
        if (await sourceDirObj.exists()) {
          await for (final entity in sourceDirObj.list(recursive: true)) {
            if (entity is File) {
              final fileName = path.basename(entity.path);
              // Remove object files, dependency files, and specifically cpu-features files
              if (entity.path.endsWith('.o') || 
                  entity.path.endsWith('.d') || 
                  fileName == '.depend' ||
                  fileName.startsWith('cpu-features.')) {
                try {
                  await entity.delete();
                } catch (e) {
                  // Ignore deletion errors
                }
              }
            }
          }
        }
      } catch (e) {
        // Ignore cleanup errors - might be nothing to clean
      }

      // Build static library only (skip shared library and demo apps)
      // OpenH264's Makefile may add -arch flags which Android NDK doesn't support,
      // so we explicitly set CFLAGS/CXXFLAGS to override them
      print('Building OpenH264...');
      final makeArgs = <String>[
        '-j',
        PlatformDetector.getCpuCores().toString(),
        'OS=android',
        "ARCH=$cpu",
        "TARGET=android-$apiLevel",
      ];
      
      // Pass USE_ASM=No if we're disabling assembly
      if (disableAsm) {
        makeArgs.add('USE_ASM=No');
      }
      
      makeArgs.add('libopenh264.a'); // Build only the static library target
      
      final buildResult = await runProcessStreaming(
        'make',
        makeArgs,
        workingDirectory: sourceDir,
        environment: env,
      );

      if (buildResult.exitCode != 0) {
        throw Exception('OpenH264 build failed: ${buildResult.stderr}');
      }

      // Install
      await FileOps.ensureDirectory(path.join(installDir, 'lib'));
      await FileOps.ensureDirectory(path.join(installDir, 'include', 'wels'));
      await FileOps.ensureDirectory(path.join(installDir, 'lib', 'pkgconfig'));

      // Copy library and validate
      final libFile = File(path.join(sourceDir, 'libopenh264.a'));
      if (await libFile.exists()) {
        final installLibPath = path.join(installDir, 'lib', 'libopenh264.a');
        await libFile.copy(installLibPath);
        // Validate the library file exists and has content
        final installedLib = File(installLibPath);
        if (!await installedLib.exists()) {
          throw Exception('Failed to copy libopenh264.a to $installLibPath');
        }
        final stat = await installedLib.stat();
        if (stat.size == 0) {
          throw Exception('libopenh264.a is empty - build may have failed');
        }
        print('✓ OpenH264 library installed: $installLibPath (${(stat.size / 1024 / 1024).toStringAsFixed(2)} MB)');
      } else {
        throw Exception('libopenh264.a not found after build in $sourceDir');
      }

      // Copy headers
      final headerDir = Directory(path.join(sourceDir, 'codec', 'api', 'wels'));
      if (await headerDir.exists()) {
        await FileOps.copyRecursive(
          headerDir.path,
          path.join(installDir, 'include', 'wels'),
        );
      }

      // Create pkg-config file
      final pcContent = '''
prefix=$installDir
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: openh264
Description: OpenH264 codec library
Version: 2.3.1
Libs: -L\${libdir} -lopenh264
Cflags: -I\${includedir}
''';
      await FileOps.writeTextFile(
        path.join(installDir, 'lib', 'pkgconfig', 'openh264.pc'),
        pcContent,
      );

      print('OpenH264 installed: $installDir');
    }
  }

  Future<void> _buildLinux(PlatformInfo platform) async {
    final arch = PlatformDetector.detectHostArchitecture();
    final abiDir = arch == Architecture.arm64 ? 'arm64' : 'x86_64';
    final cpu = arch == Architecture.arm64 ? 'arm64' : 'x86_64';

    print('Building OpenH264 for Linux $abiDir...');

    final buildDir = path.join(generatedDir, 'openh264_build_linux_$abiDir');
    final installDir = path.join(generatedDir, 'openh264_install', 'linux', abiDir);
    final sourceDir = getSourceDir('openh264');

    await FileOps.ensureDirectory(buildDir);
    await FileOps.ensureDirectory(installDir);

    final env = <String, String>{
      'PREFIX': installDir,
      'OS': 'linux',
      'ARCH': cpu,
    };

    // Clean previous build
    await runProcessStreaming('make', ['clean'], workingDirectory: sourceDir);

    // Build
    print('Building OpenH264...');
    final buildResult = await runProcessStreaming(
      'make',
      ['-j', PlatformDetector.getCpuCores().toString()],
      workingDirectory: sourceDir,
      environment: env,
    );

    if (buildResult.exitCode != 0) {
      throw Exception('OpenH264 build failed: ${buildResult.stderr}');
    }

    // Install
    await FileOps.ensureDirectory(path.join(installDir, 'lib'));
    await FileOps.ensureDirectory(path.join(installDir, 'include', 'wels'));
    await FileOps.ensureDirectory(path.join(installDir, 'lib', 'pkgconfig'));

    // Copy library
    final libFile = File(path.join(sourceDir, 'libopenh264.a'));
    if (await libFile.exists()) {
      await libFile.copy(path.join(installDir, 'lib', 'libopenh264.a'));
    } else {
      throw Exception('libopenh264.a not found after build');
    }

    // Copy headers
    final headerDir = Directory(path.join(sourceDir, 'codec', 'api', 'wels'));
    if (await headerDir.exists()) {
      await FileOps.copyRecursive(
        headerDir.path,
        path.join(installDir, 'include', 'wels'),
      );
    }

    // Create pkg-config file
    final pcContent = '''
prefix=$installDir
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: openh264
Description: OpenH264 codec library
Version: 2.3.1
Libs: -L\${libdir} -lopenh264
Cflags: -I\${includedir}
''';
    await FileOps.writeTextFile(
      path.join(installDir, 'lib', 'pkgconfig', 'openh264.pc'),
      pcContent,
    );

    print('OpenH264 installed: $installDir');
  }

  Future<void> _buildWindows(PlatformInfo platform) async {
    throw UnimplementedError('Windows build not yet fully implemented in Dart');
  }
}

