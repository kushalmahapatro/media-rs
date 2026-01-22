import 'package:code_assets/code_assets.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

@internal
extension CodeConfigMapping on CodeConfig {
  String get targetTriple {
    return switch (targetOS) {
      OS.iOS => getTargetTriple(targetOS, targetArchitecture, iOS.targetSdk),
      _ => getTargetTriple(targetOS, targetArchitecture, null),
    };
  }

  LinkMode get linkMode {
    return switch (linkModePreference) {
      LinkModePreference.dynamic || LinkModePreference.preferDynamic => DynamicLoadingBundled(),
      LinkModePreference.static || LinkModePreference.preferStatic => StaticLinking(),
      _ => throw UnsupportedError('Unsupported LinkModePreference: $linkModePreference'),
    };
  }
}

String getTargetTriple(OS targetOS, Architecture targetArchitecture, IOSSdk? iOSTargetSdk) {
  return switch ((targetOS, targetArchitecture)) {
    // Android
    (OS.android, Architecture.arm64) => 'aarch64-linux-android',
    (OS.android, Architecture.arm) => 'armv7-linux-androideabi',
    (OS.android, Architecture.x64) => 'x86_64-linux-android',

    // iOS
    (OS.iOS, Architecture.arm64) when iOSTargetSdk == IOSSdk.iPhoneSimulator => 'aarch64-apple-ios-sim',
    (OS.iOS, Architecture.arm64) when iOSTargetSdk == IOSSdk.iPhoneOS => 'aarch64-apple-ios',
    (OS.iOS, Architecture.arm64) => throw UnsupportedError('Unknown IOSSdk: ${iOSTargetSdk}'),
    (OS.iOS, Architecture.x64) => 'x86_64-apple-ios',

    // Windows
    (OS.windows, Architecture.arm64) => 'aarch64-pc-windows-msvc',
    (OS.windows, Architecture.x64) => 'x86_64-pc-windows-msvc',

    // Linux
    (OS.linux, Architecture.arm64) => 'aarch64-unknown-linux-gnu',
    (OS.linux, Architecture.x64) => 'x86_64-unknown-linux-gnu',

    // macOS
    (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
    (OS.macOS, Architecture.x64) => 'x86_64-apple-darwin',
    (_, _) => throw UnsupportedError('Unsupported target: $targetOS on $targetArchitecture'),
  };
}
