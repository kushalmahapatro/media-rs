fn main() {
    // Debug env vars
    let env_vars = std::env::vars();
    let mut dump = String::new();
    for (k, v) in env_vars {
        dump.push_str(&format!("{}={}\n", k, v));
    }
    std::fs::write("/tmp/media_rs_cargo_env.txt", dump).unwrap();

    // Link libheif statically if built from source
    // Note: When LIBHEIF_DIR is set, we're using our pre-built libheif
    // libheif-sys will use pkg-config to find it, but we still need to ensure
    // libde265 is linked since it's a dependency
    if let Ok(libheif_dir) = std::env::var("LIBHEIF_DIR") {
        let lib_dir = format!("{}/lib", libheif_dir);
        let include_dir = format!("{}/include", libheif_dir);

        println!("cargo:rustc-link-search=native={}", lib_dir);
        // Link libheif and libde265 as static libraries
        println!("cargo:rustc-link-lib=static=heif");
        println!("cargo:rustc-link-lib=static=de265"); // libheif depends on libde265
                                                       // libheif is a C++ library, so we need to link the C++ standard library
        println!("cargo:rustc-link-lib=c++");
        println!("cargo:include={}", include_dir);
    }

    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if target_os == "macos" {
        println!("cargo:rustc-link-lib=framework=VideoToolbox");
        println!("cargo:rustc-link-lib=framework=CoreVideo");
        println!("cargo:rustc-link-lib=framework=CoreMedia");
        println!("cargo:rustc-link-lib=framework=CoreFoundation");
        println!("cargo:rustc-link-lib=framework=CoreServices");
        println!("cargo:rustc-link-lib=framework=AudioToolbox");
        println!("cargo:rustc-link-lib=framework=Security");
        // AppKit removed just in case, typical rust media crates don't need it explicitly unless windowing
        println!("cargo:rustc-link-lib=z");
        println!("cargo:rustc-link-lib=bz2");
        println!("cargo:rustc-link-lib=iconv");
        // libheif is a C++ library, so we need to link C++ standard library
        // This is needed even when using libheif-sys via pkg-config
        println!("cargo:rustc-link-lib=c++");
    } else if target_os == "android" {
        // Android needs zlib linked - it's available in the NDK
        // FFmpeg uses zlib for compression/decompression
        println!("cargo:rustc-link-lib=z");
        // Android also needs log for logging
        println!("cargo:rustc-link-lib=log");
        // Note: MediaCodec has been disabled in FFmpeg build to avoid NDK linking issues
        // H.264 encoding will use OpenH264 or built-in encoder instead
    } else if target_os == "ios" {
        // Set minimum deployment target to iOS 16.0 for __isPlatformVersionAtLeast support
        // This intrinsic is required by FFmpeg's VideoToolbox code
        let target = std::env::var("TARGET").unwrap_or_default();
        if target.contains("sim") {
            println!("cargo:rustc-link-arg=-mios-simulator-version-min=16.0");
        } else {
            println!("cargo:rustc-link-arg=-mios-version-min=16.0");
        }

        println!("cargo:rustc-link-lib=framework=VideoToolbox");
        println!("cargo:rustc-link-lib=framework=CoreVideo");
        println!("cargo:rustc-link-lib=framework=CoreMedia");
        println!("cargo:rustc-link-lib=framework=CoreFoundation");
        println!("cargo:rustc-link-lib=framework=AudioToolbox");
        println!("cargo:rustc-link-lib=framework=Security");
        println!("cargo:rustc-link-lib=framework=AVFoundation");
        println!("cargo:rustc-link-lib=framework=CoreAudio");
        println!("cargo:rustc-link-lib=framework=CoreGraphics");
        println!("cargo:rustc-link-lib=framework=QuartzCore");
        println!("cargo:rustc-link-lib=z");
        println!("cargo:rustc-link-lib=bz2");
        println!("cargo:rustc-link-lib=iconv");
    }
}
