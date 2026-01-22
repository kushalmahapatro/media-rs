// Build system abstractions
import 'dart:io';
import 'package:path/path.dart' as path;
import '../platforms/platform.dart';
import '../utils/file_ops.dart';
import '../utils/process.dart';

abstract class BuildSystem {
  Future<void> configure({
    required String sourceDir,
    required String buildDir,
    required PlatformInfo platform,
    Map<String, String>? environment,
    List<String>? extraArgs,
  });

  Future<void> build({required String buildDir, required int cores});

  Future<void> install({required String buildDir, required String installDir});
}

class CMakeBuildSystem implements BuildSystem {
  final List<String> cmakeArgs;

  CMakeBuildSystem({List<String>? cmakeArgs}) : cmakeArgs = cmakeArgs ?? [];

  @override
  Future<void> configure({
    required String sourceDir,
    required String buildDir,
    required PlatformInfo platform,
    Map<String, String>? environment,
    List<String>? extraArgs,
  }) async {
    await FileOps.ensureDirectory(buildDir);

    final args = <String>['..', ...cmakeArgs, if (extraArgs != null) ...extraArgs];

    final env = <String, String>{...Platform.environment, if (environment != null) ...environment};

    print('Configuring with CMake...');
    print('  Source: $sourceDir');
    print('  Build: $buildDir');
    print('  Args: ${args.join(' ')}');

    // Find cmake executable on Windows (in MSYS2)
    final cmakeExe = Platform.isWindows ? await PlatformDetector.findCmake() : 'cmake';

    final result = await runProcessStreaming(cmakeExe, args, workingDirectory: buildDir, environment: env);

    if (result.exitCode != 0) {
      print('CMake configure failed:');
      print(result.stdout);
      print(result.stderr);
      throw Exception('CMake configure failed with exit code ${result.exitCode}');
    }
  }

  @override
  Future<void> build({required String buildDir, required int cores}) async {
    print('Building with CMake (using $cores cores)...');

    final cmakeExe = Platform.isWindows ? await PlatformDetector.findCmake() : 'cmake';
    final result = await runProcessStreaming(cmakeExe, [
      '--build',
      '.',
      '--parallel',
      cores.toString(),
    ], workingDirectory: buildDir);

    if (result.exitCode != 0) {
      print('CMake build failed:');
      print(result.stdout);
      print(result.stderr);
      throw Exception('CMake build failed with exit code ${result.exitCode}');
    }
  }

  @override
  Future<void> install({required String buildDir, required String installDir}) async {
    await FileOps.ensureDirectory(installDir);

    final cmakeExe = Platform.isWindows ? await PlatformDetector.findCmake() : 'cmake';
    final result = await runProcessStreaming(cmakeExe, [
      '--install',
      '.',
      '--prefix',
      installDir,
    ], workingDirectory: buildDir);

    if (result.exitCode != 0) {
      print('CMake install failed:');
      print(result.stdout);
      print(result.stderr);
      throw Exception('CMake install failed with exit code ${result.exitCode}');
    }
  }
}

class AutotoolsBuildSystem implements BuildSystem {
  final List<String> configureArgs;
  Map<String, String>? _environment;
  String? _makeExe;

  AutotoolsBuildSystem({List<String>? configureArgs}) : configureArgs = configureArgs ?? [];

  @override
  Future<void> configure({
    required String sourceDir,
    required String buildDir,
    required PlatformInfo platform,
    Map<String, String>? environment,
    List<String>? extraArgs,
  }) async {
    await FileOps.ensureDirectory(buildDir);

    // Ensure configure script is executable
    final configureScript = path.join(sourceDir, 'configure');
    if (await File(configureScript).exists()) {
      if (!Platform.isWindows) {
        await runProcessStreaming('chmod', ['+x', configureScript]);
      }
    } else {
      throw Exception('configure script not found in $sourceDir');
    }

    final args = <String>[...configureArgs, if (extraArgs != null) ...extraArgs];

    final env = <String, String>{...Platform.environment, if (environment != null) ...environment};
    _environment = env;

    // Find make executable on Windows
    if (Platform.isWindows) {
      try {
        _makeExe = await PlatformDetector.findMake();
      } catch (e) {
        // If findMake fails, try to use 'make' and let it fail with a better error
        _makeExe = 'make';
      }
    } else {
      _makeExe = 'make';
    }

    print('Configuring with autotools...');
    print('  Source: $sourceDir');
    print('  Build: $buildDir');
    print('  Args: ${args.join(' ')}');
    
    // Debug: Print PKG_CONFIG environment variables if they exist
    if (env.containsKey('PKG_CONFIG_PATH') || env.containsKey('PKG_CONFIG_LIBDIR') || env.containsKey('PKG_CONFIG_ALLOW_CROSS')) {
      print('  PKG_CONFIG environment:');
      if (env.containsKey('PKG_CONFIG_PATH')) {
        print('    PKG_CONFIG_PATH: ${env['PKG_CONFIG_PATH']}');
      }
      if (env.containsKey('PKG_CONFIG_LIBDIR')) {
        print('    PKG_CONFIG_LIBDIR: ${env['PKG_CONFIG_LIBDIR']}');
      }
      if (env.containsKey('PKG_CONFIG_ALLOW_CROSS')) {
        print('    PKG_CONFIG_ALLOW_CROSS: ${env['PKG_CONFIG_ALLOW_CROSS']}');
      }
    }

    // On Windows, configure scripts must be run through sh/bash from MSYS2
    final ProcessResult result;
    if (Platform.isWindows) {
      final shExe = await PlatformDetector.findSh();
      // Use ./configure (relative path) since we're running from buildDir
      // This matches how the bash script does it: ./configure
      result = await runProcessStreaming(
        shExe,
        ['./configure', ...args],
        workingDirectory: buildDir,
        environment: env,
      );
    } else {
      result = await runProcessStreaming(configureScript, args, workingDirectory: buildDir, environment: env);
    }

    if (result.exitCode != 0) {
      print('Configure failed:');
      print(result.stdout);
      print(result.stderr);
      throw Exception('Configure failed with exit code ${result.exitCode}');
    }
  }

  @override
  Future<void> build({required String buildDir, required int cores}) async {
    print('Building with make (using $cores cores)...');

    final makeCmd = _makeExe ?? 'make';
    final result = await runProcessStreaming(
      makeCmd,
      ['-j', cores.toString()],
      workingDirectory: buildDir,
      environment: _environment,
    );

    if (result.exitCode != 0) {
      print('Make build failed:');
      print(result.stdout);
      print(result.stderr);
      throw Exception('Make build failed with exit code ${result.exitCode}');
    }
  }

  @override
  Future<void> install({required String buildDir, required String installDir}) async {
    await FileOps.ensureDirectory(installDir);

    final makeCmd = _makeExe ?? 'make';
    final result = await runProcessStreaming(
      makeCmd,
      ['install'],
      workingDirectory: buildDir,
      environment: _environment,
    );

    if (result.exitCode != 0) {
      print('Make install failed:');
      print(result.stdout);
      print(result.stderr);
      throw Exception('Make install failed with exit code ${result.exitCode}');
    }
  }
}
