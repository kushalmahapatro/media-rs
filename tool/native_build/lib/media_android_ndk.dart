import 'dart:io';

import 'package:path/path.dart' as path;

/// API level for NDK clang wrappers (`*-linux-android<api>-clang` /
/// `armv7a-linux-androideabi<api>-clang`).
/// Keep aligned with a typical Flutter `minSdk` (21+).
const mediaAndroidNdkApiLevel = 24;

/// Locates an installed Android NDK (same discovery order as many Flutter setups).
String? mediaResolveAndroidNdkRoot() {
  for (final key in ['ANDROID_NDK_HOME', 'ANDROID_NDK_ROOT']) {
    final v = Platform.environment[key];
    if (v != null && v.isNotEmpty && Directory(v).existsSync()) {
      return path.normalize(v);
    }
  }
  final sdk = Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'];
  if (sdk == null || sdk.isEmpty) return null;
  final ndkParent = Directory(path.join(sdk, 'ndk'));
  if (!ndkParent.existsSync()) return null;
  final versions = ndkParent
      .listSync()
      .whereType<Directory>()
      .map((e) => path.basename(e.path))
      .toList()
    ..sort();
  if (versions.isEmpty) return null;
  return path.normalize(path.join(sdk, 'ndk', versions.last));
}

String _ndkLlvmBinDir(String ndkRoot) {
  final prebuiltRoot = path.join(ndkRoot, 'toolchains', 'llvm', 'prebuilt');
  final d = Directory(prebuiltRoot);
  if (!d.existsSync()) {
    throw StateError('Invalid NDK at $ndkRoot (missing $prebuiltRoot)');
  }
  final hosts = d
      .listSync()
      .whereType<Directory>()
      .map((e) => path.basename(e.path))
      .toList();
  if (hosts.isEmpty) {
    throw StateError('No host prebuilts under $prebuiltRoot');
  }
  String? pick(String h) =>
      hosts.contains(h) ? path.join(prebuiltRoot, h, 'bin') : null;
  if (Platform.isMacOS) {
    final uname = Process.runSync('uname', ['-m']);
    final m = (uname.stdout as String).trim();
    if (m == 'arm64') {
      final a = pick('darwin-arm64');
      if (a != null) return a;
    }
    final x = pick('darwin-x86_64');
    if (x != null) return x;
  } else if (Platform.isLinux) {
    final x = pick('linux-x86_64');
    if (x != null) return x;
  } else if (Platform.isWindows) {
    final x = pick('windows-x86_64');
    if (x != null) return x;
  }
  return path.join(prebuiltRoot, hosts.first, 'bin');
}

/// Environment entries to merge into `cargo` when building [rustTriple] for Android.
///
/// Returns `null` if [rustTriple] is not Android.
Map<String, String>? mediaAndroidCargoEnvironmentExtra(String rustTriple) {
  final isAndroid = rustTriple.contains('-linux-android') ||
      rustTriple.contains('-linux-androideabi');
  if (!isAndroid) return null;

  final ndk = mediaResolveAndroidNdkRoot();
  if (ndk == null) {
    throw StateError(
      'Android NDK not found (needed for $rustTriple). '
      'Install the NDK in Android Studio or set ANDROID_NDK_HOME / ANDROID_HOME.',
    );
  }

  final bin = _ndkLlvmBinDir(ndk);
  final api = mediaAndroidNdkApiLevel.toString();

  void checkFile(String p, String label) {
    if (!File(p).existsSync()) {
      throw StateError('NDK tool missing: $label ($p). Try a newer NDK or check ANDROID_NDK_HOME.');
    }
  }

  if (rustTriple == 'aarch64-linux-android') {
    final clang = path.join(bin, 'aarch64-linux-android$api-clang');
    final clangxx = path.join(bin, 'aarch64-linux-android$api-clang++');
    final ar = path.join(bin, 'llvm-ar');
    checkFile(clang, 'clang');
    checkFile(clangxx, 'clang++');
    checkFile(ar, 'llvm-ar');
    return {
      'ANDROID_NDK_HOME': ndk,
      'CC_aarch64_linux_android': clang,
      'CXX_aarch64_linux_android': clangxx,
      'AR_aarch64_linux_android': ar,
      'CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER': clang,
    };
  }
  if (rustTriple == 'x86_64-linux-android') {
    final clang = path.join(bin, 'x86_64-linux-android$api-clang');
    final clangxx = path.join(bin, 'x86_64-linux-android$api-clang++');
    final ar = path.join(bin, 'llvm-ar');
    checkFile(clang, 'clang');
    checkFile(clangxx, 'clang++');
    checkFile(ar, 'llvm-ar');
    return {
      'ANDROID_NDK_HOME': ndk,
      'CC_x86_64_linux_android': clang,
      'CXX_x86_64_linux_android': clangxx,
      'AR_x86_64_linux_android': ar,
      'CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER': clang,
    };
  }
  if (rustTriple == 'armv7-linux-androideabi') {
    // NDK binaries use the armv7a prefix (not armv7).
    final prefix = 'armv7a-linux-androideabi$api';
    final clang = path.join(bin, '$prefix-clang');
    final clangxx = path.join(bin, '$prefix-clang++');
    final ar = path.join(bin, 'llvm-ar');
    checkFile(clang, 'clang');
    checkFile(clangxx, 'clang++');
    checkFile(ar, 'llvm-ar');
    return {
      'ANDROID_NDK_HOME': ndk,
      'CC_armv7_linux_androideabi': clang,
      'CXX_armv7_linux_androideabi': clangxx,
      'AR_armv7_linux_androideabi': ar,
      'CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER': clang,
    };
  }
  if (rustTriple == 'i686-linux-android') {
    final clang = path.join(bin, 'i686-linux-android$api-clang');
    final clangxx = path.join(bin, 'i686-linux-android$api-clang++');
    final ar = path.join(bin, 'llvm-ar');
    checkFile(clang, 'clang');
    checkFile(clangxx, 'clang++');
    checkFile(ar, 'llvm-ar');
    return {
      'ANDROID_NDK_HOME': ndk,
      'CC_i686_linux_android': clang,
      'CXX_i686_linux_android': clangxx,
      'AR_i686_linux_android': ar,
      'CARGO_TARGET_I686_LINUX_ANDROID_LINKER': clang,
    };
  }

  throw UnsupportedError(
    'No NDK toolchain mapping for $rustTriple (add it in media_android_ndk.dart).',
  );
}
