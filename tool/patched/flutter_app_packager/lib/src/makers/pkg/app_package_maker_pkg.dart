import 'dart:io';

import 'package:flutter_app_packager/src/api/app_package_maker.dart';
import 'package:flutter_app_packager/src/makers/pkg/make_pkg_config.dart';
import 'package:path/path.dart' as p;
import 'package:shell_executor/shell_executor.dart';

class AppPackageMakerPkg extends AppPackageMaker {
  @override
  String get name => 'pkg';
  @override
  String get platform => 'macos';
  @override
  String get packageFormat => 'pkg';

  @override
  MakeConfigLoader get configLoader {
    return MakePkgConfigLoader()
      ..platform = platform
      ..packageFormat = packageFormat;
  }

  @override
  Future<MakeResult> make(MakeConfig config) async {
    MakePkgConfig makeConfig = config as MakePkgConfig;
    File appFile = config.buildOutputFiles.first;

    File outputFile = config.outputFile;
    File unsignedPkgFile = File(
      outputFile.path.replaceFirst(
        '.$packageFormat',
        '-unsigned.$packageFormat',
      ),
    );

    // Stage a folder whose only top-level entry is `*.app`. Use `pkgbuild` (not
    // `productbuild --root`) with `BundleIsRelocatable` false so Installer does
    // not relocate to an existing bundle id elsewhere on disk.
    final stage = Directory.systemTemp.createTempSync('flutter_app_pkg_');
    final componentPlist = File(
      p.join(
        Directory.systemTemp.path,
        'flutter_app_pkg_cmp_${DateTime.now().microsecondsSinceEpoch}.plist',
      ),
    );
    final installRaw = makeConfig.installPath ?? '/Applications/';
    final trimmed = installRaw.replaceAll(RegExp(r'/+$'), '');
    final installLocation = trimmed.isEmpty ? '/Applications' : trimmed;
    try {
      final stagedApp = p.join(stage.path, p.basename(appFile.path));
      await $('cp', ['-R', appFile.path, stagedApp]);

      await $('xcrun', [
        'pkgbuild',
        '--root',
        stage.path,
        '--analyze',
        componentPlist.path,
      ]);
      await $(r'/usr/libexec/PlistBuddy', [
        '-c',
        'set :0:BundleIsRelocatable false',
        componentPlist.path,
      ]);
      await $('xcrun', [
        'pkgbuild',
        '--root',
        stage.path,
        '--identifier',
        _installerPackageIdentifier(appFile),
        '--version',
        makeConfig.appBuildName,
        '--install-location',
        installLocation,
        '--component-plist',
        componentPlist.path,
        unsignedPkgFile.path,
      ]);
    } finally {
      if (stage.existsSync()) {
        stage.deleteSync(recursive: true);
      }
      if (componentPlist.existsSync()) {
        componentPlist.deleteSync();
      }
    }
    if (makeConfig.signIdentity != null) {
      await $('xcrun', [
        'productsign',
        '--sign',
        makeConfig.signIdentity!,
        unsignedPkgFile.path,
        outputFile.path,
      ]);
      unsignedPkgFile.deleteSync();
    } else {
      unsignedPkgFile.renameSync(outputFile.path);
    }
    return Future.value(resultResolver.resolve(config));
  }
}

String _installerPackageIdentifier(File appBundle) {
  final info = File(p.join(appBundle.path, 'Contents', 'Info.plist'));
  if (!info.existsSync()) {
    return 'app.pkg';
  }
  final r = Process.runSync('plutil', [
    '-extract',
    'CFBundleIdentifier',
    'raw',
    '-o',
    '-',
    info.path,
  ]);
  if (r.exitCode != 0) {
    return 'app.pkg';
  }
  final id = (r.stdout as String).trim();
  if (id.isEmpty) {
    return 'app.pkg';
  }
  return '$id.pkg';
}
