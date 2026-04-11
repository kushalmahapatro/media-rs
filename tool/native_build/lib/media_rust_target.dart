import 'package:code_assets/code_assets.dart';

/// Fat-binary macOS triple for GitHub release zips (`universal-apple-darwin.zip`).
///
/// Not emitted by [mediaRustTargetTriple] (Dart uses [Architecture.arm64] or
/// [Architecture.x64]); use [mediaMacOsEffectivePrebuildTriple] when consuming prebuilts.
const String mediaUniversalAppleDarwinTriple = 'universal-apple-darwin';

/// Rust target triple for [code], matching [native_toolchain_rust] / the build hook.
String mediaRustTargetTriple(CodeConfig code) {
  return switch ((code.targetOS, code.targetArchitecture)) {
    (OS.android, Architecture.arm64) => 'aarch64-linux-android',
    (OS.android, Architecture.arm) => 'armv7-linux-androideabi',
    (OS.android, Architecture.x64) => 'x86_64-linux-android',
    (OS.iOS, Architecture.arm64)
        when code.iOS.targetSdk == IOSSdk.iPhoneSimulator =>
      'aarch64-apple-ios-sim',
    (OS.iOS, Architecture.arm64) when code.iOS.targetSdk == IOSSdk.iPhoneOS =>
      'aarch64-apple-ios',
    (OS.iOS, Architecture.x64) => 'x86_64-apple-ios',
    (OS.windows, Architecture.arm64) => 'aarch64-pc-windows-msvc',
    (OS.windows, Architecture.x64) => 'x86_64-pc-windows-msvc',
    (OS.linux, Architecture.arm64) => 'aarch64-unknown-linux-gnu',
    (OS.linux, Architecture.x64) => 'x86_64-unknown-linux-gnu',
    (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
    (OS.macOS, Architecture.x64) => 'x86_64-apple-darwin',
    _ => throw UnsupportedError(
      'Unsupported target: ${code.targetOS} ${code.targetArchitecture}',
    ),
  };
}

/// Resolved [LinkMode] from [CodeConfig.linkModePreference].
LinkMode mediaResolvedLinkMode(CodeConfig code) {
  return switch (code.linkModePreference) {
    LinkModePreference.dynamic ||
    LinkModePreference.preferDynamic => DynamicLoadingBundled(),
    LinkModePreference.static ||
    LinkModePreference.preferStatic => StaticLinking(),
    _ => throw UnsupportedError(
      'Unsupported LinkModePreference: ${code.linkModePreference}',
    ),
  };
}

/// Native library file name for crate `media` (matches [RustBuilder] output).
String mediaNativeLibraryFileName(CodeConfig code) {
  final linkMode = mediaResolvedLinkMode(code);
  return code.targetOS.libraryFileName('media', linkMode).replaceAll('-', '_');
}

/// `native/ffmpeg/<dir>/` for downloads; throws if desktop FFmpeg is not used for this target.
String mediaFfmpegBundleDir(CodeConfig code) {
  return switch ((code.targetOS, code.targetArchitecture)) {
    (OS.linux, Architecture.x64) => 'linux-x86_64',
    (OS.linux, Architecture.arm64) => 'linux-aarch64',
    (OS.macOS, Architecture.x64) => 'darwin-x64',
    (OS.macOS, Architecture.arm64) => 'darwin-arm64',
    (OS.windows, Architecture.x64) => 'windows-x86_64',
    (OS.windows, Architecture.arm64) => 'windows-aarch64',
    _ => throw UnsupportedError(
      'FFmpeg bundle: unsupported ${code.targetOS} ${code.targetArchitecture}',
    ),
  };
}

/// `native/ffmpeg/<dir>/` for a Rust triple, or `null` if FFmpeg is not bundled (Android/iOS).
String? mediaFfmpegBundleDirForRustTriple(String rustTriple) {
  return switch (rustTriple) {
    'aarch64-unknown-linux-gnu' => 'linux-aarch64',
    'x86_64-unknown-linux-gnu' => 'linux-x86_64',
    'aarch64-apple-darwin' => 'darwin-arm64',
    'x86_64-apple-darwin' => 'darwin-x64',
    mediaUniversalAppleDarwinTriple => 'darwin-universal',
    'aarch64-pc-windows-msvc' => 'windows-aarch64',
    'x86_64-pc-windows-msvc' => 'windows-x86_64',
    _ => null,
  };
}

/// Folder under repository `platform-builds/` (matches layout: `macos/`, `ios/`, …).
String mediaPlatformBuildsOsDirName(String rustTriple) {
  return switch (mediaOsForRustTriple(rustTriple)) {
    OS.macOS => 'macos',
    OS.iOS => 'ios',
    OS.android => 'android',
    OS.linux => 'linux',
    OS.windows => 'windows',
    _ => throw UnsupportedError(
      'Unknown rust triple for platform-builds layout: $rustTriple',
    ),
  };
}

/// Target [OS] implied by [rustTriple] (for naming the cdylib output).
OS mediaOsForRustTriple(String rustTriple) {
  if (rustTriple.contains('-apple-ios')) return OS.iOS;
  if (rustTriple.contains('-apple-darwin')) return OS.macOS;
  if (rustTriple.contains('-linux-android') ||
      rustTriple.contains('linux-androideabi')) {
    return OS.android;
  }
  if (rustTriple.contains('-unknown-linux-gnu')) return OS.linux;
  if (rustTriple.contains('-pc-windows-msvc')) return OS.windows;
  throw UnsupportedError('Unknown rust triple for OS mapping: $rustTriple');
}

/// Whether [rustTriple] is macOS desktop (needs ffmpeg in `bundled/current` before cargo).
bool mediaRustTripleIsMacOsDesktop(String rustTriple) {
  return rustTriple == 'aarch64-apple-darwin' ||
      rustTriple == 'x86_64-apple-darwin' ||
      rustTriple == mediaUniversalAppleDarwinTriple;
}

/// When [useUniversalMacOsPrebuild] is true, GitHub / `platform-builds` use the fat
/// [mediaUniversalAppleDarwinTriple] asset for any macOS [code] config; otherwise the
/// per-arch triple from [mediaRustTargetTriple].
String mediaMacOsEffectivePrebuildTriple(
  CodeConfig code, {
  required bool useUniversalMacOsPrebuild,
}) {
  if (code.targetOS == OS.macOS && useUniversalMacOsPrebuild) {
    return mediaUniversalAppleDarwinTriple;
  }
  return mediaRustTargetTriple(code);
}

/// Dynamic library filename for crate `media` (matches hook / [RustBuilder] with bundled dynamic link).
String mediaDynamicLibraryFileNameForRustTriple(String rustTriple) {
  final os = mediaOsForRustTriple(rustTriple);
  return os
      .libraryFileName('media', DynamicLoadingBundled())
      .replaceAll('-', '_');
}
