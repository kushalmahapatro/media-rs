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

    final result = await runProcessStreaming('cmake', args, workingDirectory: buildDir, environment: env);

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

    final result = await runProcessStreaming('cmake', [
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

    final result = await runProcessStreaming('cmake', [
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

    // For Linux, we need to ensure environment variables are properly passed to FFmpeg's configure script
    // The configure script is a bash script that calls pkg-config, so the environment must be available
    // We pass the environment directly to Process.start, which should work correctly
    final result = await runProcessStreaming(configureScript, args, workingDirectory: buildDir, environment: env);

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

    final result = await runProcessStreaming('make', ['-j', cores.toString()], workingDirectory: buildDir);

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

    final result = await runProcessStreaming('make', ['install'], workingDirectory: buildDir);

    if (result.exitCode != 0) {
      print('Make install failed:');
      print(result.stdout);
      print(result.stderr);
      throw Exception('Make install failed with exit code ${result.exitCode}');
    }
  }
}
