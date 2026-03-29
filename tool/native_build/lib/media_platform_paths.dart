import 'package:media_native_build/media_rust_target.dart';
import 'package:path/path.dart' as path;

/// Hook output directory for cargo-style layout: `<out>/target/<triple>/<mode>/`.
String mediaHookNativeOutputDir({
  required Uri outputDirectory,
  required String rustTriple,
  required String cargoModeFolder,
}) {
  return path.join(
    path.fromUri(outputDirectory),
    'target',
    rustTriple,
    cargoModeFolder,
  );
}

/// Prebuilt source: `<workspaceRoot>/platform-builds/<os>/<triple>/`.
///
/// [packageRoot] is the `media_dart` package directory. [workspaceRoot] is its
/// parent (repository root when this package lives next to `platform-builds/`).
String mediaPlatformBuildSourceDir({
  required String packageRoot,
  required String rustTriple,
}) {
  final workspaceRoot = path.normalize(path.join(packageRoot, '..'));
  return path.join(
    workspaceRoot,
    'platform-builds',
    mediaPlatformBuildsOsDirName(rustTriple),
    rustTriple,
  );
}
