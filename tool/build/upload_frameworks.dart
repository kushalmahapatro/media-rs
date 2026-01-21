import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import '../build.dart';

Logger logger = Logger('upload_framework');

enum Target {
  android,
  apple,
  windows,
  linux;

  static Target? fromString(String value) => switch (value.toLowerCase()) {
    'android' => Target.android,
    'apple' => Target.apple,
    'windows' => Target.windows,
    'linux' => Target.linux,
    _ => null,
  };
}

void main(List<String> args) async {
  bool verbose = false;
  logger.onRecord.listen((e) => stdout.writeln(e.toString()));

  if (args.isNotEmpty && ['-h', '--help'].contains(args.first)) {
    logger.info(
      'Usage: dart tool/upload_framework.dart [--version=<version>] [--targets=<target1,target2,target3>] [--verbose]',
    );

    logger.info('Version: 0.0.1');
    logger.info('Targets: apple, windows, linux, android');
    logger.info('--verbose to print the upload logs');

    logger.info('\nIf --version or --targets are not provided, you will be prompted interactively.');
    logger.info('\nIf --version or --targets are not provided, you will be prompted interactively.');
    exit(1);
  }

  // Parse command line arguments

  String? version;

  List<Target>? targets;

  for (final arg in args) {
    if (arg.startsWith('--version=')) {
      version = arg.substring('--version='.length).trim();
    } else if (arg.startsWith('--targets=')) {
      final targetStrings = arg
          .substring('--targets='.length)
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      targets = targetStrings.map((t) => Target.fromString(t)).whereType<Target>().toList();

      if (targets.length != targetStrings.length) {
        final invalid = targetStrings.where((t) => Target.fromString(t) == null).toList();

        logger.severe('Invalid targets: ${invalid.join(', ')}');

        logger.info('Valid targets: ${Target.values.map((t) => t.name).join(', ')}');

        exit(1);
      }
    } else if (arg.startsWith('--verbose') && !verbose) {
      verbose = true;
    }
  }

  if (version == null && targets == null) {
    await interactiveMode(verbose);
  } else {
    version ??= await promptForVersion();

    targets ??= await promptForTargets();

    final availableTargets = getAvailableTargets();

    final invalidTargets = targets.where((t) => !availableTargets.contains(t)).toList();

    if (invalidTargets.isNotEmpty) {
      logger.severe(
        'Invalid targets for platform ${Platform.operatingSystem}: ${invalidTargets.map((t) => t.name).join(', ')}',
      );

      logger.info('Available targets: ${availableTargets.map((t) => t.name).join(', ')}');

      exit(1);
    }

    await uploadFrameworks(version, targets, verbose);
  }
}

Future<void> interactiveMode(bool verbose) async {
  final version = await promptForVersion();

  final targets = await promptForTargets();

  stdout.writeln('\nSelected targets: ${targets.map((t) => t.name).join(', ')}');

  stdout.writeln('\nVersion: $version\n');

  final process = await Process.start('dart', ['run', 'tool/update_version.dart']);
  await stdout.addStream(process.stdout);

  await uploadFrameworks(version, targets, verbose);
}

Future<String> promptForVersion() async {
  // Ask for version (default to VERSION file)

  final defaultVersion = libraryVersion();

  stdout.write('Enter version (default: $defaultVersion): ');

  final versionInput = stdin.readLineSync()?.trim();

  final version = versionInput?.isEmpty ?? true ? defaultVersion : versionInput!;

  if (version.isEmpty) {
    logger.severe('Version cannot be empty');

    exit(1);
  }

  return version;
}

Future<List<Target>> promptForTargets() async {
  final availableTargets = getAvailableTargets();

  if (availableTargets.isEmpty) {
    logger.severe('No targets available for platform: ${Platform.operatingSystem}');

    exit(1);
  }

  // Display available targets

  stdout.writeln('\nAvailable targets for ${Platform.operatingSystem}:\n');

  for (int i = 0; i < availableTargets.length; i++) {
    stdout.write('  ${i + 1}. ${availableTargets[i].name}\n');
  }

  stdout.write('  0. All available targets\n');

  // Ask for target selection

  stdout.write('\nSelect targets (comma-separated numbers, e.g., 1,2 or 0 for all): ');

  final selectionInput = stdin.readLineSync()?.trim() ?? '';

  List<Target> selectedTargets;

  if (selectionInput == '0') {
    selectedTargets = availableTargets;
  } else {
    final indices = selectionInput
        .split(',')
        .map((s) => s.trim())
        .map((s) => int.tryParse(s))
        .where((i) => i != null && i > 0 && i <= availableTargets.length)
        .map((i) => i! - 1)
        .toSet()
        .toList();

    if (indices.isEmpty) {
      logger.severe('Invalid selection. Please enter valid numbers.');

      exit(1);
    }

    selectedTargets = indices.map((i) => availableTargets[i]).toList();
  }

  return selectedTargets;
}

List<Target> getAvailableTargets() {
  if (Platform.isMacOS) {
    return [Target.apple, Target.android];
  } else if (Platform.isWindows) {
    return [Target.windows, Target.android];
  } else if (Platform.isLinux) {
    return [Target.linux, Target.android];
  } else {
    return [];
  }
}

Future<void> uploadFrameworks(String version, List<Target> targets, bool verbose) async {
  logger.info('Uploading frameworks...');

  logger.info('Version: $version');

  logger.info('Targets: ${targets.map((t) => t.name).join(', ')}');

  for (final target in targets) {
    logger.info('\n--- Uploading ${target.name} ---');

    try {
      await uploadFrameworkForTarget(version, target, verbose);

      logger.info('✓ Successfully uploaded ${target.name}');
    } catch (e) {
      logger.severe('✗ Failed to upload ${target.name}: $e');
    }
  }

  logger.info('\nUpload completed!');
}

Future<void> uploadFrameworkForTarget(String version, Target target, bool verbose) => switch (target) {
  Target.android => _run(target.name, 'android-all', version, verbose),
  Target.windows => _run(target.name, 'windows-all', version, verbose),
  Target.linux => _run(target.name, 'linux-all', version, verbose),
  Target.apple => _run(target.name, 'apple-all', version, verbose),
};

Future<void> _run(String target, String command, String version, bool verbose) async {
  final stopwatch = Stopwatch()..start();

  bool isComplete = false;

  // Start progressive loader

  final loaderCompleter = Completer<void>();

  late final Timer loaderTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
    if (isComplete) {
      timer.cancel();
      loaderCompleter.complete();

      return;
    }

    final elapsed = stopwatch.elapsed;
    final seconds = elapsed.inSeconds;
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    final timeStr = minutes > 0 ? '${minutes}m ${remainingSeconds}s' : '${remainingSeconds}s';

    // Spinner characters that rotate
    final spinnerChars = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
    final spinnerIndex = (elapsed.inMilliseconds ~/ 100) % spinnerChars.length;

    // Clear line and write loader
    stdout.write('\r${spinnerChars[spinnerIndex]} Building $target... (elapsed: $timeStr)');
  });

  try {
    final process = await Process.start('make', [command]);
    if (verbose) {
      await stdout.addStream(process.stdout);
    }

    isComplete = true;
    stopwatch.stop();

    // Wait for loader to finish current cycle
    await loaderCompleter.future;
    loaderTimer.cancel();

    // Clear the loader line
    stdout.write('\r${' ' * 80}\r');
    final totalTime = stopwatch.elapsed;
    final totalSeconds = totalTime.inSeconds;
    final totalMinutes = totalSeconds ~/ 60;
    final totalRemainingSeconds = totalSeconds % 60;
    final totalTimeStr = totalMinutes > 0 ? '${totalMinutes}m ${totalRemainingSeconds}s' : '${totalSeconds}s';

    if (await process.exitCode != 0) {
      logger.severe('Failed to build $target, version: $version (took $totalTimeStr)');
      logger.severe('stderr: ${process.stderr}');
      logger.severe('stdout: ${process.stdout}');

      exit(1);
    }

    logger.info('stdout: ${process.stdout}');
    logger.info('✓ Successfully built $target, version: $version (took $totalTimeStr)');
  } catch (e) {
    isComplete = true;
    stopwatch.stop();
    loaderTimer.cancel();
    stdout.write('\r${' ' * 80}\r');

    final totalTime = stopwatch.elapsed;
    final totalSeconds = totalTime.inSeconds;
    final totalMinutes = totalSeconds ~/ 60;
    final totalRemainingSeconds = totalSeconds % 60;
    final totalTimeStr = totalMinutes > 0 ? '${totalMinutes}m ${totalRemainingSeconds}s' : '${totalSeconds}s';

    logger.severe('✗ Failed to build $target, version: $version (took $totalTimeStr)');
    logger.severe('Error: $e');

    rethrow;
  }
}
