import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'utils/process_runner.dart';
import 'utils/target_mapping.dart';

Future<void> buildAndUpload(
  String buildDir,
  String version,
  String crateName,
  String toolchainChannel,
  OS os,
  List<Architecture> architectures,
  Logger logger,
  Future<Map<String, String>> Function(OS os, Architecture architecture, String tripleTarget, IOSSdk? iOSSdk)
  createBuildEnvVars,
) async {
  final libraryName = os.libraryFileName(crateName, DynamicLoadingBundled());
  final osName = os.name;
  final androidDir = Directory(path.join(buildDir, osName));

  // Create android directory if it doesn't exist
  if (!androidDir.existsSync()) {
    androidDir.createSync(recursive: true);
  }

  // Build libraries for each architecture
  logger.info('Building $osName libraries...');
  for (final architecture in architectures) {
    IOSSdk? iOSSdk;
    Architecture targetArchitecture = architecture;
    if (os == OS.iOS && architecture == Architecture.arm64) {
      iOSSdk = IOSSdk.iPhoneOS;
    } else if (os == OS.iOS && (architecture == Architecture.arm || architecture == Architecture.x64)) {
      iOSSdk = IOSSdk.iPhoneSimulator;
      if (architecture == Architecture.arm) {
        targetArchitecture = Architecture.arm64;
      }
    }
    final targetTriple = getTargetTriple(os, targetArchitecture, iOSSdk);
    await _buildLibrary(
      buildDir,
      targetTriple,
      osName,
      toolchainChannel,
      libraryName,
      crateName,
      targetArchitecture,
      os,
      logger,
      iOSSdk,
      createBuildEnvVars,
    );
  }

  // Iterate through all architecture folders
  final archDirs = androidDir.listSync().whereType<Directory>().where((dir) => dir.existsSync()).toList();

  if (archDirs.isEmpty) {
    logger.warning('No architecture directories found in ${androidDir.path}');
    return;
  }

  for (final archDir in archDirs) {
    String archName = path.basename(archDir.path);
    final libFile = File(path.join(archDir.path, libraryName));

    if (!libFile.existsSync()) {
      logger.warning('Skipping $archName: $libraryName not found');
      continue;
    }

    logger.info('Processing $archName...');

    if (archName.startsWith('arm64')) {
      archName = 'arm64';
    }

    try {
      // Rename the library
      final extension = libraryName.split('.').last;
      final libraryNameWithoutExtension = libraryName.split('.').first;
      final newLibName = '${libraryNameWithoutExtension}_${osName}_$archName.$extension';
      final renamedLib = await libFile.rename(path.join(archDir.path, newLibName));

      // Upload to Storage
      final uploadUrl = '';
      // final success = await _uploadFile(renamedLib, uploadUrl, logger);

      // if (success) {
      //   // Delete the folder on success
      //   await archDir.delete(recursive: true);
      //   logger.info('$archName uploaded and folder deleted');
      // } else {
      //   logger.severe('Upload failed for $archName');
      //   exit(1);
      // }
    } catch (e) {
      logger.severe('Error processing $archName: $e');
      exit(1);
    }
  }

  logger.info('$osName libraries upload completed successfully');
}

Future<void> _buildLibrary(
  String buildDir,
  String targetTriple,
  String osName,
  String toolchainChannel,
  String libraryName,
  String crateName,
  Architecture architecture,
  OS os,
  Logger logger,
  IOSSdk? iOSSdk,
  Future<Map<String, String>> Function(OS os, Architecture architecture, String tripleTarget, IOSSdk? iOSSdk)
  createBuildEnvVars,
) async {
  final targetDir = Directory(path.join(buildDir, osName));
  final targetBuildDir = Directory(path.join(buildDir, osName, 'build'));
  final cargoTomlPath = path.join(Directory.current.path, '..', 'native', 'Cargo.toml');

  logger.info('Building $targetTriple...');

  final processRunner = ProcessRunner(logger);
  final envVars = await createBuildEnvVars(os, architecture, targetTriple, iOSSdk);
  final processResult = await processRunner.invokeRustup([
    'run',
    toolchainChannel,
    'cargo',
    'build',
    '--release',
    '--manifest-path',
    cargoTomlPath,
    '--package',
    crateName,
    '--target',
    targetTriple,
    '--target-dir',
    targetBuildDir.path,
  ], environment: envVars);

  if (processResult.exitCode != 0) {
    logger.severe('Failed to build $targetTriple: ${processResult.stderr}');
    exit(1);
  }

  final osTargetDir = Directory(path.join(targetDir.path, targetTriple));
  osTargetDir.create();
  final dylibFile = File(path.join(targetBuildDir.path, targetTriple, 'release', libraryName));
  if (!dylibFile.existsSync()) {
    logger.severe('Failed to build $targetTriple: $libraryName not found');
    exit(1);
  }

  // Copy the library
  dylibFile.copySync(path.join(osTargetDir.path, libraryName));
  final libFile = File(path.join(osTargetDir.path, libraryName));
  if (!libFile.existsSync()) {
    logger.severe('Failed to build $targetTriple: $libraryName not found');
    exit(1);
  }

  targetBuildDir.deleteSync(recursive: true);

  logger.info('$targetTriple built successfully');
}

Future<bool> _uploadFile(File file, String url, Logger logger) async {
  return true;
  try {
    final result = await Process.run('curl', [
      '-X',
      'PUT',
      '-T',
      file.path,
      '--fail-with-body', // Return non-zero exit code on HTTP errors
      '--silent',
      '--show-error', // Show errors even in silent mode
      url,
    ]);

    if (result.exitCode == 0) {
      return true;
    } else {
      logger.severe('Upload failed with exit code: ${result.exitCode}');
      if (result.stderr.isNotEmpty) {
        logger.severe('Error: ${result.stderr}');
      }
      if (result.stdout.isNotEmpty) {
        logger.severe('Response: ${result.stdout}');
      }
      return false;
    }
  } catch (e) {
    logger.severe('Upload error: $e');
    return false;
  }
}
