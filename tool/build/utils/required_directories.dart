import 'dart:io';

import 'package:code_assets/code_assets.dart';

String? getEnv(Map<String, String> systemEnv, String key) {
  return Platform.environment[key] ?? systemEnv[key];
}

String resolveFfmpegDir(
  Uri packageRoot,
  OS targetOS,
  Architecture effectiveArchitecture,
  dynamic iOSSdk,
  Map<String, String> systemEnv,
) {
  final envDir = getEnv(systemEnv, 'MEDIA_RS_FFMPEG_DIR');
  if (envDir != null) return envDir;

  final subDir = _getFfmpegSubDir(targetOS, effectiveArchitecture, iOSSdk);

  final uri = packageRoot.resolve('${Directory.current.path}/../third_party/generated/ffmpeg_install/$subDir');
  final dir = File.fromUri(uri).path;

  if (!Directory(dir).existsSync()) {
    throw Exception("FFmpeg install not found at $dir for $targetOS/$effectiveArchitecture");
  }
  return dir;
}

String _getFfmpegSubDir(OS targetOS, Architecture arch, dynamic iOSSdk) {
  switch (targetOS) {
    case OS.macOS:
      return '';
    case OS.iOS:
      if (iOSSdk?.type == 'iphonesimulator') {
        return arch == Architecture.x64 ? 'ios/simulator_x64' : 'ios/simulator_arm64';
      }
      return arch == Architecture.x64 ? 'ios/simulator_x64' : 'ios/device';
    case OS.android:
      if (arch == Architecture.arm64 || arch == Architecture.arm) {
        return 'android/arm64-v8a';
      }
      return 'android/x86_64';
    case OS.linux:
      return arch == Architecture.arm64 ? 'linux/arm64' : 'linux/x86_64';
    case OS.windows:
      return 'windows/x86_64';
    default:
      throw Exception('Unsupported OS: $targetOS');
  }
}

String? resolveLibheifDir(
  Uri packageRoot,
  OS targetOS,
  Architecture effectiveArchitecture,
  bool isSimulator,
  Map<String, String> systemEnv,
) {
  final envDir = getEnv(systemEnv, 'MEDIA_RS_LIBHEIF_DIR');
  if (envDir != null && Directory(envDir).existsSync()) return envDir;

  String? path;

  switch (targetOS) {
    case OS.macOS:
      path = File.fromUri(
        packageRoot.resolve('${Directory.current.path}/../third_party/generated/libheif_install/macos/universal'),
      ).path;
      break;
    case OS.iOS:
      final platform = isSimulator ? 'iphonesimulator' : 'iphoneos';
      final arch = effectiveArchitecture == Architecture.arm64 ? 'arm64' : 'x86_64';
      path = File.fromUri(
        packageRoot.resolve('${Directory.current.path}/../third_party/generated/libheif_install/ios/$platform/$arch'),
      ).path;
      break;
    case OS.android:
      final abi = (effectiveArchitecture == Architecture.arm64 || effectiveArchitecture == Architecture.arm)
          ? 'arm64-v8a'
          : 'x86_64';
      path = File.fromUri(
        packageRoot.resolve('${Directory.current.path}/../third_party/generated/libheif_install/android/$abi'),
      ).path;
      break;
    case OS.linux:
      final arch = effectiveArchitecture == Architecture.arm64 ? 'arm64' : 'x86_64';
      path = File.fromUri(
        packageRoot.resolve('${Directory.current.path}/../third_party/generated/libheif_install/linux/$arch'),
      ).path;
      break;
    case OS.windows:
      path = File.fromUri(
        packageRoot.resolve('${Directory.current.path}/../third_party/generated/libheif_install/windows/x86_64'),
      ).path;
      break;
    default:
      return null;
  }

  return Directory(path).existsSync() ? path : null;
}

String? resolveOpenh264Dir(
  Uri packageRoot,
  OS targetOS,
  Architecture effectiveArchitecture,
  Map<String, String> systemEnv,
) {
  final envDir = getEnv(systemEnv, 'MEDIA_RS_OPENH264_DIR');
  if (envDir != null && Directory(envDir).existsSync()) return envDir;

  String? path;

  switch (targetOS) {
    case OS.macOS:
      path = File.fromUri(
        packageRoot.resolve('${Directory.current.path}/../third_party/generated/openh264_build_arm64'),
      ).path;
      break;
    case OS.android:
      final abi = (effectiveArchitecture == Architecture.arm64 || effectiveArchitecture == Architecture.arm)
          ? 'arm64-v8a'
          : 'x86_64';
      path = File.fromUri(
        packageRoot.resolve('${Directory.current.path}/../third_party/generated/openh264_install/android/$abi'),
      ).path;
      if (!Directory(path).existsSync()) {
        path = File.fromUri(
          packageRoot.resolve('${Directory.current.path}/../third_party/generated/openh264_build_android_$abi'),
        ).path;
      }
      break;
    case OS.linux:
      final arch = effectiveArchitecture == Architecture.arm64 ? 'arm64' : 'x86_64';
      path = File.fromUri(
        packageRoot.resolve('${Directory.current.path}/../third_party/generated/openh264_install/linux/$arch'),
      ).path;
      break;
    case OS.windows:
      path = File.fromUri(
        packageRoot.resolve('${Directory.current.path}/../third_party/generated/openh264_install/windows/x86_64'),
      ).path;
      break;
    default:
      return null;
  }

  return Directory(path).existsSync() ? path : null;
}
