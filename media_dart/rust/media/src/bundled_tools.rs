//! Resolve bundled `ffmpeg` / `ffprobe`.
//!
//! Linux / Windows: binaries next to `libmedia` (Dart hook registers them as CodeAssets).
//! macOS + Flutter: bundled executables cannot be CodeAssets (Flutter wraps each asset as a
//! dylib framework and runs `otool -D`, which fails on MH_EXECUTE). When
//! `media_embed_macos_ffmpeg` is set, tools are `include_bytes!` from `bundled/current/` at
//! compile time and extracted to a cache directory on first use. Otherwise we fall back to
//! siblings next to the dylib (e.g. non-Flutter loads).

use std::path::PathBuf;

#[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
#[no_mangle]
extern "C" fn media_dylib_path_anchor() {}

#[cfg(all(target_os = "macos", media_embed_macos_ffmpeg))]
mod macos_embedded {
    use std::path::PathBuf;
    use std::sync::OnceLock;

    static FFMPEG: OnceLock<PathBuf> = OnceLock::new();
    static FFPROBE: OnceLock<PathBuf> = OnceLock::new();

    const FFMPEG_BYTES: &[u8] =
        include_bytes!(concat!(env!("CARGO_MANIFEST_DIR"), "/bundled/current/ffmpeg"));
    const FFPROBE_BYTES: &[u8] =
        include_bytes!(concat!(env!("CARGO_MANIFEST_DIR"), "/bundled/current/ffprobe"));

    fn extract_once(cell: &OnceLock<PathBuf>, file_name: &str, bytes: &[u8]) -> PathBuf {
        cell.get_or_init(|| {
            let base = std::env::temp_dir().join("media_rs_bundled_tools");
            std::fs::create_dir_all(&base).unwrap_or_else(|e| {
                panic!("create {}: {e}", base.display());
            });
            let p = base.join(file_name);
            std::fs::write(&p, bytes).unwrap_or_else(|e| panic!("write {}: {e}", p.display()));
            #[cfg(unix)]
            {
                use std::fs;
                use std::os::unix::fs::PermissionsExt;
                let mut perms = fs::metadata(&p).unwrap().permissions();
                perms.set_mode(0o755);
                fs::set_permissions(&p, perms).unwrap();
            }
            p
        })
        .clone()
    }

    pub fn ffmpeg_path() -> PathBuf {
        extract_once(&FFMPEG, "ffmpeg", FFMPEG_BYTES)
    }

    pub fn ffprobe_path() -> PathBuf {
        extract_once(&FFPROBE, "ffprobe", FFPROBE_BYTES)
    }
}

#[cfg(all(
    any(target_os = "linux", target_os = "windows"),
    not(all(target_os = "macos", media_embed_macos_ffmpeg))
))]
fn sibling_tool(name: &str) -> PathBuf {
    let ext = if cfg!(target_os = "windows") { ".exe" } else { "" };
    let dir = dylib_parent_dir().unwrap_or_else(|| {
        panic!(
            "could not resolve the directory containing libmedia; ffmpeg/ffprobe must live next to the library"
        )
    });
    let p = dir.join(format!("{name}{ext}"));
    if !p.is_file() {
        panic!(
            "bundled {name}{ext} not found next to libmedia at {}. Build native assets so the Dart hook places ffmpeg/ffprobe beside the library.",
            p.display()
        );
    }
    p
}

#[cfg(all(
    target_os = "macos",
    not(media_embed_macos_ffmpeg),
))]
fn sibling_tool(name: &str) -> PathBuf {
    // First try: look in the same directory as libmedia.dylib (for non-Flutter)
    if let Some(dir) = dylib_parent_dir() {
        let p = dir.join(name);
        if p.is_file() {
            return p;
        }
        
        // Second try: Flutter / CocoaPods copy ffmpeg next to *.framework, not inside it.
        // dylib dir is .../media.framework/Versions/A — the container that holds
        // media.framework is MyApp.app/Contents/Frameworks/ (or build/native_assets/macos/).
        if let Some(container) = dir.parent().and_then(|v| v.parent()).and_then(|fw| fw.parent()) {
            let sibling = container.join(name);
            if sibling.is_file() {
                return sibling;
            }
        }
    }
    
    panic!(
        "bundled {name} not found. Expected at:\n\
         - Next to libmedia.dylib, or\n\
         - In MyApp.app/Contents/Frameworks/\n\
         Run the post-build script: ./macos/copy_ffmpeg.sh"
    );
}

#[cfg(all(
    any(target_os = "linux", target_os = "macos"),
    not(all(target_os = "macos", media_embed_macos_ffmpeg)),
))]
fn dylib_parent_dir() -> Option<PathBuf> {
    use libc::{dladdr, Dl_info};
    use std::ffi::c_void;
    use std::ffi::CStr;

    let mut info: Dl_info = unsafe { std::mem::zeroed() };
    let ok = unsafe { dladdr(media_dylib_path_anchor as *const c_void, &mut info) };
    if ok == 0 || info.dli_fname.is_null() {
        return None;
    }
    let s = unsafe { CStr::from_ptr(info.dli_fname) };
    let path = PathBuf::from(s.to_string_lossy().as_ref());
    path.parent().map(|p| p.to_path_buf())
}

#[cfg(windows)]
use std::ffi::c_void;

#[cfg(windows)]
fn dylib_parent_dir() -> Option<PathBuf> {
    use std::os::windows::ffi::OsStringExt;
    use windows_sys::Win32::Foundation::HMODULE;
    use windows_sys::Win32::System::LibraryLoader::{
        GetModuleFileNameW, GetModuleHandleExW, GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
        GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
    };

    let mut module: HMODULE = std::ptr::null_mut();
    let flags = GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT;
    let ok = unsafe {
        GetModuleHandleExW(
            flags,
            media_dylib_path_anchor as *const u16,
            &mut module as *mut HMODULE,
        )
    };
    if ok == 0 || module.is_null() {
        return None;
    }
    let mut buf = vec![0u16; 1024];
    let len = unsafe { GetModuleFileNameW(module, buf.as_mut_ptr(), buf.len() as u32) } as usize;
    if len == 0 {
        return None;
    }
    buf.truncate(len);
    let os = std::ffi::OsString::from_wide(&buf);
    PathBuf::from(os).parent().map(std::path::Path::to_path_buf)
}

/// Bundled `ffmpeg` path; no `PATH` fallback.
pub fn ffmpeg_path() -> PathBuf {
    #[cfg(all(target_os = "macos", media_embed_macos_ffmpeg))]
    {
        macos_embedded::ffmpeg_path()
    }
    #[cfg(not(all(target_os = "macos", media_embed_macos_ffmpeg)))]
    {
        sibling_tool("ffmpeg")
    }
}

/// Bundled `ffprobe` path; no `PATH` fallback.
pub fn ffprobe_path() -> PathBuf {
    #[cfg(all(target_os = "macos", media_embed_macos_ffmpeg))]
    {
        macos_embedded::ffprobe_path()
    }
    #[cfg(not(all(target_os = "macos", media_embed_macos_ffmpeg)))]
    {
        sibling_tool("ffprobe")
    }
}
