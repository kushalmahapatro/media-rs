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

  /// Get MSYS2 root directory (default: C:\msys64)
  static String getMsys2Root() {
    return Platform.environment['MSYS2_ROOT'] ?? r'C:\msys64';
  }

  /// Convert Windows path to MSYS2 Unix-style path
  /// Example: D:\media-rs\media-rs -> /d/media-rs/media-rs
  static String windowsToMsys2Path(String windowsPath) {
    if (!Platform.isWindows) {
      return windowsPath;
    }
    // Convert backslashes to forward slashes
    var unixPath = windowsPath.replaceAll('\\', '/');
    // Convert drive letter (e.g., D:/ -> /d/)
    unixPath = unixPath.replaceAllMapped(RegExp(r'^([A-Z]):/'), (match) {
      return '/${match.group(1)!.toLowerCase()}/';
    });
    return unixPath;
  }

  /// Find MinGW-w64 compiler for Windows builds
  /// Returns the compiler name (not full path, like bash script) and cross-prefix (if any)
  /// This matches the bash script behavior which uses command names directly
  static Future<({String cc, String? crossPrefix})> findMinGWCompiler() async {
    if (!Platform.isWindows) {
      throw Exception('findMinGWCompiler only works on Windows');
    }

    final msys2Root = getMsys2Root();
    final usrBin = path.join(msys2Root, 'usr', 'bin');
    final mingwBin = path.join(msys2Root, 'mingw64', 'bin');
    final env = Map<String, String>.from(Platform.environment);
    env['PATH'] = '$usrBin;$mingwBin;${env['PATH'] ?? ''}';

    // Try x86_64-w64-mingw32-gcc first (cross-compiler) - match bash script behavior
    // Try both with and without .exe extension
    // Use runInShell: true on Windows to properly resolve commands from PATH
    for (final gccName in ['x86_64-w64-mingw32-gcc.exe', 'x86_64-w64-mingw32-gcc']) {
      try {
        final result = await runProcessStreaming(gccName, ['--version'], environment: env, runInShell: true);
        if (result.exitCode == 0) {
          // Check if all required tools are available (nm, ar, ranlib, strip)
          // Check by file existence rather than running commands, as some tools don't support --version
          bool allToolsFound = true;
          final requiredTools = ['nm', 'ar', 'ranlib', 'strip'];
          for (final tool in requiredTools) {
            final toolPath = path.join(mingwBin, 'x86_64-w64-mingw32-$tool.exe');
            if (!await File(toolPath).exists()) {
              allToolsFound = false;
              break;
            }
          }
          
          if (allToolsFound) {
            // Use the base name without .exe for consistency with bash script
            return (cc: 'x86_64-w64-mingw32-gcc', crossPrefix: 'x86_64-w64-mingw32-');
          } else {
            // Some tools missing, use without cross-prefix
            return (cc: 'x86_64-w64-mingw32-gcc', crossPrefix: null);
          }
        }
      } catch (e) {
        // Not found, try next name
        continue;
      }
    }

    // Try gcc (native MinGW) - match bash script behavior
    // Try both with and without .exe extension
    // Use runInShell: true on Windows to properly resolve commands from PATH
    for (final gccName in ['gcc.exe', 'gcc']) {
      try {
        final result = await runProcessStreaming(gccName, ['-dumpmachine'], environment: env, runInShell: true);
        if (result.exitCode == 0) {
          final output = result.stdout.toString().trim();
          if (output.contains('mingw')) {
            // Use the base name without .exe for consistency with bash script
            return (cc: 'gcc', crossPrefix: null);
          }
        }
      } catch (e) {
        // Not found, try next name
        continue;
      }
    }

    // Fallback: check if files exist directly (in case PATH resolution fails)
    final possibleGccPaths = [
      path.join(mingwBin, 'x86_64-w64-mingw32-gcc.exe'),
      path.join(mingwBin, 'gcc.exe'),
    ];

    for (final gccPath in possibleGccPaths) {
      if (await File(gccPath).exists()) {
        final basename = path.basenameWithoutExtension(gccPath);
        // Check if it's the cross-compiler
        if (basename == 'x86_64-w64-mingw32-gcc') {
          final nmPath = path.join(mingwBin, 'x86_64-w64-mingw32-nm.exe');
          if (await File(nmPath).exists()) {
            return (cc: 'x86_64-w64-mingw32-gcc', crossPrefix: 'x86_64-w64-mingw32-');
          }
          return (cc: 'x86_64-w64-mingw32-gcc', crossPrefix: null);
        } else {
          return (cc: 'gcc', crossPrefix: null);
        }
      }
    }

    throw Exception(
      'MinGW-w64 compiler not found.\n'
      'Install with: pacman -S mingw-w64-x86_64-gcc\n'
      'Or set MSYS2_ROOT environment variable if MSYS2 is installed elsewhere.\n'
      'Checked paths: $mingwBin, $usrBin',
    );
  }

  /// Find make executable in MSYS2
  static Future<String> findMake() async {
    if (!Platform.isWindows) {
      return 'make';
    }

    final msys2Root = getMsys2Root();
    final possiblePaths = [
      path.join(msys2Root, 'usr', 'bin', 'make.exe'),
      path.join(msys2Root, 'mingw64', 'bin', 'make.exe'),
      path.join(msys2Root, 'usr', 'bin', 'make'),
    ];

    for (final makePath in possiblePaths) {
      if (await File(makePath).exists()) {
        return makePath;
      }
    }

    // Fallback: try to find make in PATH (with environment that includes MSYS2)
    try {
      final usrBin = path.join(msys2Root, 'usr', 'bin');
      final mingwBin = path.join(msys2Root, 'mingw64', 'bin');
      final env = Map<String, String>.from(Platform.environment);
      env['PATH'] = '$usrBin;$mingwBin;${env['PATH'] ?? ''}';
      final result = await runProcessStreaming('where', ['make'], environment: env);
      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        if (output.isNotEmpty) {
          return output.split('\n').first.trim();
        }
      }
    } catch (e) {
      // Ignore
    }

    throw Exception(
      'make not found in MSYS2 at $msys2Root.\n'
      'Install with: pacman -S make\n'
      'Or set MSYS2_ROOT environment variable if MSYS2 is installed elsewhere.',
    );
  }

  /// Find sh/bash executable in MSYS2 for running shell scripts on Windows
  static Future<String> findSh() async {
    if (!Platform.isWindows) {
      return 'sh';
    }

    final msys2Root = getMsys2Root();
    final possiblePaths = [
      path.join(msys2Root, 'usr', 'bin', 'sh.exe'),
      path.join(msys2Root, 'usr', 'bin', 'bash.exe'),
      path.join(msys2Root, 'usr', 'bin', 'sh'),
      path.join(msys2Root, 'usr', 'bin', 'bash'),
    ];

    for (final shPath in possiblePaths) {
      if (await File(shPath).exists()) {
        return shPath;
      }
    }

    throw Exception(
      'sh/bash not found in MSYS2 at $msys2Root.\n'
      'This is required for running configure scripts on Windows.\n'
      'Or set MSYS2_ROOT environment variable if MSYS2 is installed elsewhere.',
    );
  }

  /// Find cmake executable in MSYS2 for Windows builds
  static Future<String> findCmake() async {
    if (!Platform.isWindows) {
      return 'cmake';
    }

    final msys2Root = getMsys2Root();
    final possiblePaths = [
      path.join(msys2Root, 'usr', 'bin', 'cmake.exe'),
      path.join(msys2Root, 'mingw64', 'bin', 'cmake.exe'),
      path.join(msys2Root, 'usr', 'bin', 'cmake'),
    ];

    for (final cmakePath in possiblePaths) {
      if (await File(cmakePath).exists()) {
        return cmakePath;
      }
    }

    throw Exception(
      'cmake not found in MSYS2 at $msys2Root.\n'
      'Install with: pacman -S cmake\n'
      'Or set MSYS2_ROOT environment variable if MSYS2 is installed elsewhere.',
    );
  }
}
