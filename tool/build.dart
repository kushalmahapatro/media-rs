import 'dart:io';
import 'package:code_assets/code_assets.dart' show Architecture, CCompilerConfig, IOSSdk, OS;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:toml/toml.dart';
import 'package:yaml/yaml.dart';

import 'build/android/setup_android.dart';
import 'build/build_upload.dart';
import 'build/utils/build_environment.dart';
import 'build/utils/env_vars.dart';
import 'build/utils/required_directories.dart';
import 'build/windows/setup_windows.dart';

final List<Architecture> androidArchitectures = [Architecture.arm64, Architecture.arm, Architecture.x64];
final List<Architecture> iosArchitectures = [Architecture.arm64, Architecture.x64, Architecture.arm];
final List<Architecture> macosArchitectures = [Architecture.arm64, Architecture.x64];
final List<Architecture> linuxArchitectures = [Architecture.x64];
final List<Architecture> windowsArchitectures = [Architecture.x64];
// final List<String> windowsArchitectures = ['x86_64-pc-windows-msvc' /* 'aarch64-pc-windows-msvc' */];
Logger logger = Logger('upload_library');

void main(List<String> args) async {
  logger.onRecord.listen((e) => stdout.writeln(e.toString()));

  // Verify we're running from the tool directory
  final currentDir = Directory.current.path;
  final currentDirName = path.basename(currentDir);

  if (currentDirName != 'tool') {
    logger.severe('ERROR: This script must be run from the tool directory.');
    logger.severe('Current directory: $currentDir');
    logger.severe('Expected: <project_root>/tool');
    logger.severe('');
    logger.severe('Please run: cd tool && dart build.dart <target>');
    exit(1);
  }

  if (args.isEmpty) {
    logger.info('Usage: dart tool/build.dart <target>');
    logger.info('Targets: ${OS.values.map((e) => e.name).join(', ')}');
    exit(1);
  }
  final pubspecContent = loadYaml(File(path.join(Directory.current.path, '..', 'pubspec.yaml')).readAsStringSync());
  final version = pubspecContent['version'].toString();

  final String target = args[0];
  final String buildDir = path.join(Directory.current.path, '..', 'platform-builds');

  logger.info('''\n
-----------------------------------------------
Building libraries and uploading...
Version: $version
Targets: $target
-----------------------------------------------
    ''');

  final cargoTomlPath = path.join(Directory.current.path, '..', 'native', 'Cargo.toml');
  final rustToolchainPath = path.join(Directory.current.path, '..', 'native', 'rust-toolchain.toml');

  final cargoToml = await TomlDocument.load(cargoTomlPath);
  final rustToolchain = await TomlDocument.load(rustToolchainPath);

  final crateName = cargoToml.toMap()['package']['name'];
  final toolchainChannel = rustToolchain.toMap()['toolchain']['channel'];

  final systemEnv = Platform.environment;
  final packageRoot = Uri.parse('${Directory.current.path}/..');

  final (OS os, List<Architecture> architectures) = switch (target) {
    'ios' => (OS.iOS, iosArchitectures),
    'macos' => (OS.macOS, macosArchitectures),
    'windows' => (OS.windows, windowsArchitectures),
    'linux' => (OS.linux, linuxArchitectures),
    'android' => (OS.android, androidArchitectures),
    _ => throw Exception('Unknown target: $target'),
  };

  await buildAndUpload(buildDir, version, crateName, toolchainChannel, os, architectures, logger, (
    os,
    architecture,
    tripleTarget,
    iOSSdk,
  ) async {
    bool isSimulator = iOSSdk == IOSSdk.iPhoneSimulator;
    final ffmpegDir = resolveFfmpegDir(packageRoot, os, architecture, iOSSdk, systemEnv);
    final libheifPath = resolveLibheifDir(packageRoot, os, architecture, isSimulator, systemEnv);
    final openh264Path = resolveOpenh264Dir(packageRoot, os, architecture, systemEnv);

    // Setup environment variables
    final envVars = buildEnvVars(
      ffmpegDir: ffmpegDir,
      targetOS: os,
      effectiveArchitecture: architecture,
      isSimulator: isSimulator,
      systemEnv: systemEnv,
      logger: logger,
      libheifPath: libheifPath,
      openh264Path: openh264Path,
    );

    CCompilerConfig? cCompilerConfig;

    if (os == OS.android) {
      final ndkHomePath = getEnv(systemEnv, 'ANDROID_NDK_HOME');

      await setupAndroid(envVars, packageRoot, architecture, systemEnv, logger: logger, ndkHomePath: ndkHomePath);
      cCompilerConfig = CCompilerConfig(
        archiver: Uri.parse('$ndkHomePath/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-ar'),
        compiler: Uri.parse('$ndkHomePath/toolchains/llvm/prebuilt/darwin-x86_64/bin/clang'),
        linker: Uri.parse('$ndkHomePath/toolchains/llvm/prebuilt/darwin-x86_64/bin/ld.lld'),
      );
    } else if (os == OS.windows) {
      setupWindows(envVars, systemEnv, logger);
    }

    final buildEnvironmentFactory = BuildEnvironmentFactory();
    final envFactory = await buildEnvironmentFactory.createBuildEnvVars(
      targetOS: os,
      targetTriple: tripleTarget,
      cCompilerConfig: cCompilerConfig,
    );

    return {...envFactory, ...envVars};
  });
}

String libraryVersion() {
  final versionFile = File('VERSION');
  if (!versionFile.existsSync()) {
    logger.severe('VERSION file not found');
    exit(1);
  }
  return versionFile.readAsStringSync().trim();
}
