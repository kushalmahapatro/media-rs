#!/usr/bin/env dart
// Complete Dart-based cross-platform build system for media-rs
// This replaces all bash scripts with pure Dart implementation

import 'dart:io';
import 'package:path/path.dart' as path;
import 'setup/platforms/platform.dart';
import 'setup/builders/ffmpeg_builder.dart';
import 'setup/builders/openh264_builder.dart';
import 'setup/builders/libheif_builder.dart';

void main(List<String> args) async {
  final projectRoot = path.absolute(path.current);
  final script = SetupScript(projectRoot);

  final options = parseArgs(args);

  if (options['help'] == true) {
    printUsage();
    exit(0);
  }

  await script.run(options);
}

void printUsage() {
  print('''
Usage: dart tool/setup.dart [options]

Options:
  --all              Build for all platforms
  --macos            Build for macOS
  --ios              Build for iOS (macOS host only)
  --android          Build for Android
  --linux            Build for Linux
  --windows          Build for Windows
  --skip-openh264    Skip OpenH264 build
  -h, --help         Show this help message

Defaults:
  - On macOS: builds macos + ios + android
  - On Linux: builds linux + android
  - On Windows: builds windows + android

Environment:
  - ANDROID_NDK_HOME: required for --android
''');
}

Map<String, dynamic> parseArgs(List<String> args) {
  final options = <String, dynamic>{
    'all': false,
    'macos': false,
    'ios': false,
    'android': false,
    'linux': false,
    'windows': false,
    'skip_openh264': false,
    'help': false,
  };

  for (final arg in args) {
    switch (arg) {
      case '--all':
        options['all'] = true;
        break;
      case '--macos':
        options['macos'] = true;
        break;
      case '--ios':
        options['ios'] = true;
        break;
      case '--android':
        options['android'] = true;
        break;
      case '--linux':
        options['linux'] = true;
        break;
      case '--windows':
        options['windows'] = true;
        break;
      case '--skip-openh264':
        options['skip_openh264'] = true;
        break;
      case '--skip-ffmpeg':
        options['skip_ffmpeg'] = true;
        break;
      case '-h':
      case '--help':
        options['help'] = true;
        break;
      default:
        print('Unknown argument: $arg');
        printUsage();
        exit(2);
    }
  }

  // Set defaults if no platform specified
  if (!options['macos'] && !options['ios'] && !options['android'] && !options['linux'] && !options['windows']) {
    final hostOS = Platform.operatingSystem;
    if (hostOS == 'macos') {
      options['macos'] = true;
      options['ios'] = true;
      options['android'] = true;
    } else if (hostOS == 'linux') {
      options['linux'] = true;
      options['android'] = true;
    } else if (hostOS == 'windows') {
      options['windows'] = true;
      options['android'] = true;
    }
  }

  if (options['all'] == true) {
    options['macos'] = true;
    options['ios'] = true;
    options['android'] = true;
    options['linux'] = true;
    options['windows'] = true;
  }

  return options;
}

class SetupScript {
  final String projectRoot;
  final String hostOS;

  SetupScript(this.projectRoot) : hostOS = Platform.operatingSystem;

  Future<void> run(Map<String, dynamic> options) async {
    print('Repository: $projectRoot');
    print('Host OS: $hostOS');
    print(
      'Targets: macos=${options['macos']} ios=${options['ios']} '
      'android=${options['android']} linux=${options['linux']} '
      'windows=${options['windows']}',
    );
    print('');

    final skipOpenH264 = options['skip_openh264'] == true;

    // macOS builds
    if (options['macos'] == true) {
      if (hostOS != 'macos') {
        print('Skipping macOS deps: host is not macOS.');
      } else {
        await _buildMacOS(skipOpenH264);
      }
    }

    // iOS builds
    if (options['ios'] == true) {
      if (hostOS != 'macos') {
        print('Skipping iOS deps: host is not macOS.');
      } else {
        await _buildIOS(skipOpenH264);
      }
    }

    // Android builds
    if (options['android'] == true) {
      final ndkHome = await PlatformDetector.findAndroidNdk();
      if (ndkHome == null) {
        print('ERROR: ANDROID_NDK_HOME is required for Android builds.');
        exit(2);
      }
      await _buildAndroid(skipOpenH264);
    }

    // Linux builds
    if (options['linux'] == true) {
      if (hostOS != 'linux') {
        print('Skipping Linux deps: host is not Linux.');
      } else {
        await _buildLinux(skipOpenH264);
      }
    }

    // Windows builds
    if (options['windows'] == true) {
      if (hostOS != 'windows') {
        print('Skipping Windows deps: host is not Windows.');
      } else {
        await _buildWindows(skipOpenH264, options);
      }
    }

    print('');
    print('Done. third_party installs are ready.');
  }

  Future<void> _buildMacOS(bool skipOpenH264) async {
    print('=== macOS: libheif (universal) ===');
    final libheifBuilder = LibHeifBuilder(projectRoot);
    await libheifBuilder.build(PlatformInfo(platform: BuildPlatform.macos));

    print('=== macOS: FFmpeg (universal) ===');
    final builder = FFmpegBuilder(projectRoot);
    await builder.build(PlatformInfo(platform: BuildPlatform.macos), skipOpenH264: skipOpenH264);
  }

  Future<void> _buildIOS(bool skipOpenH264) async {
    print('=== iOS: libheif ===');
    final libheifBuilder = LibHeifBuilder(projectRoot);
    await libheifBuilder.build(PlatformInfo(platform: BuildPlatform.ios));

    print('=== iOS: FFmpeg ===');
    final builder = FFmpegBuilder(projectRoot);
    await builder.build(PlatformInfo(platform: BuildPlatform.ios), skipOpenH264: skipOpenH264);
  }

  Future<void> _buildAndroid(bool skipOpenH264) async {
    if (!skipOpenH264) {
      print('=== Android: OpenH264 ===');
      final openh264Builder = OpenH264Builder(projectRoot);
      await openh264Builder.build(PlatformInfo(platform: BuildPlatform.android));
    }

    print('=== Android: libheif ===');
    final libheifBuilder = LibHeifBuilder(projectRoot);
    await libheifBuilder.build(PlatformInfo(platform: BuildPlatform.android));

    print('=== Android: FFmpeg ===');
    final builder = FFmpegBuilder(projectRoot);
    await builder.build(PlatformInfo(platform: BuildPlatform.android), skipOpenH264: skipOpenH264);
  }

  Future<void> _buildLinux(bool skipOpenH264) async {
    if (!skipOpenH264) {
      print('=== Linux: OpenH264 ===');
      final openh264Builder = OpenH264Builder(projectRoot);
      await openh264Builder.build(PlatformInfo(platform: BuildPlatform.linux));
    }

    print('=== Linux: libheif ===');
    final libheifBuilder = LibHeifBuilder(projectRoot);
    await libheifBuilder.build(PlatformInfo(platform: BuildPlatform.linux));

    print('=== Linux: FFmpeg ===');
    final builder = FFmpegBuilder(projectRoot);
    await builder.build(PlatformInfo(platform: BuildPlatform.linux), skipOpenH264: skipOpenH264);
  }

  Future<void> _buildWindows(bool skipOpenH264, Map<String, dynamic> options) async {
    if (!skipOpenH264) {
      print('=== Windows: OpenH264 ===');
      final openh264Builder = OpenH264Builder(projectRoot);
      await openh264Builder.build(PlatformInfo(platform: BuildPlatform.windows));
    }

    if (options['skip_ffmpeg'] != true) {
      print('=== Windows: FFmpeg ===');
      final builder = FFmpegBuilder(projectRoot);
      try {
        await builder.build(PlatformInfo(platform: BuildPlatform.windows), skipOpenH264: skipOpenH264);
      } catch (e) {
        print('WARNING: FFmpeg build failed: $e');
        print('Continuing to build libheif...');
      }
    } else {
      print('Skipping FFmpeg build (--skip-ffmpeg)...');
    }

    print('=== Windows: libheif (MinGW) ===');
    final libheifBuilder = LibHeifBuilder(projectRoot);
    await libheifBuilder.build(PlatformInfo(platform: BuildPlatform.windows));

    // After MinGW build, rebuild with MSVC to generate .lib files
    // This matches the old setup_all.bat behavior which called build_libheif_msvc.bat
    print('');
    print('=== Windows: Converting libheif to MSVC format ===');
    print('');
    print('NOTE: MinGW-built libheif has COMDAT incompatibility with MSVC linker.');
    print('Rebuilding libheif with MSVC to generate .lib files...');
    print('This will take 10-15 minutes.');
    print('');

    try {
      await libheifBuilder.buildMSVC(PlatformInfo(platform: BuildPlatform.windows));
      print('');
      print('========================================');
      print('SUCCESS: MSVC-built libheif installed!');
      print('========================================');
      print('');
      print('The MSVC-compatible libraries (.lib files) are now ready.');
      print('You can now run: flutter build windows');
      print('');
    } catch (e) {
      print('');
      print('WARNING: MSVC build failed or Visual Studio not found.');
      print('');
      print('The MinGW-built libraries are installed, but they may have COMDAT issues.');
      print('To fix this, you can:');
      print('  1. Install Visual Studio 2022 with C++ development tools');
      print('  2. Ensure CMake can find Visual Studio');
      print('  3. Run the setup again');
      print('');
      print('Error: $e');
      print('');
      print('Continuing with MinGW-built libraries (may cause linker errors)...');
      print('');
    }
  }
}
