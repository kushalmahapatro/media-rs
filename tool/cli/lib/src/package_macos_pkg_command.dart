import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:media_cli/src/example_app_dir.dart';
import 'package:path/path.dart' as path;

/// Builds a macOS `.pkg` that installs `*.app` as a bundle under `/Applications/`.
///
/// [flutter_app_packager] passes `Foo.app` to `productbuild --root`, which installs
/// the **contents** of that bundle (e.g. `Contents/`) straight onto disk. We stage a
/// temp directory that contains **only** `*.app` (not all of `Release/`, which has
/// loose frameworks/dSYMs) and use that as `--root` so the installer drops
/// `/Applications/media.app` as a proper bundle.
class PackageMacosPkgCommand extends Command<void> {
  PackageMacosPkgCommand() {
    argParser
      ..addOption(
        'app-dir',
        help: 'Flutter app root (example with macos/Runner).',
        defaultsTo: resolveMediaExampleAppDir(),
      )
      ..addFlag(
        'no-build',
        negatable: false,
        help: 'Skip flutter build (use existing build/macos/.../Release/*.app).',
      )
      ..addOption(
        'install-path',
        help: 'PKG install location (default: from macos/packaging/pkg/make_config.yaml or /Applications/).',
      )
      ..addOption(
        'sign-identity',
        help: 'Optional signing identity for productsign (Developer ID Installer, etc.).',
      )
      ..addOption(
        'output',
        help: 'Output .pkg path (default: ../../dist/<version>/media-<version>-macos.pkg).',
      );
  }

  @override
  String get name => 'package-macos-pkg';

  @override
  String get description =>
      'Build a correct macOS installer .pkg (productbuild root = parent of .app).';

  @override
  Future<void> run() async {
    if (!Platform.isMacOS) {
      stderr.writeln('package-macos-pkg only runs on macOS.');
      exitCode = 2;
      return;
    }

    final appDir = path.absolute(argResults!['app-dir'] as String);
    final noBuild = argResults!['no-build'] as bool;
    final signIdentity = argResults!['sign-identity'] as String?;
    var installPath = argResults!['install-path'] as String?;
    final outputOpt = argResults!['output'] as String?;

    if (!Directory(appDir).existsSync()) {
      stderr.writeln('app-dir not found: $appDir');
      exitCode = 1;
      return;
    }

    installPath ??= _readInstallPathFromPkgYaml(appDir) ?? '/Applications/';
    if (!installPath.endsWith('/')) {
      installPath = '$installPath/';
    }

    if (!noBuild) {
      stdout.writeln('Running flutter build macos --release...');
      final flutter = await Process.run(
        'flutter',
        const ['build', 'macos', '--release'],
        workingDirectory: appDir,
      );
      stdout.write(flutter.stdout);
      stderr.write(flutter.stderr);
      if (flutter.exitCode != 0) {
        exitCode = flutter.exitCode;
        return;
      }
    }

    final releaseDir = path.join(appDir, 'build', 'macos', 'Build', 'Products', 'Release');
    final d = Directory(releaseDir);
    if (!d.existsSync()) {
      stderr.writeln('Missing Release build output: $releaseDir');
      exitCode = 1;
      return;
    }

    final bundles = d
        .listSync()
        .whereType<Directory>()
        .where((e) => e.path.endsWith('.app'))
        .toList();
    if (bundles.isEmpty) {
      stderr.writeln('No .app under $releaseDir');
      exitCode = 1;
      return;
    }
    if (bundles.length > 1) {
      stderr.writeln(
        'Multiple .app bundles in Release; using first: ${bundles.first.path}',
      );
    }

    final bundle = bundles.first;
    final version = _readPubspecVersion(appDir);
    final repoRoot = path.normalize(path.join(appDir, '..', '..'));
    final outDir = path.join(repoRoot, 'dist', version);
    Directory(outDir).createSync(recursive: true);
    final outPkg = outputOpt ??
        path.join(outDir, 'media-$version-macos.pkg');
    final unsigned = path.join(
      Directory.systemTemp.path,
      'media_pkg_unsigned_${DateTime.now().microsecondsSinceEpoch}.pkg',
    );

    // `Release/` contains frameworks, dSYMs, etc. Only the .app must be the
    // productbuild root, or those siblings get installed next to /Applications/*.app.
    final stage = Directory(
      path.join(
        Directory.systemTemp.path,
        'media_pkg_stage_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    try {
      stage.createSync();
      final stagedApp = path.join(stage.path, path.basename(bundle.path));
      await Process.run('cp', ['-R', bundle.path, stagedApp]);

      stdout.writeln(
        'xcrun productbuild --root ${stage.path} $installPath → $outPkg',
      );
      final pb = await Process.run('xcrun', [
        'productbuild',
        '--root',
        stage.path,
        installPath,
        unsigned,
      ]);
      stdout.write(pb.stdout);
      stderr.write(pb.stderr);
      if (pb.exitCode != 0) {
        exitCode = pb.exitCode;
        return;
      }
    } finally {
      if (stage.existsSync()) {
        stage.deleteSync(recursive: true);
      }
    }

    if (signIdentity != null && signIdentity.isNotEmpty) {
      final signed = await Process.run('xcrun', [
        'productsign',
        '--sign',
        signIdentity,
        unsigned,
        outPkg,
      ]);
      stdout.write(signed.stdout);
      stderr.write(signed.stderr);
      File(unsigned).deleteSync();
      if (signed.exitCode != 0) {
        exitCode = signed.exitCode;
        return;
      }
    } else {
      File(unsigned).renameSync(outPkg);
    }

    stdout.writeln('Wrote $outPkg');
  }

  static String? _readInstallPathFromPkgYaml(String appDir) {
    final f = File(path.join(appDir, 'macos', 'packaging', 'pkg', 'make_config.yaml'));
    if (!f.existsSync()) return null;
    final text = f.readAsStringSync();
    final m = RegExp(
      r'''^install-path:\s*['"]?([^'"\s]+)''',
      multiLine: true,
    ).firstMatch(text);
    return m?.group(1);
  }

  static String _readPubspecVersion(String appDir) {
    final text = File(path.join(appDir, 'pubspec.yaml')).readAsStringSync();
    final m = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(text);
    if (m == null) throw StateError('No version: in $appDir/pubspec.yaml');
    return m.group(1)!.split('+').first.trim();
  }
}
