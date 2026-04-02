//! Resolve bundled `ffmpeg` / `ffprobe`.
//!
//! Linux / Windows / macOS: binaries next to `libmedia` (Dart hook + CodeAssets).
//! The Dart hook places ffmpeg/ffprobe beside the library during build.

use std::path::PathBuf;

#[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
#[no_mangle]
extern "C" fn media_dylib_path_anchor() {}

#[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
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

#[cfg(all(unix, not(target_os = "macos")))]
fn dylib_parent_dir() -> Option<PathBuf> {
    use libc::{dladdr, Dl_info};

    let mut info: Dl_info = unsafe { std::mem::zeroed() };
    let ok = unsafe { dladdr(media_dylib_path_anchor as *const c_void, &mut info) };
    if ok == 0 || info.dli_fname.is_null() {
        return None;
    }
    let s = unsafe { CStr::from_ptr(info.dli_fname) };
    let path = PathBuf::from(s.to_string_lossy().as_ref());
    path.parent().map(|p| p.to_path_buf())
}

#[cfg(target_os = "macos")]
fn dylib_parent_dir() -> Option<PathBuf> {
    // macOS uses the same dladdr approach as Linux
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
    sibling_tool("ffmpeg")
}

/// Bundled `ffprobe` path; no `PATH` fallback.
pub fn ffprobe_path() -> PathBuf {
    sibling_tool("ffprobe")
}
