// Base builder class
import 'package:path/path.dart' as path;
import '../platforms/platform.dart';
import '../utils/file_ops.dart';

abstract class BaseBuilder {
  final String projectRoot;
  final String generatedDir;
  final String sourcesDir;

  BaseBuilder(this.projectRoot)
    : generatedDir = path.join(projectRoot, 'third_party', 'generated'),
      sourcesDir = path.join(projectRoot, 'third_party', 'generated', 'sources');

  Future<void> ensureDirectories() async {
    await FileOps.ensureDirectory(generatedDir);
    await FileOps.ensureDirectory(sourcesDir);
  }

  String getBuildDir(PlatformInfo platform, {String? suffix}) {
    final suffixStr = suffix != null ? '_$suffix' : '';
    return path.join(generatedDir, '${getName()}_build_${platform.name}$suffixStr');
  }

  String getInstallDir(PlatformInfo platform, {String? subdir}) {
    // For macOS, install directly to the root install directory (no subdir)
    // This matches the build script's expectation: ffmpeg_install/ not ffmpeg_install/macos/
    if (platform.platform == BuildPlatform.macos && subdir == null) {
      return path.join(generatedDir, '${getName()}_install');
    }
    final subdirStr = subdir != null ? path.join(platform.name, subdir) : platform.name;
    return path.join(generatedDir, '${getName()}_install', subdirStr);
  }

  String getSourceDir(String sourceName) {
    return path.join(sourcesDir, sourceName);
  }

  String getName();

  Future<bool> isAlreadyBuilt(PlatformInfo platform) async {
    final installDir = getInstallDir(platform);
    final libDir = path.join(installDir, 'lib');
    final expectedLib = path.join(libDir, getLibraryName());
    return await FileOps.exists(expectedLib);
  }

  String getLibraryName();

  Future<void> build(PlatformInfo platform, {bool skipOpenH264 = false}) async {
    if (await isAlreadyBuilt(platform)) {
      print('${getName()} already built for ${platform.name}, skipping...');
      return;
    }

    await ensureDirectories();
    await downloadSource();
    await buildForPlatform(platform, skipOpenH264: skipOpenH264);
  }

  Future<void> downloadSource();
  Future<void> buildForPlatform(PlatformInfo platform, {bool skipOpenH264 = false});
}
