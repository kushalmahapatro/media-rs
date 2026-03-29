import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:media_cli/src/example_app_dir.dart';
import 'package:path/path.dart' as path;

/// Runs [Fastforge](https://pub.dev/packages/fastforge) `release` using
/// `distribute_options.yaml` in the Flutter app directory.
class DistCommand extends Command<void> {
  DistCommand() {
    argParser
      ..addOption(
        'app-dir',
        help: 'Flutter app root (with distribute_options.yaml).',
        defaultsTo: resolveMediaExampleAppDir(),
      )
      ..addOption(
        'release-name',
        help: 'Name of the release block in distribute_options.yaml.',
        defaultsTo: 'media-example',
      )
      ..addFlag(
        'skip-clean',
        help: 'Forward --skip-clean to fastforge.',
      )
      ..addOption(
        'jobs',
        help: 'Comma-separated fastforge job names (see distribute_options.yaml).',
      )
      ..addOption(
        'skip-jobs',
        help: 'Comma-separated job names to skip.',
      );
  }

  @override
  String get name => 'dist';

  @override
  String get description =>
      'Run `dart run fastforge:main release` in the example app (see distribute_options.yaml).';

  /// DMG packaging runs `appdmg` (npm). Prepend [tool/shims] so a fallback can use `npx`.
  static Map<String, String> _distEnvironment(String appDir) {
    final env = Map<String, String>.from(Platform.environment);
    if (!Platform.isMacOS) return env;
    final repoRoot = path.normalize(path.join(appDir, '..', '..'));
    final shimDir = path.join(repoRoot, 'tool', 'shims');
    final shim = path.join(shimDir, 'appdmg');
    if (!File(shim).existsSync()) return env;
    final pathVar = env['PATH'] ?? '';
    final sep = Platform.isWindows ? ';' : ':';
    env['PATH'] = '$shimDir$sep$pathVar';
    // Fewer npx/npm stalls when stdio is not a TTY (progress spinners, audit prompts).
    env.putIfAbsent('npm_config_progress', () => 'false');
    env.putIfAbsent('npm_config_audit', () => 'false');
    env.putIfAbsent('npm_config_fund', () => 'false');
    return env;
  }

  @override
  Future<void> run() async {
    final appDir = path.absolute(argResults!['app-dir'] as String);
    final releaseName = argResults!['release-name'] as String;
    final skipClean = argResults!['skip-clean'] as bool;
    final jobs = argResults!['jobs'] as String?;
    final skipJobs = argResults!['skip-jobs'] as String?;

    final yaml = File(path.join(appDir, 'distribute_options.yaml'));
    if (!yaml.existsSync()) {
      stderr.writeln('Missing ${yaml.path}');
      exitCode = 1;
      return;
    }

    final args = <String>[
      'run',
      // Executable is `main` → bin/main.dart (not bin/fastforge.dart).
      'fastforge:main',
      'release',
      '--name',
      releaseName,
      if (skipClean) '--skip-clean',
      if (jobs != null && jobs.isNotEmpty) ...['--jobs', jobs],
      if (skipJobs != null && skipJobs.isNotEmpty) ...['--skip-jobs', skipJobs],
    ];

    stdout.writeln('cd $appDir');
    stdout.writeln('dart ${args.join(' ')}');

    final code = await Process.start(
      'dart',
      args,
      workingDirectory: appDir,
      environment: _distEnvironment(appDir),
      mode: ProcessStartMode.inheritStdio,
    );
    exitCode = await code.exitCode;
  }
}
