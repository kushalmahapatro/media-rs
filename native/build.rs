fn main() {
    // Debug env vars (only on Unix systems)
    #[cfg(unix)]
    {
        let env_vars = std::env::vars();
        let mut dump = String::new();
        for (k, v) in env_vars {
            dump.push_str(&format!("{}={}\n", k, v));
        }
        if let Ok(tmp_dir) = std::env::var("TMPDIR").or_else(|_| std::env::var("TMP")) {
            let _ = std::fs::write(format!("{}/media_rs_cargo_env.txt", tmp_dir), dump);
        } else if let Ok(tmp_dir) = std::env::var("TEMP") {
            let _ = std::fs::write(format!("{}/media_rs_cargo_env.txt", tmp_dir), dump);
        }
    }

    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();

    // Link libheif statically if built from source
    // Note: When LIBHEIF_DIR is set, we're using our pre-built libheif
    // libheif-sys will use pkg-config to find it, but we still need to ensure
    // libde265 is linked since it's a dependency
    if let Ok(libheif_dir) = std::env::var("LIBHEIF_DIR") {
        let lib_dir = format!("{}/lib", libheif_dir);
        let include_dir = format!("{}/include", libheif_dir);

        println!("cargo:rustc-link-search=native={}", lib_dir);
        
        // On Windows MSVC, use .lib files (converted from MinGW .a files)
        // On other platforms or MinGW, use .a files
        let target_env = std::env::var("CARGO_CFG_TARGET_ENV").unwrap_or_default();
        if target_os == "windows" && target_env == "msvc" {
            // Check for .lib files (MSVC format, converted from MinGW .a)
            // Try both heif.lib and libheif.lib (Rust looks for heif.lib, but we might have libheif.lib)
            let heif_lib_paths = [format!("{}/lib/heif.lib", libheif_dir),
                format!("{}\\lib\\heif.lib", libheif_dir),
                format!("{}/lib/libheif.lib", libheif_dir),
                format!("{}\\lib\\libheif.lib", libheif_dir)];
            let de265_lib_paths = [format!("{}/lib/de265.lib", libheif_dir),
                format!("{}\\lib\\de265.lib", libheif_dir),
                format!("{}/lib/libde265.lib", libheif_dir),
                format!("{}\\lib\\libde265.lib", libheif_dir)];
            
            let heif_lib_exists = heif_lib_paths.iter().any(|p| std::path::Path::new(p).exists());
            let de265_lib_exists = de265_lib_paths.iter().any(|p| std::path::Path::new(p).exists());
            
            if heif_lib_exists && de265_lib_exists {
                // Use .lib files (MSVC format)
                // IMPORTANT: Link libde265 BEFORE heif because heif depends on libde265
                // The linker processes libraries in order, so dependencies must come first
                // Note: LIBDE265_STATIC_BUILD should be defined when building libheif
                // to avoid __imp_ prefix issues. This is handled in build_libheif_msvc.bat
                println!("cargo:rustc-link-lib=static=de265");
                println!("cargo:rustc-link-lib=static=libde265");
                println!("cargo:rustc-link-lib=static=heif");
                println!("cargo:rustc-link-lib=static=libheif");
            } else {
                // .lib files not found, try to convert or use .a with /FORCE:MULTIPLE
                println!("cargo:warning=MSVC .lib files not found. Run: scripts/support/convert_to_msvc_lib.bat");
                println!("cargo:rustc-link-arg=/FORCE:MULTIPLE");
                // Link dependencies first
                println!("cargo:rustc-link-lib=static=de265");
                println!("cargo:rustc-link-lib=static=libde265");
                println!("cargo:rustc-link-lib=static=heif");
                println!("cargo:rustc-link-lib=static=libheif");
            }
        } else {
            // Use .a files (MinGW/Unix format)
            println!("cargo:rustc-link-lib=static=heif");
            println!("cargo:rustc-link-lib=static=de265");
        }

        // libheif is a C++ library, so we need to link the C++ standard library
        // For Android, we'll link c++_shared in the Android-specific block below
        // For Windows with MinGW, we use stdc++ (handled in Windows block)
        // For macOS, use c++ (libc++)
        // For Linux, use stdc++ (libstdc++)
        if target_os == "macos" {
            println!("cargo:rustc-link-lib=c++");
        } else if target_os == "linux" {
            println!("cargo:rustc-link-lib=stdc++");
        }
        println!("cargo:include={}", include_dir);
    }
    // Link OpenH264 statically when provided (used by FFmpeg's libopenh264 wrapper)
    if let Ok(openh264_dir) = std::env::var("OPENH264_DIR") {
        let lib_dir = format!("{}/lib", openh264_dir);
        println!("cargo:rustc-link-search=native={}", lib_dir);
        
        // On Windows MSVC, prefer .lib files (MSVC format) over .a files (MinGW format)
        // to avoid COMDAT incompatibility issues
        let target_env = std::env::var("CARGO_CFG_TARGET_ENV").unwrap_or_default();
        if target_os == "windows" && target_env == "msvc" {
            // Check for .lib files (MSVC format)
            let openh264_lib_paths = [format!("{}/lib/openh264.lib", openh264_dir),
                format!("{}\\lib\\openh264.lib", openh264_dir),
                format!("{}/lib/libopenh264.lib", openh264_dir),
                format!("{}\\lib\\libopenh264.lib", openh264_dir)];
            
            let openh264_lib_exists = openh264_lib_paths.iter().any(|p| std::path::Path::new(p).exists());
            
            if openh264_lib_exists {
                // Use .lib file (MSVC format) - Rust will find openh264.lib or libopenh264.lib
                println!("cargo:rustc-link-lib=static=openh264");
            } else {
                // .lib file not found - warn and try .a (may cause COMDAT errors)
                println!("cargo:warning=OpenH264 MSVC .lib file not found. Run: scripts/support/build_openh264_msvc.bat");
                println!("cargo:warning=Attempting to use MinGW .a file - this may cause LNK1143 COMDAT errors");
                println!("cargo:rustc-link-lib=static=openh264");
            }
        } else {
            // Use .a files (MinGW/Unix format)
            println!("cargo:rustc-link-lib=static=openh264");
        }
    }
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
        // MediaCodec disabled - using OpenH264 instead for licensing clarity
        // H.264 encoding priority: OpenH264 (software, has patent coverage) > built-in encoder

        // If libheif is being used, we need to link c++_shared (not static c++)
        // libheif is built with c++_shared, so we need to match that
        if std::env::var("LIBHEIF_DIR").is_ok() {
            // Link c++_shared for Android when using libheif
            // This requires the shared library to be bundled with the APK
            println!("cargo:rustc-link-lib=c++_shared");
        }
        // OpenH264 is a C++ library on Android; link the C++ runtime when it's enabled.
        // This also matches FFmpeg's configure/link expectations when building with libopenh264.
        if std::env::var("OPENH264_DIR").is_ok() {
            println!("cargo:rustc-link-lib=c++_shared");
        }
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
    } else if target_os == "windows" {
        // Windows linking - depends on toolchain (MSVC vs MinGW)
        let target_env = std::env::var("CARGO_CFG_TARGET_ENV").unwrap_or_default();
        
        if target_env == "msvc" {
            // MSVC toolchain (used by Flutter on Windows)
            // MSVC automatically links the C++ runtime, so we don't need to link stdc++
            // FFmpeg was built with MinGW, so we need to link MinGW runtime for compatibility
            // This provides symbols like __mingw_snprintf that FFmpeg expects
            // Add MinGW library search paths
            if let Ok(msys_root) = std::env::var("MSYS2_ROOT") {
                println!("cargo:rustc-link-search=native={}/mingw64/lib", msys_root);
                println!("cargo:rustc-link-search=native={}/usr/lib", msys_root);
            } else {
                // Try common MSYS2 locations
                println!("cargo:rustc-link-search=native=C:/msys64/mingw64/lib");
                println!("cargo:rustc-link-search=native=C:/msys64/usr/lib");
            }
            // Link MinGW runtime libraries (provides __mingw_snprintf and other MinGW symbols)
            // Note: These are .a files, but MSVC linker can handle them with /FORCE:MULTIPLE if needed
            println!("cargo:rustc-link-lib=static=mingwex");
            println!("cargo:rustc-link-lib=static=mingw32");
            // Link iconv for character encoding conversion (FFmpeg needs this)
            println!("cargo:rustc-link-lib=static=iconv");
            // Link zlib (FFmpeg needs uncompress function)
            println!("cargo:rustc-link-lib=static=z");
            // Link bzip2 (FFmpeg needs BZ2 decompression)
            println!("cargo:rustc-link-lib=static=bz2");
            // Link lzma (FFmpeg needs LZMA compression support)
            println!("cargo:rustc-link-lib=static=lzma");
            // Link Windows system libraries
            println!("cargo:rustc-link-lib=user32"); // GetDesktopWindow
            println!("cargo:rustc-link-lib=crypt32"); // CryptBinaryToStringA
            println!("cargo:rustc-link-lib=secur32"); // SChannel functions
            println!("cargo:rustc-link-lib=ncrypt"); // NCrypt functions
            println!("cargo:rustc-link-lib=ole32"); // COM functions (CoInitializeEx, CoTaskMemFree, CoUninitialize)
            println!("cargo:rustc-link-lib=mf"); // Media Foundation (IID_ICodecAPI)
            println!("cargo:rustc-link-lib=mfplat"); // Media Foundation Platform
            // Compile and link our stub for MinGW runtime functions
            // FFmpeg was built with MinGW and expects these symbols, but MSVC doesn't provide them
            let stub_src = std::path::Path::new("src/mingw_stub.c");
            if stub_src.exists() {
                println!("cargo:rerun-if-changed=src/mingw_stub.c");
                cc::Build::new()
                    .file("src/mingw_stub.c")
                    .compile("mingw_stub");
            }
            // Use /FORCE:MULTIPLE to allow linking MinGW .a files with MSVC
            println!("cargo:rustc-link-arg=/FORCE:MULTIPLE");
            // FFmpeg and libheif were built with MinGW and include zlib/bzip2 statically
            // so we don't need to link them separately on MSVC
            // Note: MSVC doesn't use pthread - it uses Windows threads
        } else {
            // MinGW-w64 toolchain
            // Link C++ standard library (MinGW uses stdc++)
            // This is needed for libheif and OpenH264 which are C++ libraries
            println!("cargo:rustc-link-lib=stdc++");
            // Link system libraries that FFmpeg and libheif may need
            println!("cargo:rustc-link-lib=z");
            println!("cargo:rustc-link-lib=bz2");
            // MinGW-w64 uses pthread for threading
            println!("cargo:rustc-link-lib=pthread");
        }
    }
}
