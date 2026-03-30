import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:logging/logging.dart';
import 'package:media_native_build/media_android_ndk.dart';
import 'package:media_native_build/media_ffmpeg_fetch.dart';
import 'package:media_native_build/media_platform_paths.dart';
import 'package:media_native_build/media_prebuilt_archive.dart';
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
        help:
            'Rust target triple(s), e.g. aarch64-apple-darwin. '
            'Repeat or comma-separated. Default: host triple.',
      )
      ..addFlag(
        'debug',
        negatable: false,
        help: 'Collect debug artifacts (default is release).',
      )
      ..addOption(
        'archive-format',
        help:
            'Write a per-triple archive for GitHub releases '
            '(e.g. aarch64-apple-darwin.zip → '
            'https://github.com/…/releases/download/v0.0.1/…). '
            'none: only populate platform-builds/.',
        allowed: ['none', 'zip', 'tgz'],
        defaultsTo: 'none',
      )
      ..addOption(
        'archive-dir',
        help: 'Output directory for archives (default: <repo>/release-assets).',
      )
      ..addOption(
        'archive-version',
        help: 'Optional subdirectory under --archive-dir (e.g. v0.0.1).',
      )
      ..addFlag(
        'archive-only',
        negatable: false,
        help:
            'Skip cargo; only create archives from existing platform-builds/. '
            'Without --target, archives every triple that has files.',
      );
  }

  @override
  String get name => 'collect-native';

  @override
  String get description =>
      'Build Rust cdylib (and desktop FFmpeg layout) into platform-builds/<os>/<triple>/; '
      'optional zip/tar.gz for GitHub release assets.';

  @override
  Future<void> run() async {
    final logger = Logger.detached('collect-native')
      ..level = Level.CONFIG
      ..onRecord.listen((r) => stdout.writeln('${r.level.name}: ${r.message}'));

    final packageRoot = _resolvePackageRoot(
      argResults!['package-root'] as String?,
    );
    final workspaceRoot = path.normalize(path.join(packageRoot, '..'));
    final release = !(argResults!['debug'] as bool);
    final archiveFormat = _parseArchiveFormat(
      argResults!['archive-format'] as String,
    );
    final archiveOnly = argResults!['archive-only'] as bool;
    final archiveVersion = argResults!['archive-version'] as String?;
    final archiveDirOpt = argResults!['archive-dir'] as String?;
    final archiveDir = path.absolute(
      (archiveDirOpt != null && archiveDirOpt.isNotEmpty)
          ? archiveDirOpt
          : path.join(workspaceRoot, 'release-assets'),
    );

    final rawTargets = argResults!['target'] as List<String>;
    final targets = _expandTargets(rawTargets);

    if (archiveOnly) {
      if (archiveFormat == null) {
        throw UsageException(
          '--archive-only requires --archive-format zip or tgz (not none).',
          usage,
        );
      }
      final triples = targets.isEmpty
          ? mediaDiscoverPlatformBuildTriples(workspaceRoot)
          : targets;
      if (triples.isEmpty) {
        stderr.writeln(
          'No platform-builds triples found. Build first or pass --target.',
        );
        exitCode = 1;
        return;
      }
      for (final triple in triples) {
        stdout.writeln('=== archive $triple ===');
        try {
          await mediaArchivePlatformBuildFolder(
            workspaceRoot: workspaceRoot,
            rustTriple: triple,
            format: archiveFormat,
            outputDirectory: archiveDir,
            release: release,
            versionSubdirectory: archiveVersion,
          );
          stdout.writeln(
            'Wrote ${_archiveOutputPath(archiveDir: archiveDir, archiveVersion: archiveVersion, triple: triple, release: release, extension: archiveFormat.fileExtension)}',
          );
        } catch (e, st) {
          stderr.writeln('Archive failed for $triple: $e\n$st');
          exitCode = 1;
        }
      }
      return;
    }

    final effective = targets.isEmpty
        ? <String>[_defaultHostTriple()]
        : targets;

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
      stdout.writeln('=== $triple ===');
      try {
        await _collectOne(
          packageRoot: packageRoot,
          crateDir: crateDir,
          cargoTargetRoot: cargoTargetRoot,
          triple: triple,
          release: release,
          logger: logger,
        );
        if (archiveFormat != null) {
          await mediaArchivePlatformBuildFolder(
            workspaceRoot: workspaceRoot,
            rustTriple: triple,
            format: archiveFormat,
            outputDirectory: archiveDir,
            release: release,
            versionSubdirectory: archiveVersion,
          );
          stdout.writeln(
            'Archive: ${_archiveOutputPath(archiveDir: archiveDir, archiveVersion: archiveVersion, triple: triple, release: release, extension: archiveFormat.fileExtension)}',
          );
        }
      } catch (e, st) {
        stderr.writeln('Failed for $triple: $e\n$st');
        exitCode = 1;
      }
    }
  }

  MediaPrebuiltArchiveFormat? _parseArchiveFormat(String raw) {
    return switch (raw) {
      'zip' => MediaPrebuiltArchiveFormat.zip,
      'tgz' => MediaPrebuiltArchiveFormat.tarGz,
      'none' => null,
      _ => null,
    };
  }

  String _archiveOutputPath({
    required String archiveDir,
    required String? archiveVersion,
    required String triple,
    required bool release,
    required String extension,
  }) {
    var root = archiveDir;
    if (archiveVersion != null && archiveVersion.isNotEmpty) {
      root = path.join(root, archiveVersion);
    }
    final base = release ? triple : '$triple-debug';
    return path.join(root, '$base.$extension');
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
      final arch = (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '')
          .toUpperCase();
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
    final builtLib = path.join(cargoTargetRoot, triple, libFile);
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
