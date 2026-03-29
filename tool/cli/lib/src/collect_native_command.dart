import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:logging/logging.dart';
import 'package:media_native_build/media_android_ndk.dart';
import 'package:media_native_build/media_ffmpeg_fetch.dart';
import 'package:media_native_build/media_platform_paths.dart';
import 'package:media_native_build/media_rust_target.dart';
import 'package:path/path.dart' as path;

/// Populates `platform-builds/<os>/<triple>/` (repo root) for prebuilt hooks.
class CollectNativeCommand extends Command<void> {
  CollectNativeCommand() {
    argParser
      ..addOption(
        'package-root',
        help:
            'Root of the media_dart package (contains pubspec.yaml). '
            'Default: walk up from cwd (and from this tool) for media_dart, '
            'or ../../media_dart from the tool/cli package dir.',
      )
      ..addMultiOption(
        'target',
        abbr: 't',
        help: 'Rust target triple(s), e.g. aarch64-apple-darwin. '
            'Repeat or comma-separated. Default: host triple.',
      )
      ..addFlag(
        'debug',
        negatable: false,
        help: 'Collect debug artifacts (default is release).',
      );
  }

  @override
  String get name => 'collect-native';

  @override
  String get description =>
      'Build Rust cdylib (and desktop FFmpeg layout) into platform-builds/<os>/<triple>/';

  @override
  Future<void> run() async {
    final logger = Logger.detached('collect-native')
      ..level = Level.CONFIG
      ..onRecord.listen((r) => stdout.writeln('${r.level.name}: ${r.message}'));

    final packageRoot = _resolvePackageRoot(argResults!['package-root'] as String?);
    final release = !(argResults!['debug'] as bool);
    final modeFolder = mediaCargoBuildModeFolder(release: release);

    final rawTargets = argResults!['target'] as List<String>;
    final targets = _expandTargets(rawTargets);
    final effective = targets.isEmpty ? <String>[_defaultHostTriple()] : targets;

    final crateDir = path.join(packageRoot, 'rust', 'media');
    if (!Directory(crateDir).existsSync()) {
      stderr.writeln('No rust crate at $crateDir');
      exitCode = 1;
      return;
    }

    final cargoTargetRoot = path.join(
      packageRoot,
      '.dart_tool',
      'media_cli_cargo_target',
    );

    for (final triple in effective) {
      stdout.writeln('=== $triple ($modeFolder) ===');
      try {
        await _collectOne(
          packageRoot: packageRoot,
          crateDir: crateDir,
          cargoTargetRoot: cargoTargetRoot,
          triple: triple,
          modeFolder: modeFolder,
          release: release,
          logger: logger,
        );
      } catch (e, st) {
        stderr.writeln('Failed for $triple: $e\n$st');
        exitCode = 1;
      }
    }
  }

  List<String> _expandTargets(List<String> raw) {
    final out = <String>[];
    for (final chunk in raw) {
      for (final part in chunk.split(',')) {
        final t = part.trim();
        if (t.isNotEmpty) out.add(t);
      }
    }
    return out;
  }

  String _resolvePackageRoot(String? opt) {
    if (opt != null && opt.isNotEmpty) {
      final d = path.absolute(opt);
      if (!_isMediaDartRoot(d)) {
        throw UsageException('Not a media_dart package root: $d', usage);
      }
      return d;
    }
    final starts = <String>{
      path.normalize(Directory.current.path),
      path.normalize(path.dirname(Platform.script.toFilePath())),
    };
    for (final start in starts) {
      final found = _discoverMediaDartRoot(start);
      if (found != null) return found;
    }
    throw UsageException(
      'Could not find media_dart (pubspec name media_dart). '
      'Run from media_dart/, or from tool/cli, '
      'or pass --package-root.',
      usage,
    );
  }

  /// Walks [start] upward: any segment may be `media_dart`, or the `media_cli`
  /// package (tool/cli) with sibling `../../media_dart`.
  String? _discoverMediaDartRoot(String start) {
    var dir = path.absolute(start);
    for (var i = 0; i < 40; i++) {
      if (_isMediaDartRoot(dir)) return path.normalize(dir);
      final fromCli = _mediaDartRootAdjacentToMediaCliPackage(dir);
      if (fromCli != null) return fromCli;
      final parent = path.dirname(dir);
      if (parent == dir) break;
      dir = parent;
    }
    return null;
  }

  /// If [dir] is the `media_cli` package root (e.g. tool/cli), `media_dart` lives at `../../media_dart`.
  String? _mediaDartRootAdjacentToMediaCliPackage(String dir) {
    final pubspec = File(path.join(dir, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    if (!RegExp(
      r'^name:\s*media_cli\b',
      multiLine: true,
    ).hasMatch(pubspec.readAsStringSync())) {
      return null;
    }
    final candidate = path.normalize(path.join(dir, '..', '..', 'media_dart'));
    return _isMediaDartRoot(candidate) ? candidate : null;
  }

  bool _isMediaDartRoot(String dir) {
    final f = File(path.join(dir, 'pubspec.yaml'));
    if (!f.existsSync()) return false;
    return RegExp(
      r'^name:\s*media_dart\b',
      multiLine: true,
    ).hasMatch(f.readAsStringSync());
  }

  String _defaultHostTriple() {
    if (Platform.isMacOS) {
      final r = Process.runSync('uname', ['-m']);
      final m = (r.stdout as String).trim();
      if (m == 'arm64') return 'aarch64-apple-darwin';
      return 'x86_64-apple-darwin';
    }
    if (Platform.isLinux) {
      final r = Process.runSync('uname', ['-m']);
      final m = (r.stdout as String).trim();
      if (m == 'aarch64') return 'aarch64-unknown-linux-gnu';
      return 'x86_64-unknown-linux-gnu';
    }
    if (Platform.isWindows) {
      final arch = (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '').toUpperCase();
      if (arch == 'ARM64') return 'aarch64-pc-windows-msvc';
      return 'x86_64-pc-windows-msvc';
    }
    throw UnsupportedError('Unsupported host OS for default triple');
  }

  Future<void> _collectOne({
    required String packageRoot,
    required String crateDir,
    required String cargoTargetRoot,
    required String triple,
    required String modeFolder,
    required bool release,
    required Logger logger,
  }) async {
    if (mediaRustTripleIsMacOsDesktop(triple)) {
      await mediaSyncMacosFfmpegIntoRustCrate(
        packageRoot: packageRoot,
        logger: logger,
        rustTriple: triple,
      );
    } else {
      final ffDir = mediaFfmpegBundleDirForRustTriple(triple);
      if (ffDir != null) {
        await mediaEnsureFfmpegDownloadedForRustTriple(
          rustTriple: triple,
          packageRoot: packageRoot,
          logger: logger,
        );
      }
    }

    final args = <String>[
      'build',
      if (release) '--release',
      '--manifest-path',
      path.join(crateDir, 'Cargo.toml'),
      '--package',
      'media',
      '--target',
      triple,
      '--target-dir',
      cargoTargetRoot,
    ];

    final env = Map<String, String>.from(Platform.environment);
    final androidExtra = mediaAndroidCargoEnvironmentExtra(triple);
    if (androidExtra != null) env.addAll(androidExtra);

    final code = await Process.run(
      'cargo',
      args,
      workingDirectory: crateDir,
      environment: env,
    );
    if (code.exitCode != 0) {
      stderr.writeln(code.stderr);
      stderr.writeln(code.stdout);
      throw StateError('cargo exited ${code.exitCode}');
    }

    final libFile = mediaDynamicLibraryFileNameForRustTriple(triple);
    final builtLib = path.join(cargoTargetRoot, triple, modeFolder, libFile);
    if (!File(builtLib).existsSync()) {
      throw StateError('Expected artifact missing: $builtLib');
    }

    final destDir = mediaPlatformBuildSourceDir(
      packageRoot: packageRoot,
      rustTriple: triple,
    );
    Directory(destDir).createSync(recursive: true);
    final destLib = path.join(destDir, libFile);
    File(builtLib).copySync(destLib);
    stdout.writeln('Wrote $destLib');

    final subdir = mediaFfmpegBundleDirForRustTriple(triple);
    if (subdir != null && !mediaRustTripleIsMacOsDesktop(triple)) {
      final isWin = triple.contains('windows');
      final ffmpegName = isWin ? 'ffmpeg.exe' : 'ffmpeg';
      final ffprobeName = isWin ? 'ffprobe.exe' : 'ffprobe';
      final srcDir = path.join(packageRoot, 'native', 'ffmpeg', subdir);
      for (final n in [ffmpegName, ffprobeName]) {
        final src = path.join(srcDir, n);
        if (!File(src).existsSync()) {
          throw StateError('Missing $src');
        }
        final dst = path.join(destDir, n);
        File(src).copySync(dst);
      }
      if (!isWin) {
        await Process.run('chmod', [
          '+x',
          path.join(destDir, ffmpegName),
          path.join(destDir, ffprobeName),
        ]);
      }
      stdout.writeln('Copied $ffmpegName and $ffprobeName into $destDir');
    }
  }
}
