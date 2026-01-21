// Platform detection and configuration
import 'dart:io';
import 'package:path/path.dart' as path;
import '../utils/process.dart';

enum BuildPlatform { macos, ios, android, linux, windows }

enum Architecture { arm64, x86_64, aarch64 }

class PlatformInfo {
  final BuildPlatform platform;
  final Architecture? architecture;
  final String? sdkPath;
  final Map<String, String> environment;

  PlatformInfo({required this.platform, this.architecture, this.sdkPath, Map<String, String>? environment})
    : environment = environment ?? {};

  String get name {
    switch (platform) {
      case BuildPlatform.macos:
        return 'macos';
      case BuildPlatform.ios:
        return 'ios';
      case BuildPlatform.android:
        return 'android';
      case BuildPlatform.linux:
        return 'linux';
      case BuildPlatform.windows:
        return 'windows';
    }
  }

  String get archName {
    switch (architecture) {
      case Architecture.arm64:
        return 'arm64';
      case Architecture.x86_64:
        return 'x86_64';
      case Architecture.aarch64:
        return 'aarch64';
      case null:
        return 'unknown';
    }
  }
}

class PlatformDetector {
  static BuildPlatform detectHostPlatform() {
    final os = Platform.operatingSystem;
    switch (os) {
      case 'macos':
        return BuildPlatform.macos;
      case 'linux':
        return BuildPlatform.linux;
      case 'windows':
        return BuildPlatform.windows;
      default:
        throw Exception('Unsupported host platform: $os');
    }
  }

  static Architecture detectHostArchitecture() {
    final arch = Platform.version.contains('arm64') || Platform.version.contains('aarch64')
        ? Architecture.arm64
        : Architecture.x86_64;

    // More reliable detection
    if (Platform.isMacOS || Platform.isLinux) {
      try {
        final result = Process.runSync('uname', ['-m']);
        final output = result.stdout.toString().trim().toLowerCase();
        if (output.contains('arm64') || output.contains('aarch64')) {
          return Architecture.arm64;
        } else if (output.contains('x86_64') || output.contains('amd64')) {
          return Architecture.x86_64;
        }
      } catch (e) {
        // Fallback to default
      }
    }

    return arch;
  }

  static int getCpuCores() {
    if (Platform.isMacOS || Platform.isLinux) {
      try {
        final result = Process.runSync('nproc', []);
        return int.tryParse(result.stdout.toString().trim()) ?? 4;
      } catch (e) {
        try {
          final result = Process.runSync('sysctl', ['-n', 'hw.ncpu']);
          return int.tryParse(result.stdout.toString().trim()) ?? 4;
        } catch (e) {
          return 4;
        }
      }
    } else if (Platform.isWindows) {
      // Windows: use environment variable or default
      final cores = Platform.environment['NUMBER_OF_PROCESSORS'];
      return int.tryParse(cores ?? '4') ?? 4;
    }
    return 4;
  }

  static Future<String?> findXcodeSdkPath(String sdk) async {
    if (!Platform.isMacOS) return null;

    try {
      final result = await runProcessStreaming('xcrun', ['--sdk', sdk, '--show-sdk-path']);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (e) {
      // Ignore
    }
    return null;
  }

  static Future<String?> findXcodeCompiler(String sdk, {bool cxx = false}) async {
    if (!Platform.isMacOS) return null;

    try {
      final compiler = cxx ? 'clang++' : 'clang';
      final result = await runProcessStreaming('xcrun', ['--sdk', sdk, '--find', compiler]);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (e) {
      // Ignore
    }
    return null;
  }

  static Future<String?> findAndroidNdk() async {
    final ndkHome = Platform.environment['ANDROID_NDK_HOME'] ?? Platform.environment['ANDROID_NDK_ROOT'];
    if (ndkHome != null && ndkHome.isNotEmpty) {
      final dir = Directory(ndkHome);
      if (await dir.exists()) {
        return ndkHome;
      }
    }
    return null;
  }

  static Future<String?> findAndroidToolchain(String ndkHome) async {
    final hostOs = Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
        ? 'darwin'
        : 'linux';
    final hostArch = detectHostArchitecture();
    final hostTag = '$hostOs-${hostArch == Architecture.arm64 ? "arm64" : "x86_64"}';

    // Try detected tag first
    var toolchain = path.join(ndkHome, 'toolchains', 'llvm', 'prebuilt', hostTag);
    if (await Directory(toolchain).exists()) {
      return toolchain;
    }

    // Fallback: try darwin-x86_64 on macOS (Rosetta)
    if (Platform.isMacOS && hostArch == Architecture.arm64) {
      toolchain = path.join(ndkHome, 'toolchains', 'llvm', 'prebuilt', 'darwin-x86_64');
      if (await Directory(toolchain).exists()) {
        return toolchain;
      }
    }

    // Last resort: find any prebuilt directory
    final prebuiltDir = Directory(path.join(ndkHome, 'toolchains', 'llvm', 'prebuilt'));
    if (await prebuiltDir.exists()) {
      final entries = await prebuiltDir.list().toList();
      if (entries.isNotEmpty) {
        return entries.first.path;
      }
    }

    return null;
  }
}
