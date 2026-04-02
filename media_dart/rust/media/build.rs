//! Android: link `nativehelper` / `mediandk` (JNI + NDK Media). NDK API 24 sysroots omit
//! `libnativehelper.so` stubs for some ABIs; add a higher-API `rustc-link-search` so the
//! linker can resolve `-lnativehelper` while the app `minSdk` can stay lower.

use std::path::Path;

fn main() {
    let target = std::env::var("TARGET").unwrap_or_default();

    if target.contains("android") {
        android_link_libs(&target);
    }

    // macOS now works like Linux/Windows - FFmpeg is a CodeAsset, not embedded
    // No need to check for bundled/current/ffmpeg anymore
}

fn android_link_libs(target: &str) {
    let arch_dir = if target.contains("aarch64-linux-android") {
        "aarch64-linux-android"
    } else if target.contains("x86_64-linux-android") {
        "x86_64-linux-android"
    } else if target.contains("armv7-linux-androideabi") || target.contains("arm-linux-androideabi") {
        "arm-linux-androideabi"
    } else if target.contains("i686-linux-android") {
        "i686-linux-android"
    } else {
        ""
    };

    if !arch_dir.is_empty() {
        if let Ok(ndk) = std::env::var("ANDROID_NDK_HOME")
            .or_else(|_| std::env::var("ANDROID_NDK_ROOT"))
        {
            let prebuilt = Path::new(&ndk).join("toolchains/llvm/prebuilt");
            if prebuilt.is_dir() {
                'host: for host in [
                    "darwin-arm64",
                    "darwin-x86_64",
                    "linux-x86_64",
                    "windows-x86_64",
                ] {
                    let base = prebuilt.join(host).join("sysroot/usr/lib").join(arch_dir);
                    if !base.is_dir() {
                        continue;
                    }
                    // Stubs for libnativehelper appear from API 31+ in current NDKs.
                    for api in ["35", "34", "33", "32", "31"] {
                        let stub = base.join(api);
                        if stub.is_dir() && stub.join("libnativehelper.so").is_file() {
                            println!("cargo:rustc-link-search=native={}", stub.display());
                            break 'host;
                        }
                    }
                }
            }
        }
    }

    println!("cargo:rustc-link-lib=nativehelper");
    println!("cargo:rustc-link-lib=mediandk");
}
